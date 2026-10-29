---
name: solidity-dev-loop
description: Development loop for Solidity / EVM systems that hold user funds, from requirements to deployment - spec and architecture agreed with the human at two gates, slices built test-first (unit, fuzz, invariant, fork against the real protocols, Halmos), deploy and ops, independent audit by subagents with bounded fix rounds. Use it for multi-step work on a funds-holding system: starting or extending one, designing a vault, adapter, lending pool, collateral, oracle, settlement or governance, adding a protocol integration or asset, taking over an existing or already-deployed codebase, writing deploy scripts, or fixing findings from an audit, even if the user never says "loop" or "process". Not for single Solidity or Foundry questions, and not for auditing a protocol you are not building (use contract-security-audit for that: it finds, this skill builds and fixes).
---

# Solidity development loop

Contracts that hold funds are expensive to get wrong and often impossible to patch. Most rework in real projects comes from four sources: third-party assumptions never checked on chain, a design-layer decision patched in code, a fix that adds more surface than it removes, and deploy or ops steps treated as outside the system. This loop settles decisions early and makes every later step check against something written down.

Guiding principle: **less is more.** The fewest contracts, the least state, the smallest change that meets the spec. Every line of custom code is audit surface.

## How to use this skill

1. **Find the entry point.** New system or new protocol integration: phase 1 in full. Small feature: the light gate; amendment to a signed spec: a delta at one gate (both in phase 1, "Scale"). Existing codebase: "Brownfield entry" first. Implementation, deployment or findings already under way: start at that phase, and say so if the request exposes a design-layer gap.
2. In each phase, produce its artifacts and check its exit gate before moving on.
3. A problem found late goes back to the layer it came from ("Loop back to the right layer").
4. The project's own rules (CLAUDE.md, spec, IDs) win; this skill is the default where they are silent.

References: `references/templates.md` (every document and table), `references/checklists.md` (adversary, valuation, liquidity, deploy, CI), `references/audit-lite.md` (independent design and code review by subagents).

## Non-negotiable invariant

**User funds can never be seized or permanently locked.** Every choice is judged against this. Temporary denial of service is acceptable when a recovery path exists (a timelocked setter, migration to a successor contract, another exit route); a permanent lock is not. A liveness fix must never relax a safety bound: "the oracle is stale, so accept any output" turns a stuck withdrawal into theft.

## Brownfield entry (existing or deployed code)

Before changing an existing system: reconstruct the spec from code, docs and deployed state (requirement IDs and invariants for what the code actually guarantees); write characterisation tests that pin current behaviour; for deployed contracts read the live configuration, roles, and for proxies the storage layout and initializer state. Mark every behaviour the reconstruction cannot justify as an open question. Then take the reconstructed spec through Gate 2 (no Gate 1 package needed unless the change itself is new architecture) before the first change.

## Phase 1: Spec and architecture, two human gates

The human decides at two gates; between them the agent works in parallel, so neither waits on the other.

```
original requirements (never edited)
  -> [agent, parallel] enriched PRD + ranked open questions
                       + fork spikes, dependency and exit-liquidity research
                       + architecture options (prototyped where they differ in lock risk,
                         custom code or third-party behaviour)
                       + independent design review (audit-lite, design mode)
  -> Gate 1 (human): answer the questions, choose the architecture      one package
  -> [agent] TRD + architecture + ADRs + delivery plan + traceability, reviewed again
  -> Gate 2 (human): sign off spec and plan together                     one sign-off
  -> autonomous loop; milestone reports; stops only per "When the loop stops"
```

**Scale.** The full flow is for a new system or a new protocol integration. A small feature (a new function, parameter or asset inside the signed architecture) gets one light gate: a short plan with its open questions, confirmed once. A fix that changes no requirement, role, parameter range or architecture needs no gate. An amendment to a signed spec is a delta (changed PRD and TRD sections, affected ADRs, plan impact) reviewed at one gate.

### Before Gate 1

