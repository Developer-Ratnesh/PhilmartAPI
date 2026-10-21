# Milestone evidence tools

These produce the evidence pack in the structure the Client proposed (Attachment C, 21 October 2026).

| File | What it does |
|---|---|
| `m2-evidence.mjs` | Drives the website, the API and the database of one environment, and records an outcome per checklist / review ID, with screenshots, sanitised API exchanges and database rows. |
| `outage-and-restore.sh` | Backup → restore → outage → restart demonstration on a copy of the database (O.1, N23, N30). Local or isolated staging only. |
| `catalogue.py` | The 100 checklist rows, N01–N30 and B01–B14, each mapped to its requirement, milestone, automated tests and overlaps. |
| `build-index.py` | Joins the automated test results (TRX) and the environment run into `00_INDEX.xlsx`. |
| `build-docs.py`, `print-pdf.mjs` | Write the developer response and submission document (DOCX and PDF). |

## Outcome rule

FAIL if anything that ran failed. PASS if the environment check or the mapped automated tests ran and passed. Otherwise BLOCKED (with the reason) or NOT RUN. Nothing that wasn't executed is reported as PASS.

## Running the automated tests

```
export PHILMART_TEST_CONNECTION="Server=localhost;Database=PhilmartTest;Integrated Security=True;TrustServerCertificate=True"
bash database/migrate.sh            # PHILMART_SQL_DATABASE=PhilmartTest
dotnet test Philmart.sln -c Release --logger trx --results-directory test-results
dotnet test --filter "Review=N03"   # one review item
dotnet test --filter "BR=BR-13-R05" # one requirement
```

Never point `PHILMART_TEST_CONNECTION` at a database that matters: the tests move the database clock and add rows that can't be deleted.

## Running the environment check

Needs Node 20+, the web app's `node_modules` (Playwright, Chrome) and `sqlcmd`.

```
WEB_URL=https://philmart.co.za \
API_URL=https://morneoosza-003-site4.etempurl.com \
SQL_SERVER=sql6032.site4now.net SQL_DATABASE=db_acd9e3_philmart \
SQL_USER=db_acd9e3_philmart_admin SQL_PASSWORD=... \
ADMIN_PASSWORD=... EMAIL_DOMAIN=<a domain you receive mail for> \
OUT_DIR=evidence-out BROWSERS=msedge,firefox,webkit \
node tools/evidence/m2-evidence.mjs
```

It takes about 12 minutes, because it waits for real auctions to open, soft-close and close. Run it at most once per 10 minutes against one API, because the run itself uses about 25 of the 30 PIN requests a client may make in 10 minutes (N01).

### What it changes on the environment

All of it is synthetic and on the demo Shops:

- adds a fresh batch of demo listings (`database/dev/staging_topup.sql`) and six Ready to List items plus one consigned item on Cape Stamp Traders
- registers synthetic buyers `m2-<x>-<run>@<EMAIL_DOMAIN>`, and makes Buy Now purchases and bids with them
- schedules, bids on, cancels and lets close a few auctions on Cape Stamp Traders
- invites one synthetic Shop user; changes staff@capestamps.test's permissions and restores them
- restricts and then lifts one synthetic buyer at Highveld Philatelics
- deactivates Highveld Philatelics for under a minute (M.6), then reactivates it; both are audited with a reason
- submits one support request marked "M2 evidence test - please ignore"
- issues one invoice, records a payment and reverses it (N29)

No real money moves and no real person is contacted. Emails go to the synthetic addresses only.

### What it can't see

- The sign-in PIN and the support-request copy are never stored (by design), so L.3, L.5, E.3 and E.8 need the inbox. Locally, `API_LOG` lets the run read the sign-in PIN from the development log.
- Emails are proven up to the hand-over to the mail server, not arrival in an inbox.
- O.1 / N30 need the API to be stopped and restarted: use `outage-and-restore.sh` on a copy.
