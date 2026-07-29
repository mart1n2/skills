#!/usr/bin/env bash
# atlas-inventory.sh — bootstrap the Pass P "reachability atlas" inventories.
#
# Usage:
#   atlas-inventory.sh <contracts-dir> <atlas-out-dir>
#
# Produces optional seed Markdown tables. Each row is a grep hit + minimal
# context. Regex inventory is a reproducible lower bound, never proof of
# completeness. If these tables support a coverage claim, enrich and reconcile
# them using any suitable independent method; otherwise point coverage.md to the
# replacement evidence and record this helper's blind spots.

set -uo pipefail

CONTRACTS_DIR_INPUT="${1:?Usage: atlas-inventory.sh <contracts-dir> <atlas-out-dir>}"
OUT_DIR_INPUT="${2:?Usage: atlas-inventory.sh <contracts-dir> <atlas-out-dir>}"

if ! CONTRACTS_DIR="$(cd "$CONTRACTS_DIR_INPUT" 2>/dev/null && pwd)"; then
    echo "ERROR: contracts directory not found: $CONTRACTS_DIR_INPUT" >&2
    exit 1
fi
mkdir -p "$OUT_DIR_INPUT"
OUT_DIR="$(cd "$OUT_DIR_INPUT" && pwd)"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ATLAS_WORKSPACE="$(cd "$OUT_DIR/.." && pwd)"

source "$SKILL_DIR/scripts/retention.sh"
audit_archive_existing "$ATLAS_WORKSPACE" "atlas-inventory" "$OUT_DIR" || {
    echo "ERROR: refusing to replace Atlas output without retaining the prior version" >&2
    exit 1
}

# Exclude common dependency / dev paths so the seed tables are about the project.
EXCLUDES=(
    --exclude-dir=node_modules
    --exclude-dir=@openzeppelin
    --exclude-dir=hardhat
    --exclude-dir=forge-std
    --exclude-dir=ds-test
    --exclude-dir=out
    --exclude-dir=cache
    --exclude-dir=lib
    --exclude-dir=.git
)

echo "=== Atlas Inventory ==="
echo "Contracts: $CONTRACTS_DIR"
echo "Atlas out: $OUT_DIR"
echo

