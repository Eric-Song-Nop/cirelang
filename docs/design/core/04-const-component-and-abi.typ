#import "../shared.typ": *

== Const exact value 与 Component manifest <const-component-wire>

```text
ConstScalarV1 =
    { kind: "UnitConstV1" }
  | { kind: "BoolConstV1", value: Bool }
  | { kind: "SignedIntConstV1", width: 8 | 16 | 32 | 64,
      twos_complement_be: [u8] }
  | { kind: "UnsignedIntConstV1", width: 8 | 16 | 32 | 64,
      magnitude_be: [u8] }
  | { kind: "FloatBitsConstV1", width: 32 | 64, ieee_be: [u8] }
  | { kind: "CharConstV1", unicode_scalar: WireU32V1 }
  | { kind: "StringConstV1", utf8: [u8] }
  | { kind: "BytesConstV1", octets: [u8] }

ConstValueV1 =
    { kind: "ScalarConstV1", scalar: ConstScalarV1 }
  | { kind: "TupleConstV1", elements: [ConstValueV1] }
  | { kind: "ArrayConstV1", elements: [ConstValueV1] }
  | { kind: "BuiltinVariantConstV1",
      constructor: "OptionV1" | "ResultV1",
      variant: "NoneV1" | "SomeV1" | "OkV1" | "ErrV1",
      fields: [ConstValueV1] }
  | { kind: "NominalConstV1", declaration: DeclarationIdentityV1,
      variant_ordinal: WireU32V1 | null, fields: [ConstFieldValueV1] }

ConstFieldValueV1 = { ordinal: WireU32V1, value: ConstValueV1 }

ConstDeclarationV1 = {
  artifact: "ConstDeclarationV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  identity: DeclarationIdentityV1,
  visibility: VisibilityV1,
  type: M3(TypeRefV2),
  value: ConstValueV1,
  evaluator: "CireConstEvaluatorV1"
}

ComponentItemRefV1 =
    { kind: "CallableComponentItemV1", callable: PackageCallableEdgeV1 }
  | { kind: "DataComponentItemV1", declaration: DeclarationIdentityV1 }
  | { kind: "ResourceComponentItemV1", declaration: DeclarationIdentityV1 }

ComponentImportV1 = {
  wit_path: [NfcSegmentV1],
  source_binding: [NfcSegmentV1],
  item: ComponentItemRefV1,
  generated_capability: DeclarationIdentityV1
}

ComponentExportV1 = {
  wit_path: [NfcSegmentV1],
  item: ComponentItemRefV1
}

ComponentManifestV1 = {
  artifact: "ComponentManifestV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  package: PackageInstanceIdV1,
  name: NfcSegmentV1,
  imports: [ComponentImportV1],
  exports: [ComponentExportV1]
}
```

`StoredFieldV1.default_value` 直接内嵌已求值的 `ConstValueV1`，不是指向一个不存在的 hidden
`ConstDeclarationV1`。Producer在 enclosing data declaration的完整 binder scope下，以 field type检查
source default，再用 `CireConstEvaluatorV1`求值得到该 value；generic parameter可出现在 expected type，
但 value本身只能是对任意合法 instantiation都相同的 parametric const constructor（例如 `None`），不能
读取或 case-analyze未知 type。Importer用同一 field type/binders重验 value shape。没有 hidden const
identity、额外 package declaration edge或 bare hash；default presence/value变化直接改变 data artifact/API
hash。

`ConstValueWF(expected,value)` 是每个 `ConstDeclarationV1.value` 与 `StoredFieldV1.default_value`
的 recursive total judgment，不只检查 outer tag。先展开 transparent alias并应用 enclosing type
substitution：

- scalar branch必须 exact匹配 Unit/Bool/fixed-width int/float/Char/String/Bytes expected primitive；
- tuple/array branch的 length 与每个 child expected type exact；
- `BuiltinVariantConstV1` 只对 `Option[T]`/`Result[T,E]`；None=0 fields，Some/Ok/Err=1 field，
  variant与 payload expected type由 constructor唯一决定；
