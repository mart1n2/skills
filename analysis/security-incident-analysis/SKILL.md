---
name: security-incident-analysis
description: >
  Forensic post-mortem of a live or past on-chain security incident (exploit, drain, hack, rug). Reconstruct the attack from tx traces, classify and fork-replay the root cause, quantify the loss two independent ways, trace the stolen funds, and assess whether the deployment is still at risk — producing a reproducible incident report. Use when a protocol has been exploited/drained and the user wants an incident analysis, exploit reconstruction, loss quantification, fund-flow tracing, root-cause + PoC, or a post-mortem report. Self-contained and EVM-focused (Ethereum + L2s); bundles its own chain config, scripts, taxonomy, and report template. Bash scripts run on macOS (zsh→Bash 3.2+) and Linux.
---

# Security Incident Analysis (Forensic Post-Mortem + Fork Replay)

Reactive forensics for an on-chain incident that already happened. This is the **sibling of a pre-deployment audit, inverted**: an audit asks "can this be exploited?"; this asks "an exploit occurred — reconstruct it, prove the root cause, size it, trace it, and tell me if it is still bleeding."

This skill is **self-contained**. Everything it needs — chain config, env loader, forensic scripts, the vulnerability taxonomy, the report template, a fork-replay PoC harness — ships inside this directory. It does not depend on any other skill.

> **First principles**
>
> **Axiom 1 — On-chain state is the only witness.** Every claim in the report is backed by an on-chain fact pinned to an explicit block number. Twitter/Telegram numbers, block-explorer labels, and the team's statement are *hypotheses* until a `balanceOf` delta, a log sum, or a fork replay confirms them. Never write `latest` into evidence — it drifts between calls and makes the report irreproducible.
>
> **Axiom 2 — A drain is a hypothesis, not an observation.** A zero balance is equally consistent with theft, a legitimate migration, and an admin sweep. "Exploited" is established only when you see *who* the outflow went to and *whether the path was permissioned*. Rule out the boring cause (key/admin compromise, governance action, benign migration) **before** theorizing about a clever bug — they have identical fund-flow shapes but completely different remediation.
>
> **Axiom 3 — Root cause is not asserted, it is replayed.** A causal claim that has not been reproduced on a fork *and* falsified by toggling the broken guard is a hypothesis, not a finding. Correlation in a trace is not root cause.
>
> **Axiom 4 — Every number is derived twice.** The loss figure is computed two independent ways (event-log summation AND balance-snapshot delta) that must reconcile. The single most common way a public post-mortem gets torn apart is a wrong loss number — from a truncated explorer export, a wrong baseline block, or flash-loan principal counted as loss.

---

## Quick Reference

| Phase | Output | Anti-fooling gate |
|-------|--------|-------------------|
| 0. Intake & evidence freeze | `workspace/{incident}/run.env`, raw `tx.json`/`receipt.json`/`block.json` | Reachable archive RPC verified; every artifact block-pinned |
| 1. Confirm & scope the drain | `scope.md` (assets, contracts, proxy/impl, drain vs migration) | Balance baseline taken *before the first attacker-touching tx* |
| 2. Actor map | `actors.md` (EOA / exploit contract / beneficiary / funder / victim) | Every address verified on-chain, never transcribed from a page |
| 3. Reconstruct the attack | `trace.md` (decoded call tree + all setup/pre txs) | Setup txs enumerated, not just the "main" tx |
| 4. Root cause | `rootcause.md` (class from `references/vuln-taxonomy.md`, violated invariant) | Read exploit-*time* code (impl at the exploit block) |
| 5. Quantify loss | `loss.md` (two methods, per-asset, reconciled, correction log) | getLogs sum ≈ balanceOf delta; flash-loan principal excluded |
| 6. Fork replay + counterfactual | `poc/` (`.t.sol` + logs), evidence verdict | Reproduces real extracted amount; toggling the guard stops it |
| 7. Fund tracing & attribution | `funds.md` (hop-by-hop to terminals) | Bridge memos decoded; attribution on-chain-only |
| 8. Containment & residual risk | `containment.md` (verdict: still exploitable?) | Kill-switch ≠ fix; surviving assets at risk quantified |
| 9. Report | `reports/{incident}-{chain}-{date}.md` | CONFIRMED vs INFERRED separated; every claim cites tx/block |

**Loop, don't pipeline.** A failed fork replay (Phase 6) sends you back to root cause (Phase 4) and often to the trace (Phase 3). A new setup tx found while tracing funds (Phase 7) becomes an actor-map entry (Phase 2). Phase numbers are stable artifacts; their order is iteration.

**Reference files (bundled — load at start):**
- `references/incident-methodology.md` — the full forensic method, the exact commands per phase, and the anti-fooling discipline. **The source of truth; read it before Phase 0.**
- `references/vuln-taxonomy.md` — root-cause classes (access/key compromise, oracle/price manipulation, NAV/accounting inflation, reentrancy, ZK/verifier soundness, permit/approval phishing, math/precision, cross-boundary, economic-design) with the on-chain *tell* and how to confirm each on a fork.
- `config/chains.json` — chain IDs, Chainlist discovery settings, and configured official/public RPC fallbacks.

**Bundled scripts (`scripts/`, run each with `bash`):**
- `preflight.sh` — honor user RPC configuration first; otherwise test Chainlist candidates and the configured official/public fallback for reachability, chain ID, and archival state. Fail closed if no archive endpoint is available.
- `load-env.sh` — env/API-key loader (sourced by other scripts).
- `intake.sh` — pin an incident: fetch tx + receipt, resolve block/timestamp, classify `to`, dump immutable raw artifacts.
- `find-drain-block.sh` — binary-search the block where a victim's token balance dropped (for when you have an address but no tx).
- `reconcile-loss.sh` — the two-method loss tally (eth_getLogs Transfer sum + balanceOf pre/post delta) for one asset, with the reconciliation residual.

**Bundled PoC harness:** `templates/poc/ForkReplay.t.sol` — Foundry fork-replay + counterfactual skeleton (reproduce the extraction, then patch the one guard and assert the drain reverts).

**Bundled report template:** `templates/incident-report.md`.

---

## Phase 0: Intake & Evidence Freeze

Goal: freeze the facts before the chain re-orgs, before the attacker moves funds again, and before hypotheses bias your reading.

```bash
INCIDENT="{lowercase-kebab-name}"      # e.g. "acme-vault-drain"
CHAIN="{ethereum|arbitrum|base|bsc|...}"
SKILL_DIR="/absolute/path/to/security-incident-analysis"
WORKSPACE="incident-workspace/${INCIDENT}"
mkdir -p "$WORKSPACE"/{evidence,poc}

bash "$SKILL_DIR/scripts/preflight.sh" "$CHAIN" "$WORKSPACE"
source "$WORKSPACE/tool-resolution.env"      # RPC_URL, RPC_SOURCE, ARCHIVE_OK, CHAIN_ID, AUDIT_MODE
```

If `AUDIT_MODE=blocked` (including no reachable archive RPC), halt and report the blocker. If `degraded` because a non-RPC tool is unavailable, proceed only through supported phases and keep the evidence verdict `INCONCLUSIVE` where required.

Then pin the incident with the two inputs you have (a tx hash, an address, or both):

```bash
bash "$SKILL_DIR/scripts/intake.sh" "$TX" "$VICTIM" "$CHAIN" "$WORKSPACE"
# Atomically writes source-safe run.env plus tx.json, receipt.json, block.json.
# Any RPC/JSON/hash mismatch exits nonzero and leaves no partial evidence.
```

Raw `tx.json`, `receipt.json`, and `block.json` are the immutable evidence base. The intake script refuses to overwrite them; read from the saved copies. See `references/incident-methodology.md § 0`.

---

## Phase 1: Confirm & Scope the Drain

> A zero balance is not proof of theft (Axiom 2). Confirm a real, unpermissioned outflow and enumerate *what* left and *from where*.

1. **Confirm the outflow.** Snapshot the victim's balance for each candidate asset at `PRE` vs `POST` (or before/after the incident window). If you only have an address, use `find-drain-block.sh` to locate the drop — but a sawtoothing balance (normal traffic) invalidates the bisection; fall back to a full log scan.
2. **Establish the correct baseline.** The baseline balance MUST be taken at the block *before the first attacker-touching tx* — not after an early attacker deposit/seed, or the loss number is wrong. (This is a repeat offender.)
3. **Enumerate all affected assets.** "The USDC pool is gone" often means everything went. Scan every ERC-20 the victim ever held (`Transfer` logs with `to = victim`), dedup, and snapshot each pre/post. Report per-asset: fully drained vs test-scratched vs staged-but-not-cashed (a net *inflow* asset the attacker positioned but never withdrew).
4. **Map the contract set.** The victim façade is rarely where the money sits. Resolve proxy → implementation *at the exploit block* (EIP-1967 slots), and find the vault/strategy/ark/pool that actually held the assets.

