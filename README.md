# PHILMART V1 — Source

Clean-architecture .NET API and a Next.js frontend, built against the Controlled
Decision Register **D001–D076** and the naming standard in
`../01_Documents/PHILMART_Coding_Standard.md`.

```
03_Source/
├── Philmart.sln
├── src/
│   ├── Philmart.Domain/          Rules, constants, abstractions. No dependencies.
│   ├── Philmart.Application/     Use cases, DTOs, ports. Depends on Domain only.
│   ├── Philmart.Infrastructure/  EF Core, services, tenancy. Implements the ports.
│   └── Philmart.Api/             ASP.NET Core Web API. Composition root.
├── tests/
│   ├── Philmart.UnitTests/       Domain rules, no database.
│   └── Philmart.IntegrationTests/ Real SQL Server, migrated by database/migrate.sh.
├── tools/scaffold.ps1            Regenerates the EF model from the database.
└── web/                          Next.js 16 App Router, TypeScript, Tailwind 4.
```

Dependencies point **inward**. `Philmart.Domain` references nothing;
`Philmart.Api` references Application and Infrastructure and is the only project
that knows both exist.

## Running it

```bash
# 1. Create the database and apply all migrations, including the seed
#    (needs sqlcmd; see database/migrate.sh for the environment variables)
./database/migrate.sh

# 2. API
dotnet user-secrets set "ConnectionStrings:Philmart" "<connection string>" \
  --project src/Philmart.Api
dotnet run --project src/Philmart.Api        # https://localhost:7001

# 3. Frontend
cd web && npm run dev                        # http://localhost:3000
```

The API connection string must use a login mapped to the **`philmart_app`**
database role. Not `db_owner`, not `sysadmin` — Row Level Security does not
apply to either, and the whole tenancy layer silently disappears.

## Three things that are not optional

**Tenancy is resolved server-side, always.** `TenantContext` reads validated
claims and nothing else. Agreement clause 9.1: a Shop identifier supplied by the
client application is not sufficient authorisation, and a failure of Shop
isolation is a Critical Severity Defect that blocks acceptance.
`SessionContextInterceptor` pushes the verified session into `SESSION_CONTEXT`
on every connection open, which is what the RLS predicates read.

**Time comes from the database.** Every rule calls `IServerClock`, which reads
`philmart.ServerNow()`. Never `DateTime.Now`, never an inline
`SYSDATETIMEOFFSET()`. That is clause 9.2, and it is also what makes the 90-day
expiry, the 14-day query auto-close and the outbid throttle testable without
waiting — freeze the test clock and they all move.

**History is never destroyed.** `DENY DELETE ON SCHEMA::philmart TO
philmart_app`. Corrections are linked reversals, adjustments or superseding
records. If a change needs a `DELETE`, the change is wrong.

## The database is the source of truth

There are **no EF migrations**. Every controlled rule is enforced in SQL by
constraint, trigger, filtered index or security policy, and the C# model is
scaffolded *from* the database:

```powershell
./tools/scaffold.ps1 -Server localhost -Database Philmart
```

Schema changes are made by adding a numbered file under
`database/migrations` and re-running that. Never call `EnsureCreated`.

`Philmart.Domain.Rules.ItemStateMachine` deliberately mirrors
`philmart.Item_TransitionRule` so the rule is unit-testable without a database.
The database remains the enforcing authority; an integration test asserts the
two agree.

## Conventions

Per `../01_Documents/PHILMART_Coding_Standard.md`:

- **Async methods carry no `Async` suffix** — `GetById`, `Create`, `Transition`.
- **Services use primary-constructor DI with `IDbContextFactory<T>`**, opening
  one context per method.
- **Entities map PascalCase C# to `ID`-in-caps columns** — `ShopId` →
  `ShopID`, class `ItemItem` → table `Item_Item`.
- 4 spaces, file-scoped namespaces, nullable enabled.

## Frontend

Next.js 16 App Router, TypeScript, Tailwind 4, no component library. The design
comes from the controlled screen evidence (SCR-PUB-001, SCR-PUB-002A,
SCR-SHP-002): deep navy with a gold accent, serif display over sans body, warm
ivory cards on the public marketplace against a cool grey Shop workspace.

**Light and dark are both first-class.** Every colour is a token in
`globals.css`, redefined under `@media (prefers-color-scheme: dark)` and again
under `[data-theme="dark"]`. Nothing downstream hard-codes a hex value. An
inline script applies the stored preference before paint, so a dark-mode viewer
never sees a flash of the light palette.

Money is integer minor units end to end. `formatMoney` divides once, at the
edge; nothing divides in a template.

## What is built so far

Two vertical slices proving the patterns, not all 24 modules:

| Slice | Covers | Demonstrates |
|---|---|---|
| **BR-10 Items** | Item lifecycle, transitions, ageing | State machine, permissions, audit, 422 with decision reference |
| **BR-02 Marketplace** | Public browse, storefront, classifications | Anonymous read path, one query behind grid and list, discoverability gate |

21 unit tests cover the Item state machine, including the transitions that are
easiest to implement plausibly and wrongly — Missing/Damaged not auto-returning,
Return to Seller being terminal, and reason-mandatory moves.

The remaining modules follow the same shape. Part 5 of
`../01_Documents/PHILMART_V1_Development_Guide.docx` has the build spec for each.
