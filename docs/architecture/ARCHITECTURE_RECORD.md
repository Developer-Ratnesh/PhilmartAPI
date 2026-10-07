# PHILMART V1 architecture record

Required by Agreement clause 8 and delivered as Milestone 1 task T03. It covers
every topic clause 8 lists, in that order. It is a living record: when a
decision changes, the entry is updated in the same pull request as the code,
and the change log at the foot says what moved and why.

| | |
|---|---|
| Version | 0.2, Milestone 2 |
| Date | 3 October 2026 |
| Governing scope | Controlled Decision Register D001–D076, BRD V1, Development Guide, Schedule A baseline verified in [T01](../milestone-1/T01_baseline_integrity.md) |
| Status key | **Decided**: agreed and in force. **Built**: decided and in the repository. **Proposed**: our recommendation, waiting on the Client. **Open**: needs a decision. |

---

## 1. Application architecture (Built)

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

### Deviation from the Development Guide (Decided, Client to confirm in writing)

Development Guide section 2.1 names TypeScript end to end with NestJS for the
API, Redis + BullMQ for jobs and Vitest/Jest for tests. The controlled source
baseline in the pack (`03_Source`) is a .NET solution, and this repository is
built from it. What changes and what does not:

| Guide | This build | Effect on controlled rules |
|---|---|---|
| NestJS API, TypeScript domain package | ASP.NET Core API, `Philmart.Domain` class library | None. The guide's layering (framework-free domain, thin HTTP layer) is kept exactly. |
| Redis + BullMQ jobs | See section 7 | None, provided close is durable and idempotent, which section 7 requires. |
| Vitest/Jest | xUnit | None. Real SQL Server for constraint-level tests is kept. |
| Next.js, SQL Server 2019+, Full-Text Search | Same | None |

The Guide itself says the stack is the Developers' technical proposal, not a
product rule, and that architecture decisions belong in this record. We ask the
Client to confirm the .NET choice in writing so the record and the Guide do not
disagree at acceptance.

## 2. Database architecture (Built)

- Microsoft SQL Server 2019 or later, or Azure SQL Database (Client-mandated).
  2019 is needed for scalar UDF inlining of `philmart.ServerNow()`.
- The schema is the controlled `02_Database` pack, copied unchanged into
  [`database/`](../../database): ten controlled migrations plus 011 to 013
  (see section 3, 6 and `docs/milestone-2`), 82 tables, 61 indexes,
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

## 3. Tenant separation, clause 9.1 (Built)

Two independent layers, both always on:

1. **Server-side authorisation.** `TenantContext` builds the actor and Shop
   from validated token claims only, never from a URL, body or header.
   `AccountCheckMiddleware` then loads the user's permissions from the
   database on every request, so a disabled user or a removed permission
   stops working at once. `RequiresPermission` / `RequiresPlatformAdmin`
   guard each endpoint, and every service filters by the Shop from
   `TenantContext` as well.
2. **Row Level Security, as a second line.** `SessionContextInterceptor` writes
   actor id, Shop id and actor kind into `SESSION_CONTEXT` each time a pooled
   connection opens. Four RLS policies over 53 tables read them.

Testing showed RLS applies to every login, `sysadmin` included. The API still
connects as a login in the `philmart_app` role, so the schema-wide `DENY
DELETE` and the grants hold.

Migration 011 opens reads, never writes, for rows that are public anyway: live
and closed listings, their items, images and bids, and the delivery methods a
Shop offers. Without it the public marketplace was empty and bidding could not
work (see `docs/milestone-2`).

Background jobs and the commitment procedures run as the `system` actor, set
only by server code after it has authorised the caller.

`ShopIsolationTests` attempt cross-Shop reads and writes through the API and
straight against RLS, and fail the build if any get through (BR-08-R08).

## 4. Authentication and authorisation (Built)

The API issues and checks its own JWTs (HMAC-SHA256, 8 hours, 30 s skew). The
signing key comes from configuration; outside Development the API refuses to
start without one. No external identity provider, because the schema already
holds the credentials (`PasswordHash` on all three user tables).

- **Buyers** have no password. SCR-PUB-014 and 014.1 sign them in and verify
  registration with a 4-digit PIN sent by email. The server hands back a
  challenge sealed with ASP.NET Data Protection that carries a hash of the
  PIN. It expires in 10 minutes, allows 5 tries, and is single use, so no PIN
  is stored. Asking for a PIN never reveals whether an email is registered.
- **Shop users** sign in with a password set when they accept their
  invitation. Passwords use ASP.NET Identity's hasher (PBKDF2, salted).
- **PHILMART administrators** sign in with a password. MFA
  (`Sys_PlatformUser.MfaSecret`) is not built yet.
- Permissions are directly assigned to Shop users from the controlled
  catalogue (26 permissions). There is no role layer (D050). The Shop
  Administrator always holds the full set, and admin-only permissions can't be
  given to anyone else.

## 5. Business-rule placement (Decided)

Clause 8: rules are implemented once, centrally.

- Rules that the database can enforce **are** enforced there: constraints,
  filtered unique indexes (one active Listing per Item, D013), set-based
  triggers for immutability and the Item state machine, and the procedures
  `P_List_Bid_Place`, `P_List_Auction_Close`,
  `P_Sale_Fulfilment_FireFinancialTrigger` and `P_Sale_Payment_Allocate`.
