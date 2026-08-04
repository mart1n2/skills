#!/usr/bin/env bash
# init-workspace.sh
#
# Initialize a contract-security-audit workspace and bootstrap the
# methodology + chain-specific metrics references.
#
# Usage:
#   init-workspace.sh <protocol> <chain>
# Example:
#   init-workspace.sh morpho-blue ethereum
#
# Output: $WORKSPACE/ with subdirs and README pointing at the references.

set -euo pipefail

PROTOCOL="${1:?Usage: init-workspace.sh <protocol> <chain>}"
CHAIN="${2:?Missing chain (ethereum|arbitrum|optimism|base|polygon|bsc|solana|sui|...)}"

if [[ ! "$PROTOCOL" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: protocol must be lowercase kebab-case (letters, digits, hyphens): $PROTOCOL" >&2
    exit 2
fi

CHAIN="$(printf '%s' "$CHAIN" | tr '[:upper:]' '[:lower:]')"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="audit-workspace/${PROTOCOL}"

# Resolve aliases from the single chain-config source of truth. Both jq and
# python3 are supported so this stays portable across macOS and Linux.
if command -v jq >/dev/null 2>&1; then
    RESOLVED_CHAIN="$(jq -r --arg requested "$CHAIN" '
        to_entries
        | map(select(.key | startswith("_") | not))
        | map(select(
            (.key == $requested)
            or (((.value.aliases // []) | index($requested)) != null)
        ))
        | if length == 1 then .[0].key else "" end
    ' "$SKILL_DIR/config/chains.json")"
elif command -v python3 >/dev/null 2>&1; then
    RESOLVED_CHAIN="$(python3 - "$SKILL_DIR/config/chains.json" "$CHAIN" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    config = json.load(handle)
requested = sys.argv[2]
matches = [
    name for name, value in config.items()
    if not name.startswith("_")
    and (name == requested or requested in value.get("aliases", []))
]
print(matches[0] if len(matches) == 1 else "")
PY
)"
else
    echo "ERROR: jq or python3 is required to resolve chain configuration." >&2
    exit 2
fi

if [ -z "$RESOLVED_CHAIN" ]; then
    echo "ERROR: unsupported or ambiguous chain '$CHAIN'; add one canonical config entry before auditing." >&2
    exit 2
fi
CHAIN="$RESOLVED_CHAIN"

# Determine native audit resources. Fail closed rather than silently applying the
# wrong chain model: a Sui object-model playbook is not an Aptos playbook.
case "$CHAIN" in
    solana)           METRICS="metrics-solana.md"; PLAYBOOK="playbook-solana.md" ;;
    sui)              METRICS="metrics-sui.md"; PLAYBOOK="playbook-sui.md" ;;
    aptos)            echo "ERROR: Aptos is not production-supported: no native Aptos playbook or PoC harness." >&2
                      exit 2 ;;
    ethereum|arbitrum|optimism|base|polygon|bsc|avalanche|gnosis|linea|scroll|blast|mantle|mode|zksync|celo|sonic|hyperevm)
                      METRICS="metrics-evm.md"; PLAYBOOK="inline in methodology.md" ;;
    *)                echo "ERROR: unsupported chain '$CHAIN'; add a native playbook/config before auditing." >&2
                      exit 2 ;;
esac

# An existing workspace is bound to one canonical chain. Refuse to rewrite only
# the README while leaving chain-specific scope and artifacts behind.
if [ -f "$WORKSPACE/README.md" ]; then
    EXISTING_README_CHAIN="$(sed -n 's/^# Audit Workspace: .* (\([^)]*\))$/\1/p' "$WORKSPACE/README.md" | head -1)"
    if [ -z "$EXISTING_README_CHAIN" ]; then
        echo "ERROR: $WORKSPACE/README.md has no parseable chain binding; refusing partial reinitialization." >&2
        exit 2
    fi
    if [ "$EXISTING_README_CHAIN" != "$CHAIN" ]; then
        echo "ERROR: $WORKSPACE/README.md targets '$EXISTING_README_CHAIN'; refusing to reinitialize it as '$CHAIN'." >&2
        exit 2
    fi