Write `scope.md`. Full command set in `references/incident-methodology.md § 1`.

---

## Phase 2: Actor Map

Classify every address in the incident — **do not conflate the attacker EOA, the attacker's deployed exploit contract, the final beneficiary/recipient, the funding source, and the victim contract**; they are usually distinct.

- `cast code $ADDR --block $PRE` → EOA (`0x`) vs contract.
- Attacker EOA: the `from` of the exploit tx; pull its nonce (fresh = purpose-built) and its funding source (the first inbound tx that paid its gas — often minutes before, sometimes from a mixer/CEX).
- Exploit contract(s): created in the exploit tx or shortly before (`CREATE`/`CREATE2` frames, `receipt.contractAddress`).
- **Address hygiene (hard rule):** never transcribe an address from a rendered explorer page or via WebFetch — they mistranscribe hex. Extract with `curl`+`grep` from an API or read it from a trace, then verify on-chain (checksum + `cast code`) before it enters the report.

Write `actors.md` — address → label → the on-chain fact that justifies the label.

---

## Phase 3: Reconstruct the Attack

Goal: a complete, decoded mechanical record — no root-cause reasoning yet.

1. **Full execution trace:** `cast run $TX -vvvv > trace.txt`. Prefer `cast run` over `debug_traceTransaction` — archive RPCs (Infura-class) usually disable the `debug_` namespace, and `cast run` re-executes against archive state and gives the decoded internal call tree.
2. **Decode inline** (this skill is self-contained — do not delegate): use `cast 4byte <selector>` for candidate signatures, `cast 4byte-decode <calldata>` for inferred decoding, or `cast calldata-decode <sig> <calldata>` for a known signature. Decode `Transfer`/vault events from the receipt logs into a signed per-actor, per-token value-flow ledger.
3. **Enumerate ALL setup/pre txs, not just the "main" one.** Funding, token approvals, `permit` signatures, share/collateral pre-positioning, and phishing txs frequently live in *earlier* transactions. Identify the first-exploit tx. Reconcile the attacker P&L across the whole tx set (Phase 5) — a same-tx replay that counts a pre-positioned lever consumed inside the tx shows a *false* loss.
4. **Identify the capital source:** most large drains are flash-loan-funded (Aave/Balancer/Morpho/Uniswap/Maker). A flash loan means zero attacker capital and points at a *pricing/accounting* flaw rather than a stolen key.

Write `trace.md`. See `references/incident-methodology.md § 3`.

---

## Phase 4: Root Cause

Classify the broken step against `references/vuln-taxonomy.md`, then state it as a one-sentence causal claim tied to specific source lines.

- **Rule out the boring cause first** (Axiom 2): check for an `Upgraded`/`AdminChanged` event or a privileged setter call right before the drain, and whether the drain caller is the owner/admin. An impl swap or admin-signed drain just before the outflow means key/governance compromise — the flash-loan/logic-bug narrative is wrong and remediation is entirely different.
- **Read the exploit-*time* code.** Resolve the implementation at `PRE` (not head — the team may have upgraded during response) and fetch *that* source. Auditing today's code for yesterday's exploit is a classic self-own.
- **State the violated invariant** (conservation / solvency / oracle-integrity / authorization / uniqueness). The finding is that this invariant was violated.
- **Watch for tautological / self-referential checks** — the highest-yield incident tell: an on-chain "balance is sufficient" check that trusts the very quantity the proof/accounting is supposed to enforce (privacy-pool conservation-as-tautology); a NAV that reads `underlying.convertToAssets(underlying.balanceOf(self))` (donation-inflatable and illiquidity-blind); a price read from a pool the same tx just moved.

Write `rootcause.md`.

---

## Phase 5: Quantify Loss

