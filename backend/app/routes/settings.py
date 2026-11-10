import math
import re

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.routes.auth import get_current_user
from app.security.password import verify_password
from app.security.password_history import (
    REUSE_ERROR,
    is_recent_password,
    set_password_with_history,
)


router = APIRouter(
    prefix="/settings",
    tags=["Staff Settings"]
)


class PasswordChangeRequest(BaseModel):
    current_password: str = Field(repr=False)
    new_password: str = Field(repr=False)
    confirm_password: str = Field(repr=False)


def validate_new_password(password: str) -> None:
    byte_length = len(password.encode("utf-8"))

    if not 12 <= byte_length <= 64:
        raise HTTPException(
            status_code=422,
            detail="Use a new password between 12 and 64 bytes."
        )

    if "\x00" in password:
        raise HTTPException(
            status_code=422,
            detail="Password contains an invalid character."
        )

    has_upper = re.search(r"[A-Z]", password)
    has_lower = re.search(r"[a-z]", password)
    has_number = re.search(r"[0-9]", password)
    has_symbol = re.search(r"[^a-zA-Z0-9\s]", password)

    if not all([has_upper, has_lower, has_number, has_symbol]):
        raise HTTPException(
            status_code=422,
            detail=(
                "Include an uppercase letter, lowercase letter, "
                "number, and symbol."
            )
        )


@router.post("/change-password")
def change_password(
    data: PasswordChangeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role != "staff":
        raise HTTPException(
            status_code=403,
            detail="Staff access required"
        )

    try:
        # Lock and refresh the account before checking/updating it.
        # Concurrent requests cannot overwrite each other's counters.
        user = (
            db.query(User)
            .filter(User.id == current_user.id)
            .populate_existing()
            .with_for_update()
            .first()
        )

        if not user or user.role != "staff" or not user.is_active:
            raise HTTPException(
                status_code=403,
                detail="This staff account is no longer available."
            )

        now = datetime.utcnow()
        locked_until = user.password_change_locked_until

        if locked_until and locked_until > now:
            remaining = max(
                1,
                math.ceil((locked_until - now).total_seconds())
            )

            raise HTTPException(
                status_code=429,
                detail=(
                    "Too many incorrect attempts. "
                    f"Try again in {remaining} seconds."
                ),
                headers={"Retry-After": str(remaining)}
            )

        if locked_until and locked_until <= now:
            user.password_change_attempts = 0
            user.password_change_locked_until = None

        if (
            not data.current_password
            or not data.new_password
            or not data.confirm_password
        ):
            raise HTTPException(
                status_code=422,
                detail="Please fill in all password fields."
            )

        validate_new_password(data.new_password)

        if data.new_password != data.confirm_password:
            raise HTTPException(
                status_code=422,
                detail="The new passwords do not match."
            )

        try:
            current_is_correct = verify_password(
                data.current_password,
                user.password
            )
        except (ValueError, TypeError):
            current_is_correct = False

        if not current_is_correct:
            user.password_change_attempts = (
                user.password_change_attempts or 0
            ) + 1

            if user.password_change_attempts >= 5:
                user.password_change_attempts = 5
                user.password_change_locked_until = (
                    now + timedelta(seconds=60)
                )

                # Commit before raising so the cooldown is retained.
                db.commit()

                raise HTTPException(
                    status_code=429,
                    detail=(
                        "Too many incorrect attempts. "
                        "Try again in 60 seconds."
                    ),
                    headers={"Retry-After": "60"}
                )

            db.commit()

            raise HTTPException(
                status_code=400,
                detail="Your current password is incorrect."
            )

        # The current password and its last two predecessors are prohibited.
        # The account row is locked above, so competing changes cannot bypass
        # this comparison or corrupt history.
        if is_recent_password(db, user, data.new_password):
            raise HTTPException(status_code=422, detail=REUSE_ERROR)

        set_password_with_history(db, user, data.new_password)
        user.password_change_attempts = 0
        user.password_change_locked_until = None

        db.commit()

        return {
            "message": (
                "Password changed successfully. "
                "Use your new password the next time you log in."
            )
        }

    except HTTPException:
        db.rollback()
        raise

    except Exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail="Unable to change your password. Please try again."
        )