fi
if [ -f "$WORKSPACE/scope.md" ]; then
    EXISTING_CHAIN_COUNT="$(awk -F '|' '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        trim($2) == "Chain" { count++ }
        END { print count + 0 }
    ' "$WORKSPACE/scope.md")"
    EXISTING_CHAIN="$(awk -F '|' '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        trim($2) == "Chain" { print trim($3); exit }
    ' "$WORKSPACE/scope.md")"
    if [ "$EXISTING_CHAIN_COUNT" -ne 1 ] || [ -z "$EXISTING_CHAIN" ]; then
        echo "ERROR: $WORKSPACE/scope.md must contain exactly one parseable Chain binding; refusing partial reinitialization." >&2
        exit 2
    fi
    if [ "$EXISTING_CHAIN" != "$CHAIN" ]; then
        echo "ERROR: $WORKSPACE already targets '$EXISTING_CHAIN'; refusing to reinitialize it as '$CHAIN'." >&2
        exit 2
    fi
fi

# Mutate the filesystem only after protocol, alias, support, and split-brain
# checks have passed. Unsupported input must not leave a partial workspace.
mkdir -p "$WORKSPACE"/{contracts,poc,evidence,tmp,reports,atlas,triage}
mkdir -p "$WORKSPACE/triage"/{candidates,reproducers,validation}
mkdir -p audits

# Write a workspace README that points at the right references
[ -f "$WORKSPACE/README.md" ] || cat > "$WORKSPACE/README.md" <<EOF
# Audit Workspace: $PROTOCOL ($CHAIN)

Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## References (read these first)
- Methodology (chain-agnostic): $SKILL_DIR/references/methodology.md
- Candidate triage and validation: $SKILL_DIR/references/triage.md
- Native playbook: $PLAYBOOK
- Chain metrics: $SKILL_DIR/references/$METRICS

## Layout
- contracts/       — fetched source
- evidence/        — proofs, traces, analyses, tool output, on-chain data, and other verification artifacts
- poc/             — optional executable PoCs/tests and logs
- tmp/             — retained audit-relevant raw/intermediate data; never auto-clean solely because it is temporary
- reports/         — default internal reference report plus explicitly requested external reports/revisions
- target-lock.md   — target identity + T-NN artifact manifest used by evidence records (digests optional internally)
- scope.md         — Phase 0: pinned scope, revision, deployment, build profile, exclusions
- orientation.md   — optional target-model scaffold or links to equivalent semantic evidence
- atlas/           — optional reachability-scaffold output
- model.md         — optional invariant/state/trust scaffold or links to equivalent evidence
- triage/          — candidate registry, known-issue ledger, verification manifests, independent validation
- findings.md      — evidence-closed, independently validated findings; human sign-off is added before reporting
- coverage.md      — closure ledger; every open row is a reported limitation

Default internal reference report → reports/$PROTOCOL-$CHAIN-{REPORT-DATE}.md
Optional external report source → reports/$PROTOCOL-$CHAIN-{REPORT-DATE}-external.md
Optional external delivery copy → ../../audits/$PROTOCOL-$CHAIN-{REPORT-DATE}.md

## Data Retention
- Keep all audit-related inputs, intermediate results, and final artifacts in this workspace.
- Preserve relevant tmp/ data that informed discovery, falsification, verification, coverage, remediation, or reporting.
- Do not automatically clean or prune workspace data. Delete it only on explicit user instruction after checking dependencies.
- Generate one internal reference report by default after closure.
- Generate the professional external-format report only on an explicit external/client/public report request; public release still requires explicit authorization.
- Keep every editable report source under reports/; files outside this workspace are delivery copies.
- Before changing an approved, delivered, or published external report, preserve its versioned source and digest under reports/; routine internal drafts need no duplicate copy.
EOF

