import os
from pathlib import Path
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from dotenv import load_dotenv

# ✅ Load environment variables from .env file
load_dotenv()

# ✅ Read database connection details from environment (PostgreSQL)
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")  # PostgreSQL default port
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

# ✅ Prefer Postgres when all required vars are present; otherwise gracefully fall back to SQLite
use_postgres = all([DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD])

if use_postgres:
    DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    print("[DB] Using PostgreSQL via asyncpg (env vars detected)")
else:
    # Fallback SQLite database next to this file (dev/test convenience)
    base_dir = Path(__file__).resolve().parent
    sqlite_path = base_dir / "test.db"
    DATABASE_URL = f"sqlite+aiosqlite:///{sqlite_path.as_posix()}"
    print(f"[DB] Using SQLite fallback at {sqlite_path} (Postgres env not set)")

# ✅ Create async SQLAlchemy engine
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