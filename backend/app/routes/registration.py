"""PeakGym staff registration: CAPTCHA, username check, and OTP initiation.

This stage does not activate accounts. Final registration/activation must add
approved gym-specific fields and the instructor-required ID-key migration.
"""

import hashlib
import json
import re
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.invitation import StaffInvitation
from app.models.otp import OTP
from app.models.pending_registration import PendingStaffRegistration
from app.models.user import User
from app.schemas.registration import StaffRegistrationRequest
from app.security.captcha import create_captcha_challenge
from app.security.activity_logger import record_security_event
from app.security.recaptcha_v2 import verify_recaptcha_v2
from app.security.email_service import send_otp_email
from app.security.email_notifications import audit_otp_sent
from app.security.encryption import encrypt_sensitive_data
from app.security.otp import generate_otp, hash_otp, verify_otp
from app.security.password import hash_password, validate_password
from app.security.policy import OTP_EXPIRY_MINUTES, OTP_MAX_ATTEMPTS


router = APIRouter(prefix="/registration", tags=["Staff Registration"])


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class RegistrationStartRequest(StaffRegistrationRequest):
    recaptcha_token: str = Field(min_length=20, max_length=8192)


@router.get("/captcha")
def get_registration_captcha(db: Session = Depends(get_db)):
    return create_captcha_challenge(db)


@router.get("/check-username")
def check_registration_username(
    username: str = Query(..., min_length=6, max_length=19),
    db: Session = Depends(get_db),
):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", username):
        return {
            "available": False,
            "message": "Username must start with a letter and contain letters and numbers only.",
        }

    existing = db.query(User.id).filter(
        func.lower(User.username) == username.lower()
    ).first()
    if existing:
        return {"available": False, "message": "This username is already taken."}

    pending = db.query(PendingStaffRegistration.id).filter(
        func.lower(PendingStaffRegistration.username) == username.lower(),
        PendingStaffRegistration.status == "pending",
        PendingStaffRegistration.expires_at > utc_now(),
    ).first()
    if pending:
        return {"available": False, "message": "This username is currently unavailable."}

    return {"available": True, "message": "Username is available."}


