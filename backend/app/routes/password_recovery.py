
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.otp import OTP
from app.security.otp import generate_otp, hash_otp
from app.security.email_service import send_otp_email
from app.security.policy import (
    OTP_EXPIRY_MINUTES,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_MAX_RESENDS,
    OTP_RESEND_WINDOW_MINUTES,
)

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/auth/password-recovery",
    tags=["Password Recovery"],
)


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class PasswordResetRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


@router.post("/request")
def request_password_reset(
    data: PasswordResetRequest,
    db: Session = Depends(get_db),
):
    # Same response for registered and unregistered addresses.
    message = {
        "message": (
            "If the email belongs to an eligible PeakGym account, "
            "a password reset code will be sent."
        )
    }

    email = data.email.strip().lower()
    now = utc_now()

    # Avoid resetting an ambiguous account if an email is duplicated.
    users = (
        db.query(User)
        .filter(func.lower(User.email) == email)
        .limit(2)
        .all()
    )

    if len(users) != 1 or not users[0].is_active:
        return message

    user = users[0]

    latest = (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "reset",
        )
        .order_by(OTP.id.desc())
        .first()
    )

    if latest is not None:
        elapsed = (now - latest.created_at).total_seconds()

        if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
            return message

    recent_count = (
        db.query(func.count(OTP.id))
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "reset",
            OTP.created_at >= now - timedelta(
                minutes=OTP_RESEND_WINDOW_MINUTES
            ),
        )
        .scalar()
    ) or 0

    if recent_count >= OTP_MAX_RESENDS + 1:
        return message

    # Invalidate previous unused reset codes.
    previous_otps = (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "reset",
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .all()
    )

    for previous in previous_otps:
        previous.cancelled_at = now

    code = generate_otp()

    otp = OTP(
        user_id=user.id,
        pending_registration_id=None,
        email=user.email,
        purpose="reset",
        code_hash=hash_otp(code),
        expires_at=now + timedelta(
            minutes=OTP_EXPIRY_MINUTES
        ),
        attempts=0,
        resend_count=recent_count,
        resend_window_started_at=now,
        created_at=now,
    )

    db.add(otp)
    db.commit()

    try:
        sent = send_otp_email(
            user.email,
            code,
            "reset",
            OTP_EXPIRY_MINUTES,
        )

        if sent is False:
            raise RuntimeError("Email delivery not confirmed.")

    except Exception:
        logger.exception("Password reset email delivery failed.")

        otp.cancelled_at = utc_now()
        db.commit()

    return message



# =========================================
# VERIFY AND COMPLETE PASSWORD RESET
# =========================================

from fastapi import HTTPException, Request
from pydantic import SecretStr

from app.security.otp import verify_otp
from app.security.password import (
    validate_password,
    hash_password,
    verify_password,
)
from app.security.policy import OTP_MAX_ATTEMPTS
from app.security.activity_logger import record_security_event


class PasswordResetVerifyRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    otp_code: str = Field(pattern=r"^[0-9]{6}$")


class PasswordResetCompleteRequest(PasswordResetVerifyRequest):
    new_password: SecretStr
    confirm_password: SecretStr


def _check_reset_code(
    db: Session,
    request: Request,
    email: str,
    code: str,
):
    """Validate and count incorrect reset-code attempts."""

    now = utc_now()
    generic = "Invalid or expired password reset code."

    users = (
        db.query(User)
        .filter(func.lower(User.email) == email)
        .limit(2)
        .with_for_update()
        .all()
    )

    if len(users) != 1 or not users[0].is_active:
        db.rollback()
        raise HTTPException(400, generic)

    user = users[0]

    otp = (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "reset",
        )
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )

    if (
        otp is None
        or otp.email.strip().lower() != email
        or otp.consumed_at is not None
        or otp.cancelled_at is not None
    ):
        db.rollback()
        raise HTTPException(400, generic)

    if otp.expires_at <= now:
        otp.cancelled_at = now

        record_security_event(
            db,
            event_type="password_reset_otp_expired",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details="Password reset code expired",
        )

        db.commit()
        raise HTTPException(400, generic)

    if otp.attempts >= OTP_MAX_ATTEMPTS:
        otp.cancelled_at = now
        db.commit()

        raise HTTPException(
            429,
            "Too many incorrect reset-code attempts.",
        )

    if not verify_otp(code, otp.code_hash):
        otp.attempts += 1

        record_security_event(
            db,
            event_type="password_reset_otp_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=(
                f"Incorrect password reset code "
                f"attempt {otp.attempts}"
            ),
        )

        if otp.attempts >= OTP_MAX_ATTEMPTS:
            otp.cancelled_at = now

            record_security_event(
                db,
                event_type="password_reset_otp_limit",
                request=request,
                user_id=user.id,
                username_typed=user.username,
                details="Password reset OTP attempt limit reached",
            )

        db.commit()

        if otp.attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(
                429,
                "Too many incorrect reset-code attempts.",
            )

        raise HTTPException(400, generic)

    return user, otp


# =========================================
# VERIFY RESET OTP
# =========================================

@router.post("/verify")
def verify_password_reset_code(
    data: PasswordResetVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    email = data.email.strip().lower()

    _check_reset_code(
        db,
        request,
        email,
        data.otp_code,
    )

    # Release database locks.
    # The code is checked again during password reset.
    db.rollback()

    return {
        "verified": True,
        "message": "Code verified. Choose a new password.",
    }


# =========================================
# COMPLETE PASSWORD RESET
# =========================================

@router.post("/complete")
def complete_password_reset(
    data: PasswordResetCompleteRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    email = data.email.strip().lower()

    # Verify the OTP again before changing the password.
    user, otp = _check_reset_code(
        db,
        request,
        email,
        data.otp_code,
    )

    new_password = data.new_password.get_secret_value()
    confirmation = data.confirm_password.get_secret_value()

    if new_password != confirmation:
        db.rollback()
        raise HTTPException(
            422,
            "New passwords do not match.",
        )

    valid, message = validate_password(new_password)

    if not valid:
        db.rollback()
        raise HTTPException(422, message)

    if verify_password(new_password, user.password):
        db.rollback()
        raise HTTPException(
            422,
            "Choose a password different from the current one.",
        )

    now = utc_now()

    # Update password using the existing secure hash function.
    user.password = hash_password(new_password)

    # Reset failed-login and password-change counters.
    user.failed_attempts = 0
    user.locked_until = None
    user.password_change_attempts = 0
    user.password_change_locked_until = None

    # Consume the OTP so it cannot be reused.
    otp.consumed_at = now

    record_security_event(
        db,
        event_type="password_reset_completed",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Password successfully reset using email verification",
    )

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(
            500,
            "Unable to update password.",
        ) from None

    return {
        "message": "Password updated. Sign in with the new password.",
    }
