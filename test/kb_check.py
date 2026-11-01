#!/usr/bin/env python3
"""Check a keybindings.json that vsc changed (tests only; vsc itself needs no python).

  kb_check.py parse <kb.json>
      parse it the strict way (comments taken out, no trailing comma allowed); print the entry count
  kb_check.py same-user <kb.json> <original.json>
      the entries that are not vsc's must be exactly the original entries, in the same order
  kb_check.py ours <kb.json> <shift-esc.tsv> <folder>...
      vsc's entries: one shift+escape per tsv line, same command, when = (tsv when) && folder regex,
      inside the marked part; the regex matches files in the folders and nothing else
  kb_check.py states <shift-esc.tsv> <folder> <count>
      print the same states as simulate (random ones + one per Esc rule) as JSON, for vscode_when.js
  kb_check.py simulate <kb.json> <shift-esc.tsv> <folder> <count>
      random VSCode states: inside the folder, Shift+Esc must run the same command as Esc
      (a later matching rule wins, user rules after the defaults); outside it, no vsc rule may match

The when evaluator covers what the tsv uses: ! && || ( ) == != =~ /re/ 'str' and bare keys.
"""
import json, os, random, re, sys

BEGIN, END = "// >>> vsc shift+escape", "// <<< vsc shift+escape"


def strip_comments(t):
    out, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        if c == '"':
            j = i + 1
            while j < n and t[j] != '"':
                j += 2 if t[j] == "\\" else 1
            out.append(t[i:j + 1]); i = j + 1
        elif t.startswith("//", i):
            j = t.find("\n", i); i = n if j < 0 else j
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2); i = n if j < 0 else j + 2
        else:
            out.append(c); i += 1
    return "".join(out)


def load(path):
    t = open(path, encoding="utf-8").read()
    s = strip_comments(t)
    if re.search(r",\s*[\]}]", s):
        raise SystemExit("trailing comma in " + path)
    v = json.loads(s) if s.strip() else []
    if not isinstance(v, list):
        raise SystemExit("not a JSON array: " + path)
    return t, v


def ours_marked(text):
    """entries written between the vsc markers (by their command+when text)"""
    b, e = text.find(BEGIN), text.find(END)
    if b < 0:
        return 0
    return text[b:e].count('"key": "shift+escape"')


def is_ours(k):
    return k.get("key") == "shift+escape" and "resourcePath =~ /^(" in k.get("when", "")


