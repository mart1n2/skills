# EVM Smart Contract Audit Metrics

> **Scope:** EVM chains (Ethereum + L2s + EVM-compatible). Historical pattern
> pointers were derived from a dated DefiLlama Hacks snapshot; they are not
> finding evidence or a substitute for primary post-mortems.
>
> **Companion:** see `methodology.md` for the audit process (P / A–I passes); this file is the chain-specific pattern catalog.

## How to Use This File

This is a **reference library of historical attack patterns**, not a coverage checklist. Discovery may use any method; Pass P and A–J are optional scaffolds in `methodology.md`. This file's role is **cross-reference**, with two uses:

1. **Sanity-check a hypothesis.** When any method surfaces a candidate, search this file for matching prior art. A match may inform severity context and suggest optional verification approaches; it does not validate the candidate. *Absence* of a match is **not** evidence of safety—novel attack classes by definition match nothing in history.
2. **Compound knowledge across audits.** When you find a class not represented here, add it. The catalog gets sharper over time *because* the methodology stays adversarial.

**Misuse warning:** Treating the gates (G-1 through G-17) as a pass/fail checklist will miss bugs outside the catalog, including novel classes. Truth comes from target-faithful evidence and independent challenge, not this file or any named discovery method; this file is a phone book of historical leads.

---

## Historical-Data Integrity Boundary

The catalog keeps incident names and approximate loss figures as search leads.
Do not use them to prove a mechanism, rank the current target, or set severity.
Verify any cited incident against its primary post-mortem and state the valuation
date/source because loss estimates and classifications can differ.

Earlier revisions included aggregate class counts, loss totals, and a claimed
mapping percentage. They were removed because the raw snapshot, classification
transform, deduplication rules, and valuation procedure are not shipped here,
and the published rows were internally inconsistent. Restoring aggregates
requires a versioned dataset plus a reproducible classifier and arithmetic tests.

---

## 1. Historical Candidate Triggers (Not Automatic Findings)

Each trigger corresponds to at least one documented DefiLlama exploit. A match opens a candidate; it does not establish reachability, impact, severity, or a finding. Validate it against the pinned target and threat model with any sound method, attempt falsification, and apply the evidence/independent-triage gates in `methodology.md`. Absence of a trigger is not evidence of safety.

### 1.1 Privilege Concentration & Access Control

- **[G-1] EOA controls upgrade.** `ProxyAdmin.owner()` / `_authorizeUpgrade` resolves to a single non-multisig non-timelock address.
  *DefiLlama:* Poly Network $611M, Radiant V2 $53M, Dolomite $1.8M.
- **[G-2] EOA can drain user funds.** `withdraw()` / `emergencyWithdraw()` / `skim()` / `rescueTokens()` / `sweep()` reachable by single owner EOA.
  *DefiLlama:* Meerkat Finance $32M, AnubisDAO $60M.
- **[G-3] Timelock bypass present.** `emergencyExecute()`, `fastTrack()`, `skipDelay()`, owner overrides.
- **[G-4] No pause / circuit breaker on mutable contract.** Upgradeable or admin-bearing contract lacks `pause()`.
- **[G-5] Access-control bypass via callback / hook.** Privileged operations callable through a callback path that omits the modifier.
  *DefiLlama:* Cork V1 $12M.

### 1.2 Initialization & Deployment

- **[G-6] Implementation initializable post-deploy.** Constructor does not call `_disableInitializers()`.
  *DefiLlama:* Parity Multisig $150M.
- **[G-7] Unsafe initialization or upgrade configuration.** The initializer is replayable/unprotected, deployment leaves a takeover window, or critical initialization values are not validated against runtime sentinels and invariants.
  *DefiLlama:* Nomad $190M.
- **[G-8] Proxy hijack via storage corruption.** Implementation slot writeable without upgrade authorization, or storage layout collision across upgrades.
  *DefiLlama:* Munchables $62.5M; ERC1967Proxy Backdoor Hijack; Upgraded ProxyAdmin + withdrawByAdmin Hack.

### 1.3 Reentrancy

- **[G-9] State-changing external call without CEI or `nonReentrant`.**
  *DefiLlama:* The DAO $60M; Rari Capital $80M; GMX V1 Perps $42M; Penpie $27M; Siren $3.45M; Cream Lending $130M.

### 1.4 Oracle

- **[G-10] Spot DEX price as oracle.** `getReserves()` / `slot0()` / pool `balanceOf` read as price without TWAP.
  *DefiLlama:* CREAM $130M, Bunny $45M, Vee Finance $34M, UwU Lend $20M.
