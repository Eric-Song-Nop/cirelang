#import "../shared.typ": *

== CallableInterfaceV1 与 FunctionContractV3 <function-contract-v3>

```text
CallableInterfaceV1 = {
  artifact: "CallableInterfaceV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  module: PackageModulePathV1,
  export_path: [NfcSegmentV1],
  core_contract: {
    artifact: "FunctionContractV3",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  },
  surface_signature: CallableSurfaceSignatureV1
}

CallableSurfaceSignatureV1 = {
  kind: "CallableSurfaceSignatureV1",
  slots: [ParameterSurfaceSlotV1]
}

ParameterSurfaceSlotV1 =
    { slot: u32, passing: "ImplicitReceiverV1" }
  | { slot: u32, passing: "PositionalOnlyV1" }
  | { slot: u32, passing: "NamedOrPositionalV1",
      public_label: NFC nonempty String, defaultable: Bool }

ImportedCallableRefV3 = {
  import_slot: WireU32V1,
  module: PackageModulePathV1,
  export_path: [NfcSegmentV1],
  interface_hash: Sha256V1
}

FunctionContractV3 = {
  artifact: "FunctionContractV3",
  profile: "Cire-v1.0",
  schema_version: 3,
  root_declaration_slot: WireU32V1,
  declaration_kind: M3(FunctionContractKindV2) | null,
  binders: M3(DeclarationBindersV2),
  callable_dependencies: [ImportedCallableRefV3],
  local_declarations: [LocalFunctionDeclarationV3],
  default_prologues: [DefaultPrologueV1],
  applications: [M3(AppliedContractV2)],
  computation: M3(ContractComputationV2),
  closure_environment: [M3(EnvironmentBindingV2)]
}

LocalFunctionDeclarationV3 = {
  declaration_slot: u32,
  declaration_kind: M3(FunctionContractKindV2),
  binders: M3(DeclarationBindersV2),
  default_prologues: [DefaultPrologueV1],
  applications: [M3(AppliedContractV2)],
  computation: M3(ContractComputationV2),
  closure_environment: [M3(EnvironmentBindingV2)]
}

DefaultPrologueV1 = {
  kind: "DefaultPrologueV1",
  parameter_slot: WireU32V1,
  input_type: M3(TypeRefV2),
  output_type: M3(TypeRefV2),
  computation: M3(ContractComputationV2),
  origin: SourceOriginV1
}

ContractRefV3 =
    ContractParameterRefV2 { parameter: M3(ContractParameterV2) }
  | ImportedCallableSlotRefV3 { import_slot: WireU32V1 }
  | LocalFunctionRefV2 { declaration_slot: u32 }

TypeBinderV3 =
    TypeBinderV1 { slot: u32, kind: Type | Effect | OwnerRegion }
  | EffectConstructorBinderV3 {
      slot: u32,
      kind: "EffectConstructorV3",
      constructor_arity: WireU32V1
    }

EffectConstructorActualV1 =
    { kind: "NominalEffectConstructorActualV1",
      effect: DeclarationIdentityV1,
      constructor_arity: WireU32V1 }
  | { kind: "EffectConstructorParameterActualV1",
      binder_slot: WireU32V1,
      constructor_arity: WireU32V1 }

TypeSubstitutionV3 =
    TypeSubstitutionV2 { binder_slot: u32, value: M3(TypeRefV2) }
  | EffectConstructorSubstitutionV3 {
      binder_slot: WireU32V1,
      constructor: EffectConstructorActualV1
    }

TypeConstructorRefV3 =
    BuiltinConstructorV1 { name: Array | Option | Result }
  | NominalConstructorV1 {
      module: ModulePathV1,
      name: IdentifierV1
    }
  | EffectParameterConstructorV3 {
      binder_slot: WireU32V1,
      constructor_arity: WireU32V1
    }
```

`FunctionContractV3` 上述 12 个 fields 是 exact set；没有 `module`、`export_path`、
`package`、trait/const facts、`imports` 或 `dependencies` alias。`M3` 是 schema
migration function，不是 wire tag：它结构递归保留每个 approved V2 object/union/list 的 field、
tag、order 与 scalar shape；非恒等式恰是：

```text
M3(FunctionContractV2) = FunctionContractV3
M3(ContractRefV2)      = ContractRefV3
M3(DeclarationBindersV2.type_binders[*]: TypeBinderV1) = TypeBinderV3
M3(ContractSubstitutionV2.type_arguments[*]: TypeSubstitutionV2) = TypeSubstitutionV3
M3(ApplyTypeV2.constructor: TypeConstructorRefV1) = TypeConstructorRefV3
```

所以 applications、substitution、function type、nested contract、closure、handler、resumption、
computation 与 type tree 中任意深度的 V2 contract/ref nonterminal都必须递归迁移；raw
`ImportedFunctionRefV2` 或 raw Core hash 在 V3 中稳定
`callable-interface-contract-mismatch`。
后两个 delta共同关闭 source `F[_]` 的既有 kind domain：每个 declaration scope（root、local、lambda
与允许的 local scheme）都把 `F[_]` 写成 `EffectConstructorBinderV3`；atomic `F` 仍是 retained
`TypeBinderV1{kind:Effect}`。Constructor arity必须大于 0，slot与同 scope的其它 type binder互异。
`M3(ApplyTypeV2.constructor)` 可用 `EffectParameterConstructorV3`，其 slot必须解析为 enclosing
`M3(DeclarationBindersV2).type_binders` 中 exact `EffectConstructorBinderV3`；exported/named declaration
还必须与 `DeclarationRequirementsV1.effect_parameters` 的同 slot/arity交叉核对。Application argument
count恰等于该 arity。Atomic `F`、Type binder、Row binder、unbound slot或 arity drift
稳定 `contract-component-kind-mismatch`；builtin/nominal constructor的 retained shape不变。该 tag不能
出现在 raw V2/TR0 artifact，也不能作为 ordinary term/type parameter constructor。

