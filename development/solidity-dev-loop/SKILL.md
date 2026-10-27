---
name: solidity-dev-loop
description: Development loop for production Solidity / EVM smart contracts that hold user funds - spec and design, acceptance tests first (unit, fuzz, invariant, fork against the real third-party protocols, regression, Halmos), whole-slice implementation, deploy and ops, independent audit and minimal fixes. Use it whenever the user starts, designs, plans, extends or hardens a contract system (vault, adapter, lending pool, collateral, oracle, settlement, governance/timelock, upgradeability), adds a third-party protocol integration or a new asset, writes deploy scripts, asks how to test or verify contracts, or is triaging and fixing audit findings, even if they do not mention a "loop" or "process". Not for one-off Solidity syntax questions or for auditing someone else's deployed protocol (use an audit skill for that).
---

# Solidity development loop

Contracts that hold funds are expensive to get wrong and often impossible to patch. In two real projects most rework came from four sources: third-party assumptions that were never checked on chain, a design-layer decision patched at the code layer, a fix that added more attack surface than it removed, and deploy / ops steps treated as outside the system. This loop pushes decisions early and makes every later step check against something written down.

Guiding principle: **less is more.** The fewest contracts, the least state, the smallest change that meets the spec. Every line of custom code is audit surface.

## How to use this skill

1. Work out which phase the user is in (a new system, a new feature, integration or asset, a test plan, implementation, deployment, or audit findings) and start there. Do not force a finished project back through phase 1, but if the request reveals a design-layer gap, say so.
2. For each phase, produce the artifacts it names, then check the exit gate before moving on.
3. When a later phase finds a problem, classify which layer it came from and go back to that layer (see "Loop back to the right layer").
4. Respect the project's own rules first (CLAUDE.md, spec, requirement IDs). This skill is the default where the project is silent.

Read `references/templates.md` when producing design artifacts, `references/checklists.md` for the adversary, valuation and deploy checklists, and `references/audit-lite.md` before running an audit or verification pass.

## Non-negotiable invariant

**User funds can never be seized or permanently locked.** Every choice below is judged against this. Temporary denial of service is acceptable when a recovery path exists (a timelocked setter, a `migrate` to a successor, another exit route); a permanent lock is not. A liveness fix must never relax a safety bound: "the oracle is stale, so accept any output" turns a stuck epoch into theft.

## Phase 1: Spec and design (the most important step)

**Human in the loop.** This phase is where the human decides; later phases mostly execute. In past projects the costliest rework came from questions settled late: access and API choices changed after the first implementation, a spec scoped to one chain and two assets when the product meant many, an asset listed that had no live market, deferred scope built anyway. So:

- **Keep the original requirements untouched; write an enriched PRD next to them.** The user's requirement document or PRD is the source and is never edited (for example `docs/prd/original.md`). Write `docs/PRD.md` from it: every statement made explicit (actors, flows, numbers, states, failure cases, non-goals), each traced to the original section it came from, and everything you added marked as derived or as an assumption linked to an open question. The original shows what was asked; the enriched PRD shows what will be built; the gap between them is the list of things the human must confirm.
- **Derive the open questions from the document, not from a generic list.** Read the original for vague words ("safe", "fast", "low risk"), missing numbers, undefined actors or roles, flows with no failure path, statements that conflict, implicit assumptions about third parties, and anything the product clearly varies (assets, chains, number of vaults). Each becomes a question with its source pointer, the options and your recommendation. Do not resolve a business question by guessing and moving on.
- **The human decides business and risk; the agent decides engineering defaults.** The generic floor of human decisions, which the PRD questions extend: scope and what is deferred, users and trust model, roles and who holds them, assets, chains and venues, risk appetite (caps, ceilings, LTV, slippage), economics and fairness rules, upgrade model, timelock lengths, which third-party risks are accepted. Agent: choices with a conventional answer (library, rounding direction, naming, test layout), stated in the spec so the human can overrule them.
- **Ask in batches, with a recommendation.** Group the open questions by topic, give the options, the consequence of each and your pick first; do not ask one question per turn, and do not ask what the code, the docs or a fork read can answer.
- **Record every answer in the spec** (a decision log with date and the reason), and update the requirement it changes, so the decision is not re-argued later.
- **The human confirms the enriched PRD, then signs off the spec (TRD) before phase 2.** The TRD's requirement IDs trace back to enriched-PRD sections, and those to the original. Present the finished spec with the remaining assumptions highlighted; the agent never self-approves it. After sign-off, a change to a requirement, a role, a parameter range or the accepted risks goes back to the human; a fix that stays inside the signed spec does not.

