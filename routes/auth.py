from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from pydantic import BaseModel, EmailStr
import random
from database import get_db
from models import Patient, Doctor

# In-memory store for OTPs (for demo; use DB or cache for production)
otp_store = {}

router = APIRouter()

# Minimal request schema for OTP endpoints
class RequestResetSchema(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None

class VerifyOtpSchema(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    otp: str

class ResetPasswordSchema(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    otp: str
    new_password: str

# --- Signup OTP Verification ---
class SignupOtpSchema(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    otp: str

# Request OTP for signup (after user registers, but before login)
@router.post("/auth/request-signup-otp")
async def request_signup_otp(data: RequestResetSchema, db: AsyncSession = Depends(get_db)):
    target = data.email or data.phone
    if not target:
        raise HTTPException(status_code=400, detail="Email or phone required.")
    # Find user by email or phone (check Patient then Doctor)
    user = None
    if data.email:
        stmt = select(Patient).where(Patient.email == data.email)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.email == data.email)
            result = await db.execute(stmt)
            user = result.scalars().first()
    else:
        stmt = select(Patient).where(Patient.phone == data.phone)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.phone == data.phone)
            result = await db.execute(stmt)
            user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    otp = str(random.randint(100000, 999999))
    otp_store[target] = otp
    try:
        if data.email:
            from utils import send_mailgun_email
            send_mailgun_email(data.email, "Your Signup OTP", f"Your signup OTP code is {otp}")
        else:
            print(f"Send SMS to {data.phone}: Signup OTP code is {otp}")
    except Exception as e:
        print(f"Failed to send signup OTP: {e}")
        raise HTTPException(status_code=500, detail="Failed to send OTP. Please try again later.")
    return {"message": "Signup OTP sent"}

# Verify signup OTP and set is_verified=True
@router.post("/auth/verify-signup-otp")
async def verify_signup_otp(data: SignupOtpSchema, db: AsyncSession = Depends(get_db)):
    target = data.email or data.phone
    if not target:
        raise HTTPException(status_code=400, detail="Email or phone required.")
    expected_otp = otp_store.get(target)
    if not expected_otp or data.otp != expected_otp:
        raise HTTPException(status_code=400, detail="Invalid OTP.")
    # Find user (check Patient then Doctor)
    user = None
    if data.email:
        stmt = select(Patient).where(Patient.email == data.email)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.email == data.email)
            result = await db.execute(stmt)
            user = result.scalars().first()
    else:
        stmt = select(Patient).where(Patient.phone == data.phone)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.phone == data.phone)
            result = await db.execute(stmt)
            user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    setattr(user, "is_verified", True)
    await db.commit()
    # Send registration email after successful verification
    try:
        if data.email:
            from utils import send_registration_email
            send_registration_email(data.email, getattr(user, 'name', 'User'))
    except Exception as e:
        print("Error sending registration email:", e)
    try:
        del otp_store[target]
    except Exception as e:
        print("Error deleting signup OTP:", e)
    return {"message": "Signup verified"}

@router.post("/auth/request-reset")
async def request_reset(data: RequestResetSchema, db: AsyncSession = Depends(get_db)):
    target = data.email or data.phone
    if not target:
        raise HTTPException(status_code=400, detail="Email or phone required.")

    # Find user by email or phone (check Patient then Doctor)
    user = None
    if data.email:
        stmt = select(Patient).where(Patient.email == data.email)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.email == data.email)
            result = await db.execute(stmt)
            user = result.scalars().first()
    else:
        stmt = select(Patient).where(Patient.phone == data.phone)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.phone == data.phone)
            result = await db.execute(stmt)
            user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    otp = str(random.randint(100000, 999999))
    otp_store[target] = otp

    # --- Send OTP via email or SMS here ---
    try:
        if data.email:
            from utils import send_mailgun_email
            send_mailgun_email(data.email, "Your OTP", f"Your OTP code is {otp}")
        else:
            print(f"Send SMS to {data.phone}: OTP code is {otp}")
    except Exception as e:
        print(f"Failed to send OTP: {e}")
        raise HTTPException(status_code=500, detail="Failed to send OTP. Please try again later.")

    return {"message": "OTP sent"}


# Step 1: Verify OTP only
@router.post("/auth/verify-otp")
async def verify_otp(data: VerifyOtpSchema):
    print("/auth/verify-otp called with:", data)
    target = data.email or data.phone
    if not target:
        raise HTTPException(status_code=400, detail="Email or phone required.")
    expected_otp = otp_store.get(target)
    print("Expected OTP:", expected_otp, "Provided OTP:", data.otp)
    if not expected_otp or data.otp != expected_otp:
        raise HTTPException(status_code=400, detail="Invalid OTP.")
    # Do not delete OTP yet; allow password reset
    return {"message": "OTP verified"}

# Step 2: Reset password (requires OTP)
@router.post("/auth/reset-password")
async def reset_password(data: ResetPasswordSchema, db: AsyncSession = Depends(get_db)):
    print("/auth/reset-password called with:", data)
    target = data.email or data.phone
    if not target:
        raise HTTPException(status_code=400, detail="Email or phone required.")
    expected_otp = otp_store.get(target)
    if not expected_otp or data.otp != expected_otp:
        raise HTTPException(status_code=400, detail="Invalid OTP.")
    # Find user (check Patient then Doctor)
    user = None
    if data.email:
        stmt = select(Patient).where(Patient.email == data.email)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.email == data.email)
            result = await db.execute(stmt)
            user = result.scalars().first()
    else:
        stmt = select(Patient).where(Patient.phone == data.phone)
        result = await db.execute(stmt)
        user = result.scalars().first()
        if not user:
            stmt = select(Doctor).where(Doctor.phone == data.phone)
            result = await db.execute(stmt)
            user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    try:
        user.set_password(data.new_password)
        await db.commit()
    except Exception as e:
        print("Error updating password:", e)
        raise HTTPException(status_code=500, detail="Failed to update password.")
    try:
        del otp_store[target]
    except Exception as e:
        print("Error deleting OTP:", e)
    return {"message": "Password reset successful"}