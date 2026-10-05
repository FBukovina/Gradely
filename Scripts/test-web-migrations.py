#!/usr/bin/env python3
"""Run synthetic web/Planner migration fixtures on an isolated Unix-socket-only PostgreSQL instance.

Requires local PostgreSQL binaries and pgcrypto. Applies the original platform schema plus
new Planner/web migrations; this is not a replacement for a full Supabase migration reset.
Never connects to an existing database or reads Supabase project credentials.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINDIR = Path(os.environ.get("GRADEY_TEST_PG_BINDIR") or subprocess.check_output(["pg_config", "--bindir"], text=True).strip())

def run(command, **kwargs):
    subprocess.run([str(x) for x in command], check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix="gradey-web-db-") as directory:
    fixture = Path(directory)
    data = fixture / "data"
    socket = fixture / "socket"
    socket.mkdir()
    run([BINDIR / "initdb", "-D", data, "-U", "postgres", "--auth=trust", "--no-locale", "-E", "UTF8"], stdout=subprocess.DEVNULL)
    run([BINDIR / "pg_ctl", "-D", data, "-l", fixture / "postgres.log", "-o", f"-h '' -k '{socket}' -p 5432", "-w", "start"], stdout=subprocess.DEVNULL)
    try:
        psql = [BINDIR / "psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", socket, "-U", "postgres", "-d", "postgres"]
        run(psql, input="""create role anon; create role authenticated; create role service_role bypassrls;
create schema auth;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb not null default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth, public to anon, authenticated, service_role;
""", text=True, stdout=subprocess.DEVNULL)
        for filename in ["202606300001_gradey_platform.sql", "20261005141914_planner_account_sync.sql", "20261005141931_web_calendar_notifications.sql", "20261005142104_web_session_vault.sql"]:
            print(f"Applying {filename}", flush=True)
            run(psql + ["-f", ROOT / "supabase/migrations" / filename], stdout=subprocess.DEVNULL)
        for filename in ["planner_account_sync.sql", "web_calendar_notifications.sql", "web_session_vault.sql"]:
            print(f"Testing {filename}", flush=True)
            run(psql + ["-f", ROOT / "supabase/tests" / filename], stdout=subprocess.DEVNULL)
        print("All local migration fixtures passed.")
    finally:
        run([BINDIR / "pg_ctl", "-D", data, "-m", "fast", "-w", "stop"], stdout=subprocess.DEVNULL)
