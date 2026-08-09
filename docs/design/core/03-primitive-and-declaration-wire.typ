#import "../shared.typ": *

== PrimitiveCatalogV1 与 source builtin identity <primitive-catalog-v1>

`PrimitiveCatalogV1` 是 source builtin 的唯一 resolver input。Legacy
`Unit/Never/Bool/Int/String` 保留旧 `TypeRefV2` exact form；其余 builtin 不扩写
`BuiltinTypeV1.name`，而是 locked core package 下的 sealed zero-argument nominal reference。

```text
PrimitiveCatalogV1 = {
  artifact: "PrimitiveCatalogV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  core_package: PackageInstanceIdV1,
  entries: [PrimitiveEntryV1; 16]
}

PrimitiveEntryV1 = {
  source_name: "Unit" | "Never" | "Bool"
             | "Int8" | "Int16" | "Int" | "Int64"
             | "UInt8" | "UInt16" | "UInt" | "UInt64"
             | "Float32" | "Float" | "Char" | "String" | "Bytes",
  type: M3(TypeRefV2),
  carrier: "NoneV1" | "I32V1" | "I64V1" | "F32V1" | "F64V1"
         | "PrivateManagedV1"
}

LegacyPrimitive(name) =
  LegacyTypeRefV2 { value: BuiltinTypeV1 { name: name } }

CorePrimitive(core,name) =
  NominalTypeV2 {
    module: ["pkg-" + core.digest, "core", "primitive"],
    name: name,
    arguments: []
  }
```

entries 的 canonical source-name order固定为：

```text
Unit, Never, Bool,
Int8, Int16, Int, Int64,
UInt8, UInt16, UInt, UInt64,
Float32, Float, Char, String, Bytes
```

其 exact mapping 为：`Unit/Never/Bool/Int/String -> LegacyPrimitive(same name)`；
`Int8/Int16/Int64/UInt8/UInt16/UInt/UInt64/Float32/Float/Char/Bytes ->
CorePrimitive(core_package,same name)`。Carriers 为：Unit/Never=`NoneV1`；Bool、Int8、
Int16、Int、UInt8、UInt16、UInt、Char=`I32V1`；Int64、UInt64=`I64V1`；
Float32=`F32V1`；Float=`F64V1`；String、Bytes=`PrivateManagedV1`。
Catalog 必须恰含上述 16 项（5 个 legacy exact form 与 11 个 sealed nominal form）且
`core_package` 等于 profile lock 中 core dependency；source
resolver 对任一 builtin 只读这个 catalog。`Byte`、pointer-sized integer、raw pointer、SIMD 或
user shadow identity 都不是 builtin。

Carrier ingress/egress 也是 catalog contract，不是 backend freedom：`Int8/Int16` 的 i32
carrier在每个 ingress 验证高位为 canonical sign extension，`UInt8/UInt16` 验证 canonical
zero extension，每个 result/export 用同一规则重建 carrier；`Bool` 只接受并产生 i32
0/1；`Char` 的 i32 恰是一个非-surrogate Unicode scalar。非 canonical ingress 必须在进入
typed Core 前拒绝，不准依赖截断、truthiness 或 host 容忍。

== Package-level declaration 与 evidence schema <foundation-declaration-wire>

以下 artifact承载 ordinary foundation facts。它们不嵌入 callable V3 root，也不能通过
`M3` 增加 V2 object field。

