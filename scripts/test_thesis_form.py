#!/usr/bin/env python3
"""Browser checks with synthetic data and mocked RPC; serves only an explicit asset allowlist."""
import asyncio
from pathlib import Path
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    '/tesi.html': ('tesi.html', 'text/html'),
    '/public/supabase-config.js': ('public/supabase-config.js', 'text/javascript'),
    '/public/thesis-application.js': ('public/thesis-application.js', 'text/javascript'),
}


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        requests = []
        release = asyncio.Event()
        mode = 'success'

        unavailable = {'autumn26-d'}
        availability_status = 200

        async def availability_rpc(route):
            import json
            rows = [{'topic_id': topic, 'available': topic not in unavailable} for topic in
                ['autumn26-a','autumn26-b','autumn26-c','autumn26-d','autumn26-e','other']]
            await route.fulfill(status=availability_status, body=json.dumps(rows), content_type='application/json')

        async def rpc(route):
            requests.append(route.request.post_data_json)
            if mode == '409':
                unavailable.add('autumn26-a')
            if mode in ['pending', 'timeout']:
                await release.wait()
            if mode == 'network':
                await route.abort('failed')
            else:
                code = int(mode) if mode.isdigit() else 204
                await route.fulfill(status=code, body='' if code == 204 else '{}')

        async def asset(route):
            from urllib.parse import urlparse
            path = urlparse(route.request.url).path
            if path in ASSETS:
                source, content_type = ASSETS[path]
                await route.fulfill(body=(ROOT / source).read_bytes(), content_type=content_type)
            else:
                await route.fulfill(status=404, body='')

        await page.route('http://thesis.test/**', asset)
        await page.route('https://*/rest/v1/rpc/submit_thesis_application', rpc)
        await page.route('https://*/rest/v1/rpc/thesis_topic_availability', availability_rpc)

        async def load():
            await page.goto('http://thesis.test/tesi.html')
            await page.wait_for_function("!document.getElementById('submit-application').disabled")

        async def fill():
            for field, value in [('first-name','Test'), ('last-name','Applicant'),
                    ('email','student@example.invalid'), ('degree-program','Computer Science')]:
                await page.locator('#' + field).fill(value)
            await page.locator('#degree-level').select_option('bachelor')
            await page.locator('#topic-a').check()

        async def finished():
            await page.wait_for_function("document.getElementById('thesis-application').getAttribute('aria-busy') === 'false'")

        await load()
        assert await page.locator('#topic-d').is_disabled()
        assert 'Unavailable' in await page.locator('label[for=topic-d]').inner_text()
        assert await page.locator('#degree-level option[value=master]').is_disabled()
        assert await page.locator('#other-topic-field').is_hidden()
        assert await page.locator('#additional-notes').is_visible()
        assert await page.locator('.guide-download').get_attribute('href') == 'public/thesis-guide/autum26.pdf'
        await page.locator('#submit-application').click()
        assert not requests
        await fill()
        await page.locator('#topic-a').uncheck()
        await page.locator('#submit-application').click()
        assert not requests
        await page.locator('#topic-a').check()
        await page.locator('#topic-e').check()
        await page.locator('#topic-other').check()
        assert await page.locator('#other-topic-field').is_visible()
        assert await page.locator('#other-topic-description').get_attribute('required') is not None
        await page.locator('#other-topic-description').fill('short')
        await page.locator('#submit-application').click()
        assert not requests
        await page.locator('#other-topic-description').fill('An alternative topic with enough detail.')
        mode = 'pending'
        await page.locator('#submit-application').click()
        await page.wait_for_function("document.getElementById('thesis-application').getAttribute('aria-busy') === 'true'")
        assert await page.locator('#submit-application').is_disabled()
        await page.locator('#thesis-application').evaluate("form => form.dispatchEvent(new Event('submit', {cancelable:true}))")
        await asyncio.sleep(.15)
        assert len(requests) == 1
        release.set()
        await finished()
        assert requests[0]['topics'] == ['autumn26-a', 'autumn26-e', 'other']
        assert await page.locator('#form-status').get_attribute('data-state') == 'success'
        assert await page.locator('#first-name').input_value() == ''
        assert await page.locator('#submit-application').is_disabled()

        for mode, message in [('400','Check your application'), ('429','temporarily limited'),
                ('503','currently unavailable'), ('network','retry with the same details')]:
            await load()
            await fill()
            await page.locator('#topic-other').check()
            await page.locator('#other-topic-description').fill('A topic which should not be sent once Other is unchecked.')
            await page.locator('#topic-other').uncheck()
            assert await page.locator('#other-topic-description').is_disabled()
            await page.locator('#submit-application').click()
            await finished()
            assert message in await page.locator('#form-status').inner_text()
            assert not await page.locator('#submit-application').is_disabled()
            assert requests[-1]['other_description'] == ''
            retry_id = requests[-1]['application_id']
            mode = 'success'
            await page.locator('#submit-application').click()
            await finished()
            assert requests[-1]['application_id'] == retry_id
            assert await page.locator('#form-status').get_attribute('data-state') == 'success'
        await load()
        await fill()
        mode = '409'
        await page.locator('#submit-application').click()
        await finished()
        assert 'no longer available' in await page.locator('#form-status').inner_text()
        assert await page.locator('#topic-a').is_disabled()
        assert not await page.locator('#topic-a').is_checked()
        assert await page.locator('#first-name').input_value() == 'Test'
        await page.locator('#topic-b').check()
        mode = 'success'
        await page.locator('#submit-application').click()
        await finished()
        assert await page.locator('#form-status').get_attribute('data-state') == 'success'
        unavailable.discard('autumn26-a')

        availability_status = 503
        await page.goto('http://thesis.test/tesi.html')
        await page.wait_for_function("document.getElementById('form-status').textContent.includes('could not be checked')")
        assert await page.locator('#submit-application').is_disabled()
        assert await page.locator('#topic-a').is_disabled()
        availability_status = 200
        await page.locator('#refresh-availability').click()
        await page.wait_for_function("!document.getElementById('submit-application').disabled")
        assert await page.locator('#topic-d').is_disabled()
        await load()
        await page.clock.install()
        await fill()
        mode = 'timeout'
        release.clear()
        before = len(requests)
        await page.locator('#submit-application').click()
        while len(requests) == before:
            await asyncio.sleep(.01)
        await page.clock.fast_forward(20001)
        await finished()
        assert 'retry with the same details' in await page.locator('#form-status').inner_text()
        timed_out_id = requests[-1]['application_id']
        release.set()
        mode = 'success'
        await page.locator('#submit-application').click()
        await finished()
        assert requests[-1]['application_id'] == timed_out_id
        assert await page.locator('#form-status').get_attribute('data-state') == 'success'
        assert not errors, errors
        assert await page.evaluate('localStorage.length + sessionStorage.length') == 0
        await browser.close()
        print('Browser tests passed: validation, conditional fields, multiple topics, pending lock, success, HTTP/network/timeout failures, idempotent retries, no browser storage, DB availability, stale-topic rejection, availability failure recovery.')


if __name__ == '__main__':
    asyncio.run(main())
