"""Server-enforced password recovery: CAPTCHA -> question -> Gmail OTP -> reset.

This module reuses the existing otps table for short-lived recovery proofs;
no database migration is required for this phase.
"""

import hashlib
import hmac
import logging
import secrets
from datetime import datetime, timedelta, timezone
from math import ceil

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from pydantic import BaseModel, Field, SecretStr
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.otp import OTP
from app.models.staff_profile import StaffProfile
from app.models.user import User
from app.models.user_session import UserSession
from app.security.activity_logger import record_security_event
from app.security.recaptcha_v2 import verify_recaptcha_v2
from app.security.email_service import send_otp_email
from app.security.email_notifications import audit_otp_sent, send_password_changed_notice
from app.security.login_alerts import send_login_lockout_alert
from app.security.otp import generate_otp, hash_otp, verify_otp
from app.security.password import validate_password, verify_password
from app.security.password_history import (
    REUSE_ERROR,
    is_recent_password,
    set_password_with_history,
)
from app.security.policy import (
    LOCKOUT_TIERS,
    OTP_EXPIRY_MINUTES,
    OTP_MAX_ATTEMPTS,
    OTP_MAX_RESENDS,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_RESEND_WINDOW_MINUTES,
)
from app.security.token import ALGORITHM, SECRET_KEY

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth/password-recovery", tags=["Password Recovery"])

