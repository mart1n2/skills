---
name: contract-security-audit
description: >
  Audit production smart contracts using a lightweight blackboard and goal-directed state-space search, unrestricted discovery and validation methods, evidence-bound candidates, independent triage, and human-signed-off reports. Use for smart contract audits, vulnerability hunting, exploit/PoC verification, protocol economic-design review, or audit reports. Native references cover EVM, Solana, and Sui; Aptos is comparative only. Compatible with Claude, Codex, and Hermes; bundled scripts support macOS/Linux Bash 3.2+.
---

# Contract Security Audit (Goal-Directed Search + Evidence Triage)

Methodology-driven source audit with independently reviewable evidence. Discovery and validation methods are deliberately unrestricted; the skill constrains what may be claimed, not how an agent must discover or prove it. The architecture is four layers:

- **Spine** (`references/methodology.md`) — chain-agnostic: truth-gate rationale, an optional reachability-atlas scaffold, optional A–J lenses, and severity calibration, written in EVM/Solidity as the lingua franca. Its discovery/validation techniques are examples, not the source of a claim's truth.
- **Triage** (`references/triage.md`) — candidate contract, claim/evidence gates, independent validation, deduplication, and the report-stage human sign-off. The source of truth for deciding what may enter `findings.md`.
- **Playbook** (`references/playbook-{solana,sui}.md`) — chain-native attack surfaces plus optional hunting and verification techniques. EVM's playbook content lives inline in the spine; Solana and Sui get dedicated files because their primitives diverge too far for in-head translation.
- **Metrics** (`references/metrics-{evm,solana,sui}.md`) — per-chain
  *known-pattern catalogs*: candidate triggers, vulnerable→fix pairs, and
  historical pointers. Catalog matches do not validate a finding; verify primary
  sources before citing incident facts.

This skill is self-contained — all scripts, PoC templates (EVM/Solana/Sui), and chain configs ship inside the skill directory.

## Working Model: Blackboard + Goal-Directed Search

For audit discovery, use [references/goal-directed-search.md](references/goal-directed-search.md)
as the default reasoning loop. Select one open security or proof obligation,
choose the most informative next action, retain the result, and update what is
known and what remains open. Tool choice stays unrestricted within the task's
permissions. A focused verification or report-only request consumes the relevant
obligations; it does not trigger a new full audit.

Independent validation is deferred to report preparation. During ordinary search,
build and falsify evidence, record complete producer packages as `REPRODUCED`,
and continue other goals without waiting for a validator. Before reporting,
independently review the selected candidates, admit passing findings under
`triage.md`, then obtain human sign-off. Report preparation is the trigger for
that separate review, not every successful search step. An additional agent may
perform this review: it must independently inspect and challenge the primary
evidence, not just endorse the producer or change model/session identity. It may
write a PoC, inspect pinned on-chain state, derive a proof, or combine methods.
See `triage.md` for the handoff and write-ownership rules.

Human attention goes to the final findings (including severity and disclosure)
and selected anomalous leads that need intent, risk, or unresolved-conflict
judgment. Agents handle ordinary search, evidence work, and dispositions without
per-step human approval. Keep evidence-anchored anomalies in `search.md` using
the lead policy in `goal-directed-search.md`; they are neither findings nor an
automatic reason to interrupt the user. Missing authority still requires approval.

The blackboard is the linked engagement record: `scope.md`, `target-lock.md`,
model artifacts, per-candidate files, retained evidence, and `coverage.md`.
Use one small `search.md` for active goals, partial paths, and the frontier when
work spans multiple steps; adapt [templates/search.md](templates/search.md).
Existing equivalent working notes are sufficient. Link canonical records rather
than copying their status or evidence into a second registry. No database, graph
service or Pi runtime is required. Discovery can run with one agent; report-stage
independent validation requires a separate reviewer, which may be an extra agent.

Search backward from a violated property toward necessary conditions, and forward
from real actors and observations toward consequences. Meeting at a shared state
location schedules a semantic check; it establishes neither reachability nor a
vulnerability. Keep actor, mapping key, storage context, time, and constraints
intact. Economic and liveness goals remain valid without a call-chain-shaped model.

Before accepting a reasoning step, check its target binding, input references,
changed obligations, and retained evidence. Record corrections and dependencies;
do not silently replace a relied-on premise. In this skill-only mode the main
auditor performs that control role; these instructions are not a mechanically
enforced Controller. Findings still pass `triage.md`, independent validation, and
the separate report sign-off gate.

## Runtime Compatibility

Use the same source tree on all supported agent platforms:

