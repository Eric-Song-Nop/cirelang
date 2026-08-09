#import "../shared.typ": *

==== Closed first-party binding registry <surface-8-4-1>

Cire-v1.0 中的 first-party source entry不得停留在例子/prose。Surface authority必须生成唯一
`FirstPartyRegistryV1`；它是 compiler/LSP/conformance共用的 exact registry，不是 public Core wire：

```text
BindingIdV1 = NFC nonempty String matching
  "Cire-v1.0/intrinsic/" + [a-z0-9]+ ("." | "-" | [a-z0-9])*

CallbackNameV1 = NFC nonempty identifier
NfcNameV1      = NFC nonempty identifier

FirstPartyRegistryV1 = {
  artifact: "FirstPartyRegistryV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  bindings: [FirstPartyBindingV1; 21]
}

FirstPartyBindingV1 = {
  kind: "FirstPartyBindingV1",
  id: BindingIdV1,
  source: FirstPartySourceV1,
  slots: [FirstPartySlotV1],
  types: [FirstPartyGenericBinderV1],
  fresh: [FirstPartyFreshBinderV1],
  direct: FirstPartyContractTemplateV1,
  callbacks: [FirstPartyCallbackV1],
  evidence: [FirstPartyEvidenceV1],
  kernel: FirstPartyKernelV1
}

FirstPartySourceV1 =
    { kind: "IntrinsicModuleFunctionV1", module: NfcNameV1, member: NfcNameV1 }
  | { kind: "UnqualifiedFunctionV1", name: NfcNameV1 }
  | { kind: "AssociatedFunctionV1", receiver: NfcNameV1, member: NfcNameV1 }
  | { kind: "AssociatedProjectionV1", receiver: NfcNameV1, member: NfcNameV1,
      surface_member: NfcNameV1 }
  | { kind: "ClosedLiteralV1", nominal: NfcNameV1, variant: NfcNameV1 }

FirstPartySlotV1 =
    { kind: "ImplicitReceiverSlotV1", slot: u32,
      passing: "ImplicitReceiverV1", type: TypePatternV1 }
  | { kind: "NamedOrPositionalSlotV1", slot: u32,
      passing: "NamedOrPositionalV1", public_label: NFC nonempty String,
      defaultable: false, type: TypePatternV1 }

FirstPartyTypeTemplateV1 =
    { kind: "BuiltinTypeTemplateV1", name: NfcNameV1 }
  | { kind: "BinderTypeTemplateV1", binder: FirstPartyBinderRefV1 }
  | { kind: "NominalTypeTemplateV1", module: [NfcNameV1], name: NfcNameV1,
      arguments: [FirstPartyTypeTemplateV1] }
  | { kind: "CapabilityTypeTemplateV1", identity: FirstPartyBinderRefV1,
      family: FirstPartyEffectFamilyTemplateV1 }
  | { kind: "FunctionTypeTemplateV1", parameters: [FirstPartyTypeTemplateV1],
      result: FirstPartyTypeTemplateV1 }

FirstPartyEffectFamilyTemplateV1 =
    { kind: "NominalEffectFamilyTemplateV1",
      module: [NfcNameV1], name: NfcNameV1,
      arguments: [FirstPartyTypeTemplateV1] }

TypePatternV1 =
    { kind: "TypeRefV1", type: FirstPartyTypeTemplateV1 }
  | { kind: "ContextualCallbackRefV1", callback_name: CallbackNameV1 }
  | { kind: "CallableCallbackRefV1", callback_name: CallbackNameV1 }

FirstPartyGenericBinderV1 =
    { kind: "KindBinderV1", binder_slot: u32,
      binder_kind: "TypeV1" | "OwnerRegionV1" | "ClockIdentityV1"
                 | "TrackEpochScopeV1" | "UiGenerationScopeV1"
                 | "EffectRowV1" }
  | { kind: "UiRevisionScopeBinderV1", binder_slot: u32,
      generation: { kind: "GenericBinderRefV1", binder_slot: u32 } }

FirstPartyBinderRefV1 =
    { kind: "GenericBinderRefV1", binder_slot: u32 }
  | { kind: "FreshBinderRefV1", fresh_slot: u32 }

FirstPartyFreshVisibilityV1 =
    { kind: "DirectOnlyV1" }
  | { kind: "CallbackOnlyV1", callback_name: CallbackNameV1 }
  | { kind: "DirectAndCallbackPrivateV1", callback_name: CallbackNameV1 }

FirstPartyFreshOriginV1 =
    { kind: "ChildOwnerRegionV1", parent: FirstPartyBinderRefV1,
      relation: "DirectChildV1" }
  | { kind: "FrameClockIdentityV1", owner: FirstPartyBinderRefV1 }
  | { kind: "ClockPackageSummaryV1", identity: FirstPartyBinderRefV1,
      payload: FirstPartyTypeTemplateV1 }
  | { kind: "InstalledTrackEpochV1" }
  | { kind: "AdmittedUiGenerationV1", owner: FirstPartyBinderRefV1 }
  | { kind: "UiRevisionOfV1", generation: FirstPartyBinderRefV1 }

FirstPartyFreshBinderV1 =
    { kind: "GenerativeFreshBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1" | "TrackEpochScopeV1"
                 | "UiGenerationScopeV1" | "UiRevisionScopeV1",
      cardinality: "PerDirectCallV1" | "PerCallbackInvocationV1"
                 | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1",
      visibility: FirstPartyFreshVisibilityV1,
      origin: FirstPartyFreshOriginV1 }
  | { kind: "DerivedCurrentOwnerBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1", derivation: "CurrentOwnerOfEntryPhaseV1",
      visibility: { kind: "DirectOnlyV1" }
                | { kind: "DirectAndCallbackPrivateV1",
                    callback_name: CallbackNameV1 } }
  | { kind: "OpenedPackedNextBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1",
      packed_parameter_slot: u32,
      component: "OwnerRegionV1" | "ClockIdentityV1"
               | "ClockPackageSummaryV1",
      visibility: { kind: "DirectAndCallbackPrivateV1",
                    callback_name: CallbackNameV1 } }

FirstPartyTemporalV1 =
    { kind: "PureV1" }
  | { kind: "HostObservableV1" }

FirstPartyPhaseV1 = "PureV1" | "ComputeV1" | "ActionV1" | "CommitV1"

FirstPartyRowTemplateV1 =
    { kind: "EmptyRowV1" }
  | { kind: "AnonymousAsyncRowV1" }
  | { kind: "GenericEffectRowV1", binder: FirstPartyBinderRefV1 }
  | { kind: "CallbackRowV1", callback: FirstPartyCallbackRefV1 }

FirstPartySuspensionTemplateV1 =
    { kind: "NoSuspendV1" }
  | { kind: "AsyncMaySuspendV1" }
  | { kind: "CallbackSuspensionV1", callback: FirstPartyCallbackRefV1 }

FirstPartyWorldTemplateV1 =
    { kind: "SameWorldV1" }
  | { kind: "CallbackWorldV1", callback: FirstPartyCallbackRefV1 }
  | { kind: "ProjectPrivateWorldV1", callback: FirstPartyCallbackRefV1,
      private_binders: [FirstPartyBinderRefV1] }

FirstPartyReturnMapV1 =
    { kind: "PackNextReturnMapV1", input: FirstPartyTypeTemplateV1,
      output: FirstPartyTypeTemplateV1 }
  | { kind: "AcquireOptionReturnMapV1", lost: FirstPartyTypeTemplateV1,
      input: FirstPartyTypeTemplateV1, output: FirstPartyTypeTemplateV1 }

FirstPartyFlowTemplateV1 =
    { kind: "ReturnsOnlyV1", result: FirstPartyTypeTemplateV1 }
  | { kind: "AwaitOrParkV1", result: FirstPartyTypeTemplateV1,
      park: "ParkContractV2" }
  | { kind: "CallbackFlowV1", callback: FirstPartyCallbackRefV1 }
  | { kind: "MapCallbackFlowV1", callback: FirstPartyCallbackRefV1,
      returns: FirstPartyReturnMapV1,
      preserve_terminal_tags: ["AbortsV2", "TransfersV2"] }

FirstPartyConstructionV1 = {
  kind: "CanonicalFirstPartyLiteralPathsV1",
  demand_policy: "NormalizedRowAndKernelV1",
  obligation_policy: "EvidenceArrayOrderV1",
  site_policy: "AllReferencedDirectAndProjectedCallbackSitesV1",
  result_policy: "TypeAndFlowDirectedV1",
  capture_policy: "ActualArgumentsAndCallbacksV1",
  usage_policy: "AuthoritySlotsExactV1",
  origin_policy: "ElaborationOriginProjectionV1"
}

FirstPartyContractTemplateV1 = {
  kind: "FirstPartyContractTemplateV1",
  phase: FirstPartyPhaseV1,
  row: FirstPartyRowTemplateV1,
  suspension: FirstPartySuspensionTemplateV1,
  world: FirstPartyWorldTemplateV1,
  flow: FirstPartyFlowTemplateV1,
  temporal: FirstPartyTemporalV1,
  construction: FirstPartyConstructionV1
}

FirstPartyCallbackV1 = {
  kind: "FirstPartyCallbackV1",
  name: CallbackNameV1,
  parameter_slot: u32,
  acquisition: "ContextualV1" | "CallableValueV1",
  type: FirstPartyTypeTemplateV1,
  contract: FirstPartyContractTemplateV1,
  scheme: FirstPartyCallbackSchemeV1
}

FirstPartyCallbackEntryOwnerV1 =
    { kind: "NoCallbackEntryOwnerV1" }
  | { kind: "ExactCallbackEntryOwnerV1",
      owner: FirstPartyBinderRefV1 }

FirstPartyCallbackSchemeV1 = {
  kind: "FirstPartyCallbackSchemeV1",
  trigger: "DirectInvocationV1" | "CallableInvocationV1"
         | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1"
         | "PerEventDispatchV1",
  entry_owner: FirstPartyCallbackEntryOwnerV1,
  captured_fresh_slots: [u32],
  generated_fresh_slots: [u32]
}

FirstPartyCallbackRefV1 = {
  kind: "BindingCallbackRefV1",
  callback_name: CallbackNameV1
}

FirstPartyEvidenceArgumentV1 =
    FirstPartyBinderRefV1
  | { kind: "ParameterSlotRefV1", slot: u32 }
  | FirstPartyCallbackRefV1
  | { kind: "EvidenceTypeRefV1", type: FirstPartyTypeTemplateV1 }

FirstPartyEvidenceRuleV1 =
    "CurrentOwnerV1" | "OwnerAuthorityV1" | "ChildOwnerV1"
  | "FrameClockNextSummaryCoherenceV1" | "PrivateIdentityOutwardGateV1"
  | "PackedNextPackageLeaseV1" | "ExactPackedNextOverloadV1"
  | "ExactCloseCellIdentityV1" | "OutlivesV1" | "ShareableV1"
  | "AsyncBoundarySafeV1" | "SuspensionStableV1" | "OwnerBoundParkingV1"
  | "ExactOutcomeTaskV1" | "DuplicableEnvironmentV1"
  | "OwnerStorageProvenanceV1" | "BoundarySafeCaptureV1"
  | "TemporalStableCaptureV1" | "CrossWorldSafeCaptureV1"
  | "ExactResourceRootV1" | "ExactBuilderRootV1"
  | "CompleteDependencyTraceV1" | "ContextualNonescapeV1"
  | "FixedSnapshotV1" | "NoDependencyRegistrationV1"
  | "ExactCoalesceLatestV1" | "ExactGenerationRevisionBindingV1"
  | "ActionSafeRowV1" | "EventEntryDischargeOnlyV1"
  | "EventOccurrenceStorageV1"
  | "ExactMountRootV1" | "ExactOwnerV1" | "InvalidatingDependencyV1"
  | "ExactBackpressureArgumentV1" | "ExactPackagePrivateScopeV1"
  | "ExactTaskRegionGenerationV1" | "ProjectionNonescapeV1"
  | "CandidatePlanCaptureNonescapeV1" | "PrivateFrameBuilderNonescapeV1"

ResourceLoaderContractV1 = {
  kind: "ResourceLoaderContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  generation_owner: FirstPartyBinderRefV1,
  key_type: FirstPartyTypeTemplateV1,
  value_type: FirstPartyTypeTemplateV1,
  error_type: FirstPartyTypeTemplateV1
}

SignalTailContractEvidenceV1 = {
  kind: "SignalTailContractEvidenceV1",
  callback: FirstPartyCallbackRefV1,
  clock: FirstPartyBinderRefV1,
  input_type: FirstPartyTypeTemplateV1,
  output_type: FirstPartyTypeTemplateV1
}

ActionPlanContractV1 = {
  kind: "ActionPlanContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  generation: FirstPartyBinderRefV1,
  revision: FirstPartyBinderRefV1,
  event_type: FirstPartyTypeTemplateV1,
  event_parameter_index: u32,
  occurrence_policy: "OwnerStoredExactQueuedOccurrenceV1"
}

FirstPartyRetainedInvocationScopeV1 =
    { kind: "InstalledTrackInvocationV1", epoch: FirstPartyBinderRefV1 }
  | { kind: "UiAdmissionInvocationV1", generation: FirstPartyBinderRefV1,
      revision: FirstPartyBinderRefV1 }

RetainedCallbackContractV1 = {
  kind: "RetainedCallbackContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  invocation_scope: FirstPartyRetainedInvocationScopeV1,
  capture_policy: "OwnerStorageBoundarySafeOutlivesV1"
}

FirstPartyEvidenceV1 =
    { kind: "ProofRuleEvidenceV1", rule: FirstPartyEvidenceRuleV1,
      arguments: [FirstPartyEvidenceArgumentV1] }
  | ResourceLoaderContractV1
  | SignalTailContractEvidenceV1
  | ActionPlanContractV1
  | RetainedCallbackContractV1

FirstPartyKernelV1 =
    { kind: "PackedNextPackV1" }
  | { kind: "PackedNextOpenV1" }
  | { kind: "PackedNextDisposeV1" }
  | { kind: "OperationCallV1", family: "AsyncV1",
      operation: "awaitV1" | "await_receiptV1" }
  | { kind: "TaskCancelV1" }
  | { kind: "ResourceSwitchLatestV1" }
  | { kind: "ResourceViewV1" }
  | { kind: "ResourceDisposeV1" }
  | { kind: "SignalMapV1" }
  | { kind: "SignalTrackV1" }
  | { kind: "TrackReadLiveV1" }
  | { kind: "TrackReadSourceV1" }
  | { kind: "SnapshotReadLiveV1" }
  | { kind: "SnapshotReadSourceV1" }
  | { kind: "UiBackpressureCoalesceLatestV1" }
  | { kind: "UiRunSignalV1" }
  | { kind: "UiBuilderOwnerV1" }
  | { kind: "UiRenderV1" }
  | { kind: "UiCandidateActionV1" }
  | { kind: "UiMountDisposeV1" }

N(n,name,T) = { kind: "NamedOrPositionalSlotV1", slot: n,
  passing: "NamedOrPositionalV1", public_label: name,
  defaultable: false, type: T }
I(n,T) = { kind: "ImplicitReceiverSlotV1", slot: n,
  passing: "ImplicitReceiverV1", type: T }
ContextualCallback(name) = {
  kind: "ContextualCallbackRefV1", callback_name: name
}
CallableCallback(name) = {
  kind: "CallableCallbackRefV1", callback_name: name
}
```

