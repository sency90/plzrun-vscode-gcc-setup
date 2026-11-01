#!/usr/bin/env node
// Check keybindings with the when-clause parser and evaluator of the installed VSCode (tests only).
//
//   node vscode_when.js <kb.json> <shift-esc.tsv> <states.json> <folder>
//
// The parser is cut out of VSCode's own workbench bundle at run time (by the shape of the code,
// not by the minified names, which change between versions) and run in a sandbox where every
// outside name is an empty stand-in. Then:
//   1. every "when" in kb.json must parse with no error (VSCode would ignore a rule that does not)
//   2. for each state in states.json, using VSCode's evaluate():
//      inside <folder>: Shift+Esc must run the same command as Esc (a later matching rule wins)
//      outside it: no vsc rule may match
// Exit 3 = VSCode not found (the caller skips the check).
const fs = require("fs"), vm = require("vm"), path = require("path");

const BUNDLES = [
  process.env.VSCODE_WORKBENCH_JS,
  "/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js",
  "/usr/share/code/resources/app/out/vs/workbench/workbench.desktop.main.js",
].filter(Boolean);

function loadParser() {
  const file = BUNDLES.find((p) => fs.existsSync(p));
  if (!file) return null;
  const s = fs.readFileSync(file, "utf8");
  const scan = s.search(/=class \w+\{constructor\(\)\{this\._input="";this\._start=0;this\._current=0;this\._tokens=\[\];this\._errors=\[\];/);
  if (scan < 0) throw new Error("when-clause scanner not found in " + file);
  // 시작: 스캐너 앞의 오류 문구 도우미 함수 (function X(...s){switch(s.length){case 1:return ...)
  const head = s.lastIndexOf("function ", scan);
  const helper = s.slice(Math.max(0, scan - 4000), scan).search(/function \w+\(\.\.\.\w\)\{switch\(\w\.length\)\{case 1:return/);
  const start = helper < 0 ? head : Math.max(0, scan - 4000) + helper;
  // 끝: RawContextKey 클래스 바로 앞 (",X=class s extends Y{static{this._info=[]}")
  const tail = s.slice(scan).search(/,\w+=class \w+ extends \w+\{static\{this\._info=\[\]\}/);
  if (tail < 0) throw new Error("end of the context key classes not found");
  const code = s.slice(start, scan + tail) + ";";
  const m = code.match(/static\{this\._parser=new (\w+)\(\{regexParsingWithErrorRecovery:!1\}\)\}static deserialize/);
  if (!m) throw new Error("when-clause parser class not found");
  let version = "?";
  try { version = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "../../../package.json"), "utf8")).version; } catch (e) {}
  const real = { console, Object, Array, Map, Set, RegExp, Error, String, Number, Math, JSON, Symbol, Boolean, TypeError };
  const stub = new Proxy(function () { return stub; }, { get: (t, p) => (p === Symbol.toPrimitive ? () => "" : stub) });
  let ctx;
  const g = new Proxy(real, {
    has: (t, p) => !(typeof p === "string" && ctx && Object.prototype.hasOwnProperty.call(ctx, p)),
    get: (t, p) => (p in t ? t[p] : p === Symbol.unscopables ? undefined : stub),
    set: (t, p, v) => { t[p] = v; return true; },
  });
  ctx = vm.createContext({ g });
  vm.runInContext("with (g) {" + code + "\n g.__Parser = " + m[1] + "; }", ctx);
  return { Parser: real.__Parser, version, file };
}

function stripComments(t) {
  let out = "", i = 0;
  while (i < t.length) {
    const c = t[i];
    if (c === '"') {
      let j = i + 1;
      while (j < t.length && t[j] !== '"') j += t[j] === "\\" ? 2 : 1;
      out += t.slice(i, j + 1); i = j + 1;
    } else if (t.startsWith("//", i)) { const j = t.indexOf("\n", i); i = j < 0 ? t.length : j; }
    else if (t.startsWith("/*", i)) { const j = t.indexOf("*/", i + 2); i = j < 0 ? t.length : j + 2; }
    else { out += c; i++; }
  }
  return out;
}

function main() {
  const [kbFile, tsvFile, statesFile, folder] = process.argv.slice(2);
  const vs = loadParser();
  if (!vs) { console.log("VSCode not found: skipped"); process.exit(3); }
  const P = new vs.Parser({ regexParsingWithErrorRecovery: false });
  const parse = (w, where) => {
    const e = P.parse(w || "true");
    if (!e || P.parsingErrors.length || P.lexingErrors.length) {
      console.log("VSCode cannot parse the when of " + where + ": " + JSON.stringify(w));
      process.exit(1);
    }
    return e;
  };
  const kb = JSON.parse(stripComments(fs.readFileSync(kbFile, "utf8")) || "[]");
  const isOurs = (k) => k.key === "shift+escape" && (k.when || "").includes("resourcePath =~ /^(");
  let n = 0;
  const user = kb.map((k) => ({ ...k, expr: parse(k.when, k.command), ours: isOurs(k) }));
  n = user.length;
  const esc = [];
  for (const ln of fs.readFileSync(tsvFile, "utf8").split("\n")) {
    if (!ln || ln.startsWith("#")) continue;
    const t = ln.indexOf("\t");
    esc.push({ command: ln.slice(0, t), expr: parse(ln.slice(t + 1), "tsv " + ln.slice(0, t)) });
  }
  for (const k of user) if (k.key === "escape") esc.push(k);
  const sesc = user.filter((k) => k.key === "shift+escape");
  const win = (rules, ctx) => { let w = null; for (const r of rules) if (r.expr.evaluate(ctx)) w = r.command; return w; };
  const states = JSON.parse(fs.readFileSync(statesFile, "utf8"));
  let inside = 0, outside = 0, ran = 0;
  const cmds = new Set();
  for (const st of states) {
    const ctx = { getValue: (k) => st[k] };
    const e = win(esc, ctx), s = win(sesc, ctx);
    if (typeof st.resourcePath === "string" && st.resourcePath.startsWith(folder + "/")) {
      inside++;
      if (e !== null) { ran++; cmds.add(e); }
      if (e !== s) { console.log("inside: Esc -> " + e + " but Shift+Esc -> " + s + " in " + JSON.stringify(st)); process.exit(1); }
    } else {
      outside++;
      const m = sesc.find((k) => k.ours && k.expr.evaluate(ctx));
      if (m) { console.log("outside the folder a vsc rule matched: " + m.command); process.exit(1); }
    }
  }
  console.log("VSCode " + vs.version + " parser: all " + n + " when clauses in keybindings.json and " +
    (esc.length) + " Esc rules parse");
  console.log("VSCode evaluator: " + inside + " states inside (Esc ran a command in " + ran + ", " + cmds.size +
    " different commands), " + outside + " outside: Shift+Esc = Esc inside, no vsc rule outside");
}
main();
