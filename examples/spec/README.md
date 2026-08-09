# Cire-TR₀ conformance corpus

> **Profile:** `Cire-TR₀/2026-08-01`

这里保存规范级输入，不是编译器测试实现。`accept/` 与 `reject/` 下每个
`.cire` 文件头部记录：

```text
profile
expect
rule
oracle
```

`accept` 表示存在符合 profile 的静态推导；`reject` 表示必须由指定 rule
拒绝。`oracle` 是首版 machine-readable semantic expectation。每条先记录
`subject` 与 `ambient`（使用的 prelude/rigid binders）；accept case至少记录
type/row，并按构造记录 immediate/latent row、world、demand route、capture、
usage 或 Owner evidence；reject case记录稳定 diagnostic id 与拒绝位置。
未来 harness应把它扩展成 resolved identity graph、normalized Core 与完整
evidence artifact，不得只检查 parser 是否接受。

| Case | 结论 | 核心义务 |
|---|---|---|
| `accept/named-reader.cire` | accept | 双形参列表、ability/effect/cap、implicit return |
| `accept/row-union.cire` | accept | kinded `RowExpr` union |
| `accept/label-order.cire` | accept | positional-first、label 唯一、source-order |
| `accept/four-modes.cire` | accept | mode lowering、answer transform、explicit return |
| `accept/temporal-next.cire` | accept | fresh clock、delay/advance、same clock |
| `accept/owner-park.cire` | accept | sealed completion source、terminal `Transfers(ParkContractV2)` |
| `accept/owner-park-nonidentity.cire` | accept | `A=Int`、`B=Array[Int]` 的 ParkContractV2 |
| `accept/packed-next-open.cire` | accept | pack/open/yield/advance、won path exactly-once release |
| `accept/packed-next-after-dispose.cire` | accept | lost acquire返回 `None` 且 try-open仍 `MayReturn` |
| `accept/packed-next-local-use.cire` | accept | private clock/Next在 delimiter内完全消费 |
| `accept/packed-next-mixed-exits.cire` | accept | Returns/Aborts/两个Transfers逐 path release并保留tag |
| `accept/secondary-row.cire` | accept | operation dispatch entry ∪ `SecondaryRow` |
| `accept/secondary-row-closed-forms.cire` | accept | `! {}` 与多 entry closed secondary |
| `accept/named-cap-lexical-scope.cire` | accept | named cap binder 的 scoped lexical visibility |
| `accept/associated-ability.cire` | accept | associated三 kind与 local effect-header conformance |
| `accept/associated-generic-evidence.cire` | accept | partial generic equality保留 omitted symbolic projections，不应用 header default |
| `accept/row-predicate-lacks.cire` | accept | sole frozen `Lacks` evidence与row extension |
| `reject/two-row-tails.cire` | reject | literal 最多一个 open tail |
| `reject/positional-after-label.cire` | reject | labelled-call grammar |
| `reject/discontinue.cire` | reject | TR₀ 没有 discontinue primitive |
| `reject/named-escape.cire` | reject | generative identity nonescape |
| `reject/ctl-captures-once.cire` | reject | multi-shot 不复制 one-shot authority |
| `reject/early-advance.cire` | reject | `T-Advance` 需要对应 clock lock |
| `reject/abort-resumes-next.cire` | reject | abort operation 没有 successful resumption |
| `reject/park-is-not-unit.cire` | reject | T-Park 不产生 `Unit` 或普通 expression result |
| `reject/park-source-payload-mismatch.cire` | reject | source payload必须等于 resumption argument A |
| `reject/packed-next-private-identity-escape.cire` | reject | private clock/Next递归 nonescape |
| `reject/packed-next-shadowed-intrinsic.cire` | reject | 同名用户函数不能获得 privileged lowering |
| `reject/open-secondary-row.cire` | reject | TR₀ operation secondary row 必须 closed |
| `reject/bare-open-secondary-row.cire` | reject | bare `! E` 经 recovery CST 到 closed-only WF |
| `reject/associated-effect-kind-mismatch.cire` | reject | associated argument跨 Type/Effect/EffectRow kind |
| `reject/associated-declaration-constraint.cire` | reject | associated Type/Effect constraint尚无 retained evidence wire |
| `reject/associated-parameterization.cire` | reject | parameterized associated item尚无 higher-kinded wire |
| `reject/independent-ability-impl.cire` | reject | independent ability `impl` 尚不属于 TR₀ |
| `reject/row-predicate-has.cire` | reject | explicit `Has` 没有冻结 solver/schema |
| `reject/row-predicate-all.cire` | reject | explicit `All` 没有冻结 solver/schema |
| `reject/row-predicate-only.cire` | reject | explicit `Only` 没有冻结 solver/schema |

