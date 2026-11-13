import os
import base64
import secrets

from pathlib import Path
from app.security.private_config import load_private_env
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag


load_private_env()


# =====================================
# AES-256 CONFIGURATION
# =====================================

NONCE_LENGTH = 12
KEY_LENGTH = 32


def get_encryption_key() -> bytes:
    key_text = os.getenv("FIELD_ENCRYPTION_KEY")

    if not key_text:
        raise RuntimeError(
            "FIELD_ENCRYPTION_KEY is missing from private configuration"
        )

    try:
        key = base64.urlsafe_b64decode(key_text)
    except Exception:
        raise RuntimeError(
            "FIELD_ENCRYPTION_KEY has an invalid format."
        )

    if len(key) != KEY_LENGTH:
        raise RuntimeError(
            "FIELD_ENCRYPTION_KEY must decode to exactly 32 bytes."
        )

    return key


# =====================================
# ENCRYPTION
# =====================================

def encrypt_sensitive_data(
    value: str,
    context: str = "peakgym"
) -> str:

    if not isinstance(value, str) or not value:
        raise ValueError("Value to encrypt cannot be empty.")

    if not isinstance(context, str) or not context:
        raise ValueError("Encryption context is required.")

    key = get_encryption_key()

    aes = AESGCM(key)

    nonce = secrets.token_bytes(NONCE_LENGTH)

    ciphertext = aes.encrypt(
        nonce,
        value.encode("utf-8"),
        context.encode("utf-8")
    )

    encrypted_data = base64.urlsafe_b64encode(
        nonce + ciphertext
    ).decode("ascii")

    return "v1:" + encrypted_data


# =====================================
# DECRYPTION
# =====================================

def decrypt_sensitive_data(
    encrypted_value: str,
    context: str = "peakgym"
) -> str:

    if not isinstance(encrypted_value, str):
        raise ValueError("Invalid encrypted value.")

    if not encrypted_value.startswith("v1:"):
        raise ValueError("Unsupported encryption format.")

    if not isinstance(context, str) or not context:
        raise ValueError("Encryption context is required.")

    try:
        encrypted_bytes = base64.b64decode(
            encrypted_value[3:],
            altchars=b"-_",
            validate=True
        )

        if len(encrypted_bytes) < NONCE_LENGTH + 16:
            raise ValueError("Invalid encrypted data.")

        nonce = encrypted_bytes[:NONCE_LENGTH]
        ciphertext = encrypted_bytes[NONCE_LENGTH:]

        aes = AESGCM(get_encryption_key())

        decrypted = aes.decrypt(
            nonce,
            ciphertext,
            context.encode("utf-8")
        )

        return decrypted.decode("utf-8")

    except InvalidTag:
        raise ValueError(
            "Decryption failed: invalid key, context or modified data."
        ) from None

    except (ValueError, UnicodeDecodeError):
        raise ValueError(
            "Unable to decrypt the supplied value."
        ) from None