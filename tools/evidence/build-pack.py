"""Assembles PHILMART_M2_Evidence_<release>.zip in the structure the Client
proposed (Attachment C, section 3).

  python -I tools/evidence/build-pack.py --release m2-rc2 --commit <sha> --out <folder>
      --trx <dir with .trx> --run Live=<evidence-out dir> [--run Local=<dir>]
      --outage <outage dir> --docs <folder with the response pdf/docx> --web <url> --api <url>
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

DEFECTS = [
    # id, found by, description, severity, status, fix, retest evidence
    ("B01", "Client interim review", "Descending price sort ordered auctions by starting price, not the current bid shown", "Medium", "Fixed in this release", "MarketplaceService.Sort uses fixed price, else current bid, else starting price", "Sorting_by_price_uses_the_current_bid_of_an_auction; M.2"),
    ("B02", "Client interim review", "Blank alternative courier address: Confirm Purchase enabled ('Destination: ,')", "Medium", "Fixed in this release", "Confirm disabled until street, city, postal code; server requires postal code", "A_blank_or_incomplete_alternative_address_is_refused; B02 screenshot"),
    ("B03", "Client interim review", "Below-minimum bid: Confirm Bid enabled (server already refused)", "Medium", "Fixed in this release", "Red minimum message and Confirm disabled below the minimum", "A_bid_below_the_minimum_is_refused_by_the_server; A.2 screenshot"),
    ("B04", "Client interim review", "Bid History closed itself every 10 seconds", "Low", "Fixed in this release", "Open state kept across the live refresh", "B04 screenshot"),
    ("B05", "Client interim review", "'A change here applies to this purchase/bid only' shown where nothing can change", "Low", "Fixed in this release", "Shown only where address or pickup point can change", "B05 screenshot"),
    ("B08", "Client interim review", "Saved-items counter read '0 items saved' during a search with no matches", "Low", "Fixed in this release", "Counter says how many saved items match; 'Show all saved items'", "M.10 screenshot"),
    ("N01", "Client additional test", "PIN requests limited per address only, not per client", "Medium (security)", "Fixed in this release", "Per-client limit on both PIN endpoints", "One_client_cannot_spray_pin_requests_across_many_addresses"),
    ("N03", "Client additional test", "Sign out didn't end the session on the server", "Medium (security)", "Fixed in this release", "POST /api/auth/logout, Sys_RevokedSession (016), checked on every request", "A_signed_out_token_is_refused_by_the_api; L.9; N03"),
    ("N28", "Client additional test", "No way to tell which build is deployed", "Low", "Fixed in this release", "GET /api/version; release tag", "The_api_says_which_build_is_running; N28"),
    ("N29", "Client additional test", "Schedule A6 invoice / payment / reversal had no screen or API", "Medium", "Fixed in this release", "InvoiceService, /api/shop/sales..., /workspace/sales", "InvoiceTests; N29 screenshots"),
    ("G.1", "Developer evidence run 21 Oct", "Marketplace scrolled sideways by 27 px on a 375 px phone (pagination row); auction price could wrap between 'R' and the amount", "Low", "Fixed in this release", "Pagination wraps; prices kept on one line", "G.1 screenshots"),
    ("B.4", "Client checklist 19 Oct", "Preferred method (Collect) not pre-selected", "Medium", "Fixed 19 Oct (migration 015), retested", "Buy_ShippingPreference.IsPreferred", "B.4 screenshots"),
    ("S.5 / E.7", "Client checklist 19 Oct", "Invitation email not received", "Medium", "Code path correct; delivery depends on DKIM (known issue)", "Link also shown on screen", "S.5, S.6"),
    ("S.6 / S.8", "Client checklist 19 Oct", "Limited user had no dashboard / unclear access", "Low", "Fixed 16-19 Oct, retested", "Shop dashboard; 'No access' panel", "S.6, S.8 screenshots"),
    ("R.10", "Client checklist 19 Oct", "Registering an existing email gave no message", "Low", "Fixed 19 Oct, retested", "'You already have an account' email", "R.10"),
    ("B.10", "Client checklist 19 Oct", "No way to restrict a buyer", "Medium", "Fixed 19 Oct, retested", "Buyer Restrictions screens (workspace and admin)", "B.10 screenshots"),
    ("L.x", "Client checklist 19 Oct (notes)", "'Review updated terms' asked at every sign-in", "High", "Fixed 19 Oct, retested", "Sign-in reads acceptances as system (RLS)", "Signing_in_does_not_ask_for_terms_already_accepted"),
    ("D.x", "Client checklist 19 Oct (notes)", "No admin log out button", "Low", "Fixed 19 Oct, retested", "Log out in the admin bar", "D.2 screenshot"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def copytree(src, dst):
    if os.path.isdir(src):
        shutil.copytree(src, dst, dirs_exist_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--trx", required=True)
    ap.add_argument("--run", action="append", default=[])
    ap.add_argument("--outage", default="")
    ap.add_argument("--docs", default="")
    ap.add_argument("--web", required=True)
    ap.add_argument("--api", required=True)
    ap.add_argument("--date", required=True)
    a = ap.parse_args()

    name = f"PHILMART_M2_Evidence_{a.release}"
    root = os.path.join(a.out, name)
    if os.path.exists(root):
        shutil.rmtree(root)
    folders = ["01_RELEASE", "02_TEST_OUTPUT", "03_SCREENSHOTS", "04_API_AND_DATABASE", "05_SECURITY", "06_AUCTION_AND_RECOVERY", "07_DEFECTS", "08_README"]
    for f in folders:
        os.makedirs(os.path.join(root, f), exist_ok=True)

    # environment runs: the first one fills the main folders; any other goes under 02_TEST_OUTPUT
    runs = [r.split("=", 1) for r in a.run]
    for i, (label, path) in enumerate(runs):
        if i == 0:
            for f in ("03_SCREENSHOTS", "04_API_AND_DATABASE", "05_SECURITY", "06_AUCTION_AND_RECOVERY"):
                copytree(os.path.join(path, f), os.path.join(root, f))
            copytree(os.path.join(path, "02_TEST_OUTPUT"), os.path.join(root, "02_TEST_OUTPUT", f"environment-run-{label.lower()}"))
            env = os.path.join(path, "01_RELEASE_environment.json")
            if os.path.exists(env):
                shutil.copy(env, os.path.join(root, "01_RELEASE", f"environment_{label.lower()}.json"))
        else:
            copytree(path, os.path.join(root, "02_TEST_OUTPUT", f"environment-run-{label.lower()}"))

    trx = [os.path.join(a.trx, x) for x in os.listdir(a.trx) if x.endswith(".trx")]
    for t in trx:
        shutil.copy(t, os.path.join(root, "02_TEST_OUTPUT", os.path.basename(t)))
    copytree(os.path.join(HERE), os.path.join(root, "02_TEST_OUTPUT", "scripts"))

    if a.outage and os.path.isdir(a.outage):
        copytree(a.outage, os.path.join(root, "06_AUCTION_AND_RECOVERY", "outage_and_restore"))

    # index
    index = os.path.join(root, "00_INDEX.xlsx")
    cmd = [sys.executable, "-I", os.path.join(HERE, "build-index.py"), "--out", index, "--release", f"Release {a.release}, commit {a.commit}", "--trx", *trx]
    for label, path in runs:
        cmd += ["--run", f"{label}={os.path.join(path, '02_TEST_OUTPUT', 'evidence-results.json')}"]
    subprocess.run(cmd, check=True)
    facts = os.path.splitext(index)[0] + ".facts.json"
    shutil.move(facts, os.path.join(a.out, f"{name}.facts.json"))

    # release record
    migrations = sorted(x for x in os.listdir(os.path.join(REPO, "database", "migrations")) if x.endswith(".sql"))
    log = subprocess.run(["git", "-C", REPO, "log", "--oneline", "658387b..HEAD"], capture_output=True, text=True).stdout
    manifest = {
        "release": a.release,
        "commit": a.commit,
        "tag": a.release,
        "date": a.date,
        "staging": {"web": a.web, "api": a.api, "version_endpoint": a.api + "/api/version"},
        "migrations": [{"name": m, "sha256": sha256(os.path.join(REPO, "database", "migrations", m))} for m in migrations],
        "previous_submission_commit": "658387b (9 October 2026)",
        "commits_since_previous_submission": log.strip().splitlines(),
        "generated": datetime.now(timezone.utc).isoformat(),
    }
    with open(os.path.join(root, "01_RELEASE", "release_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    if a.docs and os.path.isdir(a.docs):
        for x in os.listdir(a.docs):
            if x.endswith((".pdf", ".docx")):
                shutil.copy(os.path.join(a.docs, x), os.path.join(root, "01_RELEASE", x))
    shutil.copy(os.path.join(REPO, "docs", "milestone-2", "README.md"), os.path.join(root, "01_RELEASE", "milestone-2-requirements-status.md"))

    # defects
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    wb = Workbook()
    ws = wb.active
    ws.title = "Defects"
    ws.append(["Ref", "Found by", "Description", "Severity", "Status", "Fix", "Retest evidence"])
    for d in DEFECTS:
        ws.append(list(d))
    for i, w in enumerate([10, 22, 50, 16, 30, 50, 46], start=1):
        ws.column_dimensions[chr(64 + i)].width = w
        ws.cell(row=1, column=i).font = Font(bold=True, color="FFFFFF")
        ws.cell(row=1, column=i).fill = PatternFill("solid", fgColor="16233A")
    for row in ws.iter_rows(min_row=2):
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical="top")
    wb.save(os.path.join(root, "07_DEFECTS", "defects_and_retests.xlsx"))

    # readme
    with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
        tools_readme = f.read()
    with open(os.path.join(root, "08_README", "README.md"), "w", encoding="utf-8") as f:
        f.write(f"""# PHILMART Milestone 2 evidence pack, release {a.release}

Commit {a.commit}. Generated {a.date}.

## How to read it

1. Open `00_INDEX.xlsx`. The Summary sheet has the totals. The Index sheet has one row per test: the original checklist (100), N01-N30 and B01-B14. Each row shows its requirement, milestone, outcome and evidence files. The Automated tests sheet lists every automated test, its result, and the IDs it serves.
2. Files are named by test ID: `03_SCREENSHOTS/B_5_purchase_confirmed.png`, `04_API_AND_DATABASE/M_8_trace.json` (API exchanges and database rows), and so on.
3. `01_RELEASE` has the release manifest (commit, migrations with SHA-256), the environment the run was made against, and the developer response, which includes the release notes, known issues and declaration.
4. `02_TEST_OUTPUT` has the machine-readable results (TRX for the automated tests, JSON and JUnit for the environment run) and the scripts that produced them.

## Data protection

Passwords, PINs, tokens, invitation links and challenge values are replaced by *** in every trace. Only synthetic buyers and demo Shops were used.

---

{tools_readme}
""")

    zpath = os.path.join(a.out, name + ".zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(root):
            for x in files:
                full = os.path.join(base, x)
                z.write(full, os.path.relpath(full, a.out))
    print(zpath)


if __name__ == "__main__":
    main()