`interfaces/effect-family-declarations.json` 是所有完整 interface roots共用的
consumable nominal declaration environment；它用 module-qualified identity与 arity区分
Effect declaration和形状相同的普通 nominal Type，所以 effect-family position不能
仅凭 `NominalTypeV1` tag猜 kind。
`interfaces/choose-once-function-contract.json` 是可独立导入的
`FunctionContractV2`，实际含 nonempty Q与 `LatentSiteV2`；
`interfaces/q-lambda-call-install.json` 是
`CireSpecInterfaceOracleV2` envelope。其 `FunctionContractV2` 以两个
`AppliedContractV2` 和一个有序 `PathBindV2` 固定同一 imported callback的
两次调用：每次 Call Q在自己的 application处 discharge，HandlerInstall Q
与 Lambda exact key以 `(application_slot,local_id)` 保留，两个 invocation
site id不得 alias；每个 callee summary均为与同一 ImportedFunctionRef及其
instantiated declaration kind一致的 `FunctionTypeV2`，prefix terminal path
必须 byte-for-byte旁路第二次调用。evaluator还把 app 0/1各自的完整 term
actual summary代入 retained Lambda：本 fixture的 source必须分别是
`Parameter/0` 与 `Parameter/1`，并以 complete path JCS hash固定结果。
`interfaces/mixed-next-callback-function-contract.json` 是可独立导入的
`FunctionContractV2`：它有 exact `{Branch}` row、nonempty Call/HandlerInstall
Q与 Lambda，并保存 Returns(`Next[...,L]`)/Aborts/两个 Transfers
path。`interfaces/hof-mixed-later.json` 则用同一
`ContractParameterRefV2` 在两个独立 application world调用该 callback
两次；这个 generic contract亦以
`interfaces/apply-later-function-contract.json` 作为 root
`FunctionContractV2` 导出。consumer导入该 root，并同时传入真实 runtime
callback value与指向 mixed-callback root contract的
`ContractSubstitutionEntryV2`；runtime callback的 `FunctionTypeV2`也携带同一
`ImportedFunctionRefV2`，不只是同 kind的本地 placeholder。
validator实际求值 generic contract的两层 `PathBindV2`：第一次 callback的
Aborts/两个 Transfers直接旁路，唯一 Returns进入第二次的四条 flow，规范化后
严格得到 7 条 path；每条 expectation固定完整 PathContractV2 的 canonical
JCS hash，覆盖 row/demand/suspension/ordered-summary/usage/phase/Q/Lambda，
不是“两次调用”的布尔断言或 outcome label列表。
`interfaces/local-function-call.json` 固定 `LocalFunctionRefV2` 的 module-local
declaration-slot resolution，并对同一 T-App算法提供 exact callee
`FunctionTypeV2`、actual arity与逐位 type正例；deterministic evaluator也实际
解析该 local declaration。callee含引用 Parameter/0的 Call-stage Q，而 actual
是合法 `source:null` computed value；evaluator先用完整 summary discharge Call Q，
同时保留不依赖 value slot的 HandlerInstall Q。把前者改成 surviving
HandlerInstall Q则精确拒绝 `term-actual-source-unavailable`。enclosing literal
raw id 0与 nested local retained raw id 0通过真实 `JoinV2` evaluation成为两条
path中的 `[[0],[1]]`。其 composition probe另外固定 NextWorld+SameWorld、
Once+Once=Many，以及覆盖 prompt slot的 bounded fresh-u32 qualifier；合法的
`(65536,65536)` 等大输入仍产生 distinct in-range ids，负数输入被 wire decoder
拒绝；压缩的全域耗尽 probe还精确固定
`qualified-local-id-space-exhausted`。额外 probe固定 JSON object key order不影响
预分配，并证明 enclosing literal site 0与 nested local declaration site 0投影后
仍为 distinct `[0,1]`。
`interfaces/flow-abort-transfer-owner.json` 则逐 variant固定 `AbortsV2`、
`TransfersV2(ParkContractV2)`、`OwnerBoundV1`、root route以及
sealed Park summary、required phase与 Owner/generation-CAS wire形状。它显式使用 `A=Int`、`B=Array[Int]`，要求
source/port/resumption argument三者一致，并保留完整 `ResumeTypeV2`、
`SuffixContractV2` continuation/live evidence。fixture故意让 parked Owner与
保存的 resumption Owner不同，并以
`OutlivesV2(shorter=resumption,longer=parked)` 固定合法 transfer lifetime。

