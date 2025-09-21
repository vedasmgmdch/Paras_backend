from pydantic import BaseModel, EmailStr, ConfigDict
from datetime import datetime, date, time
from typing import Optional, List

class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

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

class InstructionStatusItem(BaseModel):
    date: date
    treatment: str
    subtype: Optional[str] = None
    group: str
    instruction_index: int
    instruction_text: str
    followed: bool

class InstructionStatusBulkCreate(BaseModel):
    items: List[InstructionStatusItem]

class InstructionStatusResponse(InstructionStatusItem):
    id: int
    patient_id: int
    model_config = ConfigDict(from_attributes=True)

class DepartmentDoctorSelection(BaseModel):
    department: str
    doctor: str

class TreatmentInfoCreate(BaseModel):
    username: str
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