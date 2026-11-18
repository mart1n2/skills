# Templates

These are sections, not files: put them in as few documents as the project needs (a spec, a research note per protocol, a plan per change, a progress document). Keep IDs stable so tests, docs and findings can cite them (never `src/` comments). Examples use a neutral `Vault` with `Adapter` modules; rename to the project's domain.

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
For each decision, two to four options that differ in mechanism, the recommended one first:
|                              | A (recommended) | B | C |
| Mechanism in one line        |
| Risk to funds, lock risk     |
| Trust and roles              |
| Custom code, audit surface   |
| Third-party dependence       |
| Cost: gas, fees, keepers     |
| Operations burden            |
| User experience              |
| Time to build                |
| Rules out later              |
| Evidence                     | protocol study, prototype, fork, simulation
Considered and dropped: <candidate>: <one-line reason>; ...
Detail questions with defaults: Q-07..Q-19 (reply "use the recommendations" to accept all)
Design review: N findings, M folded into options, K open
Speculative work done on the recommended options: ...
```

## Decisions (a section of the spec, or of the change plan for a change)

| ID | Decision | Options compared; candidates dropped | Reason | Requirements changed | Decided by, date |
|---|---|---|---|---|---|

## Protocol study (one per integrated protocol, before its architecture options)

```
# <Protocol> study     deployment and version studied, date; sources read (docs, repository at a commit, verified source, audited integrators)
## 1. What it is for              its users and economics: who earns, who pays, what the protocol protects itself against
## 2. Routes to the outcome needed
| Route | Entry points | Sync or async, who executes | Cost: protocol fee, execution fee, gas, price impact | Limits: minimum size, caps, delays, cooldowns | What the protocol records | Custom code this route needs |
## 3. Native features that could replace custom code     its own orders, automation, hooks, batching, isolation, accounting it already keeps
## 4. Admin powers and failure modes                     feeds the third-party dependency table
## 5. How others integrate it                            official periphery, audited integrations, known incidents
## 6. Choice                      route chosen, what it removed from the design, the assumptions left to check on a fork
```

## Architecture (a section of the spec, or its own file where the project separates it)

```
# <Product> architecture        Status: proposed | agreed at Gate 1 by <who> on <date>
## 1. Context                   PRD goals served; the non-negotiable invariant
## 2. Components                each contract: responsibility, reused library or upstream, custom code size
## 3. Value and call flows      deposit, allocate, exit, settle, emergency: who calls what, where funds sit
## 4. Accounting and valuation  where state lives, which view prices what, rounding
## 5. External integrations     per protocol: route chosen from its study, entry points, sync or async, admin powers, recovery
## 6. Roles and governance      role matrix, timelocks, risk-reducing emergency powers
## 7. Upgrade model             choice and reason
## 8. Off-chain components      keepers, bots, runbooks, monitoring: inputs they trust
## 9. Decisions                 the decisions table
```

## Decision, long form (only when one needs more than a page)

```
# <ID> <decision>              Status: proposed | accepted <date> by <who> | superseded by <ID>
Context: the PRD need and the facts (fork spikes) that constrain it
Options: A / B / C compared on the decision brief's dimensions; candidates dropped before the gate, one line each
Decision and reason
Consequences: requirements, tests and risks it creates
```

## TRD tables

Requirement:

| ID | Requirement | Source | Component | Test(s) |
|---|---|---|---|---|
| WD-01 | `withdraw` never depends on an oracle read | orig §4, PRD 4.2 | Vault | `test_WithdrawWhenFeedStale`, `invariant_exitAlwaysPossible` |

Source, component and tests are the traceability; no separate matrix is kept.

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
| custom curve f(x) | pricing | ? | none: review target, fuzz and invariant tests; a formal rule if verification is planned |

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

## Change plan (one per change to a signed system; `docs/plans/<change>.md`)

```
# <Change> plan                Status: proposed | confirmed <date> by <who>
## 1. Scope                    what changes and what does not; requirement IDs touched
## 2. Options and decision     two to four options compared as in the decision brief; candidates dropped; decisions with IDs
## 3. Protocol study           link, when a protocol is used in a new way
## 4. Spec delta               changed requirements and decisions, old and new
## 5. Design                   interfaces, state, roles; sites of the same class, who can move each new input, budgets (gas, size)
## 6. Tests                    written before the code: unit, fuzz, invariant, fork, per requirement ID
## 7. Delivery                 slices, one PR each, in order
## 8. Deployment or migration  scripts, rehearsal, runbook, read-back
## 9. Risks                    accepted, with reason; deferred, with trigger
## 10. Review                  independent review findings and how each was resolved
```
Leave out a section the change does not need; a one-function feature may be half a page.

## Delivery plan (`docs/plan.md`)

```
Status: proposed | signed at Gate 2 by <who> on <date>
| # | Slice (one PR) | Requirement IDs | Acceptance tests | Depends on | Risk it retires | Done when |
|---|---|---|---|---|---|---|
| 1 | Vault core + first adapter | VLT-01..05, ADP-01..04 | unit, fuzz, INV-01/02, fork | - | valuation never reverts | checks green, diff audit-lite where due |
Milestones (heavy checks run only here, SKILL.md "Cadence"): M1 after slice 3 (full-scope audit-lite, high-run fuzz, fork rehearsal), M2 testnet, M3 final audit round (full-scope audit-lite; formal verification: yes or no) and external audit, M4 mainnet
Checks: run locally or in CI, test profiles, archive RPC secret, fork caching, prover key if formal verification is planned
Budget per milestone: ...
Deferred: ...            Open risks carried: ...
```

## Spec sign-off

| Version / commit | Gate | Signed off by | Date | Assumptions accepted |
|---|---|---|---|---|

## Fix evaluation (before the fix is coded; kept with the finding in the audit workspace)

```
F-NN fix evaluation
Property to restore: <requirement or invariant ID>
Sites of the same class: every sibling path, fallback and caller; for each, covered by the fix or why not
New inputs:
| State, check or revert the fix adds | Who can move its inputs | Worst case |
Budgets and neighbours: gas margins, contract size, interfaces and ABIs, runbooks, bots, docs
Designs, simplest first: remove or restrict the feature / tighten an existing check / new mechanism / accept the risk
Chosen: <design>, and why each simpler one does not serve
Design challenge: reviewer and result (required when the fix adds state, a revert path, a role or an interface change)
```

## Findings index (committed: its own file, or a section of the progress document or the audit report)

| ID | Severity | Layer | Status | Fixing commit | Regression test | Note |
|---|---|---|---|---|---|---|
| F-01 | High | code | fixed | abc1234 | test_Regression_DustCannotFlipSettlement | |
| F-04 | Low | spec | accepted | | test_Regression_ExitMayUseReservedCash | intended; spec amended |
