import Foundation

private func between(_ s: String, _ a: String, _ b: String) -> String {
    guard let r1 = s.range(of: a),
          let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return "" }
    return String(s[r1.upperBound..<r2.lowerBound])
}

let extraCSS = #"""
#menuBtn{display:inline-block}
body.collapsed #panel{display:none}
.node text{pointer-events:none}
#svg *{-webkit-touch-callout:none}
.head{display:flex;justify-content:space-between;align-items:center}
.sec{border:1px solid var(--line);border-radius:8px;padding:8px 10px;font-size:13px}
.sec>summary{cursor:pointer;font-weight:600}
.sec #input{width:100%;margin:8px 0}
.sec .knob{margin-top:8px}
.sec .levels{margin-top:8px}
#libName,#dlgName{width:100%;margin:8px 0;padding:8px;font-size:14px;border:1px solid var(--fieldb);border-radius:8px;background:var(--field);color:var(--fg)}
#libList{margin-top:8px}
.lib-item{display:flex;gap:6px;align-items:center;padding:4px 0}
.lib-item span{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#nodebar{position:absolute;z-index:4;display:flex;flex-wrap:wrap;justify-content:center;gap:6px;max-width:min(240px,calc(100% - 8px))
;background:var(--pop);border:1px solid var(--fieldb);border-radius:22px;padding:4px;box-shadow:0 4px 14px rgba(0,0,0,.28)}
#nodebar[hidden]{display:none}
#nodebar button{width:38px;height:38px;border-radius:50%;padding:0;font-size:18px;display:flex;align-items:center;justify-content:center}
#nodebar button.fx{background:var(--field)}
#nodebar button:disabled{opacity:.35}
#nodebar button.arm{background:#E63946;border-color:#E63946;color:#fff}
#nbDot{display:block;width:20px;height:20px;border-radius:50%;border:2px solid #fff;box-shadow:0 0 0 1px rgba(0,0,0,.4)}
#unhide{position:absolute;z-index:4;padding:6px 10px;font-size:13px;box-shadow:0 2px 8px rgba(0,0,0,.25)}
#unhide[hidden]{display:none}
#nodeEdit{position:absolute;z-index:6;font:16px/1.25 Helvetica,Arial,sans-serif;text-align:center;border:2px solid #2A9D8F;border-radius:10px;background:var(--field);color:var(--fg);resize:none;padding:6px}
#nodeEdit[hidden]{display:none}
#masterTape{position:absolute;left:14px;bottom:14px;width:76px;height:76px;border-radius:50%;font-size:38px;z-index:3;padding:0;background:#F4E7B0;border:2px solid #C9B26B;box-shadow:0 3px 10px rgba(0,0,0,.3)}
#masterTape.on{background:#E9C46A;outline:3px solid #2A9D8F}
#masterTape{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;touch-action:none}
#masterTape.idle{opacity:.55}
#masterTape:active{transform:scale(.94)}
#dlg{position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;z-index:50}
#dlg[hidden]{display:none}
#dlg .card{background:var(--pop);color:var(--fg);padding:16px;border-radius:12px;width:min(92vw,340px);box-shadow:0 10px 30px rgba(0,0,0,.4)}

/* export-as-text window */
#expDlg{position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;z-index:60}
#expDlg[hidden]{display:none}
#expDlg .card{background:var(--pop);color:var(--fg);padding:16px;border-radius:12px;width:min(94vw,520px);box-shadow:0 10px 30px rgba(0,0,0,.4);display:flex;flex-direction:column;gap:10px}
#expText{width:100%;height:min(52vh,420px);resize:none;border:1px solid var(--fieldb);background:var(--field);color:var(--fg);border-radius:8px;padding:10px;font:13px/1.45 ui-monospace,Menlo,Consolas,monospace}
#expDlg .card{max-height:92vh;overflow:auto}
#expDlg .tg{display:flex;align-items:flex-start;gap:8px;font-size:13px;line-height:1.3}
#expDlg .tg input{width:22px;height:22px;flex:none;accent-color:#2A9D8F;margin:0}
#expDlg select{font-size:14px;padding:6px;background:var(--field);color:var(--fg);border:1px solid var(--fieldb);border-radius:8px}
#expDlg small{color:var(--muted);font-size:11px;line-height:1.3}

/* slider rows with − / + nudge buttons (1 unit per tap) */
.srow{display:flex;align-items:center;gap:6px}
.srow input[type=range]{flex:1;min-width:0;width:auto}
.srow button{flex:none;padding:2px 11px;font-size:18px;line-height:1.2}


/* canvas-only zoom: the page itself never scrolls or zooms, panels and overlays stay put */
html,body{overflow:hidden;overscroll-behavior:none;-webkit-text-size-adjust:100%;touch-action:manipulation}
#panel{overscroll-behavior:contain}

