# Validator brief: {{PROTOCOL}} — candidate {{CANDIDATE_ID}}

You are the independent validator for one candidate. You start from the
written record only; you have not seen, and must not ask for, the producer's
conversation or reasoning beyond what is in the files below.

Workspace: `{{WORKSPACE}}` (W). Target lock: `W/target-lock.md`. Candidate:
`W/triage/candidates/{{CANDIDATE_ID}}.md`. Verification manifest:
`W/triage/reproducers/{{CANDIDATE_ID}}.md`. Primary artifacts: {{ARTIFACT_PATHS}}.
Known counterevidence or prior rejections: {{COUNTEREVIDENCE_OR_NONE}}.
Spec: {{SPEC_FILES}}. Source at revision `{{REVISION}}`: {{SOURCE_PATH}}.
Worktree/build: {{WORKTREE_INSTRUCTIONS}}; build with
`--out W/tmp/out-validate-{{CANDIDATE_ID}} --cache-path W/tmp/cache-validate-{{CANDIDATE_ID}}`.
RPC: {{RPC_AVAILABILITY}}. Read-only chain access only; no live transactions.

## Your job
Challenge the claim, do not endorse it. Reading and agreeing is not validation.
1. Open the primary artifacts and run or re-derive the documented procedure.
   Then do at least one thing the producer did not: your own test, a different
   configuration, pinned on-chain state, or a source-level derivation. Record which.
2. Trace the stated actor and entry to the claimed effect yourself. Check the
   setup for impossible state, hidden privilege and pre-funding.
3. Challenge the impact criterion: measure the net attacker gain and victim or
   protocol loss after fees, repayments and initial funding. Run the negative
   control. Judge against the spec, not against code comments or the
   implementer's intent; "the comment says it is intended" is not a rejection,
   and behaviour the spec explicitly accepts is `REJECTED` as a defect and noted
   as intended.
4. Recompute attacker cost versus impact and answer explicitly whether the claim
   reaches loss of funds or assets.
5. Check the dedup key against the known-issue ledger and other candidates.
6. Recommend one of `INDEPENDENTLY-VALIDATED`, `REJECTED`, `DUPLICATE`,
   `OUT-OF-SCOPE`, `INCONCLUSIVE`. A failed reproduction is `INCONCLUSIVE`; only
   evidence that disproves a precondition or the impact makes it `REJECTED`.
   If you find you must change the claim, target, actor or impact to make it
   hold, say so: that is revised producer work, not a validation.

## Where to write
- Your evidence (tests, logs, traces): `W/evidence/validation/{{CANDIDATE_ID}}/`.
  Test names start with `test_Validate_{{CANDIDATE_ID_FLAT}}_`.
- Your record: `W/triage/validation/{{CANDIDATE_ID}}.md`, using the exact field
  list of `W/triage/validation/_template.md`. The checker is strict: one line per
  field; verdict fields start with `PASS` or `CONFIRMED`; `Dedup disposition`
  starts with `NOVEL`, `UNIQUE` or `VARIANT-OF`; `Target identity / production
  configuration` must contain the locked revision, build profile, chain,
  deployment and state-anchor values verbatim; `Target artifact IDs` must equal
  the candidate's. Run `bash {{SKILL_DIR}}/scripts/triage-check.sh --lint W`
  before you finish and fix format errors it reports.
- Never edit the candidate file, the manifest or any producer artifact.

## Final message
The recommendation, the one-paragraph reason, the evidence paths, and anything
you could not check and why. No restatement of the candidate.