- `NominalConstV1.declaration` 必须 exact equal expected nominal identity。Struct/Newtype的
  `variant_ordinal=null`，fields必须按 declaration ordinal exact total覆盖所有 stored fields；Enum的
  variant必须 non-null/in-range，unit恰 0 fields，tuple/record payload恰按 element/field ordinal exact total覆盖；
  每个 child在 nominal type arguments substitution后递归通过 WF。

Missing/extra/duplicate/reordered field、wrong declaration/variant/body kind 或 child type drift都在应用 hash/API
comparison前拒绝。`OpaqueTypeV1` 没有不泄露 representation的 const payload branch，因而任何要求
将 opaque expected type序列化为 `ConstValueV1`（public/private const或 field default）都稳定
`const-operation-not-safe`，`offending-operation=serialize-opaque-const-v1`。Runtime opaque value仍可在 owner
package构造/使用，只是不能借 const artifact暴露 representation。对 generic expected type，只接受对每个
legal instantiation都通过该 symbolic judgment的 parametric constructor（例如 `None`）。

`StringConstV1.utf8`、`BytesConstV1.octets` 与 `CharConstV1.unicode_scalar` 是
semantic payload；它们永不编码成 raw JSON string。NFC 只处理 schema/identity string，不能改变
这些 bytes/scalar。String bytes必须是 canonical valid UTF-8但不做 normalization；Char必须是非 surrogate
Unicode scalar；Bytes任意 0..255。Integer/float byte vector长度必须恰等 width/8；NaN只能是对应
width 的唯一 positive quiet NaN encoding。

Component imports/exports 只由 `cire.toml` 选择并生成 `ComponentManifestV1`；source 没有
`extern` keyword。Manifest arrays按 `wit_path` 的 canonical tuple order严格递增且无重复；export
必须指向 package root 已导出的 exact declaration/callable，import必须生成 sealed host effect/capability
identity与 HostObservable callable contract。所有会进入 adapter CallableInterface/V3 bytes的 identity与
origin只由 prehash key
`ComponentManifestPreidentityV1(package,manifest_name,wit_path,source_binding)` 产生；具体是
`ComponentManifestPreoriginV1(package,manifest_name,wit_path,source_binding)`，不是
`ElaborationOriginV1` Derived node。
Final manifest hash只能在 callable interface/hash已经确定后写入 package-level
`ManifestAdapterSourceV1`/`ManifestAdapterCallableV1` fact并形成 post-hash
`ComponentManifestOriginV1(manifest_hash,wit_path)` inverse evidence；它不得回写 V3、CallableInterface、
generated identity或 manifest item，否则形成 hash cycle。

`ComponentManifestPreoriginV1(P,n,w,s)` 到 retained `SourceOriginV1=file:subject` bytes的投影唯一为：
先对每个 segment独立使用 Surface A.12 的 uppercase `%HH` UTF-8 byte escape（仅
`[A-Za-z0-9._@#-]` 不 escape），再令
`file = component-manifest-v1/<P.digest>/<enc(n)>/<enc(w[0])>/...`，
`subject = host-import/<enc(s[0])>/...`，最后以唯一未编码 `:` 连接。$w,s$ 均 nonempty，digest是
lowercase 64-hex；segment内的 `/`/`:` 已被 `%2F`/`%3A`，所以 projection可逆且无另一 split。
Adapter V3/Q/Lambda/Core site只保存这份 preorigin；final manifest hash只存在上述 post-hash fact。

`ComponentManifestV1.name` 必须是可用于 `@alias` 的 exact non-keyword `LowerIdent`，并与该
package lock/import alias set互斥。每个 import的 `source_binding` 是 nonempty source `Name` token vector
（最后一段必须为 `LowerIdent`，不是任意 WIT/kebab segment），在 manifest内按完整 vector injective，且不能使用 compiler-reserved
segment；producer不得从 `wit_path` 猜大小写、escape或分词。Source resolver只把
`@manifest_name::source_binding` 同时登记在 local manifest Value namespace与 Effect namespace；前者指向
generated adapter callable，后者指向其 generated host Effect。这个 projection只对 owning package
source可见，不是 dependency alias或 public package export。

=== Language API、Cire link ABI 与 Component interface 三个 hash root <abi-hash-roots-v1>

`ComponentManifestV1` 只是 target-independent selection；memory、encoding、calling convention与
runtime epoch 不准写入 manifest 或 `CireLanguageInterfaceV1`。目标/runtime-specific
lowering必须另外产生下列 closed roots：

