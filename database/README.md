# PHILMART V1 — Database

**Microsoft SQL Server 2019 or later** (or Azure SQL Database), built against the
Controlled Decision Register **D001–D076** (16 September 2026) and the D076
Authority Matrix.

2016 is the floor for Row Level Security and JSON. 2019 is required for scalar
UDF inlining, without which `philmart.server_now()` becomes a per-row call
wherever it appears in a predicate.

The design intent is that the database refuses to let the application be wrong.
Rules a developer would otherwise have to remember are enforced as constraints,
triggers, filtered indexes and security policies. Where something looks
over-engineered, read its `MS_Description` — every one cites the decision it
enforces.

## Contents

| Path | What it is |
|---|---|
| `PHILMART_V1_Database_Full.sql` | **The whole database in one file** — schema *and* seed. Start here. **Generated.** |
| `PHILMART_V1_Database_Schema.sql` | Schema only, no seed. Byte-identical to migrations `001`–`009` concatenated. **Generated.** |
| `migrations/001` … `009` | The same DDL split for sequential migration. Nothing forward-references. |
| `migrations/010_seed.sql` | The controlled reference seed. **Generated.** |
| `../tools/gen_seed.py` | Generates `010_seed.sql` from the controlled artefacts. |
| `../tools/build_sql.py` | Runs `gen_seed.py`, then builds both single-file artefacts. |

Three files are generated. **Do not hand-edit them.** Change a migration, or
`gen_seed.py` for the seed, then rebuild everything with one command:

```
python tools/build_sql.py
```

The build asserts that the schema master is byte-identical to `001`–`009` and
that all ten parts appear verbatim and in order inside the full file, so the
single-file artefacts can never quietly drift from the migrations.

## Deploying

For a fresh database, one file is all you need:

```
sqlcmd -S <server> -E -C -Q "CREATE DATABASE PhilMart;"
sqlcmd -S <server> -E -C -d PhilMart -f 65001 -b -i PHILMART_V1_Database_Full.sql
```

`-f 65001` is **required** — these files are UTF-8 without a BOM and carry
accented controlled names (`Réunion`, `São Tomé and Príncipe`, em dashes).
Without it they load mojibaked into a PHILMART-controlled master. `-b` makes a
failing batch fail the run instead of scrolling past.

A successful run ends with exactly these two lines:

```
PHILMART 010_seed: controlled reference seed loaded and verified.
PHILMART: database build complete.
```

Anything less means it stopped early — read upward to the first `Msg` line.

The file targets a **fresh** database; it is not a re-runnable upgrade script,
because parts 1–9 are `CREATE` statements. Part 10, the seed, *is* idempotent
and can be re-run on its own at any time.

There is deliberately no `CREATE DATABASE` or `USE` inside the script: `USE` is
unsupported on Azure SQL Database, and the target database should be the
caller's explicit choice rather than a constant buried in a file.

Use the migrations instead of the single file when you need a migration runner,
a review diff per part, or to stop partway. All three paths — the ten
migrations in order, schema master plus seed, and the full single file —
produce an identical database, and all three are verified on each build.

## Run order

```
001_foundation.sql        Schema, test clock, server_now(), SESSION_CONTEXT
                          accessors, the enum_value catalogue, audit spine,
                          platform config, classification and delivery reference
002_identity_legal.sql    Platform users, shop, permissions, shop users, buyers
                          and preferences, buyer accounts, restrictions, legal
                          documents and acceptance
003_onboarding.sql        Applications, review, setup sections and progress,
                          shop settings, commercial terms, locations, delivery
                          methods, sellers
004_items.sql             Items, transition rules, state history, images,
                          bulk upload
005_listings.sql          Listings, bids, outbid throttle log, auction events
006_money.sql             Sales, fulfilment snapshot, combined shipping,
                          invoices, payments, allocation, buyer ledger, views
007_fulfilment_fees.sql   Fulfilment, paid item attention, seller proceeds and
                          payments, fee config, accrual, fee invoices, allocation
008_service_comms.sql     Buyer queries, notifications, email catalogue and
                          messages, governance exceptions, reports
009_enforcement.sql       Roles and grants, 4 RLS predicate functions and
                          policies, set-based immutability triggers, state
                          machine guard, auto-activation, place_bid,
                          close_auction, fire_financial_trigger,
                          allocate_payment, full-text catalogue (optional)
010_seed.sql              Controlled reference seed: permissions, Shop Setup
                          sections, the 659-row classification master, the
                          email catalogue, legal documents, report definitions
                          and platform configuration
```