```text
VisibilityV1 = "PackageV1" | "PublicV1"
OpenVisibilityV1 = "PackageV1" | "PublicSealedV1" | "PublicOpenV1"

AssociatedArgumentValueV1 =
    { kind: "TypeAssociatedArgumentV1", value: M3(TypeRefV2) }
  | { kind: "EffectAssociatedArgumentV1", value: M3(TypeRefV2) }
  | { kind: "RowAssociatedArgumentV1", value: RowExprV1 }

AssociatedArgumentBindingV1 = {
  item_ordinal: WireU32V1,
  declaration_name: NfcSegmentV1,
  value: AssociatedArgumentValueV1
}

GenericTraitAssociatedTypeV1 = {
  item_ordinal: WireU32V1,
  declaration_name: NfcSegmentV1,
  binder_slot: WireU32V1,
  equality: M3(TypeRefV2) | null
}

TraitRequirementOriginV1 =
    { kind: "SourceTraitRequirementV1" }
  | { kind: "OwningTraitSelfV1" }
  | { kind: "AssociatedConstraintEntailmentV1",
      parent_requirement_ordinal: WireU32V1,
      associated_item_ordinal: WireU32V1,
      constraint_ordinal: WireU32V1 }

GenericTraitRequirementV1 = {
  requirement_ordinal: WireU32V1,
  origin: TraitRequirementOriginV1,
  binder_slot: WireU32V1,
  trait: DeclarationIdentityV1,
  arguments: [M3(TypeRefV2)],
  associated_types: [GenericTraitAssociatedTypeV1]
}

GenericAbilityAssociatedItemV1 = {
  item_ordinal: WireU32V1,
  declaration_name: NfcSegmentV1,
  binder_slot: WireU32V1,
  equality: AssociatedArgumentValueV1 | null
}

GenericAbilityRequirementV1 = {
  ability: DeclarationIdentityV1,
  arguments: [M3(TypeRefV2)],
  associated_items: [GenericAbilityAssociatedItemV1]
}

GenericEffectParameterV1 = {
  binder_slot: WireU32V1,
  constructor_arity: WireU32V1,
  abilities: [GenericAbilityRequirementV1]
}

DeclarationRequirementsV1 = {
  ordinary_traits: [GenericTraitRequirementV1],
  effect_parameters: [GenericEffectParameterV1]
}

StoredFieldV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  visibility: VisibilityV1,
  type: M3(TypeRefV2),
  default_value: ConstValueV1 | null
}

VariantPayloadV1 =
    { kind: "UnitVariantV1" }
  | { kind: "TupleVariantV1", elements: [M3(TypeRefV2)] }
  | { kind: "RecordVariantV1", fields: [StoredFieldV1] }

EnumVariantV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  payload: VariantPayloadV1
}

DataBodyV1 =
    { kind: "StructV1", fields: [StoredFieldV1] }
  | { kind: "EnumV1", variants: [EnumVariantV1] }
  | { kind: "NewtypeV1", field: StoredFieldV1 }
  | { kind: "OpaqueTypeV1", representation: M3(TypeRefV2) | null }
  | { kind: "TransparentAliasV1", target: M3(TypeRefV2) }

DataDeclarationV1 = {
  artifact: "DataDeclarationV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: DeclarationIdentityV1,
  visibility: VisibilityV1,
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  body: DataBodyV1,
  derives: [DeclarationIdentityV1]
}

AssociatedTypeDeclarationV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  binder_slot: WireU32V1,
  constraints: [TraitGoalV1],
  default_type: M3(TypeRefV2) | null
}

TraitMethodSignatureV1 = {
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  surface_signature: CallableSurfaceSignatureV1,
  declaration_kind: M3(FunctionContractKindV2),
  default_program: TraitDefaultPrologueProgramV1
}

TraitMethodDeclarationV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  signature: TraitMethodSignatureV1,
  default_body: PackageCallableEdgeV1 | null
}

TraitDeclarationV1 = {
  artifact: "TraitDeclarationV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: DeclarationIdentityV1,
  visibility: OpenVisibilityV1,
  binders: M3(DeclarationBindersV2),
  self_binder_slot: WireU32V1,
  requirements: DeclarationRequirementsV1,
  associated_types: [AssociatedTypeDeclarationV1],
  methods: [TraitMethodDeclarationV1]
}

AssociatedTypeBindingV1 = {
  ordinal: WireU32V1,
  declaration_name: NfcSegmentV1,
  value: M3(TypeRefV2),
  source: "ExplicitImplBindingV1" | "TraitDefaultBindingV1"
}

ImplMethodBindingV1 = {
  trait_method_ordinal: WireU32V1,
  source: "ExplicitImplMethodV1" | "TraitDefaultMethodV1",
  callable: PackageCallableEdgeV1
}

ImplOriginV1 =
    { kind: "HandwrittenImplV1", origin: SourceOriginV1 }
  | { kind: "DerivedImplV1", trait: DeclarationIdentityV1,
      origin_id: WireU32V1, intrinsic_id: "Cire-v1.0/structural/derive" }

ImplEvidenceV1 = {
  artifact: "ImplEvidenceV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: EvidenceIdentityV1,
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  trait: DeclarationIdentityV1,
  target: M3(TypeRefV2),
  header: TraitGoalV1,
  associated_types: [AssociatedTypeBindingV1],
  methods: [ImplMethodBindingV1],
  origin: ImplOriginV1
}

CallableDeclarationKindV1 =
    { kind: "FreeCallableV1" }
  | { kind: "InherentCallableV1", owner: DeclarationIdentityV1,
      receiver: M3(TypeRefV2) | null }
  | { kind: "ExtensionCallableV1", receiver: M3(TypeRefV2) }
  | { kind: "TraitDefaultCallableV1", trait: DeclarationIdentityV1,
      method_ordinal: WireU32V1, receiver: M3(TypeRefV2) | null }
  | { kind: "ImplMethodCallableV1", impl: EvidenceIdentityV1,
      trait: DeclarationIdentityV1, method_ordinal: WireU32V1,
      receiver: M3(TypeRefV2) | null }
  | { kind: "ManifestAdapterCallableV1",
      manifest_name: NfcSegmentV1,
      manifest_hash: Sha256V1,
      wit_path: [NfcSegmentV1],
      source_binding: [NfcSegmentV1] }

CallableSourceIdentityV1 =
    { kind: "FreeSourceV1", declaration: DeclarationIdentityV1 }
  | { kind: "InherentSourceV1", owner: DeclarationIdentityV1,
      member: NfcSegmentV1 }
  | { kind: "ExtensionSourceV1", declaration: DeclarationIdentityV1 }
  | { kind: "TraitDefaultSourceV1", trait: DeclarationIdentityV1,
      method_ordinal: WireU32V1 }
  | { kind: "ImplMethodSourceV1", impl: EvidenceIdentityV1,
      trait_method_ordinal: WireU32V1 }
  | { kind: "ManifestAdapterSourceV1",
      manifest_name: NfcSegmentV1,
      manifest_hash: Sha256V1,
      wit_path: [NfcSegmentV1],
      source_binding: [NfcSegmentV1] }

TraitMethodUseEvidenceV1 = {
  declaration_slot: WireU32V1,
  application_slot: WireU32V1,
  requirement_ordinal: WireU32V1,
  target_type_binder_slot: WireU32V1,
  trait: DeclarationIdentityV1,
  method_ordinal: WireU32V1,
  method_instantiation: M3(ContractSubstitutionV2),
  contract_slot: WireU32V1
}

CallableRequirementScopeV1 = {
  declaration_slot: WireU32V1,
  requirements: DeclarationRequirementsV1
}

TraitDefaultPrologueProgramV1 = {
  kind: "TraitDefaultPrologueProgramV1",
  root_declaration_slot: WireU32V1,
  callable_dependencies: [ImportedCallableRefV3],
  local_declarations: [LocalFunctionDeclarationV3],
  default_prologues: [DefaultPrologueV1],
  applications: [M3(AppliedContractV2)],
  closure_environment: [M3(EnvironmentBindingV2)],
  requirement_scopes: [CallableRequirementScopeV1],
  trait_method_uses: [TraitMethodUseEvidenceV1]
}

CallableContractFactEvidenceV1 = {
  artifact: "CallableContractFactEvidenceV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: EvidenceIdentityV1,
  package: PackageInstanceIdV1,
  callable: PackageCallableEdgeV1,
  source_identity: CallableSourceIdentityV1,
  declaration_kind: CallableDeclarationKindV1,
  visibility: VisibilityV1,
  requirement_scopes: [CallableRequirementScopeV1],
  trait_method_uses: [TraitMethodUseEvidenceV1],
  const_safety: "RuntimeCallableV1" | "ConstSafeV1",
  protocol_purity: "OrdinaryCallableV1" | "ProtocolPureV1",
  trap: "NoTrapV1" | "MayTrapV1"
}

TraitAssociatedTypeEqualityV1 = {
  item_ordinal: WireU32V1,
  declaration_name: NfcSegmentV1,
  value: M3(TypeRefV2)
}

TraitGoalV1 = {
  trait: DeclarationIdentityV1,
  arguments: [M3(TypeRefV2)],
  associated_types: [TraitAssociatedTypeEqualityV1],
  target: M3(TypeRefV2)
}

AbilityAssociatedItemV1 =
    { kind: "AbilityAssociatedTypeV1", ordinal: WireU32V1,
      name: NfcSegmentV1, binder_slot: WireU32V1,
      default_type: M3(TypeRefV2) | null }
  | { kind: "AbilityAssociatedEffectV1", ordinal: WireU32V1,
      name: NfcSegmentV1, binder_slot: WireU32V1,
      default_effect: M3(TypeRefV2) | null }
  | { kind: "AbilityAssociatedRowV1", ordinal: WireU32V1,
      name: NfcSegmentV1, binder_slot: WireU32V1,
      default_row: RowExprV1 | null }

OperationDeclarationV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  surface_signature: CallableSurfaceSignatureV1,
  signature: M3(OperationSignatureV2)
}

AbilityDeclarationV1 = {
  artifact: "AbilityDeclarationV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: DeclarationIdentityV1,
  visibility: OpenVisibilityV1,
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  associated_items: [AbilityAssociatedItemV1],
  operations: [OperationDeclarationV1]
}

AbilityConformanceV1 = {
  ability: DeclarationIdentityV1,
  arguments: [M3(TypeRefV2)],
  associated_arguments: [AssociatedArgumentBindingV1]
}

EffectDeclarationV1 = {
  artifact: "EffectDeclarationV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: DeclarationIdentityV1,
  visibility: OpenVisibilityV1,
  binders: M3(DeclarationBindersV2),
  requirements: DeclarationRequirementsV1,
  conformances: [AbilityConformanceV1],
  declared_operations: [OperationDeclarationV1]
}
```

Ordinal arrays从 0 连续、严格递增且无重复。Data identity namespace必须为 `TypeV1`；
trait/ability/effect identity必须分别为 `TraitV1`/`AbilityV1`/`EffectV1`；impl identity
package必须是当前 package。`NewtypeV1.field`
的 ordinal 必须为 0，且 body恰一个 named stored field。Alias graph无 cycle；newtype
representation cycle必须穿过显式 indirection。Public enum的 variant set是 closed API。
`PublicOpenV1` 只允许 trait/ability/effect declaration，data 不允许。

Declared-name lookup在 ordinal/vector validation后还要求 injective：每个 struct/newtype/record-variant的
stored field name唯一；每个 enum的 variant name唯一；每个 trait的 associated-Type names各自唯一且
method names各自唯一；每个 ability的 associated Type/Effect/EffectRow三种 item共享一个 associated-name
namespace并唯一，operation names在独立 operation namespace唯一；每个 effect的 own
`declared_operations` name唯一。Trait associated Type与 method、ability associated item与 operation可因
kind/lookup syntax不同而同 spelling，但不能跨各自上述 namespace冒充。Duplicate在 declaration
publication/impl matching前确定性拒绝；effect conformance中来自不同 ability或 own declaration的同名
operation仍只按下述 exact-signature merge rule处理，不算 declaration内 duplicate。

每个 `TraitGoalV1` occurrence先通过同一 global WF：`trait` 必须解析为 exact
`TraitV1 -> TraitDeclarationV1`，`arguments` 的 arity/kind恰等于 trait source binders，`target`是当前
scope中的 Type；`associated_types` 是 partial equality map，按 item ordinal严格递增、
unique/in-range，`declaration_name` exact equal对应 zero-arity associated Type，value kind=Type。
Unknown/duplicate/wrong-name/wrong-kind equality不得因该 goal出现在 impl、constraint或 method scope而改变规则。
`AssociatedTypeDeclarationV1.constraints` 是逻辑 conjunction，因而每个 goal先做上述 normalization，
再按完整 semantic goal的 NFC+JCS bytes严格递增且无重复；source constraint order不得改变
artifact bytes。Associated normalization cycle/termination在此 sort前检查。

`DeclarationRequirementsV1` 是 source generic requirement、trait-method lexical scope唯一的
owning-trait Self seed，及其 ordinary-trait associated-constraint entailment closure的唯一 successor
wire projection，不是可由 importer重建的注释。
`ordinary_traits` 中 `origin=SourceTraitRequirementV1` 的 row恰是 source constraints；对每个这样的
normalized goal，producer把 resolved trait每个 associated Type的 declared constraints用该 goal的
target/arguments/associated hidden vector做 capture-avoiding substitution，生成
`AssociatedConstraintEntailmentV1(parent,item,constraint)` row，并递归到 fixed point。Derived row的
`binder_slot` 恰是 parent `associated_types[item].binder_slot`；source row的 `binder_slot` 必须解析为
enclosing `DeclarationBindersV2.type_binders` 中 kind=`Type` 的 source binder。两者的语义 target都恰是该 slot的
`TypeParameterV2`。

每个 `TraitMethodSignatureV1.requirements` 还必须恰含一个
`origin=OwningTraitSelfV1` root。它的 `binder_slot` exact等于 enclosing
`TraitDeclarationV1.self_binder_slot`，`trait` exact等于 enclosing trait identity，`arguments` 是该
trait全部 source Type binder的同序 `TypeParameterV2` vector；`associated_types` exact覆盖 enclosing
trait全部 associated Type，并把 `binder_slot` 指向对应 `AssociatedTypeDeclarationV1.binder_slot`、
`equality` 写为同一个 `TypeParameterV2`。这个 root不是 source-spelled supertrait，也不进入
`TraitDeclarationV1.requirements`；它只表达 trait method lexical scope中已知的
`Self : OwningTrait[args, Assoc = Self::Assoc...]`，使 sibling method call与 associated-Type declared
constraint有唯一 evidence root。Free/inherent/extension/impl/operation requirements不得伪造
`OwningTraitSelfV1`。

Closure先在不含任何待分配 slot/ordinal的 semantic graph上完成。
`RequirementPreallocationKeyV1` 包含 target semantic binder（source row为 source binder identity，
owning-Self row为 enclosing trait identity + Self structural binder identity，derived row为
`parent semantic key + associated item ordinal`）、resolved trait identity、positional arguments、
explicit/derived associated equality vector，以及递归展开的 derivation path semantic keys（不含
`parent_requirement_ordinal`）。同一 normalized goal经多条路径可达时，只保留 domain order
`Source < OwningTraitSelf < AssociatedDerived`、再按 derivation-path NFC+JCS bytes最小的路径；两个显式 source
duplicate仍拒绝。Goal-key/derivation cycle、不终止或无限 closure在 slot allocation前拒绝。
完成 closure后按 prekey严格递增排序，分配 exact连续
`requirement_ordinal=0..n-1`，再把 derived origin的 `parent_requirement_ordinal` 回填为已排序 parent；
decoder必须重建该 graph并 exact复算这些值。