```text
LanguageInterfaceArtifactRefV1 = {
  artifact: "CireLanguageInterfaceV1",
  hash_algorithm: "sha256-jcs-nfc-v1",
  artifact_hash: Sha256V1
}

ComponentManifestArtifactRefV1 = {
  artifact: "ComponentManifestV1",
  hash_algorithm: "sha256-jcs-nfc-v1",
  artifact_hash: Sha256V1
}

CireLinkAbiArtifactRefV1 = {
  artifact: "CireLinkAbiV1",
  hash_algorithm: "sha256-jcs-nfc-v1",
  artifact_hash: Sha256V1
}

CireWasmTargetV1 = {
  validation: "Wasm3.0V1",
  memory: "Memory32V1",
  memory_sharing: "NonSharedV1",
  multi_value: true,
  bulk_memory: true,
  indirect_calls: "OrdinaryV1",
  memory64: false,
  gc_identity: false,
  exception_handling: false,
  native_continuations: false,
  stack_switching: false,
  tail_call_semantics: false,
  simd: false,
  relaxed_simd: false,
  threads: false,
  atomics: false
}

CireCallableLinkEntryV1 = {
  module: PackageModulePathV1,
  export_path: [NfcSegmentV1],
  callable_interface_hash: Sha256V1,
  core_wasm_signature_hash: Sha256V1
}

CireDataLayoutEntryV1 = {
  declaration: DeclarationIdentityV1,
  private_layout_hash: Sha256V1
}

CireLinkAbiV1 = {
  artifact: "CireLinkAbiV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  package_instance_id: PackageInstanceIdV1,
  language_interface: LanguageInterfaceArtifactRefV1,
  compiler_abi_epoch: NfcSegmentV1,
  runtime_abi_epoch: NfcSegmentV1,
  target: CireWasmTargetV1,
  calling_convention: "CirePrivateWasmCallV1",
  callable_layouts: [CireCallableLinkEntryV1],
  data_layouts: [CireDataLayoutEntryV1]
}

ComponentScalarV1 = "BoolV1" | "S8V1" | "S16V1" | "S32V1" | "S64V1"
                  | "U8V1" | "U16V1" | "U32V1" | "U64V1"
                  | "F32V1" | "F64V1" | "CharV1"

ComponentRecordFieldV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  type: ComponentAbiTypeV1
}

ComponentVariantCaseV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  payload: ComponentAbiTypeV1 | null
}

ComponentAbiTypeV1 =
    { kind: "ScalarV1", scalar: ComponentScalarV1 }
  | { kind: "StringV1", encoding: "Utf8V1" }
  | { kind: "ListV1", element: ComponentAbiTypeV1 }
  | { kind: "TupleV1", elements: [ComponentAbiTypeV1] }
  | { kind: "RecordV1", source: M3(TypeRefV2),
      declaration: DeclarationIdentityV1,
      fields: [ComponentRecordFieldV1] }
  | { kind: "RecordPayloadV1", fields: [ComponentRecordFieldV1] }
  | { kind: "VariantV1", source: M3(TypeRefV2),
      declaration: DeclarationIdentityV1,
      cases: [ComponentVariantCaseV1] }
  | { kind: "OptionV1", value: ComponentAbiTypeV1 }
  | { kind: "ResultV1", ok: ComponentAbiTypeV1 | null,
      error: ComponentAbiTypeV1 | null }
  | { kind: "ResourceV1", source: M3(TypeRefV2),
      declaration: DeclarationIdentityV1 }

ComponentTypeMappingV1 = {
  source: M3(TypeRefV2),
  canonical_abi: ComponentAbiTypeV1
}

ComponentParameterAbiV1 = {
  ordinal: WireU32V1,
  name: NfcSegmentV1,
  type: ComponentAbiTypeV1,
  passing: "ValueV1" | "BorrowResourceV1"
}

ComponentImportAbiV1 = {
  wit_path: [NfcSegmentV1],
  source_binding: [NfcSegmentV1],
  manifest_item: ComponentItemRefV1,
  parameters: [ComponentParameterAbiV1],
  result: ComponentAbiTypeV1 | null,
  result_passing: "NoResultV1" | "ValueV1" | "OwnResourceV1",
  generated_capability: DeclarationIdentityV1,
  semantic_summary: "HostObservableV1"
}

ComponentExportAbiV1 = {
  wit_path: [NfcSegmentV1],
  callable: PackageCallableEdgeV1,
  parameters: [ComponentParameterAbiV1],
  result: ComponentAbiTypeV1 | null,
  result_passing: "NoResultV1" | "ValueV1" | "OwnResourceV1",
  owner_policy: "PerCallChildOwnerV1",
  terminal_close_policy: "EveryCireReturnsOrAbortsV1"
}

ComponentResourceAbiV1 = {
  wit_path: [NfcSegmentV1],
  declaration: DeclarationIdentityV1,
  ownership: "BorrowInputOwnResultV1",
  runtime_identity: "InstanceHandleTableAndOwnerGenerationV1",
  destruction: "SealedOwnerCloseV1"
}

ComponentBorrowPolicyV1 = {
  provenance: "CallbackOrFfiV1",
  escape: false,
  suspend: false,
  store_without_owned_copy: false
}

ComponentTrapPolicyV1 = {
  cire_defect: "DefectTransitionV1AfterSuffixRetirementV1",
  host_or_engine_trap: "CatastrophicInstanceFailureV1",
  catchable_as_raise: false,
  convert_to_result: false
}

CireComponentInterfaceV1 = {
  artifact: "CireComponentInterfaceV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  package_instance_id: PackageInstanceIdV1,
  manifest: ComponentManifestArtifactRefV1,
  link_abi: CireLinkAbiArtifactRefV1,
  component_abi_epoch: "cire-component-memory32-utf8-sync-v1",
  memory: "Memory32V1",
  string_encoding: "Utf8V1",
  native_async: false,
  type_mappings: [ComponentTypeMappingV1],
  imports: [ComponentImportAbiV1],
  exports: [ComponentExportAbiV1],
  resources: [ComponentResourceAbiV1],
  borrow_policy: ComponentBorrowPolicyV1,
  trap_policy: ComponentTrapPolicyV1
}
```

