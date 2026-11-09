from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Index,
    func
)

from app.database import Base


class OTP(Base):
    __tablename__ = "otps"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    pending_registration_id = Column(
        Integer,
        ForeignKey(
            "pending_staff_registrations.id",
            ondelete="RESTRICT"
        ),
        nullable=True,
        index=True
    )

    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    email = Column(
        String(100),
        nullable=False
    )

    purpose = Column(
        String(20),
        nullable=False
    )

    code_hash = Column(
        String(64),
        nullable=False
    )

    expires_at = Column(
        DateTime,
        nullable=False
    )

    attempts = Column(
        Integer,
        nullable=False,
        default=0
    )

    resend_count = Column(
        Integer,
        nullable=False,
        default=0
    )

    resend_window_started_at = Column(
        DateTime,
        nullable=True
    )

    consumed_at = Column(
        DateTime,
        nullable=True
    )

    cancelled_at = Column(
        DateTime,
        nullable=True
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now()
    )

    __table_args__ = (
        Index(
            "ix_otps_email_purpose",
            "email",
            "purpose"
        ),
        Index(
            "ix_otps_expiry",
            "expires_at"
        ),
    )