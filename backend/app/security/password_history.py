"""Shared recent-password policy for Settings and Forgot Password.

Current password + two immediately preceding passwords = last three.
Historical hashes are never converted to plaintext or sent to the frontend.
"""
from sqlalchemy.orm import Session

from app.models.password_history import PasswordHistory
from app.models.user import User
from app.security.password import hash_password, verify_password

RECENT_PASSWORD_COUNT = 3
REUSE_ERROR = "You cannot reuse a recent password."


def is_recent_password(db: Session, user: User, candidate: str) -> bool:
    """Compare a proposed password with the current and last two old hashes."""
    prior_hashes = (
        db.query(PasswordHistory.password_hash)
        .filter(PasswordHistory.user_id == user.id)
        .order_by(PasswordHistory.id.desc())
        .limit(RECENT_PASSWORD_COUNT - 1)
        .all()
    )
    recent_hashes = [user.password] + [row[0] for row in prior_hashes]
    return any(verify_password(candidate, item) for item in recent_hashes)


def set_password_with_history(db: Session, user: User, new_password: str) -> None:
    """Set the password and retain its two predecessors in the SAME transaction.

    The caller must lock the user row and commit/rollback the transaction.
    A failed commit rolls back BOTH the new hash and the history update.
    """
    new_hash = hash_password(new_password)
    db.add(PasswordHistory(user_id=user.id, password_hash=user.password))
    user.password = new_hash
    db.flush()

    stale = (
        db.query(PasswordHistory)
        .filter(PasswordHistory.user_id == user.id)
        .order_by(PasswordHistory.id.desc())
        .offset(RECENT_PASSWORD_COUNT - 1)
        .all()
    )
    for item in stale:
        db.delete(item)
