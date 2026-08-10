#import "../shared.typ": *

= Cire-v1.0 successor profile <cire-v1-profile>

本章是 ordinary-language foundation、integrated first-party contract 与下文 TR0 calculus
之间唯一的 integration layer。对 `profile == "Cire-v1.0"`：

- 本章标成 *retain* 的旧 schema/rule 原样保留；
- 本章标成 *replace* 的旧 schema/rule 只可 exact-decode legacy artifact；
- 本章新增的 closed schema/tag 与 rule 是唯一 successor meaning；
- 未列出的字段、tag、intrinsic、surface shortcut 与 runtime transition 全部拒绝。

处理顺序固定为：`exact decode -> NFC fields -> JCS -> hash-edge verification ->
package/profile check -> ContractWF -> semantic judgment`。Decode 或 hash 失败时不得进入后续
阶段，也不得用 host object、side table 或旧 artifact 填缺字段。除另有说明，closed object
只允许写出的 exact field set；array 的顺序是 semantic，不能按 producer map iteration 产生。

`WireU32V1` 表示 exact unsigned integer range `0..4294967295`。Successor-only schema用这个
别名书写新增 field，既保持与 `u32` 相同的 wire domain，也不污染 retained TR0 validator按
历史 formal text提取的 frozen `: u32` field inventory。

== Canonical successor rule anchors <successor-rule-anchors-v1>

`Cire-v1.0` conformance coverage 只能使用 authority owner发布的 stable rule ID。同一 ID 在
authority coverage、mutation/control、runtime trace、diagnostic relation 与 review report 中必须 byte-equal；
不得为同一 rule 临时创建 alias。下列恰是 Formal-owned 21 个 ID；每个 Typst anchor 是该 ID 的
canonical normative landing point，后文 retained TR0 anchor 只是 proof dependency。

另外 15 个 Surface-owned ID（`FND-control-structural`、`FND-explicit-named-rows`、
`FND-local-inference-boundary`、`FND-method-resolution`、`FND-nominal-data`、
`FND-pattern-matrix`、`FND-postfix-derive`、`FND-trait-coherence`、
`R06-associated-ability-profile-boundary`、`R06-call-assembly`、`R06-capability-identity`、
`R06-first-party-registry`、`R06-inline-handler`、`R06-no-generic-event-on` 与
`R06-origin-arena`）只在本入口的 surface 章节暴露 canonical anchor；本文只引用，不重复
`#metadata` 或 label。

#metadata("FND-component-sync-v1") <rule-fnd-component-sync-v1>
#metadata("FND-const-evaluation") <rule-fnd-const-evaluation>
#metadata("FND-mutation-place-replay") <rule-fnd-mutation-place-replay>
#metadata("FND-numeric-semantics") <rule-fnd-numeric-semantics>
#metadata("FND-package-instance-identity") <rule-fnd-package-instance-identity>
#metadata("FND-primitive-wire-forms") <rule-fnd-primitive-wire-forms>
#metadata("FND-semantic-string-const-bytes") <rule-fnd-semantic-string-const-bytes>
#metadata("FND-maytrap-defect-transition") <rule-fnd-maytrap-defect-transition>
#metadata("R06-callable-hash-dag") <rule-r06-callable-hash-dag>
#metadata("R06-cleanup-receipt-report") <rule-r06-cleanup-receipt-report>
#metadata("R06-diagnostic-origin-stability") <rule-r06-diagnostic-origin-stability>
#metadata("R06-packed-next") <rule-r06-packed-next>
#metadata("R06-public-plan-commit-excluded") <rule-r06-public-plan-commit-excluded>
#metadata("R06-resource-latest-retained") <rule-r06-resource-latest-retained>
#metadata("R06-runtime-symbolic-replay") <rule-r06-runtime-symbolic-replay>
#metadata("R06-sealed-checkpoint") <rule-r06-sealed-checkpoint>
#metadata("R06-signal-tracking") <rule-r06-signal-tracking>
#metadata("R06-task-multiwaiter-shareable") <rule-r06-task-multiwaiter-shareable>
#metadata("R06-ui-action-flow") <rule-r06-ui-action-flow>
#metadata("R06-ui-exact-occurrence") <rule-r06-ui-exact-occurrence>
#metadata("R06-ui-generation-cleanup") <rule-r06-ui-generation-cleanup>

