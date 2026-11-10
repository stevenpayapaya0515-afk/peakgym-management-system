
import logging

from app.security.email_service import send_email

logger = logging.getLogger(__name__)


def send_login_lockout_alert(
    *,
    email: str,
    username: str,
    attempts: int,
    lockout_seconds: int,
) -> None:
    """Notify the account owner about a login lockout."""

    if not email:
        logger.warning(
            "Cannot send lockout notification: no account email."
        )
        return

    subject = "PeakGym Security Alert - Failed Login Attempts"

    body_text = f"""
PeakGym Management System
SECURITY ALERT

Hello {username},

We detected multiple unsuccessful login attempts
on your PeakGym account.

Failed password attempts: {attempts}
Temporary lockout: {lockout_seconds} seconds

If these attempts were yours, please wait until
the lockout expires before trying again.

If you did not attempt to sign in, someone may
be trying to access your account.

We recommend reviewing your account security
and changing your password.

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

        if delivered is False:
            logger.warning(
                "Login lockout alert delivery was not confirmed."
            )

    except Exception:
        # Email delivery must never bypass or undo a lockout.
        logger.exception(
            "Unable to send login lockout notification."
        )
