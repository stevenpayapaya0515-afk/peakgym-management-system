import bcrypt
import hashlib

from app.security.policy import (
    MIN_PASSWORD_LENGTH,
    MAX_PASSWORD_LENGTH
)


def password_strength(password: str) -> str:
    if not isinstance(password, str):
        return "Weak"

    if len(password) < MIN_PASSWORD_LENGTH:
        return "Weak"

    if len(password) > MAX_PASSWORD_LENGTH:
        return "Weak"

    categories = sum([
        any(c.islower() for c in password),
        any(c.isupper() for c in password),
        any(c.isdigit() for c in password),
        any(not c.isalnum() for c in password),
    ])

    if categories < 3:
        return "Weak"

    if len(password) >= 14 and categories == 4:
        return "Strong"

    return "Medium"


def validate_password(password: str) -> tuple[bool, str]:
    if not isinstance(password, str):
        return False, "Password is required."

    if len(password) < MIN_PASSWORD_LENGTH:
        return False, f"Password must contain at least {MIN_PASSWORD_LENGTH} characters."

    if len(password) > MAX_PASSWORD_LENGTH:
        return False, f"Password cannot exceed {MAX_PASSWORD_LENGTH} characters."

    strength = password_strength(password)

    if strength == "Weak":
        return False, "Password must contain at least three character types: uppercase, lowercase, numbers or symbols."

    return True, strength


def hash_password(password: str) -> str:
    if not isinstance(password, str) or not password:
        raise ValueError("Password cannot be empty.")

    # SHA-256 pre-hashing prevents bcrypt's 72-byte truncation.
    password_bytes = hashlib.sha256(
        password.encode("utf-8")
    ).digest()

    hashed = bcrypt.hashpw(
        password_bytes,
        bcrypt.gensalt(rounds=12)
    )

    return "bcrypt-sha256$" + hashed.decode("utf-8")


def verify_password(
    plain_password: str,
    hashed_password: str
) -> bool:

    if not isinstance(plain_password, str):
        return False

    if not isinstance(hashed_password, str):
        return False

    try:
        if hashed_password.startswith("bcrypt-sha256$"):

            stored_hash = hashed_password.split("$", 1)[1]

            password_bytes = hashlib.sha256(
                plain_password.encode("utf-8")
            ).digest()

        else:
            # Backward compatibility with existing PHP/Python bcrypt.
            if hashed_password.startswith("$2y$"):
                hashed_password = "$2b$" + hashed_password[4:]

            stored_hash = hashed_password
            password_bytes = plain_password.encode("utf-8")

        return bcrypt.checkpw(
            password_bytes,
            stored_hash.encode("utf-8")
        )

    except (ValueError, TypeError):
        return False