| Agent | Default install directory | Detection signal |
|-------|---------------------------|------------------|
| Claude | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/contract-security-audit` | default when no Codex/Hermes runtime signal exists |
| Codex | `${CODEX_HOME:-$HOME/.codex}/skills/contract-security-audit` | `CODEX_SHELL` |
| Hermes | `${HERMES_HOME:-$HOME/.hermes}/skills/contract-security-audit` | `HERMES_SESSION_ID` |

Hermes accepts the same `SKILL.md` `name`/`description` frontmatter and recursively discovers supporting files under `~/.hermes/skills/`. Keep platform-specific metadata out of the shared frontmatter unless all three parsers accept it.

Run every bundled `.sh` explicitly with `bash`; do not rely on the user's interactive shell:

```bash
bash "$SKILL_DIR/scripts/compat-check.sh"
```

- Supported: macOS with zsh as the interactive shell and Apple Bash 3.2+, Linux with Bash 3.2+.
- Do not use Bash 4-only features (`mapfile`, associative arrays, `${var,,}`, namerefs) or GNU-only tool flags without a Darwin fallback.
- Treat a failed compatibility check as blocking the affected bundled-helper or
  artifact-generation workflow. It does not make an otherwise sound manual,
  agentic, or external-tool audit method invalid; use another sound method or
  report the specific helper limitation.

> **First principles:**
>
> **Axiom 1 — A useful exploit model:** A fund-related exploit can be modeled as a reachable chain of state transitions from an entry point to a fund-effect sink that either (a) is outside the protocol's intended set, or (b) is intended but violates a safety/economic invariant or lets one actor extract value at another party's expense. This model helps expose chain-shaped bugs, but it is not a required discovery route or a complete definition of every security impact.
>
> **Axiom 2 — Optional ways to look:** Adversarial enumeration and the lenses below are high-recall thinking tools, not a prescribed workflow or checklist. The docs express intended behavior; target evidence determines actual behavior. The metric catalogs in `references/` are a reference library of historical patterns, not a coverage list.
>
> **Axiom 3 — What may count:** An agent is a search tool, not an oracle. A candidate becomes a finding when reviewable evidence binds the claimed mechanism, reachability, impact, scope, and deployment state; survives a relevant falsification attempt; is deduplicated; and is independently validated. `findings = independently_validate(evidence_bind(candidates))`. Proof is the admission gate. A human auditor then signs each finding, its severity, and its disclosure decision before any report is issued: `report = human_signoff(findings)`. Candidate volume is not an audit outcome; triage quality is.
>
> **Axiom 4 — Methods are open:** manual review, agents, SAST, fuzzing, invariant/property testing, symbolic execution, formal methods, differential analysis, historical transactions, simulations, traces, replays, source-level proofs, or any combination may discover or validate a candidate. No method earns a finding by name, and no sound method is excluded. The evidence must support the exact claim.
>
> **Axiom 5 — Proof, not paperwork:** Claims bind to the target by identity (chain, deployment/program/package ID, revision, build profile, artifact path) and to evidence by a retained, openable artifact. SHA-256 digests are optional integrity bookkeeping for internal review and required only under `--strict-hashes` (external delivery, moving baselines, shared workspaces). A digest that *is* recorded must be correct; an absent digest is not a defect, but a missing or unreadable proof artifact always is.

---

## Chain Support Matrix

| Chain  | Spine (`methodology.md`) | Chain-native reference and optional techniques | Metrics catalog | Optional examples |
|--------|--------------------------|------------------------------------------------|-----------------|-------------------|
| **EVM** (Ethereum + L2s, Solidity/Vyper) | ✅ | ✅ inline in spine (optional ladder and Foundry examples) | ✅ `metrics-evm.md` — dated historical pointers; no aggregate-coverage claim | Foundry templates (`templates/simulation/`) |
| **Solana** (Rust / Anchor) | ✅ | ✅ `playbook-solana.md` — semantics, optional prompts, LiteSVM/Mollusk/coherent-snapshot guidance | ✅ `metrics-solana.md` — SlowMist-derived catalog + incidents (Cashio/Wormhole/Mango/Jet) | LiteSVM + exploratory live-clone scaffold (`templates/solana/`) |
| **Sui** (Move) | ✅ | ✅ `playbook-sui.md` — semantics, optional prompts, `test_scenario`/localnet examples | ✅ `metrics-sui.md` — SlowMist-derived catalog | `sui move test` / localnet reconstruction (`templates/sui/`) |
| **Aptos** (Move) | ✅ principles only | ❌ no native production reference | ⚠ comparative notes in `metrics-sui.md` | unsupported — do not translate Sui object-model assumptions |

**What this means in practice:** the phases below are stable artifact vocabulary
and a truth/closure model, not a required discovery order. Load `methodology.md`
and `triage.md`, plus native semantics for the target chain. Grep recipes,
ladders, catalogs, and PoC templates are optional accelerators, not required
routes; a catalog match is precedent, never proof.

> **Why EVM has no separate playbook file:** the spine is written in EVM/Solidity as the lingua franca, so EVM's ladder and PoC library live inline in `methodology.md`. Solana and Sui diverge far enough (account model, capability discipline, object ownership) that in-head translation is lossy — hence dedicated playbook files. The three chains are at parity; only the file layout differs.

---

## Quick Reference

| Phase | Output | Owner |
|-------|--------|-------|
| 0. Setup | `audit-workspace/{protocol}/` initialized; `scope.md` records scope and `target-lock.md` initializes the immutable target snapshot | recon/main |
| 1. Source fetch + target lock | `contracts/` populated; target identity reconciled between `scope.md` and `target-lock.md`; every relied-on target artifact assigned a `T-NN` ID and path (SHA-256 optional internally) | main |
| 2. Understand the target (O, recommended artifact) | `audit-workspace/{protocol}/orientation.md` or pointers to equivalent reviewable semantic-model evidence | main |
| 3. Reachability/coverage model (P, optional scaffold) | reviewable evidence for entries, state transitions, sinks, intent, and residual blind spots; the bundled `atlas/` is one option | main |
| 4. Record the security model (C/D/E, optional scaffolds) | `audit-workspace/{protocol}/model.md` or pointers to equivalent invariant, transition, and trust evidence | main |
| 5. Register candidates | `triage/candidates.md` + one schema-complete `triage/candidates/C-NN.md` per material lead, regardless of discovery method | recon |
| 6. Challenge candidates | candidate files enriched with reachability, consequence, falsification, and scope/state evidence appropriate to each claim | hunter |
| 7. Explore residual surfaces | optional A/B/F/G/H/X/J lenses or any other methods; append material leads under the same candidate contract | recon/hunter |
| 8. Verify + producer triage | evidence artifacts, manifests, falsification, dedup; complete producer packages remain `REPRODUCED` | hunter/main |
| 9. Severity calibration (I) | provisional candidate impact assessment; final finding calibration after report-preparation review | main |
| 10. Report preparation + sign-off | independent validation of selected candidates, record passing findings, human sign-off, then internal report under `reports/` | independent validator + human + main |

Track closure throughout in `audit-workspace/{protocol}/coverage.md`; an unresolved row is a limitation, never a pass.

### Workspace Data Retention

Keep audit-related inputs, intermediate results, and final artifacts under
`audit-workspace/{protocol}/`. The workspace is the durable engagement record,
not disposable scratch space.

- Use `tmp/` inside the audit workspace for raw downloads, parser output,
  decompiler output, traces, logs, snapshots, generated corpora, and other
  intermediate data whose lasting evidentiary value is not yet known.
- Preserve every artifact that informed target identity, discovery, a
  falsification attempt, candidate disposition, finding verification, coverage,
  remediation review, or report content. Promote stable proof packages to
  `evidence/` or `poc/` when useful, but retain relevant raw/intermediate data in
  `tmp/` as well when it is needed to reproduce or audit the derivation.
- Do not automatically clean, prune, overwrite, or discard workspace data merely
  because it is named `tmp`, a candidate was rejected, or the final report is
  complete. Remove engagement data only on an explicit user instruction and only
  after checking that no retained conclusion depends on it.
- OS-level temporary directories may be used for atomic helper implementation
  details that have no audit relevance. Any audit-relevant output created there
  must be copied into the workspace before the operation ends.
- Bundled helpers that refresh current source, on-chain, compiler, preflight, or
  Atlas outputs snapshot the prior non-empty artifact under
  `tmp/{helper}/{UTC-run-id}/` first. Preserve these snapshots. In particular,
  never rerun the Atlas over semantically enriched tables without retaining the
  prior directory.
- Preserve the internal workspace alongside any generated report. The report
  is a projection of retained evidence, never the sole record of the audit.
- Store the default internal report and any explicitly requested external-report
  source under `reports/` in the audit workspace. A file copied to top-level
  `audits/`, a client portal, or a public location is a delivery copy, not the
  only retained report artifact.
- Record remediation deliveries, client responses, exact fix revisions, retest
  evidence/results, residual risk, and disclosure handling in the corresponding
  recorded entry in `findings.md` as those facts arise. Keep source communications
  and raw artifacts in `evidence/` or `tmp/` under the engagement's access rules.

For an existing workspace created by an earlier skill version, re-run
`init-workspace.sh` with the same protocol/chain to add missing durable directories
without deleting data. Before final checking, migrate each recorded finding
manually: rename `Severity` to `Original severity`, then add current remediation
status, deployment/state anchor, client response, remediation baseline, retest,
residual risk, and disclosure handling. Use explicit reasoned `NOT ASSESSED`,
`NOT PROVIDED`, or `NOT YET RETESTED` values where facts do not exist. Never infer
a fix, exposure state, client decision, or retest result during migration.

> **Loop, don't pipeline.** Failed falsification or incomplete evidence sends a candidate back to discovery and modeling. The phase numbers are stable artifacts; their order is iteration, not a one-pass funnel.

**Reference files (load for the work being performed):**

- `references/goal-directed-search.md` — default blackboard, frontier, bidirectional search, semantic meeting, and resume/closure rules. Read for discovery, gap-filling, or resuming an audit; unnecessary for a report-only formatting change.
- `references/methodology.md` — first principles, truth-gate rationale, and optional P / A–J lenses (chain-agnostic). Always load for the shared evidence contract; use or replace its techniques freely.
- `references/triage.md` — candidate lifecycle, role boundaries, verification-evidence contract, false-positive gates, independent validation, dedup, metrics, and the report-stage human sign-off. Always load.
- `references/playbook-solana.md` / `references/playbook-sui.md` — chain-native attack surfaces and optional hunting/verification techniques. Load for Solana/Sui audits. (EVM's playbook is inline in the spine.)
- `references/metrics-{evm|solana|sui}.md` — the chain's **known-pattern catalog**
  for cross-reference and optional verification modeling. **Not a checklist;
  absence of a match is not safety, and incident pointers require primary-source
  verification before citation.**
- `config/chains.json` — chain RPC + explorer config (incl. Solana/Sui; Aptos is metadata-only)
- `config/compiler-cves.json` — compiler version advisory database (EVM)
- `references/evm-tools.md` — read when selecting Etherscan API/CLI acquisition,
  Halmos symbolic properties, or Echidna campaigns; includes result limits and
  retained-evidence guidance. These tools are optional, not audit prerequisites.

**Bundled scripts (all under `scripts/`):**

- `compat-check.sh` — Claude/Codex/Hermes path + macOS/Linux Bash portability check
- `test-skill.sh` — portable local/CI smoke suite for scripts, JSON, workspace bootstrap, atlas, and compiler checks
- `preflight.sh` — tool detection, env loading, chain config resolution
- `fetch-source.sh` — verified source from Etherscan V2 / Sourcify / GitHub
- `collect-onchain-data.sh` — on-chain state, owner, role, proxy data
- `check-compiler.sh` — pragma vs CVE database check
- `atlas-inventory.sh` — Pass P bootstrap: seed sinks/gates/writes tables from grep over source (EVM / Solana / Move)
- `triage-index.sh` — deterministically rebuild/check the shared candidate index from one-file-per-candidate sources, reducing multi-agent edit conflicts
- `triage-check.sh` — portable final acceptance check for pinned scope, closure placeholders, candidate/finding separation, verification artifacts, and independent validation; `--report` additionally requires human sign-off, `--strict-hashes` additionally requires every integrity digest, and `--bootstrap` validates only a newly initialized workspace's structure
- `retention.sh` — shared non-destructive snapshot helper used before bundled scripts replace audit-relevant current outputs
- `load-env.sh` — env var loader (sourced by other scripts)
- `init-workspace.sh` — bootstrap workspace + references

**Bundled templates:**

- `templates/audit-report.md` — default internal reference report with candidate provenance, evidence, triage closure, coverage, findings, and limitations
- `templates/search.md` — compact active-goal and frontier scaffold; links existing authoritative artifacts without duplicating them
- `templates/external-audit-report.md` — optional professional client/public report, generated only on explicit request; includes exact scope/baseline, disclosure controls, remediation status, limitations, and release gate
- `templates/simulation/` — **EVM** Foundry fork PoCs: `BaseTest.sol` (fork setup, labels, deal helpers), `FlashLoanAttack.t.sol`, `OracleManipulation.t.sol`, `ReentrancyAttack.t.sol`, `ShareInflation.t.sol`, `GovernanceAttack.t.sol`
- `templates/solana/` — **Solana** PoCs: `litesvm_harness.rs` (base), `exploit_signer_and_substitution.rs`, `fork_replay.sh` (fail-closed live-clone scaffold; adapt to a coherent snapshot)
- `templates/sui/` — **Sui/Move** PoCs: `exploit_shared_object.move`, `exploit_shift_truncation.move` (`test_scenario`), `localnet_replay.sh`

---

## Phase 0: Setup

Resolve protocol identifier, chain, and target addresses. Create workspace.

```bash
PROTOCOL="{lowercase-kebab-name}"      # e.g., "morpho-blue"
CHAIN="{evm-name|solana|sui}"          # e.g., "ethereum", "arbitrum", "solana", "sui"

