/* ──────────────────────────────────────────────────────────────────────────────
   DVLA Portal — Frontend Application
────────────────────────────────────────────────────────────────────────────── */

'use strict';

// ─── Language (locale) ───────────────────────────────────────────────────────
// The dictionary comes from the client script (RegisterNUICallback 'locale' -> LocaleDict()).
// English stays in the HTML/JS as the default; keys live in locales/en.lua.

var RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'as-drivingschool';

// NUI locale helper. English text stays in the HTML as the default, so the page is never blank if the
// dictionary is late; once the dictionary arrives applyI18n() swaps in the chosen language.
// Markup: the attributes data-i18n (text), data-i18n-placeholder, data-i18n-title and data-i18n-aria-label
// name a locale key; the element keeps its English text as the default.
// In JS call t with a key plus arguments: %s / %d placeholders are filled in order; a missing key returns the key.
var I18N = {};
function t(key) {
    var s = Object.prototype.hasOwnProperty.call(I18N, key) ? I18N[key] : key;
    var args = Array.prototype.slice.call(arguments, 1), i = 0;
    return String(s).replace(/%[sd]/g, function () { return i < args.length ? args[i++] : ''; });
}
function applyI18n(root) {
    root = root || document;
    root.querySelectorAll('[data-i18n]').forEach(function (el) { if (I18N[el.dataset.i18n] != null) el.textContent = t(el.dataset.i18n); });
    ['placeholder', 'title', 'aria-label'].forEach(function (a) {
        root.querySelectorAll('[data-i18n-' + a + ']').forEach(function (el) {
            var k = el.getAttribute('data-i18n-' + a); if (I18N[k] != null) el.setAttribute(a, t(k));
        });
    });
}
// RESOURCE = this resource's name. The client script answers this callback with LocaleDict().
function loadLocale(cb) {
    fetch('https://' + RESOURCE + '/locale', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
        .then(function (r) { return r.json(); })
        .then(function (d) { if (d && typeof d === 'object') { I18N = d; } applyI18n(); if (cb) cb(); })
        .catch(function () { if (cb) cb(); });
}

// Elements marked data-i18n-html hold a little markup (<strong> ...) inside the locale string.
function applyI18nHtml() {
    document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
        var k = el.getAttribute('data-i18n-html');
        if (I18N[k] != null) el.innerHTML = t(k);
    });
}

function localeReady() { return Object.keys(I18N).length > 0; }

// Loads the dictionary if it is not there yet, then re-renders whatever is on screen.
function ensureLocale(after) {
    if (localeReady()) return;
    loadLocale(function () {
        applyI18nHtml();
        if (State.playerData) renderAll();
        if (after) after();
    });
}

// ─── State ───────────────────────────────────────────────────────────────────

const State = {
    playerData:    null,
    testQuestions: [],
    testAnswers:   [],
    currentQ:      0,
    timerInterval: null,
    timeLeft:      480,
};

// Theory questions from config (injected via message)
let THEORY_QUESTIONS = [];
const TOTAL_QUESTIONS = 15;
const PASS_MARK = 12;
const TIME_LIMIT = 480;

// ─── NUI Communication ───────────────────────────────────────────────────────

