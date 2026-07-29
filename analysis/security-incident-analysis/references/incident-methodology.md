# Incident Forensic Methodology (source of truth)

The full method behind `SKILL.md`. Exact commands, per phase, plus the anti-fooling discipline that keeps a public post-mortem from being torn apart. EVM/Solidity is the lingua franca; adapt selectors/tooling for the target chain.

Convention in this file: `$RPC_URL` is the verified archive endpoint, `$TX` the exploit tx, `$VICTIM` the victim contract, `$BLOCK` the exploit block, `$PRE=$((BLOCK-1))`, and `$POST=$BLOCK`. Source `tool-resolution.env` and then `run.env` before using the commands below.

---

## The six anti-fooling rules (apply at every step)

1. **On-chain state beats every claim.** The community "$X drained" is a hypothesis until a `balanceOf` delta or a log sum confirms it.
2. **Pin every query to an explicit block.** Never `latest` in evidence — it drifts and breaks reproducibility. Verify the RPC is archival first (`scripts/preflight.sh`): a pruned node returns wrong/empty historical state *without erroring*.
3. **Compute the loss two independent ways.** Log summation AND balance snapshots; they must agree. Etherscan `txlist`/`tokentx` pagination silently truncates — never use it for totals.
4. **Verify every address on-chain.** Never trust an address transcribed from a webpage or via WebFetch (hex gets mistranscribed). `curl`+`grep` from an API or read it from a trace, then checksum + `cast code`.
5. **Replay before you assert root cause.** A hypothesis becomes a finding only when a fork reproduces it *and* toggling the broken guard stops it.
6. **Keep rival explanations alive.** Soundness/logic bug, privileged/upgrade compromise (rug), and benign migration produce identical fund-flow shapes but need different remediation. Kill two with evidence before naming one.

---

## § 0 — Intake & evidence freeze

Resolve a reachable endpoint from explicit environment configuration, Chainlist, or the configured official/public fallback. Require archival state, then atomically pin the primitives:

```bash
bash "$SKILL_DIR/scripts/preflight.sh" "$CHAIN" "$WORKSPACE"
source "$WORKSPACE/tool-resolution.env"
bash "$SKILL_DIR/scripts/intake.sh" "$TX" "$VICTIM" "$CHAIN" "$WORKSPACE"
source "$WORKSPACE/run.env"

jq -e . "$WORKSPACE/evidence/tx.json" \
  "$WORKSPACE/evidence/receipt.json" "$WORKSPACE/evidence/block.json"
```

`intake.sh` exits nonzero on an RPC or validation failure, refuses to overwrite prior evidence, and writes `run.env` only after the transaction, receipt, and containing block have been validated and atomically moved into place. Read `tx.json`, `receipt.json`, and `block.json` from the saved copies; never re-derive them.

---

## § 1 — Confirm & scope the drain

**Confirm the outflow** (USDC is 6 decimals — $770k = `770000000000`; do not read as 18):

```bash
cast call "$USDC" "balanceOf(address)(uint256)" "$VICTIM" --block "$PRE"  --rpc-url "$RPC_URL"
cast call "$USDC" "balanceOf(address)(uint256)" "$VICTIM" --block "$POST" --rpc-url "$RPC_URL"
```

**Baseline discipline (repeat offender):** the "before" balance must be at the block *before the first attacker-touching tx*. If an attacker seeded/deposited before draining, a naive `PRE` that sits after that seed understates the loss. Enumerate attacker txs against the victim first, take the earliest, and baseline at *its* parent block.

**Address, but no tx?** Bisect for the drop with `scripts/find-drain-block.sh` — but only if the balance is monotone. A sawtoothing balance (ordinary deposit/withdraw traffic) breaks bisection; fall back to the full `Transfer` log scan (§5 Method A).

