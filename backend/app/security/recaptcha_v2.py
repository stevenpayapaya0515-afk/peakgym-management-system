"""Google reCAPTCHA v2 checkbox verification. Only FastAPI knows the secret."""
import os
import logging
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")
logger = logging.getLogger(__name__)
VERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"


def verify_recaptcha_v2(response_token: str) -> bool:
    """Verify the single-use token with Google and enforce its source hostname."""
    secret = os.getenv("RECAPTCHA_SECRET_KEY", "").strip()
    allowed = {
        host.strip().lower()
        for host in os.getenv("RECAPTCHA_ALLOWED_HOSTNAMES", "").split(",")
        if host.strip()
    }
    if not secret or not allowed:
        logger.error("reCAPTCHA v2 configuration is missing")
        return False
    if not isinstance(response_token, str) or not 20 <= len(response_token) <= 8192:
        return False
    try:
        result = requests.post(
            VERIFY_URL,
            data={"secret": secret, "response": response_token},
            timeout=8,
        )
        result.raise_for_status()
        verified = result.json()
    except (requests.RequestException, ValueError):
        logger.warning("reCAPTCHA verification could not be completed")
        return False
    hostname = str(verified.get("hostname") or "").lower()
    return verified.get("success") is True and hostname in allowed
