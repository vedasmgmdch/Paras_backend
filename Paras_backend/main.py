from datetime import datetime, timedelta, date
import os
from typing import List, Optional, Any
from pydantic import BaseModel

import models
from database import get_db

from fastapi import FastAPI, Depends, HTTPException, status, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

import schemas
from database import engine

from utils import send_registration_email, send_fcm_notification, send_fcm_notification_ex
import os
from fastapi import Request
from sqlalchemy import and_, select
from datetime import datetime, timedelta
import pytz
from routes import auth
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
import asyncio

app = FastAPI()

app.include_router(auth.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/healthz")
async def healthz():
    # Cheap DB probe (optional, ignore errors to still return ok if DB transiently slow)
    try:
        async with get_db() as db:  # type: ignore
            await db.execute(select(1))
        db_ok = True
    except Exception:
        db_ok = False
    return {"ok": True, "db": db_ok}

@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(models.Base.metadata.create_all)
    if os.getenv("SCHEDULER_ENABLED", "1") == "1":
        print("[Startup] Scheduler enabled (SCHEDULER_ENABLED=1)")
        scheduler = AsyncIOScheduler()
        async def _run_dispatch():
            from fastapi import Request as _Req
            scope = {"type": "http", "headers": []}
            fake_request = _Req(scope)
            async with get_db() as db:  # type: ignore
                try:
                    await dispatch_due_pushes(fake_request, db)  # type: ignore[arg-type]
                except Exception as e:
                    print(f"[Scheduler] dispatch_due_pushes error: {e}")
        scheduler.add_job(_run_dispatch, IntervalTrigger(seconds=60), id="dispatch_due", replace_existing=True)
        scheduler.start()
    else:
        print("[Startup] Scheduler disabled via SCHEDULER_ENABLED env var")

@app.on_event("shutdown")
async def shutdown_event():
    # Attempt graceful scheduler shutdown if running
    try:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler as _S
        for inst in list(_S._instances):  # type: ignore[attr-defined]
            try:
                inst.shutdown(wait=False)
            except Exception:
                pass
    except Exception:
        pass

SECRET_KEY = os.getenv("SECRET_KEY", "secret")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 90  # 90 days

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/login")
doctor_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/doctor-login")

# --- Auth helpers: tolerate proxies that move Authorization to X-Forwarded-Authorization ---
def _extract_bearer_from_request(request: Request) -> Optional[str]:
    """Return the bearer token from common auth headers.
    Some proxies/CDNs forward Authorization as X-Forwarded-Authorization.
    """
    candidate_headers = [
        "authorization",
        "Authorization",
        "x-authorization",
        "X-Authorization",
        "x-auth-token",
        "X-Auth-Token",
        "x-forwarded-authorization",
        "X-Forwarded-Authorization",
    ]
    for h in candidate_headers:
        v = request.headers.get(h)
        if not v:
            continue
        # For X-Auth-Token allow either raw token or "Bearer <token>"
        if h.lower() == "x-auth-token":
            parts = v.strip().split(" ", 1)
            if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1]:
                return parts[1]
            # treat the whole value as the token when no Bearer prefix
            return v.strip()
        # Other headers must be in the form "Bearer <token>"
        parts = v.strip().split(" ", 1)
        if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1]:
            return parts[1]
    # Try common cookies
    cookie_auth = request.cookies.get("Authorization") or request.cookies.get("authorization")
    if cookie_auth:
        parts = cookie_auth.strip().split(" ", 1)
        if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1]:
            return parts[1]

    # Try query params (?access_token=... or ?token=...)
    qp = request.query_params
    for key in ("access_token", "token"):
        val = qp.get(key)
        if val:
            # Accept raw token or "Bearer <token>"
            parts = val.strip().split(" ", 1)
            if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1]:
                return parts[1]
            return val
    return None

# --- Reminder scheduling helper (module level) ---
def _compute_next_fire(now_utc: datetime, hour: int, minute: int, tz_name: str) -> tuple[datetime, datetime]:
    """Return (next_local_dt, next_utc_dt) naive datetimes.
    now_utc must be naive UTC. We compute the next local wall-clock occurrence and its UTC instant.
    """
    try:
        tz = pytz.timezone(tz_name)
    except Exception:
        tz = pytz.UTC
    if now_utc.tzinfo is not None:
        now_utc = now_utc.astimezone(pytz.UTC).replace(tzinfo=None)
    now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
    candidate = now_local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= now_local:
        candidate = candidate + timedelta(days=1)
    candidate = tz.normalize(candidate)
    candidate_utc = candidate.astimezone(pytz.UTC).replace(tzinfo=None)
    return candidate.replace(tzinfo=None), candidate_utc

async def get_bearer_token(request: Request) -> str:
    token = _extract_bearer_from_request(request)
    if not token:
        # Fall back to OAuth2PasswordBearer parsing (for docs/compat)
        # If that also fails, raise 401
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return token

# Temporary debug endpoint to inspect how auth headers arrive in the deployment
@app.get("/auth/debug")

