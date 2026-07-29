<!--
DEFAULT INTERNAL REFERENCE REPORT TEMPLATE

Use this file for the default audit output. It summarizes candidate provenance,
target IDs, evidence references, triage closure, findings, and coverage for the
audit team. It is not publication-ready and must not be delivered externally
without an explicit conversion/disclosure review. Generate
`external-audit-report.md` only when the user explicitly requests an external,
client-facing, public, or professional report. The canonical internal record
remains the workspace artifacts. Retain all audit-relevant workspace data,
including needed `tmp/` artifacts.
-->

# Smart Contract Security Audit — {PROTOCOL_NAME}

| Field | Value |
|-------|-------|
| Protocol | {PROTOCOL_NAME} |
| Chain | {CHAIN} |
| Contracts | {CONTRACT_ADDRESSES} |
| Audit window | {START_DATE} – {END_DATE} |
| Auditor | {AUDITOR} |
| Source-of-truth | {GIT_COMMIT_OR_DEPLOYED_BYTECODE} |
| Target lock | {`audit-workspace/{protocol}/target-lock.md` + SHA-256} |
| Discovery and validation methods | {manual / agents / SAST / fuzz / symbolic / formal / differential / transaction or trace analysis / simulation / replay / source proof / other}; independent evidence-triage gate; chain references: metrics-{CHAIN}.md |

---

## Executive Summary

**Verdict:** {NO-MATERIAL-FINDINGS / FINDINGS-PRESENT / INCOMPLETE}

**Headline accepted findings:**
- {CRITICAL/HIGH summary, 1 line each}

**Accepted evidence distribution:** {CONFIRMED-DEPLOYED: N / CONFIRMED-RECONSTRUCTION: N / CONFIRMED-LOGIC: N / no accepted findings}. List every material finding below with its own grade; strong evidence for one finding does not upgrade the others.

**Scope coverage:** {N} pinned target artifacts; {M} method-defined security obligations/surfaces. Open material coverage rows: {0 / count and link}.

**Triage closure:** {A} accepted / {D} dispositioned non-duplicate candidates ({acceptance rate}%); material inconclusive candidates: {0 / count and IDs}.

---

## Scope

### In scope
- {Contract 1}: {address / file path} — {role}
- {Contract 2}: …

### Out of scope
- Off-chain components (frontend, key management, signer operations)
- {Other explicit exclusions}

### Methods and environment
- Discovery methods: {methods, versions/configuration, exact scope, raw artifact links}
- Validation methods: {methods, versions/configuration, proof/test/trace/simulation artifacts}
- Build/source identity: {forge / anchor build+verify / sui build+verify-source / other / not applicable with reason}
- Target revision / deployed digest: {commit + bytecode/package/program hash}
- Production build/profile: {exact release build command, compiler, features/optimizer}
- State/config anchor: {block/slot/object versions or pre-deployment revision}
- Target-lock SHA-256: {digest of complete `target-lock.md`}
- Target artifact manifest: {`T-NN` → workspace-relative path + SHA-256 + role}
- Deployment-identity evidence: {primary chain/build artifact proving the
  chain-native ID, deployed digest, revision and pinned state correspond}

Target identity in `scope.md` and `target-lock.md` matches exactly. Every
evidence-bearing claim below names the lock digest and exact `T-NN` subset it
depends on. If target identity or artifact content changed during the audit,
record the new lock and which claims were revalidated; do not silently replace a
stale digest.

No method is excluded or accepted by label. Each finding below states what its evidence proves, its falsification result, and its residual assumptions.

---

## Triage Summary

| Disposition | Count | Candidate IDs / evidence |
|-------------|-------|--------------------------|
| Proposed | {N} | {IDs} |
| Hunting | {N} | {IDs} |
| Verification evidence complete (`REPRODUCED` compatibility status) | {N} | {IDs} |
| Independently validated | {N} | {IDs} |
| Human accepted | {N} | {IDs → F-NN} |
| Rejected | {N} | {IDs + reason links} |
| Duplicate | {N} | {IDs → canonical issue} |
| Out of scope | {N} | {IDs + scope rationale} |
| Inconclusive | {N} | {IDs + blocker} |

**Acceptance rate:** `{human accepted} / {dispositioned non-duplicate candidates} = {%}`. Candidate volume is not treated as success.

**Decision ownership:** Producers: {names/agents}; independent validators: {names/agents}; final human acceptor: {name/role}.