- **[G-11] Admin sets price unilaterally.** `setPrice()` / `updatePrice()` without timelock or multi-party.
- **[G-12] Oracle misconfiguration / wrong feed.** Wrong heartbeat, decimals, aggregator address.
  *DefiLlama:* "Misconfigured Oracle Exploit" ×2; "Oracle Misconfiguration Exploit" ×2; "CAPO Oracle Misconfiguration"; "Outdated Oracle Exploit".

### 1.5 Logic

- **[G-13] Unlimited mint authority.** `mint()` lacks cap, rate limit, AND multi-party authorization.
  *DefiLlama:* "Infinite Mint and Dump" ×10; Gala $22M.
- **[G-14] Unsafe `delegatecall` / arbitrary `.call`.** To user-controlled / unvalidated target.
  *DefiLlama:* "Delegatecall Exploit" ×3; "Arbitrary External Call" ×2.
- **[G-15] Flash-loanable governance vote.** Voting power via `balanceOf` at execution rather than snapshot.
  *DefiLlama:* Beanstalk $181M; Curio $16M.
- **[G-16] Production compiler/settings may match a published security advisory.** Pin the exact released version, optimizer/codegen/settings, and affected source pattern; a version-family match opens review but does not establish that the deployed bytecode is exploitable.
  *DefiLlama:* Curve DEX $61.7M.

### 1.6 User Path

- **[G-17] No slippage parameter on value-producing function.** Swap/withdraw/liquidate/redeem lacks `minAmountOut` / `maxAmountIn`.

---

## 2. Access Control & Privilege

### 2.1 Privileged Function Inventory

For every `onlyOwner` / `onlyRole(...)` / custom-modifier-gated function:

1. **Effect** — moves funds / sets parameters / upgrades / pauses
2. **Caller resolution** — timelock → multisig → EOA → another role
3. **Compromise blast radius** — what does a single private-key compromise enable

This is a high-leverage orientation artifact because it exposes authority and
blast radius. It is not a loss predictor or finding by itself; assess the
actual controller, threshold, delay, bypasses, operational model, and reachable
effects for the pinned target.

### 2.2 Multisig & Timelock

- Resolve the real signer set, threshold, independence, custody, rotation, and
  emergency paths; no universal M-of-N threshold proves safety.
- Verify the deployed timelock implementation, delay, cancellation and bypass
  paths against the protocol's value-at-risk and incident-response model; do
  not apply a universal hour threshold.
- Review ownership-transfer acceptance and recovery semantics. `Ownable2Step`
  may reduce accidental transfer risk, but its presence is not proof of safe
  administration and its absence is not automatically a vulnerability.

### 2.3 Governance Mechanism

- Identify when voting power is measured and whether borrowing/transfers can
  change it within the relevant proposal/vote/execution sequence.
- Derive quorum and proposal thresholds from the stated governance and economic
  threat model; labels such as "non-trivial" do not establish safety.
- Review execution delay, veto/cancellation, emergency and bypass paths; a
  timelock is one possible control, not a universal requirement.
- If checkpoints are intended, verify every mint/burn/transfer/delegation path
  updates them consistently.

### 2.4 Authorization Anti-Patterns

- Treat `tx.origin` authorization as a phishing/composability candidate and
  prove the reachable unauthorized effect.
- For raw `ecrecover`, verify zero-address handling, malleability, domain
  separation and replay rules. A reviewed library can reduce implementation
  risk, but library identity alone is not proof.
- Resolve the intended authority and delay/emergency policy for every Merkle
  root setter; absence of a specific timelock/multisig design is not itself a
  finding.
  *DefiLlama:* "updateMerkleRoot Access Control Exploit".

### 2.5 Hook / Callback Access Control

- Compare hook/callback entry paths with the intended authorization and phase
  invariants of the core effect.
- Determine whether an installable hook can gain authority beyond its declared
  scope through registration, delegatecall, callbacks, or shared state.
- Trace `beforeSwap` / `afterSwap` / `beforeAddLiquidity` re-entry and prove any
  reachable invariant violation rather than inferring it from a callback alone.
  *DefiLlama:* Cork V1 $12M.

### 2.6 State-Gate Write and Default Channels

When the contract uses a state value as the authorization gate for a downstream effect (e.g., `if (state == GoodStanding) { /* allow drawdown */ }`), then **every write-site that can land on that value is an authorization channel.** Bookkeeping functions, refresh helpers, and lifecycle "ticks" are the usual culprits — they look innocuous and bypass linters, yet write the auth-gate value with weaker preconditions than the privileged setter.

**Optional detection recipe (Pass P.2/P.3 or equivalent):**

1. Enumerate every read of the gating field as a precondition (`gates.md`).
2. Enumerate every assignment to that field (`writes.md`).
3. For every write-site whose containing function is permissionless or reachable via a permissionless entry, ask: does it enforce the same precondition the privileged setter enforces? If not, it is a back-channel.

