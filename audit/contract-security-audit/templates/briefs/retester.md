# Retester brief: {{PROTOCOL}} — fix round {{ROUND}}

You check whether a fix closes the findings it claims to close, and whether it
introduces new defects. You have the diff and the findings; you do not have,
and must not ask for, the implementer's explanation.

Workspace: `{{WORKSPACE}}` (W). Baseline revision `{{BASE_REVISION}}`; fix
revision `{{FIX_REVISION}}` (diff: {{DIFF_RANGE_OR_PATH}}). Findings claimed
closed: {{FINDING_IDS}} (records in `W/findings.md`, PoCs in `W/poc/`, evidence
in `W/evidence/`). Spec: {{SPEC_FILES}}. Worktree/build: {{WORKTREE_INSTRUCTIONS}};
build with `--out W/tmp/out-retest-{{ROUND}} --cache-path W/tmp/cache-retest-{{ROUND}}`.
RPC: {{RPC_AVAILABILITY}}.

## Per finding
1. Run the finding's original PoC against the fixed code. Closed means the
   exploit assertion now fails for the right reason and the negative control
   still passes. A test that is green because the entry point reverts for an
   unrelated reason, or because the test was weakened, is not closed.
2. Check that the stated property is restored, not just the test: re-derive the
   violated invariant or requirement ID against the new code; try the obvious
   variants (different amounts, ordering, a second actor, the sibling function).
3. Record the result as a retest line the checker accepts:
   `reviewer={{YOUR_IDENTITY}}; date={{DATE}}; method=<what you ran or derived>; evidence=<W-relative path>; result=<original mechanism closed | violated property holds | ...>`
   or `not closed` with the evidence that shows the residual path.

## The fix diff itself
Hunt the diff as new code: every changed function, its transitive callers,
shared storage, invariants that read changed state, and external assumptions it
relies on. Any new candidate gets a `test_Audit_Retest{{ROUND}}_*` PoC in
`{{TEST_DIR}}/Retest{{ROUND}}Audit.t.sol`, log in `W/evidence/retest-{{ROUND}}.log`,
and is reported in the hunter report-back format (title, locator, actor,
mechanism, quantified impact, asset-loss yes/no, severity, test, falsification,
dedup).

Do not modify `src/`, `script/`, docs or existing tests. Do not commit, push or
change git state.

## Final message
Per finding: closed / not closed, evidence path, and the retest line. Then new
candidates (if any) in the report-back format, then leads, then what you could
not run and why. No padding.
