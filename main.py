from datetime import datetime, timedelta, date
import traceback
import os
from typing import List, Optional, Any
from pydantic import BaseModel
import asyncio  # moved here so exception handlers can reference

import models
from database import get_db, AsyncSessionLocal

from fastapi import FastAPI, Depends, HTTPException, status, Body, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, delete
from sqlalchemy.exc import IntegrityError

import schemas
from database import engine
import instruction_catalog

from utils import send_registration_email, send_fcm_notification, send_fcm_notification_ex
import os
from fastapi import Request
from sqlalchemy import and_, or_, select
from sqlalchemy import func
from datetime import datetime, timedelta
import pytz
from routes import auth
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
import asyncio

app = FastAPI()

# Unverified signups are auto-pruned after this many hours (set env to 0/negative to disable)
UNVERIFIED_SIGNUP_RETENTION_HOURS = int(os.getenv("UNVERIFIED_SIGNUP_RETENTION_HOURS", "24"))

# In-memory rate limiter buckets for instruction status endpoint (patient_id -> list[timestamps])
# NOTE: Single-process only. Replace with shared store (Redis) for multi-worker deployments.
_instruction_rate_limiter: dict[int, list[float]] = {}

# --- In-memory instrumentation for reminder fallback dispatch (non-persistent) ---
# Updated each time /push/dispatch-due (or scheduler invoking dispatch_due_pushes) runs.
REMINDER_DISPATCH_LAST_RUN: Optional[datetime] = None
REMINDER_DISPATCH_LAST_COUNTS: dict[str, Any] = {}

app.include_router(auth.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def schedule_existing_unverified_cleanup() -> None:
    """At startup, queue cleanup tasks for any lingering unverified signups."""
    if UNVERIFIED_SIGNUP_RETENTION_HOURS <= 0:
        return
    try:
        async with AsyncSessionLocal() as _session:
            res = await _session.execute(select(models.Patient.id).where(models.Patient.is_verified == False))
            pending_ids = list(res.scalars())
        for pid in pending_ids:
            _schedule_unverified_cleanup(pid)
        if pending_ids:
            print(f"[signup-cleanup] Scheduled cleanup for {len(pending_ids)} unverified patient(s) on startup")
    except Exception as exc:
        # On first boot with a brand-new database (e.g., new Neon project), tables
        # may not exist until the schema startup hook runs. Avoid misleading noise.
        msg = str(exc)
        if "does not exist" in msg or "UndefinedTable" in msg:
            print("[signup-cleanup] Skipped (tables not ready yet)")
            return
        print(f"[signup-cleanup] Failed to schedule startup cleanup: {exc}")

@app.get("/healthz")
async def healthz():
    # Cheap DB probe (optional, ignore errors to still return ok if DB transiently slow)
    try:
        async with AsyncSessionLocal() as db:
            await db.execute(select(1))
        db_ok = True
    except Exception:
        db_ok = False
    return {"ok": True, "db": db_ok}

@app.head("/healthz")
async def healthz_head():
    # Some uptime monitors use HEAD. Mirror GET semantics.
    return await healthz()

@app.get("/diag/echo")
async def diag_echo():
    """Minimal fast diagnostic endpoint to verify service reachability and latency.
    Returns server UTC timestamp and a static message without touching the DB."""
    now = datetime.utcnow().isoformat() + "Z"
    return {"echo": "ok", "utc": now}

@app.get("/reminders/health")
async def reminders_health(db: AsyncSession = Depends(get_db)):
    """Lightweight insight into reminder fallback system.
    Returns last dispatch attempt timestamp and counts plus active reminder stats for current authenticated user (optional).
    If auth header present, will scope reminder counts to that user; otherwise returns global aggregates.
    """
    from fastapi import Request as _Req
    # Try to get bearer if possible (best-effort, do not fail if missing)
    user_id = None
    try:
        # We cannot rely on dependency chain here without enforcing auth; manually parse token
        # Reuse existing logic by calling get_current_user if token present
        # Build a fake request to extract token from contextless call is complex; instead rely on normal dependency if provided.
        pass
    except Exception:
        user_id = None
    # Aggregate reminder counts
    total_active = 0
    try:
        res = await db.execute(select(models.Reminder).where(models.Reminder.active == True))
        rows = res.scalars().all()
        total_active = len(rows)
    except Exception:
        pass
    return {
        "last_run": REMINDER_DISPATCH_LAST_RUN.isoformat() if REMINDER_DISPATCH_LAST_RUN else None,
        "last_counts": REMINDER_DISPATCH_LAST_COUNTS,
        "active_reminders": total_active,
    }

@app.get("/reminders/debug-ops")
async def reminders_debug_ops(limit: int = 50, db: AsyncSession = Depends(get_db)):
    """Return recently attempted reminders that are in retry/token_invalid/failed states.
    Intended for operational diagnostics.
    """
    problematic_status = {"retry", "token_invalid", "failed_permanent"}
    res = await db.execute(select(models.Reminder).where(models.Reminder.last_delivery_status.in_(problematic_status)).order_by(models.Reminder.last_attempt_utc.desc()))
    rows = res.scalars().all()
    out = []
    for r in rows[:limit]:
        out.append({
            "id": object.__getattribute__(r,'id'),
            "patient_id": getattr(r,'patient_id'),
            "title": getattr(r,'title'),
            "status": getattr(r,'last_delivery_status'),
            "attempts_today": getattr(r,'attempts_today'),
            "next_fire_utc": getattr(r,'next_fire_utc').isoformat() if getattr(r,'next_fire_utc') else None,
            "last_attempt_utc": getattr(r,'last_attempt_utc').isoformat() if getattr(r,'last_attempt_utc') else None,
        })
    return {"count": len(out), "reminders": out}

@app.get("/push/diag")
async def push_diag(request: Request):
    """Return server-side FCM configuration visibility + optional token test.
    Query params:
      token=<device_fcm_token>  (optional) if provided, will attempt a debug send (title 'Diag', body 'Test').
    NEVER returns secrets; only boolean presence flags.
    """
    import base64, json as _json, os as _os
    sa_present = bool(_os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON") or _os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON_B64"))
    legacy_present = bool(_os.getenv("FCM_SERVER_KEY"))
    project_id = _os.getenv("FIREBASE_PROJECT_ID")
    diag: dict[str, Any] = {
        "has_v1_config": sa_present,
        "has_legacy_key": legacy_present,
        "project_id_set": bool(project_id),
    }
    token = request.query_params.get("token")
    if token:
        # Perform a lightweight debug send (will fail gracefully if config incomplete)
        res = send_fcm_notification_ex(token, "Diag", "Test push")  # type: ignore
        # Drop large bodies
        body_txt = res.get("body") or ""
        if len(body_txt) > 400:
            body_txt = body_txt[:400] + "…(truncated)"
        diag["test_send"] = {k: (body_txt if k == "body" else v) for k, v in res.items()}
    return diag

@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(models.Base.metadata.create_all)
        # --- InstructionStatus hardening: dedupe & ensure unique index for idempotent upserts ---
        try:
            # Remove duplicate logical rows keeping the latest (highest id)
            await conn.execute(text(
                """
                WITH ranked AS (
                  SELECT id, ROW_NUMBER() OVER (
                    PARTITION BY patient_id, date, "group", instruction_index
                    ORDER BY id DESC
                  ) AS rn
                  FROM instruction_status
                )
                DELETE FROM instruction_status WHERE id IN (
                  SELECT id FROM ranked WHERE rn > 1
                );
                """
            ))
            # Create unique index to support ON CONFLICT upserts (ignore if already exists)
            await conn.execute(text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ux_instruction_identity ON instruction_status (patient_id, date, \"group\", instruction_index);"
            ))
            # Ensure updated_at column exists (auto-migration for older deployments)
            try:
                result = await conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='instruction_status' AND column_name='updated_at';"))
                col = result.first()
                if not col:
                    print("[Startup] Adding missing instruction_status.updated_at column and backfilling …")
                    # Add column with default now and backfill existing rows
                    await conn.execute(text("ALTER TABLE instruction_status ADD COLUMN updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW() NOT NULL;"))
                    # Optional index to accelerate /instruction-status/changes queries
                    await conn.execute(text("CREATE INDEX IF NOT EXISTS ix_instruction_status_updated_at ON instruction_status (updated_at);"))
                    print("[Startup] instruction_status.updated_at added.")
                else:
                    # Still ensure index exists
                    await conn.execute(text("CREATE INDEX IF NOT EXISTS ix_instruction_status_updated_at ON instruction_status (updated_at);"))
            except Exception as mig_e:
                print(f"[Startup] WARNING could not ensure updated_at column/index: {mig_e}")
        except Exception as e:
            print(f"[Startup] InstructionStatus index init warning: {e}")
        # --- Lightweight online migrations for new push/reminder columns ---
        try:
            # DeviceToken lifecycle columns
            cols = await conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='device_tokens';"))
            existing_cols = {r[0] for r in cols.fetchall()}
            alter_stmts = []
            if 'active' not in existing_cols:
                alter_stmts.append("ALTER TABLE device_tokens ADD COLUMN active BOOLEAN DEFAULT TRUE NOT NULL;")
            if 'deactivated_at' not in existing_cols:
                alter_stmts.append("ALTER TABLE device_tokens ADD COLUMN deactivated_at TIMESTAMP WITHOUT TIME ZONE NULL;")
            if 'deactivated_reason' not in existing_cols:
                alter_stmts.append("ALTER TABLE device_tokens ADD COLUMN deactivated_reason VARCHAR NULL;")
            if 'local_reminders_enabled' not in existing_cols:
                alter_stmts.append("ALTER TABLE device_tokens ADD COLUMN local_reminders_enabled BOOLEAN DEFAULT FALSE NOT NULL;")
            for stmt in alter_stmts:
                try:
                    await conn.execute(text(stmt))
                except Exception as _e:
                    print(f"[Startup] device_tokens migration note: {_e}")
            # Reminder retry / instrumentation columns
            rcols = await conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='reminders';"))
            existing_rcols = {r[0] for r in rcols.fetchall()}
            r_alter = []
            if 'attempts_today' not in existing_rcols:
                r_alter.append("ALTER TABLE reminders ADD COLUMN attempts_today INTEGER DEFAULT 0 NOT NULL;")
            if 'last_attempt_utc' not in existing_rcols:
                r_alter.append("ALTER TABLE reminders ADD COLUMN last_attempt_utc TIMESTAMP WITHOUT TIME ZONE NULL;")
            if 'last_delivery_status' not in existing_rcols:
                r_alter.append("ALTER TABLE reminders ADD COLUMN last_delivery_status VARCHAR NULL;")
            for stmt in r_alter:
                try:
                    await conn.execute(text(stmt))
                except Exception as _e:
                    print(f"[Startup] reminders migration note: {_e}")

            # UserSession table for multi-device login warnings
            try:
                await conn.execute(text(
                    """
                    CREATE TABLE IF NOT EXISTS user_sessions (
                      id SERIAL PRIMARY KEY,
                      patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
                      device_id VARCHAR NOT NULL,
                      device_name VARCHAR NULL,
                      created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW() NOT NULL,
                      last_seen_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW() NOT NULL,
                      active BOOLEAN DEFAULT TRUE NOT NULL,
                      CONSTRAINT ux_user_sessions_patient_device UNIQUE (patient_id, device_id)
                    );
                    """
                ))
                await conn.execute(text(
                    "CREATE INDEX IF NOT EXISTS ix_user_sessions_patient_active ON user_sessions (patient_id, active);"
                ))
                await conn.execute(text(
                    "CREATE INDEX IF NOT EXISTS ix_user_sessions_last_seen_at ON user_sessions (last_seen_at);"
                ))
                # Enforce at most one active session per patient (Postgres partial unique index)
                await conn.execute(text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS ux_user_sessions_patient_active_true ON user_sessions (patient_id) WHERE active = TRUE;"
                ))
            except Exception as sess_mig_e:
                print(f"[Startup] user_sessions migration note: {sess_mig_e}")
        except Exception as mig_all:
            print(f"[Startup] WARNING push/reminder migration block failed: {mig_all}")

        # --- Patients table lightweight migrations (completion history flags) ---
        try:
            patients_cols: set[str] = set()
            try:
                pcols = await conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='patients';"))
                patients_cols = {r[0] for r in pcols.fetchall()}
            except Exception:
                # SQLite fallback
                try:
                    pcols = await conn.execute(text("PRAGMA table_info(patients);"))
                    patients_cols = {r[1] for r in pcols.fetchall()}
                except Exception:
                    patients_cols = set()

            p_alter: list[str] = []
            if 'ever_completed' not in patients_cols:
                p_alter.append("ALTER TABLE patients ADD COLUMN ever_completed BOOLEAN DEFAULT FALSE NOT NULL;")
            if 'last_completed_episode_id' not in patients_cols:
                p_alter.append("ALTER TABLE patients ADD COLUMN last_completed_episode_id INTEGER NULL;")
            if 'last_completed_at' not in patients_cols:
                p_alter.append("ALTER TABLE patients ADD COLUMN last_completed_at TIMESTAMP WITHOUT TIME ZONE NULL;")

            for stmt in p_alter:
                try:
                    await conn.execute(text(stmt))
                except Exception as _e:
                    print(f"[Startup] patients migration note: {_e}")
        except Exception as p_mig_all:
            print(f"[Startup] WARNING patients migration block failed: {p_mig_all}")

        # --- Read-only view: completed_patients (one row per completed+locked episode) ---
        # This view intentionally allows multiple rows with the same email/phone/etc.
        # because it represents historical procedures (episodes), not unique accounts.
        try:
            dialect_name = getattr(getattr(engine, "dialect", None), "name", "") or ""
            where_clause = "te.procedure_completed = TRUE AND te.locked = TRUE"
            if dialect_name.lower() == "sqlite":
                # SQLite stores booleans as integers.
                where_clause = "te.procedure_completed = 1 AND te.locked = 1"

            view_body = f"""
                SELECT
                  te.id AS episode_id,
                  p.id AS patient_id,
                  p.username AS username,
                  p.name AS name,
                  p.phone AS phone,
                  p.email AS email,
                  te.department AS department,
                  te.doctor AS doctor,
                  te.treatment AS treatment,
                  te.subtype AS treatment_subtype,
                  te.procedure_date AS procedure_date,
                  te.procedure_time AS procedure_time,
                  te.created_at AS episode_created_at,
                  p.last_completed_at AS patient_last_completed_at
                FROM treatment_episodes te
                JOIN patients p ON p.id = te.patient_id
                WHERE {where_clause}
            """

            if dialect_name.lower() == "sqlite":
                await conn.execute(text("DROP VIEW IF EXISTS completed_patients"))
                await conn.execute(text(f"CREATE VIEW completed_patients AS {view_body}"))
            else:
                await conn.execute(text(f"CREATE OR REPLACE VIEW completed_patients AS {view_body}"))
        except Exception as view_mig_e:
            print(f"[Startup] completed_patients view migration note: {view_mig_e}")
    if os.getenv("SCHEDULER_ENABLED", "1") == "1":
        print("[Startup] Scheduler enabled (SCHEDULER_ENABLED=1)")
        scheduler = AsyncIOScheduler()
        _dispatch_lock = asyncio.Lock()
        async def _run_dispatch():
            if _dispatch_lock.locked():
                return
            async with _dispatch_lock:
                agen = get_db()
                db = None
                try:
                    db = await agen.__anext__()  # type: ignore
                except StopAsyncIteration:
                    db = None
                try:
                    if db is not None:
                        debug_env = os.getenv("DISPATCH_DEBUG", "0").lower() in {"1","true","yes","on"}
                        res = await _internal_dispatch_due(db, dry_run=False, limit=50, debug=debug_env)
                        if debug_env:
                            print(f"[Scheduler][debug] {res}")
                except Exception as e:
                    print(f"[Scheduler] dispatch internal error: {e}")
                finally:
                    try:
                        await agen.aclose()  # type: ignore
                    except Exception:
                        pass
        # Make dispatch interval configurable to tune delivery latency.
        # Default is 5s to avoid "~45s late" delivery when users set an exact minute.
        try:
            interval_sec = int(os.getenv("DISPATCH_INTERVAL_SEC", "5"))
        except Exception:
            interval_sec = 5
        if interval_sec < 5:
            interval_sec = 5  # clamp to safe minimum
        print(f"[Startup] Dispatch interval set to {interval_sec}s (DISPATCH_INTERVAL_SEC)")
        scheduler.add_job(_run_dispatch, IntervalTrigger(seconds=interval_sec), id="dispatch_due", replace_existing=True)

        # Optional: adherence nudges (server-side instruction follow-up)
        if os.getenv("ADHERENCE_NUDGE_ENABLED", "1").lower() in {"1", "true", "yes", "on"}:
            _adherence_lock = asyncio.Lock()
            async def _run_adherence():
                if _adherence_lock.locked():
                    return
                async with _adherence_lock:
                    agen = get_db()
                    db = None
                    try:
                        db = await agen.__anext__()  # type: ignore
                    except StopAsyncIteration:
                        db = None
                    try:
                        if db is not None:
                            debug_env = os.getenv("ADHERENCE_DEBUG", "0").lower() in {"1", "true", "yes", "on"}
                            res = await _internal_send_adherence_nudges(db)
                            if debug_env:
                                print(f"[Scheduler][adherence][debug] {res}")
                    except Exception as e:
                        print(f"[Scheduler] adherence internal error: {e}")
                    finally:
                        try:
                            await agen.aclose()  # type: ignore
                        except Exception:
                            pass

            try:
                adh_interval_sec = int(os.getenv("ADHERENCE_INTERVAL_SEC", "300"))
            except Exception:
                adh_interval_sec = 300
            if adh_interval_sec < 30:
                adh_interval_sec = 30
            print(f"[Startup] Adherence interval set to {adh_interval_sec}s (ADHERENCE_INTERVAL_SEC)")
            scheduler.add_job(_run_adherence, IntervalTrigger(seconds=adh_interval_sec), id="adherence_nudge", replace_existing=True)

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


