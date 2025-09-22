from datetime import datetime, timedelta, date
import os
from typing import List, Optional

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

from utils import send_registration_email, send_fcm_notification
import os
from fastapi import Request
from routes import auth

app = FastAPI()

app.include_router(auth.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(models.Base.metadata.create_all)

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
        "x-forwarded-authorization",
        "X-Forwarded-Authorization",
    ]
    for h in candidate_headers:
        v = request.headers.get(h)
        if not v:
            continue
        # Expect format: "Bearer <token>"
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

@app.get("/push/scheduled", response_model=list[schemas.ScheduledPushResponse])
async def list_scheduled_pushes(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.ScheduledPush).where(models.ScheduledPush.patient_id == current_user.id).order_by(models.ScheduledPush.send_at.asc()))
    return res.scalars().all()

@app.post("/push/dispatch-due")
async def dispatch_due_pushes(request: Request, db: AsyncSession = Depends(get_db)):
    cron_secret = os.getenv("CRON_SECRET")
    key = request.headers.get("X-CRON-KEY")
    if not cron_secret or key != cron_secret:
        raise HTTPException(status_code=403, detail="Invalid cron key")
    now = datetime.utcnow()
    res = await db.execute(
        select(models.ScheduledPush)
        .where(models.ScheduledPush.sent == False)
        .where(models.ScheduledPush.send_at <= now)
    )
    pushes = res.scalars().all()
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
    if pushes:
        await db.commit()
    return {"sent": sent, "dispatched": len(pushes)}
@app.post("/push/register-device", response_model=schemas.DeviceTokenResponse)
async def register_device(payload: schemas.DeviceRegisterRequest, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    # Upsert by unique token; if token exists, reassign to current user and update platform
    existing_q = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == payload.token))
    existing = existing_q.scalars().first()
    if existing:
        object.__setattr__(existing, 'patient_id', current_user.id)
        object.__setattr__(existing, 'platform', payload.platform)
        db.add(existing)
        await db.commit()
        await db.refresh(existing)
        return existing
    row = models.DeviceToken(patient_id=current_user.id, platform=payload.platform, token=payload.token)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.get("/push/devices", response_model=List[schemas.DeviceTokenResponse])
async def list_my_devices(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.DeviceToken).where(models.DeviceToken.patient_id == current_user.id))
    return res.scalars().all()

@app.post("/push/test")
async def push_test(payload: schemas.PushTestRequest, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == current_user.id))
    tokens = [row[0] for row in res.all()]
    if not tokens:
        raise HTTPException(status_code=400, detail="No registered device tokens")
    sent = 0
    for t in tokens:
        if send_fcm_notification(t, payload.title, payload.body):
            sent += 1
    return {"sent": sent, "total": len(tokens)}