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

    if user.role == "staff" and not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="This account is inactive"
        )

    return user

@router.post("/login")
def login(credentials: LoginRequest, db: Session = Depends(get_db)):

    user = db.query(User).filter(
        User.username == credentials.username
    ).first()

    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid username or password"
        )

    # Block inactive staff accounts.
    if user.role == "staff" and not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="This account is inactive. Contact the administrator."
        )

    now = datetime.now()

    # Check whether the account is currently locked.
    if user.locked_until and user.locked_until > now:
        remaining = int((user.locked_until - now).total_seconds())
        remaining = max(1, remaining)

        raise HTTPException(
            status_code=429,
            detail=f"Too many failed attempts. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)}
        )

    # Reset expired lockout.
    if user.locked_until and user.locked_until <= now:
        user.failed_attempts = 0
        user.locked_until = None

    # Verify the existing PHP bcrypt password.
    if not verify_password(credentials.password, user.password):

        user.failed_attempts += 1

        if user.failed_attempts >= 5:
            user.failed_attempts = 5
            user.locked_until = now + timedelta(seconds=60)
            db.commit()

            raise HTTPException(
                status_code=429,
                detail="Too many failed attempts. Account locked for 60 seconds.",
                headers={"Retry-After": "60"}
            )

        db.commit()

        raise HTTPException(
            status_code=401,
            detail="Invalid username or password"
        )

    # Successful login: reset failed attempts.
    user.failed_attempts = 0
    user.locked_until = None
    db.commit()

    # Generate JWT access token.
    access_token = create_access_token({
        "sub": str(user.id),
        "role": user.role
    })

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "role": user.role
        }
    }

@router.get("/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "role": current_user.role
    }