import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

# Student Security Configuration
# IT 107 - Final Laboratory Project
# Student ID: 241-00333

STUDENT_ID = "241-00333"

# =====================================
# STUDENT SEED
# =====================================

D1 = 3
D2 = 3


# =====================================
# USERNAME CONFIGURATION
# =====================================

MIN_USERNAME_LENGTH = 6
MAX_USERNAME_LENGTH = 19


# =====================================
# PASSWORD CONFIGURATION
# =====================================

MIN_PASSWORD_LENGTH = 11
MAX_PASSWORD_LENGTH = 64


# =====================================
# PERSONAL INFORMATION
# =====================================

MAX_NAME_FIELD_LENGTH = 23


# =====================================
# LOGIN SECURITY
# =====================================

FORGOT_PASSWORD_AFTER_FAILURES = 3

# (failed attempts, lockout duration in seconds)
LOCKOUT_TIERS = (
    (3, 18),
    (6, 36),
    (9, 72),
)


# =====================================
# OTP CONFIGURATION
# =====================================

OTP_LENGTH = 6
OTP_EXPIRY_MINUTES = 3
OTP_MAX_ATTEMPTS = 3

OTP_RESEND_COOLDOWN_SECONDS = 60
OTP_MAX_RESENDS = 3
OTP_RESEND_WINDOW_MINUTES = 15


# =====================================
# CAPTCHA CONFIGURATION
# =====================================

CAPTCHA_LENGTH = 6
CAPTCHA_EXPIRY_MINUTES = 5


# =====================================
# SESSION SECURITY
# =====================================

# The class demonstration uses 60s idle + 15s warning.
# Normal graded seed remains 8 minutes idle + 1 minute warning.
SESSION_DEMO_MODE = os.getenv("SESSION_DEMO_MODE", "false").lower() == "true"
IDLE_SESSION_TIMEOUT_MINUTES = 8
SESSION_WARNING_BEFORE_MINUTES = 1
IDLE_SESSION_TIMEOUT_SECONDS = 60 if SESSION_DEMO_MODE else 8 * 60
SESSION_WARNING_BEFORE_SECONDS = 15 if SESSION_DEMO_MODE else 60


# =====================================
# IP BLOCKING
# =====================================

IP_BLOCK_THRESHOLD = 11
IP_BLOCK_WINDOW_MINUTES = 10
IP_BLOCK_DURATION_MINUTES = 10


# =====================================
# AUTHENTICATION QUESTIONS
# =====================================

AUTH_QUESTION_A = 4
AUTH_QUESTION_B = 7
AUTH_QUESTION_C = 1

AUTH_QUESTION_IDS = (
    AUTH_QUESTION_A,
    AUTH_QUESTION_B,
    AUTH_QUESTION_C,
)


# =====================================
# CSRF CONFIGURATION
# =====================================

CSRF_TOKEN_EXPIRY_MINUTES = 10
CSRF_TOKEN_LENGTH = 32