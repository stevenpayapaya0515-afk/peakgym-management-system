"""Safe offline tests: no Gmail requests and no MySQL writes.

Run: python tests/test_email_notification_isolated.py
"""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.security.email_notifications import (
    audit_otp_sent, record_sent_email, send_password_changed_notice,
)
from app.security.login_alerts import send_login_lockout_alert

class FakeDB:
    def __init__(self):
        self.events = []
        self.did_commit = False
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def add(self, item):
        self.events.append(item)
    def commit(self):
        self.did_commit = True

fake_db = FakeDB()
with patch('app.security.email_notifications.SessionLocal', return_value=fake_db):
    assert record_sent_email(
        event_type='otp_sent', username='demo.staff', user_id=None,
        ip_address='127.0.0.1', user_agent='TestBrowser/1.0',
        details='Gmail accepted login OTP email',
    ) is True
assert fake_db.did_commit and len(fake_db.events) == 1
assert fake_db.events[0].event_type == 'otp_sent'
assert fake_db.events[0].ip_address == '127.0.0.1'
assert '123456' not in fake_db.events[0].details

with patch('app.security.email_notifications.record_sent_email', return_value=True) as audit:
    request = SimpleNamespace(
        client=SimpleNamespace(host='192.168.1.88'),
        headers={'user-agent': 'TestBrowser/1.0'},
    )
    audit_otp_sent(purpose='reset', request=request, username='demo.staff', user_id=12)
    assert audit.call_args.kwargs['event_type'] == 'otp_sent'
    assert audit.call_args.kwargs['ip_address'] == '192.168.1.88'

with patch('app.security.email_notifications.send_email', return_value=True) as send, \
     patch('app.security.email_notifications.record_sent_email') as audit:
    send_password_changed_notice(
        email='demo@example.com', username='demo.staff', user_id=12,
        ip_address='127.0.0.1', user_agent='TestBrowser/1.0',
        method='Forgot Password',
    )
    sent_args = send.call_args.kwargs
    assert 'Your password was changed' in sent_args['subject']
    assert 'PHT' in sent_args['body_text']
    assert '127.0.0.1' in sent_args['body_text']
    assert 'TestBrowser' in sent_args['body_text']
    assert '123456' not in sent_args['body_text']
    assert audit.call_count == 1
    assert audit.call_args.kwargs['event_type'] == 'alert_email_sent'

with patch('app.security.email_notifications.send_email', return_value=False), \
     patch('app.security.email_notifications.record_sent_email') as audit:
    send_password_changed_notice(
        email='demo@example.com', username='demo.staff', user_id=12,
        ip_address=None, user_agent=None, method='Staff Settings',
    )
    assert audit.call_count == 0

with patch('app.security.login_alerts.send_email', return_value=True) as send, \
     patch('app.security.login_alerts.record_sent_email') as audit:
    send_login_lockout_alert(
        email='demo@example.com', username='demo.staff', attempts=3,
        lockout_seconds=18, user_id=12, ip_address='127.0.0.1',
        user_agent='TestBrowser/1.0',
    )
    assert 'PHT' in send.call_args.kwargs['body_text']
    assert '127.0.0.1' in send.call_args.kwargs['body_text']
    assert 'TestBrowser' in send.call_args.kwargs['body_text']
    assert audit.call_count == 1
    assert audit.call_args.kwargs['event_type'] == 'alert_email_sent'

print('PASS: email notifications, OTP audit, accepted-send logging, failure isolation')