# Initialize stable phase artifacts so later phases update rather than improvise formats.
[ -f "$WORKSPACE/scope.md" ] || cat > "$WORKSPACE/scope.md" <<EOF
# Scope — Phase 0

## Target Identity

| Field | Value |
|-------|-------|
| Protocol | $PROTOCOL |
| Chain | $CHAIN |
| Source repository / package | TBD |
| Source revision | TBD |
| Deployment / program / package IDs | TBD <!-- use N/A only when no live deployment is in scope --> |
| Deployed bytecode / package hash | TBD <!-- use N/A only when no live deployment is in scope --> |
| Production build/profile or target-identity procedure | TBD |
| Compiler / toolchain | TBD |
| Configuration / state anchor | TBD |

## In Scope

<!-- List exact files, contracts/programs/packages, deployments, integrations, and economic flows. -->

## Out of Scope

<!-- List explicit exclusions and why. -->

## Narrow Work Units

| ID | Attack surface / invariant | Owner | Status | Evidence / candidate links |
|----|----------------------------|-------|--------|----------------------------|
EOF

[ -f "$WORKSPACE/target-lock.md" ] || cat > "$WORKSPACE/target-lock.md" <<EOF
# Target Lock

> Canonical immutable identity used by candidates, verification manifests,
> validations, and findings. Complete this after target acquisition. If any
> identity field or target artifact changes, re-check every linked claim.
> SHA-256 digests below are optional for internal review and required under
> triage-check.sh --strict-hashes; a recorded digest is always verified, so
> refresh it deliberately rather than bulk-replacing it.

## Target Identity

| Field | Value |
|-------|-------|
| Protocol | $PROTOCOL |
| Chain | $CHAIN |
| Source repository / package | TBD |
| Source revision | TBD |
| Deployment / program / package IDs | TBD <!-- use N/A only when no live deployment is in scope --> |
| Deployed bytecode / package hash | TBD <!-- use N/A only when no live deployment is in scope --> |
| Production build/profile or target-identity procedure | TBD |
| Compiler / toolchain | TBD |
| Configuration / state anchor | TBD |

## Target Artifact Manifest

> List every workspace artifact relied on to identify or analyze the scoped
> target. Paths are workspace-relative regular files under contracts/ and are
> resolved mechanically. Roles explain source/build/bytecode/config significance
> and prevent arbitrary files from being mistaken for target units. For deployed
> claims, use chain-native deployment IDs and retain primary chain/build evidence
> that proves their semantic association. Put a 64-hex SHA-256 in the digest
> column when the engagement needs integrity binding, or leave it N/A; a
> recorded digest is verified against the file.

| Target ID | Workspace path | SHA-256 | Role / scope significance |
|-----------|----------------|---------|---------------------------|
| T-01 | TBD | N/A | TBD |
EOF

[ -f "$WORKSPACE/orientation.md" ] || cat > "$WORKSPACE/orientation.md" <<'EOF'
# Orientation — Phase 2

## O.1 Protocol Summary

## O.2 Value-Flow Diagram

## O.3 Storage Glossary
| Variable | Type | Meaning | Writers | Readers / sink implications |
|----------|------|---------|---------|-----------------------------|

## O.4 Pre-Read Red Flags
| Signal | Location | Follow-up lens | Status |
|--------|----------|----------------|--------|
EOF

[ -f "$WORKSPACE/model.md" ] || cat > "$WORKSPACE/model.md" <<'EOF'
# Model — Phase 4 Outputs

## Invariants
| ID | Statement | Class | Test method | Status / evidence |
|----|-----------|-------|-------------|-------------------|

## State Machines
<!-- For each lifecycle object: full from/to matrix, W-NN reference, guard, terminal markers. -->

## Trust Boundaries
| Entity | Compromise | Liveness | Lie | Slow | Mitigation / residual risk |
|--------|------------|----------|-----|------|----------------------------|
EOF

[ -f "$WORKSPACE/triage/candidates.md" ] || cat > "$WORKSPACE/triage/candidates.md" <<'EOF'
# Candidate Registry — Generated Index

> Generated from `triage/candidates/C-NN.md` by `triage-index.sh`. Do not edit this table manually; claim work by creating/updating the per-candidate file, then regenerate.

| ID | Target / threat actor and entry | Invariant / mechanism | Impact criterion / falsification | Verification manifest | Dedup key | Owner | Status |
|----|-------------------------|-----------------------|----------------------------------|-----------------------|-----------|-------|--------|
EOF

[ -f "$WORKSPACE/triage/candidates/_template.md" ] || cat > "$WORKSPACE/triage/candidates/_template.md" <<'EOF'
# C-NN — Candidate Title

- Candidate ID: C-NN
- Target artifact IDs: T-NN <!-- comma-separated with no spaces, e.g. T-01,T-02 -->
- Target lock SHA-256: N/A <!-- optional integrity binding; a recorded digest must match target-lock.md -->
- Target component: TBD
- Target revision: TBD
- Deployment / package / program: TBD
- Production build / configuration: TBD
- Threat actor / entry: TBD
- Required actor capabilities: TBD
- Invariant: TBD
- Mechanism and reachability evidence: TBD
- Claimed impact / success criterion: TBD
- Falsification / control: TBD
- Verification manifest: triage/reproducers/C-NN.md
- Dedup key: TBD
- Known-issue search: TBD
- Producer: TBD
- Producer context / timestamp: TBD
- Source and verification artifact hashes: N/A <!-- optional; required under --strict-hashes -->
- Cost versus impact: TBD
- Potential severity / materiality: TBD / MATERIAL <!-- engagement taxonomy label / MATERIAL or NON-MATERIAL -->
- Coverage limitation: TBD <!-- N/A unless INCONCLUSIVE; then cite coverage.md row -->
- Canonical candidate / finding: TBD <!-- N/A unless DUPLICATE; then cite C-NN/F-NN -->
- Status: PROPOSED
- Disposition reason / evidence: TBD
EOF

[ -f "$WORKSPACE/triage/known-issues.md" ] || cat > "$WORKSPACE/triage/known-issues.md" <<'EOF'
# Known Issues and Deduplication Ledger

| Dedup key (root-cause\|invariant\|sink) | Status | Canonical candidate/finding/advisory | Affected variants | Evidence / notes |
|------------------------------------------|--------|--------------------------------------|-------------------|------------------|
EOF

[ -f "$WORKSPACE/triage/reproducers/_template.md" ] || cat > "$WORKSPACE/triage/reproducers/_template.md" <<'EOF'
# Verification Manifest — C-NN

> `triage/reproducers/` is the stable directory name for independently reviewable
> evidence packages. The method may be a PoC, trace, fork/snapshot replay, formal
> proof, source-level proof, differential test, historical transaction, or any
> other method that supports the exact claim.

- Candidate: C-NN
- Target artifact IDs:
- Target lock SHA-256: N/A <!-- optional integrity binding; verified when recorded -->
- Target/source revision and artifact hash:
- Production build/profile or target-identity procedure:
- Chain, deployment/configuration, dependencies:
- Evidence verdict: <!-- CONFIRMED-DEPLOYED / CONFIRMED-RECONSTRUCTION / CONFIRMED-LOGIC -->
- Target fidelity: <!-- DEPLOYED / RECONSTRUCTION / LOGIC -->
- Target fidelity basis:
- State anchor kind: <!-- BLOCK / SLOT / TRANSACTION / OBJECT-VERSIONS / STATE-ROOT / SNAPSHOT / DEPLOYMENT-VERSION / SOURCE-REVISION / PRE-DEPLOYMENT / OTHER-PINNED -->
- State anchor value:
- Producer context and evidence revision:
- Toolchain/OS versions:
- Actor initial conditions and capital/capability acquisition:
- Preconditions checked:
- Action sequence or proof derivation:
- Evidence method:
- Primary verification artifact path:
- Primary verification artifact SHA-256: N/A <!-- optional; the artifact itself must resolve -->
- Exact command or review procedure:
- Claimed impact / success criterion:
- Primary evidence path:
- Primary evidence SHA-256: N/A <!-- optional; the artifact itself must resolve -->
- Falsification / control procedure and expected discriminator:
- Falsification / control evidence path:
- Falsification / control evidence SHA-256: N/A <!-- optional; the artifact itself must resolve -->
- Production-state deviations:
- Repeatability / proof-review result:
EOF

