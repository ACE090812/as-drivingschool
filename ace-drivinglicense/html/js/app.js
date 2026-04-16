/* ──────────────────────────────────────────────────────────────────────────────
   DVLA Portal — Frontend Application
────────────────────────────────────────────────────────────────────────────── */

'use strict';

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
    return fetch(`https://dvla/${event}`, {
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

    document.getElementById('playerName').textContent = d.playerName || '—';

    renderStatusCards();
    renderLicence();
    renderPenalty();
    renderHistory();
    renderTheoryPage();
    renderPracticalPage();
    renderMOTPage();
    renderReplacePage();
}

// ─── Status Cards ─────────────────────────────────────────────────────────────

function renderStatusCards() {
    const lic = State.playerData.licence;

    const licType = lic ? lic.licence_type : 'none';
    const labels = { none: 'No Licence', provisional: 'Provisional', full: 'Full Licence', suspended: 'Suspended' };
    document.getElementById('statusLicence').textContent = labels[licType] || licType;

    const pts = lic ? (lic.penalty_points || 0) : 0;
    document.getElementById('statusPoints').textContent = pts + ' / 12';

    const theoryPassed = lic && lic.theory_passed;
    document.getElementById('statusTheory').textContent = theoryPassed ? '✓ Passed' : '✗ Not Passed';

    const practPassed = lic && lic.practical_passed;
    document.getElementById('statusPractical').textContent = practPassed ? '✓ Passed' : '✗ Not Passed';
}

// ─── My Licence ──────────────────────────────────────────────────────────────

function renderLicence() {
    const d = State.playerData;
    const lic = d.licence;

    document.getElementById('licName').textContent = d.playerName || '—';

    const typeMap = { none: 'No Licence', provisional: 'Provisional Licence', full: 'Full Licence', suspended: 'Suspended' };
    document.getElementById('licType').textContent = typeMap[lic.licence_type] || lic.licence_type;
    document.getElementById('licIssueDate').textContent = lic.issue_date || '—';
    document.getElementById('licTheory').innerHTML   = lic.theory_passed    ? 'Passed ✓' : '<span style="color:#d4351c">Not Passed</span>';
    document.getElementById('licPractical').innerHTML= lic.practical_passed ? 'Passed ✓' : '<span style="color:#d4351c">Not Passed</span>';

    const statusMap = {
        none:        '<span class="dvla-badge-status dvla-badge-status--none">NO LICENCE</span>',
        provisional: '<span class="dvla-badge-status dvla-badge-status--provisional">VALID — PROVISIONAL</span>',
        full:        '<span class="dvla-badge-status dvla-badge-status--full">VALID — FULL</span>',
        suspended:   '<span class="dvla-badge-status dvla-badge-status--suspended">DISQUALIFIED</span>',
    };
    document.getElementById('licStatus').innerHTML = statusMap[lic.licence_type] || lic.licence_type;
    document.getElementById('licPoints').textContent = (lic.penalty_points || 0) + ' / 12 points';
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
            <td class="govuk-table__cell dvla-empty" colspan="3">No endorsements on record.</td>
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
        tBody.innerHTML = `<tr class="govuk-table__row"><td class="govuk-table__cell dvla-empty" colspan="3">No theory test records.</td></tr>`;
    } else {
        tBody.innerHTML = theory.map(t => `
            <tr class="govuk-table__row">
                <td class="govuk-table__cell">${t.score}/${t.max_score || 15}</td>
                <td class="govuk-table__cell">${t.passed ? '<span class="dvla-badge-pass">PASS</span>' : '<span class="dvla-badge-fail">FAIL</span>'}</td>
                <td class="govuk-table__cell">${esc(t.date)}</td>
            </tr>
        `).join('');
    }

    // Practical history
    const pBody = document.getElementById('practicalHistoryBody');
    const pract = d.practicalTests || [];
    if (pract.length === 0) {
        pBody.innerHTML = `<tr class="govuk-table__row"><td class="govuk-table__cell dvla-empty" colspan="5">No practical test records.</td></tr>`;
    } else {
        pBody.innerHTML = pract.map(p => `
            <tr class="govuk-table__row">
                <td class="govuk-table__cell">${esc(p.centre || '—')}</td>
                <td class="govuk-table__cell">${p.minor_faults}</td>
                <td class="govuk-table__cell">${p.major_faults}</td>
                <td class="govuk-table__cell">${p.passed ? '<span class="dvla-badge-pass">PASS</span>' : '<span class="dvla-badge-fail">FAIL</span>'}</td>
                <td class="govuk-table__cell">${esc(p.date)}</td>
            </tr>
        `).join('');
    }
}

