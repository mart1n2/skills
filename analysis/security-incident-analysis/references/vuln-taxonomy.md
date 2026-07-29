# Incident Root-Cause Taxonomy

Classify the drained step into exactly one primary class (note secondaries). Each entry gives the **tell** (what you see on-chain / in the trace), the **invariant** it violates, how to **confirm on a fork** (the counterfactual toggle), and the **fix family**. Absence of a listed pattern is not proof of safety — these are precedents, not a checklist.

**Always test class 0 first.** It has the same fund-flow shape as a clever logic bug but demands entirely different remediation, and misattributing it discredits the whole report.

---

## 0. Access / key / governance compromise (the "boring cause")
- **Tell:** the drain caller *is* the owner/admin/multisig; or an `Upgraded(address)`/`AdminChanged` event or a privileged setter fires immediately before the drain; or the impl slot differs at `POST` vs `PRE`. No flash loan, no clever call sequence — just a privileged function moving funds.
- **Invariant:** Authorization — only the intended actor can move funds / upgrade.
- **Confirm:** show the entry function was permissioned and the caller held the role at `PRE`. If the impl changed mid-incident, the "logic bug" is in code that wasn't even live during the exploit.
- **Fix family:** timelock + multisig on privileged setters/upgrades; revoke EOA ownership; guardian separation.
- **Note:** could be a stolen key (off-chain) or a malicious insider (rug) — on-chain evidence rarely distinguishes them; report both as live hypotheses.

## 1. Oracle / price manipulation
- **Tell:** a price read (`getPrice`, `latestAnswer`, `get_virtual_price`, `getRate`, spot reserves) taken in the *same tx* the attacker moved the source pool; flash-loan pump → borrow/withdraw against the inflated mark → dump.
- **Invariant:** Oracle-integrity — the price used for a fund-effect is not manipulable within one tx.
- **Confirm:** replace the read with a manipulation-resistant value (TWAP / Chainlink at block) in the counterfactual → drain reverts or nets ~0.
- **Fix family:** TWAP / multi-source oracle, freshness+deviation bounds, no spot-price for solvency.

## 2. NAV / accounting inflation (vault-of-vaults, adapters, wrappers)
- **Tell:** `totalAssets`/NAV computed as `underlying.convertToAssets(underlying.balanceOf(self))` — counts shares *donated* directly into the contract (no reconciliation vs tracked principal) and marks them at `convertToAssets` even when the underlying is illiquid (`maxWithdraw==0`). Same-tx deposit → inject shares → redeem at inflated price. (Summer.fi FleetCommander class.)
- **Invariant:** Conservation / solvency — marked value ≤ realizable value; donations don't mint claims.
- **Confirm:** counterfactual reconciles NAV to tracked principal (ignore un-deposited donations) or gates redemption on realizable liquidity → inflated redeem fails.
- **Fix family:** internal principal accounting (donation-proof), realizability/illiquidity check before marking, deposit-vs-redeem same-tx guard.

## 3. Reentrancy (classic + read-only)
- **Tell:** an external call (token transfer, callback, `receive`) before a state update; or a *view* function returning stale price/NAV mid-callback that another contract trusts (read-only reentrancy).
- **Invariant:** state consistency across external calls.
- **Confirm:** counterfactual adds the guard / checks-effects-interactions ordering → reentrant path reverts.
- **Fix family:** nonReentrant, CEI ordering, read-only-reentrancy guards on shared price views.

## 4. ZK / verifier soundness (shielded/privacy pools, rollups, proof-gated withdrawals)
- **Tell:** the on-chain check is a **tautology** — it verifies "do I hold enough to pay this?" which is trivially true after honest deposits, delegating *all* value conservation to the proof; and one of: recipient/amount **not bound as public inputs** to `verifyProof` (proof replay with attacker recipient), nullifier not marked spent before the transfer / reused, `isKnownRoot` accepts an arbitrary root, or a wrong/malleable VK. Withdrawals far exceed deposits with valid-looking proofs; many zero-value `transact` calls seeding phantom notes. (Hinkal class.)
- **Invariant:** Conservation — Σ withdrawals per note ≤ Σ deposits, enforced by *sound* proofs, not by the balance check.
- **Confirm:** on a fork, replay with a fresh nullifier / correct public-input binding and show the guard *should* have rejected it. If the circuit/VK is the defect (off-chain, unpublished), confirm on-chain public-input binding is present and conclude the break is in the circuit/VK.
- **Fix family:** bind all public inputs (root, nullifier, recipient, amount, fee); independent on-chain per-token shielded-supply invariant bounding withdrawals; audited circuit + published VK; timelock on `registerVerifiers`.