[ -f "$WORKSPACE/triage/validation/_template.md" ] || cat > "$WORKSPACE/triage/validation/_template.md" <<'EOF'
# Independent Validation — C-NN

> The validator must differ from the producer and independently challenge the
> claim against pinned artifacts. They may reproduce the producer's procedure,
> use a different sound method, or do both; record the method selected.

- Candidate: C-NN
- Target artifact IDs: T-NN
- Target lock SHA-256: N/A <!-- optional integrity binding; verified when recorded -->
- Validator: TBD
- Validator context / timestamp: TBD
- Independent from producer: TBD
- Independent verification procedure: TBD
- Target identity / production configuration: TBD
- Independent verification result: TBD <!-- PASS/CONFIRMED with evidence -->
- Evidence verdict: TBD <!-- must match the verification manifest -->
- Target fidelity verdict: TBD <!-- PASS/CONFIRMED with deployed/reconstruction/logic basis -->
- Actor/reachability verdict: TBD <!-- PASS/CONFIRMED — threat-model-valid actor/entry and capabilities -->
- Impossible-state review: TBD <!-- PASS/CONFIRMED — no unreachable state or hidden privilege -->
- Impact criterion and falsification result: TBD <!-- PASS/CONFIRMED — consequence established; method-appropriate falsification addressed -->
- Dedup disposition: TBD <!-- NOVEL / UNIQUE / VARIANT-OF C-NN or F-NN -->
- Actor cost versus impact: TBD
- Recommendation: TBD <!-- INDEPENDENTLY-VALIDATED / ACCEPT -->
- Decision reason: TBD
- Validation evidence path: TBD
- Validation evidence SHA-256: N/A <!-- optional; the artifact itself must resolve -->
- Human decision / acceptor / date: TBD <!-- report gate, not the findings gate: ACCEPTED / human name or role / YYYY-MM-DD -->
EOF

[ -f "$WORKSPACE/findings.md" ] || cat > "$WORKSPACE/findings.md" <<'EOF'
# Findings — Phases 8-10

> Evidence-closed, independently validated findings only. Proof admits a finding
> here; human sign-off is added before any report is issued. All hypotheses and
> non-validated dispositions stay in `triage/candidates.md`.

## Format