// ─── Theory Test Page ─────────────────────────────────────────────────────────

function renderTheoryPage() {
    const d = State.playerData;
    const passed = d.licence && d.licence.theory_passed;
    document.getElementById('theoryAlreadyPassed').hidden = !passed;
    document.getElementById('theoryCanTake').hidden = !!passed;
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
    const heldDisplay = document.getElementById('heldCategoriesDisplay');
    if (held.length > 0) {
        document.getElementById('practicalAlreadyPassed').hidden = false;
        if (heldDisplay) heldDisplay.textContent = held.join(' · ');
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
        const available  = !isHeld && reqsMet;
        let statusBadge  = '';
        if (isHeld)       statusBadge = '<span class="dvla-badge-pass" style="font-size:0.75rem;">HELD ✓</span>';
        else if (!reqsMet) statusBadge = '<span style="color:#d4351c;font-size:0.75rem;">Requires: ' + (cat.requires||[]).join(', ') + '</span>';

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
                    + ' Begin ' + card.dataset.category + ' Test';
            }
        });
    });

    // Store selected for the button handler to read
    container._getSelected = () => selectedCategory;
}

// (examiner queue removed — AI examiner used instead)

// ─── MOT Page ─────────────────────────────────────────────────────────────────

function renderMOTPage() {
    const d = State.playerData;
    const inspectorTerminal = document.getElementById('motInspectorTerminal');
    inspectorTerminal.hidden = !d.isMOTInspector;
    if (d.isMOTInspector) renderMOTQueue(d.pendingMOT || []);
}