`M3(ContractSubstitutionV2).type_arguments` 对 ordinary Type/atomic Effect继续使用 retained
`TypeSubstitutionV2{value}` branch；target是 `EffectConstructorBinderV3` 时必须且只能使用
`EffectConstructorSubstitutionV3`。Nominal actual的 `effect` 必须解析为 exact `EffectDeclarationV1`，
其 source Type-binder arity等于 `constructor_arity`；parameter actual必须解析 caller scope中另一个
`EffectConstructorBinderV3`，且 arity exact。Substitution递归把 target slot的每个
`EffectParameterConstructorV3` 替为 nominal `NominalConstructorV1`（按该 effect identity的唯一
module/path projection）或 caller parameter constructor，然后才应用其 arguments并重跑 Effect kind/WF。
不允许 partial application、ordinary nominal type、atomic Effect value、self-asserted occurrence arity或
new tag藏入 `LegacyTypeRefV2.value`；missing/duplicate/wrong branch稳定
`contract-component-kind-mismatch`。

Root declaration slot固定 0。每个 source `LambdaExpr`（ordinary 或 generic）恰好 lift一次为
最近 local/evidence boundary 的 `LocalFunctionDeclarationV3`：ordinary callable body使用 enclosing
V3，trait-method signature default computation使用 sibling `TraitDefaultPrologueProgramV1`。Expression 使用 `LocalFunctionRefV2`并保留 exact
closure environment；ordinary lambda的 binder仍 monomorphic，generic lambda只按上述 local rank-1 gate成为 scheme。
Normalized Surface HIR lexical declaration preorder为所有 reachable local def/lambda连续分配 `1..n`；同 node内多个 synthesized
declaration用 `(schema-field-ordinal,list-index)` 排序。`local_declarations` 必须按 slot严格为
`1..n`，exact reachable、无 missing/unused；`LocalFunctionRefV2` 只解析最近 V3 或
`TraitDefaultPrologueProgramV1` boundary，绝不跨过任一 root slot 0。Program boundary使用自己的
callable dependency/application/closure/requirement-scope/trait-method-use tables做与 V3 相同的 exact
allocation与双向 coverage。
Source lambda不允许另嵌一个重置 slot 0的 `FunctionContractV3`，因而
`CallableContractFactEvidenceV1.requirement_scopes/trait_method_uses` 的 declaration slot在 lambda内仍唯一。
每个 named `def` row，包括 package-private、method、extension、trait default、impl method 与
`const def`，必须显式 source-spell result与 `! row`；pure 也写 `! {}`。省略稳定
`named-function-effect-row-required`，绝不触发全局 API inference。

Dependencies先从 symbolic `(module,export_path)` public graph建立；imported frozen node也须
exact-decode并解开其 lexical slot tables来恢复全部 nested edge。Imported self-edge或 SCC 大于 1
稳定 `recursive-public-callable-scc-not-in-v1`；same-module recursion只用 local declaration slot。
DAG通过后按 callee-before-caller填 hash，再对每个 V3 boundary把 distinct
`{module,export_path,interface_hash}` 的 NFC+JCS bytes严格排序并连续分配 `import_slot=0..n-1`。
每个 dependency必须 used且每个 ref in range；非 source-lambda的独立 imported/sealed V3 boundary仍重置 lexical dependency table但不截断
public graph extraction。

Interface slots按 numeric slot严格递增，exact equal于 Core call-entry binder slots。Implicit receiver
与 destructuring parameter分别只能是 `ImplicitReceiverV1` 与 `PositionalOnlyV1`；simple parameter
是 `NamedOrPositionalV1`。每个 `CallableSurfaceSignatureV1`（包括 callable、trait method 与
ability/effect operation）内所有 `NamedOrPositionalV1.public_label` 必须 pairwise distinct；slot或 type
不同不能使同名 label变得可分辨。Defaultable slot的 Core input恰为
`ProvidedOrOmitted[output_type]`，prologue按 parameter slot递增且 exact equal于 defaultable slots；
caller先按 source order求值 callee、全部 explicit arguments与 trailing closure，callee再按 declaration
order求值 omitted defaults。Direct capability binder永不 defaultable。

`PackageCallableEdgeV1.module/export_path`、载入的 `CallableInterfaceV1` identity及其 hash必须
三者 exact equal。Public import永远指 interface hash，随后只沿该 envelope 的 V3 edge；没有
`CireLanguageInterfaceV1 -> raw FunctionContractV3` shortcut。

每个 user public `(module,export_path)` 恰一 callable；user source 不依参数类型或返回类型
overload。Sealed first-party member/intrinsic 即使共享 source member spelling，也必须有 distinct
stable export paths/registry IDs；冲突稳定 `public-overload-requires-distinct-export-path`，同 key
来自两个 source root 则 `callable-source-import-collision`。

Hash differential是强制的：public label rename 改变 callee `CallableSurfaceSignatureV1` 及
interface hash；若 typed binder/Core computation 未变，callee `FunctionContractV3` bytes 可保持不变，
但每个 caller 的 `ImportedCallableRefV3.interface_hash`、V3 root 及自身 interface hash都必须沿 DAG
逐层重算。Default add/remove/change 同时改变 surface slot与 callee `default_prologues`，因而
callee interface/Core 两个 hash都改变，再以同一 dependency edge 规则传播到所有 transitive caller。
任一 producer 只改 envelope 而不重算 caller，或只改 prologue 而沿用 old interface hash，均稳定
`callable-interface-contract-mismatch`。
