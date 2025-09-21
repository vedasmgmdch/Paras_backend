import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from dotenv import load_dotenv

# ✅ Load environment variables from .env file
load_dotenv()

# ✅ Read database connection details from environment
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")  # PostgreSQL default port
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

# ✅ Ensure all required variables are set
required_vars = [DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD]
if not all(required_vars):
    raise EnvironmentError(
        "⚠️ One or more required DB environment variables are missing. "
        "Check your .env file and ensure DB_HOST, DB_PORT, DB_NAME, DB_USER, and DB_PASSWORD are set."
    )

# ✅ Construct database URL for asyncpg
DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

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