Artifacts:

1. **Requirements as testable items with IDs** (for example `CARRY-05`). Tests, docs and findings cite them. If the spec conflicts with itself or with reality, stop and ask; do not guess.
2. **Role and permission matrix**: every privileged function, who may call it, with what delay, and whether it can only reduce risk. Get it signed off before implementation; access and API choices changed after the first implementation are expensive. Check that no role can veto its own removal.
3. **What is not built.** Deferred features and the trigger that forces them in. Do not build deferred scope "while we are here". Keep the design generic where the product already varies (asset, decimals, chain, number of vaults), so configuration is data.
4. **Reuse before building.** Map every component to an audited library or existing protocol (OpenZeppelin, Solady, an unmodified upstream vault). Custom code is only glue. This includes governance: `TimelockController` or `AccessManager`, not hand-built stage/execute pairs.
5. **Verify every third-party assumption on a fork before freezing the design.** Run a short spike against the real deployed contracts at a pinned block: does the token actually output what you assume, is the market active, does the call accept a whole-balance amount, what does the keeper really execute, which parameters can the protocol's admins change. Designs built only on mocks have shipped with a default path that could never work and an oracle that did not exist.
6. **Formula table.** Every formula, its rounding direction (assets down, debts up, always favouring the protocol) and the library that implements it (`Math.mulDiv` with `Rounding`, Solady `FixedPointMathLib`, `SafeCast`, ERC-4626 conversions). A formula with no library is a top review and Halmos target.
7. **Valuation rule.** Value positions at what the exit actually returns (swap output, redemption rate from protocol state), not at an oracle mark, and measure the chosen feed against the market on a fork. Write a degraded-mode matrix: for each external read, what each function does when it fails, is stale, or returns garbage. See `references/checklists.md`.
8. **Economic review per actor.** For each actor (early and late depositor, first mover out, LP exiting, borrowers of different tenors, keeper, liquidator), what they gain or lose in normal, stressed and default scenarios. Back each fairness claim with a numeric example or PoC. Mutualised losses, phantom NAV and floating rates on fixed-term debt are design bugs, not tuning.
9. **Upgrade model, chosen from the business.** Immutable, immutable plus timelocked setters, immutable core plus replaceable modules (`migrate`), or proxy. Decide from the users' trust model, logic maturity, integration churn, need for emergency fixes, and re-audit / migration cost; record the reason. Whatever the model: no power can move user funds, changes go through a timelock, users get an exit window longer than the timelock, upgrade and operations roles are separate.
10. **Third-party dependency table.** For each protocol, oracle, router, keeper: what its admins can change, through what delay, the worst case for our exits, and our recovery. Permanent lock means redesign; bounded DoS with recovery is fine. Dependencies are not only code: liquidity migrates, markets die, risk parameters get cut, assets depeg.
11. **Recovery paths are features.** `migrate`, emergency setters, write-off and impairment paths get the same threat model and tests as the main flow; they are used in the worst conditions (feeds down, venue paused) and are a common source of new bugs.
12. **Exit path and exit liquidity.** Trace how funds leave in every state. The exit must not depend on a price read or replaceable contract that can fail for good unless a timelocked setter or `migrate` restores it. Measure real depth for the exit route at the sizes you intend (for example quotes at 1M and 5M), across all positions that share the same route or underlying, and derive caps from it. Illiquidity is a lock too.
13. **Adversary model.** Walk `references/checklists.md`: donations and dust to any address (never infer state from raw `balanceOf`), flash and same-block deposits, reentrancy including read-only via callbacks, repeated calls against per-call caps, griefing that blocks batches, caller-supplied routes and calldata, reused approvals. Every caller-supplied input is hostile: enforce floors and arrival checks in the contract.

