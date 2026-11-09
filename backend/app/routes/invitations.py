import hashlib
import secrets
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Header,
)
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.database import get_db
from app.models.user import User
from app.models.invitation import StaffInvitation
from app.routes.auth import get_current_user
from app.security.csrf import (
    generate_csrf_token,
    verify_csrf_token,
)
from app.security.email_service import send_email


router = APIRouter(
    prefix="/invitations",
    tags=["Staff Invitations"]
)

INVITATION_EXPIRY_HOURS = 24
MAX_INVITATIONS_PER_HOUR = 3

FRONTEND_URL = "http://localhost:3000"


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def hash_invitation_token(token: str):
    return hashlib.sha256(
        token.encode("utf-8")
    ).hexdigest()


def require_admin(user: User):
    if user.role != "admin" or not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required."
        )


class InvitationCreate(BaseModel):
    email: str

    @field_validator("email")
    @classmethod
    def validate_email(cls, value):
        email = value.strip().lower()

        if (
            len(email) > 100
            or not re.fullmatch(
                r"[^@\s]+@[^@\s]+\.[^@\s]+",
                email
            )
        ):
            raise ValueError(
                "Please enter a valid email address."
            )

        return email


@router.get("/csrf")
def get_invitation_csrf(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    require_admin(current_user)

    return generate_csrf_token(db)


@router.post("/")
def create_staff_invitation(
    data: InvitationCreate,
    x_csrf_token: str | None = Header(
        default=None,
        alias="X-CSRF-Token"
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    require_admin(current_user)

    if not verify_csrf_token(db, x_csrf_token):
        raise HTTPException(
            status_code=403,
            detail="Invalid or expired CSRF token."
        )

    now = utc_now()

    existing_user = (
        db.query(User)
        .filter(
            func.lower(User.email) == data.email
        )
        .first()
    )

    if existing_user:
        raise HTTPException(
            status_code=409,
            detail="This email is already registered."
        )

    recent_count = (
        db.query(StaffInvitation)
        .filter(
            StaffInvitation.invited_email == data.email,
            StaffInvitation.created_at >= (
                now - timedelta(hours=1)
            )
        )
        .count()
    )

    if recent_count >= MAX_INVITATIONS_PER_HOUR:
        raise HTTPException(
            status_code=429,
            detail="Too many invitations. Try again later."
        )

    # Invalidate earlier pending invitations.
    pending = (
        db.query(StaffInvitation)
        .filter(
            StaffInvitation.invited_email == data.email,
            StaffInvitation.accepted_at.is_(None),
            StaffInvitation.revoked_at.is_(None)
        )
        .all()
    )

    for invitation in pending:
        invitation.revoked_at = now

    raw_token = secrets.token_urlsafe(32)

    invitation = StaffInvitation(
        invited_email=data.email,
        token_hash=hash_invitation_token(raw_token),
        invited_by_id=current_user.id,
        created_at=now,
        expires_at=now + timedelta(
            hours=INVITATION_EXPIRY_HOURS
        )
    )

    db.add(invitation)

    try:
        db.commit()
        db.refresh(invitation)
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to create invitation."
        )

    registration_url = (
        f"{FRONTEND_URL}/register?"
        + urlencode({"invite": raw_token})
    )

    subject = "You're invited to join PeakGym"

    body = f"""
PeakGym Management System

You have been invited to create a PeakGym staff account.

Complete your registration using this link:

{registration_url}

This invitation expires in 24 hours.

If you were not expecting this invitation,
please ignore this message.

PeakGym Management System
"""

    try:
        send_email(
            recipient=data.email,
            subject=subject,
            body_text=body
        )

    except Exception:
        # Revoke the invitation when delivery fails.
        invitation.revoked_at = utc_now()

        try:
            db.commit()
        except Exception:
            db.rollback()

        raise HTTPException(
            status_code=503,
            detail="Invitation email could not be sent."
        )

    return {
        "message": "Staff invitation email submitted successfully.",
        "invitation_id": invitation.id,
        "email": data.email,
        "expires_at": invitation.expires_at.isoformat()
    }


@router.get("/")
def list_invitations(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    require_admin(current_user)

    invitations = (
        db.query(StaffInvitation)
        .order_by(StaffInvitation.id.desc())
        .limit(100)
        .all()
    )

    now = utc_now()

    results = []

    for invitation in invitations:
        if invitation.accepted_at:
            status = "Accepted"
        elif invitation.revoked_at:
            status = "Revoked"
        elif invitation.expires_at <= now:
            status = "Expired"
        else:
            status = "Pending"

        results.append({
            "id": invitation.id,
            "email": invitation.invited_email,
            "status": status,
            "created_at": invitation.created_at,
            "expires_at": invitation.expires_at,
        })

    return results


# ============================================
# PUBLIC STAFF INVITATION VALIDATION
# ============================================

class InvitationValidate(BaseModel):
    token: str


@router.post("/validate")
def validate_staff_invitation(
    data: InvitationValidate,
    db: Session = Depends(get_db)
):
    token = data.token.strip()

    if not token or len(token) > 256:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired invitation."
        )

    token_hash = hash_invitation_token(token)

    invitation = (
        db.query(StaffInvitation)
        .filter(
            StaffInvitation.token_hash == token_hash
        )
        .first()
    )

    if (
        invitation is None
        or invitation.revoked_at is not None
        or invitation.accepted_at is not None
        or invitation.expires_at <= utc_now()
    ):
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired invitation."
        )

    return {
        "valid": True,
        "email": invitation.invited_email,
        "message": "Invitation is valid. You may continue registration."
    }