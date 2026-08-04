# Skills

Two self-contained agent skills for on-chain security work — one **proactive** (audit a deployment before it breaks), one **reactive** (reconstruct an exploit after it did).

Each skill is a directory of Markdown instructions plus its own scripts, chain config, PoC harnesses, and report templates. Drop one into your agent's skills directory and it works — no shared runtime, no cross-skill dependencies.

| Skill | Question it answers | Chains |
| ----- | ------------------- | ------ |
| [`contract-security-audit`](audit/contract-security-audit/SKILL.md) | "Can this be exploited?" | EVM, Solana, Sui |
| [`security-incident-analysis`](analysis/security-incident-analysis/SKILL.md) | "It *was* exploited — how, how much, where did the funds go, is it still bleeding?" | EVM (Ethereum + L2s) |

---

## contract-security-audit

Methodology-driven source audit whose defining property is that **discovery is unrestricted but claims are gated**. The skill does not prescribe how you find a bug — regex, AST queries, SAST, fuzzing, formal methods, or reading the code. It prescribes what may be written down as a finding: every candidate carries reachability, consequence, and falsification evidence and is independently validated before it reaches `findings.md`. Proof is the admission gate; a human auditor signs each finding off before any report is issued.

**Architecture** (four layers, in `references/`):

- **Spine** — `methodology.md`: chain-agnostic truth gates, optional reachability-atlas scaffold, A–J lenses, severity calibration. EVM/Solidity as the lingua franca.
- **Triage** — `triage.md`: the acceptance layer. Candidate contract, claim/evidence gates, independent validation, dedup, and the report-stage human sign-off. The source of truth for what enters `findings.md` and what may be reported.
- **Playbooks** — `playbook-solana.md`, `playbook-sui.md`: chain-native attack surfaces where the primitives diverge too far to translate in-head. EVM's playbook lives inline in the spine.
- **Metrics** — `metrics-{evm,solana,sui}.md`: known-pattern catalogs (triggers, vulnerable→fix pairs, historical pointers). A catalog match is a lead, never a validated finding.

**Flow** — 11 phases from setup through a signed-off internal report. Setup → source fetch + **target lock** (every relied-on artifact gets a `T-NN` ID and path; digests are optional for internal review, required for external delivery) → semantic model → optional reachability/coverage model → candidate registration → adversarial challenge → residual-surface sweep → verify + independent triage → severity calibration (Critical/High reserved for loss of funds or assets) → human sign-off → report. Closure is tracked continuously in `coverage.md`, where **an unresolved row is a stated limitation, never a silent pass**.

**Output** — `audit-workspace/{protocol}/reports/{protocol}-{chain}-{date}.md`, plus a retained evidence trail. The workspace is the durable engagement record, not scratch space: nothing is auto-pruned just because a candidate was rejected or the report is written.

**Bundled** — `scripts/` (preflight, compat check, source fetch, on-chain collection, compiler-CVE check, atlas inventory, triage index/check, retention), `templates/simulation/` (Foundry fork PoCs: flash loan, oracle manipulation, reentrancy, share inflation, governance), `templates/solana/` (LiteSVM harness + fork replay), `templates/sui/` (Move exploits + localnet replay), `config/` (chain registry, compiler CVEs).

> Aptos appears only as comparative notes. A Sui playbook is not an Aptos audit — the skill halts rather than pretend otherwise.

## security-incident-analysis

Forensic post-mortem of a live or past incident, built on four axioms:

1. **On-chain state is the only witness.** Every claim pins to an explicit block number. Twitter figures, explorer labels, and the team's statement are hypotheses until a `balanceOf` delta, log sum, or fork replay confirms them. Never `latest` in evidence — it drifts and makes the report irreproducible.
2. **A drain is a hypothesis, not an observation.** A zero balance is equally consistent with theft, a migration, and an admin sweep. Rule out the boring cause — key compromise, governance action, benign migration — *before* theorizing about a clever bug. Identical fund-flow shape, completely different remediation.
3. **Root cause is replayed, not asserted.** A causal claim not reproduced on a fork *and* falsified by toggling the broken guard is a hypothesis.
4. **Every number is derived twice.** Loss is computed by event-log summation **and** balance-snapshot delta, and the two must reconcile. A wrong loss number is the most common way a public post-mortem gets torn apart.

