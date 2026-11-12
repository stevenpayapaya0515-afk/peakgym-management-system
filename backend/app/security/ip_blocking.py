"""Server-enforced IP blocking for PeakGym's username/password login.

11 incorrect passwords from one source IP within 10 minutes blocks it for
10 minutes, independent of the usernames being attempted. IP is obtained
from ASGI Request.client.host, NOT a caller-supplied X-Forwarded-For value.

ActivityLog and IPBlock timestamps are naive Philippine local time, matching
the existing PeakGym activity logger and MySQL configuration.
"""
from datetime import datetime, timedelta
from math import ceil

from fastapi import HTTPException, Request
from sqlalchemy import func
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from app.models.activity_log import ActivityLog
from app.models.ip_block import IPBlock
from app.security.activity_logger import record_security_event
from app.security.policy import (
    IP_BLOCK_THRESHOLD,
    IP_BLOCK_WINDOW_MINUTES,
    IP_BLOCK_DURATION_MINUTES,
)


def client_ip(request: Request) -> str | None:
    """Use the server-observed client address, not an arbitrary client header."""
    return request.client.host if request.client else None


def seconds_blocked(db: Session, ip: str | None, now: datetime | None = None) -> int:
    if not ip:
        return 0
    row = db.query(IPBlock).filter(IPBlock.ip_address == ip).first()
    current = now or datetime.now()
    if row is None or row.blocked_until is None or row.blocked_until <= current:
        return 0
    return max(1, ceil((row.blocked_until - current).total_seconds()))


def reject_blocked_ip(db: Session, request: Request) -> None:
    """Use on BOTH login/start and login/verify-otp before authentication."""
    remaining = seconds_blocked(db, client_ip(request))
    if remaining:
        raise HTTPException(
            status_code=429,
            detail=f"Too many failed logins from this IP. Try again in {remaining} seconds.",
            headers={"Retry-After": str(remaining)},
        )


def _ensure_ip_row_and_lock(db: Session, ip: str) -> IPBlock:
    """The unique IP row serializes concurrent attempts on MySQL/InnoDB."""
    dialect = db.get_bind().dialect.name
    values = {"ip_address": ip, "blocked_until": None}
    if dialect == "mysql":
        db.execute(mysql_insert(IPBlock.__table__).values(**values).prefix_with("IGNORE"))
    elif dialect == "sqlite":  # Test support. Production database is MySQL.
        db.execute(sqlite_insert(IPBlock.__table__).values(**values).on_conflict_do_nothing(
            index_elements=["ip_address"]
        ))
    else:
        raise RuntimeError("IP blocking is configured for MySQL; test mode supports SQLite")
    return (
        db.query(IPBlock)
        .filter(IPBlock.ip_address == ip)
        .with_for_update()
        .one()
    )


def block_after_failed_password(
    db: Session,
    request: Request,
    *,
    username: str,
    user_id: int | None,
) -> int:
    """Call after recording login_failed, BEFORE committing its transaction.

    Returns block seconds, or 0. Caller performs exactly one db.commit().
    Usernames are not used to count failures: the IP is the only key.
    """
    ip = client_ip(request)
    if not ip:
        return 0
    row = _ensure_ip_row_and_lock(db, ip)
    now = datetime.now()
    if row.blocked_until and row.blocked_until > now:
        return max(1, ceil((row.blocked_until - now).total_seconds()))

    # The caller queued the failed-login activity event. Flush it into the
    # transaction so the count includes this newest attempt.
    db.flush()
    failures = (
        db.query(func.count(ActivityLog.id))
        .filter(
            ActivityLog.ip_address == ip,
            ActivityLog.event_type.in_(("login_failed", "LOGIN_FAILED")),
            ActivityLog.created_at >= now - timedelta(minutes=IP_BLOCK_WINDOW_MINUTES),
            ActivityLog.created_at <= now + timedelta(seconds=5),
        )
        .scalar()
    ) or 0
    if failures < IP_BLOCK_THRESHOLD:
        return 0

    seconds = IP_BLOCK_DURATION_MINUTES * 60
    row.blocked_until = now + timedelta(seconds=seconds)
    record_security_event(
        db,
        event_type="ip_blocked",
        request=request,
        user_id=user_id,
        username_typed=username,
        details=(
            f"IP blocked for {IP_BLOCK_DURATION_MINUTES} minutes "
            f"after {failures} failed logins within {IP_BLOCK_WINDOW_MINUTES} minutes"
        ),
    )
    return seconds
