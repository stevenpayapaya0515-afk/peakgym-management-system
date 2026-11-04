from datetime import date
from pydantic import BaseModel, Field, field_validator


class MemberCreate(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    start_date: date

    @field_validator("full_name")
    @classmethod
    def validate_full_name(cls, value):
        value = value.strip()

        if not value:
            raise ValueError("Member name cannot be empty")

        return value


class MemberUpdate(BaseModel):
    full_name: str | None = Field(
        default=None,
        min_length=1,
        max_length=100
    )

    @field_validator("full_name")
    @classmethod
    def validate_full_name(cls, value):
        if value is None:
            return value

        value = value.strip()

        if not value:
            raise ValueError("Member name cannot be empty")

        return value