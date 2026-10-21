"""Builds 00_INDEX.xlsx for the evidence pack: requirement -> test -> evidence.

  python -I tools/evidence/build-index.py --trx a.trx b.trx --run Live=results.json [--run Local=other.json] --out 00_INDEX.xlsx

Outcome rule (client protocol, Attachment C): nothing un-executed becomes
PASS. A row is FAIL if anything that ran for it failed; PASS if the
environment run passed, or the automated tests for it ran and passed;
otherwise it keeps the environment status (BLOCKED / NOT RUN) with the reason.
"""

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

import re

from openpyxl import Workbook
from openpyxl.cell.cell import ILLEGAL_CHARACTERS_RE
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def clean(value):
    # error text from the browser driver can carry terminal colour codes
    if isinstance(value, str):
        return ILLEGAL_CHARACTERS_RE.sub("", ANSI.sub("", value))
    return value

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from catalogue import ATTACHMENT_A, ATTACHMENT_B, CHECKLIST  # noqa: E402

NS = {"t": "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"}
FILL = {
    "CLARIFICATION": PatternFill("solid", fgColor="DCE8F5"),
    "M3 SCOPE": PatternFill("solid", fgColor="DCE8F5"),
    "PASS": PatternFill("solid", fgColor="D9F2E3"),
    "FAIL": PatternFill("solid", fgColor="F8D7DA"),
    "BLOCKED": PatternFill("solid", fgColor="FFF3CD"),
    "NOT RUN": PatternFill("solid", fgColor="E9ECEF"),
}
HEAD = PatternFill("solid", fgColor="16233A")


RESULT_COUNT = {"total": 0, "passed": 0}


def read_trx(paths):
    tests = {}
    for path in paths:
        root = ET.parse(path).getroot()
        for r in root.iter("{%s}UnitTestResult" % NS["t"]):
            name = r.get("testName").split(".")[-1].split("(")[0]
            outcome = r.get("outcome")
            RESULT_COUNT["total"] += 1
            RESULT_COUNT["passed"] += 1 if outcome == "Passed" else 0
            prev = tests.get(name)
            if prev is None or outcome != "Passed":
                tests[name] = {"outcome": outcome, "duration": r.get("duration"), "file": os.path.basename(path)}
    return tests


def read_runs(specs):
    runs = []
    for spec in specs:
        label, path = spec.split("=", 1)
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        runs.append((label, data, {r["id"]: r for r in data["results"]}))
    return runs


def automated(names, tests):
    if not names:
        return "", "none mapped"
    found = [tests.get(n) for n in names]
    missing = [n for n, t in zip(names, found) if t is None]
    passed = sum(1 for t in found if t and t["outcome"] == "Passed")
    failed = sum(1 for t in found if t and t["outcome"] not in ("Passed",))
    if failed:
        return "FAIL", f"{passed}/{len(names)} passed, {failed} failed"
    if missing:
        return ("PASS" if passed else "NOT RUN"), f"{passed}/{len(names)} passed, {len(missing)} not in this run"
    return "PASS", f"{passed}/{len(names)} passed"


def overall(auto, env_statuses):
    if auto == "FAIL" or "FAIL" in env_statuses:
        return "FAIL"
    if "PASS" in env_statuses:
        return "PASS"
    if auto == "PASS":
        return "PASS"
    if "BLOCKED" in env_statuses:
        return "BLOCKED"
    return "NOT RUN"


