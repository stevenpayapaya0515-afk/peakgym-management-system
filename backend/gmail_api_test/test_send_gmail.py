
import base64
from email.message import EmailMessage
from pathlib import Path

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

BASE_DIR = Path(__file__).resolve().parent
TOKEN_FILE = BASE_DIR / "token.json"

SCOPES = ["https://www.googleapis.com/auth/gmail.send"]


def main():
    if not TOKEN_FILE.exists():
        print("ERROR: token.json was not found.")
        return

    credentials = Credentials.from_authorized_user_file(
        str(TOKEN_FILE),
        SCOPES,
    )

    message = EmailMessage()
    message["To"] = "steven.payapaya0515@gmail.com"
    message["From"] = "steven.payapaya0515@gmail.com"
    message["Subject"] = "PeakGym Gmail API Test"
    message.set_content(
        "This is a test email sent through the Gmail API "
        "for the PeakGym Security 1 project."
    )

    raw_message = base64.urlsafe_b64encode(
        message.as_bytes()
    ).decode("utf-8")

    service = build(
        "gmail",
        "v1",
        credentials=credentials,
        cache_discovery=False,
    )

    result = (
        service.users()
        .messages()
        .send(
            userId="me",
            body={"raw": raw_message},
        )
        .execute()
    )

    print("SUCCESS: Gmail API accepted the test email.")
    print("Message ID:", result.get("id"))


if __name__ == "__main__":
    main()
