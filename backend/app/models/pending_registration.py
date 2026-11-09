from datetime import datetime, timezone

from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Text,
    Index,
)

from app.database import Base


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class PendingStaffRegistration(Base):
    __tablename__ = "pending_staff_registrations"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    # Registration must come from an admin invitation.
    invitation_id = Column(
        Integer,
        ForeignKey(
            "staff_invitations.id",
            ondelete="RESTRICT"
        ),
        nullable=False,
        index=True,
    )

    # Only the hash of the registration reference
    # will be stored in the database.
    registration_token_hash = Column(
        String(64),
        unique=True,
        nullable=False,
    )

    email = Column(
        String(255),
        nullable=False,
        index=True,
    )

    username = Column(
        String(19),
        nullable=False,
        index=True,
    )

    # Password is stored only as a secure hash.
    password_hash = Column(
        String(255),
        nullable=False,
    )

    # Encrypted JSON registration details.
    # Never store plaintext personal information
    # or security-question answers here.
    encrypted_registration_data = Column(
        Text,
        nullable=False,
    )

    # pending, verified, expired, cancelled
    status = Column(
        String(20),
        nullable=False,
        default="pending",
    )

    created_at = Column(
        DateTime,
        nullable=False,
        default=utc_now,
    )

    expires_at = Column(
        DateTime,
        nullable=False,
    )

    verified_at = Column(
        DateTime,
        nullable=True,
    )

    # Filled only after successful account creation.
    activated_user_id = Column(
        Integer,
        ForeignKey(
            "users.id",
            ondelete="RESTRICT"
        ),
        nullable=True,
    )

    __table_args__ = (
        Index(
            "ix_pending_registration_status_expiry",
            "status",
            "expires_at",
        ),
    )