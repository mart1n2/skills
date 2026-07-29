#!/usr/bin/env bash
# fork_replay.sh — Solana deployed-state PoC: clone the deployed program + every affected
# account/program dependency into a local validator, then run the exploit.
#
# Scaffold for a Critical/High deployed-fund-loss candidate (playbook-solana.md § 3.1, 3.3).
# The live per-account clone below is exploratory and is not deterministic acceptance
# evidence by itself: a candidate-specific version must snapshot all required accounts
# at one recorded RPC context slot, freeze/reuse the ledger, and execute both the exploit
# oracle and negative control. Until then the result is INCONCLUSIVE.
#
# Usage: edit the variables, then: bash fork_replay.sh
set -euo pipefail

PROGRAM_ID="${PROGRAM_ID:?set the deployed program id}"
CANDIDATE_NN="${CANDIDATE_NN:-${FINDING_NN:-00}}"  # FINDING_NN kept as a compatibility alias.
# Space-separated accounts the exploit reads/writes: config PDAs, victim vaults, oracle accounts.
CLONE_ACCOUNTS=(
  "${CONFIG_PDA:?}"
  "${VICTIM_VAULT:?}"
  "${ORACLE_ACCOUNT:?}"
  # "$PYTH_PRICE_ACCOUNT"
)

mkdir -p evidence
# Snapshot the pre-exploit state for the report.
for acc in "$PROGRAM_ID" "${CLONE_ACCOUNTS[@]}"; do
  solana account "$acc" --url mainnet-beta --output json > "evidence/${acc}.json" 2>/dev/null || true
done

CLONE_ARGS=()
for acc in "${CLONE_ACCOUNTS[@]}"; do CLONE_ARGS+=(--clone "$acc"); done

solana-test-validator \
  --clone-upgradeable-program "$PROGRAM_ID" \
  "${CLONE_ARGS[@]}" \
  --url mainnet-beta --reset --quiet &
VALIDATOR_PID=$!
trap 'kill "$VALIDATOR_PID" 2>/dev/null || true' EXIT
sleep 8
solana config set --url localhost

# Run the exploit instruction sequence. Reuse the project's Anchor TS tests / Bankrun client,
# or a small Rust client. Assert attacker token balance up and target down.
#   anchor test --skip-build --skip-deploy --skip-local-validator -- --features "exploit-${CANDIDATE_NN}"
echo "Validator up with cloned mainnet state. Run the exploit client now, asserting:"
echo "  attacker_token_after - attacker_token_before > 0   AND   target_after < target_before"

# Drive the exploit here, e.g.:
# anchor test --skip-build --skip-deploy --skip-local-validator \
#   -- --features "exploit-${CANDIDATE_NN}" 2>&1 | tee "C-${CANDIDATE_NN}.log"

echo "ERROR: scaffold only — add a coherent-slot snapshot, executable exploit, oracle, and negative control before using as evidence." >&2
exit 2