async def _internal_send_adherence_nudges(db: AsyncSession) -> dict[str, Any]:
    """Server-side adherence nudges.

    Strategy:
      - For each patient with an active device token and an active (or recent) reminder timezone,
        compute their local "today".
      - If local time is within the configured window, and adherence for today is below threshold
        (or there is no activity), send an FCM push.
      - Suppress to once per patient per local day using models.AdherenceNudge unique constraint.
    """
    now_utc = datetime.utcnow()

    enabled = os.getenv("ADHERENCE_NUDGE_ENABLED", "1").lower() in {"1", "true", "yes", "on"}
    if not enabled:
        return {"enabled": False, "evaluated": 0, "nudged": 0, "skipped": 0}

    # Allow a range of hours (e.g. "8,9") for morning windows.
    # Back-compat: if ADHERENCE_NUDGE_LOCAL_HOURS not set, use ADHERENCE_NUDGE_LOCAL_HOUR.
    hours_raw = os.getenv("ADHERENCE_NUDGE_LOCAL_HOURS")
    allowed_hours: set[int]
    if hours_raw:
        allowed_hours = set()
        for part in hours_raw.split(','):
            part = part.strip()
            if not part:
                continue
            try:
                allowed_hours.add(int(part))
            except Exception:
                pass
        if not allowed_hours:
            allowed_hours = {8}
    else:
        try:
            target_hour = int(os.getenv("ADHERENCE_NUDGE_LOCAL_HOUR", "20"))
        except Exception:
            target_hour = 20
        allowed_hours = {target_hour}
    try:
        minute_window = int(os.getenv("ADHERENCE_NUDGE_MINUTE_WINDOW", "30"))
    except Exception:
        minute_window = 30
    if minute_window < 1:
        minute_window = 1
    if minute_window > 60:
        minute_window = 60
    try:
        threshold = float(os.getenv("ADHERENCE_NUDGE_THRESHOLD", "0.6"))
    except Exception:
        threshold = 0.6
    try:
        max_days_after = int(os.getenv("ADHERENCE_MAX_DAYS_AFTER_PROCEDURE", "60"))
    except Exception:
        max_days_after = 60
    # India (including Maharashtra) uses Asia/Kolkata
    default_tz = os.getenv("ADHERENCE_DEFAULT_TZ", "Asia/Kolkata")

    def _extract_fcm_error(body: str | None) -> str | None:
        if not body:
            return None
        for key in ["UNREGISTERED", "InvalidRegistration", "NotRegistered", "MismatchSenderId", "QuotaExceeded", "Internal", "Unavailable"]:
            if key in body:
                return key
        return None

    async def _get_patient_timezone(patient_id: int) -> str:
        # Use reminder timezone if available (best proxy for user's current device timezone)
        try:
            tz_res = await db.execute(
                select(models.Reminder.timezone)
                .where(models.Reminder.patient_id == patient_id)
                .order_by(models.Reminder.updated_at.desc())
                .limit(1)
            )
            tz_name = tz_res.scalar_one_or_none()
            if tz_name:
                return str(tz_name)
        except Exception:
            pass
        return default_tz

    def _normalize_procedure_date(value: Any) -> date | None:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value.date()
        if isinstance(value, date):
            return value
        try:
            s = str(value)
            # Accept "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS" strings
            return date.fromisoformat(s[:10])
        except Exception:
            return None

    evaluated = 0
    nudged = 0
    skipped = 0
    errors = 0

    # Consider only patients that currently have at least one active token.
    # This also reduces DB work for large tables.
    pat_res = await db.execute(
        select(models.Patient)
        .join(models.DeviceToken, models.DeviceToken.patient_id == models.Patient.id)
        .where(models.DeviceToken.active == True)
        .where(or_(models.Patient.procedure_completed == False, models.Patient.procedure_completed.is_(None)))
        .distinct()
    )
    patients = pat_res.scalars().all()

    for p in patients:
        evaluated += 1
        try:
            pid = object.__getattribute__(p, "id")
            proc_date = _normalize_procedure_date(getattr(p, "procedure_date"))
            if not proc_date:
                skipped += 1
                continue

            tz_name = await _get_patient_timezone(pid)
            try:
                tz = pytz.timezone(tz_name)
            except Exception:
                tz = pytz.UTC
                tz_name = "UTC"

            now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
            if now_local.hour not in allowed_hours:
                skipped += 1
                continue
            if now_local.minute >= minute_window:
                skipped += 1
                continue

            local_day = now_local.date()
            day_delta = (local_day - proc_date).days
            if day_delta < 0 or (max_days_after >= 0 and day_delta > max_days_after):
                skipped += 1
                continue

            # Compute adherence for today (local day)
            sres = await db.execute(
                select(models.InstructionStatus.followed)
                .where(models.InstructionStatus.patient_id == pid)
                .where(models.InstructionStatus.date == local_day)
            )
            flags = [bool(row[0]) for row in sres.all()]
            total = len(flags)
            followed = sum(1 for f in flags if f)
            ratio_val: float | None = None
            if total > 0:
                ratio_val = followed / float(total)

            needs_attention = (total == 0) or (ratio_val is not None and ratio_val < threshold)
            ok_enabled = os.getenv("ADHERENCE_ALRIGHT_ENABLED")
            if ok_enabled is None:
                ok_enabled = os.getenv("ADHERENCE_OK_ENABLED", "0")
            ok_enabled = str(ok_enabled).lower() in {"1", "true", "yes", "on"}
            if (not needs_attention) and (not ok_enabled):
                skipped += 1
                continue

            # Suppress to once/day via unique constraint
            nudge_row = models.AdherenceNudge(
                patient_id=pid,
                local_date=local_day,
                timezone=tz_name,
                total=total,
                followed=followed,
                ratio=(f"{ratio_val:.3f}" if ratio_val is not None else None),
                status="pending",
                created_at=now_utc,
            )
            db.add(nudge_row)
            try:
                await db.commit()
                await db.refresh(nudge_row)
            except IntegrityError:
                await db.rollback()
                skipped += 1
                continue

            # Send to all active tokens
            tok_res = await db.execute(
                select(models.DeviceToken.token)
                .where(models.DeviceToken.patient_id == pid)
                .where(models.DeviceToken.active == True)
            )
            tokens = [row[0] for row in tok_res.all()]
            if not tokens:
                object.__setattr__(nudge_row, "tokens_attempted", 0)
                object.__setattr__(nudge_row, "tokens_sent", 0)
                object.__setattr__(nudge_row, "status", "no_tokens")
                db.add(nudge_row)
                await db.commit()
                nudged += 1
                continue

            if needs_attention:
                title = os.getenv("ADHERENCE_NUDGE_TITLE", "Instruction Reminder")
                body = os.getenv("ADHERENCE_NUDGE_BODY", "Please follow your instructions today.")
                kind = "adherence_nudge"
            else:
                title = os.getenv("ADHERENCE_ALRIGHT_TITLE") or os.getenv("ADHERENCE_OK_TITLE", "All right")
                body = os.getenv("ADHERENCE_ALRIGHT_BODY") or os.getenv(
                    "ADHERENCE_OK_BODY",
                    "You're doing well. Please continue following your doctor's instructions.",
                )
                kind = "adherence_ok"
            data = {"type": kind, "local_date": local_day.isoformat()}

            attempted = 0
            sent_tokens = 0
            for t in tokens:
                attempted += 1
                try:
                    adh_ttl = int(os.getenv("ADHERENCE_FCM_TTL_SECONDS", "7200"))
                except Exception:
                    adh_ttl = 7200
                if adh_ttl < 0:
                    adh_ttl = 0
                res_obj = send_fcm_notification_ex(str(t), title, body, data=data, ttl_seconds=adh_ttl)  # type: ignore
                if res_obj.get("ok"):
                    sent_tokens += 1
                else:
                    err_code = _extract_fcm_error(res_obj.get("body"))
                    if err_code in {"UNREGISTERED", "NotRegistered"}:
                        tok_row = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == t))
                        tok = tok_row.scalars().first()
                        if tok and getattr(tok, "active"):
                            object.__setattr__(tok, "active", False)
                            object.__setattr__(tok, "deactivated_at", datetime.utcnow())
                            object.__setattr__(tok, "deactivated_reason", "UNREGISTERED")
                            db.add(tok)

            object.__setattr__(nudge_row, "tokens_attempted", attempted)
            object.__setattr__(nudge_row, "tokens_sent", sent_tokens)
            if sent_tokens > 0:
                object.__setattr__(nudge_row, "status", "sent_ok" if not needs_attention else "sent_attention")
            else:
                object.__setattr__(nudge_row, "status", "failed")
            db.add(nudge_row)
            await db.commit()

            nudged += 1
        except Exception:
            errors += 1
            try:
                await db.rollback()
            except Exception:
                pass
            print(f"[adherence] per-patient error patient_id={getattr(p, 'id', None)}\n{traceback.format_exc()}")
            continue

    return {"enabled": True, "evaluated": evaluated, "nudged": nudged, "skipped": skipped, "errors": errors}


async def _internal_preview_adherence_nudges(
    db: AsyncSession,
    *,
    max_patients: int = 200,
    sample: int = 50,
) -> dict[str, Any]:
    """Dry-run preview for adherence nudges.

    This does NOT send push notifications and does NOT write to AdherenceNudge.
    Intended for ops/debug to verify config + eligibility quickly.
    """
    now_utc = datetime.utcnow()

    enabled = os.getenv("ADHERENCE_NUDGE_ENABLED", "1").lower() in {"1", "true", "yes", "on"}

    def _normalize_procedure_date(value: Any) -> date | None:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value.date()
        if isinstance(value, date):
            return value
        try:
            s = str(value)
            return date.fromisoformat(s[:10])
        except Exception:
            return None

    # Allow a range of hours (e.g. "8,9") for morning windows.
    hours_raw = os.getenv("ADHERENCE_NUDGE_LOCAL_HOURS")
    allowed_hours: set[int]
    if hours_raw:
        allowed_hours = set()
        for part in hours_raw.split(','):
            part = part.strip()
            if not part:
                continue
            try:
                allowed_hours.add(int(part))
            except Exception:
                pass
        if not allowed_hours:
            allowed_hours = {8}
    else:
        try:
            target_hour = int(os.getenv("ADHERENCE_NUDGE_LOCAL_HOUR", "20"))
        except Exception:
            target_hour = 20
        allowed_hours = {target_hour}

    try:
        minute_window = int(os.getenv("ADHERENCE_NUDGE_MINUTE_WINDOW", "30"))
    except Exception:
        minute_window = 30
    if minute_window < 1:
        minute_window = 1
    if minute_window > 60:
        minute_window = 60

    try:
        threshold = float(os.getenv("ADHERENCE_NUDGE_THRESHOLD", "0.6"))
    except Exception:
        threshold = 0.6

    try:
        max_days_after = int(os.getenv("ADHERENCE_MAX_DAYS_AFTER_PROCEDURE", "60"))
    except Exception:
        max_days_after = 60

    default_tz = os.getenv("ADHERENCE_DEFAULT_TZ", "Asia/Kolkata")

    ok_enabled_raw = os.getenv("ADHERENCE_ALRIGHT_ENABLED")
    if ok_enabled_raw is None:
        ok_enabled_raw = os.getenv("ADHERENCE_OK_ENABLED", "0")
    ok_enabled = str(ok_enabled_raw).lower() in {"1", "true", "yes", "on"}

    async def _get_patient_timezone(patient_id: int) -> str:
        try:
            tz_res = await db.execute(
                select(models.Reminder.timezone)
                .where(models.Reminder.patient_id == patient_id)
                .order_by(models.Reminder.updated_at.desc())
                .limit(1)
            )
            tz_name = tz_res.scalar_one_or_none()
            if tz_name:
                return str(tz_name)
        except Exception:
            pass
        return default_tz

    max_patients = int(max_patients)
    sample = int(sample)
    if max_patients < 1:
        max_patients = 1
    if max_patients > 5000:
        max_patients = 5000
    if sample < 0:
        sample = 0
    if sample > max_patients:
        sample = max_patients

    evaluated = 0
    would_send_attention = 0
    would_send_ok = 0
    skipped = 0
    reason_counts: dict[str, int] = {}
    samples: list[dict[str, Any]] = []

    pat_res = await db.execute(
        select(models.Patient)
        .join(models.DeviceToken, models.DeviceToken.patient_id == models.Patient.id)
        .where(models.DeviceToken.active == True)
        .where(or_(models.Patient.procedure_completed == False, models.Patient.procedure_completed.is_(None)))
        .distinct()
        .limit(max_patients)
    )
    patients = pat_res.scalars().all()

    for p in patients:
        evaluated += 1
        pid = int(object.__getattribute__(p, "id"))
        proc_date = _normalize_procedure_date(getattr(p, "procedure_date"))

        reason: str | None = None
        tz_name = await _get_patient_timezone(pid)
        tz_fallback = False
        try:
            tz = pytz.timezone(tz_name)
        except Exception:
            tz = pytz.UTC
            tz_name = "UTC"
            tz_fallback = True

        now_local = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
        local_day = now_local.date()

        if not proc_date:
            reason = "no_procedure_date"
        elif now_local.hour not in allowed_hours:
            reason = "outside_allowed_hour"
        elif now_local.minute >= minute_window:
            reason = "outside_minute_window"
        else:
            day_delta = (local_day - proc_date).days
            if day_delta < 0 or (max_days_after >= 0 and day_delta > max_days_after):
                reason = "procedure_day_out_of_range"
            else:
                # Adherence for today (local day)
                sres = await db.execute(
                    select(models.InstructionStatus.followed)
                    .where(models.InstructionStatus.patient_id == pid)
                    .where(models.InstructionStatus.date == local_day)
                )
                flags = [bool(row[0]) for row in sres.all()]
                total = len(flags)
                followed = sum(1 for f in flags if f)
                ratio_val: float | None = None
                if total > 0:
                    ratio_val = followed / float(total)

                needs_attention = (total == 0) or (ratio_val is not None and ratio_val < threshold)

                # Would we send at all?
                if (not needs_attention) and (not ok_enabled):
                    reason = "ok_disabled"
                else:
                    # Would it be suppressed as already sent today?
                    prev = await db.execute(
                        select(models.AdherenceNudge.id)
                        .where(models.AdherenceNudge.patient_id == pid)
                        .where(models.AdherenceNudge.local_date == local_day)
                        .limit(1)
                    )
                    already = prev.scalar_one_or_none() is not None
                    if already:
                        reason = "already_nudged_today"
                    else:
                        if needs_attention:
                            would_send_attention += 1
                        else:
                            would_send_ok += 1

                # Emit sample row when useful
                if len(samples) < sample:
                    samples.append(
                        {
                            "patient_id": pid,
                            "timezone": tz_name,
                            "tz_fallback": tz_fallback,
                            "now_local": now_local.isoformat(),
                            "local_day": local_day.isoformat(),
                            "procedure_date": proc_date.isoformat() if proc_date else None,
                            "adherence_total": total,
                            "adherence_followed": followed,
                            "adherence_ratio": ratio_val,
                            "needs_attention": needs_attention,
                            "would_send": None if reason else ("attention" if needs_attention else "ok"),
                            "skip_reason": reason,
                        }
                    )

        if reason:
            skipped += 1
            reason_counts[reason] = reason_counts.get(reason, 0) + 1

    return {
        "enabled": enabled,
        "now_utc": now_utc.isoformat() + "Z",
        "config": {
            "allowed_hours": sorted(list(allowed_hours)),
            "minute_window": minute_window,
            "threshold": threshold,
            "max_days_after_procedure": max_days_after,
            "default_tz": default_tz,
            "ok_enabled": ok_enabled,
            "max_patients": max_patients,
            "sample": sample,
        },
        "counts": {
            "evaluated": evaluated,
            "would_send_attention": would_send_attention,
            "would_send_ok": would_send_ok,
            "skipped": skipped,
        },
        "skip_reasons": reason_counts,
        "samples": samples,
    }


def _require_task_token(request: Request) -> None:
    """Lightweight protection for cron/ops task endpoints.

    Set TASK_TOKEN in the environment and call endpoints with either:
      - Header: X-Task-Token: <token>
      - Query:  ?token=<token>
    """
    expected = os.getenv("TASK_TOKEN")
    if not expected:
        raise HTTPException(status_code=503, detail="TASK_TOKEN not configured")
    provided = request.headers.get("X-Task-Token") or request.query_params.get("token")
    if not provided or provided != expected:
        raise HTTPException(status_code=401, detail="Invalid task token")


