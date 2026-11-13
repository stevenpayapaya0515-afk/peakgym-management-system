"""Protection 10: private traceback logging and generic public HTTP 500 responses.

Store traceback files outside XAMPP/Apache htdocs,
never log authorization headers, cookies, request bodies, or query strings.
"""
from __future__ import annotations

import logging
import os
import secrets
from logging.handlers import RotatingFileHandler
from pathlib import Path

from app.security.private_config import PRIVATE_ERROR_LOG_DIR

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


_LOG_NAME = "peakgym.private_errors"
_BACKEND_ROOT = Path(__file__).resolve().parents[2]


def _private_error_logger(log_directory: Path | None = None) -> logging.Logger:
    destination = Path(
        log_directory
        if log_directory is not None
        else os.getenv("PEAKGYM_ERROR_LOG_DIR", str(PRIVATE_ERROR_LOG_DIR))
    ).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    logfile = destination / "application_errors.log"

    logger = logging.getLogger(_LOG_NAME)
    logger.setLevel(logging.ERROR)
    logger.propagate = False
    # Avoid duplicate handlers during reloads and isolated tests.
    if not any(
        isinstance(h, RotatingFileHandler)
        and Path(h.baseFilename).resolve() == logfile
        for h in logger.handlers
    ):
        handler = RotatingFileHandler(
            logfile, maxBytes=2 * 1024 * 1024, backupCount=3, encoding="utf-8"
        )
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
    return logger


def install_error_handling(app: FastAPI, log_directory: Path | None = None) -> None:
    """Register a fallback for unexpected errors; normal 4xx responses stay intact."""
    logger = _private_error_logger(log_directory)

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        error_id = secrets.token_hex(8)
        # Log a route template, never the actual path/query/body: URLs may be secret.
        route = request.scope.get("route")
        safe_route = getattr(route, "path", "<unknown route>")
        logger.error(
            "Unhandled server error id=%s method=%s route=%s",
            error_id, request.method, safe_route,
            exc_info=(type(exc), exc, exc.__traceback__),
        )
        return JSONResponse(
            status_code=500,
            content={
                "detail": "An unexpected server error occurred. Please try again.",
                "error_id": error_id,
            },
            headers={
                "X-Frame-Options": "DENY",
                "X-Content-Type-Options": "nosniff",
                "Cache-Control": "no-store",
            },
        )
