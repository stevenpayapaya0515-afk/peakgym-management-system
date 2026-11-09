import os
import secrets
import hashlib

from datetime import datetime, timedelta, timezone

from fastapi import Response
from sqlalchemy.orm import Session

from app.models.user_session import UserSession

from app.security.policy import (
    IDLE_SESSION_TIMEOUT_MINUTES
)


SESSION_COOKIE_NAME = "peakgym_session"


def _now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash_token(token: str) -> str:
    return hashlib.sha256(
        token.encode("utf-8")
    ).hexdigest()


def create_session(
    db: Session,
    user_id: int,
    ip_address: str = None,
    user_agent: str = None
) -> dict:
    """
    Create a new server-tracked session.
    The original token is returned only once.
    Only its SHA-256 hash is stored.
    """

    token = secrets.token_urlsafe(48)

    now = _now()

    expires_at = now + timedelta(
        minutes=IDLE_SESSION_TIMEOUT_MINUTES
    )

    session_record = UserSession(
        user_id=user_id,
        token_hash=_hash_token(token),
        ip_address=ip_address,
        user_agent=user_agent,
        last_activity_at=now,
        expires_at=expires_at
    )

    try:
        db.add(session_record)
        db.commit()
        db.refresh(session_record)

    except Exception:
        db.rollback()
        raise

    return {
        "session_token": token,
        "session_id": session_record.id,
        "expires_at": expires_at.isoformat()
    }


def validate_session(
    db: Session,
    token: str,
    touch: bool = True
) -> dict | None:
    """
    Validate a session and enforce idle timeout.
    Active requests refresh the idle expiration.
    """

    if not isinstance(token, str):
        return None

    if len(token) < 32 or len(token) > 200:
        return None

    token_hash = _hash_token(token)
    now = _now()

    try:
        session_record = (
            db.query(UserSession)
            .filter(
                UserSession.token_hash == token_hash
            )
            .with_for_update()
            .first()
        )

        if session_record is None:
            return None

        if session_record.revoked_at is not None:
            return None

        idle_duration = now - session_record.last_activity_at

        if (
            session_record.expires_at <= now
            or idle_duration >= timedelta(
                minutes=IDLE_SESSION_TIMEOUT_MINUTES
            )
        ):
            session_record.revoked_at = now
            db.commit()
            return None

        if touch:
            session_record.last_activity_at = now

            session_record.expires_at = now + timedelta(
                minutes=IDLE_SESSION_TIMEOUT_MINUTES
            )

            db.commit()

        return {
            "session_id": session_record.id,
            "user_id": session_record.user_id,
            "expires_at": session_record.expires_at.isoformat()
        }

    except Exception:
        db.rollback()
        raise


def revoke_session(
    db: Session,
    token: str
) -> bool:
    """Revoke a session during logout."""

    if not isinstance(token, str) or not token:
        return False

    try:
        session_record = (
            db.query(UserSession)
            .filter(
                UserSession.token_hash == _hash_token(token),
                UserSession.revoked_at.is_(None)
            )
            .with_for_update()
            .first()
        )

        if session_record is None:
            return False

        session_record.revoked_at = _now()

        db.commit()

        return True

    except Exception:
        db.rollback()
        raise


def revoke_all_user_sessions(
    db: Session,
    user_id: int
) -> int:
    """Revoke every active session belonging to a user."""

    try:
        now = _now()

        count = (
            db.query(UserSession)
            .filter(
                UserSession.user_id == user_id,
                UserSession.revoked_at.is_(None)
            )
            .update(
                {"revoked_at": now},
                synchronize_session=False
            )
        )

        db.commit()

        return count

    except Exception:
        db.rollback()
        raise


def set_session_cookie(
    response: Response,
    token: str
):
    """
    Set an HttpOnly session cookie.
    Use HTTPS and SESSION_COOKIE_SECURE=true in production.
    """

    secure = os.getenv(
        "SESSION_COOKIE_SECURE",
        "false"
    ).lower() == "true"

    response.set_cookie(
        key=SESSION_COOKIE_NAME,
        value=token,
        max_age=IDLE_SESSION_TIMEOUT_MINUTES * 60,
        httponly=True,
        secure=secure,
        samesite="lax",
        path="/"
    )


def clear_session_cookie(response: Response):
    """Clear the browser session cookie during logout."""

    response.delete_cookie(
        key=SESSION_COOKIE_NAME,
        httponly=True,
        secure=os.getenv(
            "SESSION_COOKIE_SECURE",
            "false"
        ).lower() == "true",
        samesite="lax",
        path="/"
    )