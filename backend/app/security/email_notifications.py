"""Gmail security notifications and append-only email delivery audit.

Email sends happen AFTER password changes are committed. Delivery failures are
logged server-side and never roll back a successful password change.
"""
import logging
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from app.database import SessionLocal
from app.models.activity_log import ActivityLog
from app.security.email_service import send_email

logger = logging.getLogger(__name__)
PHT = ZoneInfo("Asia/Manila")


def record_sent_email(*, event_type: str, username: str | None,
                      user_id: int | None, ip_address: str | None,
                      user_agent: str | None, details: str) -> bool:
    """Add an event only after the Gmail API accepts a message.

    Independent transaction: never reuse an expired FastAPI request DB session.
    The log does not include OTP values, answers, passwords, or recipient emails.
    """
    try:
        with SessionLocal() as db:
            db.add(ActivityLog(
                event_type=event_type[:50],
                username_typed=username[:100] if username else None,
                user_id=user_id,
                ip_address=ip_address[:45] if ip_address else None,
                user_agent=(user_agent or "")[:512],
                details=details[:500],
            ))
            db.commit()
        return True
    except Exception:
        logger.exception("Unable to audit successful %s email send", event_type)
        return False


def audit_otp_sent(*, purpose: str, request, username: str | None,
                   user_id: int | None = None) -> bool:
    """Call only when send_otp_email returned True."""
    return record_sent_email(
        event_type="otp_sent",
        username=username,
        user_id=user_id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent", ""),
        details=f"Gmail accepted {purpose} OTP email",
    )


def send_password_changed_notice(*, email: str, username: str,
                                  user_id: int, ip_address: str | None,
                                  user_agent: str | None, method: str) -> None:
    """Background task: notify account owner; never expose credentials."""
    when = datetime.now(PHT).strftime("%Y-%m-%d %I:%M:%S %p PHT")
    web_url = os.getenv("PEAKGYM_WEB_URL", "http://localhost:3000").rstrip("/")
    body = (
        "PeakGym Management System\n\n"
        f"Hello {username},\n\n"
        "Your password was changed successfully.\n\n"
        f"Date and time: {when}\n"
        f"Action: {method}\n"
        f"IP address: {ip_address or 'Unavailable'}\n"
        f"Browser or device: {(user_agent or 'Unavailable')[:200]}\n\n"
        "If this was not you, reset your password now using\n"
        f"the Forgot password? link at {web_url}\n"
        "and contact your administrator.\n\n"
        "We never include your password or OTP in this email.\n"
        "PeakGym Management System\n"
    )
    try:
        accepted = send_email(
            recipient=email,
            subject="Your password was changed - PeakGym",
            body_text=body,
        )
        if accepted is True:
            record_sent_email(
                event_type="alert_email_sent",
                username=username,
                user_id=user_id,
                ip_address=ip_address,
                user_agent=user_agent,
                details=f"Password-change confirmation accepted by Gmail ({method})",
            )
        else:
            logger.warning("Gmail did not confirm password-change notification")
    except Exception:
        logger.exception("Unable to send password-change confirmation")
