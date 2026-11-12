import os
import ssl
import smtplib
import re
import socket


from pathlib import Path
from html import escape
from email.message import EmailMessage
from email.utils import formataddr
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parents[2]

load_dotenv(BASE_DIR / ".env")

# =====================================
# FORCE IPV4 FOR SMTP
# =====================================

def _create_ipv4_socket(host, port, timeout):
    addresses = socket.getaddrinfo(
        host,
        port,
        family=socket.AF_INET,
        type=socket.SOCK_STREAM
    )

    last_error = None

    for family, socktype, proto, _, sockaddr in addresses:
        connection = socket.socket(
            family,
            socktype,
            proto
        )

        connection.settimeout(timeout)

        try:
            connection.connect(sockaddr)
            return connection

        except OSError as error:
            last_error = error
            connection.close()

    if last_error:
        raise last_error

    raise OSError("No IPv4 SMTP address available.")


class IPv4SMTP(smtplib.SMTP):

    def _get_socket(self, host, port, timeout):
        return _create_ipv4_socket(
            host,
            port,
            timeout
        )


class IPv4SMTP_SSL(smtplib.SMTP_SSL):

    def _get_socket(self, host, port, timeout):
        connection = _create_ipv4_socket(
            host,
            port,
            timeout
        )

        try:
            return self.context.wrap_socket(
                connection,
                server_hostname=host
            )

        except Exception:
            connection.close()
            raise

# =====================================
# SMTP CONFIGURATION
# =====================================

def get_smtp_settings():
    host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    port = int(os.getenv("SMTP_PORT", "587"))

    username = os.getenv("SMTP_USERNAME")
    password = os.getenv("SMTP_PASSWORD", "").replace(" ", "").strip()

    from_email = os.getenv("SMTP_FROM_EMAIL", username)
    from_name = os.getenv(
        "SMTP_FROM_NAME",
        "PeakGym Management System"
    )

    use_tls = os.getenv(
        "SMTP_USE_TLS", "true"
    ).lower() == "true"

    use_ssl = os.getenv(
        "SMTP_USE_SSL", "false"
    ).lower() == "true"

    timeout = int(os.getenv("SMTP_TIMEOUT_SECONDS", "15"))

    if not host or not username or not password or not from_email:
        raise RuntimeError(
            "SMTP configuration is incomplete. Check backend/.env."
        )

    if use_tls == use_ssl:
        raise RuntimeError(
            "Enable exactly one SMTP security mode: TLS or SSL."
        )

    if not 1 <= port <= 65535 or timeout <= 0:
        raise RuntimeError("Invalid SMTP port or timeout.")

    return {
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "from_email": from_email,
        "from_name": from_name,
        "use_tls": use_tls,
        "use_ssl": use_ssl,
        "timeout": timeout
    }


# =====================================
# EMAIL MESSAGE
# =====================================

def create_email_message(
    recipient: str,
    subject: str,
    body_text: str,
    body_html: str = None
) -> EmailMessage:

    if not isinstance(recipient, str):
        raise ValueError("Invalid recipient email.")

    recipient = recipient.strip()

    if len(recipient) > 254 or not re.fullmatch(
        r"[^@\s]+@[^@\s]+\.[^@\s]+",
        recipient
    ):
        raise ValueError("Invalid recipient email.")

    settings = get_smtp_settings()

    message = EmailMessage()

    message["Subject"] = subject

    message["From"] = formataddr((
        settings["from_name"],
        settings["from_email"]
    ))

    message["To"] = recipient

    message.set_content(body_text)

    if body_html:
        message.add_alternative(
            body_html,
            subtype="html"
        )

    return message


# =====================================
# SMTP CONNECTION
# =====================================

def _open_smtp_connection():
    settings = get_smtp_settings()

    context = ssl.create_default_context()

    if settings["use_ssl"]:
        server = IPv4SMTP_SSL(
            settings["host"],
            settings["port"],
            timeout=settings["timeout"],
            context=context
        )

    else:
        server = IPv4SMTP(
            settings["host"],
            settings["port"],
            timeout=settings["timeout"]
        )

        server.ehlo()

        server.starttls(context=context)

        server.ehlo()

    server.login(
        settings["username"],
        settings["password"]
    )

    return server


# =====================================
# SMTP CONNECTION TEST
# =====================================

def verify_smtp_connection() -> bool:

    server = None

    try:
        server = _open_smtp_connection()

        return True

    except (smtplib.SMTPException, OSError):
        logger.exception("SMTP connection test failed.")
        raise RuntimeError(
            "SMTP connection failed. Check your configuration."
        ) from None

    finally:
        if server is not None:
            try:
                server.quit()
            except Exception:
                server.close()


# =====================================
# OTP EMAIL
# =====================================

OTP_PURPOSES = {
    "register": (
        "Verify your PeakGym account",
        "Verify your account"
    ),
    "login": (
        "Your PeakGym log-in code",
        "Your log-in code"
    ),
    "reset": (
        "Your PeakGym password reset code",
        "Password reset code"
    ),
    "questions": (
        "Your PeakGym security questions verification code",
        "Security question update code"
    )
}


def send_otp_email(
    recipient: str,
    otp: str,
    purpose: str,
    expiry_minutes: int = 3
) -> bool:

    if purpose not in OTP_PURPOSES:
        raise ValueError("Invalid OTP purpose.")

    if not isinstance(otp, str) or not re.fullmatch(
        r"\d{6}", otp
    ):
        raise ValueError("OTP must contain six digits.")

    if not isinstance(expiry_minutes, int) or expiry_minutes <= 0:
        raise ValueError("Invalid OTP expiration.")

    subject, purpose_text = OTP_PURPOSES[purpose]

    body_text = f"""
PeakGym Management System

{purpose_text}

Your verification code is:

{otp}

This code expires in {expiry_minutes} minutes.

If you did not request this code, ignore this email
and consider changing your password.

Please do not share this code with anyone.

PeakGym Management System
"""

    safe_otp = escape(otp)
    safe_purpose = escape(purpose_text)

    body_html = f"""
    <html>
        <body style="font-family: Arial, sans-serif;">
            <h2>PeakGym Management System</h2>

            <p>{safe_purpose}</p>

            <div style="
                padding: 20px;
                background: #f1f5f3;
                text-align: center;
                font-size: 30px;
                font-weight: bold;
                letter-spacing: 8px;
            ">
                {safe_otp}
            </div>

            <p>
                This code expires in
                <strong>{expiry_minutes} minutes.</strong>
            </p>

            <p>
                If you did not request this code, ignore
                this email and consider changing your password.
            </p>

            <p>
                Please do not share this code with anyone.
            </p>

            <hr>

            <small>PeakGym Management System</small>
        </body>
    </html>
    """

    return send_email(
        recipient=recipient,
        subject=subject,
        body_text=body_text,
        body_html=body_html
    )


# ============================================
# PEAKGYM EMAIL PROVIDER SELECTION
# ============================================

def send_email(
    recipient: str,
    subject: str,
    body_text: str,
    body_html: str = None,
) -> bool:
    from app.security.gmail_service import send_gmail

    return send_gmail(
        recipient=recipient,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )