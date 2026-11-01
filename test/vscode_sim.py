#!/usr/bin/env python3
"""Run what VSCode would run from the generated .vscode files, without VSCode.

  vscode_sim.py task   <workspace> <viewed file> <label>   run a task (and its dependsOn)
  vscode_sim.py f5-lldb <workspace> <viewed file>          F5 on macOS: preLaunchTask, then
                                                          lldb-mi driven like cpptools does
  vscode_sim.py f5-gdb  <workspace> <viewed file>          F5 on Linux: print the gdb run line
  vscode_sim.py ctrl-f5 <workspace> <viewed file> <os> [shell]
                                                          Ctrl+F5 (Run Without Debugging) on
                                                          osx or linux: preLaunchTask, then the
                                                          terminal command line cpptools builds

Variables substituted like VSCode: ${workspaceFolder} ${file} ${fileDirname}
${fileBasename} ${fileBasenameNoExtension}. Only for tests; vsc itself needs no python.
"""
import glob
import json
import os
import re
import select
import shlex
import subprocess
import sys
import time


def load_jsonc(path):
    lines = [l for l in open(path, encoding="utf-8") if not l.lstrip().startswith("//")]
    return json.loads("".join(lines))


def make_vars(ws, f):
    f = os.path.abspath(f)
    base = os.path.basename(f)
    return {
        "workspaceFolder": os.path.abspath(ws),
        "file": f,
        "fileDirname": os.path.dirname(f),
        "fileBasename": base,
        "fileBasenameNoExtension": os.path.splitext(base)[0],
    }


def subst(v, vs):
    if isinstance(v, str):
        return re.sub(r"\$\{(\w+)\}", lambda m: vs[m.group(1)], v)
    if isinstance(v, list):
        return [subst(x, vs) for x in v]
    if isinstance(v, dict):
        return {k: subst(x, vs) for k, x in v.items()}
    return v


def run_task(ws, f, label, depth=0):
    tasks = {t["label"]: t for t in load_jsonc(os.path.join(ws, ".vscode", "tasks.json"))["tasks"]}
    if label not in tasks:
        sys.exit("no task labeled %r (have: %s)" % (label, ", ".join(tasks)))
    t = subst(tasks[label], make_vars(ws, f))
    dep = t.get("dependsOn")
    for d in ([dep] if isinstance(dep, str) else dep or []):
        rc = run_task(ws, f, d, depth + 1)
        if rc:
            return rc
    opts = t.get("options", {})
    cwd = opts.get("cwd", ws)
    if "args" in t:
        argv = [t["command"]] + t["args"]
        shown = " ".join(shlex.quote(a) for a in argv)
    else:
        sh = opts.get("shell", {"executable": os.environ.get("SHELL", "/bin/sh"), "args": ["-c"]})
        argv = [sh["executable"]] + sh["args"] + [t["command"]]
        shown = "%s %s <command>" % (sh["executable"], " ".join(sh["args"]))
    print("> [%s] (cwd %s)" % (label, cwd))
    print(">   " + (shown if "args" in t else t["command"]))
    sys.stdout.flush()
    return subprocess.call(argv, cwd=cwd)


def launch_config(ws, f, osname):
    c = load_jsonc(os.path.join(ws, ".vscode", "launch.json"))["configurations"][0]
    c = dict(c)
    c.update(c.pop(osname, {}))
    c.pop("linux", None), c.pop("osx", None), c.pop("windows", None)
    return subst(c, make_vars(ws, f))


def find_lldb_mi():
    hits = sorted(glob.glob(os.path.expanduser(
        "~/.vscode/extensions/ms-vscode.cpptools-*/debugAdapters/lldb-mi/bin/lldb-mi")))
    if not hits:
        sys.exit("lldb-mi from ms-vscode.cpptools not found")
    return hits[-1]


