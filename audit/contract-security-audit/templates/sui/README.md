# Optional Sui / Move PoC Templates

Optional executable examples for Sui verification. Use, adapt, or ignore them; any sound validation method may support a candidate.

## Choosing a harness (see playbook § 3.1)

| File | Harness | Use for |
|------|---------|---------|
| `exploit_shared_object.move` | `sui::test_scenario` | Fast example for logic PoCs and pre-deployment audits; ordinarily supports `CONFIRMED-LOGIC`. |
| `exploit_shift_truncation.move` | `test_scenario` | Hand-rolled checked-math / shift truncation (Cetus class, [SUI-G12]). |
| `localnet_replay.sh` | local Sui network + reconstructed objects | Fail-closed scaffold for documented reconstruction. It does not establish exact deployed state merely because it runs. |

## Setup

```bash
# Put PoC modules under the package's tests/ dir (or a sibling test package).
sui move test 2>&1 | tee "C-${CANDIDATE_NN}.log"
sui move test --coverage   # optional review signal; coverage is not proof of safety
```

## Assertion discipline (playbook § 3.4)

When using an executable PoC, assert the claimed consequence: net value change, unauthorized ownership/capability/state, integrity failure, liveness failure, governance impact, or another measurable effect. Do not force every issue into a funds-only assertion.

## Candidate verdict (record under triage/)

- **CONFIRMED-DEPLOYED** — evidence, by any sound method, binds the mechanism/effect to the actual deployed package, relevant objects/configuration, and state.
- **CONFIRMED-RECONSTRUCTION** — localnet with documented object reconstruction establishes the claimed effect; current-deployment exploitability remains unconfirmed.
- **CONFIRMED-LOGIC** — `test_scenario` establishes the code-level mechanism on controlled state; current deployment exposure remains separate.
- **INCONCLUSIVE** — state/tooling is incomplete or the blocker does not disprove the hypothesis.
- **REFUTED** — a faithful harness disproves a necessary premise; record which one.

Record a method-appropriate falsification/control and preserve the relevant
artifacts. A validator other than the producer independently challenges the
claim by inspecting the primary artifacts and may rerun/re-review the documented
method, use a different sound method, or do both. Record the current target-lock
SHA-256 and exact `T-NN` artifact set in the candidate, verification manifest,
validation, and accepted finding. Only a human-accepted candidate is copied into
`findings.md`.