#table(
  columns: (1.7fr, 1.5fr, 3fr),
  [*rule ID*], [*canonical anchor*], [*closed obligation*],
  [`FND-component-sync-v1`], [@abi-hash-roots-v1 / @component-boundary-v1], [sync memory32/UTF-8 Component boundary 与三 hash roots],
  [`FND-const-evaluation`], [@ordinary-foundation-v1], [ConstSafe domain、termination 与 definite defect],
  [`FND-mutation-place-replay`], [@ordinary-foundation-v1], [place source order 与 replay/capture gate],
  [`FND-numeric-semantics`], [@maytrap-defect-transition-v1], [numeric policies、canonical float 与 traps],
  [`FND-package-instance-identity`], [@package-interface-v1 / @api-compatibility-v1], [acyclic lock Merkle identity 与 API evolution],
  [`FND-primitive-wire-forms`], [@primitive-catalog-v1], [exact 16 identities 与 carrier canonicalization],
  [`FND-semantic-string-const-bytes`], [@const-component-wire], [byte/scalar const payload],
  [`FND-maytrap-defect-transition`], [@maytrap-defect-transition-v1], [ordinary MayTrap fact 与 post-cleanup defect],
  [`R06-callable-hash-dag`], [@function-contract-v3], [Interface→V3 exact edge 与 transitive rehash],
  [`R06-cleanup-receipt-report`], [@cleanup-ledger-v1], [receipt multiwaiter 与 ordered report],
  [`R06-diagnostic-origin-stability`], [@successor-diagnostics], [six-field registry 与 causal precedence],
  [`R06-packed-next`], [@packed-next-protocol-v1], [successor protocol; V2 profile-disjoint],
  [`R06-public-plan-commit-excluded`], [@first-party-type-boundary-v1 / @checkpoint-runner-v1], [Plan/Commit private only],
  [`R06-resource-latest-retained`], [@resource-protocol-v1], [switch-latest + keep-last-good],
  [`R06-runtime-symbolic-replay`], [@successor-conformance-v1], [finite exact-checked protocol traces],
  [`R06-sealed-checkpoint`], [@checkpoint-runner-v1], [fixed-Epoch sealed runner],
  [`R06-signal-tracking`], [@signal-ui-protocol-v1], [recursive Signal tail 与 exact tracking],
  [`R06-task-multiwaiter-shareable`], [@task-protocol-v1], [broadcast completion 与 independent waiter],
  [`R06-ui-action-flow`], [@signal-ui-protocol-v1], [action full-flow/suspension contract],
  [`R06-ui-exact-occurrence`], [@signal-ui-protocol-v1], [typed payload 与 same FIFO lease],
  [`R06-ui-generation-cleanup`], [@signal-ui-protocol-v1], [single generation gate count 与 exactly-once release],
)

== Package identity 与 package-root interface <package-interface-v1>

`CireLanguageInterfaceV1` 是 package 的唯一 public semantic root。Callable 不是 package root；
每个 callable edge 必须先载入一个 `CallableInterfaceV1`，再沿其唯一
`core_contract` edge 载入 `FunctionContractV3`。Foundation-only data、trait、const、impl、
package 与 Component facts只出现在 package-level declaration/evidence artifact，绝不向
`FunctionContractV3` 增加字段。