**Exit gate:** the open-questions list is empty or every remaining item is an explicit, human-accepted assumption; the human has signed off the spec; every requirement answers "how is this tested"; every third-party assumption was checked on a fork; every dependency answers "worst case for exits and recovery"; every formula maps to a library or is flagged; the role matrix, valuation rule, economic table and upgrade model have written reasons.

## Phase 2: Acceptance tests first

Turn the requirements into tests before implementing. All layers:

| Layer | Write first | Catches |
|---|---|---|
| Unit | Happy path and every revert path per requirement ID, exact error selector | Logic, access control |
| Fuzz | Amounts, decimals, prices, timestamps; `bound()` over `vm.assume()` | Boundaries, rounding, overflow |
| Invariant | Accounting equals real positions; every holder can exit; full exit leaves zero residual at the venue; approvals return to zero; value conservation. Handlers include adversary actions (donations, dust, same-block deposits) | Bugs that appear only across call sequences |
| Fork | Every third-party interaction against the real contracts at a pinned block, including third-party admin actions (pause, parameter cut, router replacement) and real keeper execution | Wrong assumptions about the protocol; mocks that lie |
| Regression | One test per finding or incident, running in CI | The same bug returning |
| Symbolic (Halmos) | Custom core properties: rounding direction, deposit-then-redeem never gains, monotonic share price | Edge cases fuzzing misses |

Key points:
- **Fork tests are mandatory for every real third-party dependency.** Mocks encode your assumptions; only the fork shows what the protocol does. Every fork finding then becomes a fix to the mock as well, so mock-based tests stay faithful.
- **Fork tests must run in CI.** Provide the RPC URL as a CI secret and pin blocks. If a fork test is skipped in CI it covers nothing there, so every security-relevant fork path also needs a unit or regression test with a protocol-faithful mock.
- Tests assert the spec's properties, not the current behaviour. A test written to "prove" a fallback works can end up asserting the bug.
- The invariant list is the spec's safety properties made executable; write it now, not after the audit.
- Halmos runs locally (`uv tool install halmos`, then `halmos --function check_`), no API key. Bounded, and slow on nonlinear math: treat library math as trusted and prove the logic around it. Kontrol and Certora are optional, for large TVL or novel math, usually bought as a service.

**Exit gate:** every requirement ID has a test; every third-party interaction has a fork test that runs in CI; the invariant list including adversary handlers is reviewed.

## Phase 3: Implement whole slices

- One complete vertical slice per PR: contract, tests, docs, dependency-table entry. Avoid many tiny or stacked PRs; they lose context and invite merges that drop tests or land on dead branches. Bundle similar changes.
- Arithmetic goes through the libraries in the formula table; hand-written math is a review finding unless the table explains why.
- Never edit vendored dependencies; wrap them. Name things by meaning, not protocol type codes.
- Formatter, linter (every severity on, and check the config is actually valid) and the full suite before every commit; branch and PR.

**Exit gate:** all tests pass in CI including fork; lint clean; every requirement ID covered.

## Phase 4: Deploy and operations

Deploy scripts, verifiers, runbooks and bots are part of the system and in audit scope. See the deploy checklist in `references/checklists.md`. In short: scripts are tested on a fork; the verifier reads back every configured field and has a negative test per field; policy decided in the design (oracle bounds, caps, decimals) is enforced by the script, not by memory; access gates are attached before any external deposit; runbooks never use raw balances an attacker can inflate; configs with real addresses stay local.

**Exit gate:** a fork rehearsal of the full deployment passes the verifier; runbooks and monitoring are reviewed against the adversary checklist.

## Phase 5: Verify, independent audit, fix

