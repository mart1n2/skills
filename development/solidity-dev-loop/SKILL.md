---
name: solidity-dev-loop
description: Development loop for Solidity / EVM systems that hold user funds, from requirements to deployment - spec and architecture agreed with the human at two gates, slices built test-first (unit, fuzz, invariant, fork against the real protocols) with light checks per change and heavy ones (full-scope audit, deploy rehearsal, optional formal verification) only at milestones, deploy and ops, independent audit by subagents with bounded fix rounds. Use it for multi-step work on a funds-holding system: starting or extending one, designing a vault, adapter, lending pool, collateral, oracle, settlement or governance, adding a protocol integration or asset, taking over an existing or already-deployed codebase, writing deploy scripts, or fixing findings from an audit, even if the user never says "loop" or "process". Not for single Solidity or Foundry questions, and not for auditing a protocol you are not building (use contract-security-audit for that: it finds, this skill builds and fixes).
---

# Solidity development loop

Contracts that hold funds are expensive to get wrong and often impossible to patch. Most rework in real projects comes from four sources: a third-party protocol integrated before it was studied and checked on chain, a design-layer decision patched in code, a fix coded before its design was evaluated, and deploy or ops steps treated as outside the system. This loop settles decisions early and makes every later step check against something written down.

Guiding principle: **less is more.** The fewest contracts, the least state, the smallest change that meets the spec. Every line of custom code is audit surface, and doing more is not skill.

- Nothing is added unless it is necessary. Every addition (a state variable, role, parameter, check, branch, fallback or option) names the requirement or finding it serves and what breaks without it; one that cannot stays out.
- Between two designs that meet the spec, the one with the simpler logic wins: less state, fewer branches, fewer actors.
- Before adding a mechanism, look for the version that removes or narrows something instead.
- Hardening against a threat the current deployment does not face is deferred scope with its trigger, not code.

## How to use this skill

1. **Size the work** ("One loop, three sizes") and start there. Implementation, deployment or findings already under way: start at that phase, and say so if the request exposes a design-layer gap.
2. In each phase, produce its artifacts and check its exit gate before moving on.
3. A problem found late goes back to the layer it came from ("Loop back to the right layer").
4. The project's own rules (CLAUDE.md, spec, IDs) win; this skill is the default where they are silent. Write the rules that recur into short CLAUDE.md files, one per package: the root holds the principle, the source of truth (the TRD and its IDs), the layout and safety; each package (contracts, bots, apps) holds its exact commands and its code and test rules. A rule the agent forgot twice belongs there, not in chat.
5. Run each check at its cadence ("Cadence"): cheap checks on every change, expensive ones only at milestones.

References: `references/templates.md` (every document and table), `references/checklists.md` (adversary, valuation, liquidity, deploy, checks, formal verification), `references/audit-lite.md` (independent design and code review by subagents).

## Non-negotiable invariant

**User funds can never be seized or permanently locked.** Every choice is judged against this. Temporary denial of service is acceptable when a recovery path exists (a timelocked setter, migration to a successor contract, another exit route); a permanent lock is not. A liveness fix must never relax a safety bound: "the oracle is stale, so accept any output" turns a stuck withdrawal into theft.

## One loop, three sizes

Every piece of work runs the same loop: understand, lay out options, decide, write it down, build test-first, verify, ship. Its size sets how much of each, which document carries it and who decides.

| Work | Document | The human decides | The agent decides |
|---|---|---|---|
| New system, or the first integration of a protocol | spec, protocol studies, delivery plan (phase 1 in full) | Gate 1: the options. Gate 2: spec and plan | everything after Gate 2 |
| Change to a signed system: a feature, a new use of an integrated protocol, a migration, an amended requirement | one change plan | one gate: the options and the spec delta together | the build, its audit and its fixes |
| Fix inside the signed spec: no requirement, role, parameter range, external interface or architecture changes | a fix evaluation | nothing | the fix, at any severity |
| Existing code without a spec | "Brownfield entry", then one of the rows above | Gate 2 on the reconstructed spec | the reconstruction |