`interfaces/clock-package-paths.json` 携带完整 `PackedNextPackageV2` 和
`LiteralPathsV2`，固定 child-Owner→Identity→Clock→Summary→Body binder顺序、
lost-acquire `MayReturn`，以及实际 Returns/Aborts/两个完整
`TransfersV2(ParkContractV2)` 的 exactly-once release与 tag preservation。
它还把四条独立 `body_observers` 逐字段组合进 won paths；两个 Park path必须
保留 `OwnerBoundV1`、`δpark`、OwnerAuthority/current Owner，并让 summary
严格为 acquire/body/release。`pack_observers` 则固定每条 path先出现非 Pure
allocation，且 Aborts/Transfers在相同 terminal tag前恰好追加一次非 Pure
terminal-close；ordered summary删除 Pure identity/flatten sequence，pack输出
phase还必须是 body phase与 Action + storage OwnerAuthority/current Owner的
`RequireBoth`。package的 outer storage Owner binder、first-party sealed origin、
allocate/terminal-close exact certificate trust与 runtime schema V2同样由 oracle
decoder验证，不能从被验证 certificate自身反向提取信任。named package decoder
还逐 literal验证 profile/schema，并把 storage owner解析成 envelope scope中的
Owner slot；自洽地同时伪造 relation parent不能通过。
`interfaces/handler-forward-contract.json` 是正向
`HandlerContractV2`/`DelegatesV2`/`ForwardContractV2` fixture：handler-level
application ledger、clause disposition lexical scope、exclusive
Open→Forwarded evidence，以及 return-bound Resume在 path usage、live-site
usage和 V2 Q slot中的引用全部由同一 context-sensitive decoder检查。Forward
route必须是 nearest lexical outer prompt；entry/operation使用封闭 variant，且
mode quantity精确为 fun/once→Once、ctl→Many、abort→Zero。clause的
`PathBindV2` 以 `CurrentDispositionPathsV2` 显式携带完整 path observers并注入
当前 disposition，其 binder type只从 `ClauseDispositionBinderV2.type` 派生；
validator还直接求值完整 clause（prefix与 continuation），把 return-bound slot/
world/provenance/capture/usage投影到同一 `SuffixLive` disposition并得到
`DelegatesV2`，而不是只测 prefix或把它当作 unknown kind；
另一种合法 literal prefix必须由同 path的 `OperationResultProvenanceV1` + unique `LatentSiteV2`
signature result派生，普通 untyped以及 Aborts-only `LiteralPathsV2` prefix一律拒绝。
`runtime/packed-next-lease-runtime.json` 的 transition table由
`PackedNextPackageV2.control_protocol` JSON逐条导出，不含第二份 hardcoded
lease machine；它覆盖 dispose/acquire线性化、active
acquire存活、两个同时 lease 的 Closing递减、幂等 dispose与 unique final close；
`mutations/v1-rejects-v2-tags.json` 以 base file + JSON Patch operation和显式
`decoder_target` 给出可执行 malformed payload，保证 V1 decoder拒绝 V2
tag，并拒绝 terminal bind、Q stage、Lambda key、full-observer HOF hash、Pure
sequence identity、unbound SuffixLive、Forward operation/route/signature、
import/local ContractRef、T-App arity/type、Park CAS/state/phase/Outlives、unpacked
Park observer、general Park observer、row/substitution domain、PathBind binder与
observer algebra、local evaluation、Forward prompt/variant/abort quantity、package
profile/storage Owner/origin/outer Owner/certificate trust、T-Try summary NF、
term-actual substitution、u32 qualification、Literal PathBind typing、control
protocol及runtime schema/initial/table，以及新增 exact cases覆盖的所有 wire-u32
occurrence（含 application world、type parameter、Owner authority与 prompt binder）、
abstract ContractParameter PathBind application lineage、closed Legacy Q variant/stage、
retained `source:null` bare slot以及 Aborts-only literal vacuity
破坏。本轮还直接覆盖 Join包裹后的 abstract/concrete application lineage、
literal与 CurrentDisposition binder的 exact world/provenance/capture、跨全部
Invoke result paths的一次性排序 id batch、Call-Q fully decoded actual与真实
BoundarySafe求解、declaration-kind/binder arity、完整 handler clause求值、
recursive Legacy world/Q slot与 OperationSignature type binder解码。JSON oracle的 `canonical_json`
expectation固定 schema规定的
`RFC8785-JCS+NFC-V1` serializer；repository中的 oracle envelope保留
human-readable layout，本身不是 raw artifact byte golden。

