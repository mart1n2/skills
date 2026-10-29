# Audit-lite: independent review inside the dev loop

A light profile of the `contract-security-audit` skill (installed next to this one, for example `~/.claude/skills/contract-security-audit`). The method is unchanged: goal-directed search, evidence-bound candidates, a falsification attempt, independent validation, an asset-loss gate on severity. The consumer changes: findings go back to the implementing agent as test-backed feedback, not into a signed report. Use the full skill for an external or pre-mainnet report.

Independence means a fresh context that never sees the implementer's reasoning. An author reviewing their own fix tends to confirm it; in practice, fixes trusted by their author introduced new findings that only an agent who had not written them caught.

## Roles

| Role | Gets | Never gets | Produces |
|---|---|---|---|
| Auditor | spec and requirement IDs, invariants, dependency table, code at a commit, diff range | implementer's notes, PR description, chat, prior conclusions | candidates with PoC tests |
| Validator | candidate files, PoC tests, code, spec | the auditor's reasoning beyond the candidate file | a verdict and severity per candidate |
| Retester (after fixes) | fix diff, the findings it claims to close, full suite | the implementer's explanation | closed / not closed per finding, new candidates from the fix |

- Each role is a separate fresh subagent; in a runtime without subagents, a separate fresh session (for example a non-interactive `codex exec` or `claude -p` run) given only that role's inputs.
- **Models:** PR audits use the implementer's model. Milestone audits run two auditors on different models and take the union, then each model validates the other's candidates. In one measured run on a real codebase with seven known issues, each auditor alone found three or four, the union five, and each found one issue the project only discovered later.
- **Isolation:** auditors and validators work in their own git worktree at the audited commit, so PoCs never land in the implementer's tree until a fix ships them.
- A validator reruns the PoC, tries to falsify it and challenges reachability and impact; reading and agreeing is not validation. It judges against the spec, not against code comments or the implementer's design notes. "The comment says it is intended" is not a rejection; when the spec is silent, the result is a spec-layer finding ("decide and write the intended behaviour"). Behaviour the spec explicitly accepts is `REJECTED` as a defect and noted as intended.
- Auditor/validator disagreements follow "When the loop stops" in SKILL.md.

## Modes and cadence

- **Design review** (before Gate 1 and before Gate 2): inputs are the original requirements, the enriched PRD and the architecture options or chosen design, never the author's reasoning. Candidates: contradictions, untestable requirements, missing failure paths, trust assumptions, and actors who gain or lose unfairly. Evidence is a numeric simulation of each actor's outcome (early and late entrants, first mover out, exiting LP, keeper, liquidator) in normal, stressed and default cases, or a prototype run on a fork. Confirmed findings become gate questions or changed options. This mode catches economic design defects that no code audit finds.
- **PR audit:** every PR touching `src/`, deploy scripts or runbooks. Scope is the diff plus what it can affect: transitive callers, shared storage, invariants reading changed state, external assumptions it relies on.
- **Milestone audit:** before deployment, before an external audit, after a large feature merges. Whole system, all invariants, deploy scripts and runbooks.

## What to load from contract-security-audit

- `SKILL.md`: the five axioms; Phase 8 triage acceptance gates and claim-to-evidence grades; Phase 9 asset-loss gate.
- `references/goal-directed-search.md` §3 to §6.
- `references/methodology.md`: the Hypothesis Ladder, B Boundary Cases, E Trust Boundary, F Negative Space, H Failure-Mode Catalog, X Cross-Boundary Logic, J Business-Logic & Economic-Design, and the PoC Pattern Library.
- `references/triage.md`: Candidate Schema, False-Positive Gates 2, 3, 5, 6, Independent Validation Protocol (validator only).

Skipped: target lock and artifact IDs (the git commit binds), digests, source fetching and on-chain collection, the reachability atlas (optional at milestones), report templates, per-finding human sign-off, disclosure.

