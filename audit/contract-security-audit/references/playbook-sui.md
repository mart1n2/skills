# Sui / Move Audit Playbook (Native Semantics + Optional Techniques)

> **What this is.** Sui/Move-native semantics, attack surfaces, and optional discovery/verification techniques. The ladder, atlas recipes, and harnesses are accelerators, not required methods.
>
> **Companion:** `metrics-sui.md` is the known-pattern catalog (the [SUI-Gn] gates, the SlowMist Move audit primer items, historical incidents, secure-pattern fixes). This file can generate and test hypotheses; that file can cross-reference precedent and inform remediation. Neither is a checklist or required discovery path. Truth comes from target-faithful, independently challenged evidence, regardless of method.
>
> **Status:** production for Sui only. Aptos notes in `metrics-sui.md § 6` are comparative and do not provide a native Aptos ladder, source-verification flow, or PoC harness.

---

## 0. The Move/Sui model that rewrites the threat model

Move's resource model and Sui's object model prevent or reshape many familiar
EVM/Solana failure mechanisms, but they do not bound the discovery space. The
semantics below are a minimum native baseline, not an exhaustive threat model.

| Move/Sui reality | What it deletes | What it concentrates risk into |
|------------------|-----------------|-------------------------------|
| **Arithmetic is overflow-checked by default; the tx aborts on overflow.** | Silent wrapping assumptions for ordinary arithmetic. | Shift counts at or above the type width abort, but high bits shifted out of a fixed-width value are discarded; hand-rolled overflow guards can be wrong. This is the **Cetus** class. (B1) |
| **Move function calls are statically determined (whether imported, fully qualified, or method-syntax); there is no native-token fallback/`receive` hook.** | Fallback-triggered and dynamic-target callback assumptions. | Ordering/composition risk on **shared objects** (consensus-sequenced), and wrong assumptions about a statically known dependency's semantics (X.3). |
| **Resources can't be copied or implicitly dropped; a value of a no-`drop` type must be explicitly consumed.** | Accidental value duplication / silent loss for well-typed values. | **Ability declarations themselves** (`copy`/`drop`/`store`/`key`) are security-relevant. An ability mismatch is a candidate only when real construction, custody, transfer, storage, or destruction paths violate an intended property. (abilities) |
| **Objects have a unique `UID`; current access/ownership forms include address- or object-owned, shared, immutable, and consensus-owned party objects. Wrapping/nesting changes access through containment. Abilities do not determine the live owner mode.** | "anyone can read/write any storage slot." | A shared object has no owner-signature gate and a party object is consensus-versioned, but mutation still requires a type-correct callable function and any authorization/object-binding logic it implements. Verify the actual on-chain owner representation and intended access model. (B5) |
| **Authorization may use capability possession or the authenticated transaction sender.** Holding an `&AdminCap` proves possession; `tx_context::sender` supplies the runtime-authenticated sender and is not mutable by PTB composition. | Assuming every address ACL is spoofable. | Prefer the mechanism intended by the design. For capabilities, audit reachability, abilities, and custody; for sender ACLs, audit the compared address/config, key rotation, sponsored-transaction semantics, and every bypass path. (B4, B8) |
| **`init` runs exactly once at first publish and may optionally receive the module's one-time witness (OTW).** | Re-initialization through `init`. | **Upgrades don't re-run `init`** and **don't auto-update dependencies**; state versioning/migration is explicit. (B9) |
| **Programmable Transaction Blocks (PTBs): one tx chains commands and feeds outputs to later inputs.** | (n/a) | An actor can compose transaction-callable functions in many type-correct orders, subject to visibility, ownership, borrow, object-version, and verifier rules. Do not rely on a preferred UI sequence as a security boundary. (B3, B14) |
| **Flash loans commonly use a "hot potato": a no-ability receipt that must be consumed in the same tx.** | The belief that consumption proves repayment. | The type system forces receipt consumption, not correct settlement. Trace every constructor and reachable consumer/destructor; prove each intended repay/cancel path binds the required asset, amount, parties, and replay domain. Then audit flash-amplified economics/oracles. (B7) |
| **`Coin<T>` is a `key + store` object; `Balance<T>` is a storable non-object value (`store`, without `key/copy/drop`). The live Coin owner mode is state, not an ability. Sui also supports address balances and `Withdrawal<Balance<T>>` flows.** | `balanceOf` mapping confusion. | Track Coin/Balance lifecycle, address-funds sends/redemptions, withdrawal ownership/limits, and settled-balance snapshot semantics. (B6) |

