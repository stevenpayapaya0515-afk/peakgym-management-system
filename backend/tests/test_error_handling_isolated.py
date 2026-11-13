r"""Protection 10 isolated test; no database, Gmail, or network calls.

Run from backend: .\.venv\Scripts\python.exe tests/test_error_handling_isolated.py
"""
import asyncio
import logging
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi import FastAPI, HTTPException
from starlette.requests import Request

from app.security.error_handling import install_error_handling


def request(path: str = "/private/abc123?token=secret") -> Request:
    return Request({
        "type": "http", "method": "GET", "path": path,
        "headers": [], "query_string": b"token=secret",
        "client": ("127.0.0.1", 12345),
        "scheme": "http", "server": ("localhost", 8000),
    })


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as root:
        app = FastAPI()
        install_error_handling(app, Path(root))
        crash = RuntimeError("private database failure")
        response = asyncio.run(app.exception_handlers[Exception](request(), crash))
        assert response.status_code == 500
        assert response.headers["X-Frame-Options"] == "DENY"
        assert response.headers["X-Content-Type-Options"] == "nosniff"
        assert response.headers["Cache-Control"] == "no-store"
        assert b"private database failure" not in response.body
        assert b"secret" not in response.body
        assert b"unexpected server error" in response.body.lower()
        assert HTTPException not in app.exception_handlers, "Normal HTTP errors must remain unchanged"

        file = Path(root) / "application_errors.log"
        contents = file.read_text(encoding="utf-8")
        assert "private database failure" in contents
        assert "RuntimeError" in contents
        assert "token=secret" not in contents
        assert "abc123" not in contents

        # Close file handlers before Windows removes the temporary folder.
        logger = logging.getLogger("peakgym.private_errors")
        for handler in logger.handlers[:]:
            handler.flush()
            handler.close()
            logger.removeHandler(handler)

    print("PASS: Generic 500 response, private traceback log, protected response headers")