async def debug_auth(request: Request):
    token = _extract_bearer_from_request(request)
    candidate_headers = {
        "authorization": request.headers.get("authorization"),
        "Authorization": request.headers.get("Authorization"),
        "x-authorization": request.headers.get("x-authorization"),
        "X-Authorization": request.headers.get("X-Authorization"),
    "x-auth-token": request.headers.get("x-auth-token"),
    "X-Auth-Token": request.headers.get("X-Auth-Token"),
        "x-forwarded-authorization": request.headers.get("x-forwarded-authorization"),
        "X-Forwarded-Authorization": request.headers.get("X-Forwarded-Authorization"),
    }
    return {
        "seen_headers": candidate_headers,
        "has_token": bool(token),
        "token_preview": (token[:12] + "..." + token[-6:]) if token and len(token) > 24 else token,
        "from_cookie": bool(request.cookies.get("Authorization") or request.cookies.get("authorization")),
        "query_params": {k: request.query_params.get(k) for k in ["access_token", "token"]},
    }

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(token: str = Depends(get_bearer_token), db: AsyncSession = Depends(get_db)):
    cred_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise cred_exc
    except JWTError:

        raise cred_exc

    result = await db.execute(select(models.Patient).where(models.Patient.username == username))
    user = result.scalars().first()
    if user is None:
        raise cred_exc
    return user

async def get_current_doctor(token: str = Depends(get_bearer_token), db: AsyncSession = Depends(get_db)):

    cred_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials (doctor)",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise cred_exc
    except JWTError:
        raise cred_exc

    result = await db.execute(select(models.Doctor).where(models.Doctor.username == username))
    doctor = result.scalars().first()
    if doctor is None:
        raise cred_exc
    return doctor

@app.get("/")
async def root():
    return {"message": "✅ MGM Hospital API is running."}

async def _get_or_create_open_episode(db: AsyncSession, patient_id: int) -> models.TreatmentEpisode:
    stmt = (
        select(models.TreatmentEpisode)
        .where(
            models.TreatmentEpisode.patient_id == patient_id,
            models.TreatmentEpisode.locked == False,
        )
        .order_by(models.TreatmentEpisode.id.desc())
    )
    res = await db.execute(stmt)
    open_episodes = res.scalars().all()
    if open_episodes:
        # If more than one open episode, lock all but the most recent
        for ep in open_episodes[1:]:
            object.__setattr__(ep, 'locked', True)
            db.add(ep)
        if len(open_episodes) > 1:
            await db.commit()
        return open_episodes[0]

    new_ep = models.TreatmentEpisode(
        patient_id=patient_id,
        department=None,
        doctor=None,
        treatment=None,
        subtype=None,
        procedure_completed=False,
        locked=False,
        procedure_date=None,
        procedure_time=None,
    )
    db.add(new_ep)
    await db.commit()
    await db.refresh(new_ep)
    return new_ep

async def _mirror_episode_to_patient(db: AsyncSession, patient: models.Patient, episode: models.TreatmentEpisode) -> None:
    patient.department = episode.department
    patient.doctor = episode.doctor
    patient.treatment = episode.treatment
    patient.treatment_subtype = episode.subtype
    patient.procedure_date = episode.procedure_date
    patient.procedure_time = episode.procedure_time
    patient.procedure_completed = episode.procedure_completed
    db.add(patient)
    await db.commit()
    await db.refresh(patient)

async def _rotate_if_due(db: AsyncSession, patient: models.Patient) -> Optional[int]:
    ep = await _get_or_create_open_episode(db, object.__getattribute__(patient, 'id'))
    if getattr(ep, "locked", False):
        return None
    if not getattr(ep, "procedure_completed", False) or not getattr(ep, "procedure_date", None):
        return None
    if (date.today() - ep.procedure_date).days < 15:
        return None

    object.__setattr__(ep, 'locked', True)
    db.add(ep)
    await db.commit()

    new_ep = models.TreatmentEpisode(
        patient_id=object.__getattribute__(patient, 'id'),
        department=None,
        doctor=None,
        treatment=None,
        subtype=None,
        procedure_completed=False,
        locked=False,
        procedure_date=None,
        procedure_time=None,
    )
    db.add(new_ep)
    await db.commit()
    await db.refresh(new_ep)

    await _mirror_episode_to_patient(db, patient, new_ep)
    return object.__getattribute__(new_ep, 'id')