**Minimum Sui semantic baseline:** distinguish live ownership from abilities;
verify the authorization model actually promised (capability, sender, party, or
other binding); and account for Move arithmetic, PTB composition, shared/party
ordering, Coin/Balance/address-funds flows, upgrades, dependencies, and economic
effects. Discovery methods and additional attack classes remain unrestricted.

---

## 1. Atlas adaptation for Sui (Pass P)

If using the optional atlas, run `scripts/atlas-inventory.sh` (auto-detects `.move`) and enrich it with Move-native columns. Other discovery/coverage methods are equally valid when their scope and blind spots are recorded.

### P.1 Sinks — what moves value or alters accounting

Grep targets:

- `transfer::transfer`, `transfer::public_transfer` (and `share_object`/`freeze_object` — irreversible state moves)
- `coin::split`, `coin::join`, `coin::take`, `coin::put`, `coin::from_balance`, `coin::into_balance`
- `balance::split`, `balance::join`, `balance::withdraw_all`, `balance::increase_supply`, `balance::decrease_supply`
- address-balance flows: `balance::send_funds`, `balance::redeem_funds`,
  `balance::withdraw_funds_from_object`, and consumers of
  `Withdrawal<Balance<T>>`; treat `settled_funds_value` as a security-relevant
  commit-start snapshot read when it feeds authorization or value calculations
- `coin::mint`, `coin::burn`, `coin::mint_and_transfer` (require `&mut TreasuryCap`)
- `dynamic_field::add/remove`, `dynamic_object_field::add/remove` (state additions a sink may depend on)

**Optional per-effect columns:** the promised authorization mechanism
(capability/sender/party/object binding/permissionless) · actual on-chain owner
mode of each object · whether a hot-potato or `Withdrawal` gates it · the
Coin/Balance/address-funds destination and snapshot/version assumptions.

### P.2 Gates — authorization reads

Move gates are mostly *type-and-capability shaped*, not `if`-shaped. Enumerate **all** of:

- `assert!(...)`, `assert_eq!`, explicit `if (...) abort` / error codes
- **the capability gates**: any function parameter of type `&Cap`, `&mut Cap`, `&AdminCap`, `&mut TreasuryCap`, `&UpgradeCap` — possession *is* the authorization
- **witness/OTW gates**: `T: drop` alone is only a regular witness bound; a
  generic library that requires an OTW must validate
  `types::is_one_time_witness`, while a true OTW is system-created only for
  `init`
- **the callable-surface gates**: `public` / `public(package)` (formerly
  `public(friend)`) / private visibility, plus the separate `entry`
  transaction-boundary modifier
- **the ownership/access shape**: address/object-owned, shared, immutable, or
  consensus-owned party; shared inputs can appear by `&`, `&mut`, and in limited
  consuming paths by value. Anyone may reference shared input, but only
  type-correct callable code can act on it; verify any authorization the design
  requires.
- `tx_context::sender(ctx)` comparisons (valid address-based authorization; inventory the compared address/config, key custody/rotation, sponsored-tx semantics, and bypass paths)

> **Sui authorization review:** `entry` is a transaction-boundary modifier, not a
> visibility tier; `public` functions are already PTB-callable. Compare each
> security-sensitive function with the intended permission model and all actual
> checks—capability, sender, object/party binding, visibility, and state. Wide
> visibility or an absent capability is a candidate signal only when a protected
> effect lacks another valid authorization mechanism.

### P.3 Writes — assignments to gating fields

`object.field = ...` through `&mut`, `dynamic_field::add`, `share_object` (the
one-time transition that publishes a fresh object as shared), `set`-style
mutators, and `init` distribution of caps.

### P.4/P.5 Paths, Intent, Delta

