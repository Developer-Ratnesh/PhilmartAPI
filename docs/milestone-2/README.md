# Milestone 2: First integrated build

Schedule B, R8,000. Delivery Plan target 27 November 2026 (week 10).

Schedule B trigger: a working staging build with registration and login, Shop
permissions and isolation, item browsing, Buy Now, auction bidding,
authoritative close, soft close, outage and recovery behaviour, and relevant
tests.

## Status against the trigger

| Item | Status | Where |
|---|---|---|
| Registration and login | Built, tested | BR-01 below |
| Shop permissions and isolation | Built, tested | BR-08 below |
| Item browsing | Built | BR-02 below |
| Buy Now | Built, tested | BR-03 below |
| Auction bidding | Built, tested | BR-03, BR-13 |
| Authoritative close | Built, tested | `AuctionCloser`, `P_List_Auction_Close` |
| Soft close | Built, tested | `P_List_Bid_Place`, `AuctionTests` |
| Outage and recovery | Built, tested | sweep on startup and every 5 s |
| Relevant tests | 54 integration, 24 unit, all passing, plus a 41-check end-to-end run on a freshly built database | `tests/` |
| Emails actually sent | Built, tested. Every email uses one PHILMART layout with the logo, HTML and plain text | `EmailJob`, `EmailDispatcher`, `EmailLayout`, `EmailDispatchTests`, `EmailLayoutTests` |
| Staging build | Database ready | `db_acd9e3_philmart` on site4now has 001 to 014 and the demo data. The API and site are deployed by us |

## Requirements

Every test carries its BR ID as an xUnit trait, so
`dotnet test --filter "BR=BR-13-R05"` runs the tests for one requirement.

### BR-01 Buyer registration, login and legal acceptance

| Req | Status | Evidence |
|---|---|---|
| R01 four steps, registered only at step 4 | Done | `Four_steps_and_the_welcome_email_only_at_the_end` |
| R02 EML-019 verification, doesn't imply registration | Done | same test. Buyer verifies with a 4-digit PIN per SCR-PUB-014.1 |
| R03 EML-020 only on completion (D036) | Done | same test |
| R04 exact versions stored | Done | `Acceptance_is_stored_by_version...`, `Accepting_an_old_version_is_refused` |
| R05 append-only, renewal is a new row | Done | same, plus `Superseded_terms_block...` |
| R06 shipping preferences per method (D037, D009) | Done | registration step 3 |
| R07 identity read-only after registration (D039) | Done | `Identity_is_read_only_once_registered` |
| R08 only optional emails controllable (D040) | Done | `Only_the_outbid_alert_can_be_switched_off` |
| R09 login, renewal gate before commitment | Done | `Superseded_terms_block...`, `Sign_in_pin_works_only...` |
| R10 audit of registration and acceptance | Done | audit rows on every step |

### BR-02 Public marketplace and discovery

| Req | Status | Notes |
|---|---|---|
| R01 public home | Existing page | |
| R02 grid and list over one query | Existing page | |
| R03 classification-driven browsing | Existing page | |
| R04 only live listings of active Shops | Done | `Only_live_listings_of_active_shops_are_public`, plus migration 011 |
| R05 storefront, no commitments on a deactivated Shop | Done | `/shop/{id}`, `Deactivated_shop_takes_no_new_purchases` |
| R06 sample values aren't rules (D053) | Followed | no invented limits |
| R07 support form | Done | `/support`, `SupportTests`. Migration 014 adds `Sys_SupportRequest`. The on-screen reference is the confirmation, the email is a copy (SCR-PUB-015 says so) |
| SCR-PUB-008 Recently Viewed, SCR-PUB-009 Saved Items | Done | `/account/recent`, `/account/saved`, `BuyerListTests`. Kept per buyer behind `BuyerSelfPolicy` |

### BR-03 Item detail, Buy Now and Confirm Bid

| Req | Status | Evidence |
|---|---|---|
| R01 two variants | Done | `/item/{id}`, `Item_detail_has_what_the_buyer_needs` |
| R02 commitment wording, version recorded | Done | `Commitment_wording_must_be_the_version_shown` |
| R03 any offered method, default pre-filled (D009) | Done | purchase defaults endpoint |
| R04 override for this transaction only (D038) | Done | `Buy_now_snapshots_delivery_and_leaves_the_profile_alone` |
| R05 immutable snapshot (D042) | Done | same test |
| R06 not below Seller Minimum Price (D062) | Done | `Nothing_can_be_listed_below_the_seller_minimum` |
| R07 item detail content | Done | images show once BR-10 image upload exists |
| R08 restriction enforced server-side (D044) | Done | `Restricted_buyer_is_refused_at_the_commitment_point` |
| **R09 Ask Shop a Question** | **Not done** | belongs with BR-05/BR-20 Buyer Queries (Milestone 4 in the plan) |

### BR-08 Shop users and permissions

| Req | Status | Evidence |
|---|---|---|
| R01 Shop user administration | Done | `/workspace/users` |
| R02 no role layer (D050) | Done | `Permissions_go_straight_onto_one_user` checks no role table exists |
| R03 administrator holds everything | Done | `Shop_administrator_holds_every_permission` |
| R04 editing changes that user only (D051) | Done | `Permissions_go_straight_onto_one_user` |
| R05 disable removes access, keeps history (D049) | Done | `Disabled_user_loses_access_at_once...` |
| R06 server-side authorisation, client Shop ID ignored | Done | `A_token_for_one_shop_cant_be_bent_to_another` and the API tests |
| R07 database safeguards | Done | `Row_level_security_holds_even_without_the_api` |
| R08 tests that attempt cross-Shop access | Done | `ShopIsolationTests`, 8 tests |
| R09 isolation failure is Critical | Covered by R08 | |