@app.post("/signup", response_model=schemas.TokenResponse)
async def signup(patient: schemas.PatientCreate, db: AsyncSession = Depends(get_db)):
    errors = {}

    # Check username
    res = await db.execute(select(models.Patient).where(models.Patient.username == patient.username))
    if res.scalars().first():
        errors["username"] = "Username already exists"

    # Check email
    res = await db.execute(select(models.Patient).where(models.Patient.email == patient.email))
    if res.scalars().first():
        errors["email"] = "Email already exists"

    # Check phone
    res = await db.execute(select(models.Patient).where(models.Patient.phone == patient.phone))
    if res.scalars().first():
        errors["phone"] = "Phone number already exists"

    if errors:
        raise HTTPException(status_code=400, detail=errors)

    hashed_pw = get_password_hash(patient.password)
    db_patient = models.Patient(**patient.dict(exclude={"password"}), password=hashed_pw)
    db.add(db_patient)
    await db.commit()
    await db.refresh(db_patient)

    ep = await _get_or_create_open_episode(db, object.__getattribute__(db_patient, 'id'))
    await _mirror_episode_to_patient(db, db_patient, ep)

    try:
        send_registration_email(db_patient.email, db_patient.name)
    except Exception as e:
        print(f"Email sending failed: {e}")

    access_token = create_access_token(data={"sub": db_patient.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/login", response_model=schemas.TokenResponse)
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(models.Patient).where(models.Patient.username == form_data.username))
    user = result.scalars().first()
    if not user or not verify_password(form_data.password, user.password):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    access_token = create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/doctor-login", response_model=schemas.TokenResponse)
async def doctor_login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(models.Doctor).where(models.Doctor.username == form_data.username))
    doctor = result.scalars().first()
    if not doctor or not verify_password(form_data.password, doctor.password):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    access_token = create_access_token(data={"sub": doctor.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/patients/me", response_model=schemas.PatientPublic)
async def get_my_profile(current_user: models.Patient = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await _rotate_if_due(db, current_user)
    return current_user

@app.post("/feedback", response_model=schemas.FeedbackResponse)
async def submit_feedback(feedback: schemas.FeedbackCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    new_feedback = models.Feedback(patient_id=current_user.id, message=feedback.message)
    db.add(new_feedback)
    await db.commit()
    await db.refresh(new_feedback)
    return {"message": feedback.message, "status": "success"}

@app.get("/feedback", response_model=List[schemas.FeedbackResponse])
async def get_my_feedbacks(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    result = await db.execute(select(models.Feedback).where(models.Feedback.patient_id == current_user.id))
    feedbacks = result.scalars().all()
    return [{"message": f.message, "status": "success"} for f in feedbacks]

@app.post("/progress", response_model=schemas.ProgressEntry)
async def submit_progress(progress: schemas.ProgressCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    await _rotate_if_due(db, current_user)
    db_entry = models.Progress(patient_id=current_user.id, message=progress.message)
    db.add(db_entry)
    await db.commit()
    await db.refresh(db_entry)
    return db_entry

@app.get("/progress", response_model=List[schemas.ProgressEntry])
async def get_progress(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    result = await db.execute(select(models.Progress).where(models.Progress.patient_id == current_user.id).order_by(models.Progress.timestamp.desc()))
    return result.scalars().all()

@app.post("/instruction-status", response_model=List[schemas.InstructionStatusResponse])
async def save_instruction_status(payload: schemas.InstructionStatusBulkCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    await _rotate_if_due(db, current_user)
    saved: list[models.InstructionStatus] = []
    for item in payload.items:
        row = models.InstructionStatus(
            patient_id=current_user.id,
            date=item.date,
            treatment=item.treatment,
            subtype=item.subtype,
            group=item.group,
            instruction_index=item.instruction_index,
            instruction_text=item.instruction_text,
            followed=item.followed,
        )
        db.add(row)
        saved.append(row)
    await db.commit()
    for r in saved:
        await db.refresh(r)
    return saved

@app.get("/instruction-status", response_model=List[schemas.InstructionStatusResponse])
async def list_instruction_status(date_from: Optional[date] = None, date_to: Optional[date] = None, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    q = select(models.InstructionStatus).where(models.InstructionStatus.patient_id == current_user.id)
    if date_from:
        q = q.where(models.InstructionStatus.date >= date_from)
    if date_to:
        q = q.where(models.InstructionStatus.date <= date_to)
    result = await db.execute(
        q.order_by(
            models.InstructionStatus.date.desc(),
            models.InstructionStatus.group.asc(),
            models.InstructionStatus.instruction_index.asc(),
        )
    )
    return result.scalars().all()

@app.post("/department-doctor")
async def save_department_doctor(data: schemas.DepartmentDoctorSelection, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    await _rotate_if_due(db, current_user)
    ep = await _get_or_create_open_episode(db, object.__getattribute__(current_user, 'id'))
    if getattr(ep, "locked", False):
        raise HTTPException(status_code=423, detail="Episode is locked and cannot be modified.")
    object.__setattr__(ep, 'department', data.department)
    object.__setattr__(ep, 'doctor', data.doctor)
    db.add(ep)
    await db.commit()
    await db.refresh(ep)
    await _mirror_episode_to_patient(db, current_user, ep)
    return {"status": "success", "department": data.department, "doctor": data.doctor, "current_episode_id": ep.id}

@app.post("/treatment-info", response_model=schemas.PatientPublic)
async def save_treatment_info(info: schemas.TreatmentInfoCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(models.Patient).where(models.Patient.username == info.username))
    patient = result.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    await _rotate_if_due(db, patient)
    ep = await _get_or_create_open_episode(db, object.__getattribute__(patient, 'id'))
    if getattr(ep, "locked", False):
        raise HTTPException(status_code=423, detail="Episode is locked and cannot be modified.")
    object.__setattr__(ep, 'treatment', info.treatment)
    object.__setattr__(ep, 'subtype', info.subtype)
    object.__setattr__(ep, 'procedure_date', info.procedure_date)
    object.__setattr__(ep, 'procedure_time', info.procedure_time)
    db.add(ep)
    await db.commit()
    await db.refresh(ep)
    await _mirror_episode_to_patient(db, patient, ep)
    return patient

@app.get("/episodes/current", response_model=schemas.CurrentEpisodeResponse)
async def get_current_episode(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    await _rotate_if_due(db, current_user)
    ep = await _get_or_create_open_episode(db, object.__getattribute__(current_user, 'id'))
    return schemas.CurrentEpisodeResponse.model_validate(ep, from_attributes=True)

@app.get("/episodes/history", response_model=List[schemas.EpisodeResponse])
async def get_episode_history(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    stmt = select(models.TreatmentEpisode).where(models.TreatmentEpisode.patient_id == object.__getattribute__(current_user, 'id')).order_by(models.TreatmentEpisode.id.desc())
    res = await db.execute(stmt)
    episodes = res.scalars().all()
    return [schemas.EpisodeResponse.model_validate(e, from_attributes=True) for e in episodes]

@app.post("/episodes/mark-complete", response_model=schemas.EpisodeResponse)
async def mark_episode_complete(payload: schemas.MarkCompleteRequest, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    ep = await _get_or_create_open_episode(db, object.__getattribute__(current_user, 'id'))
    if getattr(ep, "locked", False):
        raise HTTPException(status_code=423, detail="Episode is locked and cannot be modified.")
    object.__setattr__(ep, 'procedure_completed', bool(payload.procedure_completed))
    if payload.procedure_date is not None:
        object.__setattr__(ep, 'procedure_date', payload.procedure_date)
    if payload.procedure_time is not None:
        object.__setattr__(ep, 'procedure_time', payload.procedure_time)
    db.add(ep)
    await db.commit()
    await db.refresh(ep)
    await _mirror_episode_to_patient(db, current_user, ep)
    return schemas.EpisodeResponse.model_validate(ep, from_attributes=True)

@app.post("/episodes/rotate-if-due", response_model=schemas.RotateIfDueResponse)
async def rotate_if_due_endpoint(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    new_id = await _rotate_if_due(db, current_user)
    if new_id is None:
        return schemas.RotateIfDueResponse(rotated=False, new_episode_id=None)
    return schemas.RotateIfDueResponse(rotated=True, new_episode_id=new_id)

# ---------------------------
# Reminder endpoints (hybrid system)
# ---------------------------
@app.post("/reminders", response_model=schemas.ReminderResponse)
async def create_reminder(payload: schemas.ReminderCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    if not (0 <= payload.hour <= 23 and 0 <= payload.minute <= 59):
        raise HTTPException(status_code=422, detail="Invalid hour/minute")
    now_utc = datetime.utcnow()
    next_local, next_utc = _compute_next_fire(now_utc, payload.hour, payload.minute, payload.timezone)
    row = models.Reminder(
        patient_id=current_user.id,
        title=payload.title,
        body=payload.body,
        hour=payload.hour,
        minute=payload.minute,
        timezone=payload.timezone,
        active=payload.active,
        grace_minutes=payload.grace_minutes,
        next_fire_local=next_local,
        next_fire_utc=next_utc,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.get("/reminders", response_model=list[schemas.ReminderResponse])
async def list_reminders(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id).order_by(models.Reminder.id.asc()))
    return res.scalars().all()

@app.patch("/reminders/{reminder_id}", response_model=schemas.ReminderResponse)
async def update_reminder(reminder_id: int, payload: schemas.ReminderUpdate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id).where(models.Reminder.id == reminder_id))
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    changed_time = False
    if payload.title is not None:
        setattr(row, 'title', payload.title)
    if payload.body is not None:
        setattr(row, 'body', payload.body)
    if payload.hour is not None:
        if not 0 <= payload.hour <= 23:
            raise HTTPException(status_code=422, detail="Invalid hour")
        setattr(row, 'hour', payload.hour); changed_time = True
    if payload.minute is not None:
        if not 0 <= payload.minute <= 59:
            raise HTTPException(status_code=422, detail="Invalid minute")
        setattr(row, 'minute', payload.minute); changed_time = True
    if payload.timezone is not None:
        setattr(row, 'timezone', payload.timezone); changed_time = True
    if payload.active is not None:
        setattr(row, 'active', payload.active)
    if payload.grace_minutes is not None:
        setattr(row, 'grace_minutes', payload.grace_minutes)
    now_utc = datetime.utcnow()
    if changed_time:
        next_local, next_utc = _compute_next_fire(now_utc, getattr(row, 'hour'), getattr(row, 'minute'), getattr(row, 'timezone'))
        setattr(row, 'next_fire_local', next_local)
        setattr(row, 'next_fire_utc', next_utc)
    if payload.ack_today:
        # mark acknowledgement for today's local date
        try:
            tz = pytz.timezone(getattr(row, 'timezone'))
        except Exception:
            tz = pytz.UTC
        now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
        setattr(row, 'last_ack_local_date', now_local.date())
    setattr(row, 'updated_at', now_utc)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.delete("/reminders/{reminder_id}")
async def delete_reminder(reminder_id: int, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id).where(models.Reminder.id == reminder_id))
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    await db.delete(row)
    await db.commit()
    return {"deleted": reminder_id}

@app.post("/reminders/reschedule-all")
async def reschedule_all(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    now_utc = datetime.utcnow()
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
    rows = res.scalars().all()
    count = 0
    for r in rows:
        next_local, next_utc = _compute_next_fire(now_utc, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
        setattr(r, 'next_fire_local', next_local)
        setattr(r, 'next_fire_utc', next_utc)
        setattr(r, 'updated_at', now_utc)
        db.add(r); count += 1
    if count:
        await db.commit()
    return {"rescheduled": count}

@app.post("/reminders/{reminder_id}/ack", response_model=schemas.ReminderResponse)
async def acknowledge_reminder(reminder_id: int, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id).where(models.Reminder.id == reminder_id))
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    now_utc = datetime.utcnow()
    try:
        tz = pytz.timezone(getattr(row, 'timezone'))
    except Exception:
        tz = pytz.UTC
    now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
    setattr(row, 'last_ack_local_date', now_local.date())
    setattr(row, 'updated_at', now_utc)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

class ReminderSyncItem(BaseModel):
    id: Optional[int] = None
    title: str
    body: str
    hour: int
    minute: int
    timezone: str
    active: bool
    grace_minutes: int
    ack_today: bool | None = None

class ReminderSyncRequest(BaseModel):
    items: list[ReminderSyncItem]
    prune_missing: bool = False  # if true, server deletes any reminders not listed

@app.post("/reminders/sync")
async def sync_reminders(payload: ReminderSyncRequest, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    now_utc = datetime.utcnow()
    existing_q = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
    existing = {int(getattr(r, 'id')): r for r in existing_q.scalars().all()}
    seen_ids: set[int] = set()
    created = 0
    updated = 0
    for item in payload.items:
        if item.id and int(item.id) in existing:
            row = existing[int(item.id)]
            changed_time = False
            if getattr(row, 'title') != item.title:
                setattr(row, 'title', item.title)
            if getattr(row, 'body') != item.body:
                setattr(row, 'body', item.body)
            if getattr(row, 'hour') != item.hour:
                setattr(row, 'hour', item.hour)
                changed_time = True
            if getattr(row, 'minute') != item.minute:
                setattr(row, 'minute', item.minute)
                changed_time = True
            if getattr(row, 'timezone') != item.timezone:
                setattr(row, 'timezone', item.timezone)
                changed_time = True
            if getattr(row, 'active') != item.active:
                setattr(row, 'active', item.active)
            if getattr(row, 'grace_minutes') != item.grace_minutes:
                setattr(row, 'grace_minutes', item.grace_minutes)
            if item.ack_today:
                try:
                    tz = pytz.timezone(item.timezone)
                except Exception:
                    tz = pytz.UTC
                now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
                setattr(row, 'last_ack_local_date', now_local.date())
            if changed_time:
                next_local, next_utc = _compute_next_fire(now_utc, item.hour, item.minute, item.timezone)
                setattr(row, 'next_fire_local', next_local)
                setattr(row, 'next_fire_utc', next_utc)
            setattr(row, 'updated_at', now_utc)
            db.add(row)
            updated += 1
            seen_ids.add(int(getattr(row, 'id')))
        else:
            next_local, next_utc = _compute_next_fire(now_utc, item.hour, item.minute, item.timezone)
            row = models.Reminder(
                patient_id=current_user.id,
                title=item.title,
                body=item.body,
                hour=item.hour,
                minute=item.minute,
                timezone=item.timezone,
                active=item.active,
                grace_minutes=item.grace_minutes,
                next_fire_local=next_local,
                next_fire_utc=next_utc,
            )
            if item.ack_today:
                try:
                    tz = pytz.timezone(item.timezone)
                except Exception:
                    tz = pytz.UTC
                now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
                setattr(row, 'last_ack_local_date', now_local.date())
            db.add(row)
            created += 1
    await db.commit()
    # Prune if requested
    pruned = 0
    if payload.prune_missing:
        existing_q2 = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
        for row in existing_q2.scalars().all():
            if row.id not in seen_ids and row.id in existing:
                await db.delete(row); pruned += 1
        if pruned:
            await db.commit()
    return {"created": created, "updated": updated, "pruned": pruned}

@app.get("/reminders/health")
async def reminders_health(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    now_utc = datetime.utcnow()
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
    rows = res.scalars().all()
    total = len(rows)
    active = sum(1 for r in rows if getattr(r, 'active'))
    due_now = sum(1 for r in rows if getattr(r, 'next_fire_utc') <= now_utc)
    pending_after_grace = 0
    for r in rows:
        if getattr(r, 'next_fire_utc') <= now_utc:
            try:
                tz = pytz.timezone(getattr(r, 'timezone'))
            except Exception:
                tz = pytz.UTC
            local_now = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
            scheduled_local = getattr(r, 'next_fire_local')
            if scheduled_local:
                sched_local = tz.localize(scheduled_local) if scheduled_local.tzinfo is None else scheduled_local.astimezone(tz)
                if local_now > sched_local + timedelta(minutes=getattr(r, 'grace_minutes') or 0):
                    pending_after_grace += 1
    return {"total": total, "active": active, "due_now": due_now, "pending_after_grace": pending_after_grace}

# ---------------------------
# Push notifications endpoints
# ---------------------------
@app.post("/push/schedule", response_model=schemas.ScheduledPushResponse)
async def schedule_push(
    request: Request,
    payload: Optional[schemas.ScheduledPushCreate] = Body(None),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    # Accept JSON body (preferred) or form-encoded fallback
    def _parse_iso_dt(s: str) -> datetime:
        # Support trailing 'Z' by converting to +00:00
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(s)
        except Exception:
            raise HTTPException(status_code=422, detail="Invalid send_at datetime format. Use ISO8601, e.g. 2025-09-22T15:30:00Z")

    if payload is None:
        try:
            form = await request.form()
        except Exception:
            form = None
        if form:
            title = form.get("title")
            body = form.get("body")
            send_at_str = form.get("send_at") or form.get("scheduled_time")
            if not (title and body and send_at_str):
                raise HTTPException(status_code=422, detail="Field required: title, body, send_at")
            # Convert potential UploadFile values to str explicitly
            title_s = title if isinstance(title, str) else str(title)
            body_s = body if isinstance(body, str) else str(body)
            send_at_s = send_at_str if isinstance(send_at_str, str) else str(send_at_str)
            payload = schemas.ScheduledPushCreate(title=title_s, body=body_s, send_at=_parse_iso_dt(send_at_s))
        else:
            raise HTTPException(status_code=422, detail="Body required: JSON or form with title, body, send_at")

    row = models.ScheduledPush(
        patient_id=current_user.id,
        title=payload.title,
        body=payload.body,
        send_at=payload.send_at,
        sent=False,
        created_at=datetime.utcnow(),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.post("/push/schedule-and-dispatch")
async def schedule_and_optionally_dispatch(
    request: Request,
    payload: Optional[schemas.ScheduledPushCreate] = Body(None),
    force_now: Optional[bool] = None,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    # Allow force_now via query param or JSON/form
    def _truthy(v: Optional[str | bool]) -> bool:
        if isinstance(v, bool):
            return v
        return str(v).lower() in {"1", "true", "yes", "on"}
    if force_now is None:
        force_now = _truthy(request.query_params.get("force_now"))
        if not force_now:
            try:
                data = await request.json()
                if isinstance(data, dict) and "force_now" in data:
                    force_now = _truthy(data["force_now"])  # type: ignore[index]
            except Exception:
                try:
                    form = await request.form()
                    if form and "force_now" in form:
                        fv = form.get("force_now")
                        force_now = _truthy(fv if isinstance(fv, str) else (str(fv) if fv is not None else None))
                except Exception:
                    pass

    # Reuse schedule_push logic to accept JSON or form
    if payload is None:
        try:
            form = await request.form()
        except Exception:
            form = None
        if form:
            title = form.get("title")
            body = form.get("body")
            send_at = form.get("send_at") or form.get("scheduled_time")
            if not (title and body and send_at):
                raise HTTPException(status_code=422, detail="Field required: title, body, send_at")
            s = str(send_at)
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            try:
                dt = datetime.fromisoformat(s)
            except Exception:
                raise HTTPException(status_code=422, detail="Invalid send_at datetime format. Use ISO8601")
            payload = schemas.ScheduledPushCreate(title=str(title), body=str(body), send_at=dt)
        else:
            raise HTTPException(status_code=422, detail="Body required: JSON or form with title, body, send_at")

    # Create the scheduled row
    row = models.ScheduledPush(
        patient_id=current_user.id,
        title=payload.title,
        body=payload.body,
        send_at=payload.send_at,
        sent=False,
        created_at=datetime.utcnow(),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)

    # Dispatch immediately if due or forced
    if force_now or payload.send_at <= datetime.utcnow():
        token_res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == current_user.id))
        tokens = [r[0] for r in token_res.all()]
        sent = 0
        for t in tokens:
            if send_fcm_notification(t, getattr(row, "title"), getattr(row, "body")):
                sent += 1
        setattr(row, "sent", True)
        setattr(row, "sent_at", datetime.utcnow())
        db.add(row)
        await db.commit()
        await db.refresh(row)
        return {"scheduled": row.id, "sent": sent, "dispatched": 1}

    return {"scheduled": row.id, "sent": 0, "dispatched": 0}

@app.get("/push/scheduled", response_model=list[schemas.ScheduledPushResponse])
async def list_scheduled_pushes(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.ScheduledPush).where(models.ScheduledPush.patient_id == current_user.id).order_by(models.ScheduledPush.send_at.asc()))
    return res.scalars().all()

@app.post("/push/dispatch-due")
async def dispatch_due_pushes(request: Request, db: AsyncSession = Depends(get_db)):
    """Dispatch all due scheduled pushes.
    Auth: supply the cron secret in one of the following (first match wins):
      - Header: X-CRON-KEY: <secret>
      - Query param: ?cron_key=<secret> or ?key=<secret>
      - Form body field (x-www-form-urlencoded or multipart): cron_key=<secret>
    """
    cron_secret = os.getenv("CRON_SECRET")
    # Collect provided key from multiple sources to avoid header stripping
    provided_key = (
        request.headers.get("X-CRON-KEY")
        or request.headers.get("x-cron-key")
        or request.query_params.get("cron_key")
        or request.query_params.get("key")
    )
    form_obj = None
    json_obj = None
    if not provided_key:
        try:
            form_obj = await request.form()
            provided_key = form_obj.get("cron_key") if form_obj else None
        except Exception:
            provided_key = None
    if not provided_key:
        try:
            json_obj = await request.json()
            if isinstance(json_obj, dict):
                provided_key = json_obj.get("cron_key") or json_obj.get("key")
        except Exception:
            pass
    if not cron_secret or provided_key != cron_secret:
        raise HTTPException(
            status_code=403,
            detail="Invalid cron key",
            headers={
                "X-Usage-Hint": "Send cron key via header X-CRON-KEY, query ?cron_key=, or body {cron_key} (form or json)"
            },
        )
    # Determine dry-run mode
    def _truthy(v: Optional[str]) -> bool:
        return str(v).lower() in {"1", "true", "yes", "on"}
    dry_run = _truthy(request.query_params.get("dry_run"))
    if not dry_run:
        if form_obj is None:
            try:
                form_obj = await request.form()
            except Exception:
                form_obj = None
        if form_obj:
            dv = form_obj.get("dry_run")
            if dv is not None:
                dry_run = _truthy(dv if isinstance(dv, str) else str(dv))
    if not dry_run and isinstance(json_obj, dict):
        dv = json_obj.get("dry_run")
        if dv is not None:
            dry_run = _truthy(dv if isinstance(dv, str) else str(dv))
    # Optional limit of pushes per call
    def _as_int(v: Optional[str], default: int) -> int:
        try:
            return int(str(v))
        except Exception:
            return default
    limit = _as_int(request.query_params.get("limit"), default=50)
    if form_obj and not request.query_params.get("limit"):
        lv = form_obj.get("limit")
        if lv is not None:
            limit = _as_int(lv if isinstance(lv, str) else str(lv), default=50)
    if (not request.query_params.get("limit")) and isinstance(json_obj, dict):
        lv = json_obj.get("limit")
        if lv is not None:
            limit = _as_int(lv if isinstance(lv, str) else str(lv), default=50)
    now = datetime.utcnow()
    res = await db.execute(
        select(models.ScheduledPush)
        .where(models.ScheduledPush.sent == False)
        .where(models.ScheduledPush.send_at <= now)
    )
    pushes = res.scalars().all()
    if limit and len(pushes) > limit:
        pushes = pushes[:limit]
    # If dry-run, return quickly without sending
    if dry_run:
        return {"sent": 0, "dispatched": len(pushes), "mode": "dry_run"}
    sent = 0
    for push in pushes:
        # Get all device tokens for patient
        token_res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == push.patient_id))
        tokens = [row[0] for row in token_res.all()]
        for t in tokens:
            ok = send_fcm_notification(t, getattr(push, "title"), getattr(push, "body"))
            if ok:
                sent += 1

        setattr(push, "sent", True)
        setattr(push, "sent_at", datetime.utcnow())
        db.add(push)
    # --- Reminder fallback processing ---
    now2 = datetime.utcnow()
    # Fetch active reminders whose next_fire_utc has passed
    rem_res = await db.execute(
        select(models.Reminder)
        .where(models.Reminder.active == True)
        .where(models.Reminder.next_fire_utc <= now2)
    )
    reminders = rem_res.scalars().all()
    dispatched_rem = 0
    for r in reminders:
        # Check grace & acknowledgement: skip if ack today
        try:
            tz = pytz.timezone(getattr(r, 'timezone'))
        except Exception:
            tz = pytz.UTC
        now_local = now2.replace(tzinfo=pytz.UTC).astimezone(tz)
        # If already acknowledged today, skip sending
        if getattr(r, 'last_ack_local_date') == now_local.date():
            # Still advance to next day to avoid tight loop
            next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
            setattr(r, 'next_fire_local', next_local)
            setattr(r, 'next_fire_utc', next_utc)
            setattr(r, 'updated_at', now2)
            db.add(r)
            continue
        # If within grace window since local scheduled time, skip for now
        scheduled_local_time = getattr(r, 'next_fire_local')
        # next_fire_local is the *target*; we only send when we reach/past it + inside grace start
        # Grace logic: wait grace_minutes before we send fallback (to allow local notification to fire first)
        grace_minutes = getattr(r, 'grace_minutes') or 0
        if scheduled_local_time:
            # Convert scheduled_local_time (stored naive as local?) to localized dt
            sched_local = tz.localize(scheduled_local_time) if scheduled_local_time.tzinfo is None else scheduled_local_time.astimezone(tz)
            grace_deadline = sched_local + timedelta(minutes=grace_minutes)
            if now_local < grace_deadline:
                # Skip until grace window passed
                continue
        # Send fallback push
        token_res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == getattr(r, 'patient_id')))
        tokens = [row[0] for row in token_res.all()]
        for t in tokens:
            if send_fcm_notification(t, getattr(r, 'title'), getattr(r, 'body')):
                sent += 1
                dispatched_rem += 1
        setattr(r, 'last_sent_utc', now2)
        # Advance to next day occurrence
        next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
        setattr(r, 'next_fire_local', next_local)
        setattr(r, 'next_fire_utc', next_utc)
        setattr(r, 'updated_at', now2)
        db.add(r)
    if pushes or reminders:
        await db.commit()
    return {"sent": sent, "dispatched_pushes": len(pushes), "dispatched_reminders": dispatched_rem}
@app.post("/push/register-device", response_model=schemas.DeviceTokenResponse)
async def register_device(
    request: Request,
    payload: Optional[schemas.DeviceRegisterRequest] = Body(None),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    if payload is None:
        # Try form first
        form = None
        try:
            form = await request.form()
        except Exception:
            form = None
        if form:
            platform = form.get("platform")
            token = form.get("token")
            if not (platform and token):
                # fall through to query/JSON error
                pass
            else:
                payload = schemas.DeviceRegisterRequest(platform=str(platform), token=str(token))
        if payload is None:
            # Try query params as a last resort
            qp = request.query_params
            qplat = qp.get("platform")
            qtok = qp.get("token")
            if qplat and qtok:
                payload = schemas.DeviceRegisterRequest(platform=qplat, token=qtok)
        if payload is None:
            raise HTTPException(status_code=422, detail="Body required: JSON or form with platform, token")
    # Upsert by unique token; if token exists, reassign to current user and update platform
    existing_q = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == payload.token))
    existing = existing_q.scalars().first()
    if existing:
        object.__setattr__(existing, 'patient_id', current_user.id)
        object.__setattr__(existing, 'platform', payload.platform)
        db.add(existing)
        await db.commit()
        await db.refresh(existing)
        # Enforce single-device-per-user if enabled
        if os.getenv("PUSH_SINGLE_DEVICE", "true").lower() in {"1", "true", "yes", "on"}:
            others_q = await db.execute(
                select(models.DeviceToken)
                .where(models.DeviceToken.patient_id == current_user.id)
                .where(models.DeviceToken.id != object.__getattribute__(existing, 'id'))
            )
            for d in others_q.scalars().all():
                await db.delete(d)
            await db.commit()
        return existing
    row = models.DeviceToken(patient_id=current_user.id, platform=payload.platform, token=payload.token)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    # Enforce single-device-per-user if enabled
    if os.getenv("PUSH_SINGLE_DEVICE", "true").lower() in {"1", "true", "yes", "on"}:
        others_q = await db.execute(
            select(models.DeviceToken)
            .where(models.DeviceToken.patient_id == current_user.id)
            .where(models.DeviceToken.id != object.__getattribute__(row, 'id'))
        )
        for d in others_q.scalars().all():
            await db.delete(d)
        await db.commit()
    return row

@app.get("/push/devices", response_model=List[schemas.DeviceTokenResponse])
async def list_my_devices(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.DeviceToken).where(models.DeviceToken.patient_id == current_user.id))
    return res.scalars().all()

@app.post("/push/test")
async def push_test(
    request: Request,
    payload: Optional[schemas.PushTestRequest] = Body(None),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    if payload is None:
        try:
            form = await request.form()
        except Exception:
            form = None
        if form:
            title = form.get("title")
            body = form.get("body")
            if not (title and body):
                raise HTTPException(status_code=422, detail="Field required: title, body")
            payload = schemas.PushTestRequest(title=str(title), body=str(body))
        else:
            raise HTTPException(status_code=422, detail="Body required: JSON or form with title, body")
    res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == current_user.id))
    tokens = [row[0] for row in res.all()]
    if not tokens:
        raise HTTPException(status_code=400, detail="No registered device tokens")
    debug = request.query_params.get("debug", "").lower() in {"1", "true", "yes", "on"}
    sent = 0
    details = []
    for t in tokens:
        if debug:
            res = send_fcm_notification_ex(t, payload.title, payload.body)
            if res.get("ok"):
                sent += 1
            details.append({"token": t[-12:] if len(t) > 12 else t, **res})
        else:
            if send_fcm_notification(t, payload.title, payload.body):
                sent += 1
    resp: dict[str, Any] = {"sent": sent, "total": len(tokens)}
    if debug:
        resp["debug"] = {"details": details}
    return resp

@app.post("/push/now")
async def push_now(
    request: Request,
    payload: Optional[schemas.PushTestRequest] = Body(None),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    return await push_test(request, payload, db, current_user)

@app.post("/push/ping")
async def push_ping(request: Request, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == current_user.id))
    tokens = [row[0] for row in res.all()]
    if not tokens:
        raise HTTPException(status_code=400, detail="No registered device tokens")
    title = "Hello from MGM"
    body = "This is a quick test push."
    debug = request.query_params.get("debug", "").lower() in {"1", "true", "yes", "on"}
    sent = 0
    details = []
    for t in tokens:
        if debug:
            res_det = send_fcm_notification_ex(t, title, body)
            if res_det.get("ok"):
                sent += 1
            details.append({"token": t[-12:] if len(t) > 12 else t, **res_det})
        else:
            if send_fcm_notification(t, title, body):
                sent += 1
    resp: dict[str, Any] = {"sent": sent, "total": len(tokens), "title": title, "body": body}
    if debug:
        resp["debug"] = {"details": details}
    return resp

@app.post("/push/prune-invalid")
async def prune_invalid_devices(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    debug = request.query_params.get("debug", "").lower() in {"1", "true", "yes", "on"}
    dry_run = request.query_params.get("dry_run", "").lower() in {"1", "true", "yes", "on"}
    res = await db.execute(select(models.DeviceToken).where(models.DeviceToken.patient_id == current_user.id))
    devices = res.scalars().all()
    if not devices:
        return {"removed": 0, "checked": 0}
    removed = 0
    details = []
    title = "MGM token check"
    body = "Verifying your notification token."
    for dev in devices:
        det = send_fcm_notification_ex(object.__getattribute__(dev, 'token'), title, body)
        is_invalid = False
        txt = (det.get("body") or "").upper()
        if not det.get("ok"):
            for marker in ("UNREGISTERED", "NOT_FOUND", "INVALID_ARGUMENT", "MISMATCH_SENDER_ID"):
                if marker in txt:
                    is_invalid = True
                    break
        if is_invalid:
            if not dry_run:
                await db.delete(dev)
            removed += 1
        if debug:
            details.append({
                "id": object.__getattribute__(dev, 'id'),
                "token": object.__getattribute__(dev, 'token')[-12:],
                "result": det,
                "invalid": is_invalid,
            })
    if not dry_run and removed:
        await db.commit()
    resp = {"removed": removed, "checked": len(devices), "dry_run": dry_run}
    if debug:
        resp["debug"] = details
    return resp

@app.delete("/push/devices/{device_id}")
async def delete_device(device_id: int, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.DeviceToken).where(models.DeviceToken.id == device_id).where(models.DeviceToken.patient_id == current_user.id))
    dev = res.scalars().first()
    if not dev:
        raise HTTPException(status_code=404, detail="Device not found")
    await db.delete(dev)
    await db.commit()
    return {"deleted": device_id}

# Simpler: Dispatch due pushes for the authenticated user (no cron key)
@app.post("/push/dispatch-mine")
async def dispatch_my_due_pushes(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    def _truthy(v: Optional[str]) -> bool:
        return str(v).lower() in {"1", "true", "yes", "on"}
    dry_run = _truthy(request.query_params.get("dry_run"))
    def _as_int(v: Optional[str], default: int) -> int:
        try:
            return int(str(v))
        except Exception:
            return default
    limit = _as_int(request.query_params.get("limit"), default=20)

    now = datetime.utcnow()
    res = await db.execute(
        select(models.ScheduledPush)
        .where(models.ScheduledPush.patient_id == current_user.id)
        .where(models.ScheduledPush.sent == False)
        .where(models.ScheduledPush.send_at <= now)
        .order_by(models.ScheduledPush.id.asc())
    )
    pushes = res.scalars().all()
    if limit and len(pushes) > limit:
        pushes = pushes[:limit]
    if dry_run:
        return {"sent": 0, "dispatched": len(pushes), "mode": "dry_run"}

    sent = 0
    for push in pushes:
        token_res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == current_user.id))
        tokens = [row[0] for row in token_res.all()]
        for t in tokens:
            ok = send_fcm_notification(t, getattr(push, "title"), getattr(push, "body"))
            if ok:
                sent += 1
        setattr(push, "sent", True)
        setattr(push, "sent_at", datetime.utcnow())
        db.add(push)
    if pushes:
        await db.commit()
    return {"sent": sent, "dispatched": len(pushes)}