- **Enriched PRD next to the unedited original.** The original requirements (for example `docs/prd/original.md`) are the source and are never edited. `docs/PRD.md` makes every statement explicit (actors, flows, numbers, states, failure cases, non-goals), traced to the original; everything added is marked derived or an assumption tied to a question.
- **Open questions derived from the document, then ranked.** Look for vague words ("safe", "low risk"), missing numbers, undefined actors, flows without a failure path, conflicts, implicit third-party assumptions, and what the product clearly varies (assets, chains, number of instances). Each question carries its source, options, consequences and your recommendation. Architecture-shaping questions need an answer; detail questions carry a default the human can accept wholesale. A conflict found later goes onto this list rather than stopping the work. Never ask what code, docs or a fork read can answer.
- **Who decides.** The human: scope and deferrals, users and trust model, roles and holders, assets, chains and venues, risk appetite (caps, LTV, slippage), economics and fairness, upgrade model, timelock lengths, accepted third-party risks, plus whatever the PRD questions add. The agent: choices with a conventional answer (library, rounding, naming, test layout), written into the spec so the human can overrule them.
- **Research that does not depend on the answers runs now:** fork spikes on every third-party assumption (does the token output what you think, is the market live, what do admins control, what does the keeper really execute), exit-liquidity quotes, mock-versus-fork checks, CI scaffolding. Work that depends on an answer may start on the recommended option, marked speculative.
- **Architecture options.** For each major decision (topology and reuse, protocol integration, sync or async flows, where accounting and valuation live, upgrade model, governance, off-chain keepers and runbooks) give two or three options with trade-offs against the PRD and the invariant. Prototype in parallel subagents only the decisions whose options differ in lock risk, custom code size or third-party behaviour, and measure them on a fork; argue the rest in the ADR.
- **Independent design review** (audit-lite, design mode) before the human sees the package.
- **Gate 1 package:** a one-page decision brief, the ranked questions, the options with measurements, the enriched PRD and the review findings; about half an hour to review.

### Between the gates

Record every answer in the decision log and every architecture choice as an ADR summarised in `docs/architecture.md`. Write the TRD from the artifact list below, the delivery plan and the traceability matrix (original -> PRD -> TRD ID -> component -> tests), then run a second design review on the chosen design. Templates for all of these are in `references/templates.md`.

**TRD artifacts.** Requirements as testable items with IDs; role and permission matrix (no role can veto its own removal; emergency powers only reduce risk); deferred scope with triggers; reuse map (audited libraries, unmodified upstream contracts, standard governance such as `TimelockController` or `AccessManager`); formula table; valuation rule with degraded-mode matrix; per-actor economics; upgrade model; third-party dependency table; recovery paths; exit paths and exit liquidity; adversary model. Rules that shape them:

- **Rounding:** every conversion rounds against the caller (ERC-4626: `deposit`/`redeem` round down, `mint`/`withdraw` round up; debts up), through library math (`Math.mulDiv` with `Rounding`, Solady `FixedPointMathLib`, `SafeCast`). A formula with no library is a Halmos and review target.
- **Valuation:** choose and bound the on-chain price source by what the exit really returns, measured off-chain on a fork. Never use a same-block manipulable quote (spot reserves, a single-block swap quote) in a view that gates deposits, borrows, liquidations or share price. The valuation view never reverts.
- **Upgrade model, chosen from the business:** immutable, immutable with timelocked setters, immutable core with replaceable modules, or proxy. Under any model no operational role can move user funds. Under a proxy the upgrade power can, so it sits behind a timelock longer than the time users need to exit, separate from operations, and the residual trust is disclosed.
- **Dependencies are judged by the worst case for exits:** permanent lock means redesign; bounded DoS with recovery is fine. Liquidity migrating, markets dying, parameters being cut and depegs count as dependencies too.
- **Recovery paths are features:** migration, emergency setters, write-off and impairment get the same threat model and tests as the main flow.
- **Illiquidity is a lock:** caps come from measured exit depth across every position that shares a route or underlying.

**Delivery plan** (signed at Gate 2): vertical slices, each one PR with its contract, tests and docs, riskiest first; per slice the requirement IDs, acceptance tests and definition of done; milestones (full-scope audits, fork rehearsal, testnet, mainnet), budget per milestone; CI setup and the secrets it needs; deferred scope and open risks.

### Gate 2

Present TRD, architecture and plan with remaining assumptions highlighted; the agent never self-approves. After sign-off the loop runs without per-step approval.

**Exit gate:** Gate 2 signed; open questions empty or explicitly accepted as assumptions; every requirement says how it is tested; every third-party assumption checked on a fork; every dependency has a worst case and recovery; every formula maps to a library or is flagged.

## Phase 2: Build slices, test-first

Each slice is an inner loop: write the slice's tests, see them fail, implement, get them green, run audit-lite on the PR, merge.

| Layer | What | Catches |
|---|---|---|
| Unit | Happy path and every revert path per requirement ID, exact error selector | Logic, access control |
| Fuzz | Amounts, decimals, prices, timestamps; `bound()` over `vm.assume()` | Boundaries, rounding, overflow |
| Invariant | Accounting equals real positions; every holder can exit; full exit leaves no residual value at the venue; allowances return to zero; value conservation. Handlers include adversary actions (donations, dust, same-block deposits) | Bugs across call sequences |
| Fork | Every third-party interaction against the real contracts at a pinned block, including their admin actions (pause, parameter cut, router replacement) and real keeper execution | Wrong assumptions; mocks that lie |
| Regression | One test per closed finding or incident | The bug returning |
| Symbolic | Halmos `check_` properties (with a harness that makes state symbolic) on custom core logic: rounding direction, deposit-then-redeem never gains, monotonic share price | Edges fuzzing misses |

