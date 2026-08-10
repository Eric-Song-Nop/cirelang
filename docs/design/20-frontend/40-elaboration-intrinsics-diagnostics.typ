#import "../shared.typ": *

== Elaboration origin 的 typed-Core consumption <successor-origin-registry>

Frontend 固定阶段为：

```text
UTF-8 source -> lossless tokens -> lossless CST -> syntax validation
 -> resolved Surface HIR -> normalized Surface HIR
 -> signature/kind Surface HIR -> evidence-indexed Kernel HIR
 -> typed Core + Q/Lambda/package interface
```

Normalize 与 Kernel 是可审计 structural rewrite；后续阶段不能重新 parse、改变 CST branch、
重排 source evaluation 或重新选择 lowering。Surface 章节的
`rule-r06-origin-arena` 是 `ElaborationOriginV1`、13 项 `DerivedKindV1`、4 项
`OriginRoleV1`、arena allocation、site map 与 percent-encoded `SourceOriginV1` projection 的
唯一 normative producer authority；本章不复制第二份 origin schema、enum order、allocation 或
projection algorithm。

形式化只消费同一 frontend snapshot 产生的 exact map。令

$
  "OriginMapWF"("surface", "normalized-HIR", "kernel", "core", O)
$

当且仅当：$O$ 已按上述 Surface rule exact-decode；每个 evidence-indexed Kernel/typed-Core
diagnostic-capable site恰有一个 `CanonicalSiteIdV1 -> OriginId` edge；site 的 root slot、
Kernel preorder、role 与 field path exact equal于被检查的 Core field；所有 synthesized Core node
只使用 Surface allocation 已给出的 Derived origin；投影到既有
`SourceOriginV1=file:subject` 后，Core、Q、Lambda、diagnostic 与 source-map artifact保存同一 bytes。
形式化不得补分配 origin、沿 parent猜 primary、把 Component manifest adapter伪造成 source DAG node，
或在 alpha-renaming 后改变 public parameter label/origin。任一缺失、重复、错 role、错 field path、
noncanonical projection或 snapshot drift稳定 `origin-map-noncanonical`。因此 Surface拥有
origin construction，Formal只拥有 typed-Core consumption/WF；两者没有重叠 authority。

== Intrinsic registry 的 formal evidence/Kernel consumption <intrinsic-registry-root-v1>

Surface 章节的 `rule-r06-first-party-registry` 与 #ref(<surface-8-4-2>) 是
`FirstPartyRegistryV1` closed schema/21-entry generation contract、
`StructuralIntrinsicRegistryV1` exact 2-entry contract、`IntrinsicRegistryRootV1` child hashes及
BuildString/finalizer surface lowering的唯一 normative producer authority。本章不维护第二张
entry表、第二份 child/root schema或第二套 lowering contract。Formal只在 root与两个 child均已按
Surface authority exact-decode/hash-check后消费它们；任一 child被并入另一 array、hash漂移或按名字
重建都稳定 `intrinsic-registry-root-mismatch`。

Formal消费 Surface生成的 binding时使用 judgment

$
  K; I; Phi; Omega@Theta; Gamma |- "FirstPartyEvidenceWF"(b, sigma, e)
$

其中 $b$ 是已 exact-decode 的 Surface binding、$sigma$ 是 direct-call与 callback-entry的 rigid
generic/fresh substitution、$e$ 是该 binding 按 declaration order给出的 evidence array。
它不是通过 type name自动成立的 marker。各 predicate 的唯一 formal意义分组如下：

- `CurrentOwnerV1`、`OwnerAuthorityV1` 与 `ChildOwnerV1` 分别要求当前 phase owner exact、
  该 Owner live authority可用、child是同一 parent的 sealed direct child；它们由
  @cleanup-ledger-v1、@task-protocol-v1、@resource-protocol-v1 与 @signal-ui-protocol-v1 消费。
- `FrameClockNextSummaryCoherenceV1`、`PrivateIdentityOutwardGateV1`、
  `PackedNextPackageLeaseV1`、`ExactPackedNextOverloadV1`、
  `ExactPackagePrivateScopeV1` 与 `PrivateFrameBuilderNonescapeV1` 要求同一 package的
  clock/Next/summary、overload、lease及 private-scope tuple exact，所有 terminal path通过
  @packed-next-protocol-v1 的 nonescape/release gate。
- `ShareableV1`、`AsyncBoundarySafeV1`、`SuspensionStableV1`、
  `DuplicableEnvironmentV1`、`BoundarySafeCaptureV1`、
  `TemporalStableCaptureV1`、`CrossWorldSafeCaptureV1` 与 `OutlivesV1`
  是对完整 value/capture summary 的 structural proof，不得由 nominal whitelist或空 capture猜测；
  suspend/retention sites分别在 @task-protocol-v1、@resource-protocol-v1 与
  @signal-ui-protocol-v1 重新核对。
- `OwnerBoundParkingV1`、`ExactOutcomeTaskV1`、`ExactTaskRegionGenerationV1` 与
  `ExactCloseCellIdentityV1` 将 park/outcome/waiter/receipt绑定同一 Owner region、generation与
  close cell；它们不授权第二 waiter、foreign cancellation或隐式 cleanup。
- `OwnerStorageProvenanceV1`、`ExactResourceRootV1`、`ExactBuilderRootV1`、
  `CompleteDependencyTraceV1`、`ContextualNonescapeV1`、`FixedSnapshotV1`、
  `NoDependencyRegistrationV1`、`InvalidatingDependencyV1` 与 `ProjectionNonescapeV1`
  分别证明 storage/root/trace/context/snapshot/dependency/projection的 exact tuple，不能只比较
  nominal type或 ambient current owner。
- `ExactCoalesceLatestV1`、`ExactGenerationRevisionBindingV1`、
  `ActionSafeRowV1`、`EventEntryDischargeOnlyV1`、
  `EventOccurrenceStorageV1`、`ExactMountRootV1`、`ExactOwnerV1`、
  `ExactBackpressureArgumentV1` 与 `CandidatePlanCaptureNonescapeV1` 共同闭合
  @signal-ui-protocol-v1 的 generation/revision、typed event occurrence、action flow、FIFO lease与
  close/stale/dispatch exactly-once release；其中任一 proof都不能由另一个隐含。
- `RetainedCallbackContractV1`、`ResourceLoaderContractV1`、
  `SignalTailContractEvidenceV1` 与 `ActionPlanContractV1` 是 Surface registry中的 special
  evidence object；Formal将其 callback、owner、scope、type与完整 contract substitution作为一个
  atomic tuple核对。它们不会替代同一 array中明列的 ordinary proof predicates。

Surface 已由其 `rule-r06-first-party-registry` 定义的唯一
`instantiate_first_party` 总函数产生 binding 声明的
evidence-indexed Kernel tag 与 M3 typed-Core/Q/Lambda objects。Formal 只在 root/child hash、
Surface binding WF、`OriginMapWF`、每个 evidence object与 direct/callback contract全部成立时接受该
exact output；本章不再生成、重选或改写其 Kernel/Core/Q/Lambda projection。Callback entry owner、
captured/generated fresh set与 special contract必须 exact等于 Surface binding；每个 evidence恰
discharge一次。漏证据、重复证据、kind/slot/scope drift、foreign owner或 runtime-name dispatch分别稳定
使用已注册的 `first-party-*` / `intrinsic-registry-root-mismatch` diagnostic；不得发明简化 wire。
Kernel/Core tag的静态与动态意义由下述 PackedNext、Task、Resource、Signal/UI、checkpoint rules给出。

对于 Surface-owned structural child，Formal仅解释已生成 Kernel node：`BuildStringV1` 的每个 literal
byte segment与 hole computation按 Surface origin/source-order edge执行一次，hole保留自身
effect/flow，locked-core `Show` format step满足 ProtocolPure，最终构造一次 String；不存在隐式
Show。`ControlFinallyV1` 在 @cleanup-ledger-v1 中登记一个 sealed suffix责任；body 的任一
Returns/Aborts/Transfers先执行或移交该 responsibility并保留原 terminal tag。Cleanup本身
NoSuspend、Returns Unit、无 outward Abort/Transfer且在 finalization point满足
phase/Owner/capture/usage；multi-shot duplication只在 Replayable时允许。它不是 user destructor、
`defer`、catchable error或新的 flow aggregation model。Derive使用 Surface分配的
`SealedIntrinsicV1` origin但不生成第三个 structural binding，其 semantic evidence仍由
`ImplEvidenceV1` 与 ordinary coherence闭合。

== Diagnostic stage 与 stable rejection <successor-diagnostics>

本 profile 的 stable diagnostic root是 exact closed artifact：

```text
DiagnosticEntryV3 = {
  id: NFC nonempty kebab String,
  stage: "Decode" | "Lex" | "Parse" | "Syntax" | "Resolve" | "Kind"
       | "Type" | "Row" | "HandlerWF" | "Flow" | "Capture" | "Usage"
       | "World" | "Phase" | "Owner" | "ContractWF",
  causal_cluster: NFC nonempty String,
  primary_origin_role: "PrincipalV1" | "ArgumentV1" | "DeclarationV1"
                     | "SynthesisBasisV1",
  required_notes: [NFC nonempty kebab String],
  fix_safety: "None" | "Manual" | "MachineApplicable" | "MaybeIncorrect"
}

CireDiagnosticsV3 = {
  artifact: "CireDiagnosticsV3",
  profile: "Cire-v1.0",
  schema_version: 3,
  diagnostics: [DiagnosticEntryV3; 133]
}
```

同一 causal defect/origin cluster 的 primary precedence按“最早可确定且能阻止后阶段”固定为
`Decode > Lex > Parse > Syntax > Resolve > Kind > Type > Row > HandlerWF > Flow > Capture >
Usage > World > Phase > Owner > ContractWF`。这是唯一 stage enum/order；Interface、
Elaboration、Coherence、Effect、Const、Component、Runtime 可作 causal-cluster 名称但不是
stage literal。Raw JSON/container/JCS/hash failure停在 Decode；已 exact-decode 但 semantic/hash-edge/
protocol WF 失败在最早可确定的 Resolve/Kind/Type/.../ContractWF 阶段拒绝，不伪造
未注册的 `*-schema-mismatch` umbrella ID。

下列 tuple 按 id UTF-8 bytes 严格递增，恰是 133 个 entries 的全部六字段；未列出 ID
不属于 `CireDiagnosticsV3`：

