# Milestone 1 — Commencement and foundation

Schedule B, R10,000. Target submission **9 October 2026** (week 3).

| Task | Deliverable | Status | Evidence |
|---|---|---|---|
| T01 | Verify Schedule A baseline and SHA-256 | **Done** | [T01_baseline_integrity.md](T01_baseline_integrity.md), re-run with `python tools/verify_baseline.py <PHILMART_DEVELOPER_SLIM folder> --report ...` |
| T02 | Client-accessible repository and project controls | **Done in repo, two GitHub settings pending** | This repository; [pull request template](../../.github/pull_request_template.md); workflow in [T04](T04_development_and_test_approach.md) |
| T03 | Architecture record (clause 8) | **Draft for review** | [ARCHITECTURE_RECORD.md](../architecture/ARCHITECTURE_RECORD.md) |
| T04 | Development and test approach, CI and quality gates | **Done** | [T04_development_and_test_approach.md](T04_development_and_test_approach.md), [ci.yml](../../.github/workflows/ci.yml) |
| T05 | Initial database and migration setup | **Done** | [database/](../../database), [migrate.sh](../../database/migrate.sh) |
| T06 | Deterministic test clock harness | **Done** | [TestClock.cs](../../tests/Philmart.IntegrationTests/Support/TestClock.cs), [TestClockTests.cs](../../tests/Philmart.IntegrationTests/TestClockTests.cs), [AuthoritativeTimeTests.cs](../../tests/Philmart.UnitTests/AuthoritativeTimeTests.cs) |

## Verified locally on 2 October 2026

- T01: 238 of 238 files re-hashed, 0 mismatches; manifest digest equals BRD 2.3.
- T05: all ten migrations applied to an empty SQL Server 2022 database; seed
  self-verification passed; 82 tables, 61 indexes, 30 triggers, 4 procedures,
  3 views, 4 security policies, 123 check constraints; re-run applied nothing;
  an edited migration was refused.
- Build: solution builds on .NET 10 with 0 warnings and 0 errors.
- Tests: 24 unit tests and 5 integration tests pass. The time guard was
  mutation-checked: adding a `DateTime.UtcNow` to `src/` fails the build.
- Frontend: lint, type check and production build pass.

## Still needed before submission

Actions for the repository owner:

1. **Client access (T02):** add the Client as a collaborator on
   `Developer-Ratnesh/PhilmartAPI` (or transfer it to a Client-owned
   organisation, clause 7).
2. **Branch protection (T02):** on `main`, require a pull request, one
   approving review and the three CI checks (`Database migrations`,
   `API build and tests`, `Frontend lint, types and build`).
3. Confirm the first CI run on GitHub is green.
4. Sign the T01 confirmation.

Decisions to ask the Client for in the submission notice:

1. Written confirmation of the .NET stack in place of the Development Guide's
   NestJS (architecture record section 1).
2. Identity provider (section 4), job runner (section 7), hosting and backups
   (sections 11–12).

## Known issues to declare (Schedule B1)

| # | Severity | Issue |
|---|---|---|
| 1 | Medium | Controlled migration `003_onboarding.sql` defaults `Shop_CommercialTerms.EffectiveFrom` from `SYSUTCDATETIME()` instead of `philmart.ServerNow()`, so the test clock does not move it (clause 9.2). Not edited because the file is controlled; raised as a query. Tracked as a known exception in `AuthoritativeTimeTests`. |
| 2 | — (fixed) | `Microsoft.OpenApi` 2.0.0, pulled in by `Microsoft.AspNetCore.OpenApi`, carried high-severity advisory GHSA-v5pm-xwqc-g5wc. Pinned to 2.7.5. |
| 3 | Low | The seed generators (`gen_seed.py`, `build_sql.py`) named in `database/README.md` are not in the controlled pack, so `010_seed.sql` is kept exactly as issued. |
| 4 | Info | The admin login screen is not yet wired to authentication (Milestone 2 scope). |