Run with `sqlcmd`, SqlPackage or a runner that honours `GO`. A driver that
submits a whole file as one batch will fail on the first statement that must
begin a batch.

Part 9 ends with the full-text catalogue, which is **optional**. On an instance
without the Full-Text Search feature it prints a warning, skips the catalogue
and carries on; `Item_Item` catalogue search is then unavailable until the
feature is installed and that block is re-run. The block is guarded and its DDL
deferred through `EXEC` because `CREATE FULLTEXT CATALOG` raises error 7609 when
the feature is missing *even inside an `IF` branch that is never taken* —
unguarded, that error would abort everything after it and, in the single-file
build, take the seed down with it.

## The seed

**`010_seed.sql` is generated. Do not hand-edit it.** Regenerate with:

```
python tools/gen_seed.py
```

The generator reads the controlled artefacts directly and records each file's
SHA-256 in the header of the output, so a seed can always be traced to the pack
revision it came from. It refuses to run if a controlled set has changed shape —
a different row count per classification domain, or a changed Type list.

Loading by hand is the failure this guards against: typing the 24 email rows is
how a RETIRED template gets marked current, and typing 659 classification rows
is worse.

Seeding is idempotent. Every section is a `MERGE` on the natural key, so
re-running updates controlled attributes in place and inserts anything new.
Nothing is ever deleted — a value the controlled master withdraws is
deactivated, because historical Items still point at it (D055, clause 8).

Run it as `philmart_migrator` or `db_owner`; the script refuses to run as
`philmart_app`. It ends with a verification block that throws rather than
leaving a half-seeded database looking healthy.

Three tables are **deliberately left empty**, each for a reason documented at
the foot of the file: `Sys_DeliveryMethod` (no controlled list exists; PHILMART
maintains it through SCR-ADM-007.2), `Sys_ItemCondition` (genuinely unsourced —
needs a controlled decision) and `Sys_PlatformUser` (a bootstrap credential must
not ship in source control). Shop Setup cannot complete until delivery methods
are loaded, which is the correct failure: it blocks on missing controlled data
rather than trading on invented data.

### Seed this before any Shop exists

`TR_shop_setup_auto_activation` activates a Shop when no `Mandatory = 1` section
is outstanding. That test is vacuously true when no row is mandatory. Both
failure modes were reproduced against this schema on SQL Server 2025:

- `Shop_SetupSection` **empty** — `FK_ssp_section` rejects every
  `Shop_SetupProgress` row, so Shop Setup is inoperable and no Shop can activate.
- `Shop_SetupSection` **populated with no mandatory row** — the first progress
  row flips the Shop straight to `active`, *even with `IsValid = 0`*.

The seed loads all eight controlled setup stages as mandatory, and the
verification block asserts that at least one mandatory row exists.

## Scale

82 tables · 61 indexes · 13 functions · 4 stored procedures · 30 triggers ·
3 views · 4 security policies over 53 tables · 122 check constraints ·
63 inline decision citations.

Seeded: 516 Area/Country nodes · 60 subtypes · 37 formats · 32 themes ·
26 permissions · 24 email templates · 8 setup sections · 7 types ·
7 stamp states · 7 legal documents · 7 report definitions · 10 platform settings.

## Deployment errors fixed 22 September 2026

Four errors stopped `001`–`009` deploying to SQL Server. All are fixed; each is
recorded here because two of them were silent.

| Where | Problem | Fix |
|---|---|---|
| `004`, `008` | `RowCount` is a reserved keyword | `[RowCount]` |
| `005` | `UX_lst_one_active_per_item` used `OR` in a filtered-index predicate, which is a syntax error. **The "one active Listing per Item" guarantee (D013) was absent from the database.** | `WHERE State IN ('draft','scheduled','live')` |
| `008` | `IX_em_failed` — same `OR` problem | `WHERE DeliveryState IN ('bounced','failed')` |
| `009` | The full-text block aborted the rest of the script on any instance without Full-Text Search | Guarded on `SERVERPROPERTY('IsFullTextInstalled')`, DDL deferred through `EXEC`, and made idempotent |

