from pydantic import BaseModel, EmailStr, ConfigDict
from datetime import datetime, date, time
from typing import Optional, List

class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class DoctorMasterLoginRequest(BaseModel):
    password: str

class PatientBase(BaseModel):
    name: str
    dob: date
    gender: str
    phone: str
    email: EmailStr
    username: str
    department: Optional[str] = None
    doctor: Optional[str] = None
    treatment: Optional[str] = None
    treatment_subtype: Optional[str] = None
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None
    procedure_completed: Optional[bool] = None

class PatientCreate(PatientBase):
    password: str

class PatientUpdate(BaseModel):
    phone: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    department: Optional[str] = None
    doctor: Optional[str] = None
    treatment: Optional[str] = None
    treatment_subtype: Optional[str] = None
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None
    procedure_completed: Optional[bool] = None

class Patient(BaseModel):
    id: int
    name: str
    dob: date
    gender: str
    phone: str
    email: EmailStr
    username: str
    password: str
    department: Optional[str] = None
    doctor: Optional[str] = None
    treatment: Optional[str] = None
    treatment_subtype: Optional[str] = None
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None
    procedure_completed: Optional[bool] = None
    model_config = ConfigDict(from_attributes=True)

class PatientPublic(BaseModel):
    id: int
    name: str
    dob: date
    gender: str
    phone: str
    email: EmailStr
    username: str
    department: Optional[str] = None
    doctor: Optional[str] = None
    treatment: Optional[str] = None
    treatment_subtype: Optional[str] = None
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None
    procedure_completed: Optional[bool] = None
    model_config = ConfigDict(from_attributes=True)

class DoctorBase(BaseModel):
    name: str
    specialty: str
    email: EmailStr

class DoctorCreate(DoctorBase):
    username: str
    password: str

class Doctor(DoctorBase):
    id: int
    username: str
    password: str
    model_config = ConfigDict(from_attributes=True)

class AppointmentBase(BaseModel):
    patient_id: int
    doctor_id: int
    appointment_time: datetime

class AppointmentCreate(AppointmentBase):
    pass

class Appointment(AppointmentBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

class FeedbackCreate(BaseModel):
    message: str

class FeedbackResponse(BaseModel):
    message: str
    status: str = "success"

class DoctorFeedbackCreate(BaseModel):
    patient_id: int
    message: str

class DoctorFeedback(BaseModel):
    id: int
    doctor_id: int
    patient_id: int
    message: str
    model_config = ConfigDict(from_attributes=True)

class ProgressCreate(BaseModel):
    message: str

class ProgressEntry(BaseModel):
    id: int
    message: str
    timestamp: datetime
    model_config = ConfigDict(from_attributes=True)


class ChatMessage(BaseModel):
    id: int
    patient_id: int
    sender_role: str
    sender_username: Optional[str] = None
    message: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class ChatMessageCreate(BaseModel):
    message: str


class DoctorChatMessageCreate(BaseModel):
    message: str

class InstructionStatusItem(BaseModel):
    date: date
    treatment: str
    subtype: Optional[str] = None
    group: str
    instruction_index: int
    instruction_text: str
    followed: bool
    # Sticky flag: once an instruction is followed at least once this stays true.
    ever_followed: Optional[bool] = None
    updated_at: Optional[datetime] = None

class InstructionStatusBulkCreate(BaseModel):
    items: List[InstructionStatusItem]

class InstructionStatusResponse(InstructionStatusItem):
    id: int
    patient_id: int
    model_config = ConfigDict(from_attributes=True)

class DailyInstructionSummary(BaseModel):
    date: date
    followed: int
    unfollowed: int
    total: int
    followed_ratio: float

class InstructionStatusExtended(InstructionStatusResponse):
    synthetic: bool = False  # True if server synthesized a placeholder (not currently populated, reserved)

class InstructionStatusFullResponse(BaseModel):
    patient: PatientPublic
    range: dict
    instructions: List[InstructionStatusExtended]
    daily_summary: List[DailyInstructionSummary]

# --- Enhanced materialized daily instruction log ---
class DayInstructionLog(BaseModel):
    date: date
    instructions: List[InstructionStatusExtended]
    followed_count: int
    unfollowed_count: int
    total: int
    followed_ratio: float

class InstructionStatusEnhancedResponse(BaseModel):
    patient: PatientPublic
    range: dict
    days: List[DayInstructionLog]
    generated_at: datetime

class DepartmentDoctorSelection(BaseModel):
    department: str
    doctor: str

class TreatmentInfoCreate(BaseModel):
    username: str
    treatment: str
    subtype: Optional[str] = None
    procedure_date: date
    procedure_time: time


class ReplaceTreatmentRequest(BaseModel):
    treatment: str
    subtype: Optional[str] = None
    procedure_date: date
    procedure_time: time

class TreatmentInfoResponse(BaseModel):
    id: int
    patient_id: int
    treatment: str
    subtype: Optional[str] = None
    procedure_date: date
    procedure_time: time
    model_config = ConfigDict(from_attributes=True)

class EpisodeBase(BaseModel):
    department: Optional[str] = None
    doctor: Optional[str] = None
    treatment: Optional[str] = None
    subtype: Optional[str] = None
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None

class EpisodeResponse(EpisodeBase):
    id: int
    patient_id: int
    procedure_completed: bool
    locked: bool
    model_config = ConfigDict(from_attributes=True)

class CurrentEpisodeResponse(BaseModel):
    id: int
    patient_id: int
    locked: bool
    procedure_completed: bool
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None
    model_config = ConfigDict(from_attributes=True)

class MarkCompleteRequest(BaseModel):
    procedure_completed: bool = True
    procedure_date: Optional[date] = None
    procedure_time: Optional[time] = None

class RotateIfDueResponse(BaseModel):
    rotated: bool
    new_episode_id: Optional[int] = None

# ---- Push Notifications ----
class DeviceRegisterRequest(BaseModel):
    platform: str  # 'android' | 'ios'
    token: str     # FCM device token

class DeviceTokenResponse(BaseModel):
    id: int
    platform: str
    token: str
    model_config = ConfigDict(from_attributes=True)

class PushTestRequest(BaseModel):
    title: str
    body: str

class ScheduledPushCreate(BaseModel):
    title: str
    body: str
    send_at: datetime  # ISO8601; expected UTC or with timezone

class ScheduledPushResponse(BaseModel):
    id: int
    patient_id: int
    title: str
    body: str
    send_at: datetime
    sent: bool
    sent_at: Optional[datetime] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

# ---- Hybrid Reminder Schemas ----
class ReminderBase(BaseModel):
    title: str
    body: str
    hour: int  # 0-23
    minute: int  # 0-59
    timezone: str  # IANA tz (e.g., 'Asia/Kolkata')
    active: bool = True
    grace_minutes: int = 20

class ReminderCreate(ReminderBase):
    pass

class ReminderUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    hour: Optional[int] = None
    minute: Optional[int] = None
    timezone: Optional[str] = None
    active: Optional[bool] = None
    grace_minutes: Optional[int] = None
    ack_today: Optional[bool] = None  # client can pass true to acknowledge local fire today

class ReminderResponse(ReminderBase):
    id: int
    next_fire_local: datetime
    next_fire_utc: datetime
    last_sent_utc: Optional[datetime] = None
    last_ack_local_date: Optional[date] = None
    created_at: datetime
    updated_at: datetime
    model_config = ConfigDict(from_attributes=True)