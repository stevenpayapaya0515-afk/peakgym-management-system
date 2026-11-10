"""Create password_history safely in the EXISTING security_1 database.

Run once from the backend folder:
    python database/migrations/add_password_history.py

Idempotent: re-running does not delete or overwrite existing data.
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import inspect  # noqa: E402
from app.database import engine  # noqa: E402
from app.models.user import User  # noqa: F401, E402
from app.models.password_history import PasswordHistory  # noqa: E402

if not inspect(engine).has_table("users"):
    raise SystemExit("ERROR: users table is missing; no changes made.")

if inspect(engine).has_table("password_history"):
    print("password_history already exists; no changes made.")
else:
    PasswordHistory.__table__.create(bind=engine, checkfirst=True)
    print("Created password_history table.")

print("Password-history migration complete. Existing accounts and passwords were preserved.")
