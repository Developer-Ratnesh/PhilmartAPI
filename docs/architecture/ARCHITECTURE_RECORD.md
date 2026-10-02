# PHILMART V1 — Architecture record

Required by Agreement clause 8 and delivered as Milestone 1 task T03. It covers
every topic clause 8 lists, in that order. It is a living record: when a
decision changes, the entry is updated in the same pull request as the code,
and the change log at the foot says what moved and why.

| | |
|---|---|
| Version | 0.1 — Milestone 1 submission draft |
| Date | 2 October 2026 |
| Governing scope | Controlled Decision Register D001–D076, BRD V1, Development Guide, Schedule A baseline verified in [T01](../milestone-1/T01_baseline_integrity.md) |
| Status key | **Decided** — agreed and in force · **Built** — decided and present in the repository · **Proposed** — the Developers' recommendation, awaiting Client confirmation · **Open** — needs a decision |

---

## 1. Application architecture — **Built**

A modular monolith. The controlled rules interlock too tightly to split across
services: every service boundary would be another place an invariant can be
broken.

```
web/                         Next.js 16 App Router, React 19, TypeScript, Tailwind 4.
                             Rendering and interaction only. No business rule lives here.
src/Philmart.Api             ASP.NET Core Web API (.NET 10). Authentication, request
                             validation, serialisation. Composition root.
src/Philmart.Application     Use cases, DTOs and ports. Depends on Domain only.
src/Philmart.Domain          The rules: state machines, invariants, constants.
                             No HTTP, no EF Core, no dependencies at all.
src/Philmart.Infrastructure  EF Core (database-first), service implementations,
                             tenancy plumbing. Implements the Application ports.
database/                    The SQL schema, owned by migrations, not by EF.
```

Dependencies point inward. Only `Philmart.Api` knows the other projects exist.

### Deviation from the Development Guide — **Decided, Client to confirm in writing**

Development Guide section 2.1 names TypeScript end to end with NestJS for the
API, Redis + BullMQ for jobs and Vitest/Jest for tests. The controlled source
baseline in the pack (`03_Source`) is a .NET solution, and this repository is
built from it. What changes and what does not:

| Guide | This build | Effect on controlled rules |
|---|---|---|
| NestJS API, TypeScript domain package | ASP.NET Core API, `Philmart.Domain` class library | None. The guide's layering (framework-free domain, thin HTTP layer) is kept exactly. |
| Redis + BullMQ jobs | See section 7 | None, provided close is durable and idempotent, which section 7 requires. |
| Vitest/Jest | xUnit | None. Real SQL Server for constraint-level tests is kept. |
| Next.js, SQL Server 2019+, Full-Text Search | Same | — |

The Guide itself says the stack is the Developers' technical proposal, not a
product rule, and that architecture decisions belong in this record. We ask the
Client to confirm the .NET choice in writing so the record and the Guide do not
disagree at acceptance.

## 2. Database architecture — **Built**

- Microsoft SQL Server 2019 or later, or Azure SQL Database (Client-mandated).
  2019 is needed for scalar UDF inlining of `philmart.ServerNow()`.
- The schema is the controlled `02_Database` pack, copied unchanged into
  [`database/`](../../database): ten migrations, 82 tables, 61 indexes,
  15 functions, 4 procedures, 30 triggers, 3 views, 4 security policies,
  123 check constraints.
- The SQL owns the schema. EF Core is database-first (`tools/scaffold.ps1`);
  there are no EF migrations and `EnsureCreated` is never called.
- Migrations are applied by [`database/migrate.sh`](../../database/migrate.sh),
  which records each file's SHA-256 in `dbo.SchemaMigration` and refuses to
  continue if an applied migration has since been edited. A shipped migration is
  corrected by a new migration.
- Money is `BIGINT` minor units; percentages `DECIMAL(9,6)`; no `FLOAT`, `REAL`
  or `MONEY`. Closed sets are `VARCHAR` + `CHECK`, catalogued in
  `philmart.Sys_EnumValue`.

## 3. Tenant separation (clause 9.1) — **Built in part**

Two independent layers, both always on:

1. **Server-side authorisation.** `TenantContext` builds the actor, Shop and
   permissions from validated token claims only — never from a URL, body or
   header. `RequiresPermission` / `RequiresPlatformAdmin` guard each endpoint,
   and every service scopes queries by the Shop from `TenantContext`.
2. **Row Level Security, defence in depth.** `SessionContextInterceptor` writes
   actor id, Shop id and actor kind into `SESSION_CONTEXT` each time a pooled
   connection opens. Four RLS policies over 53 tables read them.

The API connects as a login in the `philmart_app` role. RLS does not apply to
`db_owner` or `sysadmin`, so either would silently remove layer 2.

**Still to build (Milestone 2):** automated tests that actively attempt
cross-Shop access through the API and directly against RLS, and fail the build
if any attempt succeeds.

## 4. Authentication and authorisation — **Proposed**

- JWT bearer tokens validated by the API (issuer, audience, lifetime, signing
  key; 30 s skew). Configuration currently points at Microsoft Entra ID.
- **Open:** the identity provider for Buyers and Shop users. BR-01 requires
  self-registration with email verification and legal acceptance; we propose an
  external OIDC provider (Entra External ID) issuing the `philmart:*` claims,
  with PHILMART's own tables remaining the source of Shop membership and
  permissions. Needs Client agreement, because it affects hosting cost and
  account ownership (clause 7).
- Permissions are directly assigned to Shop users from the controlled
  catalogue (26 permissions). There is no custom role layer (clause 9.1).
  Shop Administrator holds the full set.
- PHILMART administrators are a separate actor kind, checked by
  `RequiresPlatformAdmin`.

## 5. Business-rule placement — **Decided**

Clause 8: rules are implemented once, centrally.

- Rules that the database can enforce **are** enforced there: constraints,
  filtered unique indexes (one active Listing per Item, D013), set-based
  triggers for immutability and the Item state machine, and the procedures
  `P_List_Bid_Place`, `P_List_Auction_Close`,
  `P_Sale_Fulfilment_FireFinancialTrigger` and `P_Sale_Payment_Allocate`.
- Rules that need application context live in `Philmart.Domain`
  (e.g. `ItemStateMachine`), mirrored by the database guard where one exists, so
  a screen, an API call and a background job all hit the same rule.
- Controllers and React components contain no business rules.

## 6. Auction concurrency and authoritative time (clause 9.2) — **Built in part**

- **Time:** every rule reads `philmart.ServerNow()`, through `IServerClock` in
  .NET. The web server clock and the browser clock are never used. Automated
  guards fail the build on `DateTime.Now` / `UtcNow` in `src/`, and on any SQL
  clock call outside `ServerNow()` in the migrations.
- **Test clock (T06):** `philmart.Sys_TestClock` lets tests freeze or move time;
  `ServerNow()` is the only place it hooks in. Harness:
  `tests/Philmart.IntegrationTests/Support/TestClock.cs`.
- **Known issue raised with the Client:** `003_onboarding.sql` defaults
  `Shop_CommercialTerms.EffectiveFrom` from `SYSUTCDATETIME()`, which bypasses
  the test clock. Not edited here because the file is controlled; recorded as a
  known exception in the guard test until a corrected migration is issued.
- **Bidding:** bids go through `philmart.P_List_Bid_Place` in a `SERIALIZABLE`
  transaction. EF Core retries deadlock victims (error 1205) up to five times.
- **Still to build (Milestone 2):** tests for simultaneous bids, duplicate
  submission, last-second bids, soft-close extension, simultaneous closes,
  interruption and idempotent recovery.

## 7. Background jobs — **Proposed**

Needed for auction close, clock-driven sweeps (expiry, query auto-close),
month-end fee accrual and email dispatch.

Proposal: a .NET worker using a durable job store in the same SQL Server
(Hangfire with SQL storage, or an equivalent outbox table polled by a hosted
service). The rules a job must follow are fixed whichever is picked:

- Durable: a lost close is an invalid auction outcome, so a job survives a
  restart.
- Idempotent: `P_List_Auction_Close` can be called twice for the same Listing and
  the second call changes nothing.
- Time-driven by `ServerNow()`, so the test clock drives jobs too.
- Recovery: after an outage, a sweep closes every auction whose end time has
  passed, in end-time order.

This avoids adding Redis as a second piece of infrastructure the Client must
host. Decision needed by the start of auction work (Milestone 2).

## 8. Audit records — **Built in schema**

- `philmart.Sys_AuditEvent` is the audit spine. History tables (Item state history, ledgers,
  bids, legal acceptance) are append-only, enforced by set-based triggers.
- `DELETE` is denied to `philmart_app` across the schema.
- Corrections are linked reversals, adjustments or superseding records showing
  who, what, when and, where required, why (clause 8). `IAuditWriter` writes
  application-level events.

## 9. Security — **Decided**

- No buyer funds, wallet, gateway or stored card or bank credentials. There is
  no column to hold one and none may be added (clause 9.3).
- Least privilege: the app runs as `philmart_app`; migrations run as
  `philmart_migrator`.
- Secrets live in user-secrets locally and in the host's secret store in
  staging and production — never in the repository. The CI database password
  is a throwaway for an ephemeral container.
- Transport encryption on every connection (`Encrypt=True`); HTTPS only;
  CORS restricted to the configured web origins.
- Frontend dependencies are locked by `package-lock.json` and installed with
  `npm ci` in CI. NuGet versions are pinned exactly in each project file.

## 10. Testing — **Built**

See [T04 development and test approach](../milestone-1/T04_development_and_test_approach.md).
In short: unit tests for domain rules, integration tests against a real SQL
Server, guard tests for clause 9.2, and CI that blocks merging on failure.
Every BR requirement gets at least one test naming its ID.

## 11. Deployment — **Open**

Staging is required from Milestone 2. Proposal: Azure App Service (API and
web) with Azure SQL Database, deployed from `main` by GitHub Actions after the
quality gates pass. Accounts to be registered in Client-controlled
subscriptions (clause 7). Needs Client decision on hosting provider and budget.

## 12. Backups and recovery — **Open**

Depends on section 11. With Azure SQL: automated point-in-time restore
(minimum 7 days), plus a long-term weekly backup. A restore drill is part of the
Final Acceptance handover evidence.

## 13. Monitoring — **Proposed**

Structured logging through Serilog (configured), with request correlation ids.
Production sink and alerting (e.g. Application Insights) chosen with section 11.
Alerts at minimum for: failed auction close jobs, job backlog, error rate, and
database DTU/CPU.

## 14. AI controls — **Decided**

- AI assistants are used for development under the Coding Standard: every
  change is reviewed by a named developer, who is responsible for it.
- No production data, Buyer personal information or credentials are sent to
  any AI tool.
- AI tool use is disclosed in the handover evidence, as Schedule B requires.

## 15. Scaling assumptions — **Decided**

- Catalogue in the low hundreds of thousands of Items; SQL Server Full-Text
  Search, no separate search engine (Guide 2.1).
- One API instance is sufficient for V1. The API is stateless, so it can scale
  out; auction correctness never depends on in-process state, only on the
  database.
- Full-Text Search is optional on-premises: migration 009 skips the catalogue
  and warns if the feature is missing. Azure SQL has it by default.

---

## Change log

| Date | Version | Change |
|---|---|---|
| 2026-10-02 | 0.1 | First version for Milestone 1. |
