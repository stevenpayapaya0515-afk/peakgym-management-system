
from datetime import datetime, timedelta, timezone
from math import ceil

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from typing import Literal
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.otp import OTP
from app.models.user import User
from app.security.recaptcha_v2 import verify_recaptcha_v2
from app.security.email_service import send_otp_email
from app.security.email_notifications import audit_otp_sent
from app.security.otp import generate_otp, hash_otp, verify_otp
from app.security.password import verify_password
from app.security.policy import (
    LOCKOUT_TIERS,
    OTP_EXPIRY_MINUTES,
    OTP_MAX_ATTEMPTS,
    OTP_MAX_RESENDS,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_RESEND_WINDOW_MINUTES,
)
from app.security.token import create_access_token
from fastapi import BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi import Request
from app.security.activity_logger import record_security_event
from app.security.login_alerts import send_login_lockout_alert
from app.security.token import create_access_token, password_token_stamp
from app.security.session import create_session, set_session_cookie, revoke_session, SESSION_COOKIE_NAME
from app.security.ip_blocking import reject_blocked_ip, block_after_failed_password
from app.security.policy import IDLE_SESSION_TIMEOUT_SECONDS, SESSION_WARNING_BEFORE_SECONDS



router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class LoginStartRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1)
    recaptcha_token: str = Field(min_length=20, max_length=8192)