Most work on a live system is the second and third row. Phase 1 in full is too much for it, and no plan at all is too little.

## Cadence: light per change, heavy at milestones

Expensive checks repeated on every change cost more than they find: the code still moves, so each run is redone after the next fix. Run them once the scope is stable.

| Per change (every PR) | At milestones only |
|---|---|
| Formatter and linter at the strictest level, build, contract size, the history grep over `src/` | Static analysis (Slither or Aderyn) with findings triaged |
| Unit, fuzz and invariant tests at default runs | Fuzz and invariant at a high-run profile (for example `FOUNDRY_PROFILE=ci`) |
| Fork tests of the third parties the change touches, run locally | The whole fork suite at its pinned blocks |
| Diff audit-lite, one auditor, only when the change touches value-moving code, roles or deploy scripts | Full-scope audit-lite, two auditors on different models |
| Fix evaluation before each fix; a design review when the fix adds state, a revert path, a role or an interface change | |
| | Fork rehearsal of the full deployment or migration, read-back verifier included |
| | Optional: formal verification of the custom core, final audit round only (`references/checklists.md`, "Formal verification") |

**Milestones** are named in the delivery plan: the end of a feature set that will be deployed, each deployment or migration of a live system, and the final audit round before an external audit or mainnet. The design reviews of phase 1 run once before each gate. A change to docs, tests, comments or configuration outside `src/` and the deploy scripts gets the per-change checks without an audit.

## Brownfield entry (existing or deployed code)

Before changing an existing system: reconstruct the spec from code, docs and deployed state (requirement IDs and invariants for what the code actually guarantees); write characterisation tests that pin current behaviour; for deployed contracts read the live configuration, roles, and for proxies the storage layout and initializer state. Write the study of each integrated protocol the change touches, where none exists. Mark every behaviour the reconstruction cannot justify as an open question. Then take the reconstructed spec through Gate 2 (no Gate 1 package needed unless the change itself is new architecture) before the first change.

## Phase 1: Spec and architecture, two human gates

The human decides at two gates; between them the agent works in parallel, so neither waits on the other.

```
original requirements (never edited)
  -> [agent, parallel] enriched PRD + ranked open questions
                       + protocol studies, fork spikes, dependency and exit-liquidity research
                       + architecture options (prototyped where they differ in lock risk,
                         custom code or third-party behaviour)
                       + independent design review (audit-lite, design mode)
  -> Gate 1 (human): answer the questions, choose the architecture      one package
  -> [agent] spec (requirements, architecture, decisions) + delivery plan, reviewed again
  -> Gate 2 (human): sign off spec and plan together                     one sign-off
  -> autonomous loop; milestone reports; stops only per "When the loop stops"
```

**A change to a signed system** does not rerun this phase. Its change plan (`references/templates.md`) carries, at the size the change needs: the protocol study, when it uses a protocol in a new way; the options, diverged and converged as below, when it can be built in more than one way; the spec delta (changed requirements and decisions); the answers, before any code, to the questions a fix evaluation asks (sites of the same class, who can move each new input, budgets); then tests, slices, deployment or migration, and risks. One gate confirms the options and the delta together. A fix inside the signed spec needs no gate; it still gets its evaluation (phase 4).

### Before Gate 1