```text
Sha256V1 = "sha256:" + 64 lowercase hex
PackageDigestV1 = 64 lowercase hex
NfcSegmentV1 = NFC nonempty String without '/', '\\', '.', '..' or control

PackageInstanceIdV1 = {
  kind: "PackageInstanceIdV1",
  digest: PackageDigestV1
}

PackageIdentityInputV1 = {
  kind: "PackageIdentityInputV1",
  source_identity: NFC nonempty String,
  exact_version: NFC canonical SemVer String,
  source_checksum: Sha256V1,
  profile: "Cire-v1.0",
  features: [NfcSegmentV1],
  dependencies: [PackageDependencyIdentityV1]
}

PackageDependencyIdentityV1 = {
  alias: NfcSegmentV1,
  instance: PackageInstanceIdV1
}

PackageIdentityEvidenceV1 = {
  kind: "PackageIdentityEvidenceV1",
  instance: PackageInstanceIdV1,
  input: PackageIdentityInputV1,
  hash_algorithm: "sha256-jcs-nfc-v1"
}

PackageImportV1 = {
  alias: NfcSegmentV1,
  instance: PackageInstanceIdV1,
  interface_hash: Sha256V1
}

DeclarationArtifactRefV1 =
    { artifact: "DataDeclarationV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }
  | { artifact: "TraitDeclarationV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }
  | { artifact: "AbilityDeclarationV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }
  | { artifact: "EffectDeclarationV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }
  | { artifact: "ConstDeclarationV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }

EvidenceArtifactRefV1 =
    { artifact: "ImplEvidenceV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }
  | { artifact: "CallableContractFactEvidenceV1",
      hash_algorithm: "sha256-jcs-nfc-v1", artifact_hash: Sha256V1 }

PrimitiveCatalogArtifactRefV1 = {
  artifact: "PrimitiveCatalogV1",
  hash_algorithm: "sha256-jcs-nfc-v1",
  artifact_hash: Sha256V1
}

IntrinsicRegistryRootArtifactRefV1 = {
  artifact: "IntrinsicRegistryRootV1",
  hash_algorithm: "sha256-jcs-nfc-v1",
  artifact_hash: Sha256V1
}

PackageDeclarationEdgeV1 = {
  identity: DeclarationIdentityV1,
  declaration: DeclarationArtifactRefV1
}

PackageEvidenceEdgeV1 = {
  identity: EvidenceIdentityV1,
  evidence: EvidenceArtifactRefV1
}

PackageCallableEdgeV1 = {
  module: PackageModulePathV1,
  export_path: [NfcSegmentV1],
  callable_interface: {
    artifact: "CallableInterfaceV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  }
}

PackageComponentEdgeV1 = {
  name: NfcSegmentV1,
  manifest: {
    artifact: "ComponentManifestV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  }
}

CireLanguageInterfaceV1 = {
  artifact: "CireLanguageInterfaceV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  package_identity: PackageIdentityEvidenceV1,
  package_instance_id: PackageInstanceIdV1,
  imports: [PackageImportV1],
  declarations: [PackageDeclarationEdgeV1],
  evidence: [PackageEvidenceEdgeV1],
  callables: [PackageCallableEdgeV1],
  components: [PackageComponentEdgeV1],
  primitive_catalog: PrimitiveCatalogArtifactRefV1 | null,
  intrinsic_registry: IntrinsicRegistryRootArtifactRefV1 | null
}
```

`package_instance_id` 必须 exact equal于 `package_identity.instance`。`PackageIdentityInputV1.features`
按 NFC UTF-8 bytes 严格递增且无重复；dependencies 与
imports 都按 alias 的 NFC UTF-8 bytes 严格递增、alias 无重复，且两者的 `(alias,instance)`
集合 exact equal。Profile lock 必须是有限有向无环图：以 package instance 为 node、
dependency identity 为 edge，所有 root 可达 node必须只有一个 exact lock entry；按 dependency alias
UTF-8 order 的 DFS 必须在回到 gray node前结束。Cycle、infinite/unresolved edge 或同一 instance 的
conflicting lock entry 稳定返回 `package-import-not-locked`，`dependency-instance-id` note写入第一个
canonical DFS back-edge 的 target。