# Detect language family
SOL_COUNT=$(find "$CONTRACTS_DIR" -name "*.sol" -not -path "*/node_modules/*" -not -path "*/@openzeppelin/*" -not -path "*/hardhat/*" 2>/dev/null | wc -l | tr -d ' ')
RS_COUNT=$(find "$CONTRACTS_DIR" -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')
MV_COUNT=$(find "$CONTRACTS_DIR" -name "*.move" 2>/dev/null | wc -l | tr -d ' ')
echo "Detected: ${SOL_COUNT} .sol, ${RS_COUNT} .rs, ${MV_COUNT} .move"
echo

# -------- P.1 Sink Inventory --------
SINKS="$OUT_DIR/sinks.md"
cat > "$SINKS" <<'EOF'
# P.1 Sink Inventory (Optional Regex Seed)

> Each row below is a grep hit. If this inventory supports coverage or a claim,
> replace `?` with concrete semantic data and record excluded syntax/paths.

| ID | File:Line | Containing Fn | Effect (direction · asset · amount) | Local Preconds | State Reads |
|----|-----------|---------------|--------------------------------------|----------------|-------------|
EOF

ID=1
emit_sink_row() {
    local pattern_label="$1"; shift
    local pattern_regex="$1"; shift
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file="${line%%:*}"
        local rest="${line#*:}"
        local lineno="${rest%%:*}"
        printf '| S-%02d | `%s:%s` | ? | %s | ? | ? |\n' \
            "$ID" "${file#$CONTRACTS_DIR/}" "$lineno" "$pattern_label" >> "$SINKS"
        ID=$((ID + 1))
    done < <(grep -RIn "${EXCLUDES[@]}" -E "$pattern_regex" "$CONTRACTS_DIR" 2>/dev/null || true)
}

if [ "$SOL_COUNT" -gt 0 ]; then
    emit_sink_row 'ERC-20 transfer'         '\.safeTransfer(From)?\s*\(|\.transfer(From)?\s*\('
    emit_sink_row 'Mint/Burn'               '\b_?mint\s*\(|\b_?burn\s*\('
    emit_sink_row 'Native value call'       '\{[[:space:]]*value[[:space:]]*:'
    emit_sink_row 'Native value helper'     '(^|[^[:alnum:]_])(Address\.)?sendValue[[:space:]]*\(|\.send[[:space:]]*\(|payable[[:space:]]*\([^)]+\)\.transfer[[:space:]]*\('
    emit_sink_row 'SELFDESTRUCT value send' '(^|[^[:alnum:]_])selfdestruct[[:space:]]*\('
    emit_sink_row 'Inline assembly review'  '(^|[^[:alnum:]_])assembly[[:space:]]*\{'
    emit_sink_row 'Approval grant'          '\.(safeApprove|approve|increaseAllowance|decreaseAllowance)\s*\('
    emit_sink_row 'Delegatecall'            '\.delegatecall\s*\('
fi

if [ "$RS_COUNT" -gt 0 ]; then
    # SPL / Token-2022 movement (anchor_spl + raw)
    emit_sink_row 'SPL transfer'            'token::transfer\s*\(|token::transfer_checked\s*\(|\btransfer_checked\s*\('
    emit_sink_row 'SPL mint/burn'           'token::mint_to\s*\(|token::burn\s*\(|\bmint_to\s*\(|\bburn\s*\('
    emit_sink_row 'token authority change'  '\bset_authority\s*\(|\bapprove\s*\(|\bfreeze_account\s*\(|\bclose_account\s*\('
    # Lamport / native value moves (the Solana "native transfer")
    emit_sink_row 'lamport move'            '\.lamports\s*\.borrow_mut\s*\(|try_borrow_mut_lamports\s*\(|system_program::transfer\s*\('
    # CPI invocation — every invoke is a potential unbounded fund-effect (validate target id!)
    emit_sink_row 'CPI invoke'              '\binvoke\s*\(|\binvoke_signed\s*\(|CpiContext::new'
    # Direct accounting writes to a deserialized amount/balance/debt field
    emit_sink_row 'accounting field write'  '\.\s*(amount|balance|debt|supply|collateral|shares?)\s*(=|\+=|-=)'
fi

if [ "$MV_COUNT" -gt 0 ]; then
    emit_sink_row 'object transfer'         'transfer::(public_)?transfer\b'
    emit_sink_row 'object share/freeze'     'transfer::(public_)?(share_object|freeze_object)\b'
    emit_sink_row 'party object transfer'   '(public_)?party_transfer\b|party::'
    emit_sink_row 'coin ops'                'coin::(split|join|take|put|mint|burn|from_balance|into_balance|mint_and_transfer)\b'
    emit_sink_row 'balance/address-funds ops' 'balance::(join|split|withdraw_all|increase_supply|decrease_supply|send_funds|redeem_funds|withdraw_funds_from_object)\b'
    emit_sink_row 'dynamic field write'     'dynamic_(object_)?field::(add|remove)\b'
fi

SINKS_COUNT=$((ID - 1))
echo "P.1 sinks: $SINKS_COUNT rows → $SINKS"

# -------- P.2 Gate-Read Inventory --------
GATES="$OUT_DIR/gates.md"
cat > "$GATES" <<'EOF'
# P.2 Gate-Read Inventory (Seeded)

> Branches and require/assert that read a state field for control-flow. Enrich with the unlocked branch + which sink it gates.

| ID | File:Line | Containing Fn | Field Read | Branch Unlocked |
|----|-----------|---------------|------------|-----------------|
EOF

ID=1
emit_gate_row() {
    local label="$1"; shift
    local regex="$1"; shift
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file="${line%%:*}"
        local rest="${line#*:}"
        local lineno="${rest%%:*}"
        printf '| G-%02d | `%s:%s` | ? | %s | ? |\n' \
            "$ID" "${file#$CONTRACTS_DIR/}" "$lineno" "$label" >> "$GATES"
        ID=$((ID + 1))
    done < <(grep -RIn "${EXCLUDES[@]}" -E "$regex" "$CONTRACTS_DIR" 2>/dev/null || true)
}

if [ "$SOL_COUNT" -gt 0 ]; then
    emit_gate_row 'state/status enum compare'    '\b(if|require|assert)\s*\([^)]*\.\s*(state|status|phase|stage)\s*(==|!=|>=|<=|>|<)'
    emit_gate_row 'boolean approval flag'        '\b(if|require)\s*\(\s*!?(_?approved|_?verified|_?paused|_?initialized|_?finalized)'
    emit_gate_row 'role / address check'         '\bif\s*\(\s*msg\.sender\s*(==|!=)|\brequire\s*\(\s*msg\.sender\s*(==|!=)'
    emit_gate_row 'custom only* modifier site'   '\bonly[A-Z][A-Za-z]+\s*\('
fi

if [ "$RS_COUNT" -gt 0 ]; then
    # Explicit checks
    emit_gate_row 'require!/assert/err'          'require(_eq|_keys_eq|_gt|_neq)?!\s*\(|assert!\s*\(|err!\s*\(|return\s+Err'
    emit_gate_row 'enum match on state'          'match\s+[a-zA-Z_.]+\.(state|status|phase)'
    # Native account-validation checks
    emit_gate_row 'native is_signer/owner/writable' '\.is_signer\b|\.is_writable\b|\.owner\s*(==|!=)|key\s*(==|!=)'
    # Anchor implicit gates inside #[account(...)] — possession/binding IS the auth
    emit_gate_row 'anchor constraint gate'       'has_one\s*=|constraint\s*=|owner\s*=|address\s*=|seeds\s*=|\bbump\b|token::(authority|mint)|mint::authority|init_if_needed|close\s*='
    emit_gate_row 'anchor typed-account gate'    'Signer<|Account<|Program<|Sysvar<|InterfaceAccount<'
    # NEGATIVE SPACE: raw AccountInfo/UncheckedAccount = a gate ABSENCE until proven otherwise.
    # These rows are gate-holes to interrogate, not gates present.
    emit_gate_row 'GATE-ABSENCE raw AccountInfo' 'AccountInfo<|UncheckedAccount<|/CHECK'
fi

if [ "$MV_COUNT" -gt 0 ]; then
    emit_gate_row 'assert! gate'                 'assert!\s*\(|assert_eq!\s*\(|\babort\b'
    # Capability-object gates — a &Cap parameter IS the authorization
    emit_gate_row 'capability param gate'        '&\s*(mut\s+)?[A-Za-z_]*(Cap|AdminCap|TreasuryCap|UpgradeCap|OwnerCap)\b'
    # Visibility gates — public/entry too-open is the bug; build vs the design permission table
    emit_gate_row 'visibility surface'           '\bpublic\s+entry\s+fun|\bpublic\s+fun|\bentry\s+fun|public\((package|friend)\)'
    # Shared-object mutation surface (anyone may reference; verify the design's
    # actual capability/sender/object/party/state authorization requirements).
    emit_gate_row 'shared &mut surface'          'fun\s+[A-Za-z_]+\s*\([^)]*&mut\s+[A-Z]'
    emit_gate_row 'sender authorization surface' 'tx_context::sender\s*\(|sender\s*\(\s*ctx'
    emit_gate_row 'settled address-balance read' 'balance::settled_funds_value\s*\('
fi

GATES_COUNT=$((ID - 1))
echo "P.2 gates: $GATES_COUNT rows → $GATES"

# -------- P.3 Gate-Write Inventory --------
WRITES="$OUT_DIR/writes.md"
cat > "$WRITES" <<'EOF'
# P.3 Gate-Write Inventory (Seeded)

> Assignments to gating fields. If this inventory supports coverage, enrich it
> with a suitable method. One option is to extract field names from `gates.md`,
> re-search each name, and inspect struct-literal overwrites where the field name
> may appear only in a constructor.

| ID | File:Line | Containing Fn | From-values | To-value | Local Preconds | Caller Class | External Reach |
|----|-----------|---------------|-------------|----------|----------------|--------------|----------------|
EOF

ID=1
emit_write_row() {
    local label="$1"; shift
    local regex="$1"; shift
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local file="${line%%:*}"
        local rest="${line#*:}"
        local lineno="${rest%%:*}"
        printf '| W-%02d | `%s:%s` | ? | ? | %s | ? | ? | ? |\n' \
            "$ID" "${file#$CONTRACTS_DIR/}" "$lineno" "$label" >> "$WRITES"
        ID=$((ID + 1))
    done < <(grep -RIn "${EXCLUDES[@]}" -E "$regex" "$CONTRACTS_DIR" 2>/dev/null || true)
}

if [ "$SOL_COUNT" -gt 0 ]; then
    emit_write_row 'state field assign'           '\.\s*state\s*=|\.\s*status\s*=|\.\s*phase\s*=|\.\s*stage\s*='
    emit_write_row 'approval/verified flag set'   '_?approved\s*\[[^]]*\]\s*=|_?verified\s*\[[^]]*\]\s*=|_?paused\s*='
    emit_write_row 'role mapping assign'          '_?roles?\s*\[[^]]*\]\s*=|_?operators?\s*\[[^]]*\]\s*='
    emit_write_row 'pause toggle'                 '_pause\s*\(\)|_unpause\s*\(\)'
    emit_write_row 'initializer field set'        'function\s+initialize\s*\('
    emit_write_row 'struct/enum literal write'    '(CreditState|enum)\.[A-Z][A-Za-z]+|state\s*:\s*'
    # Full-struct overwrite — field name may NOT appear on the line, only in struct literal
    emit_write_row 'whole-struct mapping write'   '\[\s*[^]]+\s*\]\s*=\s*[A-Z][A-Za-z]+\s*[\({]'
    # `delete map[key]` resets struct to default — field becomes 0/false/enum.0
    emit_write_row 'delete (state reset)'         '\bdelete\s+[A-Za-z_][A-Za-z_0-9]*\s*(\[|\.)'
    # Inline assembly storage write — easy to miss in review (no field name on the line)
    emit_write_row 'assembly sstore'              '\bsstore\s*\('
    # `using X for Y` — library functions can mutate Y; treat library callsites as potential writers
    emit_write_row 'using-for library binding'    '\busing\s+[A-Za-z_][A-Za-z_0-9]*\s+for\s+'
    # OZ-style helper setters
    emit_write_row 'setter helper (_setX/updateX)' '\bfunction\s+(_set|set|update|_update)[A-Z][A-Za-z]+\s*\('
    # Inheritance hint — fields may be defined in parent contracts
    emit_write_row 'inherited storage hint'       '\bcontract\s+[A-Za-z_]+\s+is\s+'
fi

if [ "$RS_COUNT" -gt 0 ]; then
    emit_write_row 'state/flag field assign'      '\.\s*(state|status|phase|stage)\s*=|\.is_[a-z_]+\s*=\s*(true|false)'
    emit_write_row 'authority/owner field assign' '\.\s*(authority|owner|admin|delegate|delegated_amount|close_authority)\s*='
    emit_write_row 'AccountInfo data mutation'    '\.try_borrow_mut_data\s*\(|\.data\.borrow_mut\s*\(|\.serialize\s*\('
    emit_write_row 'init handler'                 'fn\s+initialize\s*\(|#\[account\(\s*init'
    emit_write_row 'token-authority CPI write'    '\bset_authority\s*\(|\bapprove\s*\('
    emit_write_row 'unsafe/raw write'             'unsafe\s*\{|raw_pointer'
fi

if [ "$MV_COUNT" -gt 0 ]; then
    emit_write_row 'state field assign'           '\.\s*(state|status|authority|owner|admin|version)\s*='
    emit_write_row 'borrow_mut field'             '&mut\s+[A-Za-z_][A-Za-z_0-9]*\.'
    emit_write_row 'object share/freeze (mode!)'  'transfer::(public_)?(share_object|freeze_object)\b'
    emit_write_row 'dynamic field add/remove'     'dynamic_(object_)?field::(add|remove)\b'
    emit_write_row 'init / cap distribution'      'fun\s+init\s*\(|transfer::(public_)?transfer\s*\([^)]*Cap'
fi

WRITES_COUNT=$((ID - 1))
echo "P.3 writes: $WRITES_COUNT rows → $WRITES"

# -------- P.4 Paths & P.5 Intent (templates only) --------
PATHS="$OUT_DIR/paths.md"
cat > "$PATHS" <<'EOF'
# P.4 Reachable-Path Enumeration

> For each sink S-NN, list every entry-sequence (possibly multi-call) that reaches it. Walk the call graph forward from each external entry; conjoin every precondition encountered; for each gate-read precondition, look up the writes in `writes.md` and recursively expand which entries can satisfy it.

## S-?? (sink description)

Reachable via:
- `[entry_A(args)]` — preconds: `?` — intended? `yes/no`
- `[entry_B(args) → tickHelper(...) → entry_C(args)]` — preconds: `?` — intended? `yes/no`

(Repeat per sink.)
EOF
echo "P.4 paths template → $PATHS"

INTENT="$OUT_DIR/intent.md"
cat > "$INTENT" <<'EOF'
# P.5 Intent Specification

> From whitepaper, docs, NatSpec, and naming. For each sink and privileged actor, list the entry-sequence the protocol team *intends* to authorize.

| Sink | Intended Actor | Intended Entry-Sequence | Source (whitepaper / NatSpec / docs) |
|------|----------------|--------------------------|---------------------------------------|
| S-?? | ?              | ?                        | ?                                     |
EOF
echo "P.5 intent template → $INTENT"

DELTA="$OUT_DIR/delta.md"
cat > "$DELTA" <<'EOF'
# P.5 Delta — Candidate Chains

> Set difference: paths.md \ intent.md. Map every material populated row to a
> schema-complete C-NN file under triage/candidates/ and verify it with any sound
> method before acceptance.

| Delta ID | Candidate ID | Sink | Unintended Entry-Sequence | Atlas Refs (S/G/W) | Lens Suspect (A.x / B.y) | Candidate status |
|----------|--------------|------|---------------------------|--------------------|--------------------------|------------------|
| D-?? | C-?? | S-?? | ? | ? | ? | PROPOSED |
EOF
echo "P.5 delta template → $DELTA"

echo
echo "=== Atlas Bootstrap Complete ==="
echo "Sinks: $SINKS_COUNT · Gates: $GATES_COUNT · Writes: $WRITES_COUNT"
echo
echo "Optional next steps when using the Atlas for discovery or coverage:"
echo "  1. Enrich relied-on rows in sinks.md / gates.md / writes.md; replace '?' with concrete data."
echo "  2. Use any suitable method to find regex blind spots (for example AST/IR, queries, SAST, formal models, traces, or manual review)."
echo "  3. Build paths.md and intent.md where they improve the target analysis."
echo "  4. Map material delta.md rows to triage candidates, not findings."
echo "  5. Record covered surfaces, exclusions, and residual uncertainty in coverage.md."
echo "  6. If another method replaces the Atlas, retain only useful leads and cite the replacement evidence."
