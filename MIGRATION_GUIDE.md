# Database Migration Guide - Step by Step

## Easy Method: Using pgAdmin Export/Import

This is the easiest way to copy your entire database!

---

## Step 1: Export from OLD Database

### Connect to Old Database in pgAdmin:
- **Host:** `dpg-d21sveidbo4c73ejpmqg-a.oregon-postgres.render.com`
- **Port:** `5432`
- **Database:** `cloudbackend_mgm`
- **Username:** `cloud_localhost`
- **Password:** `RBOQNX1cfwU72X5YOhhgANrCDVvoasGj`

### Export Each Table:

1. **Right-click on `patients` table** → Import/Export → Export
   - Format: CSV
   - Header: Yes
   - Filename: `C:\temp\patients.csv`

2. **Repeat for all tables:**
   - `doctors` → `C:\temp\doctors.csv`
   - `treatment_episodes` → `C:\temp\treatment_episodes.csv`
   - `device_tokens` → `C:\temp\device_tokens.csv`
   - `progress` → `C:\temp\progress.csv`
   - `instruction_status` → `C:\temp\instruction_status.csv`
   - `reminders` → `C:\temp\reminders.csv`
   - `scheduled_pushes` → `C:\temp\scheduled_pushes.csv`
   - `appointments` → `C:\temp\appointments.csv`
   - `feedback` → `C:\temp\feedback.csv`
   - `doctor_feedback` → `C:\temp\doctor_feedback.csv`

---

## Step 2: Create Tables in NEW Database

### Connect to New Database in pgAdmin:
- **Host:** `dpg-d41qos0gjchc73b6pck0-a.oregon-postgres.render.com`
- **Port:** `5432`
- **Database:** `ninhubdb`
- **Username:** `ninhubdb_user` (NOT ninhubdb!)
- **Password:** `3L1LvbQqrOuoHHGI67zZjLqzId9NYvgK`

### Create Tables Automatically:

**Option A: Run Backend Once**
```powershell
cd MGM_backend
python -c "from database import engine; from models import Base; Base.metadata.create_all(bind=engine)"
```

**Option B: Let FastAPI Create Them**
- Just start your backend and it will auto-create tables on first run

---

## Step 3: Import to NEW Database

### Import Each Table in pgAdmin:

1. **Right-click on `patients` table** → Import/Export → Import
   - Format: CSV
   - Header: Yes
   - Filename: `C:\temp\patients.csv`
   - Click OK

2. **Repeat for all tables in this ORDER (important for foreign keys!):**
   - `doctors`
   - `patients`
   - `treatment_episodes`
   - `device_tokens`
   - `progress`
   - `instruction_status`
   - `reminders`
   - `scheduled_pushes`
   - `appointments`
   - `feedback`
   - `doctor_feedback`

---

## Step 4: Fix Auto-Increment Sequences

After importing, run this in the **Query Tool** of the new database:

```sql
-- Fix sequences so new records don't conflict with imported IDs
SELECT setval('patients_id_seq', (SELECT MAX(id) FROM patients));
SELECT setval('doctors_id_seq', (SELECT MAX(id) FROM doctors));
SELECT setval('treatment_episodes_id_seq', (SELECT MAX(id) FROM treatment_episodes));
SELECT setval('device_tokens_id_seq', (SELECT MAX(id) FROM device_tokens));
SELECT setval('progress_id_seq', (SELECT MAX(id) FROM progress));
SELECT setval('instruction_status_id_seq', (SELECT MAX(id) FROM instruction_status));
SELECT setval('reminders_id_seq', (SELECT MAX(id) FROM reminders));
SELECT setval('scheduled_pushes_id_seq', (SELECT MAX(id) FROM scheduled_pushes));
SELECT setval('appointments_id_seq', (SELECT MAX(id) FROM appointments));
SELECT setval('feedback_id_seq', (SELECT MAX(id) FROM feedback));
SELECT setval('doctor_feedback_id_seq', (SELECT MAX(id) FROM doctor_feedback));
```

---

## Step 5: Verify Migration

Run this query in the new database to check counts:

```sql
SELECT 'Patients' as table_name, COUNT(*) as count FROM patients
UNION ALL
SELECT 'Doctors', COUNT(*) FROM doctors
UNION ALL
SELECT 'Treatment Episodes', COUNT(*) FROM treatment_episodes
UNION ALL
SELECT 'Device Tokens', COUNT(*) FROM device_tokens
UNION ALL
SELECT 'Progress', COUNT(*) FROM progress
UNION ALL
SELECT 'Instruction Status', COUNT(*) FROM instruction_status
UNION ALL
SELECT 'Reminders', COUNT(*) FROM reminders
UNION ALL
SELECT 'Scheduled Pushes', COUNT(*) FROM scheduled_pushes
UNION ALL
SELECT 'Appointments', COUNT(*) FROM appointments
UNION ALL
SELECT 'Feedback', COUNT(*) FROM feedback
UNION ALL
SELECT 'Doctor Feedback', COUNT(*) FROM doctor_feedback;
```

Compare the counts with the old database to ensure everything copied!

---

## Alternative: Quick Dump & Restore Method

### From Command Line (Faster for large databases):

**Export from OLD database:**
```powershell
pg_dump "postgresql://cloud_localhost:RBOQNX1cfwU72X5YOhhgANrCDVvoasGj@dpg-d21sveidbo4c73ejpmqg-a.oregon-postgres.render.com:5432/cloudbackend_mgm" > backup.sql
```

**Import to NEW database:**
```powershell
psql "postgresql://ninhubdb_user:3L1LvbQqrOuoHHGI67zZjLqzId9NYvgK@dpg-d41qos0gjchc73b6pck0-a.oregon-postgres.render.com:5432/ninhubdb" < backup.sql
```

---

## Troubleshooting

### "relation does not exist"
- Tables haven't been created yet. Run backend first to create schema.

### "duplicate key value violates unique constraint"
- You're trying to import data that already exists. Clear the table first:
  ```sql
  TRUNCATE TABLE table_name CASCADE;
  ```

### "permission denied"
- Make sure you're using the correct username: `ninhubdb_user` not `ninhubdb`

### "password authentication failed"
- Double-check the password, ensure no extra spaces

---

## After Migration

1. Update your `.env` file with new database credentials
2. Update Render backend environment variables
3. Test the backend API
4. Test login from the Flutter app
5. Verify patients can see their old treatment data

---

**Created:** October 31, 2025
