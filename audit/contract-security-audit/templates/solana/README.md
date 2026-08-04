# Optional Solana PoC Templates

Optional executable examples for Solana verification. Use, adapt, or ignore them; any sound validation method may support a candidate.

## Choosing a harness (see playbook § 3.1)

| File | Harness | Use for |
|------|---------|---------|
| `litesvm_harness.rs` | LiteSVM (in-process SVM, Rust) | Fast example for logic PoCs and pre-deployment audits. Ordinarily supports `CONFIRMED-LOGIC`. |
| `fork_replay.sh` | `solana-test-validator --clone` | Fail-closed exploratory scaffold. Sequential clones are not a coherent deployed-state snapshot by themselves. |
| `exploit_*.rs` | LiteSVM (build on the harness) | Concrete exploit shapes (signer bypass, account substitution, arbitrary CPI). |

## Setup

```bash
cd "$WORKSPACE/poc"
cargo init --lib
# Pin versions compatible with the target program/toolchain, then commit and hash Cargo.lock.
cargo add litesvm@<PIN> solana-sdk@<PIN> spl-token@<PIN> spl-associated-token-account@<PIN>
# Build the target program first: anchor build  → target/deploy/<program>.so
#                          (or)  cargo build-sbf for native programs
cargo test --locked -- --nocapture 2>&1 | tee "C-${CANDIDATE_NN}.log"
```

## Assertion discipline (playbook § 3.5)

When using an executable PoC, assert the claimed consequence: net value change, unauthorized state/capability, integrity failure, liveness failure, governance impact, or another measurable effect. Do not force every issue into a funds-only assertion.

## Candidate verdict (record under triage/)

- **CONFIRMED-DEPLOYED** — evidence, by any sound method, binds the mechanism/effect to the actual deployed program, relevant accounts/configuration, and state.
- **CONFIRMED-LOGIC** — LiteSVM/Mollusk closes the chain on controlled state; current-deployment exploitability remains separate.
- **INCONCLUSIVE** — clone/state/tooling is incomplete or the blocker does not disprove the hypothesis.
- **REFUTED** — a faithful harness disproves a necessary premise; record which one.

Record a method-appropriate falsification/control and preserve the relevant
artifacts. A validator other than the producer independently challenges the
claim by inspecting the primary artifacts and may rerun/re-review the documented
method, use a different sound method, or do both. Record the exact `T-NN` artifact
set — plus the target-lock SHA-256 when the engagement records digests — in the
candidate, verification manifest, validation, and recorded finding. Only an
independently validated candidate is copied into `findings.md`.
