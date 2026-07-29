# Solana Audit Playbook (Native Semantics + Optional Techniques)

> **What this is.** Solana/Anchor-native semantics, attack surfaces, and optional discovery/verification techniques. The ladder, atlas recipes, and harnesses are accelerators, not required methods.
>
> **Companion:** `metrics-solana.md` is the known-pattern catalog (the [SOL-Gn] gates, SlowMist vuln entries, historical incidents, and the secure-pattern fixes). This file can generate and test hypotheses; that file can cross-reference precedent and inform remediation. Neither is a checklist or required discovery path. Truth comes from target-faithful, independently challenged evidence, regardless of method.
>
> **Status:** production. EVM's playbook content lives inline in `methodology.md`; Solana and Sui get dedicated playbooks because their primitives diverge far enough from the Solidity lingua franca that translation-in-your-head is lossy.

---

## 0. The Solana execution model that rewrites the threat model

Solana's account/runtime model invalidates several EVM assumptions. Use the
semantics below when evaluating a claim, whether or not the optional atlas is
used.

| Solana reality | EVM instinct it breaks | Audit consequence |
|----------------|------------------------|-------------------|
| **Programs keep mutable application state in accounts supplied to instructions.** | "The contract owns its storage." | The transaction selects account addresses, while runtime rules and program checks constrain which selections are valid. Establish owner, type, address, and authority relationships for every account material to the claim. |
| **Stored account state contains lamports, data, owner, executable, and rent epoch; signer/writable privileges are transaction context.** | Typed storage with access control baked in. | Type is *your interpretation* of `data`. Deserializing bytes as `User` does not prove it *is* a `User` (type cosplay). Validate the account owner/type/address and the transaction privileges the logic relies on. |
| **The runtime enforces signatures, write locks/privilege, and account-owner modification rules; application authority relationships remain program logic.** | `msg.sender`, `require(owner == ...)`. | A pubkey passed as "authority" is not authorized unless the intended signer and data/address relationships are established. When logic trusts account data, establish its required owner/type/address properties. |
| **PDAs (program-derived addresses) are off-curve addresses a program can sign for.** | `address(this)` / contract-held keys. | Seeds + bump derive the address. A non-canonical bump can yield a *second valid address*, violating uniqueness assumptions; it is not an address collision. Shared seeds can let one PDA signer authorize overly broad actions. |
| **CPI (cross-program invocation) is the only way programs compose, and the target program is an account you pass in.** | `IERC20(token).transfer(...)` to a fixed, type-checked address. | If you `invoke` whatever `token_program` account was passed without checking its key == `spl_token::ID`, the attacker substitutes a malicious program that fakes the transfer interface (arbitrary CPI). |
| **Rent collection is deprecated; new accounts and post-transaction balances must not enter a rent-paying state. Closing normally drains lamports and invalidates data.** | `selfdestruct`/storage clearing. | A custom close flow that drains lamports without clearing/marking data can be re-funded in the same transaction and reused with stale state (close/revive bug). |
| **Fallback reentrancy and indirect CPI re-entry differ from EVM.** | The transplanted assumption that any CPI target can call back `A → B → A`. | The runtime rejects indirect re-entry with `ReentrancyNotAllowed`; direct self-recursion (`A → A`) is allowed within stack limits. Audit self-CPI recursion, instruction ordering, and post-CPI stale state; Anchor account structs are **not auto-reloaded after CPI**. |
| **Anchor adds a validation layer (`#[account(...)]` constraints plus account discriminators, defaulting to 8 bytes but supporting custom discriminator lengths in current Anchor).** | Solidity modifiers. | Anchor mitigates many classes *if used*. Raw `AccountInfo` / manual deserialization or incomplete constraints can bypass those checks. Audit the actual wrapper and discriminator semantics for the pinned version. |
| **Every transaction is atomic and can pack many instructions.** | One external call per tx (mostly). | Atomic instruction composition does not require a flash loan *for atomicity*; obtaining temporary capital may still require flash liquidity. Model the actual sequence and capital source. |
| **Token balances are SPL token *accounts*, not a `balanceOf` mapping.** | `token.balanceOf(x)`. | A token account has its own `owner` (the authority who controls it) distinct from the account's program-owner (`spl_token::ID`). Establish every owner, mint, and decimal assumption material to the effect. |