Each finding:
- ID: F-NN
- Candidate ID / dedup key: C-NN / <root-cause|invariant|sink>
- Target lock SHA-256: <exact target-lock.md digest, or N/A — optional unless --strict-hashes>
- Target artifact IDs: T-NN
- Discovery context / classification: <optional A-J lens, tool/query, manual/formal analysis, incident trace, or other useful label>
- Target locator: <source line, bytecode range, instruction, transaction, object version, model obligation, or other exact locator>
- Reachability chain / evidence: <entry sequence → effect, with code/model/evidence refs>
- Mechanism: <evidence-backed mechanism, state transition, or violated proof obligation>
- Invariant violated: <explicit safety/economic property; model.md ID when used>
- Original severity: <engagement or bug-bounty taxonomy label; Critical/High require an asset-loss consequence; never rewrite because of remediation>
- Current remediation status: Open / Fixed - Verified / Partially Fixed / Acknowledged / Risk Accepted / Not Yet Retested
- Current deployment: confirmed exploitable / conditionally exposed / plausibly exposed / not exposed at pinned state / not deployed / unknown <!-- confirmed/conditional/plausible/not-exposed state claims require CONFIRMED-DEPLOYED evidence -->
- Deployment/state anchor: <network + deployment ID + immutable block/slot/checkpoint/object version, or NOT ASSESSED with reason>
- Evidence verdict: CONFIRMED-DEPLOYED / CONFIRMED-RECONSTRUCTION / CONFIRMED-LOGIC
- Verification evidence: triage/reproducers/C-NN.md
- Independent validation: triage/validation/C-NN.md
- Cost versus impact: <attacker prerequisites/cost versus user/protocol impact; state explicitly whether the claim reaches loss of funds/assets>
- Human decision: ACCEPTED / <human acceptor> / YYYY-MM-DD <!-- report gate; required before any report is issued (triage-check.sh --report) -->
- Client response: <exact response or concise faithful summary + retained source reference/date, or NOT PROVIDED with date>
- Remediation baseline: <for Fixed - Verified: revision=TYPE:IMMUTABLE_ID; manifest=WORKSPACE_RELATIVE_PATH[; sha256=64HEX], otherwise NOT PROVIDED with reason>
- Retest: <for Fixed - Verified: reviewer=IDENTITY; date=YYYY-MM-DD; method=UNRESTRICTED_DESCRIPTION; evidence=WORKSPACE_RELATIVE_PATH[; sha256=64HEX]; result=POSITIVE_MECHANISM_OR_PROPERTY_CLOSURE, otherwise NOT YET RETESTED with reason>
- Residual risk: <bounded remaining risk, or NO RESIDUAL RISK IDENTIFIED within stated retest scope>
- Disclosure handling: <classification/embargo/redaction decision + owner/date, or NOT DECIDED>

## Findings

EOF

[ -f "$WORKSPACE/coverage.md" ] || cat > "$WORKSPACE/coverage.md" <<'EOF'
# Coverage & Closure

> Update continuously. Objective artifact counts are reconciled mechanically.
> Security coverage is method-defined: record the obligations/surfaces actually
> selected, the method/evidence, and residual blind spots. `PARTIAL` or `OPEN` is
> a limitation, never a pass. Do not invent Atlas/lens rows for methods not used.

## Objective Artifact Reconciliation

| Artifact class | Expected | Reviewed / resolved | Open | Evidence |
|----------------|----------|---------------------|------|----------|
| In-scope target artifacts | ? | 0 | ? | scope manifest / pinned target identity |
| Candidates dispositioned | ? | 0 | ? | triage/candidates.md |
| Candidates with verification evidence | ? | 0 | ? | triage/reproducers/ + evidence/proof artifacts |
| Independent validations | ? | 0 | ? | triage/validation/ |
| Material candidate verdicts | ? | 0 | ? | candidate closure class + triage evidence |
| Findings recorded | ? | 0 | ? | findings.md |

## Method-Defined Security Coverage

> Status is `COVERED`, `PARTIAL`, `OPEN`, `EXCLUDED`, or `NOT-APPLICABLE`.
> Add any number of rows. A row may represent properties, entries/effects,
> transitions, query sets, proof obligations, state regions, transactions,
> economic assumptions, or another unit appropriate to the selected method.

| Coverage obligation / surface | Status | Evidence / method | Residual blind spots / limitation |
|-------------------------------|--------|-------------------|------------------------------------|
| TBD | OPEN | TBD | TBD |

## Candidate Limitations

> Every INCONCLUSIVE candidate has exactly one row. Candidates classified
> `MATERIAL` require report verdict `INCOMPLETE`; `NON-MATERIAL` limitations still
> need an explicit report verdict. Severity label vocabulary is engagement-defined.

| Candidate | Severity / materiality | Status | Blocker / open proof obligation | Required next step | Report verdict |
|-----------|------------------------|--------|---------------------------------|--------------------|----------------|

## Open Assumptions and Blocked Checks

| ID | Question / blocker | Affected scope or funds | Required next step | Reported as limitation? |
|----|--------------------|-------------------------|--------------------|-------------------------|
EOF

echo "[ok] Workspace initialized at $WORKSPACE"
echo "[ok] Chain: $CHAIN → playbook: $PLAYBOOK → metrics: $METRICS"
echo "[next] Phase 1: fetch source into $WORKSPACE/contracts/"