`effect_parameters` 对每个 source `F`/`F[_]` binder恰有一项，其 slot必须解析为
enclosing `M3(DeclarationBindersV2)` 中 atomic `Effect` 或 `EffectConstructorBinderV3`；
`constructor_arity` 分别为 0/underscore count并与 binder exact交叉核对，不会把 higher-kinded
constructor信息丢掉。Effect-parameter rows按其不含 allocated slot的 semantic key严格递增，每个
effect parameter的 `abilities` 也按相同 key严格递增。`constructor_arity > 0` 时 `abilities`
必须为空：本 profile没有 `F[_] : Ability` 的 pointwise higher-kinded evidence；只有 arity 0
的 atomic `F` 可携带 ability requirements。所有 method-use用 final requirement ordinal消除同一
binder/trait不同 arguments或 derived path的歧义。同一
effect binder的 `abilities` 中同一个 resolved ability identity最多出现一次，即使 arguments不同也
拒绝第二项；否则 `F::operation` 没有唯一 evidence selector。同一 source constraint重复出现不是 dedup hint，而是 declaration
WF failure。Trait/ability identity必须从 exact package declaration closure解析，generic arguments
kind/arity exact。`GenericTraitRequirementV1.associated_types` 是 resolved trait全部 zero-arity Type item
的 total ordinal vector。`SourceTraitRequirementV1` 与
`AssociatedConstraintEntailmentV1` 的每项各有一个 deterministic requirement-hidden Type binder；source
row的显式 named equality写入 `equality`，omitted为 `null`，derived row则写入 associated constraint
goal实例化后的 exact equality/null。`OwningTraitSelfV1` 是唯一例外：它不再分配 binder，而是逐项复用
已经分配的 enclosing `AssociatedTypeDeclarationV1.binder_slot`，并按上文写入同 slot的 exact
`TypeParameterV2` equality。
Trait method evidence不在这里伪装成一个 monomorphic binder；每个实际
method invocation由下述 `TraitMethodUseEvidenceV1` 单独实例化。Unknown、duplicate、wrong-kind或缺项
使用 `associated-contract-mismatch`。Generic ability 的 `associated_items` 是 ability全部
associated item的 total ordinal vector，按 declared kind指向 deterministic hidden Type/Effect/Row
binder；source partial explicit map只写入 nullable `equality`，omitted保持 symbolic。Concrete
`AbilityConformanceV1.associated_arguments` 则是应用 default 后的 total vector，必须恰含 ability
每个 associated item一次。两种 context 都要求 ordinal、name、value tag与 declared kind exact。
`RowParam` 不另复制 companion field：每个 source `..E` 与其完整 `Lacks` set已由 enclosing
`DeclarationBindersV2.row_binders` 一一保存并交叉核对。

Hidden evidence allocation对每个 declaration scope与每个 namespace只运行一次，并使用同一个
noncircular顺序。先保留全部 explicit source slots；再分配 declaration-structural slots（trait 的
Self、own associated Type，或 ability 的 own associated item，均按 item ordinal）；随后把
ordinary-trait associated Type、generic-ability associated Type/Effect、generic-ability associated Row
按 `(domain order OrdinaryTraitV1 < AbilityV1, RequirementPreallocationKeyV1, item ordinal)` 排序，
其中 OrdinaryTraitV1 只含 `SourceTraitRequirementV1` 与
`AssociatedConstraintEntailmentV1`；`OwningTraitSelfV1` 已复用 structural slots，绝不进入这个待分配
集合。在对应 Type/Row namespace从当前最大 slot加一连续分配。Contract namespace先保留显式/source
contract slots，再按 normalized-HIR lexical application preorder为每个 direct trait-method call分配
一个 `FunctionContractBinderV2`；同一 method在两个 type instantiation或两个 call site出现时是两个
slot，不共享一个伪多态 contract。任何 visitor/map/source constraint顺序不得改变 slot。
每个 call-site binder的 parameter/result/visible-row是 `TraitMethodSignatureV1.declaration_kind` 对
Self、trait arguments、total associated hidden vector及该 call的 method-local substitution后的 exact
monomorphic值。Allocator collision、u32耗尽、wrong-kind slot或 companion↔binder drift都在进入
application前拒绝。

Data/trait/ability/effect 的 `requirements` 恰是各自 `TypeHead TypeParams` 的 normalized projection；
impl 的同名 field恰是其 own `GenericClauses` projection；`TraitMethodSignatureV1.requirements` 则恰为
method-own `GenericClauses` 的 source roots、唯一 `OwningTraitSelfV1` root与由两者重算的 associated
constraint closure；operation
只有 unconstrained `OperationTypeParams`，其 `requirements` 恰是两个 empty arrays；
`CallableContractFactEvidenceV1.requirement_scopes` 则保存下述每个 root/local scope的 complete lexical
closure。`ImplEvidenceV1.header`
恰是 source impl header 的一个 normalized `TraitGoalV1`；其 `trait`/`target` 必须分别 exact equal
sibling `ImplEvidenceV1.trait/target`，arguments与 source-spelled associated equality不得省略、漂移或藏进
`requirements`。`header.associated_types` 是 source header equality的 partial map，必须按 item ordinal
严格递增、unique/in-range，`declaration_name` exact equal trait item，且每项 value exact equal
`ImplEvidenceV1.associated_types[item_ordinal].value`；未在 header显式出现的 item才由 impl body或 trait default
完成。该 partial→total cross-check在 `ImplPreidentityKeyV1`、evidence ordinal 与 coherence overlap计算之前完成。
Package-private/local declaration在 typed HIR 中保留同一 requirement set直到
每个 application选定 exact impl/callable evidence；它们必须在 producer内全部 discharge并降为
direct typed edges，不能靠 importer source重建。对所有 scope（包括 local declaration、lambda 与
允许的 local rank-1 scheme），Surface把普通 trait requirement唯一结构化为上述 hidden
associated-type binder；每个 direct method use再产生一个 monomorphic call-site
`FunctionContractBinderV2`。Generic application用 impl的 associated type与该 method callable exact
填充 `TypeSubstitutionV2`/`ContractSubstitutionEntryV2`。所以 local/nested requirement即使不另存
source trait name也没有丢可执行 evidence：其每个实际 use已在 binder/substitution中；
unresolved或 partial substitution稳定 `callable-interface-contract-mismatch`。Exported root
callable 的 open requirements则必须完整写入其 package-level
`CallableContractFactEvidenceV1.requirement_scopes` 并与 V3 root/local binder table交叉核对；这保持 R6 的 exact
`FunctionContractV3` field set不变，同时不丢 generic API fact。

`TraitDeclarationV1.binders` 先含 source Type binders，再分配一个 `self_binder_slot`，随后按
associated-type ordinal分配每个 `AssociatedTypeDeclarationV1.binder_slot`，最后才按上述 prekey分配
trait自身 TypeHead constraints导出的 hidden requirement slots；这些部分在同一 Type namespace连续且互异，
对应 hidden binder的 kind都为 Type。Trait declaration内的 `Self`、`Self::Item`、
associated constraint target/equality/default与 method signature全部分别改写为这些
`TypeParameterV2` slot，不能保留 source projection或猜 short name。`TraitMethodSignatureV1.binders`
以该完整 trait binder table为 lexical prefix，再追加 method自己的 explicit generic binders，最后按
同一 combined allocator追加 method-own requirements导出的 hidden slots；impl evidence以
target替换 Self slot、以 exact `AssociatedTypeBindingV1`/default替换每个 associated slot，缺失、重复、
wrong ordinal/name或未关闭 constraint都在载入 impl method前拒绝。

`TraitMethodSignatureV1` 是 required/default trait method共有的 signature-only contract；它不要求
也不伪造 executable computation。`default_body=null` 表示 bodyless required method；非 null edge
必须载入一个 `CallableInterfaceV1 -> FunctionContractV3`，其 surface signature、declaration kind、
method-own source requirements、上述唯一 owning-Self root与 derived closure都与本 signature exact equal；其 callable fact还必须加入
enclosing trait lexical requirements。

`TraitDefaultPrologueProgramV1` 是该 signature中唯一 executable 的局部子程序，不是 method body。
`root_declaration_slot` 必须为 0，root binder table恰为 sibling `TraitMethodSignatureV1.binders`；
`requirement_scopes[0]` 恰为 owning `TraitDeclarationV1.requirements` 与
`TraitMethodSignatureV1.requirements` 的 `CompleteCallableRequirementsV1` closure，不能只复制 method-own
array。`local_declarations` 按 lexical preorder连续分配
`1..n`。`callable_dependencies`、`applications`、`closure_environment`、
`requirement_scopes` 与 `trait_method_uses` 共同对每个 default computation及其 reachable local/lambda
closure做 exact closure：每个 ref used且 in-range，没有 orphan/missing/foreign table entry；scopes exact-cover
root与每个 local declaration，trait-method use按 application slot与 requirement ordinal交叉核对。所以
bodyless signature的 default仍可合法调用 module callable、创建 local lambda、并使用 enclosing/method-own
ordinary-trait requirement，不依赖未存在的 body fact。这些 dependency edges参与同一
callee-before-caller DAG 与 package support closure。

Signature-level `default_prologues` 按 parameter slot严格递增，只能对应
`surface_signature.defaultable=true` 的 named slot；其 scope恰含 module/generic facts与此前已完成的
simple parameter，求值 order与 ordinary callable default rule相同。
`ProjectTraitDefaultProgramV1(V3,fact)` 从 concrete default/impl callable的 `V3.default_prologues`为 roots，
只取可达 dependency/local/application/environment/scope/method-use closure，然后按独立 program的
lexical/callee-before-caller规则重新分配局部 slots。Trait default callable在 generic trait scope中的该 object
必须 raw exact equal `TraitMethodSignatureV1.default_program`。Explicit impl callable则先用当前
`ImplEvidenceV1.header` 的 trait arguments/target与 completed `associated_types` 对 signature program做与
method signature相同的 capture-avoiding Self/trait/associated substitution（method-own generic binders仍保持为 scheme），
得到 `InstantiateTraitDefaultProgramV1(signature,impl)`；重排 slots后的 projection必须与该 instantiated
NFC+JCS object exact equal。Body-only entries不得混入 projection，同一语义也不得用另一套
slot/hash编码。Bodyless method因此仍有完整 call-assembly semantics而没有伪造 body。
Explicit impl method不能另写或改变 parameter default；其 concrete callable必须投影为该 exact-instantiated program。
Impl method仍由 `ImplMethodBindingV1` 从 method ordinal
指向自己的 concrete callable。因此 bodyless trait declaration、default implementation与 impl body
是三个不同 identity/evidence role，不能用空 computation互换。

`ImplEvidenceV1.associated_types` 与 `methods` 都是 trait item ordinal的 total vector。每个 associated
Type优先采用唯一 explicit impl binding；若没有则采用 declaration的 non-null `default_type`；两者皆无
即拒绝。每个 method同样优先采用唯一 explicit impl body；否则采用 trait declaration的 non-null
`default_body`；两者皆无即拒绝。`source` 必须精确记录所选分支，default分支的 value/callable必须
exact equal trait artifact，explicit分支必须来自当前 impl；header中的每个 explicit associated equality还必须
exact equal这个 completed vector的同 ordinal/name/value。Unknown/duplicate/extra item、同一 item同时
给两个 explicit binding/body、required item遗漏或 default漂移都在 coherence publication前拒绝。

每个 completed associated binding（explicit 或 trait default）还必须对 declaration的每个
`AssociatedTypeDeclarationV1.constraints[k]` 运行 `AssociatedConstraintProofV1`：先用当前
impl target/trait arguments/完整 associated vector实例化并 normalize该 goal。若当前
`ImplEvidenceV1.requirements.ordinary_traits` entailment closure中有恰一个 semantic-equal row，则使用该
local generic proof；否则在 exact package/import roots中选择恰一个 coherent applicable
`ImplEvidenceV1`，并递归证明它的 own requirements。Current-package selected evidence必须由 fixed-point
加入 resolver-hidden/public evidence edge，foreign evidence必须来自 matching locked import root；重算的
identity/header/associated bindings必须 exact。Local proof优先于 global impl，全局 coherence保证后者至多一个。
以 normalized goal key建立 proof dependency graph，cycle/nontermination/no proof 均在发布当前 impl前拒绝。
因为该 selection 是由 normalized goal + exact package graph唯一复算，wire不再嵌一个会与
`EvidenceIdentityV1.ordinal` 分配形成循环的自申报 proof vector。
方法 callable的 lexical binders、requirements、surface slots、result/row与 declaration kind必须在
Self/trait arguments/total associated substitution后逐字段等于 `TraitMethodSignatureV1`；generic method
保持 method-local scheme binders，不能预先单态化或用另一个 free callable冒充。