- **Enriched PRD next to the unedited original.** The original requirements (for example `docs/prd/original.md`) are the source and are never edited. `docs/PRD.md` makes every statement explicit (actors, flows, numbers, states, failure cases, non-goals), traced to the original; everything added is marked derived or an assumption tied to a question. Where the original leaves the product's shape open, the PRD does not choose silently: the alternatives go to the questions as options. Where the requirements arrive in conversation and not as a document, there is no PRD: they are recorded in the spec's decisions and scope, each with who decided and when.
- **Open questions derived from the document, then ranked.** Look for vague words ("safe", "low risk"), missing numbers, undefined actors, flows without a failure path, conflicts, implicit third-party assumptions, and what the product clearly varies (assets, chains, number of instances). Each question carries its source, options, consequences and your recommendation. Architecture-shaping questions need an answer; detail questions carry a default the human can accept wholesale. A conflict found later goes onto this list rather than stopping the work. Never ask what code, docs or a fork read can answer.
- **Who decides.** The human: scope and deferrals, users and trust model, roles and holders, assets, chains and venues, risk appetite (caps, LTV, slippage), economics and fairness, upgrade model, timelock lengths, accepted third-party risks, plus whatever the PRD questions add. The agent: choices with a conventional answer (library, rounding, naming, test layout), written into the spec so the human can overrule them.
- **Study each third-party protocol before designing around it.** For every protocol or contract to be integrated, read its docs, its source and how audited integrators use it, and write a protocol study (`references/templates.md`): what the protocol is for and how its users and its economics work; every route it offers to the outcome needed (direct call, router or periphery, its own orders, automation, hooks or keepers, batch entry points); per route the cost (protocol fees, execution or keeper fees, gas, price impact), the limits (minimum sizes, caps, delays, cooldowns), what the protocol records and who can change it. The study is where a design gets simpler: a native feature often replaces a mechanism the design was about to build. Every integration's options include the native route with the least custom code, and an option that adds a custom mechanism says which native route it was compared with and why that one does not serve. Using an integrated protocol in a new way updates its study first.
- **Research that does not depend on the answers runs now:** fork spikes on every third-party assumption (does the token output what you think, is the market live, what do admins control, what does the keeper really execute), exit-liquidity quotes, mock-versus-fork checks, CI scaffolding. Work that depends on an answer may start on the recommended option, marked speculative.
- **Design options: diverge, then converge.** A decision that is the human's is never presented as one finished design. This covers the product's shape in the PRD (who it serves, which flows, what is deferred) and each major architecture decision (topology and reuse, protocol integration, sync or async flows, where accounting and valuation live, upgrade model, governance, off-chain keepers and runbooks).
  - *Diverge first.* Collect candidates that differ in mechanism, not in a parameter: the native routes from the protocol study, how comparable protocols solved the same problem, on chain against off chain, sync against async, reuse against custom, not building it, deferring it with a trigger. For an architecture-shaping decision, have two or three fresh subagents each propose a design from the PRD alone, without seeing each other's or yours: a single author anchors on its first idea.
  - *Then converge.* Drop the candidates that break the invariant or that another candidate beats on every dimension, one line each with the reason, so the human sees what was considered. Bring two to four to the gate, always including the least that meets the PRD, compared on the same dimensions: risk to funds and lock risk, trust and roles, custom code and audit surface, third-party dependence, cost (gas, fees, keepers), operations burden, user experience, time to build, what it rules out later. Put the recommendation first. Never pad the list with an option nobody would choose; when one candidate survives, say so and show what was dropped and why.
  - Prototype in parallel subagents only the decisions whose options differ in lock risk, custom code size or third-party behaviour, and measure them on a fork; argue the rest in the decision record.
- **Independent design review** (audit-lite, design mode) before the human sees the package.
- **Gate 1 package:** a one-page decision brief, the ranked questions, the option comparison for each decision with its measurements and its dropped candidates, the enriched PRD and the review findings; about half an hour to review.

### Between the gates

Write each thing once, in as few documents as carry it. The spec (the TRD) holds the requirements with their IDs, the architecture and the decisions: every decision recorded once with an ID, the options compared and the reason, and given a file of its own only when it needs more than a page. Traceability is three columns of the requirement table (source, component, tests), not a separate matrix. A project that already keeps these apart keeps its layout. Write the spec from the artifact list below and the delivery plan, then run a second design review on the chosen design. Templates are in `references/templates.md`.

