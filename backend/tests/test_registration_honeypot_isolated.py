"""Isolated no-DB honeypot check: does not send Gmail or mutate MySQL.

Run: python tests/test_registration_honeypot_isolated.py
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from starlette.requests import Request
from app.routes.registration import RegistrationStartRequest, start_staff_registration


class NoDatabaseAccess:
    def __getattr__(self, key):
        raise AssertionError(f"Honeypot rejection accessed the database: {key}")


if __name__ == '__main__':
    request = Request({
        'type': 'http', 'method': 'POST', 'path': '/registration/start',
        'headers': [], 'client': ('127.0.0.1', 5050), 'scheme': 'http',
        'server': ('127.0.0.1', 8000), 'query_string': b'',
    })
    payload = RegistrationStartRequest.model_construct(website='spam.example')
    result = start_staff_registration(payload, request, NoDatabaseAccess())
    assert result.status_code == 200, result.status_code
    assert b'registration_token' not in result.body
    print('PASS: Filled honeypot rejected without database access, OTP, or Gmail')
