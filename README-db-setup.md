# Database Reset / New Free Database Setup

This backend supports:
- **PostgreSQL** (recommended for production)
- **SQLite** fallback (local dev only)

Your `database.py` will use Postgres if these env vars exist:
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`

Otherwise it falls back to a local file `test.db`.

## Recommended Free Postgres (2026)
A solid free option is **Neon** (serverless Postgres). Create a project there and copy the connection values.

## 1) Put Postgres credentials in `.env`
Create a file named `.env` in the project root with:

```
DB_HOST=YOUR_HOST
DB_PORT=5432
DB_NAME=YOUR_DB
DB_USER=YOUR_USER
DB_PASSWORD=YOUR_PASSWORD
```

### If Neon gives you a connection string (recommended)
Neon typically provides a single connection string. You can paste it into `.env` as:

```
DATABASE_URL=postgresql://USER:PASSWORD@HOST/DB?sslmode=require
```

This repo supports `DATABASE_URL` (and will automatically enable SSL for Neon).

> You do **not** need to run `npx neonctl@latest init` for this backend unless you specifically want to use Neon’s CLI tooling.

## 2) One-time command to recreate ALL tables
Run this once (PowerShell):

```
cd "c:\Users\paras\OneDrive\Documents\Paras_backend"
C:/Users/paras/OneDrive/Documents/Paras_backend/.venv/Scripts/python.exe -m pip install -r requirements.txt
C:/Users/paras/OneDrive/Documents/Paras_backend/.venv/Scripts/python.exe create_tables.py
```

This runs SQLAlchemy `Base.metadata.create_all()` against your configured DB and recreates:
- patients, doctors
- treatment_episodes (episode history is preserved forever)
- instruction_status, progress, chat_messages
- reminders, scheduled_pushes, device_tokens
- and all other models in `models.py`

## 3) Verify tables exist
If you use Postgres, your provider’s dashboard should show the tables after step (2).

## Notes
- If you accidentally run against SQLite, `create_tables.py` will print a warning and create `test.db` locally.
- This creates schema only (tables/indexes/constraints). It will not restore old data from an expired DB.