从 repository root执行真实 decoder/import/runtime gate：

```sh
python3 examples/spec/validate-oracles.py
```

该 gate以 NFC validation后的 RFC 8785 JCS bytes重算所有 import
SHA-256，不使用 pretty-file raw bytes；每个 mutation都先应用 JSON
Patch，再把 `decoder_target` 指向的实际节点交给声明的 decoder，
并校验精确 diagnostic id。负测还把合法 `DelegatesV2` 拷到 Function及handler
return context、注入未知 outcome、未绑定 return slot与 nominal callee sentinel，
证明 decoder会穷尽 tag并线程 lexical context，而非只检查 fixture形状。
另有 17 个 task #28 full-root probe固定相邻组合：concrete source的全部 Returns
projection、terminal Join与 nested PathBind；secondary id/ref共同 qualification；
完整 actual/closure scope与 Call-Q predicate discharge；无需 slot materialization的
`source:null`；Legacy cleanup、operation type binder及 declaration kind exactness；
以及 outer ContractParameter向 imported generic的合法 pass-through求值。它们都从
repository fixture构造完整 root并走同一 validator/evaluator，不是 isolated helper
assertion。

另有 16 个 task #29 full-root probe继续固定递归与 exact-decoding边界：local和
generic HOF都允许合法 `PathBindV2` term再次作为 prefix且保留完整 terminal flow；
Call-Q按 boundary求 provenance、拒绝 unresolved Owner formal，并把 application与
latent site的 `OperationArgument`绑定到各自 actual position；`StableAcross` 对
`EnvironmentV2`逐 binding求值并要求 capture具备 cross-world witness。Type projection
只由 `kind: Type` binder绑定，不能由同号 Effect binder冒充；object-valued binder kind、
非 String source origin、root closure binding的未知 capture，以及未知 declaration/
signature enum都必须在 untrusted-wire阶段给稳定 diagnostic，不能 ACCEPT或泄漏内部
assertion。

另有 15 个 task #30 full-root probe固定 boundary与 lexical shadow的相邻语义：
Owner/Region/GenerationBound provenance以及 Owner capture没有 valid-at/outlives evidence
时不能跨 Suspension或 OwnerStorage，但 CallArgument正向仍合法；Call-stage
`PhaseAllows` 的 all-phase/no-authority identity可直接证明，非平凡 phase要求没有证据
仍拒绝。Operation signature的同号 local binder按 lexical scope遮蔽 outer binder，
因此 local Type/0正向接受而 Effect/0不能让 `TypeParameterV2/0`逃逸。所有
SourceOrigin必须是非空 canonical `file:subject`，root closure slot也必须属于
`ClosureCapture` namespace；这两类 malformed wire均返回稳定 diagnostic。

