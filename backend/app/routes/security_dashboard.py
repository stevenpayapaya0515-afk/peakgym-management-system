
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.activity_log import ActivityLog
from app.models.user import User
from app.routes.auth import get_current_user


router = APIRouter(
    prefix="/security-monitoring",
    tags=["Security Monitoring"],
)


def require_admin(
    current_user: User = Depends(get_current_user),
) -> User:
    """Allow active administrators only."""

    if current_user.role != "admin" or not current_user.is_active:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required.",
        )

    return current_user


@router.get("/overview")
def get_security_overview(
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """
    Read-only security monitoring.

    Summarizes stored activity logs and returns
    the latest security events.
    """

    # Count security events by their recorded type.
    counts_query = (
        db.query(
            ActivityLog.event_type,
            func.count(ActivityLog.id),
        )
        .group_by(ActivityLog.event_type)
        .all()
    )

    event_counts = {
        event_type: int(count)
        for event_type, count in counts_query
    }

    # Summary cards use real MySQL activity data.
    summary = {
        "total_events": sum(event_counts.values()),
        "successful_logins": event_counts.get(
            "login_success", 0
        ),
        "failed_logins": event_counts.get(
            "login_failed", 0
        ),
        "account_lockouts": event_counts.get(
            "account_locked", 0
        ),
        "otp_failures": event_counts.get(
            "login_otp_failed", 0
        ),
        "otp_expired": event_counts.get(
            "login_otp_expired", 0
        ),
        "otp_limits": event_counts.get(
            "login_otp_limit", 0
        ),
    }

    # Fetch the most recent security events.
    # No activity record is modified or deleted.
    latest_events = (
        db.query(ActivityLog)
        .order_by(ActivityLog.id.desc())
        .limit(limit)
        .all()
    )

    activities = []

    for event in latest_events:
        activities.append({
            "id": event.id,
            "event_type": event.event_type,
            "username": event.username_typed,
            "user_id": event.user_id,
            "ip_address": event.ip_address,
            "details": event.details,
            "created_at": (
                event.created_at.isoformat()
                if event.created_at is not None
                else None
            ),
        })

    return {
        "summary": summary,
        "recent_activities": activities,
        "event_counts": event_counts,
        "read_only": True,
    }
