import re
from datetime import date

from pydantic import (
    BaseModel,
    Field,
    SecretStr,
    field_validator,
    model_validator,
)


def is_adult(birthdate: date) -> bool:
    today = date.today()

    if birthdate > today:
        return False

    age = today.year - birthdate.year

    if (today.month, today.day) < (
        birthdate.month,
        birthdate.day,
    ):
        age -= 1

    return age >= 18


def validate_person_name(value: str) -> str:
    value = value.strip()

    if not 2 <= len(value) <= 23:
        raise ValueError(
            "Name must contain 2 to 23 characters."
        )

    if not re.fullmatch(r"[A-Za-z]+(?: [A-Za-z]+)*", value):
        raise ValueError(
            "Name must contain letters and single spaces only."
        )

    if re.search(r"(.)\1\1", value, re.IGNORECASE):
        raise ValueError(
            "Name cannot contain three identical consecutive letters."
        )

    if value != value.title():
        raise ValueError(
            "Capitalize the first letter of each name."
        )

    return value


def validate_security_answer(value: SecretStr) -> SecretStr:
    answer = value.get_secret_value().strip()

    if not 2 <= len(answer) <= 50:
        raise ValueError(
            "Security answer must contain 2 to 50 characters."
        )

    if not re.fullmatch(r"[A-Za-z]+(?: [A-Za-z]+)*", answer):
        raise ValueError(
            "Security answer must contain letters and single spaces only."
        )

    return SecretStr(answer)


class StaffRegistrationRequest(BaseModel):
    # Hidden anti-bot field; genuine registrants leave this empty.
    # Optional to keep existing clients working.
    website: str = Field(default="", max_length=2048)

    # Admin invitation
    invitation_token: str = Field(
        min_length=20,
        max_length=256,
    )

    # Required ID number
    id_number: str

    # Personal information
    first_name: str
    middle_name: str | None = None
    family_name: str

    # Either Jr., Sr., or a permitted Roman numeral
    extension_name: str | None = None

    birthdate: date

    # Address
    region: str = Field(min_length=1, max_length=100)
    province: str = Field(min_length=1, max_length=100)
    city_municipality: str = Field(min_length=1, max_length=100)
    barangay: str = Field(min_length=1, max_length=100)
    street_address: str = Field(min_length=1, max_length=150)
    postal_code: str = Field(min_length=4, max_length=10)

    # Account credentials
    username: str = Field(min_length=6, max_length=19)
    password: SecretStr
    confirm_password: SecretStr

    # Seed 33 security questions
    security_answer_q4: SecretStr
    security_answer_q7: SecretStr
    security_answer_q1: SecretStr

    # Four approved PeakGym staff fields
    staff_position: str
    employment_type: str
    date_hired: date
    emergency_contact_number: str

    privacy_consent: bool

    @field_validator("staff_position")
    @classmethod
    def check_staff_position(cls, value):
        allowed = {"Trainer", "Receptionist", "Maintenance", "Manager"}
        if value not in allowed:
            raise ValueError("Staff position must be Trainer, Receptionist, Maintenance, or Manager.")
        return value

    @field_validator("employment_type")
    @classmethod
    def check_employment_type(cls, value):
        if value not in {"Full-time", "Part-time"}:
            raise ValueError("Employment type must be Full-time or Part-time.")
        return value

    @field_validator("date_hired")
    @classmethod
    def check_date_hired(cls, value):
        if value > date.today():
            raise ValueError("Date hired cannot be in the future.")
        return value

    @field_validator("emergency_contact_number")
    @classmethod
    def check_emergency_contact_number(cls, value):
        value = value.strip()
        if not re.fullmatch(r"(?:09\d{9}|\+639\d{9})", value):
            raise ValueError("Use a Philippine mobile number: 09XXXXXXXXX or +639XXXXXXXXX.")
        return value

    @field_validator("id_number")
    @classmethod
    def check_id_number(cls, value):
        if not re.fullmatch(r"\d{4}-\d{4}", value):
            raise ValueError(
                "ID Number must follow xxxx-xxxx format."
            )
        return value

    @field_validator(
        "first_name",
        "family_name",
    )
    @classmethod
    def check_required_name(cls, value):
        return validate_person_name(value)

    @field_validator("middle_name")
    @classmethod
    def check_middle_name(cls, value):
        if value is None or not value.strip():
            return None
        return validate_person_name(value)

    @field_validator("extension_name")
    @classmethod
    def check_extension(cls, value):
        if value is None or not value.strip():
            return None

        allowed = {
            "Jr.",
            "Sr.",
            "I",
            "II",
            "III",
            "IV",
            "IX",
            "X",
        }

        if value not in allowed:
            raise ValueError(
                "Choose Jr., Sr., or an allowed Roman numeral."
            )

        return value

    @field_validator("birthdate")
    @classmethod
    def check_birthdate(cls, value):
        if value > date.today():
            raise ValueError(
                "Birthdate cannot be in the future."
            )

        if not is_adult(value):
            raise ValueError(
                "You must be at least 18 years old to register."
            )

        return value

    @field_validator("username")
    @classmethod
    def check_username(cls, value):
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", value):
            raise ValueError(
                "Username must start with a letter "
                "and contain letters and digits only."
            )

        return value

    @field_validator(
        "security_answer_q4",
        "security_answer_q7",
        "security_answer_q1",
    )
    @classmethod
    def check_answers(cls, value):
        return validate_security_answer(value)

    @model_validator(mode="after")
    def check_registration(self):
        password = self.password.get_secret_value()
        confirmation = self.confirm_password.get_secret_value()

        if not 11 <= len(password) <= 64:
            raise ValueError(
                "Password must contain 11 to 64 characters."
            )

        if password != confirmation:
            raise ValueError(
                "Passwords do not match."
            )

        if not self.privacy_consent:
            raise ValueError(
                "You must accept the Privacy Notice."
            )

        return self