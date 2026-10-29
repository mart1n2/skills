# Checklists

## Adversary

Walk every state-changing function and every view the system relies on.

- **Donations and dust.** Anyone can send tokens, shares or 1 wei to any address. Never infer state (executed or cancelled, profit, equity, health) from a raw `balanceOf` delta; compare against recorded amounts. Add donations to the invariant handlers.
- **Share inflation.** First-depositor and donation attacks on share accounting: use virtual shares or a decimals offset (OpenZeppelin ERC4626 `_decimalsOffset`), or a seeded, burned first deposit.
- **Spot prices.** A spot reserve or single-block swap quote is moved by a flash loan inside one transaction; never let it gate deposits, borrows, liquidations or share price.
- **Flash and same-block actors.** A deposit, borrow and withdrawal in one transaction or block: can it move a rate quote, bypass a cap or rate limit, or capture a NAV step-up, a recovery or a write-off? Exclude same-block deposits from quotes and limits where needed.
- **Reentrancy**, including read-only: views (ERC-4626 `totalAssets`, NAV) read during an external callback or third-party hook.
- **Repeated calls.** Per-call caps drained by looping; limits must be per period or global.
- **Griefing.** Inputs that make a keeper batch, settlement or post-check revert for everyone: inflated balances, dust positions, malformed return data decoded outside `try/catch`.
- **Caller-supplied routes and calldata.** The contract enforces a minimum output and an arrival check from its own price source and never trusts the route's return value. No fallback lowers that minimum, and no tolerance widens over time for anyone who can wait. Slippage a permissionless caller may choose is value they take on every call: keep it measured and tight, or restrict who picks the route.
- **Third-party callbacks.** Prefer reading the protocol's own state over callbacks whose gas, ordering and failure handling the third party controls.
- **Approvals.** Who holds an allowance to what, and can a module trusted for one token use an allowance meant for another? Pin the token at approval; exact approvals, reset to zero.
- **Privileged roles.** Can a role veto its own removal (for example a guardian that can cancel timelocked proposals)? Can an emergency role do more than reduce risk?
- **Third-party admins.** Pause, upgrade, parameter cuts (collateral factors, caps), router replacement, allowlist changes, seizure of dust or allowlisted positions.
- **Initialization and deployment windows.** Anything callable before gates, roles or caps are set; uninitialized implementations behind proxies (`_disableInitializers()`).

## Valuation and degraded modes

- Choose and bound the price source by what the exit really returns, measured off-chain on a fork; report the gap between mark and realizable value.
- Per feed: who updates it, heartbeat, behaviour at maturity or deprecation, manipulation history (TWAPs on thin markets), lag against the market measured on a fork. Prefer the most liquid reference, and price any wrapper or bridge depeg separately rather than assuming 1:1.
- Per external read and per function: behaviour when it reverts, is stale or returns garbage. Fallbacks commit unit prices, not totals, and never relax a safety bound.
- The valuation view never reverts.
- After a full exit nothing of value remains at the venue (interest, refunds, credits): an invariant.

## Exit liquidity

- Quote the real exit route at 1x, 5x and 10x the intended size.
- Sum every position that shares the route or underlying; they compete for the same depth.
- Derive caps from depth at the acceptable slippage; record the numbers and the date.
- Record correlated exposures (same issuer, stablecoin or venue) for disclosure.

## Deploy and operations

- Deploy scripts run end to end on a fork in CI.
- Role hand-over: grant the new holders, verify them, then the deployer renounces; verify the final role set, including roles the configuration says the deployer keeps.
- Optional steps (seed deposits) do not block deployment.
- The verifier reads back every configured field (fees and recipients, limits, timelocks at their configured values) and has a negative test per field.
- Design policy (oracle age, decimals, discount bounds, caps) is enforced in the script.
- Gates and caps are attached before any external deposit is possible.
- Signing: keystore, hardware wallet or multisig; never a raw private key in an environment variable or file in the repository.
- Configs with real addresses stay local; per-chain deployment outputs are committed.
- Runbooks and bots read recorded amounts, not raw balances; monitoring alerts on the conditions the accepted risks depend on.

## CI

- Formatter, linter and static analysis (Slither or Aderyn) run and fail the build; check the configuration is actually valid, since an invalid one silently checks less.
- Fork tests run against an archive RPC from a CI secret with fork caching; a skipped fork test is reported, never silent.
- Contract size stays under EIP-170 (`forge build --sizes`).
- A grep over `src/` fails on development history in comments. Starting patterns, tuned per project: `\b(F|C|H|M|L|SEC|NEW)-[0-9]+\b`, `ADR-[0-9]+`, `\baudit\b`, `\b(review|retest)\b [A-Z]+-[0-9]`, `PR #[0-9]+`, `\b20[0-9]{2}-[0-9]{2}-[0-9]{2}\b`, plus the project's requirement-ID prefixes.
