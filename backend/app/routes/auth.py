"""Authenticate browser cookies and native Bearer sessions with the same idle policy."""
import hmac

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jwt.exceptions import InvalidTokenError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.security.captcha import create_captcha_challenge
from app.security.session import (
    SESSION_COOKIE_NAME,
    clear_session_cookie,
    revoke_session,
    revoke_session_id,
    set_session_cookie,
    validate_session,
    validate_session_id,
)
from app.security.token import decode_access_token, password_token_stamp

router = APIRouter(prefix="/auth", tags=["Authentication"])
bearer_scheme = HTTPBearer(auto_error=False)


def _reject(detail: str):
    raise HTTPException(
        status_code=401,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(
    request: Request,
    response: Response,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    # Browser cookies take priority. Never allow an invalid cookie to fall back
    # to a different Authorization credential on the same request.
    cookie_token = request.cookies.get(SESSION_COOKIE_NAME)
    if cookie_token:
        session = validate_session(db, cookie_token)
        if not session:
            _reject("Your session has expired. Please log in again.")
        user = db.query(User).filter(User.id == session["user_id"]).first()
        if not user or not user.is_active:
            _reject("Your account is unavailable. Please log in again.")
        # Sliding browser cookie expiration matches the server idle deadline.
        set_session_cookie(response, cookie_token)
        return user

    if credentials is None:
        _reject("Please log in to access this resource.")
    try:
        payload = decode_access_token(credentials.credentials)
    except InvalidTokenError:
        _reject("Invalid or expired access token.")

    # Only JWTs issued after password + email OTP are accepted.
    if payload.get("amr") != ["pwd", "otp"]:
        _reject("Please log in again with email verification.")
    user_id = payload.get("sub")
    if not user_id or not str(user_id).isdigit():
        _reject("Invalid access token.")
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        _reject("User not found.")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="This account is inactive")

    # A password change also invalidates previously issued native JWTs.
    stamp = payload.get("pwdv")
    expected = password_token_stamp(user.password)
    if not isinstance(stamp, str) or not hmac.compare_digest(stamp, expected):
        _reject("Your session is no longer valid. Please log in again.")

    session_id = payload.get("sid")
    if type(session_id) is not int or not validate_session_id(db, session_id, user.id):
        _reject("Your session has expired due to inactivity. Please log in again.")
    return user


@router.post("/session/logout")
def logout_current_session(
    request: Request,
    response: Response,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    """Always clear a browser cookie; revoke valid browser/native sessions."""
    cookie_token = request.cookies.get(SESSION_COOKIE_NAME)
    if cookie_token:
        revoke_session(db, cookie_token)
    clear_session_cookie(response)

    if credentials is not None:
        try:
            payload = decode_access_token(credentials.credentials)
            sid, sub = payload.get("sid"), payload.get("sub")
            if type(sid) is int and sub is not None and str(sub).isdigit():
                revoke_session_id(db, sid, int(sub))
        except InvalidTokenError:
            pass  # Expired JWT: still clear any browser cookie and local auth.
    return {"message": "Session ended."}


@router.get("/captcha")
def get_login_captcha(db: Session = Depends(get_db)):
    return create_captcha_challenge(db)


@router.post("/login", include_in_schema=False)
def legacy_login_disabled():
    raise HTTPException(
        status_code=410,
        detail="Legacy login is disabled. Use CAPTCHA and email OTP authentication.",
    )


@router.get("/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "role": current_user.role,
    }
