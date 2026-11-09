"""Safely add a unique staff ID number to existing staff_profiles.

Run from backend root: python database/migrations/add_staff_id_number.py
The original users.id integer PK and foreign keys are preserved.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import inspect, text
from app.database import engine

TABLE = "staff_profiles"
INDEX = "uq_staff_profiles_id_number"
inspector = inspect(engine)
if not inspector.has_table(TABLE):
    raise SystemExit("ERROR: staff_profiles not found; no changes made")

columns = {column["name"] for column in inspector.get_columns(TABLE)}
if "id_number" not in columns:
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE staff_profiles ADD COLUMN id_number VARCHAR(9) NULL"))
    print("Added: id_number")
else:
    print("Already exists: id_number")

# Do not silently accept an existing non-unique index or duplicate IDs.
inspector = inspect(engine)
unique_sets = [set(u["column_names"]) for u in inspector.get_unique_constraints(TABLE)]
unique_sets += [set(i["column_names"]) for i in inspector.get_indexes(TABLE) if i.get("unique")]
if {"id_number"} not in unique_sets:
    with engine.begin() as connection:
        connection.execute(text(f"CREATE UNIQUE INDEX {INDEX} ON {TABLE} (id_number)"))
    print("Added unique index:", INDEX)
else:
    print("Unique constraint already exists for id_number")

print("Staff ID migration complete; existing users.id and foreign keys unchanged.")
