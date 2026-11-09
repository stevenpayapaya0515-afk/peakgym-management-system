import secrets
import hashlib
import hmac

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models.csrf_token import CSRFToken

from app.security.policy import (
    CSRF_TOKEN_EXPIRY_MINUTES
)


def _hash_token(token: str) -> str:
    return hashlib.sha256(
        token.encode("utf-8")
    ).hexdigest()


def generate_csrf_token(db: Session) -> dict:
    """
    Generate a secure, one-time CSRF token.
    Only the hash is stored in the database.
    """

    token = secrets.token_urlsafe(32)

    now = datetime.utcnow()

    expires_at = now + timedelta(
        minutes=CSRF_TOKEN_EXPIRY_MINUTES
    )

    csrf_record = CSRFToken(
        token_hash=_hash_token(token),
        expires_at=expires_at
    )

    try:
        db.add(csrf_record)
        db.commit()
    except Exception:
        db.rollback()
        raise

    return {
        "csrf_token": token,
        "expires_at": expires_at.isoformat()
    }


def verify_csrf_token(
    db: Session,
    token: str
) -> bool:
    """
    Verify and consume a CSRF token.
    A valid token can only be used once.
    """

    if not isinstance(token, str):
        return False

    if not token or len(token) > 200:
        return False

    token_hash = _hash_token(token)

    now = datetime.utcnow()

    try:
        record = (
            db.query(CSRFToken)
            .filter(
                CSRFToken.token_hash == token_hash
            )
            .with_for_update()
            .first()
        )

        if record is None:
            return False

        if record.consumed_at is not None:
            return False

        if record.expires_at <= now:
            record.consumed_at = now
            db.commit()
            return False

        if not hmac.compare_digest(
            record.token_hash,
            token_hash
        ):
            return False

        record.consumed_at = now

        db.commit()

        return True

    except Exception:
        db.rollback()
        raise