Known/rejected/fixed/duplicate ledger: `audit-workspace/{protocol}/triage/known-issues.md`.

---

## Optional Model Artifacts

Include these or equivalent model artifacts only when they were part of the selected audit method; otherwise omit this section.

### C. Invariants Catalogued

| ID | Invariant | Class | Verification status / method |
|----|-----------|-------|------------------------------|
| INV-1 | {e.g., totalSupply == sum(userBalances)} | Conservation | Verified / Refuted / Open — {method/evidence} |
| INV-2 | {e.g., sharePrice monotonic except on realized loss} | Monotonicity | … |

### D. State Machines

For each lifecycle object, attach a state diagram with edges labeled by guard:

- {Position}: Open → Liquidatable → Liquidated / Closed
- {Proposal}: …
- {Message}: …

### E. Trust Boundaries

| Entity | Compromise | Liveness | Lie | Slow |
|--------|------------|----------|-----|------|
| {Oracle X} | Wrong price → bad liquidation | Reverts → user cannot exit | Stale price accepted (no check) | Heartbeat boundary |
| {Admin multisig} | … | … | N/A | N/A |
| {Upstream protocol Y} | … | … | … | … |

---

## Accepted Findings

Only independently validated, human-accepted candidates appear here. For each finding, include:

### F-{NN}: {Title}

| Field | Value |
|-------|-------|
| Candidate / dedup key | C-{NN} / {root-cause\|invariant\|sink} |
| Target lock SHA-256 | {64-hex digest of `target-lock.md`} |
| Target artifact IDs | {T-01,T-03} |
| Original severity | {engagement or bug-bounty taxonomy label; cite the policy used; never rewrite because of remediation} |
| Classification (optional) | {Reentrancy / Oracle / Access Control / …} |
| Discovery context (optional) | {agent/manual/SAST/fuzz/symbolic/formal/trace/other; optional A.2/B.5/F/G/… mapping} |
| Metric mapping (optional) | {§1.4 [G-10] / §6.4 / …} |
| Current remediation status | Open / Fixed - Verified / Partially Fixed / Acknowledged / Risk Accepted / Not Yet Retested. Only Fixed - Verified is resolved. |
| Current deployment | Confirmed exploitable / conditionally exposed / plausibly exposed / not exposed at pinned state / not deployed / unknown. Confirmed/conditional/plausible/not-exposed deployment-state claims require `CONFIRMED-DEPLOYED` and an immutable state anchor; logic/reconstruction evidence does not establish deployment exposure. |
| Deployment/state anchor | {network + deployment ID + immutable block/slot/checkpoint/object version, or NOT ASSESSED with reason} |
| Evidence verdict | CONFIRMED-DEPLOYED / CONFIRMED-RECONSTRUCTION / CONFIRMED-LOGIC |
| Evidence confidence | High / Medium / Low — explain |
| Independent validator | {identity/context + `triage/validation/C-NN.md`} |
| Human decision | {acceptor, date, rationale} |
| Client response | {exact response or faithful summary + retained source/date, or NOT PROVIDED with date} |
| Remediation baseline | {for Fixed - Verified: `revision=TYPE:IMMUTABLE_ID; manifest=WORKSPACE_RELATIVE_PATH; sha256=64HEX`; otherwise NOT PROVIDED with reason} |
| Retest | {for Fixed - Verified: `reviewer=IDENTITY; date=YYYY-MM-DD; method=UNRESTRICTED_DESCRIPTION; evidence=WORKSPACE_RELATIVE_PATH; sha256=64HEX; result=POSITIVE_MECHANISM_OR_PROPERTY_CLOSURE`; otherwise NOT YET RETESTED with reason} |
| Residual risk | {bounded remaining risk, or NO RESIDUAL RISK IDENTIFIED within stated retest scope} |
| Disclosure handling | {classification/embargo/redaction decision + owner/date, or NOT DECIDED with reason} |

**Target locator:** {source line, bytecode range, instruction, transaction, object version, model obligation, or another exact locator}.

**Description:** What is the bug? Walk the reader from the entry point to the violation.

**Impact:**
- Blast radius: {All funds / capped / single user}
- Reversibility: {Permanent / pause-recoverable / governance-recoverable}
- Prerequisites: {Anyone / requires capital / requires privileged role / requires market state}
- Mempool visibility: {Front-runnable / private}
- Detection latency: {Immediate / delayed / silent}