所有 object/union只允许上列 exact fields/tags。`types[*].binder_slot`、
`fresh[*].fresh_slot` 与 `slots[*].slot` 分别从 0 连续、严格递增且无重复；
每个 binder reference必须解析到同 binding中较早声明且 kind相符的 binder。
字段名 `fresh` 为 registry v1 wire兼容名；其中 `DerivedCurrentOwnerBinderV1` 明确不是
generative fresh scope，不能分配新 Owner，只解析 entry phase的 `CurrentOwner(Phi)`；
`OpenedPackedNextBinderV1` 解析 parameter中已经存在的 sealed package component，也不
generative；只有 `GenerativeFreshBinderV1` 分配新 scope且必须携带 cardinality。
`DirectAndCallbackPrivateV1` 只允许 direct template及所名 callback引用，仍必须通过
所有 outward gates，绝不成为 public type binder。

每个 `ContextualCallbackRefV1` 或 `CallableCallbackRefV1(callback_name)` 必须与 `callbacks` 中恰好一个
同名 callback双向对应；该 callback的 `parameter_slot` 必须等于引用它的 slot，
且 `type` 必须等于该 parameter slot的 exact callable type。
反向地，每个 callback必须被恰好一个 callback-typed slot引用。`callbacks` 按
`parameter_slot` 数值严格递增。`ContextualCallbackRefV1`只允许 acquisition=`ContextualV1`；
`CallableCallbackRefV1`只允许 acquisition=`CallableValueV1`。普通 `TypeRefV1` slot不能秘密关联 callback。
`scheme.captured_fresh_slots` 与 `generated_fresh_slots` 各自严格递增、无重复且互不相交；两者的 union
必须恰好等于该 callback type/contract、`scheme.entry_owner` 及其 special evidence可达的全部 fresh ref。
`entry_owner` 引用同一 fresh binder时不另加一个 slot，只要求它已经出现在正确的 captured/generated array。
Generic refs由 direct-call
substitution closure捕获，不进入这两个 array。`captured` 只能引用 direct阶段已解析的
`DerivedCurrentOwnerBinderV1`、`OpenedPackedNextBinderV1` 或 enclosing trigger已生成的 binder；
`generated` 只能引用 `GenerativeFreshBinderV1`，按 fresh slot的依赖拓扑顺序实例化。Trigger与
cardinality的 exact对应为：`DirectInvocationV1 -> PerDirectCallV1`；
`PerInstalledSubscriptionV1 -> PerInstalledSubscriptionV1`；
`PerAdmittedGenerationV1 -> PerAdmittedGenerationV1`；`CallableInvocationV1` 与
`PerEventDispatchV1` 若有 generated项则只许 `PerCallbackInvocationV1`。不匹配、漏项、把同一 ref同时
captured/generated或让 generated origin forward-reference都稳定
`first-party-callback-scheme-mismatch`。Scheme在 rigid fresh tuple下普遍检查；它不是把第一次 runtime
generation的 ref封进一个 monomorphic closure。

`scheme.entry_owner` 不是 ambient hint，而是 callback entry phase的唯一 current-Owner source。八个
callback的 exact mapping固定为：`pack_next.builder -> rho_child`、
`try_with_packed_next.body -> rho_child`、`resource.switch_latest.load -> rho_child`、
`signal.map.transform -> NoCallbackEntryOwnerV1`、`signal.track.body -> rho`、
`ui.run_signal.body -> rho`、`ui.render.transform -> rho`、
`ui.candidate_action.body -> rho`。前七个 contextual callback必须使用对应
`ExactCallbackEntryOwnerV1`；唯一 callable callback `signal.map.transform` 必须使用
`NoCallbackEntryOwnerV1`。任何漏 owner、错 owner、把 contextual改成 NoOwner、把 callable改成 exact
owner、或在相同 kind的 foreign/cross-admission owner间替换，都稳定
`first-party-callback-entry-owner-mismatch`。

每个 exact mapping还必须有唯一 authority source，不能只因 type中出现同名 `rho` 就获得 lease：
pack builder与 Resource loader的 generated child由同一 binding的
`ChildOwnerV1(parent,rho_child)` 和该 trigger原子取得的 child-entry lease共同授权；open body由同一
package的 `PackedNextPackageLeaseV1` 与
`ExactPackagePrivateScopeV1(rho_child,i,L,body)`授权；track body的 derived current `rho`由
`CurrentOwnerV1(rho)+OwnerAuthorityV1(rho)`授权；UI runner body的 `rho`由 explicit `under` actual解出、
经 `OwnerAuthorityV1(rho)`验证后由 sealed runner entry lease重绑定；render transform的 `rho`必须同时等于
`UiBuilder` receiver的 exact root、retained storage owner与 callback entry owner；candidate action body的
`rho`必须同时等于 `UiCandidate` receiver、`ActionPlanContractV1.storage_owner`、retained storage owner与
callback entry owner。少任一 authority edge、把 lease从别的 owner/generation搬来或只继承 ambient
visitor owner都按同一 diagnostic拒绝。
`ResourceLoaderContractV1.callback` 必须解析到同 binding的 `load` callback；
其 exact row、Q、Λ、capture与 usage就是匹配到的 actual callback contract对应 fields，
不存在第二份可漂移的 loader contract。`SignalTailContractEvidenceV1` 同理解析到
`transform` callback；`ActionPlanContractV1` 同理解析到 `body` callback并把其完整
row/suspension/flow/summary/capture/Q/Λ与 exact owner/generation/revision/event substitution
作为一个不可拆分 contract保存在 ActionPlan中。其 zero-based `event_parameter_index` 必须恰为 1；callback参数 0
必须恰为 `SnapshotContext[storage_owner,revision]`，参数 1 必须恰为 `event_type`，且不能有额外参数。
`occurrence_policy` 必须恰为 `OwnerStoredExactQueuedOccurrenceV1`。同一
`ActionPlanContractWF` 还必须在 evidence array中找到恰好一次
`ShareableV1(event_type)` 与
`EventOccurrenceStorageV1(storage_owner,generation,event_type)`；后者逐完整 value summary证明该值
BoundarySafe、没有可逃逸的 affine/linear Owner或 capability authority、borrow、resumption、private static
scope或 user-finalizer责任，并可作为 immutable exact value保存在 `OwnerStorage(storage_owner)` 到该
generation的 occurrence终结。该保存责任的 release是 sealed、total、NoSuspend且 infallible；它不建立
CleanupLedger reservation。ContractWF据这两项 proof与 special contract的 exact五元组
`(callback,storage_owner,generation,revision,event_type)` 派生不可伪造的
`UiEventStorageWitness[event_type]` 并保存在 erased action entry中；该 sealed value内部仍精确绑定
`(storage_owner,generation,event_type)` 三元组，只有 `event_type` 保留为 runtime type index；不得从 host
tag、declaration slot或 ambient current generation重建。index/policy/proof/type/owner/generation任一错配稳定
`first-party-action-occurrence-contract-mismatch`。`ResourceLoaderContractWF` 与
`ActionPlanContractWF` 虽各自用 special contract保存 admission/event substitution，仍必须对同一 callback/
storage owner在 evidence array找到下述 exact三项 proof；special contract不暗含、替代或重复其中任一项。
`RetainedCallbackContractWF` 不是对 `capture_policy` literal的空检查：对同一 callback/storage owner，
evidence array必须恰有 `OwnerStorageProvenanceV1(cb,owner)`、`BoundarySafeCaptureV1(cb)` 与
`OutlivesV1(cb,owner)`，并逐 capture slot证明 provenance=`OwnerStorage(owner)`、BoundarySafe且该 slot
outlives storage lifetime；short-lived borrow/capability、foreign Owner或漏任一 proof都在安装前拒绝。
其 invocation scope必须与 callback scheme generated tuple exact相等：Track为唯一 eta，UI为依赖有序
gamma/nu。`RetainTrack`/`RetainUi` 与三项 proof重复、错序引用其它 callback或只把 policy string当证明都
`first-party-retained-callback-contract-mismatch`。

下列 source pretty-print有唯一展开：`@m::f` 是
`IntrinsicModuleFunctionV1{module:m,member:f}`，裸 `map_signal` 是
`UnqualifiedFunctionV1`，`T::f` 是 `AssociatedFunctionV1`，带
``surface projection `p` ``的 `T::f` 是 `AssociatedProjectionV1`，裸
`CoalesceLatest` 是 `ClosedLiteralV1{nominal:UiBackpressureV1,
variant:CoalesceLatest}`。Kernel pretty-print同样逐 tag展开为上列 union；唯一带
payload的两项是 exact `OperationCallV1`。`types=[x:K,...]` 按 list index生成
连续 `binder_slot`；`nu:UiRevisionScope[gamma]` 唯一生成依赖 gamma ref的
`UiRevisionScopeBinderV1`。`N`/`I` 中普通 type唯一包成 `TypeRefV1`。

下列 21个 entry各自必须 materialize为一个完整 `FirstPartyBindingV1` object；
行式 contract是 closed `FirstPartyContractTemplateV1` 的 *normative lossless notation*，
不是 `M3(FunctionContractV2)` 的残缺 projection，也不是自由 prose。wire decoder只接受
上列 tagged object；文档 notation先经下述总函数展开后才能进入 canonical bytes。
Producer先构造以 `id` 为 key的 exact 21-entry
map，验证 key与 object.id相等、exact ID set、source与 kernel逐 ID匹配，再按
ID的 NFC UTF-8 bytes排序后一次 materialize `bindings`。Decoder不替调用者重排：
非严格递增输入稳定拒绝。Canonical bytes是递归 NFC后的 RFC 8785/JCS UTF-8
bytes；semantic binding sort仍按 ID的 NFC UTF-8 bytes，不改 JCS object-member
UTF-16 ordering。

Table notation只有下列 constructors；它们逐字段展开成上列 tagged AST，不进入
canonical bytes；`Pure/Compute/Action/Commit` 分别唯一展开为同名 `*V1` phase tag：