**Symptomatic surface forms:**

- `refresh<X>(...)` / `accrue<X>(...)` / `update<X>(...)` / `tick(...)` / `settle(...)` / `harvest(...)` that recomputes state and writes a "happy-path" default value (e.g., `Active`, `GoodStanding`, `Valid`).
- An "initialize-or-recover" path that writes a privileged field as part of its bookkeeping.
- A user-facing function that mutates its own credit/position record as a side effect of a no-op or read-like action.
- An off-chain `process` / `relay` / `consume` that defaults a "validated" flag.

**Common case:** a permissionless `refreshPosition` recomputes a cached
`Active`/`Eligible` state, while a withdrawal or borrow path trusts that cached
state. Open a candidate when the refresh/default path can reach the gate without
the intended eligibility inputs or privilege. Confirm it only after proving the
exact entry-to-effect path and security consequence; a permissionless refresh,
default enum value, or alternate writer alone is not a vulnerability.

**Optional review heuristic:** for an enum or scalar that gates a material
effect, enumerate its explicit writers plus default/whole-struct initialization
paths, then compare their reachable preconditions. Equivalent semantic analysis
may be produced by any discovery method.

---

## 3. Initialization & Upgrade Safety

### 3.1 Implementation Lockdown

- Determine whether direct implementation initialization creates a reachable
  security effect; `_disableInitializers()` is a common control, not proof by
  itself.
- Reconstruct deployment/upgrade initialization ordering, atomicity, caller,
  versioning, and takeover window on the pinned target.
- Verify each `reinitializer(N)` version and reachable call sequence against the
  intended migration lifecycle.

### 3.2 Storage Layout

- Legacy linear-layout upgradeable contracts preserve layout, often using `__gap`; ERC-7201 namespaced-storage designs instead validate stable, non-colliding namespaces
- No incompatible insertion/reordering/type change across upgrades under the selected storage-layout scheme
- Proxy control slots follow the applicable standard (for example EIP-1967); application storage may use validated EIP-7201 namespaces
- Inheritance order remains compatible when linearized storage is used
- No transient storage collisions (EIP-1153)
  *DefiLlama:* Munchables $62.5M; "Transient storage collision"; "Storage Misalignment Exploit".

### 3.3 Upgrade Authorization

- Resolve the actual UUPS `_authorizeUpgrade` or `ProxyAdmin` controller,
  threshold/delay/emergency paths, and compromise blast radius; no particular
  timelock/multisig topology is universally required.
- Compare `upgradeToAndCall` and every alternate upgrade path with the intended
  authorization and initialization invariants.
- Test proxy creation/initialization ordering, address precomputation and
  front-running only where the deployment mechanism makes them reachable.
  *DefiLlama:* "CPIMP proxy front-run"; "Proxy Upgrade Skim".

---

## 4. Reentrancy

### 4.1 Standard External-Call Reentrancy

- Preserve every security invariant across external-call boundaries. CEI, pull-based flows, mutexes, state snapshots, and purpose-built callback validation are possible controls; choose the one that fits the call graph.
- If `nonReentrant` is used, cover all mutually reachable entry paths without creating unsafe guard gaps or assuming guarded functions can freely call one another.
- External calls inside loops or around partial state updates require explicit reasoning about callbacks, partial progress, failure, and gas—not an automatic finding.

### 4.2 Cross-Function Reentrancy

- Related functions preserve shared invariants during callbacks; a shared mutex is one option, but architecture-specific state machines or callback allowlists may be correct.
- Withdrawal/balance reads used by security-sensitive consumers cannot observe an unsafe mid-transition state.

### 4.3 Read-Only Reentrancy

- View functions consumed by other protocols (`get_virtual_price`, `convertToAssets`, `getAmountsOut`) return correct values during callback, OR are guarded
  *DefiLlama:* Sentiment, Conic Finance, dForce, Market.xyz.

### 4.4 Cross-Contract Reentrancy

- ERC-777, ERC-1155, ERC-721 `onReceived` callbacks: state updated before transfer
- Custom token hooks (rebasing, fee-on-transfer) treated as reentrancy surface
  *DefiLlama:* Lendf.me imBTC class; ERC-777 callback exploits.

### 4.5 Flash-Loan-Compounded Reentrancy

- Flash loan entry + callback combinations explicitly modeled
- Historical search pointers include Penpie (2024-09) and GMX V1 Perps
  (2025-07); verify the incident mechanism and loss against primary post-mortems
  before using either as precedent.

---

## 5. External Call Safety

### 5.1 Return Value Discipline

- Establish the intended failure semantics for each low-level call; ignored
  failure is a candidate only when execution continues into an unsafe state.