- Rules that need application context live in `Philmart.Domain`
  (e.g. `ItemStateMachine`) and the Infrastructure services, mirrored by the
  database guard where one exists, so a screen, an API call and a background
  job all hit the same rule.
- Controllers and React components contain no business rules.

## 6. Auction concurrency and authoritative time, clause 9.2 (Built)

- **Time:** every rule reads `philmart.ServerNow()`, through `IServerClock` in
  .NET. The web server clock and the browser clock are never used. Automated
  guards fail the build on `DateTime.Now` / `UtcNow` in `src/` (login token
  expiry is the one named exception), and on any SQL clock call outside
  `ServerNow()` in the migrations. Item detail sends the server time so the
  countdown doesn't trust the device clock.
- **Test clock (T06):** `philmart.Sys_TestClock` lets tests freeze or move time;
  `ServerNow()` is the only place it hooks in.
- **Known issue raised with the Client:** `003_onboarding.sql` defaults
  `Shop_CommercialTerms.EffectiveFrom` from `SYSUTCDATETIME()`.
- **Bidding:** `P_List_Bid_Place` in a `SERIALIZABLE` transaction, run through
  EF Core's execution strategy so a deadlock victim (1205) is retried. The bid
  carries an idempotency key, so a double submit is one bid.
- **Close:** `P_List_Auction_Close` is idempotent. Migration 013 fixes its
  unsold branch, which failed on every unsold auction as shipped.
- **Tests:** `AuctionTests` covers simultaneous bids, duplicate submission,
  ordering, last-second bids and soft close, simultaneous closes, and recovery
  after an outage, all on the test clock.

## 7. Background jobs (Built for auctions)

`AuctionJob`, a .NET hosted service inside the API, runs the auction sweep on
startup and then every 5 seconds (`Jobs:AuctionSweepSeconds`):

- scheduled auctions go live once their start passes
- ended auctions close through `P_List_Auction_Close`, oldest first, each in
  its own transaction, with the sale row and EML-012 written by the call that
  actually closed it

Durability comes from the database, not a queue: an auction's end time is a
column, so a restart or an outage loses nothing, and the first sweep after it
is the recovery. A close a few seconds late can't change the result, because
`P_List_Bid_Place` refuses any bid at or after `EndsAt`. Polling every few
seconds rather than one timer per auction means a soft-close extension needs no
re-arming. No Redis or job store to host.

Still to come, in the same pattern: email dispatch, listing expiry, ageing,
query auto-close, month-end fees (Development Guide section 6).

## 8. Audit records (Built in schema)

- `philmart.Sys_AuditEvent` is the audit spine. History tables (Item state history, ledgers,
  bids, legal acceptance) are append-only, enforced by set-based triggers.
- `DELETE` is denied to `philmart_app` across the schema.
- Corrections are linked reversals, adjustments or superseding records showing
  who, what, when and, where required, why (clause 8). `IAuditWriter` writes
  application-level events.

## 9. Security (Decided)

- No buyer funds, wallet, gateway or stored card or bank credentials. There is
  no column to hold one and none may be added (clause 9.3).
- Least privilege: the app runs as `philmart_app`; migrations run as
  `philmart_migrator`.
- Secrets live in user-secrets locally and in the host's secret store in
  staging and production, never in the repository. The CI database password
  is a throwaway for an ephemeral container.
- Transport encryption on every connection (`Encrypt=True`); HTTPS only;
  CORS restricted to the configured web origins.
- Frontend dependencies are locked by `package-lock.json` and installed with
  `npm ci` in CI. NuGet versions are pinned exactly in each project file.

## 10. Testing (Built)

See [T04 development and test approach](../milestone-1/T04_development_and_test_approach.md).
In short: unit tests for domain rules, integration tests against a real SQL
Server, guard tests for clause 9.2, and CI that blocks merging on failure.
Every BR requirement gets at least one test naming its ID.

## 11. Deployment (Open)

Staging is required from Milestone 2. Proposal: Azure App Service (API and
web) with Azure SQL Database, deployed from `main` by GitHub Actions after the
quality gates pass. Accounts to be registered in Client-controlled
subscriptions (clause 7). Needs Client decision on hosting provider and budget.

## 12. Backups and recovery (Open)

Depends on section 11. With Azure SQL: automated point-in-time restore
(minimum 7 days), plus a long-term weekly backup. A restore drill is part of the
Final Acceptance handover evidence.

## 13. Monitoring (Proposed)

Structured logging through Serilog (configured), with request correlation ids.
Production sink and alerting (e.g. Application Insights) chosen with section 11.
Alerts at minimum for: failed auction close jobs, job backlog, error rate, and
database DTU/CPU.

## 14. AI controls (Decided)

- AI assistants are used for development under the Coding Standard: every
  change is reviewed by a named developer, who is responsible for it.
- No production data, Buyer personal information or credentials are sent to
  any AI tool.
- AI tool use is disclosed in the handover evidence, as Schedule B requires.

## 15. Scaling assumptions (Decided)

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
| 2026-10-03 | 0.2 | Sign-in decided and built (own JWT, buyer email PIN). Auction job built. Migrations 011 to 013. Corrected: RLS applies to sysadmin too. |