`CireLinkAbiV1.language_interface` 必须指向同一 package instance 的 exact
`CireLanguageInterfaceV1`；callable/data arrays分别按完整 semantic identity bytes严格递增，
且恰是当前 link unit的 reachable exported closure。`CireComponentInterfaceV1.manifest`必须
指向 package root 中同名 manifest edge，`link_abi` 必须指向同 package instance 的 exact link
root。

`CanonicalComponentTypeV1(T,M)` 是 manifest $M$ 下的唯一 recursive mapping；先展开 transparent
alias，要求 $T$ closed/monomorphic/ComponentSafe，然后：

- `Unit -> TupleV1([])`；Bool；Int8/16/32/64；UInt8/16/32/64；Float32/64；Char分别
  exact映射 `BoolV1,S8/S16/S32/S64,U8/U16/U32/U64,F32/F64,CharV1`；`Never`拒绝；
- `String -> StringV1(Utf8V1)`，`Bytes -> ListV1(ScalarV1(U8V1))`；Bytes不能当 raw
  pointer/borrowed view；`Array[T] -> ListV1(map(T))`，tuple按 element order递归；
- `Option[T] -> OptionV1(map(T))`，`Result[T,E] -> ResultV1(payload(T),payload(E))`，其中
  `payload(Unit)=null`，其余 `payload(X)=map(X)`；
- exact nominal Struct/Newtype 映射 `RecordV1(source,declaration,fields)`，要求所有 stored fields
  `PublicV1`，fields按 declaration ordinal exact total，name exact，type在 nominal arguments substitution后递归；
- exact nominal Enum 映射 `VariantV1(source,declaration,cases)`，cases按 declaration ordinal/name exact total。
  Unit payload与 zero-element tuple payload都为 null；单 element tuple payload为该 element mapping，
  多 element tuple payload为 `TupleV1`；record payload为
  `RecordPayloadV1`，其所有 fields也必须 public并按 ordinal/name exact total；