When using the Atlas, useful Sui leads include a public/entry path mutating
security-sensitive shared state without the promised authorization, a fresh
object published as shared contrary to intent, an authority object whose actual
transfer/wrapper paths violate custody intent, and hand-rolled checked math
feeding an effect. Each remains a candidate until reachability and consequence
are established.

---

## 2. The Sui Hypothesis Ladder

This native ladder is an optional high-recall prompt set. Apply it wherever useful; leads from it or any other discovery method become schema-complete files under `triage/candidates/`, never direct findings. Apply `triage.md` before promotion.

### Identity, Capability & Visibility

1. **Does this privileged function enforce the authorization model the design promises?** A capability gate must require an actor-unreachable cap for the stated threat model; a sender ACL must compare the runtime-authenticated `tx_context::sender` against the correct governed address. PTB composition cannot spoof the sender, but missing/wrong address binding, compromised custody, unsafe rotation, or an alternate path may still bypass the intended model. Establish the protected effect before treating an absent check as a defect. (SlowMist B8; [SUI-G9].)
2. **Is the callable surface wider than intended?** Examples include `public`
   where package visibility was promised, or a non-public `entry` function that
   was not intended to be a transaction command. `entry` is not a visibility
   tier; compare both visibility and transaction callability with the design.
   (SlowMist B4; [SUI-G-vis].)
3. **Does the gating capability have `store` or `copy`?** `store` permits nesting
   and, for `key + store` objects, enables `public_transfer`, but does not by
   itself expose the cap. Trace actual constructors, wrappers, transfers, and
   accessors. `copy` permits duplication; prove why uniqueness is required.
   (SlowMist abilities; [SUI-G4/G6].)
4. **Does capability custody match the stated trust model?** A single key can be
   a material compromise assumption, but is not automatically a vulnerability;
   establish the promised custody/rotation policy and maximum reachable impact.
   ([SUI-G9].)
5. **Is a regular witness mistaken for an OTW, or does a generic library omit `types::is_one_time_witness`?** A true OTW cannot be manually constructed and is injected only into `init`; verify its four defining conditions (only `drop`, zero fields, non-generic, uppercase module name) and the library's runtime check. (SlowMist abilities/init; [SUI-G7/G8].)

### Object Ownership & Abilities

6. **Is a fresh object published as shared when the design requires owner authorization?** Anyone can reference a shared object, so prove that a callable function reaches a protected effect without the promised in-body authorization or object binding. Sharing alone is not a finding. (SlowMist B5; [SUI-G1/G2].)
7. **Does a value-bearing type (Position, Debt, Receipt, LP) have `drop`?** A holder may discard the value without an explicit destructor; prove whether that actually erases or desynchronizes an obligation tracked elsewhere. (SlowMist abilities; [SUI-G5].)
8. **Does a type that should be soulbound have `key + store`, or another transfer path?** Its owner may be able to use `public_transfer`, undermining non-transferability intent; trace actual ownership and callers. (SlowMist A6/B5; [SUI-G3].)
9. **Can a type-correct public/entry path mutate a shared object contrary to the permission model?** Check capability, sender, party/object binding, state guards, and consequence; a permissionless shared mutation may be intended. ([SUI-G1].)
10. **Dynamic fields: do key construction, parent binding, and growth match the
    design?** Prove a collision/substitution or actor-reachable persistent
    liveness effect rather than labeling weak-looking keys or one expensive call
    as DoS. (metrics-sui § 3.)

### Numeric & Boundary

11. **Are there bitwise/shift operations, or hand-rolled "checked" math helpers?** A shift count at or above the width aborts, but shifted-out high bits are discarded; a wrong mask/threshold can therefore misreport truncation. Re-derive the helper against adversarial inputs—the Cetus `checked_shlw` class. (SlowMist B1; [SUI-G12].)
12. **Does any division/ratio/fee/interest computation lose precision (no floats in Move)?** Derive the operation-specific invariant and complete round trip, including fees; quantify whether rounding creates extractable value or another security consequence. (SlowMist B2; [SUI-G13].)
13. **Do casts, shifts, or edition/toolchain-specific helpers change the intended numeric semantics?** Ordinary Move integer arithmetic and narrowing casts abort on overflow in both older and newer editions; do not invent a "pre-Move-2024 silent wrap" candidate. Focus on shifted-out bits, shift-count boundaries, precision/rounding, and faulty hand-rolled checked helpers. ([SUI-G12].)