`AbilityDeclarationV1.binders` 先含 source Type binders，再按 associated-item ordinal为每个 item
确定分配 hidden binder：Type/Effect item进入对应 kind的 type-binder namespace，EffectRow item进入
row-binder namespace并携带其唯一允许的 `Lacks` set；item的 `binder_slot` 必须指向该 exact hidden
binder；随后才按 prekey分配 ability自身 TypeHead constraints导出的 hidden requirement slots。没有
ability inheritance或隐式 parent closure。`OperationDeclarationV1.binders` 是 enclosing
declaration lexical binders（含这些 hidden associated binders）加 operation自身 source Type binders的
complete scope；operation-own Type binders全部 unconstrained，不追加 requirement-derived hidden slots；
`signature.type_binders` 必须与其中 type-binder table exact equal，signature内所有
type/row/identity reference都在该 complete scope重做 WF。Operation parameter surface slots与
signature parameters一一对应且 `defaultable=false`。更精确地，operation不允许
`ImplicitReceiverV1`；每个 source simple parameter唯一产生
`NamedOrPositionalV1(public_label=source name,defaultable=false)`，每个 irrefutable pattern parameter唯一
产生 `PositionalOnlyV1`。Surface slots、`binders.parameter_binders` 与
`OperationSignatureV2.parameters` 三个 vectors必须在 slot set、declaration order与 instantiated type上
逐项 equal；slot缺失/重复/reorder、receiver、label/default或 type drift都在 operation publication前拒绝。
Operation自己的 `requirements` 必须 exact为
`{ordinary_traits:[],effect_parameters:[]}`；它不能声明 ordinary-trait constraint、
Effect/constructor/Row generic或 parameter default。这样 performed/forwarded/latent operation site不需要一个
`OperationSignatureV2` 中并不存在的 contract-evidence substitution edge。

`EffectDeclarationV1.declared_operations` 只保存 source body declarations；完整 operation environment
是它们与所有 `conformances` 所引用 ability operations在 total associated substitution后的 deterministic
union。Conformance按 resolved ability identity的 NFC+JCS bytes严格递增、无重复；同名 operation只有
在 `InstantiatedOperationComparisonV1` 中的完整 declaration contract exact equal才合并。该 view先把
ability parent Type/associated binders用当前 `AbilityConformanceV1` 的 arguments/associated bindings
capture-avoiding substitute到 effect lexical scope，再把 operation-local Type binders按它们的 declaration order
连续分配到 effect prefix之后，重写 requirements/surface/Core signature中的所有 refs。Effect own
declaration按同一 prefix/local allocator normalization；两边 name必须相同，只忽略各自 declaration-local
operation ordinal。然后比较 `binders`、
`requirements`、`surface_signature` 与 `M3(OperationSignatureV2)` 的每一 field（parameters/result、
mode、secondary sites/row、transition、result transformer、world/suspension、required phase、obligation IDs）
都必须相等；不得直接比较两个不同 enclosing scope的 raw slot numbers，也不得仅比较 surface shape，
否则 `effect-header-conformance-mismatch`。Effect family arity恰是其 source Type binder数。
Successor producer/importer只能从 package graph中 exact-decoded `EffectDeclarationV1` 得到 nominal
Effect identity、arity与 operation table；retained `EffectFamilyDeclarationsV1` 仅是 profile-disjoint
TR0 fixture，不能成为 Cire-v1 declaration environment。

`CompleteCallableRequirementsV1(c,d)` 对 root/local declaration slot $d$ 由 lexical owner与 callable
source role确定，不能只取 method自己的
`GenericClauses`：free/inherent/extension使用 own requirements；trait default使用 owning trait
requirements与 `TraitMethodSignatureV1.requirements` 的 union；impl method使用 owning
`ImplEvidenceV1.requirements`、该 trait method requirements在 Self/associated/header substitution后的
projection与 method own requirements的 union；manifest adapter没有 source/generic/local declaration，
其 root scope必须 exact为 `{ordinary_traits:[],effect_parameters:[]}`、`local_declarations=[]`、
`trait_method_uses=[]`。Union先按 lexical parent→method顺序解析 binder scope。
Generic trait signature/default scope保留 signature中唯一 `OwningTraitSelfV1` root；其它 role不得产生它。
随后只取各输入 `SourceTraitRequirementV1` roots、该 optional owning-Self root与 effect-parameter roots，再在合并后 scope上重跑完整
associated-constraint entailment fixed point；不直接 union两组已分配 parent ordinal的 derived rows。
随后以 `RequirementPreallocationKeyV1` 排序并重分配本 callable closure内连续
`requirement_ordinal`，同时重写每个 derived parent link；相同 semantic source requirement exact dedup只在它来自
parent与required signature的同一 source obligation时允许，其余 source duplicate仍拒绝。每个 row保留原 binder slot，因而同 shape但
不同 parent identity不能合并。`requirement_scopes` 必须按 declaration slot严格递增并 exact覆盖 root slot
与每个 `LocalFunctionDeclarationV3.declaration_slot`（empty closure也保留一项）；每项 requirements必须
exact equal `CompleteCallableRequirementsV1(c,d)`，并与该 declaration可达的 hidden binders/uses双向
exact。Nested local/lambda scope继承其 lexical parent仍 live的 requirements，再加入 own
`GenericClauses`，按相同 prekey重排并只在该 scope内重分 requirement ordinal；相同 slot number跨
declaration不 alias。Package-private/local producer
使用同一 closure算法但在 enclosing boundary内 discharge。这样 trait default/impl body可引用 parent
`A: Eq`，而 importer不重读 parent source。

`ManifestAdapterCallableV1` 的 `CallableContractFactEvidenceV1.requirement_scopes` 因而必须恰为一项
`{declaration_slot:0,requirements:{ordinary_traits:[],effect_parameters:[]}}`，并与 adapter V3 的
`root_declaration_slot=0`/empty binders exact交叉核对；missing/extra scope、local/lambda、trait use或任一
generic binder都拒绝，不能借 generated status跳过 complete-scope gate。