Compute the loss **two independent ways that must reconcile** — see `scripts/reconcile-loss.sh` and `references/incident-methodology.md § 5`.

- **Method A — event-log sum:** `eth_getLogs` for `Transfer` out of the victim to attacker-controlled addresses across the incident window (chunk the block range if the provider caps it). **Do NOT use Etherscan `txlist`/`tokentx` for totals — its `offset`/pagination silently truncates and understates the loss.**
- **Method B — balance-snapshot delta:** `balanceOf(victim)` at the correct baseline (`§1.2`) vs post; also snapshot `totalAssets()`/`totalSupply()` for vault share accounting.
- **Reconcile.** A and B must agree to within dust; itemize the residual (flash-loan fee, gas, slippage the attacker ate).
- **Report the attacker's NET extraction.** Exclude flash-loan principal that round-tripped — conflating it is the most common source of inflated headline figures.
- **Per asset**, valued at the incident block via an on-chain reference (Chainlink `latestRoundData` at the block, or a DEX TWAP) — never a current price.
- **Keep a correction log.** If your first number was wrong, state it and why (truncation / bad baseline). Self-correcting in the open is what makes the report defensible.

Write `loss.md`.

---

## Phase 6: Fork Replay + Counterfactual (Critical Gate)

A root cause is not confirmed until it is replayed. Use `templates/poc/ForkReplay.t.sol`.

1. **Fork at `PRE`** and replay the attacker's exact sequence against real victim state. Initialize `$WORKSPACE/poc` with `forge init --no-git --force .`, copy `templates/poc/ForkReplay.t.sol` to `test/ForkReplay.t.sol`, then run `forge test --fork-url "$RPC_URL" --fork-block-number "$PRE" --match-path test/ForkReplay.t.sol -vvvv`. Assert the extraction ≈ the on-chain figure from Phase 5.
2. **Counterfactual (the falsification step — non-negotiable):** neutralize *only* the hypothesized root cause (patch the manipulable price to an oracle value / add the missing gate / supply a correct proof / mark the nullifier) and assert the drain now reverts or nets ~0. If removing the suspected flaw does not stop the drain, the root cause is wrong — return to Phase 4.
3. **Sensitivity:** vary flash-loan size; confirm profit scales as the mechanism predicts. Call out per-band/per-tx caps that only *rate-limit* rather than prevent a drain — they are routinely mistaken for mitigations.

**Evidence verdict per claim:** `CONFIRMED-DEPLOYED` (pinned fork replay reproduces extraction + counterfactual falsifies) · `CONFIRMED-LOGIC` (local harness only) · `INCONCLUSIVE` (replay blocked — record the exact blocker; do NOT downgrade severity for a tooling failure) · `REFUTED` (a faithful test shows a required precondition cannot be reached).

---

## Phase 7: Fund Tracing & Attribution