1. **Self-check by requirement**, not by line coverage.
2. **Run Halmos** on the custom core properties.
3. **Independent audit with fresh context, by separate subagents**: follow `references/audit-lite.md` (an auditor, a validator and a retester, each a fresh subagent that never sees the implementer's reasoning; diff scope per PR, full scope at milestones with two auditors on different models). Include deploy scripts and runbooks in scope. Critical or High findings stop for the user; lower ones the agent fixes or records as accepted risk.
4. **Reproduce every finding as a PoC test** (on a fork when a third party is involved) before changing code. Unreproduced findings stay "plausible".
5. **Fix minimally, or accept the risk.** A fix can add more surface than it removes. When every fix introduces new findings, a documented accepted risk is a legitimate outcome (the user signs off when it is Critical or High). A third party's patch for a finding is verified like any other code.
6. **The PoC becomes a regression test.** Regression tests may be adapted, never silently deleted; reviewers check diffs for removed tests, and merges are checked against what the rehearsal said they would do.
7. **Independent retest** after fixes: a fresh agent or person who did not write the fix, the full suite including invariants and fork, and a pass over the fix diff.
8. **Docs, UI and spec match the code**: no claims of features that do not exist, no ADR the code does not follow.
9. **External audit** before mainnet for anything holding real funds.

**Exit gate:** no open confirmed finding; each fix has a regression test; accepted risks documented (Critical or High signed off by the user); docs match code.

## Loop back to the right layer

```
spec/design --> tests --> implementation --> deploy/ops --> verify/audit
     ^                                                          |
     +------- design-layer problem: change spec/ADR first ------+
              code-layer problem: fix code + regression test
```

Before fixing anything found late, ask which layer it came from. A wrong trust assumption, a missing exit path, a wrong valuation rule or an unfair economic outcome is a design problem: update the spec or ADR, then the tests, then the code.

## When the loop stops

The loop finishes the whole task by default; it stops only for a human decision or when it has converged. Without these rules an audit-fix-retest cycle can run forever: auditors always propose something, and a fix can create the next finding.

- **Converged:** a round with no new confirmed finding at Medium or above ends the cycle. Low and Info findings go to a backlog in the docs; they do not drive another round.
- **Round cap:** at most three audit-fix-retest rounds per scope (a PR or a milestone). At the cap, stop and hand the human the open list with a recommendation for each.
- **Reopened twice means wrong layer:** a finding whose fix is rejected twice is a design-layer problem; stop and take it back to the spec with the human.
- **A fix must not make things worse:** if a fix introduces a finding at least as severe as the one it closes, revert it and choose between an accepted risk and a design change (the human decides when it is High or above).
- **One tie-break:** when auditor and validator disagree, one fresh validator decides; if they still disagree on something at High or above, the human decides.
- **Unblock yourself before stopping.** A missing dependency is work, not a reason to halt. Missing RPC for fork tests: use a public endpoint for the chain (read-only, and pin a recent block, since public nodes often lack archive state). Missing ABI, address or protocol behaviour: read the verified source on the explorer, the protocol's docs or its repository. Missing tool: install it the way the project pins tools. Keep working on everything the block does not touch, and list blockers and workarounds in the final report.
- **Stop only for what needs the human's authority:** private keys or paid API keys, access to private repositories or accounts, spending money, deploying to a live network, or a business question the documents do not answer. Even then, finish every other part of the task first and stop with a precise question.
- **Flaky tests:** reproduce with the failing seed first; a failure that does not reproduce is reported as flaky and is not a fix target.
- **Budget:** a milestone has a token or time budget; when it is spent, stop and report progress, open items and what remains.

## Tool stack

Foundry unit, fuzz and invariant tests; fork tests against every real third-party protocol at pinned blocks, running in CI; Halmos for symbolic properties; an independent audit pass with retest; an external audit before mainnet. Kontrol / Certora only when TVL or novel math justify them.

## Output

For a plan or design: the phase 1 artifacts (templates), the phase 2 test plan, and which exit gates are not met yet. When reviewing an existing system or a proposal: gaps against the gates, ordered by risk to funds, with the layer each belongs to. Answer in the user's language.
