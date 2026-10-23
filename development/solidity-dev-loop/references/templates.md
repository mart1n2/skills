# Design artifact templates

Use these in the spec / design documents. Keep IDs stable so tests and audit findings can cite them.

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