**TRD artifacts.** Requirements as testable items with IDs; role and permission matrix (no role can veto its own removal; emergency powers only reduce risk); deferred scope with triggers; reuse map (audited libraries, unmodified upstream contracts, standard governance such as `TimelockController` or `AccessManager`); formula table; valuation rule with degraded-mode matrix; per-actor economics; upgrade model; third-party dependency table; recovery paths; exit paths and exit liquidity; adversary model. Rules that shape them:

- **Rounding:** every conversion rounds against the caller (ERC-4626: `deposit`/`redeem` round down, `mint`/`withdraw` round up; debts up), through library math (`Math.mulDiv` with `Rounding`, Solady `FixedPointMathLib`, `SafeCast`). A formula with no library is a review target, covered by fuzz and invariant tests, and a property for formal verification where the project runs it.
- **Valuation:** choose and bound the on-chain price source by what the exit really returns, measured off-chain on a fork. Never use a same-block manipulable quote (spot reserves, a single-block swap quote) in a view that gates deposits, borrows, liquidations or share price. The valuation view never reverts.
- **Upgrade model, chosen from the business:** immutable, immutable with timelocked setters, immutable core with replaceable modules, or proxy. Under any model no operational role can move user funds. Under a proxy the upgrade power can, so it sits behind a timelock longer than the time users need to exit, separate from operations, and the residual trust is disclosed.
- **Dependencies are judged by the worst case for exits:** permanent lock means redesign; bounded DoS with recovery is fine. Liquidity migrating, markets dying, parameters being cut and depegs count as dependencies too.
- **Recovery paths are features:** migration, emergency setters, write-off and impairment get the same threat model and tests as the main flow.
- **Illiquidity is a lock:** caps come from measured exit depth across every position that shares a route or underlying.

**Delivery plan** (signed at Gate 2): vertical slices, each one PR with its contract, tests and docs, riskiest first; per slice the requirement IDs, acceptance tests and definition of done; milestones and the heavy checks each one runs (full-scope audit, fork rehearsal, testnet, final audit round, mainnet), and whether the final round includes formal verification, budget per milestone; where the checks run (locally or in CI) and the secrets they need; deferred scope and open risks.

### Gate 2

Present the spec and the plan with remaining assumptions highlighted; the agent never self-approves. After sign-off the loop runs without per-step approval.

**Exit gate:** Gate 2 signed; open questions empty or explicitly accepted as assumptions; every requirement says how it is tested; every integrated protocol has its study and every assumption about it is checked on a fork; every dependency has a worst case and recovery; every formula maps to a library or is flagged.

## Phase 2: Build slices, test-first

Each slice is an inner loop: write the slice's tests, see them fail, implement, get them green, run the diff audit-lite when the change calls for one ("Cadence"), merge.

| Layer | What | Catches |
|---|---|---|
| Unit | Happy path and every revert path per requirement ID, exact error selector | Logic, access control |
| Fuzz | Amounts, decimals, prices, timestamps; `bound()` over `vm.assume()` | Boundaries, rounding, overflow |
| Invariant | Accounting equals real positions; every holder can exit; full exit leaves no residual value at the venue; allowances return to zero; value conservation. Handlers include adversary actions (donations, dust, same-block deposits) | Bugs across call sequences |
| Fork | Every third-party call, encoding, permission and state relied on, against the real contracts at a pinned block, including their admin actions (pause, parameter cut, router replacement) and real keeper execution | Wrong assumptions; stand-ins that lie |
| Regression | One test per closed finding or incident | The bug returning |

