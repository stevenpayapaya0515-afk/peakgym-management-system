"""IT107 Security 1: manual, read-only activity scan and append-only flagging.

Run from backend:  .\\.venv\\Scripts\\python.exe scripts/monitor.py

ActivityLog.created_at is a MySQL naive datetime and is assumed to use Asia/Manila
local time. Keep the MySQL server timezone set to Asia/Manila for this project.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict, deque
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

# Running as `python scripts/monitor.py` must import the app package from backend.
BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from app.database import SessionLocal  # noqa: E402
from app.models.activity_log import ActivityLog  # noqa: E402
from app.models.security_flag import SecurityFlag  # noqa: E402
from app.security.policy import IP_BLOCK_THRESHOLD  # noqa: E402

PHT = ZoneInfo("Asia/Manila")
FAILED_LOGIN_TYPES = {"login_failed", "LOGIN_FAILED"}
FAILED_OTP_TYPES = {
    "login_otp_failed", "password_reset_otp_failed",
    "registration_otp_failed", "OTP_FAILED",
}
LOGIN_SUCCESS_TYPES = {"login_success", "LOGIN_SUCCESS"}


def analyze(events: list, now: datetime) -> list[dict]:
    """Pure detector; accepts ActivityLog-like objects, no database writes."""
    cutoff = now - timedelta(hours=24)
    recent = [e for e in events if e.created_at and cutoff <= e.created_at <= now]
    recent.sort(key=lambda e: e.created_at)
    findings = []

    ip_events = defaultdict(list)
    user_failure_ips = defaultdict(set)
    otp_events = defaultdict(list)

    for event in recent:
        event_type = event.event_type
        username = (event.username_typed or "").strip()
        ip = (event.ip_address or "").strip()
        if event_type in FAILED_LOGIN_TYPES:
            if ip:
                ip_events[ip].append(event)
            if username and ip:
                user_failure_ips[username].add(ip)
        if event_type in FAILED_OTP_TYPES:
            # Prefer the stable account identifier for correlation.
            target = username or (f"user:{event.user_id}" if event.user_id else "")
            if target:
                otp_events[target].append(event)
        if event_type in LOGIN_SUCCESS_TYPES and event.created_at.hour < 5:
            target = username or (f"user:{event.user_id}" if event.user_id else "")
            if target:
                findings.append({
                    "pattern": "off_hours_login", "target": target,
                    "severity": "MED",
                    "description": "Successful login between 00:00 and 05:00 PHT",
                    "evidence": {
                        "login_time_pht": event.created_at.isoformat(timespec="seconds"),
                        "ip": ip,
                    },
                })

    for ip, failures in sorted(ip_events.items()):
        if len(failures) >= IP_BLOCK_THRESHOLD:
            usernames = {e.username_typed for e in failures if e.username_typed}
            findings.append({
                "pattern": "ip_over_threshold", "target": ip,
                "severity": "HIGH",
                "description": f"{len(failures)} failed logins from one IP (threshold {IP_BLOCK_THRESHOLD})",
                "evidence": {"failures": len(failures), "usernames": len(usernames)},
            })

    for username, ips in sorted(user_failure_ips.items()):
        if len(ips) >= 3:
            findings.append({
                "pattern": "account_targeted", "target": username,
                "severity": "MED",
                "description": f"Failed logins for one username from {len(ips)} IPs",
                "evidence": {"distinct_ips": len(ips)},
            })

    for target, attempts in sorted(otp_events.items()):
        window = deque()
        max_in_ten_minutes = 0
        for event in attempts:
            window.append(event.created_at)
            while window and event.created_at - window[0] > timedelta(minutes=10):
                window.popleft()
            max_in_ten_minutes = max(max_in_ten_minutes, len(window))
        if max_in_ten_minutes >= 5:
            findings.append({
                "pattern": "otp_guessing", "target": target,
                "severity": "MED",
                "description": f"{max_in_ten_minutes} incorrect OTPs within 10 minutes",
                "evidence": {"max_attempts_in_10_minutes": max_in_ten_minutes},
            })

    # Only one finding per pattern and target per run, even if many off-hour logins.
    return list({(f["pattern"], f["target"]): f for f in findings}.values())


def run() -> None:
    now = datetime.now(PHT).replace(tzinfo=None)
    cutoff = now - timedelta(hours=24)
    with SessionLocal() as db:
        events = (
            db.query(ActivityLog)
            .filter(ActivityLog.created_at >= cutoff, ActivityLog.created_at <= now)
            .order_by(ActivityLog.created_at, ActivityLog.id)
            .all()
        )
        findings = analyze(events, now)
        today = now.date()
        existing = {
            (flag.pattern, flag.target)
            for flag in db.query(SecurityFlag).filter(SecurityFlag.flag_date == today).all()
        }
        added = 0
        already = 0
        for item in findings:
            key = (item["pattern"], item["target"])
            if key in existing:
                already += 1
                continue
            db.add(SecurityFlag(
                pattern=item["pattern"],
                target=item["target"][:100],
                severity=item["severity"],
                description=item["description"],
                evidence=json.dumps(item["evidence"]),
                flag_date=today,
            ))
            existing.add(key)
            added += 1
        db.commit()

    print(f"IT 107 Monitoring Report - {now:%Y-%m-%d %H:%M} PHT")
    print(f"Scanned: {len(events)} events (last 24 hours)")
    for item in findings:
        print(f"[{item['severity']:<4}] {item['pattern']:<20} {item['target']:<20} {item['description']}")
    print(f"New flags written: {added}   Already flagged today: {already}")


if __name__ == "__main__":
    run()