- 通常 `OpaqueTypeV1` 拒绝。唯一 resource例外是 manifest 中 exact
  `ResourceComponentItemV1(D)`：$D$ 必须是 public、zero-binder、empty-requirement opaque declaration，
  并有同一 manifest/link root产生的 Owner-backed handle adapter；此时唯一 mapping为
  `ResourceV1(source,D)`。

Non-resource nominal recursion按 declaration/type-argument DFS 检测，cycle在 Component boundary拒绝；不展开为
infinite ABI tree。`type_mappings` 按 complete source `M3(TypeRefV2)` NFC+JCS bytes严格递增，且
exact-cover manifest选定 callable/data/resource所有 parameter/result/payload的 transitive unique source-type set；
每项 `canonical_abi` 必须 deep-equal上述函数结果。因此 Int→F64、record→tuple、错 field/case
name/order、generic/opaque laundering或 missing/extra mapping都拒绝。

Resource mapping只允许出现在 callable的 direct top-level parameter或 result，不能嵌入 list/tuple/record/
variant/Option/Result；否则 v1没有唯一 nested own/borrow direction而拒绝 ComponentSafe。每个 direct
resource parameter的 `ComponentParameterAbiV1.passing` 固定 `BorrowResourceV1`，non-resource固定
`ValueV1`；Unit result固定 `(result=null,result_passing=NoResultV1)`，direct resource result固定
`OwnResourceV1`，其它 non-Unit result固定 `ValueV1`。v1没有 own-resource input、borrowed result或
nested resource；未来增加必须改 profile/schema。`ComponentResourceAbiV1.ownership` 因而固定
`BorrowInputOwnResultV1`，而不是容许 producer自行选择的 “OwnOrBorrow”。

Manifest/interface partition也是 exact：每个 `ComponentImportV1.item` 必须是
`CallableComponentItemV1`，对应恰一 `ComponentImportAbiV1`；manifest exports 中 callable恰进入
`exports`，resource恰进入 `resources`，data item只作 type-mapping root。
`DataComponentItemV1(D)` 必须 exact解析为 public `DataDeclarationV1`，body kind只能是
`StructV1 | EnumV1 | NewtypeV1`，binders与 requirements全空；其唯一 mapping root是
`NominalRef(D,[])`。Generic declaration因 manifest没有 type-argument field而拒绝，
`TransparentAliasV1` 已在 M3前展开、没有 nominal source ref且不能被选择，`OpaqueTypeV1` 只能使用
`ResourceComponentItemV1`。

对 import preidentity $(P,n,w,s)$，唯一 generated authority family是
`CanonicalHostEffectV1(P,n,w,s)`：一个 `EffectV1` identity，module为
`["pkg-" + P.digest,"~component-import-v1",n]`、path exact为 $s$。
`ComponentImportV1.generated_capability` 必须 exact equal该 identity，并反向解析 package support closure中
唯一 `EffectDeclarationV1`；该 declaration固定 `visibility=PackageV1`、zero binders、empty requirements、
empty conformances与 empty declared operations。它是 sealed host authority row marker，不是 direct `Cap`
value、ordinary Ability或用户可声明/handle的 operation family；唯一 source name是上文 local manifest
Effect-namespace projection `@n::s`。每个 import有不同 preidentity/Effect identity，同一 generated
identity不得被两个 import复用。

Matching manifest adapter是 existing wire的确定构造，不新增 Core/M3 tag。其 `CallableInterfaceV1`
module/export exact为 `CanonicalCallableExport(ManifestAdapterSourceV1(n,h,w,s))`，surface slots与 selected
Component import signature exact equal且全部 non-defaulted named slots。V3固定 root slot 0、zero generic/
row/contract/local binders，只有 exact parameter binders；callable dependencies、local declarations、default
prologues、applications、closure environment全空。`declaration_kind.visible_row` 是 exact closed singleton
`AnonV1(CanonicalHostEffectV1(P,n,w,s))`，无 row tail。