- **Fork tests are mandatory for every third-party dependency** and assert what the protocol recorded (its stored request, minimum outputs, owner, pending amounts), not only that the call succeeded. Coverage check: every third-party interface function that `src/` calls appears in the traces of the fork suite (`forge test --match-path "test/fork/*" -vvvv`).
- **Stand-ins are written from the protocol's source**, read and cited in the stand-in, and never replace the fork test. A stand-in that skips one step of the protocol (a subtraction, a freeze rule) hides a wrong encoding for weeks; every fork finding also corrects the stand-in.
- Fork tests pin a block. Locally a public RPC with a recent block is enough; CI needs an archive RPC from a secret. A project may keep contract CI manual and run the per-change checks locally before each PR; the PR then states what ran.
- Tests assert the spec's properties, not current behaviour; a test written to "prove" a fallback works can end up asserting the bug.
- Arithmetic only through the libraries in the formula table. Never edit vendored dependencies; wrap them.
- **Source code states behaviour, never development history.** Comments and NatSpec in `src/` say what the code does and why, in the present tense. They never cite finding, audit or review IDs, ADR or requirement IDs, PR numbers, dates, or "previously" and "fixed". History lives in commits, PRs, ADRs, the spec, the findings index and test names. Enforce it with a grep over `src/` in the per-change checks (patterns in `references/checklists.md`).
- **Comments say only what the code cannot.** Worth a comment: an invariant, a rounding direction, why the more direct form is wrong, a third-party behaviour the code relies on. Not worth one: restating the statement below it, or NatSpec that repeats a function or parameter name. NatSpec is for external and public interfaces and for internal functions whose behaviour is not obvious. State a fact once, at the interface, and do not repeat it in the implementation and the library. Design rationale lives in the TRD or an ADR, not in `src/`.
- Before every commit: formatter, linter with every severity failing (for example `forge lint --deny notes`), contract size under EIP-170, suite green. When a contract interface changes, regenerate the ABIs the off-chain apps consume in the same PR.
- One PR per concern: a change and the fixes it needs to be complete go together; a separate component or migration gets its own PR.

**Exit gate per slice:** its tests green, fork tests of the touched dependencies included; lint clean; its requirement IDs covered, and no state, role, parameter or branch that serves none of them. At each milestone: the milestone column of "Cadence" done, and every requirement ID in the TRD has a test.

## Phase 3: Deploy and operations

Deploy scripts, verifiers, runbooks and bots are part of the system and in audit scope. Work through the deploy and checks checklists in `references/checklists.md`; the ones most often missed are the full read-back verifier, granting roles before the deployer renounces, and gates attached before any external deposit.

Changing a live system (replacing a module, moving positions, rotating roles) is a deployment too: its own scripts, a fork rehearsal against the live state at a recent block, the same verifier, and a runbook. Batch the calls each signer sends to one contract through its `multicall`, so a multisig signs once per contract.

**Exit gate:** a fork rehearsal of the full deployment or migration passes the verifier; runbooks and monitoring reviewed against the adversary checklist.

## Phase 4: Verify, independent audit, fix