### BR-13 Auctions and bidding

| Req | Status | Evidence |
|---|---|---|
| R01 start in the future, end after start, states | Done | `Auction_must_start_in_the_future_and_opens_on_time` |
| R02 server time only | Done | test clock, `AuthoritativeTimeTests` |
| R03 soft close | Done | `Last_second_bid_extends_the_close...` |
| R04 transactionally safe | Done | `Simultaneous_bids...`, `Racing_bids_keep_a_clean_order` |
| R05 the clause 9.2 test list | Done | simultaneous, duplicate, ordering, last-second, soft close, simultaneous closes, outage and recovery |
| R06 unsold returns to Ready to List, listing read-only (D012) | Done | `After_an_outage_one_sweep_closes_everything_correctly` |
| R07 exceptional cancellation with bids (D016) | Done | `Cancelling_with_bids_is_exceptional_and_keeps_the_bids` |
| R08 EML-012 on a win | Done (queued) | `Close_picks_the_highest_bid...` |
| R09 outbid throttle, email only (D068) | Done | `Outbid_emails_are_throttled_but_bids_never_are` |
| R10 EML-014 not built, EML-015 on exceptional cancel | Done | tests check both |
| R11 bid-bearing auction runs to end despite deactivation (D033) | Done | bidding stays open when bids exist |
| R12 effective minimum not below Seller Minimum | Done | BR-03-R06 test, plus a check when creating |
| R13 invalid outcome is Critical | Covered | close tests |
| Auction events, bulk auctions (SCR-SHP-007 and bulk screens) | **Not done** | BR-14 is Milestone 4, bulk upload is BR-11 (Milestone 3) |

## Changes to the controlled schema, raised with the Client

001 to 010 are untouched. 011 to 013 fix defects that stopped M2 working and
014 adds the tables BR-02 needs. Each file explains itself in its header.

| Migration | Problem in the controlled schema | Severity if left |
|---|---|---|
| `011_catalogue_and_system_access.sql` | RLS hid every listing and item from the public and from buyers, and nothing admitted the `system` actor the jobs use. Bidding could not succeed. | Critical: no marketplace, no bidding |
| `012_permission_revoke.sql` | DELETE is denied schema-wide and the grants table has no revoked flag, so a permission could never be taken away (D051). | High |
| `013_unsold_auction_close.sql` | `P_List_Auction_Close` broke `CK_item_ready_since` on every unsold auction, so it never closed and the job retried for ever. | Critical: invalid auction outcome |
| `014_support_saved_recent.sql` | No tables for the support form (SCR-PUB-015), Saved Items (SCR-PUB-009) or Recently Viewed (SCR-PUB-008). | Medium: three BR-02 screens missing |

## Known issues to declare (Schedule B1)

| # | Severity | Issue |
|---|---|---|
| 1 | High | The staging database is ready, the API and site still need deploying to the server. |
| 2 | Medium | Emails only go out once `Email:Host` and the other SMTP settings are filled in. Until then they wait in `Sys_EmailMessage` and, in development, PINs and links go to the API log. |
| 3 | Low | The sign-in PIN, Shop user invitation and support copy aren't in the controlled email catalogue, so they're sent straight over SMTP and not stored. That also keeps the sign-in PIN out of the database. |
| 4 | Medium | All email templates in the seed have no subject or body. The code uses plain fallback wording that follows each rule until the Client supplies it. |
| 5 | Medium | Legal documents have no published versions in the controlled seed. The demo seed publishes placeholder text, which is what the staging database has now. The real wording has to replace it before production. |
| 6 | Medium | Admin sign-in has no MFA step yet (`Sys_PlatformUser.MfaSecret` exists). |
| 7 | Medium | Wrong-PIN counting is in memory, which is correct for one API instance only. |
| 8 | Medium | `ItemService.Transition` (BR-10, Milestone 3) has the same ready-to-list problem 013 fixes. Fix lands with BR-10. |
| 9 | Low | `003_onboarding.sql` defaults `EffectiveFrom` from `SYSUTCDATETIME()` (from Milestone 1). |
| 10 | Low | The controlled schema spells actor kinds and some audit actions `Buy_Buyer`, `Shop_User`, `Shop_Shop`. The code matches the schema exactly. |
| 11 | Info | Delivery tariffs are not seeded, so delivery prices are not shown yet. |

## Trying it locally

```bash
PHILMART_SQL_DATABASE=PhilmartDev ./database/migrate.sh
sqlcmd -S localhost -E -C -I -f 65001 -d PhilmartDev -i database/dev/seed_demo.sql
```

Every demo login uses the password `Philmart-dev-1`:

| Who | Where | Login |
|---|---|---|
| Buyer | `/register`, then `/login` | any email, PIN is in the API log |
| Shop administrator | `/workspace/login` | owner@capestamps.test |
| Shop staff | `/workspace/login` | staff@capestamps.test |
| Second Shop | `/workspace/login` | owner@highveld.test |
| PHILMART admin | `/admin/login` | admin@philmart.test (on staging the password is `admin@123`) |

One demo auction ends 10 minutes after the seed is loaded, so you can watch it close.