**Evidence and triage verification:**
- [ ] Target-lock SHA-256 and exact `T-NN` artifact set match the candidate, verification manifest, independent validation, and this finding
- [ ] Every listed `T-NN` digest verifies, and target identity matches `scope.md`
- [ ] Chain-native identifier/digest shape passes, and primary artifacts—not
      string consistency alone—prove the deployment/source/state association
- [ ] Target/revision/build/deployment/configuration identity is bound to the claim
- [ ] Threat-model-valid actor, capabilities, preconditions, transitions, and effect are established
- [ ] Verification manifest exists at `triage/reproducers/C-{NN}.md`; method: {PoC/test/fuzz/symbolic/formal/trace/simulation/replay/source proof/other}
- [ ] Primary artifact or review procedure and SHA-256 are recorded
- [ ] State fidelity and deviations are recorded — block/slot/object versions/digests, bytecode/package hash, dependencies, or explicit non-deployed scope
- [ ] Impact criterion is established: {net loss/gain / authorization / integrity / liveness / governance / other}
- [ ] Method-appropriate falsification/control is recorded, including why a negative control is inapplicable if so
- [ ] Independent validator inspected the primary artifacts and independently challenged the claim, using a rerun/re-review of the documented method, a different sound method, or both, and documented the method and assumptions
- [ ] Dedup and attacker-cost-versus-impact checks passed
- [ ] Human acceptance and severity decision recorded

**Recommendation:** Concrete fix; preferred approach + alternatives if any.

**References:** Primary post-mortems, advisories, specifications, or source
artifacts relevant to the claim. Aggregate incident catalogs are discovery
pointers, not mechanism or loss evidence.

---

## Evidence and Independent-Validation Summary

List every accepted security finding and its result. Any current-deployment claim requires deployed-target/state evidence; no particular PoC format is mandatory.

| Finding / candidate | Evidence method | Artifact or review procedure | Target lock + `T-NN` set + state anchor | Impact criterion / falsification | Independent validator | Human decision | Evidence verdict |
|---------------------|-----------------|------------------------------|-----------------------------------|--------------------------------|-----------------------|----------------|------------------|
| F-1 / C-1 | {historical trace / replay / formal proof / …} | {path+hash or exact review procedure} | {lock hash; T-01,T-03; deployment + pinned state} | {effect + control/counterexample result} | {validator + evidence} | {acceptor/date} | CONFIRMED-DEPLOYED |
| F-2 / C-2 | {source proof / unit test / …} | {path+hash or procedure} | {lock hash; T-02; source/package revision; deviations} | {effect + falsification result} | {validator + evidence} | {acceptor/date} | CONFIRMED-LOGIC |

Verification manifests live under `triage/reproducers/` for compatibility. Executable artifacts may live under `poc/`; proofs, traces, and analyses may live under `evidence/`. Give an exact command or complete review procedure and omit no target/state/dependency fact material to the claim.

---

## Coverage & Closure

Populate from `audit-workspace/{protocol}/coverage.md`.

### Objective Artifact Reconciliation

These rows reconcile mechanically countable audit artifacts. They do not prescribe how vulnerabilities are discovered or validated.

| Artifact class | Expected | Reviewed / resolved | Open | Evidence |
|----------------|----------|---------------------|------|----------|
| In-scope target artifacts | … | … | … | `target-lock.md` `T-NN` manifest, verified artifact hashes, pinned identity |
| Candidates dispositioned | … | … | … | `triage/candidates.md`, per-candidate files |
| Candidates with verification evidence | … | … | … | `triage/reproducers/`, claim-bound evidence |
| Independent validations | … | … | … | `triage/validation/` |
| Material candidate verdicts | … | … | … | candidate closure class, verification, and validation records |
| Human-accepted findings | … | … | … | `findings.md` |

### Method-Defined Security Coverage

Choose coverage obligations/surfaces appropriate to the methods actually used. Add, replace, or remove rows freely; do not invent Atlas, lens, entry, sink, invariant, or economic-loop rows when those are not part of the selected approach.

| Coverage obligation / surface | Status | Evidence / method | Residual blind spots / limitation |
|-------------------------------|--------|-------------------|------------------------------------|
| {method-defined property, surface, state region, trace set, proof obligation, or other unit} | {COVERED / PARTIAL / OPEN / EXCLUDED / NOT-APPLICABLE} | {claim-bound evidence and method} | {remaining uncertainty, or why none remains} |

