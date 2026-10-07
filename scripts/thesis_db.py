#!/usr/bin/env python3
"""Local admin helper. Requires psycopg[binary] and python-dotenv; never logs credentials."""
import argparse
import os
from pathlib import Path
import sys

import psycopg
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'kmfpuqswhgslmhvekphl'


def connect():
    config = dotenv_values(ROOT / 'supa.env')
    if config.get('PROJECT_ID') != PROJECT or not config.get('DB_PASSWORD'):
        sys.exit('Expected the existing PSI project credentials in local supa.env.')
    host = os.environ.get('THESIS_DB_HOST', f'db.{PROJECT}.supabase.co')
    user = 'postgres' if host == f'db.{PROJECT}.supabase.co' else f'postgres.{PROJECT}'
    try:
        return psycopg.connect(host=host, port=int(os.environ.get('THESIS_DB_PORT', '5432')),
            dbname='postgres', user=user, password=config['DB_PASSWORD'],
            sslmode='require', connect_timeout=8)
    except psycopg.Error:
        sys.exit('Database connection failed. Set THESIS_DB_HOST/THESIS_DB_PORT to the session pooler shown in Dashboard > Connect. Credentials were not logged.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'apply', 'test'])
    parser.add_argument('--migration', choices=[p.name for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))],
        default='202610070001_thesis_applications.sql', help='Migration file to apply once (apply action only).')
    args = parser.parse_args()
    with connect() as conn:
        with conn.cursor() as cur:
            if args.action == 'inspect':
                cur.execute("select current_database(), to_regclass('public.thesis_applications'), to_regclass('public.votes')")
                print(cur.fetchone())
            elif args.action == 'apply':
                cur.execute((ROOT / 'supabase/migrations' / args.migration).read_text())
                print('Thesis migration applied to the existing PSI project.')
            else:
                for test in sorted((ROOT / 'supabase/tests').glob('*.sql')):
                    cur.execute(test.read_text())
                print('Thesis database tests passed; test data rolled back.')


if __name__ == '__main__':
    try:
        main()
    except psycopg.Error as error:
        # Do not print server details, parameters, or student records.
        sys.exit(f'Database operation failed (SQLSTATE {error.sqlstate or "unknown"}). No credentials or records logged.')
