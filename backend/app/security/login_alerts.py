
import logging

from app.security.email_service import send_email
from app.security.email_notifications import record_sent_email
from datetime import datetime
from zoneinfo import ZoneInfo
import os

logger = logging.getLogger(__name__)


def send_login_lockout_alert(
    *,
    email: str,
    username: str,
    attempts: int,
    lockout_seconds: int,
    user_id: int | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
) -> None:
    """Notify the account owner about a login lockout."""

    if not email:
        logger.warning(
            "Cannot send lockout notification: no account email."
        )
        return

    subject = "PeakGym Security Alert - Failed Login Attempts"
    when = datetime.now(ZoneInfo("Asia/Manila")).strftime("%Y-%m-%d %I:%M:%S %p PHT")
    web_url = os.getenv("PEAKGYM_WEB_URL", "http://localhost:3000").rstrip("/")

    body_text = f"""
PeakGym Management System
SECURITY ALERT

Hello {username},

We detected multiple unsuccessful login attempts
on your PeakGym account.

Failed password attempts: {attempts}
Temporary lockout: {lockout_seconds} seconds
Date and time: {when}
IP address: {ip_address or "Unavailable"}
Browser or device: {(user_agent or "Unavailable")[:200]}

If these attempts were yours, please wait until
the lockout expires before trying again.

If you did not attempt to sign in, someone may
be trying to access your account.

If this was not you, reset your password now using
the Forgot password? link at {web_url}
and contact your administrator.

Please never share your password or OTP codes.

PeakGym Management System
Security Notification
"""

    try:
        delivered = send_email(
            recipient=email,
            subject=subject,
            body_text=body_text,
        )

        if delivered is True:
            record_sent_email(
                event_type="alert_email_sent",
                username=username,
                user_id=user_id,
                ip_address=ip_address,
                user_agent=user_agent,
                details=f"Lockout alert accepted by Gmail; attempts={attempts}; duration={lockout_seconds}s",
            )
        else:
            logger.warning("Login lockout alert delivery was not confirmed.")

    except Exception:
        # Email delivery must never bypass or undo a lockout.
        logger.exception(
            "Unable to send login lockout notification."
        )
