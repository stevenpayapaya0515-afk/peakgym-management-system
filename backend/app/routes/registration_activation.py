"""Activate an OTP-verified PeakGym staff registration.

Requires a validated pending registration and a still-valid admin invitation.
Does not replace the existing registration/start or verify-otp routes.
"""

import hashlib
import json
import re
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.invitation import StaffInvitation
from app.models.pending_registration import PendingStaffRegistration
from app.models.staff_profile import StaffProfile
from app.models.user import User
from app.security.encryption import decrypt_sensitive_data, encrypt_sensitive_data

router = APIRouter(prefix="/registration", tags=["Staff Registration"])


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class RegistrationActivateRequest(BaseModel):
    registration_token: str = Field(min_length=32, max_length=256)


@router.post("/activate")
def activate_staff_registration(
    data: RegistrationActivateRequest,
    db: Session = Depends(get_db),
):
    """Create a staff user + profile after OTP verification, atomically."""
    now = utc_now()
    token_hash = hashlib.sha256(data.registration_token.encode("utf-8")).hexdigest()

    # Lock one pending registration to prevent duplicate activation.
    pending = (
        db.query(PendingStaffRegistration)
        .filter(PendingStaffRegistration.registration_token_hash == token_hash)
        .with_for_update()
        .first()
    )
    if (
        pending is None
        or pending.status != "verified"
        or pending.verified_at is None
        or pending.expires_at <= now
        or pending.activated_user_id is not None
    ):
        db.rollback()
        raise HTTPException(400, "Invalid or unverified registration reference.")

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
        or invitation.invited_email.strip().lower() != pending.email.strip().lower()
    ):
        db.rollback()
        raise HTTPException(400, "Invitation is no longer valid.")

    # Never trust data just because it is stored; validate decoded fields again.
    try:
        raw = decrypt_sensitive_data(
            pending.encrypted_registration_data, context="staff-registration"
        )
        details = json.loads(raw)
        if not isinstance(details, dict):
            raise ValueError("Invalid registration details")
        identity = details["id_number"]
        birthdate = date.fromisoformat(details["birthdate"])
        hired = date.fromisoformat(details["date_hired"])
        position = details["staff_position"]
        employment = details["employment_type"]
        emergency = details["emergency_contact_number"]
        consent = details["privacy_consent"]
        if (
            not re.fullmatch(r"[0-9]{4}-[0-9]{4}", identity)
            or position not in {"Trainer", "Receptionist", "Maintenance", "Manager"}
            or employment not in {"Full-time", "Part-time"}
            or hired > date.today()
            or not re.fullmatch(r"(?:09[0-9]{9}|\+639[0-9]{9})", emergency)
            or consent is not True
        ):
            raise ValueError("Invalid staff registration fields")
        age = date.today().year - birthdate.year - (
            (date.today().month, date.today().day) < (birthdate.month, birthdate.day)
        )
        if age < 18:
            raise ValueError("Registrant must be 18 or older")
        for key in (
            "first_name", "family_name", "region", "province", "city_municipality",
            "barangay", "street_address", "postal_code", "security_answer_q4_hash",
            "security_answer_q7_hash", "security_answer_q1_hash",
        ):
            if not isinstance(details.get(key), str) or not details[key].strip():
                raise ValueError("Missing required registration field")
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        db.rollback()
        raise HTTPException(400, "Saved registration details are invalid.") from None

    existing_user = db.query(User.id).filter(
        (func.lower(User.username) == pending.username.lower())
        | (func.lower(User.email) == pending.email.lower())
    ).first()
    existing_id = db.query(StaffProfile.id).filter(
        StaffProfile.id_number == identity
    ).first()
    if existing_user or existing_id:
        db.rollback()
        raise HTTPException(409, "Staff account information is already in use.")

    try:
        staff = User(
            username=pending.username,
            email=pending.email,
            password=pending.password_hash,  # already hashed by /registration/start
            role="staff",
            is_active=True,
            failed_attempts=0,
            password_change_attempts=0,
        )
        db.add(staff)
        db.flush()  # obtains user ID without committing

        profile = StaffProfile(
            user_id=staff.id,
            id_number=identity,
            first_name=details["first_name"],
            middle_name=details.get("middle_name"),
            family_name=details["family_name"],
            extension_name=details.get("extension_name"),
            birthdate=birthdate,
            region=details["region"],
            province=details["province"],
            city_municipality=details["city_municipality"],
            barangay=details["barangay"],
            street_address_encrypted=encrypt_sensitive_data(
                details["street_address"], context="staff-address"
            ),
            postal_code=details["postal_code"],
            security_answer_q4_hash=details["security_answer_q4_hash"],
            security_answer_q7_hash=details["security_answer_q7_hash"],
            security_answer_q1_hash=details["security_answer_q1_hash"],
            privacy_consent_at=pending.created_at,
            staff_position=position,
            employment_type=employment,
            date_hired=hired,
            emergency_contact_number=emergency,
        )
        db.add(profile)
        invitation.accepted_at = now
        pending.status = "activated"
        pending.activated_user_id = staff.id
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Staff account information is already in use.") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(500, "Unable to activate staff account.") from None
    except Exception:
        db.rollback()
        raise

    return {
        "message": "Staff account activated successfully.",
        "account_activated": True,
        "role": "staff",
    }
