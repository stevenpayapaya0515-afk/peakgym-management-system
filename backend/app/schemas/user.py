from pydantic import BaseModel, Field, field_validator


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=50)
    email: str = Field(min_length=5, max_length=100)
    password: str

    @field_validator("password")
    @classmethod
    def validate_password(cls, value: str) -> str:
        size = len(value.encode("utf-8"))

        if size < 12 or size > 72:
            raise ValueError(
                "Password must be between 12 and 72 bytes."
            )

        if "\x00" in value:
            raise ValueError(
                "Password contains an invalid character."
            )

        return value


class UserUpdate(BaseModel):
    username: str | None = Field(
        default=None,
        min_length=3,
        max_length=50
    )

    email: str | None = Field(
        default=None,
        min_length=5,
        max_length=100
    )