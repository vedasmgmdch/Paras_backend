import os
import ssl
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from dotenv import load_dotenv

# ✅ Load environment variables from .env file
# Render mounts Secret Files at /etc/secrets/<filename> (commonly /etc/secrets/.env).
# Prefer an explicit DOTENV_PATH if provided, otherwise try Render's default location,
# and finally fall back to the local .env discovery behavior.
dotenv_path = os.getenv("DOTENV_PATH")
if dotenv_path and os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
elif os.path.exists("/etc/secrets/.env"):
    load_dotenv("/etc/secrets/.env")
else:
    load_dotenv()

def _normalize_asyncpg_url(url: str) -> str:
    # Neon and many providers provide postgres:// or postgresql://
    # SQLAlchemy asyncpg dialect expects postgresql+asyncpg://
    if url.startswith("postgresql+asyncpg://"):
        return url
    if url.startswith("postgres://"):
        return "postgresql+asyncpg://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        return "postgresql+asyncpg://" + url[len("postgresql://"):]
    return url

def _should_require_ssl(url: str) -> bool:
    try:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        qs = parse_qs(parsed.query or "")
        sslmode = (qs.get("sslmode", [""])[0] or "").lower()
        # Neon requires TLS; many guides include sslmode=require, but we also detect neon hosts.
        if sslmode in {"require", "verify-ca", "verify-full"}:
            return True
        if host.endswith(".neon.tech"):
            return True
    except Exception:
        pass
    return False

# ✅ Read database connection details from environment (PostgreSQL)
DATABASE_URL_ENV = os.getenv("DATABASE_URL") or os.getenv("NEON_DATABASE_URL")

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")  # PostgreSQL default port
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

# ✅ Prefer Postgres when DATABASE_URL is set or when all required vars are present.
connect_args = None

if DATABASE_URL_ENV:
    DATABASE_URL = _normalize_asyncpg_url(DATABASE_URL_ENV)
    if _should_require_ssl(DATABASE_URL):
        connect_args = {"ssl": ssl.create_default_context()}
    print("[DB] Using PostgreSQL via asyncpg (DATABASE_URL detected)")
else:
    use_postgres = all([DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD])
    if use_postgres:
        DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
        if (DB_HOST or "").lower().endswith(".neon.tech"):
            connect_args = {"ssl": ssl.create_default_context()}
        print("[DB] Using PostgreSQL via asyncpg (env vars detected)")
    else:
        # Fallback SQLite database next to this file (dev/test convenience)
        base_dir = Path(__file__).resolve().parent
        sqlite_path = base_dir / "test.db"
        DATABASE_URL = f"sqlite+aiosqlite:///{sqlite_path.as_posix()}"
        print(f"[DB] Using SQLite fallback at {sqlite_path} (Postgres env not set)")

# ✅ Create async SQLAlchemy engine
if connect_args:
    engine = create_async_engine(DATABASE_URL, echo=True, connect_args=connect_args)  # Set echo=False in production
else:
    engine = create_async_engine(DATABASE_URL, echo=True)  # Set echo=False in production

# ✅ Configure async session factory
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    expire_on_commit=False
)

# ✅ Base class for SQLAlchemy models
Base = declarative_base()

# ✅ Dependency for FastAPI routes to access DB session
from typing import AsyncGenerator

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session