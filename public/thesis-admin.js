/* Supabase Auth REST, with session and private records held only in page memory. */
(() => {
    'use strict';
    const $ = id => document.getElementById(id);
    const config = window.SITE_SUPABASE;
    const usable = Boolean(config?.url && config?.publishableKey) &&
        (location.protocol === 'https:' || ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname));
    const status = message => { $('admin-status').textContent = message; };
    let session = null;
    let email = '';
    let epoch = 0;
    let refreshTimer;
    let refreshTask = null;
    let authBusy = false;
    const pending = new Set();
    const sections = ['applications', 'assignments'].map(kind => ({
        kind, cursor: null, snapshot: null, busy: false, count: 0,
        list: $(kind + '-list'), status: $(kind + '-status'), more: $(kind + '-more')
    }));
    const dateFormat = new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/Rome', year: 'numeric', month: 'short', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit', timeZoneName: 'short'
    });
    const formatDate = value => value ? dateFormat.format(new Date(value)) : 'Not recorded';
    const topicNames = {
        'autumn26-a': 'A · Additivity', 'autumn26-b': 'B · Linear decoding of ATT&CK techniques',
        'autumn26-c': 'C · Order invariance', 'autumn26-d': 'D · Fine-tuning and compositional geometry',
        'autumn26-e': 'E · Compositional novelty benchmark', other: 'Other'
    };
    function clearSection(section) {
        section.list.replaceChildren();
        section.status.textContent = '';
        section.cursor = section.snapshot = null;
        section.busy = false;
        section.count = 0;
        section.more.hidden = true;
        section.more.disabled = false;
        section.list.setAttribute('aria-busy', 'false');
    }
    function clearPrivate(message) {
        epoch++;
        clearTimeout(refreshTimer);
        for (const controller of pending) controller.abort();
        pending.clear();
        session = null;
        refreshTask = null;
        email = '';
        authBusy = false;
        sections.forEach(clearSection);
        $('dashboard').hidden = true;
        $('login-panel').hidden = false;
        $('email-form').hidden = false;
        $('code-form').hidden = true;
        $('email-form').reset();
        $('code-form').reset();
        $('send-code').disabled = !usable;
        $('verify-code').disabled = false;
        $('admin-email').disabled = false;
        $('refresh-all').disabled = false;
        status(message);
    }
    async function request(path, body, token, keepalive = false) {
        const controller = new AbortController();
        pending.add(controller);
        const timeout = setTimeout(() => controller.abort(), 15000);
        try {
            const headers = { apikey: config.publishableKey, 'Content-Type': 'application/json' };
            if (token) headers.Authorization = 'Bearer ' + token;
            const response = await fetch(config.url + path, {
                method: 'POST', headers, body: JSON.stringify(body), cache: 'no-store',
                credentials: 'omit', referrerPolicy: 'no-referrer', signal: controller.signal, keepalive
            });
            if (!response.ok) throw Object.assign(new Error('Request failed'), { status: response.status });
            if (response.status === 204) return null;
            return await response.json();
        } finally {
            clearTimeout(timeout);
            pending.delete(controller);
        }
    }
    function installSession(data) {
        if (!data || !data.access_token || !data.refresh_token || !(data.expires_in > 0)) {
            throw new Error('Invalid session');
        }
        session = {
            access: data.access_token, refresh: data.refresh_token,
            expires: data.expires_at ? data.expires_at * 1000 : Date.now() + data.expires_in * 1000
        };
        clearTimeout(refreshTimer);
        refreshTimer = setTimeout(() => renewSession(), Math.max(0, session.expires - Date.now() - 30000));
    }
    async function renewSession() {
        if (refreshTask) return refreshTask;
        if (!session) return false;
        if (Date.now() >= session.expires) {
            clearPrivate('Your session has expired. Sign in again.');
            return false;
        }
        const run = epoch;
        const refresh = session.refresh;
        refreshTask = (async () => {
            try {
                const data = await request('/auth/v1/token?grant_type=refresh_token', { refresh_token: refresh });
                if (run !== epoch) return false;
                installSession(data);
                // Recheck authorization after renewal, including when the allowlist changed.
                const allowed = await request('/rest/v1/rpc/thesis_admin_access', {}, session.access);
                if (run !== epoch) return false;
                if (allowed !== true) {
                    clearPrivate('This account does not have administrator access.');
                    return false;
                }
                return true;
            } catch (_) {
                if (run === epoch) clearPrivate('Your session has expired or could not be renewed. Sign in again.');
                return false;
            } finally {
                if (run === epoch) refreshTask = null;
            }
        })();
        return refreshTask;
    }
    async function rpc(name, body) {
        const run = epoch;
        if (!session || Date.now() >= session.expires) {
            clearPrivate('Your session has expired. Sign in again.');
            throw new Error('Session expired');
        }
        if (session.expires - Date.now() < 30000 && !(await renewSession())) throw new Error('Session expired');
        try {
            return await request('/rest/v1/rpc/' + name, body, session.access);
        } catch (error) {
            if (run === epoch && error.status === 401) clearPrivate('Your session has expired. Sign in again.');
            else if (run === epoch && error.status === 403) clearPrivate('This account does not have administrator access.');
            throw error;
        }
    }
    // All record values are text nodes. Student content never becomes markup or URLs.
    function renderRecord(row, kind) {
        const card = document.createElement('article');
        card.className = 'record';
        const heading = document.createElement('h3');
        heading.textContent = row.first_name + ' ' + row.last_name;
        const details = document.createElement('dl');
        const field = (label, value) => {
            const dt = document.createElement('dt');
            const dd = document.createElement('dd');
            dt.textContent = label;
            dd.textContent = value || 'Not recorded';
            details.append(dt, dd);
        };
        if (kind === 'applications') {
            field('Application arrival', formatDate(row.created_at));
        } else {
            field('Assignment date', formatDate(row.assigned_at));
            field('Application arrival', formatDate(row.application_arrived_at));
        }
        field('Email', row.email);
        field('Degree programme', row.degree_programme);
        if (kind === 'applications') field('Thesis level', row.thesis_level === 'bachelor' ? 'Bachelor’s' : row.thesis_level);
        field(kind === 'applications' ? 'Selected topics' : 'Assigned topic',
            (kind === 'applications' ? row.topics : [row.topic_id]).map(t => topicNames[t] || t).join('\n'));
        field('Other description', row.other_description);
        if (kind === 'applications') field('Additional notes', row.additional_notes);
        card.append(heading, details);
        return card;
    }
    async function loadSection(section) {
        if (section.busy || !session) return;
        const run = epoch;
        section.busy = true;
        section.more.disabled = true;
        section.status.textContent = 'Loading…';
        section.list.setAttribute('aria-busy', 'true');
        try {
            const data = await rpc('thesis_admin_' + section.kind, {
                page_size: 20,
                after_time: section.cursor?.time || null, after_id: section.cursor?.id || null,
                through_time: section.snapshot?.time || null, through_id: section.snapshot?.id || null
            });
            if (run !== epoch || !session) return;
            if (!Array.isArray(data.rows) || typeof data.has_more !== 'boolean') throw new Error('Invalid page');
            const cards = data.rows.map(row => renderRecord(row, section.kind));
            section.list.append(...cards);
            section.count += data.rows.length;
            section.cursor = data.next_cursor;
            section.snapshot = data.snapshot;
            section.more.hidden = !data.has_more;
            section.status.textContent = section.count === 0
                ? (section.kind === 'applications' ? 'No applications yet.' : 'No confirmed assignments yet.')
                : section.count + ' shown · ' + (data.has_more ? 'more available' : 'end of list');
        } catch (_) {
            if (run === epoch) section.status.textContent = 'Could not load ' + section.kind + '. Please try again using Refresh all or Load more.';
        } finally {
            if (run === epoch) {
                section.busy = false;
                section.more.disabled = false;
                section.list.setAttribute('aria-busy', 'false');
            }
        }
    }
    async function refreshAll() {
        if (!session || sections.some(section => section.busy)) return;
        sections.forEach(clearSection);
        $('refresh-all').disabled = true;
        const run = epoch;
        await Promise.all(sections.map(loadSection));
        if (run === epoch) $('refresh-all').disabled = false;
    }
    $('email-form').addEventListener('submit', async event => {
        event.preventDefault();
        if (authBusy || !usable) return;
        authBusy = true;
        email = $('admin-email').value.trim().toLowerCase();
        $('send-code').disabled = true;
        $('admin-email').disabled = true;
        status('Requesting a sign-in code…');
        const run = epoch;
        try {
            // Login only: the public page never provisions an Auth account.
            await request('/auth/v1/otp', { email, create_user: false });
            if (run !== epoch) return;
            $('email-form').hidden = true;
            $('code-form').hidden = false;
            $('admin-code').focus();
            status('If your account is eligible, a sign-in code has been sent. Check your email.');
        } catch (error) {
            if (run === epoch) status(error.status === 429
                ? 'Too many sign-in requests. Please wait before trying again.'
                : 'Could not request a code. Check your account and the project’s email setup, then try again.');
        } finally {
            if (run === epoch) {
                authBusy = false;
                $('send-code').disabled = false;
                $('admin-email').disabled = false;
            }
        }
    });
    $('code-form').addEventListener('submit', async event => {
        event.preventDefault();
        if (authBusy || !usable) return;
        authBusy = true;
        $('verify-code').disabled = true;
        status('Verifying your sign-in code…');
        const token = $('admin-code').value.trim();
        $('admin-code').value = '';
        const run = epoch;
        try {
            const data = await request('/auth/v1/verify', { email, token, type: 'email' });
            if (run !== epoch) return;
            installSession(data);
            const allowed = await rpc('thesis_admin_access', {});
            if (run !== epoch) return;
            if (allowed !== true) {
                const access = session.access;
                clearPrivate('This account does not have administrator access.');
                void request('/auth/v1/logout?scope=local', {}, access).catch(() => {});
                return;
            }
            email = '';
            $('email-form').reset();
            $('login-panel').hidden = true;
            $('dashboard').hidden = false;
            status('Signed in · read-only administration.');
            await refreshAll();
        } catch (_) {
            if (run === epoch) {
                if (session) clearPrivate('Could not verify administrator access. Sign in again.');
                else status('The code is invalid, expired, or could not be verified. Try again or request a new code.');
            }
        } finally {
            if (run === epoch) {
                authBusy = false;
                $('verify-code').disabled = false;
            }
        }
    });
    $('change-email').addEventListener('click', () => clearPrivate('Sign in with your administrator email.'));
    $('refresh-all').addEventListener('click', refreshAll);
    sections.forEach(section => section.more.addEventListener('click', () => loadSection(section)));
    $('logout').addEventListener('click', async () => {
        const access = session?.access;
        clearPrivate('Logged out. Private data has been cleared.');
        const run = epoch;
        if (access) {
            try { await request('/auth/v1/logout?scope=local', {}, access); }
            catch (_) {
                if (run === epoch) status('Logged out locally. Server sign-out could not be confirmed; this session’s access token remains valid until expiry.');
            }
        }
    });
    // Returning from a suspended tab must not leave expired records visible.
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && session && Date.now() >= session.expires) clearPrivate('Your session has expired. Sign in again.');
    });
    window.addEventListener('pagehide', () => clearPrivate('Sign in with your administrator email.'));
    if (!config?.url || !config?.publishableKey) {
        status('Administration is unavailable: public Supabase configuration is missing.');
    } else if (location.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(location.hostname)) {
        status('Open administration over HTTPS to sign in securely.');
    } else {
        $('send-code').disabled = false;
    }
})();