@app.post("/tasks/dispatch/run")
@app.get("/tasks/dispatch/run")
@app.head("/tasks/dispatch/run")
async def task_run_dispatch(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Trigger scheduled push + reminder fallback dispatch immediately.

    This is the preferred server-only mechanism on hosts where the in-process
    APScheduler may be paused/slept. Configure an external cron to call this
    endpoint periodically.

    Protected by TASK_TOKEN.
    Query params:
      - dry_run=1
      - limit=50
      - debug=1
    """
    _require_task_token(request)

    def _truthy(v: Optional[str]) -> bool:
        return str(v).lower() in {"1", "true", "yes", "on"}

    def _as_int(v: Optional[str], default: int) -> int:
        try:
            return int(str(v))
        except Exception:
            return default

    dry_run = _truthy(request.query_params.get("dry_run"))
    debug = _truthy(request.query_params.get("debug"))
    limit = _as_int(request.query_params.get("limit"), default=50)
    return await _internal_dispatch_due(db, dry_run=dry_run, limit=limit, debug=debug)


@app.post("/tasks/adherence/run")
@app.get("/tasks/adherence/run")
@app.head("/tasks/adherence/run")
async def task_run_adherence(request: Request, db: AsyncSession = Depends(get_db)):
    """Trigger adherence nudges immediately.

    Useful for external cron/wake-ups on hosts that may sleep background schedulers.
    Protected by TASK_TOKEN.
    """
    _require_task_token(request)
    try:
        res = await _internal_send_adherence_nudges(db)
        # Keep a stable, monitor-friendly envelope
        if isinstance(res, dict) and "ok" not in res:
            return {"ok": True, **res}
        return res
    except Exception as exc:
        print(f"[tasks][adherence] fatal error: {exc}\n{traceback.format_exc()}")
        # Return 200 so UptimeRobot doesn't mark the service down; /healthz should cover uptime.
        return {"ok": False, "error": str(exc)}


@app.post("/tasks/adherence/test")
@app.get("/tasks/adherence/test")
async def task_test_adherence(
    request: Request,
    patient_id: int | None = None,
    kind: str = "adherence_nudge",
    title: str | None = None,
    body: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """Force-send an adherence/progress notification for testing.

    Protected by TASK_TOKEN.

    Query params:
      - patient_id: optional; if omitted, sends to the first patient with an active token
      - kind: 'adherence_nudge' or 'adherence_ok'
      - title/body: optional overrides
    """
    _require_task_token(request)

    kind_norm = (kind or "").strip()
    if kind_norm not in {"adherence_nudge", "adherence_ok"}:
        raise HTTPException(status_code=422, detail="kind must be adherence_nudge or adherence_ok")

    if title is None:
        if kind_norm == "adherence_ok":
            title = os.getenv("ADHERENCE_ALRIGHT_TITLE") or os.getenv("ADHERENCE_OK_TITLE", "All right")
        else:
            title = os.getenv("ADHERENCE_NUDGE_TITLE", "Instruction Reminder")
    if body is None:
        if kind_norm == "adherence_ok":
            body = os.getenv("ADHERENCE_ALRIGHT_BODY") or os.getenv(
                "ADHERENCE_OK_BODY",
                "You're doing well. Please continue following your doctor's instructions.",
            )
        else:
            body = os.getenv("ADHERENCE_NUDGE_BODY", "Please follow your instructions today.")

    target_pid: int | None = patient_id
    if target_pid is None:
        # Pick any patient with an active device token.
        pid_res = await db.execute(
            select(models.DeviceToken.patient_id)
            .where(models.DeviceToken.active == True)
            .order_by(models.DeviceToken.updated_at.desc())
            .limit(1)
        )
        target_pid = pid_res.scalar_one_or_none()

    if target_pid is None:
        return {"ok": False, "reason": "no_active_tokens", "sent": 0}

    tok_res = await db.execute(
        select(models.DeviceToken.token)
        .where(models.DeviceToken.patient_id == int(target_pid))
        .where(models.DeviceToken.active == True)
    )
    tokens = [row[0] for row in tok_res.all()]
    if not tokens:
        return {"ok": False, "reason": "no_tokens_for_patient", "patient_id": int(target_pid), "sent": 0}

    try:
        adh_ttl = int(os.getenv("ADHERENCE_FCM_TTL_SECONDS", "7200"))
    except Exception:
        adh_ttl = 7200
    if adh_ttl < 0:
        adh_ttl = 0

    data = {
        "type": kind_norm,
        "local_date": datetime.utcnow().date().isoformat(),
        "test": "1",
    }

    sent = 0
    details: list[dict[str, Any]] = []
    debug = str(request.query_params.get("debug", "")).lower() in {"1", "true", "yes", "on"}
    for t in tokens:
        res_obj = send_fcm_notification_ex(
            str(t),
            str(title),
            str(body),
            data=data,
            ttl_seconds=adh_ttl,
        )  # type: ignore
        if res_obj.get("ok"):
            sent += 1
        if debug:
            details.append({"token": str(t)[-12:], **res_obj})

    resp: dict[str, Any] = {"ok": True, "patient_id": int(target_pid), "kind": kind_norm, "sent": sent, "total": len(tokens)}
    if debug:
        resp["debug"] = details
    return resp


@app.get("/tasks/adherence/preview")
async def task_preview_adherence(
    request: Request,
    max_patients: int = 200,
    sample: int = 50,
    db: AsyncSession = Depends(get_db),
):
    """Dry-run preview of adherence nudges.

    Protected by TASK_TOKEN.
    Does not send notifications and does not write AdherenceNudge.
    """
    _require_task_token(request)
    return await _internal_preview_adherence_nudges(db, max_patients=max_patients, sample=sample)

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
    """Verify a password hash safely.

    Passlib can raise for malformed/legacy hashes; treat as non-match instead of
    crashing the request (which would surface as HTTP 500 on login).
    """
    try:
        if not plain_password or not hashed_password:
            return False
        return pwd_context.verify(plain_password, hashed_password)
    except Exception as exc:
        # Avoid leaking secrets; keep logs minimal for ops.
        print(f"[auth] verify_password failed: {type(exc).__name__}: {exc}")
        return False

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
        newest = open_episodes[0]

        # Safety: never allow a completed episode to remain editable.
        # If some older client/version marked procedure_completed=True but forgot to lock,
        # we auto-lock it and create a fresh open episode so new procedures don't overwrite
        # completed treatment details.
        if bool(getattr(newest, 'procedure_completed', False)) and not bool(getattr(newest, 'locked', False)):
            object.__setattr__(newest, 'locked', True)
            db.add(newest)
            await db.commit()

            new_ep = models.TreatmentEpisode(
                patient_id=patient_id,
                # Preserve assignment to keep doctor dashboards stable.
                department=getattr(newest, 'department', None),
                doctor=getattr(newest, 'doctor', None),
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

        return newest

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


async def _cleanup_unverified_patient_later(patient_id: int, retention_hours: int = UNVERIFIED_SIGNUP_RETENTION_HOURS) -> None:
    """Delete the patient row if it is still unverified after the retention window."""
    if retention_hours <= 0:
        return
    try:
        await asyncio.sleep(retention_hours * 3600)
        async with AsyncSessionLocal() as _session:
            patient = await _session.get(models.Patient, patient_id)
            if patient and not getattr(patient, "is_verified", False):
                await _session.delete(patient)
                await _session.commit()
                print(f"[signup-cleanup] Deleted unverified patient id={patient_id} after {retention_hours}h")
    except Exception as exc:
        print(f"[signup-cleanup] Cleanup failed for patient id={patient_id}: {exc}")


def _schedule_unverified_cleanup(patient_id: int) -> None:
    """Fire-and-forget task to remove unverified signups after the retention window."""
    asyncio.create_task(_cleanup_unverified_patient_later(patient_id))

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

    # Schedule automatic cleanup if the user never verifies their email/OTP.
    _schedule_unverified_cleanup(object.__getattribute__(db_patient, 'id'))

    ep = await _get_or_create_open_episode(db, object.__getattribute__(db_patient, 'id'))
    await _mirror_episode_to_patient(db, db_patient, ep)

    access_token = create_access_token(data={"sub": db_patient.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/login", response_model=schemas.TokenResponse)
async def login(
    username: str = Form(...),
    password: str = Form(...),
    device_id: Optional[str] = Form(None),
    device_name: Optional[str] = Form(None),
    force_takeover: Optional[bool] = Form(False),
    db: AsyncSession = Depends(get_db),
):
    normalized = (username or "").strip()
    result = await db.execute(select(models.Patient).where(models.Patient.username == normalized))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=401, detail="Incorrect username or password")

    # Extract frequently used scalar fields without triggering SQLAlchemy attribute
    # instrumentation / lazy loads. This prevents MissingGreenlet if attributes
    # get expired (e.g., after a commit in best-effort session tracking).
    try:
        patient_id = object.__getattribute__(user, "id")
    except Exception:
        patient_id = getattr(user, "id", None)
    try:
        token_subject = str(object.__getattribute__(user, "username"))
    except Exception:
        token_subject = str(getattr(user, "username", normalized))
    try:
        stored_hash_or_pw = object.__getattribute__(user, "password")
    except Exception:
        stored_hash_or_pw = getattr(user, "password", None)

    password_ok = verify_password(password, stored_hash_or_pw)

    # Legacy fallback: some older deployments may have stored plaintext passwords.
    # If the plaintext matches, upgrade to a proper hash and proceed.
    if not password_ok:
        try:
            stored = stored_hash_or_pw
            if isinstance(stored, str) and stored == password:
                try:
                    object.__setattr__(user, "password", get_password_hash(password))
                    db.add(user)
                    await db.commit()
                    password_ok = True
                    print(f"[auth] Upgraded plaintext password to hash for user={normalized}")
                except Exception as exc:
                    try:
                        await db.rollback()
                    except Exception:
                        pass
                    # Still allow login if the plaintext matched; the upgrade can retry later.
                    password_ok = True
                    print(f"[auth] Password upgrade commit failed for user={normalized}: {type(exc).__name__}: {exc}")
        except Exception:
            # Ignore legacy upgrade errors and fall through to 401 below.
            pass

    if not password_ok:
        raise HTTPException(status_code=401, detail="Incorrect username or password")

    # Single-device enforcement is best-effort; if session tracking fails we still allow login.
    did = (device_id or "").strip()
    if did and patient_id is not None:
        try:
            now = datetime.utcnow()
            try:
                window_min = int(os.getenv("SESSION_ACTIVE_WINDOW_MINUTES", "60"))
            except Exception:
                window_min = 60
            window_min = max(1, window_min)
            cutoff = now - timedelta(minutes=window_min)

            other_recent_q = await db.execute(
                select(models.UserSession)
                .where(models.UserSession.patient_id == patient_id)
                .where(models.UserSession.active == True)
                .where(models.UserSession.device_id != did)
                .where(models.UserSession.last_seen_at >= cutoff)
                .order_by(models.UserSession.last_seen_at.desc())
                .limit(1)
            )
            other_recent = other_recent_q.scalars().first()
            if other_recent:
                # By default, block to enforce single-device sessions.
                # If the client explicitly opts in, allow a "takeover" that deactivates
                # other active sessions and proceeds with login.
                if not force_takeover:
                    raise HTTPException(
                        status_code=409,
                        detail="Account is in use on another device. Please log out on that device first.",
                    )

            # Deactivate any other active sessions (stale), then upsert this device as active.
            stale_q = await db.execute(
                select(models.UserSession)
                .where(models.UserSession.patient_id == patient_id)
                .where(models.UserSession.active == True)
                .where(models.UserSession.device_id != did)
            )
            for s in stale_q.scalars().all():
                object.__setattr__(s, 'active', False)
                db.add(s)

            me_q = await db.execute(
                select(models.UserSession)
                .where(models.UserSession.patient_id == patient_id)
                .where(models.UserSession.device_id == did)
                .limit(1)
            )
            me = me_q.scalars().first()
            if me:
                object.__setattr__(me, 'last_seen_at', now)
                object.__setattr__(me, 'active', True)
                if device_name:
                    object.__setattr__(me, 'device_name', str(device_name)[:200])
                db.add(me)
            else:
                db.add(models.UserSession(
                    patient_id=patient_id,
                    device_id=did,
                    device_name=(str(device_name)[:200] if device_name else None),
                    created_at=now,
                    last_seen_at=now,
                    active=True,
                ))

            await db.commit()
        except HTTPException:
            raise
        except Exception:
            try:
                await db.rollback()
            except Exception:
                pass

    access_token = create_access_token(data={"sub": token_subject})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/session/logout")
async def logout_session(
    device_id: str = Form(...),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    did = (device_id or "").strip()
    if not did:
        raise HTTPException(status_code=422, detail="device_id required")
    now = datetime.utcnow()
    try:
        q = await db.execute(
            select(models.UserSession)
            .where(models.UserSession.patient_id == current_user.id)
            .where(models.UserSession.device_id == did)
            .limit(1)
        )
        sess = q.scalars().first()
        if sess:
            object.__setattr__(sess, 'active', False)
            object.__setattr__(sess, 'last_seen_at', now)
            db.add(sess)
            await db.commit()
        return {"ok": True}
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
        raise HTTPException(status_code=500, detail="Failed to logout session")


@app.post("/doctor-login", response_model=schemas.TokenResponse)
async def doctor_login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(models.Doctor).where(models.Doctor.username == form_data.username))
    doctor = result.scalars().first()
    if not doctor or not verify_password(form_data.password, doctor.password):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    access_token = create_access_token(data={"sub": doctor.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/doctor/master-login", response_model=schemas.TokenResponse)
async def doctor_master_login(payload: schemas.DoctorMasterLoginRequest, db: AsyncSession = Depends(get_db)):
    """Single shared password doctor login (prototype).
    Environment variables:
      DOCTOR_MASTER_PASSWORD (required) - plaintext master secret.
      DOCTOR_MASTER_USERNAME (optional, default 'masterdoctor') - subject placed in token.
    Behavior:
      - Verifies master password.
      - Ensures a Doctor row (username == master username) exists; if absent, creates a placeholder doctor record.
      - Issues JWT so auth-protected doctor endpoints function.
    SECURITY: Do NOT use in production; replace with real doctor accounts.
    """
    master_pw = os.getenv("DOCTOR_MASTER_PASSWORD")
    if not master_pw:
        raise HTTPException(status_code=503, detail="Master login disabled (password not configured)")
    if payload.password != master_pw:
        raise HTTPException(status_code=401, detail="Invalid master password")
    username = os.getenv("DOCTOR_MASTER_USERNAME", "masterdoctor")
    # Ensure doctor row exists
    res = await db.execute(select(models.Doctor).where(models.Doctor.username == username))
    doc = res.scalars().first()
    if not doc:
        # Create minimal doctor entry with hashed master password (so /doctor-login also works if needed)
        hashed = get_password_hash(master_pw)
        doc = models.Doctor(
            name="Master Doctor",
            specialty="General",
            username=username,
            password=hashed,
            email=f"{username}@example.com",
            is_verified=True,
        )
        db.add(doc)
        try:
            await db.commit()
        except Exception:
            await db.rollback()
    access_token = create_access_token(data={"sub": username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/doctor/register", response_model=schemas.TokenResponse)
async def doctor_register(request: Request, doctor: schemas.DoctorCreate = Body(...), db: AsyncSession = Depends(get_db)):
    """Create a doctor account (dev/ops only).
    Guarded by environment variable DOCTOR_SELF_REGISTER=1. Returns JWT on success.
    """
    if os.getenv("DOCTOR_SELF_REGISTER", "0") not in {"1","true","yes","on"}:
        raise HTTPException(status_code=403, detail="Doctor self-registration disabled")
    errors: dict[str,str] = {}
    existing_u = await db.execute(select(models.Doctor).where(models.Doctor.username == doctor.username))
    if existing_u.scalars().first():
        errors["username"] = "Username already exists"
    existing_e = await db.execute(select(models.Doctor).where(models.Doctor.email == doctor.email))
    if existing_e.scalars().first():
        errors["email"] = "Email already exists"
    if errors:
        raise HTTPException(status_code=400, detail=errors)
    hashed_pw = get_password_hash(doctor.password)
    db_doc = models.Doctor(
        name=doctor.name,
        specialty=doctor.specialty,
        username=doctor.username,
        password=hashed_pw,
        email=doctor.email,
        is_verified=True,
    )
    db.add(db_doc)
    await db.commit()
    await db.refresh(db_doc)
    access_token = create_access_token(data={"sub": db_doc.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/patients/me", response_model=schemas.PatientPublic)
async def get_my_profile(current_user: models.Patient = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await _rotate_if_due(db, current_user)
    return current_user


class ThemeModeUpdate(BaseModel):
    theme_mode: str


@app.patch("/patients/me/theme-mode", response_model=schemas.PatientPublic)
async def update_my_theme_mode(
    payload: ThemeModeUpdate,
    current_user: models.Patient = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    mode = (payload.theme_mode or "").strip().lower()
    if mode not in {"light", "dark"}:
        raise HTTPException(status_code=400, detail="theme_mode must be 'light' or 'dark'")
    current_user.theme_mode = mode
    await db.commit()
    await db.refresh(current_user)
    return current_user

# -------------------------------------------------
# Temporary public endpoint: list patients by doctor
# SECURITY NOTE: This endpoint is unauthenticated right now to support
# prototype doctor UI. It should be protected (require doctor auth)
# before production deployment.
# -------------------------------------------------
@app.get("/patients/by-doctor", response_model=List[schemas.PatientPublic])
async def list_patients_by_doctor(
    doctor: str,
    db: AsyncSession = Depends(get_db),
    current_doctor: models.Doctor = Depends(get_current_doctor),
):
    start = datetime.utcnow()
    print(f"[patients/by-doctor] inbound doctor='{doctor}' @ {start.isoformat()}Z")
    try:
        stmt = select(models.Patient).where(models.Patient.doctor == doctor)
        # Enforce DB execution timeout (5s) to surface stalls
        async def _run():
            res = await db.execute(stmt)
            return res.scalars().all()
        patients = await asyncio.wait_for(_run(), timeout=5.0)

        # Pull the latest episode per patient with a non-empty treatment.
        # This keeps the dashboard stable even after an episode completes and a new blank episode is opened.
        pt_ids = [object.__getattribute__(p, "id") for p in patients]
        latest_by_patient: dict[int, Any] = {}
        if pt_ids:
            ep = models.TreatmentEpisode
            ranked = (
                select(
                    ep.patient_id.label("patient_id"),
                    ep.department.label("department"),
                    ep.doctor.label("doctor"),
                    ep.treatment.label("treatment"),
                    ep.subtype.label("subtype"),
                    ep.procedure_date.label("procedure_date"),
                    ep.procedure_time.label("procedure_time"),
                    ep.procedure_completed.label("procedure_completed"),
                    ep.locked.label("locked"),
                    ep.id.label("episode_id"),
                    func.row_number().over(partition_by=ep.patient_id, order_by=ep.id.desc()).label("rn"),
                )
                .where(ep.patient_id.in_(pt_ids))
                .where(ep.treatment.is_not(None))
                .where(ep.treatment != "")
                .subquery()
            )
            latest_stmt = select(ranked).where(ranked.c.rn == 1)
            latest_rows = (await db.execute(latest_stmt)).mappings().all()
            latest_by_patient = {int(r["patient_id"]): r for r in latest_rows}

        # Build response objects using patient identity fields + episode-derived treatment fields when available.
        out: list[dict[str, Any]] = []
        for p in patients:
            pid = object.__getattribute__(p, "id")
            ep_row = latest_by_patient.get(int(pid))
            out.append(
                {
                    "id": pid,
                    "name": getattr(p, "name", None),
                    "dob": getattr(p, "dob", None),
                    "gender": getattr(p, "gender", None),
                    "phone": getattr(p, "phone", None),
                    "email": getattr(p, "email", None),
                    "username": getattr(p, "username", None),
                    "department": (ep_row.get("department") if ep_row else None) or getattr(p, "department", None),
                    "doctor": (ep_row.get("doctor") if ep_row else None) or getattr(p, "doctor", None),
                    "treatment": (ep_row.get("treatment") if ep_row else None) or getattr(p, "treatment", None),
                    "treatment_subtype": (ep_row.get("subtype") if ep_row else None) or getattr(p, "treatment_subtype", None),
                    "procedure_date": (ep_row.get("procedure_date") if ep_row else None) or getattr(p, "procedure_date", None),
                    "procedure_time": (ep_row.get("procedure_time") if ep_row else None) or getattr(p, "procedure_time", None),
                    "procedure_completed": (ep_row.get("procedure_completed") if ep_row else None) if ep_row else getattr(p, "procedure_completed", None),
                    "ever_completed": getattr(p, "ever_completed", None),
                    "last_completed_episode_id": getattr(p, "last_completed_episode_id", None),
                    "last_completed_at": getattr(p, "last_completed_at", None),
                    "theme_mode": getattr(p, "theme_mode", None),
                }
            )
        elapsed = (datetime.utcnow() - start).total_seconds()*1000
        print(f"[patients/by-doctor] doctor='{doctor}' count={len(out)} elapsed_ms={elapsed:.1f}")
        return out
    except asyncio.TimeoutError:
        elapsed = (datetime.utcnow() - start).total_seconds()*1000
        print(f"[patients/by-doctor][timeout] doctor='{doctor}' after {elapsed:.1f}ms")
        raise HTTPException(status_code=504, detail="DB timeout fetching patients")
    except Exception as e:
        print(f"[patients/by-doctor][error] doctor='{doctor}' error={e}")
        raise


@app.get("/patients/by-doctor-episodes", response_model=List[schemas.PatientEpisodePublic])
async def list_patient_episodes_by_doctor(
    doctor: str,
    db: AsyncSession = Depends(get_db),
    current_doctor: models.Doctor = Depends(get_current_doctor),
):
    """Doctor dashboard feed that includes completed treatments as separate entries.

    Returns one row per treatment episode that belongs to the doctor.
    Filters out episodes that don't have a treatment set yet.
    """
    start = datetime.utcnow()
    print(f"[patients/by-doctor-episodes] inbound doctor='{doctor}' @ {start.isoformat()}Z")
    try:
        ep = models.TreatmentEpisode
        pt = models.Patient
        stmt = (
            select(ep, pt)
            .join(pt, ep.patient_id == pt.id)
            .where(ep.doctor == doctor)
            .where(ep.treatment.is_not(None))
            .where(ep.treatment != "")
            .order_by(pt.name.asc(), ep.procedure_date.desc().nullslast(), ep.created_at.desc())
        )

        async def _run():
            res = await db.execute(stmt)
            return res.all()

        rows = await asyncio.wait_for(_run(), timeout=5.0)
        out: List[schemas.PatientEpisodePublic] = []
        for ep_row, pt_row in rows:
            out.append(
                schemas.PatientEpisodePublic(
                    patient_id=object.__getattribute__(pt_row, "id"),
                    episode_id=object.__getattribute__(ep_row, "id"),
                    username=object.__getattribute__(pt_row, "username"),
                    name=object.__getattribute__(pt_row, "name"),
                    department=getattr(ep_row, "department", None) or getattr(pt_row, "department", None),
                    doctor=getattr(ep_row, "doctor", None) or getattr(pt_row, "doctor", None),
                    treatment=getattr(ep_row, "treatment", None),
                    treatment_subtype=getattr(ep_row, "subtype", None),
                    procedure_date=getattr(ep_row, "procedure_date", None),
                    procedure_time=getattr(ep_row, "procedure_time", None),
                    procedure_completed=getattr(ep_row, "procedure_completed", None),
                    locked=getattr(ep_row, "locked", None),
                )
            )

        elapsed = (datetime.utcnow() - start).total_seconds() * 1000
        print(f"[patients/by-doctor-episodes] doctor='{doctor}' count={len(out)} elapsed_ms={elapsed:.1f}")
        return out
    except asyncio.TimeoutError:
        elapsed = (datetime.utcnow() - start).total_seconds() * 1000
        print(f"[patients/by-doctor-episodes][timeout] doctor='{doctor}' after {elapsed:.1f}ms")
        raise HTTPException(status_code=504, detail="DB timeout fetching patient episodes")
    except Exception as e:
        print(f"[patients/by-doctor-episodes][error] doctor='{doctor}' error={e}")
        raise

@app.get("/patients/by-doctor-debug")
async def list_patients_by_doctor_debug(doctor: str, db: AsyncSession = Depends(get_db)):
    """Debug variant: returns minimal patient identifiers and uses case-insensitive & prefix-less matching.

    Matching logic:
      - Exact doctor
      - Case-insensitive
      - Strips a leading 'Dr. ' from either side for comparison
    """
    start = datetime.utcnow()
    print(f"[patients/by-doctor-debug] inbound doctor='{doctor}'")
    cleaned = doctor.strip()
    lowered = cleaned.lower()
    def _strip_prefix(s: str) -> str:
        s = s.strip()
        if s.lower().startswith("dr. "):
            return s[4:].strip()
        if s.lower().startswith("dr "):
            return s[3:].strip()
        return s
    target = _strip_prefix(lowered)
    # Build OR conditions
    cond = func.lower(models.Patient.doctor) == lowered
    cond = cond | (func.lower(models.Patient.doctor) == target)
    cond = cond | func.lower(models.Patient.doctor).ilike(f"%{target}%")
    try:
        res = await db.execute(select(models.Patient.username, models.Patient.doctor).where(cond))
        rows = res.all()
        elapsed = (datetime.utcnow() - start).total_seconds()*1000
        print(f"[patients/by-doctor-debug] matched={len(rows)} elapsed_ms={elapsed:.1f}")
        return [{"username": r[0], "doctor": r[1]} for r in rows]
    except Exception as e:
        print(f"[patients/by-doctor-debug][error] {e}")
        raise HTTPException(status_code=500, detail="debug query failed")

# ------------------------------------------------------------------
# Instruction progress (last N days) for a patient (TEMP: no auth)
# SECURITY: Should be protected by doctor auth & assignment validation.
# ------------------------------------------------------------------
@app.get("/doctor/patients/{username}/instruction-progress")
async def patient_instruction_progress(username: str, days: int = 14, db: AsyncSession = Depends(get_db)):
    """Aggregate instruction adherence over the last N days.

    Uses the enhanced materialization logic so "missing" instructions are counted as
    unfollowed when we can infer the expected instruction set (union-of-observed in the window).
    """
    days = max(1, min(days, 60))  # clamp range

    enhanced = await doctor_instruction_status_enhanced(
        username=username,
        days=days,
        date_from=None,
        date_to=None,
        filter_treatment=None,
        filter_subtype=None,
        include_unfollowed_placeholders=True,
        db=db,
    )

    patient_public = enhanced.get("patient") or {}
    days_out = enhanced.get("days") or []

    total_followed = 0
    total_unfollowed = 0
    daily = []
    for d in days_out:
        # d['date'] is a date object (from Pydantic model); coerce safely
        dt = d.get("date")
        ds = dt.isoformat() if hasattr(dt, "isoformat") else str(dt or "")
        followed = int(d.get("followed_count") or 0)
        unfollowed = int(d.get("unfollowed_count") or 0)
        total = int(d.get("total") or (followed + unfollowed))
        ratio = float(d.get("followed_ratio") or (followed / total if total else 0.0))
        total_followed += followed
        total_unfollowed += unfollowed
        daily.append(
            {
                "date": ds,
                "followed": followed,
                "unfollowed": unfollowed,
                "total": total,
                "followed_ratio": round(ratio, 3),
            }
        )

    total_all = total_followed + total_unfollowed
    return {
        "patient": {
            "username": patient_public.get("username"),
            "department": patient_public.get("department"),
            "doctor": patient_public.get("doctor"),
            "treatment": patient_public.get("treatment"),
            "subtype": patient_public.get("treatment_subtype"),
            # keep old key too for compatibility with other clients
            "treatment_subtype": patient_public.get("treatment_subtype"),
        },
        "summary": {
            "days": len(daily),
            "followed": total_followed,
            "unfollowed": total_unfollowed,
            "total": total_all,
            "followed_ratio": round((total_followed / total_all) if total_all else 0.0, 3),
        },
        "daily": daily,
    }

# ------------------------------------------------------------------
# Doctor read-only instruction status list for a patient (TEMP: no auth)
# SECURITY: Protect with doctor auth & assignment validation before production.
# Mirrors /instruction-status but requires specifying patient username.
# ------------------------------------------------------------------
@app.get("/doctor/patients/{username}/instruction-status", response_model=List[schemas.InstructionStatusResponse])
async def doctor_list_instruction_status(
    username: str,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    filter_treatment: Optional[str] = None,
    filter_subtype: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Return raw instruction-status rows for the patient.
    Optional filters:
      - date_from / date_to (inclusive)
      - filter_treatment / filter_subtype to scope to current episode treatment
    """
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    q = select(models.InstructionStatus).where(models.InstructionStatus.patient_id == patient.id)
    if date_from:
        q = q.where(models.InstructionStatus.date >= date_from)
    if date_to:
        q = q.where(models.InstructionStatus.date <= date_to)
    if filter_treatment:
        q = q.where(models.InstructionStatus.treatment == filter_treatment)
    if filter_subtype:
        q = q.where(models.InstructionStatus.subtype == filter_subtype)
    result = await db.execute(
        q.order_by(
            models.InstructionStatus.date.desc(),
            models.InstructionStatus.group.asc(),
            models.InstructionStatus.instruction_index.asc(),
        )
    )
    return result.scalars().all()

@app.get("/doctor/patients/{username}/instruction-status/full", response_model=schemas.InstructionStatusFullResponse)
async def doctor_instruction_status_full(
    username: str,
    days: int = 14,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    filter_treatment: Optional[str] = None,
    filter_subtype: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Combined instruction status raw rows + aggregated daily summary for last N days.

    NOTE: Does not yet synthesize missing (unsubmitted) instructions; only returns actual rows.
    Use filter_treatment / filter_subtype to narrow scope.
    """
    from datetime import date as _date, timedelta as _td
    days = max(1, min(days, 60))
    # Patient lookup
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # Default window: last N days up to today (legacy behavior).
    # If date_from/date_to are provided, they override days.
    if date_from is None and date_to is None:
        date_to = _date.today()
        date_from = date_to - _td(days=days - 1)
    else:
        if date_from is None or date_to is None:
            raise HTTPException(status_code=400, detail="Both date_from and date_to must be provided")
        if date_from > date_to:
            raise HTTPException(status_code=400, detail="date_from must be <= date_to")
        # Explicit doctor queries are capped to the 14-day recovery window.
        if (date_to - date_from).days + 1 > 14:
            date_to = date_from + _td(days=13)
        days = (date_to - date_from).days + 1
        days = max(1, min(days, 14))
    q = select(models.InstructionStatus).where(
        models.InstructionStatus.patient_id == patient.id,
        models.InstructionStatus.date >= date_from,
        models.InstructionStatus.date <= date_to,
    )
    if filter_treatment:
        q = q.where(models.InstructionStatus.treatment == filter_treatment)
    if filter_subtype:
        q = q.where(models.InstructionStatus.subtype == filter_subtype)
    q = q.order_by(models.InstructionStatus.date.desc(), models.InstructionStatus.group.asc(), models.InstructionStatus.instruction_index.asc())
    rows = (await db.execute(q)).scalars().all()
    # Aggregate daily
    by_date: dict[str, dict[str,int]] = {}
    for r in rows:
        ds = r.date.isoformat()
        if ds not in by_date:
            by_date[ds] = {"followed":0, "unfollowed":0}
        if getattr(r, "followed", False):
            by_date[ds]["followed"] += 1
        else:
            by_date[ds]["unfollowed"] += 1
    daily_summary = []
    for i in range(days):
        d = date_from + _td(days=i)
        ds = d.isoformat()
        rec = by_date.get(ds, {"followed":0, "unfollowed":0})
        total = rec["followed"] + rec["unfollowed"]
        ratio = (rec["followed"] / total) if total else 0.0
        daily_summary.append({
            "date": ds,
            "followed": rec["followed"],
            "unfollowed": rec["unfollowed"],
            "total": total,
            "followed_ratio": round(ratio,3)
        })
    patient_public = {
        "id": patient.id,
        "name": patient.name,
        "dob": patient.dob,
        "gender": patient.gender,
        "phone": patient.phone,
        "email": patient.email,
        "username": patient.username,
        "department": patient.department,
        "doctor": patient.doctor,
        "treatment": patient.treatment,
        "treatment_subtype": patient.treatment_subtype,
        "procedure_date": patient.procedure_date,
        "procedure_time": patient.procedure_time,
        "procedure_completed": patient.procedure_completed,
    }
    return {
        "patient": patient_public,
        "range": {"from": date_from.isoformat(), "to": date_to.isoformat(), "days": days},
        "instructions": [
            {
                "id": r.id,
                "patient_id": r.patient_id,
                "date": r.date,
                "treatment": r.treatment,
                "subtype": r.subtype,
                "group": r.group,
                "instruction_index": r.instruction_index,
                "instruction_text": r.instruction_text,
                "followed": r.followed,
                "synthetic": False,
            } for r in rows
        ],
        "daily_summary": daily_summary,
    }


@app.get("/doctor/patients/{username}/episodes", response_model=List[schemas.EpisodeResponse])
async def doctor_get_patient_episodes(
    username: str,
    db: AsyncSession = Depends(get_db),
    current_doctor: models.Doctor = Depends(get_current_doctor),
):
    """Return treatment episode history for a patient (doctor view).

    Episodes are persisted as rows in treatment_episodes. Completed treatments are represented
    as locked=true episodes.
    """
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    stmt = (
        select(models.TreatmentEpisode)
        .where(models.TreatmentEpisode.patient_id == patient.id)
        .order_by(models.TreatmentEpisode.id.desc())
    )
    ep_res = await db.execute(stmt)
    episodes = ep_res.scalars().all()
    return [schemas.EpisodeResponse.model_validate(e, from_attributes=True) for e in episodes]

@app.get("/doctor/patients/{username}/instruction-status/enhanced", response_model=schemas.InstructionStatusEnhancedResponse)
async def doctor_instruction_status_enhanced(
    username: str,
    days: int = 14,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    filter_treatment: Optional[str] = None,
    filter_subtype: Optional[str] = None,
    include_unfollowed_placeholders: bool = True,
    db: AsyncSession = Depends(get_db)
):
    """Return fully materialized per-day instruction logs for last N days.

        If include_unfollowed_placeholders is true, we attempt to ensure that missing instruction rows
        are materialized as placeholders (followed=False, synthetic=True) so doctors can see a consistent
        timeline.

        Materialization order:
            1) Use a built-in instruction catalog for the patient's treatment/subtype when available.
            2) Fallback to a union-of-observed heuristic inside the requested window.
    """
    from datetime import date as _date, timedelta as _td, datetime as _dt
    days = max(1, min(days, 60))
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # Default window: last N days up to today.
    # If date_from/date_to are provided, they override days.
    if date_from is None and date_to is None:
        date_to = _date.today()
        date_from = date_to - _td(days=days - 1)
    else:
        if date_from is None or date_to is None:
            raise HTTPException(status_code=400, detail="Both date_from and date_to must be provided")
        if date_from > date_to:
            raise HTTPException(status_code=400, detail="date_from must be <= date_to")
        # Cap to 14-day recovery window.
        if (date_to - date_from).days + 1 > 14:
            date_to = date_from + _td(days=13)
        days = (date_to - date_from).days + 1
        days = max(1, min(days, 14))
    q = select(models.InstructionStatus).where(
        models.InstructionStatus.patient_id == patient.id,
        models.InstructionStatus.date >= date_from,
        models.InstructionStatus.date <= date_to,
    )
    if filter_treatment:
        q = q.where(models.InstructionStatus.treatment == filter_treatment)
    if filter_subtype:
        q = q.where(models.InstructionStatus.subtype == filter_subtype)
    q = q.order_by(models.InstructionStatus.date.asc(), models.InstructionStatus.group.asc(), models.InstructionStatus.instruction_index.asc())
    rows = (await db.execute(q)).scalars().all()

    def _canon_group(g: Optional[str]) -> str:
        return (g or "").strip().lower()

    def _canon_text(t: Optional[str]) -> str:
        return instruction_catalog.canonical_instruction_text(t)

    def _stable_idx(grp: str, text: str, fallback: int) -> int:
        # Some historical rows may have used unstable indices; normalize to stable identity.
        # If we can't compute from text, fall back to stored index.
        try:
            if grp and text:
                return int(instruction_catalog.stable_instruction_index(grp, text))
        except Exception:
            pass
        return int(fallback)

    # Build base structures
    # Observed instruction identities across window (keyed by (group, stable_instruction_index))
    observed_keys: dict[tuple, dict] = {}
    rows_by_date: dict[str, list[dict]] = {}
    for r in rows:
        ds = r.date.isoformat()
        grp = _canon_group(getattr(r, "group", None))
        text = _canon_text(getattr(r, "instruction_text", None))
        idx = _stable_idx(grp, text, getattr(r, "instruction_index", 0) or 0)
        rows_by_date.setdefault(ds, []).append({
            "row": r,
            "group": grp,
            "instruction_index": idx,
            "instruction_text": text,
        })

        key = (grp, idx)
        # Keep first seen meta; instruction_text may vary historically.
        if key not in observed_keys:
            observed_keys[key] = {
                "group": grp,
                "instruction_index": idx,
                "instruction_text": text,
                "treatment": r.treatment,
                "subtype": r.subtype,
            }

    # Prefer a real catalog for the effective treatment/subtype when possible.
    effective_treatment = filter_treatment or patient.treatment
    effective_subtype = filter_subtype or patient.treatment_subtype
    catalog_keys = instruction_catalog.expected_instruction_identities(
        treatment=effective_treatment,
        subtype=effective_subtype,
    )
    baseline_keys = catalog_keys or observed_keys

    days_out = []
    # Iterate each day and materialize
    for i in range(days):
        d = date_from + _td(days=i)
        ds = d.isoformat()
        real_rows = rows_by_date.get(ds, [])
        # De-dupe any accidental duplicates for the same identity; prefer newest updated_at, else highest id.
        real_map: dict[tuple, dict] = {}
        for item in real_rows:
            key = (item["group"], item["instruction_index"])
            existing = real_map.get(key)
            if existing is None:
                real_map[key] = item
                continue
            r_new = item["row"]
            r_old = existing["row"]
            ua_new = getattr(r_new, "updated_at", None)
            ua_old = getattr(r_old, "updated_at", None)
            if ua_new is not None and ua_old is not None:
                if ua_new > ua_old:
                    real_map[key] = item
            else:
                if getattr(r_new, "id", 0) > getattr(r_old, "id", 0):
                    real_map[key] = item
        materialized = []
        followed_ct = 0
        unfollowed_ct = 0
        if include_unfollowed_placeholders and baseline_keys:
            # Use catalog when available; else fallback to union-of-observed.
            for key, meta in baseline_keys.items():
                item = real_map.get(key)
                if item is None:
                    # Placeholder synthetic entry (did not appear this day)
                    materialized.append({
                        "id": 0,
                        "patient_id": patient.id,
                        "date": d,
                        "treatment": meta["treatment"],
                        "subtype": meta["subtype"],
                        "group": meta["group"],
                        "instruction_index": meta["instruction_index"],
                        "instruction_text": meta["instruction_text"],
                        "followed": False,
                        "synthetic": True,
                    })
                    unfollowed_ct += 1
                else:
                    r = item["row"]
                    materialized.append({
                        "id": r.id,
                        "patient_id": r.patient_id,
                        "date": r.date,
                        "treatment": r.treatment,
                        "subtype": r.subtype,
                        "group": item["group"],
                        "instruction_index": item["instruction_index"],
                        "instruction_text": item["instruction_text"],
                        "followed": r.followed,
                        "synthetic": False,
                    })
                    if r.followed:
                        followed_ct += 1
                    else:
                        unfollowed_ct += 1
        else:
            for item in real_rows:
                r = item["row"]
                materialized.append({
                    "id": r.id,
                    "patient_id": r.patient_id,
                    "date": r.date,
                    "treatment": r.treatment,
                    "subtype": r.subtype,
                    "group": item["group"],
                    "instruction_index": item["instruction_index"],
                    "instruction_text": item["instruction_text"],
                    "followed": r.followed,
                    "synthetic": False,
                })
                if r.followed:
                    followed_ct += 1
                else:
                    unfollowed_ct += 1

        total = followed_ct + unfollowed_ct
        ratio = (followed_ct / total) if total else 0.0
        days_out.append({
            "date": d,
            "instructions": materialized,
            "followed_count": followed_ct,
            "unfollowed_count": unfollowed_ct,
            "total": total,
            "followed_ratio": round(ratio,3),
        })

    patient_public = {
        "id": patient.id,
        "name": patient.name,
        "dob": patient.dob,
        "gender": patient.gender,
        "phone": patient.phone,
        "email": patient.email,
        "username": patient.username,
        "department": patient.department,
        "doctor": patient.doctor,
        "treatment": patient.treatment,
        "treatment_subtype": patient.treatment_subtype,
        "procedure_date": patient.procedure_date,
        "procedure_time": patient.procedure_time,
        "procedure_completed": patient.procedure_completed,
    }
    return {
        "patient": patient_public,
        "range": {"from": date_from.isoformat(), "to": date_to.isoformat(), "days": days},
        "days": days_out,
        "generated_at": _dt.utcnow(),
    }

# ------------------------------------------------------------------
# Doctor read-only progress entries for a patient (TEMP: no auth)
# SECURITY: Protect with doctor auth & assignment validation before production.
# Mirrors /progress GET but for specified patient.
# ------------------------------------------------------------------
@app.get("/doctor/patients/{username}/progress", response_model=List[schemas.ProgressEntry])
async def doctor_get_patient_progress(username: str, db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    result = await db.execute(
        select(models.Progress)
        .where(models.Progress.patient_id == patient.id)
        .order_by(models.Progress.timestamp.desc())
    )
    return result.scalars().all()

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


# --------------------------
# Chat: patient side
# --------------------------
@app.get("/chat/thread", response_model=List[schemas.ChatMessage])
async def get_chat_thread(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(
        select(models.ChatMessage)
        .where(models.ChatMessage.patient_id == current_user.id)
        .order_by(models.ChatMessage.created_at.asc())
    )
    return res.scalars().all()


@app.post("/chat/thread", response_model=schemas.ChatMessage)
async def send_chat_message(payload: schemas.ChatMessageCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    msg = models.ChatMessage(
        patient_id=current_user.id,
        sender_role="patient",
        sender_username=current_user.username,
        message=payload.message,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg

@app.post("/instruction-status", response_model=List[schemas.InstructionStatusResponse])
async def save_instruction_status(payload: schemas.InstructionStatusBulkCreate, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    """Idempotent upsert for instruction status rows.

    Reliability changes:
      * Removes destructive per-(date,group) delete cycles (previous churn source).
      * Uses PostgreSQL ON CONFLICT to update existing rows in-place.
      * Unique index (patient_id, date, group, instruction_index) enforced at startup.

    Returns the freshly persisted rows corresponding to submitted items.
    """
    await _rotate_if_due(db, current_user)

    # Lightweight in-memory rate limiting (per patient) to suppress accidental rapid bursts
    # Environment variables (optional):
    #   INSTR_STATUS_RATE_WINDOW_SECONDS (default 5)
    #   INSTR_STATUS_RATE_MAX_REQUESTS (default 12)
    # This is a best-effort, in-process limiter. For multi-worker deployments replace with Redis.
    try:
        import os, time
        window_s = int(os.getenv("INSTR_STATUS_RATE_WINDOW_SECONDS", "5"))
        max_req = int(os.getenv("INSTR_STATUS_RATE_MAX_REQUESTS", "12"))
        if window_s > 0 and max_req > 0:
            now = time.time()
            bucket = _instruction_rate_limiter.setdefault(current_user.id, [])  # type: ignore  # defined below
            # Drop timestamps outside window
            cutoff = now - window_s
            i = 0
            while i < len(bucket):
                if bucket[i] < cutoff:
                    i += 1
                else:
                    break
            if i > 0:
                del bucket[:i]
            if len(bucket) >= max_req:
                # Too many in window -> 429
                from fastapi import Response
                retry_after = max(1, int(cutoff + window_s - now))
                raise HTTPException(status_code=429, detail="Too many instruction-status submissions; please retry shortly.")
            bucket.append(now)
    except HTTPException:
        raise
    except Exception:
        # Fail open on limiter errors
        pass
    if not payload.items:
        return []

    # Normalize & collapse duplicates inside the same payload (last wins)
    collapsed: dict[tuple, schemas.InstructionStatusItem] = {}
    for item in payload.items:
        key = (item.date, item.group, item.instruction_index)
        collapsed[key] = item  # overwrite if repeated

    # Upsert with sticky ever_followed logic: once true, always true.
    upsert_sql = text(
        """
        INSERT INTO instruction_status (patient_id, date, treatment, subtype, "group", instruction_index, instruction_text, followed, ever_followed, updated_at)
        VALUES (:patient_id, :date, :treatment, :subtype, :group, :instruction_index, :instruction_text, :followed, :ever_followed, NOW())
        ON CONFLICT (patient_id, date, "group", instruction_index)
        DO UPDATE SET
          treatment = EXCLUDED.treatment,
          subtype = EXCLUDED.subtype,
          instruction_text = EXCLUDED.instruction_text,
          followed = EXCLUDED.followed,
          ever_followed = (instruction_status.ever_followed OR EXCLUDED.ever_followed),
          updated_at = NOW()
        RETURNING id, patient_id, date, treatment, subtype, "group", instruction_index, instruction_text, followed, ever_followed, updated_at;
        """
    )

    returned_rows = []
    for (_d, _g, _idx), item in collapsed.items():
        params = {
            "patient_id": current_user.id,
            "date": item.date,
            "treatment": item.treatment or "",
            "subtype": item.subtype,
            "group": item.group,
            "instruction_index": item.instruction_index,
            "instruction_text": item.instruction_text,
            "followed": item.followed,
            "ever_followed": (item.followed is True),
        }
        res = await db.execute(upsert_sql, params)
        row = res.first()
        if row:
            returned_rows.append(row)
    await db.commit()

    # Shape rows into response models
    out = []
    for r in returned_rows:
        out.append({
            "id": r.id,
            "patient_id": r.patient_id,
            "date": r.date,
            "treatment": r.treatment,
            "subtype": r.subtype,
            "group": r.group,
            "instruction_index": r.instruction_index,
            "instruction_text": r.instruction_text,
            "followed": r.followed,
            "ever_followed": getattr(r, 'ever_followed', None),
            "updated_at": getattr(r, 'updated_at', None),
        })
    return out

@app.get("/doctor/patients/{username}/instruction-status-debug")
async def doctor_instruction_status_debug(username: str, db: AsyncSession = Depends(get_db)):
    """UNAUTHENTICATED DEBUG: Returns raw instruction-status rows for a patient (limit 200).
    NOTE: Remove / secure before production. Helps verify persistence problems.
    """
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    q = select(models.InstructionStatus).where(models.InstructionStatus.patient_id == patient.id).order_by(models.InstructionStatus.date.desc()).limit(200)
    rows = (await db.execute(q)).scalars().all()
    return [
        {
            "id": r.id,
            "date": r.date.isoformat(),
            "group": r.group,
            "idx": r.instruction_index,
            "text": r.instruction_text,
            "followed": r.followed,
            "treatment": r.treatment,
            "subtype": r.subtype,
        }
        for r in rows
    ]

@app.get("/doctor/patients/{username}/info")
async def doctor_patient_info(username: str, db: AsyncSession = Depends(get_db), current_doctor: models.Doctor = Depends(get_current_doctor)):
    """Return high-level patient metadata for doctor dashboard.
    Includes: username, name, department, doctor, treatment, subtype, procedure_date, procedure_completed.
    Authorization: doctor must be authenticated; we do not (yet) restrict doctor-patient assignment; add check later if needed.
    """
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    return {
        "username": patient.username,
        "name": patient.name,
        "department": patient.department,
        "doctor": patient.doctor,
        "treatment": patient.treatment,
        "subtype": patient.treatment_subtype,
    "procedure_date": patient.procedure_date.isoformat() if getattr(patient, 'procedure_date', None) is not None else None,
        "procedure_completed": patient.procedure_completed,
    }


@app.get("/completed-patients", response_model=List[schemas.CompletedPatientRow])
async def list_completed_patients(
    username: Optional[str] = None,
    email: Optional[str] = None,
    phone: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    current_doctor: models.Doctor = Depends(get_current_doctor),
):
    """Read-only list of completed procedures.

    This reads from the DB view `completed_patients` (one row per completed+locked episode).
    Duplicates by phone/email are expected because this is historical.
    """
    limit = max(1, min(int(limit or 200), 500))
    offset = max(0, int(offset or 0))

    base_sql = """
        SELECT
          episode_id,
          patient_id,
          username,
          name,
          phone,
          email,
          department,
          doctor,
          treatment,
          treatment_subtype,
          procedure_date,
          procedure_time,
          episode_created_at,
          patient_last_completed_at
        FROM completed_patients
    """
    clauses: list[str] = []
    params: dict[str, Any] = {"limit": limit, "offset": offset}
    if username:
        clauses.append("username = :username")
        params["username"] = username
    if email:
        clauses.append("email = :email")
        params["email"] = email
    if phone:
        clauses.append("phone = :phone")
        params["phone"] = phone

    where_sql = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    order_sql = " ORDER BY episode_id DESC"
    page_sql = " LIMIT :limit OFFSET :offset"
    stmt = text(base_sql + where_sql + order_sql + page_sql)
    res = await db.execute(stmt, params)
    rows = res.mappings().all()
    return [schemas.CompletedPatientRow(**dict(r)) for r in rows]


@app.get("/doctor/patients/{username}/chat", response_model=List[schemas.ChatMessage])
async def doctor_get_chat_thread(username: str, db: AsyncSession = Depends(get_db), current_doctor: models.Doctor = Depends(get_current_doctor)):
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    result = await db.execute(
        select(models.ChatMessage)
        .where(models.ChatMessage.patient_id == patient.id)
        .order_by(models.ChatMessage.created_at.asc())
    )
    return result.scalars().all()


@app.post("/doctor/patients/{username}/chat", response_model=schemas.ChatMessage)
async def doctor_send_chat_message(username: str, payload: schemas.DoctorChatMessageCreate, db: AsyncSession = Depends(get_db), current_doctor: models.Doctor = Depends(get_current_doctor)):
    res = await db.execute(select(models.Patient).where(models.Patient.username == username))
    patient = res.scalars().first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    msg = models.ChatMessage(
        patient_id=patient.id,
        sender_role="doctor",
        sender_username=current_doctor.username,
        message=payload.message,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg

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

@app.get("/instruction-status/changes", response_model=List[schemas.InstructionStatusResponse])
async def list_instruction_status_changes(
    since: str,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    """Return instruction status rows updated AFTER the provided ISO8601 timestamp (UTC).
    Example since: "2025-08-01T00:00:00Z" or "2025-08-01T00:00:00+00:00"
    """
    try:
        from datetime import datetime, timezone as _dt_tz
        # Accept both Z and explicit offset forms
        parsed = datetime.fromisoformat(since.replace("Z", "+00:00"))
        # Convert to naive UTC to match TIMESTAMP WITHOUT TIME ZONE columns
        if parsed.tzinfo is not None:
            since_dt = parsed.astimezone(_dt_tz.utc).replace(tzinfo=None)
        else:
            # Treat naive input as UTC already
            since_dt = parsed
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid 'since' timestamp")

    q = (
        select(models.InstructionStatus)
        .where(
            models.InstructionStatus.patient_id == current_user.id,
            models.InstructionStatus.updated_at > since_dt,
        )
        .order_by(models.InstructionStatus.updated_at.asc())
    )
    res = await db.execute(q)
    rows = res.scalars().all()
    # Response models will be built from attributes (schemas.from_attributes)
    return rows

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
    # Mark current episode as completed and lock it permanently
    object.__setattr__(ep, 'procedure_completed', bool(payload.procedure_completed))
    if payload.procedure_date is not None:
        object.__setattr__(ep, 'procedure_date', payload.procedure_date)
    if payload.procedure_time is not None:
        object.__setattr__(ep, 'procedure_time', payload.procedure_time)
    # If no date/time provided and none set yet, default to server 'now'
    if getattr(ep, 'procedure_date', None) is None and payload.procedure_date is None:
        object.__setattr__(ep, 'procedure_date', date.today())
    if getattr(ep, 'procedure_time', None) is None and payload.procedure_time is None:
        object.__setattr__(ep, 'procedure_time', datetime.utcnow().time())
    object.__setattr__(ep, 'locked', True)
    db.add(ep)
    await db.commit()
    await db.refresh(ep)

    # Persist account-scoped completion markers on the Patient row so that
    # "SELECT * FROM patients" shows that this account has completed a treatment.
    try:
        object.__setattr__(current_user, 'ever_completed', True)
        object.__setattr__(current_user, 'last_completed_episode_id', int(object.__getattribute__(ep, 'id')))
        object.__setattr__(current_user, 'last_completed_at', datetime.utcnow())
        db.add(current_user)
        await db.commit()
        await db.refresh(current_user)
    except Exception as _e:
        # Best-effort only; don't block completion if the DB hasn't been migrated yet.
        print(f"[episodes/mark-complete] patient completion marker write skipped: {_e}")

    # Immediately create a new open episode for the patient to start a fresh treatment
    new_ep = models.TreatmentEpisode(
        patient_id=object.__getattribute__(current_user, 'id'),
        # Preserve assignment to keep /patients/by-doctor stable after completion.
        department=getattr(ep, 'department', None) or getattr(current_user, 'department', None),
        doctor=getattr(ep, 'doctor', None) or getattr(current_user, 'doctor', None),
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

    # Mirror the new open episode state to the Patient row (so edits apply to the new episode)
    await _mirror_episode_to_patient(db, current_user, new_ep)

    # Return the locked episode as confirmation of completion
    return schemas.EpisodeResponse.model_validate(ep, from_attributes=True)

@app.post("/episodes/rotate-if-due", response_model=schemas.RotateIfDueResponse)
async def rotate_if_due_endpoint(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    new_id = await _rotate_if_due(db, current_user)
    if new_id is None:
        return schemas.RotateIfDueResponse(rotated=False, new_episode_id=None)
    return schemas.RotateIfDueResponse(rotated=True, new_episode_id=new_id)


@app.post("/episodes/start-new", response_model=schemas.StartNewEpisodeResponse)
async def start_new_episode(
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    """Start a new procedure AFTER the current one is completed.

    Intended for the patient Instruction tab flow:
      - Current procedure has been completed (procedure_completed=True)
      - Patient taps "Start new procedure"
      - Server locks the completed episode and creates a fresh open episode (new id)

    This keeps the same account (patients row) and preserves old treatment history in treatment_episodes.
    """
    ep = await _get_or_create_open_episode(db, object.__getattribute__(current_user, 'id'))

    # If current open episode is not completed, we refuse to start a new one.
    # This prevents accidental loss/overwrite of an ongoing procedure.
    if not bool(getattr(ep, 'procedure_completed', False)):
        raise HTTPException(status_code=409, detail="Current procedure is not completed yet.")

    locked_id: int | None = None
    if not bool(getattr(ep, 'locked', False)):
        object.__setattr__(ep, 'locked', True)
        db.add(ep)
        await db.commit()
        await db.refresh(ep)
    try:
        locked_id = int(object.__getattribute__(ep, 'id'))
    except Exception:
        locked_id = getattr(ep, 'id', None)

    # Persist account-scoped completion markers (best-effort).
    try:
        object.__setattr__(current_user, 'ever_completed', True)
        object.__setattr__(current_user, 'last_completed_episode_id', locked_id)
        object.__setattr__(current_user, 'last_completed_at', datetime.utcnow())
        db.add(current_user)
        await db.commit()
        await db.refresh(current_user)
    except Exception as _e:
        print(f"[episodes/start-new] patient completion marker write skipped: {_e}")

    new_ep = models.TreatmentEpisode(
        patient_id=object.__getattribute__(current_user, 'id'),
        # Preserve assignment to keep doctor dashboards stable.
        department=getattr(ep, 'department', None) or getattr(current_user, 'department', None),
        doctor=getattr(ep, 'doctor', None) or getattr(current_user, 'doctor', None),
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

    await _mirror_episode_to_patient(db, current_user, new_ep)
    return schemas.StartNewEpisodeResponse(started=True, locked_episode_id=locked_id, new_episode_id=new_ep.id)


@app.post("/episodes/replace-treatment", response_model=schemas.PatientPublic)
async def replace_treatment_episode(
    payload: schemas.ReplaceTreatmentRequest,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    """Replace the current (open) treatment episode.

    Intended for the "Treatment Options" menu when a patient accidentally selected the wrong treatment.

    Behavior:
      - Deletes progress entries since the previous procedure date (if available).
      - Deletes instruction_status rows for the previous treatment/subtype since the previous procedure date.
      - Deletes any open episode(s) (locked=False) and creates a fresh open episode with the new treatment.
      - Mirrors the new open episode onto the Patient row.
    """
    await _rotate_if_due(db, current_user)

    # Snapshot the CURRENT OPEN episode (ongoing treatment). Completed (locked) episodes must remain in history.
    ep = await _get_or_create_open_episode(db, object.__getattribute__(current_user, 'id'))
    if getattr(ep, "locked", False):
        raise HTTPException(status_code=423, detail="Episode is locked and cannot be modified.")

    old_treatment = getattr(ep, 'treatment', None)
    old_subtype = getattr(ep, 'subtype', None)
    old_proc_date = getattr(ep, 'procedure_date', None)

    # Reset ongoing episode data only.
    # Progress table doesn't have episode id, so we cut from the ongoing episode start date.
    effective_cutoff_date = old_proc_date or payload.procedure_date
    if effective_cutoff_date is not None:
        cutoff_dt = datetime.combine(effective_cutoff_date, datetime.min.time())
        await db.execute(
            delete(models.Progress).where(
                models.Progress.patient_id == current_user.id,
                models.Progress.timestamp >= cutoff_dt,
            )
        )

    # Clear instruction statuses for the ongoing episode identity only.
    # This preserves completed history for other episodes/treatments.
    if old_treatment:
        stmt = delete(models.InstructionStatus).where(
            models.InstructionStatus.patient_id == current_user.id,
            models.InstructionStatus.treatment == old_treatment,
        )
        if old_subtype is None:
            stmt = stmt.where(models.InstructionStatus.subtype.is_(None))
        else:
            stmt = stmt.where(models.InstructionStatus.subtype == old_subtype)
        if effective_cutoff_date is not None:
            stmt = stmt.where(models.InstructionStatus.date >= effective_cutoff_date)
        await db.execute(stmt)

    # Delete any open episodes and create a fresh one.
    await db.execute(
        delete(models.TreatmentEpisode).where(
            models.TreatmentEpisode.patient_id == current_user.id,
            models.TreatmentEpisode.locked == False,
        )
    )

    new_ep = models.TreatmentEpisode(
        patient_id=current_user.id,
        department=getattr(current_user, 'department', None),
        doctor=getattr(current_user, 'doctor', None),
        treatment=payload.treatment,
        subtype=payload.subtype,
        procedure_date=payload.procedure_date,
        procedure_time=payload.procedure_time,
        procedure_completed=False,
        locked=False,
    )
    db.add(new_ep)
    await db.commit()
    await db.refresh(new_ep)

    await _mirror_episode_to_patient(db, current_user, new_ep)
    # Ensure patient is marked not completed.
    object.__setattr__(current_user, 'procedure_completed', False)
    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)
    return current_user

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
            dt = datetime.fromisoformat(s)
            # Always store as naive UTC to match TIMESTAMP WITHOUT TIME ZONE columns
            # and comparisons against datetime.utcnow() elsewhere.
            if dt.tzinfo is not None:
                dt = dt.astimezone(pytz.UTC).replace(tzinfo=None)
            return dt
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
                # Normalize to naive UTC for DB storage
                if dt.tzinfo is not None:
                    dt = dt.astimezone(pytz.UTC).replace(tzinfo=None)
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
    # Delegate to internal processor
    debug = request.query_params.get("debug") in {"1","true","yes","on"}
    result = await _internal_dispatch_due(db, dry_run=dry_run, limit=limit, debug=debug)
    return result

# --- Internal shared logic for scheduled push + reminder fallback dispatch ---
async def _internal_dispatch_due(
    db: AsyncSession,
    dry_run: bool = False,
    limit: int = 50,
    debug: bool = False,
) -> dict[str, Any]:
    """Core logic used by both the public endpoint and background scheduler.
    Returns counts; if debug=True includes per-item decision traces.
    """
    decisions: list[dict[str, Any]] = [] if debug else []
    sent = 0
    # Scheduled pushes first
    now = datetime.utcnow()
    res = await db.execute(
        select(models.ScheduledPush)
        .where(models.ScheduledPush.sent == False)
        .where(models.ScheduledPush.send_at <= now)
    )
    pushes = res.scalars().all()
    if limit and len(pushes) > limit:
        pushes = pushes[:limit]
    if dry_run:
        return {"sent": 0, "dispatched_pushes": len(pushes), "dispatched_reminders": 0, "mode": "dry_run"}
    # Helper to classify FCM error code from response body text (minimal regex-free scan)
    def _extract_fcm_error(body: str | None) -> str | None:
        if not body:
            return None
        # Look for common error markers
        for key in ["UNREGISTERED", "InvalidRegistration", "NotRegistered", "MismatchSenderId", "QuotaExceeded", "Internal", "Unavailable"]:
            if key in body:
                return key
        return None
    for push in pushes:
        token_res = await db.execute(select(models.DeviceToken.token).where(models.DeviceToken.patient_id == push.patient_id).where(models.DeviceToken.active == True))
        tokens = [row[0] for row in token_res.all()]
        push_sent_tokens = 0
        for t in tokens:
            res_obj = send_fcm_notification_ex(t, getattr(push, "title"), getattr(push, "body"))  # type: ignore
            if res_obj.get("ok"):
                sent += 1
                push_sent_tokens += 1
            else:
                err_code = _extract_fcm_error(res_obj.get("body"))
                if err_code in {"UNREGISTERED", "NotRegistered"}:
                    # Deactivate token
                    tok_row = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == t))
                    tok = tok_row.scalars().first()
                    if tok and getattr(tok, 'active'):
                        object.__setattr__(tok, 'active', False)
                        object.__setattr__(tok, 'deactivated_at', datetime.utcnow())
                        object.__setattr__(tok, 'deactivated_reason', 'UNREGISTERED')
                        db.add(tok)
            if os.getenv("REMINDER_STRUCTURED_LOG", "0").lower() in {"1","true","yes","on"}:
                import json as _json
                try:
                    print(_json.dumps({
                        "evt": "scheduled_push_attempt",
                        "push_id": object.__getattribute__(push,'id'),
                        "patient_id": getattr(push,'patient_id'),
                        "token_tail": t[-10:] if len(t) > 10 else t,
                        "ok": res_obj.get("ok"),
                        "status": res_obj.get("status"),
                        "error_code": _extract_fcm_error(res_obj.get("body")),
                        "ts": datetime.utcnow().isoformat()+"Z"
                    }))
                except Exception:
                    pass
        # Mark push complete regardless of per-token success; logic could be adapted to retry unsent tokens if desired.
        setattr(push, "sent", True)
        setattr(push, "sent_at", datetime.utcnow())
        db.add(push)
        if debug:
            decisions.append({
                "type": "scheduled_push",
                "id": object.__getattribute__(push, 'id'),
                "tokens": len(tokens),
                "sent_tokens": push_sent_tokens,
            })

    # Reminder fallback
    now2 = datetime.utcnow()
    rem_res = await db.execute(
        select(models.Reminder)
        .where(models.Reminder.active == True)
        .where(models.Reminder.next_fire_utc <= now2)
    )
    reminders = rem_res.scalars().all()
    dispatched_rem = 0
    server_only = os.getenv("REMINDERS_SERVER_ONLY", "0").lower() in {"1","true","yes","on"}
    decision_log_enabled = os.getenv("REMINDER_DECISION_LOG", "0").lower() in {"1","true","yes","on"}
    # Optional global grace override (e.g. force 0 for immediate server fallback) set REMINDER_FORCE_GRACE_MINUTES=0
    force_grace: int | None = None
    fge = os.getenv("REMINDER_FORCE_GRACE_MINUTES")
    if fge is not None:
        try:
            force_grace = int(fge.strip())
        except Exception:
            force_grace = None
    # Retry/backoff parameters
    MAX_ATTEMPTS_PER_DAY = int(os.getenv("REMINDER_MAX_ATTEMPTS", "3"))
    BACKOFF_SECONDS = [120, 300, 600]  # default 2m,5m,10m
    raw_backoff = os.getenv("REMINDER_BACKOFF")
    if raw_backoff:
        try:
            parsed = [int(x.strip()) for x in raw_backoff.split(',') if x.strip()]
            if parsed:
                BACKOFF_SECONDS = parsed
        except Exception as _e:
            print(f"[Dispatch] Ignoring REMINDER_BACKOFF parse error: {_e}")
    for r in reminders:
        reason = "send"
        try:
            tz = pytz.timezone(getattr(r, 'timezone'))
        except Exception:
            tz = pytz.UTC
        now_local = now2.replace(tzinfo=pytz.UTC).astimezone(tz)
        # Apply forced grace override only in non-server-only mode.
        # In server-only mode grace is ignored for send decisions, so forcing it
        # would just mutate DB rows and spam logs.
        if (not server_only) and (force_grace is not None) and getattr(r, 'grace_minutes') != force_grace:
            try:
                object.__setattr__(r, 'grace_minutes', force_grace)
            except Exception:
                pass
        if server_only:
            # Server-only mode: ignore ack/grace decisions, but still honor delivery success/failure.
            # Critically: do NOT advance to next day if nothing was delivered.
            reason = "server_only_send"
            try:
                token_res = await db.execute(
                    select(models.DeviceToken.token)
                    .where(models.DeviceToken.patient_id == getattr(r, 'patient_id'))
                    .where(models.DeviceToken.active == True)
                    # Avoid duplicate reminders if the client schedules locally.
                    .where(models.DeviceToken.local_reminders_enabled == False)
                )
                tokens = [row[0] for row in token_res.all()]
            except Exception:
                # Backwards-compatible: if migration not applied yet, don't filter.
                token_res = await db.execute(
                    select(models.DeviceToken.token)
                    .where(models.DeviceToken.patient_id == getattr(r, 'patient_id'))
                    .where(models.DeviceToken.active == True)
                )
                tokens = [row[0] for row in token_res.all()]
            tokens_count = len(tokens)
            if tokens_count == 0:
                # No active token to deliver to.
                next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
                object.__setattr__(r, 'next_fire_local', next_local)
                object.__setattr__(r, 'next_fire_utc', next_utc)
                object.__setattr__(r, 'attempts_today', 0)
                object.__setattr__(r, 'last_delivery_status', 'no_tokens')
                object.__setattr__(r, 'updated_at', now2)
                db.add(r)
                if debug:
                    decisions.append({
                        "type": "reminder",
                        "id": object.__getattribute__(r,'id'),
                        "action": reason,
                        "status": 'no_tokens',
                        "tokens": 0,
                    })
                continue

            if decision_log_enabled:
                try:
                    print({
                        "evt": "reminder_decision",
                        "reminder_id": object.__getattribute__(r, 'id'),
                        "patient_id": getattr(r, 'patient_id'),
                        "action": "send_start",
                        "mode": "server_only",
                        "tokens": tokens_count,
                        "data": {
                            "kind": "reminder",
                            "reminder_id": str(object.__getattribute__(r, 'id')),
                            "patient_id": str(getattr(r, 'patient_id')),
                            "fire_utc": now2.isoformat() + "Z",
                        },
                        "android_channel_id": "reminders_channel_alarm_v2",
                        "ts": datetime.utcnow().isoformat() + "Z",
                    })
                except Exception:
                    pass

            sent_tokens = 0
            any_token_invalid = False
            for t in tokens:
                reminder_id = str(object.__getattribute__(r, 'id'))
                due_utc = getattr(r, 'next_fire_utc', None)
                due_utc_str = None
                try:
                    if due_utc is not None:
                        due_utc_str = due_utc.isoformat() + "Z"
                except Exception:
                    due_utc_str = None
                # Keep reminders queued while the device is offline, but don't deliver extremely late.
                try:
                    max_late_min = int(os.getenv("REMINDER_MAX_LATE_MINUTES", "720"))
                except Exception:
                    max_late_min = 720
                if max_late_min < 1:
                    max_late_min = 1
                if max_late_min > 10080:
                    max_late_min = 10080
                ttl_seconds = max_late_min * 60
                try:
                    base_due = due_utc if due_utc is not None else now2
                    ttl_seconds = int((base_due + timedelta(minutes=max_late_min) - now2).total_seconds())
                    if ttl_seconds < 0:
                        ttl_seconds = 0
                except Exception:
                    pass
                data = {
                    "kind": "reminder",
                    "reminder_id": reminder_id,
                    "patient_id": str(getattr(r, 'patient_id')),
                    "fire_utc": now2.isoformat() + "Z",
                    "scheduled_utc": due_utc_str or (now2.isoformat() + "Z"),
                    "title": str(getattr(r, 'title')),
                    "body": str(getattr(r, 'body')),
                }
                res_obj = send_fcm_notification_ex(
                    t,
                    getattr(r, 'title'),
                    getattr(r, 'body'),
                    data=data,
                    android_channel_id="reminders_channel_alarm_v2",
                    data_only=False,
                    ttl_seconds=ttl_seconds,
                )  # type: ignore
                if res_obj.get("ok"):
                    sent += 1
                    sent_tokens += 1
                else:
                    err_code = _extract_fcm_error(res_obj.get("body"))
                    if err_code in {"UNREGISTERED", "NotRegistered"}:
                        any_token_invalid = True
                        tok_row = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == t))
                        tok = tok_row.scalars().first()
                        if tok and getattr(tok, 'active'):
                            object.__setattr__(tok, 'active', False)
                            object.__setattr__(tok, 'deactivated_at', datetime.utcnow())
                            object.__setattr__(tok, 'deactivated_reason', 'UNREGISTERED')
                            db.add(tok)

                if os.getenv("REMINDER_STRUCTURED_LOG", "0").lower() in {"1","true","yes","on"}:
                    import json as _json
                    try:
                        print(_json.dumps({
                            "evt": "reminder_attempt",
                            "reminder_id": object.__getattribute__(r,'id'),
                            "patient_id": getattr(r,'patient_id'),
                            "mode": "server_only",
                            "token_tail": t[-10:] if len(t) > 10 else t,
                            "ok": res_obj.get("ok"),
                            "status": res_obj.get("status"),
                            "error_code": _extract_fcm_error(res_obj.get("body")),
                            "attempts_today": getattr(r,'attempts_today'),
                            "ts": datetime.utcnow().isoformat()+"Z"
                        }))
                    except Exception:
                        pass

            attempts = getattr(r, 'attempts_today') or 0
            object.__setattr__(r, 'last_attempt_utc', now2)
            if sent_tokens > 0:
                dispatched_rem += 1
                object.__setattr__(r, 'last_sent_utc', now2)
                next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
                object.__setattr__(r, 'next_fire_local', next_local)
                object.__setattr__(r, 'next_fire_utc', next_utc)
                object.__setattr__(r, 'attempts_today', 0)
                object.__setattr__(r, 'last_delivery_status', 'delivered')
            else:
                # Retry with backoff (same as non-server-only), so failed pushes don't get dropped.
                if attempts + 1 >= MAX_ATTEMPTS_PER_DAY:
                    next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
                    object.__setattr__(r, 'next_fire_local', next_local)
                    object.__setattr__(r, 'next_fire_utc', next_utc)
                    object.__setattr__(r, 'attempts_today', 0)
                    object.__setattr__(r, 'last_delivery_status', 'token_invalid' if any_token_invalid else 'failed_permanent')
                else:
                    backoff_idx = min(attempts, len(BACKOFF_SECONDS)-1)
                    retry_delay = BACKOFF_SECONDS[backoff_idx]
                    retry_utc = now2 + timedelta(seconds=retry_delay)
                    try:
                        tz_retry = pytz.timezone(getattr(r, 'timezone'))
                    except Exception:
                        tz_retry = pytz.UTC
                    retry_local = retry_utc.replace(tzinfo=pytz.UTC).astimezone(tz_retry).replace(tzinfo=None)
                    object.__setattr__(r, 'next_fire_local', retry_local)
                    object.__setattr__(r, 'next_fire_utc', retry_utc)
                    object.__setattr__(r, 'attempts_today', attempts + 1)
                    object.__setattr__(r, 'last_delivery_status', 'token_invalid' if any_token_invalid else 'retry')

            object.__setattr__(r, 'updated_at', now2)
            db.add(r)
            if debug:
                decisions.append({
                    "type": "reminder",
                    "id": object.__getattribute__(r,'id'),
                    "action": reason,
                    "tokens": tokens_count,
                    "sent_tokens": sent_tokens,
                    "attempts_today": getattr(r,'attempts_today'),
                    "status": getattr(r,'last_delivery_status'),
                })
            continue
        # Skip if acknowledged today
        if getattr(r, 'last_ack_local_date') == now_local.date():
            reason = "skip_ack_today"
            next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
            setattr(r, 'next_fire_local', next_local)
            setattr(r, 'next_fire_utc', next_utc)
            setattr(r, 'updated_at', now2)
            db.add(r)
            if debug:
                decisions.append({
                    "type": "reminder",
                    "id": object.__getattribute__(r,'id'),
                    "action": reason,
                })
            continue
        # Grace window check
        scheduled_local_time = getattr(r, 'next_fire_local')
        grace_minutes = getattr(r, 'grace_minutes') or 0
        if scheduled_local_time:
            try:
                sched_local = tz.localize(scheduled_local_time) if scheduled_local_time.tzinfo is None else scheduled_local_time.astimezone(tz)
            except Exception:
                sched_local = now_local
            grace_deadline = sched_local + timedelta(minutes=grace_minutes)
            if now_local < grace_deadline:
                reason = "skip_in_grace"
                if debug:
                    decisions.append({
                        "type": "reminder",
                        "id": object.__getattribute__(r,'id'),
                        "action": reason,
                        "grace_deadline": grace_deadline.isoformat(),
                        "now_local": now_local.isoformat(),
                        "grace_minutes": grace_minutes,
                    })
                if decision_log_enabled:
                    try:
                        print({
                            "evt": "reminder_decision",
                            "reminder_id": object.__getattribute__(r,'id'),
                            "action": reason,
                            "grace_minutes": grace_minutes,
                            "grace_deadline": grace_deadline.isoformat(),
                            "now_local": now_local.isoformat(),
                            "ts": datetime.utcnow().isoformat()+"Z"
                        })
                    except Exception:
                        pass
                continue
        # Send
        try:
            token_res = await db.execute(
                select(models.DeviceToken.token)
                .where(models.DeviceToken.patient_id == getattr(r, 'patient_id'))
                .where(models.DeviceToken.active == True)
                # Avoid duplicate reminders if the client schedules locally.
                .where(models.DeviceToken.local_reminders_enabled == False)
            )
            tokens = [row[0] for row in token_res.all()]
        except Exception:
            # Backwards-compatible: if migration not applied yet, don't filter.
            token_res = await db.execute(
                select(models.DeviceToken.token)
                .where(models.DeviceToken.patient_id == getattr(r, 'patient_id'))
                .where(models.DeviceToken.active == True)
            )
            tokens = [row[0] for row in token_res.all()]
        tokens_count = len(tokens)
        if tokens_count == 0:
            # No device tokens: treat as terminal for today; move to next day to avoid tight retries.
            reason = "no_tokens"
            next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
            object.__setattr__(r, 'next_fire_local', next_local)
            object.__setattr__(r, 'next_fire_utc', next_utc)
            object.__setattr__(r, 'attempts_today', 0)
            object.__setattr__(r, 'last_delivery_status', 'no_tokens')
            object.__setattr__(r, 'updated_at', now2)
            db.add(r)
            if debug:
                decisions.append({
                    "type": "reminder",
                    "id": object.__getattribute__(r,'id'),
                    "action": reason,
                    "status": 'no_tokens',
                    "attempts_today": 0,
                })
            if decision_log_enabled:
                try:
                    print({
                        "evt": "reminder_decision",
                        "reminder_id": object.__getattribute__(r,'id'),
                        "action": reason,
                        "status": 'no_tokens',
                        "tokens": 0,
                        "ts": datetime.utcnow().isoformat()+"Z"
                    })
                except Exception:
                    pass
            continue

        if decision_log_enabled:
            try:
                print({
                    "evt": "reminder_decision",
                    "reminder_id": object.__getattribute__(r, 'id'),
                    "patient_id": getattr(r, 'patient_id'),
                    "action": "send_start",
                    "mode": "normal",
                    "tokens": tokens_count,
                    "data": {
                        "kind": "reminder",
                        "reminder_id": str(object.__getattribute__(r, 'id')),
                        "patient_id": str(getattr(r, 'patient_id')),
                        "fire_utc": now2.isoformat() + "Z",
                    },
                    "android_channel_id": "reminders_channel_alarm_v2",
                    "ts": datetime.utcnow().isoformat() + "Z",
                })
            except Exception:
                pass
        sent_tokens = 0
        any_token_invalid = False
        for t in tokens:
            reminder_id = str(object.__getattribute__(r, 'id'))
            due_utc = getattr(r, 'next_fire_utc', None)
            due_utc_str = None
            try:
                if due_utc is not None:
                    due_utc_str = due_utc.isoformat() + "Z"
            except Exception:
                due_utc_str = None
            # Keep reminders queued while the device is offline, but don't deliver extremely late.
            try:
                max_late_min = int(os.getenv("REMINDER_MAX_LATE_MINUTES", "720"))
            except Exception:
                max_late_min = 720
            if max_late_min < 1:
                max_late_min = 1
            if max_late_min > 10080:
                max_late_min = 10080
            ttl_seconds = max_late_min * 60
            try:
                base_due = due_utc if due_utc is not None else now2
                ttl_seconds = int((base_due + timedelta(minutes=max_late_min) - now2).total_seconds())
                if ttl_seconds < 0:
                    ttl_seconds = 0
            except Exception:
                pass
            data = {
                "kind": "reminder",
                "reminder_id": reminder_id,
                "patient_id": str(getattr(r, 'patient_id')),
                "fire_utc": now2.isoformat() + "Z",
                "scheduled_utc": due_utc_str or (now2.isoformat() + "Z"),
                "title": str(getattr(r, 'title')),
                "body": str(getattr(r, 'body')),
            }
            res_obj = send_fcm_notification_ex(
                t,
                getattr(r, 'title'),
                getattr(r, 'body'),
                data=data,
                android_channel_id="reminders_channel_alarm_v2",
                data_only=False,
                ttl_seconds=ttl_seconds,
            )  # type: ignore
            if res_obj.get("ok"):
                sent += 1
                sent_tokens += 1
            else:
                err_code = _extract_fcm_error(res_obj.get("body"))
                if err_code in {"UNREGISTERED", "NotRegistered"}:
                    any_token_invalid = True
                    tok_row = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == t))
                    tok = tok_row.scalars().first()
                    if tok and getattr(tok, 'active'):
                        object.__setattr__(tok, 'active', False)
                        object.__setattr__(tok, 'deactivated_at', datetime.utcnow())
                        object.__setattr__(tok, 'deactivated_reason', 'UNREGISTERED')
                        db.add(tok)
            if os.getenv("REMINDER_STRUCTURED_LOG", "0").lower() in {"1","true","yes","on"}:
                import json as _json
                try:
                    print(_json.dumps({
                        "evt": "reminder_attempt",
                        "reminder_id": object.__getattribute__(r,'id'),
                        "patient_id": getattr(r,'patient_id'),
                        "token_tail": t[-10:] if len(t) > 10 else t,
                        "ok": res_obj.get("ok"),
                        "status": res_obj.get("status"),
                        "error_code": _extract_fcm_error(res_obj.get("body")),
                        "attempts_today": getattr(r,'attempts_today'),
                        "ts": datetime.utcnow().isoformat()+"Z"
                    }))
                except Exception:
                    pass
        # Update reminder retry state
        attempts = getattr(r, 'attempts_today') or 0
        object.__setattr__(r, 'last_attempt_utc', now2)
        status_val = None
        if sent_tokens > 0:
            # Success: advance to next day, reset attempts
            dispatched_rem += 1
            object.__setattr__(r, 'last_sent_utc', now2)
            next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
            object.__setattr__(r, 'next_fire_local', next_local)
            object.__setattr__(r, 'next_fire_utc', next_utc)
            object.__setattr__(r, 'attempts_today', 0)
            status_val = 'delivered'
        else:
            # Failure path
            if attempts + 1 >= MAX_ATTEMPTS_PER_DAY:
                # Give up for today: schedule next day
                next_local, next_utc = _compute_next_fire(now2, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
                object.__setattr__(r, 'next_fire_local', next_local)
                object.__setattr__(r, 'next_fire_utc', next_utc)
                object.__setattr__(r, 'attempts_today', 0)
                status_val = 'token_invalid' if any_token_invalid else 'failed_permanent'
            else:
                # Schedule retry using backoff
                backoff_idx = min(attempts, len(BACKOFF_SECONDS)-1)
                retry_delay = BACKOFF_SECONDS[backoff_idx]
                retry_utc = now2 + timedelta(seconds=retry_delay)
                # Keep local retry time for transparency (convert from utc)
                try:
                    tz_retry = pytz.timezone(getattr(r, 'timezone'))
                except Exception:
                    tz_retry = pytz.UTC
                retry_local = retry_utc.replace(tzinfo=pytz.UTC).astimezone(tz_retry).replace(tzinfo=None)
                object.__setattr__(r, 'next_fire_local', retry_local)
                object.__setattr__(r, 'next_fire_utc', retry_utc)
                object.__setattr__(r, 'attempts_today', attempts + 1)
                status_val = 'token_invalid' if any_token_invalid else 'retry'
        object.__setattr__(r, 'last_delivery_status', status_val)
        object.__setattr__(r, 'updated_at', now2)
        db.add(r)
        if debug:
            decisions.append({
                "type": "reminder",
                "id": object.__getattribute__(r,'id'),
                "action": reason,
                "sent_tokens": sent_tokens,
                "attempts_today": getattr(r,'attempts_today'),
                "status": status_val,
                "tokens": tokens_count,
                "grace_minutes": grace_minutes,
            })
        if decision_log_enabled:
            try:
                print({
                    "evt": "reminder_decision",
                    "reminder_id": object.__getattribute__(r,'id'),
                    "action": reason,
                    "status": status_val,
                    "tokens": tokens_count,
                    "sent_tokens": sent_tokens,
                    "attempts_today": getattr(r,'attempts_today'),
                    "grace_minutes": grace_minutes,
                    "ts": datetime.utcnow().isoformat()+"Z"
                })
            except Exception:
                pass

    if pushes or reminders:
        await db.commit()
    global REMINDER_DISPATCH_LAST_RUN, REMINDER_DISPATCH_LAST_COUNTS
    REMINDER_DISPATCH_LAST_RUN = datetime.utcnow()
    REMINDER_DISPATCH_LAST_COUNTS = {
        "sent": sent,
        "dispatched_pushes": len(pushes),
        "dispatched_reminders": dispatched_rem,
    }
    base = {"sent": sent, "dispatched_pushes": len(pushes), "dispatched_reminders": dispatched_rem}
    if debug:
        # decisions is a list of dicts; acceptable dynamic payload
        base["decisions"] = decisions  # type: ignore[assignment]
    return base


@app.post("/push/register-device", response_model=schemas.DeviceTokenResponse)
async def register_device(
    request: Request,
    payload: Optional[schemas.DeviceRegisterRequest] = Body(None),
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    # Avoid ORM lazy-load surprises; grab scalar user id once.
    try:
        current_user_id = object.__getattribute__(current_user, 'id')
    except Exception:
        current_user_id = getattr(current_user, 'id', None)

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

        # Optional log to verify client registration on hosted environments
        if os.getenv("PUSH_REGISTER_LOG", "0").lower() in {"1", "true", "yes", "on"}:
            try:
                tok_tail = payload.token[-10:] if isinstance(payload.token, str) and len(payload.token) > 10 else payload.token
                print({
                    "evt": "push_register_device",
                    "patient_id": getattr(current_user, 'id', None),
                    "platform": payload.platform,
                    "token_tail": tok_tail,
                    "ts": datetime.utcnow().isoformat() + "Z",
                })
            except Exception:
                pass
    # Upsert by unique token; if token exists, reassign to current user and update platform
    async def _commit_or_race_recover() -> Optional[models.DeviceToken]:
        """Commit the current unit of work.

        If another concurrent request inserted the same device token (unique constraint),
        rollback and return the row that now exists.
        """
        try:
            await db.commit()
            return None
        except IntegrityError as exc:
            try:
                await db.rollback()
            except Exception:
                pass
            msg = str(exc)
            # If this looks like the token unique constraint, treat it as an upsert race.
            if "device_tokens" in msg and "token" in msg and ("duplicate" in msg.lower() or "unique" in msg.lower()):
                try:
                    q = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == payload.token))
                    return q.scalars().first()
                except Exception:
                    return None
            raise

    existing_q = await db.execute(select(models.DeviceToken).where(models.DeviceToken.token == payload.token))
    existing = existing_q.scalars().first()
    if existing:
        object.__setattr__(existing, 'patient_id', current_user_id)
        object.__setattr__(existing, 'platform', payload.platform)
        try:
            if hasattr(models.DeviceToken, 'local_reminders_enabled'):
                object.__setattr__(existing, 'local_reminders_enabled', bool(getattr(payload, 'local_reminders_enabled', False)))
        except Exception:
            pass
        # Reactivate if previously deactivated
        if hasattr(existing, 'active'):
            object.__setattr__(existing, 'active', True)
            object.__setattr__(existing, 'deactivated_at', None)
            object.__setattr__(existing, 'deactivated_reason', None)
        db.add(existing)
        raced = await _commit_or_race_recover()
        if raced is not None:
            existing = raced
        await db.refresh(existing)
        # Enforce single-device-per-user if enabled
        if os.getenv("PUSH_SINGLE_DEVICE", "true").lower() in {"1", "true", "yes", "on"}:
            others_q = await db.execute(
                select(models.DeviceToken)
                .where(models.DeviceToken.patient_id == current_user_id)
                .where(models.DeviceToken.id != object.__getattribute__(existing, 'id'))
            )
            for d in others_q.scalars().all():
                await db.delete(d)
            try:
                await db.commit()
            except Exception:
                try:
                    await db.rollback()
                except Exception:
                    pass
        return existing
    create_kwargs = {
        'patient_id': current_user_id,
        'platform': payload.platform,
        'token': payload.token,
    }
    if hasattr(models.DeviceToken, 'local_reminders_enabled'):
        create_kwargs['local_reminders_enabled'] = bool(getattr(payload, 'local_reminders_enabled', False))

    row = models.DeviceToken(**create_kwargs)
    db.add(row)
    raced = await _commit_or_race_recover()
    if raced is not None:
        # Another request inserted the same token concurrently. Update it to this user/platform.
        row = raced
        try:
            object.__setattr__(row, 'patient_id', current_user_id)
            object.__setattr__(row, 'platform', payload.platform)
            if hasattr(models.DeviceToken, 'local_reminders_enabled'):
                object.__setattr__(row, 'local_reminders_enabled', bool(getattr(payload, 'local_reminders_enabled', False)))
            if hasattr(row, 'active'):
                object.__setattr__(row, 'active', True)
                object.__setattr__(row, 'deactivated_at', None)
                object.__setattr__(row, 'deactivated_reason', None)
            db.add(row)
            await db.commit()
        except Exception:
            try:
                await db.rollback()
            except Exception:
                pass
    await db.refresh(row)
    # Enforce single-device-per-user if enabled
    if os.getenv("PUSH_SINGLE_DEVICE", "true").lower() in {"1", "true", "yes", "on"}:
        others_q = await db.execute(
            select(models.DeviceToken)
            .where(models.DeviceToken.patient_id == current_user_id)
            .where(models.DeviceToken.id != object.__getattribute__(row, 'id'))
        )
        for d in others_q.scalars().all():
            await db.delete(d)
        try:
            await db.commit()
        except Exception:
            try:
                await db.rollback()
            except Exception:
                pass

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

# ---------------------------
# Reminder CRUD & Hybrid Sync
# ---------------------------

def _validate_reminder_time(hour: int, minute: int):
    if hour < 0 or hour > 23:
        raise HTTPException(status_code=422, detail="hour must be 0-23")
    if minute < 0 or minute > 59:
        raise HTTPException(status_code=422, detail="minute must be 0-59")

def _compute_next_local_utc(now_utc: datetime, hour: int, minute: int, tz_name: str) -> tuple[datetime, datetime]:
    # Reuse existing helper if present
    try:
        return _compute_next_fire(now_utc, hour, minute, tz_name)
    except Exception:
        # Fallback simple implementation
        try:
            tz = pytz.timezone(tz_name)
        except Exception:
            tz = pytz.UTC
        local_now = now_utc.replace(tzinfo=pytz.UTC).astimezone(tz)
        candidate = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate <= local_now:
            candidate = candidate + timedelta(days=1)
        # Store local naive (strip tz) for continuity with existing model comment
        local_store = candidate.replace(tzinfo=None)
        utc_instant = candidate.astimezone(pytz.UTC).replace(tzinfo=None)
        return local_store, utc_instant

@app.post("/reminders", response_model=schemas.ReminderResponse)
async def create_reminder(
    payload: schemas.ReminderCreate,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    _validate_reminder_time(payload.hour, payload.minute)
    now_utc = datetime.utcnow()
    # Apply default grace override if env set and payload omitted / zero
    try:
        default_grace_env = os.getenv("REMINDER_DEFAULT_GRACE")
        if default_grace_env is not None and (payload.grace_minutes is None or payload.grace_minutes == 0):
            g = int(default_grace_env)
            if g >= 0:
                object.__setattr__(payload, 'grace_minutes', g)
    except Exception:
        pass
    next_local, next_utc = _compute_next_local_utc(now_utc, payload.hour, payload.minute, payload.timezone)
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
        created_at=now_utc,
        updated_at=now_utc,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.get("/reminders", response_model=list[schemas.ReminderResponse])
async def list_reminders(db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id).order_by(models.Reminder.next_fire_utc.asc()))
    return res.scalars().all()

@app.get("/reminders/{reminder_id}", response_model=schemas.ReminderResponse)
async def get_reminder(reminder_id: int, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(
        select(models.Reminder).where(models.Reminder.id == reminder_id).where(models.Reminder.patient_id == current_user.id)
    )
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    return row

@app.patch("/reminders/{reminder_id}", response_model=schemas.ReminderResponse)
async def update_reminder(
    reminder_id: int,
    payload: schemas.ReminderUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    res = await db.execute(
        select(models.Reminder).where(models.Reminder.id == reminder_id).where(models.Reminder.patient_id == current_user.id)
    )
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    changed_time = False
    if payload.title is not None:
        object.__setattr__(row, 'title', payload.title)
    if payload.body is not None:
        object.__setattr__(row, 'body', payload.body)
    if payload.hour is not None:
        _validate_reminder_time(payload.hour, payload.minute if payload.minute is not None else object.__getattribute__(row, 'minute'))
        object.__setattr__(row, 'hour', payload.hour)
        changed_time = True
    if payload.minute is not None:
        _validate_reminder_time(object.__getattribute__(row, 'hour'), payload.minute)
        object.__setattr__(row, 'minute', payload.minute)
        changed_time = True
    if payload.timezone is not None:
        object.__setattr__(row, 'timezone', payload.timezone)
        changed_time = True
    if payload.active is not None:
        object.__setattr__(row, 'active', payload.active)
    if payload.grace_minutes is not None:
        object.__setattr__(row, 'grace_minutes', payload.grace_minutes)
    elif os.getenv("REMINDER_DEFAULT_GRACE_OVERRIDE_ON_UPDATE", "0").lower() in {"1","true","yes","on"}:
        # Optional force override on update when not explicitly provided
        try:
            g = int(os.getenv("REMINDER_DEFAULT_GRACE", ""))
            if g >= 0:
                object.__setattr__(row, 'grace_minutes', g)
        except Exception:
            pass
    if payload.ack_today:
        # Acknowledge local fire for today in user's timezone
        try:
            tz = pytz.timezone(object.__getattribute__(row, 'timezone'))
        except Exception:
            tz = pytz.UTC
        local_today = datetime.utcnow().replace(tzinfo=pytz.UTC).astimezone(tz).date()
        object.__setattr__(row, 'last_ack_local_date', local_today)
    if changed_time:
        nl, nu = _compute_next_local_utc(datetime.utcnow(), object.__getattribute__(row, 'hour'), object.__getattribute__(row, 'minute'), object.__getattribute__(row, 'timezone'))
        object.__setattr__(row, 'next_fire_local', nl)
        object.__setattr__(row, 'next_fire_utc', nu)
    object.__setattr__(row, 'updated_at', datetime.utcnow())
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.delete("/reminders/{reminder_id}")
async def delete_reminder(reminder_id: int, db: AsyncSession = Depends(get_db), current_user: models.Patient = Depends(get_current_user)):
    res = await db.execute(
        select(models.Reminder).where(models.Reminder.id == reminder_id).where(models.Reminder.patient_id == current_user.id)
    )
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    await db.delete(row)
    await db.commit()
    return {"deleted": reminder_id}

class SyncReminderItem(BaseModel):
    title: str
    body: str
    hour: int
    minute: int
    timezone: str
    active: bool
    grace_minutes: int
    # Optional server id if previously created
    id: Optional[int] = None

class ReminderSyncRequest(BaseModel):
    items: list[SyncReminderItem]
    # Whether to deactivate reminders that are not present in the sent snapshot.
    # Defaults to True to preserve the original "client snapshot is authoritative" behavior.
    # Clients that are only doing a best-effort upload should send false to avoid accidental data loss.
    prune_missing: bool = True

class ReminderSyncResponse(BaseModel):
    created: int
    updated: int
    deactivated: int
    total_active: int
    synced: list[schemas.ReminderResponse]

@app.post("/reminders/sync", response_model=ReminderSyncResponse)
async def sync_reminders(
    payload: ReminderSyncRequest,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    # Fetch existing
    res = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
    existing = {object.__getattribute__(r, 'id'): r for r in res.scalars().all()}  # type: ignore[arg-type]
    sent_ids = set()
    created = 0
    updated = 0
    now_utc = datetime.utcnow()
    for item in payload.items:
        _validate_reminder_time(item.hour, item.minute)
        if item.id and item.id in existing:
            row = existing[item.id]
            changed = False
            for fld in ("title","body","hour","minute","timezone","active","grace_minutes"):
                new_v = getattr(item, fld)
                if getattr(row, fld) != new_v:  # type: ignore[attr-defined]
                    object.__setattr__(row, fld, new_v)
                    changed = True
                    if fld in {"hour","minute","timezone"}:
                        # force recompute later
                        changed = True
            if changed:
                nl, nu = _compute_next_local_utc(now_utc, object.__getattribute__(row,'hour'), object.__getattribute__(row,'minute'), object.__getattribute__(row,'timezone'))
                object.__setattr__(row, 'next_fire_local', nl)
                object.__setattr__(row, 'next_fire_utc', nu)
                object.__setattr__(row, 'updated_at', now_utc)
                db.add(row)
                updated += 1
            sent_ids.add(item.id)
        else:
            nl, nu = _compute_next_local_utc(now_utc, item.hour, item.minute, item.timezone)
            # Apply default grace if not provided (or zero) and env set
            gm = item.grace_minutes
            try:
                if (gm is None or gm == 0) and os.getenv("REMINDER_DEFAULT_GRACE") is not None:
                    g = int(os.getenv("REMINDER_DEFAULT_GRACE", "0"))
                    if g >= 0:
                        gm = g
            except Exception:
                pass
            row = models.Reminder(
                patient_id=current_user.id,
                title=item.title,
                body=item.body,
                hour=item.hour,
                minute=item.minute,
                timezone=item.timezone,
                active=item.active,
                grace_minutes=gm,
                next_fire_local=nl,
                next_fire_utc=nu,
                created_at=now_utc,
                updated_at=now_utc,
            )
            db.add(row)
            created += 1
    # Deactivate any not present (soft deactivate rather than delete) iff prune_missing is enabled
    deactivated = 0
    if getattr(payload, 'prune_missing', True):
        current_ids = {object.__getattribute__(r,'id') for r in existing.values()}
        missing = current_ids - sent_ids
        for rid in missing:
            row = existing[rid]
            if object.__getattribute__(row,'active'):
                object.__setattr__(row,'active', False)
                object.__setattr__(row,'updated_at', now_utc)
                db.add(row)
                deactivated += 1
    await db.commit()
    # Return fresh list
    res2 = await db.execute(select(models.Reminder).where(models.Reminder.patient_id == current_user.id))
    all_rows = res2.scalars().all()
    active_count = sum(1 for r in all_rows if object.__getattribute__(r,'active'))
    return ReminderSyncResponse(created=created, updated=updated, deactivated=deactivated, total_active=active_count, synced=all_rows)  # type: ignore[arg-type]

class ReminderAckRequest(BaseModel):
    reminder_id: int

class ReminderAckResponse(BaseModel):
    acknowledged: bool
    reminder_id: int
    local_date: date

@app.post("/reminders/ack", response_model=ReminderAckResponse)
async def ack_reminder(
    payload: ReminderAckRequest,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    res = await db.execute(select(models.Reminder).where(models.Reminder.id == payload.reminder_id).where(models.Reminder.patient_id == current_user.id))
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    try:
        tz = pytz.timezone(object.__getattribute__(row,'timezone'))
    except Exception:
        tz = pytz.UTC
    local_today = datetime.utcnow().replace(tzinfo=pytz.UTC).astimezone(tz).date()
    object.__setattr__(row,'last_ack_local_date', local_today)
    object.__setattr__(row,'updated_at', datetime.utcnow())
    db.add(row)
    await db.commit()
    return ReminderAckResponse(acknowledged=True, reminder_id=payload.reminder_id, local_date=local_today)


# Compatibility endpoint for older clients/docs: acknowledge by path id and return updated reminder row.
@app.post("/reminders/{reminder_id}/ack", response_model=schemas.ReminderResponse)
async def ack_reminder_compat(
    reminder_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    res = await db.execute(
        select(models.Reminder)
        .where(models.Reminder.id == reminder_id)
        .where(models.Reminder.patient_id == current_user.id)
    )
    row = res.scalars().first()
    if not row:
        raise HTTPException(status_code=404, detail="Reminder not found")
    try:
        tz = pytz.timezone(object.__getattribute__(row, 'timezone'))
    except Exception:
        tz = pytz.UTC
    local_today = datetime.utcnow().replace(tzinfo=pytz.UTC).astimezone(tz).date()
    object.__setattr__(row, 'last_ack_local_date', local_today)
    object.__setattr__(row, 'updated_at', datetime.utcnow())
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row

@app.post("/reminders/reschedule-all")
async def reschedule_all_reminders(
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
):
    """Recompute next_fire_local/utc for all of the current user's reminders from now.
    Useful if timezones changed or after bulk edits. Returns count updated.
    """
    now_utc = datetime.utcnow()
    res = await db.execute(
        select(models.Reminder).where(models.Reminder.patient_id == current_user.id)
    )
    rows = res.scalars().all()
    updated = 0
    for r in rows:
        nl, nu = _compute_next_local_utc(now_utc, getattr(r, 'hour'), getattr(r, 'minute'), getattr(r, 'timezone'))
        object.__setattr__(r, 'next_fire_local', nl)
        object.__setattr__(r, 'next_fire_utc', nu)
        object.__setattr__(r, 'updated_at', now_utc)
        db.add(r)
        updated += 1
    if updated:
        await db.commit()
    return {"updated": updated}

@app.get("/reminders/debug")
async def reminders_debug(
    db: AsyncSession = Depends(get_db),
    current_user: models.Patient = Depends(get_current_user),
    limit: int = 100,
):
    """Return raw reminder timing fields for diagnostics.
    Not for production exposure without auth; uses patient auth context.
    """
    res = await db.execute(
        select(models.Reminder)
        .where(models.Reminder.patient_id == current_user.id)
        .order_by(models.Reminder.next_fire_utc.asc())
    )
    rows = res.scalars().all()
    out = []
    now = datetime.utcnow()
    for r in rows[:limit]:
        out.append({
            "id": object.__getattribute__(r,'id'),
            "title": object.__getattribute__(r,'title'),
            "hour": object.__getattribute__(r,'hour'),
            "minute": object.__getattribute__(r,'minute'),
            "tz": object.__getattribute__(r,'timezone'),
            "active": object.__getattribute__(r,'active'),
            "grace_minutes": object.__getattribute__(r,'grace_minutes'),
            "next_fire_local": object.__getattribute__(r,'next_fire_local').isoformat() if object.__getattribute__(r,'next_fire_local') else None,
            "next_fire_utc": object.__getattribute__(r,'next_fire_utc').isoformat() if object.__getattribute__(r,'next_fire_utc') else None,
            "last_ack_local_date": str(object.__getattribute__(r,'last_ack_local_date')) if object.__getattribute__(r,'last_ack_local_date') else None,
            "last_sent_utc": object.__getattribute__(r,'last_sent_utc').isoformat() if object.__getattribute__(r,'last_sent_utc') else None,
            "due": (object.__getattribute__(r,'next_fire_utc') <= now) if object.__getattribute__(r,'next_fire_utc') else False,
        })
    return {"now_utc": now.isoformat(), "reminders": out}