def mi_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def f5_lldb(ws, f):
    c = launch_config(ws, f, "osx")
    rc = run_task(ws, f, c["preLaunchTask"])
    if rc:
        sys.exit("preLaunchTask failed: %d" % rc)
    cmds = []
    # cpptools: setupCommands that do not start with '-' go through the console
    for s in c.get("setupCommands", []):
        t = s["text"]
        cmds.append(t if t.startswith("-") else "-interpreter-exec console " + mi_quote(t))
    cmds.append("-file-exec-and-symbols " + mi_quote(c["program"]))
    cmds.append("-environment-cd " + mi_quote(c["cwd"]))
    if c.get("args"):
        cmds.append("-exec-arguments " + " ".join(mi_quote(a) for a in c["args"]))
    cmds.append("-exec-run")
    lmi = find_lldb_mi()
    print("> lldb-mi: " + lmi)
    for x in cmds:
        print(">   " + x)
    p = subprocess.Popen([lmi], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, cwd=c["cwd"])
    p.stdin.write(("\n".join(cmds) + "\n").encode())
    p.stdin.flush()
    out, buf, end = [], b"", time.time() + 60
    exited = None
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if not r:
            continue
        chunk = os.read(p.stdout.fileno(), 65536)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            ln, buf = buf.split(b"\n", 1)
            ln = ln.decode(errors="replace").rstrip("\r")
            if ln.startswith("@"):
                out.append(json.loads(ln[1:]))
            if ln.startswith("^error"):
                print("> lldb-mi " + ln)
            if ln.startswith("*stopped"):
                exited = ln[:160]
        if exited:
            break
    p.stdin.write(b"-gdb-exit\n")
    p.stdin.flush()
    p.wait(timeout=10)
    print("> program output (Debug Console):")
    sys.stdout.write("".join(out).replace("\r\n", "\n"))
    print("> " + (exited or "program did not stop in 60s"))


def f5_gdb(ws, f):
    c = launch_config(ws, f, "linux")
    print("> preLaunchTask: " + c["preLaunchTask"])
    print("> %s %s, args %s" % (c["MIMode"], c.get("miDebuggerPath", ""), json.dumps(c["args"])))
    print(">   same as: gdb -ex 'run %s' %s" % (" ".join(c["args"]), shlex.quote(c["program"])))


def ctrl_f5_cmdline(c):
    """The terminal command line for Ctrl+F5, built the way cpptools 1.34.4 builds it.

    cpptools sends a noDebug launch of a cppdbg config to RunWithoutDebuggingAdapter
    (dist/src/main.js). It reads only program, args, cwd, environment and
    console/externalConsole; setupCommands, MIMode and the debugger never run.
    With shell integration it calls VSCode's shellIntegration.executeCommand(program,
    args), which appends each arg as is, or wrapped in "..." if it has whitespace and
    no quote (extensionHostProcess.js). Without shell integration it sends
    buildShellCommandLine('', program, args, true), which also quotes ('...') only
    args with a space. Either way "<" and ">" reach the shell unquoted.
    """
    prog, args = c["program"], c.get("args", [])
    with_si = '"%s"' % prog if (not re.search(r"[\"']", prog) and re.search(r"\s", prog)) else prog
    for a in args:
        with_si += ' "%s"' % a if (not re.search(r"[\"'`]", a) and re.search(r"\s", a)) else " " + a
    no_si = " ".join("'%s'" % x if " " in x and not re.match(r"^(['\"]).*\1$", x) else x
                     for x in [prog] + args)
    return with_si, no_si


def ctrl_f5(ws, f, osname, shell):
    c = launch_config(ws, f, osname)
    rc = run_task(ws, f, c["preLaunchTask"])
    if rc:
        sys.exit("preLaunchTask failed: %d" % rc)
    with_si, no_si = ctrl_f5_cmdline(c)
    print("> Ctrl+F5 (%s): setupCommands are not used; terminal cwd %s" % (osname, c["cwd"]))
    print(">   shell integration:    " + with_si)
    print(">   no shell integration: " + no_si)
    for name, line in (("shell integration", with_si), ("no shell integration", no_si)):
        print("> %s -c <%s line>, terminal input is /dev/null:" % (shell, name))
        sys.stdout.flush()
        rc = subprocess.call([shell, "-c", line], cwd=c["cwd"], stdin=subprocess.DEVNULL)
        print("> exit %d" % rc)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    cmd, ws, f = sys.argv[1:4]
    if cmd == "task":
        sys.exit(run_task(ws, f, sys.argv[4]))
    elif cmd == "f5-lldb":
        f5_lldb(ws, f)
    elif cmd == "f5-gdb":
        f5_gdb(ws, f)
    elif cmd == "ctrl-f5":
        ctrl_f5(ws, f, sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "/bin/zsh")
    else:
        sys.exit(__doc__)
