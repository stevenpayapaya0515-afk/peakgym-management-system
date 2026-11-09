"""Add nullable OTP -> pending registration association safely.

Run from backend root:
    python database/migrations/link_registration_otps.py

Does not erase OTPs or alter existing keys. Does not backfill old OTPs:
new registrations must set pending_registration_id explicitly.
"""
from sqlalchemy import inspect, text
from app.database import engine

TABLE = "otps"
COLUMN = "pending_registration_id"
INDEX = "ix_otps_pending_registration_id"
FK = "fk_otps_pending_registration"

with engine.begin() as connection:
    inspector = inspect(connection)
    if not inspector.has_table("pending_staff_registrations"):
        raise SystemExit("Missing pending_staff_registrations table. No changes made.")
    columns = {c["name"] for c in inspector.get_columns(TABLE)}
    if COLUMN not in columns:
        connection.execute(text(
            "ALTER TABLE otps ADD COLUMN pending_registration_id INT NULL"
        ))
        print("Added: pending_registration_id")
    else:
        print("Already exists: pending_registration_id")

# Reinspect after ALTER (MySQL DDL may implicitly commit).
with engine.begin() as connection:
    inspector = inspect(connection)
    indexes = {i["name"] for i in inspector.get_indexes(TABLE)}
    if INDEX not in indexes:
        connection.execute(text(
            "CREATE INDEX ix_otps_pending_registration_id "
            "ON otps (pending_registration_id)"
        ))
        print("Added index:", INDEX)
    else:
        print("Already exists index:", INDEX)

with engine.begin() as connection:
    inspector = inspect(connection)
    fks = inspector.get_foreign_keys(TABLE)
    has_fk = any(
        f.get("referred_table") == "pending_staff_registrations"
        and f.get("constrained_columns") == [COLUMN]
        for f in fks
    )
    if not has_fk:
        connection.execute(text(
            "ALTER TABLE otps ADD CONSTRAINT fk_otps_pending_registration "
            "FOREIGN KEY (pending_registration_id) "
            "REFERENCES pending_staff_registrations(id) ON DELETE SET NULL"
        ))
        print("Added foreign key:", FK)
    else:
        print("Foreign key already exists")

print("OTP registration association migration complete")