将 trait signature/default program实例化到某个 exact `ImplEvidenceV1 I` 时，
`OwningTraitSelfV1` 不作为 open requirement复制到 concrete impl callable：它必须由 $I$ 的
trait/target/header/total associated vector exact discharge。所有以该 root选择 sibling method的
`TraitMethodUseEvidenceV1` 都改写为 `I.methods` 中对应 ordinal的唯一 concrete/default callable edge；
所有由该 root派生的 associated-constraint row都改写为 `AssociatedConstraintProofV1` 选中的 exact
local requirement或 package/import impl evidence。完成改写后 synthetic Self root及只服务于它的 generic
use row从 concrete scope消失；missing/wrong impl、method inverse link、associated proof或仍悬空的
`OwningTraitSelfV1` 一律 `callable-interface-contract-mismatch`。因此 generic trait body可以对 `self`
调用 sibling required/default method，也可使用 `Self::Assoc : Bound`，而 concrete impl仍没有伪造的
open Self obligation。

`CallableContractFactEvidenceV1.identity.kind` 必须为 `ProtocolEvidenceV1`，其 package与顶层
`package` exact equal；`callable` 必须 exact equal package root中的一个 callable edge，并且
每个 edge恰有一个这样的 evidence edge。对 source-backed kind，`visibility` exact等于 source
declaration；manifest adapter没有 source declaration且固定 `PackageV1`。只有
`PublicV1` fact进入 dependent source resolver，`PackageV1` fact只作为 semantic support。Trait default/
impl body support fact固定 `PackageV1`，由 trait/impl method selection间接到达，不产生独立 source name。
`declaration_kind` 是 method lookup所需的完整
public classification：free callable不进入 dot lookup；inherent owner必须是当前 package拥有的
`TypeV1` nominal，且 declaration kind只能是 `StructV1 | EnumV1 | NewtypeV1 | OpaqueV1`；
`TransparentAliasV1` 已在 M3/type serialization前展开，绝无 inherent-owner identity。
`receiver=null` 表示 qualification-only associated function，否则 receiver必须与
首个 `self` slot exact；extension receiver必须与其 mandatory首个 `self` slot exact；trait-method
default identity/ordinal必须回指同 package closure的 `TraitDeclarationV1.methods`，impl method还必须
回指 exact `ImplEvidenceV1`；其 nullable receiver同样区分 associated function与 method。Importer不得从
export-path spelling、file path或 source text猜
这些 facts。Manifest adapter是唯一非 source declaration的 callable kind；它只能由 component manifest
import反向证明，不能伪装 free callable，并固定 `const_safety=RuntimeCallableV1`、
`protocol_purity=OrdinaryCallableV1`；其 `trap` 仍从 exact host contract/trap policy重算。
其它 kind的 `const_safety=ConstSafeV1` 当且仅当 declaration是 `const def` 且通过 ConstSafe；
`protocol_purity=ProtocolPureV1` 当且仅当 sealed standard-protocol obligation成立；`trap` 是完整
MayTrap join。三者互不推出，也不能从空 row猜测。

每个 included `ComponentManifestV1.imports` row还唯一产生一个 resolver-hidden manifest-adapter
callable edge与 `PackageV1` fact。它是 generated wire class，不是第 22 种 accepted source declaration；
没有 source `def`，也不会进入 value namespace collision或 ordinary method lookup。其
source/classification只按下述 manifest preidentity与 post-hash inverse link建立。

`source_identity` 与 `declaration_kind` 是 closed bijection，并唯一生成 callable edge：

```text
CanonicalCallableExport(FreeSourceV1(D))      = (D.module, D.path)
CanonicalCallableExport(ExtensionSourceV1(D)) = (D.module, D.path)
CanonicalCallableExport(InherentSourceV1(O,m))
  = (O.module, O.path ++ [m])
CanonicalCallableExport(TraitDefaultSourceV1(T,k))
  = (T.module, T.path ++ ["~trait-default-v1", CanonicalNatSegment(k)])
CanonicalCallableExport(ImplMethodSourceV1(I,k))
  = (CanonicalSourceModuleV1(I.package),
     ["~impl-method-v1", ImplHeaderDigestV1(I), CanonicalNatSegment(k)])
CanonicalCallableExport(ManifestAdapterSourceV1(n,h,w,s))
  = (["pkg-" + P.digest, "~component-import-v1", n], s)
```

`CanonicalNatSegment` 是无前导零 decimal u32。`ImplHeaderDigestV1(I)` 是 owning
`ImplEvidenceV1` 的
`SelfRelativeV1(I.package,{package:I.package,binders,requirements,header})` NFC+JCS bytes SHA-256，
刻意不含
identity ordinal、method callable/hash或 source location，因而没有 identity/hash cycle；coherence在
此 digest前已拒绝相同 normalized header。Free/extension source declaration必须是当前 package的
`ValueV1` identity；inherent owner必须是当前 package未实例化的
`StructV1 | EnumV1 | NewtypeV1 | OpaqueV1` declaration，不得是 `TransparentAliasV1`，source
`FunctionOwner`不能带 TypeArgs；trait default与 impl method分别只允许对应 kind。Fact的 callable
`(module,export_path)` 必须 exact等于此函数结果，反投影也必须回到唯一 source identity。Reserved
`~trait-default-v1`/`~impl-method-v1`/`~component-import-v1` segments不属于 user identifier grammar。
Manifest adapter case中的 $P$ 是 fact owning package，$n$、$w$、$s$ 是 manifest name、nonempty import
`wit_path` 与 explicit `source_binding`；$(P,n,w,s)$ preidentity决定 callable module/export，绝不读取 $h$。完成
`ComponentManifestV1`（它已经包含该 callable edge）并求 hash 后，producer才把 final hash写入
`ManifestAdapterSourceV1.manifest_hash` 与 matching
`ManifestAdapterCallableV1.manifest_hash`。两者的
`(manifest_name,manifest_hash,wit_path,source_binding)` 必须 exact
equal，并唯一反向定位 package root中一个 manifest及其中一个 import；hash/name/path drift、missing或
multiple inverse link都拒绝。这样没有 `manifest_hash -> callable edge/interface/V3 -> manifest_hash`
cycle。
`FreeSourceV1.declaration`/`ExtensionSourceV1.declaration` 的 `ValueV1` object在这里是 source
namespace key，不进入 `PackageDeclarationEdgeV1`；只有实际出现在 declarations array中的 `ValueV1`
identity才由 closed dispatcher指向 `ConstDeclarationV1`。两者共享 collision domain但不共享 artifact role。

