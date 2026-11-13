import os
from pathlib import Path
from datetime import datetime, timedelta, timezone
import hashlib
import hmac

import jwt
from app.security.private_config import load_private_env


load_private_env()

SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

if not SECRET_KEY:
    raise RuntimeError("JWT_SECRET_KEY is missing from the .env file")


def create_access_token(data: dict) -> str:
    to_encode = data.copy()

    expire = datetime.now(timezone.utc) + timedelta(
        minutes=ACCESS_TOKEN_EXPIRE_MINUTES
    )

    to_encode.update({"exp": expire})

    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        SECRET_KEY,
        algorithms=[ALGORITHM]
    )



# =====================================
# PASSWORD-BOUND JWT VERSION
# =====================================

def password_token_stamp(password_hash: str) -> str:
    """
    Generate a JWT validation stamp using
    the account's current password hash.
    """
    return hmac.new(
        SECRET_KEY.encode("utf-8"),
        password_hash.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
