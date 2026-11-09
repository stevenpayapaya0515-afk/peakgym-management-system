from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    func
)

from app.database import Base


class StaffInvitation(Base):
    __tablename__ = "staff_invitations"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    invited_email = Column(
        String(100),
        nullable=False,
        index=True
    )

    token_hash = Column(
        String(64),
        nullable=False,
        unique=True
    )

    invited_by_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False
    )

    expires_at = Column(
        DateTime,
        nullable=False
    )

    accepted_at = Column(
        DateTime,
        nullable=True
    )

    revoked_at = Column(
        DateTime,
        nullable=True
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now()
    )