同一 package 的 source value namespace在 declarations/callables之间全局唯一：`ValueV1` const的
`(module,path)` 与 free/extension callable的 canonical key不能相等，free与 extension也不能共享一项；
inherent/default/impl reserved paths仍参与全局 `(module,export_path)` uniqueness。碰撞统一稳定
`public-overload-requires-distinct-export-path`，不能靠 declaration-vs-callable array或 receiver type分流。
每个 non-null trait `default_body` 必须被恰一个 `TraitDefaultCallableV1` fact反向引用；每个
`ImplMethodBindingV1{source=ExplicitImplMethodV1}` 必须被恰一个同 impl identity/ordinal的
`ImplMethodCallableV1` fact反向引用；default-selected impl item直接引用 trait default edge，不创建第二
impl-body fact。每个 manifest import同样必须被恰一个 `ManifestAdapterCallableV1` /
`ManifestAdapterSourceV1` fact反向引用，且其 callable edge就是 manifest item；adapter fact固定
`visibility=PackageV1`，永不进入 source resolver或 dot/UFCS candidate。Missing、extra或多重 inverse
link一律拒绝。

`trait_method_uses` 按 `(declaration_slot,application_slot)` 严格递增，并 exact覆盖该 V3 root及全部
`local_declarations` 中每个经 ordinary-trait evidence解析的 direct method application；其它 call不在
此 array。每项先用 `declaration_slot` exact定位 `requirement_scopes` 中一项，再用
`requirement_ordinal` 定位该 scope的 `requirements.ordinary_traits` 中一项，并且
`target_type_binder_slot` + trait与该 row exact equal；它可直接选中 source row，也可选中由
associated-Type constraint entailment生成的 derived row，后者的 origin/parent/item/constraint 必须已在同
requirement closure内 exact验证。
method ordinal定位该 trait declaration；`method_instantiation` 对 method自己的 Type/Effect/Row/
contract binders total、kind-correct且与同 application的 substitution逐项 equal。`contract_slot` 必须
解析到 containing declaration的唯一 `FunctionContractBinderV2`，其 kind等于 trait signature在
Self、trait/associated facts与本 method instantiation后的 monomorphic kind；该 application的 callee
必须是此 `ContractParameterRefV2`。在 enclosing callable应用时，impl evidence选出的 generic method
callable进入该 slot的 `ContractSubstitutionEntryV2`，method application再用自己的完整 substitution
实例化 concrete callable；结果 kind必须 exact equal call-site binder。同一 generic method以不同 type
argument调用会有不同 use row/contract slot；不允许 method value逃入 field/parameter/result或以一个
共享 monomorphic slot伪装 rank-2 evidence。Missing/extra/reused use、wrong method/impl、partial
substitution或 application↔slot drift稳定 `callable-interface-contract-mismatch`。

对每个 public declaration/callable/impl 定义有限 `OutwardSurfaceClosureV1`：

- 所有 public data/trait/ability/effect declaration 的 own `DeclarationRequirementsV1`；
- public alias target，public struct/newtype/record-variant中每个 public stored field的
  type/default，以及 public enum的每个 tuple-variant element；hidden stored field不进入 outward set；
- public trait associated-Type constraint/default、method binders/requirements/parameter/result/row/surface labels；
  default-program 内部 dependency/body-only type不因此自动对 source可见；
- public ability的 associated item default/constraint 与每个 operation完整 surface/signature/requirements；
  public effect的 conformance ability/arguments/associated bindings与每个 declared/merged operation完整 contract；
- public callable的 parameter/result/defaultable/row/generic requirement/direct-capability surface facts，public const的
  type/value，以及 importer-visible impl的 header/requirements/associated binding/method signature facts。

该 closure的 transitive type/evidence reference都只能指向 public 或 exact-importable identity；任一
package-private type/evidence泄漏使 package interface WF失败。Resolver-hidden `PackageV1` support
closure只能验证 serialized computation/default/body的内部 reference，绝不能使 outward occurrence合法化。
Public data的 postfix derive trait identity本身不是 source-visible type/signature occurrence；它若指向
package-private trait，对应 `DerivedImplV1` 与 trait artifact只能进入 resolver-hidden support closure，
不使下游可命名该 trait。只有下述 importer-visible impl predicate成立时才发布为 public coherence fact。
`OpaqueTypeV1` 的 public artifact 只导出 nominal identity、binders与 public trait/operation facts，
且 `representation` 必须 exact为 `null`；owner-package-private declaration payload中该 field必须为
non-null representation。Reachable package-private declaration可作为上述 support edge进入
`CireLanguageInterfaceV1.declarations`，但 visibility gate使它只参与已序列化 Core的 WF，不可被依赖
source命名；unreachable private payload不进入 root。Public opaque的 `representation`
不进入 importer declaration edge、
const value、Component type mapping 或 diagnostic note。Importer不得用 layout/link artifact反向揭示该
representation。

`derives` 是 source postfix `} derive(Trait, ...)` 经 resolve 后的 declaration identities，按
source order且无重复；它只允许 `StructV1 | EnumV1 | NewtypeV1`，
`OpaqueTypeV1 | TransparentAliasV1` 的 `derives` 必须 exact为 `[]`。Prefix attribute 或另一 derive spelling不进入 HIR。每个 derive 必须产生
恰一个 `DerivedImplV1`，其 origin是 `SealedIntrinsicV1`，并通过普通 orphan/overlap gate。
Handwritten与 derived 的同一 `(trait,target)` 是 overlap。组件 adapter 不产生 `DerivedImplV1`
也不进入 source origin DAG；其 provenance只来自下述 manifest edge。

每个 `CireLanguageInterfaceV1.callables` member（public或 resolver-hidden support）必须有恰一个
`CallableContractFactEvidenceV1` package evidence，其 `callable` object与该 edge exact equal；只有未被
closure收录成 edge的 private/local callable，其同一 fact才由 typed computation在 enclosing declaration
boundary内计算并在所有 local use discharge。该 evidence是 package-level ordinary contract fact，不是
`FunctionContractV3` 的第 13 个 field，也不改变 CallableInterface→V3 edge。
