# Audit-lite: independent audit and verification inside the dev loop

A light profile of the `contract-security-audit` skill (installed next to this skill, for example `~/.claude/skills/contract-security-audit`; source in `audit/contract-security-audit` of the skills repo). The method is unchanged: goal-directed search, evidence-bound candidates, a falsification attempt, independent validation, an asset-loss gate on severity. What changes is the consumer: findings go back to the implementing agent as test-backed feedback, not into a signed report. Use the full skill for an external or pre-mainnet audit report.

## Why independent agents

The implementer's context carries its assumptions. In past projects, fixes trusted by their author introduced new findings (a value mark that a flash deposit could capture, an emergency floor that could be skimmed after a repeg, a decoding revert in a never-revert view), and they were caught only by an agent that had not written the fix. A second auditor's patch for a High finding was still exploitable and was rejected only because someone verified it. Independence here means a fresh context that is never given the implementer's reasoning.

## Roles

| Role | Who | Gets | Never gets | Produces |
|---|---|---|---|---|
| Implementer | the main agent | everything | | code, tests, fixes |
| Auditor (hunter) | a fresh subagent | spec / requirement IDs, invariant list, dependency table, the code at a commit, the diff range | the implementer's notes, PR description, chat history, prior conclusions | candidates, each with a failing PoC test |
| Validator | a second fresh subagent | the candidate files, PoC tests, code, spec | the auditor's reasoning beyond the candidate file | CONFIRMED / INCONCLUSIVE / REFUTED per candidate, severity check |
| Retester | a fresh subagent after fixes | the fix diff, the findings it claims to fix, full suite | the implementer's explanation of the fix | per finding: closed / not closed / new candidates from the fix |

PR audits use the same model as the implementer: independence comes from the fresh context. Milestone audits run **two auditors on different models** (for example Opus and Sonnet) and take the union of their candidates, then each model validates the other's. In a measured run on a real codebase with seven known issues, both auditors found the High; each alone found three or four known issues, the union found five, and each also found one issue the project only discovered later. The roles must be different subagent invocations. A validator that only reads and agrees is not validation: it reruns the PoC, tries to falsify it, and challenges reachability and impact.

The validator judges against the spec and requirements, not against code comments or design notes written by the implementer. "The comment says it is intended" is not a refutation; when the spec is silent, the verdict is a spec-layer finding ("decide and write the intended behaviour"), not REFUTED. Behaviour the spec explicitly accepts is REFUTED as a defect and noted as intended.

## Scope and cadence

- **PR audit (diff scope):** every PR that touches `src/`, deploy scripts or runbooks. Scope is the diff plus everything it can affect: transitive callers, shared storage, invariants that read changed state, and external assumptions the change relies on. A diff-only read is not enough when shared state changes.
- **Milestone audit (full scope):** before a deployment, before an external audit, and after a large feature merges. Whole system, all invariants, deploy scripts and runbooks included.

## What to load from contract-security-audit

The auditor reads these and skips the rest:

- `SKILL.md`: the five axioms (first principles) and the Phase 8 triage acceptance gates and claim-to-evidence grades.
- `references/goal-directed-search.md` §3 to §6: goals and frontier, search operators, semantic meeting, evidence and search control.
- `references/methodology.md`: Optional Hypothesis Ladder (the EVM questions), B Boundary Cases, E Trust Boundary, F Negative Space, H Failure-Mode Catalog, X Cross-Boundary Logic, J Business-Logic & Economic-Design, and the PoC Pattern Library when writing a PoC.
- `references/triage.md`: Candidate Schema (fields), False-Positive Gates 2, 3, 5, 6, and the Independent Validation Protocol (validator only).

Skipped in lite: target-lock and T-NN artifact IDs (the git commit is the binding), SHA-256 digests, source fetching and on-chain data collection (pre-deployment), the reachability atlas (optional, milestone audits only), the report templates, per-finding human sign-off and disclosure.

## Workflow

1. **Goals.** Start from the project's own invariant list and requirement IDs: for each, search backward for conditions that break it. Then search forward from real actors (anyone, depositor, keeper, allocator, guardian, third-party admin, donor of dust). Add the adversary checklist in `checklists.md`. Walk every runbook and bot step as code too: which values it reads (raw balances an attacker can inflate), and what a griefer can make it revert on; both auditors in the measured run skipped the runbook and missed exactly such a finding.
2. **Candidates.** One file per candidate in `audit-workspace/<scope>/candidates/C-NN.md` (gitignored), with: commit, actor and preconditions, mechanism, violated invariant or requirement ID, claimed impact in assets, falsification plan, dedup key.
3. **PoC.** A Foundry test in the project's `test/` tree (fork test when a third party is involved), named `test_Audit_C_NN_<what>`, that drives the attack from the real entry point and **asserts the violated property**, so it fails on the current code and passes once fixed; the same test then becomes the regression test unchanged. Assert the fund effect (attacker gain, victim loss, permanent revert of an exit), not just a revert, and add a negative control (the same flow without the attack) that passes.
4. **Falsify.** Try to kill the candidate: a negative control, the realistic configuration, real third-party behaviour on a fork. Failed attempts to reproduce are INCONCLUSIVE, not refuted.
5. **Validate.** The validator reruns and challenges each candidate and records the verdict and severity.
6. **Feedback.** Return the confirmed findings to the implementer in the format below.
7. **Fix and retest.** The implementer fixes; the retester checks every claimed fix and hunts the fix diff for new candidates; the full suite including invariants and fork runs.

## Severity and the human gate

Apply the asset-loss gate from contract-security-audit: Critical and High require a path to loss or permanent lock of assets; without one, cap at Medium.

- **Stop for the user:** Critical or High findings, that is, where the loss reached is large in share of TVL or in amount. The project may set explicit thresholds (for example "loss of at least 1% of a vault or 100k USD") in its CLAUDE.md; without them, every Critical or High stops for review. Also stop when auditor and validator disagree on whether a finding is Critical or High.
- **Agent decides, then reports:** Medium and below, including fixing, deferring, or recording as an accepted risk. Accepted risks are still written into the project's docs (README or spec) with the reason, so the decision is visible and reversible.

## Feedback format (auditor/validator to implementer)

```
F-NN · <severity> · layer: spec | design | code | test | deploy
violates: <requirement ID or invariant ID>
actor / preconditions: ...
mechanism: <two or three sentences>
impact: <assets, amount or share, permanent or temporary>
PoC: test/<path>::<test name>  · run: forge test --mt <name> [--fork-url ...]
evidence: CONFIRMED-LOGIC | CONFIRMED-RECONSTRUCTION (fork) | INCONCLUSIVE (<blocker>)
```

Give the violated property, not a patch: a prescribed patch anchors the implementer and invites a fix that makes the PoC pass without restoring the property. When the layer is spec or design, the implementer goes back to the spec or ADR first (see "Loop back to the right layer" in SKILL.md).

## After a finding is closed

- The PoC is renamed to a regression test and stays in `test/`; it is adapted when the code changes, never deleted.
- The candidate record stays in `audit-workspace/` (local, gitignored) with the commit that closed it.
- Findings recorded as accepted risks keep their PoC as a test that documents the accepted behaviour.

## Cost control

PR audits stay cheap by keeping scope to the diff and its blast radius and by skipping the atlas. Milestone audits are the expensive pass (in the measured run, about 340k tokens per full-scope auditor and 150k to 190k per validator on a codebase of eleven adapters); run them deliberately, not on every PR.