`PackageInstanceIdV1.digest` 按该 DAG 的 reverse topological order计算，恰是本 node
`input` 的 NFC+JCS bytes 的 SHA-256 裸 64-hex digest；因而身份是 well-founded、与遍历调度无关。
Package root 的 declaration/evidence/callable/component arrays 分别按其
完整 identity object 的 NFC+JCS bytes 严格递增，且必须是 package 自己的 exact semantic validation
closure；它不 flatten任何 import。Closure从全部 public declarations/callables、下述 importer-visible
coherent impl/derive evidence与 component selections
出发，递归跟随其 V3/default/const/type/trait/ability/effect/impl refs，只要 target由当前 package拥有就
必须加入对应 declaration/evidence/callable edge，直到 fixed point；unreachable private artifact不加入。
`visibility=PackageV1` 的 support entry可被 importer用于 exact kind/contract WF，但绝不进入 source
resolver、method candidate、wildcard或 export lookup。每个
declaration/evidence identity、callable module prefix与 component manifest package都必须 exact equal
`package_instance_id`；foreign declaration只通过 `imports[].interface_hash`进入其 own package root验证。
每个 `PackageComponentEdgeV1.name` 必须 exact equal其 hash载入的
`ComponentManifestV1.name`；同一 package 的 component names按 NFC UTF-8 bytes pairwise unique，不能用
两个不同 manifest hash共享外层 name。Name equality/injectivity在 component sort、adapter preidentity与
API pairing前验证。
Schema/closed-field/order failure在 package semantic validation之前停于 `Decode`，不伪造一个
未注册 umbrella diagnostic；identity/hash 错误用 `package-instance-hash-mismatch`，未 lock/cycle
用 `package-import-not-locked`，duplicate instance 用 `duplicate-package-instance`，callable hash edge
错误用 `callable-interface-contract-mismatch`。

Membership按 source class closed决定：public struct/enum/newtype/alias/opaque、trait、ability、effect与
const分别贡献一个 matching declaration edge；它们的 associated items/operations/variants/fields嵌在
该 artifact，不另建 top-level edge。Public free/extension callable各贡献一个 callable edge与一个
Public callable fact；public inherent callable只有在 owner `TypeV1` declaration也 public时可导出，否则
只能作 support。Bodyless trait method没有 callable edge；每个已 included trait artifact的 non-null default
body与每个已 included impl evidence的 explicit method body贡献一个 resolver-hidden support callable edge/fact，并由 owning trait/impl artifact
反向引用。每个 handwritten/derived impl只要 normalized trait goal的 trait、target与所有 outward
requirements均 public/exact-importable，就贡献一个 importer-visible `ImplEvidenceV1`；否则仅在被 public
Core/support artifact引用时进入 resolver-hidden support closure。每个 included callable（public或 support）
恰有一个 matching callable fact；lambda、local declaration、local rank-1 scheme与 operation signature永不
成为 package callable/declaration edge，分别只在 V3 local table或 ability/effect artifact内。Component
只由 manifest selection进入 `components`。任何其它 private artifact只有 fixed-point traversal可达时加入，
不可用 directory scan补齐；public fact若引用 private owner/receiver/signature fact则直接 API WF失败，不能
降级成 hidden public name。

```text
PackageModulePathV1 = [NfcSegmentV1; length >= 2]

PackageModuleWF(instance,module) iff
  module[0] == "pkg-" + instance.digest
  and every later segment is NfcSegmentV1

DeclarationIdentityV1 = {
  package: PackageInstanceIdV1,
  namespace: "TypeV1" | "ValueV1" | "TraitV1" | "EffectV1"
           | "AbilityV1",
  module: PackageModulePathV1,
  path: [NfcSegmentV1]
}

EvidenceIdentityV1 = {
  package: PackageInstanceIdV1,
  kind: "ImplEvidenceV1" | "ProtocolEvidenceV1",
  ordinal: WireU32V1
}
```

Source grammar没有 module declaration或 file-to-module convention。对普通 user declaration，唯一
`CanonicalSourceModuleV1(P) = ["pkg-" + P.digest,"root"]`；file path、directory、visitor与 import alias
都不得改变它。每个 `DeclarationIdentityV1.path` 与 `PackageCallableEdgeV1.export_path` 必须 nonempty。
Top-level data/type alias/trait/ability/effect/const以及 free/extension callable的 source path恰是其单个
declared name；inherent member使用 owner path后追加 member。Sealed core/first-party producer可使用本规范
另列的 reserved module segments，但 user source不能伪造它们。

任一 nominal Struct/Enum/Newtype/Opaque `TypeV1` declaration identity $D$ 与 semantic nominal reference的
可逆投影唯一为：