# Override explicitly when the skill is installed elsewhere. Prefer the active
# runtime's copy so its private .env is not silently borrowed from another runtime.
if [ -n "${CONTRACT_AUDIT_SKILL_DIR:-}" ]; then
  SKILL_DIR="$CONTRACT_AUDIT_SKILL_DIR"
elif [ -n "${HERMES_SESSION_ID:-}" ]; then
  SKILL_DIR="${HERMES_HOME:-$HOME/.hermes}/skills/contract-security-audit"
elif [ -n "${CODEX_SHELL:-}" ]; then
  SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/contract-security-audit"
else
  SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/contract-security-audit"
fi
[ -f "$SKILL_DIR/SKILL.md" ] || { echo "contract-security-audit skill not found: $SKILL_DIR" >&2; exit 1; }

bash "$SKILL_DIR/scripts/compat-check.sh"
bash "$SKILL_DIR/scripts/init-workspace.sh" "$PROTOCOL" "$CHAIN"
WORKSPACE="audit-workspace/${PROTOCOL}"
```

**Chain class determines which playbook + metrics files to load:**

| Chain class | Playbook | Metrics catalog | PoC templates |
|-------------|----------|-----------------|---------------|
| EVM (`ethereum`, `arbitrum`, `optimism`, `base`, `polygon`, `bsc`, …) | inline in `methodology.md` | `references/metrics-evm.md` | `templates/simulation/` |
| Solana | `references/playbook-solana.md` | `references/metrics-solana.md` | `templates/solana/` |
| Sui | `references/playbook-sui.md` | `references/metrics-sui.md` | `templates/sui/` |
| Aptos | **unsupported** — stop; a Sui playbook is not an Aptos-native audit | comparative notes only | none |

Always load `references/methodology.md` for the shared claim/evidence vocabulary. For Solana and Sui, also load the chain's semantic reference before Phase 2. The metrics catalog is the chain-specific pattern reference; none of these files restricts discovery or validation methods, and only target-faithful evidence supports truth.

**For EVM helpers:** optionally run the bundled preflight to inventory available
capabilities before invoking fetch, RPC, compiler, or Foundry scripts:

```bash
bash "$SKILL_DIR/scripts/preflight.sh" "$WORKSPACE"
source "$WORKSPACE/tool-resolution.env"
# Use $HAS_FORGE, $HAS_CAST in conditional logic
# Optional inventory: $HAS_ETHERSCAN_CLI, $HAS_HALMOS, $HAS_ECHIDNA
```

`AUDIT_MODE` describes those helper capabilities, not the truth of a candidate.
If a selected helper is blocked, choose another sound method or report the
specific unclosed proof obligation; do not downgrade a claim merely because an
unneeded tool is absent.

### Target-Lock Contract

`scope.md` records engagement scope, exclusions, and evolving work units.
`target-lock.md` is the canonical snapshot that evidence-bearing claims bind to;
it contains the same target-identity values as `scope.md` plus the target
artifact manifest. Complete it after acquiring the target:

- reconcile Protocol, Chain, source repository/package, source revision,
  deployment/program/package IDs, deployed digest, production build or identity
  procedure, compiler/toolchain, and configuration/state anchor exactly with
  `scope.md`;
- use chain-native deployment identifiers and digests (for example a 20-byte
  EVM address plus 32-byte code hash, Solana program ID plus deployed-binary
  digest, or Sui package ID plus package/object digest), then verify their
  actual chain/revision association from primary artifacts;
- assign every source, bytecode, package, configuration, or other target artifact
  relied on by the audit a stable `T-NN` ID, workspace-relative `contracts/`
  path, and substantive role; and
- record the exact relevant artifact-ID set (for example `T-01,T-03`) in every
  candidate, verification manifest, independent validation, and recorded finding.

**Digests are optional for internal review.** Per-artifact SHA-256 values and the
digest of the completed `target-lock.md` are integrity bookkeeping, not the binding
itself — the binding is the identity above plus the artifact set. Record them when
integrity matters (client/public delivery, a moving baseline, a shared or
long-running workspace) using `shasum -a 256 <path>` on macOS or
`sha256sum <path>` on Linux, and enforce them with
`bash "$SKILL_DIR/scripts/triage-check.sh" --strict-hashes "$WORKSPACE"`. Whatever
digest you do record is verified: a wrong or stale value fails the checker in every
mode, while an absent one fails only under `--strict-hashes`. Deployment
identifiers (address, program ID, package ID) remain required for any deployed
claim in every mode; only the digest columns relax.

The lock and checker establish target identity, native identifier shape, and
cross-record consistency; they cannot by themselves prove that a typed address,
hash, source revision, or human/validator identity is authentic. Primary
deployment/build/state evidence plus independent review establish that semantic
association. This does not constrain how a vulnerability is discovered or
validated. If any identity value or target
artifact content changes, re-check every linked claim and artifact set and refresh
any digest that was recorded. Never bulk-replace a digest merely to make stale
evidence pass. Scope work-unit or coverage edits that do not alter target
identity/artifacts do not require a new target lock.

**For Solana CLI/Anchor helpers (optional):** record `solana --version` and
`anchor --version`; configure a read-only RPC only if the selected method needs
it (for example `solana config set --url mainnet-beta`).

**For Sui CLI helpers (optional):** record `sui --version`; select mainnet,
testnet, or localnet only when required by the chosen acquisition or validation
method.

---

## Phase 1: Source Acquisition

### EVM

Use the bundled fetch script (handles Etherscan V2, Sourcify, GitHub fallback):

```bash
bash "$SKILL_DIR/scripts/fetch-source.sh" \
  "$ADDRESSES" "$CHAIN" "$WORKSPACE/contracts"
