import os
import secrets
import hashlib
import hmac

from pathlib import Path
from dotenv import load_dotenv

from app.security.policy import (
    OTP_LENGTH,
    OTP_MAX_ATTEMPTS,
    OTP_EXPIRY_MINUTES,
    OTP_RESEND_COOLDOWN_SECONDS,
    OTP_MAX_RESENDS,
    OTP_RESEND_WINDOW_MINUTES
)


BASE_DIR = Path(__file__).resolve().parents[2]

load_dotenv(BASE_DIR / ".env")


def generate_otp() -> str:
    """Generate a cryptographically secure six-digit OTP."""

    return f"{secrets.randbelow(10 ** OTP_LENGTH):0{OTP_LENGTH}d}"


def hash_otp(code: str) -> str:
    """Hash an OTP using a dedicated secret pepper."""

    if not isinstance(code, str):
        raise ValueError("Invalid OTP.")

    if len(code) != OTP_LENGTH or not code.isdigit():
        raise ValueError("OTP must contain exactly six digits.")

    pepper = os.getenv("OTP_PEPPER")

    if not pepper:
        raise RuntimeError("OTP_PEPPER is missing from backend/.env")

    return hmac.new(
        pepper.encode("utf-8"),
        code.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()


def verify_otp(code: str, stored_hash: str) -> bool:
    """Securely compare an entered OTP with its stored hash."""

    if not isinstance(code, str):
        return False

    if not isinstance(stored_hash, str):
        return False

    if len(code) != OTP_LENGTH or not code.isdigit():
        return False

    try:
        calculated_hash = hash_otp(code)

        return hmac.compare_digest(
            calculated_hash,
            stored_hash
        )

    except (ValueError, RuntimeError):
        return False