# These match the three questions shown in the existing Staff registration form.
QUESTIONS = (
    {"id": 4, "text": "Mother's maiden first name"},
    {"id": 7, "text": "Elementary school name"},
    {"id": 1, "text": "First pet name"},
)
GATE_PURPOSE = "reset_gate"  # Fits otps.purpose VARCHAR(20).
GATE_MINUTES = 10
IDENTIFY_MINUTES = 5
GENERIC_ANSWER_ERROR = "Unable to verify the security answer."
GENERIC_OTP_ERROR = "Invalid or expired password reset code."


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _proof_hash(proof: str) -> str:
    return hmac.new(
        SECRET_KEY.encode("utf-8"),
        proof.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _check_ticket(ticket: str) -> str:
    try:
        claims = jwt.decode(ticket, SECRET_KEY, algorithms=[ALGORITHM])
        if claims.get("purpose") != "recovery_identify":
            raise ValueError("Incorrect ticket purpose")
        username = claims.get("username")
        if not isinstance(username, str) or not username:
            raise ValueError("Invalid username")
        return username
    except (jwt.InvalidTokenError, ValueError) as exc:
        raise HTTPException(400, "Recovery step expired. Start again.") from exc


def _check_gate(db: Session, proof: str, username: str):
    if len(proof) < 32 or len(proof) > 256:
        raise HTTPException(400, "Recovery verification expired. Start again.")

    gate = (
        db.query(OTP)
        .filter(
            OTP.purpose == GATE_PURPOSE,
            OTP.code_hash == _proof_hash(proof),
        )
        .with_for_update()
        .first()
    )
    if (
        gate is None
        or gate.consumed_at is not None
        or gate.cancelled_at is not None
        or gate.expires_at <= utc_now()
    ):
        db.rollback()
        raise HTTPException(400, "Recovery verification expired. Start again.")

    user = (
        db.query(User)
        .filter(User.id == gate.user_id, User.username == username)
        .with_for_update()
        .first()
    )
    if user is None or not user.is_active:
        db.rollback()
        raise HTTPException(400, "Recovery verification expired. Start again.")
    # Existing account lockouts apply to every recovery step as well.
    local_now = datetime.now()
    if user.locked_until is not None and user.locked_until > local_now:
        remaining = max(1, ceil((user.locked_until - local_now).total_seconds()))
        db.rollback()
        raise HTTPException(
            429,
            f"Too many failed attempts. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)},
        )
    return user, gate


class IdentifyRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    recaptcha_token: str = Field(min_length=20, max_length=8192)


@router.post("/identify")
def identify_account(
    data: IdentifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    if not verify_recaptcha_v2(data.recaptcha_token):
        record_security_event(
            db, event_type="captcha_failed", request=request,
            username_typed=data.username, details="Password recovery reCAPTCHA rejected",
        )
        db.commit()
        raise HTTPException(400, "reCAPTCHA verification failed. Check the box again.")

    # Do not disclose whether a username exists. The question list is fixed by
    # the instructor seed, and the ticket is safe even for unknown usernames.
    username = data.username.strip()
    record_security_event(
        db, event_type="reset_requested", request=request,
        username_typed=username, details="Password recovery identification requested",
    )
    db.commit()
    ticket = jwt.encode(
        {
            "purpose": "recovery_identify",
            "username": username,
            "jti": secrets.token_urlsafe(16),
            "exp": datetime.now(timezone.utc) + timedelta(minutes=IDENTIFY_MINUTES),
        },
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    return {
        "recovery_ticket": ticket,
        "questions": list(QUESTIONS),
        "message": "Choose one of your registration questions and confirm the answer.",
    }


class AnswerRequest(BaseModel):
    recovery_ticket: str = Field(min_length=20, max_length=2048)
    question_id: int
    answer: SecretStr
    confirm_answer: SecretStr


@router.post("/answer")
def verify_security_answer(
    data: AnswerRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    username = _check_ticket(data.recovery_ticket)
    answer = data.answer.get_secret_value().strip().casefold()
    confirmation = data.confirm_answer.get_secret_value().strip().casefold()

    if not answer or answer != confirmation:
        raise HTTPException(422, "Your Answer and Re-enter Answer must match.")
    if data.question_id not in (4, 7, 1) or len(answer) > 50:
        raise HTTPException(400, GENERIC_ANSWER_ERROR)

    user = db.query(User).filter(User.username == username).with_for_update().first()
    if user is None or not user.is_active:
        db.rollback()
        raise HTTPException(400, GENERIC_ANSWER_ERROR)

    # Same counters and lockout periods as failed login passwords.
    local_now = datetime.now()
    if user.locked_until is not None and user.locked_until > local_now:
        remaining = max(1, ceil((user.locked_until - local_now).total_seconds()))
        db.rollback()
        raise HTTPException(
            429,
            f"Too many failed attempts. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)},
        )

    profile = db.query(StaffProfile).filter(StaffProfile.user_id == user.id).first()
    stored = None
    if profile is not None:
        stored = {
            4: profile.security_answer_q4_hash,
            7: profile.security_answer_q7_hash,
            1: profile.security_answer_q1_hash,
        }.get(data.question_id)

    # Accounts without registered answers, including legacy admins, do not
    # bypass this verification. Admin enrollment must be handled separately.
    if stored is None or not verify_password(answer, stored):
        user.failed_attempts = (user.failed_attempts or 0) + 1
        failures = user.failed_attempts
        lock_seconds = next((secs for n, secs in LOCKOUT_TIERS if n == failures), 0)
        if failures >= LOCKOUT_TIERS[-1][0]:
            lock_seconds = LOCKOUT_TIERS[-1][1]
        user.locked_until = (
            local_now + timedelta(seconds=lock_seconds) if lock_seconds else None
        )
        record_security_event(
            db,
            event_type="password_recovery_answer_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=f"Failed security question attempt; account failures={failures}",
        )
        if failures in (3, 6, 9) and lock_seconds:
            record_security_event(
                db,
                event_type="account_locked",
                request=request,
                user_id=user.id,
                username_typed=user.username,
                details=f"Security question failures contributed to lockout {lock_seconds}s",
            )
        db.commit()
        if failures in (3, 6, 9) and lock_seconds:
            background_tasks.add_task(
                send_login_lockout_alert,
                email=user.email,
                username=user.username,
                attempts=failures,
                lockout_seconds=lock_seconds,
                user_id=user.id,
                ip_address=request.client.host if request.client else None,
                user_agent=request.headers.get("user-agent", ""),
            )
        if lock_seconds:
            raise HTTPException(
                429,
                f"Too many failed attempts. Try again in {lock_seconds} seconds.",
                headers={"Retry-After": str(lock_seconds)},
            )
        raise HTTPException(400, GENERIC_ANSWER_ERROR)

    now = utc_now()
    # Only the latest successful question verification is allowed. Cancel any
    # unconsumed reset OTPs so an older code cannot be carried into this flow.
    for old in (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose.in_((GATE_PURPOSE, "reset")),
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .all()
    ):
        old.cancelled_at = now

    proof = secrets.token_urlsafe(32)
    db.add(
        OTP(
            user_id=user.id,
            pending_registration_id=None,
            email=user.email,
            purpose=GATE_PURPOSE,
            code_hash=_proof_hash(proof),
            expires_at=now + timedelta(minutes=GATE_MINUTES),
            attempts=0,
            resend_count=0,
            resend_window_started_at=now,
            created_at=now,
        )
    )
    record_security_event(
        db,
        event_type="password_recovery_answer_verified",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Registration security answer verified",
    )
    db.commit()
    return {"recovery_proof": proof, "message": "Security answer verified."}


class ResetRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    recovery_proof: str = Field(min_length=32, max_length=256)


@router.post("/request")
def request_password_reset(data: ResetRequest, request: Request, db: Session = Depends(get_db)):
    user, _gate = _check_gate(db, data.recovery_proof, data.username.strip())
    now = utc_now()
    message = {"message": "A reset code has been requested for the registered email."}

    latest = (
        db.query(OTP)
        .filter(OTP.user_id == user.id, OTP.purpose == "reset")
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
            OTP.purpose == "reset",
            OTP.created_at >= now - timedelta(minutes=OTP_RESEND_WINDOW_MINUTES),
        )
        .scalar()
    ) or 0
    if recent_count >= OTP_MAX_RESENDS + 1:
        db.rollback()
        raise HTTPException(429, "Too many reset OTP requests. Try again later.")

    for old in (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "reset",
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None),
        )
        .all()
    ):
        old.cancelled_at = now

    code = generate_otp()
    otp = OTP(
        user_id=user.id,
        pending_registration_id=None,
        email=user.email,
        purpose="reset",
        code_hash=hash_otp(code),
        expires_at=now + timedelta(minutes=OTP_EXPIRY_MINUTES),
        attempts=0,
        resend_count=recent_count,
        resend_window_started_at=now,
        created_at=now,
    )
    db.add(otp)
    db.commit()
    try:
        delivered = send_otp_email(user.email, code, "reset", OTP_EXPIRY_MINUTES)
        if delivered is False:
            raise RuntimeError("Email delivery not confirmed")
        audit_otp_sent(purpose="reset", request=request,
                       username=user.username, user_id=user.id)
    except Exception:
        logger.exception("Password recovery email delivery failed")
        otp.cancelled_at = utc_now()
        db.commit()
    return message


class ResetVerifyRequest(ResetRequest):
    otp_code: str = Field(pattern=r"^[0-9]{6}$")


class ResetCompleteRequest(ResetVerifyRequest):
    new_password: SecretStr
    confirm_password: SecretStr


def _check_reset_code(db: Session, request: Request, user: User, gate: OTP, code: str):
    now = utc_now()
    otp = (
        db.query(OTP)
        .filter(OTP.user_id == user.id, OTP.purpose == "reset")
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )
    if (
        otp is None
        or otp.created_at < gate.created_at
        or otp.consumed_at is not None
        or otp.cancelled_at is not None
    ):
        db.rollback()
        raise HTTPException(400, GENERIC_OTP_ERROR)
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
        raise HTTPException(400, GENERIC_OTP_ERROR)
    if otp.attempts >= OTP_MAX_ATTEMPTS:
        otp.cancelled_at = now
        db.commit()
        raise HTTPException(429, "Too many incorrect reset-code attempts.")
    if not verify_otp(code, otp.code_hash):
        otp.attempts += 1
        record_security_event(
            db,
            event_type="password_reset_otp_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=f"Incorrect password reset code attempt {otp.attempts}",
        )
        if otp.attempts >= OTP_MAX_ATTEMPTS:
            otp.cancelled_at = now
            record_security_event(
                db,
                event_type="password_reset_otp_limit",
                request=request,
                user_id=user.id,
                username_typed=user.username,
                details="Reset OTP attempt limit reached",
            )
        db.commit()
        if otp.attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(429, "Too many incorrect reset-code attempts.")
        raise HTTPException(400, GENERIC_OTP_ERROR)
    return otp


@router.post("/verify")
def verify_password_reset_code(
    data: ResetVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    user, gate = _check_gate(db, data.recovery_proof, data.username.strip())
    _check_reset_code(db, request, user, gate, data.otp_code)
    db.rollback()  # Release locks, recheck during complete.
    return {"verified": True, "message": "Code verified. Choose a new password."}


@router.post("/complete")
def complete_password_reset(
    data: ResetCompleteRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    user, gate = _check_gate(db, data.recovery_proof, data.username.strip())
    otp = _check_reset_code(db, request, user, gate, data.otp_code)
    new_password = data.new_password.get_secret_value()
    confirmation = data.confirm_password.get_secret_value()
    if new_password != confirmation:
        db.rollback()
        raise HTTPException(422, "New passwords do not match.")
    valid, validation_message = validate_password(new_password)
    if not valid:
        db.rollback()
        raise HTTPException(422, validation_message)
    # Enforce the same recent-password policy used by Staff Settings.
    # The user row is locked by _check_gate, so this check is serialized.
    if is_recent_password(db, user, new_password):
        db.rollback()
        raise HTTPException(422, REUSE_ERROR)

    now = utc_now()
    set_password_with_history(db, user, new_password)
    user.failed_attempts = 0
    user.locked_until = None
    user.password_change_attempts = 0
    user.password_change_locked_until = None
    otp.consumed_at = now
    gate.consumed_at = now
    # Recovery also invalidates any already-authenticated browser/device.
    db.query(UserSession).filter(
        UserSession.user_id == user.id,
        UserSession.revoked_at.is_(None),
    ).update({"revoked_at": now}, synchronize_session=False)
    record_security_event(
        db,
        event_type="password_reset_completed",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Password reset after CAPTCHA, question, and email OTP verification",
    )
    record_security_event(
        db,
        event_type="password_changed",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Password reset and changed after security-question and Gmail OTP checks",
    )
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to update password.") from None
    if user.email:
        background_tasks.add_task(
            send_password_changed_notice,
            email=user.email,
            username=user.username,
            user_id=user.id,
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent", ""),
            method="Forgot Password",
        )
    return {"message": "Password updated. Sign in with your new password."}
