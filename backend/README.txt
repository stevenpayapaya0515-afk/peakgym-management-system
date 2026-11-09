PeakGym staff activation patch

Copy app/routes/registration_activation.py into backend/app/routes/registration_activation.py.
Do not replace your registration.py, models, or database migrations.

In backend/app/main.py add:
  from app.routes.registration_activation import router as registration_activation_router
and after the existing registration router include:
  app.include_router(registration_activation_router)

Test with:
  .\.venv\Scripts\python.exe -m py_compile app/routes/registration_activation.py app/main.py
  .\.venv\Scripts\python.exe -c "from app.main import app; print('POST /registration/activate' in [m.upper()+' '+p for p,ops in app.openapi()['paths'].items() for m in ops])"

IMPORTANT: This endpoint assumes /registration/verify-otp set pending.status='verified'.
The existing OTP model links registration OTP to email rather than pending ID; strengthen this binding before production/final security assessment.
This also preserves users.id INTEGER as primary key: staff_profiles.id_number is UNIQUE but is not the instructor-required PRIMARY KEY.
