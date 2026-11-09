from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    Date,
    DateTime,
    Index,
    UniqueConstraint,
    func
)

from app.database import Base


class SecurityFlag(Base):
    __tablename__ = "security_flags"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    pattern = Column(
        String(50),
        nullable=False
    )

    target = Column(
        String(100),
        nullable=False
    )

    severity = Column(
        String(10),
        nullable=False
    )

    description = Column(
        Text,
        nullable=False
    )

    evidence = Column(
        Text,
        nullable=True
    )

    flag_date = Column(
        Date,
        nullable=False
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "pattern",
            "target",
            "flag_date",
            name="uq_security_flag_daily"
        ),
        Index(
            "ix_security_flags_date",
            "flag_date"
        ),
        Index(
            "ix_security_flags_severity",
            "severity"
        ),
    )