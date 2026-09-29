# Deep Math

A macOS flashcard course for the mathematics used in modern deep learning, from Grade 5 up to
Masters level. It uses the notation of research papers. Every card shows the formula properly
typeset (KaTeX, bundled so it works offline), how to **read it aloud**, what it means, and where
it is used in modern AI. Equation cards also explain each term, so a formula like attention or
DPO stops being a wall of symbols.

It is built on the same app layout as Sloka Words: sidebar selection, Learn and
Test modes, Known / Review marks, shuffle, print / PDF, and deck import.

## What the course covers

| Branch | Topics | Used in modern AI for | Cards |
| --- | --- | --- | --- |
| Foundations & Notation | Numbers, variables, functions, sets & logic, sums & products, Greek letters, paper conventions | The symbols every paper assumes you can read | 69 |
| Linear Algebra | Vectors, dot products & norms, matrices, matrix multiplication, tensors & shapes, eigenvalues & SVD, Transformer layers | Embeddings, vector spaces, matrix multiplication in Transformer layers, dimensions | 59 |
| Multivariate Calculus | Rates & slopes, derivatives, chain rule, partial derivatives & gradients, Jacobians & Hessians, backpropagation | Backpropagation, gradients, partial derivatives for weight updates | 39 |
| Probability & Statistics | Chance & counting, random variables & expectation, distributions, Bayes, MLE & MAP, stochastic sampling, evaluation metrics | MLE, Bayesian networks, stochastic sampling, evaluating model metrics | 56 |
| Information Theory | Surprise & entropy, cross-entropy, KL divergence, mutual information & information gain, alignment objectives | Cross-entropy objectives, information gain, model alignment (RLHF, DPO, PPO, GRPO) | 28 |
| Optimization Theory | Minima, gradient descent, SGD & momentum, Adam & AdamW, learning-rate schedules, convexity & convergence rates, loss landscape, regularisation | Convergence rates, optimizer dynamics, loss-landscape navigation | 40 |
| Numerical Analysis | Number representation, floating-point formats, rounding & error, numerical stability, quantization, compute & memory efficiency | Quantization, FP8/BF16 training stability, memory-bound efficiency | 44 |

Altogether there are 335 cards: 178 **notation** cards (one symbol, such as $\nabla_{\boldsymbol\theta}\mathcal{L}$ or
$D_{\mathrm{KL}}(p\,\|\,q)$) and 157 **equation** cards (a whole formula, such as scaled dot-product
attention, Adam, the DPO loss or the KV-cache size).

Each card has one of five levels: Grade 5–6 (19 cards), Grade 7–8 (23), High school (53),
Undergraduate (111) and Masters (129). With Shuffle off, cards come in course order: every
Grade 5–6 card across all branches first, then Grade 7–8, and so on. Every card, even at
Grade 5, ends with a note on where the idea is used in modern AI.

## Build and run

Requires macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./scripts/build_app.sh
open build/DeepMath.app
```

For development you can also run `swift run --package-path app`.

## Using the app

- **Notation / Equations / Both** (toolbar): practice single symbols, whole equations, or both.
- **Learn / Test** (toolbar):
  - *Learn* shows every card in full: the formula, how to read it aloud, its meaning, the
    term-by-term breakdown or an example, and its use in AI. Step through with **← / →**, and mark
    cards with **K** (known) or **R** (review).
  - *Test* hides the answer. Recall it, press **Space** (or click the card) to reveal, then
    **G** (got it) or **M** (missed it). The header keeps the score. At the end you see your
    score and can retest just the missed cards.
  - **Test direction** (toolbar menu): *Notation → meaning* shows the formula; say how it is read
    and what each part means. *Meaning → notation* shows the name and meaning; write down the
    formula.
- **Read aloud (S):** speaks the card's reading with the system voice, so you hear how papers'
  notation is pronounced ("the gradient with respect to theta of L…").
- **Sidebar:** tick the **levels** to include, and the topics within each branch. Each branch
  shows how many of its cards you know and has **Select all** and **Clear**. Your choices are
  saved.
- **Toolbar:** choose *All cards*, *Not yet known* or *Review only*; turn **Shuffle** on or off;
  **Restart** from the first card.
- **Print** (⌘P, or the printer button): prints the selected cards as a study sheet, or saves
  it as a PDF, with the formulas typeset. Choose whether to include the reading, meaning,
  term-by-term notes and AI use, and optionally only cards marked for review.
- **File menu:** **Import Deck…** (⌘O) loads a regenerated `deck.json` without rebuilding the
  app, **Reload Deck** (⇧⌘R), **Use Built-in Deck**, and **Reset Progress…**.

Progress is saved per card id, so adding cards keeps your known and review marks.

## Editing or adding cards

The course lives in `content/`:

- `content/course.yaml` lists the levels and the branches, and each branch's topics in teaching
  order.
- `content/<branch>.yaml` holds that branch's `notation:` and `equations:` cards.

```yaml
notation:
  - id: c.gradient          # unique and stable: progress is stored by id
    group: partials         # a topic id from course.yaml
    level: 4                # 1 = Grade 5–6 … 5 = Masters
    name: Gradient (nabla)
    tex: '\nabla f(\mathbf{x})'
    read: the gradient of f at x, or del f of x
    meaning: 'The vector of all partial derivatives …'
    example: 'f(x, y) = x^{2} + 3y: \quad \nabla f = \begin{bmatrix} 2x \\ 3 \end{bmatrix}'   # optional
    ai: 'Training walks against the gradient: $-\nabla\mathcal{L}$ …'                       # optional

equations:
  - id: la.eq.attention
    group: transformers
    level: 5
    name: Scaled dot-product attention
    tex: '\operatorname{Attention}(\mathbf{Q}, \mathbf{K}, \mathbf{V}) = …'
    read: attention of Q, K, V equals softmax of …
    meaning: '…'
    terms:                  # [symbol, explanation] pairs
      - ['\sqrt{d_k}', 'keeps the score variance near 1 …']
    ai: '…'
    cite: 'Vaswani et al., “Attention Is All You Need”, 2017'   # optional
```

`tex`, `example` and term symbols are KaTeX. Prose fields can contain inline math between
`$…$`, `` `code` `` and `*emphasis*`. In YAML, put TeX in single quotes so backslashes stay
literal, and write an apostrophe inside single quotes as `''` (or use ’).

Then rebuild the deck:

```sh
python3 tools/build_deck.py
```

It checks every card (required fields, known topic and level, unique id). It then parses every
formula, including the inline math in prose, with the KaTeX bundled in the app
(`tools/check_tex.mjs`, which needs Node), so a TeX typo fails the build instead of showing red
in the app. Afterwards rebuild the app with `./scripts/build_app.sh`, or use
**File → Import Deck…** and pick `app/Sources/DeepMath/Resources/deck.json`.

## Layout

```
app/                         Swift package (SwiftUI app)
  Sources/DeepMath/Resources/deck.json   generated deck bundled into the app
  Sources/DeepMath/Resources/web/        card.html / card.js / card.css and KaTeX 0.16.22 (MIT)
content/                     the course: course.yaml plus one YAML file per branch
tools/build_deck.py          deck builder and validator
tools/check_tex.mjs          parses every formula with the bundled KaTeX
scripts/build_app.sh         builds build/DeepMath.app
scripts/make_icon.swift      draws the ∇ app icon
```