class LoginVerifyRequest(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    otp_code: str = Field(pattern=r"^[0-9]{6}$")
    token_transport: Literal["cookie", "bearer"] = "bearer"


# =====================================
# STEP 1: VERIFY PASSWORD AND CAPTCHA
# =====================================

@router.post("/login/start")
def start_login(
    data: LoginStartRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    # IP lockout applies to ALL usernames, including nonexistent ones.
    # Reject before CAPTCHA or password checking; untrusted headers cannot bypass it.
    reject_blocked_ip(db, request)

    if not verify_recaptcha_v2(data.recaptcha_token):
        record_security_event(
            db, event_type="captcha_failed", request=request,
            username_typed=data.username, details="Login reCAPTCHA rejected",
        )
        db.commit()
        raise HTTPException(400, "reCAPTCHA verification failed. Check the box again.")

    user = (
        db.query(User)
        .filter(User.username == data.username.strip())
        .with_for_update()
        .first()
    )

    if user is None:
        # Preserve username-enumeration resistance, but also count failures
        # for usernames that don't exist (the seeded rule is per IP).
        record_security_event(
            db,
            event_type="login_failed",
            request=request,
            username_typed=data.username,
            details="Invalid username or password",
        )
        ip_seconds = block_after_failed_password(
            db, request, username=data.username, user_id=None,
        )
        db.commit()
        if ip_seconds:
            raise HTTPException(
                429,
                f"Too many failed logins from this IP. Try again in {ip_seconds} seconds.",
                headers={"Retry-After": str(ip_seconds)},
            )
        raise HTTPException(401, "Invalid username or password.")

    if not user.is_active:
        db.rollback()
        raise HTTPException(403, "This account is inactive.")

    # Keep the existing application's local-time
    # representation for account lockout timestamps.
    local_now = datetime.now()

    if user.locked_until and user.locked_until > local_now:
        remaining = max(
            1,
            ceil((user.locked_until - local_now).total_seconds())
        )
        db.rollback()
        raise HTTPException(
            429,
            f"Too many failed attempts. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)}
        )

    if not verify_password(data.password, user.password):
        user.failed_attempts = (user.failed_attempts or 0) + 1
        failures = user.failed_attempts

        lock_seconds = next(
            (
                seconds
                for count, seconds in LOCKOUT_TIERS
                if count == failures
            ),
            0
        )

        if failures >= LOCKOUT_TIERS[-1][0]:
            lock_seconds = LOCKOUT_TIERS[-1][1]

        if lock_seconds:
            user.locked_until = local_now + timedelta(
                seconds=lock_seconds
            )
        else:
            user.locked_until = None
        
        # Record every incorrect password attempt.
        record_security_event(
            db,
            event_type="login_failed",
            request=request,
            user_id=user.id,
            username_typed=data.username,
            details=f"Failed password attempt {failures}",
        )

        # Record a separate security event at each lockout tier.
        if failures in (3, 6, 9) and lock_seconds:
            record_security_event(
                db,
                event_type="account_locked",
                request=request,
                user_id=user.id,
                username_typed=user.username,
                details=(
                    f"Failed attempts: {failures}; "
                    f"Lockout duration: {lock_seconds} seconds"
                ),
            )

        # Count this attempt in the shared per-IP 10-minute window and
        # apply a separate ten-minute IP block if the seeded limit is met.
        ip_seconds = block_after_failed_password(
            db, request, username=data.username, user_id=user.id,
        )
        db.commit()

        # Account lockout alert is still sent at 3/6/9, even if the IP
        # threshold is reached by this same attempt.
        if lock_seconds and failures in (3, 6, 9):
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

        if ip_seconds:
            return JSONResponse(
                status_code=429,
                content={"detail": (
                    f"Too many failed logins from this IP. Try again in {ip_seconds} seconds."
                )},
                headers={"Retry-After": str(ip_seconds)},
                background=background_tasks,
            )

        if lock_seconds:
            return JSONResponse(
                status_code=429,
                content={
                    "detail": (
                        f"Account locked for {lock_seconds} seconds."
                    )
                },
                headers={
                    "Retry-After": str(lock_seconds)
                },
                background=background_tasks,
            )

        raise HTTPException(
            401,
            "Invalid username or password."
        )


    now = utc_now()

    latest = (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "login"
        )
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )

    # Restrict repeated OTP email requests.
    if latest is not None:
        elapsed = (now - latest.created_at).total_seconds()

        if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
            remaining = max(
                1,
                ceil(OTP_RESEND_COOLDOWN_SECONDS - elapsed)
            )
            db.rollback()
            raise HTTPException(
                429,
                f"Please wait {remaining} seconds before requesting another code.",
                headers={"Retry-After": str(remaining)}
            )

    recent_codes = (
        db.query(OTP.id)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "login",
            OTP.created_at >= now - timedelta(
                minutes=OTP_RESEND_WINDOW_MINUTES
            )
        )
        .count()
    )

    if recent_codes >= OTP_MAX_RESENDS + 1:
        db.rollback()
        raise HTTPException(
            429,
            "Too many OTP requests. Try again later."
        )

    if (
        latest is not None
        and latest.consumed_at is None
        and latest.cancelled_at is None
    ):
        latest.cancelled_at = now

    code = generate_otp()

    otp = OTP(
        user_id=user.id,
        pending_registration_id=None,
        email=user.email,
        purpose="login",
        code_hash=hash_otp(code),
        expires_at=now + timedelta(
            minutes=OTP_EXPIRY_MINUTES
        ),
        attempts=0,
        resend_count=recent_codes,
        resend_window_started_at=now,
        created_at=now
    )

    user.locked_until = None
    db.add(otp)
    db.commit()

    try:
        sent = send_otp_email(
            user.email,
            code,
            "login",
            OTP_EXPIRY_MINUTES
        )

        if not sent:
            raise RuntimeError("Email delivery was not confirmed.")

    except Exception:
        db.rollback()
        otp.cancelled_at = utc_now()
        db.commit()
        raise HTTPException(
            503,
            "Could not send login OTP email."
        ) from None

    audit_otp_sent(
        purpose="login", request=request,
        username=user.username, user_id=user.id,
    )

    # IMPORTANT: No JWT is returned here.
    return {
        "message": "A login verification code was sent to the account email.",
        "otp_required": True,
        "otp_expires_in_seconds": OTP_EXPIRY_MINUTES * 60
    }


