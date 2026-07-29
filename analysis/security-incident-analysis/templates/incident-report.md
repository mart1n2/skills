# Incident Post-Mortem — {Protocol} {chain}

> Status: {DRAFT | FINAL} · Analyst: {you} · Report date: {YYYY-MM-DD}
> Every factual claim below cites a tx hash or block number. CONFIRMED = on-chain/replay evidence; INFERRED = reasoning not yet proven on-chain.

## 1. Executive Summary
- **Protocol / component:** {name}, {victim contract(s)}
- **Incident time:** block {BLOCK} · {YYYY-MM-DD HH:MM UTC}
- **Net loss:** {amount + asset(s)} (≈ ${USD} at incident block) — *net of flash-loan principal*; method: {log-sum + balance-delta, reconciled}
- **Root cause (one sentence):** {…} → taxonomy class {N}
- **Fund status:** {on-chain / swapped / mixed / bridged}; **freezable assets outstanding:** {yes+amount / no}
- **⚠ Residual-risk verdict:** {STILL EXPLOITABLE — remaining ${X} at risk / NEUTRALIZED by pause (kill-switch, bug NOT fixed) / FULLY REMEDIATED}
- **Evidence verdict:** {CONFIRMED-DEPLOYED / CONFIRMED-LOGIC / INCONCLUSIVE}

## 2. Affected Contracts
| Role | Address | Impl at PRE | Notes |
|------|---------|-------------|-------|
| Victim (façade/proxy) | | | |
| Where assets sat (vault/strategy/pool) | | | |
| Verifier/oracle/helper dependency | | | |

## 3. Timeline (block / UTC anchored)
| Block | UTC | Tx | Event |
|-------|-----|----|-------|
| | | | attacker EOA funded ({source}) |
| | | | exploit contract deployed |
| | | | setup tx(s): {approve/permit/pre-position} |
| | | | **exploit tx** |
| | | | funds moved out / laundered |
| | | | containment tx ({pause / null dependency}) |

## 4. Actors
| Label | Address | On-chain justification |
|-------|---------|------------------------|
| Attacker EOA | | nonce {n}, funded by {…} |
| Exploit contract | | created in {tx} |
| Beneficiary/recipient | | received {amount} in {tx} |
| Victim | | |

## 5. Technical Root Cause
- **Violated invariant:** {conservation / solvency / oracle-integrity / authorization}
- **Taxonomy class:** {N — name} (see vuln-taxonomy.md)
- **Exact source (exploit-time impl):** `{file}:{lines}`
- **The divergent call (trace excerpt):**
```
{annotated cast run frame showing the broken step}
```
- **Why the check failed to stop it:** {tautology / manipulable read / missing gate / donation-inflated NAV / unbound public input …}

## 6. Exploit Walk-Through
Narrative of the decoded call tree tied to the value-flow ledger, including setup txs:
1. …
2. …

## 7. Loss Accounting
| Asset | Method A (log sum) | Method B (balance delta) | Residual | Valued at block (USD) | Classification |
|-------|--------------------|--------------------------|----------|-----------------------|----------------|
| | | | | | fully drained / test-scratched / staged |

- **Baseline block:** {block before first attacker-touching tx}
- **Flash-loan principal excluded:** {amount, source}
- **Correction log:** {first figure → why wrong → corrected figure}

## 8. Proof of Concept (Fork Replay + Counterfactual)
- **Fork block:** {PRE} · **RPC class:** {archive}
- **Reproduction:** extraction on fork = {amount} ≈ on-chain {amount} ✅
- **Counterfactual:** patched {guard} → drain {reverts / nets ~0} ✅ → causality proven
- **Sensitivity:** profit scales with {flash-loan size / pool depth}; caps {do / do not} prevent drain
- PoC: `poc/ForkReplay.t.sol` · log: `poc/replay.log`

## 9. Fund Tracing & Status
- Flow: {victim → recipient → DEX → unwrap → mixer/bridge/CEX}
- Bridge memo decoded: {chain + destination}
- **Freezable now:** {USDC/USDT held at {addr} — freeze window OPEN / none}
- **Recovery prospects:** {…}

## 10. Containment & Residual Risk
- **Stopped by:** {tx} — mechanism: {pause() / setVerifier(0) / setHelper(0)}
- **Kill-switch vs fix:** {they set 0 = kill-switch, bug NOT repaired / actual fix deployed at {tx}}
- **Remaining value protected only by pause:** {amount + assets}
- **Current-deployment exploitable:** {yes/no — fork-at-head result}
- **Sibling exposure:** {other chains/markets/forks + balances}
- **Remediation surface:** {owner / multisig / timelock; how fast they can fix}

## 11. Remediation
- **Validated fix (matches the counterfactual):** {…}
- **Generalizable lesson:** {…}

## 12. Appendix
- Commands (each with its block number): {…}
- Artifacts: run.env, tx.json, receipt.json, block.json, trace.txt, scope.md, actors.md, rootcause.md, loss.md, funds.md, containment.md, poc/
- Reproduction: {how a third party reruns this}