## 5. Signature / permit / approval abuse (phishing-adjacent)
- **Tell:** `permit` (EIP-2612) or pre-existing `approve` lets the attacker `transferFrom` victims' tokens/shares in a *setup* tx, then those assets are the lever for the main tx. Often the stolen asset is itself illiquid and can't be redeemed directly — it's injected elsewhere to extract value.
- **Invariant:** Authorization — only the token owner authorizes movement.
- **Confirm:** trace the setup `permit`/`transferFrom`; the main-tx drain depends on assets that entered via the phish.
- **Fix family:** (protocol-side) don't build valuation on injectable balances; (user-side) is off-chain hygiene — name it, but it's outside the contract's fix.

## 6. Math / precision / share inflation
- **Tell:** rounding in the protocol's favor reversed, downcast truncation (`uint256`→`uint128`), unchecked over/underflow, first-depositor share-inflation (empty-vault donation), precision-loss ordering (mul-after-div).
- **Invariant:** monotonicity / conservation of share↔asset math.
- **Confirm:** counterfactual fixes the rounding/precision/virtual-offset → attacker profit vanishes.
- **Fix family:** virtual shares/assets offset, checked math, consistent rounding direction, mul-before-div.

## 7. Input validation / missing gate / arbitrary call
- **Tell:** unchecked user-supplied address/token/amount; an arbitrary external `call`/`delegatecall` with attacker calldata; missing pause/access modifier on a sibling of a guarded function (partial-pause).
- **Invariant:** Authorization / integrity of the call graph.
- **Confirm:** counterfactual adds the validation/gate → path reverts.
- **Fix family:** allowlist tokens/targets, validate inputs, mirror modifiers across sibling functions.

## 8. Cross-boundary seam (cross-function / cross-contract / cross-protocol)
- **Tell:** two functions/contracts share a quantity that desyncs on call order (reward-debt desync, accrue-before-borrow); one reads a stale snapshot of the other; unit/decimal mismatch at the boundary; a callback assumed to come only from a trusted caller but reachable by anyone; wrong assumption about an external dependency's semantics (upgradeable dependency, token quirk, fork/version mismatch).
- **Invariant:** the shared invariant both sides assume.
- **Confirm:** counterfactual enforces the boundary agreement (re-read fresh, check the caller, align units) → desync path closes.
- **Fix family:** single source of truth, fresh reads, caller checks on callbacks, explicit unit handling.

## 9. Business-logic / economic design (code is "correct", design is the bug)
- **Tell:** the *intended* flow is exploitable by a rational actor — JIT liquidity around a fee/reward snapshot, first-mover redemption socializing losses onto stayers, liquidation/penalty economics that pay the attacker, griefing that's cheap for the attacker and costly for the protocol, retroactive/self-dealing parameter power. No line is "wrong."
- **Invariant:** fairness / economic conservation across actor classes and time.
- **Confirm:** model the incentive with real numbers; a fork PoC of the *intended* flow shows net extraction. (Pattern 2/3/9-style economic PoC.)
- **Fix family:** redesign the incentive (commit-reveal, snapshot timing, redemption ordering/queues, min-holding, fee floors), not a code patch.

---

## Mapping tells to the trace fast
| You see in `trace.txt` / logs… | Suspect class |
|---|---|
| owner/admin is the caller; `Upgraded`/`AdminChanged` before drain | 0 |
| flash loan → pool swap → price read → borrow/withdraw → dump | 1 |
| deposit → transfer shares into contract → redeem at higher price | 2 |
| external call, then state write; view used mid-callback | 3 |
| `withdraw`/`transact` with proof; withdrawals ≫ deposits; many 0-value calls | 4 |
| `permit`/`transferFrom` in a setup tx moving victims' assets | 5 |
| tiny/zero first deposit then huge; truncated amounts; mul/div ordering | 6 |
| arbitrary `call`/`delegatecall`; unchecked token/target; one sibling unpaused | 7 |
| two contracts' numbers disagree; stale snapshot; decimals off | 8 |
| every check passes, attacker still profits via timing/ordering | 9 |
