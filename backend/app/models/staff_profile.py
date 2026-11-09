from datetime import datetime, timezone

from sqlalchemy import (
    Column,
    Integer,
    String,
    Date,
    DateTime,
    ForeignKey,
    Text,
)

from app.database import Base


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class StaffProfile(Base):
    __tablename__ = "staff_profiles"

    id = Column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )

    # Links to the existing users table.
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="RESTRICT"),
        unique=True,
        nullable=False,
        index=True,
    )

    # Instructor-format staff ID, nullable for legacy rows.
    # This is unique but not yet the database primary key.
    id_number = Column(String(9), unique=True, nullable=True)

    # Personal information
    first_name = Column(String(23), nullable=False)
    middle_name = Column(String(23), nullable=True)
    family_name = Column(String(23), nullable=False)
    extension_name = Column(String(10), nullable=True)

    birthdate = Column(Date, nullable=False)

    # Address information
    region = Column(String(100), nullable=False)
    province = Column(String(100), nullable=False)
    city_municipality = Column(String(100), nullable=False)
    barangay = Column(String(100), nullable=False)

    # Store only AES-256-GCM encrypted street address.
    street_address_encrypted = Column(
        Text,
        nullable=False,
    )

    postal_code = Column(String(10), nullable=False)

    # Staff fields are nullable for existing legacy staff profiles.
    # Newly invited registrations require all four in the schema.
    staff_position = Column(String(20), nullable=True)
    employment_type = Column(String(10), nullable=True)
    date_hired = Column(Date, nullable=True)
    emergency_contact_number = Column(String(13), nullable=True)

    # Store only hashes, never plaintext answers.
    security_answer_q4_hash = Column(
        String(255),
        nullable=False,
    )

    security_answer_q7_hash = Column(
        String(255),
        nullable=False,
    )

    security_answer_q1_hash = Column(
        String(255),
        nullable=False,
    )

    # Privacy consent
    privacy_consent_at = Column(
        DateTime,
        nullable=False,
    )

    created_at = Column(
        DateTime,
        default=utc_now,
        nullable=False,
    )

    updated_at = Column(
        DateTime,
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )