# Cire v1 specification authority and release manifest

<a id="cire-v10-successor-profile"></a>

Active profile: `Cire-v1.0`.

Repository `main` is a candidate stream. The previously approved teaching
baseline `71c631605ae7b16795f2490123230048f68d1c3f` remains canonical until one
immutable Cire-v1.0 candidate passes the final exact review. Intermediate TR0
repair commits, including `759ab5ec3864308a6b38225879ac140efbbb2588`, are
migration substrate, not separately approved baselines and not Cire-v1.0.

This repository targets **v1 specification complete**: one closed language
design plus executable schema and finite protocol-model conformance. It does
not contain a compiler, production runtime/backend, standard library, or LSP,
so it cannot claim **v1 implementation release**.

## Authority order and hard ownership boundary

1. [Surface grammar and elaboration](surface-syntax.md) is the only source for
   tokens, lossless CST, precedence, source scopes, name-resolution boundary,
   normalization, source-facing declaration WF and local-inference boundary,
   nominal/pattern source rules, trait/extension method resolution,
   Surface-to-evidence-indexed-Kernel lowering, and the frontend-owned
   intrinsic-registry/origin-map artifact schemas. As the one closed exception
   that makes the first-party registry mechanically complete, its
   `instantiate_first_party` contract also uniquely selects and projects that
   registry's declared Kernel/M3/Core/Q/Λ output; the formal authority checks
   and interprets that output but does not regenerate it.
2. [Temporal and ordinary-language formalization](temporal-reactivity-formalization.typ)
   begins at Kernel WF and is the only source for the typed-Core judgments and
   wire/runtime enforcement of inference, nominal data, traits, effects,
   provenance/capture/world/usage, public interface/ABI/runtime schemas,
   operational transitions, and runtime protocols outside that exact
   first-party projection exception. It consumes the source decisions and
   frontend registry/origin artifacts rather than regenerating them.
3. [Consumable conformance artifacts](../examples/spec/README.md) are generated
   or exact checked models of those two sources. They cannot define a new rule
   or fill a missing premise.

This file alone owns profile identity, authority precedence, inventory, and
release status. A parser, compiler, runtime, tutorial, checker, or model that
disagrees with this order is wrong. The historical design memos consumed by
this migration are evidence only and are not a fourth specification.

## Intentional profile-delta ledger

| Domain | Cire-v1.0 decision | Removed or excluded |
|---|---|---|
| Parameter labels | A simple `name : T` parameter is positional or `name = expr`; destructuring is positional-only; trailing lambda fills the final non-receiver formal. | Declaration/call `~`, label punning, label-based structural function calls. |
| Named capability | Only direct `app : F` parameter binding introduces an abstract identity and lowers to `Cap[i,F]`; handler installation creates runtime identity. | Surface `cap F`, defaulted capability binders, bare Effect-kind fields/results/nested types. |
| Function boundary | Every named def/method/trait/default/impl/extension/const-def spells generics, parameter/result types, and an effect row; pure is `! {}`. | API inference and omitted named-function rows. |
| Primitive/runtime value universe | Fixed Wasm-shaped scalars, valid immutable UTF-8 String, immutable Bytes, explicit conversions, checked-trap integers, canonical NaNs. | Pointer-sized/raw-pointer/SIMD/null/truthiness, implicit casts, general `as`, Float Eq/Ord/Hash. |
| Local inference | Bidirectional qualified rank-1 HM with a Cire value restriction and weak-monomorphic fallback. | Higher-rank/impredicative inference, polymorphic recursion, authority/Owner/clock generalization. |
| Data/patterns | Nominal struct/enum/newtype/opaque, transparent alias, const defaults, exact update/privacy, exhaustive constructor-matrix patterns, opt-in derive. | Anonymous structural records, refutable let/parameter/for, float patterns, hidden zero/default initialization. |
| Ordinary traits/extensions | Coherent orphan/overlap rules, zero-arity associated Type, inherent-first then unique trait+extension candidate, exact UFCS and `use @pkg::name [as alias]`. | Trait or ability inheritance/supertrait entailment, GATs, trait objects, specialization, negative impls, autoderef/autoref, wildcard activation, effect/result-directed tie-break. |
| Mutation/control | Immutable by default, monomorphic local places, exact escape/replay rules; structural if/match/loop and derived while/for; private lexical return/break/continue. | Hidden shared mutation/snapshot, user-interceptable structural transfers, builtin yield/try. |
| Cleanup | Sealed `with @control::finally(cleanup) in body`, integrated with the suffix/Owner ledger. | Reachable `defer`, user destructors, generic discontinue, competing Drop/error aggregation. |
| Package/API/const | Exact lock-derived PackageInstanceId, closed package declaration/evidence dispatch, package-qualified data/trait/ability/effect and callable-kind metadata, content-addressed callable DAG, no dynamic top-level init, explicit ConstSafe evaluator. | Dependency search, wildcard imports, implicit modules/init order, unchecked public metas or source-reconstructed generic requirements. |
| Wasm/Component | Wasm 3.0 memory32 nonshared subset; synchronous Component canonical ABI, UTF-8, explicit Owner-backed resources and host capability contracts. | Required GC/EH/native continuations/tail/SIMD/threads, raw core ABI as stable API, implicit async ABI. |
| PackedNext | Shared sealed `PackedNext[A]`, checked scoped open, Building/Open/Closing/Closed protocol, close receipt/report. | General existential/rank-2/OwnedNext, unchecked open, Unit-returning dispose. |
| Handler | Full handler remains canonical; one inline derived form expands before omitted return and shares clause semantics. | Macros, omitted clause mode, shallow handlers, explicit forwarding surface. |
| Frontend | One lossless source→CST→resolved/normalized/signature-Kind Surface→Kernel pipeline with canonical origins. | Type-directed parser, alternate PEG/lowering, unowned synthetic spans. |
| Task | Shareable multi-waiter broadcast; only `Async::await`; outcome-only central cancel with exact Owner authority. | Task::await, implicit single-consumer semantics, foreign-owner parking, forged cancellation reasons. |
| Resource | `Resource[rho,K,A,E]`, SwitchLatest + LatestEpoch + keep-last-good, exact input cursor/generation/cleanup ownership, view and receipt dispose. | Merge/concat/exhaust, Resource::next/snapshot, implicit coercions. |
| Signal/UI | Pure clock-indexed Signal, sealed track/snapshot, required CoalesceLatest, generation-checked plan/commit, exact typed FIFO event payload and one Queued→Running lease. | UiDeclare effect, generic spawn, hidden host queue, late payload reread, per-event cleanup report, public Plan/Commit authority. |
| Event/checkpoint | Event nominal remains for explicit future bridges; Source/Live use a sealed fixed-Epoch checkpoint runner. | Generic on/on_async and user checkpoint API in v1. |

## Cross-input resolution record

The integrated ordinary-language freeze and Revision 6 left nine intersections
that required one successor decision. They are closed as follows:

1. `CireLanguageInterfaceV1` is the package-level separate-checking/API root.
   It holds exact package/import/declaration roots and hash edges to per-callable
   `CallableInterfaceV1 -> FunctionContractV3` artifacts. A callable module
   vector begins with `pkg-<PackageInstanceId-digest>`, so R6 callable hashes do
   not erase locked-package nominal identity. Target-specific `CireLinkAbiV1`
   and manifest-selected `CireComponentInterfaceV1` are two additional,
   non-interchangeable hashes; neither can replace the language API root.
2. `FunctionContractV3` remains the exact R6 computation root. Package, nominal,
   trait/ability generic requirements, callable free/inherent/extension identity,
   ConstSafe/ProtocolPure/MayTrap, and component facts live in closed package
   declaration/evidence artifacts tied to the callable edge; importers may not
   infer them from source spelling or add V3 root fields. Beyond the two R6 root/ref
   migrations, the only recursive M3 deltas are the three exact grammar positions
   `DeclarationBindersV2.type_binders[*] -> TypeBinderV3`,
   `ContractSubstitutionV2.type_arguments[*] -> TypeSubstitutionV3`, and
   `ApplyTypeV2.constructor -> TypeConstructorRefV3`. Their new branches are respectively
   `EffectConstructorBinderV3`, `EffectConstructorSubstitutionV3`, and
   `EffectParameterConstructorV3`; together they preserve accepted `F[_]` arity in every
   root/local/lambda/local-scheme declaration scope, application, and caller substitution.
3. The exact 21-entry `FirstPartyRegistryV1` remains unchanged in cardinality.
   `BuildString` and sealed `@control::finally` live in a two-entry
   `StructuralIntrinsicRegistryV1`; one `IntrinsicRegistryRootV1` binds both.
4. The 13 R6 origin kinds remain exact. Interpolation/finally/derive map to
   `SealedIntrinsicV1`; while/for/numeric/place temporaries map to
   `SourceOrderTemporaryV1`; manifest-generated component adapters do not forge
   source origins.
5. Recursive NFC/JCS applies to artifact strings. Semantic Char/String/Bytes
   const payloads use scalar/byte encodings, so Unicode normalization cannot
   change a program value.
6. The foundation's later explicit-row rule wins over optional-row examples.
7. Primitive source identity is fixed by `PrimitiveCatalogV1`: the five legacy
   builtin wire forms remain exact; new builtins use sealed nominal references
   in the locked core package and canonicalize through the same catalog.
8. `MayTrap` is a non-catchable ordinary contract fact. `DefectTransition`
   retires registered suffix/Owner responsibility and then traps; it is not a
   user Abort/Transfer flow variant.
9. Derive is postfix `} derive(Trait, ...)`; pattern alias remains
   `pattern as name`; Component import/export selection is manifest-based with
   no new source `extern` keyword; generic Event handlers and public Plan/Commit
   are excluded; checkpointing is sealed fixed-Epoch.

## Exact repository inventory

### Normative authority

- `docs/spec-status.md` — this profile/status/authority manifest.
- `docs/surface-syntax.md` — complete source grammar and unique elaboration.
- `docs/temporal-reactivity-formalization.typ` — Kernel/Core/static/wire/runtime semantics.

### Non-normative entry points

- `.gitignore` — repository hygiene.
- `README.md` — project entry point.
- `examples/spec/README.md` — conformance index and commands.

### Frozen TR0 historical conformance lane

- `examples/spec/validate-oracles.py`.
- `examples/spec/task35-regressions.py`.
- `examples/spec/task45-regressions.py`.
- `examples/spec/task46-regressions.py`.
- `examples/spec/diagnostics-v2.json`.
- `examples/spec/interfaces/*.json` and `interfaces/choose-once.cire`.
- `examples/spec/mutations/v1-rejects-v2-tags.json`.
- `examples/spec/runtime/packed-next-lease-runtime.json`.
- `examples/spec/accept/*.cire` and `examples/spec/reject/*.cire`.

These bytes prove only their pinned TR0/V2 decoder/effect/handler/Owner/Park
properties. The legacy validator does not parse the `.cire` files and cannot be
reported as Cire-v1.0 frontend or runtime evidence.

### Cire-v1.0 specification-model lane

- `examples/spec/validate-v1-profile.py`.
- `examples/spec/v1/manifest.json`.
- `examples/spec/v1/authority-rule-coverage.json`.
- `examples/spec/v1/diagnostics-v3.json`.
- `examples/spec/v1/interfaces/canonicalization-cases.json`.
- `examples/spec/v1/interfaces/primitive-catalog.json`.
- `examples/spec/v1/interfaces/numeric-semantics.json`.
- `examples/spec/v1/interfaces/function-contract-v3.json`.
- `examples/spec/v1/interfaces/function-contract-v3-suite.json`.
- `examples/spec/v1/interfaces/call-assembly.json`.
- `examples/spec/v1/interfaces/control-mutation.json`.
- `examples/spec/v1/interfaces/local-inference.json`.
- `examples/spec/v1/interfaces/callable-interface.json`.
- `examples/spec/v1/interfaces/callable-contract-fact.json`.
- `examples/spec/v1/interfaces/language-interface.json`.
- `examples/spec/v1/interfaces/data-declaration.json`.
- `examples/spec/v1/interfaces/trait-declaration.json`.
- `examples/spec/v1/interfaces/ability-declaration.json`.
- `examples/spec/v1/interfaces/effect-declaration.json`.
- `examples/spec/v1/interfaces/const-declaration.json`.
- `examples/spec/v1/interfaces/impl-evidence.json`.
- `examples/spec/v1/interfaces/nominal-data.json`.
- `examples/spec/v1/interfaces/trait-impl-extension.json`.
- `examples/spec/v1/interfaces/const-values.json`.
- `examples/spec/v1/interfaces/component-interface.json`.
- `examples/spec/v1/interfaces/component-manifest.json`.
- `examples/spec/v1/interfaces/link-abi.json`.
- `examples/spec/v1/interfaces/intrinsic-registry.json`.
- `examples/spec/v1/interfaces/first-party-registry.json`.
- `examples/spec/v1/interfaces/structural-intrinsic-registry.json`.
- `examples/spec/v1/interfaces/elaboration-origin-map.json`.
- `examples/spec/v1/mutations/profile-mutations.json`.
- `examples/spec/v1/runtime/protocol-models.json`.

The v1 lane exact-decodes closed specification artifacts, checks profile/header/
hash/order/reference/rule-coverage invariants, and executes finite symbolic
protocol traces. It is not a lexer/parser/typechecker/backend and is never
counted as an implementation-release gate.

## Removed authority

All former design/tutorial/simple/architecture/research documents removed by
the TR0 authority reduction remain removed. The historical decision inputs
`cire-foundation-integrated.md` and
`cirelang-task1-v1-design-closure-rev6-approved.md` live outside the repository;
after this migration they have no unique normative rule. A deleted- or
memo-only proposal cannot supply semantics to reachable grammar.

## Specification-complete gate

A candidate may enter final review only when all of the following are true:

1. The three authority files are the only normative sources; every reachable
   production/domain is decided or explicitly excluded and authority ownership
   has no overlap.
2. Appendix A has no duplicate/undefined rules except its explicitly pinned
   Unicode lexical terminals and PEG `CUT`; removed/reserved recovery spellings
   (`~`, `cap`, `defer`, and omitted named-function row) have
   exact successor diagnostics. Identity/API exclusions use the owning ordinary
   stable Resolve/profile diagnostic and need not mint a token-level alias.
3. The v1 manifest, schemas, diagnostic registry, rule coverage, hash edges,
   mutations, origin map, and finite protocol traces pass
   `python3 examples/spec/validate-v1-profile.py` with no host exception.
4. The frozen historical lane still passes
   `python3 examples/spec/validate-oracles.py`, and its counts are reported
   separately rather than added to v1 coverage.
5. Recursive NFC + RFC 8785/JCS, package/callable hash identity, canonical sort,
   alpha/public-label/default hash differentials, reference closure, and
   deterministic manifest/hash-edge freshness are exact. Hand-authored model
   artifacts are never described as generated unless a repository generator
   can reproduce their bytes.
6. PackedNext, CloseReceipt, Task, Resource, Signal/UI, finally, and Component
   resource models cover completion/cancel/close, stale/publication races,
   locator uniqueness, exact event payload, and exactly-once release.
7. Markdown links/fences, JSON, Python compilation/Ruff, Typst compilation,
   NFC, forbidden retired references, and `git diff --check` all pass.
8. One immutable commit is recorded with exact parent/tree/archive hash and
   path/blob/mode/content inventory, then receives one independent semantic and
   exact-archive review. Until approval, the approved baseline remains `71c6316`.

## Implementation-release gate

Implementation release is a later milestone. It additionally requires one
lossless parser/elaborator/checker snapshot, whole-program/imported-interface
equivalence, reference Core interpreter, Wasm/backend and Component adapters,
all protocol race tests against the production runtime, and an LSP/formatter
whose incremental results equal clean from-scratch results. No status or model
in this repository may imply those components already exist.