function nuiFetch(event, data = {}) {
    const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'as-drivingschool';
    return fetch(`https://${res}/${event}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data),
    }).then(r => r.json());
}

// ─── Init ────────────────────────────────────────────────────────────────────

window.addEventListener('message', (e) => {
    const msg = e.data;
    if (!msg || !msg.action) return;

    switch (msg.action) {
        case 'openUI':
            document.getElementById('app').classList.add('ui-open');
            State.playerData = msg.data;
            if (msg.data.questions) THEORY_QUESTIONS = msg.data.questions;
            ensureLocale();
            renderAll();
            showSection('dashboard');
            break;

        case 'closeUI':
            document.getElementById('app').classList.remove('ui-open');
            clearInterval(State.timerInterval);
            break;

        case 'updatePoints':
            if (State.playerData && State.playerData.licence) {
                State.playerData.licence.penalty_points = msg.points;
                renderStatusCards();
                renderLicence();
                renderPenalty();
            }
            break;
    }
});

// ─── Section Routing ─────────────────────────────────────────────────────────

function showSection(name) {
    document.querySelectorAll('main section').forEach(s => s.hidden = true);

    const id = name.startsWith('section-') ? name : 'section-' + name;
    const el = document.getElementById(id);
    if (el) el.hidden = false;

    // Re-render pages that depend on state which may have changed since initial load
    if (id === 'section-practical') renderPracticalPage();
    if (id === 'section-theory')    renderTheoryPage();
    if (id === 'section-replace')   renderReplacePage();
}

// ─── Render All ──────────────────────────────────────────────────────────────

function renderAll() {
    const d = State.playerData;
    if (!d) return;

    document.getElementById('welcomeLine').innerHTML =
        t('ui.dash.welcome', '<strong id="playerName">' + esc(d.playerName || '—') + '</strong>');

    renderStatusCards();
    renderLicence();
    renderPenalty();
    renderHistory();
    renderTheoryPage();
    renderPracticalPage();
    renderReplacePage();
}

// ─── Status Cards ─────────────────────────────────────────────────────────────

function renderStatusCards() {
    const lic = State.playerData.licence;

    const licType = lic ? lic.licence_type : 'none';
    const labels = { none: t('ui.status.noLicence'), provisional: t('ui.status.provisional'), full: t('ui.status.full'), suspended: t('ui.status.suspended') };
    document.getElementById('statusLicence').textContent = labels[licType] || licType;

    const pts = lic ? (lic.penalty_points || 0) : 0;
    document.getElementById('statusPoints').textContent = pts + ' / 12';

    const theoryPassed = lic && lic.theory_passed;
    document.getElementById('statusTheory').textContent = theoryPassed ? t('ui.passedTick') : t('ui.notPassedCross');

    const practPassed = lic && lic.practical_passed;
    document.getElementById('statusPractical').textContent = practPassed ? t('ui.passedTick') : t('ui.notPassedCross');
}

// ─── My Licence ──────────────────────────────────────────────────────────────

function renderLicence() {
    const d = State.playerData;
    const lic = d.licence;

    document.getElementById('licName').textContent = d.playerName || '—';

    const typeMap = { none: t('ui.lic.typeNone'), provisional: t('ui.lic.typeProvisional'), full: t('ui.lic.typeFull'), suspended: t('ui.lic.typeSuspended') };
    document.getElementById('licType').textContent = typeMap[lic.licence_type] || lic.licence_type;
    document.getElementById('licIssueDate').textContent = lic.issue_date || '—';
    document.getElementById('licTheory').innerHTML   = lic.theory_passed    ? esc(t('ui.lic.passed')) : '<span style="color:#d4351c">' + esc(t('ui.lic.notPassed')) + '</span>';
    document.getElementById('licPractical').innerHTML= lic.practical_passed ? esc(t('ui.lic.passed')) : '<span style="color:#d4351c">' + esc(t('ui.lic.notPassed')) + '</span>';

    const statusMap = {
        none:        '<span class="dvla-badge-status dvla-badge-status--none">' + esc(t('ui.lic.statusNone')) + '</span>',
        provisional: '<span class="dvla-badge-status dvla-badge-status--provisional">' + esc(t('ui.lic.statusProvisional')) + '</span>',
        full:        '<span class="dvla-badge-status dvla-badge-status--full">' + esc(t('ui.lic.statusFull')) + '</span>',
        suspended:   '<span class="dvla-badge-status dvla-badge-status--suspended">' + esc(t('ui.lic.statusSuspended')) + '</span>',
    };
    document.getElementById('licStatus').innerHTML = statusMap[lic.licence_type] || lic.licence_type;
    document.getElementById('licPoints').textContent = t('ui.lic.pointsOf', lic.penalty_points || 0);
}

// ─── Penalty Points ───────────────────────────────────────────────────────────

function renderPenalty() {
    const d = State.playerData;
    const pts = d.licence ? (d.licence.penalty_points || 0) : 0;

    document.getElementById('pointsTotal').textContent = pts + ' / 12';

    const pct = Math.min((pts / 12) * 100, 100);
    const bar = document.getElementById('pointsBarFill');
    bar.style.width = pct + '%';
    bar.className = 'dvla-points-bar__fill';
    if (pts >= 9)  bar.classList.add('danger');
    if (pts >= 12) bar.classList.add('critical');

    const tbody = document.getElementById('penaltyTableBody');
    const penalties = d.penalties || [];

    if (penalties.length === 0) {
        tbody.innerHTML = `<tr class="govuk-table__row">
            <td class="govuk-table__cell dvla-empty" colspan="3">${esc(t('ui.pen.empty'))}</td>
        </tr>`;
        return;
    }

    tbody.innerHTML = penalties.map(p => `
        <tr class="govuk-table__row">
            <td class="govuk-table__cell">${esc(p.offence)}</td>
            <td class="govuk-table__cell"><strong>${p.points}</strong></td>
            <td class="govuk-table__cell">${esc(p.date)}</td>
        </tr>
    `).join('');
}

// ─── Test History ────────────────────────────────────────────────────────────

function renderHistory() {
    const d = State.playerData;

    // Theory history
    const tBody = document.getElementById('theoryHistoryBody');
    const theory = d.theoryTests || [];
    if (theory.length === 0) {
        tBody.innerHTML = `<tr class="govuk-table__row"><td class="govuk-table__cell dvla-empty" colspan="3">${esc(t('ui.hist.emptyTheory'))}</td></tr>`;
    } else {
        tBody.innerHTML = theory.map(r => `
            <tr class="govuk-table__row">
                <td class="govuk-table__cell">${r.score}/${r.max_score || 15}</td>
                <td class="govuk-table__cell">${r.passed ? '<span class="dvla-badge-pass">' + esc(t('ui.hist.pass')) + '</span>' : '<span class="dvla-badge-fail">' + esc(t('ui.hist.fail')) + '</span>'}</td>
                <td class="govuk-table__cell">${esc(r.date)}</td>
            </tr>
        `).join('');
    }

    // Practical history
    const pBody = document.getElementById('practicalHistoryBody');
    const pract = d.practicalTests || [];
    if (pract.length === 0) {
        pBody.innerHTML = `<tr class="govuk-table__row"><td class="govuk-table__cell dvla-empty" colspan="5">${esc(t('ui.hist.emptyPractical'))}</td></tr>`;
    } else {
        pBody.innerHTML = pract.map(p => `
            <tr class="govuk-table__row">
                <td class="govuk-table__cell">${esc(p.centre || '—')}</td>
                <td class="govuk-table__cell">${p.minor_faults}</td>
                <td class="govuk-table__cell">${p.major_faults}</td>
                <td class="govuk-table__cell">${p.passed ? '<span class="dvla-badge-pass">' + esc(t('ui.hist.pass')) + '</span>' : '<span class="dvla-badge-fail">' + esc(t('ui.hist.fail')) + '</span>'}</td>
                <td class="govuk-table__cell">${esc(p.date)}</td>
            </tr>
        `).join('');
    }
}

// ─── Theory Test Page ─────────────────────────────────────────────────────────

function renderTheoryPage() {
    const d = State.playerData;
    const passed = d.licence && d.licence.theory_passed;
    // Tests are booked and paid for on lsgov.co.uk (see Config.Booking)
    const needBooking = !passed && d.bookingRequired && !(d.bookings && d.bookings.theory > 0);
    document.getElementById('theoryAlreadyPassed').hidden = !passed;
    document.getElementById('theoryNeedBooking').hidden = !needBooking;
    document.getElementById('theoryCanTake').hidden = !!passed || needBooking;
    const bookText = document.getElementById('theoryBookText');
    if (bookText) bookText.innerHTML = t('ui.theory.bookBody', '<span id="theoryFee">£' + ((d.fees && d.fees.theory) || 0) + '</span>');
}

// ─── Practical Page ───────────────────────────────────────────────────────────

function renderPracticalPage() {
    const d   = State.playerData;
    const lic = d.licence;

    const needTheory = lic && !lic.theory_passed;

    // Parse held categories from JSON string e.g. '["B","AM"]'
    let held = [];
    try { held = JSON.parse((lic && lic.categories) || '[]'); } catch(e) { held = []; }

    // Always show the category picker if theory passed (can always add more categories)
    document.getElementById('practicalNeedTheory').hidden = !needTheory;
    document.getElementById('practicalCanBook').hidden    = needTheory;

    // Show held categories banner if any
    if (held.length > 0) {
        document.getElementById('practicalAlreadyPassed').hidden = false;
        const heldLine = document.getElementById('heldCategoriesLine');
        if (heldLine) heldLine.innerHTML = t('ui.prac.categoriesHeld', '<strong id="heldCategoriesDisplay">' + esc(held.join(' · ')) + '</strong>');
    } else {
        document.getElementById('practicalAlreadyPassed').hidden = true;
    }

    // Build category cards from server-provided categories list
    const cats = d.categories || [];
    const container = document.getElementById('categoryCards');
    if (!container) return;

    container.innerHTML = cats.map(cat => {
        const isHeld     = held.includes(cat.label);
        const reqsMet    = (cat.requires || []).every(r => held.includes(r));
        const booked     = !d.bookingRequired || !!(d.bookings && d.bookings.practical && d.bookings.practical[cat.label] > 0);
        const available  = !isHeld && reqsMet && booked;
        let statusBadge  = '';
        if (isHeld)       statusBadge = '<span class="dvla-badge-pass" style="font-size:0.75rem;">' + esc(t('ui.prac.held')) + '</span>';
        else if (!reqsMet) statusBadge = '<span style="color:#d4351c;font-size:0.75rem;">' + esc(t('ui.prac.requires', (cat.requires||[]).join(', '))) + '</span>';
        else if (!booked)  statusBadge = '<span style="color:#b45309;font-size:0.75rem;">' + esc(t('ui.prac.bookOnSite', (d.fees && d.fees.practical) || 0)) + '</span>';
        else if (d.bookingRequired) statusBadge = '<span class="dvla-badge-pass" style="font-size:0.75rem;">' + esc(t('ui.prac.booked')) + '</span>';

        return `<div class="dvla-category-card${available ? ' dvla-category-card--available' : ''}${isHeld ? ' dvla-category-card--held' : ''}"
                     data-category="${esc(cat.label)}"
                     data-available="${available}"
                     style="border:2px solid ${available ? '#00703c' : isHeld ? '#1d70b8' : '#b1b4b6'};
                            border-radius:4px;padding:1rem;cursor:${available ? 'pointer' : 'default'};
                            background:${available ? '#f3faf4' : isHeld ? '#f0f4ff' : '#f8f8f8'};">
                    <div style="font-size:2rem;margin-bottom:0.4rem;">${esc(cat.icon)}</div>
                    <div style="font-weight:700;font-size:1.1rem;">${esc(cat.label)} &mdash; ${esc(cat.name)}</div>
                    <div style="font-size:0.85rem;color:#505a5f;margin:0.3rem 0 0.5rem;">${esc(cat.description)}</div>
                    ${statusBadge}
                </div>`;
    }).join('');

    // Category card click to select
    let selectedCategory = null;
    container.querySelectorAll('[data-available="true"]').forEach(card => {
        card.addEventListener('click', () => {
            container.querySelectorAll('.dvla-category-card').forEach(c => c.style.outline = '');
            card.style.outline = '3px solid #00703c';
            selectedCategory = card.dataset.category;
            const btn = document.getElementById('btnBookPractical');
            if (btn) {
                btn.disabled = false;
                btn.textContent = card.querySelector('[style*="font-size:2rem"]').textContent
                    + ' ' + t('ui.prac.beginCat', card.dataset.category);
            }
        });
    });

    // Store selected for the button handler to read
    container._getSelected = () => selectedCategory;
}

// (examiner queue removed — AI examiner used instead)

// ─── Theory Test Logic ────────────────────────────────────────────────────────

function startTheoryTest() {
    // Shuffle and pick questions
    const pool = [...THEORY_QUESTIONS].sort(() => Math.random() - 0.5).slice(0, TOTAL_QUESTIONS);
    State.testQuestions = pool;
    State.testAnswers   = new Array(pool.length).fill(null);
    State.currentQ      = 0;
    State.timeLeft      = TIME_LIMIT;

    showSection('section-theory-test');
    renderQuestion();
    startTimer();
}

function renderQuestion() {
    const q   = State.testQuestions[State.currentQ];
    const idx = State.currentQ;
    const total = State.testQuestions.length;

    document.getElementById('qProgress').textContent = t('ui.test.questionOf', idx + 1, total);
    document.getElementById('testProgress').style.width = ((idx + 1) / total * 100) + '%';
    document.getElementById('questionText').textContent = q.question;

    const letters = ['A', 'B', 'C', 'D'];
    const container = document.getElementById('answersContainer');
    container.innerHTML = q.answers.map((ans, i) => `
        <div class="dvla-answer ${State.testAnswers[idx] === i ? 'selected' : ''}"
             onclick="selectAnswer(${i})">
            <span class="dvla-answer__letter">${letters[i]}</span>
            <span>${esc(ans)}</span>
        </div>
    `).join('');

    // Nav buttons
    document.getElementById('btnPrevQ').disabled = idx === 0;
    const isLast = idx === total - 1;
    document.getElementById('btnNextQ').hidden     = isLast;
    document.getElementById('btnSubmitTest').hidden = !isLast;
}

function selectAnswer(answerIndex) {
    State.testAnswers[State.currentQ] = answerIndex;
    renderQuestion();
}

function startTimer() {
    clearInterval(State.timerInterval);
    updateTimerDisplay();
    State.timerInterval = setInterval(() => {
        State.timeLeft--;
        updateTimerDisplay();
        if (State.timeLeft <= 0) {
            clearInterval(State.timerInterval);
            submitTest();
        }
    }, 1000);
}

function updateTimerDisplay() {
    const m = Math.floor(State.timeLeft / 60);
    const s = State.timeLeft % 60;
    const display = `${m}:${String(s).padStart(2, '0')}`;
    const el = document.getElementById('testTimer');
    el.textContent = display;
    el.className = 'dvla-test-timer' + (State.timeLeft <= 60 ? ' timer-warning' : '');
}

function submitTest() {
    clearInterval(State.timerInterval);

    let score = 0;
    State.testQuestions.forEach((q, i) => {
        // correct is 1-based in config
        if (State.testAnswers[i] === (q.correct - 1)) score++;
    });

    const passed = score >= PASS_MARK;

    nuiFetch('submitTheoryTest', { score, passed }).then(result => {
        if (result && result.success === false) {
            document.getElementById('theoryResultBox').innerHTML = `
                <div class="dvla-result-fail">
                    <div class="dvla-result__heading">&#10005; ${esc(t('ui.result.notRecorded'))}</div>
                    <div class="dvla-result__sub">${esc(result.reason || t('ui.result.notRecordedSub'))}</div>
                </div>`;
            showSection('section-theory-result');
            return;
        }
        if (result && result.success) {
            // Update local state
            State.playerData.theoryTests   = result.theoryTests || State.playerData.theoryTests;
            State.playerData.licence       = result.licence     || State.playerData.licence;
            renderStatusCards();
            renderLicence();
            renderHistory();
            renderTheoryPage();
        }

        // Show result
        const box = document.getElementById('theoryResultBox');
        if (passed) {
            box.innerHTML = `
                <div class="dvla-result-pass">
                    <div class="dvla-result__heading">&#10003; ${esc(t('ui.result.passed'))}</div>
                    <div class="dvla-result__score">${score} / ${TOTAL_QUESTIONS}</div>
                    <div class="dvla-result__sub">${esc(t('ui.result.passedSub', PASS_MARK))}</div>
                </div>`;
        } else {
            box.innerHTML = `
                <div class="dvla-result-fail">
                    <div class="dvla-result__heading">&#10005; ${esc(t('ui.result.failed'))}</div>
                    <div class="dvla-result__score">${score} / ${TOTAL_QUESTIONS}</div>
                    <div class="dvla-result__sub">${esc(t('ui.result.failedSub', PASS_MARK))}</div>
                </div>`;
        }
        showSection('section-theory-result');
    });
}

// (examiner practical modal removed — AI examiner used instead)

// ─── Event Listeners ─────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {

    // Language: fetch the dictionary from the client script and translate the static text
    loadLocale(() => {
        applyI18nHtml();
        if (State.playerData) renderAll();
    });

    // Close button
    document.getElementById('btnClose').addEventListener('click', () => {
        document.getElementById('app').classList.remove('ui-open');
        clearInterval(State.timerInterval);
        nuiFetch('closeUI');
    });

    // ESC key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            document.getElementById('app').classList.remove('ui-open');
            clearInterval(State.timerInterval);
            nuiFetch('closeUI');
        }
    });

    // Navigation links (back links + nav bar)
    document.addEventListener('click', (e) => {
        const link = e.target.closest('[data-section]');
        if (!link) return;
        e.preventDefault();
        const target = link.dataset.section;
        if (target) showSection(target);
    });

    // Service cards
    document.querySelectorAll('.dvla-service-card').forEach(card => {
        card.addEventListener('click', () => {
            const target = card.dataset.section;
            if (target) showSection(target);
        });
    });

    // Start theory test
    document.getElementById('btnStartTheory').addEventListener('click', () => {
        startTheoryTest();
    });

    // Theory nav
    document.getElementById('btnNextQ').addEventListener('click', () => {
        if (State.currentQ < State.testQuestions.length - 1) {
            State.currentQ++;
            renderQuestion();
        }
    });
    document.getElementById('btnPrevQ').addEventListener('click', () => {
        if (State.currentQ > 0) {
            State.currentQ--;
            renderQuestion();
        }
    });
    document.getElementById('btnSubmitTest').addEventListener('click', () => {
        const unanswered = State.testAnswers.filter(a => a === null).length;
        if (unanswered > 0) {
            if (!confirm(t('ui.test.unanswered', unanswered))) return;
        }
        submitTest();
    });

    // Start AI Practical Test — passes selected category to Lua
    document.getElementById('btnBookPractical').addEventListener('click', () => {
        const container = document.getElementById('categoryCards');
        const category  = container && container._getSelected ? container._getSelected() : 'B';
        if (!category) {
            const el = document.getElementById('practicalError');
            document.getElementById('practicalErrorMsg').textContent = t('ui.prac.pickFirst');
            el.hidden = false;
            return;
        }
        document.getElementById('btnBookPractical').disabled = true;
        nuiFetch('startAIPractical', { category }).then(() => {
            document.getElementById('btnBookPractical').disabled = false;
        });
    });

    // Replace Licence
    document.getElementById('btnReplaceLicence').addEventListener('click', () => {
        const btn    = document.getElementById('btnReplaceLicence');
        const errBox = document.getElementById('replaceError');
        errBox.hidden = true;
        btn.disabled = true;
        btn.textContent = t('ui.replace.processing');

        nuiFetch('replaceLicence').then(result => {
            if (result && result.success) {
                document.getElementById('replaceSuccess').hidden = false;
                document.getElementById('replaceCanApply').querySelector('table').hidden = true;
                btn.hidden = true;
            } else {
                document.getElementById('replaceErrorMsg').textContent = (result && result.reason) || t('ui.replace.failed');
                errBox.hidden = false;
                btn.disabled = false;
                btn.textContent = t('ui.replace.applyBtn', (State.playerData.fees && State.playerData.fees.replace) || 20);
            }
        });
    });
});

// ─── Replace Licence Page ─────────────────────────────────────────────────────

function renderReplacePage() {
    const d   = State.playerData;
    const lic = d && d.licence;

    const noLicence    = document.getElementById('replaceNoLicence');
    const alreadyHave  = document.getElementById('replaceAlreadyHave');
    const canApply     = document.getElementById('replaceCanApply');
    const successBox   = document.getElementById('replaceSuccess');
    const btn          = document.getElementById('btnReplaceLicence');

    // Reset
    noLicence.hidden   = true;
    alreadyHave.hidden = true;
    canApply.hidden    = true;
    successBox.hidden  = true;
    if (btn) btn.disabled = false;

    // No licence on record at all
    if (!lic || lic.practical_passed === 0) {
        noLicence.hidden = false;
        return;
    }

    // Has a valid licence — populate detail table
    const cats = lic.categories ? lic.categories.replace(/["\[\]]/g, '').replace(/,/g, ' · ') : '—';
    document.getElementById('replaceName').textContent      = d.playerName || '—';
    document.getElementById('replaceLicType').textContent   = lic.licence_type || '—';
    document.getElementById('replaceCategories').textContent = cats;
    document.getElementById('replaceIssueDate').textContent = lic.issue_date || '—';

    const replaceFee = (d.fees && d.fees.replace) || 20;
    document.getElementById('replaceFeeHeading').textContent = t('ui.replace.feeHeading', replaceFee);
    if (btn) btn.textContent = t('ui.replace.applyBtn', replaceFee);
    canApply.hidden = false;
}

// ─── Utilities ───────────────────────────────────────────────────────────────

function esc(str) {
    if (str === null || str === undefined) return '—';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}


// Driving licence card. Opened by the client script when the driver_license item is used.
function initLicenceCard() {
    var root = document.getElementById('licCardRoot');
    if (!root) return;
    var current = null;
    function months() { return t('meta.months').split(','); }

    function $(id) { return document.getElementById(id); }
    function pad(n) { return (n < 10 ? '0' : '') + n; }

    // Accepts 2001-04-23, 23/04/2001 or plain text. Returns text like "23 Apr 2001".
    function dateText(s) {
        s = String(s || '').trim();
        if (!s) return '-';
        var a = /^(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})/.exec(s);
        if (a) return pad(+a[3]) + ' ' + months()[+a[2] - 1] + ' ' + a[1];
        var b = /^(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4})/.exec(s);
        if (b) return pad(+b[1]) + ' ' + months()[+b[2] - 1] + ' ' + b[3];
        return s;
    }

    function silhouette() {
        return '<svg viewBox="0 0 100 100"><circle cx="50" cy="34" r="20" fill="#000"/><path d="M10 100c0-26 18-38 40-38s40 12 40 38z" fill="#000"/></svg>';
    }

    function show(msg, again) {
        if (!again) ensureLocale(function () { if (current) show(msg, true); });
        var c = msg.card;
        current = c;
        var bad = c.status === 'suspended' || c.status === 'expired';
        $('lcCard').className = 'lc-card' + (bad ? ' bad' : '');
        $('lcStamp').textContent = c.status === 'expired' ? t('card.expired') : t('card.suspended');
        var st = $('lcStatus');
        st.className = 'lc-status ' + (c.status === 'provisional' ? 'provisional' : 'valid');
        st.textContent = c.status === 'provisional' ? t('card.provisional') : t('card.valid');

        $('lcLast').textContent = (c.last || '').toUpperCase();
        $('lcFirst').textContent = (c.first || '').toUpperCase();
        $('lcDob').textContent = dateText(c.dob);
        $('lcSexNat').textContent = (c.sex || '-') + ' / ' + String(c.nationality || '').toUpperCase();
        $('lcIssued').textContent = dateText(c.issued);
        $('lcExpires').textContent = c.expires ? dateText(c.expires) : t('card.noExpiry');
        $('lcAuth').textContent = c.authority || '';
        $('lcNumber').textContent = c.number || '';

        var chips = $('lcChips');
        chips.innerHTML = '';
        var cats = c.categories || [];
        if (!cats.length) {
            var none = document.createElement('span');
            none.className = 'lc-chip none';
            none.textContent = c.status === 'provisional' ? t('card.provisionalNoCats') : t('card.none');
            chips.appendChild(none);
        } else {
            cats.forEach(function (label) {
                var chip = document.createElement('span');
                chip.className = 'lc-chip';
                chip.textContent = label;
                chips.appendChild(chip);
            });
        }

        var ph = $('lcPhoto');
        if (c.photo) { ph.style.backgroundImage = 'url("' + String(c.photo).replace(/"/g, '') + '")'; ph.innerHTML = ''; }
        else { ph.style.backgroundImage = ''; ph.innerHTML = silhouette(); }

        $('lcFrom').textContent = msg.from ? t('card.shownBy', msg.from) : '';
        $('lcShow').style.display = msg.own && !bad ? '' : 'none';
        root.className = 'on';
        root.style.display = 'flex';
    }

    function post(name, data) {
        try {
            var res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'as-drivingschool';
            fetch('https://' + res + '/' + name, {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}),
            }).catch(function () {});
        } catch (e) {}
    }
    function hide() { root.className = ''; root.style.display = 'none'; current = null; }
    function closeAndTell() { hide(); post('closeCard'); }

    window.addEventListener('message', function (e) {
        var m = e.data || {};
        if (m.action === 'openCard' && m.card) show(m);
        else if (m.action === 'closeCard') hide();
    });
    document.addEventListener('keydown', function (e) {
        if (root.style.display === 'flex' && (e.key === 'Escape' || e.key === 'Backspace')) closeAndTell();
    });
    $('lcClose').onclick = closeAndTell;
    $('lcShow').onclick = function () { if (current) post('showCardNearby'); };
    root.addEventListener('mousedown', function (e) { if (e.target === root) closeAndTell(); });
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initLicenceCard);
else initLicenceCard();
