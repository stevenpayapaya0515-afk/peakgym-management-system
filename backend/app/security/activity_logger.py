
from fastapi import Request
from sqlalchemy.orm import Session

from app.models.activity_log import ActivityLog


def record_security_event(
    db: Session,
    *,
    event_type: str,
    request: Request,
    user_id: int | None = None,
    username_typed: str | None = None,
    details: str | None = None,
) -> None:
    """Add a security event to the current database transaction."""

    ip_address = (
        request.client.host
        if request.client is not None
        else None
    )

    user_agent = request.headers.get("user-agent", "")

    event = ActivityLog(
        event_type=event_type[:50],
        username_typed=(
            username_typed[:100]
            if username_typed is not None
            else None
        ),
        user_id=user_id,
        ip_address=ip_address,
        user_agent=user_agent[:512],
        details=details,
    )

    db.add(event)
    # The caller commits this event alongside the login changes.
