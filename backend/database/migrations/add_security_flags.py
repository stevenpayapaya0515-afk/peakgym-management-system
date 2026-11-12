"""Create only the security_flags table if absent; preserve existing records."""
import sys
from pathlib import Path
BACKEND = Path(__file__).resolve().parents[2]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))
from app.database import engine
from app.models.security_flag import SecurityFlag

if __name__ == "__main__":
    with engine.begin() as conn:
        SecurityFlag.__table__.create(bind=conn, checkfirst=True)
    print("security_flags table ready; existing data preserved.")
