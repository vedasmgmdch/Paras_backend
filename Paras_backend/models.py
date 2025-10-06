from sqlalchemy import Column, Integer, String, Date, DateTime, ForeignKey, Boolean, Time
from sqlalchemy import Index
from sqlalchemy.orm import relationship
from datetime import datetime

from database import Base

# Secure password hashing
from passlib.context import CryptContext
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class Patient(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False, index=True)
    dob = Column(Date, nullable=False)
    gender = Column(String, nullable=False)
    phone = Column(String, unique=True, nullable=False)
    email = Column(String, unique=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    password = Column(String, nullable=False)
    department = Column(String, nullable=True)
    doctor = Column(String, nullable=True)
    treatment = Column(String, nullable=True)
    treatment_subtype = Column(String, nullable=True)
    procedure_date = Column(Date, nullable=True)
    procedure_time = Column(Time, nullable=True)
    procedure_completed = Column(Boolean, nullable=True, default=None)
    is_verified = Column(Boolean, default=False, nullable=False)

    appointments = relationship("Appointment", back_populates="patient", cascade="all, delete-orphan")
    feedbacks = relationship("Feedback", back_populates="patient", cascade="all, delete-orphan")
    doctor_feedbacks = relationship("DoctorFeedback", back_populates="patient", cascade="all, delete-orphan")
    progress_entries = relationship("Progress", back_populates="patient", cascade="all, delete-orphan")
    instruction_statuses = relationship("InstructionStatus", back_populates="patient", cascade="all, delete-orphan")
    episodes = relationship("TreatmentEpisode", back_populates="patient", cascade="all, delete-orphan")
    device_tokens = relationship("DeviceToken", back_populates="patient", cascade="all, delete-orphan")
    scheduled_pushes = relationship("ScheduledPush", back_populates="patient", cascade="all, delete-orphan")

    def set_password(self, raw_password):
        self.password = pwd_context.hash(raw_password)

    def verify_password(self, raw_password):
        if not isinstance(self.password, str):
            raise ValueError("Password attribute is not loaded or not a string.")
        return pwd_context.verify(raw_password, self.password)

class TreatmentEpisode(Base):
    __tablename__ = "treatment_episodes"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id", ondelete="CASCADE"), nullable=False, index=True)
    department = Column(String, nullable=True)
    doctor = Column(String, nullable=True)
    treatment = Column(String, nullable=True)
    subtype = Column(String, nullable=True)
    procedure_date = Column(Date, nullable=True)
    procedure_time = Column(Time, nullable=True)
    procedure_completed = Column(Boolean, default=False, nullable=False)
    locked = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    patient = relationship("Patient", back_populates="episodes")

class Doctor(Base):
    __tablename__ = "doctors"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False, index=True)
    specialty = Column(String, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    password = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)
    is_verified = Column(Boolean, default=False, nullable=False)
    appointments = relationship("Appointment", back_populates="doctor", cascade="all, delete-orphan")
    doctor_feedbacks = relationship("DoctorFeedback", back_populates="doctor", cascade="all, delete-orphan")

    def set_password(self, raw_password):
        self.password = pwd_context.hash(raw_password)

    def verify_password(self, raw_password):
        if not isinstance(self.password, str):
            raise ValueError("Password attribute is not loaded or not a string.")
        return pwd_context.verify(raw_password, self.password)

class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id", ondelete="CASCADE"), nullable=False, index=True)
    platform = Column(String, nullable=False)  # e.g., 'android', 'ios'
    token = Column(String, unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    patient = relationship("Patient", back_populates="device_tokens")

class Appointment(Base):
    __tablename__ = "appointments"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    doctor_id = Column(Integer, ForeignKey("doctors.id"), nullable=False)
    appointment_time = Column(DateTime, nullable=False)
    patient = relationship("Patient", back_populates="appointments")
    doctor = relationship("Doctor", back_populates="appointments")

class Feedback(Base):
    __tablename__ = "feedback"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    message = Column(String, nullable=False)
    patient = relationship("Patient", back_populates="feedbacks")

class DoctorFeedback(Base):
    __tablename__ = "doctor_feedback"
    id = Column(Integer, primary_key=True, index=True)
    doctor_id = Column(Integer, ForeignKey("doctors.id"), nullable=False)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    message = Column(String, nullable=False)
    doctor = relationship("Doctor", back_populates="doctor_feedbacks")
    patient = relationship("Patient", back_populates="doctor_feedbacks")

class Progress(Base):
    __tablename__ = "progress"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    message = Column(String, nullable=False)
    timestamp = Column(DateTime, default=datetime.utcnow)
    patient = relationship("Patient", back_populates="progress_entries")

class InstructionStatus(Base):
    __tablename__ = "instruction_status"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    date = Column(Date, nullable=False)
    treatment = Column(String, nullable=False)
    subtype = Column(String, nullable=True)
    group = Column(String, nullable=False)
    instruction_index = Column(Integer, nullable=False)
    instruction_text = Column(String, nullable=False)
    followed = Column(Boolean, default=False)
    # New: tracks if instruction was EVER followed at least once historically.
    # This value becomes sticky (once true it never reverts to false) and is
    # updated via upsert logic OR (existing, new.followed).
    ever_followed = Column(Boolean, default=False, nullable=False)
    patient = relationship("Patient", back_populates="instruction_statuses")

class ScheduledPush(Base):
    __tablename__ = "scheduled_pushes"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String, nullable=False)
    body = Column(String, nullable=False)
    send_at = Column(DateTime, nullable=False, index=True)  # stored as UTC
    sent = Column(Boolean, default=False, nullable=False)
    sent_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    patient = relationship("Patient", back_populates="scheduled_pushes")

# --- Hybrid reminder model (local + server fallback) ---
class Reminder(Base):
    __tablename__ = "reminders"
    __table_args__ = (
        # Composite index to speed due reminder scans per patient
        Index('ix_reminder_patient_due_active', 'patient_id', 'next_fire_utc', 'active'),
    )
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id", ondelete="CASCADE"), nullable=False, index=True)
    # Human readable content
    title = Column(String, nullable=False)
    body = Column(String, nullable=False)
    # Time fields
    hour = Column(Integer, nullable=False)          # 0-23 user local hour of day
    minute = Column(Integer, nullable=False)        # 0-59 user local minute
    timezone = Column(String, nullable=False)       # IANA tz name from device
    # Scheduling state
    active = Column(Boolean, default=True, nullable=False)
    next_fire_local = Column(DateTime, nullable=False, index=True)  # next local datetime in user's tz (stored naive or as UTC? we store UTC converted)
    next_fire_utc = Column(DateTime, nullable=False, index=True)    # cached UTC instant for dispatch comparison
    last_sent_utc = Column(DateTime, nullable=True)
    last_ack_local_date = Column(Date, nullable=True)  # date (in user tz) we received an acknowledgement to suppress fallback that day
    grace_minutes = Column(Integer, default=20, nullable=False)     # suppress push until grace window passes
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    patient = relationship("Patient")