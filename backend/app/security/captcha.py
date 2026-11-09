import os
import base64
import secrets
import hmac
import hashlib
import io

from datetime import datetime, timedelta, timezone
from pathlib import Path

from dotenv import load_dotenv
from PIL import Image, ImageDraw, ImageFont

from sqlalchemy.orm import Session

from app.models.captcha_challenge import CaptchaChallenge

from app.security.policy import (
    CAPTCHA_LENGTH,
    CAPTCHA_EXPIRY_MINUTES
)


BASE_DIR = Path(__file__).resolve().parents[2]

load_dotenv(BASE_DIR / ".env")


# Characters that are difficult to confuse.
CAPTCHA_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

IMAGE_WIDTH = 270
IMAGE_HEIGHT = 90


def _get_captcha_pepper() -> str:
    pepper = os.getenv("CAPTCHA_PEPPER")

    if not pepper or len(pepper) < 32:
        raise RuntimeError(
            "CAPTCHA_PEPPER is missing or too short."
        )

    return pepper


def _hash_answer(answer: str) -> str:
    normalized = answer.strip().upper()

    return hmac.new(
        _get_captcha_pepper().encode("utf-8"),
        normalized.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()


def _generate_answer() -> str:
    return "".join(
        secrets.choice(CAPTCHA_ALPHABET)
        for _ in range(CAPTCHA_LENGTH)
    )


def _render_captcha_image(answer: str) -> str:
    image = Image.new(
        "RGB",
        (IMAGE_WIDTH, IMAGE_HEIGHT),
        (245, 247, 250)
    )

    draw = ImageDraw.Draw(image)

    try:
        font = ImageFont.truetype("arial.ttf", 42)
    except OSError:
        try:
            font = ImageFont.truetype("DejaVuSans.ttf", 42)
        except OSError:
            try:
                font = ImageFont.load_default(size=42)
            except TypeError:
                font = ImageFont.load_default()

    # Background noise lines.
    for _ in range(12):
        draw.line(
            (
                secrets.randbelow(IMAGE_WIDTH),
                secrets.randbelow(IMAGE_HEIGHT),
                secrets.randbelow(IMAGE_WIDTH),
                secrets.randbelow(IMAGE_HEIGHT)
            ),
            fill=(
                secrets.randbelow(150),
                secrets.randbelow(150),
                secrets.randbelow(150)
            ),
            width=1
        )

    # Random noise dots.
    for _ in range(150):
        x = secrets.randbelow(IMAGE_WIDTH)
        y = secrets.randbelow(IMAGE_HEIGHT)

        draw.point(
            (x, y),
            fill=(120, 130, 145)
        )

    # Draw distorted characters.
    for index, character in enumerate(answer):

        x = 20 + (index * 39) + secrets.randbelow(9)
        y = 15 + secrets.randbelow(15)

        draw.text(
            (x, y),
            character,
            font=font,
            fill=(
                secrets.randbelow(100),
                secrets.randbelow(100),
                secrets.randbelow(100)
            ),
            stroke_width=1
        )

    # Additional interference lines.
    for _ in range(4):
        y = secrets.randbelow(IMAGE_HEIGHT)

        draw.line(
            (0, y, IMAGE_WIDTH, secrets.randbelow(IMAGE_HEIGHT)),
            fill=(100, 110, 130),
            width=2
        )

    buffer = io.BytesIO()

    image.save(buffer, format="PNG")

    return base64.b64encode(
        buffer.getvalue()
    ).decode("ascii")


def create_captcha_challenge(db: Session) -> dict:
    answer = _generate_answer()

    challenge_id = secrets.token_urlsafe(32)

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    expires_at = now + timedelta(
        minutes=CAPTCHA_EXPIRY_MINUTES
    )

    challenge = CaptchaChallenge(
        id=challenge_id,
        answer_hash=_hash_answer(answer),
        expires_at=expires_at
    )

    try:
        db.add(challenge)
        db.commit()
    except Exception:
        db.rollback()
        raise

    return {
        "challenge_id": challenge_id,
        "image": _render_captcha_image(answer),
        "image_type": "image/png",
        "expires_at": expires_at.isoformat()
    }


def verify_captcha(
    db: Session,
    challenge_id: str,
    answer: str
) -> bool:

    if not isinstance(challenge_id, str):
        return False

    if not isinstance(answer, str):
        return False

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    try:
        challenge = (
            db.query(CaptchaChallenge)
            .filter(
                CaptchaChallenge.id == challenge_id
            )
            .with_for_update()
            .first()
        )

        if challenge is None:
            return False

        if challenge.consumed_at is not None:
            return False

        if challenge.expires_at <= now:
            challenge.consumed_at = now
            db.commit()
            return False

        # Every verification attempt consumes the challenge.
        challenge.consumed_at = now

        if len(answer.strip()) != CAPTCHA_LENGTH:
            db.commit()
            return False

        submitted_hash = _hash_answer(answer)

        is_valid = hmac.compare_digest(
            submitted_hash,
            challenge.answer_hash
        )

        db.commit()

        return is_valid

    except Exception:
        db.rollback()
        raise