# Optional EVM tools

Read when selecting an acquisition or verification tool. Choose for the open
obligation; do not run every tool. Existing triage and report gates remain in force.

| Need | Starting point | Boundary |
|------|----------------|----------|
| Verified source and build metadata | Bundled direct-API fetcher | Explorer verification is not deployed-state proof |
| Ad hoc ABI, transactions, logs, exports | Official Etherscan CLI, if available | Same provider, quotas and data as the API |
| Pinned storage/code, full traces, concrete replay | RPC + Cast/Foundry or equivalent | Bind actual code, dependencies and block number/hash |
| Stateful fuzzing in a Foundry project | Existing invariant tests/handlers | Add another engine only when it helps the search |
| Rare arithmetic/permission cases, bounded transitions | Halmos | Assumptions, modeled semantics, bounds and solver completion limit the result |
| Longer transaction-sequence search, economic objectives | Echidna | No counterexample within a budget is not universal safety |

## Etherscan

Keep the API as the bundled acquisition default; use the CLI for convenient
queries. No second parser or evidence registry is needed. npm and Homebrew are
installation routes for the same official native CLI. API/CLI agreement is not
independent corroboration; switching interfaces does not fix exhausted quotas,
invalid keys or provider outages.

Check `etherscan version` and command-specific help. Specify numeric `--chain`
and `--output json` explicitly. Use existing secret delivery, not credentials in
chat or command arguments. Retain output, stderr, exit status, version, sanitized
parameters and observation time. A `--max-pages` warning means potentially
incomplete results; preserve it and narrow/continue collection as needed.

The bundled fetcher retains complete response bodies and request metadata in
`tmp/fetch-source/<run-id>/request.*/`. This includes failed/partial responses;
HTTP success still requires provider-envelope validation. Each outer attempt
retains curl's final body, not every internal retry response. Metadata omits URL
credentials/query and records endpoint, operation, chain/address, time, HTTP/exit
status and retry/time limits. Etherscan queries use `module=contract`,
`action=getsourcecode`, `address`, and V2 `chainid`; Sourcify uses `fields=all`.

Preserve compiler settings, ABI, constructor and proxy metadata alongside source.
Reconcile build/runtime identity and proxy implementation at the pinned state.
Internal-transaction lists are not complete call traces; historical transactions
need their historical implementation, not today's metadata.

Borrow upstream skills' source-orientation and transaction-evidence guidance
selectively. Contract Review's no-build/test rule and Flow's JSON-only/path rules
belong to their separate scopes; do not import them into the audit workflow.
Acquisition does not authorize verification submissions or broadcasts.

## Halmos and Echidna

Adapt a property against scoped target code, preferably from an existing test.
Neither tool is a mandatory dependency. Check installed version/help and EVM,
compiler and cheatcode compatibility before running; do not assume a Foundry fork
harness transfers unchanged. Halmos also supports bounded stateful invariants.

- **Halmos:** retain assumptions, mocks, initial state, loop/sequence bounds,
  array lengths, path limits, solver version and timeouts. Check that valid inputs
  reach the intended assertions. Make unexpected reverts/overflow explicit when
  those are the property; assertion-only checks may ignore them. Unsupported
  paths, exhausted bounds and solver `unknown`/timeout leave obligations open.
- **Echidna:** retain mode, seed/workers, actors/function filters, sequence length,
  campaign/shrink budget, corpus, coverage and minimized sequences. Check that
  setup/privileged helpers cannot create fake reachability, and that filtering or
  reverts do not prevent useful exploration. A seed alone is insufficient replay
  evidence. RPC-backed campaigns also need pinned state and block environment.
- **Economic optimization:** define units, capital/repayment and applicable fees.
  The best objective found is not a global maximum or an impact upper bound.

Feed results into the existing candidate manifest. Retain actual counterexamples
and replay them concretely where useful; establish deployed applicability
separately. Coverage means exercised code, not closed security obligations.
A second engine does not replace the independent reviewer.

## Primary references

Reviewed 2026-09-09; verify capabilities against the selected release.

- [Etherscan CLI](https://github.com/etherscan/etherscan-cli), [source API](https://docs.etherscan.io/api-reference/endpoint/getsourcecode), [skills](https://github.com/etherscan/skills)
- [Halmos](https://github.com/a16z/halmos), [configuration](https://github.com/a16z/halmos/blob/main/src/halmos/config.py)
- [Echidna](https://github.com/crytic/echidna), [configuration](https://secure-contracts.com/program-analysis/echidna/configuration.html), [optimization](https://secure-contracts.com/program-analysis/echidna/advanced/optimization_mode.html)
