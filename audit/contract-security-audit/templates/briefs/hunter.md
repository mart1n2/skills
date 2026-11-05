# Hunter brief: {{PROTOCOL}} — surface: {{SURFACE}}

Target: {{REPO_OR_SOURCE_PATH}} at revision `{{REVISION}}` (chain: {{CHAIN}}).
Workspace: `{{WORKSPACE}}` (W below). Work in your own checkout/worktree
detached at that revision: {{WORKTREE_INSTRUCTIONS}}. Never print `.env` values.
RPC for forks: {{RPC_AVAILABILITY}} (use `--threads 1` on rate-limited providers).

## What the system is
{{ONE_PARAGRAPH_SYSTEM_SUMMARY}}

Spec and intent sources, in order of authority: {{SPEC_FILES_WITH_REQUIREMENT_IDS}}.
Operations/runbooks: {{RUNBOOK_FILES}}. Project rules: {{PROJECT_RULE_FILES}}.
Other project documents you may read as intent evidence (README, NatSpec,
design notes that are part of the spec): {{OTHER_INTENT_DOCS_OR_NONE}}.
Do NOT read: `audits/`, `audit-workspace/*/reports`, prior review notes, commit
messages, PR descriptions, or any chat or notes from the people who wrote the
code. Form your own view.

## Already known (do not re-report; check the fix instead)
{{KNOWN_ISSUES_LIST}}  <!-- F-NN: one line each, with the fix commit or the spec clause that accepts the risk; write "none" for a first audit, and then dedup is against your own candidates only -->
An accepted risk recorded in the spec is not a finding unless the recorded
acceptance is wrong about the mechanism or its bound.

## Your surface
Files: {{FILES_IN_SCOPE}}. Seams shared with other surfaces (check both sides of
each): {{SEAMS}}.

Invariants and requirement IDs to attack (non-exhaustive): {{INVARIANTS_AND_IDS}}.
Search backward from each violated property to what must be true for it to
fail, and forward from every real actor (anyone, depositor, keeper, privileged
roles within their powers, third-party admins, a donor of dust, a failing or
paused dependency) to its consequences. Treat runbook and bot steps as code:
what each reads, and what a griefer can make it revert on. A spec/code mismatch
with a security effect counts; style, gas and NatSpec do not.

## Proving a candidate
For every candidate you believe is real, prove it with a test from the real
entry point:
- File: `{{TEST_DIR}}/{{AREA}}Audit.t.sol` (create it; reuse existing fixtures and
  mocks where they exist, otherwise write the smallest mock that models only the
  external behaviour the claim depends on, in the same file or next to it).
  Test names start with `test_Audit_`. The test asserts the violated
  property (fund effect, not just a revert) and has a negative control: the same
  flow without the attack, which passes.
- Build with your own dirs so parallel agents do not collide:
  `{{BUILD_COMMAND}} --out W/tmp/out-{{AREA}} --cache-path W/tmp/cache-{{AREA}}`
- Save the run log to `W/evidence/{{AREA}}-poc.log` and copy the test file to `W/poc/`.
- Try to falsify each candidate: realistic configuration, real third-party
  behaviour, spec intent. A failed reproduction is a lead, not a finding.
- Do NOT modify `src/`, `script/`, docs or existing tests. Do not commit, push or
  change git state.

## Report back (your final message, nothing else)
Per candidate:
```
title · file:line
actor and privileges needed · preconditions
mechanism (steps)
impact, quantified from the test · reaches loss of funds/assets: yes|no
proposed severity (Critical/High only with a path to loss or permanent lock of assets)
test name · log path · pass/fail
falsification result
dedup: vs known issues, spec-recorded accepted risks, your other candidates
```
Then, separately: leads you could not prove (`INCONCLUSIVE`, with the exact
blocker), and surfaces you checked and found sound (one line each). Be precise;
no padding. Unproven speculation goes only in the leads list.
