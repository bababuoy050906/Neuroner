let pageHTML = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Text → Mind Map</title>
  <style>
:root{
  --bg:#f4f6f8;--fg:#1d2433;--panel:#ffffff;--line:#dde2e8;--field:#ffffff;--fieldb:#cfd6de;
  --btn:#ffffff;--btnb:#c5ccd6;--muted:#5b6676;--canvas:#fafbfc;--dot:#cdd3da;--pop:#ffffff;
}
body.dark{
  --bg:#0f1319;--fg:#e6e9ef;--panel:#171c24;--line:#2a323d;--field:#0f1319;--fieldb:#313a47;
  --btn:#1f2630;--btnb:#3a4452;--muted:#9aa5b5;--canvas:#12161c;--dot:#2a313b;--pop:#1f2630;
  color-scheme:dark;
}
*{box-sizing:border-box}
html,body{height:100%;margin:0;font-family:Helvetica,Arial,sans-serif;color:var(--fg);background:var(--bg)}
body{display:flex}
#panel{width:340px;max-width:100%;background:var(--panel);border-right:1px solid var(--line);padding:14px;display:flex;flex-direction:column;gap:10px;z-index:5;overflow:auto}
#panel h1{font-size:18px;margin:0}
#input{flex:1;min-height:180px;resize:none;border:1px solid var(--fieldb);background:var(--field);color:var(--fg);border-radius:8px;padding:10px;font:13px/1.45 ui-monospace,Menlo,Consolas,monospace}
.row{display:flex;gap:8px;flex-wrap:wrap}
button,.btn{border:1px solid var(--btnb);background:var(--btn);border-radius:8px;padding:8px 12px;font-size:14px;cursor:pointer;color:inherit}
button:disabled{opacity:.45;cursor:default}
button.primary{background:#2A9D8F;border-color:#2A9D8F;color:#fff;font-weight:600}
.knob{display:flex;flex-direction:column;gap:4px;font-size:13px}
.knob label{display:flex;justify-content:space-between}
.knob input[type=range]{width:100%;accent-color:#2A9D8F}
.knob small{color:var(--muted);font-size:11px;line-height:1.3}

/* per-level line controls */
.levels{border:1px solid var(--line);border-radius:8px;padding:8px 10px;font-size:13px}
.levels summary{cursor:pointer;font-weight:600}
#levelsBody{display:flex;flex-direction:column;gap:8px;margin-top:8px}
#levelsBody small{color:var(--muted);font-size:11px;line-height:1.3}
.lvl{display:flex;flex-direction:column;gap:2px}
.lvl label{display:flex;justify-content:space-between;font-size:12px}
.lvl input[type=range]{width:100%;accent-color:#2A9D8F}
#levelsBody .reset{align-self:flex-start;padding:5px 10px;font-size:12px}

#status{font-size:12px;color:var(--muted);min-height:16px}
#legendBody{display:grid;gap:4px;margin-top:6px;font-size:12px}
.sw{display:inline-block;width:14px;height:14px;border-radius:4px;vertical-align:-2px;margin-right:6px}
#canvas{flex:1;position:relative;overflow:hidden;touch-action:none;cursor:grab;background-color:var(--canvas);
  background-image:radial-gradient(circle,var(--dot) 1px,transparent 1.2px);background-size:28px 28px}
#canvas:active{cursor:grabbing}
#svg{width:100%;height:100%;display:block;user-select:none;-webkit-user-select:none}
#toolbar{position:absolute;right:12px;top:12px;display:flex;gap:6px;z-index:3}
#toolbar button{box-shadow:0 1px 3px rgba(0,0,0,.18)}
#toolbar button.primary{background:#2A9D8F}
#menuBtn{display:none}

/* box popup: type + single-line length */
#editor{position:absolute;z-index:4;background:var(--pop);border:1px solid var(--fieldb);border-radius:8px;padding:8px;
  box-shadow:0 6px 20px rgba(0,0,0,.28);font-size:13px;min-width:210px;display:flex;flex-direction:column;gap:8px}
#editor[hidden]{display:none}
#editor select{font-size:14px;padding:4px;background:var(--field);color:var(--fg);border:1px solid var(--fieldb);border-radius:6px}
.erow{display:flex;align-items:center;gap:6px}
.erow.col{flex-direction:column;align-items:stretch;gap:3px}
.erow[hidden]{display:none}
.erow label{display:flex;justify-content:space-between;font-size:12px}
.erow input[type=range]{width:100%;accent-color:#2A9D8F}
button.mini{padding:4px 8px;font-size:12px;align-self:flex-start}

/* highlight + ripple */
.node,.edge{transition:opacity .28s ease}
.node{transform-box:fill-box;transform-origin:center}
.dim{opacity:.13}

@media (max-width:760px){
  #panel{position:absolute;inset:0 auto 0 0;width:88%;transform:translateX(-100%);transition:transform .2s}
  #panel.open{transform:none}
  #menuBtn{display:inline-block}
}
  </style>
</head>
<body>
  <aside id="panel">
    <h1>Text → Mind Map</h1>
    <textarea id="input" spellcheck="false" placeholder="Paste or type your text here…"></textarea>
    <div class="row">
      <button id="gen" class="primary">Generate</button>
      <label class="btn">Open file<input type="file" id="file" accept=".txt,.md,.text" hidden></label>
      <button id="sample">Sample</button>
    </div>
    <div class="knob">
      <label for="len">Line length (all levels) <b id="lenVal">100%</b></label>
      <input type="range" id="len" min="100" max="300" step="5" value="100">
      <small>Default layout is already compacted (long lines are shortened automatically and the map is kept within ~17,000 px so the PDF stays crisp). Raise this to stretch every line.</small>
    </div>
    <details class="levels" id="levelsBox">
      <summary>Line length by level</summary>
      <div id="levelsBody"><small>Generate a map first.</small></div>
    </details>
    <div id="status"></div>
    <details open>
      <summary>Colour legend</summary>
      <div id="legendBody"></div>
    </details>
  </aside>

  <main id="canvas">
    <svg id="svg" xmlns="http://www.w3.org/2000/svg"></svg>
    <div id="toolbar">
      <button id="menuBtn">☰</button>
      <button id="theme" title="Toggle dark mode">☾</button>
      <button id="zin">+</button>
      <button id="zout">−</button>
      <button id="fit">Fit</button>
      <button id="pdf" class="primary">PDF</button>
    </div>
    <div id="editor" hidden>
      <div class="erow">Type: <select id="typeSel"></select></div>
      <div class="erow col" id="lineRow">
        <label for="lineLen">This line only <b id="lineVal">100%</b></label>
        <input type="range" id="lineLen" min="0" max="400" step="1" value="100">
        <button id="lineReset" class="mini">Reset this line</button>
      </div>
    </div>
  </main>

  <script src="https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/svg2pdf.js@2.2.4/dist/svg2pdf.umd.min.js"></script>

  <script>
(function (global) {
  'use strict';

  /* ---------------- types & colours ---------------- */
  const TYPES = {
    term:       { label: 'Term',              color: '#E63946' },
    definition: { label: 'Definition',        color: '#457B9D' },
    member:     { label: 'Member of a Group', color: '#2A9D8F' },
    value:      { label: 'Value / Number',    color: '#F4A261' },
    person:     { label: 'Name / Person',     color: '#9B5DE5' },
    substance:  { label: 'Name / Substance',  color: '#00B4D8' },
    structure:  { label: 'Name / Structure',  color: '#6C757D' },
    concept:    { label: 'Name / Concept',    color: '#7B2CBF' },
    plant:      { label: 'Name / Plant',      color: '#70AD47' },
    creature:   { label: 'Name / Creature',   color: '#F15BB5' },
    food:       { label: 'Name / Food',       color: '#E9C46A' },
    label:      { label: 'Label',             color: '#ADB5BD' },
    quote:      { label: 'Quotation',         color: '#FF6B6B' }
  };
  const TEAL = TYPES.member.color;

  /* ---------------- symbols & emoji (the formatter's shorthand: → ↑ ✓ ⚠ = + & @ 🔑 …) ---------------- */
  // A "symbol word" is a space-separated word made only of symbols / emoji. Symbol words are content, not filler:
  // they are kept inside the boxes instead of being trimmed away.
  let SYM_TOKEN, LEAD_LETTER;
  try {
    SYM_TOKEN = new RegExp('^[\\p{S}&@\\uFE0E\\uFE0F\\u200D\\u20E3]+$', 'u');
    LEAD_LETTER = new RegExp('^([^\\p{L}\\p{N}]*?)(\\p{L})', 'u');
  } catch (e) {
    // older engines without Unicode property escapes
    SYM_TOKEN = /^(?:[=+<>&@~^|$]|[\u00A9\u00AE\u00B0\u00B1\u00D7\u00F7]|[\u2190-\u23FF\u2460-\u27BF\u2900-\u2BFF\uFE0E\uFE0F\u200D\u20E3]|[\uD83C-\uD83E][\uDC00-\uDFFF])+$/;
    LEAD_LETTER = /^([^A-Za-z0-9]*?)([A-Za-z])/;
  }
  const ARROW_ASCII = /^(?:<[-=]+>|[-=]+>|<[-=]+)$/;            // -> <- <-> => (ASCII mode)
  const isSym = t => SYM_TOKEN.test(t) || ARROW_ASCII.test(t);
  const KEEP_LOWER = /^(?:w\/o?|e\.g\.|i\.e\.)(?=\s|$)/i;         // these shorthands stay lowercase

  /* ---------------- helpers ---------------- */
  const wc = s => (s.trim() ? s.trim().split(/\s+/).length : 0);
  // capitalises the first LETTER (skipping leading symbols / emoji): "↑blood" -> "↑Blood"
  function capFirst(s) {
    if (!s) return s;
    if (KEEP_LOWER.test(s)) return s;
    const m = LEAD_LETTER.exec(s);
    if (!m) return s;
    const i = m[1].length;
    return s.slice(0, i) + m[2].toUpperCase() + s.slice(i + m[2].length);
  }
  const bare = w => w.toLowerCase().replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, '');
  const strip = s => s.replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/[*_`~]+/g, ' ').replace(/\s+/g, ' ').trim();

  const STOP = new Set(('a an the of in on at to for with by from and or but as is are was were be been being that which who whom whose ' +
    'it its this these those they their them he she his her we our you your i my there here also then than into onto over under about ' +
    'can could will would shall should may might must do does did has have had very just such so if when while because although though ' +
    'however thus therefore both each other some any many much more most like through across between among during within without per via ' +
    'upon toward towards against along around behind beyond near').split(' '));

  /* ---------------- lexicons (rule-based "knowledge") ---------------- */
  const LEX = new Map();
  const addLex = (type, list) => list.split(/\s+/).forEach(w => { if (w && !LEX.has(w)) LEX.set(w, type); });

  addLex('plant', 'plant tree flower shrub vine herb weed seedling sapling conifer oak pine maple birch willow palm bamboo fern moss grass rose tulip lily orchid daisy sunflower cactus ivy algae wheat barley oat soybean cotton tobacco lotus jasmine lavender basil cedar elm eucalyptus seaweed crop');
  addLex('creature', 'animal dog cat horse cow pig sheep goat chicken duck rabbit mouse rat lion tiger wolf fox deer elephant giraffe monkey ape gorilla whale dolphin shark fish salmon trout frog toad snake lizard turtle crocodile bird eagle owl sparrow penguin bee ant butterfly spider beetle mosquito worm dinosaur camel zebra kangaroo panda otter octopus squid crab lobster snail bacteria bacterium mammal reptile amphibian insect predator');
  addLex('food', 'food bread rice pasta noodle cheese milk butter egg meat beef pork apple banana orange grape mango tomato potato carrot onion garlic lettuce spinach broccoli bean nut almond peanut honey sugar chocolate cake cookie pizza soup salad sandwich burger coffee tea juice wine beer yogurt fruit vegetable cereal flour');
  addLex('substance', 'water oxygen hydrogen carbon nitrogen helium sodium chlorine calcium iron gold silver copper zinc mercury sulfur sulphur phosphorus potassium magnesium aluminum aluminium lithium uranium plutonium silicon neon argon methane ethanol glucose fructose insulin protein enzyme hormone dna rna atp vitamin acid alkali salt oil plastic steel alloy oxide ozone ammonia hemoglobin haemoglobin chlorophyll cholesterol caffeine penicillin aspirin antibiotic vaccine toxin venom polymer mineral metal gas liquid ion molecule pigment fuel');
  addLex('structure', 'cell nucleus membrane mitochondria mitochondrion chloroplast ribosome organ heart lung liver kidney brain skin bone muscle tissue neuron artery vein stomach intestine eye ear nose tooth skeleton wall bridge tower building castle temple pyramid dam tunnel cathedral mosque palace stadium museum library university leaf root petal seed trunk cortex vacuole cytoplasm atom crystal planet star galaxy moon continent mountain river ocean sea lake volcano island desert valley canyon earth sun mars venus jupiter saturn neptune uranus');

  const PHRASES = {
    'carbon dioxide': 'substance', 'sulfuric acid': 'substance', 'hydrochloric acid': 'substance',
    'nitric acid': 'substance', 'amino acid': 'substance', 'fatty acid': 'substance',
    'red blood cell': 'structure', 'white blood cell': 'structure', 'blood cell': 'structure',
    'cell membrane': 'structure', 'cell wall': 'structure', 'black hole': 'structure',
    'solar system': 'structure', 'sweet potato': 'food', 'olive oil': 'food'
  };

  const FIRST = new Set(('james john robert michael william david richard joseph thomas charles mary patricia jennifer linda elizabeth barbara susan jessica sarah karen nancy lisa margaret sandra ashley emily donna michelle carol amanda melissa deborah stephanie rebecca laura sharon cynthia kathleen amy angela anna ruth brenda pamela nicole katherine samantha christine helen emma olivia sophia isabella ava mia charlotte amelia peter paul george henry edward albert isaac nikola marie pierre rosalind maria jose juan carlos luis pedro miguel antonio francisco ana andres emilio ferdinand benigno corazon gregorio apolinario marcelo rodrigo manuel ramon diosdado fidel elpidio melvin jan jean john-paul stephen alexander charles galileo leonardo isabel louis').split(' '));
  const FAMOUS = new Set(('aristotle plato socrates einstein newton darwin galileo tesla edison curie pasteur mendel hawking mozart beethoven shakespeare napoleon caesar cleopatra lincoln washington gandhi mandela rizal bonifacio aguinaldo magellan columbus').split(' '));
  const TITLE = new Set(['mr', 'mrs', 'ms', 'dr', 'prof', 'sir', 'st', 'lord', 'lady']);
  const PERSON_BEFORE = new Set(('by named called professor prof president king queen emperor captain general author philosopher scientist physicist chemist biologist mathematician inventor explorer writer poet painter artist composer doctor saint').split(' '));
  const PERSON_AFTER = new Set(('said argued wrote stated claimed noted discovered invented proposed founded born died believed suggested showed developed published described explained observed conducted named served became put').split(' '));
  const MONTHS = new Set(('january february march april may june july august september october november december monday tuesday wednesday thursday friday saturday sunday').split(' '));

  function lexType(w) {
    w = w.toLowerCase();
    const c = [w, w.replace(/ies$/, 'y'), w.replace(/es$/, ''), w.replace(/s$/, '')];
    for (const x of c) if (LEX.has(x)) return LEX.get(x);
    return null;
  }

  /* ---------------- entity finder ---------------- */
  const DATE_RE = /\b(?:(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?|\d{1,2}(?:st|nd|rd|th)?\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:,?\s+\d{4})?)\b/g;
  // NOTE: a bare degree sign ("25°") is now accepted as a unit so it stays one value box.
  const UNITS = '%|percent|per cent|°\\s?[CFK]|°|degrees?(?:\\s(?:Celsius|Fahrenheit))?|km/h|mph|kg|mg|g|lbs?|cm|mm|km|m|mL|ml|L|l|Hz|kHz|MHz|GHz|KB|MB|GB|TB|ms|s|sec|seconds?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|decades?|centuries|century|million|billion|trillion|thousand|BC|AD|BCE|CE|times|miles?|meters?|metres?|kilometers?|kilometres?|feet|foot|ft|inch(?:es)?|liters?|litres?|grams?|kilograms?|tons?|tonnes?|volts?|V|watts?|W|kW|calories?|kcal|pounds?|dollars?|euros?|pesos?|people|species';
  const NUM_RE = new RegExp('(?:[$€£₱¥]\\s?)?\\b\\d+(?:,\\d{3})*(?:\\.\\d+)?(?:\\s?[-–]\\s?\\d+(?:\\.\\d+)?)?(?:\\s?(?:' + UNITS + '))?(?![A-Za-z])', 'g');
  // qualifiers that belong inside a value box ("For 20 mins", "At 25°", "Up to 3 hours")
  const VALUE_PREFIX_RE = /\b(?:for|at|around|about|approximately|up to|within|nearly|roughly|over|under)\s+$/i;
  const CAP_RE = /\b(?:(?:Mr|Mrs|Ms|Dr|Prof|Sir|St|Lord|Lady)\.?\s+)?[A-Z][\w'’\-]*(?:\s+(?:(?:of|the|de|van|von|da|di|la|le)\s+)*[A-Z][\w'’\-]*)*/g;

  function classifyCaps(ws, text, start, end) {
    const lw = ws.map(bare);
    if (ws.length === 1 && MONTHS.has(lw[0])) return 'value';
    if (TITLE.has(lw[0])) return 'person';
    const lt = lexType(lw[lw.length - 1]);
    if (ws.length === 1 && /^[A-Z]{2,}$/.test(ws[0])) return lt || 'concept';
    if (lw.some(w => FIRST.has(w) || FAMOUS.has(w))) return 'person';
    const prev = (text.slice(0, start).match(/([A-Za-z]+)\W*$/) || [])[1];
    const next = (text.slice(end).match(/^\W*([A-Za-z]+)/) || [])[1];
    if ((prev && PERSON_BEFORE.has(prev.toLowerCase())) || (next && PERSON_AFTER.has(next.toLowerCase()))) return lt || 'person';
    if (lt) return lt;
    if (ws.length === 1 && /^(?:[A-Z][a-z]?\d*){2,}$/.test(ws[0]) && /[\da-z]/.test(ws[0])) return 'substance';
    return 'concept';
  }

  function findEntities(text) {
    const spans = [];
    const free = (a, b) => !spans.some(s => a < s.end && b > s.start);
    const add = (start, end, type) => {
      if (end > start && free(start, end)) spans.push({ start, end, type, text: text.slice(start, end).trim() });
    };

    for (const m of text.matchAll(DATE_RE)) add(m.index, m.index + m[0].length, 'value');
    for (const m of text.matchAll(NUM_RE)) {
      let s = m.index; const e = m.index + m[0].length;
      // a minus sign glued to the number stays inside its box ("-15 °C", "−3")
      if ((text[s - 1] === '-' || text[s - 1] === '\u2212') && (s === 1 || /[\s(\[]/.test(text[s - 2])) && free(s - 1, e)) s -= 1;
      const pm = text.slice(0, s).match(VALUE_PREFIX_RE);
      if (pm && free(s - pm[0].length, e)) s -= pm[0].length;   // pull "for / at / around…" into the value box
      add(s, e, 'value');
    }

    const lead = text.search(/[A-Za-z0-9]/);
    for (const m of text.matchAll(CAP_RE)) {
      let start = m.index, str = m[0], stripped = 0;
      for (;;) {
        const mm = str.match(/^(\S+)\s*/);
        if (mm && STOP.has(bare(mm[1]))) { start += mm[0].length; str = str.slice(mm[0].length); stripped++; } else break;
      }
      if (str.length < 2) continue;
      const end = start + str.length;
      if (!free(start, end)) continue;
      const ws = str.split(/\s+/);
      const atStart = stripped === 0 && m.index <= lead;
      if (ws.length === 1 && atStart) {
        const w = bare(ws[0]);
        if (!(lexType(w) || /^[A-Z]{2,}$/.test(ws[0]) || FIRST.has(w) || FAMOUS.has(w) || MONTHS.has(w))) continue;
      }
      add(start, end, classifyCaps(ws, text, start, end));
    }

    const toks = [...text.matchAll(/[A-Za-z][A-Za-z'’\-]*/g)];
    for (let i = 0; i < toks.length; i++) {
      const t = toks[i], s = t.index, e = s + t[0].length;
      if (!free(s, e)) continue;
      const w = t[0].toLowerCase(), nx = toks[i + 1];
      if (nx && free(nx.index, nx.index + nx[0].length) && /^\s$/.test(text.slice(e, nx.index))) {
        const ph = PHRASES[w + ' ' + nx[0].toLowerCase()];
        if (ph) { add(s, nx.index + nx[0].length, ph); i++; continue; }
      }
      const lt = lexType(w);
      if (lt) { add(s, e, lt); continue; }
      if (w.length >= 7 && /(?:ism|ology|osis|ography)$/.test(w)) add(s, e, 'concept');
    }
    return spans.sort((a, b) => a.start - b.start);
  }

  function singleEntity(t) {
    t = t.trim();
    const sp = findEntities(t);
    return sp.length === 1 && sp[0].start <= 1 && sp[0].end >= t.length - 1 ? sp[0] : null;
  }

  /* ---------------- text cleaning ---------------- */
  const trimP = x => x.replace(/^[,;:.\-–—!?]+|[,;:.\-–—!?]+$/g, '');
  function tidy(f) {
    const w = f.replace(/[()\[\]"“”]/g, ' ').replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
    // filler words and bare punctuation are trimmed from both ends; symbol / emoji words (→ ↑ ✓ ⚠ = + & …) are kept
    const stop = x => { const c = trimP(x); if (!c) return true; const b = bare(c); return b === '' ? !isSym(c) : STOP.has(b); };
    while (w.length && stop(w[0])) w.shift();
    while (w.length && stop(w[w.length - 1])) w.pop();
    if (!w.length) return '';
    // punctuation glued to the first / last word is removed, but never from a symbol word or an ASCII arrow
    const edge = x => {
      if (isSym(x) || /^(?:e\.g\.|i\.e\.)$/i.test(x)) return x;
      let y = x;
      if (!/^<?[-=]+>/.test(y)) y = y.replace(/^[,;:.\-–—]+/, '');
      if (!/<[-=]+$/.test(y)) y = y.replace(/[,;:.\-–—]+$/, '');
      return y;
    };
    w[0] = edge(w[0]); w[w.length - 1] = edge(w[w.length - 1]);
    return capFirst(w.join(' ').trim());
  }

  function splitClauses(str) {
    if (wc(str) <= 9) return [str];
    const parts = str
      .split(/\s*[;:,—–]\s*|\s+(?=(?:and|but|which|that|because|while|although|whereas|when|where|since|thus|therefore|however|then|unless|until)\s)/i)
      .map(tidy).filter(Boolean);
    const out = [];
    for (const p of parts) {
      if (out.length && wc(p) < 3) out[out.length - 1] += ' ' + p.toLowerCase();
      else out.push(p);
    }
    return out.length ? out : [str];
  }

  function splitSentences(p) {
    const t = p
      .replace(/\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc|No|Fig|approx|Inc|Ltd|Co)\./g, '$1\u0003')
      .replace(/\b(e\.g|i\.e|U\.S|a\.m|p\.m)\./gi, m => m.replace(/\./g, '\u0003'))
      .replace(/(\d)\.(\d)/g, '$1\u0003$2')
      .replace(/[“"][^”"]*[”"]/g, q => q.replace(/\./g, '\u0003').replace(/!/g, '\u0004').replace(/\?/g, '\u0005'));
    const parts = t.match(/[^.!?]+(?:[.!?]+["”')\]]*|$)/g) || [t];
    return parts.map(s => s.replace(/\u0003/g, '.').replace(/\u0004/g, '!').replace(/\u0005/g, '?').trim()).filter(s => wc(s) >= 1);
  }

  function autoTopic(text, excl) {
    const freq = new Map();
    for (const m of text.matchAll(/[A-Za-z][A-Za-z'\-]{3,}/g)) {
      const w = m[0].toLowerCase();
      if (STOP.has(w) || (excl && excl.includes(w))) continue;
      freq.set(w, (freq.get(w) || 0) + 1);
    }
    let best = null, bs = 0;
    for (const [w, c] of freq) { const sc = c * (1 + Math.min(w.length, 12) / 20); if (sc > bs) { bs = sc; best = w; } }
    return best ? capFirst(best) : 'Mind Map';
  }

  /* ---------------- tree building ---------------- */
  let uid = 0;
  function createNode(text, type, parent) {
    text = text.trim();
    if (parent) {
      const dup = parent.children.find(c => c.type === type && c.text.toLowerCase() === text.toLowerCase());
      if (dup) return dup;
    }
    const n = {
      id: ++uid, text, type, parent: parent || null, children: [], group: false,
      depth: parent ? parent.depth + 1 : 0, isMember: !!(parent && parent.group)
    };
    if (parent) parent.children.push(n);
    return n;
  }

  // Turns a piece of text into: [entity | fragment] nodes, entities hang off the fragment that precedes them.
  function buildSegments(text, parent, opt) {
    const o = Object.assign({ headType: 'label', restType: 'label' }, opt);
    const spans = findEntities(text), segs = [];
    // Symbols / emoji that stand alone (→ ↑ ✓ ⚠ = + …) are kept: they are glued onto the neighbouring box
    // (in front of the entity that follows, or after the entity before) instead of being dropped.
    let carry = '', carryL = false, carryR = false;
    const frag = f => {
      const t = tidy(f);
      if (!t) return;
      if (t.split(' ').every(isSym)) { carry = t; carryL = /^\s/.test(f); carryR = /\s$/.test(f); return; }
      segs.push({ frag: true, text: t, raw: f });
    };
    let pos = 0;
    for (const s of spans) {
      if (s.start > pos) frag(text.slice(pos, s.start));
      let t = capFirst(s.text), pre = false;
      if (carry) { t = carry + (carryR ? ' ' : '') + t; carry = ''; pre = true; }
      segs.push({ frag: false, text: t, type: s.type, pre });
      pos = s.end;
    }
    if (pos < text.length) frag(text.slice(pos));
    if (carry) {                                           // symbols at the very end of the text
      if (segs.length) segs[segs.length - 1].text += (carryL ? ' ' : '') + carry;
      else segs.push({ frag: true, text: carry, raw: carry });   // a line made only of symbols still becomes a box
    }

    // Merge "modifier phrase + closing term" into one box, e.g. "Drugs that undergo rapid" + "Hydrolysis".
    // Only when the phrase ends on a content word (not "in", "of", a comma, …) and the result stays short.
    if (segs.length >= 2) {
      const a = segs[segs.length - 2], b = segs[segs.length - 1];
      if (a.frag && !b.frag && b.type !== 'value' && !b.pre) {
        const raw = a.raw.trim();
        const lastW = bare(raw.split(/\s+/).pop() || '');
        if (lastW && !STOP.has(lastW) && !/[,;:\-–—(]$/.test(raw) && wc(a.text) + wc(b.text) <= 8) {
          segs.splice(segs.length - 2, 2, { frag: false, text: a.text + ' ' + b.text, type: b.type });
        }
      }
    }

    let head = null, cur = null, headIsEnt = false;
    for (const sg of segs) {
      if (sg.frag) {
        const chunks = splitClauses(sg.text);
        const node = createNode(chunks[0], head ? o.restType : o.headType, head || parent);
        for (let i = 1; i < chunks.length; i++) createNode(chunks[i], o.restType, node);
        if (!head) { head = node; headIsEnt = false; }
        cur = node;
      } else {
        const sibling = !head || (headIsEnt && cur === head);
        const node = createNode(sg.text, sg.type, sibling ? parent : cur);
        if (!head) { head = node; headIsEnt = true; cur = node; }
      }
    }
    return head;
  }

  function splitList(tail) {
    return tail.replace(/[.!?]+$/, '').split(/\s*(?:,|;|\band\b|\bor\b|\bas well as\b)\s*/i)
      .map(s => s.trim()).filter(s => s && !/^etc\.?$/i.test(s));
  }

  function tryList(s, parent) {
    let m = s.match(/^(.{2,90}?),?\s+(?:include[sd]?|including|such as|consist(?:s|ed)? of|comprise[sd]?|composed of|made up of|divided into|classified into|categori[sz]ed into|come in)\s+(.+)$/i);
    let colon = false;
    if (!m) { m = s.match(/^([^:]{2,70}):\s+(.+)$/); colon = true; }
    if (!m) return null;
    const items = splitList(m[2]);
    if (items.length < 2 || Math.max(...items.map(wc)) > 6) return null;
    if (colon && (/^(?:a|an|the)\s/i.test(m[2]) || /\b(?:that|which|who|is|are|was|were)\b/i.test(items[0]))) return null;
    const head = buildSegments(m[1].replace(/^there\s+(?:are|is)\s+(?:\w+\s+)?/i, ''), parent, { headType: 'label' }) || parent;
    head.group = true;
    items.forEach(it => buildSegments(it, head, { headType: 'member' }));
    return head;
  }

  const PRON = /^(?:it|this|that|these|those|they|he|she|we|i|you|there|here|which|who|what|some|many|most|all)\b/i;
  function tryDefinition(s, parent) {
    let subj = null, obj = null;
    let m = s.match(/^(.{2,70}?)\s+(?:is defined as|can be defined as|is known as|are known as|is called|are called|refers? to|means|is|are|was|were)\s+(.{6,})$/i);
    if (m && !/,/.test(m[1]) && wc(m[1]) <= 5 && !PRON.test(m[1])) { subj = m[1]; obj = m[2]; }
    else {
      m = s.match(/^([^:]{2,50}):\s+(.{6,})$/);
      if (m && wc(m[1]) <= 5) { subj = m[1]; obj = m[2]; }
    }
    if (!subj || wc(obj) < 2) return null;
    subj = subj.replace(/^(?:the|a|an)\s+/i, '').trim();
    const ent = singleEntity(subj);
    const type = ent && ent.type !== 'concept' && ent.type !== 'value' ? ent.type : 'term';
    const node = createNode(capFirst(subj), type, parent);
    buildSegments(obj, node, { headType: 'definition', restType: 'definition' });
    return node;
  }

  function processText(raw, parent, opt) {
    opt = opt || {};
    let s = strip(raw);
    if (!s) return null;
    const quotes = [];
    s = s.replace(/[“"]([^”"]+)[”"]/g, (m, q) => {
      if (wc(q) >= 4) { quotes.push(q.trim()); return ' '; }
      return ' ' + q + ' ';
    }).replace(/\s+/g, ' ').trim();

    const head = s ? (tryList(s, parent) || tryDefinition(s, parent) || buildSegments(s, parent, { headType: opt.headType || 'label' })) : null;
    let first = null;
    quotes.forEach(q => {
      const n = createNode('“' + q.replace(/[.\s]+$/, '') + '”', 'quote', head || parent);
      first = first || n;
    });
    return head || first;
  }

  /* ---------------- document parser ---------------- */
  function parse(raw) {
    uid = 0;
    const lines = raw.replace(/\r\n?/g, '\n').replace(/\t/g, '    ').split('\n');
    const blank = i => i < 0 || i >= lines.length || !lines[i].trim();
    const BUL = /^(\s*)(?:[-*•·–+]|\d+[.)]|[a-z][.)])\s+(.+)$/;

    const first = lines.findIndex(l => l.trim());
    if (first < 0) return null;

    let title = null, start = first;
    const f = lines[first].trim(), fm = f.match(/^#{1,6}\s+(.+?)\s*#*$/);
    if (fm) { title = strip(fm[1]); start = first + 1; }
    else if (wc(f) <= 12 && !/[.!?:;,]$/.test(f) && !BUL.test(lines[first]) && lines.slice(first + 1).some(l => l.trim())) {
      title = strip(f); start = first + 1;
    }

    function kind(i) {
      const rawL = lines[i], t = rawL.trim();
      if (!t) return { k: 'blank' };
      let m = t.match(/^(#{1,6})\s+(.+?)\s*#*$/);
      if (m) return { k: 'head', level: m[1].length, text: m[2] };
      const prevBlank = i <= start || blank(i - 1);
      let nxt = i + 1; while (nxt < lines.length && !lines[nxt].trim()) nxt++;
      const hasNext = nxt < lines.length;
      m = t.match(/^(\d+(?:\.\d+)+)\.?\s+(.+)$/);
      if (m && wc(m[2]) <= 10 && !/[.!?;,]$/.test(m[2])) return { k: 'head', level: m[1].split('.').length, text: m[2] };
      m = t.match(/^\d+[.)]\s+(.+)$/);
      if (m && prevBlank && wc(m[1]) <= 9 && !/[.!?;,:]$/.test(m[1]) && hasNext && !/^\s*\d+[.)]\s/.test(lines[nxt]))
        return { k: 'head', level: 1, text: m[1] };
      m = rawL.match(BUL);
      if (m) return { k: 'bullet', indent: m[1].length, text: m[2] };
      if (/:$/.test(t) && wc(t) <= 12) return { k: 'colon', text: t.slice(0, -1) };
      const caps = /^[A-Z0-9][A-Z0-9\s\-&',]*$/.test(t) && /[A-Z]{2}/.test(t) && wc(t) <= 10;
      if (caps || (prevBlank && hasNext && wc(t) <= 8 && !/[.!?;,:]$/.test(t) && /^[A-Z0-9]/.test(t)))
        return { k: 'head', level: 1, text: caps ? capFirst(t.toLowerCase()) : t };
      return { k: 'text', text: t };
    }

    let anyHeads = false;
    for (let i = start; i < lines.length; i++) if (kind(i).k === 'head') { anyHeads = true; break; }

    const ent = title ? singleEntity(title) : null;
    const root = createNode(capFirst(title || autoTopic(raw)), ent && ent.type !== 'value' ? ent.type : 'concept', null);
    root.group = true;

    const stack = [];
    let container = root, bullets = [], para = [], colonGroup = null;

    function flushPara() {
      if (!para.length) return;
      const text = para.join(' ').replace(/\s+/g, ' ');
      para = [];
      const sents = splitSentences(text);
      let target = colonGroup || container;
      if (target === root && !anyHeads && sents.length >= 2) {
        target = createNode(autoTopic(text, [root.text.toLowerCase()]), 'label', root);
        target.group = true;
      }
      sents.forEach(s => processText(s, target, { headType: 'label' }));
    }

    for (let i = start; i < lines.length; i++) {
      const c = kind(i);
      if (c.k === 'blank') { flushPara(); bullets = []; colonGroup = null; }
      else if (c.k === 'head') {
        flushPara(); bullets = []; colonGroup = null;
        while (stack.length && stack[stack.length - 1].level >= c.level) stack.pop();
        const parent = stack.length ? stack[stack.length - 1].node : root;
        const node = createNode(capFirst(strip(c.text).replace(/:$/, '')), 'label', parent);
        node.group = true;
        stack.push({ level: c.level, node });
        container = node;
      } else if (c.k === 'colon') {
        flushPara(); bullets = [];
        const node = createNode(capFirst(strip(c.text)), 'label', container);
        node.group = true;
        colonGroup = node;
      } else if (c.k === 'bullet') {
        flushPara();
        while (bullets.length && bullets[bullets.length - 1].indent >= c.indent) bullets.pop();
        const parent = bullets.length ? bullets[bullets.length - 1].node : (colonGroup || container);
        if (bullets.length) parent.group = true;
        const node = processText(c.text, parent, { headType: 'member' });
        bullets.push({ indent: c.indent, node: node || parent });
      } else {
        bullets = [];
        para.push(c.text);
      }
    }
    flushPara();
    return root;
  }

  global.NLP = { TYPES, TEAL, parse };
})(window);
  </script>

  <script>
(function (g) {
  'use strict';
  const FONT = 'Helvetica, Arial, sans-serif';
  const ctx = document.createElement('canvas').getContext('2d');
  const ROOT_FS = 34, FLOOR_FS = 13;
  const GAP = 14, EDGE_MIN = 34, EPS = 0.03, EXCL = 0.14;
  const FAN = 2.6, MAXFAN = 4.2, TAU = Math.PI * 2;

  /* ---- default compaction (what makes generations "B-like") ----
     Lines shorter than SOFT_L are untouched. Longer lines are pulled in with a power curve
         L' = SOFT_L * (L / SOFT_L) ^ p        (p < 1)
     so a 134,000 px spoke becomes a few thousand px while the relative order of lines is kept
     (wordier / busier branches still get longer lines). The exponent p is lowered automatically
     until the whole map fits inside MAX_SPAN px on its longest side (PDF export is capped at
     19,000 px per side, so staying below that keeps exported text crisp).                    */
  const SOFT_L = 300, P_START = 0.55, P_MIN = 0.18, P_STEP = 0.03, MAX_SPAN = 17000;

  /* ---- font size: big centre, decay that plateaus at a readable floor ---- */
  function fontSize(depth, maxDepth) {
    if (depth === 0) return ROOT_FS;
    const k = 3 / Math.max(maxDepth, 3);
    return Math.round((FLOOR_FS + (ROOT_FS - FLOOR_FS) * Math.exp(-k * depth)) * 10) / 10;
  }

  /* ---- measure & wrap text inside each box ---- */
  function measure(n, maxDepth) {
    const root = n.depth === 0;
    const fs = fontSize(n.depth, maxDepth);
    const fw = n.depth <= 1 ? 'bold' : 'normal';
    ctx.font = fw + ' ' + fs + 'px ' + FONT;
    const maxW = root ? 380 : Math.max(170, Math.round(fs * 9.5));
    const lines = []; let line = '';
    for (const w of n.text.split(/\s+/)) {
      const t = line ? line + ' ' + w : w;
      if (line && ctx.measureText(t).width > maxW) { lines.push(line); line = w; } else line = t;
    }
    if (line) lines.push(line);
    let tw = 0; lines.forEach(l => { tw = Math.max(tw, ctx.measureText(l).width); });
    n.fs = fs; n.fontWeight = fw; n.lines = lines; n.lh = Math.round(fs * 1.3);
    n.padY = Math.round(fs * (root ? 0.55 : 0.42));
    n.w = Math.ceil(tw * 1.03) + Math.round(fs * (root ? 1.8 : 1.3)) + 6;
    n.h = lines.length * n.lh + n.padY * 2;
    n.rad = Math.hypot(n.w, n.h) / 2;                 // bounding-circle radius of the box
  }

  /* ------------------------------------------------------------------
     Natural tree layout ("balloon" style), applied identically at EVERY level.
     Each subtree is a rigid body wrapped in a circle (centre on the branch axis).
     A node fans its children out around itself; every child's circle sits inside
     its own tangent cone from the parent, the cones never overlap, and the
     direction back to the grandparent is kept free.
     (This produces the collision-free "natural" geometry; compaction below then
     shortens the long spokes.)
     ------------------------------------------------------------------ */
  function build(n) {
    const kids = n.children;
    kids.forEach(build);
    if (!kids.length) { n.r = n.rad; n.a = 0; n.pl = []; return; }

    const k = kids.length, isRoot = !n.parent;
    const avail = isRoot ? TAU : Math.min(TAU - 2 * EXCL, MAXFAN);
    const gaps = isRoot ? k : k - 1;

    const Dmin = kids.map(c => n.rad + c.r + 2 * GAP + EDGE_MIN);
    const need = f => {
      let s = gaps * EPS;
      for (let i = 0; i < k; i++) s += 2 * Math.asin(Math.min(1, (kids[i].r + GAP) / (Dmin[i] * f)));
      return s;
    };
    let f = 1;
    if (need(1) > avail) {
      let hi = 2; while (need(hi) > avail && hi < 1e4) hi *= 2;
      let lo = hi / 2;
      for (let i = 0; i < 40; i++) { const mid = (lo + hi) / 2; if (need(mid) > avail) lo = mid; else hi = mid; }
      f = hi;
    }
    const D = Dmin.map(d => d * f);
    const al = kids.map((c, i) => Math.asin(Math.min(1, (c.r + GAP) / D[i])));
    const cones = al.reduce((s, a) => s + 2 * a, 0);

    let gap, cur;
    if (isRoot) {
      gap = (TAU - cones) / k;
      cur = -Math.PI / 2;
    } else {
      const T = Math.min(avail, Math.max(cones + gaps * EPS, Math.min(FAN, 0.9 * k)));
      gap = k > 1 ? (T - cones) / (k - 1) : 0;
      cur = -(cones + gap * (k - 1)) / 2;
    }
    n.pl = [];
    for (let i = 0; i < k; i++) {
      n.pl.push({ th: cur + al[i], D: D[i] });
      cur += 2 * al[i] + gap;
    }

    const C = n.pl.map(p => [p.D * Math.cos(p.th), p.D * Math.sin(p.th)]);
    const fa = a => {
      let m = Math.abs(a) + n.rad;
      for (let i = 0; i < k; i++) m = Math.max(m, Math.hypot(C[i][0] - a, C[i][1]) + kids[i].r);
      return m;
    };
    let lo = -n.rad, hi = lo;
    for (let i = 0; i < k; i++) hi = Math.max(hi, C[i][0] + kids[i].r);
    for (let i = 0; i < 60; i++) {
      const m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
      if (fa(m1) < fa(m2)) hi = m2; else lo = m1;
    }
    n.a = (lo + hi) / 2; n.r = fa(n.a);
  }

  function placeDown(n) {
    n.children.forEach((c, i) => {
      const p = n.pl[i], phi = n.ang + p.th, d = p.D - c.a;
      c.bx = n.bx + d * Math.cos(phi); c.by = n.by + d * Math.sin(phi); c.ang = phi;
      c.nx = c.bx - n.bx; c.ny = c.by - n.by;          // natural (uncompacted) parent→child offset
      placeDown(c);
    });
  }

  /* ---- default compaction: set each line's default vector (n.dx, n.dy = the "100%" line) ---- */
  function compact(nodes, p) {
    for (const n of nodes) {
      if (!n.parent) continue;
      const L = Math.hypot(n.nx, n.ny) || 1;
      let target = L > SOFT_L ? SOFT_L * Math.pow(L / SOFT_L, p) : L;
      const floor = Math.min(L, n.parent.rad + n.rad + EDGE_MIN);   // never pull a box onto its parent
      target = Math.max(target, floor);
      const s = target / L;
      n.dx = n.nx * s; n.dy = n.ny * s;
    }
  }

  /* ---- line-length controls ----
     For the line that ends at node n (parent → n), the multiplier is chosen in this order:
       1. n.ov            single-line override (set by selecting that box), 0 allowed
       2. lv[n.depth]     level multiplier, 0 allowed
       3. 1               default (compacted) layout
     L = overall stretch (>= 1) applied on top of everything.
     Nodes are in pre-order, so a parent is always positioned before its children. */
  function stretch(nodes, L, lv) {
    L = Math.max(1, L || 1);
    for (const n of nodes) {
      if (!n.parent) { n.ux = 0; n.uy = 0; }
      else {
        const m = n.ov != null ? n.ov : (lv && lv[n.depth] != null ? lv[n.depth] : 1);
        n.ux = n.parent.ux + n.dx * m;
        n.uy = n.parent.uy + n.dy * m;
      }
      n.x = n.ux * L; n.y = n.uy * L;
    }
  }

  function span(nodes) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    nodes.forEach(n => {
      x0 = Math.min(x0, n.x - n.w / 2); x1 = Math.max(x1, n.x + n.w / 2);
      y0 = Math.min(y0, n.y - n.h / 2); y1 = Math.max(y1, n.y + n.h / 2);
    });
    return Math.max(x1 - x0, y1 - y0);
  }

  function layout(root, L, lv) {
    const nodes = [];
    (function walk(n) { nodes.push(n); n.children.forEach(walk); })(root);
    let maxDepth = 0; nodes.forEach(n => { if (n.depth > maxDepth) maxDepth = n.depth; });
    nodes.forEach(n => measure(n, maxDepth));
    build(root);

    root.bx = 0; root.by = 0; root.ang = 0;
    placeDown(root);

    // Choose the gentlest compression that keeps the default map within MAX_SPAN (any topic, any size).
    let p = P_START;
    for (;;) {
      compact(nodes, p);
      stretch(nodes, 1, null);
      if (span(nodes) <= MAX_SPAN || p <= P_MIN) break;
      p = Math.max(P_MIN, p - P_STEP);
    }
    stretch(nodes, L, lv);
    return nodes;
  }

  function bounds(nodes, margin) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    nodes.forEach(n => {
      x0 = Math.min(x0, n.x - n.w / 2); x1 = Math.max(x1, n.x + n.w / 2);
      y0 = Math.min(y0, n.y - n.h / 2); y1 = Math.max(y1, n.y + n.h / 2);
    });
    return { x: x0 - margin, y: y0 - margin, w: x1 - x0 + 2 * margin, h: y1 - y0 + 2 * margin };
  }

  function borderPoint(a, b) {
    const dx = b.x - a.x, dy = b.y - a.y;
    const tx = dx ? (a.w / 2) / Math.abs(dx) : Infinity;
    const ty = dy ? (a.h / 2) / Math.abs(dy) : Infinity;
    const t = Math.min(tx, ty, 1);
    return { x: a.x + dx * t, y: a.y + dy * t };
  }

  g.MM = { layout, stretch, bounds, borderPoint, FONT };
})(window);
  </script>

  <script>
(function () {
  'use strict';
  const { TYPES, TEAL, parse } = window.NLP;
  const { layout, stretch, bounds, borderPoint, FONT } = window.MM;
  const NS = 'http://www.w3.org/2000/svg';
  const $ = id => document.getElementById(id);
  const svg = $('svg'), canvas = $('canvas'), input = $('input'), statusEl = $('status');
  const editor = $('editor'), typeSel = $('typeSel'), panel = $('panel');
  const lenEl = $('len'), lenVal = $('lenVal'), themeBtn = $('theme');
  const levelsBody = $('levelsBody');
  const lineRow = $('lineRow'), lineLen = $('lineLen'), lineVal = $('lineVal'), lineReset = $('lineReset');

  let nodes = [], world = null, editing = null;
  let selected = null, nodeEls = new Map(), edgeEls = new Map();
  let lenK = (+lenEl.value || 100) / 100;
  let levels = {};                       // per-level line multipliers (absent = default layout = 100%)
  let dark = false;
  const view = { x: 0, y: 0, k: 1 };

  const SAMPLE = `Photosynthesis

Photosynthesis is the process by which green plants convert light energy into chemical energy. It takes place in the chloroplasts of leaf cells, usually at around 25 °C.

Inputs and Outputs
- Inputs: carbon dioxide, water, and sunlight
- Outputs: glucose and oxygen
- Chlorophyll: the green pigment that absorbs light

History
Jan Ingenhousz discovered in 1779 that light is essential for plants. Dr. Melvin Calvin later mapped the cycle and won the Nobel Prize in 1961. As he explained, "the path of carbon in photosynthesis was traced with radioactive tracers."`;

  /* ---------- svg helper ---------- */
  function S(tag, attrs, parent) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }

  /* ---------- colour helpers ---------- */
  function lum(hex) {
    const c = [1, 3, 5].map(i => parseInt(hex.substr(i, 2), 16) / 255)
      .map(v => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  function textColor(colors) {
    const w = Math.min(...colors.map(c => contrast('#ffffff', c)));
    const d = Math.min(...colors.map(c => contrast('#111111', c)));
    return w >= d ? '#ffffff' : '#111111';
  }
  function mix(h1, h2, t) {
    const a = [1, 3, 5].map(i => parseInt(h1.substr(i, 2), 16));
    const b = [1, 3, 5].map(i => parseInt(h2.substr(i, 2), 16));
    return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, '0')).join('');
  }
  const isGrad = n => n.isMember && n.type !== 'member';
  const PAGE_BG = () => (dark ? '#12161c' : '#ffffff');

  /* ---------- draw the graph into a <g> (used by screen AND pdf) ---------- */
  function drawGraph(list, g, defs, pre) {
    const eg = S('g', {}, g), ng = S('g', {}, g);
    const els = { nodes: new Map(), edges: new Map() };
    const STEPS = 10;

    for (const n of list) {
      const p = n.parent; if (!p) continue;
      const a = borderPoint(p, n), b = borderPoint(n, p), col = TYPES[n.type].color;
      const w = Math.max(1.8, 4.2 - 0.6 * n.depth);
      const grp = S('g', { 'class': 'edge' }, eg);
      if (isGrad(n)) {
        for (let i = 0; i < STEPS; i++) {
          const t0 = i / STEPS, t1 = (i + 1) / STEPS;
          S('path', {
            d: 'M' + (a.x + (b.x - a.x) * t0) + ' ' + (a.y + (b.y - a.y) * t0) +
               'L' + (a.x + (b.x - a.x) * t1) + ' ' + (a.y + (b.y - a.y) * t1),
            fill: 'none', stroke: mix(TEAL, col, (i + 0.5) / STEPS),
            'stroke-width': w, 'stroke-linecap': 'round'
          }, grp);
        }
      } else {
        S('path', { d: 'M' + a.x + ' ' + a.y + 'L' + b.x + ' ' + b.y, fill: 'none', stroke: col, 'stroke-width': w, 'stroke-linecap': 'round' }, grp);
      }
      els.edges.set(n.id, grp);
    }

    for (const n of list) {
      const grp = S('g', { 'data-id': n.id, 'class': 'node', style: 'cursor:pointer' }, ng);
      const col = TYPES[n.type].color;
      let fill = col, tc;
      if (isGrad(n) && n.parent) {
        const id = pre + 'ng' + n.id;
        let ux = n.parent.x - n.x, uy = n.parent.y - n.y; const L = Math.hypot(ux, uy) || 1; ux /= L; uy /= L;
        const lg = S('linearGradient', { id, x1: 0.5 + 0.5 * ux, y1: 0.5 + 0.5 * uy, x2: 0.5 - 0.5 * ux, y2: 0.5 - 0.5 * uy }, defs);
        S('stop', { offset: '0', 'stop-color': TEAL }, lg);
        S('stop', { offset: '1', 'stop-color': col }, lg);
        fill = 'url(#' + id + ')';
        tc = textColor([TEAL, col]);
      } else tc = textColor([col]);

      S('rect', {
        x: n.x - n.w / 2, y: n.y - n.h / 2, width: n.w, height: n.h, rx: n.depth === 0 ? 18 : 10,
        fill, stroke: dark ? '#ffffff' : '#000000', 'stroke-opacity': dark ? 0.22 : 0.12, 'stroke-width': 1
      }, grp);
      n.lines.forEach((ln, i) => {
        const t = S('text', {
          x: n.x, y: n.y - n.h / 2 + n.padY + i * n.lh + n.lh / 2 + n.fs * 0.35,
          'text-anchor': 'middle', 'font-family': FONT, 'font-size': n.fs, 'font-weight': n.fontWeight, fill: tc
        }, grp);
        t.textContent = ln;
      });
      els.nodes.set(n.id, grp);
    }
    return els;
  }

  function render() {
    svg.innerHTML = '';
    const defs = S('defs', {}, svg);
    world = S('g', {}, svg);
    const els = drawGraph(nodes, world, defs, 's');
    nodeEls = els.nodes; edgeEls = els.edges;
    applyView();
    applySelection();
  }

  /* ---------- highlight + domino ripple ---------- */
  function applySelection() {
    const keep = new Set();
    if (selected) (function w(m) { keep.add(m.id); m.children.forEach(w); })(selected);
    nodeEls.forEach((el, id) => el.classList.toggle('dim', !!selected && !keep.has(id)));
    edgeEls.forEach((el, id) => el.classList.toggle('dim', !!selected && (!keep.has(id) || id === selected.id)));
  }
  function ripple(n) {
    const base = n.depth;
    (function walk(m) {
      const el = nodeEls.get(m.id);
      if (el && el.animate) {
        el.animate(
          [{ transform: 'scale(1)' }, { transform: 'scale(1.22)', offset: 0.4 }, { transform: 'scale(1)' }],
          { duration: 520, delay: (m.depth - base) * 130, easing: 'ease-in-out', iterations: 1 }
        );
      }
      m.children.forEach(walk);
    })(n);
  }
  function select(n, animate) {
    selected = n;
    applySelection();
    if (n && animate) ripple(n);
  }

  /* ---------- infinite canvas ---------- */
  function applyView() {
    if (world) world.setAttribute('transform', `translate(${view.x} ${view.y}) scale(${view.k})`);
    const s = 28 * view.k;
    canvas.style.backgroundSize = s + 'px ' + s + 'px';
    canvas.style.backgroundPosition = view.x + 'px ' + view.y + 'px';
  }
  function zoomAt(px, py, f) {
    const k = Math.min(4, Math.max(0.01, view.k * f)), r = k / view.k;
    view.x = px - (px - view.x) * r; view.y = py - (py - view.y) * r; view.k = k; applyView();
  }
  function fit() {
    if (!nodes.length) return;
    const b = bounds(nodes, 60), r = canvas.getBoundingClientRect();
    view.k = Math.max(0.01, Math.min(r.width / b.w, r.height / b.h, 1.5));
    view.x = r.width / 2 - (b.x + b.w / 2) * view.k;
    view.y = r.height / 2 - (b.y + b.h / 2) * view.k;
    applyView();
  }

  const ptrs = new Map(); let drag = null, pinch = null;
  const rel = e => { const r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };

  canvas.addEventListener('pointerdown', e => {
    if (e.target.closest('#toolbar') || e.target.closest('#editor')) return;
    canvas.setPointerCapture(e.pointerId);
    ptrs.set(e.pointerId, rel(e));
    if (ptrs.size === 1) drag = { sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y, moved: false, target: e.target };
    else if (ptrs.size === 2) {
      drag = null;
      const [a, b] = [...ptrs.values()], m = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), k: view.k, wx: (m.x - view.x) / view.k, wy: (m.y - view.y) / view.k };
    }
  });
  canvas.addEventListener('pointermove', e => {
    if (!ptrs.has(e.pointerId)) return;
    ptrs.set(e.pointerId, rel(e));
    if (ptrs.size === 2 && pinch) {
      const [a, b] = [...ptrs.values()], m = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      view.k = Math.min(4, Math.max(0.01, pinch.k * Math.hypot(a.x - b.x, a.y - b.y) / pinch.d));
      view.x = m.x - pinch.wx * view.k; view.y = m.y - pinch.wy * view.k; applyView();
    } else if (drag) {
      const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
      if (Math.hypot(dx, dy) > 4) drag.moved = true;
      if (drag.moved) { view.x = drag.vx + dx; view.y = drag.vy + dy; applyView(); }
    }
  });
  const endPtr = e => {
    if (drag && !drag.moved && ptrs.size === 1) {
      const el = drag.target.closest && drag.target.closest('[data-id]');
      if (el) {
        const n = nodes.find(n => n.id === +el.getAttribute('data-id'));
        openEditor(n, e);
        select(n, true);
      } else { editor.hidden = true; select(null, false); }
    }
    ptrs.delete(e.pointerId); drag = null; if (ptrs.size < 2) pinch = null;
  };
  canvas.addEventListener('pointerup', endPtr);
  canvas.addEventListener('pointercancel', endPtr);
  canvas.addEventListener('wheel', e => {
    e.preventDefault();
    const p = rel(e);
    zoomAt(p.x, p.y, Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)));
  }, { passive: false });

  /* ---------- click a box → change its type / its own line length ---------- */
  Object.keys(TYPES).forEach(k => {
    const o = document.createElement('option'); o.value = k; o.textContent = TYPES[k].label; typeSel.appendChild(o);
  });

  const effMul = n => (n.ov != null ? n.ov : (levels[n.depth] != null ? levels[n.depth] : 1));

  function syncLineUI(n) {
    const has = !!(n && n.parent);
    lineRow.hidden = !has;
    if (!has) return;
    const v = Math.round(effMul(n) * 100);
    lineLen.value = v; lineVal.textContent = v + '%';
    lineReset.disabled = n.ov == null;
  }

  function openEditor(n, e) {
    if (!n) return;
    editing = n; typeSel.value = n.type;
    syncLineUI(n);
    const p = rel(e), r = canvas.getBoundingClientRect();
    editor.hidden = false;
    editor.style.left = Math.max(4, Math.min(p.x + 8, r.width - 230)) + 'px';
    editor.style.top = Math.max(4, Math.min(p.y + 8, r.height - 140)) + 'px';
  }
  typeSel.addEventListener('change', () => { if (editing) { editing.type = typeSel.value; render(); } });

  /* ---------- line-length sliders with a locked view anchor ---------- */
  let anchor = null, raf = 0;
  function grabAnchor() {
    if (!nodes.length) return;
    const r = canvas.getBoundingClientRect(), cx = r.width / 2, cy = r.height / 2;
    let best = null, bd = Infinity, bsx = 0, bsy = 0;
    for (const n of nodes) {
      const sx = n.x * view.k + view.x, sy = n.y * view.k + view.y;
      const d = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy);
      if (d < bd) { bd = d; best = n; bsx = sx; bsy = sy; }
    }
    anchor = best ? { n: best, sx: bsx, sy: bsy } : null;
  }
  const dropAnchor = () => { anchor = null; };
  function bindLock(el) {
    el.addEventListener('pointerdown', grabAnchor);
    el.addEventListener('keydown', () => { if (!anchor) grabAnchor(); });
    ['change', 'pointerup', 'pointercancel', 'blur'].forEach(ev => el.addEventListener(ev, dropAnchor));
  }
  function relayout(keepEditor) {
    if (!nodes.length) return;
    if (!anchor) grabAnchor();
    stretch(nodes, lenK, levels);
    if (anchor) { view.x = anchor.sx - anchor.n.x * view.k; view.y = anchor.sy - anchor.n.y * view.k; }
    if (!keepEditor) editor.hidden = true;
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; render(); });
  }

  bindLock(lenEl);
  lenEl.addEventListener('input', () => {
    lenK = (+lenEl.value) / 100;
    lenVal.textContent = Math.round(lenK * 100) + '%';
    relayout();
  });

  bindLock(lineLen);
  lineLen.addEventListener('input', () => {
    if (!editing || !editing.parent) return;
    editing.ov = (+lineLen.value) / 100;
    lineVal.textContent = lineLen.value + '%';
    lineReset.disabled = false;
    relayout(true);
  });
  lineReset.addEventListener('click', () => {
    if (!editing) return;
    editing.ov = undefined;
    syncLineUI(editing);
    grabAnchor(); relayout(true); dropAnchor();
  });

  function buildLevelControls() {
    levelsBody.innerHTML = '';
    let maxD = 0; nodes.forEach(n => { if (n.depth > maxD) maxD = n.depth; });
    if (maxD < 1) { levelsBody.innerHTML = '<small>No branches yet.</small>'; return; }

    const hint = document.createElement('small');
    hint.textContent = 'Each slider changes only the lines that end at that level. 100% = the default (auto-compacted) layout; 0% pulls those boxes onto their parent, so overlaps are expected near 0. Tap a box to override just its own line.';
    levelsBody.appendChild(hint);

    const sliders = [];
    for (let d = 1; d <= maxD; d++) {
      const wrap = document.createElement('div'); wrap.className = 'lvl';
      const lab = document.createElement('label');
      const name = document.createElement('span');
      name.textContent = d === 1 ? 'Level 1 · center → main branches' : 'Level ' + d + ' · level ' + (d - 1) + ' → ' + d;
      const val = document.createElement('b'); val.textContent = '100%';
      lab.append(name, val);
      const sl = document.createElement('input');
      sl.type = 'range'; sl.min = 0; sl.max = 300; sl.step = 1; sl.value = 100;
      sl.addEventListener('input', () => {
        levels[d] = (+sl.value) / 100;
        val.textContent = sl.value + '%';
        relayout();
      });
      bindLock(sl);
      wrap.append(lab, sl);
      levelsBody.appendChild(wrap);
      sliders.push({ d, sl, val });
    }
    const rs = document.createElement('button');
    rs.className = 'reset'; rs.textContent = 'Reset levels';
    rs.onclick = () => {
      levels = {};
      sliders.forEach(s => { s.sl.value = 100; s.val.textContent = '100%'; });
      grabAnchor(); relayout(); dropAnchor();
    };
    levelsBody.appendChild(rs);

    const cl = document.createElement('button');
    cl.className = 'reset'; cl.textContent = 'Clear single-line overrides';
    cl.onclick = () => {
      nodes.forEach(n => { n.ov = undefined; });
      grabAnchor(); relayout(); dropAnchor();
    };
    levelsBody.appendChild(cl);
  }

  /* ---------- dark mode ---------- */
  function setTheme(d, save) {
    dark = d;
    document.body.classList.toggle('dark', dark);
    themeBtn.textContent = dark ? '☀' : '☾';
    if (save) { try { localStorage.setItem('mm-theme', dark ? 'dark' : 'light'); } catch (e) { /* ignore */ } }
    if (nodes.length) render();
  }
  themeBtn.onclick = () => setTheme(!dark, true);
  (function initTheme() {
    let t = null;
    try { t = localStorage.getItem('mm-theme'); } catch (e) { /* ignore */ }
    const pref = t ? t === 'dark' : !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    setTheme(pref, false);
  })();

  /* ---------- generate ---------- */
  function generate() {
    try {
      const root = parse(input.value);
      if (!root || !root.children.length) { statusEl.textContent = 'Nothing to map — add a few sentences or bullet points.'; return; }
      statusEl.textContent = 'Building…';
      setTimeout(() => {
        try {
          levels = {};
          nodes = layout(root, lenK, levels);
          editor.hidden = true; editing = null;
          selected = null;
          buildLevelControls();
          render(); fit();
          statusEl.textContent = nodes.length + ' boxes · drag to pan · scroll/pinch to zoom · tap a box to highlight its branch, change its type or set its own line length (tap empty space to clear)';
          panel.classList.remove('open');
        } catch (err) { console.error(err); statusEl.textContent = 'Error: ' + err.message; }
      }, 20);
    } catch (err) { console.error(err); statusEl.textContent = 'Error: ' + err.message; }
  }

  /* ---------- PDF (vector, cropped to content, current line lengths + current theme, never dimmed) ---------- */
  async function downloadPDF() {
    if (!nodes.length) { statusEl.textContent = 'Generate a map first.'; return; }
    try {
      const { jsPDF } = window.jspdf;
      const b = bounds(nodes, 40);
      const W = Math.ceil(b.w), H = Math.ceil(b.h);
      const s = Math.min(1, 19000 / Math.max(W, H));          // PDF page-size limit

      const holder = document.createElement('div');
      holder.style.cssText = 'position:fixed;left:-99999px;top:0;opacity:0;pointer-events:none';
      document.body.appendChild(holder);
      const out = S('svg', { xmlns: NS, width: W, height: H, viewBox: `0 0 ${W} ${H}` }, holder);
      const defs = S('defs', {}, out);
      S('rect', { x: 0, y: 0, width: W, height: H, fill: PAGE_BG() }, out);
      const g = S('g', { transform: `translate(${-b.x} ${-b.y})` }, out);
      drawGraph(nodes, g, defs, 'p');

      const pdf = new jsPDF({ orientation: W >= H ? 'l' : 'p', unit: 'px', format: [W * s, H * s], hotfixes: ['px_scaling'] });
      const opts = { x: 0, y: 0, width: W * s, height: H * s };
      if (typeof pdf.svg === 'function') await pdf.svg(out, opts);
      else await (window.svg2pdf.svg2pdf || window.svg2pdf)(out, pdf, opts);
      pdf.save((nodes[0].text.replace(/[^\w\-]+/g, '_') || 'mindmap') + '_mindmap' + (dark ? '_dark' : '') + '.pdf');
      holder.remove();
    } catch (err) { console.error(err); statusEl.textContent = 'PDF error: ' + err.message; }
  }

  /* ---------- legend & wiring ---------- */
  const lg = $('legendBody');
  Object.keys(TYPES).forEach(k => {
    lg.insertAdjacentHTML('beforeend', `<div><span class="sw" style="background:${TYPES[k].color}"></span>${TYPES[k].label} <small>${TYPES[k].color}</small></div>`);
  });
  lg.insertAdjacentHTML('beforeend', `<div><span class="sw" style="background:linear-gradient(90deg,${TEAL},#9B5DE5)"></span>Group member with a type (teal → type colour)</div>`);

  $('gen').onclick = generate;
  $('sample').onclick = () => { input.value = SAMPLE; generate(); };
  $('fit').onclick = fit;
  $('zin').onclick = () => { const r = canvas.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 1.3); };
  $('zout').onclick = () => { const r = canvas.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 1 / 1.3); };
  $('pdf').onclick = downloadPDF;
  $('menuBtn').onclick = () => panel.classList.toggle('open');
  $('file').onchange = e => {
    const f = e.target.files[0]; if (!f) return;
    const rd = new FileReader();
    rd.onload = () => { input.value = rd.result; generate(); };
    rd.readAsText(f);
  };
  window.addEventListener('resize', () => { if (nodes.length) applyView(); });

  lenVal.textContent = Math.round(lenK * 100) + '%';
  input.value = SAMPLE;
  generate();
})();
  </script>
</body>
</html>
"""#