```text
C(phase,row,suspension,world,flow,temporal) = {
  kind: FirstPartyContractTemplateV1,
  phase, row, suspension, world, flow, temporal,
  construction: {
    kind: CanonicalFirstPartyLiteralPathsV1,
    demand_policy: NormalizedRowAndKernelV1,
    obligation_policy: EvidenceArrayOrderV1,
    site_policy: AllReferencedDirectAndProjectedCallbackSitesV1,
    result_policy: TypeAndFlowDirectedV1,
    capture_policy: ActualArgumentsAndCallbacksV1,
    usage_policy: AuthoritySlotsExactV1,
    origin_policy: ElaborationOriginProjectionV1
  }
}

R0                 = EmptyRowV1
RAsync             = AnonymousAsyncRowV1
RG(x)              = GenericEffectRowV1(GenericBinderRefV1(slot(x)))
RCB(name)          = CallbackRowV1(BindingCallbackRefV1(name))
S0                 = NoSuspendV1
SAsync             = AsyncMaySuspendV1
SCB(name)          = CallbackSuspensionV1(BindingCallbackRefV1(name))
W0                 = SameWorldV1
WCB(name)          = CallbackWorldV1(BindingCallbackRefV1(name))
WPrivate(name,xs)  = ProjectPrivateWorldV1(BindingCallbackRefV1(name),refs(xs))
FRet(T)            = ReturnsOnlyV1(Ty(T))
FAwait(T)          = AwaitOrParkV1(Ty(T),ParkContractV2)
FCB(name)          = CallbackFlowV1(BindingCallbackRefV1(name))
FPack(name,X,Y)    = MapCallbackFlowV1(CBRef(name),PackNextReturnMapV1(Ty(X),Ty(Y)),
                                      [AbortsV2,TransfersV2])
FOpen(name,N,X,Y)  = MapCallbackFlowV1(CBRef(name),
                       AcquireOptionReturnMapV1(Ty(N),Ty(X),Ty(Y)),
                       [AbortsV2,TransfersV2])
TPure              = PureV1
THost              = HostObservableV1

VBoth(name)        = DirectAndCallbackPrivateV1(name)
VCallback(name)    = CallbackOnlyV1(name)
GChild(n,parent,card,vis) = GenerativeFreshBinderV1(
  n,OwnerRegionV1,card,vis,ChildOwnerRegionV1(ref(parent),DirectChildV1))
GFrame(n,owner,card,vis) = GenerativeFreshBinderV1(
  n,ClockIdentityV1,card,vis,FrameClockIdentityV1(ref(owner)))
GSummary(n,identity,payload,card,vis) = GenerativeFreshBinderV1(
  n,ClockPackageSummaryV1,card,vis,
  ClockPackageSummaryV1(ref(identity),Ty(payload)))
GTrack(n,vis) = GenerativeFreshBinderV1(
  n,TrackEpochScopeV1,PerInstalledSubscriptionV1,vis,InstalledTrackEpochV1)
GGeneration(n,owner,vis) = GenerativeFreshBinderV1(
  n,UiGenerationScopeV1,PerAdmittedGenerationV1,vis,
  AdmittedUiGenerationV1(ref(owner)))
GRevision(n,generation,vis) = GenerativeFreshBinderV1(
  n,UiRevisionScopeV1,PerAdmittedGenerationV1,vis,
  UiRevisionOfV1(ref(generation)))
CurrentOwner(n,vis) = DerivedCurrentOwnerBinderV1(
  n,OwnerRegionV1,CurrentOwnerOfEntryPhaseV1,vis)
Opened(n,kind,parameter,component,name) = OpenedPackedNextBinderV1(
  n,kind,parameter,component,DirectAndCallbackPrivateV1(name))
NoEntryOwner          = NoCallbackEntryOwnerV1
EntryOwner(owner)     = ExactCallbackEntryOwnerV1(B(owner))
Scheme(trigger,owner,captured,generated) = FirstPartyCallbackSchemeV1(
  trigger,owner,sorted-u32(captured),sorted-u32(generated))
E(rule,args...)      = ProofRuleEvidenceV1(rule,[args...])
B(name)              = ref(name)
P(n)                 = ParameterSlotRefV1(n)
CBRef(name)          = BindingCallbackRefV1(name)
ET(T)                = EvidenceTypeRefV1(Ty(T))
Loader(cb,rho,child,K,A,E) = ResourceLoaderContractV1(
  CBRef(cb),B(rho),B(child),Ty(K),Ty(A),Ty(E))
Tail(cb,i,A,B)       = SignalTailContractEvidenceV1(
  CBRef(cb),B(i),Ty(A),Ty(B))
ActionContract(cb,rho,gamma,nu,E) = ActionPlanContractV1(
  CBRef(cb),B(rho),B(gamma),B(nu),Ty(E),1,
  OwnerStoredExactQueuedOccurrenceV1)
RetainTrack(cb,rho,eta) = RetainedCallbackContractV1(
  CBRef(cb),B(rho),InstalledTrackInvocationV1(B(eta)),
  OwnerStorageBoundarySafeOutlivesV1)
RetainUi(cb,rho,gamma,nu) = RetainedCallbackContractV1(
  CBRef(cb),B(rho),UiAdmissionInvocationV1(B(gamma),B(nu)),
  OwnerStorageBoundarySafeOutlivesV1)
```

`types` 的 `x:K` 与 `fresh` 的 `x := Constructor(...)` 左侧 name都只是
notation-time symbol；它们必须唯一、按 list位置等于 object slot并在 tagged object生成后擦除。
`Ty` 是 closed type-template notation，不是 string field。它先把 `types`/`fresh` 左侧 name按
list index变成 numeric `GenericBinderRefV1`/`FreshBinderRefV1`，再严格按下列 constructor matrix
生成 bytes；表中的 module path/name是 `NominalTypeTemplateV1` 的 exact field，不由 importer猜测。
`O/I/L/H/G/U/R/F` 分别是 OwnerRegion/ClockIdentity/ClockPackageSummary/TrackEpochScope/
UiGenerationScope/UiRevisionScope/EffectRow/EffectFamily kind，`T` 是 ordinary Type kind：

```text
notation                  canonical module/name                    argument kinds   target after substitution
Owner[O]                  ["cire","owner"] / "Owner"              O                OwnerTypeV2(owner)
Cap[I,F]                  closed CapabilityTypeTemplateV1          I,F              CapabilityTypeV2(identity,effect-family)
Next[I,T,L]               ["cire","temporal"] / "Next"            I,T,L            SchemeOnly
PackedNext[O,T]           ["cire","temporal"] / "PackedNext"      O,T              PackedNextTypeV2(owner,payload)
Option[T]                 ["cire","core"] / "Option"              T                NominalTypeV2
Task[O,T]                 ["cire","async"] / "Task"               O,T              OwnerIndexedTypeV2(Task,owner,payload)
TaskOutcome[T,T]          ["cire","async"] / "TaskOutcome"        T,T              NominalTypeV2
CloseReceipt[T]           ["cire","async"] / "CloseReceipt"       T                NominalTypeV2
Live[O,T]                 ["cire","reactive"] / "Live"            O,T              OwnerIndexedTypeV2(Live,owner,payload)
Source[O,T]               ["cire","reactive"] / "Source"          O,T              OwnerIndexedTypeV2(Source,owner,payload)
Resource[O,T,T,T]         ["cire","resource"] / "Resource"        O,T,T,T          NominalTypeV2(OwnerTypeV2(owner),K,A,E)
ResourceView[T,T,T]       ["cire","resource"] / "ResourceView"    T,T,T            NominalTypeV2
Signal[I,T]               ["cire","signal"] / "Signal"            I,T              SignalTypeV2(clock,payload)
TrackContext[O,I,H]       ["cire","signal"] / "TrackContext"      O,I,H            SchemeOnly
SnapshotContext[O,R]      ["cire","ui"] / "SnapshotContext"       O,R              SchemeOnly
UiBuilder[O,I]            ["cire","ui"] / "UiBuilder"             O,I              SchemeOnly
UiCandidate[O,G,R]        ["cire","ui"] / "UiCandidate"           O,G,R            SchemeOnly
ActionPlan[G,T]           ["cire","ui"] / "ActionPlan"            G,T              SchemeOnly
ViewPlan[G]               ["cire","ui"] / "ViewPlan"              G                SchemeOnly
UiMount[O]                ["cire","ui"] / "UiMount"               O                NominalTypeV2(OwnerTypeV2(owner))
CancelResult              ["cire","async"] / "CancelResult"       -                NominalTypeV2
DisposeReport             ["cire","owner"] / "DisposeReport"      -                NominalTypeV2
UiBackpressureV1          ["cire","ui"] / "UiBackpressureV1"      -                NominalTypeV2
```

`FrameClock` *不在 ordinary type matrix*；它唯一生成
`NominalEffectFamilyTemplateV1{module:["cire","temporal"],name:"FrameClock",arguments:[]}`，kind=`F`，
substitution后作为 `CapabilityTypeV2.family` 的 exact
`LegacyTypeRefV2{value:NominalTypeV1{module:["cire","temporal"],name:"FrameClock",arguments:[]}}`，且该
legacy nominal必须由 Effect-family declaration catalog解析为 Effect。把它生成为 `NominalTypeV2`、当普通
Type argument或交给非 Effect declaration都 `first-party-type-template-kind-mismatch`。
`ParkContractV2` 也不在 type matrix：它只由 `AwaitOrParkV1.park="ParkContractV2"` 生成 closed park
contract/Transfers object，任何 `Ty(ParkContractV2)` 都拒绝。

`Unit` 唯一生成 `BuiltinTypeTemplateV1{name:"Unit"}`，substitution后生成 approved
`LegacyTypeRefV2{value:BuiltinTypeV1{name:"Unit"}}`；v1不新增 `BuiltinTypeV2`。
Parenthesized function type唯一生成
`FunctionTypeTemplateV1`；它是 callback matching pattern，不自行伪造必需的
`FunctionTypeV2.contract`，只能匹配 callable actual已有的 contract或进入下述 sealed callback scheme。
`NominalTypeV2(...)` 一栏按 matrix列出的参数顺序生成 exact target；Owner/Identity/Contract/static
scope ref从不被塞进普通 type argument。`CapabilityTypeTemplateV1` 与
`NominalEffectFamilyTemplateV1` 是独立 tagged constructors，不通过 `NominalTypeTemplateV1.arguments`
偷渡 Effect kind。

`SchemeOnly` 只存在于 normalized Kernel HIR的
`FirstPartyCallbackSchemeV1`：ContractWF在 rigid scope下检查后，backend擦除 wrapper/static index；它们以及
`FirstPartyBinderRefV1` 均不得进入 `M3(TypeRefV2)`、`FunctionContractV3`、
`CallableInterfaceV1` 或 outward value。因而 callback不是一个含未表示 eta/gamma/nu 的普通 local
`FunctionContractV3`。一个本来可 materialize的 constructor只要含非 M3 scoped ref，也按 SchemeOnly处理。
其唯一 M3 runtime carrier函数 `EraseSchemeTypeV1` 先递归 erasure ordinary payload，再按下表删除全部
Owner/Identity/Clock/Contract/epoch/generation/revision index：

```text
EType(name,args) = NominalTypeV2(
  module=["cire","kernel","firstparty"], name=name, arguments=args)

Owner[O]              -> EType("ErasedOwnerHandleV1",[])
Cap[I,F]              -> EType("ErasedCapabilityHandleV1",[])
Next[I,T,L]           -> EType("ErasedNextHandleV1",[Erase(T)])
PackedNext[O,T]       -> EType("ErasedPackedNextHandleV1",[Erase(T)])
Task[O,T]             -> EType("ErasedTaskHandleV1",[Erase(T)])
Live[O,T]             -> EType("ErasedLiveHandleV1",[Erase(T)])
Source[O,T]           -> EType("ErasedSourceHandleV1",[Erase(T)])
Resource[O,K,A,E]     -> EType("ErasedResourceHandleV1",[Erase(K),Erase(A),Erase(E)])
Signal[I,T]           -> EType("ErasedSignalHandleV1",[Erase(T)])
TrackContext[O,I,H]   -> EType("ErasedTrackContextV1",[])
SnapshotContext[O,R]  -> EType("ErasedSnapshotContextV1",[])
UiBuilder[O,I]        -> EType("ErasedUiBuilderV1",[])
UiCandidate[O,G,R]    -> EType("ErasedUiCandidateV1",[])
ActionPlan[G,T]       -> EType("ErasedActionPlanV1",[Erase(T)])
ViewPlan[G]           -> EType("ErasedViewPlanV1",[])
UiMount[O]            -> EType("ErasedUiMountHandleV1",[])
```

其它不含 static ref的 builtin/Option/TaskOutcome/CloseReceipt/ResourceView/CancelResult/DisposeReport/
UiBackpressure nominal按 ordinary M3 target递归使用 `Erase(T)`；`FunctionTypeTemplateV1`只作 callback
matching pattern，不能直接请求 erasure。上列 `cire.kernel.firstparty` carrier是 closed compiler-known
nominal set，没有 source constructor、import/export、member或 `CallableInterfaceV1`；只许出现在
`SchemeActualSummaryV1.erased_runtime_view.type` 与 `FirstPartySchemeContractWF` differential。把 carrier当 public
type、少/多 payload、保留 static ref、将两个 carrier name互换或对 ordinary M3 actual使用 carrier都稳定
`first-party-static-scope-escape`。因此
`erased_runtime_view.type == EraseSchemeTypeV1(scheme_type)` 是一个总函数，
不是实现自行选择的 representation。

Unknown module/name、arity、argument kind、forward ref、wrong target variant、
SchemeOnly outward use或 bare unary arrow都拒绝。Names在 tagged object生成后擦除，所以 table notation的
alpha-renaming不改变 canonical bytes。

`PackedNext[O,T]` 是 registry/typed-Core template spelling；surface仍只显示 sealed
`PackedNext[T]`。Hidden `O` 从 package value的 exact `PackedNextTypeV2.owner`解出，不能由 caller填写，
也不能在 public pretty-print、type argument list或 overload choice中出现；pack/open/dispose三项因此都能
round-trip同一 storage owner而不发明未编码参数。
`Resource[O,K,A,E]` 明确走新 profile的 four-argument nominal target；它不借旧
`ResourceTypeV2{owner,value,cleanup_result}` 丢掉 key/error，也无二者间 implicit coercion。Importer按
module/name与四个 argument exact匹配，旧 variant只属于旧 profile。

`ProofRuleEvidenceV1` 的 arguments不是 open list。下表是 exact signature matrix，
`B/P/C/T` 分别表示 binder/parameter-slot/callback/type argument；rule不在表、arity不同或
argument sort不同都拒绝：

```text
CurrentOwnerV1(B)                         OwnerAuthorityV1(B)
ChildOwnerV1(B,B)                         FrameClockNextSummaryCoherenceV1(B,B,B,T)
PrivateIdentityOutwardGateV1(B,B,B,C)     PackedNextPackageLeaseV1(P,C)
ExactPackedNextOverloadV1(P)              ExactCloseCellIdentityV1(P)
OutlivesV1(B|C,B)                         ShareableV1(T)
AsyncBoundarySafeV1(B,T)                  SuspensionStableV1(P)
OwnerBoundParkingV1(B)                    ExactOutcomeTaskV1(P,B,T,T)
DuplicableEnvironmentV1(C)                OwnerStorageProvenanceV1(C,B)
BoundarySafeCaptureV1(C)                  TemporalStableCaptureV1(C,B)
CrossWorldSafeCaptureV1(C,B)              ExactResourceRootV1(P,B)
ExactBuilderRootV1(P,B,B)                 CompleteDependencyTraceV1(C,B)
ContextualNonescapeV1(C)                  FixedSnapshotV1(B)
NoDependencyRegistrationV1(P)             ExactCoalesceLatestV1()
ExactGenerationRevisionBindingV1(C,B,B)   ActionSafeRowV1(B,B,B)
EventEntryDischargeOnlyV1(C)              EventOccurrenceStorageV1(B,B,T)
ExactMountRootV1(P,B)
ExactOwnerV1(B)                           InvalidatingDependencyV1(B,P)
ExactBackpressureArgumentV1(P)            ExactPackagePrivateScopeV1(B,B,B,C)
ExactTaskRegionGenerationV1(P,B)          ProjectionNonescapeV1(P)
CandidatePlanCaptureNonescapeV1(C,B,B)    PrivateFrameBuilderNonescapeV1(B,C)
```

调用点输入也是 closed compiler record，不能从 ambient visitor state补字段：

```text
FirstPartyInstantiationSiteV1 = {
  kind: "FirstPartyInstantiationSiteV1",
  kernel_node_preorder: u32,
  kernel_site_slot: u32,
  entry_world: M3(WorldExprV2),
  route: M3(RouteSelectorV1),
  call_origin: SourceOriginV2,
  sealed_intrinsic_origin: SourceOriginV2,
  caller_scope: FirstPartyCallerScopeV1
}

FirstPartyScopedValueRefV1 =
    { kind: "M3OwnerValueV1", owner: SlotRefV1 }
  | { kind: "M3IdentityClockValueV1",
      identity: SlotRefV1, clock: SlotRefV1 }
  | { kind: "M3ContractValueV1", contract: M3(ContractRefV2) }
  | { kind: "SchemeFreshValueV1",
      scheme_body_preorder: u32,
      fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1" | "TrackEpochScopeV1"
                 | "UiGenerationScopeV1" | "UiRevisionScopeV1" }
  | { kind: "OpenedPackedNextComponentValueV1",
      packed_parameter_slot: u32,
      packed_source: M3(SlotRefV2),
      component: "OwnerRegionV1" | "ClockIdentityV1"
               | "ClockPackageSummaryV1" }

FirstPartyCallerScopeV1 = {
  declaration_binders: M3(DeclarationBindersV2),
  entry_phase: M3(PhaseRequirementV1),
  current_owner: FirstPartyScopedValueRefV1 | null,
  frame_builder_witnesses: [FirstPartyFrameBuilderWitnessV1]
}

FirstPartyFrameBuilderWitnessV1 = {
  kind: "FirstPartyFrameBuilderWitnessV1",
  frame_source: M3(SlotRefV2),
  identity_clock: FirstPartyScopedValueRefV1,
  owner: FirstPartyScopedValueRefV1,
  builder_origin: SourceOriginV2
}

FirstPartyCallbackSourceV1 =
    { kind: "ContextualCallbackSourceV1", parameter_slot: u32,
      normalized_hir_node_preorder: u32, capture_slots: [M3(SlotRefV2)] }
  | { kind: "CallableCallbackSourceV1", parameter_slot: u32,
      actual_slot: u32 }

FirstPartyErasedRuntimeValueViewV1 = {
  kind: "FirstPartyErasedRuntimeValueViewV1",
  source: M3(SlotRefV2) | null,
  type: M3(TypeRefV2),
  origin: SourceOriginV2
}

FirstPartyActualSummaryV1 =
    { kind: "M3ActualSummaryV1", value: M3(ValueSummaryExprV2) }
  | { kind: "SchemeActualSummaryV1",
      typed_kernel_value_preorder: u32,
      erased_runtime_view: FirstPartyErasedRuntimeValueViewV1,
      scheme_body_preorder: u32,
      scheme_type: FirstPartyTypeTemplateV1,
      kernel_scope_refs: [FirstPartyScopedValueRefV1] }

FirstPartyInstantiationOutputV1 =
    { kind: "M3FirstPartyInstantiationV1",
      computation: M3(ContractComputationV2),
      callback_schemes: [FirstPartyInstantiatedCallbackSchemeV1],
      site_allocations: [FirstPartySiteAllocationV1],
      projection_items: [FirstPartyProjectionItemV1] }
  | { kind: "SchemeFirstPartyInstantiationV1",
      typed_kernel_computation_preorder: u32,
      callback_schemes: [FirstPartyInstantiatedCallbackSchemeV1],
      site_allocations: [FirstPartySiteAllocationV1],
      projection_items: [FirstPartyProjectionItemV1] }

FirstPartySolvedValueV1 =
    { kind: "SolvedTypeV1", value: M3(TypeRefV2) }
  | { kind: "SolvedOwnerV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedIdentityClockV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedContractV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedRowV1", value: M3(RowExprV1) }
  | { kind: "SolvedStaticScopeV1", value: FirstPartyScopedValueRefV1 }

FirstPartySolvedBindingV1 = {
  generic_slot: u32,
  value: FirstPartySolvedValueV1
}

FirstPartyCapturedFreshV1 = {
  fresh_slot: u32,
  value: FirstPartySolvedValueV1
}

FirstPartyInstantiatedCallbackSchemeV1 = {
  kind: "FirstPartyInstantiatedCallbackSchemeV1",
  binding_id: BindingIdV1,
  callback_name: CallbackNameV1,
  trigger: "DirectInvocationV1" | "CallableInvocationV1"
         | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1"
         | "PerEventDispatchV1",
  entry_owner: FirstPartyScopedValueRefV1 | null,
  solved_generics: [FirstPartySolvedBindingV1],
  captured_fresh: [FirstPartyCapturedFreshV1],
  rigid_fresh: [FirstPartyFreshBinderV1],
  frame_builder_witnesses: [FirstPartyFrameBuilderWitnessV1],
  erased_kernel_body_preorder: u32,
  type_template: FirstPartyTypeTemplateV1,
  contract_template: FirstPartyContractTemplateV1,
  evidence_indices: [u32]
}

FirstPartySiteKeyV1 = {
  kernel_node_preorder: u32,
  source_kind: "DirectFirstPartyCallV1" | "CallbackLexicalSiteV1",
  callback_parameter_slot: u32,
  source_local_site_slot: u32
}

FirstPartySiteAllocationV1 = {
  kind: "FirstPartySiteAllocationV1",
  key: FirstPartySiteKeyV1,
  provisional_site_slot: u32,
  final_site_slot: u32
}

FirstPartyProjectionKeyV1 = {
  kernel_node_preorder: u32,
  item_namespace: "ObligationOccurrenceV1" | "LatentSiteOccurrenceV1",
  source_kind: "DirectEvidenceV1" | "KernelSiteV1" | "CallbackProjectionV1",
  path_ordinal: u32,
  source_major: u32,
  source_minor: u32
}

FirstPartyProjectedObligationValueV1 =
    { kind: "M3ProjectedObligationValueV1",
      value: M3(ObligationV2) }
  | { kind: "SchemeObligationTemplateValueV1",
      typed_kernel_occurrence_preorder: u32,
      scoped_refs: [FirstPartyScopedValueRefV1],
      final_obligation_id: u32,
      site_key: FirstPartySiteKeyV1 | null }

FirstPartyProjectedLatentSiteValueV1 =
    { kind: "M3ProjectedLatentSiteValueV1",
      value: M3(LatentSiteV2) }
  | { kind: "SchemeLatentSiteTemplateValueV1",
      typed_kernel_occurrence_preorder: u32,
      scoped_refs: [FirstPartyScopedValueRefV1],
      site_key: FirstPartySiteKeyV1,
      final_site_slot: u32 }

FirstPartyProjectionItemV1 =
    { kind: "ProjectedObligationV1", key: FirstPartyProjectionKeyV1,
      value: FirstPartyProjectedObligationValueV1 }
  | { kind: "ProjectedLatentSiteV1", key: FirstPartyProjectionKeyV1,
      value: FirstPartyProjectedLatentSiteValueV1 }
```

`ProjectedObligationV1.key.item_namespace` 必须为 `ObligationOccurrenceV1`，
`ProjectedLatentSiteV1` 必须为 `LatentSiteOccurrenceV1`；互换不是另一种 ordering，而是 exact decode
`first-party-projection-namespace-mismatch`。

`sealed_intrinsic_origin` 不是 caller任填 string：它必须等于 #ref(<surface-a-12>) 中以 call Direct node为 anchor、
`DerivedKindV1=SealedIntrinsicV1`、唯一 `PrincipalV1` parent生成的 Derived node投影；
`call_origin` 必须等于同一个 anchor的 `SourceOriginV2`（该 profile中仍是 `SourceOriginV1` alias）。
`kernel_node_preorder` 是 #ref(<surface-a-12>) normalized Kernel HIR preorder；`kernel_site_slot` 是 binding-local provisional
slot且 v1唯一合法值为0。first-party invocation的最终 Q/Λ若至少一个 field引用该 direct site，就必须
消费它并生成恰好一个 `DirectFirstPartyCallV1` site allocation；若全部 Q静态 discharge且没有 Λ，则必须
生成零 direct allocation且不消耗 final slot。`OperationCallV1` 因必有 Λ总会生成 allocation，并在该 site另外生成
`LatentSiteV2`，不是 site存在的条件。随后必须由第7步 root-wide rebase同时重写所有引用它的
Q/Λ field。它不是 caller选择的 final slot。Preorder、local zero、route、entry world与 caller
binders都由 caller ContractWF重算相等。Registry lowering直接 splice一个 `LiteralPathsV2/PathBindV2` computation；它*不*
伪造无 target artifact的 `AppliedContractV2` 或 `InvokeV2`，所以 `FunctionContractV3.applications` delta
为 `[]`。Lexical `site_slot` 与 static contract `application_slot` 是独立 namespace；分配前者不创造后者。
普通 callback body里的真实 calls仍保留各自 applications。
`FirstPartyScopedValueRefV1` 是 internal arena ref而非 Core wire。`SolvedOwnerV1`只许
`M3OwnerValueV1`、Owner-kind `SchemeFreshValueV1`或 Owner component；
`SolvedIdentityClockV1`只许 exact M3 pair、ClockIdentity-kind scheme fresh或 opened clock component；
`SolvedContractV1`只许 M3 Contract、ClockPackageSummary-kind scheme fresh或 opened summary；
`SolvedStaticScopeV1`只许相应 Track/Generation/Revision-kind scheme fresh。每个
`SchemeFreshValueV1` 必须在同一 normalized typed-Kernel arena中解析到 active或所名 enclosing callback
scheme的 `captured_fresh` *或* `rigid_fresh` 中恰好一个 exact `fresh_slot`，并由 registry fresh
declaration重算相同 `binder_kind`。解析到 captured项时继续解析它的 `FirstPartySolvedValueV1`，但不得形成
cycle；解析到 rigid项时必须是该 scheme本次 trigger将分配的 declaration。零个、两个表同时命中、引用
inactive/unreachable scheme、slot/kind不等或 capture cycle都 `first-party-callback-scheme-mismatch`；
`OpenedPackedNextComponentValueV1` 必须把 parameter、source与 sealed package component三者重算相等。
因此 opened `rho_child/i/L` 与 enclosing UiRunSignal `i` 都不伪装成普通 M3 slot。

`FirstPartyInstantiatedCallbackSchemeV1.entry_owner` 由 registry scheme owner作总替换：
`NoCallbackEntryOwnerV1 -> null`；`ExactCallbackEntryOwnerV1(B(x))` 则从
`solved_generics/captured_fresh/rigid_fresh` 中取得 x的唯一 `FirstPartyScopedValueRefV1`。它可以是
`M3OwnerValueV1`、Owner-kind `SchemeFreshValueV1` 或 opened Owner component，不能是其它 kind。
为 `M3OwnerValueV1` 时 precompiled entry phase与它必须是同一 Owner slot；为后两种 non-M3 ref时，scheme的
M3 erasure中 `entry_phase.current_owner` 必须为 null，不能伪造 Legacy slot。每次 trigger先按 rigid tuple作
capture-avoiding substitution，再用上文该 binding的 exact authority source原子取得该 owner的 entry lease，
把 callback active `entry_phase.current_owner` 设置为刚 materialize的 concrete Owner，且 nested
`FirstPartyCallerScopeV1.current_owner` 只能 exact复制该 active owner；Returns/Aborts/Transfers任一路离开都
恢复先前 entry phase。`signal.map.transform` 的 null owner不取得 lease也不重绑定其 ordinary callable
scope。任何 ambient继承、最近 owner启发式或跨 owner lease都拒绝。

Frame witness的 owner/identity_clock分别按上述 kind规则解析，`frame_source`只允许 Legacy source slot；
表按 resolved `(scheme-body-preorder,fresh-slot-or-M3-slot,owner-key,frame-source namespace,slot)`严格递增、
无重复。`UiRunSignalV1` 是唯一 producer：构造其 `body` scheme时，
`PrivateFrameBuilderNonescapeV1(i,body)` 必须生成恰好一个 witness，source为 body parameter 0的 canonical
provenance root，identity_clock为该 scheme的 `SchemeFreshValueV1(body_preorder,0,ClockIdentityV1)`，owner为
已解 `rho`，origin为同 call的 sealed derived origin；该 witness写入
`FirstPartyInstantiatedCallbackSchemeV1.frame_builder_witnesses`。其它七个 callback scheme该 array必须为空。
进入 nested call时 caller scope只可 exact复制 active scheme中 source仍可达的 witness；identity-preserving
alias通过 canonical provenance root解析，不能另造 witness。由此 `Signal::track` 的 unique-witness check有
closed producer，不读取 ambient visitor state。
`solved_generics` 必须按 generic slot严格递增并 exact覆盖 binding.types；`captured_fresh` 与
`rigid_fresh` 分别按 scheme两张 slot array严格递增且 exact相等，不能另带 binder。`evidence_indices`
严格递增并恰好列出引用该 callback的 proof/special evidence array index；body preorder必须指向同一
callback source的 normalized Kernel HIR root。每个仍被 Q/Λ引用的 direct call恰有一个 site allocation；callback graph中
每个被 Q/Λ引用的 lexical site也恰有一个 `CallbackLexicalSiteV1` allocation，key中的 callback slot与
source-local site必须解析到同一 callback typed graph。`site_allocations` 按 key严格递增，root builder把它与
其它 normalized-HIR site key合并后从0分配一个共享 lexical-site namespace，回填 `final_site_slot`。合并键统一为
`(kernel_node_preorder,site-source-kind-order,source-major,source-minor)`，kind顺序固定
`OrdinaryKernelSiteV1,DirectFirstPartyCallV1,CallbackLexicalSiteV1`；direct的 major/minor=`0/0`，callback的
major/minor=`parameter_slot/source_local_site_slot`。`FirstPartySiteAllocationV1.provisional_site_slot` 必须等于
direct的0或 callback source-local slot，不能由 map order重写。
`projection_items` 则按
`(kernel_node_preorder,item-namespace-order,source-kind-order,path_ordinal,source_major,source_minor)`严格递增；
namespace顺序固定 `ObligationOccurrenceV1,LatentSiteOccurrenceV1`。Obligation ID只在前一 namespace中过滤后
从0分配；每个 obligation/latent-site的 `site_slot` 都通过 `site_allocations` map重写，不从 projection key
猜 rank。这样 callback local obligation 0与 latent site 0可同时存在而不碰 key，也不会分配两个 lexical site。
这些 internal records与 schemes都不进入 Core wire/JCS。
`M3FirstPartyInstantiationV1` 的每个 projection value只许相应
`M3ProjectedObligationValueV1/M3ProjectedLatentSiteValueV1`；其中 `value` 必须与 M3 computation的对应
occurrence byte-for-byte相等。`SchemeFirstPartyInstantiationV1` 的每项一律用相应 scheme-template variant，
即使某一 occurrence的 `scoped_refs=[]` 也不能混入 M3 variant。其
`typed_kernel_occurrence_preorder` 必须指向同一 typed-Kernel computation中的 exact obligation/latent-site
node；`scoped_refs` 按
`(ref-kind-order,scheme-body-preorder-or-parameter-slot,fresh-slot-or-component-order)`严格递增、去重，并
exact等于该 occurrence全部 fields可达的 non-M3 scoped refs。Obligation template的
`final_obligation_id` 必须等于 root allocator给该 key的 ID，`site_key` 为 null当且仅当 occurrence不引用
lexical site，否则必须 exact指向唯一 allocation；latent template的 `site_key/final_site_slot` 必须与唯一
allocation相等。Trigger substitution把对应 typed node一次 materialize为 M3 value，保留同一 final ID/site，
不得 reallocate、retype或从 erased carrier反推。Projection item只是 allocator proof，不是第二份 contract
authority；preorder/ref/key/ID/site或 materialized byte differential不等都是 producer invariant failure。
`erased_kernel_body_preorder` 指向同一 normalized typed-Kernel arena中已经拥有完整
computation/Q/Λ/capture/usage的 callback root；scheme对该 graph做 fresh substitution。`type_template`/
`contract_template` 只是已匹配的 registry pattern，不能替代或复制 inferred contract；body ref错 root、
未 typed或 pattern与 graph observer不等都拒绝。
`M3ActualSummaryV1` 的 type必须是 matrix中可 materialize target；`SchemeActualSummaryV1` 只许在
当前 caller callback scheme内使用，`scheme_body_preorder` 必须等于该 active scheme root；
`typed_kernel_value_preorder` 必须指向该 root内完整、已 type-checked的 normalized typed-Kernel
`ValueSummary` node。这个 node是 type/source/nominal-index/provenance/capture/usage/origin的唯一 authority；
ContractWF、capture/usage、evidence和所有 semantic equality都读取它，绝不读取或补写一个伪 M3 summary。
`scheme_type` 必须与该 node的 exact type observer相等，并含 SchemeOnly constructor或 non-M3 scoped ref。
`erased_runtime_view` 只供 backend representation：source必须等于 typed node的 runtime source projection，
origin byte-for-byte相等，type必须等于 `EraseSchemeTypeV1(scheme_type)`；它没有 nominal-index、provenance、
capture或usage字段，因而不能覆盖这些 typed facts。Trigger时以 scheme tables与 concrete rigid tuple对完整
typed node作 capture-avoiding substitution，随后一次 materialize完整 M3 `ValueSummaryExprV2`；这一步从
typed node复制全部 observers，只把 static refs替成已授权 concrete M3 values，并验证 runtime-view
differential，绝不从 `erased_runtime_view` 重建语义。

`kernel_scope_refs` 只列完整 typed node可达、解析后属于所名 `scheme_body_preorder` 的 distinct
`SchemeFreshValueV1`；它按 `(scheme_body_preorder,fresh_slot,binder-kind-order)`严格递增，先遍历 active
scheme的 `solved_generics/captured_fresh/rigid_fresh` 再重算 exact closure。M3 refs与
`OpenedPackedNextComponentValueV1` 明确排除，且不得因 registry fresh slot本身存在就加入未被 node引用的
项。Canonical controls固定为：`Signal::track.body` 的 `TrackContext` actual只列
`[eta@fresh_slot=1]`，不列已解 current Owner `rho@slot=0`；`try_with_packed_next.body` 的 opened actual列
`[]`；`UiRunSignal.body` 的 frame actual列 `[i@fresh_slot=0]`。漏/多/错序、把 M3/current-owner/opened
component列入、或错 scheme preorder/kind都 `first-party-static-scope-escape`。

Output tag不只查看 direct result。Producer递归扫描实例化后的 result/type/computation/Q/Λ/evidence/
capture/usage/origins全 graph：全部 refs都可物化为 M3时唯一选择 `M3FirstPartyInstantiationV1`；任一 field
仍含 SchemeOnly constructor或 non-M3 scoped ref时唯一选择 `SchemeFirstPartyInstantiationV1`，把完整 graph
和 scheme-template projection嵌在同一 callback arena。只改变 Q、Λ、evidence、capture、usage或 origin中
任一深层 ref也必须改变选择；不允许“result可 M3所以整个 output可 M3”。Scheme output进入 root/public
FunctionContract、跨 scheme返回/存储、混入 M3 projection value或两种 output tag互换都
`first-party-static-scope-escape`。

`instantiate_first_party(binding, actuals:[FirstPartyActualSummaryV1], callback_sources:[FirstPartyCallbackSourceV1], site)` 是唯一 template→typed-Core总函数，
按下列阶段运行；`actuals` 必须与 slots一一对应，callback source按
`parameter_slot`严格递增且与 callback slots exact相等：

+ *非 callback constraints。* 先匹配 receiver/ordinary input actual，只建立 kinded equality graph；
   不读期待 result。Type/Owner/Identity/Clock/row分别只与同 kind term unify；ClockIdentity同时要求 caller
   已有 exact Identity/Clock pair。Callable callback的 existing `FunctionTypeV2.contract`在本阶段加入 graph，
   contextual body不先被强行物化。若 binding是 `Signal::track`，slot 0先解出 `i`，再要求
   `frame_builder_witnesses` 中恰好一个 entry同时满足 `frame_source == summary_source(actuals[0])`、
   `identity_clock == i`、`owner == current_owner`（均按 scoped-ref semantic equality比较）；该 owner唯一解出
   `rho`。零个、多个、foreign identity或
   non-current owner都稳定 `signal-track-builder-root-mismatch`。
+ *Direct scope。* `DerivedCurrentOwnerBinderV1` 只解析上一步已验证的 current Owner；
   `OpenedPackedNextBinderV1` 从同一个 exact `PackedNextTypeV2` actual一次取 owner/clock/summary component；
   component/package identity不等即拒绝。其三项 `captured_fresh.value` 必须分别是指向同 parameter/source的
   `OpenedPackedNextComponentValueV1(OwnerRegion/ClockIdentity/ClockPackageSummary)`；current Owner使用
   `M3OwnerValueV1`，从 enclosing scheme捕获的 binder使用 fully-qualified `SchemeFreshValueV1`。用普通
   SlotRef/ContractRef冒充 opened/scheme component拒绝。只实例化 scheme的 captured项及
   `PerDirectCallV1` binder；origin依赖尚含 unsolved Type（例如 pack-next的 `L(A)`）者保留为 rigid
   deferred equation，不猜 A。
+ *Callback skeleton与唯一求解。* 对 contextual callback建立带 kind的 parameter skeleton；
   `DirectInvocationV1` 的 generated slots复用第2步同一 direct tuple；其它 trigger的
   `scheme.generated_fresh_slots` 依 fresh-slot拓扑成为不在 direct scope实例化的 rigid skolems。Callback body在该 skeleton下做一次
   bidirectional type/row/flow/ContractWF，允许从 parameter uses、inferred Returns type与 inferred row解
   callback-only `A/B/E/epsilon_action`，仍禁止从 direct expected result猜解。Callable actual则用其已有
   type/contract加入同一 constraints。随后解全部 graph；每个 generic必须有一个完整 substitution，零解/
   多解、occurs check、kind mismatch或 deferred origin不相等都
   `first-party-registry-contract-nonunique`。因此 pack-next先由 body解 A再验证 `L(A)`，open解 B，
   Resource解 A/E，track解 A，candidate.action解 E/row；不是在 callback之前假称它们已经存在。
+ *Sealed generative scheme。* Contextual callback不生成含 eta/gamma/nu的 ordinary local
   `FunctionContractV3`。Producer生成 `FirstPartyInstantiatedCallbackSchemeV1`，保存完整 solved generic
   substitution、captured refs、rigid fresh declarations、closed frame-witness table、erased typed Kernel body、
   contract template、entry owner及 evidence。`entry_owner` 按上文 exact mapping从同一三张 substitution
   table求解；它必须同时出现在 callback body entry phase和每个 nested caller scope的 current-Owner
   observer中。Scheme在任意 fresh tuple下已通过 ContractWF；每次对应 runtime trigger才原子分配 concrete
   sealed evidence并按 fresh slot替换 type/computation/evidence/Q/Λ/capture/usage的所有 ref：Resource
   admission `{rho_child}`，track installation `{eta}`，UI admission按依赖序 `{gamma,nu=UiRevisionOf(gamma)}`。
   同一原子 trigger随后从 binding-specific authority取得 entry lease、重绑定 active current Owner，且在
   callback任何 terminal path后恢复；NoOwner callable不执行这一步。两次 admission的每个 generative
   component必须 non-alias；stale/foreign/cross-admission substitution在
   callback启动前 `first-party-callback-scheme-mismatch`。这一步是 precompiled universal scheme的
   instantiation，不在 runtime重新 type-check user source。
+ *Contract paths。* `C` normalise row/world/suspension/flow。`R0/S0/W0` 分别唯一生成 Empty、
   `SuspensionV1{grade:NoSuspend,atoms:[]}`、SameWorld；`RAsync/SAsync` 使用
   `site.kernel_site_slot/site.route/site.entry_world`生成 exact Async demand/request/park tuple。
   `TPure` 产生 Pure；`THost` 产生唯一 sealed certificate：HostObservable、replay Fresh、fork Forbid、
   publish Immediate、suspend按 template取 StackOnly或OwnerBound、trust
   `Sealed{module:["cire","intrinsic"]}`，全部新 origin用 `site.sealed_intrinsic_origin`。
   `FRet`一个 Returns；`FAwait`按 Returns、Transfers canonical tag顺序；`FCB` alpha-copy immediate
   callback paths；`FPack/FOpen`只 map Returns并原样保留每个 Abort/Transfer，FOpen lost path为 ordinal 0。
+ *Q 的 total mapping。* 每个 evidence element先按 array index验证。下列六种是唯一可能 emit
   `ObligationV2` 的 mapping；`ids(xs)`/`captures(cb)`均按 resolved source slot严格递增，emission index
   就是该顺序：

   ```text
   DuplicableEnvironmentV1(cb)       -> DuplicableEnvV2(captures(cb),kernel_site_slot)
   BoundarySafeCaptureV1(cb)         -> BoundarySafeV2(captures(cb),OwnerStorage)
   TemporalStableCaptureV1(cb,i)     -> StableAcrossV2(captures(cb),i,[entry,callback-world])
   CrossWorldSafeCaptureV1(cb,i)     -> BoundarySafeV2(captures(cb),TemporalLock)
   OutlivesV1(cb,owner)              -> one OutlivesV2(capture-slot,LegacySlotRefV2(owner)) per capture slot
   OwnerBoundParkingV1(owner)        -> OwnerParkingV2(owner,kernel_site_slot)
   ```

   每项 stage=`Call`、origin=`site.sealed_intrinsic_origin`；若 exact caller facts静态 discharge则删除，否则
   保留。`OutlivesV1(B,B)` 与 signature matrix中其余全部 rule/special evidence都是 mandatory static
   predicate：逐项成功且 emit零 Q，失败即相应 evidence diagnostic，绝不 silent drop或映成别的 variant。
   M3 owner/identity ref按上表直接 materialize；scheme-fresh ref只保存在
   `SchemeObligationTemplateValueV1` 指向的 typed-Kernel obligation occurrence，`scoped_refs`必须是该 node
   exact closure；对应 trigger实例化为 concrete M3 slot后才以已经分配的 final obligation ID/site
   materialize `ObligationV2`，不能伪造 Legacy slot、重分配 ID或把 template混进 M3 output。
   Path `required_phase` 直接由 template phase生成 exact `PhaseRequirementV1`，不伪造 Phase Q。
+ *site、Λ 与 rebasing。* 若第6步保留任何引用 direct site的 Q，或本步生成 direct Λ，先为本 invocation生成
   唯一 `FirstPartySiteAllocationV1(key={node,DirectFirstPartyCallV1,0,0},provisional=0)`；两者都没有时必须
   省略 allocation，避免无 occurrence的 final-slot gap。只有 `OperationCallV1` 新建一个 `LatentSiteV2`：site slot引用该 allocation，route/origin取
   `site`；receiver是 exact anonymous Async family；operation取 kernel enum；actual_arguments取对应
   `M3ActualSummaryV1.value`（OperationCall binding含 SchemeActual即拒绝）；signature是 Async registry在
   solved substitution下的 exact `OperationSignatureV2`；suffix取
   本 path contract；secondary sites=`Closed([])`；call obligation IDs恰为第6步仍保留且引用本 site的 IDs，
   install IDs为空。其它 kernel tag不凭名字制造 LatentSite。Immediate callback-derived path复制 actual
   callback已有 Q/Λ并保持内部 ID linkage，并把其 typed graph中所有被 Q/Λ引用的 lexical-site table entry
   投影成 `CallbackLexicalSiteV1` allocation；retained callback的 Q/Λ保存在第4步 scheme或
   `ResourceLoaderContractV1/ActionPlanContractV1` 中，*不*伪装成 direct-call `LatentSiteV2`。

   每个待投影 item先带 key
   `(kernel_node_preorder,item_namespace,source_kind,path_ordinal,source_major,source_minor)`；namespace order固定为
   `ObligationOccurrenceV1,LatentSiteOccurrenceV1`，`source_kind` enum order固定为
   `DirectEvidenceV1, KernelSiteV1, CallbackProjectionV1`，major/minor分别是 evidence-index/emission-index、
   `0/0`、callback-parameter-slot/source-local-id。Root builder与其它 normalized-HIR items一起按
   上文 `FirstPartySiteAllocationV1` 的 root-wide key ordering先分配 shared lexical-site slot；再按完整
   projection key unsigned numeric
   lexicographic sort，只从 Obligation namespace过滤后连续分配 obligation ID。Latent occurrence不另分配
   site slot，而必须引用对应 direct/callback site allocation；同时重写 `call_obligation_ids/install_obligation_ids`。
   duplicate key、dangling source-local obligation/site、一个 latent occurrence无/多于一个 allocation、或
   rebase后 ID/site不连续都稳定 ContractWF拒绝；visitor/map/object order不参与。
+ *Result/capture/usage与 output。* Callback-derived result做 exact substitution；其它 Shareable/sealed
   scalar为 Stable+NoCapture；含 live Owner/Identity/Clock index者逐 index生成 canonical provenance/capture。
   Usage只含 type/Kernel确定的 affine authority slot，Zero省略。新生成的 path/outcome/demand/summary/Q/Λ/
   transformer origin一律是 `site.sealed_intrinsic_origin`；投影 callback item保留自己的 source origin。
   M3 output的完整 `LiteralPathsV2/PathBindV2` 与 projection evidence送入现有 Decode/ContractWF；
   Scheme output的 typed-Kernel computation与 schemes送入同字段的 `FirstPartySchemeContractWF`，并在
   每次 concrete trigger substitution及 wrapper erasure后，逐 observer与 materialized M3 projection做
   differential：result/type/computation/Q/Λ/evidence/capture/usage/origin、obligation ID与site slot必须全部
   byte-for-byte相等；`erased_runtime_view` 只参与 backend source/type/origin representation comparison。
   任何 field不能唯一生成即 nonunique diagnostic。

因此 registry canonical bytes只含 closed templates；outward实例化输出是完整 M3
`ContractComputationV2`（row/demand/outcome/world/suspension/full Summary、Q/Λ、capture/usage/result
transformer/origin）并 splice进 caller `FunctionContractV3`；含 SchemeOnly type的内部实例化只进入 enclosing
callback scheme的 typed-Kernel arena，绝不进该 wire。两者都可携带不出 wire的 sealed callback schemes，
不与 registry artifact混同，也没有未声明的 `RegistryOrigin`/field ordinal或所谓 D4 allocator。

所有下列 parameter都 nondefaultable；`N` 可 positional或用该 public label传入，不引入 named-only
passing variant。`ContextualCallback` 只是在 registry slot里引用同 entry下方 exact callback contract的
closed marker，不是用户可构造 type。`fresh` 是 sealed Kernel contextual binder table，绝不开放 source
existential/rank-2 syntax。函数 spelling仍只用 `() -> R`、`(A) -> B`、`(A, B) -> C`。
`N/I` 中普通 `T` 自动包成 `TypePatternV1.TypeRefV1`；`ContextualCallback` 自动包成
`ContextualCallbackRefV1{callback_name=<同 entry callback name>}`，name必须在该 entry的 callbacks中
恰好解析一次。其它 stringly-typed type或 callback reference拒绝。
每个 direct/callback contract都逐项给出 phase、row、suspension、world、full flow与 temporal summary；
省略 field不代表实现可选。`{}` 是 empty row，`same` 是 same-world。Registry按
`id` 的 NFC UTF-8 bytes严格递增且 ID唯一；source spelling只有下列显式列出的两组 nominally-disjoint
read overload pairs可以重复，其余唯一。shadowed同 spelling value始终
走 ordinary call，不得取得 `kernel`。全部 type/callback/evidence pattern进入同一
CallableInterface/ContractWF gate。
重复检查基于完整 tagged `FirstPartySourceV1` canonical key；exact exceptions只有
`AssociatedFunctionV1(TrackContext,read)` 的 Live/Source pair与
`AssociatedFunctionV1(SnapshotContext,read)` 的 Live/Source pair，不能只比较 `member` string。

下列 blocks是 exact objects的 lossless normative table notation：`id/source/slots/types/fresh/direct/evidence/kernel`
逐列对应同名 field；`builder/body/load/transform` 行给 callback的 `name/type`，紧随的 `callback` 行给其
`contract`，`scheme` 行给其 `FirstPartyCallbackSchemeV1`，三行共同生成一个
`FirstPartyCallbackV1`。有 callback却缺任一行稳定拒绝；没有这些行的 entry显式生成
`callbacks=[]`，不能省略
field；一个 entry至多使用列出的 callback rows，不允许其它隐式 column。文中的 `stable_binding_id` 就是
object field `id`，`kernel_lowering` 就是 field `kernel`。
callback linkage的 exact全集只有：pack-next `slot 1 -> builder`、try-with-packed-next
`slot 1 -> body`、resource.switch-latest `slot 2 -> load`、signal.map `slot 1 -> transform`、
signal.track `slot 1 -> body`、ui.run-signal `slot 2 -> body`、ui.render
`slot 2 -> transform`、ui.candidate-action `slot 1 -> body`；其它13个 binding的
`callbacks=[]`。这张全集也参与 exact ID-by-ID producer validation，不能从名字启发式推断。
其中只有 signal.map 的 `transform` 是 `CallableValueV1`；其它七个都是 `ContextualV1`。

UI contextual nominal types固定为：

```text
UiBackpressureV1 = CoalesceLatest
TrackContext[rho,i,eta]
UiBuilder[rho,i]
UiCandidate[rho,gamma,nu]
SnapshotContext[rho,nu]
ActionPlan[gamma,E]
ViewPlan[gamma]
UiMount[rho]
```

`eta : TrackEpochScope`、`gamma : UiGenerationScope`、
`nu : UiRevisionScope[gamma]` 是不进入 source syntax的 fresh static scope witness；runtime
`RuntimeNat`/`FixedEpochRevision` 不进入 type equality。每个 `nu` 只携带 sealed evidence指向一个 admitted
runtime pair。`TrackContext`/`UiBuilder`/`UiCandidate`/`SnapshotContext` 都不可存储、返回或跨 contextual
callback逃逸。`ViewPlan[gamma]` 是 sealed immutable adapter value；adapter widget constructor是普通、
scheme-local function，必须在同一个 callback scheme的 pre-erasure Kernel HIR中以
Compute/empty-row/NoSuspend/same/Returns-only contract产生同 `gamma` 的 plan，并可消费同 gamma的
`ActionPlan`。它不能导出、导入或取得 `CallableInterfaceV1`（static gamma在该 wire中无 variant）；可复用的
public helper只能生产普通 Shareable adapter data，由 scheme-local constructor组装 plan。Constructor没有
独立 privileged Kernel tag、不属于本 registry；它随 `UiRenderV1` scheme整体检查/擦除，不能引入第二套 UI
language semantics。

Action callback唯一允许的 latent row predicate是：

```text
ActionSafeRow(rho,gamma,epsilon) iff
  epsilon is a normalized row containing only attributed Named(i,F) demands,
  every selected operation has required phase Action, NoSuspend, world same,
  full flow exactly Returns(Unit); no Anonymous entry,
  await, Abort, Transfer, raw Resume or generic spawn is admitted.
```

`ActionSafeRowV1` 的 exact arguments只有 `rho/gamma/epsilon`，因此它*不*检查 callback capture。
`candidate.action.body` 的 capture lifetime只由同 callback/ref的
`OwnerStorageProvenanceV1 + BoundarySafeCaptureV1 + OutlivesV1` 三项与
`ActionPlanContractWF`逐 slot检查；generation gate/occurrence lease只负责 enqueue/invocation/retire ordering，不能替代
从 plan创建到 event dispatch的静态 outlives proof。event参数也不是 capture：它必须另由同一 entry末尾的
`ShareableV1(E) + EventOccurrenceStorageV1(rho,gamma,E)` 证明并由
`ActionPlanContractWF`铸成 exact storage witness；三项 callback-capture proof不能替它。

Closed entries如下；`RCB/SCB/WCB/FCB(name)` 总是解析同一个已 type-checked callback
contract的 exact observer，不是自由 metavariable或实现选择，direct template必须按写出的
mapping逐 path保留：

```text
id       = "Cire-v1.0/intrinsic/temporal.pack-next"
source   = @temporal::pack_next
slots    = [N(0,"under",Owner[rho]), N(1,"builder",ContextualCallback("builder"))]
types    = [rho:OwnerRegion,A:Type]
fresh    = [rho_child := GChild(0,rho,PerDirectCallV1,VBoth("builder")),
            i := GFrame(1,rho_child,PerDirectCallV1,VBoth("builder")),
            L := GSummary(2,i,A,PerDirectCallV1,VBoth("builder"))]
builder  = (Cap[i,FrameClock]) -> Next[i,A,L]
callback = C(Action,RCB("builder"),SCB("builder"),WCB("builder"),
             FCB("builder"),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho_child),[],[0,1,2])
direct   = C(Action,RCB("builder"),SCB("builder"),
             WPrivate("builder",[rho_child,i,L]),
             FPack("builder",Next[i,A,L],PackedNext[rho,A]),THost)
evidence = [E(CurrentOwnerV1,B(rho)), E(OwnerAuthorityV1,B(rho)),
            E(ChildOwnerV1,B(rho),B(rho_child)),
            E(FrameClockNextSummaryCoherenceV1,B(rho_child),B(i),B(L),ET(A)),
            E(PrivateIdentityOutwardGateV1,B(rho_child),B(i),B(L),CBRef("builder"))]
kernel   = PackedNextPackV1

id       = "Cire-v1.0/intrinsic/temporal.try-with-packed-next"
source   = @temporal::try_with_packed_next
slots    = [N(0,"packed",PackedNext[rho,A]), N(1,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion,A:Type,B:Type]
fresh    = [rho_child := Opened(0,OwnerRegionV1,0,OwnerRegionV1,"body"),
            i := Opened(1,ClockIdentityV1,0,ClockIdentityV1,"body"),
            L := Opened(2,ClockPackageSummaryV1,0,ClockPackageSummaryV1,"body")]
body     = (Cap[i,FrameClock], Next[i,A,L]) -> B
callback = C(Action,RCB("body"),SCB("body"),WCB("body"),FCB("body"),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho_child),[0,1,2],[])
direct   = C(Action,RCB("body"),SCB("body"),
             WPrivate("body",[rho_child,i,L]),
             FOpen("body",Option[B],B,Option[B]),THost)
evidence = [E(PackedNextPackageLeaseV1,P(0),CBRef("body")),
            E(ExactPackagePrivateScopeV1,B(rho_child),B(i),B(L),CBRef("body")),
            E(PrivateIdentityOutwardGateV1,B(rho_child),B(i),B(L),CBRef("body"))]
kernel   = PackedNextOpenV1

id       = "Cire-v1.0/intrinsic/temporal.packed-next-dispose"
source   = @temporal::dispose
slots    = [N(0,"packed",PackedNext[rho,A])]
types    = [rho:OwnerRegion,A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactPackedNextOverloadV1,P(0)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = PackedNextDisposeV1

id       = "Cire-v1.0/intrinsic/async.await-task"
source   = Async::await
slots    = [N(0,"task",Task[rho_task,R])]
types    = [rho_task:OwnerRegion,R:Type]
fresh    = [rho_observer := CurrentOwner(0,DirectOnlyV1)]
direct   = C(Action,RAsync,SAsync,W0,FAwait(R),THost)
evidence = [E(OwnerAuthorityV1,B(rho_observer)),
            E(OutlivesV1,B(rho_observer),B(rho_task)),
            E(AsyncBoundarySafeV1,B(rho_observer),ET(R)),
            E(SuspensionStableV1,P(0)), E(OwnerBoundParkingV1,B(rho_observer)),
            E(ExactTaskRegionGenerationV1,P(0),B(rho_task)),
            E(ShareableV1,ET(R))]
kernel   = OperationCallV1(family="AsyncV1",operation="awaitV1")

id       = "Cire-v1.0/intrinsic/async.await-receipt"
source   = CloseReceipt::await
slots    = [N(0,"receipt",CloseReceipt[R])]
types    = [R:Type]
fresh    = [rho_observer := CurrentOwner(0,DirectOnlyV1)]
direct   = C(Action,RAsync,SAsync,W0,FAwait(R),THost)
evidence = [E(OwnerAuthorityV1,B(rho_observer)), E(ShareableV1,ET(R)),
            E(AsyncBoundarySafeV1,B(rho_observer),ET(R)),
            E(SuspensionStableV1,P(0)), E(OwnerBoundParkingV1,B(rho_observer))]
kernel   = OperationCallV1(family="AsyncV1",operation="await_receiptV1")

id       = "Cire-v1.0/intrinsic/task.cancel-outcome"
source   = Task::cancel
slots    = [N(0,"task",Task[rho,TaskOutcome[A,E]]), N(1,"under",Owner[rho])]
types    = [rho:OwnerRegion,A:Type,E:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CancelResult),THost)
evidence = [E(OwnerAuthorityV1,B(rho)),
            E(ExactOutcomeTaskV1,P(0),B(rho),ET(A),ET(E))]
kernel   = TaskCancelV1

id       = "Cire-v1.0/intrinsic/resource.switch-latest"
source   = Resource::switch_latest
slots    = [N(0,"under",Owner[rho]), N(1,"keys",Live[rho,K]),
            N(2,"load",ContextualCallback("load"))]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = [rho_child := GChild(0,rho,PerAdmittedGenerationV1,VCallback("load"))]
load     = (Owner[rho_child], K) -> Task[rho_child,TaskOutcome[A,E]]
callback = C(Action,RCB("load"),S0,W0,
             FRet(Task[rho_child,TaskOutcome[A,E]]),THost)
scheme   = Scheme(PerAdmittedGenerationV1,EntryOwner(rho_child),[],[0])
direct   = C(Action,R0,S0,W0,FRet(Resource[rho,K,A,E]),THost)
evidence = [E(ShareableV1,ET(K)), E(ShareableV1,ET(A)), E(ShareableV1,ET(E)),
            E(ChildOwnerV1,B(rho),B(rho_child)),
            E(DuplicableEnvironmentV1,CBRef("load")),
            E(OwnerStorageProvenanceV1,CBRef("load"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("load")),
            E(OutlivesV1,CBRef("load"),B(rho)),
            Loader("load",rho,rho_child,K,A,E)]
kernel   = ResourceSwitchLatestV1

id       = "Cire-v1.0/intrinsic/resource.view"
source   = Resource::view
slots    = [N(0,"resource",Resource[rho,K,A,E])]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = []
direct   = C(Pure,R0,S0,W0,FRet(Live[rho,ResourceView[K,A,E]]),TPure)
evidence = [E(ShareableV1,ET(ResourceView[K,A,E]))]
kernel   = ResourceViewV1

id       = "Cire-v1.0/intrinsic/resource.dispose"
source   = Resource::dispose
slots    = [N(0,"resource",Resource[rho,K,A,E])]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactResourceRootV1,P(0),B(rho)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = ResourceDisposeV1

id       = "Cire-v1.0/intrinsic/signal.map"
source   = map_signal
slots    = [N(0,"input",Signal[i,A]),
            N(1,"transform",CallableCallback("transform"))]
types    = [i:ClockIdentity,A:Type,B:Type]
fresh    = []
transform = (A) -> B
callback = C(Pure,R0,S0,W0,FRet(B),TPure)
scheme   = Scheme(CallableInvocationV1,NoEntryOwner,[],[])
direct   = C(Pure,R0,S0,W0,FRet(Signal[i,B]),TPure)
evidence = [E(ShareableV1,ET(A)), E(ShareableV1,ET(B)),
            E(DuplicableEnvironmentV1,CBRef("transform")),
            E(TemporalStableCaptureV1,CBRef("transform"),B(i)),
            E(CrossWorldSafeCaptureV1,CBRef("transform"),B(i)),
            Tail("transform",i,A,B)]
kernel   = SignalMapV1

id       = "Cire-v1.0/intrinsic/signal.track"
source   = Signal::track
slots    = [N(0,"frame",Cap[i,FrameClock]), N(1,"body",ContextualCallback("body"))]
types    = [i:ClockIdentity,A:Type]
fresh    = [rho := CurrentOwner(0,VBoth("body")),
            eta := GTrack(1,VCallback("body"))]
body     = (TrackContext[rho,i,eta]) -> A
callback = C(Compute,R0,S0,W0,FRet(A),THost)
scheme   = Scheme(PerInstalledSubscriptionV1,EntryOwner(rho),[0],[1])
direct   = C(Action,R0,S0,W0,FRet(Signal[i,A]),THost)
evidence = [E(CurrentOwnerV1,B(rho)), E(OwnerAuthorityV1,B(rho)),
            E(ExactBuilderRootV1,P(0),B(rho),B(i)), E(ShareableV1,ET(A)),
            E(DuplicableEnvironmentV1,CBRef("body")),
            E(CompleteDependencyTraceV1,CBRef("body"),B(eta)),
            E(ContextualNonescapeV1,CBRef("body")),
            E(OwnerStorageProvenanceV1,CBRef("body"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("body")),
            E(OutlivesV1,CBRef("body"),B(rho)), RetainTrack("body",rho,eta)]
kernel   = SignalTrackV1

id       = "Cire-v1.0/intrinsic/track.read-live"
source   = TrackContext::read
slots    = [I(0,TrackContext[rho,i,eta]), N(1,"input",Live[rho,A])]
types    = [rho:OwnerRegion,i:ClockIdentity,eta:TrackEpochScope,A:Type]
fresh    = []
direct   = C(Compute,R0,S0,W0,FRet(A),THost)
evidence = [E(InvalidatingDependencyV1,B(eta),P(1)), E(ExactOwnerV1,B(rho))]
kernel   = TrackReadLiveV1

id       = "Cire-v1.0/intrinsic/track.read-source"
source   = TrackContext::read
slots    = [I(0,TrackContext[rho,i,eta]), N(1,"input",Source[rho,A])]
types    = [rho:OwnerRegion,i:ClockIdentity,eta:TrackEpochScope,A:Type]
fresh    = []
direct   = C(Compute,R0,S0,W0,FRet(A),THost)
evidence = [E(InvalidatingDependencyV1,B(eta),P(1)), E(ExactOwnerV1,B(rho))]
kernel   = TrackReadSourceV1

id       = "Cire-v1.0/intrinsic/snapshot.read-live"
source   = SnapshotContext::read
slots    = [I(0,SnapshotContext[rho,nu]), N(1,"input",Live[rho,A])]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,nu:UiRevisionScope[gamma],A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(A),TPure)
evidence = [E(FixedSnapshotV1,B(nu)), E(NoDependencyRegistrationV1,P(1))]
kernel   = SnapshotReadLiveV1

id       = "Cire-v1.0/intrinsic/snapshot.read-source"
source   = SnapshotContext::read
slots    = [I(0,SnapshotContext[rho,nu]), N(1,"input",Source[rho,A])]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,nu:UiRevisionScope[gamma],A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(A),TPure)
evidence = [E(FixedSnapshotV1,B(nu)), E(NoDependencyRegistrationV1,P(1))]
kernel   = SnapshotReadSourceV1

id       = "Cire-v1.0/intrinsic/ui.coalesce-latest"
source   = CoalesceLatest
slots    = []
types    = []
fresh    = []
direct   = C(Pure,R0,S0,W0,FRet(UiBackpressureV1),TPure)
evidence = [E(ExactCoalesceLatestV1)]
kernel   = UiBackpressureCoalesceLatestV1

id       = "Cire-v1.0/intrinsic/ui.run-signal"
source   = @ui::run_signal
slots    = [N(0,"under",Owner[rho]), N(1,"backpressure",UiBackpressureV1),
            N(2,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion]
fresh    = [i := GFrame(0,rho,PerDirectCallV1,VBoth("body"))]
body     = (Cap[i,FrameClock], UiBuilder[rho,i]) -> Unit
callback = C(Action,R0,S0,W0,FRet(Unit),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho),[],[0])
direct   = C(Action,R0,S0,W0,FRet(UiMount[rho]),THost)
evidence = [E(OwnerAuthorityV1,B(rho)), E(ExactBackpressureArgumentV1,P(1)),
            E(ContextualNonescapeV1,CBRef("body")),
            E(PrivateFrameBuilderNonescapeV1,B(i),CBRef("body"))]
kernel   = UiRunSignalV1

id       = "Cire-v1.0/intrinsic/ui.builder-owner"
source   = UiBuilder::owner (surface projection `owner`)
slots    = [I(0,UiBuilder[rho,i])]
types    = [rho:OwnerRegion,i:ClockIdentity]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(Owner[rho]),TPure)
evidence = [E(ExactBuilderRootV1,P(0),B(rho),B(i)), E(ProjectionNonescapeV1,P(0))]
kernel   = UiBuilderOwnerV1

id       = "Cire-v1.0/intrinsic/ui.render"
source   = UiBuilder::render
slots    = [I(0,UiBuilder[rho,i]), N(1,"model",Signal[i,A]),
            N(2,"transform",ContextualCallback("transform"))]
types    = [rho:OwnerRegion,i:ClockIdentity,A:Type]
fresh    = [gamma := GGeneration(0,rho,VBoth("transform")),
            nu := GRevision(1,gamma,VBoth("transform"))]
transform = (UiCandidate[rho,gamma,nu], A) -> ViewPlan[gamma]
callback = C(Compute,R0,S0,W0,FRet(ViewPlan[gamma]),TPure)
scheme   = Scheme(PerAdmittedGenerationV1,EntryOwner(rho),[],[0,1])
direct   = C(Action,R0,S0,W0,FRet(Unit),THost)
evidence = [E(DuplicableEnvironmentV1,CBRef("transform")),
            E(ExactBuilderRootV1,P(0),B(rho),B(i)),
            E(ExactGenerationRevisionBindingV1,CBRef("transform"),B(gamma),B(nu)),
            E(OwnerStorageProvenanceV1,CBRef("transform"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("transform")),
            E(OutlivesV1,CBRef("transform"),B(rho)),
            E(CandidatePlanCaptureNonescapeV1,CBRef("transform"),B(gamma),B(nu)),
            RetainUi("transform",rho,gamma,nu)]
kernel   = UiRenderV1

id       = "Cire-v1.0/intrinsic/ui.candidate-action"
source   = UiCandidate::action
slots    = [I(0,UiCandidate[rho,gamma,nu]), N(1,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,
            nu:UiRevisionScope[gamma],E:Type,epsilon_action:EffectRow]
fresh    = []
body     = (SnapshotContext[rho,nu], E) -> Unit
callback = C(Action,RG(epsilon_action),S0,W0,FRet(Unit),THost)
scheme   = Scheme(PerEventDispatchV1,EntryOwner(rho),[],[])
direct   = C(Compute,R0,S0,W0,FRet(ActionPlan[gamma,E]),TPure)
evidence = [E(ActionSafeRowV1,B(rho),B(gamma),B(epsilon_action)),
            E(DuplicableEnvironmentV1,CBRef("body")),
            E(OwnerStorageProvenanceV1,CBRef("body"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("body")),
            E(OutlivesV1,CBRef("body"),B(rho)),
            ActionContract("body",rho,gamma,nu,E),
            E(EventEntryDischargeOnlyV1,CBRef("body")),
            E(ShareableV1,ET(E)),
            E(EventOccurrenceStorageV1,B(rho),B(gamma),ET(E))]
kernel   = UiCandidateActionV1

id       = "Cire-v1.0/intrinsic/ui.mount-dispose"
source   = UiMount::dispose
slots    = [N(0,"mount",UiMount[rho])]
types    = [rho:OwnerRegion]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactMountRootV1,P(0),B(rho)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = UiMountDisposeV1
```

