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

- Deploy scripts run end to end in a fork test, and at each deployment milestone as a broadcast rehearsal on a local fork.
- Role hand-over: grant the new holders, verify them, then the deployer renounces; verify the final role set, including roles the configuration says the deployer keeps.
- Optional steps (seed deposits) do not block deployment.
- The verifier reads back every configured field (fees and recipients, limits, timelocks at their configured values) and has a negative test per field.
- Design policy (oracle age, decimals, discount bounds, caps) is enforced in the script.
- Gates and caps are attached before any external deposit is possible.
- Signing: keystore, hardware wallet or multisig; never a raw private key in an environment variable or file in the repository.
- Configs with real addresses stay local; per-chain deployment outputs are committed.
- Runbooks and bots read recorded amounts, not raw balances; monitoring alerts on the conditions the accepted risks depend on.
- A migration of a live system (new modules, moved positions, rotated roles) is scripted step by step, rehearsed on a fork of the live state, and read back by the verifier like a fresh deployment.
- Off-chain apps read contracts only through generated ABIs and addresses from the committed deployment files; a check fails when the ABIs drift from the contracts.

## Checks (local or CI)

- Per change: formatter and linter with every severity failing; check the configuration is actually valid, since an invalid one silently checks less. Contract size stays under EIP-170 (`forge build --sizes`).
- At milestones: static analysis (Slither or Aderyn) with findings triaged, the high-run fuzz and invariant profile, the whole fork suite.
- Fork tests in CI need an archive RPC from a secret with fork caching; a skipped fork test is reported, never silent. Where contract CI is manual, the PR states which checks ran locally.
- A grep over `src/` fails on development history in comments. Starting patterns, tuned per project: `\b(F|C|H|M|L|SEC|NEW)-[0-9]+\b`, `ADR-[0-9]+`, `\baudit\b`, `\b(review|retest)\b [A-Z]+-[0-9]`, `PR #[0-9]+`, `\b20[0-9]{2}-[0-9]{2}-[0-9]{2}\b`, plus the project's requirement-ID prefixes.

## Formal verification (optional, final audit round only)

Optional: the human decides at Gate 2 whether the final round includes it, and the loop never blocks on it. Without it, the custom core rests on fuzz and invariant tests and the full-scope audit. When it is planned, run it once, after the full-scope audit findings are fixed, on the custom core: the code a library does not already cover. Earlier runs are redone after every fix and spend most of their effort on model gaps. Certora Prover is the usual tool; record the tool version and the commit. It needs a key and runs in the vendor's cloud, so ask the human for it; typecheck the specs locally first (`certoraRun <conf> --compilation_steps_only`). After a later fix, rerun only the confs whose code it changed.

- **Properties from the invariant, not from the code:** the exit needs no price read or replaceable contract; the valuation view never reverts; no function lowers a holder's claim except their own exit; rounding never favours the caller; deposit then redeem never gains. Requirement IDs go in the rule names and the spec notes.
- **Third parties as adversarial models:** each external call may revert or return any value within a realistic bound. A rule then proves that the project adds no failure or leak of its own, not that the venue pays; say so in the results.
- **Bounds are stated:** amounts, indices and timestamps carry a `require` with its reason. Library assembly the solver cannot finish (for example 512-bit `mulDiv`) is replaced by its exact semantics, never by a weaker one.
- **A counterexample is a bug or a model gap.** A gap (a state no path reaches, a model that pays when the real protocol would not) is closed by making the model faithful, never by weakening the property; record each gap and its closure.
- **Mutation check:** plant known defects in a scratch copy of `src/` (a removed role check, a flipped rounding, a skipped record update) and run each against the rule meant to catch it. A surviving mutant shows a model gap or a missing rule.
- **Results table per conf:** rules, verified, not verified with the reason (timeout, no verdict, unreachable function), and what unit or fuzz tests cover instead. A rule with no verdict is reported as not proved, not as passed.
