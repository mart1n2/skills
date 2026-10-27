# Design artifact templates

Use these in the spec / design documents. Keep IDs stable so tests and audit findings can cite them.

## Enriched PRD (`docs/PRD.md`; the original stays unedited)

```
# <Product> PRD (enriched)
Source: docs/prd/original.md (unedited). Status: draft | confirmed by <who> on <date>

## 1. Goals and non-goals          each line: [orig §2] stated | [derived] | [assumption Q-03]
## 2. Users, actors and roles       who, what they may do, trust level
## 3. Assets, chains, venues        listed explicitly, with what may vary later
## 4. Flows                         per flow: happy path, failure paths, who can trigger
## 5. Numbers                       caps, ceilings, LTV, slippage, fees, delays (value or Q-NN)
## 6. Economics and fairness        who earns or bears what in normal, stressed, default cases
## 7. Third parties                 what is relied on, what happens when it fails
## 8. Deferred scope and triggers
## 9. Open questions                Q-NN list below
## 10. Traceability                 original section -> PRD section -> TRD IDs
```

## Open questions (until sign-off)

| # | Source | Question | Options and consequence | Recommendation | Owner | Status |
|---|---|---|---|---|---|---|
| Q-01 | orig §4 "keepers rebalance when needed" | Who may call `emergencyDelever`, and when? | anyone (liveness, griefing risk) / keeper only (needs a live keeper) | keeper only, plus permissionless after 24h | human | open |
| Q-02 | orig §3 "USDC vault" | Is the vault asset fixed to USDC, or will ETH/BTC vaults follow? | fixed (simpler) / generic asset (no rewrite later) | generic asset | human | open |

## Decision log

| Date | Decision | Reason | Requirements changed | Decided by |
|---|---|---|---|---|
| 2026-10-10 | Rebalancing goes through one `rebalance()`; no permissionless delever | fewer entry points, keeper is monitored | CARRY-03, CARRY-07 | product owner |

## Spec sign-off

| Version / commit | Signed off by | Date | Assumptions accepted at sign-off |
|---|---|---|---|

## Requirement

| ID | Requirement | Test(s) |
|---|---|---|
| WD-01 | `withdraw` never depends on an oracle read | `test_WithdrawWhenFeedStale`, `invariant_exitAlwaysPossible` |

## Deferred scope

| Feature | Why deferred | Trigger that forces it |
|---|---|---|
| Async withdrawal queue | Few, known investors | More than two illiquid venues, or a public deposit |

## Formula table

| Formula | Where | Rounding | Library |
|---|---|---|---|
| shares = assets * supply / totalAssets | deposit | down (favours vault) | OZ `Math.mulDiv(..., Rounding.Floor)` |
| debt = principal * index / 1e18 | accrue | up | Solady `mulDivUp` |
| custom curve f(x) | pricing | ? | none: flag for Halmos + review |

## Upgrade model

| Contract | Model | Reason | Who can change what, with what delay | User exit window |
|---|---|---|---|---|
| Vault | immutable | upstream vault is immutable; flexibility comes from swappable adapters | none | n/a |
| Adapter | immutable + timelocked setters | integration addresses change upstream | curator, 3d timelock; limits lowered instantly | > 3d |

## Third-party dependency

| Dependency | What its admins can change | Delay | Worst case for our funds | Our response / recovery |
|---|---|---|---|---|
| DEX router | replace router, pause | none | swap reverts (DoS) | timelocked `setRouter`; exit via other venue |
| Oracle feed | deprecate feed | announced | stale price blocks valuation | exit path does not read the feed |

Verdict per row: OK (bounded DoS with recovery) / redesign (permanent lock possible).

## Exit liquidity

| Route | Size | Quote received | Depth | Cap derived |
|---|---|---|---|---|
| PT -> underlying -> USDC | 1M | 0.999 | ok | ceiling <= 1-2M |
| same | 5M | 0.778 | thin | |

## Invariants

| ID | Property | Handler actions |
|---|---|---|
| INV-01 | sum of recorded positions == assets actually held (within rounding) | deposit, allocate, deallocate, accrue |
| INV-02 | after any sequence, every holder can exit | all |
| INV-03 | token allowances to venues are zero between calls | all |