上述 block是 map-entry presentation，不是 encoded array order；producer必须恰好输出下列
NFC UTF-8 ID order，decoder只接受这个顺序：

```text
Cire-v1.0/intrinsic/async.await-receipt
Cire-v1.0/intrinsic/async.await-task
Cire-v1.0/intrinsic/resource.dispose
Cire-v1.0/intrinsic/resource.switch-latest
Cire-v1.0/intrinsic/resource.view
Cire-v1.0/intrinsic/signal.map
Cire-v1.0/intrinsic/signal.track
Cire-v1.0/intrinsic/snapshot.read-live
Cire-v1.0/intrinsic/snapshot.read-source
Cire-v1.0/intrinsic/task.cancel-outcome
Cire-v1.0/intrinsic/temporal.pack-next
Cire-v1.0/intrinsic/temporal.packed-next-dispose
Cire-v1.0/intrinsic/temporal.try-with-packed-next
Cire-v1.0/intrinsic/track.read-live
Cire-v1.0/intrinsic/track.read-source
Cire-v1.0/intrinsic/ui.builder-owner
Cire-v1.0/intrinsic/ui.candidate-action
Cire-v1.0/intrinsic/ui.coalesce-latest
Cire-v1.0/intrinsic/ui.mount-dispose
Cire-v1.0/intrinsic/ui.render
Cire-v1.0/intrinsic/ui.run-signal
```

同 source spelling的 `TrackContext::read` / `SnapshotContext::read` 两对候选只按 nominal input type解析到
上列不同 stable ID，不存在 `Live|Source` implicit coercion或运行时 tag猜测。`UiDeclare` 不是 effect family、
row entry或 user value，v1不定义这个名字；ViewPlan/ActionPlan构造与 runner bookkeeping由上述 ordinary
adapter interfaces和 privileged evidence分层承担，绝不产生 `Anonymous(UiDeclare)` 或
`Named(_,UiDeclare)`。

Conformance必须包含完整21-entry canonical object与 canonical-byte golden；把 producer
输入 block顺序完全反转仍生成相同 bytes，而把 encoded `bindings` 中任意相邻 pair交换则稳定
`first-party-registry-noncanonical-order`。每个 binding分别做 id/source/slot/type/fresh/direct/
callback type/contract/scheme/evidence/kernel的 single-field mutation。至少还要独立覆盖：unknown object/union tag；
missing/extra field；duplicate/gapped/wrong-kind generic或fresh binder；pack-next删除 rho binder；
dangling binder reference；direct删除 temporal；pack-next、try-with-packed-next或
resource loader callback删除 temporal；orphan contextual/callable slot；orphan callback；duplicate callback
name；callback `parameter_slot`或 `acquisition`错连；scheme trigger/captured/generated漏项、重复、交叠、
wrong cardinality或 forward dependency；callback type与 direct parameter不等；signal.map退回普通
TypeRef transform但保留 callback；`ResourceLoaderContractV1`缺失、错 callback、错 storage/generation
owner或 K/A/E；`ActionPlanContractV1`缺失或错 owner/generation/revision/event；unknown evidence rule/argument；kernel tag与 ID不匹配；duplicate/missing/extra ID；
`ActionPlanContractV1.event_parameter_index`缺失/非 1、`occurrence_policy`缺失/错误；
NFC别名 ID；非 canonical callback顺序；非 canonical bindings顺序。所有这些必须在进入
CallableInterface/Kernel lowering前稳定 exact Decode/ContractWF拒绝。
另覆盖 type matrix每个 constructor的 wrong module/name/arity/argument kind/target M3 variant，
`Unit` exact Legacy wrapper positive与 `BuiltinTypeV2` reject，FrameClock exact Effect-family legacy nominal
positive及 ordinary `NominalTypeV2`/wrong declaration-kind rejects，并证明 `Ty(ParkContractV2)`不存在；
每个 `EraseSchemeTypeV1` carrier逐行有 positive，wrong carrier/payload/static-ref/public escape/ordinary-M3误用
逐项 reject；
function template伪造 contract、SchemeOnly进入 outward M3、unknown type/row/suspension/world/flow/construction tag、wrong evidence arity/sort、
callback actual contract与 template不匹配、opened-package component被误标 generative、
pack shared-private binder被误标单侧 visibility、flow path重排/drop/join、以及 static scope进入
outward M3 type；instantiation site wrong call/sealed origin、route/world/site/preorder、Q rule mapping、
operation LatentSite field、referenced direct site的 missing/duplicate allocation、无 Q/Λ call伪造 unused allocation、
non-operation retained Q仍为 provisional site 0、
callback obligation/local-site dangling mapping、Q-local-0与Λ-local-0同路径 collision control、wrong item namespace、
callback ID/site rebase/permutation/dangling link都须 reject；golden必须逐字段含完整
computation/Q/Λ/capture/usage/origin且证明 `applications` 无伪造 intrinsic entry。
`Signal::track.body` 与 `UiBuilder::render.transform` 另各有 missing/wrong storage owner、
short-lived borrow/capability capture、wrong eta或 stale/foreign gamma/nu invocation-scope
mutation；缺少 `RetainedCallbackContractV1` 或配套三项 lifetime proof也必须在安装前拒绝。另用同一
compiled call-site做两次 Resource admission、两次 track installation与两次 UI admission：分别证明
`rho_child₀ != rho_child₁`、`eta₀ != eta₁`、`gamma₀ != gamma₁`、每个 `nu_j=UiRevisionOf(gamma_j)`且
`nu₀ != nu₁`；把任一 first tuple ref替到 second的 type/computation/evidence/Q/Λ/capture/usage任一深度都稳定
`first-party-callback-scheme-mismatch`。Signal::track另覆盖 body不读 track仍由 unique builder witness解 rho、
missing/duplicate/foreign builder witness、UiRunSignal scheme漏/伪造 witness、ordinary M3 ref冒充 scheme fresh
identity、wrong scheme preorder/fresh slot/kind拒绝，以及 callback-only A/row constraint的零解/多解拒绝。
try-with-packed-next另逐项证明 captured opened owner/identity/summary用 exact package-component ref，换 source/
component或伪造普通 M3 slot拒绝。`candidate.action.body` 单独删除/换 owner的 Outlives proof或只保留
ActionSafeRow时必须在 plan创建前拒绝 short-lived capture；另逐项删除、复制或替换其末尾
`ShareableV1(E)` / `EventOccurrenceStorageV1(rho,gamma,E)`，把 storage owner换成 foreign rho、generation换成
stale/foreign gamma、callback参数 1换成 `E2`、action entry保存的 event witness/action plan/revision任一错配，
以及以 non-Shareable、non-BoundarySafe、含 affine Owner/capability、borrow/resumption或 private static scope的
event type实例化，都必须在 plan创建或 listener prepare前稳定拒绝。两项新增 mandatory static evidence
追加在原 evidence array尾部，既有 Q-producing evidence index不重编号；21-entry canonical object/bytes golden
仍因新 fields/evidence而必须更新。`async.await-task` 也在原 evidence array尾部追加 exact
`ShareableV1(R)`；删除、复制、换成另一 type或 non-Shareable R actual都在 `instantiate_first_party` 前拒绝，
existing OwnerParking Q evidence index保持不变。

Entry-owner conformance对七个 contextual mapping逐一做 exact positive，并逐行至少覆盖：删除
`entry_owner` field、改为 `NoCallbackEntryOwnerV1`、换成同 kind foreign owner、跨 admission复用旧 owner/lease，
以及让 nested `FirstPartyCallerScope.current_owner` 不等于 active entry owner；signal.map则做 null/no-rebind
positive和伪造 exact owner reject。pack/resource各删除 `ChildOwnerV1`，open分别删除 package lease/private
scope，track删除 CurrentOwner或OwnerAuthority，run删除 under-owner authority，render换 UiBuilder root或 storage
owner，candidate换 receiver/ActionPlan storage owner，都必须在 callback启动前稳定
`first-party-callback-entry-owner-mismatch`，并证明 Abort/Transfer path也恢复先前 entry phase。

`SchemeActualSummaryV1` 至少有三条 complete-root golden：track body的 `kernel_scope_refs=[eta@1]`、
try-open body的 `[]`、UiRun frame的 `[i@0]`。逐项 mutation typed-kernel preorder、scheme root/type、runtime
source/type/origin、ref sort/duplicate/missing/extra，以及把 current-owner M3 ref或 opened component塞进 array；
还要只改 typed node的 nominal-index/provenance/capture/usage任一 observer，证明 ContractWF读取完整 typed
authority而不是 erased view。Concrete trigger materialization必须逐 observer与 full M3 ValueSummary相等；从
erased carrier反推、保留 static ref或对 typed facts静默补默认都拒绝。

Projection/output conformance分别给纯 M3与 scheme-template Q/Λ complete root：验证 typed occurrence preorder、
sorted scoped-ref closure、final obligation ID、nullable/exact site key与 final site slot。将两种 value variant
互换、混在同一 output、错 preorder/ref/key/ID/site、trigger后 reallocate/retype或 materialized bytes不等均
拒绝。另从一个 M3-compatible result开始，分别只在 computation、Q、Λ、evidence、capture、usage与 origin
深层加入一个 non-M3 ref，七条 mutation都必须选择 `SchemeFirstPartyInstantiationV1`；删掉最后一个 non-M3
ref则必须回到 M3 output，证明选择不是 result-only heuristic。
