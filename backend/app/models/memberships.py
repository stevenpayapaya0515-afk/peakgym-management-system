from sqlalchemy import Column, Integer, Date, TIMESTAMP, ForeignKey, text
from app.database import Base


class Membership(Base):
    __tablename__ = "memberships"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    member_id = Column(
        Integer,
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False
    )
    start_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    created_at = Column(
        TIMESTAMP,
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP")
    )