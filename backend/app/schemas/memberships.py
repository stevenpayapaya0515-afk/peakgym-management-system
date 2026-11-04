from datetime import date

from pydantic import BaseModel, Field


class MembershipUpdate(BaseModel):
    member_id: int = Field(gt=0)
    start_date: date
    due_date: date


class MembershipRenew(BaseModel):
    member_id: int = Field(gt=0)
    start_date: date