**Minimum Solana semantic baseline:** for every account material to a claim, ask
what is proven about program owner, signer/writable transaction privileges,
type/discriminator, data-level authority, and address binding versus what the
logic assumes. This baseline does not limit other discovery methods or attack
classes; any gap remains a candidate until consequence and reachability are
established.

---

## 1. Atlas adaptation for Solana (Pass P)

If using the optional atlas from `methodology.md § P`, run `scripts/atlas-inventory.sh` (it auto-detects `.rs`) and enrich it with these Solana-native columns. Other discovery/coverage methods are equally valid when their scope and blind spots are recorded.

### P.1 Sinks — what moves value or alters accounting

Grep targets (the script seeds these; verify completeness):

- `token::transfer`, `token::transfer_checked`, `transfer_checked`, anchor_spl `Transfer` CPI
- `token::mint_to`, `token::burn`, `mint_to`, `burn`
- `**...lamports.borrow_mut() =`, `.try_borrow_mut_lamports()`, `**ctx.accounts.x.to_account_info().lamports.borrow_mut()`
- `system_program::transfer`, `invoke`/`invoke_signed` to the system or token program
- direct writes to a deserialized balance/debt/amount field (`acct.amount =`, `position.debt +=`, `vault.total -=`)
- `set_authority`, `approve` (delegate), `freeze_account`, `close_account`

**Per-sink Solana columns to add:** which accounts the sink writes/moves between · whether a **PDA signer** authorizes it (and with which seeds) · the `mint` and `decimals` assumed · whether the amount is checked-arithmetic.

### P.2 Gates — state reads used as authorization

On Solana the gate set is wider than `if/require`. Enumerate **all** of:

- `require!`, `require_eq!`, `require_keys_eq!`, `require_gt!`, `assert!`, `if ... return Err`
- **the implicit Anchor gates** in `#[account(...)]`: `has_one = x`, `constraint = ...`, `seeds = [...]`, `bump`, `owner = ...`, `address = ...`, `signer`, `mut`, `init`, `init_if_needed`, `close = ...`, `token::authority`, `token::mint`, `mint::authority`
- the type-level gates: `Signer<'info>`, `Account<'info, T>` (enforces owner+discriminator), `Program<'info, Token>`, `Sysvar<'info, T>`, `InterfaceAccount`
- `match account.state { ... }`, enum-state comparisons
- `account.is_signer`, `account.is_writable`, `account.owner == ...` (native, non-Anchor)

> **Raw-account review:** `AccountInfo<'info>` and `UncheckedAccount` provide no
> implicit owner/discriminator/signer validation. If using this optional
> inventory, record which properties the protected effect actually relies on and
> where each is enforced—typed wrapper, explicit check, derivation, or another
> mechanism. A raw account or absent redundant check is a lead, not a finding.

### P.3 Writes — every assignment to a gating field

