"""Authenticated Staff security-question rotation using password + Gmail OTP.

Uses the existing otps table (purpose='questions'). No new table or
migration is needed. No answer is ever returned or logged in plaintext.
"""

from datetime import datetime, timedelta, timezone
from math import ceil

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, SecretStr
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.otp import OTP
from app.models.staff_profile import StaffProfile
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.registration import validate_security_answer
from app.security.activity_logger import record_security_event
from app.security.email_service import send_otp_email
from app.security.email_notifications import audit_otp_sent
from app.security.otp import generate_otp, hash_otp, verify_otp
from app.security.password import hash_password, verify_password
from app.security.policy import (
    OTP_EXPIRY_MINUTES,
    OTP_MAX_ATTEMPTS,
    OTP_MAX_RESENDS,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_RESEND_WINDOW_MINUTES,
)

router = APIRouter(prefix="/settings/security-questions", tags=["Staff Settings"])
PURPOSE = "questions"  # Fits otps.purpose VARCHAR(20)


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def locked_staff(db: Session, authenticated: User) -> User:
    """Serialize modifications for a single authenticated Staff account."""
    user = (
        db.query(User)
        .filter(User.id == authenticated.id)
        .populate_existing()
        .with_for_update()
        .first()
    )
    if user is None or user.role != "staff" or not user.is_active:
        db.rollback()
        raise HTTPException(403, "Active Staff access required.")
    return user


class RequestCode(BaseModel):
    current_password: SecretStr


class ReplaceQuestions(BaseModel):
    otp_code: str = Field(pattern=r"^[0-9]{6}$")
    security_answer_q4: SecretStr
    security_answer_q7: SecretStr
    security_answer_q1: SecretStr


@router.post("/request-code")
def request_security_questions_code(
    data: RequestCode,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    user = locked_staff(db, current_user)
    now_local = datetime.now()
    locked_until = user.password_change_locked_until

    if locked_until is not None and locked_until > now_local:
        remaining = max(1, ceil((locked_until - now_local).total_seconds()))
        db.rollback()
        raise HTTPException(
            429,
            f"Too many incorrect password attempts. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)},
        )
    if locked_until is not None:
        user.password_change_attempts = 0
        user.password_change_locked_until = None

    if not verify_password(data.current_password.get_secret_value(), user.password):
        attempts = min(5, (user.password_change_attempts or 0) + 1)
        user.password_change_attempts = attempts
        record_security_event(
            db,
            event_type="security_questions_password_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=f"Incorrect current password for security questions; attempt {attempts}",
        )
        if attempts >= 5:
            user.password_change_locked_until = now_local + timedelta(seconds=60)
            db.commit()
            raise HTTPException(
                429,
                "Too many incorrect password attempts. Try again in 60 seconds.",
                headers={"Retry-After": "60"},
            )
        db.commit()
        raise HTTPException(400, "Current password is incorrect.")

    profile_exists = (
        db.query(StaffProfile.id).filter(StaffProfile.user_id == user.id).first()
    )
    if not profile_exists or not user.email:
        db.rollback()
        raise HTTPException(400, "This Staff account cannot update security questions.")

    now = utc_now()
    latest = (
        db.query(OTP)
        .filter(OTP.user_id == user.id, OTP.purpose == PURPOSE)
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )
    if latest is not None:
        elapsed = (now - latest.created_at).total_seconds()
        if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
            remaining = max(1, ceil(OTP_RESEND_COOLDOWN_SECONDS - elapsed))
            db.rollback()
            raise HTTPException(
                429,
                f"Please wait {remaining} seconds before requesting another code.",
                headers={"Retry-After": str(remaining)},
            )

    recent_count = (
        db.query(func.count(OTP.id))
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == PURPOSE,
            OTP.created_at >= now - timedelta(minutes=OTP_RESEND_WINDOW_MINUTES),
        )
        .scalar()
    ) or 0
    if recent_count >= OTP_MAX_RESENDS + 1:
        db.rollback()
        raise HTTPException(429, "Too many verification codes requested. Try again later.")

    for old in (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == PURPOSE,
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .all()
    ):
        old.cancelled_at = now

    code = generate_otp()
    entry = OTP(
        user_id=user.id,
        pending_registration_id=None,
        email=user.email,
        purpose=PURPOSE,
        code_hash=hash_otp(code),
        expires_at=now + timedelta(minutes=OTP_EXPIRY_MINUTES),
        attempts=0,
        resend_count=recent_count,
        resend_window_started_at=now,
        created_at=now,
    )
    db.add(entry)
    user.password_change_attempts = 0
    user.password_change_locked_until = None
    db.commit()

    try:
        sent = send_otp_email(user.email, code, PURPOSE, OTP_EXPIRY_MINUTES)
        if sent is False:
            raise RuntimeError("Gmail did not confirm delivery")
        audit_otp_sent(purpose="questions", request=request,
                       username=user.username, user_id=user.id)
    except Exception:
        db.rollback()
        entry.cancelled_at = utc_now()
        db.commit()
        raise HTTPException(503, "Unable to send verification code. Please try again later.") from None

    return {
        "message": "A verification code was sent to your registered Gmail address.",
        "otp_expires_in_seconds": OTP_EXPIRY_MINUTES * 60,
    }


@router.post("/update")
def update_security_questions(
    data: ReplaceQuestions,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    user = locked_staff(db, current_user)
    now = utc_now()
    entry = (
        db.query(OTP)
        .filter(OTP.user_id == user.id, OTP.purpose == PURPOSE)
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )
    if entry is None or entry.consumed_at is not None or entry.cancelled_at is not None:
        db.rollback()
        raise HTTPException(400, "No active verification code. Request a new code.")
    if entry.expires_at <= now:
        entry.cancelled_at = now
        db.commit()
        raise HTTPException(400, "Verification code expired. Request a new code.")
    if entry.attempts >= OTP_MAX_ATTEMPTS:
        entry.cancelled_at = now
        db.commit()
        raise HTTPException(429, "Too many incorrect verification attempts. Request a new code.")
    if not verify_otp(data.otp_code, entry.code_hash):
        entry.attempts += 1
        if entry.attempts >= OTP_MAX_ATTEMPTS:
            entry.cancelled_at = now
        record_security_event(
            db,
            event_type="security_questions_otp_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=f"Incorrect security-question update OTP; attempt {entry.attempts}",
        )
        db.commit()
        if entry.attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(429, "Too many incorrect verification attempts. Request a new code.")
        raise HTTPException(400, "Incorrect verification code.")

    # Use the same answer policy and normalization as Staff registration.
    answers = {}
    for label, value in (
        ("q4", data.security_answer_q4),
        ("q7", data.security_answer_q7),
        ("q1", data.security_answer_q1),
    ):
        try:
            normalized = validate_security_answer(value).get_secret_value().casefold()
        except ValueError as exc:
            db.rollback()
            raise HTTPException(422, str(exc)) from None
        answers[label] = normalized

    profile = (
        db.query(StaffProfile)
        .filter(StaffProfile.user_id == user.id)
        .with_for_update()
        .first()
    )
    if profile is None:
        db.rollback()
        raise HTTPException(400, "Staff registration profile is missing.")

    profile.security_answer_q4_hash = hash_password(answers["q4"])
    profile.security_answer_q7_hash = hash_password(answers["q7"])
    profile.security_answer_q1_hash = hash_password(answers["q1"])
    entry.consumed_at = now
    record_security_event(
        db,
        event_type="security_questions_updated",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Staff rotated all three security-question answer hashes via Gmail OTP",
    )
    db.commit()
    return {"message": "Security answers updated successfully."}
