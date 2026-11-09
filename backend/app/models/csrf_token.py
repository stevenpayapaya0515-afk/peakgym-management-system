from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    Index,
    func
)

from app.database import Base


class CSRFToken(Base):
    __tablename__ = "csrf_tokens"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    token_hash = Column(
        String(64),
        nullable=False,
        unique=True
    )

    expires_at = Column(
        DateTime,
        nullable=False
    )

    consumed_at = Column(
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
            "ix_csrf_tokens_expiry",
            "expires_at"
        ),
    )