def tsv_rows(path):
    rows = []
    for ln in open(path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        c, w = ln.split("\t", 1)
        rows.append((c, w))
    return rows


def folder_regex(folders):
    esc = lambda f: "".join("\\" + ch if ch in "\\^$.|?*+()[]{}/" else ch for ch in f)
    return "resourcePath =~ /^(" + "|".join(esc(f) for f in folders) + ")\\//"


# ---------------------------------------------------------------- when 평가
TOK = re.compile(r"\s*(&&|\|\||==|!=|=~|!|\(|\)|'[^']*'|/(?:\\.|[^/\\])*/[a-z]*|[A-Za-z0-9_.:\-]+)")


def tokens(s):
    out, i = [], 0
    while i < len(s):
        m = TOK.match(s, i)
        if not m:
            if s[i:].strip() == "":
                break
            raise ValueError("cannot read when at %r" % s[i:])
        out.append(m.group(1)); i = m.end()
    return out


class When:
    def __init__(self, s):
        self.src = s; self.t = tokens(s); self.i = 0
        self.tree = self.orx()
        if self.i != len(self.t):
            raise ValueError("extra tokens in when: %r" % s)

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def eat(self):
        self.i += 1; return self.t[self.i - 1]

    def orx(self):
        a = [self.andx()]
        while self.peek() == "||":
            self.eat(); a.append(self.andx())
        return ("or", a)

    def andx(self):
        a = [self.unary()]
        while self.peek() == "&&":
            self.eat(); a.append(self.unary())
        return ("and", a)

    def unary(self):
        if self.peek() == "!":
            self.eat(); return ("not", self.unary())
        if self.peek() == "(":
            self.eat(); e = self.orx()
            if self.eat() != ")":
                raise ValueError("missing )")
            return e
        key = self.eat()
        if self.peek() in ("==", "!=", "=~"):
            op = self.eat(); v = self.eat()
            if op == "=~":
                m = re.fullmatch(r"/((?:\\.|[^/\\])*)/([a-z]*)", v)
                return ("re", key, re.compile(m.group(1), re.I if "i" in m.group(2) else 0))
            return (op, key, v[1:-1] if v.startswith("'") else v)
        return ("key", key)

    def keys(self, e=None, out=None):
        e = self.tree if e is None else e; out = {} if out is None else out
        k = e[0]
        if k in ("or", "and"):
            for x in e[1]: self.keys(x, out)
        elif k == "not":
            self.keys(e[1], out)
        elif k in ("==", "!="):
            out.setdefault(e[1], set()).add(e[2])
        elif k == "re":
            out.setdefault(e[1], set())
        else:
            out.setdefault(e[1], set())
        return out

    def ev(self, ctx, e=None):
        e = self.tree if e is None else e; k = e[0]
        if k == "or": return any(self.ev(ctx, x) for x in e[1])
        if k == "and": return all(self.ev(ctx, x) for x in e[1])
        if k == "not": return not self.ev(ctx, e[1])
        if k == "key":
            v = ctx.get(e[1]); return bool(v) and v != "false"
        if k == "==": return str(ctx.get(e[1])) == e[2] if e[1] in ctx else False
        if k == "!=": return not (str(ctx.get(e[1])) == e[2] if e[1] in ctx else False)
        if k == "re":
            v = ctx.get(e[1]); return isinstance(v, str) and bool(e[2].search(v))
        raise ValueError(k)


def make_states(esc, folder, count):
    """random states (60% in the folder) + one state per rule that makes that rule's when true"""
    keys = {}
    for _, c in esc:
        for k, vals in c.keys().items(): keys.setdefault(k, set()).update(vals)
    keys.pop("resourcePath", None); keys.pop("true", None)
    rnd = random.Random(372); out = []
    def fill(ctx, ks, p):
        for k, vals in ks.items():
            if vals: ctx[k] = rnd.choice(sorted(vals) + ["other"])
            elif k == "config.agents.voice.useBYOKVoiceModel": ctx[k] = rnd.choice(["", "x"])
            elif rnd.random() < p: ctx[k] = True
    for i in range(count):
        ctx = {"true": True}; fill(ctx, keys, 0.35)
        where = rnd.random()
        if where < 0.6: ctx["resourcePath"] = folder + "/14216/14216.cpp"
        elif where < 0.9:
            ctx["resourcePath"] = rnd.choice(["/elsewhere/a.cpp", folder + "2/a.cpp", os.path.dirname(folder) + "/a.cpp",
                                              folder, "/x" + folder + "/a.cpp"])
        out.append(ctx)
    for cmd, cond in esc:
        ks = cond.keys(); ks.pop("resourcePath", None)
        for _ in range(4000):
            ctx = {"true": True, "resourcePath": folder + "/14216/14216.cpp"}; fill(ctx, ks, 0.6)
            if cond.ev(ctx): out.append(ctx); break
        else:
            raise SystemExit("could not make a state for " + cmd)
    return out


def winner(rules, ctx):
    w = None
    for cmd, cond in rules:
        if cond.ev(ctx):
            w = cmd
    return w


def main(a):
    if a[0] == "parse":
        _, v = load(a[1]); print("entries", len(v)); return 0
    if a[0] == "same-user":
        _, v = load(a[1]); _, o = load(a[2])
        mine = [k for k in v if not is_ours(k)]
        if mine != o:
            print("user entries changed"); return 1
        print("user entries kept:", len(o)); return 0
    if a[0] == "ours":
        text, v = load(a[1]); rows = tsv_rows(a[2]); folders = a[3:]
        ours = [k for k in v if is_ours(k)]
        cond = folder_regex(folders)
        want = [{"key": "shift+escape", "command": c, "when": ("(%s) && %s" % (w, cond)) if w else cond} for c, w in rows]
        if ours != want:
            for x, y in zip(ours, want):
                if x != y: print("got ", x); print("want", y); break
            print("vsc entries differ (%d, want %d)" % (len(ours), len(want))); return 1
        if ours_marked(text) != len(ours) or text.count(BEGIN) != 1 or text.count(END) != 1:
            print("vsc entries are not all inside one marked part"); return 1
        for f in folders:
            if ("// vsc-folder: " + f) not in text:
                print("folder comment missing:", f); return 1
        r = When(cond)
        for f in folders:
            for p, ok in ((f + "/14216/14216.cpp", True), (f + "/main.cpp", True), (f, False),
                          (f + "2/main.cpp", False), ("/elsewhere" + f + "/a.cpp", False)):
                if r.ev({"resourcePath": p}) != ok:
                    print("regex wrong for", p); return 1
        print("vsc entries ok:", len(ours), "folders", len(folders)); return 0
    if a[0] == "states":
        rows = tsv_rows(a[1]); folder = a[2]; count = int(a[3])
        esc = [(c, When(w if w else "true")) for c, w in rows]
        print(json.dumps(make_states(esc, folder, count)))
        return 0
    if a[0] == "simulate":
        _, v = load(a[1]); rows = tsv_rows(a[2]); folder = a[3]; count = int(a[4])
        esc = [(c, When(w if w else "true")) for c, w in rows]
        esc += [(k["command"], When(k.get("when") or "true")) for k in v if k.get("key") == "escape"]
        sesc = [(k["command"], When(k.get("when") or "true"), is_ours(k)) for k in v if k.get("key") == "shift+escape"]
        states = make_states(esc[:len(rows)], folder, count)
        inside = outside = 0; won = set()
        for ctx in states:
            e = winner(esc, ctx); s_ = winner([(c, w) for c, w, _ in sesc], ctx)
            if str(ctx.get("resourcePath", "")).startswith(folder + "/"):
                inside += 1
                if e is not None: won.add(e)
                if e != s_:
                    print("inside: Esc ->", e, "but Shift+Esc ->", s_); return 1
            else:
                outside += 1
                mine = [c for c, w, o in sesc if o and w.ev(ctx)]
                if mine:
                    print("outside the folder a vsc rule matched:", mine[0]); return 1
        print("simulated %d states inside (random ones and one per Esc rule, %d rules), %d outside: "
              "Shift+Esc ran the same command as Esc every time (%d different commands)"
              % (inside, len(rows), outside, len(won)))
        return 0
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