/* line-length knob: vertical, on the far right edge, shown while a box with a line is chosen */
#rpanel{--vh:clamp(150px,34vh,300px);position:absolute;right:8px;left:auto;top:50%;transform:translateY(-50%);z-index:4;width:116px;background:var(--pop);color:var(--fg);border:1px solid var(--fieldb);border-radius:14px;padding:10px 8px;box-shadow:0 6px 20px rgba(0,0,0,.28);display:flex;flex-direction:column;align-items:center;gap:6px;font-size:13px}
#rpanel[hidden]{display:none}
.rhead{display:flex;flex-direction:column;align-items:center;width:100%;line-height:1.2}
#rname{color:var(--muted);font-size:11px;max-width:100px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rcol{display:flex;flex-direction:column;align-items:center;gap:6px;width:100%}
.rcol[hidden]{display:none}
#lineVal{font-size:24px;font-weight:700;text-align:center;display:block}
#vwrap{position:relative;width:96px;height:var(--vh)}
#vticks{position:absolute;left:0;top:0;bottom:0;width:44px}
#vticks i{position:absolute;right:0;width:8px;height:1.5px;background:var(--muted);bottom:calc(17px + (var(--vh) - 34px) * var(--f) - 1px)}
#vticks i.maj{width:14px}
#vticks i b{position:absolute;right:20px;top:-7px;font-size:10px;font-style:normal;font-weight:600;color:var(--muted)}
#rpanel input[type=range]{-webkit-appearance:none;appearance:none;background:transparent;margin:0}
#lineLen{position:absolute;left:68px;top:50%;width:var(--vh);height:44px;transform:translate(-50%,-50%) rotate(-90deg)}
#rpanel input[type=range]::-webkit-slider-runnable-track{height:10px;border-radius:5px;background:var(--line)}
#rpanel input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;width:34px;height:34px;border-radius:50%;background:#2A9D8F;border:3px solid #fff;margin-top:-12px;box-shadow:0 1px 5px rgba(0,0,0,.45)}
button.rstep{width:100%;height:42px;font-size:24px;padding:0}
button.rbig{height:40px;font-size:13px;width:100%;padding:0}

/* no text selection on toolbar buttons (theme toggle etc.) */
#toolbar button,.rot,#nodebar button{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent;touch-action:manipulation}
#theme{-webkit-user-select:none;user-select:none}

/* middle tier of the selection hierarchy (nearest siblings + deeper levels of the chosen branch) */
.semi{opacity:.5}

/* CCW / CW sibling reorder, placed around the big tape button */
.rot{position:absolute;z-index:3;width:56px;height:56px;border-radius:50%;padding:0;font-size:30px;line-height:1;display:flex;align-items:center;justify-content:center;background:var(--pop);border:2px solid var(--fieldb);box-shadow:0 3px 10px rgba(0,0,0,.3)}
.rot:active:not(:disabled){transform:scale(.94)}
#ccwBtn{left:24px;bottom:100px}
#cwBtn{left:100px;bottom:24px}
"""#

let bodyHTML = #"""
<aside id="panel">
  <div class="head"><h1>Text → Mind Map</h1><button id="panelHide" title="Hide panel">‹</button></div>
  <details class="sec" open>
    <summary>Text &amp; upload</summary>
    <textarea id="input" spellcheck="false" placeholder="Paste or type your text here…"></textarea>
    <div class="row">
      <button id="gen" class="primary">Generate</button>
      <label class="btn">Open file<input type="file" id="file" accept=".txt,.md,.text" hidden></label>
      <button id="sample">Sample</button>
    </div>
  </details>
  <details class="sec" open>
    <summary>Line length</summary>
    <div class="knob">
      <label for="len">Line length (all levels) <b id="lenVal">120%</b></label>
      <div class="srow"><button id="lenMinus" title="1% shorter">−</button><input type="range" id="len" min="100" max="300" step="1" value="100"><button id="lenPlus" title="1% longer">+</button></div>
      <small>100% is the tightest default layout. Higher values stretch every line. Boxes never get closer than 0.25 grid squares.</small>
    </div>
    <details class="levels" id="levelsBox">
      <summary>Line length by level</summary>
      <div id="levelsBody"><small>Generate a map first.</small></div>
    </details>
  </details>
  <details class="sec" open>
    <summary>Library</summary>
    <input id="libName" placeholder="Name this mind map">
    <div class="row">
      <button id="libSave" class="primary">Save to library</button>
      <button id="libNew">New map</button>
            <button id="libExp">Export / import</button>
      <label class="btn">Import file<input type="file" id="impFile" hidden></label>

    </div>
    <div id="libList"></div>
  </details>
  <div id="status"></div>
  <details class="sec" open>
    <summary>Colour legend</summary>
    <div id="legendBody"></div>
  </details>
</aside>

