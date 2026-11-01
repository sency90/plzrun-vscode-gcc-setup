#!/usr/bin/env python3
"""Check a keybindings.json that vsc changed (tests only; vsc itself needs no python).

  kb_check.py parse <kb.json>
      parse it the strict way (comments taken out, no trailing comma allowed); print the entry count
  kb_check.py same-user <kb.json> <original.json>
      the entries outside the vsc part must be exactly the original entries, in the same order
  kb_check.py ours <kb.json> <shift-esc.tsv>
      vsc's entries: one marked part at the start of the array, one shift+escape per tsv line,
      same command and same when as the tsv (no folder condition, no // vsc-folder: line)
  kb_check.py none <kb.json>
      the file has no vsc part
  kb_check.py states <shift-esc.tsv> <count>
      print the same states as simulate (random ones + one per Esc rule) as JSON, for vscode_when.js
  kb_check.py simulate <kb.json> <shift-esc.tsv> <count>
      random VSCode states (any file, or no editor at all): Shift+Esc must run the same command
      as Esc every time (a later matching rule wins, user rules after the defaults)

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


def split_ours(path):
    """(text, vsc entries, user entries): the user entries are what is left with the marked part taken out"""
    text, v = load(path)
    lines = text.split("\n")
    b = next((i for i, x in enumerate(lines) if BEGIN in x), None)
    if b is None:
        return text, [], v
    e = next(i for i in range(b, len(lines)) if END in lines[i])
    rest = lines[:b] + lines[e + 1:]
    if "[split]" in lines[b]:              # vsc split the [ line; join it back the same way
        rest = lines[:b - 1] + [lines[b - 1] + lines[e + 1]] + lines[e + 2:]
    u = json.loads(strip_comments("\n".join(rest)) or "[]")
    k = len(v) - len(u)
    if k < 0 or v[k:] != u:
        raise SystemExit("the vsc part is not at the start of the array")
    return text, v[:k], u


def tsv_rows(path):
    rows = []
    for ln in open(path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        c, w = ln.split("\t", 1)
        rows.append((c, w))
    return rows


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


PATHS = ["/Users/me/github/poj/14216/14216.cpp", "/Users/me/sw expert/EX_1/user.cpp", "/elsewhere/a.cpp",
         "/Users/me/notes/todo.md", "untitled:Untitled-1"]


def make_states(esc, count):
    """random states (any file, or no editor) + one state per rule that makes that rule's when true"""
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
        if rnd.random() < 0.9: ctx["resourcePath"] = rnd.choice(PATHS)
        out.append(ctx)
    for cmd, cond in esc:
        ks = cond.keys(); ks.pop("resourcePath", None)
        for _ in range(4000):
            ctx = {"true": True, "resourcePath": rnd.choice(PATHS)}; fill(ctx, ks, 0.6)
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
        _, _, mine = split_ours(a[1]); _, o = load(a[2])
        if mine != o:
            print("user entries changed"); return 1
        print("user entries kept:", len(o)); return 0
    if a[0] == "none":
        text, ours, _ = split_ours(a[1])
        if BEGIN in text or END in text or ours:
            print("there is a vsc part"); return 1
        print("no vsc part"); return 0
    if a[0] == "ours":
        text, ours, _ = split_ours(a[1]); rows = tsv_rows(a[2])
        want = [dict({"key": "shift+escape", "command": c}, **({"when": w} if w else {})) for c, w in rows]
        if ours != want:
            for x, y in zip(ours, want):
                if x != y: print("got ", x); print("want", y); break
            print("vsc entries differ (%d, want %d)" % (len(ours), len(want))); return 1
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            print("not exactly one marked part"); return 1
        part = text[text.find(BEGIN):text.find(END)]
        if "resourcePath" in part or "vsc-folder" in part:
            print("a folder condition is left"); return 1
        print("vsc entries ok:", len(ours), "(no folder condition)"); return 0
    if a[0] == "states":
        rows = tsv_rows(a[1]); count = int(a[2])
        esc = [(c, When(w if w else "true")) for c, w in rows]
        print(json.dumps(make_states(esc, count)))
        return 0
    if a[0] == "simulate":
        _, v = load(a[1]); rows = tsv_rows(a[2]); count = int(a[3])
        esc = [(c, When(w if w else "true")) for c, w in rows]
        esc += [(k["command"], When(k.get("when") or "true")) for k in v if k.get("key") == "escape"]
        sesc = [(k["command"], When(k.get("when") or "true")) for k in v if k.get("key") == "shift+escape"]
        states = make_states(esc[:len(rows)], count)
        won = set(); ran = 0; noed = 0
        for ctx in states:
            e = winner(esc, ctx); s_ = winner(sesc, ctx)
            if "resourcePath" not in ctx: noed += 1
            if e is not None: won.add(e); ran += 1
            if e != s_:
                print("Esc ->", e, "but Shift+Esc ->", s_, "in", ctx); return 1
        print("simulated %d states (random ones and one per Esc rule, %d rules; %d with no editor open): "
              "Shift+Esc ran the same command as Esc every time (Esc ran a command in %d, %d different commands)"
              % (len(states), len(rows), noed, ran, len(won)))
        return 0
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