- Verify token calls against the exact deployed token semantics. `SafeERC20` is
  one compatibility control, not evidence that fee/rebase/hook/accounting
  behavior is safe.
- Non-standard-token compatibility and allowance races are separate concerns. Some tokens such as USDT require a zero allowance before a new non-zero allowance; use a wrapper/`forceApprove` flow compatible with the exact token
- A spender can front-run a pending non-zero-to-non-zero allowance change and consume both the old and new allowance. For contract-managed allowances, prefer an atomic wrapper appropriate to the token; for user approvals, reduce standing scope/duration and use increase/decrease or nonce/expiry-bound permit designs where they fit. A token's zero-first compatibility rule is not, by itself, complete mitigation of the user-level race
- When a path expects a specific asset, prove the supplied token/account is
  bound to that asset before its balance/value is credited.
  *DefiLlama:* "Fake Collateral Exploit" ×2; Rhea Lend $18.4M.

### 5.2 Delegatecall Target Discipline

- Resolve every `delegatecall` target/selector and who can influence it, then
  model the callee under the caller's storage/authority context. Immutability or
  allowlisting is one possible control.
- Verify proxy implementation writes are reachable only through the intended
  upgrade authority and lifecycle.

### 5.3 Arbitrary External Call as Attack Surface

- For generic-call executors, trace who selects target/selector/value/data and
  what approvals, balances, callbacks, or authority the executor exposes. A
  whitelist is one possible restriction; the finding is the reachable
  unauthorized effect, not genericity alone.
  *DefiLlama:* LI.FI; "Router Exploit" ×4; "Router Exploit via Infinite Approvals"; "Arbitrary External Call" ×2; "Unvalidated call data exploit"; Matcha $13.4M.

### 5.4 Token Approval Hygiene

- Model spender selection, allowance amount/duration, revocation, upgradeability
  and token behavior. Standing or infinite approval is a risk input, not an
  automatic vulnerability.
- Compare one-shot, bounded, Permit2, permit, and other flows against the exact
  threat model rather than treating one mechanism as universally preferred.
  *DefiLlama:* "Token approval exploit" ×2; "Unlimited Approval Exploit"; "Unchecked FlashLoan Approve Exploit".

### 5.5 Gas Considerations

- Treat `transfer()` / `send()` to contract recipients as a liveness and gas-
  assumption candidate; prove the affected withdrawal/effect and available
  recovery path.
- Analyze attacker-controlled iteration plus external calls under target-chain
  gas and state bounds; a loop is a finding only with a reachable consequence.

---

## 6. Oracle & Price Manipulation

### 6.1 Source Candidate Signals

| Pattern | Review context | Questions before opening or accepting a candidate |
|---------|----------------|----------------------------------------------------|
| `AggregatorV3Interface.latestRoundData()` (Chainlink) | External feed | Is the exact feed/config correct, fresh under its documented update policy, positive, decimal-normalized, and safe under sequencer/feed failure? |
| `IPyth.getPriceNoOlderThan()` | Age-bounded external feed | Is the price identifier correct, `maxAge` appropriate to the dependent action, confidence handled as designed, and update/authentication path valid? |
| `OracleLibrary.consult(pool, secondsAgo)` (Uni V3 TWAP) | Windowed pool observation | What are the real window, observations, liquidity distribution, manipulation cost, and downstream extractable value? |
| `IUniswapV2Pair.getReserves()` direct | Same-state pool measure | Can the relevant actor move the reserves in the reachable sequence, and does any dependent effect create a net gain/loss after costs? |
| `slot0().sqrtPriceX96` direct | Same-state pool measure | Is the read security-sensitive and manipulable in the exact transaction/state, with material extractable impact? |
| `balanceOf(pool)` as price | Raw-balance input | Can donations/rebases/direct transfers alter the input contrary to intended accounting, and who benefits at whose expense? |
| Custom internal curve (sPMM, bonding curve) | Protocol-specific model | Do implemented domains, rounding, parameters, and economic assumptions preserve the stated invariants under reachable actions? |

API shape never determines severity. A familiar feed can be misconfigured and a
pool read can be safely bounded; severity follows verified impact on the pinned
target.

### 6.2 Chainlink Integration Checks

- `updatedAt > block.timestamp - maxStaleness` enforced (heartbeat-aware)
- `answeredInRound >= roundId` enforced
- `price > 0` enforced
- Per-feed staleness, not global
- L2 sequencer uptime feed checked on Arbitrum/Optimism

### 6.3 TWAP Window Adequacy

There is no universal safe window or TVL threshold. For the pinned pool and target state:

- identify the exact observation/window construction, update cadence, liquidity distribution, fees, cross-venue arbitrage, and any sequencer or liveness assumptions
- quantify the capital and cost required to sustain the relevant price distortion over the window, including flash liquidity and back-running/arbitrage effects
- compare the cheapest credible manipulation cost with the maximum value extractable through every dependent borrow, mint, liquidation, redemption, or governance path
- treat a spot read as a candidate when it affects a security-sensitive value, not as an automatic finding; a non-security use or an independently bounded design may be safe

### 6.4 Donation Attack Resistance

- If `balanceOf(address(this))` feeds price or accounting, verify whether donations, rebases, fees, and direct transfers are intended inputs. Raw balance and internal ledgers can each be correct or wrong; define and test their reconciliation and surplus/deficit semantics
- Sync mechanism (`skim` / `sync`) not exploitable by repeated donation
  *DefiLlama:* "Donation Attack" ×3; "Flashloan Donate Function Logic Exploit" ×5; Sonne $20M; Euler V1 $197M; "Rounding Donation Attack"; "Donate Negative Amounts Hack"; Venus Core Pool $3.7M.

### 6.5 Derived Value & Vault Share Pricing

- Treat raw `balanceOf(pool) / totalSupply` LP pricing as a manipulation and
  accounting candidate. Establish whether direct transfers, rebases, fees,
  virtual balances, pool invariants, or reentrancy make it unsafe for the exact
  consumer; a named helper is not universally safe.
- For vault share pricing, test operation-specific rounding, empty-vault and
  donation states, and any virtual-offset/dead-share design against the actual
  beneficiary and loss condition.
  *DefiLlama:* "First Depositor Attack"; "Deposit Inflation Attack"; "Inflationary Accounting Manipulation"; "Share Accounting Flaw"; "Redeem Rounding Error Exploit" ×2.
- Treat ERC-4626 methods according to their specified semantics: `convert*` is an idealized estimate, `preview*` estimates an operation but ignores limits, and `max*` reports caller-specific execution limits. A `maxWithdraw` below `convertToAssets` can be valid. Investigate consumers that price immediately realizable liquidity, collateral, or settlement from an idealized conversion/preview, and vaults whose `max*` overstates what will execute; establish the actual beneficiary and deficit before calling it a finding (see methodology § X.3 item 8 and § J item 10)

### 6.6 Fallback & Failure Handling

- Define and test the intended failure policy for stale, unavailable, disputed,
  or sequencer-affected data. Revert, pause, bounded fallback, or another design
  can be safe depending on liveness and solvency requirements.
- If sources are aggregated or deviation breakers exist, validate source
  independence, update semantics, thresholds, bypasses, and failure behavior;
  neither aggregation nor an arbitrary percentage proves safety.

---

## 7. Arithmetic & Precision

### 7.1 Overflow / Underflow

- Pin the compiler and arithmetic semantics. Solidity 0.8+ checked arithmetic
  reduces one class of risk but does not make casts, assembly, or `unchecked`
  code safe; older builds require operation-specific overflow analysis rather
  than a library-name check.
- Review each relevant `unchecked { ... }` path and prove its bounds or show
  that overflow cannot violate the claimed invariant.

### 7.2 Rounding Direction

- Verify operation-specific rounding and the full net economic effect; one user-favoring intermediate result does not prove a profitable round trip
- ERC-4626: `convertToShares` / `convertToAssets` round down by specification, while previews and mutable operations have operation-specific directions and semantics
- Test small-input floor-to-zero behavior against the intended minimums,
  beneficiary and accounting invariant; zero output can be specified behavior.

### 7.3 Precision & Decimal Scaling

- Choose operation ordering that preserves the intended precision without
  overflowing under proven bounds; "multiply first" is not universally safe.
- Review the exact fixed-point implementation and call-site units; a named
  library does not prove correct scaling or rounding.
- Verify decimal/unit normalization for every heterogeneous asset and oracle.
- Quantify dust creation, ownership and recovery before treating precision loss
  as a security finding.
  *DefiLlama:* KyberSwap Elastic $48M; Uranium Finance $57.2M; Compound V2 $147M; "Decimal Miscalculation Exploit"; "Calculation Error in Liquidation Engine"; "Fee Overflow Exploit".

### 7.4 Compound Math

- Bound user-influenced exponentiation and prove its gas/numeric behavior in the
  reachable domain.
- Verify interest-accrual direction and discontinuities against the protocol's
  stated model; negative rates or loss socialization may be intentional.
- Treat assembly/custom math as a semantic review surface. Validation may use
  any sound method; no particular reviewer or tool is mandated.

---

## 8. Input Validation

### 8.1 Value-Producing Function Questions

- Determine whether the caller needs a `minAmountOut`, `maxAmountIn`, deadline,
  or equivalent protection for the exact operation and execution model.