<main id="canvas">
  <svg id="svg" xmlns="http://www.w3.org/2000/svg"></svg>
  <div id="toolbar">
    <button id="theme" title="Toggle dark mode">☾</button>
    <button id="undoBtn" title="Undo" disabled>↶</button>
    <button id="redoBtn" title="Redo" disabled>↷</button>
    <button id="menuBtn">☰</button>
    <button id="zin">+</button>
    <button id="zout">−</button>
    <button id="fit">Fit</button>
    <button id="pdf" class="primary">PDF</button>
  </div>
  <div id="nodebar" hidden>
    <button id="nbType" title="Category and colour"><span id="nbDot"></span></button>
    <button id="nbAdd" title="Add child box">＋</button>
    <button id="nbDup" title="Duplicate: tap = this box alone, snapped out · double-tap = whole branch, collapsed">⧉</button>
    <button id="nbDel" title="Delete this box and its sub-branches">🗑</button>
    <button id="nbTape" title="Cover / uncover this box">🩹</button>
    <button id="nbFixO" class="fx" title="Fix overlaps in this branch">🧹</button>
    <button id="nbFixL" class="fx" title="Fix line lengths in this branch">📏</button>
    <button id="nbFixD" class="fx" title="Fix directions in this branch">🧭</button>
    <button id="nbRev" class="fx" title="Re-vector: re-aligns the sub-branches so the first and last sandwich this box's own line (your order is kept)">🎡</button>
  </div>
  <button id="unhide" hidden></button>
  <div id="editor" hidden>
    <div class="erow">Type: <select id="typeSel"></select></div>
  </div>
  <aside id="rpanel" hidden>
    <div class="rhead"><b>Line</b><span id="rname"></span></div>
    <div id="lineRow" class="rcol">
      <span id="lineVal">100%</span>
      <button id="linePlus" class="rstep" title="Longer (1 unit)">+</button>
      <div id="vwrap">
        <div id="vticks">
          <i class="maj" style="--f:1"><b>400</b></i>
          <i style="--f:.875"></i>
          <i class="maj" style="--f:.75"><b>300</b></i>
          <i style="--f:.625"></i>
          <i class="maj" style="--f:.5"><b>200</b></i>
          <i style="--f:.375"></i>
          <i class="maj" style="--f:.25"><b>100</b></i>
          <i style="--f:.125"></i>
          <i class="maj" style="--f:0"><b>0</b></i>
        </div>
        <input type="range" id="lineLen" min="0" max="400" step="1" value="100">
      </div>
      <button id="lineMinus" class="rstep" title="Shorter (1 unit)">−</button>
      <button id="lineReset" class="rbig">Reset</button>
    </div>
  </aside>
  <textarea id="nodeEdit" hidden rows="1"></textarea>
  <button id="masterTape" title="Tap: cover/uncover the selected box · Hold: cover/uncover everything">🩹</button>
  <button id="ccwBtn" class="rot" title="Counter-clockwise: swap this branch with its previous sibling" disabled>↺</button>
  <button id="cwBtn" class="rot" title="Clockwise: swap this branch with its next sibling" disabled>↻</button>
</main>


<div id="dlg" hidden>
  <div class="card">
    <b>Save this mind map?</b>
    <input id="dlgName" placeholder="Name">
    <div class="row">
      <button id="dlgSave" class="primary">Save</button>
      <button id="dlgNo">Don't save</button>
      <button id="dlgCancel">Cancel</button>
    </div>
  </div>
</div>

<div id="expDlg" hidden>
  <div class="card">
    <b>Export / import</b>
    <label class="tg"><input type="checkbox" id="expMeta"><span>Include layout and metadata (positions, line lengths, directions)</span></label>
    <textarea id="expText" spellcheck="false"></textarea>
    <small id="expHint"></small>
    <div class="row">
      <button id="expCopy" class="primary">Copy</button>
      <button id="expUse">Put in text box</button>
      <button id="expImp">Import this text</button>
      <button id="expClose">Close</button>
    </div>
    <div class="row">
      <button id="expFile">Save file</button>
      <select id="expExt"><option value=".mindmap">.mindmap</option><option value=".json">.json</option></select>
      <label class="btn">Import file<input type="file" id="expImpFile" hidden></label>
    </div>
    <small>The saved file also holds your drawings. The text never does.</small>
  </div>
</div>

"""#
let fullHTML: String = {
    let oldCSS = between(pageHTML, "<style>", "</style>")
    let nlp = "(function (global) {" + between(pageHTML, "(function (global) {", "})(window);") + "})(window);"
    let lay = "(function (g) {" + between(pageHTML, "(function (g) {", "})(window);") + "})(window);"
    return """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<title>Text → Mind Map</title>
<style>
\(oldCSS)
\(extraCSS)
</style>
</head>
<body>
<script>
window.addEventListener('error', function (e) {
  var b = document.getElementById('errBar');
  if (!b) { b = document.createElement('div'); b.id = 'errBar'; b.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:99999;background:#E63946;color:#fff;font:12px/1.35 Helvetica,Arial,sans-serif;padding:8px 10px;white-space:pre-wrap;max-height:40vh;overflow:auto'; document.body.appendChild(b); }
  b.textContent += '⚠ ' + e.message + '\n';
});
</script>
\(bodyHTML)

<script src="https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/svg2pdf.js@2.2.4/dist/svg2pdf.umd.min.js"></script>
<script>
\(nlp)
</script>
<script>
\(lay)
</script>
<script>
\(appJS)
</script>


<script>
\(paintJS)
</script>
</body>
</html>
"""
}()