```

The helper retains complete explorer response bodies and sanitized request
metadata in each `tmp/fetch-source/<run-id>` generation before extracting source.
Keep these records, including failed responses, for build/proxy reconciliation.
For ad hoc CLI queries or another acquisition path, use
[references/evm-tools.md](references/evm-tools.md). API and CLI share Etherscan's
data and limits; using both does not provide independent corroboration.

Validate verification status:

- Bytecode + metadata match
- All linked libraries verified
- Note any proxy patterns (UUPS / Transparent / Beacon) — fetch implementation contracts too

For source from a public repo at a specific commit:

```bash
GITHUB_URL="https://github.com/{org}/{repo}" GITHUB_REF="{commit-sha}" \
  bash "$SKILL_DIR/scripts/fetch-source.sh" \
  "$ADDRESSES" "$CHAIN" "$WORKSPACE/contracts"
```

`GITHUB_REF` must be the full 40-hex commit SHA. When both variables are set,
the helper fetches that exact detached revision into a fresh retained run,
verifies `HEAD` equals the requested SHA, records the resolved commit, and only
then promotes the source. A failed run never reclassifies stale contracts as the
new current target. This repository path is optional: do not set `GITHUB_URL` or
`GITHUB_REF` for a chain-only target and never invent a commit SHA for one.

Collect on-chain context (owner, roles, proxy slot, role events):

```bash
bash "$SKILL_DIR/scripts/collect-onchain-data.sh" \
  "$ADDRESSES" "$CHAIN" "$RPC_URL" "$WORKSPACE/evidence" "$WORKSPACE"
```

For a chain-only target, delete repository-only rows from the released report or
mark them `NOT APPLICABLE - chain-only target`. Bind the target instead with the
chain/network ID, deployment address or native program/package/object ID, code or
package digest, and an immutable observation-state anchor. If acquisition starts
from `latest`, resolve it once and record at least the EVM block number **and block
hash** (or the chain-native equivalent); never retain floating `latest` or a block
number alone as the identity marker. The bundled collector records a non-atomic
start/end observation window. Use a separately pinned procedure when a finding's
deployment-exposure claim requires one-state correspondence.

### Solana

One optional acquisition and build-verification path is:

```bash
# Fetch program binary
solana program dump "$PROGRAM_ID" "$WORKSPACE/contracts/${PROGRAM_ID}.so"

# If source is open, clone the repo at the deployment commit
git clone "$REPO_URL" "$WORKSPACE/contracts/src"
cd "$WORKSPACE/contracts/src" && git checkout "$DEPLOY_COMMIT"

# Produce a deterministic build, then separately compare it with the deployment
anchor build --verifiable
anchor verify -p "$PROGRAM_LIB_NAME" "$PROGRAM_ID"
```

See `references/playbook-solana.md § 5` for verified-build matching and the closed-source (bytecode-only) caveat.

### Sui

One optional acquisition and source-verification path is:

```bash
# Fetch package source if open
git clone "$REPO_URL" "$WORKSPACE/contracts/src"
cd "$WORKSPACE/contracts/src" && git checkout "$DEPLOY_REF"

# Inspect on-chain package + confirm source matches the published bytecode
sui client object "$PACKAGE_ID" --json
sui client verify-source
```

See `references/playbook-sui.md § 5`. When ownership is material, capture each
in-scope object's current on-chain owner representation, including
address/object-owned, shared, immutable, and consensus-owned party forms, plus
wrapping/nesting and relevant callable paths.

---

## Phase 2: Understand the Target (Optional Pre-Pass O Scaffold)

> A truthful claim requires an accurate target model. The O artifact below is one efficient way to record that model, not a required discovery route. An existing specification, call graph, state model, formal model, or other reviewable evidence may replace or augment it; link that evidence from `orientation.md`. See `references/methodology.md § O`.

When using this scaffold, produce `$WORKSPACE/orientation.md` containing:

- **O.1 One-paragraph protocol summary** — written in your own words, not copied from docs. Whose money is here? Who is the user / operator / admin? What is the central economic loop? What does "things going wrong" look like *from the protocol's perspective*?
- **O.2 Value-flow diagram** — every asset the contract touches, with in/out edges. Answer "if I were trying to steal this, where would I aim?" in one glance.
- **O.3 Storage glossary** — every storage variable: what does it mean, who writes it, who reads it (sink-implications).
- **O.4 Pre-read red flags** — minute-zero structural smells (EOA-controlled upgrade, open initializer, balance-based accounting, fee-on-transfer naive math, tx.origin auth, raw ecrecover, hardhat/console imports, whole-struct mapping overwrites, `using X for Y` library bindings).

Keep the artifact proportionate to the target. Before accepting a finding, the recorded evidence must still establish every semantic assumption material to that claim, whether it came from O or another method.

---

## Phase 3: Reachability and Coverage Model (Pre-Pass P — Optional Scaffold)

> The bundled reachability atlas is a strong default for chain-shaped bugs, but it is not a restriction on discovery. Replace or augment it with any method that produces equivalent or stronger reviewable coverage evidence. See `references/methodology.md § P` for the scaffold.

Goal: make coverage claims reviewable: identify the security-relevant surface examined, what method covered it, what evidence supports closure, and what blind spots remain. The bundled regex helper is only a lower-bound seed.

```bash
mkdir -p "$WORKSPACE/atlas"
bash "$SKILL_DIR/scripts/atlas-inventory.sh" "$WORKSPACE/contracts" "$WORKSPACE/atlas"
```

If used, the helper produces seed `.md` tables (one row per grep hit). Enrich the rows semantically before relying on them. Empty rows or `unknown` cells are limitations, not evidence of safety.

Deliverables in `$WORKSPACE/atlas/`:

| File | Content |
|------|---------|
| `sinks.md` | Every fund-effect statement: ERC-20 transfer/transferFrom, mint/burn, native call, balance/allowance/debt storage write, delegatecall. Per row: `S-NN · file:line · containing fn · direction+asset+amount · local preconds · state-reads`. |
| `gates.md` | Every read of a state field used as a control-flow gate (`if/require/assert/modifier`). Per row: `G-NN · file:line · containing fn · field read · branch unlocked`. |
| `writes.md` | Every assignment to a field listed in `gates.md`. Per row: `W-NN · file:line · containing fn · from-values · to-value · local preconds · caller class · external reach`. |
| `paths.md` | For each sink, the union of `(entry-sequence, accumulated preconditions)` leaves reachable in the call graph. Built by walking writes.md back to entry points. |
| `intent.md` | The protocol team's intended set of `(actor, entry-sequence, preconditions) → sink` rows, extracted from whitepaper/docs/NatSpec. |
| `delta.md` | Set difference `paths.md \ intent.md`. Each row maps to a `C-NN` triage candidate — feed to Phases 4/5. |

**Closure gate:** record the discovery/coverage methods used, the surfaces they cover, exclusions, and residual blind spots in `coverage.md`. If the bundled atlas is used, every security-relevant row must be classified; if another method is used, preserve its equivalent evidence. Unresolved material surface = reported limitation.

---

## Phase 4: Optional Security-Model Scaffolds (C / D / E)

Open `references/methodology.md` for optional modeling prompts and apply only the
parts useful to the target. Write resulting evidence or links to
`$WORKSPACE/model.md`. Use whatever source, trace, property, formal, or generated
artifacts support the model; Atlas tables are one input when available.

### C. Invariants

Read whitepaper, docs, and source to enumerate system properties. Categorize as Solvency / Conservation / Monotonicity / Uniqueness / Authorization / Liveness. Aim for 5–20 invariants.

Write to `$WORKSPACE/model.md` under `## Invariants` — one row per invariant with: ID, statement, class, testability, expected runtime cost to violate.

