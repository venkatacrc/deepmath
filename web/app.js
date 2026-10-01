'use strict';

const $ = (sel) => document.querySelector(sel);

function h(tag, attrs = {}, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'html') { el.innerHTML = v; continue; }
        else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
        else if (typeof v === 'boolean') el[k] = v;
        else el.setAttribute(k, v);
    }
    for (const c of children.flat()) {
        if (c == null || c === false) continue;
        el.append(c instanceof Node ? c : String(c));
    }
    return el;
}

function esc(s) {
    return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

function tex(src, display) {
    return katex.renderToString(src, { displayMode: !!display, throwOnError: false });
}

// Prose may contain $inline math$, `code` and *emphasis*.
function prose(text) {
    if (!text) return '';
    return text.split(/(\$[^$]+\$|`[^`]+`)/).map((part) => {
        if (part.length > 1 && part[0] === '$' && part.endsWith('$')) return tex(part.slice(1, -1), false);
        if (part.length > 1 && part[0] === '`' && part.endsWith('`')) return `<code>${esc(part.slice(1, -1))}</code>`;
        return esc(part).replace(/\*([^*\s][^*]*)\*/g, '<em>$1</em>');
    }).join('');
}

function section(title, body) {
    return body ? `<section><h3>${title}</h3>${body}</section>` : '';
}

function termsTable(terms) {
    if (!terms?.length) return '';
    const rows = terms.map((t) => `<tr><td class="sym">${tex(t.tex, false)}</td><td>${prose(t.text)}</td></tr>`);
    return `<table class="terms">${rows.join('')}</table>`;
}

function details(card) {
    return [
        section('Read aloud', card.read ? `<p class="read">“${prose(card.read)}”</p>` : ''),
        section('Meaning', card.meaning ? `<p>${prose(card.meaning)}</p>` : ''),
        section('Term by term', termsTable(card.terms)),
        section('Example', card.example ? `<div class="formula example">${tex(card.example, true)}</div>` : ''),
        section('In modern AI', card.ai ? `<p>${prose(card.ai)}</p>` : ''),
        card.cite ? `<p class="cite">Source: ${prose(card.cite)}</p>` : '',
    ].join('');
}

// Long equations shrink until they fit the card width, down to 55% of the base size.
function fitFormulas(root) {
    for (const el of root.querySelectorAll('.formula')) {
        el.style.fontSize = '';
        const base = parseFloat(getComputedStyle(el).fontSize);
        let size = base;
        while (el.scrollWidth > el.clientWidth + 1 && size > base * 0.55) {
            size *= 0.92;
            el.style.fontSize = size + 'px';
        }
    }
}

// ---- Saved state (localStorage) ----

const saved = {
    get(key, fallback) {
        try {
            const v = localStorage.getItem('deepMath.' + key);
            return v == null ? fallback : JSON.parse(v);
        } catch {
            return fallback;
        }
    },
    set(key, value) {
        localStorage.setItem('deepMath.' + key, JSON.stringify(value));
    },
};

const prefs = {
    selected: saved.get('selected', '*'),
    excludedLevels: saved.get('excludedLevels', []),
    kind: saved.get('kind', 'both'),
    study: saved.get('study', 'learn'),
    practice: saved.get('practice', 'all'),
    direction: saved.get('direction', 'symbol'),
    shuffle: saved.get('shuffle', false),
    collapsed: saved.get('collapsed', []),
    installDismissed: saved.get('installDismissed', false),
};

function setPref(key, value) {
    prefs[key] = value;
    saved.set(key, value);
}

const progress = {
    known: new Set(saved.get('known', [])),
    review: new Set(saved.get('review', [])),
    save() {
        saved.set('known', [...this.known]);
        saved.set('review', [...this.review]);
    },
    markKnown(id) { this.known.add(id); this.review.delete(id); this.save(); },
    markReview(id) { this.review.add(id); this.known.delete(id); this.save(); },
    toggleKnown(id) { this.known.has(id) ? this.known.delete(id) : this.markKnown(id); this.save(); },
    toggleReview(id) { this.review.has(id) ? this.review.delete(id) : this.markReview(id); this.save(); },
};

let deck = null;
let loadError = null;
let deferredInstall = null;

const session = { order: [], position: 0, flipped: false, answers: {}, finished: false };

// ---- Deck helpers ----

const groupKey = (src, group) => `${src}|${group}`;

function allGroupKeys() {
    return deck.sources.flatMap((s) => s.groups.map((g) => groupKey(s.id, g.id)));
}

function selectedSet() {
    return new Set(prefs.selected === '*' ? allGroupKeys() : prefs.selected);
}

function setSelected(set) {
    const all = allGroupKeys();
    setPref('selected', all.every((k) => set.has(k)) ? '*' : [...set].sort());
}

function kindIncludes(card) {
    if (prefs.kind === 'notation') return card.kind !== 'equation';
    if (prefs.kind === 'equations') return card.kind === 'equation';
    return true;
}

function selectedCards() {
    const groups = selectedSet();
    const excluded = new Set(prefs.excludedLevels);
    return deck.cards.filter((c) => kindIncludes(c) && groups.has(groupKey(c.src, c.group)) && !excluded.has(c.level));
}

function levelLabel(level) {
    return deck.levels.find((l) => l.id === level)?.label ?? `Level ${level}`;
}

function sourceOf(card) {
    return deck.sources.find((s) => s.id === card.src);
}

function contextOf(card) {
    const source = sourceOf(card);
    if (!source) return card.src;
    const group = source.groups.find((g) => g.id === card.group)?.label ?? card.group;
    return `${source.title} · ${group}`;
}

function cardAt(index) {
    return deck.cards[index];
}

function cardId(index) {
    return deck.cards[index].id;
}

function currentIndex() {
    const i = session.order[session.position];
    return i != null && i < deck.cards.length ? i : null;
}

function shuffled(list) {
    const a = [...list];
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
}

function noun() {
    if (prefs.kind === 'notation') return 'notation cards';
    if (prefs.kind === 'equations') return 'equation cards';
    return 'cards';
}

// ---- Session ----

function rebuild() {
    const ids = new Map(deck.cards.map((c, i) => [c.id, i]));
    let picked = selectedCards().map((c) => ids.get(c.id));
    if (prefs.practice === 'notKnown') picked = picked.filter((i) => !progress.known.has(cardId(i)));
    if (prefs.practice === 'review') picked = picked.filter((i) => progress.review.has(cardId(i)));
    startSession(prefs.shuffle ? shuffled(picked) : picked);
}

function startSession(order) {
    Object.assign(session, { order, position: 0, flipped: false, answers: {}, finished: false });
    render();
}

function move(delta) {
    const n = session.order.length;
    if (!n) return;
    session.position = (session.position + delta + n) % n;
    session.flipped = false;
    stopSpeak();
    render();
}

function reveal() {
    if (prefs.study !== 'test' || session.flipped) return;
    session.flipped = true;
    render();
}

function answer(correct) {
    const index = currentIndex();
    if (index == null || !session.flipped) return;
    const id = cardId(index);
    session.answers[id] = correct;
    correct ? progress.markKnown(id) : progress.markReview(id);
    const n = session.order.length;
    for (let step = 1; step <= n; step++) {
        const p = (session.position + step) % n;
        if (!(cardId(session.order[p]) in session.answers)) {
            session.position = p;
            session.flipped = false;
            render();
            return;
        }
    }
    session.finished = true;
    render();
}

// ---- Speech ----

function stopSpeak() {
    if (window.speechSynthesis) speechSynthesis.cancel();
}

function speak(text) {
    if (!window.speechSynthesis || !text) return;
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'en-US';
    u.rate = 0.95;
    speechSynthesis.speak(u);
}

// ---- Rendering ----

function render() {
    renderSwitches();
    renderStatus();
    renderStage();
    renderActions();
    renderSpeakButton();
    if ($('#drawer').classList.contains('open')) renderDrawer();
}

function renderSwitches() {
    for (const [id, value] of [['#kind-switch', prefs.kind], ['#study-switch', prefs.study]]) {
        for (const b of $(id).querySelectorAll('button')) b.classList.toggle('on', b.dataset.value === value);
    }
}

function renderStatus() {
    const el = $('#status');
    el.replaceChildren();
    if (!deck || !session.order.length || (prefs.study === 'test' && session.finished)) return;
    const n = session.order.length;
    el.append(h('span', {}, h('strong', {}, `Card ${session.position + 1}`), ` of ${n}`));
    if (prefs.study === 'test') {
        const answered = Object.keys(session.answers).length;
        const correct = Object.values(session.answers).filter(Boolean).length;
        el.append(h('span', {}, `Score ${correct} of ${answered} · ${n - answered} to go`));
    } else {
        let known = 0, review = 0;
        for (const i of session.order) {
            const id = cardId(i);
            if (progress.known.has(id)) known++;
            if (progress.review.has(id)) review++;
        }
        el.append(h('span', {}, `Known ${known} · Review ${review}`));
    }
}

function renderSpeakButton() {
    const btn = $('#speak-btn');
    const index = deck ? currentIndex() : null;
    const flipped = prefs.study === 'learn' || session.flipped;
    const show = index != null && flipped && !(prefs.study === 'test' && session.finished);
    btn.hidden = !show;
}

function renderStage() {
    const stage = $('#stage');
    stage.replaceChildren();
    if (loadError) {
        stage.append(h('div', { class: 'empty' }, h('h2', {}, 'Could not load the cards'), h('p', {}, loadError)));
        return;
    }
    if (!deck) {
        stage.append(h('div', { class: 'empty' }, 'Loading cards…'));
        return;
    }
    if (prefs.study === 'test' && session.finished) {
        stage.append(testSummary());
        return;
    }
    const index = currentIndex();
    if (index == null) {
        stage.append(h('div', { class: 'empty' },
            h('div', { class: 'big' }, '∇'),
            h('h2', {}, 'No cards to practice'),
            h('p', {}, emptyHint()),
            h('button', { class: 'btn primary', onclick: openDrawer }, 'Choose topics')));
        return;
    }
    const flipped = prefs.study === 'learn' || session.flipped;
    const card = mathCard(cardAt(index), flipped);
    card.addEventListener('click', (e) => { if (!e.target.closest('button, a')) reveal(); });
    addSwipe(card);
    stage.append(card);
    fitFormulas(card);
    document.fonts.ready.then(() => fitFormulas(card));
}

function emptyHint() {
    if (prefs.practice === 'review') return 'No cards are marked for review in the selected topics.';
    if (prefs.practice === 'notKnown') return 'Every card in the selected topics is marked known.';
    return 'Tick at least one level and one topic.';
}

function mathCard(c, flipped) {
    const badges = h('div', { class: 'badges' },
        h('span', { class: 'badge' }, c.kind === 'equation' ? 'Equation' : 'Notation'),
        h('span', { class: 'context' }, contextOf(c)),
        progress.known.has(c.id) && h('span', { class: 'badge known' }, 'Known'),
        progress.review.has(c.id) && h('span', { class: 'badge review' }, 'Review'),
        h('span', { class: 'badge' }, levelLabel(c.level)));

    let body;
    if (flipped) {
        body = h('div', { html:
            `<div class="card-name">${prose(c.name)}</div>
             <div class="formula hero small">${tex(c.tex, true)}</div>
             <div class="sections">${details(c)}</div>` });
    } else if (prefs.study === 'test' && prefs.direction === 'meaning') {
        body = h('div', { html:
            `<div class="card-name">${prose(c.name)}</div>
             <p class="prompt-meaning">${prose(c.meaning)}</p>
             <div class="hint">Write down or picture the notation, then tap the card to check.</div>` });
    } else {
        const hint = c.kind === 'equation'
            ? 'Read the equation aloud and explain each term, then tap the card to check.'
            : 'Say how this is read and what it means, then tap the card to check.';
        body = h('div', { html:
            `<div class="formula hero">${tex(c.tex, true)}</div>
             <div class="hint">${esc(hint)}</div>` });
    }

    return h('article', { class: 'card' + (flipped ? ' flipped' : '') }, badges, body);
}

function testSummary() {
    const correct = Object.values(session.answers).filter(Boolean).length;
    const missed = session.order.filter((i) => session.answers[cardId(i)] === false);
    const total = session.order.length;
    const percent = total ? Math.round((correct / total) * 100) : 0;
    return h('div', { class: 'summary' },
        h('div', { class: 'big' }, missed.length ? '✅' : '⭐'),
        h('h2', {}, 'Test complete'),
        h('div', { class: 'score' }, `${correct} of ${total} correct (${percent}%)`),
        h('p', {}, missed.length
            ? `Cards you got are marked known; the ${missed.length} you missed are marked for review.`
            : 'Every card is now marked known.'),
        h('div', { class: 'buttons' },
            missed.length > 0 && h('button', {
                class: 'btn primary',
                onclick: () => startSession(prefs.shuffle ? shuffled(missed) : missed),
            }, `Retest the ${missed.length} missed`),
            h('button', { class: 'btn', onclick: rebuild }, 'Start a new test'),
            h('button', { class: 'btn', onclick: () => { setPref('study', 'learn'); rebuild(); } }, 'Switch to Learn')));
}

function renderActions() {
    const bar = $('#actions');
    bar.replaceChildren();
    const index = deck ? currentIndex() : null;
    if (index == null || (prefs.study === 'test' && session.finished)) return;
    const id = cardId(index);
    const prev = h('button', { class: 'btn small', onclick: () => move(-1), 'aria-label': 'Previous card' }, '‹');
    const next = h('button', { class: 'btn small', onclick: () => move(1), 'aria-label': 'Next card' }, '›');
    if (prefs.study === 'learn') {
        bar.append(prev,
            h('button', {
                class: 'btn' + (progress.known.has(id) ? ' on-known' : ''),
                onclick: () => { progress.toggleKnown(id); render(); },
            }, progress.known.has(id) ? '✓ Known' : 'Known'),
            h('button', {
                class: 'btn' + (progress.review.has(id) ? ' on-review' : ''),
                onclick: () => { progress.toggleReview(id); render(); },
            }, progress.review.has(id) ? '⚑ Review' : 'Review'),
            next);
    } else if (!session.flipped) {
        bar.append(prev,
            h('button', { class: 'btn primary', onclick: reveal }, 'Show answer'),
            h('button', { class: 'btn small', onclick: () => move(1) }, 'Skip ›'));
    } else {
        bar.append(prev,
            h('button', { class: 'btn bad', onclick: () => answer(false) }, '✗ Missed'),
            h('button', { class: 'btn good', onclick: () => answer(true) }, '✓ Got it'),
            h('button', { class: 'btn small', onclick: () => move(1), 'aria-label': 'Skip' }, '›'));
    }
}

function addSwipe(el) {
    let x0 = null, y0 = null;
    el.addEventListener('touchstart', (e) => {
        x0 = e.touches[0].clientX;
        y0 = e.touches[0].clientY;
    }, { passive: true });
    el.addEventListener('touchend', (e) => {
        if (x0 == null) return;
        const dx = e.changedTouches[0].clientX - x0;
        const dy = e.changedTouches[0].clientY - y0;
        x0 = null;
        if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) move(dx < 0 ? 1 : -1);
    });
}

// ---- Drawer ----

function openDrawer() {
    renderDrawer();
    $('#drawer').classList.add('open');
    $('#drawer').setAttribute('aria-hidden', 'false');
    $('#backdrop').hidden = false;
}

function closeDrawer() {
    $('#drawer').classList.remove('open');
    $('#drawer').setAttribute('aria-hidden', 'true');
    $('#backdrop').hidden = true;
}

function checkRow(label, checked, onchange, disabled = false) {
    const id = 'c' + Math.random().toString(36).slice(2);
    return h('div', { class: 'row' },
        h('input', { type: 'checkbox', id, checked, disabled, onchange: (e) => onchange(e.target.checked) }),
        h('label', { for: id }, label));
}

function sourceProgress() {
    const excluded = new Set(prefs.excludedLevels);
    const result = {};
    for (const card of deck.cards) {
        if (!kindIncludes(card) || excluded.has(card.level)) continue;
        const entry = result[card.src] ?? { known: 0, total: 0 };
        entry.total += 1;
        if (progress.known.has(card.id)) entry.known += 1;
        result[card.src] = entry;
    }
    return result;
}

function renderDrawer() {
    const body = $('#drawer-body');
    const scroll = body.scrollTop;
    body.replaceChildren();
    if (!deck) return;

    if (!prefs.installDismissed && !window.matchMedia('(display-mode: standalone)').matches) {
        body.append(installPanel());
    }

    const practice = h('select', { onchange: (e) => { setPref('practice', e.target.value); rebuild(); } },
        [['all', 'All cards'], ['notKnown', 'Not yet known'], ['review', 'Review only']]
            .map(([v, t]) => h('option', { value: v, selected: prefs.practice === v }, t)));
    const direction = h('select', {
        disabled: prefs.study !== 'test',
        onchange: (e) => { setPref('direction', e.target.value); session.flipped = false; render(); },
    },
        [['symbol', 'Notation → meaning'], ['meaning', 'Meaning → notation']]
            .map(([v, t]) => h('option', { value: v, selected: prefs.direction === v }, t)));

    body.append(h('h4', {}, 'Practice'), h('div', { class: 'panel' },
        h('div', { class: 'row' }, h('span', { class: 'grow' }, 'Cards'), practice),
        h('div', { class: 'row' }, h('span', { class: 'grow' }, 'Test direction'), direction),
        checkRow('Shuffle', prefs.shuffle, (on) => { setPref('shuffle', on); rebuild(); }),
        h('button', { class: 'menu-btn', onclick: () => { rebuild(); closeDrawer(); } }, '↺ Restart from the first card')));

    body.append(h('h4', {}, 'Levels'), h('div', { class: 'panel' },
        deck.levels.map((level) =>
            checkRow(level.label, !prefs.excludedLevels.includes(level.id), (on) => {
                const set = new Set(prefs.excludedLevels);
                on ? set.delete(level.id) : set.add(level.id);
                setPref('excludedLevels', [...set].sort((a, b) => a - b));
                rebuild();
            }))));

    const selected = selectedSet();
    const counts = sourceProgress();
    const toggle = (keys, on) => {
        for (const k of keys) on ? selected.add(k) : selected.delete(k);
        setSelected(selected);
        rebuild();
    };
    body.append(h('h4', {}, 'Practice these'));
    for (const source of deck.sources) {
        const keys = source.groups.map((g) => groupKey(source.id, g.id));
        const collapsed = prefs.collapsed.includes(source.id);
        const count = keys.filter((k) => selected.has(k)).length;
        const prog = counts[source.id];
        const progLabel = prog ? `${prog.known}/${prog.total}` : `${count}/${keys.length}`;
        body.append(h('div', { class: 'panel', style: 'margin-bottom:10px' },
            h('button', {
                class: 'source-head' + (collapsed ? ' collapsed' : ''),
                onclick: () => {
                    const set = new Set(prefs.collapsed);
                    collapsed ? set.delete(source.id) : set.add(source.id);
                    setPref('collapsed', [...set]);
                    renderDrawer();
                },
            }, h('span', { class: 'chev' }, '▾'), source.title, h('span', { class: 'count' }, progLabel)),
            !collapsed && source.ai && h('div', { class: 'source-ai' }, source.ai),
            !collapsed && h('div', { class: 'links' },
                h('button', { onclick: () => toggle(keys, true) }, 'Select all'),
                h('button', { onclick: () => toggle(keys, false) }, 'Clear')),
            !collapsed && source.groups.map((g, i) =>
                checkRow(g.label, selected.has(keys[i]), (on) => toggle([keys[i]], on)))));
    }

    body.append(h('h4', {}, 'More'), h('div', { class: 'panel' },
        h('button', {
            class: 'menu-btn danger',
            onclick: () => {
                if (!confirm('Clear every Known and Review mark?')) return;
                progress.known.clear();
                progress.review.clear();
                progress.save();
                rebuild();
            },
        }, 'Reset progress')));

    $('#drawer-foot').textContent = `${session.order.length} ${noun()} selected`;
    body.scrollTop = scroll;
}

function installPanel() {
    const canPrompt = !!deferredInstall;
    return h('div', { class: 'install-banner' },
        h('div', {}, h('strong', {}, 'Install on your Pixel'),
            canPrompt
                ? ' — add Deep Math to your home screen for offline practice.'
                : ' — in Chrome: menu ⋮ → Install app / Add to Home screen.'),
        h('div', { class: 'actions-row' },
            canPrompt && h('button', {
                class: 'btn primary',
                onclick: async () => {
                    deferredInstall.prompt();
                    await deferredInstall.userChoice;
                    deferredInstall = null;
                    renderDrawer();
                },
            }, 'Install'),
            h('button', {
                class: 'btn',
                onclick: () => { setPref('installDismissed', true); renderDrawer(); },
            }, 'Not now')));
}

// ---- Boot ----

function wire() {
    $('#open-drawer').addEventListener('click', openDrawer);
    $('#close-drawer').addEventListener('click', closeDrawer);
    $('#backdrop').addEventListener('click', closeDrawer);
    $('#speak-btn').addEventListener('click', () => {
        const index = currentIndex();
        if (index != null) speak(cardAt(index).read);
    });

    for (const [id, key] of [['#kind-switch', 'kind'], ['#study-switch', 'study']]) {
        $(id).addEventListener('click', (e) => {
            const btn = e.target.closest('button[data-value]');
            if (!btn) return;
            setPref(key, btn.dataset.value);
            rebuild();
        });
    }

    window.addEventListener('resize', () => {
        const card = $('#stage .card');
        if (card) fitFormulas(card);
    });

    window.addEventListener('keydown', (e) => {
        if (e.target.matches('input, textarea, select')) return;
        if (e.key === 'ArrowLeft') { e.preventDefault(); move(-1); }
        else if (e.key === 'ArrowRight') { e.preventDefault(); move(1); }
        else if (e.key === ' ' || e.key === 'Spacebar') {
            e.preventDefault();
            if (prefs.study === 'test' && !session.flipped) reveal();
        } else if (e.key === 'g' || e.key === 'G') {
            if (prefs.study === 'test' && session.flipped) answer(true);
        } else if (e.key === 'm' || e.key === 'M') {
            if (prefs.study === 'test' && session.flipped) answer(false);
        } else if (e.key === 'k' || e.key === 'K') {
            const i = currentIndex();
            if (i != null && prefs.study === 'learn') { progress.toggleKnown(cardId(i)); render(); }
        } else if (e.key === 'r' || e.key === 'R') {
            const i = currentIndex();
            if (i != null && prefs.study === 'learn') { progress.toggleReview(cardId(i)); render(); }
        } else if (e.key === 's' || e.key === 'S') {
            const i = currentIndex();
            if (i != null && (prefs.study === 'learn' || session.flipped)) speak(cardAt(i).read);
        }
    });

    window.addEventListener('beforeinstallprompt', (e) => {
        e.preventDefault();
        deferredInstall = e;
        if ($('#drawer').classList.contains('open')) renderDrawer();
    });

    window.addEventListener('appinstalled', () => {
        deferredInstall = null;
        setPref('installDismissed', true);
    });
}

async function loadDeck() {
    try {
        const res = await fetch('deck.json', { cache: 'no-cache' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        deck = await res.json();
        rebuild();
    } catch (err) {
        loadError = err.message || String(err);
        render();
    }
}

if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
}

wire();
render();
loadDeck();