其 `computation` 是一个 canonical `LiteralPathsV2` singleton：唯一 `ReturnsV2` path有
`residual_row` equal上述 singleton、empty demand/usage/Q/LatentSite、suspension
`{atoms:[],grade:NoSuspend}`、same-world transition、non-Pure allowed phase与 exact sealed
`HostObservableV1` summary；result transformer由 total
`CanonicalComponentReturnProjectionV1(result,result_passing)` 产生（ordinary owned ComponentSafe value与
Unit为 Stable/NoCapture，`OwnResourceV1` 使用同 component instance Owner/generation的 sealed resource
provenance/capture）。Host/engine trap仍走 component catastrophic terminal policy，不伪造 Cire Abort path。
每个 origin字段使用同一个 `ComponentManifestPreoriginV1(P,n,w,s)` projection。由于
`ContractComputationV2` 是 contract/path summary而不是 backend dispatch opcode，这个 object无需也禁止
`ComponentHostCall` 新 tag；CireLink/Component lowering只在 exact manifest adapter fact + import inverse
link成立时把该 callable dispatch到对应 WIT import。Source Value-namespace的 `@n::s(...)` 只解析这一个
adapter，调用后 row保留上述 Host Effect且 summary仍为 HostObservable。

每个 selected callable必须 zero-generic、NoSuspend。Component export callable可为 `PublicV1` 或
manifest-selection所 root 的 `PackageV1` callable；ordinary `pub` 不自动导出 Component，Component
selection也不把 PackageV1 callable变成 public Cire API。Export visible row必须 closed，且每个 entry要么
empty，要么 exact为同一 manifest某个 import的 `AnonV1(CanonicalHostEffectV1(...))`；其它 effect、Named
selector或 row tail拒绝。Outer component adapter为这些 entries逐一安装 sealed manifest dispatch并要求
complete/no-extra coverage，向 ABI外部不暴露 Cire row，但 HostObservable summary不能被洗成
ProtocolPure/ConstSafe。Import adapter本身必须是上述 sealed HostObservable contract并与
`generated_capability` exact双向关联。所有 callable
surface slots必须为 `NamedOrPositionalV1`，不允许 receiver/destructuring/capability ABI parameter。
`parameters` 按 slot ordinal exact total，name恰为 `public_label`，type恰为 Core parameter output type的
`CanonicalComponentTypeV1`，`passing`按上段唯一决定；defaultable slot也保留为必传 ABI parameter，adapter总是传 `ProvidedV1`。
`result`/`result_passing` 按上段由 Cire result type唯一决定。`wit_path`、`source_binding`、manifest item、
generated capability/resource identity与全部 vectors双向 exact，不得由 host/WIT spelling重新猜 signature。
Interface的 `imports`、`exports`、`resources` 三个 arrays分别按 matching manifest `wit_path` 的 canonical
tuple order严格递增且无重复，且与 manifest partition逐项 exact equal；集合相等但 array permutation不接受。

三个 root 分别对自己的 complete NFC+JCS object（包括 distinct `artifact` domain tag）求 hash。
Language hash、link hash 与 component hash的 typed reference不可交换；即使 raw digest bytes
偶然相同，artifact tag不同也不相等。Language root没有 target/layout/ABI field；link root可变而
language root不变；component root 必须嵌 manifest+link 两条 typed hash edge并重算自己的 hash，
绝不 alias任一 child hash。Ordinary `pub` 不自动成为 Component export。

=== API evolution judgment <api-compatibility-v1>

`ApiCompatibilityV1(old,new)` 先 exact-decode两边。`SelfRelativeV1(P,x)` 递归把恰好属于 owning
package $P$ 的 `PackageInstanceIdV1` 换成 sentinel `SelfPackageV1`，把其 module首段换成
`pkg-self`；dependency/import package identity与 module prefix保持原值。所有 declaration/evidence/
callable/component payload、requirement/header/nominal/effect refs、source identity与 nested artifact都先作
这个 replacement，再用 `(namespace,module-tail,path)` 与 callable `(module-tail,export_path)`建立稳定
key；因此 source checksum/version变化不会把 unchanged self declaration误判为 remove+add，而 dependency
变化仍可见。两边必须 same source_identity与 `Cire-v1.0` profile，否则不进入 source comparison。

Compatibility matching按一个固定 order进行，不能先用尚未 normalized 的 ordinal/path/hash配对后层对象。
Trait item ordinal只是 raw declaration-order wire identity，不是 compatibility identity。完成 self-rebase后：

0. 先按 stable component name配对 package-owned manifest edges；其中的
   `ManifestAdapterSourceV1`/`ManifestAdapterCallableV1` 再按
   `(manifest_name,source_binding,wit_path)` 配对，并只在
   compatibility view把 paired `manifest_hash` 换成 `ManifestStableV1(manifest_name)` sentinel。Adapter
   fact固定 PackageV1，不作为 public source callable classification delta；它的 manifest/component ABI
   变化仍改变 raw hashes并由 component exact recheck处理。Unmatched manifest/import adapter保持真实
   add/remove，绝不靠 final hash配对。

1. 先对同一 stable trait key的 old/new associated Types在 associated namespace按 injective `name`
   配对，methods在 method namespace按 injective `name` 配对；仅在 compatibility view中把每对
   item ordinal及所有 `TraitGoalV1`、associated/method binding、trait-method use、
   `TraitDefaultCallableV1`、`TraitDefaultSourceV1`、`ImplMethodCallableV1`、`ImplMethodSourceV1`
   与 reserved export-path ordinal segment替换为
   `TraitItemStableV1(trait-key,namespace,name)` sentinel。
2. 在该 item-normalized view上重算 `ImplHeaderDigestV1`，再按 digest一一配对 impl evidence；
   然后把每对 impl `EvidenceIdentityV1` 及 nested refs替换为
   `ImplStableEvidenceV1(header-digest)` sentinel。
3. 使用已 normalized 的 trait-item/impl refs 与 reserved paths建立 callable stable key，配对 callables；
   再按该 callable key配对 protocol facts，把每对 protocol `EvidenceIdentityV1` 及 nested refs替换为
   `ProtocolStableEvidenceV1(callable-key)` sentinel。

Unmatched trait item/impl/callable/fact 仍是真实 add/remove。这使 sealed trait中
新插入一个带 total default的 earlier-sorting item不会伪装成后续 method remove+add；未配对的
required item、rename 或 `pub(open)` item变化仍按下表 breaking。Raw trait/impl/callable ordinals、export paths、
hashes与 runtime artifacts绝不使用 sentinel，每次 source build仍按 declaration order重算。

Classification按以下 ordered total procedure，不能留 unclassified hash drift：schema/profile/source identity
失败先 `IncompatibleProfileV1`；complete raw bytes+typed root hash相等则 `ExactEqualV1`；任一列举的 breaking
delta成立则 `BreakingV1`；其余变化把所有 old public consumer在 new exact import下重做完整
resolve/kind/coherence/type/row/handler/flow/capture/usage/world/phase/Owner/ContractWF，全部成功才
`SourceCompatibleAfterRecheckV1`，否则 `BreakingV1`。

#table(
  columns: (1.4fr, 3.4fr),
  [*result*], [*exact condition*],
  [`ExactEqualV1`], [两个 complete language-interface bytes 与 typed root hash exact equal。],
  [`BreakingV1`], [任一 public export removal/rename；callable public label/order/default-presence、free/inherent/extension/trait-default/impl-method classification、receiver、ConstSafe/ProtocolPure/trap fact变化；effect row、suspension、phase/authority/capture/Owner requirement 变强；新增 generic binder/trait-or-ability constraint/associated equality/required evidence；public field/data shape 改变；public enum variant 增删改；`pub(open)` trait 新增或改变 required item；任一 stable public ability 的 `associated_items`/`operations` bytes改变，或任一 stable public effect 的 `conformances`/`declared_operations` bytes改变（包括 set/name/order/binders/requirements/surface slots/secondary contract/row/transition/result transformer/phase/obligation fields）；public const type/value改变。],
  [`SourceCompatibleAfterRecheckV1`], [没有上述 breaking delta的其余变化（包括 body/Core hash变化、新增 unrelated export/defaulted sealed-trait item或缩小 requirement），且所有原 consumer在 new exact imports下通过完整 recheck。],
  [`IncompatibleProfileV1`], [source identity/profile不同或任一 artifact不能 exact-decode；不作源兼容推断。],
)

任一 semantic root 的 bytes 变化都改变 exact language hash；
`SourceCompatibleAfterRecheckV1` 不是 hash/binary compatibility，也不允许复用 old evidence。SemVer
只是 package identity input，绝不覆盖 exact `PackageInstanceId`、hash edge 或 importer recheck。
