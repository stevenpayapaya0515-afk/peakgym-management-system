from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.schemas.auth import LoginRequest
from app.security.password import verify_password
from app.security.token import create_access_token

from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jwt.exceptions import InvalidTokenError
from app.security.token import decode_access_token
from app.security.password import verify_password
from app.security.token import create_access_token
from app.security.captcha import create_captcha_challenge
import hmac
from app.security.token import password_token_stamp

router = APIRouter(prefix="/auth", tags=["Authentication"])

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db)
):
    try:
        payload = decode_access_token(credentials.credentials)
    except InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"}
        )
    
    # Only accept tokens issued after password and OTP verification.
    if payload.get("amr") != ["pwd", "otp"]:
        raise HTTPException(
            status_code=401,
            detail="Please log in again with email verification.",
            headers={"WWW-Authenticate": "Bearer"}
        )

    user_id = payload.get("sub")

    if not user_id or not str(user_id).isdigit():
        raise HTTPException(
            status_code=401,
            detail="Invalid access token"
        )

    user = db.query(User).filter(User.id == int(user_id)).first()

    if not user:
        raise HTTPException(
            status_code=401,
            detail="User not found"
        )

    if not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="This account is inactive"
        )

    # Reject tokens issued before the latest password change.
    token_stamp = payload.get("pwdv")
    expected_stamp = password_token_stamp(user.password)

    if (
        not isinstance(token_stamp, str)
        or not hmac.compare_digest(token_stamp, expected_stamp)
    ):
        raise HTTPException(
            status_code=401,
            detail="Your session is no longer valid. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user



# =====================================
# LOGIN CAPTCHA
# =====================================

@router.get("/captcha")
def get_login_captcha(
    db: Session = Depends(get_db)
):
    return create_captcha_challenge(db)


# =====================================
# LEGACY LOGIN - DISABLED
# =====================================

@router.post("/login", include_in_schema=False)
def legacy_login_disabled():
    raise HTTPException(
        status_code=410,
        detail=(
            "Legacy login is disabled. "
            "Use CAPTCHA and email OTP authentication."
        )
    )

@router.get("/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "role": current_user.role
    }