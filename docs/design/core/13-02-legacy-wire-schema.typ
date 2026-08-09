#import "../shared.typ": *

```text
FunctionContractV1 {
  artifact: "FunctionContractV1"
  profile: "Cire-TR₀/2026-07-31"
  schema_version: 1
  row: RowExprV1
  transition: TransitionV1
  flow_summary: FlowSetV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  capture_slots: [CaptureSlotV1]
  usage: [UsageV1]
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  ParametricObligations: [ObligationV1]
  LatentSites: [LatentSiteV1]
  binders: DeclarationBindersV1
}

FunctionContractV2 {
  artifact: "FunctionContractV2"
  profile: "Cire-TR₀/2026-08-01"
  schema_version: 2
  declaration_kind: FunctionContractKindV2 | null
  binders: DeclarationBindersV2
  applications: [AppliedContractV2]
  computation: ContractComputationV2
  closure_environment: [EnvironmentBindingV2]
}

AppliedContractV2 {
  application_slot: u32
  contract: ContractRefV2
  callee_summary: ValueSummaryExprV2
  actual_arguments: [ValueSummaryExprV2]
  substitution: ContractSubstitutionV2
  entry_world: WorldExprV2
  origin: SourceOriginV2
}

AppliedProjectionEvidenceV2 {
  application_slot: u32
  source_artifact_hash: StringV1
  discharged_call_keys: [QualifiedLocalKeyV2]
  retained_obligations: [RetainedObligationV2]
  retained_latent_sites: [RetainedLatentSiteV2]
}
QualifiedLocalKeyV2 { application_slot: u32, local_id: u32 }
RetainedObligationV2 {
  key: QualifiedLocalKeyV2
  source_local_id: u32
  stage: HandlerInstall
}
RetainedLatentSiteV2 {
  key: QualifiedLocalKeyV2
  source_site_slot: u32
  install_obligation_keys: [QualifiedLocalKeyV2]
}

ContractRefV2 =
    ContractParameterRefV2 { parameter: ContractParameterV2 }
  | ImportedFunctionRefV2 {
      module: ModulePathV1,
      name: IdentifierV1,
      artifact_hash: StringV1
    }
  | LocalFunctionRefV2 { declaration_slot: u32 }

ContractSubstitutionV2 {
  type_arguments: [TypeSubstitutionV2]
  row_arguments: [RowSubstitutionV2]
  contract_arguments: [ContractSubstitutionEntryV2]
  owner_arguments: [OwnerSubstitutionV2]
  identity_arguments: [IdentitySubstitutionV2]
  clock_arguments: [ClockSubstitutionV2]
}

TypeSubstitutionV2 { binder_slot: u32, value: TypeRefV2 }
RowSubstitutionV2 { binder_slot: u32, value: RowExprV1 }
ContractSubstitutionEntryV2 { binder_slot: u32, contract: ContractRefV2 }
OwnerSubstitutionV2 { binder_slot: u32, value: SlotRefV1 }
IdentitySubstitutionV2 { binder_slot: u32, value: SlotRefV1 }
ClockSubstitutionV2 { binder_slot: u32, value: SlotRefV1 }

`type_arguments` 覆盖 `TypeBinderV1` 的 Type与Effect两个 value-carrying domain，
但 importer必须先由 target binder map取 declared kind，再按 position解码 `value`：
Type binder只接受 TypeRefV2，Effect binder只接受 `EffectFamilyRefV2` 的 V2
encoding；若 nominal Effect在 `TypeSubstitutionV2.value`中以
`LegacyTypeRefV2(NominalTypeV1)` 承载，只在 Effect-family position取其内层
`NominalTypeV1`，Type position则保留 wrapper。两个 domain不得按相同
object shape互换。替换后 importer必须对完整 instantiated
`FunctionContractKindV2`（包括 `visible_row`）重跑 exact/kind/row WF，不能只比较
parameter/result。每个 `IdentitySubstitutionV2.binder_slot` 先在 target identity
binder table解析，其 family在同一 type substitution下实例化；`value` 必须引用 caller
live Identity declaration且 family结构相等，否则稳定
`contract-component-kind-mismatch`。完整 instantiated `visible_row`随后还必须用 caller
identity/handler-contract table重跑 selector scope/family WF。OwnerRegion binder不由
`type_arguments` 实例化。Substitution domain exactness之后仍须检查 caller lexical
scope；unbound projection稳定拒绝，wrong-kind value稳定
`contract-component-kind-mismatch`。

ValueSummaryExprV2 {
  source: SlotRefV2 | null
  type: TypeRefV2
  nominal_index: NominalIndexExprV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2 | null
  origin: SourceOriginV2
}

SlotRefV2 =
    LegacySlotRefV2 { value: SlotRefV1 }
  | ReturnSlotRefV2 { return_slot: u32 }

WorldExprV2 =
    LegacyWorldExprV2 { value: WorldExprV1 }
  | ReturnWorldV2 { return_slot: u32 }
  | ApplicationEntryWorldV2 { application_slot: u32 }
  | ApplyWorldTransitionV2 {
      input: WorldExprV2,
      transition: TransitionV1
    }
  | JoinWorldsV2 { members: [WorldExprV2] }

ContractComputationV2 =
    LiteralPathsV2 { paths: nonempty [PathContractV2] }
  | CurrentDispositionPathsV2 { paths: nonempty [PathContractV2] }
  | InvokeV2 { application_slot: u32 }
  | PathBindV2 {
      prefix: ContractComputationV2,
      return_binder: ReturnBinderV2,
      continuation: ContractComputationV2,
      terminal_policy: PreserveTerminalV2
    }
  | JoinV2 { members: nonempty [ContractComputationV2] }

ReturnBinderV2 {
  slot: u32
  type: TypeRefV2
  world: WorldExprV2
  nominal_index: NominalIndexExprV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2 | null
}

PathContractV2 {
  outcome: PathOutcomeV2
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  usage: [UsageExprV2]
  required_phase: PhaseRequirementV1
  ParametricObligations: [ObligationV2]
  LatentSites: [LatentSiteV2]
}

PathOutcomeV2 =
    ReturnsV2 {
      transition: TransitionV1,
      result_transformer: ResultTransformerV2
    }
  | AbortsV2 { origin: SourceOriginV1 }
  | TransfersV2 { park_contract: ParkContractV2 }
  | DelegatesV2 {
      forward_contract: ForwardContractV2,
      disposition_evidence: ForwardDispositionEvidenceV2
    } // HandlerContractV2 clause computations only

DeclarationBindersV1 {
  parameter_binders: [ParameterBinderV1]
  type_binders: [TypeBinderV1]
  row_binders: [RowBinderV1]
  contract_binders: [ContractBinderV1]
  owner_binders: [OwnerBinderV1]
  clock_binders: [ClockBinderV1]
  identity_binders: [IdentitySlotDeclV1]
  prompt_binders: [PromptSlotDeclV1]
}

DeclarationBindersV2 {
  parameter_binders: [ParameterBinderV2]
  type_binders: [TypeBinderV1]
  row_binders: [RowBinderV1]
  contract_binders: [ContractBinderV2]
  owner_binders: [OwnerBinderV1]
  clock_binders: [ClockBinderV1]
  identity_binders: [IdentitySlotDeclV1]
  prompt_binders: [PromptSlotDeclV1]
}

ParameterBinderV1 { slot: u32, type: TypeRefV1 }
ParameterBinderV2 { slot: u32, type: TypeRefV2 }
TypeBinderV1     { slot: u32, kind: Type | Effect | OwnerRegion }
RowBinderV1      { slot: u32, lacks: [EffectEntrySelectorV1] }
ContractBinderV1 =
    FunctionContractBinderV1 {
      slot: u32, parameter_type: TypeRefV1, result_type: TypeRefV1
    }
  | LaterContractBinderV1 {
      slot: u32,
      clock: SlotRefV1,                  // Clock namespace
      payload_type: TypeRefV1
    }
  | ContinuationContractBinderV1 {
      slot: u32, argument_type: TypeRefV1, answer_type: TypeRefV1
    }
  | HandlerContractBinderV1 {
      slot: u32, family: TypeRefV1,
      input_type: TypeRefV1, answer_type: TypeRefV1
    }

ContractBinderV2 =
    FunctionContractBinderV2 {
      slot: u32,
      parameter_type: TypeRefV2,
      result_type: TypeRefV2,
      visible_row: RowExprV1
    }
  | LaterContractBinderV2 {
      slot: u32,
      clock: SlotRefV1,
      payload_type: TypeRefV2
    }
  | ContinuationContractBinderV2 {
      slot: u32,
      argument_type: TypeRefV2,
      answer_type: TypeRefV2
    }
  | HandlerContractBinderV2 {
      slot: u32,
      family: TypeRefV2,
      input_type: TypeRefV2,
      answer_type: TypeRefV2
    }
OwnerBinderV1    { slot: u32, source: SlotRefV1 }
ClockBinderV1 {
  slot: u32
  identity: SlotRefV1                  // paired Identity namespace
  owner: SlotRefV1                     // Owner namespace
}

RowExprV1 =
    EmptyV1
  | ClosedV1 { entries: [EffectEntrySelectorV1] }
  | TailV1 { row_slot: SlotRefV1 }       // Row namespace
  | UnionV1 { members: [RowExprV1] }

TransitionV1 =
    BottomTransitionV1
  | SameWorldV1
  | NextWorldV1 { clock: SlotRefV1 }     // Clock namespace
  | SequenceTransitionV1 { steps: [TransitionV1] }
  | PathJoinTransitionV1 { paths: [TransitionV1] }

WorldExprV1 =
    EntryWorldV1 { site_slot: u32 }
  | WorldParameterV1 { contract_slot: u32 }
  | ApplyWorldTransitionV1 {
      input: WorldExprV1,
      transition: TransitionV1
    }
  | JoinWorldsV1 { members: [WorldExprV1] }

ResultTransformerV1 =
    BottomResultV1
  | ParametricResultV1 {
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1
    }
  | PathJoinResultV1 { paths: [ParametricResultV1] }

ResultTransformerV2 =
    LegacyResultTransformerV2 { value: ResultTransformerV1 }
  | ParametricResultV2 {
      provenance: ProvenanceExprV2,
      capture: CaptureExprV2
    }
  | ReturnBoundResultV2 { return_slot: u32 }
  | PathJoinResultV2 { paths: [ResultTransformerV2] }

SummaryV1 =
    PureV1
  | CertificateV1 {
      temporal: Pure | HostObservable,
      replay_origin: Fresh | Snapshot | SharedPersistent,
      fork: Forbid | Copy | Share | Merge,
      publish: None | CandidateBuffered | CommitOnly | Immediate,
      suspend: StackOnly | OwnerBound | Portable,
      trust: Derived | Sealed { module: ModulePathV1 } | TrustedUnsafe,
      origin: SourceOriginV1
    }
  | SequenceSummaryV1 { members: [SummaryV1] }
  | JoinSummaryV1 { members: [SummaryV1] }

ProvenanceExprV1 =
    BottomProvenanceV1
  | StableV1
  | ArgumentV1 { argument: SlotRefV1 }
  | RegionV1 { owner: SlotRefV1 }
  | CallbackV1 { site_slot: u32 }
  | OwnerV1 { owner: SlotRefV1 }
  | GenerationBoundV1 { owner: SlotRefV1 }
  | EnvironmentV1 { bindings: [EnvironmentBindingV1] }
  | ArrayElementProvenanceV1 { argument: SlotRefV1 }
  | OperationResultProvenanceV1 { site_slot: u32 }
  | JoinProvenanceV1 { members: [ProvenanceExprV1] }

CaptureExprV1 =
    BottomCaptureV1
  | NoCaptureV1
  | CaptureSlotsV1 { slots: [SlotRefV1] }
  | ArgumentCaptureV1 { argument: SlotRefV1 }
  | ArrayElementCaptureV1 { argument: SlotRefV1 }
  | OperationResultCaptureV1 { site_slot: u32 }
  | UnionCaptureV1 { members: [CaptureExprV1] }

ProvenanceExprV2 =
    LegacyProvenanceExprV2 { value: ProvenanceExprV1 }
  | ReturnProvenanceV2 { return_slot: u32 }
  | EnvironmentV2 { bindings: [EnvironmentBindingV2] }
  | JoinProvenanceV2 { members: [ProvenanceExprV2] }

CaptureExprV2 =
    LegacyCaptureExprV2 { value: CaptureExprV1 }
  | ReturnCaptureV2 { return_slot: u32 }
  | UnionCaptureV2 { members: [CaptureExprV2] }

EnvironmentBindingV1 {
  slot: SlotRefV1
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
}

EnvironmentBindingV2 {
  slot: SlotRefV1
  type: TypeRefV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
}

UsageV1 {
  slot: SlotRefV1
  kind: Zero | Once | Many
}

UsageExprV2 =
    LegacyUsageExprV2 { value: UsageV1 }
  | ReturnUsageV2 { return_slot: u32 }

PhaseRequirementV1 {
  allowed_phases: [Pure | Compute | Action | Commit]
  required_authorities: [
    OwnerAuthorityV1
    | IdentityAuthorityV1
    | AnonymousEffectAuthorityV1
  ]
  current_owner: SlotRefV1 | null        // Owner namespace
}

OwnerAuthorityV1    { owner: SlotRefV1 }     // Owner namespace
IdentityAuthorityV1 { identity: SlotRefV1 }  // Identity namespace
AnonymousEffectAuthorityV1 { family: TypeRefV1 }

TypeRefV1 =
    BuiltinTypeV1 { name: Unit | Never | Bool | Int | String }
  | TypeParameterV1 { slot: u32 }
  | NominalTypeV1 {
      module: ModulePathV1,
      name: IdentifierV1,
      arguments: [TypeRefV1]
    }
  | ApplyTypeV1 {
      constructor: TypeConstructorRefV1,
      arguments: [TypeRefV1]
    }
  | FunctionTypeV1 {
      parameter: TypeRefV1,
      result: TypeRefV1,
      contract: FunctionContractV1 | ContractParameterV1
    }
  | CapabilityTypeV1 {
      identity: SlotRefV1,               // Identity namespace
      family: TypeRefV1
    }
  | NextTypeV1 {
      clock: SlotRefV1,                  // Clock namespace
      payload: TypeRefV1,
      later_contract: LaterContractV1 | ContractParameterV1
    }
  | OwnerTypeV1 { owner: SlotRefV1 }
  | OwnerIndexedTypeV1 {
      constructor: Task | Source | Live | Event
                 | CompletionSource | CompletionPort
                 | CommitTicket | CommitGate,
      owner: SlotRefV1,                  // Owner namespace
      payload: TypeRefV1 | null
    }
  | ResourceTypeV1 {
      owner: SlotRefV1,                  // Owner namespace
      value: TypeRefV1,
      cleanup_result: TypeRefV1
    }
  | SignalTypeV1 {
      clock: SlotRefV1,                  // Clock namespace
      payload: TypeRefV1
    }
  | PlanTypeV1 { payload: TypeRefV1 }
  | ResumeTypeV1 {
      usage: Zero | Once | Many,
      continuation: SuffixContractV1 | ContractParameterV1,
      argument: TypeRefV1,
      answer: TypeRefV1,
      live_provenance: ProvenanceExprV1,
      live_capture: CaptureExprV1,
      owner: SlotRefV1                   // Owner namespace
    }
  | HandlerTemplateTypeV1 {
      family: TypeRefV1,
      owner: SlotRefV1,                  // Owner namespace
      input: TypeRefV1,
      answer: TypeRefV1,
      residual_row: RowExprV1,
      contract: HandlerContractV1 | ContractParameterV1,
      policy: SummaryV1
    }
  | ForAllIdentityTypeV1 {
      binder: QuantifiedIdentityBinderV1,
      body: TypeRefV1
    }
  | ForAllContractTypeV1 {
      binder: QuantifiedContractBinderV1,
      body: TypeRefV1
    }
  | ExistsClockPackageTypeV1 {
      clock_binder: QuantifiedClockBinderV1,
      summary_binder: QuantifiedContractBinderV1,
      body: TypeRefV1
    }
  | ForAllOwnerTypeV1 {
      binder: QuantifiedOwnerBinderV1,
      body: TypeRefV1
    }

TypeRefV2 =
    LegacyTypeRefV2 { value: TypeRefV1 }
  | TypeParameterV2 { slot: u32 }
  | NominalTypeV2 {
      module: ModulePathV1,
      name: IdentifierV1,
      arguments: [TypeRefV2]
    }
  | ApplyTypeV2 {
      constructor: TypeConstructorRefV1,
      arguments: [TypeRefV2]
    }
  | FunctionTypeV2 {
      parameter: TypeRefV2,
      result: TypeRefV2,
      contract: FunctionContractV2 | ContractParameterV2 | ContractRefV2
    }
  | CapabilityTypeV2 {
      identity: SlotRefV1,
      family: TypeRefV2
    }
  | NextTypeV2 {
      clock: SlotRefV1,
      payload: TypeRefV2,
      later_contract: LaterContractV2 | ContractParameterV2
    }
  | OwnerTypeV2 { owner: SlotRefV1 }
  | OwnerIndexedTypeV2 {
      constructor: Task | Source | Live | Event
                 | CompletionSource | CompletionPort
                 | CommitTicket | CommitGate,
      owner: SlotRefV1,
      payload: TypeRefV2 | null
    }
  | ResourceTypeV2 {
      owner: SlotRefV1,
      value: TypeRefV2,
      cleanup_result: TypeRefV2
    }
  | SignalTypeV2 { clock: SlotRefV1, payload: TypeRefV2 }
  | PlanTypeV2 { payload: TypeRefV2 }
  | ResumeTypeRefV2 { value: ResumeTypeV2 }
  | HandlerTemplateTypeV2 {
      family: TypeRefV2,
      owner: SlotRefV1,
      input: TypeRefV2,
      answer: TypeRefV2,
      residual_row: RowExprV1,
      contract: HandlerContractV2 | ContractParameterV2,
      policy: SummaryV1
    }
  | ForAllIdentityTypeV2 {
      binder: QuantifiedIdentityBinderV2,
      body: TypeRefV2
    }
  | ForAllContractTypeV2 {
      binder: QuantifiedContractBinderV2,
      body: TypeRefV2
    }
  | ForAllOwnerTypeV2 {
      binder: QuantifiedOwnerBinderV1,
      body: TypeRefV2
    }
  | ExistsClockPackageTypeV2 {
      clock_binder: QuantifiedClockBinderV2,
      summary_binder: QuantifiedContractBinderV2,
      body: TypeRefV2
    }
  | PackedNextTypeV2 {
      owner: SlotRefV1,
      payload: TypeRefV2
    }

PackedNextPackageV2 {
  artifact: "PackedNextPackageV2"
  profile: "Cire-TR₀/2026-08-01"
  schema_version: 2
  storage_owner: SlotRefV1
  child_owner_binder: QuantifiedOwnerBinderV1
  owner_relation: ChildOwnerWitnessV2
  clock_binder: QuantifiedClockBinderV2
  summary_binder: QuantifiedContractBinderV2
  body: NextTypeV2
  control_protocol: PackedNextControlProtocolV2
  sealed_origin: SourceOriginV2
}

ChildOwnerWitnessV2 {
  parent: SlotRefV1
  child: SlotRefV1
  relation: DirectChild
  sealed_origin: SourceOriginV2
}

PackedNextControlProtocolV2 {
  states: [Open(u32), Closing(u32), Closed]
  acquire: [Open(n) -> Open(n+1), Closing(n) -> None, Closed -> None]
  dispose: [Open(0) -> Closed+CloseChild,
            Open(n+1) -> Closing(n+1),
            Closing(n) -> Closing(n), Closed -> Closed]
  release: [Open(n+1) -> Open(n),
            Closing(1) -> Closed+CloseChild,
            Closing(n+1) -> Closing(n) where n>=1]
}

PackedNextExitEvidenceV2 {
  path_index: u32
  input_tag: ReturnsV2 | AbortsV2 | TransfersV2
  output_tag: ReturnsV2 | AbortsV2 | TransfersV2
  lease_action: ExactlyOnceRelease
  release_summary: SummaryV1
}

QuantifiedIdentityBinderV1 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1 | null
  family: TypeRefV1
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedIdentityBinderV2 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1 | null
  family: TypeRefV2
  owner: SlotRefV1
}

QuantifiedClockBinderV1 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1
  family: TypeRefV1
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedClockRefinementV1 {
  clock_slot: u32
  identity: SlotRefV1                    // local paired Identity namespace
}

ClockFamilyWitnessV2 = CanonicalFrameClockV2 {
  module: ["cire", "temporal"],
  name: "FrameClock",
  sealed_origin: SourceOriginV1
}

QuantifiedClockBinderV2 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1
  family_witness: ClockFamilyWitnessV2
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedOwnerBinderV1 { owner_slot: u32 }

QuantifiedContractBinderV1 {
  contract_slot: u32
  kind:
      FunctionContractKindV1 {
        parameter_type: TypeRefV1,
        result_type: TypeRefV1
      }
    | LaterContractKindV1 {
        clock: SlotRefV1,                // enclosing Clock namespace
        payload_type: TypeRefV1
      }
    | ClockPackageSummaryKindV1 {
        clock: SlotRefV1,                // paired local Clock namespace
        payload_type: TypeRefV1
      }
}

QuantifiedContractBinderV2 {
  contract_slot: u32
  kind:
      FunctionContractKindV2 {
        parameter_type: TypeRefV2,
        result_type: TypeRefV2,
        visible_row: RowExprV1
      }
    | LaterContractKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
    | ClockPackageSummaryKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
}

TypeConstructorRefV1 =
    BuiltinConstructorV1 { name: Array | Option | Result }
  | NominalConstructorV1 {
      module: ModulePathV1,
      name: IdentifierV1
    }

ContractParameterV1 {
  slot: u32
  kind: Function | Later | Continuation | Handler | ClockPackageSummary
}

ContractParameterV2 {
  slot: u32
  kind:
      FunctionContractKindV2 {
        parameter_type: TypeRefV2,
        result_type: TypeRefV2,
        visible_row: RowExprV1
      }
    | LaterContractKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
    | ContinuationContractKindV2 {
        argument_type: TypeRefV2,
        answer_type: TypeRefV2
      }
    | HandlerContractKindV2 {
        family: TypeRefV2,
        input_type: TypeRefV2,
        answer_type: TypeRefV2
      }
    | ClockPackageSummaryKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
}
LaterContractV1 {
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
}
LaterContractV2 {
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
}
HandlerContractV1 {
  handled_entry: EffectEntrySelectorV1
  prompt_slot: u32
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  handler_environment: [EnvironmentBindingV1]
  return_flow: FlowSetV1
  clause_flows: [ClauseFlowSetV1]
}
HandlerContractV2 {
  handled_entry: EffectEntrySelectorV1
  prompt_slot: u32
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
  handler_environment: [EnvironmentBindingV2]
  applications: [AppliedContractV2]
  return_computation: ContractComputationV2
  clause_computations: [ClauseComputationV2]
}
ClauseComputationV2 {
  operation: OperationSelectorV1
  disposition_binder: ClauseDispositionBinderV2
  computation: ContractComputationV2
}
ClauseDispositionBinderV2 {
  slot: u32
  site_slot: u32
  type: TypeRefV2                    // must be ResumeTypeRefV2
}
ClauseFlowSetV1 {
  operation: OperationSelectorV1
  disposition_binder: ClauseDispositionBinderV1
  flow: [ClauseFlowPathV1]
}
ClauseDispositionBinderV1 {
  slot: u32                             // declares a SuffixLive slot
  site_slot: u32
  type: TypeRefV1                       // must be ResumeTypeV1
}
IdentifierV1 = validated NFC UTF-8 identifier string
ModulePathV1 = nonempty [IdentifierV1]
StringV1 = NFC UTF-8 string

NominalIndexExprV1 =
    NoNominalIndexV1
  | TypeParameterIndexV1 { slot: u32 }
  | IdentityIndexV1 { identity: SlotRefV1 }
  | OwnerIndexV1 { owner: SlotRefV1 }

NominalIndexExprV2 =
    LegacyNominalIndexExprV2 { value: NominalIndexExprV1 }
  | ReturnNominalIndexV2 { return_slot: u32 }

OperationSignatureV1 {
  type_binders: [TypeBinderV1]
  parameters: [TypeRefV1]
  result: TypeRefV1
  mode: fun | once | ctl | abort
  transition: TransitionV1
  suspension: SuspensionV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
}

OperationSignatureV2 {
  type_binders: [TypeBinderV1]
  parameters: [TypeRefV2]
  result: TypeRefV2
  mode: fun | once | ctl | abort
  transition: TransitionV1
  suspension: SuspensionV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
}

SourceOriginV1 = canonical `file:subject` StringV1
SourceOriginV2 = SourceOriginV1

FlowSetV1 = nonempty [FlowPathV1]

FlowSetV2 = normalize(nonempty [PathOutcomeV2])

FlowPathV1 =
    Returns {
      transition: TransitionV1,
      result_transformer: ResultTransformerV1
    }
  | Aborts {
      origin: SourceOriginV1
    }
  | Transfers {
      park_contract: ParkContractV1
    }

ParkContractV1 {
  owner_slot: u32
  site_slot: u32
  claim_cell_slot: u32
  source: SourceContractV1
  completion_port: CompletionPortV1
  claim: GenerationCASV1
  disposition: OneShotDispositionV1
  required_phase: PhaseRequirementV1
  origin: SourceOriginV1
}

ParkContractV2 {
  owner_slot: u32
  site_slot: u32
  claim_cell_slot: u32
  source: SourceContractV2
  completion_port: CompletionPortV2
  claim: GenerationCASV1
  disposition: OneShotDispositionV2
  required_phase: PhaseRequirementV1
  origin: SourceOriginV1
}

SourceContractV1 {
  owner: SlotRefV1              // Owner namespace
  value_type: TypeRefV1
  generation_model: MonotoneGenerationV1
  write_authority: SingleWriterV1
}

CompletionPortV1 {
  owner: SlotRefV1              // same Owner as source
  result_type: TypeRefV1
  port_slot: u32
  claim_cell_slot: u32
}

SourceContractV2 {
  owner: SlotRefV1              // Owner namespace
  value_type: TypeRefV2         // exact resumption argument A
  generation_model: MonotoneGenerationV1
  write_authority: SingleWriterV1
}

CompletionPortV2 {
  owner: SlotRefV1              // same Owner as source
  value_type: TypeRefV2         // exact resumption argument A
  port_slot: u32
  claim_cell_slot: u32
}

GenerationCASV1 {
  claim_cell_slot: u32
  source_generation: ClaimTicketGeneration
  completion_generation_gate: EqualCurrentGeneration
  finalization_generation_gate:
    EqualCurrentGenerationOrOwnerRetireAuthority
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
  generation_transition: PreserveGeneration
  failure_transition: NoStateChange
}

OneShotDispositionV1 {
  continuation_site_slot: u32
  claim_cell_slot: u32
  continuation: SuffixContractV1
  states: [Unclaimed, Completed, Finalized]
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
}

OneShotDispositionV2 {
  continuation_site_slot: u32
  claim_cell_slot: u32
  resumption: ResumeTypeV2
  states: [Unclaimed, Completed, Finalized]
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
}

ResumeTypeV2 {
  usage: Zero | Once | Many
  continuation: SuffixContractV2
  argument: TypeRefV2
  answer: TypeRefV2
  live_provenance: ProvenanceExprV2
  live_capture: CaptureExprV2
  owner: SlotRefV1                  // Owner namespace
}

MonotoneGenerationV1 = Unsigned64NoWrap  // legacy V1/V2 wire only
SuccessorRuntimeGenerationV1 = RuntimeNat
SingleWriterV1 = OwnerExecutorOnly

ForwardContractV1 {
  site_slot: u32
  route: InstallationPromptV1 { prompt_slot: u32 }
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  continuation: ContinuationContractV1
  entry_world: WorldExprV1
  actual_argument_summaries: [ActualArgumentSummaryExprV1]
  instantiated_signature: OperationSignatureV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
  origin: SourceOriginV1
}

ForwardContractV2 {
  site_slot: u32
  route: InstallationPromptV1 { prompt_slot: u32 }
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  continuation: ContinuationContractV2
  entry_world: WorldExprV2
  actual_argument_summaries: [ValueSummaryExprV2]
  instantiated_signature: OperationSignatureV2
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
  origin: SourceOriginV2
}

ForwardDispositionEvidenceV2 {
  inner_disposition: SlotRefV1       // SuffixLive namespace
  input_state: Open
  output_state: Forwarded
  forward_site_slot: u32
  continuation_transfer: ExclusiveToForwardContract
}

ClauseFlowPathV1 =
    FlowPathV1
  | Delegates {
      forward_contract: ForwardContractV1,
      disposition_evidence: ForwardDispositionEvidenceV1
    }

ForwardDispositionEvidenceV1 {
  inner_disposition: SlotRefV1           // authority-bearing SuffixLive slot
  input_state: Open
  output_state: Forwarded
  forward_site_slot: u32
  continuation_transfer: ExclusiveToForwardContract
}

SuspensionV1 {
  grade: SuspensionGradeV1
  atoms: [SuspensionAtomV1]
}

SuspensionGradeV1 = NoSuspend | MaySuspend

SuspensionAtomV1 =
    DirectV1 {
      grade: MaySuspend,
      origin: SourceOriginV1
    }
  | RequestV1 {
      site_slot: u32,
      route: RouteSelectorV1,
      entry: EffectEntrySelectorV1,
      operation: OperationSelectorV1,
      site_role: Primary | Secondary { secondary_slot: u32 },
      grade: SuspensionGradeV1,
      origin: SourceOriginV1
    }
  | OwnerBoundV1 {
      park_site_slot: u32,
      owner_slot: u32,
      grade: SuspensionGradeV1,
      origin: SourceOriginV1
    }

SlotRefV1 {
  namespace: Parameter | ClosureCapture | OperationArgument
             | SuffixLive | Clock | Owner | Row | Identity
  slot: u32
}

PromptSlotDeclV1 {
  prompt_slot: u32
  binder_site_slot: u32
  scope: LexicalInstallation
}

IdentitySlotDeclV1 {
  identity_slot: u32
  family: EffectFamilyRefV2
  owner: SlotRefV1                       // Owner namespace
  binder: FreshCap | NamedHandler
}

EffectFamilyRefV2 =
    NominalTypeV1 resolved as an Effect declaration
  | TypeParameterV1 whose slot has kind Effect
  | TypeParameterV2 whose slot has kind Effect

EffectFamilyDeclarationsV1 {
  artifact: "EffectFamilyDeclarationsV1",
  profile: "Cire-TR₀/2026-08-01",
  schema_version: 1,
  families: [{ module: [IdentifierV1], name: IdentifierV1, arity: u32 }]
}

Catalog是 exact object；`families`按整个 declaration的 JCS encoding递增且
module-qualified identity唯一，`module`非空，`arity`在 wire-u32 domain。

EffectEntrySelectorV1 =
    AnonV1 {
      family: EffectFamilyRefV2
    }
  | NamedV1 {
      identity: SlotRefV1,       // Identity namespace
      family: EffectFamilyRefV2
    }
  | HandlerEntryParameterV1 {
      contract_slot: u32         // Handler contract binder
    }

OperationSelectorV1 =
    ExactOperationV1 {
      family: EffectFamilyRefV2,
      name: IdentifierV1
    }
  | AnyOperationOfEntry

ActualArgumentSummaryExprV1 =
    SlotArgumentV1 {
      source: SlotRefV1,
      type: TypeRefV1,
      nominal_index: NominalIndexExprV1,
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1
    }
  | ComputedArgumentV1 {
      type: TypeRefV1,
      nominal_index: NominalIndexExprV1,
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1,
      origin: SourceOriginV1
    }

DemandV1 {
  site_slot: u32
  route: RouteSelectorV1
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  site_role: Primary | Secondary { secondary_slot: u32 }
}

LiveAcrossSiteV1 {
  slot: SlotRefV1              // SuffixLive namespace
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
  usage: UsageV1
}

LiveAcrossSiteV2 {
  slot: SlotRefV2              // SuffixLive or an in-scope return binder
  type: TypeRefV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2?          // null is canonical Zero/non-authority
}

CleanupContractV1 {
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  transition: TransitionV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
}

SuffixContractV1 {
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  flow: FlowSetV1
  transition: TransitionV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  cleanup: CleanupContractV1
  live_bindings: [LiveAcrossSiteV1]
}

SuffixContractV2 {
  answer_type: TypeRefV2
  applications: [AppliedContractV2]
  computation: ContractComputationV2
  cleanup: CleanupContractV1
  live_bindings: [LiveAcrossSiteV2]
}

ContinuationContractV1 = SuffixContractV1
ContinuationContractV2 = SuffixContractV2

CaptureSlotV1 {
  slot: SlotRefV1            // namespace must be ClosureCapture
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
}

ObligationV1 =
    BoundarySafeV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      boundary: BoundaryKindV1, origin: SourceOriginV1
    }
  | StableAcrossV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      clock_slot: SlotRefV1, worlds: [WorldExprV1],
      origin: SourceOriginV1
    }
  | OutlivesV1 {
      id: u32, stage: StageV1,
      shorter: SlotRefV1, longer: SlotRefV1,
      origin: SourceOriginV1
    }
  | PhaseAllowsV1 {
      id: u32, stage: StageV1,
      required_phase: PhaseRequirementV1,
      origin: SourceOriginV1
    }
  | DuplicableEnvV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      site_slot: u32, origin: SourceOriginV1
    }
  | ReplayableCleanupV1 {
      id: u32, stage: StageV1, site_slot: u32,
      cleanup: CleanupContractV1, origin: SourceOriginV1
    }
  | TickWitnessV1 {
      id: u32, stage: StageV1,
      clock_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV1
    }
  | OwnerParkingV1 {
      id: u32, stage: StageV1,
      owner_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV1
    }
  | RowLacksV1 {
      id: u32, stage: StageV1,
      row_slot: SlotRefV1, entry: EffectEntrySelectorV1,
      origin: SourceOriginV1
    }

ObligationV2 =
    LegacyObligationV2 { value: ObligationV1 }
  | BoundarySafeV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      boundary: BoundaryKindV1, origin: SourceOriginV2
    }
  | StableAcrossV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      clock_slot: SlotRefV1, worlds: [WorldExprV2],
      origin: SourceOriginV2
    }
  | OutlivesV2 {
      id: u32, stage: StageV1,
      shorter: SlotRefV2, longer: SlotRefV2,
      origin: SourceOriginV2
    }
  | PhaseAllowsV2 {
      id: u32, stage: StageV1,
      required_phase: PhaseRequirementV1,
      origin: SourceOriginV2
    }
  | DuplicableEnvV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      site_slot: u32, origin: SourceOriginV2
    }
  | ReplayableCleanupV2 {
      id: u32, stage: StageV1, site_slot: u32,
      cleanup: CleanupContractV1, origin: SourceOriginV2
    }
  | TickWitnessV2 {
      id: u32, stage: StageV1,
      clock_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV2
    }
  | OwnerParkingV2 {
      id: u32, stage: StageV1,
      owner_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV2
    }
  | RowLacksV2 {
      id: u32, stage: StageV1,
      row_slot: SlotRefV1, entry: EffectEntrySelectorV1,
      origin: SourceOriginV2
    }

BoundaryKindV1 =
    CallArgument | Return | Closure | Aggregate | OwnerStorage
  | ContinuationCapture | TemporalLock | Suspension | FFI

LatentSiteV1 {
  site_slot: u32             // alpha-normalized lexical-site slot
  stage: Call | HandlerInstall
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  actual_arguments: [ActualArgumentSummaryExprV1]
  instantiated_signature: OperationSignatureV1
  suffix: SuffixContractV1
  secondary_sites: SecondarySiteSetV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  origin: SourceOriginV1
}

LatentSiteV2 {
  site_slot: u32
  stage: Call | HandlerInstall
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  actual_arguments: [ValueSummaryExprV2]
  instantiated_signature: OperationSignatureV2
  suffix: SuffixContractV2
  secondary_sites: SecondarySiteSetV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  origin: SourceOriginV2
}

SecondarySiteSetV1 {
  kind: Closed
  sites: [SecondarySiteV1]
}

SecondarySiteV1 {
  site_slot: u32
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  origin: SourceOriginV1
}

RouteSelectorV1 =
    ResolveAtCallV1 { on_missing: MissingRoutePolicyV1 }
  | ResolveAtInstallationV1 { on_missing: MissingRoutePolicyV1 }
  | InstallationPromptV1 { prompt_slot: u32 }
  | OuterOfV1 { prompt_slot: u32 }
  | RootOfEntryV1

MissingRoutePolicyV1 = RootOfEntryV1
StageV1 = Call | HandlerInstall
```
