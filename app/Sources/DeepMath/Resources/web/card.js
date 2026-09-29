// Renders one flashcard (renderCard) or a printable study sheet (renderSheet) with KaTeX.
// The Swift side calls these with JSON payloads and listens on the "card" message handler.
"use strict";

function post(message) {
  window.webkit?.messageHandlers?.card?.postMessage(message);
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

function tex(src, display) {
  return katex.renderToString(src, { displayMode: display, throwOnError: false });
}

// Prose may contain $inline math$, `code` and *emphasis*.
function prose(text) {
  if (!text) return "";
  return text.split(/(\$[^$]+\$|`[^`]+`)/).map(part => {
    if (part.length > 1 && part[0] === "$" && part.endsWith("$")) return tex(part.slice(1, -1), false);
    if (part.length > 1 && part[0] === "`" && part.endsWith("`")) return `<code>${esc(part.slice(1, -1))}</code>`;
    return esc(part).replace(/\*([^*\s][^*]*)\*/g, "<em>$1</em>");
  }).join("");
}

function section(title, body) {
  return body ? `<section><h3>${title}</h3>${body}</section>` : "";
}

function termsTable(terms) {
  if (!terms?.length) return "";
  const rows = terms.map(t => `<tr><td class="sym">${tex(t.tex, false)}</td><td>${prose(t.text)}</td></tr>`);
  return `<table class="terms">${rows.join("")}</table>`;
}

// Long equations are shrunk until they fit the card width, down to 55% of the base size.
function fitFormulas() {
  for (const el of document.querySelectorAll(".formula")) {
    el.style.fontSize = "";
    const base = parseFloat(getComputedStyle(el).fontSize);
    let size = base;
    while (el.scrollWidth > el.clientWidth + 1 && size > base * 0.55) {
      size *= 0.92;
      el.style.fontSize = size + "px";
    }
  }
}

function details(card) {
  return [
    section("Read aloud", card.read ? `<p class="read">“${prose(card.read)}”</p>` : ""),
    section("Meaning", card.meaning ? `<p>${prose(card.meaning)}</p>` : ""),
    section("Term by term", termsTable(card.terms)),
    section("Example", card.example ? `<div class="formula example">${tex(card.example, true)}</div>` : ""),
    section("In modern AI", card.ai ? `<p>${prose(card.ai)}</p>` : ""),
    card.cite ? `<p class="cite">Source: ${prose(card.cite)}</p>` : "",
  ].join("");
}

window.renderCard = function (p) {
  const c = p.card;
  const status = `<div class="status">
      <span class="chip">${esc(p.kindLabel)}</span>
      <span class="context">${esc(p.context)}</span>
      <span class="spacer"></span>
      ${p.known ? '<span class="chip known">Known</span>' : ""}
      ${p.review ? '<span class="chip review">Review</span>' : ""}
      <span class="chip">${esc(p.level)}</span>
    </div>`;
  let body;
  if (p.flipped) {
    body = `<div class="name">${prose(c.name)}</div>
      <div class="formula hero small">${tex(c.tex, true)}</div>
      <div class="sections">${details(c)}</div>`;
  } else if (p.prompt === "meaning") {
    body = `<div class="name">${prose(c.name)}</div>
      <p class="prompt-meaning">${prose(c.meaning)}</p>
      <div class="hint">Write down or picture the notation, then click the card or press Space to check.</div>`;
  } else {
    body = `<div class="formula hero">${tex(c.tex, true)}</div>
      <div class="hint">${esc(p.hint)}</div>`;
  }
  document.getElementById("root").innerHTML = status + body;
  document.body.className = p.flipped ? "flipped" : "front";
  fitFormulas();
  document.fonts.ready.then(fitFormulas);
  window.scrollTo(0, 0);
};

window.renderSheet = function (p) {
  document.body.className = "sheet";
  const o = p.options;
  const out = [`<h1 class="sheet-title">${esc(p.title)}</h1>`,
    `<p class="sheet-sub">${p.items.length} card${p.items.length === 1 ? "" : "s"}</p>`];
  let heading = "";
  for (const item of p.items) {
    const c = item.card;
    if (item.heading !== heading) {
      heading = item.heading;
      out.push(`<h2>${esc(heading)}</h2>`);
    }
    const line = (label, html) => html ? `<div class="line"><b>${label}</b>${html}</div>` : "";
    out.push(`<div class="item">
      <div class="item-head"><span class="item-name">${prose(c.name)}</span>
        <span class="item-meta">${esc(item.meta)}</span></div>
      <div class="formula">${tex(c.tex, true)}</div>
      ${o.read ? line("Read", prose(c.read)) : ""}
      ${o.meaning ? line("Meaning", prose(c.meaning)) : ""}
      ${o.details && c.terms.length ? termsTable(c.terms) : ""}
      ${o.details && c.example ? line("Example", tex(c.example, false)) : ""}
      ${o.ai ? line("In AI", prose(c.ai)) : ""}
      ${o.ai && c.cite ? line("Source", prose(c.cite)) : ""}
    </div>`);
  }
  document.getElementById("root").innerHTML = out.join("");
  document.fonts.ready.then(() => {
    fitFormulas();
    requestAnimationFrame(() => post("sheetReady"));
  });
};

document.addEventListener("click", () => {
  if (!window.getSelection().toString()) post("flip");
});
document.addEventListener("DOMContentLoaded", () => post("ready"));
window.addEventListener("resize", fitFormulas);