# =====================================
# STEP 2: VERIFY OTP AND ISSUE JWT
# =====================================

@router.post("/login/verify-otp")
def verify_login_otp(
    data: LoginVerifyRequest,
    request: Request,
    response: Response,
    db: Session = Depends(get_db)
):
    # A blocked address cannot finish an earlier OTP challenge either.
    reject_blocked_ip(db, request)

    user = (
        db.query(User)
        .filter(User.username == data.username.strip())
        .with_for_update()
        .first()
    )

    if user is None or not user.is_active:
        db.rollback()
        raise HTTPException(
            400,
            "Invalid or expired login code."
        )

    otp = (
        db.query(OTP)
        .filter(
            OTP.user_id == user.id,
            OTP.purpose == "login",
            OTP.consumed_at.is_(None),
            OTP.cancelled_at.is_(None)
        )
        .order_by(OTP.id.desc())
        .with_for_update()
        .first()
    )

    now = utc_now()


    if otp is None:
        db.rollback()
        raise HTTPException(
            400,
            "Invalid or expired login code."
        )

    if otp.expires_at <= now:
        otp.cancelled_at = now

        record_security_event(
            db,
            event_type="login_otp_expired",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details="Login OTP expired before verification",
        )

        db.commit()

        raise HTTPException(
            400,
            "Invalid or expired login code."
        )


    if otp.attempts >= OTP_MAX_ATTEMPTS:
        otp.cancelled_at = now
        db.commit()
        raise HTTPException(
            429,
            "Too many incorrect OTP attempts."
        )


    if not verify_otp(data.otp_code, otp.code_hash):
        attempts = otp.attempts + 1
        otp.attempts = attempts

        record_security_event(
            db,
            event_type="login_otp_failed",
            request=request,
            user_id=user.id,
            username_typed=user.username,
            details=(
                f"Incorrect login OTP attempt "
                f"{attempts} of {OTP_MAX_ATTEMPTS}"
            ),
        )

        if attempts >= OTP_MAX_ATTEMPTS:
            otp.cancelled_at = now

            record_security_event(
                db,
                event_type="login_otp_limit",
                request=request,
                user_id=user.id,
                username_typed=user.username,
                details="Maximum incorrect login OTP attempts reached",
            )

        db.commit()

        if attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(
                429,
                "Too many incorrect OTP attempts."
            )

        raise HTTPException(
            400,
            "Invalid or expired login code."
        )

    otp.consumed_at = now
    user.failed_attempts = 0
    user.locked_until = None

    # Record successful password + Gmail OTP authentication.
    record_security_event(
        db,
        event_type="login_success",
        request=request,
        user_id=user.id,
        username_typed=user.username,
        details="Password and email OTP verified successfully",
    )

    db.commit()


    # New server-tracked session is created only after successful Gmail OTP.
    # An old session ID is never reused after login.
    session = create_session(
        db,
        user_id=user.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent", "")[:512],
    )
    result = {
        "idle_timeout_seconds": IDLE_SESSION_TIMEOUT_SECONDS,
        "warning_before_seconds": SESSION_WARNING_BEFORE_SECONDS,
        "user": {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role,
        },
    }
    if data.token_transport == "cookie":
        # Regenerate the browser session after completing both login factors.
        old_cookie = request.cookies.get(SESSION_COOKIE_NAME)
        if old_cookie:
            revoke_session(db, old_cookie)
        set_session_cookie(response, session["session_token"])
        # The browser response never contains a JavaScript-readable JWT.
        return result

    # Retain the existing native Flutter Bearer JWT workflow.
    result.update({
        "access_token": create_access_token({
            "sub": str(user.id),
            "role": user.role,
            "amr": ["pwd", "otp"],
            "pwdv": password_token_stamp(user.password),
            "sid": session["session_id"],
        }),
        "token_type": "bearer",
    })
    return result