另有 11 个 task #31 full-root probe补齐相邻的实例化与递归 scope：Call-Q会按
variant解析 `shorter/longer` 与 `row_slot`，两个 formal落到同一 Owner时用
Outlives reflexivity消去，`EmptyV1`满足已声明的 `RowLacksV1`；普通 `Int`
Parameter不能在 `UsageV1`中伪造 `Many` authority。Operation-local cross-kind
shadow同样覆盖仍合法的 `LegacyTypeRefV2(TypeParameterV1)` encoding；nested
`PathBindV2` continuation保留完整 ambient Return scope，使 decoder与 evaluator
都接受外层 live `ReturnBound`。nested `SlotRefV1`/`LegacyCaptureExprV2` extra
field和 child-Owner sealed-origin漂移均稳定返回
`contract-component-kind-mismatch`，不再泄漏 `AssertionError`；同时保留 local
Type、nested evaluator与 CallArgument BoundarySafe三个正控。

另有 18 个 task #33 full-root probe固定 authority、generic row、cleanup truth、
lexical Return及 recursive exact-wire边界：`LegacyUsageExprV2`只允许引用
Resume/disposition authority，固定 Once/Once正控、Many overuse拒绝，且 Zero occurrence
必须省略；`RowLacksV1/V2`的 `TailV1` actual只能由 caller lexical row binder上的
同一 Lacks evidence证明。`ReplayableCleanupV1`按 normative truth rule要求
obligation与同一 path内唯一 site的 cleanup exact相等、cleanup为唯一 neutral wire、
suffix environment为空（因此 Π/χ均为空）；positive control与 linkage mismatch、
nonneutral、missing-site、nonempty-environment negatives分别走完整 imported root。
Call-Q扫描按 nested `PathBindV2`线程 Return scope，使 `ReturnSlotRefV2`的 reflexive
Owner投影可证明而 unscoped ref稳定拒绝。最后，recursive exact-object scalar与
PackedNext clock误指 parent Owner都稳定返回 `contract-component-kind-mismatch`，
并保留完整 clock package正控。

另有 21 个 task #34 full-root probe关闭 finite-map与递归投影的相邻边界：usage
occurrence按 `Zero < Once < Many`受 Resume capacity上界约束，Many authority合法
under-use Once；每个 path的 usage key唯一，且 `DelegatesV2`的结构性 Forwarded
消耗不能删除。Suffix V2从 computation中 provenance/capture/usage自由引用计算唯一
`LiveSupport`，要求 `live_bindings`精确相等，所以隐藏 Owner Π/χ的空数组会在 source
root即稳定拒绝。Call-Q把 lexical `ReturnSlotRefV2`物化为完整 value summary，既保留
Outlives Owner投影也支持 BoundarySafe等所有 value-slot predicate。PackedNext的
identity/clock/body关联与 scalar child object均稳定返回 profile diagnostic。最后七个
root直接使用 `ReplayableCleanupV2`，对称覆盖 neutral source/import、cleanup linkage、
nonneutral、missing-site以及真实非空 projected environment的 source/import边界；task
#33的 replay roots保留为 V1历史覆盖。

`task35-regressions.py` 提交 13 个相邻 complete-root cases：lexical
`PathBindV2` local Return不进入外层 live support；reachable `InvokeV2` 的 actual
summary进入 projection；Closure/actual live tuple逐字段校验；Return usage先沿 alias
物化、再 semiring fold并重查 capacity；null projection与 once-Resume
`DuplicableEnv`稳定拒绝；PackedNext child Owner必须 fresh/nonalias，nested payload/
Later scalar只产生稳定 diagnostic。主 validator以独立进程运行这组 roots，避免
共享 mutable fixture状态。

`task45-regressions.py` 提交 21 个 associated-evidence/kind complete-root probes：
generic `Store[Value=A]` 产生 total symbolic hidden vector但只保留显式 `Value=A`
等式，omitted `Extra`不误用 declaration default；concrete header分别覆盖 explicit
override、default、missing、equality mismatch、unknown/duplicate/cross-kind与
`Lacks`违反。Decoder root同时覆盖 Type/Effect/EffectRow hidden binder、positive
row Lacks、Type-as-Effect、Effect-as-Type、wrong-kind imported substitution、unbound
family、malformed Lacks container/entry以及未在 declaration environment解析为
Effect的普通 nominal Type，所有负例只返回 registered stable
diagnostic。主 validator也以独立进程运行本 gate。