```text
NominalRef(D,args) = NominalTypeV2 {
  module: D.module ++ D.path[0 .. length-1),
  name: D.path[length-1],
  arguments: args
}
```

反投影把 final module/name split恢复为同一 $D$；empty path、另一 split或 foreign package prefix拒绝。
`TransparentAliasV1` 虽有 package declaration/source key，但绝无 nominal constructor identity：它在进入
M3/type serialization前递归展开为 target，cycle已先拒绝，不能调用 `NominalRef`制造第二 wire image。
Trait/Ability identity只出现在各自 kinded goal/reference；`EffectFamilyRefV2` 的 nominal branch对
`EffectV1` declaration使用同一 module/path split与反投影，不能另猜 boundary。

Package edge dispatch是 closed 且双向 exact：`TypeV1 -> DataDeclarationV1`、
`TraitV1 -> TraitDeclarationV1`、`AbilityV1 -> AbilityDeclarationV1`、
`EffectV1 -> EffectDeclarationV1`、`ValueV1 -> ConstDeclarationV1`；
`ImplEvidenceV1 -> ImplEvidenceV1`、`ProtocolEvidenceV1 ->
CallableContractFactEvidenceV1`。载入 object的内嵌 `identity` 必须与 edge identity exact equal，
artifact tag/hash也必须 exact。Const是 Value declaration；derive使用
`ImplEvidenceV1.origin=DerivedImplV1`；Component只走 `components` manifest edge。因此没有
`ConstEvidenceV1`/`DeriveEvidenceV1`/`ComponentEvidenceV1` 或 `ComponentV1` declaration namespace，
也没有 arbitrary `ArtifactRefV1` escape hatch。Unknown pairing在 declaration/evidence semantic WF前
Decode拒绝。

`EvidenceIdentityV1.ordinal` 不由 map iteration、source filename或 hash table产生；两个 evidence
kind各自从 0 连续分配且允许数值重叠。`ProtocolEvidenceV1` 先把 package root 的 `callables` 按
完整 `PackageCallableEdgeV1` NFC+JCS bytes 排序，其 zero-based index就是对应且唯一
`CallableContractFactEvidenceV1` 的 ordinal。`ImplEvidenceV1` 先为每个 impl/derive形成
`ImplPreidentityKeyV1`：取完整 `ImplEvidenceV1` semantic payload，但删去顶层 `identity`；其中
resolved trait/target/header、binders/requirements、total associated/method vectors与完整 handwritten/
derived origin仍全部保留。按该 key 的 NFC+JCS bytes严格排序后，zero-based index就是 impl ordinal；
两个相同 preidentity key 是 duplicate impl evidence并在分配前拒绝，不能靠 ordinal消歧。
Package evidence array必须对两个 kind分别 exact覆盖 `0..n-1`、无 gap/duplicate/foreign package，
并与上述重算结果 exact equal；随后才按完整 `EvidenceIdentityV1` bytes进入 package root排序与 hash。

所有 module vector，包括 callable envelope/dependency、nominal type、trait/effect reference、
component manifest 与 diagnostic canonical subject 的 resolved module，都必须满足
`PackageModuleWF`。第一段因此不是人类 package alias，也不是旧 `['cire', ...]`；它是
`pkg-<PackageInstanceId digest>`。Source 中的 `@alias` 只参与 resolver，绝不进入 semantic
identity。两个 locked version 即使后续 path 相同也不相等。

`FirstPartySourceV1.module` 与 `FirstPartyTypeTemplateV1.module` 是 registry closed logical
namespace（其 schema刻意不是 `PackageModulePathV1`），为保持 exact 21-entry registry bytes可写
`["cire", ...]`/`temporal` 等 locked symbol。Surface 的 `instantiate_first_party` 已用 profile lock
生成其 package-qualified output；Formal 仅当 logical namespace 可唯一解析为 exact package
instance，且每个已产生 M3 nominal/callable Core reference 都写入
`PackageModulePathV1` 时接受该 output。logical namespace绝不能直接漏进 public interface或 TypeRef。