**All assets, not just the headline one.** Scan every ERC-20 the victim ever received, dedup the token set, snapshot each pre/post. Classify per asset: **fully drained** / **test-scratched** (a few % — attacker probed but didn't cash out) / **staged-but-not-cashed** (net *inflow* — positioned but never withdrawn, often blocked by the pause). Also check native ETH (`cast balance`).

**Contract set.** Resolve proxy → impl *at `$PRE`* and locate where assets actually sit (vault/strategy/ark/pool, not the façade):

```bash
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc  # EIP-1967 impl
ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 # EIP-1967 admin
cast storage "$VICTIM" "$IMPL_SLOT"  --block "$PRE" --rpc-url "$RPC_URL"
cast storage "$VICTIM" "$ADMIN_SLOT" --block "$PRE" --rpc-url "$RPC_URL"
```

---

## § 2 — Actor map

`cast code $ADDR --block $PRE` distinguishes EOA (`0x`) from contract. Keep five roles distinct: **attacker EOA**, **exploit contract(s)**, **beneficiary/recipient**, **funding source**, **victim contract(s)**.

```bash
cast nonce "$ATTACKER" --block "$PRE" --rpc-url "$RPC_URL"       # fresh nonce ⇒ purpose-built
# funding source: earliest inbound value tx to the attacker EOA (leads only, not totals)
```

Exploit contracts are those created in the exploit tx or just before (`receipt.contractAddress`, `CREATE`/`CREATE2` frames in the trace). The USDC `to` in the drain logs is the recipient — possibly a throwaway; its later sweeps are traced in §7. Justify every label with an on-chain fact in `actors.md`.

---

## § 3 — Reconstruct the attack

**Full decoded trace** (prefer `cast run` — archive RPCs disable `debug_traceTransaction`):

```bash
cast run "$TX" --rpc-url "$RPC_URL" -vvvv > "$WORKSPACE/evidence/trace.txt"
```

Read top-down and annotate each frame: contract, function, value moved, class (protocol / token / DEX / attacker code). **Decode inline** (self-contained — no delegation):

```bash
cast 4byte 0xSELECTOR                                            # selector → candidate signatures
cast 4byte-decode 0xCALLDATA                                     # infer + decode via OpenChain
cast calldata-decode "someFn(uint256,address)" 0xCALLDATA        # decode against a known signature
```

Build the value-flow ledger from receipt logs. ERC-20 `Transfer(address,address,uint256)` topic0 = `0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef`; `from`=topics[1], `to`=topics[2], amount=data:

```bash
jq -r '.logs[] | select(.topics[0]=="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")
       | [.address,.topics[1],.topics[2],.data] | @tsv' "$WORKSPACE/evidence/receipt.json"
```

**Setup / pre txs (do not skip).** Funding, `approve`, `permit` (EIP-2612 phishing), share/collateral pre-positioning, and phantom-note seeding usually live in *earlier* txs. Enumerate the attacker's full tx set against the victim and its assets; identify the first-exploit tx. A same-tx replay that consumes a pre-positioned lever created in an earlier tx will show a **false** loss — always reconcile P&L across the whole set plus balance snapshots.

**Capital source.** Grep the trace for the outermost flash loan (Aave `flashLoan`/`flashLoanSimple`, Balancer `flashLoan`, Morpho, Uniswap V3 `flash`, Maker flash-mint) and its tail repayment. Flash-loan-funded ⇒ zero attacker capital ⇒ points at a pricing/accounting flaw, not a stolen key.

---

## § 4 — Root cause

**Rule out the boring cause first.** Diff the impl slot across the drain and scan the proxy for admin actions:

```bash
cast storage "$VICTIM" "$IMPL_SLOT" --block "$PRE" --rpc-url "$RPC_URL"
cast storage "$VICTIM" "$IMPL_SLOT" --block "$POST" --rpc-url "$RPC_URL" # changed ⇒ upgrade mid-incident
# Upgraded(address) topic0: 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b
```

If the impl changed just before the drain, or the drain caller *is* the owner/admin, this is a rug/key-compromise — pivot the whole narrative and remediation.

**Read the exploit-time code.** Fetch source for the impl *resolved at `$PRE`* (Etherscan `getsourcecode`, or GitHub at the deployment commit for unverified/non-mainnet). Never audit head code for a past exploit.

**Name the violated invariant**, then classify against `vuln-taxonomy.md`. The highest-yield tells are **tautological / self-referential checks**: a balance-sufficiency check that trusts the value the proof/accounting must enforce; `underlying.convertToAssets(underlying.balanceOf(self))` NAV (donation-inflatable + illiquidity-blind); a price read from a pool moved in the same tx.

---

## § 5 — Quantify loss (two methods)

`scripts/reconcile-loss.sh` runs both for one asset. Manually:

**Method A — event-log sum** (outflows from victim):

```bash
POOLTOPIC="0x000000000000000000000000${VICTIM:2}"
FROM_HEX="$(cast to-hex $((BASELINE-50)))"
TO_HEX="$(cast to-hex "$TO_BLOCK")"  # explicit incident-window end; never latest
cast rpc eth_getLogs '{"address":"'$USDC'","fromBlock":"'$FROM_HEX'","toBlock":"'$TO_HEX'",
  "topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","'$POOLTOPIC'"]}' \
  --rpc-url "$RPC_URL" | jq -r '.[] | [.blockNumber,.transactionHash,.topics[2],.data] | @tsv'
```

Chunk the range in ~10k-block windows if the provider caps it. Sum `value` to attacker-controlled recipients. **Never Etherscan `txlist`/`tokentx` for totals — silent truncation.**

**Method B — balance-snapshot delta:** `balanceOf(victim)` at baseline vs post; plus `totalAssets()`/`totalSupply()` for vault accounting.

**Reconcile.** A ≈ B within dust; itemize residual (flash-loan fee, gas, slippage). Report attacker **NET** extraction — exclude round-tripped flash-loan principal (the #1 inflated-figure cause). Value each asset at the incident block (`latestRoundData` at `$BLOCK` / DEX TWAP), never current price. **Correction log:** if a first figure was wrong, state it and the cause (truncation / bad baseline).

For a shielded/anonymity-set pool there are no per-user victims — quantify the **insolvency gap** = outstanding deposit liabilities − remaining assets; post-drain, honest depositors simply cannot exit.

---

## § 6 — Fork replay + counterfactual

Initialize a clean Foundry workspace, then copy the bundled harness into the path the test command actually matches:

```bash
source "$WORKSPACE/run.env"
mkdir -p "$WORKSPACE/poc"
(
  cd "$WORKSPACE/poc"
  forge init --no-git --force .
  cp "$SKILL_DIR/templates/poc/ForkReplay.t.sol" test/ForkReplay.t.sol
  set -o pipefail
  forge test --fork-url "$RPC_URL" --fork-block-number "$PRE" \
    --match-path test/ForkReplay.t.sol -vvvv 2>&1 | tee replay.log
)
```

1. **Reproduce:** fresh attacker address (no pre-funding), replay the sequence, assert extraction ≈ Phase-5 figure. Matching the *real amount* is the proof you have the true mechanism.
2. **Counterfactual (falsification):** patch only the hypothesized flaw (oracle-price the manipulable read / add the gate / supply a valid proof / mark the nullifier) → assert revert or ~0 profit. If the drain survives, root cause is wrong → back to §4.
3. **Sensitivity:** scale flash-loan size; confirm profit tracks the mechanism. Per-band/per-tx caps that merely rate-limit are not mitigations — say so.

Verdict: `CONFIRMED-DEPLOYED` / `CONFIRMED-LOGIC` / `INCONCLUSIVE` (record the exact blocker; don't downgrade for tooling failure) / `REFUTED` (a faithful test disproves a precondition — a bare revert or missing liquidity is not refutation).

---

## § 7 — Fund tracing & attribution

Walk forward from each recipient (EOA and exploit contract):

```bash
RCPT="0x000000000000000000000000${ATTACKER:2}"
TRACE_HEAD="$(cast block-number --rpc-url "$RPC_URL")"  # record this explicit tracing cutoff
cast rpc eth_getLogs '{"fromBlock":"'$(cast to-hex "$BLOCK")'","toBlock":"'$(cast to-hex "$TRACE_HEAD")'",
  "topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","'$RCPT'"]}' --rpc-url "$RPC_URL"
cast run "$FOLLOWUP_TX" --rpc-url "$RPC_URL"      # see the DEX swap / bridge calldata
```

Typical path: USDC → DEX router → WETH → unwrap → **Tornado/Railgun** or **bridge**. Terminals to record: mixer, bridge, CEX deposit.

- **Decode bridge memos.** A THORChain memo (`=:CHAIN:DEST_ADDR:...`) reveals the cross-chain destination — decode it; it is often the only pointer to where value actually went.
- **Freezable-asset flag:** attacker still holding USDC/USDT ⇒ issuer freeze window — surface at the top of the report immediately. Swapped-to-ETH-and-mixed ⇒ recovery ~impossible; state it.
- **Attribution:** on-chain proof only (funded / deployed / directly received). No real-world identity claims. Trace decoys and throwaway contracts too; don't stop at hop 1.

---

## § 8 — Containment & residual risk

- **Stop mechanism + tx:** `cast call $VICTIM "paused()(bool)"`; scan for the emergency-stop tx after the drain. Many stops are *not* `pause()` but nulling a dependency (`setVerifier(0)`, `setHelper(0)`, `setOracle(0)`) so a required internal call reverts. Confirm the current value on-chain.
- **Kill-switch ≠ fix.** Setting a dependency to `address(0)` halts the contract by reverting; it does **not** repair the bug — they deployed `0`, not a corrected component. Surviving assets are protected *only by the pause* and are at risk the instant it is lifted. Quantify that value.
- **Still exploitable?** Fork at head, attempt the same exploit on remaining assets. Success ⇒ all-caps warning.
- **Sibling exposure:** same code on other chains/markets/forks — enumerate the deployer's other contracts and snapshot their balances.
- **Remediation surface:** owner / multisig / timelock, and how fast. A single EOA with untimelocked upgrade rights is itself an open risk.

---

## § 9 — Report & self-review (before publishing)

Adversarial self-check: Method A ≈ Method B and PoC ≈ on-chain extraction; net-of-flash-loan headline; counterfactual demonstrably breaks the exploit; rival hypotheses (§ anti-fooling rule 6) explicitly dismissed with evidence; every address re-verified against on-chain code hash; scope-of-exposure (sibling deployments, impl still live) checked. Optionally have a fresh reader (no access to your hypotheses) read the trace cold and state the bug — divergence flags confirmation bias. Then fill `templates/incident-report.md`.
