# PeakGym IP Blocking — IT107 Security 1

Scope: **11 failed password logins from one IP within 10 minutes** (including nonexistent usernames) cause a **10-minute block**. Existing 3/6/9 account lockouts remain. Both `/auth/login/start` and `/auth/login/verify-otp` refuse requests from actively blocked IPs. IP is taken from the server-observed request client, never from untrusted `X-Forwarded-For`.

Files changed: `backend/app/routes/login_otp.py`, `backend/app/routes/security_dashboard.py`, `backend/app/models/__init__.py`, `frontend/lib/screens/admin/security_monitoring.dart`. New: `backend/app/models/ip_block.py`, `backend/app/security/ip_blocking.py`, `backend/database/migrations/add_ip_blocks.py`, `backend/tests/test_ip_blocking_isolated.py`.

The monitoring dashboard files in this patch build on the **previous security dashboard update** (today metrics, 24h chart, top IPs, filters, auto-refresh). Don't overwrite them if you have made other local edits since then; preserve those edits and compare first.

## Install (Windows PowerShell)

From `C:\xampp\htdocs\Payapaya_Security1`:

```powershell
# Check for uncommitted changes before extracting
 git status --short
# Extract into project root
 Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\peakgym_ip_blocking_patch.zip" -DestinationPath "C:\xampp\htdocs\Payapaya_Security1" -Force
```

With XAMPP MySQL running:

```powershell
cd C:\xampp\htdocs\Payapaya_Security1\backend
.\.venv\Scripts\python.exe database/migrations/add_ip_blocks.py
.\.venv\Scripts\python.exe tests/test_ip_blocking_isolated.py
.\.venv\Scripts\python.exe -c "from app.main import app; print('IP blocking loaded successfully')"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

In a separate terminal:

```powershell
cd C:\xampp\htdocs\Payapaya_Security1\frontend
flutter analyze
flutter run -d chrome --web-port=3000
```

## What to test

1. As Admin, open Security Monitoring. **IPs blocked now** should display `0` when nobody is blocked, not `—`.
2. In Top 5 IP Addresses, unblocked rows should say **Not blocked**.
3. The isolated test demonstrates 11 mixed-username failures, block response `429`, `Retry-After`, expiry, and separate IPs **without touching your MySQL database**.
4. With a separate disposable test setup/database, 11 actual invalid password attempts within 10 minutes should block the source IP; the next login attempt should return `429` with the remaining time, and the Admin dashboard should show that block if accessed from an unblocked IP.

**Warning:** On your `localhost` setup, all browser sessions generally share source IP `127.0.0.1`. Triggering a real IP block while testing would also prevent normal Admin/Staff login on that machine for ten minutes. Do not deliberately trigger 11 real failures on the main development database unless you are prepared for that effect. The provided isolated test is the safer first test.

## Remaining requirements

This patch does **not** implement password-change confirmation Gmail, complete `OTP_SENT` / `ALERT_EMAIL_SENT` activity events, or audit CSRF, encryption at rest, headers, and other instructor protections. Finish and test those after IP blocking.

**Do not commit keys or secrets.** After your local checks pass, stage/review all intended changes and make one commit on `main`, per your preferred workflow.
