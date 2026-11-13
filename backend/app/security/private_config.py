"""Runtime-only secret paths outside the Apache/XAMPP document root.

For the local PeakGym installation, keep credentials in:
    %USERPROFILE%/PeakGym_Secrets/.env
and Gmail OAuth material in:
    %USERPROFILE%/PeakGym_Secrets/gmail_api_test/

Do not fall back to backend/.env: that directory may be served by Apache.
"""
from pathlib import Path

from dotenv import load_dotenv

PRIVATE_DIR = Path.home() / "PeakGym_Secrets"
PRIVATE_ENV_FILE = PRIVATE_DIR / ".env"
GMAIL_PRIVATE_DIR = PRIVATE_DIR / "gmail_api_test"
PRIVATE_ERROR_LOG_DIR = PRIVATE_DIR / "logs"


def load_private_env() -> None:
    """Load the private configuration; existing OS environment takes precedence."""
    load_dotenv(PRIVATE_ENV_FILE, override=False)
