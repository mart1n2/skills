# Templates

Keep IDs stable so tests, docs and findings can cite them (never `src/` comments). Examples use a neutral `Vault` with `Adapter` modules; rename to the project's domain.

## Enriched PRD (`docs/PRD.md`; the original stays unedited)

```
# <Product> PRD (enriched)
Source: docs/prd/original.md (unedited). Status: draft | confirmed at Gate 1 by <who> on <date>

## 1. Goals and non-goals          each line: [orig §2] stated | [derived] | [assumption Q-03]
## 2. Users, actors and roles       who, what they may do, trust level
## 3. Assets, chains, venues        listed explicitly, with what may vary later
## 4. Flows                         per flow: happy path, failure paths, who can trigger
## 5. Numbers                       caps, LTV, slippage, fees, delays (value or Q-NN)
## 6. Economics and fairness        who earns or bears what in normal, stressed, default cases
## 7. Third parties                 what is relied on, what happens when it fails
## 8. Deferred scope and triggers
## 9. Open questions                Q-NN list below
## 10. Traceability                 original section -> PRD section -> TRD IDs
```

## Open questions

| # | Source | Question | Options and consequence | Recommendation | Kind | Status |
|---|---|---|---|---|---|---|
| Q-01 | orig §4 "keepers rebalance when needed" | Who may trigger an emergency unwind, and when? | anyone (liveness, griefing risk) / keeper only (needs a live keeper) | keeper, permissionless after 24h | architecture | open |
| Q-02 | orig §3 "a USDC vault" | Fixed to USDC, or other assets later? | fixed (simpler) / generic asset (no rewrite later) | generic asset | architecture | open |
| Q-07 | orig §5 "low fees" | Management fee? | 0 / 0.5% / 1% | 0.5% | detail (default) | open |

## Gate 1 decision brief (one page)

```
Decide: 1) <architecture decision> 2) <business decision> ...
For each: options | consequence | recommendation (first) | evidence (prototype, fork, simulation)
Detail questions with defaults: Q-07..Q-19 (reply "use the recommendations" to accept all)
Design review: N findings, M folded into options, K open
Speculative work done on the recommended options: ...
```

## Decision log

| Date | Decision | Reason | Requirements changed | Decided by |
|---|---|---|---|---|

## Architecture (`docs/architecture.md`)

```
# <Product> architecture        Status: proposed | agreed at Gate 1 by <who> on <date>
## 1. Context                   PRD goals served; the non-negotiable invariant
## 2. Components                each contract: responsibility, reused library or upstream, custom code size
## 3. Value and call flows      deposit, allocate, exit, settle, emergency: who calls what, where funds sit
## 4. Accounting and valuation  where state lives, which view prices what, rounding
## 5. External integrations     per protocol: entry points, sync or async, admin powers, recovery
## 6. Roles and governance      role matrix, timelocks, risk-reducing emergency powers
## 7. Upgrade model             choice and reason
## 8. Off-chain components      keepers, bots, runbooks, monitoring: inputs they trust
## 9. Decisions                 links to ADRs
## 10. Requirement mapping      TRD ID -> component
```

## ADR (`docs/adr/NNN-<title>.md`)

```
# ADR-NNN <decision>            Status: proposed | accepted <date> by <who> | superseded by ADR-MMM
Context: the PRD need and the facts (fork spikes) that constrain it
Options: A / B / C with trade-offs (custom code, lock risk, trust, cost, what it rules out)
Decision and reason
Consequences: requirements, tests and risks it creates
```

## TRD tables

Requirement:

| ID | Requirement | Test(s) |
|---|---|---|
| WD-01 | `withdraw` never depends on an oracle read | `test_WithdrawWhenFeedStale`, `invariant_exitAlwaysPossible` |

Role and permission matrix:

| Function | Caller | Delay | Risk-reducing only? | Removable by |
|---|---|---|---|---|
| `setCap` (lower) | curator | none | yes | owner |
| `setCap` (raise) | curator | 3d timelock | no | owner |

Deferred scope:

| Feature | Why deferred | Trigger that forces it |
|---|---|---|
| Async withdrawal queue | expected withdrawals fit instant liquidity | illiquid share above a set threshold, or public deposits |

Formula table:

| Formula | Where | Rounding (against the caller) | Library |
|---|---|---|---|
| shares = assets * supply / totalAssets | deposit | down | OZ `Math.mulDiv(..., Rounding.Floor)` |
| shares = assets * supply / totalAssets | withdraw (assets given, shares burned) | up | OZ `Math.mulDiv(..., Rounding.Ceil)` |
| debt = principal * index / 1e18 | accrue | up | Solady `mulDivUp` |
| custom curve f(x) | pricing | ? | none: Halmos and review target |

Upgrade model:

| Contract | Model | Reason | Who changes what, with what delay | Time users need to exit (must be shorter than the delay) |
|---|---|---|---|---|
| Vault | immutable | core logic is stable; flexibility comes from swappable modules | none | n/a |
| Adapter | immutable + timelocked setters | integration addresses change upstream | curator, 3d; limits lowered at once | < 1d |

Third-party dependency (verdict per row: OK if bounded DoS with recovery, redesign if a permanent lock is possible):

| Dependency | What its admins can change | Delay | Worst case for our funds | Recovery |
|---|---|---|---|---|
| DEX router | replace router, pause | none | swaps revert (DoS) | timelocked `setRouter`; exit via another venue |
| Price feed | deprecate | announced | stale price blocks valuation | exit path does not read the feed |

Exit liquidity:

| Route | Size | Quote received | Depth | Cap derived |
|---|---|---|---|---|
| collateral -> stablecoin -> USDC | 1M | 0.999 | ok | ceiling 1-2M |
| same | 5M | 0.778 | thin | |

Invariants:

| ID | Property | Handler actions |
|---|---|---|
| INV-01 | recorded positions equal assets actually held, within rounding | deposit, allocate, deallocate, accrue, donate |
| INV-02 | after any sequence, every holder can exit | all |
| INV-03 | allowances to venues are zero between calls | all |

## Traceability matrix

| Original § | PRD § | TRD ID | Component | Tests |
|---|---|---|---|---|
| §4 | 4.2 | WD-01 | Vault | test_WithdrawWhenFeedStale, invariant_exitAlwaysPossible |

## Delivery plan (`docs/plan.md`)

```
Status: proposed | signed at Gate 2 by <who> on <date>
| # | Slice (one PR) | Requirement IDs | Acceptance tests | Depends on | Risk it retires | Done when |
|---|---|---|---|---|---|---|
| 1 | Vault core + first adapter | VLT-01..05, ADP-01..04 | unit, fuzz, INV-01/02, fork | - | valuation never reverts | CI green, audit-lite PR pass |
Milestones: M1 after slice 3 (full-scope audit-lite, fork rehearsal), M2 testnet, M3 external audit, M4 mainnet
CI: workflow, profiles, archive RPC secret, fork caching, static analysis
Budget per milestone: ...
Deferred: ...            Open risks carried: ...
```

## Spec sign-off

| Version / commit | Gate | Signed off by | Date | Assumptions accepted |
|---|---|---|---|---|

## Findings index (`docs/findings.md`, committed)

| ID | Severity | Layer | Status | Fixing commit | Regression test | Note |
|---|---|---|---|---|---|---|
| F-01 | High | code | fixed | abc1234 | test_Regression_DustCannotFlipSettlement | |
| F-04 | Low | spec | accepted | | test_Regression_ExitMayUseReservedCash | intended; spec amended |
