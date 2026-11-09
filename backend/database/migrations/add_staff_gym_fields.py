"""Add only missing PeakGym gym-specific columns to staff_profiles.

Run from backend: .\.venv\Scripts\python.exe database/migrations/add_staff_gym_fields.py
Requires existing security_1 database and staff_profiles table. Back it up first.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import inspect, text
from app.database import engine

COLUMNS = {
    "staff_position": "VARCHAR(20) NULL",
    "employment_type": "VARCHAR(10) NULL",
    "date_hired": "DATE NULL",
    "emergency_contact_number": "VARCHAR(13) NULL",
}

inspector = inspect(engine)
if not inspector.has_table("staff_profiles"):
    raise SystemExit("ERROR: staff_profiles table not found. No changes made.")

existing = {col["name"] for col in inspector.get_columns("staff_profiles")}
with engine.begin() as connection:
    for name, sql_type in COLUMNS.items():
        if name in existing:
            print("Already exists:", name)
        else:
            connection.execute(text(f"ALTER TABLE staff_profiles ADD COLUMN {name} {sql_type}"))
            print("Added:", name)
print("Gym fields migration complete.")
