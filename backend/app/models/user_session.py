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


class UserSession(Base):
    __tablename__ = "user_sessions"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    token_hash = Column(
        String(64),
        nullable=False,
        unique=True
    )

    ip_address = Column(
        String(45),
        nullable=True
    )

    user_agent = Column(
        String(512),
        nullable=True
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now()
    )

    last_activity_at = Column(
        DateTime,
        nullable=False
    )

    expires_at = Column(
        DateTime,
        nullable=False
    )

    revoked_at = Column(
        DateTime,
        nullable=True
    )

    __table_args__ = (
        Index(
            "ix_user_sessions_user_expiry",
            "user_id",
            "expires_at"
        ),
    )