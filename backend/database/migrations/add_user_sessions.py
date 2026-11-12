"""Idempotent migration for server-side idle sessions.

Run from the backend folder:
    python database/migrations/add_user_sessions.py
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import inspect  # noqa: E402
from app.database import engine  # noqa: E402
from app.models.user_session import UserSession  # noqa: E402

if not inspect(engine).has_table("users"):
    raise SystemExit("ERROR: users table missing. No changes made.")

if inspect(engine).has_table("user_sessions"):
    print("user_sessions already exists; no changes made.")
else:
    UserSession.__table__.create(bind=engine, checkfirst=True)
    print("Created user_sessions table.")

print("Session migration complete. Existing accounts were preserved.")
