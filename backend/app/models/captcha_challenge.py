from sqlalchemy import (
    Column,
    String,
    DateTime,
    Index,
    func
)

from app.database import Base


class CaptchaChallenge(Base):
    __tablename__ = "captcha_challenges"

    id = Column(
        String(64),
        primary_key=True
    )

    answer_hash = Column(
        String(64),
        nullable=False
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
            "ix_captcha_challenges_expiry",
            "expires_at"
        ),
    )