### Coin / Balance / Token

14. **Is the consumed `Coin`/`Balance` amount exact, where does a split remainder
    go, and are address-funds withdrawals bound to the correct owner and
    remaining limit?** `Withdrawal<T>` has `drop`; object-generated limits are
    checked at redemption. Also validate any use of the commit-start
    `settled_funds_value` snapshot. (SlowMist B6; metrics-sui § 2.6.)
15. **Who holds `TreasuryCap`, and do mint/burn paths match the intended trust and supply model?** Quantify reachable impact rather than requiring one universal cap, rate, or governance design. (metrics-sui § 4.)
16. **Are `coin::join`/`split` arithmetic and the resulting balances reconciled?** (SlowMist B6.)

### External Call / Dependency / Return Values

17. **Is every consequential result handled with the correct semantics?** A `Coin` or `Balance` without `drop` must be consumed, but it can still be misrouted, stored, joined, or returned incorrectly; a droppable success/overflow flag can be ignored. Trace the exact disposition and consequence. (SlowMist B11; metrics-sui § 2.12.)
18. **Are the `use`-imported external packages trustworthy and version-pinned?** Move has no dynamic-call surprise, so the residual risk is dependency *quality* + the fact that **upgrades don't auto-update deps**. (SlowMist B10, B9.)

### Composition / PTB / Race

19. **Can the actor compose type-correct calls allowed by visibility, ownership, object-version, and transaction-verifier rules in an unintended PTB order?** Preconditions must hold per call; “arbitrary order” never means bypassing those runtime/type constraints. (SlowMist B3, B14; methodology X.1/A.4.)
20. **Can a validator/searcher profit by reordering shared-object txs (front-running/MEV)?** Apply the three-phase state-expectation check: before / during / after each call (slippage, min-out, state asserts). (SlowMist B3.)

### Flash Loan / Oracle / Economic

21. **Does every reachable hot-potato consumer enforce the intended repayment,
    cancellation, and asset/amount/party/replay bindings; and can borrowed capital
    manipulate a price or reward/interest algorithm?** Consumption alone is not
    settlement proof. Audit both the consumer set and the economic effect.
    (SlowMist B7; [SUI-G16/G17].)
22. **Does the price path resist manipulation and stale/uncertain data for its
    actual use?** For DEX-derived prices, quantify capital, depth, bounds, and
    extractable impact. For Pyth-on-Sui, validate the applicable verification
    level, `publish_time`, `Clock`, confidence policy, and fallback semantics. No
    one TWAP or confidence threshold is universally required. ([SUI-G16/G17].)

### Init / Upgrade

23. **Can an init-like public helper or migration be replayed, or does an upgrade incorrectly assume `init` will run again?** Genuine module `init` runs once at first publish. Require migration only when changed persistent state, versions, dependencies, or invariants need it. (SlowMist B9; [SUI-G14/G15].)
24. **Does upgrade authority/custody match the trust model, and are persistent
    objects/dependencies handled across versions?** Sui enforces the selected
    package compatibility policy, but `init` does not rerun and existing objects
    or dependencies do not migrate automatically. ([SUI-G15].)

### Liveness / DoS / Gas

25. **Can an actor reach a persistent state where every relevant legitimate path inevitably aborts, with no recovery or alternate path?** One abort only rolls back that transaction and is not by itself a protocol-wide DoS. (SlowMist B12.)
26. **Can input-driven growth or an expensive path create a measurable security
    or persistent-liveness consequence under actual transaction limits?** Cost
    alone is not a DoS finding. (SlowMist B12, B13.)

### Cross-Boundary & Business Logic

27–35. When useful, adapt `methodology.md` ladder Q32–40 as optional X/J prompts. Sui-native seams include modules tracking the same balance/supply through separate state, a vault `Balance` whose share math another function or donation can move, and integrations whose Cetus/Pyth semantics differ from caller assumptions. Other discovery methods remain equally valid.

---

## 3. Optional verification techniques

