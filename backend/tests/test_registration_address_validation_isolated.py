"""Run: python tests/test_registration_address_validation_isolated.py"""
from datetime import date
from pydantic import ValidationError
from app.schemas.registration import StaffRegistrationRequest


def payload():
    return {
        "invitation_token": "a" * 32,
        "id_number": "2026-0001",
        "first_name": "Juan",
        "family_name": "Reyes",
        "birthdate": date(2000, 1, 1),
        "region": "Caraga",
        "province": "Agusan Del Norte",
        "city_municipality": "Cabadbaran City",
        "barangay": "Poblacion",
        "street_address": "Purok 1",
        "postal_code": "8600",
        "country": "Philippines",
        "username": "jreyes123",
        "password": "StrongPass123!",
        "confirm_password": "StrongPass123!",
        "security_answer_q4": "Maria",
        "security_answer_q7": "Central School",
        "security_answer_q1": "Bantay",
        "staff_position": "Trainer",
        "employment_type": "Full-time",
        "date_hired": date(2024, 1, 1),
        "emergency_contact_number": "09123456789",
        "privacy_consent": True,
    }


def reject(field, value):
    data = payload()
    data[field] = value
    try:
        StaffRegistrationRequest.model_validate(data)
    except ValidationError:
        return
    raise AssertionError(f"Expected {field}={value!r} to be rejected")


if __name__ == "__main__":
    obj = StaffRegistrationRequest.model_validate(payload())
    assert obj.postal_code == "8600"
    reject("postal_code", "86001")
    reject("postal_code", "abcd")
    reject("barangay", "Barangay 1")
    reject("province", "agusan del norte")
    reject("street_address", "Purok  1")
    reject("street_address", "St.")
    reject("country", "Otherland")
    print("PASS: Handout address validation, country, and ZIP Code rules")
