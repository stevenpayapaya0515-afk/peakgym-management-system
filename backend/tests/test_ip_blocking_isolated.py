r"""Isolated IP-blocking regression test: does NOT connect to PeakGym MySQL.

Run inside backend: .\.venv\Scripts\python.exe tests/test_ip_blocking_isolated.py
"""
import sys, types
from pathlib import Path
from datetime import datetime, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from starlette.requests import Request

root = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root))
# Use isolated SQLite DB without importing local developer MySQL credentials.
engine=create_engine('sqlite://')
Base=declarative_base()
db_module=types.ModuleType('app.database')
db_module.Base=Base
db_module.engine=engine
db_module.SessionLocal=sessionmaker(bind=engine,autoflush=False)
db_module.get_db=lambda:None
sys.modules['app.database']=db_module

from app.models.user import User
from app.models.activity_log import ActivityLog
from app.models.ip_block import IPBlock
from app.security.activity_logger import record_security_event
from app.security.ip_blocking import block_after_failed_password, reject_blocked_ip, seconds_blocked
from fastapi import HTTPException
for t in [User.__table__, ActivityLog.__table__, IPBlock.__table__]:
 t.create(bind=engine)


def request(ip='127.0.0.1'):
 return Request({'type':'http','asgi':{'version':'3.0'},'method':'POST','scheme':'http','path':'/auth/login/start', 'raw_path':b'/auth/login/start', 'query_string':b'', 'headers':[(b'user-agent', b'testclient'),(b'x-forwarded-for',b'1.2.3.4')], 'client':(ip,50501),'server':('localhost',8000)})

with db_module.SessionLocal() as db:
 for i in range(1,12):
  req=request()
  record_security_event(db, event_type='login_failed',request=req,username_typed=f'user{i%4}',details='test')
  # SQLite CURRENT_TIMESTAMP uses UTC, but PeakGym uses Philippine local
  # SQL server time. Simulate that configured timestamp explicitly.
  for pending in list(db.new):
   if isinstance(pending, ActivityLog): pending.created_at=datetime.now()
  blocked=block_after_failed_password(db,req,username=f'user{i%4}',user_id=None)
  db.commit()
  assert blocked== (600 if i==11 else 0), (i,blocked)
 assert db.query(ActivityLog).filter_by(event_type='login_failed').count()==11
 assert db.query(ActivityLog).filter_by(event_type='ip_blocked').count()==1
 assert db.query(IPBlock).filter(IPBlock.blocked_until > datetime.now()).count()==1
 assert seconds_blocked(db,'127.0.0.1')>0
 try: reject_blocked_ip(db,request()); raise AssertionError('block not enforced')
 except HTTPException as e:
  assert e.status_code==429
  assert int(e.headers['Retry-After'])>0
 # A different IP is not blocked by these requests, nor by XFF spoofing.
 assert seconds_blocked(db,'127.0.0.2')==0
 # Simulate block expiry and stale login-failure history.
 block=db.query(IPBlock).filter_by(ip_address='127.0.0.1').one()
 block.blocked_until=datetime.now()-timedelta(seconds=1)
 db.query(ActivityLog).filter_by(event_type='login_failed').update({'created_at':datetime.now()-timedelta(minutes=20)})
 db.commit()
 assert seconds_blocked(db,'127.0.0.1')==0
 record_security_event(db,event_type='login_failed',request=request(),username_typed='newaccount',details='test')
 for pending in list(db.new):
  if isinstance(pending, ActivityLog): pending.created_at=datetime.now()
 assert block_after_failed_password(db,request(),username='newaccount',user_id=None)==0
 db.commit()
 print('PASS isolated IP tests: 11 attempts across usernames, 429, 10-minute block, IP source, expiry, new window')