```text
id | stage | causal_cluster | primary_origin_role | required_notes | fix_safety
abort-has-no-resume-transition | ContractWF | AbortTransition | DeclarationV1 | [abort-operation,forbidden-resume-transition] | None
application-argument-type-mismatch | ContractWF | CallableApplication | ArgumentV1 | [actual-argument-type,expected-parameter-type,parameter-index] | Manual
application-arity-mismatch | ContractWF | CallableApplication | ArgumentV1 | [actual-arity,expected-arity] | Manual
associated-contract-mismatch | Kind | AssociatedContract | DeclarationV1 | [expected-contract,observed-contract] | None
associated-declaration-constraint-not-in-profile | Kind | AssociatedDeclarationConstraint | DeclarationV1 | [remove-associated-constraint] | None
associated-parameterization-not-in-profile | Kind | AssociatedParameterization | DeclarationV1 | [remove-associated-parameters] | None
associated-type-normalization-cycle | Type | TraitNormalization | DeclarationV1 | [projection-cycle] | Manual
byte-literal-out-of-range | Type | LiteralRange | ArgumentV1 | [valid-range-0-through-255] | MachineApplicable
call-obligation-unsatisfied | ContractWF | CallObligation | PrincipalV1 | [obligation-id,obligation-stage,unsatisfied-predicate] | Manual
callable-interface-contract-mismatch | ContractWF | InterfaceHash | PrincipalV1 | [expected-contract-hash,observed-contract-hash] | None
callable-source-import-collision | Resolve | InterfaceGraph | PrincipalV1 | [conflicting-source,module-export-key] | None
capability-binder-default-not-in-v1 | Kind | CapabilityBinder | DeclarationV1 | [remove-default] | MachineApplicable
capability-identity-required | Kind | CapabilityIdentity | DeclarationV1 | [introduce-direct-capability-binder] | Manual
clock-package-family-not-clock-indexing | Kind | ClockFamily | SynthesisBasisV1 | [actual-family,expected-clock-indexing-family] | None
clock-package-path-observer-mismatch | ContractWF | ClockPathObserver | SynthesisBasisV1 | [expected-path-observer,observed-path-observer,path-index] | None
clock-package-private-identity-escape | Capture | ClockIdentityEscape | SynthesisBasisV1 | [clock-slot,escaping-obligation-id] | None
clock-package-transfer-captures-private-identity | Capture | ClockTransferCapture | SynthesisBasisV1 | [clock-slot,transfer-site] | None
component-native-async-not-in-v1 | ContractWF | ComponentBoundary | PrincipalV1 | [use-owner-backed-resource-adapter] | None
component-public-type-not-safe | Type | ComponentBoundary | PrincipalV1 | [offending-public-type] | Manual
const-definite-trap | ContractWF | ConstEvaluation | PrincipalV1 | [defect-transition] | None
const-evaluation-did-not-terminate | ContractWF | ConstEvaluation | PrincipalV1 | [evaluation-budget] | None
const-operation-not-safe | ContractWF | ConstEvaluation | DeclarationV1 | [offending-operation] | Manual
const-safe-requirement-failed | ContractWF | ConstEvaluation | DeclarationV1 | [offending-operation] | None
const-termination-not-proven | ContractWF | ConstEvaluation | DeclarationV1 | [recursive-call-cycle] | None
contract-component-kind-mismatch | ContractWF | ContractComponentKind | PrincipalV1 | [component-path,expected-kind,observed-kind] | None
contract-parameter-inconsistent-instantiation | ContractWF | ContractInstantiation | ArgumentV1 | [contract-parameter-slot,expected-instantiation,observed-instantiation] | None
contract-projection-escapes-scope | Capture | ContractProjectionScope | PrincipalV1 | [binder-slot,escaping-projection] | None
contract-term-cycle | ContractWF | ContractDependencyCycle | DeclarationV1 | [contract-parameter-slot,cycle-path] | None
data-field-not-public | Type | NominalVisibility | ArgumentV1 | [hidden-field] | Manual
defer-not-in-cire-v1 | Syntax | RemovedSurface | PrincipalV1 | [use-sealed-finally] | MaybeIncorrect
delegates-outside-handler-clause | ContractWF | HandlerProjectionContext | SynthesisBasisV1 | [delegates-site,expected-handler-clause] | None
dispose-report-schema-mismatch | ContractWF | DisposeReport | PrincipalV1 | [expected-role-order] | None
duplicate-package-instance | ContractWF | PackageGraph | PrincipalV1 | [package-instance-id] | None
effect-header-conformance-mismatch | Resolve | EffectHeaderConformance | DeclarationV1 | [declared-operation-signature,implemented-operation-signature] | None
extension-resolution-ambiguous | Resolve | ExtensionResolution | PrincipalV1 | [candidate-identities] | Manual
extension-self-parameter-required | Syntax | ExtensionSelfParameter | DeclarationV1 | [expected-self-first-parameter] | MachineApplicable
first-party-action-occurrence-contract-mismatch | ContractWF | FirstPartyOccurrence | SynthesisBasisV1 | [event-payload-type,occurrence-id] | None
first-party-callback-entry-owner-mismatch | ContractWF | FirstPartyCallback | SynthesisBasisV1 | [callback-owner,entry-owner] | None
first-party-callback-scheme-mismatch | ContractWF | FirstPartyCallback | SynthesisBasisV1 | [binding-id,callback-slot] | None
first-party-projection-namespace-mismatch | ContractWF | FirstPartyProjection | SynthesisBasisV1 | [projection-namespace] | None
first-party-registry-contract-nonunique | ContractWF | FirstPartyRegistry | PrincipalV1 | [binding-id,conflicting-contracts] | None
first-party-registry-noncanonical-order | ContractWF | FirstPartyRegistry | PrincipalV1 | [first-out-of-order-id] | None
first-party-retained-callback-contract-mismatch | ContractWF | FirstPartyRetention | SynthesisBasisV1 | [callback-contract,retained-revision] | None
first-party-static-scope-escape | ContractWF | FirstPartyScope | SynthesisBasisV1 | [escaping-slot] | None
first-party-type-template-kind-mismatch | Kind | FirstPartyKind | PrincipalV1 | [expected-kind,template-slot] | None
float-pattern-not-in-cire-v1 | Syntax | PatternGrammar | ArgumentV1 | [use-guard-or-ordinary-comparison] | MaybeIncorrect
forward-application-arity-type-mismatch | ContractWF | ForwardApplication | ArgumentV1 | [actual-argument-types,expected-parameter-types,forward-site] | None
forward-disposition-quantity-mismatch | Usage | ForwardDisposition | SynthesisBasisV1 | [available-quantity,forward-site,required-quantity] | None
forward-obligation-projection-mismatch | ContractWF | ForwardObligationProjection | SynthesisBasisV1 | [forward-site,obligation-id,projection-stage] | None
forward-operation-mismatch | Resolve | ForwardOperation | SynthesisBasisV1 | [actual-operation,expected-operation,forward-site] | None
forward-route-mismatch | Resolve | ForwardRoute | SynthesisBasisV1 | [actual-route,expected-route,forward-site] | None
handler-clause-mode-required | Syntax | InlineHandlerRecovery | DeclarationV1 | [expected-abort-fun-once-or-ctl] | MachineApplicable
handler-disposition-escapes-scope | Capture | HandlerDispositionScope | DeclarationV1 | [disposition-binder,escaping-site] | None
hof-complete-path-observer-mismatch | ContractWF | HigherOrderPathObserver | SynthesisBasisV1 | [expected-path-observers,observed-path-observers,path-index] | None
impl-visibility-not-allowed | Syntax | ImplVisibility | DeclarationV1 | [remove-visibility-modifier] | MachineApplicable
imported-function-export-mismatch | Resolve | ImportedCallableResolution | DeclarationV1 | [actual-export-path,artifact-hash,expected-export-path] | None
independent-ability-impl-not-in-profile | Kind | AbilityCoherence | DeclarationV1 | [abilities-use-handlers-not-trait-impls] | None
integer-conversion-out-of-range | Type | NumericConversion | ArgumentV1 | [destination-range,source-value] | Manual
interpolation-evidence-not-unique | Resolve | StringInterpolation | ArgumentV1 | [show-candidates] | Manual
intrinsic-registry-root-mismatch | ContractWF | IntrinsicRegistry | PrincipalV1 | [expected-child-registry] | None
local-function-evaluation-mismatch | ContractWF | LocalCallableEvaluation | DeclarationV1 | [expected-path-contracts,local-declaration-slot,observed-path-contracts] | None
local-function-ref-unresolved | Resolve | LocalCallableResolution | PrincipalV1 | [declaration-slot,reference-site] | None
maytrap-not-an-effect | Row | DefectTransition | PrincipalV1 | [model-as-ordinary-fact] | MachineApplicable
method-candidate-ambiguous | Resolve | MethodResolution | PrincipalV1 | [candidate-identities] | Manual
multi-shot-captures-one-shot-resumption | Usage | ResumptionUsage | PrincipalV1 | [captured-resumption-slot,closure-site,resumption-quantity] | Manual
named-call-requires-static-signature | Kind | StaticCallMetadata | ArgumentV1 | [callee-type] | Manual
named-capability-escapes | Capture | CapabilityIdentityEscape | PrincipalV1 | [capability-binder,escaping-site] | Manual
named-function-effect-row-required | Syntax | NamedFunctionBoundary | DeclarationV1 | [insert-explicit-row] | MachineApplicable
newtype-representation-cycle | Type | NominalLayout | DeclarationV1 | [unbroken-recursion] | Manual
no-matching-clock-lock | World | ClockLock | PrincipalV1 | [available-clock-locks,required-clock] | Manual
non-exhaustive-match | Type | PatternMatrix | PrincipalV1 | [missing-witness-pattern] | Manual
open-visibility-not-applicable | Kind | Visibility | DeclarationV1 | [allowed-declaration-kinds] | MachineApplicable
operation-secondary-row-must-be-closed | ContractWF | OperationSecondaryRow | DeclarationV1 | [close-operation-secondary-row] | MachineApplicable
origin-map-noncanonical | ContractWF | ElaborationOrigin | SynthesisBasisV1 | [first-invalid-origin-id] | None
package-import-not-locked | Resolve | PackageImport | PrincipalV1 | [dependency-instance-id] | Manual
package-instance-hash-mismatch | ContractWF | PackageIdentity | PrincipalV1 | [expected-package-id,observed-package-id] | None
packed-next-builder-result-mismatch | ContractWF | PackedNextBuilder | SynthesisBasisV1 | [actual-builder-result,expected-packed-next-type] | None
packed-next-control-protocol-mismatch | ContractWF | PackedNextControlProtocol | SynthesisBasisV1 | [actual-control-protocol,expected-control-protocol] | None
packed-next-observer-trust-mismatch | ContractWF | PackedNextObserver | SynthesisBasisV1 | [expected-observer-summary,observed-observer-summary,path-index] | None
packed-next-owner-scope-mismatch | Owner | PackedNextOwnerScope | SynthesisBasisV1 | [owner-slot,package-site] | None
packed-next-pack-phase-mismatch | Phase | PackedNextPhase | SynthesisBasisV1 | [actual-phase-requirement,expected-pack-phase,path-index] | None
packed-next-package-header-mismatch | Decode | PackedNextPackageHeader | PrincipalV1 | [expected-artifact-profile-version,observed-artifact-profile-version] | None
packed-next-runtime-protocol-mismatch | ContractWF | PackedNextRuntimeProtocol | SynthesisBasisV1 | [expected-transition-table,first-invalid-transition,runtime-trace] | None
packed-next-sealed-origin-mismatch | ContractWF | PackedNextSealedOrigin | SynthesisBasisV1 | [expected-sealed-origin,observed-sealed-origin] | None
packed-next-storage-owner-mismatch | Owner | PackedNextStorageOwner | SynthesisBasisV1 | [owner-scope,storage-owner] | None
park-disposition-protocol-mismatch | ContractWF | ParkDisposition | SynthesisBasisV1 | [actual-disposition,expected-one-shot-disposition,park-site] | None
park-generation-protocol-mismatch | ContractWF | ParkGeneration | SynthesisBasisV1 | [actual-generation,expected-generation,park-site] | None
park-owner-outlives-missing | Owner | ParkOwnerScope | SynthesisBasisV1 | [park-owner,required-outlives-edge,resumption-owner] | None
park-path-observer-mismatch | ContractWF | ParkPathObserver | SynthesisBasisV1 | [expected-path-observer,observed-path-observer,park-site] | None
park-required-phase-mismatch | Phase | ParkPhase | PrincipalV1 | [actual-phase-requirement,park-site,required-phase] | None
park-resumption-type-mismatch | ContractWF | ParkResumptionType | SynthesisBasisV1 | [continuation-answer-type,park-site,resumption-answer-type] | None
park-source-payload-mismatch | ContractWF | ParkPayloadType | ArgumentV1 | [completion-port-type,park-source-type,resumption-argument-type] | None
path-bind-literal-prefix-forbidden | ContractWF | PathBindPrefix | SynthesisBasisV1 | [path-bind-site,prefix-outcome] | None
path-bind-observer-composition-mismatch | ContractWF | PathBindObserver | SynthesisBasisV1 | [composed-observer,expected-observer,path-bind-site] | None
path-bind-return-binder-mismatch | ContractWF | PathBindReturnBinder | SynthesisBasisV1 | [binder-type,path-bind-site,returned-type] | None
path-bind-terminal-not-preserved | ContractWF | PathBindTerminal | SynthesisBasisV1 | [observed-terminal-policy,path-bind-site,required-terminal-policy] | None
positional-after-labelled | Parse | CallAssembly | ArgumentV1 | [argument-index,first-labelled-index] | Manual
postfix-derive-required | Syntax | DerivedPlacement | DeclarationV1 | [move-derive-after-declaration] | MachineApplicable
projected-latent-site-key-mismatch | ContractWF | LatentSiteProjection | SynthesisBasisV1 | [application-slot,latent-site-key,projected-source-site] | None
projected-obligation-stage-lost | ContractWF | ObligationProjection | SynthesisBasisV1 | [obligation-id,projected-stage,source-stage] | None
public-overload-requires-distinct-export-path | Resolve | PublicCallableGraph | DeclarationV1 | [conflicting-export-path] | None
qualified-local-id-space-exhausted | ContractWF | QualifiedLocalId | SynthesisBasisV1 | [application-slot,exhausted-u32-domain,local-id] | None
record-construction-missing-field | Type | NominalConstruction | ArgumentV1 | [missing-fields] | Manual
record-update-base-not-final | Syntax | NominalUpdate | ArgumentV1 | [move-update-base-to-final-position] | Manual
recursive-public-callable-scc-not-in-v1 | ContractWF | PublicCallableGraph | DeclarationV1 | [recursive-export-cycle] | None
return-projection-does-not-match-flow | ContractWF | ReturnFlowProjection | SynthesisBasisV1 | [expected-flow-projection,observed-return-projection] | None
row-literal-has-multiple-tails | Row | RowLiteralTail | PrincipalV1 | [retain-one-row-tail] | MachineApplicable
row-predicate-not-in-profile | Kind | RowPredicateProfile | DeclarationV1 | [allowed-predicates] | None
runtime-protocol-trace-mismatch | ContractWF | RuntimeProtocol | PrincipalV1 | [first-invalid-transition,trace-id] | None
sealed-checkpoint-contract-mismatch | ContractWF | Checkpoint | SynthesisBasisV1 | [checkpoint-site,expected-transition] | None
semantic-string-payload-mismatch | ContractWF | SemanticConstPayload | PrincipalV1 | [unicode-scalars,utf8-bytes] | None
semantic-summary-not-normalized | ContractWF | SemanticSummaryNormalization | PrincipalV1 | [expected-normal-form,observed-summary] | None
signal-track-builder-root-mismatch | ContractWF | SignalBuilder | SynthesisBasisV1 | [builder-root,tracking-owner] | None
surface-cap-marker-removed | Syntax | RemovedSurface | PrincipalV1 | [remove-cap-marker] | MaybeIncorrect
surface-tilde-label-removed | Syntax | RemovedSurface | PrincipalV1 | [replace-with-name-equals-expression] | MachineApplicable
term-actual-source-unavailable | ContractWF | TermActualSource | ArgumentV1 | [formal-parameter-slot,surviving-projection] | None
term-actual-substitution-mismatch | ContractWF | TermActualSubstitution | ArgumentV1 | [actual-summary,formal-parameter-slot,projected-observer] | None
terminal-transfer-has-no-value | Flow | TerminalFlow | PrincipalV1 | [terminal-outcome,value-context] | None
trailing-lambda-target-not-callable | Kind | TrailingLambda | ArgumentV1 | [final-nonreceiver-parameter] | Manual
trait-impl-orphan-violation | Type | TraitCoherence | DeclarationV1 | [trait-package,type-package] | None
trait-impl-overlap | Type | TraitCoherence | DeclarationV1 | [conflicting-impl-identities] | None
trait-orphan-impl | Type | TraitCoherence | DeclarationV1 | [trait-package,type-package] | None
type-alias-cycle | Type | NominalLayout | DeclarationV1 | [alias-cycle] | Manual
ui-action-must-return | Flow | UiActionFlow | SynthesisBasisV1 | [observed-terminal-flow] | Manual
ui-action-suspend-policy-required | Phase | UiActionSuspension | SynthesisBasisV1 | [action-policy,suspending-site] | Manual
unknown-contract-computation-variant | Decode | ContractComputationVariant | PrincipalV1 | [computation-tag,contract-path] | None
unknown-obligation-stage | Decode | ObligationStage | PrincipalV1 | [obligation-id,observed-stage] | None
unknown-obligation-variant | Decode | ObligationVariant | PrincipalV1 | [obligation-id,obligation-tag] | None
unknown-path-outcome-v2 | Decode | PathOutcomeVariant | PrincipalV1 | [outcome-tag,path-index] | None
unknown-resumption-primitive | Resolve | ResumptionPrimitive | PrincipalV1 | [allowed-primitives,observed-primitive] | Manual
unreachable-pattern | Type | PatternMatrix | PrincipalV1 | [subsuming-arm,warning] | None
unsupported-contract-schema-version | Decode | ContractSchemaVersion | PrincipalV1 | [observed-schema-version,supported-schema-version] | None
wire-u32-out-of-range | Decode | WireU32 | PrincipalV1 | [field-path,observed-value,valid-range] | None
```

Recovery CST 不进入 semantics；后阶段错误只能做 secondary note，不能替换更早 primary。Component
manifest diagnostic使用 manifest path，不能伪造 source origin。`trait-impl-orphan-violation`
与 `trait-orphan-impl` 作为冻结的两个 distinct ID 都保留，producer不能自行 alias；其余历史
umbrella spelling 都不属于本 registry。
