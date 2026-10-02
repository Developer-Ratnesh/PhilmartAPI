# T04 Development and test approach

How PHILMART V1 is built, tested and gated. Milestone 1 task T04; the
architecture behind it is in the [architecture record](../architecture/ARCHITECTURE_RECORD.md).

## Workflow

- `main` is always releasable. Work happens on short-lived branches and reaches
  `main` only through a pull request.
- A pull request merges only when CI is green and a named developer other than
  the author has reviewed it (Coding Standard). Branch protection on `main`
  enforces both.
- Each pull request names the BR requirement IDs and decision IDs it
  implements, using the pull request template.
- Commits follow the Coding Standard and `CODE_STYLE.md`.

## Test layers

| Layer | Project | Runs against | Proves |
|---|---|---|---|
| Unit | `tests/Philmart.UnitTests` | Nothing external | Domain rules, state machines, calculations; guard tests on the code base itself |
| Integration | `tests/Philmart.IntegrationTests` | Real SQL Server 2022, migrated by `database/migrate.sh` | Constraints, triggers, RLS, procedures, services through EF Core, the test clock |
| Database build | CI `database` job | Empty SQL Server 2022 | All ten migrations apply cleanly, the seed verifies itself, a re-run applies nothing |
| Frontend | CI `web` job | Node 22 | Lint, TypeScript type check, production build |
| End-to-end | Playwright (from Milestone 2) | Staging-like build | Screen flows against the 208 controlled screen records |

Constraint-level rules are never tested against a mock or an in-memory
database. Development Guide 2.1 requires a real SQL Server, and so does this
approach.

### Traceability

- Every BR requirement has at least one automated test whose name or trait
  carries its ID (e.g. `[Trait("BR", "BR-13-R04")]`).
- Every governing decision has a test that fails if the rule is removed.
- Each milestone submission includes a requirement-to-test map generated from
  those traits, plus the CI test results (`.trx`), as Schedule B1 requires.

### High-risk areas named in the Agreement

| Clause | Test obligation | When |
|---|---|---|
| 9.1 Shop isolation | Tests that attempt cross-Shop reads and writes through the API and directly against RLS, and fail the build if any succeed | Milestone 2 |
| 9.2 Auction timing | Simultaneous bids, duplicate submission, last-second bids, soft close, simultaneous closes, interruption and idempotent recovery, all driven by the test clock | Milestone 2 |
| 9.2 Authoritative time | Guard tests: no `DateTime.Now`/`UtcNow` in `src/`; no SQL clock call outside `philmart.ServerNow()` | **Built (Milestone 1)** |
| 9.3 Money boundary | Schema test that no payment-credential column exists | Milestone 3 |

## Deterministic test clock (T06)

`philmart.ServerNow()` is the only source of time, and it reads
`philmart.Sys_TestClock`. The harness in
`tests/Philmart.IntegrationTests/Support/TestClock.cs` drives it:

```csharp
await database.Clock.FreezeAt(new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero));
await database.Clock.Advance(TimeSpan.FromDays(90));   // e.g. D063 expiry now due
```

Tests that use the clock join the `Database` xUnit collection, which never runs
in parallel, and reset the clock in `DisposeAsync`. `TestClockTests` proves the
harness and proves that the application's `ServerClock` follows it.

## Quality gates (CI)

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

1. **Database:** migrate an empty SQL Server 2022; require the seed's
   verification line; require that a second run applies nothing.
2. **API:** restore, build in Release, unit tests, migrate a test database,
   integration tests. Test results are uploaded as evidence.
3. **Web:** `npm ci`, lint, type check, production build.

All three must pass before a pull request can merge.

## Running the tests locally

```bash
# unit tests
dotnet test tests/Philmart.UnitTests

# integration tests: migrate a scratch database first
PHILMART_SQL_DATABASE=PhilmartTest ./database/migrate.sh
PHILMART_TEST_CONNECTION="Server=localhost;Database=PhilmartTest;Trusted_Connection=True;TrustServerCertificate=True" \
  dotnet test tests/Philmart.IntegrationTests
```

Never point `PHILMART_TEST_CONNECTION` at a database whose data matters: the
tests move its clock.

## Defects and known issues

Defects are tracked as GitHub issues labelled by severity (Critical, High,
Medium, Low) as defined in the Agreement. Every milestone submission declares
all known Critical, High and security-relevant issues (Schedule B1).