function renderMOTQueue(queue) {
    const container = document.getElementById('motQueue');
    if (!queue || queue.length === 0) {
        container.innerHTML = `<p class="govuk-body dvla-empty">No vehicles pending inspection.</p>`;
        return;
    }
    container.innerHTML = queue.map(item => `
        <div class="dvla-queue-item">
            <div class="dvla-queue-item__info">
                <div class="dvla-queue-item__plate">${esc(item.plate)}</div>
                <div class="dvla-queue-item__sub">Owner: ${esc(item.name)}</div>
            </div>
            <button class="dvla-inspect-btn" onclick="openMOTModal('${esc(item.citizenid)}', '${esc(item.plate)}', '${esc(item.name)}')">
                &#128295; Inspect
            </button>
        </div>
    `).join('');
}

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

    document.getElementById('qCurrent').textContent = idx + 1;
    document.getElementById('qTotal').textContent   = total;
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
                    <div class="dvla-result__heading">&#10003; Theory Test Passed</div>
                    <div class="dvla-result__score">${score} / ${TOTAL_QUESTIONS}</div>
                    <div class="dvla-result__sub">Pass mark: ${PASS_MARK} — Congratulations!</div>
                </div>`;
        } else {
            box.innerHTML = `
                <div class="dvla-result-fail">
                    <div class="dvla-result__heading">&#10005; Theory Test Failed</div>
                    <div class="dvla-result__score">${score} / ${TOTAL_QUESTIONS}</div>
                    <div class="dvla-result__sub">Pass mark: ${PASS_MARK} — Please try again.</div>
                </div>`;
        }
        showSection('section-theory-result');
    });
}

// ─── MOT Modal ────────────────────────────────────────────────────────────────

window.openMOTModal = function(citizenid, plate, ownerName) {
    document.getElementById('motInspectCitizenId').value   = citizenid;
    document.getElementById('motInspectPlate').textContent = plate;
    document.getElementById('motInspectOwner').textContent = ownerName;
    document.getElementById('motNotes').value              = '';
    document.getElementById('modalMOT').hidden             = false;
};

function closeMOTModal() {
    document.getElementById('modalMOT').hidden = true;
}

function completeMOT(passed) {
    const citizenid = document.getElementById('motInspectCitizenId').value;
    const plate     = document.getElementById('motInspectPlate').textContent;
    const notes     = document.getElementById('motNotes').value.trim();
    closeMOTModal();

    nuiFetch('completeMOT', { citizenid, plate, passed, notes }).then(result => {
        if (result && result.success) {
            State.playerData.pendingMOT = result.pendingMOT || [];
            renderMOTQueue(State.playerData.pendingMOT);
        }
    });
}

// (examiner practical modal removed — AI examiner used instead)

// ─── Event Listeners ─────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {

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
            if (!confirm(`You have ${unanswered} unanswered question(s). Submit anyway?`)) return;
        }
        submitTest();
    });

    // Start AI Practical Test — passes selected category to Lua
    document.getElementById('btnBookPractical').addEventListener('click', () => {
        const container = document.getElementById('categoryCards');
        const category  = container && container._getSelected ? container._getSelected() : 'B';
        if (!category) {
            const el = document.getElementById('practicalError');
            document.getElementById('practicalErrorMsg').textContent = 'Please select a licence category first.';
            el.hidden = false;
            return;
        }
        document.getElementById('btnBookPractical').disabled = true;
        nuiFetch('startAIPractical', { category }).then(() => {
            document.getElementById('btnBookPractical').disabled = false;
        });
    });

    // Get current vehicle plate
    document.getElementById('btnGetPlate').addEventListener('click', () => {
        nuiFetch('getVehiclePlate').then(result => {
            if (result && result.plate) {
                document.getElementById('motBookError').hidden = true;
                document.getElementById('motPlate').value = result.plate;
            } else {
                document.getElementById('motBookErrorMsg').textContent = 'No vehicle detected. Please enter your plate manually.';
                document.getElementById('motBookError').hidden = false;
            }
        });
    });

    // Book MOT
    document.getElementById('btnBookMOT').addEventListener('click', () => {
        const plate = document.getElementById('motPlate').value.trim().toUpperCase();
        if (!plate) {
            document.getElementById('motBookErrorMsg').textContent = 'Please enter a vehicle plate.';
            document.getElementById('motBookError').hidden = false;
            return;
        }
        document.getElementById('motBookError').hidden = true;
        document.getElementById('btnBookMOT').disabled = true;
        nuiFetch('bookMOT', { plate }).then(result => {
            if (result && result.success) {
                document.getElementById('motBookedPlate').textContent   = plate;
                document.getElementById('motBookedNotice').hidden       = false;
                document.getElementById('motBookForm').hidden           = true;
                State.playerData.pendingMOT = result.pendingMOT || State.playerData.pendingMOT;
                if (State.playerData.isMOTInspector) renderMOTQueue(State.playerData.pendingMOT);
            } else {
                document.getElementById('motBookErrorMsg').textContent = result.reason || 'Unable to book MOT.';
                document.getElementById('motBookError').hidden = false;
                document.getElementById('btnBookMOT').disabled = false;
            }
        });
    });

    // MOT inspector refresh
    document.getElementById('btnRefreshMOT').addEventListener('click', () => {
        nuiFetch('getPendingMOT').then(queue => {
            State.playerData.pendingMOT = queue || [];
            renderMOTQueue(State.playerData.pendingMOT);
        });
    });

    // MOT modal
    document.getElementById('btnMOTPass').addEventListener('click',   () => completeMOT(true));
    document.getElementById('btnMOTFail').addEventListener('click',   () => completeMOT(false));
    document.getElementById('btnMOTCancel').addEventListener('click', () => closeMOTModal());

    // Plate input — auto uppercase
    document.getElementById('motPlate').addEventListener('input', function() {
        this.value = this.value.toUpperCase();
        document.getElementById('motBookError').hidden = true;
    });

    // Replace Licence
    document.getElementById('btnReplaceLicence').addEventListener('click', () => {
        const btn    = document.getElementById('btnReplaceLicence');
        const errBox = document.getElementById('replaceError');
        errBox.hidden = true;
        btn.disabled = true;
        btn.textContent = 'Processing…';

        nuiFetch('replaceLicence').then(result => {
            if (result && result.success) {
                document.getElementById('replaceSuccess').hidden = false;
                document.getElementById('replaceCanApply').querySelector('table').hidden = true;
                btn.hidden = true;
            } else {
                document.getElementById('replaceErrorMsg').textContent = result.reason || 'Unable to process replacement. Please try again.';
                errBox.hidden = false;
                btn.disabled = false;
                btn.textContent = '🔄 Apply for Replacement — £20';
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
