from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    DateTime,
    ForeignKey,
    Index,
    func
)

from app.database import Base


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True
    )

    event_type = Column(
        String(50),
        nullable=False,
        index=True
    )

    username_typed = Column(
        String(100),
        nullable=True
    )

    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    ip_address = Column(
        String(45),
        nullable=True
    )

    user_agent = Column(
        String(512),
        nullable=True
    )

    details = Column(
        Text,
        nullable=True
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        index=True
    )

    __table_args__ = (
        Index(
            "ix_activity_logs_event_date",
            "event_type",
            "created_at"
        ),
        Index(
            "ix_activity_logs_ip_date",
            "ip_address",
            "created_at"
        ),
    )