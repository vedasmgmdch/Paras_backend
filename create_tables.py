import asyncio
import os

from sqlalchemy import text

from database import engine
# Import models so Base.metadata is populated
import models  # noqa: F401
from database import Base


async def main() -> None:
    print("[schema] Creating tables...")
    async with engine.begin() as conn:
        # Optional: Postgres schema sanity
        if engine.url.get_backend_name().startswith("postgresql"):
            await conn.execute(text("SELECT 1"))
        await conn.run_sync(Base.metadata.create_all)
    print("[schema] Done.")


if __name__ == "__main__":
    # Helpful reminder if user forgot env vars
    if not os.getenv("DB_HOST"):
        print("[schema] Note: DB_HOST not set; database.py will use SQLite fallback.")
    asyncio.run(main())
