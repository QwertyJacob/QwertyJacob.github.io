/* Submission-only API. Student details and credentials are never stored in browser storage. */
(() => {
    'use strict';
    const form = document.getElementById('thesis-application');
    const button = document.getElementById('submit-application');
    const status = document.getElementById('form-status');
    const other = document.getElementById('topic-other');
    const description = document.getElementById('other-topic-description');
    const topicInputs = [...form.querySelectorAll('.topics input')];
    const config = window.SITE_SUPABASE;
    const refreshButton = document.getElementById('refresh-availability');
    let availabilityReady = false;
    let checkingAvailability = false;
    let availability = new Map();
    let pending = false;
    let completed = false;
    let attempt = null;

    function showStatus(title, message, state = 'error') {
        status.dataset.state = state;
        status.querySelector('strong').textContent = title;
        status.querySelector('p').textContent = message;
    }

    function updateTopics() {
        document.getElementById('other-topic-field').hidden = !other.checked;
        description.disabled = pending || !other.checked;
        description.required = other.checked;
        other.setAttribute('aria-expanded', String(other.checked));
        topicInputs.forEach(input => input.setCustomValidity(''));
        const validationTarget = topicInputs.find(input => !input.disabled);
        validationTarget?.setCustomValidity(topicInputs.some(input => input.checked && availability.get(input.value))
            ? '' : 'Select at least one available topic of interest.');
    }
    topicInputs.forEach(input => input.addEventListener('change', updateTopics));
    window.addEventListener('pageshow', updateTopics);
    updateTopics();

    if (!config?.url || !config?.publishableKey || !globalThis.crypto?.getRandomValues) {
        showStatus('Submission unavailable', 'The form could not be initialized. Please try again later.');
        return;
    }
    // Also works on the university’s HTTP site, where crypto.randomUUID is unavailable.
    function uuid() {
        const bytes = crypto.getRandomValues(new Uint8Array(16));
        bytes[6] = (bytes[6] & 15) | 64;
        bytes[8] = (bytes[8] & 63) | 128;
        const hex = [...bytes].map(value => value.toString(16).padStart(2, '0')).join('');
        return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
    }
    function applyAvailability() {
        topicInputs.forEach(input => {
            const available = availabilityReady && availability.get(input.value) === true;
            input.disabled = pending || completed || !available;
            if (!available) input.checked = false;
            let badge = input.closest('label').querySelector('.topic-availability');
            if (!badge) {
                badge = document.createElement('span');
                badge.className = 'hint topic-availability';
                input.closest('label').querySelector('span').append(badge);
            }
            badge.textContent = !availabilityReady ? 'Availability not confirmed'
                : available ? '' : 'Unavailable';
        });
        updateTopics();
        button.disabled = pending || completed || checkingAvailability || !availabilityReady;
        refreshButton.disabled = pending || completed || checkingAvailability;
    }

    async function loadAvailability(announce = true) {
        if (checkingAvailability || completed) return;
        checkingAvailability = true;
        availabilityReady = false;
        button.disabled = true;
        refreshButton.disabled = true;
        if (announce) showStatus('Checking topic availability', 'Please wait while the available topics are checked.', 'loading');
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 10000);
        try {
            const response = await fetch(`${config.url}/rest/v1/rpc/thesis_topic_availability`, {
                method: 'POST', headers: { apikey: config.publishableKey, 'Content-Type': 'application/json' },
                body: '{}', signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store'
            });
            if (!response.ok) throw new Error('Availability unavailable');
            const rows = await response.json();
            const expected = new Set(topicInputs.map(input => input.value));
            if (!Array.isArray(rows) || rows.length !== expected.size
                || rows.some(row => !expected.delete(row.topic_id) || typeof row.available !== 'boolean')) {
                throw new Error('Invalid availability response');
            }
            availability = new Map(rows.map(row => [row.topic_id, row.available]));
            availabilityReady = true;
            if (announce) showStatus('Applications for Bachelor’s theses', 'Select at least one available topic. Your details will be sent privately to the supervisor.', 'ready');
        } catch {
            if (announce) showStatus('Topic availability could not be checked', 'Please use Refresh availability to try again. Submission is paused until availability can be confirmed.');
        } finally {
            clearTimeout(timeout);
            checkingAvailability = false;
            applyAvailability();
        }
    }
    topicInputs.forEach(input => { input.disabled = true; });
    refreshButton.addEventListener('click', () => loadAvailability());
    loadAvailability();
    form.addEventListener('submit', async event => {
        event.preventDefault();
        if (pending || completed || checkingAvailability || !availabilityReady) return;
        updateTopics();
        if (!form.reportValidity()) return;
        const value = id => document.getElementById(id).value.trim();
        const payload = {
            first_name: value('first-name'), last_name: value('last-name'),
            email: value('email').toLowerCase(), degree_programme: value('degree-program'),
            thesis_level: value('degree-level'),
            topics: topicInputs.filter(input => input.checked).map(input => input.value),
            other_description: other.checked ? value('other-topic-description') : '',
            additional_notes: value('additional-notes'), website: value('website')
        };
        if (!payload.first_name || !payload.last_name || payload.degree_programme.length < 2
            || payload.thesis_level !== 'bachelor'
            || (other.checked && payload.other_description.length < 20)) {
            showStatus('Check your application', 'Enter your name and degree programme, choose Bachelor’s, and describe Other topics in at least 20 characters.');
            status.focus();
            return;
        }
        const fingerprint = JSON.stringify(payload);
        // Keep the same key on a retry with identical fields, including after a timeout.
        if (!attempt || attempt.fingerprint !== fingerprint) attempt = { fingerprint, id: uuid() };
        payload.application_id = attempt.id;
        const enabledControls = [...form.elements].filter(element => !element.disabled);
        pending = true;
        button.disabled = true;
        button.textContent = 'Submitting…';
        form.setAttribute('aria-busy', 'true');
        enabledControls.forEach(element => { element.disabled = true; });
        showStatus('Submitting your application', 'Please wait for confirmation before leaving this page.', 'loading');
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 20000);
        try {
            const response = await fetch(`${config.url}/rest/v1/rpc/submit_thesis_application`, {
                method: 'POST',
                headers: { apikey: config.publishableKey, 'Content-Type': 'application/json' },
                body: JSON.stringify(payload), signal: controller.signal,
                credentials: 'omit', referrerPolicy: 'no-referrer'
            });
            if (!response.ok) {
                if (response.status === 409) {
                    await loadAvailability(false);
                    throw new Error('A selected topic is no longer available. Please choose another available topic. If availability could not be checked, use Refresh availability.');
                }
                if (response.status === 429) throw new Error('Submissions are temporarily limited. Please try again later.');
                if (response.status === 400) throw new Error('Check your application fields and try again. Other topics need a description of 20–2000 characters.');
                throw new Error('Submission is currently unavailable. Please try again later.');
            }
            completed = true;
            showStatus('Application received', 'Thank you. Your application has been sent privately to the supervisor. You will be contacted at your university email.', 'success');
            form.reset();
            attempt = null;
            button.textContent = 'Application submitted';
        } catch (error) {
            const message = error.name === 'AbortError' || error instanceof TypeError
                ? 'Confirmation could not be received. Please retry with the same details; a retry will not create a duplicate application.'
                : error.message;
            showStatus('Application not confirmed', message);
            button.textContent = 'Retry submission';
        } finally {
            clearTimeout(timeout);
            pending = false;
            form.setAttribute('aria-busy', 'false');
            if (!completed) {
                enabledControls.forEach(element => { element.disabled = false; });
                applyAvailability();
            } else {
                document.getElementById('other-topic-field').hidden = true;
                other.setAttribute('aria-expanded', 'false');
            }
            status.focus();
        }
    });
})();
