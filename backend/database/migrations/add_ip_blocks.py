r"""Idempotently create the IP block table (does not alter existing users).

From backend:  .\.venv\Scripts\python.exe database/migrations/add_ip_blocks.py
"""
import sys
from pathlib import Path
from sqlalchemy import inspect

BACKEND = Path(__file__).resolve().parents[2]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from app.database import engine  # noqa: E402
from app.models.ip_block import IPBlock  # noqa: E402

if not inspect(engine).has_table("users"):
    raise SystemExit("users table is missing; no changes made")

IPBlock.__table__.create(bind=engine, checkfirst=True)
print("ip_blocks table ready; existing users and activity history preserved.")
