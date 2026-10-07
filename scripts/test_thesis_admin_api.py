#!/usr/bin/env python3
"""Read-only anonymous checks against the live project using public browser config only."""
import json
from pathlib import Path
import re
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'public/supabase-config.js').read_text()
config = json.loads(re.search(r'Object\.freeze\((\{.*?\})\)', source, re.S).group(1))
assert config['url'] == 'https://kmfpuqswhgslmhvekphl.supabase.co'


def request(path, body=None):
    req = urllib.request.Request(config['url'] + '/rest/v1/' + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={'apikey': config['publishableKey'], 'Content-Type': 'application/json'},
        method='GET' if body is None else 'POST')
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, None  # Never log a server response or student data.


for table in ['thesis_applications', 'thesis_topic_assignments', 'thesis_admins']:
    status, _ = request(table + '?select=*')
    assert status in (401, 403), 'Anonymous direct table read was not denied'
for rpc in ['thesis_admin_access', 'thesis_admin_applications', 'thesis_admin_assignments']:
    status, _ = request('rpc/' + rpc, {})
    assert status in (401, 403), 'Anonymous admin RPC was not denied'
status, rows = request('rpc/thesis_topic_availability', {})
assert status == 200 and len(rows) == 6
assert all(set(row) == {'topic_id', 'available'} for row in rows)
availability = {row['topic_id']: row['available'] for row in rows}
assert availability['other'] is True and availability['autumn26-d'] is False
print('Live anonymous API checks passed: all private tables/admin RPCs denied; public availability exposes only topic IDs/booleans, Other open and D closed.')