### D. State Machines

For each lifecycle object (Position, Proposal, Order, Message, Vesting, CreditRecord, …):

- Enumerate states
- If a transition matrix is useful, build it from the selected evidence. Rows = from-state, columns = to-state, and cells identify the concrete write/transition plus its guard or proof condition. Atlas `W-NN` references are optional locators, not required identifiers.
- Read the matrix column-wise: for each to-state used as an auth gate by some sink, list every write that lands on it AND its guard. Mismatches between write-guards on the same to-state are the chain-bug signature.
- Mark terminal states
- Mark guards on each edge

Write to `$WORKSPACE/model.md` under `## State Machines`.

### E. Trust Boundaries

List every external dependency and admin role. For each, fill the 4-question matrix {Compromise / Liveness / Lie / Slow}. Note mitigations.

Write to `$WORKSPACE/model.md` under `## Trust Boundaries`.

---

## Phase 5: Register Candidates (Hypothesis Ladder Optional)

The **Hypothesis Ladder** is one optional discovery accelerator. It covers identity/authorization, state manipulation, numeric boundaries, token/external calls, composition/MEV, liveness/locks, cross-boundary logic, and economic design. Use it where it improves coverage; candidates from any other method enter the same triage contract.

- **EVM:** the 40-question ladder in `references/methodology.md`.
- **Solana:** the native ladder in `references/playbook-solana.md § 2` (signer/authority binding, account-owner/discriminator validation, PDA/bump, arbitrary CPI, oracle, atomic-tx composition — mapped to `[SOL-Gn]` gates and SlowMist items).
- **Sui:** the native ladder in `references/playbook-sui.md § 2` (capability/visibility, object-ownership mode & abilities, shift/precision math, Coin/Balance lifecycle, hot-potato/oracle, init/upgrade, PTB composition — mapped to `[SUI-Gn]` gates).

The categories map 1:1 across chains; the questions are native. Promote a lead to
`$WORKSPACE/triage/candidates/C-NN.md` when it supports a concrete, testable claim
and the candidate schema can be completed honestly. Preliminary exploration is
allowed before promotion; keep unresolved anomalies in `search.md` without
inventing an attacker path or impact to fill fields. Material unresolved security
questions also belong in `coverage.md`, even if no candidate can yet be formed.
For a candidate, record the exact `T-NN` artifact-ID set, target, actor and
preconditions, mechanism, claimed impact, falsification plan, dedup key,
provenance, and lifecycle status required by `references/triage.md`.

Per-candidate files are authoritative. After creating or changing one, rebuild
the deterministic multi-agent index instead of editing it directly:

```bash
bash "$SKILL_DIR/scripts/triage-index.sh" "$WORKSPACE"
```

---

## Phase 6: Challenge Candidates (A/B Lenses Optional)

Apply A/B lenses where useful to Atlas deltas, ladder leads, and candidates produced by any other method. Every candidate must make its claim reviewable by recording:

- an exact target locator appropriate to the claim, such as source line, instruction, bytecode range, transaction, object version, or model obligation;
- the discovery context or classification if useful, without forcing an A–J label;
- the actor, required capabilities, preconditions, and concrete derivation from entry to claimed effect; and
- the violated invariant or security property, whether recorded in Phase 4 or established directly in the evidence.

Use any discovery tooling appropriate to the target, including SAST, fuzzers, symbolic execution, formal verification, custom scripts, agents, or manual review. Raw tool output is a lead, not a finding; it must pass the same evidence and triage gates. Builds and dependency/compiler checks can also reveal candidates and produce verification artifacts.

```bash
# EVM — optional compiler-version advisory check
bash "$SKILL_DIR/scripts/check-compiler.sh" "$WORKSPACE/contracts" "$WORKSPACE"

# Solana — optional build/verification input
cd "$WORKSPACE/contracts/src" && anchor build   # native programs: cargo build-sbf

# Sui — optional compile/type/ability/borrow check
cd "$WORKSPACE/contracts/src" && sui move build 2>&1 | tee "$WORKSPACE/evidence/build.log"
```

Record tool versions, configuration, scope, and raw artifacts whenever a tool contributes to a candidate. Cross-check its assumptions and false-positive modes during triage.

---

## Phase 7: Explore Residual Surfaces (F/G/H/X/J Optional)

> F/G/H, X, and J are optional lenses, not required passes. X is useful for
> defects in the *seam* between otherwise-correct units; J is useful for
> intended flows whose economics let one actor extract value at another party's
> expense. Use either when it improves coverage, or use another method that
> addresses the relevant composition/economic surface and records its blind
> spots. See `references/methodology.md § X` and `§ J` for prompts.

### F. Negative Space

For every function moving funds or changing critical state, check the negative space:

- Missing access modifier?
- Missing return-value check?
- Missing input validation?
- Missing event emission?
- Missing pause modifier on a related function (partial-pause bug)?

Cover negative space by any combination of manual review, queries, SAST, specification checks, differential analysis, or agents. Document what was actually covered; no single technique proves absence by itself.

### G. Differential

If protocol is a fork: `git diff` source against upstream audited tag. Classify each change as parameter / new-feature / logic-modification. Logic modifications require full independent review regardless of upstream audit.

If multi-chain: diff deployed bytecode per chain; confirm trusted addresses (oracles, multisigs, integrated protocols) match per chain. Solana: check program ID changes. Sui: check package IDs.

### H. Failure-Mode Catalog

For every external dependency identified in Phase 4.E (trust boundaries), enumerate failure modes (stale / zero / revert / deviate / sequencer-down / replayed). Trace each to consequence. Identify mitigation.

### X. Cross-Boundary Logic

Pair up the seams and check that each pair *agrees* (not just that each side is individually correct). Three sub-lenses:

- **X.1 Cross-function** — two functions in one contract sharing an invariant/cache/struct that desync depending on call order or path (reward-debt desync, `accrue`-before-`borrow`, sibling-modifier asymmetry).
- **X.2 Cross-contract** — two protocol contracts tracking the same quantity, reading stale snapshots of each other, mismatched units at the boundary, or "only B calls me" assumptions that aren't enforced.
- **X.3 Cross-protocol / dependency-semantics** — *wrong assumptions* about how an external dependency works (manipulable `get_virtual_price`/`getRate`/`convertToAssets`, read-only reentrancy, token quirks of the integrated asset, fork/version/decimal mismatch, dependency upgradeability, callbacks as unprivileged entries).

