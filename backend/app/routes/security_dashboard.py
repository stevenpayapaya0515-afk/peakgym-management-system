"""Read-only, administrator-only monitoring from PeakGym's activity log.

MySQL ActivityLog.created_at is a naive local datetime. This application expects
its MySQL server clock to use Philippine time, matching scripts/monitor.py.
No activity rows are modified by this endpoint.
"""
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.activity_log import ActivityLog
from app.models.ip_block import IPBlock
from app.models.security_flag import SecurityFlag
from app.models.user import User
from app.routes.auth import get_current_user


router = APIRouter(prefix="/security-monitoring", tags=["Security Monitoring"])
PHT = ZoneInfo("Asia/Manila")
LOGIN_FAILED_TYPES = ("login_failed", "LOGIN_FAILED")


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Require an active account with the administrator role."""
    if current_user.role != "admin" or not current_user.is_active:
        raise HTTPException(status_code=403, detail="Administrator access required.")
    return current_user


def build_hourly_series(events: list, now: datetime) -> list[dict]:
    """24 ordered, hour-aligned buckets; usable in isolated unit tests."""
    first_hour = (now - timedelta(hours=23)).replace(
        minute=0, second=0, microsecond=0
    )
    buckets = [first_hour + timedelta(hours=i) for i in range(24)]
    counts = {hour: 0 for hour in buckets}
    for event in events:
        hour = event.created_at.replace(minute=0, second=0, microsecond=0)
        if hour in counts:
            counts[hour] += 1
    return [
        {
            "hour": hour.isoformat(timespec="minutes"),
            "label": hour.strftime("%H:%M"),
            "failed_logins": counts[hour],
        }
        for hour in buckets
    ]


@router.get("/overview")
def get_security_overview(
    limit: int = Query(default=50, ge=1, le=50),
    event_type: str | None = Query(default=None, max_length=50),
    username: str | None = Query(default=None, max_length=100),
    ip_address: str | None = Query(default=None, max_length=45),
    from_date: date | None = None,
    to_date: date | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Today's totals, last 24h statistics, filters and persisted findings.

    All filter values use bound SQLAlchemy query parameters. Filters affect only
    recent_activities; today / 24h metrics remain consistent across filters.
    """
    if from_date and to_date and from_date > to_date:
        raise HTTPException(status_code=422, detail="Start date must not be after end date.")

    now = datetime.now(PHT).replace(tzinfo=None)
    today_start = datetime.combine(now.date(), time.min)
    tomorrow = today_start + timedelta(days=1)
    last_24h = now - timedelta(hours=24)

    daily_rows = (
        db.query(ActivityLog.event_type, func.count(ActivityLog.id))
        .filter(ActivityLog.created_at >= today_start, ActivityLog.created_at < tomorrow)
        .group_by(ActivityLog.event_type)
        .all()
    )
    event_counts = {kind: int(count) for kind, count in daily_rows}

    def count(*names: str) -> int:
        return sum(event_counts.get(name, 0) for name in names)

    # Once IP enforcement is enabled, blocked_ips_now comes from persisted state.
    # OTP_SENT and ALERT_EMAIL_SENT are still not fully tracked.
    summary = {
        "successful_logins": count("login_success", "LOGIN_SUCCESS"),
        "failed_logins": count(*LOGIN_FAILED_TYPES),
        "accounts_locked_now": db.query(func.count(User.id)).filter(
            User.locked_until.isnot(None), User.locked_until > now
        ).scalar() or 0,
        "blocked_ips_now": db.query(func.count(IPBlock.id)).filter(
            IPBlock.blocked_until > now
        ).scalar() or 0,
        "otp_sent": None,
        "otp_failures": count(
            "login_otp_failed", "password_reset_otp_failed",
            "registration_otp_failed", "OTP_FAILED",
        ),
        "alert_emails_sent": None,
        "otp_expired": count("login_otp_expired"),
        "otp_limits": count("login_otp_limit"),
    }

    failed_events_24h = (
        db.query(ActivityLog.created_at)
        .filter(
            ActivityLog.event_type.in_(LOGIN_FAILED_TYPES),
            ActivityLog.created_at >= last_24h,
            ActivityLog.created_at <= now,
        )
        .all()
    )
    hourly_failures = build_hourly_series(failed_events_24h, now)

    top_rows = (
        db.query(ActivityLog.ip_address, func.count(ActivityLog.id).label("failures"))
        .filter(
            ActivityLog.event_type.in_(LOGIN_FAILED_TYPES),
            ActivityLog.created_at >= last_24h,
            ActivityLog.created_at <= now,
            ActivityLog.ip_address.isnot(None),
            ActivityLog.ip_address != "",
        )
        .group_by(ActivityLog.ip_address)
        .order_by(func.count(ActivityLog.id).desc(), ActivityLog.ip_address)
        .limit(5)
        .all()
    )
    active_blocks = {
        row.ip_address: row.blocked_until
        for row in db.query(IPBlock).filter(IPBlock.blocked_until > now).all()
    }
    top_ips = [
        {
            "ip_address": ip,
            "failures": int(failures),
            "blocked": ip in active_blocks,
            "block_status": (
                f"Blocked until {active_blocks[ip].strftime('%H:%M:%S')} PHT"
                if ip in active_blocks else "Not blocked"
            ),
        }
        for ip, failures in top_rows
    ]

    activities_query = db.query(ActivityLog)
    if event_type:
        activities_query = activities_query.filter(ActivityLog.event_type == event_type)
    if username:
        activities_query = activities_query.filter(
            ActivityLog.username_typed.ilike(f"%{username.strip()}%")
        )
    if ip_address:
        activities_query = activities_query.filter(
            ActivityLog.ip_address.ilike(f"%{ip_address.strip()}%")
        )
    if from_date:
        activities_query = activities_query.filter(
            ActivityLog.created_at >= datetime.combine(from_date, time.min)
        )
    if to_date:
        activities_query = activities_query.filter(
            ActivityLog.created_at < datetime.combine(to_date + timedelta(days=1), time.min)
        )
    latest_events = (
        activities_query.order_by(ActivityLog.id.desc()).limit(limit).all()
    )
    activities = [
        {
            "id": event.id,
            "event_type": event.event_type,
            "username": event.username_typed,
            "user_id": event.user_id,
            "ip_address": event.ip_address,
            "details": event.details,
            "created_at": event.created_at.isoformat() if event.created_at else None,
        }
        for event in latest_events
    ]
    event_types = [
        kind for (kind,) in db.query(ActivityLog.event_type)
        .distinct().order_by(ActivityLog.event_type).all()
    ]

    flags = (
        db.query(SecurityFlag).order_by(SecurityFlag.id.desc()).limit(50).all()
    )
    security_flags = [
        {
            "id": flag.id, "pattern": flag.pattern, "target": flag.target,
            "severity": flag.severity, "description": flag.description,
            "flag_date": flag.flag_date.isoformat() if flag.flag_date else None,
        }
        for flag in flags
    ]

    return {
        "summary": summary,
        "event_counts": event_counts,
        "hourly_failures": hourly_failures,
        "top_ips": top_ips,
        "event_types": event_types,
        "recent_activities": activities,
        "security_flags": security_flags,
        "read_only": True,
        "timezone": "Asia/Manila",
        "refreshed_at": now.isoformat(timespec="seconds"),
        "metrics_note": (
            "Summary: today (PHT). Hourly failures and top IPs: last 24 hours. "
            "IP blocks are enforced. OTP-sent and alert-sent counts are not tracked yet."
        ),
    }
