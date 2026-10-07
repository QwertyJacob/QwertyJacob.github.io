#!/usr/bin/env python3
"""Local account setup; reads dotenv, never prints passwords, tokens or student data."""
import argparse
import json
import secrets
import sys
import urllib.error
import urllib.request

from dotenv import dotenv_values
import psycopg
from thesis_db import connect, ROOT, PROJECT


def auth_request(config, path, payload=None):
    request = urllib.request.Request(
        f'https://{PROJECT}.supabase.co/auth/v1/{path}',
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'apikey': config['PUBLISHABLE_KEY'], 'Content-Type': 'application/json'},
        method='GET' if payload is None else 'POST')
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Never echo Auth response objects, email addresses, credentials or links.
        sys.exit(f'Auth request failed (HTTP {error.code}). Inspect private Auth logs and SMTP in the project dashboard; no response details logged.')
    except (urllib.error.URLError, TimeoutError):
        sys.exit('Auth request failed; no credentials or response details logged.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'provision', 'grant', 'revoke'])
    parser.add_argument('--email', help='Explicitly approved administrator email; required for account actions.')
    args = parser.parse_args()
    config = dotenv_values(ROOT / 'supa.env')
    if config.get('PROJECT_ID') != PROJECT or not config.get('PUBLISHABLE_KEY'):
        sys.exit('Expected existing PSI project credentials.')
    if args.action == 'inspect':
        settings = auth_request(config, 'settings')
        print('Email Auth enabled:', settings.get('external', {}).get('email'))
        print('Project-wide signup disabled:', settings.get('disable_signup'))
        print('Email autoconfirm enabled:', settings.get('mailer_autoconfirm'))
        print('SMTP, templates, redirects and rate limits require dashboard/Management API access. No shared Auth settings changed.')
        with connect() as conn, conn.cursor() as cursor:
            cursor.execute('select count(*) from public.thesis_admins')
            print('Allowlisted accounts:', cursor.fetchone()[0])
        return
    email = (args.email or '').strip().lower()
    if not email or '@' not in email:
        sys.exit('Supply the intended administrator email explicitly with --email.')
    with connect() as conn, conn.cursor() as cursor:
        cursor.execute('select id, email_confirmed_at is not null from auth.users where lower(email)=%s and deleted_at is null', (email,))
        accounts = cursor.fetchall()
    if not accounts and args.action == 'provision':
        settings = auth_request(config, 'settings')
        if not settings.get('external', {}).get('email') or settings.get('disable_signup'):
            sys.exit('Create only the intended account through Dashboard > Authentication > Users, then use grant. Shared Auth configuration was not changed.')
        # Official Auth signup endpoint, executed locally for ONE explicitly approved account.
        # A generated password is discarded; the browser supports email OTP only.
        # This can send a confirmation email, subject to the existing SMTP settings.
        auth_request(config, 'signup', {'email': email, 'password': secrets.token_urlsafe(48)})
        with connect() as conn, conn.cursor() as cursor:
            cursor.execute('select id, email_confirmed_at is not null from auth.users where lower(email)=%s and deleted_at is null', (email,))
            accounts = cursor.fetchall()
    if len(accounts) != 1:
        sys.exit('Exactly one intended Auth account must exist. Create/check it in the private Auth dashboard; no allowlist change made.')
    user_id, confirmed = accounts[0]
    with connect() as conn, conn.cursor() as cursor:
        if args.action == 'revoke':
            cursor.execute('delete from public.thesis_admins where user_id=%s', (user_id,))
            print('Intended account removed from the thesis allowlist. Existing JWTs cannot use the read RPCs.')
        else:
            # Initial provisioning is deliberately limited to one administrator.
            cursor.execute('select count(*) from public.thesis_admins where user_id<>%s', (user_id,))
            if cursor.fetchone()[0]:
                sys.exit('Other allowlist entries exist; review them privately before granting another account.')
            cursor.execute('insert into public.thesis_admins(user_id) values(%s) on conflict(user_id) do nothing', (user_id,))
            print('Only the intended Auth account is allowlisted for thesis administration.')
            print('Email confirmed:', confirmed)
            print('Email delivery, OTP template and an actual browser sign-in still require verification. No shared Auth settings changed.')


if __name__ == '__main__':
    try:
        main()
    except psycopg.Error as error:
        sys.exit(f'Database operation failed (SQLSTATE {error.sqlstate or "unknown"}); no credentials or records logged.')