Use any available state/write/call/dependency evidence for function and protocol seams. Atlas tables and `model.md` are optional inputs. Preserve the actual seam analysis in a reviewable artifact when it contributes to coverage or a claim.

### J. Business-Logic & Economic-Design

Interrogate intended behavior adversarially: is the *intended* flow itself exploitable by a rational actor? `intent.md`, specifications, source, transaction data, or an economic model may supply the intent evidence. Re-derive fee/reward/interest/price math; check free-rider/JIT, time-boundary incentives, liquidation/penalty economics, fairness across user classes, griefing economics, and retroactive/self-dealing parameter power. These findings often have *no code defect* — the code is correct and the design is the bug.

Route F/G/H/X/J leads through the same lead-to-candidate boundary in Phase 5;
do not promote them directly to findings. The pattern library may accelerate
verification but is never required.

---

## Phase 8: Evidence and Triage (Critical Gate)

During search, perform the producer evidence work below through `REPRODUCED`.
Keep independent validation pending until report preparation (Phase 10); its
absence does not block further discovery, falsification, or coverage work.
The acceptance gates below define what may later enter `findings.md`, not a
requirement to launch a validator after each producer result.

For every candidate intended for acceptance, produce independently reviewable evidence against the real scoped target. Any sound method is allowed: executable PoC, test, fuzz counterexample, invariant violation, symbolic trace, formal proof, transaction/trace analysis, faithful simulation/replay, differential proof, source-level proof, or a combination. Pure style or documentation notes belong in observations, not security findings.

Keep three fields separate: **code-impact severity**, **deployment exploitability**, and **evidence confidence**. Blocked or incomplete verification is `INCONCLUSIVE`, not evidence that the candidate is theoretical, refuted, or lower severity.

### Triage Acceptance Gates

Apply `references/triage.md` before anything enters `findings.md`:

1. **Scope fidelity:** bind the evidence to the `target-lock.md` target identity and exact relevant `T-NN` artifact set, and therefore to the scoped revision, production/release profile, deployment/configuration, and relevant state. The lock identity must match `scope.md`; state every deviation. Recording the lock digest is optional internally and verified when present.
2. **Reachability:** demonstrate or rigorously derive the claimed entry, preconditions, transitions, and effect. Constructed state is valid only for the claim it actually supports.
3. **Impact and falsification:** define a measurable success criterion and try to falsify the mechanism. Use a negative control when meaningful; otherwise document the proof obligation, counterexample search, or reason a control is inapplicable.
4. **Provenance and integrity:** record producer context, evidence method, exact command or review procedure, artifact paths, target/state anchors, dependencies, and result. Every referenced artifact must be retained and openable in the workspace; its digest is optional internally. Use a native immutable anchor (for example positive block/slot, native transaction digest, object-ID@version set, content-addressed snapshot, or versioned revision). Repeatability is evidence-specific; there is no arbitrary rerun quota.
5. **Deduplication:** search `triage/known-issues.md`, prior candidates/findings, upstream advisories, and known fixes using the candidate dedup key.
6. **Cost versus impact:** quantify attacker capital, privilege, ordering, timing, fees, and repetitions against user/protocol/network impact, and state explicitly whether the claim reaches loss of funds or assets.
7. **Independent validation:** a validator other than the producer inspects the primary artifacts and assumptions and independently challenges reachability, impact, target fidelity, and falsification. The validator may rerun or re-review the documented method, use a different sound method, or do both, and records the selected method and result in `triage/validation/C-NN.md`.

Gates 1–7 admit the candidate to `findings.md`; no human decision is required to record a proven finding, and none may waive these gates. Before any report is issued, a human auditor records the acceptance, severity, and disclosure decision for each finding (Phase 10) — that is the report gate.

For multi-step candidates, preserve the full sequence and state dependencies. A stateful harness, model checker, symbolic trace, formal transition proof, historical trace, or another faithful technique may establish it. An LLM-proposed sequence by itself is only a lead.

Run the checker at the gate you are actually at:

The final-mode checks below are closure/report checks. During an ongoing search,
pending `REPRODUCED` packages are expected; do not use a final checker failure on
pending review as a reason to stop other audit work or trigger early validation.

```bash
# Findings gate — evidence, validation, closure. Digests optional.
bash "$SKILL_DIR/scripts/triage-check.sh" "$WORKSPACE"

# Report gate — additionally requires human sign-off on every recorded finding.
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$WORKSPACE"

# External/client delivery — also require every integrity digest.
bash "$SKILL_DIR/scripts/triage-check.sh" --report --strict-hashes "$WORKSPACE"
```

Passing the checker catches missing contracts and obvious separation errors; it does not replace independent judgment.

For a `Fixed - Verified` finding, keep the validation method unrestricted
but store its provenance in the structured `findings.md` fields emitted by
`init-workspace.sh`. The remediation-baseline manifest and retest evidence must be
workspace-relative retained files; their `sha256=` values are optional internally
and required under `--strict-hashes`, and any recorded value must match the file.
The checker validates that binding, the real calendar date, the immutable revision
descriptor, and an explicit positive mechanism/property-closure result; the human
reviewer still decides whether the chosen method is target-faithful and sufficient.

### Claim-to-Evidence Fit

Evidence grade follows the claim supported, not the tool used:

| Grade | Required support | Example methods (non-exhaustive) |
|------|------------------|----------------------------------|
| **CONFIRMED-DEPLOYED** | Evidence binds the mechanism and impact to the actual deployed code, configuration, dependencies, and relevant pinned state. It closes material reachability assumptions for the claim. | Historical exploit transaction and trace; pinned-state replay; faithful state simulation; state proof plus source/bytecode derivation; formal proof over a deployment-faithful model. |
| **CONFIRMED-RECONSTRUCTION** | Evidence succeeds against a documented reconstruction, with deviations and unmodeled dependencies explicit. | Localnet reconstruction; reconstructed ledger; simulation with imported state. |
| **CONFIRMED-LOGIC** | Evidence establishes the code-level mechanism and impact, but does not establish current deployment exposure. | Unit/property test; fuzz counterexample; symbolic trace; formal/source proof; local deployment. |
| **INCONCLUSIVE / REFUTED** | Respectively: material proof obligations remain open; or faithful evidence disproves a necessary precondition/effect. | Any method, judged by fidelity and completeness rather than label. |

**Hard rule:** a claim that the current deployment is confirmed exploitable,
conditionally exposed, plausibly exposed, or not exposed at a pinned state must
be supported by `CONFIRMED-DEPLOYED` target evidence and an immutable state
anchor. `Conditionally exposed` means deployment applicability was verified and
the enumerated conditions determine exposure. `Plausibly exposed` expresses
remaining uncertainty inside a deployed-target assessment; it cannot be inferred
from logic/reconstruction evidence alone. A logic proof or reconstruction can
establish code impact without establishing current exposure. This is a claim
boundary, not a required PoC format.

If deployed-state verification is blocked by missing liquidity, a paused pool, unavailable historical state, incomplete account capture, or tooling failure, record `INCONCLUSIVE` with the exact blocker. Do **not** downgrade severity merely because one method failed. Try other sound methods; downgrade only when evidence disproves a required precondition or bounds the impact.

### Optional EVM Foundry Example

Use `templates/simulation/` as starting templates. Adapt with the PoC Pattern Library (`methodology.md`).

- `FlashLoanAttack.t.sol`
- `OracleManipulation.t.sol`
- `ReentrancyAttack.t.sol`
- `ShareInflation.t.sol`
- `GovernanceAttack.t.sol`
- `BaseTest.sol` (base class)

Example procedure (adapt or replace):