Any sound method may verify a Sui candidate. The techniques below are examples. Evidence must establish the claimed reachability and consequence and must not overstate deployment/state fidelity.

### 3.1 Technique and claim fit (Sui)

| Mode | Tool | When | Proves | Does NOT prove |
|------|------|------|--------|----------------|
| **Move unit test** | `sui move test` with `#[test]` + `sui::test_scenario` | Fast option for logic PoCs and pre-deployment audits; self-contained and supports multi-tx scenarios. | The module logic is exploitable under the constructed objects and state. | That the deployed package's live objects/configuration are currently exploitable. |
| **Localnet reconstruction** | `sui start --force-regenesis --with-faucet` + republish + reconstruct objects | One option for end-to-end execution with relevant objects rebuilt from recorded state. | The effect on the documented reconstruction. | Exact deployed-state exposure beyond the reconstruction's fidelity. |
| **PTB crafting** | `sui client ptb ...` against localnet/testnet or another selected target | Exercise a type-correct sequence through transaction-callable functions. | The submitted PTB reaches the asserted effect on that target/state. | Any broader deployment/state claim not bound by the evidence. |

**Claim boundary:** current-deployment exploitability requires evidence bound to the deployed package, relevant objects/configuration, and state. Localnet reconstruction is one useful method but ordinarily supports `CONFIRMED-RECONSTRUCTION`, not exact deployed exposure. Historical transactions/traces, faithful object/state analysis, or another sound deployed-target method may provide stronger evidence. Record all reconstruction deviations.

### 3.2 Harness — `test_scenario` (example)

```move
#[test_only]
module target::poc {
    use sui::test_scenario::{Self as ts};
    use sui::coin;
    use sui::transfer;
    use target::vault::{Self, Vault};

    const ADMIN: address = @0xAD;
    const ATTACKER: address = @0xBAD;

    #[test]
    fun poc_shared_object_unauthorized_withdraw() {
        // Hypothesis (Ladder Q6/Q9 / SlowMist B5): a Vault that should be
        // owner-gated is shared, and `withdraw` has no equivalent promised
        // capability, sender, party/object-binding, or state authorization.
        let mut sc = ts::begin(ADMIN);
        {
            vault::init_for_testing(ts::ctx(&mut sc)); // shares the Vault, funds it
        };
        // Attacker (not admin, holds no AdminCap) operates on the shared Vault:
        ts::next_tx(&mut sc, ATTACKER);
        {
            let mut v = ts::take_shared<Vault>(&sc);
            let stolen = vault::withdraw(&mut v, 1_000_000, ts::ctx(&mut sc)); // claimed path: no promised auth enforced
            assert!(coin::value(&stolen) == 1_000_000, 0); // attacker extracted value
            transfer::public_transfer(stolen, ATTACKER);
            ts::return_shared(v);
        };
        ts::end(sc);
    }
}
```

### 3.3 Sui PoC Pattern Library

#### Pattern U1 — Unauthorized shared-object effect  ·  Ladder Q6/Q9 · [SUI-G1] · B5

The harness above uses a missing capability as one example. A finding requires
the protected effect to be reachable without the design's promised
authorization; `take_shared` succeeding or the object being shared is not enough.

#### Pattern U2 — Shift/precision truncation (Cetus class)  ·  Ladder Q11 · [SUI-G12] · B1

```move
#[test]
fun poc_checked_shlw_truncation() {
    // The helper guards with a wrong mask so a value that should be rejected passes,
    // then `n << 64` silently drops high bits → a too-small result used downstream as
    // "amount in", letting the attacker mint/borrow more than they paid.
    let n: u256 = /* chosen so n < bad_mask but (n << 64) overflows the intended range */;
    let (result, overflow) = math::checked_shlw(n);
    assert!(!overflow, 0);              // helper wrongly reports "no overflow"
    assert!(result < expected_full, 1); // and returns a truncated, attacker-favorable value
}
```

#### Pattern U3 — Ability misuse  ·  Ladder Q3/Q7/Q8 · [SUI-G4/G5/G6]

