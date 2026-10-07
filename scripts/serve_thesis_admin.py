#!/usr/bin/env python3
"""Loopback-only preview of explicitly allowed thesis assets. Never serves supa.env."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    '/': ('thesis-admin.html', 'text/html; charset=utf-8'),
    '/thesis-admin.html': ('thesis-admin.html', 'text/html; charset=utf-8'),
    '/tesi.html': ('tesi.html', 'text/html; charset=utf-8'),
    '/public/supabase-config.js': ('public/supabase-config.js', 'text/javascript; charset=utf-8'),
    '/public/thesis-admin.js': ('public/thesis-admin.js', 'text/javascript; charset=utf-8'),
    '/public/thesis-admin.css': ('public/thesis-admin.css', 'text/css; charset=utf-8'),
    '/public/thesis-application.js': ('public/thesis-application.js', 'text/javascript; charset=utf-8'),
    '/public/thesis-guide/autum26.pdf': ('public/thesis-guide/autum26.pdf', 'application/pdf'),
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        asset = ASSETS.get(urlsplit(self.path).path)
        if asset is None or not (ROOT / asset[0]).is_file():
            self.send_response(404)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            return
        content = (ROOT / asset[0]).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', asset[1])
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Frame-Options', 'DENY')
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, *_):
        pass  # No request URLs, authentication codes or records in logs.


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'Thesis preview: http://localhost:{args.port}/thesis-admin.html', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