1. Self-check by requirement ID, not line coverage.
2. **Independent audit by subagents** per `references/audit-lite.md`, at the cadence above: diff scope for value-moving PRs, full scope at milestones with two auditors on different models; deploy scripts and runbooks in scope.
3. Every code finding is reproduced as a PoC before code changes, every design finding by a simulation or prototype; a third party's suggested patch is verified like any other code.
4. **Evaluate the fix before coding it.** The retest is the backstop, not the design review: a fix designed and coded in one step is corrected a round late, after interfaces, docs and tests have already moved. Write the evaluation first (`references/templates.md`, "Fix evaluation"):
   - every site of the same class, not only the PoC's path: each sibling `try`, fallback and caller;
   - for each state variable, check or revert the fix adds, who can move its inputs (anyone, a donation, the caller's gas limit, a keeper, a timelocked action anyone may execute); a revert an outsider can trigger is a new denial of service, so prefer clamping or adjusting;
   - what it does to existing budgets and neighbours: gas margins, contract size, interfaces, runbooks, bots;
   - the candidate designs, simplest first: remove or restrict the feature, tighten an existing check, a new mechanism, or accept the risk.

   Scale it to the fix: one that adds no state, revert path, role or interface change needs two lines (the sites of the same class, why this is the simplest design). One that adds any of them gets the full evaluation and an independent design challenge before any code (`references/audit-lite.md`, "Fix design review"). The agent decides the fix; the human decides only what "When the loop stops" names.
5. **Fix minimally, or accept the risk.** When every fix adds new findings, a documented accepted risk is legitimate (the human signs it off at High or above).
6. The PoC lands unchanged as the regression test in the fix's commit; later it may be adapted when the code it covers changes, never silently deleted, and reviewers check diffs and merges for removed tests.
7. Independent retest of every fix; the findings index in the docs records ID, severity, status and regression test.
8. **Optional, final audit round only:** formal verification (Certora) of the custom core, when the delivery plan asks for it. It runs once the full-scope findings are fixed and retested, so the rules are written once against stable code (`references/checklists.md`, "Formal verification"). A counterexample in the code is a finding like any other: PoC, fix, regression test.
9. Docs, UI and spec match the code: no claimed features that do not exist, no recorded decision the code does not follow.

**Exit gate:** no open finding at Medium or above; Low and Info logged in the findings index; every fix has its evaluation and a regression test; accepted risks documented (High and above signed off); docs match code. Additionally, before the mainnet milestone: an external audit for anything holding real funds. Where formal verification ran, its results are recorded, each unproved rule naming the tests that cover it instead.

## Loop back to the right layer

```
spec/architecture --> slices (tests, code) --> deploy/ops --> verify/audit
        ^                                                          |
        +---- design-layer: spec delta -> one human gate ----------+
              code-layer: evaluate, fix + regression test, no gate
```

Before fixing anything found late, classify it. A wrong trust assumption, missing exit path, wrong valuation rule or unfair economic outcome is a design-layer problem: write a spec delta (changed requirements and decisions, plan impact), take it through one human gate, then change tests and code. A code-layer problem inside the signed spec is fixed directly with a regression test.

## When the loop stops

The loop finishes the whole task by default and stops only when it converges or needs the human.

- **Fixes are the agent's.** A code-layer fix is designed, evaluated, coded and retested without a human go-ahead, at any severity; the round report says what was found and how it was fixed. The human decides at the gates, on a design-layer delta, and on accepting a risk at High or above instead of fixing it.
- **Converged:** a round with no new confirmed finding at Medium or above ends the audit-fix-retest cycle; Low and Info go to the findings index.
- **Round cap:** at most three audit-fix-retest rounds per scope (a PR or a milestone); at the cap, hand the human the open list with a recommendation each.
- **Reopened twice:** a finding whose fix is rejected twice is design-layer; take it back as a spec delta.
- **No patch on a patch:** a retest finding in a fix reopens its evaluation (the class, the inputs, the simpler designs); the next attempt replaces the fix and does not add a guard on top of it.
- **No worse fixes:** a fix that introduces a finding at least as severe as the one it closes is reverted; choose accepted risk or design change (the human decides at High or above).
- **Disagreement:** when auditor and validator disagree, one fresh validator decides; if it is still disputed at High or above, the human decides.
- **Unblock yourself first.** A missing dependency is work: a public RPC for local fork spikes (pin a recent block, since public nodes rarely keep archive state), the explorer's verified source, the protocol's docs or repository for ABIs and behaviour, the project's pinned way to install a tool. Keep working on everything the block does not touch, and list blockers and workarounds at the end.
- **Stop only for the human's authority:** private or paid keys (including an archive RPC for CI, or a prover key where formal verification is planned), access to private repositories or accounts, spending money, deploying to any network other than a local fork (testnets included), or a business question the documents do not answer. Finish everything else first, then stop with a precise question.
- **Flaky tests:** reproduce with the failing seed; one that does not reproduce is reported as flaky, not fixed.
- **Budget:** Gate 1 preparation (state it when starting) and each milestone have a token or time budget; when spent, stop and report progress and what remains.

## Output

New system or integration: the Gate 1 package, then the Gate 2 package. Small change: one light plan with its questions. Existing system or a proposal: gaps against the exit gates, ordered by risk to funds, each with its layer. Always state which exit gates are not met yet, and answer in the user's language.