Follow the money forward from every attacker-controlled recipient (EOA *and* deployed exploit contract — expect decoys and throwaways; don't stop at the first hop).

- Trace hop-by-hop until funds reach a terminal: DEX swap (router) → unwrap → **mixer** (Tornado/Railgun) or **bridge** (THORChain, etc.) or CEX deposit.
- **Decode bridge memos** — a THORChain memo encodes the cross-chain destination address; always decode it. See `references/incident-methodology.md § 7`.
- **Flag freezable assets immediately:** if the attacker still holds USDC/USDT (issuer-freezable), there is a live freeze window worth surfacing at the top of the report. Once swapped to ETH and mixed, recovery is ~impossible — say so plainly.
- **Attribution discipline:** label an address "attacker-controlled" only with on-chain proof (funded it / deployed it / directly received drained funds). Do not assert real-world identity. Over-attribution is what discredits a public post-mortem.

Write `funds.md`.

---

## Phase 8: Containment & Residual Risk

> This phase changes the verdict. A drained protocol with a live hole is an active emergency; a fully-neutralized one is a post-mortem. Treat it as first-class, not a footnote.

- **Was it stopped, how, and by which tx?** Check `paused()` if present; scan for the emergency-stop tx after the drain. For many protocols the stop is *not* a `pause()` — it is nulling a critical dependency (e.g. `setVerifier(0)` / `setHelper(0)`) so a required internal call reverts.
- **Kill-switch ≠ fix (the key distinction).** If the team set a dependency to `address(0)`, that is a *kill-switch*: it halts the contract by making it revert, it does **not** repair the bug. They deployed `0`, not a corrected component. Surviving assets are protected *only by the pause* and remain at risk the moment it is lifted — quantify that remaining value.
- **Is the current deployment still exploitable?** On a fork at head, attempt the same exploit against any remaining assets/markets. If it still works, this is an all-caps warning at the top of the report.
- **Sibling exposure:** enumerate the same code on other chains / other markets / forks and check their balances — the same bug elsewhere is the next target.
- **Remediation surface:** who can fix it and how fast (owner / multisig / timelock)? A single EOA with upgrade rights behind no timelock is itself an open risk, independent of the drain.

Write `containment.md` with an explicit **residual-risk verdict**.

---

## Phase 9: Report

Fill `templates/incident-report.md`:

1. **Executive summary** — protocol, date/UTC, net loss (with method), root cause in one sentence, **current fund status + residual-risk verdict** up top.
2. **Affected contracts** — verified addresses, implementation at `PRE`, roles.
3. **Timeline** — block/timestamp-anchored: funding → deploy → setup txs → exploit tx → fund movement → containment.
4. **Actors** — the address map with on-chain justification.
5. **Technical root cause** — violated invariant, exact source lines, annotated trace excerpt of the divergent call, the vuln-taxonomy class.
6. **Exploit walk-through** — the decoded call tree as narrative, tied to the value-flow ledger, including setup txs.
7. **Loss accounting** — the two independent tallies, valuation basis, residual breakdown, correction log.
8. **PoC** — fork-replay result + the counterfactual that proves causality; evidence verdict.
9. **Fund tracing & status** — flow graph to terminals; freezable-asset flag; recovery prospects.
10. **Containment & residual risk** — how it was stopped, kill-switch-vs-fix, what remains exploitable, sibling deployments.
11. **Remediation** — the specific fix validated by the counterfactual, plus generalizable lessons.
12. **Appendix** — every command with its block number; artifact list; reproduction instructions.

Save to `reports/{incident}-{chain}-{YYYY-MM-DD}.md`.

**Separate CONFIRMED from INFERRED throughout**, and cite a tx hash / block number for every factual claim. An `INCONCLUSIVE` PoC or an unresolved assumption is an explicit limitation, never silently upgraded to a finding.

---

## Scope Boundaries & Disclosure

- On-chain source-and-state forensics only. Off-chain vectors (frontend/DNS compromise, key-management/opsec failure, social engineering) are named as hypotheses when the on-chain evidence points to them, but confirming them is outside this skill.
- If a Critical/High hole is **still live**, treat it as coordinated disclosure: surface remaining-value-at-risk to the user immediately, and do not publish an exploit-ready PoC while funds are still drainable. The full PoC stays in `poc/`; the public report redacts exploit-ready detail until remediation.

## Workflow Summary (Single-Line)

```
preflight → intake(freeze) → confirm+scope → actors → reconstruct(trace+setup txs) → root cause(rule out rug, exploit-time code) → quantify(2 methods, reconcile) → fork replay + counterfactual → trace funds → containment(kill-switch≠fix) → report
```

## Skill Directory Layout

```
security-incident-analysis/
├── SKILL.md                          # This file (entry point)
├── .env.example                      # RPC + explorer API key template
├── config/
│   └── chains.json                   # Chain RPC + explorer + chain-id config
├── references/
│   ├── incident-methodology.md       # Full forensic method + exact commands + anti-fooling (source of truth)
│   └── vuln-taxonomy.md              # Root-cause classes: on-chain tell + fork-confirmation per class
├── templates/
│   ├── incident-report.md            # Final post-mortem skeleton
│   └── poc/
│       └── ForkReplay.t.sol          # Foundry fork-replay + counterfactual harness
└── scripts/
    ├── preflight.sh                  # Env → Chainlist → official/public fallback + archive verification
    ├── load-env.sh                   # Env/API-key loader (sourced)
    ├── intake.sh                     # Pin incident: tx/receipt/block/timestamp + raw artifacts
    ├── find-drain-block.sh           # Binary-search the balance-drop block from an address
    ├── reconcile-loss.sh             # Fail-closed two-method loss tally
    └── test-skill.sh                 # Portable mocked regression suite
```