```move
// If Position has `drop`: the holder can discard it without an explicit destructor.
// Verify whether this actually desynchronizes the authoritative debt ledger while the
// holder keeps borrowed Coin; `drop` alone does not prove debt erasure.
// If AdminCap has `store`: trace whether a real wrapper/transfer/accessor path exposes it.
```

#### Pattern U4 — Flash-loan (hot potato) oracle/economic manipulation  ·  Ladder Q21/Q22 · [SUI-G16] · B7

```move
// In one PTB: flash_borrow (returns Coin + a no-ability Receipt hot potato) →
// swap to skew a spot-reserve oracle the target reads → call the vulnerable
// borrow/liquidate that trusts the skewed price → swap back → repay (consume Receipt).
// Assert net Coin gain after same-denomination costs. Localnet reconstruction is
// one option; do not label reconstructed state as CONFIRMED-DEPLOYED.
```

#### Pattern U5 — PTB composition / shared-object ordering  ·  Ladder Q19/Q20 · B3/B14

```bash
# Craft a PTB that calls public functions in an order the design never intended,
# landing in a state no single call permits (e.g., claim-before-settle).
sui client ptb \
  --move-call "$PKG::m::claim" @"$SHARED_OBJ" \
  --move-call "$PKG::m::settle" @"$SHARED_OBJ" \
  --assign out --transfer-objects "[out]" @"$ATTACKER"
```

| SlowMist / gate | Pattern | Harness |
|-----------------|---------|---------|
| B5/B4 shared-object authorization or callable-surface mismatch | U1 | test_scenario / localnet |
| B1 shift/overflow truncation | U2 | test_scenario |
| abilities (key+store cap, drop on value) | U3 | test_scenario |
| B7 flash-loan oracle/economic | U4 | localnet (PTB) |
| B3/B14 ordering / composition | U5 | PTB on localnet |
| B11 unchecked return (dropped overflow flag) | U2-shape assert | test_scenario |
| B9 init/upgrade migration | publish→upgrade→assert stale state | localnet |

### 3.4 Assertion discipline (Sui)

An executable PoC should assert a consequence such as:

- attacker asset-denominated P&L is positive after repayment and
  same-denomination costs; report gas separately when it uses another asset, or
  convert only with a pinned validated valuation source
- target `Balance<T>` / vault decreased — victim lost
- an object reached an impossible-by-intent ownership/state and that state caused
  the claimed effect (for example, an intended owner-only object was published
  shared and an unauthorized withdrawal then succeeded)
- for DoS: prove the attacker-reachable persistent condition, repeated failure of
  all relevant legitimate paths, and absence of recovery/alternate paths; a lone
  `#[expected_failure]` only proves one transaction aborts

Other security consequences need their own measurable criterion; the taxonomy is not funds-only.

---

## 4. Toolchain (build · test · formal verification · verification)

Use any useful manual or automated technique. Common Sui tools include:

- **`sui move build`** — type/ability/borrow checking
- **`sui move test` + coverage** (`--coverage`) — run the module's own tests; coverage is one review signal, not proof of safety or a required discovery route
- **Formal/model methods** — use a currently supported toolchain or an independently reviewable proof/model appropriate to Sui; do not assume the sunset Sui Move Prover integration is available
- **`sui client verify-source`** — confirm the published package matches the source

**Build artifacts:** `sui move test` runs `#[test]` modules in-process; `sui move build` produces the package for publishing or analysis. These are optional verification inputs.

---

## 5. Source acquisition (Phase 1, Sui)

```bash
# Open source at the deployment ref (Move packages are usually source-published)
git clone "$REPO_URL" "$WORKSPACE/contracts/src"
cd "$WORKSPACE/contracts/src" && git checkout "$DEPLOY_REF"

# Inspect the on-chain package + its modules
sui client object "$PACKAGE_ID" --json

# Confirm the published bytecode matches the source
sui client verify-source

# Inspect UpgradeCap custody and compare it with the scoped trust model
sui client objects | grep -i upgrade   # then `sui client object <upgradecap-id> --json`
```

When ownership evidence matters, capture each in-scope object's actual on-chain
owner representation, including address/object-owned, shared, immutable, and
consensus-owned party forms. Also record wrapping/nesting and the callable paths;
abilities alone do not identify the live owner mode.
