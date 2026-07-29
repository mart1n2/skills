#!/usr/bin/env bash
# localnet_replay.sh — Sui "fork"-equivalent PoC: stand up a local network, publish the package,
# reconstruct the relevant on-chain objects, and drive the exploit as a PTB.
#
# Optional reconstruction scaffold (playbook-sui.md § 3.1).
# Sui has no native account clone, so fidelity is bounded by object reconstruction.
# `sui move test` supports CONFIRMED-LOGIC; this supports CONFIRMED-RECONSTRUCTION at most.
set -euo pipefail

PACKAGE_DIR="${PACKAGE_DIR:?path to the Move package}"
CANDIDATE_NN="${CANDIDATE_NN:-${FINDING_NN:-00}}"  # FINDING_NN kept as a compatibility alias.
ATTACKER="${ATTACKER:?attacker address (sui client active-address or a new one)}"
SHARED_OBJ="${SHARED_OBJ:?the shared object id the exploit targets}"

mkdir -p evidence
# 1. Snapshot the deployed objects you will reconstruct (fields → genesis/setup), for the report.
sui client object "$SHARED_OBJ" --json > "evidence/${SHARED_OBJ}.json" 2>/dev/null || true

# 2. Local network with a faucet.
RUST_LOG=warn sui start --force-regenesis --with-faucet &
SUI_PID=$!
trap 'kill "$SUI_PID" 2>/dev/null || true' EXIT
sleep 10
sui client switch --env localnet 2>/dev/null || true

# 3. Publish the package; capture the package id. jq or python3 may parse JSON,
# matching the skill-wide compatibility contract.
sui client publish --gas-budget 500000000 --json "$PACKAGE_DIR" \
    | tee evidence/publish.json >/dev/null
if command -v jq >/dev/null 2>&1; then
    PKG="$(jq -er '[.objectChanges[]? | select(.type == "published") | .packageId][0]' evidence/publish.json)"
elif command -v python3 >/dev/null 2>&1; then
    PKG="$(python3 -c 'import json; d=json.load(open("evidence/publish.json", encoding="utf-8")); print([o["packageId"] for o in d.get("objectChanges", []) if o.get("type") == "published"][0])')"
else
    echo "ERROR: jq or python3 is required to parse publish output." >&2
    exit 2
fi
echo "Published package: $PKG"

# 4. Reconstruct objects to mirror deployed state (call the package's setup/init with the captured
#    field values), then drive the exploit as a PTB composing public calls in the attack order.
#    Assert attacker coin balance increased and the target decreased.
echo "Now run the exploit PTB, e.g.:"
echo "  sui client ptb \\"
echo "    --move-call ${PKG}::module::vulnerable_fn @${SHARED_OBJ} <args> \\"
echo "    --assign out --transfer-objects '[out]' @${ATTACKER}"
# sui client ptb ... 2>&1 | tee "C-${CANDIDATE_NN}.log"

echo "ERROR: scaffold only — execute the candidate PTB, oracle, and negative control before using this reconstruction as evidence." >&2
exit 2
