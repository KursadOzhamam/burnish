#!/usr/bin/env python3
"""Update roadmap rows and bump the revision.

Usage: scripts/rm.py ID STATUS "note to append or replace" [--replace]
       scripts/rm.py --decision "text | rationale"
Statuses: d done, t todo, u user, k decision, o optional.
Afterwards publish docs/BurnishRoadMap.html with the Artifact tool (same path).
"""
import io, re, sys, subprocess, datetime

PATH = "docs/BurnishRoadMap.html"
DEC = "docs/DECISIONS.md"

def main(argv):
    if argv[0] == "--decision":
        text = argv[1]
        t = io.open(DEC, encoding="utf-8").read().rstrip("\n")
        t += f"\n| {datetime.date.today().isoformat()} | {text} |\n"
        io.open(DEC, "w", encoding="utf-8").write(t)
        return
    rid, status, note = argv[0], argv[1], argv[2]
    s = io.open(PATH, encoding="utf-8").read()
    m = re.search(r'\["%s","([dtuko])","([^"]*)","([^"]*)"' % re.escape(rid), s)
    if not m:
        sys.exit(f"row {rid} not found")
    desc = m.group(3)
    if "--replace" in argv:
        desc = note
    else:
        desc = (desc + " " + note).strip()
    note = desc.replace('"', "'")
    new = '["%s","%s","%s","%s"' % (rid, status, m.group(2), note)
    s = s.replace(m.group(0), new, 1)
    r = re.search(r"rev:(\d+),", s)
    s = s.replace(r.group(0), "rev:%d," % (int(r.group(1)) + 1), 1)
    io.open(PATH, "w", encoding="utf-8").write(s)
    js = re.search(r"<script>(.*?)</script>", s, re.S).group(1)
    io.open("/private/tmp/claude-501/rm.js", "w").write(js)
    subprocess.check_call(["node", "--check", "/private/tmp/claude-501/rm.js"])
    print("ok rev", int(r.group(1)) + 1)

main(sys.argv[1:])
