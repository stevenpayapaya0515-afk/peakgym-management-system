"""Isolated Protection 6 cookie/JWT test; never opens MySQL or sends email.

Run in backend: .\\.venv\\Scripts\\python.exe tests/test_session_cookie_isolated.py
"""
import os
import sys
from pathlib import Path
from types import ModuleType
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("JWT_SECRET_KEY", "isolated-test-key-never-for-production")

# Replace only the database engine module before importing application models.
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

fake_database = ModuleType("app.database")
fake_database.Base = declarative_base()
fake_database.get_db = lambda: None
sys.modules["app.database"] = fake_database

from app.models.user import User
from app.models.user_session import UserSession
from app.security.session import (
    SESSION_COOKIE_NAME, create_session, set_session_cookie,
    validate_session,
)
from app.security.token import create_access_token, password_token_stamp
from app.routes.auth import get_current_user, logout_current_session
from fastapi import HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials
from starlette.requests import Request


def request(cookie=None):
    headers = []
    if cookie:
        headers.append((b"cookie", f"{SESSION_COOKIE_NAME}={cookie}".encode()))
    return Request({
        "type": "http", "method": "GET", "path": "/auth/me",
        "headers": headers, "query_string": b"", "client": ("127.0.0.1", 50000),
        "scheme": "http", "server": ("127.0.0.1", 8000),
    })


def rejects(fn, status):
    try:
        fn()
    except HTTPException as exc:
        assert exc.status_code == status, exc.status_code
        return
    raise AssertionError(f"Expected HTTP {status} rejection")


if __name__ == "__main__":
    engine = create_engine("sqlite+pysqlite:///:memory:")
    User.__table__.create(engine)
    UserSession.__table__.create(engine)
    with sessionmaker(bind=engine)() as db:
        user = User(username="staff123", email="staff@example.test",
                    password="example-password-hash", role="staff", is_active=True)
        db.add(user)
        db.commit()
        db.refresh(user)

        session = create_session(db, user_id=user.id)
        cookie = session["session_token"]
        cookie_response = Response()
        set_session_cookie(cookie_response, cookie)
        header = cookie_response.headers["set-cookie"].lower()
        assert "httponly" in header and "samesite=lax" in header, header

        # Browser cookie requires no readable Authorization bearer token.
        response = Response()
        assert get_current_user(request(cookie), response, None, db).id == user.id
        assert response.headers.get("set-cookie"), "Sliding cookie not renewed"
        rejects(lambda: get_current_user(request(), Response(), None, db), 401)

        # Native JWT remains supported and bound to a database session.
        jwt_token = create_access_token({
            "sub": str(user.id), "amr": ["pwd", "otp"],
            "pwdv": password_token_stamp(user.password),
            "sid": session["session_id"],
        })
        bearer = HTTPAuthorizationCredentials(scheme="Bearer", credentials=jwt_token)
        assert get_current_user(request(), Response(), bearer, db).id == user.id

        # Revoke browser cookie; the logout invalidates any copied token too.
        logout_response = Response()
        assert logout_current_session(request(cookie), logout_response, None, db) == {
            "message": "Session ended."
        }
        assert "max-age=0" in logout_response.headers["set-cookie"].lower()
        assert validate_session(db, cookie) is None
        rejects(lambda: get_current_user(request(cookie), Response(), None, db), 401)
        rejects(lambda: get_current_user(request(), Response(), bearer, db), 401)

        # Simulate password-change session revocation (both transports).
        new_session = create_session(db, user_id=user.id)
        db.query(UserSession).filter(UserSession.user_id == user.id).update(
            {"revoked_at": datetime.now(timezone.utc).replace(tzinfo=None)}, synchronize_session=False)
        db.commit()
        assert validate_session(db, new_session["session_token"]) is None

    engine.dispose()
    print("PASS: HttpOnly/SameSite cookie, browser auth, native JWT, logout/revocation")
