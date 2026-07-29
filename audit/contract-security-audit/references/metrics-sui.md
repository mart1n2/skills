# Sui / Move Smart Contract Audit Metrics

> **Scope:** Move-based chains — primarily Sui (object-centric Move); Aptos differences in § 6. Source-code-verifiable patterns.
>
> **Role in the skill (three-layer model):**
> - `methodology.md` — chain-agnostic truth-gate rationale and optional techniques; target-faithful evidence, not the catalog, establishes a claim.
> - `playbook-sui.md` — Sui-native semantics plus optional prompts, recipes, and verification examples.
> - **this file** — the Sui *known-pattern catalog*: gates `[SUI-Gn]`, risk/remediation patterns, Sui mechanics, and historical incidents.
>
> **Not a checklist.** Move's resource and object model prevent or reshape some
> familiar failure mechanisms, but do not bound the attack surface. Absence of a
> match is not safety; every catalog match is only a candidate signal until its
> reachability, consequence, and target fidelity are established.
>
> **Provenance:** the catalog (§ 2) is derived from the [SlowMist Sui MOVE Smart Contract Auditing Primer](https://github.com/slowmist/Sui-MOVE-Smart-Contract-Auditing-Primer) (its 10 key-knowledge points + 15 audit items), cross-referenced with the Move/Sui incident record.

---

## 1. Threat Landscape & Gate Index

Move and Sui prevent or reshape several familiar mechanisms, while failures in
bitwise/shift math, live object ownership, authorization/capability design,
upgrades, dependencies, and protocol economics remain possible. This historical
catalog does not bound the discovery space.

| Class | Example incidents / patterns |
|-------|------------------------------|
| **Shift / hand-rolled-checked-math truncation** | **Cetus** — a wrong mask in a `checked_shlw`-style helper let a value pass and then truncate |
| **Object ownership confusion** | Fresh object published shared contrary to intent; a callable path then reaches a protected effect without the promised authorization |
| **Ability misuse** | transfer/storage/destruction paths enabled by abilities violate an intended custody or accounting property |
| **Capability / witness misuse** | Regular witness mistaken for an OTW; authority custody, transfer, or binding violates design intent |
| **Oracle / DEX manipulation** | Manipulable DEX-derived pricing, stale/uncertain oracle data, or unsafe fallback semantics |
| **Init / upgrade** | Incorrect assumption that `init` reruns; upgrade custody contrary to the trust model; unmigrated objects/dependencies |

### Candidate Trigger Index (independent evidence required)

None of these signals is automatically a vulnerability or severity. Establish
the intended security property, threat-model-valid actor/capabilities, real path,
effect, and target/state fidelity before disposition.

| Gate | Statement | Catalog § |
|------|-----------|-----------|
| **[SUI-G1]** | Shared-state path may reach a protected mutation without the authorization model promised by the design | 2.5 |
| **[SUI-G2]** | Object passed where the code assumes the other ownership mode | 2.4 |
| **[SUI-G3]** | A soulbound/protocol-controlled type has a real public transfer, wrapping, or custody-bypass path enabled by its abilities | 2.3 |
| **[SUI-G4]** | A capability's abilities plus reachable wrappers/transfers violate custody or uniqueness intent | 2.3 |
| **[SUI-G5]** | Dropping a value-bearing type may erase or desynchronize an obligation tracked elsewhere | 2.3 |
| **[SUI-G6]** | `copy` on an authority-bearing type | 2.3 |
| **[SUI-G7]** | Regular witness may be mistaken for a one-time witness | 2.7 |
| **[SUI-G8]** | Generic OTW consumer may omit `types::is_one_time_witness` or witness authority may be misbound | 2.7 |
| **[SUI-G9]** | Authority custody/rotation does not match the protocol's stated trust model | 2.2 |
| **[SUI-G-vis]** | Visibility or transaction callability is wider than intended (`entry` is a modifier, not a visibility tier) | 2.1 |
| **[SUI-G12]** | Shifted-out high-bit truncation, invalid shift-bound assumptions, or wrong hand-rolled checked-math | 2.8 |
| **[SUI-G13]** | Integer-division precision loss favoring the attacker | 2.8 |
| **[SUI-G14]** | Init-like helper/migration is replayable, or an upgrade incorrectly assumes module `init` will run again | 2.9 |
| **[SUI-G15]** | UpgradeCap custody violates the stated trust model, or persistent objects/dependencies are not handled across versions | 2.9 |
| **[SUI-G16]** | DEX spot price used without TWAP/aggregation | 2.11 |
| **[SUI-G17]** | Pyth-on-Sui `publish_time` staleness / confidence not checked against `Clock` | 2.11 |

---

## 2. Audit-Item Catalog (risk → secure pattern, with Sui mechanics)

### 2.1 Access control via visibility  ·  [SUI-G-vis]  (SlowMist B4)

Visibility determines composability, not authorization by itself. Compare the
declared surface and in-body checks with the design's permission model:

| Tier | Reach | Use for |
|------|-------|---------|
| private (no modifier) | same module | internal helpers |
| `public(package)` (replaces legacy `public(friend)`) | modules in the same package | cross-module package-internal APIs |
| `public` | any module + any PTB | genuine external surface |

`entry` is not a visibility tier. It is a transaction-boundary modifier that can
combine with private, `public(package)`, or `public`; a non-public entry function
can be a transaction command while remaining unavailable to other packages.
`public` is already directly PTB-callable and composable.

**Audit:** compare each security-sensitive function with the intended permission
table and all capability/sender/object/party checks. Wide visibility is a lead,
not an automatic asset-loss finding. **Optional Atlas grep:** `public fun`,
`public entry fun`, `entry fun`, `public(package)`, `public(friend)`.

### 2.2 Permission via capability objects  ·  [SUI-G9]  (SlowMist B8)

Sui authorization may use capability-object possession or the runtime-authenticated `tx_context::sender`. Failure classes include missing/wrong capability gates, incorrect sender/address binding, alternate ungated paths, and over-permissioned roles.

```move
// AUTH SHAPE — security also depends on construction, uniqueness, live owner
// mode, custody, transfer/wrapper paths, and binding to the protected state.
public fun set_fee(_: &AdminCap, cfg: &mut Config, bps: u64) { cfg.fee_bps = bps; }
```
**Audit:** verify every privileged path implements the authorization model the design promises. For capabilities, analyze construction, transfer, storage, custody, and every function accepting them. For sender ACLs, verify the compared address/config, key rotation, sponsored-transaction assumptions, and bypass paths. **Atlas grep:** `AdminCap`, `OwnerCap`, `TreasuryCap`, `: &mut`, `sender(ctx)`.

### 2.3 Type abilities  ·  [SUI-G3/G4/G5/G6]  (SlowMist A7)

Abilities are security-relevant type semantics. Investigate when:

| Ability | Effect | Flag when |
|---------|--------|-----------|
| `copy` | duplicable by value | on a cap/authority/value type when uniqueness is security-relevant; trace every constructor and use ([SUI-G6]) |
| `drop` | discardable without explicit destruction | on a value-bearing type when discarding it erases or desynchronizes a real obligation ([SUI-G5]) |
| `store` | storable inside other structs; with `key`, may permit public-transfer paths | on a capability or soulbound type when actual wrappers/transfers/accessors violate custody intent ([SUI-G3/G4]); `store` alone does not make a value public |
| `key` | top-level object with UID | missing on a type meant to be a top-level object |

**Hot potato:** a struct with **no abilities** `{}` cannot be
stored/dropped/copied/keyed, so it must be consumed in the same transaction.
This enforces **consumption**, not repayment correctness: trace every consumer
reachable from the public/package/entry surface and prove each permitted
settlement/cancel path enforces the intended asset, amount, parties, and replay
binding. Then audit the economics (§ 2.10). **Optional Atlas grep:** `has copy`,
`has drop`, `has store`, `has key`, `struct .* has`, plus every function taking
the receipt by value.

### 2.4 Object ownership model  ·  [SUI-G2]  (SlowMist A8)

Inspect the current on-chain owner/access form independently from type abilities:

| Owner/access form | Runtime meaning | Audit focus |
|-------------------|-----------------|-------------|
| **Address-owned** | owner metadata is an account address | owner signature, receiving/transfer paths, and called-function logic |
| **Object-owned** | owner metadata is another object ID | parent/child access, receiving, dynamic fields, and wrapper invariants |
| **Shared** | consensus-versioned shared input; anyone may reference it | type-correct callable functions and any authorization/object binding required by design |
| **Immutable** | no mutable owner; generally readable by anyone | assumptions that require mutability, uniqueness, or revocation |
| **Party / consensus-address-owned** | owned by a specified party/address but versioned through consensus | owner authorization plus party rules, sequencing, and transition paths |

Wrapping/nesting changes the access surface through containment. `store` affects
whether public transfer/nesting APIs are available, but does not select the live
owner mode or bypass runtime ownership. Capture actual owner metadata and the
callable transition paths when ownership is material.

### 2.5 Object management — unintended shared publication  ·  [SUI-G1]  (SlowMist B5)

A new object can be published shared. Anyone may then reference it, but only
type-correct callable functions can read/mutate/consume it. Create a candidate
when the design required owner/party authorization and a real path reaches a
protected effect without an equivalent capability, sender, object-binding, or
state check; sharing alone is not a finding.

```move
// CANDIDATE — Vault is shared and withdraw appears to lack the promised auth.
// Confirm no sender/object/party/state binding and establish the consequence.
public fun withdraw(v: &mut Vault, amt: u64, ctx: &mut TxContext): Coin<SUI> { /* no cap! */ }
```
```move
// POSSIBLE FIX — require the intended capability (or use the intended owner mode)
public fun withdraw(_: &AdminCap, v: &mut Vault, amt: u64, ctx: &mut TxContext): Coin<SUI> { ... }
```
**Audit:** compare each new shared publication and its callable functions with
business intent. Shared inputs may be `&`, `&mut`, or in limited consuming paths
by value. **Optional Atlas grep:** `transfer::share_object`,
`public_share_object`, relevant function signatures.

### 2.6 Fungible value — Coin, Balance, and address balances  ·  (SlowMist B6)

`Coin<T>` is a `key + store` object whose live owner mode must be inspected;
`Balance<T>` is a storable non-object value (`store`, without `key/copy/drop`).
Sui also supports address-funds flows. Check exact amounts, split remainders,
merge destinations, Coin/Balance conversion, `send_funds`/`redeem_funds`, and
`Withdrawal<Balance<T>>` owner plus remaining limit. `Withdrawal<T>` has `drop`;
an object-generated limit is checked at redemption. Also review object-funds
withdrawals and `settled_funds_value` commit-start snapshot assumptions.
**Optional Atlas grep:** `coin::split`, `coin::join`, `coin::take`, `coin::put`,
`balance::split`, `balance::join`, `send_funds`, `redeem_funds`,
`withdraw_funds_from_object`, `settled_funds_value`, `into_balance`,
`from_balance`.

### 2.7 Witness & one-time witness  ·  [SUI-G7/G8]  (SlowMist A1, B9-init)

A regular witness can prove module/type ownership but not one-time use. A true
OTW has only `drop`, zero fields, is non-generic, and is named after its module in
uppercase; it cannot be manually constructed and is supplied only to `init`.
Generic libraries expecting an OTW must call `types::is_one_time_witness` rather
than treating `T: drop` as sufficient. **Optional Atlas grep:** `fun init(`,
`: drop`, `is_one_time_witness`, witness-consuming generic APIs.

### 2.8 Arithmetic — shift truncation & precision  ·  [SUI-G12/G13]  (SlowMist B1, B2)

Move checks arithmetic overflow by default. A shift count at or above the integer width aborts, but high bits shifted out of a fixed-width value are discarded; hand-rolled overflow masks/helpers can therefore be wrong. This is the **Cetus** class.

```move
// VULNERABLE — wrong mask: values below it pass, then `n << 64` truncates silently
public fun checked_shlw(n: u256): (u256, bool) {
    let mask = 0xffffffffffffffff << 192;     // ❌ should bound n so (n<<64) can't lose high bits
    if (n > mask) { (0, true) } else { ((n << 64), false) }  // ❌ left-shift overflow truncated
}
```
The guard must reject any `n >= (1 << 192)` (equivalently
`n > MAX_U256 >> 64`) before `n << 64`. **Precision (B2):** Move has no floats;
derive rounding from the operation-specific invariant and measure the full
round trip including fees. A local rounding direction is not a finding until it
creates extractable value or another security consequence. **Optional Atlas
grep:** `<<`, `>>`, `& `, `| `, `checked_`, `fun .*shlw`, `/ `.

### 2.9 Initialization & upgrade  ·  [SUI-G14/G15]  (SlowMist B9)

A published package version remains immutable. An upgrade publishes a successor
while older code can remain callable; it does not automatically migrate existing
objects or dependencies, and module `init` does not run again. The UpgradeCap
policy is `compatible`, `additive`, or `dep_only`. `package::make_immutable`
instead consumes the UpgradeCap; it is an irreversible loss of future patching,
not a fourth policy.

**Audit:** require migration/version gates only when an upgrade changes persistent
state, dependencies, formats, or invariants. Check init-like/migration replay,
old/new entry compatibility, current policy, UpgradeCap custody under the stated
trust model, and any governance decision to make the package immutable together
with its loss-of-patchability tradeoff. **Optional Atlas grep:** `fun init`,
`migrate`, `UpgradeCap`, `make_immutable`, `package::`, `version`.

### 2.10 Flash loan (hot potato)  ·  (SlowMist B7)

Sui flash loans commonly use the hot-potato pattern (§ 2.3): borrow returns
funds plus a no-ability `Receipt` that must be consumed in the same transaction.
The type system does not prove which consumer destroys it or whether repayment
amount, asset type, lender/borrower, and nonce match. Audit every
constructor/consumer first, then the **economic** surface: can intra-transaction
capital manipulate a price input ([SUI-G16]) or game reward/interest algorithms?
**Optional Atlas grep:** `Receipt`, `fun flash`, `hot_potato`, no-ability structs
returned by `public fun`, and functions accepting them by value.

### 2.11 Oracle  ·  [SUI-G16/G17]

- **DEX-derived price:** quantify manipulation cost, depth, atomic capital,
  bounds, and extractable impact. TWAP, aggregation, or deviation/depth bounds
  are possible defenses, not universal formats.
- **Pyth on Sui:** validate the applicable verification level, `publish_time`
  against `Clock`, confidence policy, and fallback semantics for the protocol's
  asset and use case; there is no universal confidence/staleness threshold.
- **Cross-chain (Wormhole VAA):** verify guardian set + replay protection; VAA hash consumed exactly once.

### 2.12 External calls & return values  ·  (SlowMist B10, B11)

Move forces non-`drop` results such as `Coin<T>` and `Balance<T>` to be consumed,
but they can still be misrouted, joined, stored, or returned incorrectly.
Droppable results such as a success/overflow flag can be ignored. Review pinned
dependency semantics and trace every consequential result's exact disposition.
**Optional Atlas grep:** `let _ =`, discarded droppable results, tuple returns,
Coin/Balance consumers and destinations.

### 2.13 Race conditions / front-running  ·  (SlowMist B3)

Shared-object and party-object transactions are consensus-sequenced, so ordering
and MEV may matter. Address-owned fast-path transactions avoid consensus only
when they do not include shared/party consensus inputs. Evaluate ordering against
the actual input set, state versions, slippage bounds, and economic consequence.

### 2.14 DoS, gas, design logic  ·  (SlowMist B12/B13/B14)

**DoS:** a transaction abort rolls back that transaction; it does not itself
brick later calls. Establish an actor-reachable persistent condition under which
all relevant legitimate paths inevitably fail and no recovery/alternate path
exists. **Gas:** reason about bounded growth and actual transaction limits.
**Design logic:** model only type-correct PTB compositions allowed by visibility,
ownership, object versions, and verifier rules.

---

## 3. Object & ability deep reference

Dynamic fields attach a typed key/value under a parent `UID`;
`dynamic_object_field` keeps a `key` object discoverable by its ID. Verify key
construction, parent binding, read/write authorization, and input-driven growth.
PTB commands are atomic and type-checked. Shared inputs may be borrowed by
`&T`/`&mut T` and, where the rules permit consumption, passed by value.

---

## 4. Coin / Balance / Treasury reference

`Coin<T>` (`key + store`) wraps `Balance<T>` (`store`, without
`key/copy/drop`). `Supply<T>` / `TreasuryCap` hold mint/burn authority. Also
include address-balance/funds-accumulator flows. Audit actual TreasuryCap owner
mode/custody and all mint/burn bindings; `store` permits storage/public transfer
shapes but is not itself a custody flaw.

---

## 5. Case studies

- **Cetus** (shift/checked-math truncation, [SUI-G12]) — a wrong mask in a `checked_shlw`-style helper let an out-of-range value pass and then truncate, yielding an attacker-favorable "amount in." PoC shape: `playbook-sui.md` Pattern U2.
- **Unauthorized shared-object effect** ([SUI-G1]) — a fresh object is published
  shared and a real callable path reaches a protected effect without the
  authorization promised by the design. Sharing by itself is not the issue.
  Optional test shape: Pattern U1.

---

## 6. Aptos-specific differences (brief)

Account-centric (address-owned resources) rather than Sui's object-centric
model. Authorization commonly uses `signer`, and resource-account creation and
authority semantics need Aptos-native review. Principles transfer; primitives
and release semantics differ—read the current Aptos framework documentation.

---

## 7. Toolchain

Optional build, test, proof, and harness techniques live in `playbook-sui.md §§ 3–4`. Manual review, agents, SAST, fuzzing, formal methods, transaction analysis, and any other sound approach may be used; every accepted claim passes the same evidence and triage gates.

**References:** [Sui docs](https://docs.sui.io/) · [Move Book](https://move-book.com/).

**Status:** production pattern catalog for Sui; Aptos content is comparative only and does not constitute a native Aptos audit workflow. The Move post-mortem record is younger than EVM's; re-evaluate § 2 quarterly as the exploit catalogue develops.