### Candidate Limitations

| Candidate | Severity / materiality | Status | Blocker / open proof obligation | Required next step | Report verdict |
|-----------|------------------------|--------|---------------------------------|--------------------|----------------|
| {C-NN} | {exact candidate label / MATERIAL or NON-MATERIAL} | {PARTIAL / OPEN} | {unresolved fact} | {closure step} | {INCOMPLETE for MATERIAL} |

### Open assumptions and blocked checks

- {ID · exact unresolved question · why blocked · affected contracts/funds · required next step}

Any material open row or material `INCONCLUSIVE` candidate requires `INCOMPLETE`; it must not be rendered as `NO-MATERIAL-FINDINGS`.

---

## Discovery and Methodology Notes

Document the methods actually used, their configuration and scope, how leads were
triaged, and residual blind spots. The lens sections below are optional prompts;
replace or omit them when another method provides the evidence.

### A. Bypass
- A.1 Entry-point inventory: {summary, count of unprivileged / role-gated / callback}
- A.2 Input validation: {summary}
- A.3 State-change reachability: {summary}
- A.4 Combined-call composition: {summary}
- A.5 Access control reachability: {summary}
- A.6 External call dependency: {summary}
- A.7 State-as-authority back-channel: {summary}
- A.8 Init/deployment race: {summary}
- A.9 Validation/closure: {historical-class cross-check + unresolved items}

### B. Boundary
- B.1 Rounding: {summary}
- B.2 Scaling/decimals: {summary}
- B.3 Accounting invariants: {summary}
- B.4 Zero/dust/max: {summary}
- B.5 Share/asset edges: {summary}
- B.6 Tick/bucket boundaries: {summary}
- B.7 Time boundaries: {summary}
- B.8 Flash-loan amplifier: {summary}
- B.9 Validation/closure: {historical-class cross-check + unresolved items}

### F. Negative Space
- Functions missing access control: {list or none}
- Functions missing input validation: {list or none}
- State changes not emitting events: {list or none}
- Loops without bounds: {list or none}

### G. Differential
- Fork lineage: {upstream + version / not a fork}
- Logic modifications vs upstream: {summary}
- Cross-chain differences: {if applicable}

### H. Failure-Mode Catalog

| Dependency | Stale | Zero | Revert | Sequencer-down (L2 only) |
|------------|-------|------|--------|---------------------------|
| {Oracle X} | … | … | … | … |
| {Token Y} | … | … | … | … |

### X. Cross-Boundary Logic

| Boundary | Unit A | Unit B | Assumption A makes about B | Violating path → sink | Verdict |
|----------|--------|--------|----------------------------|------------------------|---------|
| X.1 cross-function | … | … | … | … | … |
| X.2 cross-contract | … | … | … | … | … |
| X.3 cross-protocol | … | … | … | … | … |

### J. Business-Logic & Economic-Design

| Economic loop | Actor | Intended flow | Value extractable by rational use | Harms (protocol / users / none) |
|---------------|-------|---------------|-----------------------------------|---------------------------------|
| {loop from O.1} | … | … | … | … |

---

## Out-of-Scope Observations

Items beyond source review that should be addressed operationally:

- {e.g., Multisig signer custody}
- {e.g., Frontend DNS / DNSSEC}
- {e.g., Bug bounty status}
- {e.g., Off-chain monitoring}

---

## Disclosure & Remediation Timeline

- {Date}: Audit started
- {Date}: First findings shared
- {Date}: material or exploit-sensitive findings disclosed under the applicable policy
- {Date}: Fixes verified / pending
- {Date}: Public disclosure (per coordinated-disclosure policy)

---

## Appendix A: Tools & Versions

- Compiler: {solc 0.8.x / rustc / Move toolchain}
- Build/verify: {forge build, anchor build --verifiable + anchor verify, sui move build + sui client verify-source, cargo audit vX}
- Fuzz: {Echidna vX, …}
- PoC framework (if used): {Foundry vX, …}
- Chain RPC: {provider, block number anchor}

## Appendix B: References

- Audit Methodology: `references/methodology.md`
- Candidate Triage Contract: `references/triage.md`
- Chain Metrics: `references/metrics-{evm|solana|sui}.md`
- DefiLlama Hacks: https://defillama.com/hacks
- SWC Registry: https://swcregistry.io/
- This protocol's prior audits: {list}

---

**END OF REPORT**