def basis(auto, runs_for_row):
    parts = []
    for label, r in runs_for_row:
        if r:
            parts.append(f"{label}: {r['status']}")
    if auto:
        parts.append(f"automated: {auto}")
    return "; ".join(parts) or "nothing ran"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trx", nargs="*", default=[])
    ap.add_argument("--run", action="append", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--release", default="")
    args = ap.parse_args()

    tests = read_trx(args.trx)
    runs = read_runs(args.run)

    wb = Workbook()
    ws = wb.active
    ws.title = "Index"
    cols = ["ID", "Source", "Check", "Requirement (D076 / BRD)", "Milestone", "Expected", "Overall outcome", "Basis"]
    for label, _, _ in runs:
        cols += [f"{label} result", f"{label} observed", f"{label} evidence"]
    cols += ["Automated tests", "Automated result", "Overlaps with", "Notes"]
    ws.append(cols)

    counts = {}
    rows_out = []
    for source, items in (("Checklist 19 Oct", CHECKLIST), ("Attachment A", ATTACHMENT_A), ("Attachment B", ATTACHMENT_B)):
        for (tid, title, expected, req, milestone, names, overlap, note) in items:
            auto, auto_text = automated(names, tests)
            per_run = [(label, idx.get(tid)) for label, _, idx in runs]
            env = [r["status"] for _, r in per_run if r]
            out = overall(auto, env)
            if not names and not env:
                out = "NOT RUN"
            # not a test to run in M2: say what it is instead of NOT RUN
            if out == "NOT RUN" and not milestone.startswith("M2"):
                out = {"Clarification": "CLARIFICATION", "M3": "M3 SCOPE", "M4": "M4 SCOPE"}.get(milestone, milestone.upper())
            counts.setdefault(source, {}).setdefault(out, 0)
            counts[source][out] += 1
            row = [tid, source, title, req, milestone, expected, out, basis(auto, per_run)]
            for _, r in per_run:
                row += [r["status"] if r else "", (r["actual"] if r else ""), "\n".join(r["evidence"]) if r else ""]
            row += ["\n".join(names), auto_text, overlap, note]
            row = [clean(v) for v in row]
            ws.append(row)
            rows_out.append(row)

    widths = {"ID": 7, "Source": 14, "Check": 34, "Requirement (D076 / BRD)": 24, "Milestone": 12, "Expected": 36, "Overall outcome": 11, "Basis": 30,
              "Automated tests": 46, "Automated result": 20, "Overlaps with": 18, "Notes": 46}
    for i, name in enumerate(cols, start=1):
        ws.column_dimensions[get_column_letter(i)].width = widths.get(name, 40 if "observed" in name else 34 if "evidence" in name else 10)
        c = ws.cell(row=1, column=i)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD
        c.alignment = Alignment(wrap_text=True, vertical="top")
    out_col = cols.index("Overall outcome") + 1
    for r in range(2, ws.max_row + 1):
        for c in range(1, len(cols) + 1):
            ws.cell(row=r, column=c).alignment = Alignment(wrap_text=True, vertical="top")
        v = ws.cell(row=r, column=out_col).value
        if v in FILL:
            ws.cell(row=r, column=out_col).fill = FILL[v]
        for i, name in enumerate(cols, start=1):
            if name.endswith(" result") and ws.cell(row=r, column=i).value in FILL:
                ws.cell(row=r, column=i).fill = FILL[ws.cell(row=r, column=i).value]
    ws.freeze_panes = "C2"
    ws.auto_filter.ref = ws.dimensions

    # every automated test, and which IDs it serves
    t = wb.create_sheet("Automated tests")
    t.append(["Test", "Outcome", "Duration", "Result file", "Serves IDs"])
    serves = {}
    for items in (CHECKLIST, ATTACHMENT_A, ATTACHMENT_B):
        for (tid, *_rest) in items:
            for n in _rest[4]:
                serves.setdefault(n, []).append(tid)
    for name in sorted(tests):
        info = tests[name]
        t.append([name, info["outcome"], info["duration"], info["file"], ", ".join(serves.get(name, []))])
    for i, w in enumerate([70, 10, 18, 40, 40], start=1):
        t.column_dimensions[get_column_letter(i)].width = w
        t.cell(row=1, column=i).font = Font(bold=True, color="FFFFFF")
        t.cell(row=1, column=i).fill = HEAD
    for r in range(2, t.max_row + 1):
        v = t.cell(row=r, column=2).value
        t.cell(row=r, column=2).fill = FILL["PASS"] if v == "Passed" else FILL["FAIL"]

    # summary
    s = wb.create_sheet("Summary", 0)
    s.append(["PHILMART Milestone 2 evidence index"])
    s["A1"].font = Font(bold=True, size=14)
    s.append([args.release])
    s.append([])
    s.append(["Source", "PASS", "FAIL", "BLOCKED", "NOT RUN", "Not an M2 test", "Total"])
    for src in ("Checklist 19 Oct", "Attachment A", "Attachment B"):
        c = counts.get(src, {})
        other = sum(v for k, v in c.items() if k not in ("PASS", "FAIL", "BLOCKED", "NOT RUN"))
        s.append([src] + [c.get(k, 0) for k in ("PASS", "FAIL", "BLOCKED", "NOT RUN")] + [other, sum(c.values())])
    # every result counts, including each case of a parameterised test
    total_tests = RESULT_COUNT["total"]
    passed = RESULT_COUNT["passed"]
    s.append([])
    s.append(["Automated tests (unit + integration)", f"{passed} of {total_tests} passed"])
    for label, data, idx in runs:
        st = [r["status"] for r in data["results"]]
        s.append([f"{label} run {data.get('runId', '')} ({data.get('web', '')})",
                  f"{st.count('PASS')} pass, {st.count('FAIL')} fail, {st.count('BLOCKED')} blocked of {len(st)}"])
    s.append([])
    s.append(["Outcome rule: FAIL if anything that ran failed; PASS if the environment run or the mapped automated tests ran and passed; otherwise BLOCKED / NOT RUN with the reason. Nothing that wasn't executed is reported as PASS."])
    s.column_dimensions["A"].width = 60
    for col in "BCDEF":
        s.column_dimensions[col].width = 14
    for c in s[4]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD

    wb.save(args.out)

    # the same figures, and every row's outcome, for the submission document
    facts = {
        "release": args.release,
        "counts": counts,
        "automated": {"passed": passed, "total": total_tests},
        "runs": [{"label": label, "runId": data.get("runId"), "web": data.get("web"), "api": data.get("api"),
                  "pass": [r["status"] for r in data["results"]].count("PASS"),
                  "fail": [r["status"] for r in data["results"]].count("FAIL"),
                  "blocked": [r["status"] for r in data["results"]].count("BLOCKED"),
                  "total": len(data["results"])} for label, data, _ in runs],
        "rows": {row[0]: {"outcome": row[6], "basis": row[7]} for row in rows_out},
        "env": {label: {k: {"status": v["status"], "actual": v["actual"]} for k, v in idx.items()} for label, _, idx in runs},
    }
    with open(os.path.splitext(args.out)[0] + ".facts.json", "w", encoding="utf-8") as f:
        json.dump(facts, f, indent=1)
    print(json.dumps(counts, indent=1))
    print(f"automated {passed}/{total_tests}; index written to {args.out}")


if __name__ == "__main__":
    main()