- Fork tests are mandatory for real third-party dependencies, and every fork finding also corrects the mock. In CI they need an archive RPC (fork caching on); where none is available, every security-relevant fork path also gets a test with a protocol-faithful mock.
- Tests assert the spec's properties, not current behaviour; a test written to "prove" a fallback works can end up asserting the bug.
- Arithmetic only through the libraries in the formula table. Never edit vendored dependencies; wrap them.
- **Source code states behaviour, never development history.** Comments and NatSpec in `src/` say what the code does and why, in the present tense. They never cite finding, audit or review IDs, ADR or requirement IDs, PR numbers, dates, or "previously" and "fixed". History lives in commits, PRs, ADRs, the spec, the findings index and test names. Enforce it with a CI grep over `src/` (patterns in `references/checklists.md`).
- Before every commit: formatter, linter, static analysis (Slither or Aderyn) with findings triaged, contract size under EIP-170, full suite green.

**Exit gate per slice:** its tests green, fork tests included (in CI once the archive RPC secret exists; until then run locally and flagged in the report); lint and static analysis clean or triaged; its requirement IDs covered. At each milestone: every requirement ID in the TRD has a test.

## Phase 3: Deploy and operations

Deploy scripts, verifiers, runbooks and bots are part of the system and in audit scope. Work through the deploy and CI checklists in `references/checklists.md`; the ones most often missed are the full read-back verifier, granting roles before the deployer renounces, and gates attached before any external deposit.

**Exit gate:** a fork rehearsal of the full deployment passes the verifier; runbooks and monitoring reviewed against the adversary checklist.

## Phase 4: Verify, independent audit, fix

1. Self-check by requirement ID, not line coverage; run Halmos on the custom core.
2. **Independent audit by subagents** per `references/audit-lite.md`: diff scope per PR, full scope at milestones with two auditors on different models; deploy scripts and runbooks in scope.
3. Every code finding is reproduced as a PoC before code changes, every design finding by a simulation or prototype; a third party's suggested patch is verified like any other code.
4. **Fix minimally, or accept the risk.** When every fix adds new findings, a documented accepted risk is legitimate (the human signs it off at High or above).
5. The PoC lands unchanged as the regression test in the fix's commit; later it may be adapted when the code it covers changes, never silently deleted, and reviewers check diffs and merges for removed tests.
6. Independent retest of every fix; the findings index in the docs records ID, severity, status and regression test.
7. Docs, UI and spec match the code: no claimed features that do not exist, no ADR the code does not follow.

**Exit gate:** no open finding at Medium or above; Low and Info logged in the findings index; every fix has a regression test; accepted risks documented (High and above signed off); docs match code. Additionally, before the mainnet milestone: an external audit for anything holding real funds.

## Loop back to the right layer

```
spec/architecture --> slices (tests, code) --> deploy/ops --> verify/audit
        ^                                                          |
        +---- design-layer: spec delta -> one human gate ----------+
              code-layer: fix + regression test, no gate
```

Before fixing anything found late, classify it. A wrong trust assumption, missing exit path, wrong valuation rule or unfair economic outcome is a design-layer problem: write a spec delta (changed requirements, ADRs, plan impact), take it through one human gate, then change tests and code. A code-layer problem inside the signed spec is fixed directly with a regression test.

## When the loop stops

The loop finishes the whole task by default and stops only when it converges or needs the human.

- **Converged:** a round with no new confirmed finding at Medium or above ends the audit-fix-retest cycle; Low and Info go to the findings index.
- **Round cap:** at most three audit-fix-retest rounds per scope (a PR or a milestone); at the cap, hand the human the open list with a recommendation each.
- **Reopened twice:** a finding whose fix is rejected twice is design-layer; take it back as a spec delta.
- **No worse fixes:** a fix that introduces a finding at least as severe as the one it closes is reverted; choose accepted risk or design change (the human decides at High or above).
- **Disagreement:** when auditor and validator disagree, one fresh validator decides; if it is still disputed at High or above, the human decides.
- **Unblock yourself first.** A missing dependency is work: a public RPC for local fork spikes (pin a recent block, since public nodes rarely keep archive state), the explorer's verified source, the protocol's docs or repository for ABIs and behaviour, the project's pinned way to install a tool. Keep working on everything the block does not touch, and list blockers and workarounds at the end.
- **Stop only for the human's authority:** private or paid keys (including an archive RPC for CI), access to private repositories or accounts, spending money, deploying to any network other than a local fork (testnets included), or a business question the documents do not answer. Finish everything else first, then stop with a precise question.
- **Flaky tests:** reproduce with the failing seed; one that does not reproduce is reported as flaky, not fixed.
- **Budget:** Gate 1 preparation (state it when starting) and each milestone have a token or time budget; when spent, stop and report progress and what remains.

## Output

New system or integration: the Gate 1 package, then the Gate 2 package. Small change: one light plan with its questions. Existing system or a proposal: gaps against the exit gates, ordered by risk to funds, each with its layer. Always state which exit gates are not met yet, and answer in the user's language.