`task46-regressions.py` 提交 108 个 schema-relative complete-root probes：catalog exact
shape一个正例与missing/extra-field两个稳定负例；public bound/unbound
Row tail、contract-binder bound/unbound row与 nested-Union unbound tail；
ordinary/handler-binder scope中的 `HandlerEntryParameterV1`；unbound/
same-family/wrong-family Named Lacks identity，以及 public row的 matching/mismatched
Named与 handler-only selector；最后是实际出现在 imported
`visible_row`的 Effect binder用 nominal Effect实例化后，target、完整 handler
import与完整 instantiated row均保持有效；used Named identity substitution的
same-family caller正例接受、different-family caller负例稳定拒绝；handler caller
scope中的同族 identity substitution接受，异族 application与 residual-row Named
selector稳定拒绝。新增 declaration-recursive roots把同一 caller type/Row/Contract/
Identity/handler-contract scope贯穿 return/clause path、latent receiver、nested
suffix cleanup、top-level与 suffix application row substitution，并以同族/异族/
unbound selector、bound/unbound Row tail及 residual Union分别作对照；另有完整
FunctionContract root把 caller-scoped inline `HandlerContractV2`置于 closure type，
证明普通 nested type继承 caller scope而 inline FunctionContract仍自建 scope。
量化补充逐一解码 Identity/Contract/Owner/Clock-package binder、paired Clock与
summary scope，并覆盖 Capability identity closure/family一致性；application补充
Owner/Identity/Clock caller substitution closure及其 formal Owner/Identity pairing，
handler environment补充 Parameter
provenance/capture closure。最后用 caller-scoped capability/contract parameter贯穿
evaluated clause二次校验，并用同 slot的 nested FunctionContract Return binder证明
Return扫描既 tag-safe又在 fresh Function/Handler declaration处停止。最后以
bare/packed ClockPackage exact与 alpha-renamed payload对照固化 binder-aware相等，
用 imported FunctionContract direct/量化两条路径固化导入解析，并覆盖 Contract
shadow后 handler-membership重算与 malformed quantifier稳定诊断；Owner、
Identity/Clock、Contract与 operation Type binder的直接结构探针则固化
capture-avoiding递归替换。相邻根还覆盖 inline FunctionContract全套
declaration binder alpha scope、`LegacyTypeRefV2(TypeParameterV1)`与 operation
Type binder的同步刷新、OperationSignature中 imported/local FunctionType的
caller resolution tables，以及 packed payload在 alpha比较前的 exact TypeRef
decode/total diagnostic。
相邻完整根进一步固定 FunctionContract 内 `HandlerContractV2.prompt_slot`、
`ParkContractV2`/`OwnerBoundV1.owner_slot` 与
`TypeParameterIndexV1.slot` 的 binder-aware alpha rename，并要求缺字段
`PromptSlotDeclV1` 与 scalar FunctionType contract 均返回稳定 exact-schema
diagnostic。最后八个相邻根补齐完整 `ContractBinderV2` union 中的 Later/
Continuation declaration member、`WorldParameterV1.contract_slot` 的 Contract
alpha scope、free Handler Prompt 与 nominal Type-index 的 fresh Function scope、
duplicate Type binder 以及 malformed imported/local FunctionRef 的 total stable
diagnostic。主 validator
同样以独立进程运行本 gate。

`diagnostics-v2.json` 冻结 corpus oracle可引用的 diagnostic id与产生 stage；
新增或重命名 id需要新 registry version，不能让 parser recovery改变同一
profile的静态诊断接口。

这些 case 是首批 corpus。完整规则来源：

- [Authority/status manifest](../../docs/spec-status.md)
- [完整表面语法与 elaboration](../../docs/surface-syntax.md)
- [Cire-TR₀ 形式化](../../docs/temporal-reactivity-formalization.typ)