- Establish the intended zero-address semantics for token, oracle, receiver,
  and beneficiary fields before treating a missing check as a defect.
- Validate rate, fee, percentage, and other parameter bounds against every
  downstream calculation and governance path.

### 8.2 Array & Calldata Bounds

- Bound or otherwise make user-controlled iteration safe using worst-case gas
  and state on the target chain; there is no universal safe element count.
- Calldata length validated for raw `bytes`
- `abi.decode` of user input preceded by length checks
  *DefiLlama:* "Calldata underflow and resolver hijack" (1inch $5M).

### 8.3 Function-Specific Logic Bugs

Named DefiLlama buckets: "Deposit Function Exploit" ×2, "Borrow Logic Exploit" ×3, "Swap Function Exploit", "Transfer Logic Exploit" ×2 (Qubit $80M, Transit Swap $21M), "Burn Function Mistake", "Buy Function Exploit", "emergencyWithdraw Function Exploit", "withdrawStuckToken() exploit", "Claim Contract Flashloan Exploit" (Hedgey $44.7M).

For each user-callable value-moving function, write down preconditions and postconditions explicitly and verify them in code.

---

## 9. Signature & Cryptography

### 9.1 ECDSA Hygiene

- No raw `ecrecover` — use OpenZeppelin `ECDSA.recover`
- s-malleability rejected (`s > secp256k1n/2`)
- Zero-address return check

### 9.2 Replay Protection

- Define the intended replay domain across chain, contract, deployment,
  signer, action and time. Verify that the signed data plus consumed state bind
  that domain; `chainId`, contract address, nonce and deadline are common
  components, not universally sufficient or individually mandatory.
- For EIP-2612, verify the exact standard/domain/nonce/deadline behavior and any
  proxy/domain-version changes.
  *DefiLlama:* "Replay Attack"; "Incomplete EIP-712 Signature Coverage".

### 9.3 Cross-Chain Signature & Proof Verification

- Validator/guardian set length checked before iterating signatures
- Duplicate signature detection (same signer signing twice)
- Quorum enforced and matches documented value
- Merkle leaf-vs-node domain separation
- Empty proof rejected
- ZK verifier configured with correct verification key
  *DefiLlama:* Kelp $293M (LayerZero OFT); Nomad $190M; Orbit Bridge $81.7M; "Fake Proof Spam"; "Fake State Proof"; "Oracle Message Spoofing"; "False Peer Exploit"; "Fake Bridge Address"; "misconfigured Groth16 verifier".

### 9.4 EIP-7702 Delegation (2024–)

- Resolve who may select/change the delegation target and what authorization the
  account design promises; allowlisting is one possible policy.
- Review revocation/recovery and replay behavior across set/unset/redelegation
  cycles under the exact wallet and chain semantics.
  *DefiLlama:* "EIP-7702 Delegation Exploit" (Fusion by IPOR $336K).

---

## 10. Flash Loan & MEV Resistance

### 10.1 Flash-Loan-Resistant Design

- Do not reject an oracle merely because it is read in the same block. Establish whether the exact source can be moved within the attacker sequence, then compare manipulation cost with extractable value
- If a TWAP or delayed source is used, validate its exact window and market state rather than applying fixed time/TVL thresholds
- If caps or rate limits exist, validate their units, bypasses, reset semantics
  and relation to extractable value; their absence is not automatically a bug.
- Trace actual state/call ordering around external reads/calls. CEI is a useful
  pattern, not a proof or universal ordering rule.
- Model flash-loan entry and callback as one state machine. Do not blanket-apply the same `nonReentrant` lock to both when the valid flow requires the callback during the entry; authenticate the lender/initiator/data, bind the live phase, and use lock domains or ordering appropriate to the actual call graph

### 10.2 Liquidation Mechanism Integrity

- Model liquidator incentives, borrower loss and protocol solvency across the
  reachable stress domain; no universal profit bound applies.
- Close factor and full-liquidation conditions match the protocol's solvency and incentive design; do not impose a universal 50% cap
- Verify bad-debt allocation and recovery against the documented design.
- Analyze self-liquidation as an economic path and establish whether it creates
  a net extraction; prevention is not inherently required.
- Quantify dust-position liveness and loss before accepting a finding.
  *DefiLlama:* Euler V1 $197M; "Liquidation Logic Exploit"; "Calculation Error in Liquidation Engine".

### 10.3 Sandwich / JIT

- Determine whether each swap caller can bind acceptable execution through
  `minAmountOut`, a quote/deadline, a solver guarantee, or another mechanism;
  no single interface shape fits every execution model.
- Test protocol-defined slippage and liquidation incentives against realistic
  ordering/MEV and the verified loss condition.
  *DefiLlama:* "Atomic Sandwich Attack"; "MEV bot manipulation exploit" (Ronin Bridge $12M); "MEV composability attack".

