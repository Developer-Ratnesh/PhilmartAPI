## What this changes

<!-- One or two sentences. -->

## Requirements and decisions

<!-- Every BR requirement ID and decision ID this implements or touches, e.g. BR-13-R04, D021. -->

- 

## Tests

<!-- Which tests prove it. Name the test classes; new tests carry [Trait("BR", "...")]. -->

- 

## Checklist

- [ ] No business rule in a controller or React component (architecture record section 5)
- [ ] Shop scope comes from `TenantContext`, never from request input (clause 9.1)
- [ ] Time comes from `IServerClock` / `philmart.ServerNow()` (clause 9.2)
- [ ] History is corrected by reversal or superseding record, never edited or deleted (clause 8)
- [ ] Database change is a new migration; no applied migration was edited
- [ ] Architecture record updated if a decision changed
- [ ] Known Critical, High or security-relevant issues declared below

## Known issues

<!-- Anything this leaves open. "None" if none. -->