**Flow** — 10 phases: intake & evidence freeze → confirm & scope the drain (baseline taken *before* the first attacker-touching tx) → actor map → reconstruct the trace including all setup/pre txs → root cause against the bundled taxonomy, read at exploit-time code → quantify loss twice, flash-loan principal excluded → fork replay + counterfactual → hop-by-hop fund tracing to mixer/bridge/CEX terminals → containment and residual risk (**a kill switch is not a fix**) → report.

Phases are artifacts, not a pipeline: a failed replay sends you back to root cause; a setup tx found while tracing funds becomes an actor-map entry.

**Output** — `reports/{incident}-{chain}-{date}.md`, separating CONFIRMED (on-chain / replay) from INFERRED evidence, with the residual-risk verdict up top.

**Bundled** — `scripts/` (preflight with archive-RPC probing, intake, drain-block finder, loss reconciliation), `references/` (incident methodology, vulnerability taxonomy), `templates/poc/ForkReplay.t.sol`, `templates/incident-report.md`, `config/chains.json`.

---

## Install

Copy the skill directory (not the category directory) into your agent's skills path:

```bash
git clone git@github.com:mart1n2/skills.git
cd skills

# Claude
cp -R audit/contract-security-audit      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/"
cp -R analysis/security-incident-analysis "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/"

# Codex
cp -R audit/contract-security-audit "${CODEX_HOME:-$HOME/.codex}/skills/"

# Hermes
cp -R audit/contract-security-audit "${HERMES_HOME:-$HOME/.hermes}/skills/"
```

`contract-security-audit` resolves its own install directory at runtime (`CONTRACT_AUDIT_SKILL_DIR` → Hermes → Codex → Claude), so each runtime uses its own private `.env` rather than silently borrowing another's. Override explicitly if you keep the skill somewhere else:

```bash
export CONTRACT_AUDIT_SKILL_DIR=/path/to/contract-security-audit
```

`security-incident-analysis` takes an explicit absolute `SKILL_DIR` in its Phase 0 block.

## Prerequisites

| Tool | Needed for |
| ---- | ---------- |
| `cast` ([Foundry](https://getfoundry.sh)) | all on-chain queries — **required** by the incident skill |
| `forge` | fork replay / PoC execution — required for incident Phase 6, optional for the audit skill |
| `jq` | chain resolution and evidence parsing (audit skill falls back to `python3`) |
| `curl` | explorer and RPC calls |

Both skills run their preflight first and report a mode of `full`, `degraded`, or `blocked` rather than failing halfway through.

## Configure

Each skill ships an `.env.example`. Copy it *inside the installed skill directory* and fill it in:

```bash
cp audit/contract-security-audit/.env.example      audit/contract-security-audit/.env
cp analysis/security-incident-analysis/.env.example analysis/security-incident-analysis/.env
```

- **Explorer** — one [Etherscan V2](https://etherscan.io/myapikey) key covers every supported EVM chain.
- **RPC** — the audit skill ships working public defaults. **The incident skill needs an archive-capable RPC** (Alchemy / Infura / QuickNode, or the keyless `https://eth.drpc.org` fallback): historical `--block` queries and fork replay against a pruned node return silently wrong state, which is worse than an error. Its preflight probes for archive capability and blocks if it can't find one.

`.env` is gitignored. So are the generated `audit-workspace/`, `incident-workspace/`, and `reports/` directories.

## Use

Ask your agent for the work; skill discovery handles the rest.

```
Audit the Foo vault at 0xabc… on Base.
Analyze the exploit in tx 0xdef… on Arbitrum.
```

## Test

Each skill carries a portable smoke suite, run in CI on macOS and Ubuntu — including invocation from zsh on macOS, and mocked Chainlist / official-RPC selection plus fail-closed evidence checks for the incident skill:

```bash
bash audit/contract-security-audit/scripts/test-skill.sh
bash analysis/security-incident-analysis/scripts/test-skill.sh
```

## Portability

Supported: **macOS** with zsh as the interactive shell and Apple Bash 3.2+, and **Linux** with Bash 3.2+. Run bundled scripts explicitly with `bash` rather than relying on the interactive shell. Contributions must avoid Bash 4-only features (`mapfile`, associative arrays, `${var,,}`, namerefs) and GNU-only tool flags without a Darwin fallback.

## Scope

These skills are for auditing code you are authorized to audit and for analyzing incidents that have already happened. The PoC harnesses exist to *prove* a root cause on a local fork so it can be fixed and reported — that is the only reason they are here.

Findings are agent-produced and evidence-gated, not certified. Evidence is what makes a finding true; human sign-off is the last gate before anything is reported — nothing reaches a report because a model asserted it.
