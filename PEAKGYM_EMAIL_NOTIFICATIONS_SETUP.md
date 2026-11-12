# PeakGym Gmail security notifications and activity logging

Install from the repository root only after checking `git status --short`.
The ZIP updates 7 backend Python files, adds `backend/app/security/email_notifications.py`, and adds one isolated test.

From `C:\xampp\htdocs\Payapaya_Security1\backend`:

```powershell
.\.venv\Scripts\python.exe -m py_compile app/security/email_notifications.py app/security/login_alerts.py app/routes/settings.py app/routes/password_recovery.py app/routes/login_otp.py app/routes/security_questions.py app/routes/registration.py app/routes/security_dashboard.py
.\.venv\Scripts\python.exe -c "from app.main import app; print('Email notifications loaded')"
.\.venv\Scripts\python.exe tests/test_email_notification_isolated.py
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

No database migration is required. Gmail OAuth in `backend/gmail_api_test/token.json` must already work.

### Check manually in Flutter

1. Sign in with a test Staff account, change the password through Settings.
2. Confirm the owner receives **Your password was changed - PeakGym**.
3. Complete Forgot Password with Gmail OTP; confirm the same notification is sent.
4. Log in as Admin; open Security Monitoring and Refresh. The OTP SENT and ALERT EMAILS SENT counters should now display actual counts for **new events**.
5. Trigger lockout alerts with a test account if safe, and verify time, IP and browser are included. Do not lock your only account during the demo.

Email sends run after database commits, so Gmail outages cannot undo a password change. Audit rows record provider-accepted sends, not inbox delivery confirmations. Old sends are not backfilled.

No credentials or OTPs are printed or logged. Never commit `.env` or Gmail OAuth tokens.
