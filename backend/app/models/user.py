from sqlalchemy import Column, Integer, String, Enum, Boolean, DateTime

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(
        Integer,
        primary_key=True,
        index=True,
        autoincrement=True
    )

    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(100), nullable=False)
    password = Column(String(255), nullable=False)

    role = Column(
        Enum("admin", "staff", name="user_role"),
        nullable=False,
        default="staff"
    )

    is_active = Column(Boolean, nullable=False, default=True)

    failed_attempts = Column(Integer, nullable=False, default=0)
    locked_until = Column(DateTime, nullable=True)

    password_change_attempts = Column(
        Integer,
        nullable=False,
        default=0
    )

    password_change_locked_until = Column(
        DateTime,
        nullable=True
    )