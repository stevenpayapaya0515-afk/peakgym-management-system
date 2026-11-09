
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow


BASE_DIR = Path(__file__).resolve().parent
CREDENTIALS_FILE = BASE_DIR / "credentials.json"
TOKEN_FILE = BASE_DIR / "token.json"

SCOPES = [
    "https://www.googleapis.com/auth/gmail.send"
]


def main():
    if not CREDENTIALS_FILE.exists():
        print("ERROR: credentials.json was not found.")
        return

    credentials = None

    if TOKEN_FILE.exists():
        credentials = Credentials.from_authorized_user_file(
            str(TOKEN_FILE),
            SCOPES,
        )

    if credentials and credentials.expired and credentials.refresh_token:
        credentials.refresh(Request())

    if not credentials or not credentials.valid:
        flow = InstalledAppFlow.from_client_secrets_file(
            str(CREDENTIALS_FILE),
            SCOPES,
        )

        credentials = flow.run_local_server(
            host="localhost",
            port=0,
            open_browser=True,
            authorization_prompt_message=(
                "Opening Google authorization in your browser..."
            ),
        )

    TOKEN_FILE.write_text(credentials.to_json(), encoding="utf-8")

    print("SUCCESS: Gmail API authorized.")
    print("Authorization saved locally.")
    print("Permission: gmail.send")


if __name__ == "__main__":
    main()
