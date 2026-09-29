// Parses every formula in a deck.json with the KaTeX bundled into the app, so the build
// fails on a TeX error instead of the app showing it in red.
// Usage: node tools/check_tex.mjs app/Sources/DeepMath/Resources/deck.json
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const katex = require(join(here, "..", "app", "Sources", "DeepMath", "Resources", "web", "katex", "katex.min.js"));

const deck = JSON.parse(readFileSync(process.argv[2], "utf8"));
const problems = [];

function check(id, field, tex, displayMode) {
  try {
    katex.renderToString(tex, { displayMode, throwOnError: true, strict: "error" });
  } catch (e) {
    problems.push(`${id} ${field}: ${e.message}\n    ${tex}`);
  }
}

// Inline math in prose is written between $…$; an odd number of $ means one is unclosed.
function checkProse(id, field, text) {
  if (!text) return;
  if ((text.match(/\$/g) || []).length % 2) {
    problems.push(`${id} ${field}: unbalanced $ in "${text}"`);
    return;
  }
  for (const m of text.matchAll(/\$([^$]+)\$/g)) check(id, field, m[1], false);
}

for (const card of deck.cards) {
  check(card.id, "tex", card.tex, true);
  if (card.example) check(card.id, "example", card.example, true);
  for (const [i, term] of card.terms.entries()) {
    check(card.id, `terms[${i}]`, term.tex, false);
    checkProse(card.id, `terms[${i}]`, term.text);
  }
  for (const field of ["name", "meaning", "ai", "read"]) checkProse(card.id, field, card[field]);
}

if (problems.length) {
  console.error(`${problems.length} formula problem(s):\n` + problems.join("\n"));
  process.exit(1);
}
console.log(`KaTeX parsed every formula in ${deck.cards.length} cards.`);