Same as EVM, plus: Borsh `serialize` back to `data.borrow_mut()`, `try_from_slice` + mutate + write-back, `init` handlers, `set_authority`/`approve` (they write the token account's authority/delegate gates).

### P.4/P.5 Paths, Intent, Delta

Identical discipline. The Solana-specific delta hotspots: any instruction whose account context contains a privileged action but whose authority account is `AccountInfo`/`UncheckedAccount` (not `Signer` + bound by `has_one`/`address`); any CPI whose program account is not a typed `Program<_, _>`; any PDA whose bump is a function argument rather than derived.

---

## 2. The Solana Hypothesis Ladder

This native ladder is an optional high-recall prompt set. Apply it wherever useful; leads from it or any other discovery method become schema-complete files under `triage/candidates/`, never direct `findings.md` rows. Apply `triage.md` before promotion.

### Identity & Authorization

1. **When the design requires a signature, is the authority a `Signer` or explicitly checked with `is_signer`?** A raw `AccountInfo`/`UncheckedAccount` can name any pubkey; prove a protected effect relies on that unproven signature. (SlowMist: *Signer authorization*, *Account signer check*. [SOL-G2])
2. **Is the authority's data-level identity bound to the account it controls?** Establish the intended signer, owner, delegate, or role relationship using explicit checks or typed constraints. Otherwise an actor may sign as themselves while operating on a victim's account. (SlowMist: *Account data matching*, *Owner checks*; the **Jet Protocol** drain. [SOL-G15])
3. **Does a PDA sign for this action, and are its seeds and in-body bindings specific enough for the intended role?** If one signer PDA authorizes destinations or roles that should be isolated, an actor may redirect another user's effect. Bind the relevant role/destination by seeds, account data, or equivalent checks. (SlowMist: *PDA sharing*. [SOL-G7/G8])
4. **Can I acquire an unintended bootstrap privilege by initializing first?** Permissionless deterministic initialization can be intended; it is a defect only when first-caller control sets or captures authority/configuration contrary to the design. (SlowMist: *Missing check for permission of caller*, *Check initialize*. [SOL-G18])
5. **Is `msg`/authority derived from `tx_context`-style ambient identity, or from a passed account I control?** Authorization keyed on a parameter the attacker provides (not on the signer) is a bypass. (methodology ladder Q6.)

### Account Validation & Type Safety

6. **Is `account.owner == expected_program` checked before reading the account's data?** If not, an actor may fabricate a look-alike account owned by another program with forged fields (the Cashio fake-collateral class). Establish whether an equivalent typed-owner/address check exists before opening a candidate. (SlowMist: *Account owner / program id check*; **Cashio $48M**. [SOL-G1])
7. **Does the type have a discriminator, and is it checked?** Two structs with identical byte layout are interchangeable without one (type cosplay) — a `Metadata` deserializes fine as a `User`. (SlowMist: *Type cosplay*. [SOL-G4/G5])
8. **Can this account actually be re-initialized?** Trace allocation, ownership,
deserialization/discriminator rules, and every guard. Only open a candidate when
a reachable repeat call can overwrite protected state. (SlowMist: *Account
initialized check*, *Check initialize*. [SOL-G19])
9. **Do writable declarations match the intended mutation surface?** The runtime rejects unauthorized read-only mutation, so a missing redundant manual `is_writable` check is not itself an exploit; prove a distinct authorization, integrity, or persistent-liveness consequence. (SlowMist: *Account writable check*. [SOL-G3])
10. **Two mutable accounts of the same type—can aliasing violate the intended invariant?** Passing the same account twice can merge roles or make exit/write-back order matter; prove the resulting state/effect. (SlowMist: *Duplicate mutable accounts*.)
11. **Is a sysvar/program account passed as raw `AccountInfo` without an address check?** Forged "Instructions sysvar" faked Wormhole's signature verification. (SlowMist: *Missing system account check*, *Sysvar address checking*; **Wormhole $326M**. [implicit])
12. **After a CPI, does the code re-read a deserialized account's fields without `reload()`?** Anchor structs hold pre-CPI data; e.g. reading `mint.supply` after `mint_to` uses the stale supply. (SlowMist: *Account reloading*.)
13. **Could this account have been closed-and-revived?** Reading an account whose lamports were zeroed but data not cleared, then refunded within the tx. (SlowMist: *Closing accounts*, *Missing check for lamports*. [SOL-G11])

### PDA & Seeds

14. **Does the design rely on one canonical PDA per logical key?** If so, an attacker-supplied bump accepted via `create_program_address` may create another valid PDA; derive or compare the canonical/stored bump. (SlowMist: *Bump seed canonicalization*. [SOL-G6])
15. **Can user-controlled seed encoding be ambiguous with a privileged PDA domain?** Prove an actual alternative seed tuple/address and protected consequence; a missing-looking prefix alone is not a finding. ([SOL-G7])
16. **Does `invoke_signed` confer PDA signer privilege to an untrusted CPI target that can forward that signer in nested CPIs?** The callee does not learn the seeds, but signer privilege can propagate within the invocation. Bind the target and the PDA's permitted role. ([SOL-G8])

### Numeric & Boundary

17. **Does arithmetic behavior match the pinned production profile?** Rust overflow checks are profile/`overflow-checks` dependent; do not rely on defaults. Use checked arithmetic with explicit error propagation where overflow is invalid. (SlowMist: *Integer overflow or underflow*. [SOL-G21])
18. **Does `saturating_*` mask a condition the invariant requires to reject?** Saturation can be intentional; prove that the boundary result changes a security-relevant state/effect. (SlowMist: *Inaccurate calculation results*.)
19. **Does each operation round in the direction required by its invariant, including fees and the full round trip?** No single floor/ceil rule is safe for every mint, redeem, borrow, repay, or liquidation path. (SlowMist: *Loss of precision*.)
20. **Can an actor drive a denominator to zero?** Division by zero fails the instruction; establish an integrity loss or an actor-reachable persistent liveness consequence before calling it a vulnerability. (SlowMist: *Panic due to division by zero*.)
21. **Are token decimals read from the mint or independently verified for a strictly bound mint before a constant is used?** Cross-mint/decimal drift is the risk. ([SOL-G17])

### Token / CPI / External

22. **Is the CPI target program-id checked against the expected program?** Else arbitrary-CPI to a fake token program. (SlowMist: *Arbitrary CPI*. [SOL-G20])
23. **Is a security-relevant `Result` ignored or misinterpreted?** Prove that execution continues under a false success assumption and reaches a consequence. (SlowMist: *Error not handled*.)
24. **Is the SPL token account's `mint` and `owner` validated against expectations?** ([SOL-G15/G16])
25. **Token-2022: does the scoped mint carry a TransferHook / TransferFee / DefaultAccountState extension that changes receipt or liveness semantics?** Measure actual deltas and validate, support, or exclude the extension under the protocol's token model. ([SOL-G22])
26. **When authority/owner of a token account changes, are `delegate` / `delegated_amount` / `close_authority` reset?** Stale delegate retains power. (SlowMist: *Timely state reset*.)

### Oracle

27. **Does the Pyth integration validate the version-appropriate verification/status signal, publish time, price representation, and a use-case-specific confidence policy?** (SlowMist: *Pyth oracle check*. [SOL-G12/G13/G14])
28. **Can a DEX-derived price be manipulated profitably under actual depth, bounds, atomic capital, fees, and protocol limits?** TWAP/liquidity-depth is one defense family, not a mandatory format. **Mango $117M**. ([SOL-G12])

### Composition / Atomicity / MEV

29. **What can the actor do by packing instructions in one atomic tx?** For example deposit→pump-price→borrow→withdraw; atomic composition is native, while any required temporary capital source must still be modeled. (methodology B.8 analog.)
30. **Can direct self-CPI recurse into a state-mutating instruction, or can post-CPI stale account data / later top-level instructions violate ordering assumptions?** Do not propose an `A → B → A` callback: the runtime rejects indirect re-entry. ([SOL-G23])

### Liveness / DoS

31. **Can an actor reach a persistent state where legitimate instructions exceed declared compute/heap limits or inevitably fail, with no recovery/alternate path?** A single reverting instruction is not a program-wide DoS. (`metrics-solana.md § 3.3`.)

### Cross-Boundary & Business Logic

32–40. When useful, adapt `methodology.md` ladder Q32–40 as optional X/J prompts. Solana-native seam hotspots include two programs tracking the same balance through separate accounts, a vault PDA whose share math reads a token-account amount moved by another instruction or donation, and integrations whose CPI semantics differ from the caller's assumptions. Other discovery methods remain equally valid.

---

## 3. Optional verification techniques

Any sound method may verify a Solana candidate. The techniques below are examples. Evidence must establish the claimed reachability and consequence and must not overstate deployment/state fidelity.

### 3.1 Technique and claim fit (Solana)

| Mode | Tool | When | Proves | Does NOT prove |
|------|------|------|--------|----------------|
| **Coherent deployed-state replay** | Frozen/reusable validator ledger assembled from a single RPC context-slot snapshot; adapt `fork_replay.sh` after snapshot capture | One method for a deployed-state claim; capture the program-data account plus every relevant account/program/sysvar dependency and feature/clock treatment. | The exploit reproduces against the documented coherent snapshot. | Transaction inclusion outside the snapshot, omitted dependencies, or future state. Sequential live `--clone` fetches are not coherent by themselves. |
| **Instruction-level** | [Mollusk](https://github.com/anza-xyz/mollusk-svm) | Fast, deterministic single/multi-instruction exploits; CU profiling; fuzzing. No validator spin-up. | The instruction logic is exploitable given crafted accounts. | That the live deployment's *current account state* is drainable (you construct the accounts). |
| **In-process SVM** | [LiteSVM](https://github.com/LiteSVM/litesvm) (Rust or TS bindings) | Fast option for logic PoCs and pre-deployment audits; easy account setup. | The program behavior under the constructed accounts and state. | Same caveat as Mollusk. |
| **Integration (TS)** | `anchor test` / Bankrun (`solana-bankrun`) | When the project already ships Anchor TS tests; reuse their client + IDL. | End-to-end exploit through the real client path. | Current deployed-state exploitability unless it loads the same coherent snapshot. |

**Claim boundary:** current-deployment exploitability requires evidence bound to the deployed program, relevant accounts/configuration, and state. A coherent snapshot replay is one way to do that; a historical transaction/trace, faithful state analysis, or another sound deployed-target method may also qualify. LiteSVM/Mollusk with constructed accounts ordinarily supports logic claims only. An incomplete or cross-slot clone does not establish coherence merely because it ran.

### 3.2 Harness A — LiteSVM (Rust example)

```rust
// poc/src/lib.rs  — cargo add litesvm solana-sdk spl-token
use litesvm::LiteSVM;
use solana_sdk::{
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey, signature::{Keypair, Signer}, transaction::Transaction,
};

fn setup() -> (LiteSVM, Keypair) {
    let mut svm = LiteSVM::new();
    // Load the target program from a built .so (anchor build → target/deploy/<name>.so)
    let program_id = Pubkey::new_unique();
    svm.add_program_from_file(program_id, "../target/deploy/target_program.so").unwrap();
    let attacker = Keypair::new();
    svm.airdrop(&attacker.pubkey(), 10_000_000_000).unwrap();
    (svm, attacker)
}

#[test]
fn poc_signer_bypass() {
    // Hypothesis (Ladder Q1 / SlowMist "Signer authorization"):
    // `log_message`/`privileged_ix` takes `authority: AccountInfo` and never checks is_signer.
    // Attacker passes the VICTIM's pubkey as authority while signing only as themselves.
    let (mut svm, attacker) = setup();
    let victim = Pubkey::new_unique();

    let ix = Instruction {
        program_id: TARGET,
        accounts: vec![
            AccountMeta::new(victim, false),            // authority — NOT a signer
            AccountMeta::new(attacker.pubkey(), true),  // fee payer only
        ],
        data: vec![/* discriminator + args */],
    };
    let tx = Transaction::new_signed_with_payer(
        &[ix], Some(&attacker.pubkey()), &[&attacker], svm.latest_blockhash());

    let res = svm.send_transaction(tx);
    // If the program accepted the unsigned authority, the privileged effect happened.
    assert!(res.is_ok(), "BUG: privileged ix executed without authority's signature");
    // Then assert the fund-effect (e.g., victim's token account debited / attacker credited).
}
```

### 3.3 Harness B — exploratory live-clone scaffold

```bash
# 1. Discover the accounts the exploit touches (program, config/PDA, victim vaults, oracle).
solana account "$ORACLE_ACCOUNT" --url mainnet-beta --output json > evidence/oracle.json

# 2. Clone program + accounts into a local validator for exploration.
# These RPC reads may come from different slots; this is not a coherent deployed
# snapshot unless the capture procedure separately proves one context slot.
solana-test-validator \
  --clone-upgradeable-program "$PROGRAM_ID" \
  --clone "$CONFIG_PDA" --clone "$VICTIM_VAULT" --clone "$ORACLE_ACCOUNT" \
  --clone "$PYTH_PRICE_ACCOUNT" \
  --url mainnet-beta --reset --quiet &
VALIDATOR_PID=$!
solana config set --url localhost

# 3. Run the exploit instruction sequence (Anchor TS / Bankrun / a Rust client),
#    asserting attacker token balance increased and target decreased.
anchor test --skip-build --skip-deploy --skip-local-validator -- --features "exploit-${CANDIDATE_NN}" \
  2>&1 | tee "poc/C-${CANDIDATE_NN}.log"

kill "$VALIDATOR_PID"
```

### 3.4 Solana PoC Pattern Library

Concrete code for the highest-frequency shapes; the rest reuse Harness A with the noted change. Each maps to a Ladder question and a `metrics-solana.md` gate.

#### Pattern S1 — Account substitution (missing owner check)  ·  Ladder Q6 · [SOL-G1] · Cashio

```rust
#[test]
fn poc_fake_oracle_account() {
    let (mut svm, attacker) = setup();
    // Build a fake "price" account OWNED BY THE ATTACKER'S PROGRAM (not the real oracle program),
    // with forged price bytes. The target never checks `price_acct.owner == ORACLE_PROGRAM`.
    let fake_price = Pubkey::new_unique();
    svm.set_account(fake_price, fabricated_price_account(/*price=*/ 1_000_000_000)).unwrap();
    // Call the vulnerable ix that reads the price and mints/borrows against it.
    // Assert: attacker minted/borrowed against a price the real oracle never published.
    // (assert minted_amount > 0 with zero real collateral)
}
```

#### Pattern S2 — Arbitrary CPI (fake token program)  ·  Ladder Q22 · [SOL-G20]

```rust
// Deploy a malicious "token program" whose `transfer` instruction is a no-op (debits nothing)
// but returns Ok. Pass it as `token_program`. Target invokes it without checking key == spl_token::ID.
// Assert: attacker received credit for a "deposit" that never moved real tokens.
let evil_token = Pubkey::new_unique();
svm.add_program_from_file(evil_token, "../target/deploy/evil_token.so").unwrap();
// ix.accounts[token_program_index] = AccountMeta::new_readonly(evil_token, false);
```

#### Pattern S3 — PDA sharing → drain to attacker  ·  Ladder Q3 · [SOL-G7/G8] · Jet Protocol

```rust
// The pool PDA signs withdrawals but its seeds = [b"pool", mint] (no destination binding),
// and `withdraw_destination` is unconstrained. Attacker calls withdraw with destination = self.
// Assert: attacker token account += vault balance; vault drained though attacker owns nothing.
```

#### Pattern S4 — Bump non-canonicalization  ·  Ladder Q14 · [SOL-G6]

```rust
// Find a non-canonical bump b' (< canonical) where create_program_address(seeds, b') succeeds.
// Initialize a SECOND "data" account at that valid-but-non-canonical PDA, bypassing the
// uniqueness assumption (the program thinks one PDA per key). Assert two live accounts per key.
```

#### Pattern S5 — Close / revive  ·  Ladder Q13 · [SOL-G11] · SlowMist "Closing accounts"

```rust
// In one tx: (1) call close (zeros lamports, but data not zeroed / no CLOSED discriminator),
// (2) transfer rent-exempt lamports back to the account, (3) call an ix that reads its stale data.
// Assert: a logically-closed position/authority is treated as live.
```

#### Pattern S6 — Atomic oracle manipulation  ·  Ladder Q28 · [SOL-G12] · Mango

```rust
// One atomic tx: obtain the required capital, skew a thin Raydium/Orca pool the
// target reads as spot price, call the vulnerable borrow/liquidate, and unwind.
// Atomicity is native; the evidence must still model the real capital source,
// fees, liquidity, price impact, and net consequence.
// A deployed-state claim additionally needs deployed-target/state binding; a
// coherent replay is one possible method.
```

| SlowMist / gate | Pattern shape | Harness |
|-----------------|---------------|---------|
| Signer authorization, signer check | S1-shape signer bypass (3.2) | A/B |
| Account data matching, owner checks | S1 | A/B |
| Type cosplay, reinitialization | account-setup variant of A | A |
| Arbitrary CPI | S2 | A |
| Duplicate mutable accounts | pass same pubkey twice | A |
| PDA sharing | S3 | A/B |
| Bump canonicalization | S4 | A |
| Closing accounts / lamports | S5 | A |
| Sysvar substitution (Wormhole) | fabricated sysvar account, A | A |
| Account reloading (stale post-CPI) | call CPI then read, assert stale | A |
| Pyth/DEX oracle | S6 | A, B, trace/state analysis, or another faithful method |

### 3.5 Assertion discipline (Solana)

An executable PoC should assert a consequence such as:

- attacker SPL-token net P&L is positive after repaying principal and accounting
  for same-denomination loan/swap/transfer costs; avoid unsigned subtraction by
  comparing ordered values first
- attacker lamports increased net of rent and transaction fees; convert lamports
  and SPL-token amounts to a common unit only with a pinned, validated valuation
  source before aggregating them
- target vault/account `amount` (or lamports) decreased — victim lost
- a state field reached an impossible-by-intent value (e.g., `position.authority == attacker` after an unauthorized init)
- for DoS: prove an actor-reachable persistent state makes all relevant
  legitimate paths fail and no recovery/alternate path remains; one `Err` only
  proves that instruction attempt failed

Other security consequences need their own measurable criterion; the taxonomy is not funds-only.

---

## 4. Toolchain (build · dependency · fuzz · verification)

Use any useful manual or automated technique. Common Solana tools include:

- **`cargo audit`** — dependency advisory DB (RUSTSEC)
- **Trident (Ackee)** — fuzzing for Anchor programs; drive it from the invariants in `methodology.md § C`
- **`anchor build --verifiable`** — produce a deterministic build; it does not compare with chain state
- **`anchor verify -p <lib-name> <program-id>`** (or an explicit local/deployed hash comparison) — verify that build against the deployed program
- **`solana account <pubkey>` + Anchor IDL decode** — inspect deployed state

**Build artifacts:** `anchor build` produces `target/deploy/<program>.so` and `target/idl/<program>.json`. For native (non-Anchor) programs, use `cargo build-sbf`. These artifacts may support tests, analysis, verification, or other methods.

---

## 5. Source acquisition (Phase 1, Solana)

```bash
# Program binary (always available)
solana program dump "$PROGRAM_ID" "$WORKSPACE/contracts/${PROGRAM_ID}.so"

# Open source at the deployment commit (preferred — bytecode-only audits are far weaker)
git clone "$REPO_URL" "$WORKSPACE/contracts/src"
cd "$WORKSPACE/contracts/src" && git checkout "$DEPLOY_COMMIT"

# Produce the deterministic build, then perform the separate deployment comparison
anchor build --verifiable
anchor verify -p "$PROGRAM_LIB_NAME" "$PROGRAM_ID"
# Alternatively compare local and deployed hashes explicitly with solana-verify;
# record the command, program-data hash, IDL result, upgrade authority, and slot.

# Inspect upgrade authority and compare its custody/impact with the stated trust model
solana program show "$PROGRAM_ID"
```

If only the `.so` is available (closed source), say so in scope — the audit is bytecode-level and materially weaker; recommend the team publish a verified build.
