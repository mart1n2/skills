# Triage: Turning Candidates into Findings

This reference operationalizes the methodology described in the Ethereum
Foundation article [Triage Is the Product](https://blog.ethereum.org/2026/07/09/triage-is-the-product)
for production smart-contract audits. It is a companion to `methodology.md`:
the spine generates attack hypotheses; this document decides which of them are
credible findings.

The article uses a runnable reproducer as its strongest default receipt. This
skill preserves the same truth bar while broadening the receipt, at the user's
direction, to any self-contained and independently reviewable method that
supports the exact claim. Executability is evidence when relevant, not a
mandatory format.

## Objective

An audit agent is a search tool, not an oracle. Candidate volume is not success.
The useful output is the set of non-duplicate, threat-model-reachable defects whose
exact claims are supported by independently reviewable evidence and survive
falsification and independent review.

Keep these sets separate:

```text
candidates != findings
findings = independently_validate(evidence_bind(candidates))
report   = human_signoff(findings)
```

**Proof is the admission gate; human sign-off is the report gate.** A finding is
true or false on its evidence, so `findings.md` admits a candidate as soon as
claim-bound evidence and independent validation close it — no human decision is
required to record it. A human auditor still signs the finding, severity, and
disclosure decision before any report is issued, internal or external; run
`triage-check.sh --report` to enforce that. Every candidate that is not
evidence-closed stays in `triage/candidates.md`, including plausible but blocked
work.

## Proof, Not Paperwork

Bind a claim to its target by **identity** — chain, deployment/program/package ID,
source revision, build/profile, and the workspace path of each relied-on artifact —
and to its evidence by a **retained, resolvable artifact** that a reviewer can open.
Those are the load-bearing facts.

SHA-256 digests are integrity bookkeeping on top of that binding, and they are
**optional for internal review**: `triage-check.sh` does not require the
`target-lock.md` digest, per-artifact digests, or evidence digests by default.
Record them when integrity actually matters — client or public delivery, a
long-running engagement over a moving baseline, a disputed or shared workspace, or
any artifact that must be provably unchanged later — and run
`triage-check.sh --strict-hashes` to require them everywhere.

One rule always holds: **a digest that is recorded must be correct.** A wrong or
stale digest is a hard failure, because a false integrity claim is worse than no
integrity claim. An absent digest is not a failure; a missing, unreadable, or
unbound *proof artifact* still is.

## Non-Negotiable Norms

1. **Real target.** Bind the evidence to the scoped production code or a
   revision-pinned build through the target identity recorded in
   `target-lock.md` and the exact `T-NN` target artifacts material to the claim.
   Target identity in the lock and `scope.md` must match. The lock digest is
   optional (see *Proof, Not Paperwork*); the identity and artifact set are not.
   Models and reconstructions are valid only to the extent their correspondence
   and deviations are explicit.
2. **Real actor path.** Start from an actor and capability set allowed by the
   stated threat model—for example an unprivileged user, compromised signer,
   malicious privileged role, validator, oracle, or governance coalition. Do not
   silently grant capabilities, manufacture internal state, or use inputs that
   the claimed real path cannot produce.
3. **Explicit invariant and mechanism.** State what must remain true and the
   exact state-transition sequence that is expected to violate it.
4. **Observable or derivable success criterion.** Define what evidence would
   establish and falsify the claimed consequence. It must distinguish the issue
   from a tool/setup failure, hidden privilege, pre-funded attacker, unrelated
   state change, or vacuous proof.
5. **Self-contained evidence package.** A reviewer must be able to reproduce an
   executable result or follow a complete review/proof procedure against pinned
   artifacts without hidden local state.
6. **Independent validation.** The candidate producer cannot be its only
   validator. The validator reviews the primary evidence and assumptions, then
   may reproduce the recorded method, use a different sound method, or do both.
   The validator independently challenges scope fidelity, reachability, impact,
   falsification, deduplication, and cost versus impact.
7. **Human sign-off before reporting.** Evidence and independent validation admit
   a finding to `findings.md`; a human auditor then signs the finding, severity,
   and disclosure decision before any report is issued. Agents propose,
   reproduce, validate, reject, and recommend — they do not release a report on
   their own authority.

These are claim-acceptance norms, not restrictions on how vulnerabilities are
found or verified. Manual review, agents, SAST, fuzzing, invariant testing,
symbolic execution, formal methods, transaction analysis, traces, simulation,
replay, differential analysis, and source-level proof are all valid inputs.
Coordinate through the versioned artifacts in `triage/`.

## Candidate Lifecycle

Use exactly one current status per candidate:

```text
PROPOSED -> HUNTING -> REPRODUCED -> INDEPENDENTLY-VALIDATED -> HUMAN-ACCEPTED
                |            |            (findings.md)          (report gate)
                +----------> REJECTED <-----------+
                +----------> DUPLICATE
                +----------> OUT-OF-SCOPE
                +----------> INCONCLUSIVE
```

Status meanings:

| Status | Meaning |
|--------|---------|
| `PROPOSED` | Concrete candidate schema is complete; verification is not yet complete. |
| `HUNTING` | An owner is tracing reachability or developing evidence. |
| `REPRODUCED` | Compatibility status name: the producer has a reviewable verification package supporting the claim. It need not be an executable PoC. |
| `INDEPENDENTLY-VALIDATED` | A different reviewer independently checked the claim with a recorded sound method and all triage gates passed. **Terminal and findings-eligible:** record it in `findings.md` now. |
| `HUMAN-ACCEPTED` | A human auditor signed the finding, severity, and disclosure decision. Required for every recorded finding before a report is issued. |
| `REJECTED` | Evidence disproves a required condition; record the reason and evidence. |
| `DUPLICATE` | Same root cause and affected invariant as a known candidate/finding. |
| `OUT-OF-SCOPE` | Valid lead outside the revision, deployment, component, or threat model. |
| `INCONCLUSIVE` | Plausible, but state, dependencies, tooling, determinism, or proof is incomplete. |

Never relabel blocked or incomplete verification as `REJECTED`. Never promote
`REPRODUCED` directly to `findings.md` without independent validation — that gate
is about proof, and it does not move.

## Candidate Schema

Before hunting begins, every candidate row and detail block must contain:

- **Candidate ID:** stable `C-NN` identifier.
- **Target binding:** the canonical comma-separated set of target artifact IDs the
  claim depends on (for example `T-01,T-03`, with no spaces); every listed ID must
  resolve to an artifact-manifest row in `target-lock.md`. The `target-lock.md`
  SHA-256 is an optional integrity field: leave it `N/A` for internal review, and
  if you do record it, it must equal the current lock digest.
- **Target:** component, code revision, deployment/address or package/program ID,
  and production build/configuration profile.
- **Threat actor / entry:** real function/instruction/PTB entry or other trigger,
  plus the actor and capabilities required by the claim.
- **Invariant:** exact safety or economic property expected to fail.
- **Mechanism and reachability evidence:** the state-transition, transaction, or
  proof derivation from entry to effect, with code/model/evidence references.
- **Claimed impact / success criterion:** the observable or derivable consequence
  that the evidence must establish.
- **Falsification / control:** a meaningful negative control, counterexample
  search, proof-obligation challenge, or a reason a particular control is not
  applicable.
- **Verification manifest:** path, method, exact command or review procedure,
  prerequisites/assumptions, pinned target/state, expected result, and artifacts.
- **Dedup key:** canonical `root-cause|invariant|sink` key and known-issue search
  result.
- **Owner and provenance:** producer, runtime/model/tool context if relevant,
  timestamp, and source/evidence revision. Artifact digests are optional here.
- **Potential severity/materiality:** the highest credible severity label under
  the engagement's taxonomy, followed by the separate closure class
  ` / MATERIAL` or ` / NON-MATERIAL` (for example `Severity 1 / MATERIAL` or
  `Low / NON-MATERIAL`). The label is not normalized by this skill; the closure
  class determines whether an unresolved candidate blocks a clean verdict. This
  is used to route validation and closure, not to pre-judge the final finding.
- **Closure links:** an `INCONCLUSIVE` candidate cites its `coverage.md`
  limitation; a `DUPLICATE` cites its canonical `C-NN`/`F-NN`.
- **Disposition:** lifecycle status plus evidence-backed reason.

A vague suspicion is a lead, not a candidate. Complete the schema or record it
in working notes; do not inflate the candidate registry.

Every `INCONCLUSIVE` candidate has exactly one row under `coverage.md` →
`Candidate Limitations`:

| Candidate | Severity / materiality | Status | Blocker / open proof obligation | Required next step | Report verdict |
|-----------|------------------------|--------|---------------------------------|--------------------|----------------|
| C-NN | exact candidate severity/materiality | PARTIAL / OPEN | substantive unresolved fact | concrete closure step | INCOMPLETE for MATERIAL |

`DUPLICATE` uses one exact, non-self `C-NN` or `F-NN` canonical reference. That
record must exist, and the known-issue ledger must bind the same dedup key to it.

## Work-Generated Roles

Roles describe the work an audit needs; they do not require a fixed scheduler:

- **Recon** narrows the scope, records coverage evidence, and converts suspicious
  paths from any discovery method into schema-complete candidates.
- **Hunting** owns one candidate at a time, traces it through real code, and
  creates the smallest faithful evidence package.
- **Gap-filling** examines accepted and rejected outcomes, updates coverage, and
  proposes new work only where a surface or assumption remains untested.
- **Validation** independently checks the candidate by reproducing its procedure,
  using another sound method, or both; deduplicates it; challenges
  scope/reachability/impact/falsification; and recommends a disposition.

Claim ownership by creating one `triage/candidates/C-NN.md` file before
expensive verification work, then run
`bash "$SKILL_DIR/scripts/triage-index.sh" "$WORKSPACE"` to rebuild the shared
index. Per-candidate files are the source of truth; `triage/candidates.md` is a
deterministic generated view and must not be hand-edited. Agents may operate in
parallel, but they share the generated index and known-issues ledger so several
agents do not rediscover the same root cause.

## Verification Evidence Contract

For every candidate intended for acceptance, create
`triage/reproducers/C-NN.md`. The directory name is retained for compatibility;
it stores verification manifests for any method. Put executable artifacts under
`poc/` when used and all proof, trace, log, or analysis artifacts under
workspace-controlled paths such as `evidence/`. The manifest must make these
facts recoverable:

1. the exact `T-NN` artifact-ID set, matching the candidate and resolving to
   target-lock artifacts (the lock SHA-256 field is optional; a recorded value
   must match the current lock);
2. target code revision and a build/profile or other target-identity procedure;
3. chain, deployment/configuration, dependency revisions, target-fidelity grade,
   and a structured immutable/versioned state anchor appropriate to the claim
   (positive block/slot, native transaction digest, object-ID@version list,
   state root, content-addressed snapshot, deployment/source revision, or another
   named pinned value);
4. producer identity/context and evidence revision;
5. one exact execution command or complete review procedure and expected result;
6. actor initial state and acquisition of any required capital/capability;
7. preconditions checked before the claimed sequence or derivation;
8. action sequence or proof derivation;
9. claimed impact/success criterion and method-appropriate falsification or
   control;
10. workspace-relative verification/evidence/control paths that each resolve to a
   retained non-empty artifact, plus environment/tool versions. Their SHA-256
   values are optional for internal review and required under
   `--strict-hashes`; any value you record is verified against the file;
11. known deviations from production state;
12. the repeatability result for executable evidence or proof-review result for
    non-executable evidence.

The three artifact fields may point to the same immutable proof document when it
contains the primary derivation, impact evidence, and falsification analysis.
If a negative control is not meaningful, record why and use the proof artifact
for the control-evidence field; never fabricate a control merely to satisfy a
format.

The manifest is the handoff boundary. A validator should not need an oral
explanation or hidden local state.

## False-Positive Gates

Apply every gate before independent validation. The gates constrain claims, not
verification methods:

### 1. Target-Identity and Build-Fidelity Gate

- Verify that every claim-listed `T-NN` artifact resolves to a retained target
  file and that lock identity agrees exactly with `scope.md`. A lock binds a
  claim to a snapshot; it is not a discovery or validation method. Digests
  strengthen that binding but are optional internally; any recorded digest is
  verified.
- Check chain-native deployment/program/package identifier and digest shape,
  then verify from primary chain/build artifacts that those identifiers actually
  correspond to the claimed revision, code and state. Hash/string consistency
  alone cannot establish that association.
- Confirm the behavior exists in the production build/profile and scoped
  revision, not only with debug assertions, test features, mocked guards, or a
  non-deployable configuration.
- Record compiler, feature flags, optimizer/profile, package/program/bytecode
  identity, and build command.
- If any identity field or target artifact changes, revalidate every affected
  candidate, manifest, validation, and finding against the new target, and
  refresh any digest that was recorded. Do not bulk-replace stale digests
  without re-checking the claim — that converts a detected drift into a silent
  one.

### 2. Actor-and-Reachability Gate

- Trace from the stated threat actor, capabilities, and real entry/trigger to the
  effect. Permissionless reachability is required only when the claim says the
  actor is permissionless.
- Prove every intermediate state and input can arise through real supported
  transitions.
- Reject tests that directly mutate storage/accounts/objects into an impossible
  state unless that mutation faithfully reconstructs pinned deployed state and
  is documented as such.

### 3. Impact-and-Falsification Gate

- Assert the claimed security consequence, not merely that a call returned or a
  transaction completed.
- For fund loss, measure net attacker gain and victim/protocol loss after fees,
  repayments, and initial funding.
- For authorization, assert an unauthorized state transition or capability.
- For liveness, assert failure of a legitimate path under reachable conditions.
- Use a negative control when meaningful: remove the attack step, apply the
  proposed fix, or use a safe boundary value. Otherwise challenge the proof with
  counterexamples, alternate semantics, missing paths, and unstated assumptions;
  record why the chosen falsification is discriminating.

### 4. Provenance-and-Repeatability Gate

- Pin code, state/block/version, dependencies, and toolchain to the extent the
  claim depends on them.
- For executable evidence, establish repeatability appropriate to the method.
  For formal/source proofs, preserve the proof obligations and review trail.
- Preserve the exact command or review procedure, artifacts, and result. The
  artifact must exist and be readable in the workspace; content-addressing it is
  optional internally.

### 5. Deduplication Gate

- Search `triage/known-issues.md`, recorded findings, upstream advisories, and
  earlier candidates.
- Two manifestations are duplicates when they share the same root cause,
  violated invariant, and affected sink. Link variants rather than inflating the
  finding count.

### 6. Cost-Impact Gate

- Quantify attacker capital, permissions, timing/ordering, repetitions, fees,
  liquidity, and opportunity cost.
- Compare them with extractable value, victim loss, protocol insolvency,
  governance/control impact, or liveness impact.
- State explicitly whether the claim reaches **loss of funds or assets** —
  extraction, unbacked mint, insolvency, or permanent lock of user assets. That
  answer, not the cleverness of the mechanism, is what admits a finding to
  Critical or High (`methodology.md § I`), and an asset-loss claim is
  `MATERIAL` for closure purposes.
- Keep severity, deployment exposure, and evidence confidence separate.

## Multi-Step and Stateful Candidates

LLMs may propose action sequences, but the proposal alone is not evidence. For
cross-function, PTB, atomic-transaction, epoch, oracle, governance, liquidation,
or repeated-rounding candidates:

1. represent allowed actions, actors, and preconditions faithfully;
2. establish the full sequence with a suitable method: stateful testing,
   fuzzing, model checking, symbolic execution, formal transition proof,
   historical trace, simulation, replay, or another sound technique;
3. check the invariant at relevant intermediate and terminal states;
4. preserve the sequence, derivation, and state dependencies; minimize a
   counterexample when that improves reviewability;
5. state exactly what the evidence establishes and what remains assumed.

Do not replace evidence with a bare assertion that the sequence "should" be
reachable. A rigorous source/formal derivation is evidence; unsupported prose is
not.

## Independent Validation Protocol

The validator starts from the registry, target lock, manifest, and immutable
artifacts—not the producer's unstated live context:

1. verify the claim-specific `T-NN` set against the lock's artifact manifest,
   exact lock/scope identity match, target fidelity, and provenance — plus any
   digest the record does claim;
2. open the primary artifacts and inspect the documented execution/review
   procedure; rerun or re-review it, use a different sound method, or do both,
   and record which;
3. independently trace the stated actor and entry/trigger to the claimed effect;
4. inspect setup for impossible state, hidden privilege, and pre-funding;
5. challenge the impact criterion and method-appropriate falsification/control;
6. verify dedup key and known-issue search;
7. recompute attacker cost and protocol/user impact;
8. record the result in `triage/validation/C-NN.md` without rewriting the
   producer's original evidence;
9. recommend `INDEPENDENTLY-VALIDATED`, `REJECTED`, `DUPLICATE`,
   `OUT-OF-SCOPE`, or `INCONCLUSIVE`.

Disagreement is useful triage evidence. Record both analyses and the precise
unresolved fact; do not average conclusions.

## Recording a Finding

A candidate enters `findings.md` on the strength of its proof. Recording requires:

- schema complete;
- candidate, verification manifest, independent validation, and finding agree on
  the exact claim-specific `T-NN` set and target identity (and on the lock digest
  wherever one is recorded);
- self-contained verification evidence against real scoped code, with every
  referenced artifact retained and openable in the workspace;
- all false-positive gates passed;
- independent validation recorded;
- known-issue/dedup check complete;
- cost-impact analysis complete, including the explicit asset-loss answer.

No human decision is needed to reach this point, and none of these obligations may
be waived by one either.

## Report Sign-off

Before issuing any report — internal reference or external delivery — a human
auditor records the acceptance decision, final severity, and disclosure decision
for each finding (`Human decision` in `findings.md`, `Human decision / acceptor /
date` in the validation record, candidate status `HUMAN-ACCEPTED`). This is where
human judgment belongs: what gets released, under which severity label, to whom.
It reviews the evidence; it does not substitute for it.

Run the checker at each of the two gates:

```bash
# Findings gate — evidence, validation, closure. Digests optional.
bash "$SKILL_DIR/scripts/triage-check.sh" "$WORKSPACE"

# Report gate — additionally requires human sign-off on every finding.
bash "$SKILL_DIR/scripts/triage-check.sh" --report "$WORKSPACE"

# External/client delivery — also require every integrity digest.
bash "$SKILL_DIR/scripts/triage-check.sh" --report --strict-hashes "$WORKSPACE"
```

The default final mode fails on an out-of-date generated index, non-substantive
or divergent scope/target-lock identity, unresolvable target artifacts, stale
`T-NN` bindings or mismatched recorded digests, malformed native deployment
identifiers or state anchors, non-numeric or arithmetically inconsistent
coverage, unstructured material `INCONCLUSIVE` closure, invalid duplicate
canonicals, non-terminal candidates, duplicate accepted keys,
missing/out-of-workspace/hash-mismatched evidence, incomplete recorded findings,
cross-section evidence links, and obvious
candidate/evidence/validator/human-decision contradictions.
`--report` adds the human sign-off requirement; `--strict-hashes` adds the
integrity-digest requirements. `--bootstrap` is only for checking the structure of
a newly initialized empty workspace. Script success is a mechanical precondition,
not a substitute for independent review or human judgment.

Claims about a live deployment additionally require evidence bound to the
deployed target and relevant state as defined in `SKILL.md` Phase 8. Replay is
one possible method, not a requirement. Preserve the more limited evidence grade
whenever target/state correspondence remains open.

Every severity still needs reviewable evidence. A focused regression test,
trace, transaction analysis, symbolic/formal result, source-level proof, or any
other sound method may suffice, but unsupported prose does not enter
`findings.md`.

## Metrics and Closure

Report at least:

- candidates proposed;
- candidates with verification evidence;
- independently validated;
- findings recorded (validated candidates in `findings.md`);
- human signed off (subset of recorded findings cleared for reporting);
- rejected;
- duplicate;
- out of scope;
- inconclusive;
- unresolved by severity potential, and how many of those claim asset loss;
- validation rate = `findings recorded / dispositioned non-duplicate candidates`.

Use the validation rate as a quality signal, not a target to game. Large candidate
volume with few recorded findings usually indicates a broad scope, weak candidate
schema, or missing false-positive gates. Narrow attack surfaces and explicit
oracles usually improve useful throughput. A gap between findings recorded and
human signed off is normal mid-engagement and blocks only reporting.

An audit cannot claim clean closure while a material candidate is unresolved or
while a material obligation/surface selected by the audit has neither a
candidate disposition nor documented no-issue evidence. Carry all such gaps into
`coverage.md` and the final report limitations.
