# Checklists

## Adversary checklist

Walk every state-changing function and every view the system relies on.

- **Donations and dust.** Anyone can send tokens, shares or 1 wei to any address. Never infer state (executed / cancelled, profit, equity, health) from a raw `balanceOf` delta; compare against recorded amounts. Add donations to the invariant handlers.
- **Flash and same-block actors.** A deposit, borrow and withdrawal in one transaction or block: can it move a rate quote, bypass a utilisation cap or rate limit, capture a NAV step-up, a recovery or a write-off? Exclude same-block deposits from quotes and limits where needed.
- **Reentrancy.** Including read-only reentrancy: views (ERC-4626 `totalAssets`, NAV) read during an external callback or a third-party hook.
- **Repeated calls.** Per-call caps drained by looping; limits must be per period or global.
- **Griefing.** Inputs that make a keeper batch, a settlement or a post-check revert for everyone (inflated balances, dust positions, malformed return data decoded outside `try/catch`).
- **Caller-supplied routes and calldata.** The contract enforces a minimum output and an arrival check from its own price source; it never trusts the route's return value. No fallback lowers that minimum, and no tolerance widens with time for anyone who can simply wait. Any slippage a permissionless caller may choose is value they can take on every call: keep it measured and tight, or restrict who picks the route.
- **Third-party callbacks.** Prefer reading the protocol's own state over relying on callbacks whose gas, ordering and failure handling the third party controls.
- **Approvals.** Who has an allowance to what, and can a module that is trusted for one token use an allowance meant for another? Pin the token at approval; exact approvals, reset to zero.
- **Privileged roles.** Can a role veto its own removal (for example a guardian with a canceller role)? Can an emergency role do more than reduce risk?
- **Third-party admins.** Pause, upgrade, parameter cut (collateral factor, caps), router replacement, allowlist changes, seizure of dust or allowlisted positions.
- **Initialization and deployment windows.** Anything callable before gates, roles or caps are set.

## Valuation and degraded-mode checklist

- Value = what the exit returns now (swap output, protocol redemption rate), not an oracle mark; measure the gap on a fork.
- For each feed: who updates it, heartbeat, behaviour at maturity or deprecation, history of manipulation (TWAP on thin markets), and lag against the market measured on a fork. Prefer the most liquid reference (for example BTC/USD over a wrapped token's own feed).
- For each external read × each function: behaviour when it reverts, is stale, or returns garbage. Fallbacks commit unit prices, not totals, and never relax a safety bound.
- The valuation view never reverts.
- After a full exit, nothing of value remains at the venue (interest, refunds, credits): add it as an invariant.

## Exit liquidity checklist

- Quote the real exit route at 1x, 5x and 10x the intended size.
- Sum the sizes of every position that shares the route or underlying (several collaterals selling through the same asset compete for the same depth).
- Derive caps and ceilings from depth at the acceptable slippage; record the numbers and the date.
- Record correlated exposures (same issuer, same stablecoin, same venue) for disclosure.

## Deploy and operations checklist

- Deploy scripts run end to end on a fork in CI.
- Role hand-over: remove before add, never strip roles the configuration says the deployer keeps; verify the final role set.
- Optional steps (seed deposits) do not block deployment.
- The verifier reads back every configured field (fees, limits, timelocks at their configured values, not a floor) and has a negative test that changes each field and expects failure.
- Policy from the design (oracle age, decimals, discount bounds, caps) is enforced in the script.
- Gates and caps are attached before any external deposit is possible.
- Configs with real addresses stay local; deployment outputs per chain are committed.
- Runbooks and bots use recorded amounts, not raw balances; batch with multicall; monitoring alerts on the conditions the accepted risks depend on.
- CI gates are actually enforced (lint config valid, fork tests not silently skipped).