@router.post("/start", status_code=201)
def start_staff_registration(
    data: RegistrationStartRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    # Reject filled honeypot silently: no invitation lookup, database writes,
    # OTP creation, or Gmail delivery. Normal registrations send an empty value.
    if data.website:
        return JSONResponse(status_code=200, content={"message": "Request received."})

    # Google enforces v2 token expiry and single-use server-side.
    if not verify_recaptcha_v2(data.recaptcha_token):
        record_security_event(
            db, event_type="captcha_failed", request=request,
            username_typed=data.username, details="Registration reCAPTCHA rejected",
        )
        db.commit()
        raise HTTPException(400, "reCAPTCHA verification failed. Check the box again.")

    now = utc_now()
    invitation_hash = hashlib.sha256(
        data.invitation_token.encode("utf-8")
    ).hexdigest()

    # Lock invitation row to serialize parallel submissions for this token.
    invitation = (
        db.query(StaffInvitation)
        .filter(StaffInvitation.token_hash == invitation_hash)
        .with_for_update()
        .first()
    )
    if (
        invitation is None
        or invitation.revoked_at is not None
        or invitation.accepted_at is not None
        or invitation.expires_at <= now
    ):
        db.rollback()
        raise HTTPException(400, "Invalid or expired invitation.")

    email = invitation.invited_email.strip().lower()
    username = data.username.strip()
    if db.query(User.id).filter(
        (func.lower(User.username) == username.lower())
        | (func.lower(User.email) == email)
    ).first():
        db.rollback()
        raise HTTPException(409, "Account information is unavailable.")

    if db.query(PendingStaffRegistration.id).filter(
        PendingStaffRegistration.invitation_id == invitation.id,
        PendingStaffRegistration.status == "pending",
        PendingStaffRegistration.expires_at > now,
    ).first():
        db.rollback()
        raise HTTPException(409, "An active registration already exists for this invitation.")

    if db.query(PendingStaffRegistration.id).filter(
        func.lower(PendingStaffRegistration.username) == username.lower(),
        PendingStaffRegistration.status == "pending",
        PendingStaffRegistration.expires_at > now,
    ).first():
        db.rollback()
        raise HTTPException(409, "Account information is unavailable.")

    recent_attempts = db.query(PendingStaffRegistration.id).filter(
        PendingStaffRegistration.invitation_id == invitation.id,
        PendingStaffRegistration.created_at >= now - timedelta(minutes=15),
    ).count()
    if recent_attempts >= 3:
        db.rollback()
        raise HTTPException(429, "Too many registration attempts. Try again later.")

    password = data.password.get_secret_value()
    password_ok, password_message = validate_password(password)
    if not password_ok:
        db.rollback()
        raise HTTPException(422, password_message)

    # No plaintext password or question answers go into the encrypted JSON.
    personal_data = data.model_dump(
        mode="json",
        exclude={
            "invitation_token", "password", "confirm_password",
            "security_answer_q4", "security_answer_q7", "security_answer_q1",
            "recaptcha_token", "website",
        },
    )
    personal_data["security_answer_q4_hash"] = hash_password(
        data.security_answer_q4.get_secret_value().strip().casefold()
    )
    personal_data["security_answer_q7_hash"] = hash_password(
        data.security_answer_q7.get_secret_value().strip().casefold()
    )
    personal_data["security_answer_q1_hash"] = hash_password(
        data.security_answer_q1.get_secret_value().strip().casefold()
    )

    registration_token = secrets.token_urlsafe(32)
    otp_code = generate_otp()

    pending = PendingStaffRegistration(
        invitation_id=invitation.id,
        registration_token_hash=hashlib.sha256(
            registration_token.encode("utf-8")
        ).hexdigest(),
        email=email,
        username=username,
        password_hash=hash_password(password),
        encrypted_registration_data=encrypt_sensitive_data(
            json.dumps(personal_data), context="staff-registration"
        ),
        status="pending",
        created_at=now,
        expires_at=min(now + timedelta(minutes=15), invitation.expires_at),
    )

    # Cancel superseded registration OTPs for the invited email.
    previous_otps = (
        db.query(OTP)
        .filter(
            OTP.email == email,
            OTP.purpose == "register",
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .with_for_update()
        .all()
    )
    for previous in previous_otps:
        previous.cancelled_at = now


    try:
        # Save the pending registration to obtain its database ID.
        db.add(pending)
        db.flush()

        # The OTP is now linked to the correct pending registration.
        new_otp = OTP(
            user_id=None,
            pending_registration_id=pending.id,
            email=email,
            purpose="register",
            code_hash=hash_otp(otp_code),
            expires_at=now + timedelta(minutes=OTP_EXPIRY_MINUTES),
            attempts=0,
            resend_count=0,
            resend_window_started_at=now,
            created_at=now,
        )

        db.add(new_otp)
        record_security_event(
            db, event_type="registered", request=request,
            username_typed=username, details="Pending invited Staff registration created",
        )
        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(
            500,
            "Unable to start registration."
        ) from None


    try:
        accepted = send_otp_email(email, otp_code, "register", OTP_EXPIRY_MINUTES)
        if accepted is False:
            raise RuntimeError("Gmail did not confirm registration OTP email")
        audit_otp_sent(purpose="register", request=request,
                       username=username, user_id=None)
    except Exception:
        # An email transport error has uncertain delivery status. Disable this
        # attempt and require a fresh CAPTCHA and a new start request.
        try:
            pending.status = "cancelled"
            new_otp.cancelled_at = utc_now()
            db.commit()
        except Exception:
            db.rollback()
        raise HTTPException(503, "Could not submit OTP email. Please try later.") from None

    return {
        "message": "Registration started. Check the invited email for a verification code.",
        "registration_token": registration_token,
        "otp_expires_in_seconds": OTP_EXPIRY_MINUTES * 60,
        "registration_expires_at": pending.expires_at.isoformat(),
    }


class RegistrationVerifyOTPRequest(BaseModel):
    registration_token: str = Field(min_length=32, max_length=256)
    otp_code: str = Field(pattern=r"^[0-9]{6}$")


@router.post("/verify-otp")
def verify_registration_otp(
    data: RegistrationVerifyOTPRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Confirm email ownership for a pending staff registration.

    Does NOT create a staff account. Account activation will be added only
    after the approved gym fields and student-ID primary-key design are ready.
    """
    now = utc_now()
    reference_hash = hashlib.sha256(
        data.registration_token.encode("utf-8")
    ).hexdigest()

    # The token acts as a private capability; do not reveal whether it exists.
    pending = (
        db.query(PendingStaffRegistration)
        .filter(PendingStaffRegistration.registration_token_hash == reference_hash)
        .with_for_update()
        .first()
    )
    if pending is None or pending.status != "pending" or pending.expires_at <= now:
        db.rollback()
        raise HTTPException(400, "Invalid or expired registration reference.")

    invitation = (
        db.query(StaffInvitation)
        .filter(StaffInvitation.id == pending.invitation_id)
        .with_for_update()
        .first()
    )
    if (
        invitation is None
        or invitation.revoked_at is not None
        or invitation.accepted_at is not None
        or invitation.expires_at <= now
        or invitation.invited_email.strip().lower() != pending.email.lower()
    ):
        db.rollback()
        raise HTTPException(400, "Invalid or expired registration reference.")

    # Find the latest eligible registration OTP for this invitation's email.
    # Existing schema ties registration OTPs to the email, not pending ID.
    otp = (
        db.query(OTP)
        .filter(
            OTP.pending_registration_id == pending.id,
            OTP.email == pending.email,
            OTP.purpose == "register",
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )

    if otp is None or otp.expires_at <= now:
        db.rollback()
        raise HTTPException(400, "Invalid or expired verification code.")

    if otp.attempts >= OTP_MAX_ATTEMPTS:
        otp.cancelled_at = now
        record_security_event(
            db,
            event_type="registration_otp_limit",
            request=request,
            username_typed=pending.username,
            details="Staff registration OTP attempt limit reached",
        )
        db.commit()
        raise HTTPException(429, "Too many incorrect verification attempts.")

    if not verify_otp(data.otp_code, otp.code_hash):
        otp.attempts += 1
        record_security_event(
            db,
            event_type="registration_otp_failed",
            request=request,
            username_typed=pending.username,
            details=f"Incorrect staff registration OTP; attempt {otp.attempts}",
        )
        reached_limit = otp.attempts >= OTP_MAX_ATTEMPTS
        if reached_limit:
            otp.cancelled_at = now
            record_security_event(
                db,
                event_type="registration_otp_limit",
                request=request,
                username_typed=pending.username,
                details="Staff registration OTP attempt limit reached",
            )
        db.commit()
        if reached_limit:
            raise HTTPException(429, "Too many incorrect verification attempts.")
        raise HTTPException(400, "Invalid or expired verification code.")

    # Make consumption and verification one atomic database transaction.
    otp.consumed_at = now
    pending.status = "verified"
    pending.verified_at = now
    record_security_event(
        db, event_type="account_verified", request=request,
        username_typed=pending.username, details="Staff registration Gmail OTP verified",
    )
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to confirm registration.") from None

    return {
        "message": "Email OTP verified. Registration is awaiting account activation.",
        "email_verified": True,
        "account_activated": False,
    }


# ==============================================
# RESEND STAFF REGISTRATION OTP
# ==============================================

from datetime import timedelta
from pydantic import BaseModel, Field

from app.models.otp import OTP
from app.models.invitation import StaffInvitation
from app.security.otp import generate_otp, hash_otp
from app.security.email_service import send_otp_email
from app.security.policy import (
    OTP_EXPIRY_MINUTES,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_MAX_RESENDS,
    OTP_RESEND_WINDOW_MINUTES,
)


class RegistrationResendOTPRequest(BaseModel):
    registration_token: str = Field(
        min_length=32,
        max_length=256
    )


@router.post("/resend-otp")
def resend_registration_otp(
    data: RegistrationResendOTPRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    import hashlib

    now = utc_now()

    token_hash = hashlib.sha256(
        data.registration_token.encode("utf-8")
    ).hexdigest()

    pending = (
        db.query(PendingStaffRegistration)
        .filter(
            PendingStaffRegistration.registration_token_hash
            == token_hash
        )
        .with_for_update()
        .first()
    )

    if (
        pending is None
        or pending.status != "pending"
        or pending.expires_at <= now
    ):
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired registration reference."
        )

    invitation = (
        db.query(StaffInvitation)
        .filter(
            StaffInvitation.id == pending.invitation_id
        )
        .with_for_update()
        .first()
    )

    if (
        invitation is None
        or invitation.revoked_at is not None
        or invitation.accepted_at is not None
        or invitation.expires_at <= now
        or invitation.invited_email.strip().lower()
        != pending.email.strip().lower()
    ):
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired registration reference."
        )

    latest_otp = (
        db.query(OTP)
        .filter(
            OTP.pending_registration_id == pending.id,
            OTP.email == pending.email,
            OTP.purpose == "register",
        )
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )

    if latest_otp is None:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Registration OTP was not found."
        )

    if latest_otp.consumed_at is not None:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Registration OTP was already used."
        )

    elapsed = (now - latest_otp.created_at).total_seconds()

    if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
        remaining = max(
            1,
            int(OTP_RESEND_COOLDOWN_SECONDS - elapsed + 0.999)
        )

        db.rollback()
        raise HTTPException(
            status_code=429,
            detail=f"Please wait {remaining} seconds before resending."
        )

    window_start = now - timedelta(
        minutes=OTP_RESEND_WINDOW_MINUTES
    )

    if (
        latest_otp.resend_window_started_at is not None
        and latest_otp.resend_window_started_at > window_start
    ):
        resend_count = latest_otp.resend_count
        resend_window_start = latest_otp.resend_window_started_at
    else:
        resend_count = 0
        resend_window_start = now

    if resend_count >= OTP_MAX_RESENDS:
        db.rollback()
        raise HTTPException(
            status_code=429,
            detail="Maximum OTP resends reached. Try again later."
        )

    new_code = generate_otp()
    db.add(pending)
    db.flush()

    new_otp = OTP(
        user_id=None,
        pending_registration_id=pending.id,
        email=pending.email,
        purpose="register",
        code_hash=hash_otp(new_code),
        expires_at=now + timedelta(
            minutes=OTP_EXPIRY_MINUTES
        ),
        attempts=0,
        resend_count=resend_count + 1,
        resend_window_started_at=resend_window_start,
        created_at=now,
    )

    if latest_otp.consumed_at is None:
        latest_otp.cancelled_at = now

    db.add(new_otp)

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Could not create a new verification code."
        ) from None

    try:
        accepted = send_otp_email(
            pending.email,
            new_code,
            "register",
            OTP_EXPIRY_MINUTES,
        )
        if accepted is False:
            raise RuntimeError("Gmail did not confirm registration OTP resend")
        audit_otp_sent(purpose="register resend", request=request,
                       username=pending.username, user_id=None)
    except Exception:
        try:
            new_otp.cancelled_at = utc_now()
            db.commit()
        except Exception:
            db.rollback()

        raise HTTPException(
            status_code=503,
            detail="Unable to submit verification email."
        ) from None

    return {
        "message": "A new verification code was submitted.",
        "otp_expires_in_seconds": OTP_EXPIRY_MINUTES * 60,
        "resends_used": resend_count + 1,
        "maximum_resends": OTP_MAX_RESENDS,
    }