The comment above the `005` index claimed filtered predicates "take simple
comparisons combined with OR/AND, hence the expanded form rather than IN". That
is backwards — `IN` is accepted, `OR` is not — and the comment has been
corrected in place.

Verified after the fix on SQL Server 2025, by all three deployment paths:
82 tables, 61 indexes, 30 triggers, 4 procedures, 3 views, 4 security policies,
123 check constraints. A second active Listing on an Item is now rejected by
`UX_lst_one_active_per_item`, and a new Listing is accepted once the previous
one goes historical.

The Full-Text-Search-present branch of part 9 could not be exercised here — the
feature is not installed on the verification instance — so only the skip path is
proven. Confirm the catalogue and index are created the first time this deploys
somewhere that has it.

### QUOTED_IDENTIFIER

Many tables here carry filtered indexes, so **every session that writes to them
needs `QUOTED_IDENTIFIER ON`** or the write fails with Msg 1934. The .NET
SqlClient sets it on by default, so the API is fine; ad-hoc `sqlcmd` sessions
are not, and `sqlcmd -I` is rejected alongside `-E` in the ODBC 17 build. Put
`SET QUOTED_IDENTIFIER ON;` at the top of any script you write against this
database. Every file in `migrations/` already does.

## Known defects

`Philmart.Domain.Constants.PhilmartConstants` disagrees with the `CHECK`
constraints on several string values (`'buyer'` vs `'Buy_Buyer'`,
`'invoice.cancelled'` vs `'Sale_Invoice.cancelled'`) — a find/replace has
rewritten identifiers inside quoted string literals. Every audit write from the
API will fail its constraint at runtime. Not fixed here: the API and the
database have to change together. See the foot of `010_seed.sql`.

The two `.zip` archives in this folder predate these fixes and are stale.

## Four invariants the schema exists to protect

1. **PHILMART never holds buyer money.** No gateway, no wallet, no stored
   credentials. There is nowhere in this schema to put one, and none may be
   added. Agreement clause 9.3.
2. **A Shop can never see or affect another Shop.** `shop_id` on every owned
   table, RLS reading `SESSION_CONTEXT`, *plus* server-side authorisation in the
   API. Both layers. Clause 9.1 — a failure here is a Critical Severity Defect.
3. **Time is authoritative on the database.** Everything calls
   `philmart.server_now()`. The test clock overrides that one function, which is
   what makes the 90-day expiry testable without waiting 90 days. Clause 9.2.
4. **History is never destroyed.** `DENY DELETE ON SCHEMA::philmart TO
   philmart_app`. Corrections are linked reversals, adjustments or superseding
   records. Clause 8.

## Three things that differ from a PostgreSQL build

If you have seen the earlier PostgreSQL draft, or you are reading the Developer
Response Pack v1.1 which proposed Postgres, these are the real differences.

**Triggers fire once per statement, not once per row.** Every guard in `009` is
set-based against the `inserted` and `deleted` pseudo-tables. A guard written
row-at-a-time — `SELECT @x = col FROM inserted` — validates one arbitrary row
and silently passes the rest of a multi-row write. On an immutability or
isolation rule that is a Critical Severity Defect that no single-row test
catches. Attack every trigger with a multi-row statement in test.

**There is no ENUM type.** Closed sets are `VARCHAR` + `CHECK`, with every
permitted value also catalogued in `philmart.enum_value` for lookup, dropdown
binding and introspection. Adding a value means changing both — deliberate
friction, because these sets come from controlled decisions.

**JSON is `NVARCHAR(MAX)` + `CHECK (ISJSON(col) = 1)`,** not an indexed type
like `JSONB`. Index a computed column if you ever need to query into an audit
payload.

## Before you change anything here

Connect as a principal in `philmart_app` and try to break it. The role is
deliberately unprivileged: no `DELETE`, not `db_owner`, not `sysadmin`. **Row
Level Security does not apply to `db_owner` or `sysadmin`** — if your tenancy
tests connect as either, they pass vacuously and prove nothing. If a change
requires loosening any of that, the change is wrong.

Full explanation of every table group, the enforcement layer and the five
callables you must use rather than reimplement is in
`../01_Documents/PHILMART_V1_Development_Guide.docx`, part 3.
