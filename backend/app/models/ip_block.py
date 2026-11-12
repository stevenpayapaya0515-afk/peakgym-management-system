"""An IP becomes blocked for ten minutes after too many failed logins.

Rows also serve as per-IP transaction locks during concurrent login attempts.
"""
from sqlalchemy import Column, DateTime, Integer, String, func
from app.database import Base


class IPBlock(Base):
    __tablename__ = "ip_blocks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ip_address = Column(String(45), unique=True, index=True, nullable=False)
    blocked_until = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default=func.now())