1. **Pick the fork block deliberately.** If using a fork, pin a numeric block and explain whether it represents a normal supported configuration, a transient window, or historical state.
2. Copy the closest template into `$WORKSPACE/poc/C-{NN}_Fork.t.sol` while it is a candidate. Rename/link it to `F-{NN}` once the candidate is recorded as a finding.
3. Replace `TARGET`, `BORROW_TOKEN`, etc. with the audited deployment's actual addresses.
4. Implement the candidate mechanism from the real attacker entry. Use `vm.prank(makeAddr("attacker"))`; the attacker should be a *fresh* address with no hidden pre-funding.
5. Assert fund-effect (PoC Pattern Library assertion discipline):
   - `assertGt(attackerBalAfter, attackerBalBefore + gasCost)` — net profit without subtraction underflow
   - `assertLt(targetBalAfter, targetBalBefore)` — target lost
   - For DoS: `vm.expectRevert(...)` on the legitimate path

Run:

```bash
cd "$WORKSPACE/poc"
forge init --no-git --force . 2>/dev/null  # idempotent
: "${FORGE_STD_REV:?Set FORGE_STD_REV to a pinned forge-std tag or commit}"
: "${FORK_BLOCK:?Set FORK_BLOCK to the numeric state anchor selected for this reproducer}"
forge install "foundry-rs/forge-std@$FORGE_STD_REV" --no-commit  # if not already locked
forge test \
  --fork-url "$RPC_URL" --fork-block-number "$FORK_BLOCK" \
  --match-path "C-${NN}_Fork.t.sol" -vvvv 2>&1 | tee "C-${NN}.log"
```

Save the trace and hash it as one evidence artifact. A trace proves only the code and state actually exercised; list omitted dependencies and assumptions.

### Optional Local-Deploy Example

Local deployment can efficiently establish code-level behavior. It may support any severity when the code impact warrants it, but it does not by itself establish that a current deployment is exposed.

For implementation contracts that call `_disableInitializers()` in the constructor (OZ Upgradeable pattern), deploy behind an `ERC1967Proxy` rather than calling `initialize()` directly on the implementation.

**Evidence verdict per candidate:**

- **CONFIRMED-DEPLOYED** — the evidence closes the claimed path against deployed code/configuration/state; no particular verification method is required.
- **CONFIRMED-RECONSTRUCTION** — the exploit succeeds against a documented state reconstruction, but exact deployed-state fidelity is unavailable.
- **CONFIRMED-LOGIC** — the evidence closes the code-level mechanism; deployed configuration/state remains unverified or no deployment exists.
- **INCONCLUSIVE** — the hypothesis remains plausible, but evidence is incomplete, non-reviewable, or lacks required target/state fidelity. Preserve it as an open limitation; do not treat it as a pass.
- **REFUTED** — faithful evidence demonstrates that a necessary precondition cannot be reached or the claimed effect cannot occur. A tool error, missing fixture, or failed attempt is not refutation. Refuted candidates remain in the triage registry and never enter `findings.md`.

### Optional Solana Techniques

Available examples include the templates in `templates/solana/` and the pattern
library in `references/playbook-solana.md § 3`. They are optional and do not
constrain mode selection:

- **LiteSVM** (`templates/solana/litesvm_harness.rs` + `exploit_*.rs`) — a fast option for logic PoCs and pre-deployment audits; ordinarily supports **CONFIRMED-LOGIC** unless stronger target/state correspondence is independently established.
- **coherent Solana snapshot replay** — one way to support a deployed-state claim. Capture the upgradeable program and every relevant account/program/sysvar dependency at one context slot, and document feature/clock treatment. Sequential live clones are exploratory unless coherence is otherwise established.
- **Mollusk** — instruction-level fuzzing/CU profiling without a validator.

### Optional Sui Techniques

Available examples include the templates in `templates/sui/` and the pattern
library in `references/playbook-sui.md § 3`. They are optional and do not
constrain mode selection:

- **`sui move test` + `test_scenario`** (`templates/sui/exploit_*.move`) — a fast option for logic PoCs; ordinarily supports **CONFIRMED-LOGIC** unless stronger target/state correspondence is independently established.
- **localnet reconstruction** (`templates/sui/localnet_replay.sh`) — reconstruct deployed objects and drive the exploit as a PTB → **CONFIRMED-RECONSTRUCTION** at most. Sui has no native account-clone, so do not label reconstruction as deployed-state confirmation.

---

## Phase 9: Severity Calibration (Post-Pass I)

During search, use these axes for provisional candidate severity/materiality.
Finalize finding severity after independent review during report preparation.

For every independently validated candidate, calibrate severity along the 5 axes from `methodology.md` § I:

- Blast radius
- Reversibility
- Prerequisites
- Mempool visibility
- Detection latency

**Apply the asset-loss gate first.** Critical and High are reserved for findings
that reach loss of funds or assets — extraction, unbacked mint, insolvency, or
permanent lock of user/protocol assets. Answer that question explicitly in the
finding's cost-versus-impact field:

- Asset loss reached → choose Critical or High by magnitude, reversibility, and prerequisites.
- No asset-loss path → cap at Medium, however novel the mechanism. Authorization or integrity violations with no value at stake, temporary liveness loss, and griefing without extraction belong here.
- Privileged-role or governance abuse counts as asset loss only when the abused authority actually reaches funds (upgrade → drain, mint, parameter → extraction). Trace that path; do not assume it.

Assign Critical / High / Medium / Low / Informational using the engagement's or
bug-bounty program's taxonomy. When none is supplied, use the tiers in
`methodology.md § I` and state the policy; deployment/sign-off actions belong to the
owner's policy, not the evidence grade. Validated candidates are recorded in
`findings.md` on their evidence; a human auditor signs each one off in Phase 10
before a report is issued. Rejected, duplicate, out-of-scope, and inconclusive
candidates stay in `triage/`; material inconclusive candidates are report
limitations.

Do not make the engagement's label vocabulary a checker gate. Candidate records
pair the chosen severity label with a separate `MATERIAL` or `NON-MATERIAL`
closure class so an arbitrary taxonomy can coexist with a mechanically honest
clean-verdict gate.

---

## Phase 10: Human Sign-off + Internal Reference Report

This is the default trigger for independent validation. Review the retained
`REPRODUCED` packages with a separate reviewer using Phase 8 and `triage.md`;
record passing findings, and return disputed claims to evidence work or explicit
limitations. An additional agent can be the reviewer under the independent
validation protocol; a human need not perform routine reproduction. Present the
human with the final findings and only the unresolved anomalies meeting the
human-review criteria in `goal-directed-search.md`. Do not fabricate validation
if a reviewer is unavailable. Ordinary
search may continue; issuance of the affected report waits for this review.

Reporting is the human gate. Before building any report, a human auditor records
the acceptance decision, final severity, and disclosure decision for every recorded
finding — `Human decision` in `findings.md`, `Human decision / acceptor / date` in
the validation record, and candidate status `HUMAN-ACCEPTED` — then verifies it:

```bash
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$WORKSPACE"
```

A finding that is evidence-closed but not yet signed off stays in `findings.md` and
blocks only the report, not the audit.

Use `templates/audit-report.md` by default. Build one internal reference report
from `scope.md`, `target-lock.md`, `findings.md`, `coverage.md`, the security model
actually used, and retained evidence. Include:

1. **Executive Summary** - bounded verdict, signed-off findings, evidence status, and material limitations
2. **Scope and Target Binding** - target identity, artifact IDs, revisions/deployments, build profile, inclusions, exclusions, and the lock digest when the engagement records one
3. **Triage Summary** - candidate dispositions, independent validation, human sign-off, and unresolved material candidates
4. **Findings and Evidence** - signed-off findings only, with candidate/dedup provenance, evidence basis, target/state anchor, severity (with the asset-loss answer behind any Critical/High), remediation, and residual risk
5. **Coverage and Closure** - objective artifact reconciliation, covered surfaces, blind spots, assumptions, and blocked checks
6. **Methods and References** - methods actually used, material tooling/configuration, and relevant disclosure notes