**Vocabulary** (from triage.md): auditor status `PROPOSED`, `REPRODUCED` or `INCONCLUSIVE`; validator verdict `INDEPENDENTLY-VALIDATED`, `REJECTED`, `DUPLICATE`, `OUT-OF-SCOPE` or `INCONCLUSIVE`; evidence grade `CONFIRMED-LOGIC` for code not yet deployed (state whether mocks or a fork were used) or `CONFIRMED-DEPLOYED` for a deployed system at a pinned state. "Confirmed finding" in SKILL.md means `INDEPENDENTLY-VALIDATED`.

## Workflow

1. **Goals.** Start from the invariants and requirement IDs and search backward for what breaks each; search forward from real actors (anyone, depositor, keeper, privileged roles, third-party admins, a donor of dust). Walk the adversary checklist. Treat every runbook and bot step as code: which values it reads, and what a griefer can make it revert on.
2. **Candidates.** One file per candidate in the audit worktree's `audit-workspace/<scope>/candidates/C-NN.md`: commit, actor and preconditions, mechanism, violated invariant or requirement ID, claimed impact in assets, falsification plan, dedup key.
3. **PoC.** A Foundry test from the real entry point, a fork test when a third party is involved (public RPC is fine locally), named `test_Audit_C_NN_<what>`. It **asserts the violated property**, so it fails on the audited code, and has a negative control (the same flow without the attack) that passes. Assert the fund effect, not just a revert.
4. **Falsify**, then **validate**: realistic configuration, real third-party behaviour, spec intent. A failed reproduction is `INCONCLUSIVE`; only evidence that disproves a precondition or the impact makes it `REJECTED`.
5. **Feedback** to the implementer in the format below. The implementer copies the PoC file from the audit worktree into its own tree as part of the fix.
6. **Fix and retest.** The PoC is committed in the same commit as the fix, renamed `test_Regression_<behaviour>` and otherwise unchanged; it is green from then on. The finding ID goes in the commit message, the test's doc comment and the findings index, never in `src/` comments. The retester checks every claimed fix and hunts the fix diff for new candidates. Rounds end per "When the loop stops".
7. **Accepted risk.** The PoC is inverted to assert the accepted behaviour (so it stays green and documents the risk), and the risk goes into the findings index and the README's known risks with its reason. If accepting it changes a requirement, it is a spec delta and needs a gate.

## Severity and the human

Severity comes only from the asset-loss gate: Critical and High require a path to loss or permanent lock of assets; otherwise Medium at most.

- **Stop for the human:** every Critical or High. A project may additionally set a size threshold in its CLAUDE.md (for example "any loss of at least 1% of a vault or 100k USD") that also stops the loop; it never lowers a severity.
- **Agent decides, then reports:** code-layer findings at Medium and below (fix or accept; Low and Info may also be deferred to the index). A spec- or design-layer finding at any severity goes through a spec delta and one human gate.

## Feedback format

```
F-NN · <severity> · layer: spec | design | code | test | deploy
violates: <requirement or invariant ID>
actor / preconditions: ...
mechanism: <two or three sentences>
impact: <assets, amount or share, permanent or temporary>
PoC: <audit worktree>/test/<path>::<test> · run: forge test --mt <test> [--fork-url ...]
verdict: INDEPENDENTLY-VALIDATED · evidence: CONFIRMED-LOGIC (mock | fork) | CONFIRMED-DEPLOYED
```

Give the violated property, not a patch: a prescribed patch anchors the implementer and invites a fix that turns the test green without restoring the property. A spec or design layer means a spec delta first (SKILL.md, "Loop back to the right layer").

## Records

- The findings index (`docs/findings.md`, committed): ID, severity, layer, status (open, fixed, accepted, rejected), fixing commit, regression test.
- Candidate and validation files stay in the local, gitignored `audit-workspace/`.

## Cost

PR audits stay cheap: diff and blast radius only, no atlas. Milestone audits are the expensive pass (about 340k tokens per full-scope auditor and 150k to 190k per validator on a codebase of about a dozen contracts); run them deliberately.
