#!/usr/bin/env python3
"""Synthetic browser checks. Only explicitly listed assets are served; no local secrets."""
import asyncio
import json
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    '/thesis-admin.html': ('thesis-admin.html', 'text/html'),
    '/public/supabase-config.js': ('public/supabase-config.js', 'text/javascript'),
    '/public/thesis-admin.js': ('public/thesis-admin.js', 'text/javascript'),
    '/public/thesis-admin.css': ('public/thesis-admin.css', 'text/css'),
}
ATTACK = '<img src=x onerror="window.pwned=1"><script>window.pwned=1</script>'
TIME = '2026-10-07T06:00:00.123456+00:00'


def application(i):
    return dict(id=f'00000000-0000-4000-8000-{i:012}', created_at=TIME,
        first_name=ATTACK if i == 1 else f'Synthetic {i}', last_name='Applicant',
        email='synthetic@example.invalid', degree_programme=ATTACK, thesis_level='bachelor',
        topics=['autumn26-a', 'other'], other_description=ATTACK, additional_notes=ATTACK)


def assignment(i):
    return dict(id=f'00000000-0000-4000-9000-{i:012}', assigned_at=TIME,
        first_name=f'Confirmed {i}', last_name='Synthetic', email=None, degree_programme=None,
        topic_id='other', other_description=ATTACK, application_id=None,
        application_arrived_at=None)


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        calls = []
        options = {}
        release = asyncio.Event()

        async def asset(route):
            path = urlparse(route.request.url).path
            if path in ASSETS:
                source, content_type = ASSETS[path]
                await route.fulfill(body=(ROOT / source).read_bytes(), content_type=content_type)
            else:
                await route.fulfill(status=404, body='')

        async def api(route):
            path = urlparse(route.request.url).path
            payload = route.request.post_data_json
            calls.append((path, payload, route.request.headers))
            code = 200
            response = {}
            if path.endswith('/otp'):
                assert payload == {'email': 'admin@example.invalid', 'create_user': False}
                code = options.get('otp_status', 200)
            elif path.endswith('/verify'):
                assert payload['type'] == 'email' and payload['token'] == '123456'
                code = options.get('verify_status', 200)
                response = {'access_token': 'synthetic-session', 'refresh_token': 'synthetic-refresh',
                    'expires_in': options.get('expires_in', 3600)}
            elif path.endswith('/token'):
                assert payload == {'refresh_token': 'synthetic-refresh'}
                code = options.get('refresh_status', 200)
                response = {'access_token': 'synthetic-session', 'refresh_token': 'synthetic-refresh', 'expires_in': 3600}
            elif path.endswith('/logout'):
                code = options.get('logout_status', 204)
            else:
                assert route.request.headers['authorization'] == 'Bearer synthetic-session'
                if path.endswith('/thesis_admin_access'):
                    response = options.get('allowed', True)
                else:
                    kind = 'applications' if path.endswith('applications') else 'assignments'
                    if options.get('pending') == kind:
                        await release.wait()
                    code = options.get(kind + '_status', 200)
                    if code == 'network':
                        await route.abort('failed')
                        return
                    size = options.get(kind + '_count', 21 if kind == 'applications' else 2)
                    offset = int(payload['after_id'][-12:]) if payload['after_id'] else 0
                    assert payload['page_size'] == 20
                    if offset:
                        assert payload['after_time'] == TIME
                        assert payload['through_time'] == TIME
                        assert payload['through_id'].endswith(f'{size:012}')
                    maker = application if kind == 'applications' else assignment
                    rows = [maker(i) for i in range(offset + 1, min(size, offset + 20) + 1)]
                    response = dict(rows=rows, has_more=offset + 20 < size,
                        next_cursor=dict(time=TIME, id=rows[-1]['id']) if rows else None,
                        snapshot=dict(time=TIME, id=maker(size)['id']) if size else None)
            await route.fulfill(status=code, content_type='application/json',
                body='' if code == 204 else json.dumps(response))

        await page.route('http://localhost/**', asset)
        await page.route('http://insecure.test/**', asset)
        await page.route('https://*.supabase.co/**', api)
        await page.add_init_script("""
            Storage.prototype.setItem = () => { throw new Error('Browser storage write forbidden'); };
            window.fetchOptions = [];
            const originalFetch = window.fetch;
            window.fetch = (url, options) => {
                window.fetchOptions.push([options.cache, options.credentials, options.referrerPolicy]);
                return originalFetch(url, options);
            };
        """)

        async def load():
            options.clear()
            calls.clear()
            release.clear()
            await page.goto('http://localhost/thesis-admin.html')
            await page.wait_for_function("() => !document.getElementById('send-code').disabled")

        async def code():
            await page.locator('#admin-email').fill('ADMIN@example.invalid')
            await page.locator('#send-code').click()
            await page.locator('#admin-code').wait_for(state='visible')
            await page.locator('#admin-code').fill('123456')
            await page.locator('#verify-code').click()

        async def signed_in():
            await page.locator('#dashboard').wait_for(state='visible')
            await page.wait_for_function("() => document.getElementById('applications-list').getAttribute('aria-busy') === 'false' && document.getElementById('assignments-list').getAttribute('aria-busy') === 'false'")

        async def cleared():
            await page.locator('#dashboard').wait_for(state='hidden')
            assert await page.locator('.record').count() == 0
            assert await page.locator('#admin-email').input_value() == ''
            assert await page.locator('#admin-code').input_value() == ''

        await load()
        assert await page.locator('#dashboard').is_hidden()
        assert not calls
        await page.locator('#send-code').click()
        assert not calls
        options['otp_status'] = 429
        await page.locator('#admin-email').fill('ADMIN@example.invalid')
        await page.locator('#send-code').click()
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('Too many')")
        options['otp_status'] = 200
        options['verify_status'] = 400
        await code()
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('invalid, expired')")
        assert await page.locator('#admin-code').input_value() == ''
        assert await page.locator('#dashboard').is_hidden()

        await load()
        options['allowed'] = False
        await code()
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('does not have')")
        await cleared()
        assert not any(path.endswith('applications') or path.endswith('assignments') for path, _, _ in calls)

        await load()
        options['pending'] = 'applications'
        await code()
        await page.locator('#dashboard').wait_for(state='visible')
        assert await page.locator('#applications-status').inner_text() == 'Loading…'
        assert await page.locator('#refresh-all').is_disabled()
        release.set()
        await signed_in()
        assert await page.locator('#applications-list .record').count() == 20
        assert await page.locator('#assignments-list .record').count() == 2
        assert '08:00:00' in await page.locator('#applications-list').inner_text()
        assert 'Bachelor’s' in await page.locator('#applications-list').inner_text()
        assert ATTACK in await page.locator('#applications-list').inner_text()
        assert await page.locator('.records img, .records script').count() == 0
        assert await page.evaluate('window.pwned') is None
        assert 'Assignment date' in await page.locator('#assignments-list').inner_text()
        assert 'Application arrival' in await page.locator('#assignments-list').inner_text()
        assert 'Not recorded' in await page.locator('#assignments-list').inner_text()
        await page.locator('#applications-more').click()
        await page.wait_for_function("() => document.querySelectorAll('#applications-list .record').length === 21")
        assert await page.locator('#applications-more').is_hidden()
        assert 'end of list' in await page.locator('#applications-status').inner_text()
        options['applications_count'] = 0
        options['assignments_count'] = 0
        await page.locator('#refresh-all').click()
        await page.wait_for_function("() => document.getElementById('applications-status').textContent === 'No applications yet.'")
        assert await page.locator('#assignments-status').inner_text() == 'No confirmed assignments yet.'
        options['applications_count'] = 21
        options['assignments_count'] = 22
        await page.locator('#refresh-all').click()
        await signed_in()
        await page.locator('#assignments-more').click()
        await page.wait_for_function("() => document.querySelectorAll('#assignments-list .record').length === 22")
        assert await page.locator('#assignments-more').is_hidden()
        assert await page.evaluate('localStorage.length + sessionStorage.length') == 0
        assert await page.context.cookies() == []
        assert all(opt == ['no-store', 'omit', 'no-referrer'] for opt in await page.evaluate('window.fetchOptions'))
        await page.locator('#logout').click()
        await cleared()
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('Logged out')")

        # Network/server errors retain no newly received data and offer a refresh.
        for failure in [503, 'network']:
            await load()
            options['applications_status'] = failure
            await code()
            await signed_in()
            assert 'Could not load' in await page.locator('#applications-status').inner_text()
            assert await page.locator('#applications-list .record').count() == 0
            options['applications_status'] = 200
            await page.locator('#refresh-all').click()
            await signed_in()
            assert await page.locator('#applications-list .record').count() == 20

        # Expired JWT and authorization revoked on subsequent reads clear both lists.
        for failure, message in [(401, 'session has expired'), (403, 'does not have')]:
            await load()
            await code()
            await signed_in()
            options['applications_status'] = failure
            await page.locator('#applications-more').click()
            await page.wait_for_function(f"() => document.getElementById('admin-status').textContent.includes('{message}')")
            await cleared()

        # Logout during a pending private read must not allow its late response to restore data.
        await load()
        await code()
        await signed_in()
        options['pending'] = 'applications'
        release.clear()
        await page.locator('#applications-more').click()
        await page.wait_for_function("() => document.getElementById('applications-list').getAttribute('aria-busy') === 'true'")
        options['logout_status'] = 503
        await page.locator('#logout').click()
        await cleared()
        release.set()
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('Server sign-out could not')")
        assert await page.locator('.record').count() == 0

        # Timer renewal succeeds, rechecks allowlist, and clears data when renewal fails.
        await page.clock.install()
        await load()
        options['expires_in'] = 61
        await code()
        await signed_in()
        await page.clock.fast_forward(32000)
        await page.wait_for_function("() => window.fetchOptions.length >= 7")
        assert any(path.endswith('/token') for path, _, _ in calls)
        assert await page.locator('#dashboard').is_visible()
        await load()
        options['expires_in'] = 61
        options['refresh_status'] = 401
        await code()
        await signed_in()
        await page.clock.fast_forward(32000)
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('could not be renewed')")
        await cleared()

        await load()
        options['expires_in'] = 61
        await code()
        await signed_in()
        options['allowed'] = False
        await page.clock.fast_forward(32000)
        await page.wait_for_function("() => document.getElementById('admin-status').textContent.includes('does not have')")
        await cleared()

        await load()
        options['pending'] = 'applications'
        await code()
        await page.locator('#dashboard').wait_for(state='visible')
        await page.clock.fast_forward(15001)
        await signed_in()
        assert 'Could not load' in await page.locator('#applications-status').inner_text()
        assert await page.locator('#applications-list .record').count() == 0
        release.set()

        await load()
        await code()
        await signed_in()
        # A tab suspended past expiry clears records when it becomes visible.
        from datetime import datetime, timezone, timedelta
        await page.clock.set_system_time(datetime.now(timezone.utc) + timedelta(days=2))
        await page.evaluate("document.dispatchEvent(new Event('visibilitychange'))")
        await cleared()
        assert 'session has expired' in await page.locator('#admin-status').inner_text()

        await page.goto('http://insecure.test/thesis-admin.html')
        assert await page.locator('#send-code').is_disabled()
        assert 'HTTPS' in await page.locator('#admin-status').inner_text()
        before = len(calls)
        await page.locator('#email-form').evaluate("form => form.dispatchEvent(new Event('submit', {cancelable:true}))")
        assert len(calls) == before
        await page.goto('http://localhost/supa.env')
        assert await page.locator('body').inner_text() == ''
        assert not errors, 'Unexpected JavaScript error'
        await browser.close()
        print('Admin browser checks passed: login-only OTP, allowlist, safe rendering, Rome dates, loading/empty/error, both paginations, memory-only session, refresh, expiry and logout races.')


if __name__ == '__main__':
    asyncio.run(main())