---

## 11. Compiler & Pragma

- Reproduce the pinned production compiler/settings and review arithmetic under
  those exact semantics; version family or a SafeMath import is not proof.
- Treat source pragmas and the build lock together. A floating source pragma is
  a reproducibility risk only when the production build does not otherwise pin
  the selected compiler.
- Cross-reference the exact compiler/settings against official Solidity and
  Vyper advisories, including each advisory's triggering conditions.
- Match the compiler's `evmVersion` and emitted opcodes (including `PUSH0`) to the pinned deployment chain and fork configuration, and reproduce the production build. Solidity version alone does not prove opcode use or target support
- For Vyper CVE-2023-32675, match the exact released affected versions and
  nonreentrant usage from the advisory; do not infer exploitability from a
  shorthand version range alone.
  *DefiLlama:* Curve DEX $61.7M.

---

## 12. Architecture-Level Candidate Signals

- For reachable `selfdestruct`, use the target fork semantics and prove the
  value/code/liveness consequence.
- Review inline assembly according to the state, memory, call and compiler
  semantics it affects; validation may use any sound method.
- If `block.timestamp` / `blockhash` influences an unpredictable choice,
  quantify producer/user influence and the resulting gain/loss.
- For hardcoded or non-rotatable administration, assess compromise/recovery
  assumptions and intended immutability.
- Trace arbitrary-spender approvals and `address.balance` accounting through the
  exact spender/donation/forced-ETH/reconciliation model.
- For recursive `delegatecall` or `CREATE2` address reuse, establish the actual
  code/storage identity confusion and reachable effect rather than assuming it.
  *DefiLlama:* "Sybil Attack with CREATE2 Addresses".

---

## 13. Lending / DEX / Yield Logic

### 13.1 Collateralization

- Test LTV, collateral factors, liquidation thresholds/buffers and caps against
  the asset's stress volatility, liquidity, oracle behavior, correlation,
  settlement latency and the protocol's solvency model; no fixed percentage or
  presence of a cap proves safety.
- Model bonus/penalty, gas, slippage, latency, close factor, target health,
  full-liquidation conditions and available liquidity for both execution
  incentives and borrower/protocol extraction.
- Resolve who may list/change assets and parameters under the stated governance
  model; a specific governance mechanism is not universally required.
  *DefiLlama:* "Collateral Offboarding Mistake"; Rhea Lend "Fake Collateral Exploit"; "cbETH Collateral Exploit"; "Staked Collateral Exploit".

### 13.2 Fork Lineage

- If fork: identify upstream + version + audited tag
- Diff source vs upstream; classify each change:
  - **Parameter** (LTV, fee bps, cap): classify by the invariant and economic effect it changes; parameter-only diffs can be critical
  - **New feature**: identify and close its affected security obligations using any sound method
  - **Logic modification** (value math, state transitions, invariants, liquidation): re-evaluate affected claims; upstream audit evidence does not automatically transfer

### 13.3 Yield & Reward Accounting

- Test deposit/withdraw timing, rate changes, checkpointing and reward-asset
  pricing against the stated accrual invariant; retroactivity or cycling is a
  finding only when it creates a reachable unauthorized gain/loss.
  *DefiLlama:* "Flashloan Incentive Rewards Exploit" ×3; "Incentive Rewards Exploit" ×2; "Incentives Function Mistake" ×2; "Referral Claims Logic Exploit"; "Mint & Stake Loop Exploit"; "Staking Logic Exploit".

### 13.4 New-Market / Empty-Pool Risks (Compound V2 forks)

- Model listing/bootstrap order, initial supply/borrow controls, empty-market
  exchange-rate/donation behavior and small-supply rounding. Caps or seeded
  liquidity are possible controls, not universal requirements.
  *DefiLlama:* "Flashloan New Market Exploit" ×2; Onyx; Hundred; Channels.

### 13.5 AMM-Specific

- Exercise invariant calculations across atomic deposit/withdraw/swap sequences
  and quantify any net extraction.
- Compare composable-pool BPT paths with the intended invariant/domain of token
  swaps; difference alone is not a defect.
  *DefiLlama:* Balancer V2 $128M (Composable Stable Pools Exploit, 2025-11).

---

## 14. Optional Reachability Atlas Recipe (Methodology P)

Use this recipe when a reachability Atlas improves discovery or coverage review. It is neither a prerequisite nor proof of completeness; another method may replace it when `coverage.md` records the selected surface, evidence, exclusions, and blind spots. Regex matches are only seeds and require semantic review before they support a claim.

### 14.1 Sink Inventory — Grep Recipes

