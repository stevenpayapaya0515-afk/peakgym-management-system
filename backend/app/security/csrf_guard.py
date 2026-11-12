"""Enforce one-time CSRF tokens on state-changing API requests.

The invitation creation route already consumes an identical token itself.
This middleware deliberately exempts that route to prevent double consumption.
"""

from fastapi import Request
from fastapi.responses import JSONResponse

from app.database import SessionLocal
from app.security.activity_logger import record_security_event
from app.security.csrf import verify_csrf_token

_MUTATING_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})
_ROUTE_WITH_OWN_CSRF_CHECK = frozenset({"/invitations/"})


async def csrf_protect_request(request: Request, call_next):
    if (
        request.method not in _MUTATING_METHODS
        or request.url.path in _ROUTE_WITH_OWN_CSRF_CHECK
    ):
        return await call_next(request)

    provided_token = request.headers.get("x-csrf-token")
    with SessionLocal() as db:
        allowed = verify_csrf_token(db, provided_token)
        if not allowed:
            # This must not log the token itself, passwords, or OTPs.
            record_security_event(
                db,
                event_type="csrf_rejected",
                request=request,
                details=f"CSRF rejected: {request.method} {request.url.path[:120]}",
            )
            db.commit()

    if not allowed:
        return JSONResponse(
            status_code=403,
            content={"detail": "Invalid or expired CSRF token."},
            headers={
                "X-Frame-Options": "DENY",
                "X-Content-Type-Options": "nosniff",
            },
        )

    return await call_next(request)