Save the canonical editable internal report to
`audit-workspace/{protocol}/reports/{protocol}-{chain}-{YYYY-MM-DD}.md`. Internal
candidate IDs, target IDs, triage metrics, and workspace-relative evidence paths
may be retained because this is an audit-team reference artifact. It is not a
client/public report and must not be distributed externally without an explicit
conversion and disclosure review.

### Optional External Report

Generate `templates/external-audit-report.md` only when the user explicitly asks
for an external, client-facing, public, or professional delivery report. Build it
from the retained workspace and signed-off findings; do not create it routinely.
For an external delivery, integrity binding does matter — gate it with
`bash "$SKILL_DIR/scripts/triage-check.sh" --report --strict-hashes "$WORKSPACE"`
and record the digests that run requires.
Save its editable source as
`audit-workspace/{protocol}/reports/{protocol}-{chain}-{YYYY-MM-DD}-external.md`.
Create a top-level `audits/` file, client delivery, or public copy only when
requested; never rely on an export as the only retained artifact.

For the external report, keep original severity, deployment exposure,
verification basis, and remediation status separate. Do not expose internal
candidates, target IDs, triage metrics, raw evidence paths, local paths, or
agent/runtime provenance. Redact exploit-enabling detail according to the
intended audience and disclosure state, and run the template's release checklist.
Public release always requires explicit authorization. Before changing an
external report version that was approved, delivered, or published, preserve that
exact source under `reports/` with its report version and digest.

Project the internal deployment field without increasing certainty:

- `confirmed exploitable` → `Confirmed Exposed`
- `conditionally exposed` → `Conditionally Exposed`
- `plausibly exposed` → `Unknown / Not Assessed`, with the unresolved exposure
  question stated; never automatically upgrade it to `Conditionally Exposed`
- `not exposed at pinned state` → `Not Exposed in Reviewed Deployment`
- `not deployed` → `Not Deployed`
- `unknown` → `Unknown / Not Assessed`

The canonical internal source of truth remains the workspace artifacts; the
default internal report is a navigable summary, not a replacement evidence store.

---

## Coordinated Disclosure

For any material or exploit-sensitive finding (including Critical/High under a
common taxonomy), or any verification artifact that would materially enable
exploitation, follow responsible disclosure:

1. Do NOT publish exploit-enabling details or artifacts publicly until the protocol has had reasonable time to remediate (default 90 days; the protocol's bug-bounty or disclosure policy takes precedence)
2. Encrypt sensitive findings if sharing over insecure channels (use protocol's PGP key from `security.txt` or Immunefi)
3. Redact exploit-enabling details from the public report; retain full verification artifacts only in the appropriate restricted workspace path (`poc/`, `evidence/`, or another workspace-controlled location)
4. Coordinate disclosure date with protocol team

---

## Scope Boundaries

- Keep off-chain components (frontend, key management, signer operations) outside the source-audit verdict unless the user explicitly expands scope.
- Treat pure style, gas, and NatSpec review as ancillary; this workflow is for fund safety and protocol correctness.
- Use differential analysis to focus a re-audit, but trace every changed component's transitive callers, storage, invariants, and sinks. A diff-only review is not sufficient when changes alter shared state or external assumptions.
- Do not claim production Aptos coverage from the Sui playbook. Aptos needs
  chain-native semantic, source/deployment-identity, and evidence-fidelity
  support before this skill can claim production coverage; no particular Atlas,
  model, PoC, or harness format is required.

---

## Workflow Summary (Single-Line)

```
[optional helper preflight] → pin scope + target lock → blackboard goal/frontier loop (any sound method) → register candidates → bind target/evidence → independent triage → record finding → calibrate (asset-loss gate) → closure gate → human sign-off → report
```

Every recorded finding rests on independently reviewable claim-bound evidence and independent validation; every reported finding additionally carries a human decision. Material `INCONCLUSIVE` candidates and incomplete coverage remain explicit limitations and prevent a `NO-MATERIAL-FINDINGS` verdict.

---

## Skill Directory Layout

```
contract-security-audit/
├── SKILL.md                              # This file (entry point)
├── .env.example                          # Environment variables template
├── config/
│   ├── chains.json                       # Chain RPC + explorer configs
│   └── compiler-cves.json                # Compiler advisory database
├── references/
│   ├── goal-directed-search.md            # Blackboard + goal/frontier search and semantic meeting
│   ├── methodology.md                    # Chain-agnostic spine (O/P, A–J lenses, severity) + EVM ladder & PoC library
│   ├── triage.md                         # Candidate contract, false-positive gates, independent validation, report sign-off
│   ├── playbook-solana.md                # Solana semantics + optional prompts/verification examples
│   ├── playbook-sui.md                   # Sui/Move semantics + optional prompts/verification examples
│   ├── metrics-evm.md                    # EVM catalog — dated historical pointers; primary-source verification required
│   ├── metrics-solana.md                 # Solana catalog — SlowMist-derived (gates, vuln→fix, incidents)
│   └── metrics-sui.md                    # Sui/Move catalog — SlowMist-derived (gates, vuln→fix, incidents)
├── templates/
│   ├── search.md                          # Lightweight goal/frontier working record
│   ├── audit-report.md                   # Default internal reference report
│   ├── external-audit-report.md          # Optional explicit-request professional report
│   ├── simulation/                       # EVM Foundry fork PoCs
│   │   ├── BaseTest.sol                  # Foundry fork base
│   │   ├── FlashLoanAttack.t.sol
│   │   ├── OracleManipulation.t.sol
│   │   ├── ReentrancyAttack.t.sol
│   │   ├── ShareInflation.t.sol
│   │   └── GovernanceAttack.t.sol
│   ├── solana/                           # Solana PoCs
│   │   ├── README.md                     # Harness selection + verdict guide
│   │   ├── litesvm_harness.rs            # LiteSVM base (token helpers, attacker setup)
│   │   ├── exploit_signer_and_substitution.rs
│   │   └── fork_replay.sh                # live clone scaffold (exploratory until coherent snapshot adaptation)
│   └── sui/                              # Sui/Move PoCs
│       ├── README.md                     # Harness selection + verdict guide
│       ├── exploit_shared_object.move    # unauthorized shared-object effect example (test_scenario)
│       ├── exploit_shift_truncation.move # Cetus-class shift/checked-math truncation
│       └── localnet_replay.sh            # localnet object reconstruction (reconstruction evidence)
└── scripts/
    ├── compat-check.sh                   # Agent/runtime + OS/Bash compatibility
    ├── test-skill.sh                     # macOS/Linux portable smoke suite
    ├── retention.sh                      # Non-destructive helper-output snapshots
    ├── init-workspace.sh                 # Phase 0 bootstrap
    ├── preflight.sh                      # Tool / env / chain detection
    ├── fetch-source.sh                   # Phase 1 source acquisition (EVM)
    ├── collect-onchain-data.sh           # Phase 1 on-chain context (EVM)
    ├── check-compiler.sh                 # Compiler vs CVE check (EVM)
    ├── atlas-inventory.sh                # Pass P bootstrap (EVM / Solana / Move greps)
    ├── triage-index.sh                   # Deterministic candidate index generator/checker
    ├── triage-check.sh                   # Candidate/finding separation + triage artifact validation (--report / --strict-hashes)
    └── load-env.sh                       # Env var loader (sourced)
```
