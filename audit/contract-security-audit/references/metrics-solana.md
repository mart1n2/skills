# Solana Smart Contract Audit Metrics

> **Scope:** Solana programs in Rust — native and Anchor. Source-code-verifiable patterns.
>
> **Role in the skill (three-layer model):**
> - `methodology.md` — chain-agnostic truth-gate rationale plus optional atlas/A–J techniques and severity guidance. Claims are true only to the extent supported by target-faithful evidence.
> - `playbook-solana.md` — Solana-native semantics plus optional prompts, recipes, and verification examples.
> - **this file** — the Solana *known-pattern catalog*: gates `[SOL-Gn]`, the vulnerability catalog (vulnerable→fix code pairs, Anchor mitigations, atlas greps), historical incidents. Use it to cross-reference a finding against precedent and to write the remediation.
>
> **Not a checklist.** Absence of a matching pattern is **not** safety — adversarial enumeration (`methodology.md` Axiom 2) is. A finding that matches no pattern here may be a novel class; interrogate it harder, then add it.
>
> **Provenance:** the vulnerability catalog (§ 2) is derived from the [SlowMist Solana Smart Contract Security Best Practices](https://github.com/slowmist/solana-smart-contract-security-best-practices), cross-referenced with the DefiLlama / post-mortem incident record.

---

## 1. Threat Landscape & Gate Index

Solana programs operate on transaction-selected accounts under runtime and
program constraints, making account validation a recurring incident class. The
catalog below is historical precedent, not a claim that every account or every
missing check is attacker-controlled or exploitable.

| Class | Example incidents |
|-------|-------------------|
| **Account ownership / type confusion** | Cashio $48M (fake collateral, missing owner check) |
| **Sysvar address / signature verification** | Wormhole $326M (unverified Instructions sysvar enabled forged verification state) |
| **Authority / signer binding** | Jet Protocol (PDA signed for any caller's withdrawal — no depositor↔account binding) |
| **Oracle manipulation** | Mango Markets $117M (thin-liquidity spot price on MNGO/USDC) |
| **PDA / seed manipulation** | Non-canonical bump, predictable/shared seeds, privilege-escalating `invoke_signed` |
| **Arithmetic / precision** | Profile-dependent overflow behavior, incorrect rounding, saturating-masks-bug, div-by-zero panic |
| **Off-chain (out of scope)** | Slope wallet $4.5M+, RPC/UI compromises |

### Candidate Trigger Index (independent evidence required)

These are review signals, not automatic vulnerabilities or severities. Establish
the intended property, actor/capabilities, real reachability, consequence, and
target/state fidelity before disposition.

| Gate | Statement | Catalog § |
|------|-----------|-----------|
| **[SOL-G1]** | `account.owner == expected_program` not checked before reading data | 2.1 |
| **[SOL-G2]** | `is_signer` not checked for the authority account | 2.2 |
| **[SOL-G3]** | Writable-account expectations may be inconsistent; runtime rejects unauthorized readonly mutation, so prove a security consequence beyond fail-fast behavior | 2.3 |
| **[SOL-G4]** | Missing or unchecked type discriminator (Anchor defaults to 8 bytes but current versions can customize length) | 2.4 |
| **[SOL-G5]** | Type confusion — same byte layout deserializes as two types | 2.4 |
| **[SOL-G6]** | Non-canonical bump accepted (`create_program_address` + user bump) | 2.6 |
| **[SOL-G7]** | User-controlled seeds collide with privileged PDA | 2.7 |
| **[SOL-G8]** | PDA signer privilege conferred by `invoke_signed` may be overbroad or forwarded by an untrusted CPI target | 2.8 |
| **[SOL-G9]** | Mint authority is a single keypair / EOA | 2.13 |
| **[SOL-G10]** | Upgrade authority is a single hot key | 2.13 |
| **[SOL-G11]** | Account close path callable by / reachable to wrong party; revivable | 2.10 |
| **[SOL-G12]** | DEX spot price used without TWAP / liquidity-depth | 2.12 |
| **[SOL-G13]** | Single oracle source on a volatile asset; no fallback | 2.12 |
| **[SOL-G14]** | Pyth confidence / status / staleness not checked | 2.12 |
| **[SOL-G15]** | SPL token account `owner`/`authority` not bound to the signer | 2.2 |
| **[SOL-G16]** | Token `mint` not validated; downstream assumes a specific mint | 2.11 |
| **[SOL-G17]** | Decimals assumed without reading or independently verifying them for a strictly bound mint | 2.11 |
| **[SOL-G18]** | Initialization actor/bootstrap policy is not bound to the design; permissionless deterministic init may still be safe | 2.5 |
| **[SOL-G19]** | `init` can be replayed (no `is_initialized`/discriminator guard) | 2.5 |
| **[SOL-G20]** | Arbitrary CPI — target program id not checked == expected | 2.9 |
| **[SOL-G21]** | Production-profile arithmetic, error propagation, or operation-specific rounding may violate an invariant | 2.14 |
| **[SOL-G22]** | Token-2022 extension (TransferHook/Fee/DefaultState) changes amount or freezes | 2.11 |
| **[SOL-G23]** | Direct self-CPI recursion or stale post-CPI read violates state-ordering assumptions | 2.9 |

---

## 2. Vulnerability Catalog (vulnerable → fix, with Anchor mitigations)

> Code is abbreviated to the essential lines. "Anchor mitigation" names the constraint/typed-wrapper that closes the gap — most Solana bugs are a raw `AccountInfo` + manual deserialization where a typed wrapper would have enforced the check.

### 2.1 Missing owner / program-id check  ·  [SOL-G1]

Reading an account's data without verifying which program owns it. The attacker fabricates a look-alike account owned by *their* program with forged fields.

```rust
// VULNERABLE — owner never checked; fake Pyth account accepted
let pyth_price_info = next_account_info(iter)?;
let market_price = get_pyth_price(pyth_price_info, clock)?;
```
```rust
// FIX
let oracle_owner = Pubkey::from_str("Oracle Program Pubkey").unwrap();
if pyth_price_info.owner != &oracle_owner { return Err(ProgramError::IllegalOwner); }
```
**Anchor mitigation:** `Account<'info, T>` checks owner automatically; or `#[account(owner = expected::ID)]`.
**Atlas grep:** `next_account_info`, `AccountInfo`, `UncheckedAccount`, `try_from_slice` without a nearby `.owner` check.
**Incident:** Cashio $48M. Wormhole belongs to the distinct Instructions-sysvar/signature-verification class in § 2.15.

### 2.2 Signer & authority-binding  ·  [SOL-G2] / [SOL-G15]

Two distinct failures, often together: (a) the authority account isn't required to *sign*; (b) the authority isn't *bound* to the account it operates on.

```rust
// VULNERABLE (a): authority is raw AccountInfo, never checked as signer
#[derive(Accounts)]
pub struct LogMessage<'info> { authority: AccountInfo<'info> }
// VULNERABLE (b): token.owner read but never tied to the signer
let token = SplTokenAccount::unpack(&ctx.accounts.token.data.borrow())?;
msg!("balance {}", token.amount); // attacker passes victim's token account
```
```rust
// FIX (a)
if !ctx.accounts.authority.is_signer { return Err(ProgramError::MissingRequiredSignature); }
// FIX (b)
if ctx.accounts.authority.key != &token.owner { return Err(ProgramError::InvalidAccountData); }
```
**Anchor mitigation:** `authority: Signer<'info>`; bind with `has_one = authority` or `#[account(constraint = token.owner == authority.key())]` / `token::authority = authority`.
**Atlas grep:** `authority: AccountInfo`, `authority: UncheckedAccount`, `is_signer`, `has_one`.
**Incident:** Jet Protocol — `market_authority` (a PDA) signed every withdrawal, and `deposit_note_account`/`withdraw_account` were never bound to the signing `depositor`, so anyone burned others' notes and routed the underlying to themselves. Fix bound the deposit account to a PDA seeded by `reserve.key() + depositor.key()` and moved burn authority from the PDA to the actual depositor.

### 2.3 Writable declaration / fail-fast behavior  ·  [SOL-G3]

```rust
// FIX (native)
if !state_account.is_writable { return Err(ProgramError::InvalidAccountData); }
```
**Anchor mitigation:** `#[account(mut)]`. The Solana runtime itself rejects data
or lamport mutation without writable privilege and rolls the transaction back;
missing a redundant manual check is not automatically a High vulnerability.
Establish a distinct authorization, integrity, or persistent-liveness consequence.

### 2.4 Discriminator & type cosplay  ·  [SOL-G4] / [SOL-G5]

Two structs with identical layout (`User { authority: Pubkey }` vs `Metadata { account: Pubkey }`) are interchangeable without a type tag, bypassing authorization.

```rust
// VULNERABLE — a Metadata account deserializes equally well as User
let user = User::try_from_slice(&ctx.accounts.user.data.borrow()).unwrap();
```
```rust
// FIX — explicit discriminant, checked
if user.discriminant != AccountDiscriminant::User { return Err(ProgramError::InvalidAccountData); }
```
**Anchor mitigation:** `#[account]` adds and checks a discriminator (8 bytes by
default; current Anchor supports custom lengths). Pin the Anchor version and
expected discriminator rather than assuming a universal length.
**Atlas grep:** `try_from_slice`, `unpack(` on raw account data without a discriminator/owner check.

### 2.5 Initialization & reinitialization  ·  [SOL-G18] / [SOL-G19]

First-caller initialization is risky when it captures bootstrap authority or
configuration contrary to the design; permissionless deterministic
initialization can be safe. Replayable initialization is distinct and may
overwrite authority or other protected state.

```rust
// VULNERABLE — init has no signer/authority check; or no initialized guard
pub fn initialize(ctx: Context<Initialize>) -> ProgramResult {
    let mut user = User::try_from_slice(&ctx.accounts.user.data.borrow()).unwrap();
    user.authority = ctx.accounts.authority.key(); // callable repeatedly
    user.serialize(&mut *ctx.accounts.user.try_borrow_mut_data()?)?; Ok(())
}
```
```rust
// POSSIBLE FIX — enforce the intended bootstrap authority/policy and guard reinit
if user.is_initialized { return Err(ProgramError::AccountAlreadyInitialized); }
user.is_initialized = true;
```
**Anchor mitigation:** `#[account(init, payer = ..., space = ...)]` fails if the
account already exists; use `init_if_needed` only with an explicit guard. For
global init, enforce the intended authority or deterministic bootstrap policy;
permissionless initialization is not inherently unsafe.
**Atlas grep:** `fn initialize`, `init_if_needed`, `is_initialized`.

### 2.6 Bump seed canonicalization  ·  [SOL-G6]

`create_program_address` yields a *different valid PDA for each valid bump*; an attacker-supplied non-canonical bump produces a different-but-valid account, breaking "one PDA per key."

```rust
// VULNERABLE — bump is untrusted user input
let addr = Pubkey::create_program_address(&[key.to_le_bytes().as_ref(), &[bump]], program_id)?;
```
```rust
// FIX — derive canonical bump and compare both address and bump
let (addr, expected_bump) = Pubkey::find_program_address(&[key.to_le_bytes().as_ref()], program_id);
if expected_bump != bump { return Err(ProgramError::InvalidArgument); }
```
**Anchor mitigation:** `#[account(seeds = [...], bump)]` enforces the canonical bump; `bump = stored_bump` after storing it at init.

### 2.7 / 2.8 PDA substitution, seed collision & sharing  ·  [SOL-G7] / [SOL-G8]

- **Substitution:** a PDA derived from an account whose value the attacker controls (e.g., a replaceable config account) validates against attacker data. *Fix:* derive from a unique, trusted account (the program's config).
- **Sharing / signer forwarding:** if one signer PDA is accepted across roles or
  destinations that should be isolated, or signer privilege is given to an
  untrusted CPI target, the actor may redirect/forward authority. Prove the
  missing binding against the intended role; a particular seed layout is not
  universally required.

```rust
// VULNERABLE — pool PDA seeded only by mint; withdraw_destination unconstrained
let seeds = &[ctx.accounts.pool.mint.as_ref(), &[ctx.accounts.pool.bump]];
token::transfer(ctx.accounts.transfer_ctx().with_signer(&[seeds]), amount)?;
```
```rust
// FIX — seed by destination, bind accounts with has_one
#[account(has_one = vault, has_one = withdraw_destination,
          seeds = [b"pool", withdraw_destination.key().as_ref()], bump = pool.bump)]
pool: Account<'info, TokenPool>,
```
**Atlas grep:** `find_program_address`, `create_program_address`, `with_signer`, `invoke_signed`, `seeds = [`.

### 2.9 Arbitrary CPI & post-CPI staleness  ·  [SOL-G20] / [SOL-G23]

```rust
// VULNERABLE — token_program is whatever the caller passed; never validated
invoke(&spl_token::instruction::transfer(ctx.accounts.token_program.key, ...)?, &[...])?;
```
```rust
// FIX
if ctx.accounts.token_program.key != &spl_token::ID { return Err(ProgramError::IncorrectProgramId); }
```
**Recursion / staleness:** Solana permits direct self-CPI recursion (`A → A`) but rejects indirect `A → B → A` re-entry. Separately, Anchor does **not** reload deserialized accounts after a CPI — reading `mint.supply` after `mint_to` uses the pre-CPI value.
```rust
// FIX (staleness) — reload after CPI before reusing fields
anchor_spl::token::mint_to(cpi_ctx, amount)?;
ctx.accounts.liquidity_mint.reload()?;
```
**Anchor mitigation:** `Program<'info, Token>` for CPI target id; `anchor_spl` CPI helpers; `.reload()` after CPI.
**Atlas grep:** `invoke(`, `invoke_signed(`, `token_program`, `CpiContext`, `.reload()`.

### 2.10 Duplicate mutable accounts & close/revive  ·  [SOL-G11]

```rust
// VULNERABLE (duplicate mut) — if user_a == user_b, second write clobbers first
ctx.accounts.user_a.data = a; ctx.accounts.user_b.data = b;
// FIX
if ctx.accounts.user_a.key() == ctx.accounts.user_b.key() { return Err(ProgramError::InvalidArgument); }
```
**Close/revive:** a custom close that only drains lamports can leave stale data
usable after same-transaction refunding. Use the pinned framework's complete
close semantics (for example Anchor `#[account(close = recipient)]`) or explicitly
invalidate data/ownership and reject the closed state on every read path. A
lamport-positive check alone does not stop revival after refunding.
**Anchor mitigation:** `#[account(constraint = a.key() != b.key())]`; `#[account(close = dest)]`.

### 2.11 Token mint / decimals / Token-2022  ·  [SOL-G16] / [SOL-G17] / [SOL-G22]

- Validate the token account's `mint` against the expected mint; downstream accounting assumes it.
- Read `decimals` from the mint, or independently verify and pin them when the
  mint address is strictly bound before using a constant.
- **Token-2022 extensions** change behavior: `TransferFeeConfig` (received < sent — measure the delta), `TransferHook` (arbitrary program runs on transfer — whitelist or reject), `DefaultAccountState` (new accounts frozen), `ConfidentialTransfer`. Use `transfer_checked` (enforces mint+decimals).
**Anchor mitigation:** `token::mint = expected`, `InterfaceAccount<'info, Mint>` for Token-2022, `transfer_checked`.

### 2.12 Oracle  ·  [SOL-G12] / [SOL-G13] / [SOL-G14]

- **Pyth:** validate the applicable verification status, publish-time staleness,
  positive/valid price representation, and a protocol/asset/use-case-specific
  confidence policy. Use adverse-side pricing or caps where appropriate; no
  universal 1–2% threshold establishes safety.
- **DEX spot:** treat Raydium/Orca/Meteora reserve-derived prices as manipulable
  inputs. Quantify manipulation cost, available atomic capital, limits, and
  extractable impact; use an appropriately defended construction such as TWAP,
  aggregation, depth checks, or protocol-specific bounds where required.
- **Derived value:** establish whether raw `total/supply` matches the intended
  donation and accounting semantics. Test first-depositor and donation effects;
  independent valuation, dead shares, or a virtual offset are possible defenses,
  not universal requirements.
```rust
if pyth_price.agg.status != PriceStatus::Trading { return Err(ErrorCode::InvalidPythConfig); }
```

### 2.13 Authority concentration & upgrade  ·  [SOL-G9] / [SOL-G10]

- Record mint, freeze, and BPF upgrade authorities, their custody, delay, and
  maximum impact. A hot key can be a material trust assumption because it may
  mint, freeze, or substitute code, but it is a finding only when that authority
  violates the scoped trust model or creates an established security consequence.
**Atlas grep:** `set_authority`, `upgrade_authority`, `freeze_authority`; `solana program show` for the deployed authority.

### 2.14 Arithmetic & precision  ·  [SOL-G21]

- Pin and inspect the production profile's `overflow-checks`; never assume all
  release builds silently wrap. Where overflow is invalid, use
  `checked_add/sub/mul/div` and propagate `None` as an explicit program error
  (`ok_or(...)?`). `unwrap()` can turn actor-controlled overflow into a panic/DoS.
- Treat `saturating_*` as a candidate only when the invariant requires rejection
  or another result at the boundary; saturation can be intentional.
- Select floor/ceil per operation and invariant, then measure the complete
  round-trip including fees; no single direction is safe for every operation.
- Guard actor-controlled denominators where failure violates an invariant or can
  create persistent liveness loss. A division-by-zero failure of one instruction
  is not by itself a protocol-wide DoS.
- Handle every security-relevant `Result`: propagate with `?`, branch explicitly,
  or prove why ignoring a particular result is safe. A dropped `Err` can let the
  caller continue under a false success assumption.
**Atlas grep:** `\b\w+\s*[+\-*/]\s*\w+` near amount/balance fields without `checked_`; `saturating_`, `try_round_u64`, `unwrap()`.

### 2.15 Sysvar substitution  ·  (Wormhole class)

A sysvar passed as raw `AccountInfo` can be substituted unless its address is
validated. Wormhole's vulnerable verification path used an unchecked instruction
loader against an unverified `instruction_acc`, letting a forged Instructions
account fake the prior signature-verification evidence.

```rust
// FIX
if *accs.instruction_acc.key != solana_program::sysvar::instructions::id() {
    return Err(SolitaireError::InvalidSysvar(*accs.instruction_acc.key));
}
```
**Anchor mitigation:** for the Instructions sysvar, constrain its address with
the SDK's canonical ID and use the checked instruction-loading API; use
appropriate typed `Sysvar<'info, T>` or canonical address constraints for other
supported sysvars/program accounts. Prefer SDK constants over copied address
strings.

### 2.16 Timely state reset

When changing an account's owner/authority, reset stale privileged state — `delegate`, `delegated_amount`, `close_authority` — or the old delegate retains power over the new owner's account.

---

## 3. Reference depth (beyond SlowMist)

These complement the catalog; they are not in the SlowMist primer but recur in Solana DeFi.

### 3.1 Token-2022 extension matrix
TransferHook (bind/validate hook semantics) · TransferFeeConfig (delta-measure
receipt) · ConfidentialTransfer (amount opacity) · DefaultAccountState
(default-frozen) · MetadataPointer (may be mutable; do not use unbound metadata
as authority) · ExtraAccountMetas (missing required metas can make transfers
fail). Apply only the extensions present on the scoped mint.

### 3.2 DeFi logic
**Lending:** derive each asset's collateral, liquidation, incentive, cap, and
bad-debt invariants from the design and market assumptions. **AMM:** recheck the
implemented invariant across operations, tick-array boundaries, and actual mint
authority. **Yield vault:** test reward accrual and first-depositor/donation
economics. No fixed parameter or authority layout is universally safe.

### 3.3 Compute & DoS
Test common and adversarial paths against the transaction's actual compute-unit
limit (which may override defaults) and requested/default heap frame. Heap-frame
requests are constrained to the supported 32–256 KiB range; do not impose a
blanket `<32KB` rule. Bound input-driven loops and state growth, and preserve a
recovery/closure path where the design requires one.

### 3.4 Clock & randomness
`Clock::get()` for time; slot timing approximate (~400ms, variable) — not for fine-grained financial logic; never use slot/timestamp for randomness (cluster-predictable).

### 3.5 Dependency & integration
Bind CPI targets and interfaces to the protocol's intended trust model. A fixed
program id, allowlist, verified interface, or another sound constraint may be
appropriate; an intentionally generic router needs evidence that its downstream
effects remain safe. Pin the deployed integration version and record unaudited
dependencies on critical paths.

---

## 4. Case studies (historical mechanism precedent)

- **Cashio $48M** — missing owner check ([SOL-G1]): accepted a fake Saber-LP account, minted $48M CASH against nothing. Optional test shape: `playbook-solana.md` Pattern S1.
- **Wormhole $326M** — forged Instructions sysvar (§ 2.15): faked guardian signatures, minted wrapped ETH. Optional test shape: fabricated-sysvar variant of Harness A.
- **Mango $117M** — thin-liquidity spot oracle ([SOL-G12]): pumped MNGO perp index, borrowed against it. Optional verification shape: Pattern S6, bound to the claimed target/state by any sound method.
- **Jet Protocol** — PDA signed for any caller, no depositor↔account binding ([SOL-G15]/[SOL-G2]). Optional test shape: Pattern S3.

---

## 5. Toolchain

Optional build, fuzz, proof, and harness techniques live in `playbook-solana.md §§ 3–4`. Manual review, agents, SAST, fuzzing, symbolic/formal methods, transaction analysis, and any other sound approach may be used. Raw scanner output is a lead rather than proof by itself; every accepted claim passes the same target, reachability, impact, falsification, and independent-triage gates.

**Status:** production. As the post-mortem record matures, re-pull the DefiLlama Solana subset quarterly and fold new classes into § 2.