Run from the contracts root (excluding `node_modules`, `@openzeppelin`, `forge-std`, `hardhat`):

```bash
# ERC-20 movement
grep -RIn -E '\.safeTransfer(From)?\(|\.transfer(From)?\(' .
# Supply changes
grep -RIn -E '\b_?mint\(|\b_?burn\(' .
# Native value
grep -RIn -E '\.call\{value:|\.send\(|\.transfer\([^,]+\)' .
# Approvals
grep -RIn -E '\.(safeApprove|approve|increaseAllowance|decreaseAllowance)\(' .
# Delegatecall (unbounded effect)
grep -RIn -E '\.delegatecall\(' .
```

Each match becomes a row in `sinks.md`.

### 14.2 Gate-Read Inventory — Grep Recipes

```bash
# Equality / inequality gates on state fields
grep -RIn -E '\b(if|require|assert)\s*\([^)]*\.\s*state\s*(==|!=|>=|<=|>|<)' .
# Boolean approval gates
grep -RIn -E '\b(if|require)\s*\(\s*[!]?[A-Za-z_]+\[[^]]+\]\s*[\)|=]' .
# Custom-modifier sites
grep -RIn -E '\b(only[A-Z][A-Za-z]*)\b' .
```

### 14.3 Gate-Write Inventory — Grep Recipes

For each field listed in `gates.md`, generate a targeted grep:

```bash
FIELD="state"   # or 'approved', 'role', 'paid', 'verified', etc.
grep -RIn -E "\.${FIELD}\s*=|^[[:space:]]*${FIELD}\s*=" .
# Struct overwrites that include the field
grep -RIn -B1 -A6 -E "\.\b${FIELD}\b\s*:" .   # struct-literal initializer with field
# Setter helpers
grep -RIn -E "(_set|set|update)[A-Za-z0-9_]*${FIELD}" .
```

**Trap:** When a record is reassigned via *whole-struct overwrite* (`creditRecord[x] = NewRecord(...)`), the field name `state` may not appear in that line — only in the struct literal. The grep above catches the struct literal form via the `${FIELD}:` pattern, but auditors must also walk every struct-assignment of records that contain the gating field.

### 14.4 Path Enumeration

For each sink (`sinks.md`) × external entry point (`A.1`):

1. Build the forward call chain.
2. Conjoin every precondition encountered.
3. For each precondition that reads a field in `gates.md`, look up its writes in `writes.md`.
4. Recursively expand: every write-site is another sub-graph of entry-sequences that can satisfy the precondition.

Express the result as a tree per sink. Each leaf is a `(entry-sequence, accumulated preconditions)` pair. The union of leaves is the reachable atlas for that sink.

### 14.5 Intent Delta

Manually annotate which entry-sequences the protocol team *intends* to authorize each sink. Set difference: `reachable - intended` = candidate chains.

If the Atlas is used, reconcile its material leads and limitations in `coverage.md`. Audit closure still depends on claim-bound evidence, candidate dispositions, independent validation, and explicit residual gaps—not completion of this particular recipe. Human sign-off is the separate report gate.

---

## 15. Dependency & Integration Safety

- Where graceful degradation is intended, verify actual external-call failure,
  return-data and retry/accounting semantics; `try/catch` is one mechanism.
- Map withdrawal/liveness dependencies and recovery paths, including single
  integrations and per-integration pause/bypass controls where the design uses
  them.
- Verify selector, return type, callback, token and state assumptions against the
  exact upstream deployment/version, and identify deprecated behavior that is
  actually reachable.
- Review custom or modified math, reentrancy, access-control, ownership and token
  components according to the semantics they affect. Validation may use any
  sound method; a brand name or independent-review label is not proof.
  *DefiLlama:* "Third-party Dev Backdoor Exploit"; "Whitelisted Address Impersonation"; "False Peer Exploit".

---

## Restoring Reproducible Historical Metrics

If quantitative catalog metrics are needed, check in or immutably identify the
input snapshot and include the chain/language filter, mutually exclusive versus
multi-label classification rules, duplicate handling, loss-valuation policy, and
a script that recomputes every count/total. Until then, this file makes no
coverage, detection-rate, frequency-ranking, or aggregate-loss claim.

---

## Appendix: EVM Toolchain

- **Symbolic execution:** Mythril
- **Fuzzing:** Echidna, Medusa, Foundry `forge fuzz` / `forge invariant`
- **Formal verification:** Certora Prover, Halmos
- **Compiler advisories:** Solidity GitHub Security Advisories, Vyper GitHub Security
- **PoC simulation:** Foundry `forge test --fork-url` against mainnet RPC

**Historical pointer snapshot:** 2026-05-12. Re-verify individual references
against primary sources before use; do not infer current frequencies from it.
