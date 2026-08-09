#import "../shared.typ": *


`StageV1` 是 closed enum；其他 string必须产生
`unknown-obligation-stage`。`LegacyObligationV2` 不是 opaque escape hatch：其
`value` 必须按上列九个 `ObligationV1` variant之一做 exact field decoding，未知
variant产生 `unknown-obligation-variant`，其中每个 `id`、site与 slot仍受 V2
importer的 scope/u32检查，并在 application projection时使用同一
declaration-local qualification，不能保留未限定的 raw id。所谓 exact decoding
必须递归到底：`StableAcrossV1.worlds` 的每个成员必须是完整 `WorldExprV1`，
`clock_slot`/`owner_slot`/`row_slot` 与 `shorter`/`longer` 必须是对应 namespace
的 `SlotRefV1` object，不能用 scalar或在 opaque payload内藏 V2 marker。
同理，每个 `OperationSignatureV2.type_binders` 成员必须 exact-decode 为
`TypeBinderV1 { slot: u32, kind: Type | Effect | OwnerRegion }`；空列表不构成
忽略非空列表的许可。

Legacy `Cire-TR₀/2026-08-01` 的 canonical envelope 是
`FunctionContractV2`。`FunctionContractV1` 只描述 fully concrete legacy
artifact；V1 decoder遇到 V2 field/tag必须拒绝。V2 importer先以
`application_slot` 建立每个 `AppliedContractV2` 的唯一原子 application：
contract ref、callee/argument summary、完整 type/row/contract/Owner/
identity/clock substitution与 entry world必须一起通过 kind/scope检查，任何
field都不能携带第二套 actuals。随后验证 `ContractComputationV2` 是无环有根
term，并从同一 term派生以下 observers：

`FunctionContractV2.declaration_kind.parameter_type` 展开的 argument序列必须与
`binders.parameter_binders` 等长且逐项同 type；decoder不能接受 unary kind加两个
parameter binder并把 arity failure留到 evaluator。`ValueSummaryExprV2.source` 可以
在不需要 slot materialization的 computed actual中为 null；一旦 result projection、
bare `SlotRefV1` substitution或其他规则确实需要 actual slot，import/evaluation必须报
`term-actual-source-unavailable`，不能抛内部 assertion。

```text
flow(C), row(C), demand(C), normal_return(C), suspension(C), summary(C),
usage(C), phase(C), obligations(C), latent_sites(C)
```

`LiteralPathsV2` 给出完整 path bundle；`InvokeV2` 只引用已验证的同一
application；`JoinV2` 在保留 path-local evidence后做 canonical union。
`PathBindV2(F,x.G)` 的 `terminal_policy` 必须是唯一 canonical 值
`PreserveTerminalV2`，并逐个处理 $F$ 的 reachable path：
Aborts/Transfers连同
其 row/demand、suspension、summary、usage、phase、Q/$Lambda$ byte-for-byte
旁路；只有 Returns path把该 path自己的 world/provenance/capture绑定到 $x$
并进入 $G$。Returns→Returns顺序组合 world/result，$G$ 产生的 terminal tag
保持 terminal。全部 path-local ContractWF/AttributedOK/nonescape通过后才能
对 observers做 ACI normalization；top-level transition/result不是可独立写入
的第二事实。
`x.type` 必须逐字段等于 $F$ 每个 reachable Returns path的 result type；若
prefix是 imported/local application，`x.world/provenance/capture` 还必须等于
该 application entry world经 source transition后的 world，以及 source result
transformer在本次 actual上的实例化。只验证 binder自身 well-formed而不把它
与 prefix return相连是不合法的。Returns→Returns的 transition按顺序组合，
`SameWorldV1` 仅是 identity，不能覆盖先前 `NextWorldV1`；同一 authority的
usage按顺序 semiring组合，尤其 `Once+Once=Many`，`Zero`从 canonical map省略。
该联系检查递归穿过 `JoinV2` 与 nested computation，对每个返回 path独立成立；
把 `InvokeV2(app0)` 包成 `JoinV2([InvokeV2(app0)])` 不能使 binder改贴成 app1。
对 operation-result literal，binder的 world必须是该唯一 site的
`EntryWorldV1` 经本 path transition后的结果，provenance/capture必须逐字段等于
本 path transformer；对 `CurrentDispositionPathsV2`，world从当前
`ClauseDispositionBinderV2.site_slot` 派生，type/provenance/capture/usage全部
从当前 disposition与本 path transformer派生，不能只检查 type。
`LiteralPathsV2` 没有独立可写的 result type。literal-path-based
`PathBindV2.prefix` 的 result type只有两个且穷尽的可推导来源：(1) Returns transformer是 exact
`OperationResultProvenanceV1(site)` 且该 path有唯一同 site `LatentSiteV2`，此时
由其 `instantiated_signature.result` 派生；(2) handler clause的
`PathBindV2.prefix` 中 exact `CurrentDispositionPathsV2 { paths }`，此时完整
path observers仍显式携带，而每条 Returns path的 result type由该 clause当前
唯一 `ClauseDispositionBinderV2.type` 派生。`CurrentDispositionPathsV2` 在其他
位置/context、携带额外 field或没有当前 disposition时均非法。零个 reachable
Returns的 Aborts/Transfers-only literal prefix没有
result type，不能因 empty universal check vacuously通过。contract evaluator把合法
`CurrentDispositionPathsV2` 与 `LiteralPathsV2` 一样作为显式 path bundle求值，
同时保留上述 implicit current-disposition result-type来源，不能落入 unknown-kind。
完整 clause（prefix加 continuation）也必须求值：其中 `ReturnSlotRefV2` materialize
为当前 clause唯一 `SuffixLive` disposition slot，`ReturnUsageV2` 等其他投影来自
同一 return binder；只求值 prefix而跳过 continuation不构成验收。
其他 untyped
literal prefix不得作为 `PathBindV2.prefix`；serializer必须改写成带 declaration kind的
local/imported `InvokeV2`，而 importer报
`path-bind-literal-prefix-forbidden`。因此 literal/binder不能互相自证一个伪造
Bool type。

每次 `InvokeV2` alpha-refresh site/prompt/Q ids；投影 id以
`(application_slot, local_id)` qualified，在完整实例化后才 flatten。
每个 function/handler/local declaration evaluation各自拥有一个
declaration-local、确定性的 bounded fresh-u32 allocator；开始求值该 declaration
前，先收集并保留其 own computation中全部 raw local ids。nested declaration用
自己的 allocator求值，只有其结果投影到 caller declaration时才由 caller的
allocator再次 qualification，不能递归复用 caller allocator。
对一次 `InvokeV2` projection，先跨该 invocation返回的全部 path收集全部 distinct
raw local ids并按数值排序，预分配每个
`(application_slot, local_id)` 的最低未用 u32，之后才做 structural rewrite；JSON
object member顺序、path顺序、pretty printer顺序或 traversal偶然性不得影响输出。
逐 path各自预分配不是 canonical batch。缓存映射
由 site、prompt、claim/port与 Q/$Lambda$ 中全部引用共享。输入
application/local id与输出都必须通过 u32 range check，空间耗尽则拒绝。
固定 radix或未检查宽度的 arithmetic pairing都不是合法实现：前者会让
`(0,1000)` 与 `(1,0)` 碰撞，后者会把合法 u32 pair溢出 wire domain。
Call-stage Q在 invocation处 discharge；HandlerInstall-stage Q与 exact
$Lambda$ application key一起保留到 fresh prompt存在。`FunctionContractKindV2`
把 visible row与 parameter/result type一起匹配；依赖求解顺序固定为
type/Owner/identity+clock/row，再 contract binder，再全 term substitution与
normalization。occurs-check、forward ref、cross-kind projection或 scope escape
一律拒绝。
Call-stage discharge不是删除操作：importer先把 Q 中每个 formal slot解析成完整
actual `ValueSummaryExprV2`，递归 exact-decode并检查其 scope，再实际判定
`BoundarySafe`/`StableAcross`/`DuplicableEnv` 等 predicate；只有判定成功才可消掉
该 obligation。lexical `ReturnSlotRefV2` 同样是 value formal：checker从对应
`ReturnBinderV2`物化 source/type/nominal-index/provenance/capture/usage全字段 summary，
而不是只在 Outlives的 Owner projection中特判；因此所有 value-slot predicate共享
同一解析规则。`BottomCaptureV1` 不能满足 `BoundarySafe`，伪造 capture kind或
unbound `SuffixLive` 必须在 discharge前产生稳定 diagnostic。
`ImportedFunctionRefV2` 的目标必须是 root
`FunctionContractV2`，其 `declaration_kind` 非 null 且与 use-site binder的
`FunctionContractKindV2` 逐字段相等；指向 oracle envelope中的裸
`LiteralPathsV2` pointer不是 function contract import。
`FunctionTypeV2.contract` 中的 `ContractRefV2` 使用同一 root/hash/kind
检查，因而跨模块 runtime callback value的 type可以直接携带它的
imported contract identity，不只携带一个同 kind但无法同一化的本地 binder。
standalone `FunctionTypeV2` 的 parameter/result必须立即等于 resolved
declaration kind；只有 `AppliedContractV2.callee_summary` 可把这一步延后到
本 application substitution完成后检查。`LocalFunctionRefV2` 在 validator与
deterministic evaluator中都解析同一 module-local declaration table，不能只
在 shape checker中接受而在 evaluator中成为未知分支。

本文内部仍用 $Q/Lambda$ 简写这两个字段。`id`、capture/site/prompt slot
都在 declaration boundary按 source order alpha-normalize；wire equality不依赖
source变量名或运行时地址。`DeclarationBindersV1` 是 artifact自己的
validation context；importer不重解析 source即可验证 parameter/type/row/
contract/Owner/clock/identity/prompt引用。所有 `ObligationV1.slots`、actual-summary引用与
suffix-live引用都使用 `SlotRefV1`；相同数值但不同 namespace绝不 alias。
`ClockBinderV1.identity` 是显式 refinement witness：它必须解析到同一
declaration context中的唯一 `IdentitySlotDeclV1`，且两者 family/owner一致。
importer先注册 Owner与Identity declaration，再验证 Clock view；Clock与Identity
slot仍是不同 namespace ref，只有该 witness允许把二者解释为同一个 nominal
capability identity。
`SlotArgumentV1` 可引用 parameter/closure/suffix-live slot；
`ComputedArgumentV1` 用于没有可引用 binder的 local/computed actual，
两者都必须携带完整 type、nominal-index、provenance与 result-capture
expression，importer不能从一个裸 slot猜测 $Xi_k$。
`OperationArgument` namespace由当前 site的 `actual_arguments` position绑定；
instantiated signature中的 parameter/result transformer必须按同一长度与
type逐项验证。
`UsageV1.slot` 还必须在当前 binder validation context中满足
`AuthorityBearingSlot`：它解析到由 $Omega$ 跟踪的
`ResumeTypeV1`/one-shot disposition authority，而不是任意值 slot。
因此普通 `Array[A]`、callback data或仅有 provenance的 parameter不能通过
在 `usage` 中写 `Many` 伪装成 latent authority usage；`kind` 必须等于
一次 closure调用对该 authority的实际 $0/1/omega$ 消耗，且 `Zero` entry
的 canonical form是从 finite map省略。Resume/disposition type中的 usage是
capacity $q$，不是要求实际消耗相等的第二份 occurrence；checker使用
$"Zero" < "Once" < "Many"$并证明 $q_"actual" <= q_"capacity"$，所以
`Many` authority使用一次合法，而 `Once` authority不能使用多次。
每个 `PathContractV2.usage` 是 namespace-qualified authority到非零 grade的
唯一 finite map；wire中的重复 key不能在 decode时偷偷 fold。顺序组合才按
$0/1/omega$ semiring fold。`DelegatesV2` 的 `Forwarded` transition结构性消耗
inner disposition一次，因此原始 path必须包含该 key；组合后的 path可因其它
消耗把总 grade fold成 `Many`，但不能把该结构性 occurrence删除。
`ReturnUsageV2` 是 lexical alias，不是独立 authority key：checker必须先沿
`ReturnBinderV2.usage` 递归物化到最终 namespace-qualified key，再建立每条 path
的唯一 map并做顺序 fold；组合完成后还要重新证明 actual grade不超过该 key的
Resume/disposition capacity。null projection必须在 decoder边界稳定拒绝，不能留给
evaluator触发 assertion。
每个 secondary site有自己的 receiver和 route，
不能继承 primary route。`SecondarySiteSetV1.kind` 在 V1 只能是 `Closed`；
没有 open row-slot variant。未知 schema version、variant tag、route selector、
悬空 slot/id或伪造的 open secondary set必须拒绝，不能默默丢字段。
`SuspensionV1.grade` 必须等于全部 atoms 的 join。无 site attribution的
`NoSuspend` 唯一编码是 `atoms=[]`；`DirectV1` 只允许 `MaySuspend`，不能用
冗余的 `DirectV1(NoSuspend)` 制造第二种相等表示。operation site即使声明
`NoSuspend` 也必须保留其 `RequestV1(NoSuspend)` attribution。每个
`RequestV1` 必须与同一
site/route/entry/operation/role 的 attributed demand或对应 schema version的
`LatentSiteV1`/`LatentSiteV2`
一一对应；`OwnerBoundV1` 必须与同一 park/Owner slot 的 `ParkContractV1`
或 `ParkContractV2` 对应。wire不序列化 runtime prompt地址。
Importer必须从三处重新计算同一个 canonical
`(site_slot,route,entry,operation,role)` key：不能相信 demand、Request atom或
primary/secondary site evidence中任一份自报的 route；所有显式 prompt route
都在当前 declaration prompt table中关闭，path-level `OuterOfV1` 直接拒绝。
`SuspensionV1.atoms` 先 exact-decode为 list，再由 atoms 的 grade join重算
aggregate grade；container或 aggregate漂移只产生稳定 contract diagnostic。
`LatentSiteV2.secondary_sites` 是 path attribution唯一可认证的 sealed side
evidence；它必须与 `instantiated_signature.secondary_sites` 的 deterministic
instantiation exact一致，signature template不能作为缺失 evidence 的 fallback。
普通 Function path要求 site key与 Request key exact closure。Handler path的额外
site只能来自 finite authenticated set：有唯一 Call-stage obligation projection、
被当前 exact handler prompt/entry消除的 HandlerInstall site，或已由
`DelegatesV2.forward_contract` 与 disposition evidence验证的 primary/secondary
site；除此以外的 orphan LatentSite一律拒绝。
Forward-authenticated LatentSite还必须是 derived HandlerInstall stage，并逐字段等于
同一 `ForwardContractV2` 的 authority-bearing语义投影：site、entry/receiver、operation、route、actuals、
instantiated signature、continuation/suffix、sealed secondary sites与两组 obligation
ids全部一致；仅命中五字段 attribution key或无唯一 Call projection却改报 Call stage，
都不能借用 disposition evidence。
`SuffixContractV1/V2` 是 $D_k,Pi_k,chi_k,u_k$ 的确定性 wire projection：
residual row/demand、flow/world、suspension、summary/result、phase、cleanup
与全部 live binding缺一不可。对 V2，checker从本 suffix computation中全部
provenance、capture与 usage expression的自由 namespace-qualified slot确定性计算
`LiveSupport(D)`；nested suffix由自己的 lexical projection单独验证。
`live_bindings` 的 key必须唯一且恰好等于 `LiveSupport(D)`，不能相信序列化的
空数组，也不能允许遗漏或多报。`cleanup` 的 demand/suspension同样必须通过
`AttributedOK`。
`LiveSupport(D)` 使用带 bound-Return set的 lexical traversal：`PathBindV2`
只把 binder加入 continuation，因而该 continuation里的同号 `Return*V2` 不属于
外层 suffix的 free support；nested suffix独立重新投影。每个 reachable
`InvokeV2` 还把同 ledger application的全部 actual summary之
$Pi/chi/u$ 纳入 support。对 legacy/closure/actual binding，serialized
`type/provenance/capture/usage` 必须逐字段等于解析出的完整 tuple，不能只比较 key；
Return live entry则必须保留同号 `ReturnProvenanceV2`/`ReturnCaptureV2`/
`ReturnUsageV2` lexical alias，递归 type本身仍由 `TypeRefV2` decoder检查。
`LatentSiteV1`/`LatentSiteV2` 的 instantiated signature、actual arguments与
selector必须相容；
call/install id分别只能引用 `ParametricObligations` 中同 stage的 obligation。
importer把这些 ids 与本 site的 actual summaries/entry world一起解析成内部
`κ.call_obligations` / `κ.install_obligations`；前者必须附 sealed
call-discharge evidence，后者保留 exact instantiation key到 `InstallOK`。
不存在可重新读取的泛化 obligations aggregate字段。
`EffectEntrySelectorV1` 与 `OperationSelectorV1` 只接受上列 tagged variants；
所有 `family` field都以 Effect position解码：nominal reference必须由 producer/import
declaration environment按 module-qualified identity解析为 Effect且 argument arity exact，
不能仅根据 `NominalTypeV1` object shape推测。Retained TR0 complete roots只为历史 lane把该
environment冻结为上述 `EffectFamilyDeclarationsV1`；Cire-v1 complete root与真实 importer必须
从 package graph的 `EffectDeclarationV1` closed declaration table取得 identity、arity与 operation
signature，禁止 profile fallback。`TypeParameterV1/V2`必须引用当前 lexical
kind environment中的 Effect slot。Type slot、builtin Type、unbound slot或普通
TypeRef shape稳定拒绝 `contract-component-kind-mismatch`（unbound projection用
`contract-projection-escapes-scope`）。`RowBinderV1.lacks` 先 exact-decode list与
entry，再走同一个 family scope/kind check；malformed container/entry不得泄漏 host
exception。
Declaration的 `visible_row`与每个 `FunctionContractBinderV2.visible_row`也必须在
同一 declaration Row-binder environment中递归关闭；unbound `TailV1`稳定拒绝
`contract-projection-escapes-scope`。对 `RowBinderV1.lacks`，selector shape解码后还必须
用当前 identity/contract-binder table解析 lexical meaning：
`NamedV1.identity` 必须引用
`binders.identity_binders` 中同 family
的 live generative binder。`HandlerEntryParameterV1` 只可出现在
`HandlerContractBinderV1/V2` 的 lexical scope，并在 actual installation
替换为同 family的 `AnonV1` 或 `NamedV1`；普通 function contract不能使用。
任何显式 prompt selector都必须引用
`binders.prompt_binders` 中 scope包含该 site的 declaration。
`ResolveAtCallV1` 只允许 stage=Call，`ResolveAtInstallationV1` 只允许
stage=HandlerInstall；两者在指定 stage选择 stack中 nearest exact entry，
没有 match时产生不与任何 prompt alias的 `RootOfEntryV1` residual route。
`OuterOfV1` 只供 Kernel Forward，必须找到所引 prompt严格外层的 nearest
exact-entry prompt，否则 artifact ill-formed；不能悄悄 fallback到 root。
`FlowSetV1` 保持每个 tagged path；同一 contract可有多个不同
`Transfers`。V1 `Delegates` 只存在 handler 的 `ClauseFlowPathV1`；
V2 `DelegatesV2` 只可在
`HandlerContractV2.clause_computations[*].computation` 的 lexical scope中出现，
必须携带 `ForwardContractV2` 与 `ForwardDispositionEvidenceV2`，并在投影
handler public result前消除。FunctionContractV2、SuffixContractV2、handler
return computation或任何外向 `FlowSetV2` 中出现它都必须拒绝。
每个 V1 `Delegates` 必须带
`ForwardDispositionEvidenceV1`：`inner_disposition` 必须解析到该 clause
所在 `ClauseFlowSetV1.disposition_binder` 所声明的
`SlotRefV1 { namespace: SuffixLive, slot: disposition_binder.slot }`，不得从
continuation/live bindings反推。`disposition_binder.slot` 是 declaration，
其 lexical scope恰为同一个 `ClauseFlowSetV1.flow`，在该 scope内不得重复；
`type` 必须为该 clause mode的 `ResumeTypeV1`，`site_slot` 必须匹配原 site；
input/output固定为
`Open→Forwarded`，`forward_site_slot` 必须等于所携
`ForwardContractV1.site_slot`，且 exclusive transfer中的 continuation
逐字段等于该 contract的 continuation。缺失或重复处置 evidence一律拒绝。
`ForwardContractV1.secondary_sites` 是 routed contract的必填 sealed
`Closed` set；所有 secondary demand/request side evidence必须由它唯一投影
且逐字段相等，不能只存在于 local side node而让 serialized contract缺失。
`ForwardContractV2` 对 V2 continuation/computation执行同样的 exactness检查；
Call/HandlerInstall obligation id必须分别精确投影到它的两个 id
list，且 `continuation_transfer` 唯一允许
`ExclusiveToForwardContract`。
`ForwardDispositionEvidenceV2.inner_disposition` 必须解析到当前
`ClauseDispositionBinderV2`，其 `ResumeTypeV2.usage` 必须与 clause mode的
$q in {0,1,omega}$ 一致，不再把 V2 硬编码为 `Once`。
精确映射是 `fun↦Once, once↦Once, ctl↦Many, abort↦Zero`；abort clause携带
`Once` continuation authority必须拒绝。
该 clause binder的 `SuffixLive` slot只在所属 clause computation的全部递归
usage/live/suffix节点中可见；handler return、其他 clause或任意未绑定 slot
一律报 `handler-disposition-escapes-scope`。Forward本身还必须逐字段满足：
`operation`等于当前 clause operation，`entry`等于 handler handled entry，
`site_slot`等于 disposition site；`route`是当前 handler prompt的严格外层
nearest lexical `InstallationPromptV1`，不能是任意不同数值、本 prompt、root
或 unresolved selector；handler entry与 clause/Forward operation都先按
封闭 tagged union解码，两个相等的未知 tag不能互相“证明”合法；
`entry_world`是该 site的 exact `EntryWorldV1`；actual summary的长度/type按位
等于 instantiated signature parameters；call/install ids只能投影 signature
声明的 obligation ids；continuation/result/answer/usage逐字段等于 disposition
Resume contract。以上分别稳定诊断 operation、route、application与 obligation
mismatch，不能由一个宽松“Forward-like”检查代替。
`ParkContractV2` 序列化 alpha-normalized Owner/site/claim-cell slot、完整
`ResumeTypeV2` 与 generation-CAS protocol，不序列化某次运行时 generation
值或地址。`ParkContractV1` 只属于 legacy V1。
`ParkContractV2.source.owner`、`completion_port.owner` 与 `owner_slot`
必须相同；source/port `value_type` 必须相同且精确等于
`disposition.resumption.argument`；park、port、CAS与 disposition
必须逐字段引用同一个 `claim_cell_slot`。completion只在 source generation
等于 current Owner generation时竞争；finalize在 Owner仍 current时使用同一
equality gate，或在 close/revoke已推进 generation后凭该 Owner sealed retire
authority竞争同一 claim cell。两条路径都不递增 generation；
completion与 finalize分别竞争
`Unclaimed→Completed` / `Unclaimed→Finalized`，失败不改变 generation、
source或 disposition。`OneShotDispositionV2.resumption` 必须是 usage=Once
的完整 `ResumeTypeV2`；它显式保存 argument $A$、answer $B$、精确
`SuffixContractV2` $D_k$、live provenance/capture与 Owner。source/port只接收
$A$；completion成功后由 $D_k:A→B$ 产生 answer，不能把 $B$ 当 host payload。
若 clause disposition binder存在，其 Resume type必须 alpha-equal。其
`required_phase` 必须覆盖 T-Park 的 Action/Owner authority gate。
parked Owner（source/port/`owner_slot`）与 resumption Owner可以不同；不同时
同一 transfer path的 `ParametricObligations` 必须含 exact
`OutlivesV2(shorter=resumption.owner,longer=parked.owner)`，相同 Owner则不要求
冗余 witness。`GenerationCASV1` 的 generation model/single-writer gate、两条
CAS transition、preserve-generation与 failure-no-state-change，以及
`OneShotDispositionV2.states=[Unclaimed,Completed,Finalized]` 都是 exact wire
protocol，不是描述性字符串集合；任一字段漂移必须在 import时拒绝。
每个 `TransfersV2(park)` path还必须保留与 park逐字段对应的
`OwnerBoundV1(MaySuspend)` atom、sealed first-party Park certificate与
`RequireBoth` 后仍包含 park Action/Owner gate的 phase。该规则对普通
FunctionContract、handler、unpack与 flow oracle完全相同；不能只在
ClockPackage专用 decoder中检查，也不能以 top-level observer删掉 sole
OwnerBound atom。
V2 normal transition/result只允许由 `normal_return(computation)` 派生；
importer不得接受独立可写的第二份 top-level projection。legacy V1仍用
`NormalizeReturnProjectionV1` 检查 concrete fields，但不能表达 symbolic
application/PathBind。

`NormalizeReturnProjectionV1(flow)` 的定义是：按 canonical byte encoding
排序并去重 `Returns` paths；零项产生两个 bottom variant，一项直接投影，
多项分别对 transition与完整 `(provenance,capture)` transformer做
idempotent join，并把成员排序去重后产生 `PathJoin*V1`。它不查看 source。
所有 AC-idempotent domain（`UnionV1`、capture/provenance union、summary
join、FlowSet）都递归 flatten、按 canonical byte encoding排序并去重；
empty/singleton分别使用该 domain唯一的 empty/scalar表示，不能保留一元
union/join。ordered semantic sequence不排序，只 flatten nested sequence并
删除 `PureV1` identity；零个非 identity member编码为 scalar `PureV1`，一个
member直接编码为该 scalar，两个以上才允许
`SequenceSummaryV1 { members=[...] }`。因此 nested sequence、含 Pure 的
sequence、empty/singleton sequence都不是另一种合法 wire encoding；importer
必须报 `semantic-summary-not-normalized`，而不是在 hash之后静默修复。
`PhaseRequirementV1.allowed_phases` 按
`Pure, Compute, Action, Commit` 固定 enum顺序去重，authority set按 canonical
encoding排序去重；`RequireBoth` 规范化为 allowed-phase intersection、authority
union与相容的单一 current Owner，不相容则拒绝。
`AnonymousEffectAuthorityV1(F)` 是 $Phi$ 中 `Anon(F)` 的 wire form；
其 `family` 必须 kind为 `Effect`；它与 named identity authority不 alias，
因而 Commit runner的
`Anon(Commit)` requirement可以无损跨模块。
例如 `wire(⟨Commit,{Anon(Commit)},ρ⟩)` 的 `allowed_phases=[Commit]`、
`required_authorities=[AnonymousEffectAuthorityV1(Commit)]` 且
`current_owner=ρ`；三个轴都必须保留。

V1/V2 canonical bytes都是 RFC 8785 JSON Canonicalization Scheme (JCS) 的完整
UTF-8输出：无 BOM/多余 whitespace，object property按 JCS规则排序，
number/string escaping严格采用 JCS serializer。所有 identifier、module
component、origin与其他 string在进入 serializer前必须已经是 Unicode NFC；
非 NFC input拒绝而不是静默改写。因此 normalization中的 “canonical byte
encoding” 唯一指 `JCS(NFC-validated value)`，不依赖宿主 JSON pretty printer。
schema列出的字段
必须且只能出现一次；duplicate key、unknown field/tag、非最小整数、悬空
slot/id、非 canonical collection或另一种等价 encoding一律拒绝。
schema中每一个声明为 `u32` 的 occurrence都必须在进入 variant-specific逻辑前
穷尽检查为 JSON integer且位于 $[0, 2^32-1]$；这不是只检查常见顶层 id的
选择性规则。尤其 `ApplicationEntryWorldV2.application_slot`、
`TypeParameterV2.slot`、`OwnerAuthorityV1.owner.slot` 与
`PromptSlotDeclV1.binder_site_slot` 同样受该规则；负数、boolean与越界整数统一
产生 `wire-u32-out-of-range`。
`TypeRefV2` 的 identity/Owner/clock/contract-bearing variants可递归出现在
任意 nested type；旁表 binder只提供引用作用域，不能替 type本身补猜 index。
`NextTypeV2` 只嵌入 `LaterContractV2`或 V2 contract parameter；
`ValueSummaryExprV2` 的 nominal index/usage 只嵌入
`NominalIndexExprV2`/`UsageExprV2`。这三处不得回落到裸 V1 node，
否则 return-bound summary无法递归代换。
`LegacyTypeRefV2` 只能封装 V1-representable concrete type；包含 symbolic V2
application/computation的 contract不能 downgrade。
`LaterContractBinderV1.clock` 与 nested `LaterContractKindV1.clock` 都必须
是当前 lexical scope中的 live Clock-namespace ref；其 identity必须与
`LaterContract(i,A)`/对应 `NextTypeV1.clock` 的 $i$ 相同，payload type也
必须逐字段相等。只保存 `payload_type` 的 binder不是合法 V1 encoding。
四个 quantified variants在 `TypeRefV1` 内建立 lexical nested scope；
`ForAllIdentityTypeV1`、`ForAllContractTypeV1`、`ForAllOwnerTypeV1`
分别编码 Core 的 `forall i`、`forall p`、`forall ρ`，
legacy `ExistsClockPackageTypeV1` 同时绑定 generative clock identity与依赖它的
`ClockPackageSummary` evidence。importer必须按 binder出现顺序检查 kind、
依赖与 body，禁止把 nested existential/universal无条件全提到 declaration
binder table。
当 `QuantifiedIdentityBinderV1.family` 是 FrameClock等 clock-indexing family时，
`clock_refinement` 必填；否则它必须为 `null`。其中 `identity` 必须恰为
`SlotRefV1 { namespace: Identity, slot: identity_slot }`，并在 body scope中
同时声明 `Clock(clock_slot)` view。`QuantifiedClockBinderV1` 对 existential
package同构地先声明 `identity_slot`，再由必填 `clock_refinement` 声明 paired
Clock view；declaration-level `IdentitySlotDeclV1`/`ClockBinderV1.identity`
使用同一关系。于是 `Cap[i,FrameClock]` 引用 Identity view，`Next[i,A]` 与
`LaterContract(i,A)` 引用 paired Clock view；importer只沿显式 witness校验同一
nominal identity，绝不按相同数值 slot或 source spelling猜 alias。
V2 canonical existential使用 `ExistsClockPackageTypeV2`；其
`QuantifiedClockBinderV2.family_witness` 必须解析为 sealed
`CanonicalFrameClockV2`，不能从任意 `family: Effect` 或裸 refinement推断。
existential的 `summary_binder.kind.ClockPackageSummaryKindV2.clock` 必须恰好
引用这个 paired Clock view，不能另指 declaration或 outer clock；其
`payload_type` 必须与 imported `body` alpha-equal。summary Contract slot即使
不自由出现于 payload type，也必须在 body import前声明，因为它是 unpack时
可用的 sealed package evidence，不能被 importer丢弃。

```text
import_quantified_identity(binder, body, scope):
  i = scope.declare(Identity, binder.identity_slot,
                    binder.family, binder.owner)
  body_scope = scope + i
  if binder.clock_refinement != null:
    r = binder.clock_refinement
    require r.identity == SlotRefV1(Identity, binder.identity_slot)
    c = body_scope.declare(Clock, r.clock_slot,
                           same_nominal_identity = i)
    body_scope += c
  return import_type(body, body_scope)

import_clock_package_v2(clock_binder, summary_binder, body, scope):
  require clock_binder.family_witness ==
    sealed CanonicalFrameClockV2("cire.temporal", "FrameClock")
  i = scope.declare(Identity, clock_binder.identity_slot,
                    FrameClock, clock_binder.owner)
  r = clock_binder.clock_refinement
  require r.identity ==
    SlotRefV1(Identity, clock_binder.identity_slot)
  c = (scope + i).declare(Clock, r.clock_slot,
                          same_nominal_identity = i)
  require summary_binder.kind is ClockPackageSummaryKindV2
  require summary_binder.kind.clock ==
    SlotRefV1(Clock, r.clock_slot)
  A = import_type(summary_binder.kind.payload_type, scope + i + c)
  L = (scope + i + c).declare(
    Contract, summary_binder.contract_slot,
    ClockPackageSummaryKindV2(clock = c, payload_type = A))
  imported_body = import_type(body, scope + i + c + L)
  require alpha_equal(imported_body, weaken(A, L))
  return imported_body

serialize_clock_package_v2(scope, i, c, L, A, body):
  require i is a live Identity binding in scope
  require family(i) is sealed canonical FrameClock and
    clock_family_witness(i) == CanonicalFrameClockV2
  require c is the paired Clock view of i
  require exact_internal_contract_binding(L) ==
    SealedClockPackageSummary(
      identity = i, clock = c, payload_type = A,
      binder_scope = scope + i + c,
      binder_owner = this existential)
  require well_formed(A, scope + i + c) and
    well_formed(body, scope + i + c + L)
  emit clock_binder with identity_slot = slot(i),
    clock_refinement = { clock_slot: slot(c), identity: ref(i) },
    family_witness = CanonicalFrameClockV2, owner = owner(i)
  emit summary_binder with contract_slot = slot(L),
    kind = ClockPackageSummaryKindV2(clock = ref(c), payload_type = A)
  require alpha_equal(body, weaken(A, L))
  emit body under scopes i, c and L

import_packed_next_package_v2(scope, wire):
  require wire.artifact == PackedNextPackageV2 and
    wire.profile == "Cire-TR₀/2026-08-01" and schema_version == 2
  storage = resolve Owner(wire.storage_owner) in scope
  ρc = scope.declare(Owner, wire.child_owner_binder.owner_slot)
  require wire.owner_relation == ChildOwnerWitnessV2(
    parent = ref(storage), child = ref(ρc), relation = DirectChild,
    sealed_origin = exact first-party pack_next)
  require wire.clock_binder.owner == ref(ρc)
  (i, c) = import_clock_binder_v2(scope + ρc, wire.clock_binder)
  require wire.clock_binder.family_witness == CanonicalFrameClockV2
  Sp = import_contract_binder_v2(
    scope + ρc + i + c, wire.summary_binder)
  require Sp.kind == ClockPackageSummaryKindV2(
    clock = ref(c), payload_type = wire.body.payload)
  body = import_type_v2(scope + ρc + i + c + Sp, wire.body)
  require body.kind == NextTypeV2 and body.clock == ref(c)
  require alpha_equal(body.payload, Sp.kind.payload_type)
  L = body.later_contract
  require LaterContractWF(body.later_contract, ref(c), body.payload)
  require SealedPackageSummaryCovers(Sp, L)
  require wire.control_protocol == canonical PackedNextControlProtocolV2
  require wire.sealed_origin resolves to exact first-party pack_next
  return sealOpaquePackedNext(
    storage, exists ρc. exists i,c,Sp. body, wire.control_protocol)
```

oracle envelope在调用 importer前必须以自己的 `DeclarationBindersV2` 验证
`storage_owner` 与所有 outward Owner refs；package内部 existential binder只
引入 child Owner，不能反向充当被删掉的 outer storage binder。
named `PackedNextPackageV2` decoder本身先要求 artifact/profile/schema逐 literal
等于本 profile，并把 `storage_owner` 解码为 Owner namespace的 u32 slot；若
decoder由 envelope调用，还必须在同一 outer Owner scope中解析该 slot。
`owner_relation.parent` 的自洽相等不能替代 namespace/scope resolution。
`PackedNextPackageV2.sealed_origin`、direct-child witness的 sealed origin与所有
first-party summary trust都必须精确等于 `cire.temporal:pack_next` / sealed
`cire.temporal` 常量；任意 forged origin或 trust erasure在 seal前拒绝。

`OwnerIndexedTypeV1.payload=null` 当且仅当 constructor是
`CommitTicket/CommitGate`；其余 owner-indexed constructors必须带 payload。
V2 `PackedNextTypeV2` 始终带 Owner ref与 payload；importer还必须验证其
sealed origin，不接受用户 nominal type冒充。
`LegacyTypeRefV2` 只包装一个完全不含 V2 node的旧 type tree；一旦
Function/PackedNext/Resume等 V2 node嵌在 nominal、builtin application、Next
或 Owner-indexed type内部，serializer必须递归使用对应 V2 variant，不能把
subtree藏进 `TypeRefV1`。`OwnerIndexedTypeV2.payload=null` 的条件与 V1相同。
每个 `ContractParameterV2` 必须按 lexical scope只在
`DeclarationBindersV2.contract_binders` 或
`QuantifiedContractBinderV2` 中解析到唯一 V2 binder，再同时匹配 use site与
binder family。V1 declaration/quantified tables只在显式 legacy decoder内
可见，绝不能作为 V2 lookup fallback。`ClockPackageSummary` parameter只允许
解析到 `ClockPackageSummaryKindV2`；Function/Later可来自两类 V2 binder，
Continuation/Handler只来自 declaration binder。shadowing按最内层 exact
Contract slot处理，跨 family或跨 scope同 slot数字不匹配。Function kind还
必须逐字段匹配 visible row；`AppliedContractV2.application_slot` 是每次
invocation的 observer入口。

`ContractRefV2` resolution不允许只凭“像一个函数”或只凭 hash成功。
`ImportedFunctionRefV2(module,name,artifact_hash)` 必须在当前 artifact的 import
table中解析到同一个三元组；hash目标必须是该 module/name实际导出的 root
`FunctionContractV2`。hash存在但 export name/module不一致产生
`imported-function-export-mismatch`。`LocalFunctionRefV2(declaration_slot)` 只在
当前 module的 local declaration table中解析；slot必须唯一指向带非 null
`FunctionContractKindV2` 的 root contract，否则产生
`local-function-ref-unresolved`。二者都不能 fallback到同 kind的 contract
parameter或另一个 local declaration。

`ContractSubstitutionEntryV2` 把一个 contract binder映射到 exact
`ContractRefV2`，不映射到某次 application。每次使用该 substituted contract
仍创建独立 `AppliedContractV2`，保存自己的 callee/actual summaries、entry
world与完整 substitution；因此同一个 contract actual被调用两次会得到两个
application slots及两套 alpha-refreshed site/Q ids，而不会共享 actual/world。
求值 `InvokeV2` 时，contract/type/Owner等 substitution完成后，还必须按 source
`parameter_binders` 的 declaration order把本 application的
`actual_arguments` 代入被调 path的全部 term-level projection：完整
`ValueSummaryExprV2`、Parameter `SlotRefV1/SlotRefV2`、Argument provenance与
Argument capture。source-derived local ids先按本 application qualification。
随后以完整 actual summary（type、nominal、provenance、capture、usage以及可选
source）求解并 discharge全部 Call-stage Q，之后才把仍存活的 term projection
materialize进 path；actual summary中 caller-owned refs不重新 qualification。
`ValueSummaryExprV2.source=null` 对纯 computed actual是合法的：若 Call-stage
obligation已由 summary其余字段 discharge，就不需要凭空构造 slot；若 surviving
HandlerInstall Q、Lambda或其他 path observer仍含该 formal的裸
`Parameter SlotRef`，importer必须产生 `term-actual-source-unavailable`，不得
assert/crash或伪造 slot。
因此同一 imported function在 app 0收到 `Parameter/0`、app 1收到
`Parameter/1` 时，两条 retained Lambda actual summary必须分别保存 0与 1；
只替换 type/contract而保留 source formal Parameter/0是不完整实例化。
当该 ref是 imported root contract，同一 outer application的 Owner/identity/
Clock substitution必须先把 imported declaration kind alpha-instantiate到 use-site
binder kind；只写 contract hash而留空这些必需 nominal mapping不能通过
`ContractWF`。
`AppliedContractV2.callee_summary.type` 必须是
`FunctionTypeV2(instantiated_parameter, instantiated_result,
application.contract)`；nominal “function sentinel”不能替代这条 T-App premise。
T-App先要求每一类 substitution domain恰好等于目标 declaration对应 binder
slots（不缺失、不多出、不重复），再作 capture-avoiding substitution。若
instantiated parameter是 canonical `*Arguments` pack，其 elements是 ordered
formal parameter list；否则它是单参数 list。`actual_arguments` 的长度必须
精确相等，且每个 `ValueSummaryExprV2.type` 按位置逐字段等于对应 formal；
分别以 `application-arity-mismatch` 与
`application-argument-type-mismatch` 拒绝。`entry_world` 还必须是带同一
`application_slot` 的 `ApplicationEntryWorldV2`。这些 premise对 imported、
local与 contract-parameter ref统一成立。
每个 row argument必须先以封闭 `RowExprV1` variant递归解码，再代入 kind中
全部 `TailV1(Row slot)`；未知 row tag不能作为 opaque JSON通过。imported/local
target的六类 substitution domain必须分别精确等于 declaration binders；
`ContractParameterRefV2` 已由 lexical binder给出完整 instantiated kind，因而
其 declaration-domain为空，任何额外 slot（即使未被结果使用）都是
`contract-parameter-inconsistent-instantiation`。
对 `PathBindV2(prefix,binder,continuation,PreserveTerminalV2)` 的实际求值先原样
保留 prefix 的每个 Aborts/Transfers，只对每个 Returns建立 binder并求值一次
continuation。因而一个具有 1 Returns、1 Aborts、2 Transfers 的 callback顺序
调用两次时，结果严格为第一调用的 3 个 terminal bypass path，加上其唯一
Returns进入第二调用得到的 4 个 path，共 7 个；不能用“两次调用”布尔字段代替
这次 computation evaluation。

这 7 项不是 outcome label列表。每个 `InvokeV2` 先以 application slot对
site/claim/Q key做 alpha refresh，完成全部 type/Owner/identity/clock/contract
substitution，在 invocation点 discharge Call-stage Q，并保留
HandlerInstall-stage Q及其 exact Lambda key。`PathBindV2` 对 returning prefix
path $f$ 与 continuation path $g$ 的唯一完整组合为：

```text
composePath(f, g):
  require f.outcome is ReturnsV2
  return PathContractV2(
    outcome               = if g.outcome is ReturnsV2 then
                              ReturnsV2(
                                transitionSeq(
                                  f.outcome.transition,
                                  g.outcome.transition),
                                g.outcome.result_transformer)
                            else g.outcome,
    residual_row          = rowSeq(f.residual_row, g.residual_row),
    attributed_demand     = canonicalUnion(f.demand, g.demand),
    suspension            = attributedJoin(f.suspension, g.suspension),
    semantic_summary      = OrderedSummaryNF(
                              f.semantic_summary, g.semantic_summary),
    usage                 = usageSeq(f.usage, g.usage),
    required_phase        = RequireBoth(f.required_phase, g.required_phase),
    ParametricObligations = canonicalQualifiedUnion(f.Q, g.Q),
    LatentSites           = canonicalQualifiedUnion(f.Lambda, g.Lambda))
```

prefix的 Aborts/Transfers则整个 `PathContractV2` byte-for-byte旁路，不进入上述
组合。故 HOF golden必须覆盖 7 个 complete canonical path bytes（或其 JCS
hash），并逐项覆盖 row/demand/suspension/summary/usage/phase/Q/Lambda；只固定
7个 tag或trace label不足以构成 observer oracle。

`PathBindV2.return_binder` 同时声明 `ReturnSlotRefV2`、
`ReturnWorldV2`、`ReturnProvenanceV2`、`ReturnCaptureV2` 与
`ReturnNominalIndexV2`、`ReturnUsageV2`、`ReturnBoundResultV2` 的同号
slot。它们只在 continuation subtree内可见；
prefix terminal path不进入该 scope。V2 occurs/scope check递归覆盖 type、value
summary、result transformer、provenance、capture和 world，因而不能用 V1
expression偷偷绕过 return-binder substitution。
`ReturnBinderV2` 的 world/nominal/provenance/capture/usage 是 prefix Returns path
经 exact application substitution后的 concrete projection，在 binder scope建立之前检查；
它们不得反向引用自身 `return_slot`。只有 continuation subtree可以用
`Return*V2(return_slot)` 引用这些已绑定的投影。
因此 `PathContractV2.usage` 与 `LiveAcrossSiteV2.usage` 都使用
`UsageExprV2`，`LiveAcrossSiteV2.slot` 与 V2 obligation 的 value-slot字段使用
`SlotRefV2`；一个 return-bound `ResumeTypeRefV2` 才能在 continuation 的
path usage、live-site usage与 $Q$ 中被引用。importer必须由同一个 lexical
return-binder type environment验证这三类引用；普通返回值不能借
`ReturnUsageV2` 伪造 disposition authority。
当 prefix是 abstract `ContractParameterRefV2` application时，kind projection虽
不能提供 concrete source path，binder world中的 `ApplicationEntryWorldV2`
lineage仍必须存在且只能指向该 prefix的同一个 `application_slot`；不能把 app0
的 binder接到 app1 entry。imported/local concrete target还在此基础上检查
exact world transition、provenance与 capture。两类失败统一产生
`contract-parameter-inconsistent-instantiation`。

`HandlerContractV2.applications` 是 return computation与全部 clause
computations共享的原子 application ledger，application slot在整个 handler
contract内唯一。`InvokeV2` 必须在该 ledger解析；clause disposition binder
只扩展其所属 `ClauseComputationV2.computation` 的 lexical context，不扩展
handler return或其他 clause。位于 `CireHandlerContractOracleV2` 时，oracle
`binders` 是整个 handler contract的 caller declaration environment：type/row/
contract/identity/handler-contract table必须传入 applications与 computation
ContractWF；`handled_entry`、header residual row、return/clause path、latent site、
nested suffix/cleanup、每层 application substitution及每个 instantiated target
public row都用同一 table递归检查 kind、Row closure、selector scope与 family。
普通 nested type中的 inline `HandlerContractV2`继承同一 table；inline
`FunctionContractV2`则开始自己的 declaration scope。imported/local function
target同样只按自身 declaration验证，caller scope仅支配 reference、substitution与
实例化 public row。Return binder与 clause disposition binder仍分别只扩展自己的
continuation/clause subtree，不得泄入 handler header、return或其他 clause。V2
serializer/importer不得把其中任何一段降级成
`ClauseFlowSetV1`、`SuffixContractV1` 或从旧 flow字段重建。

Normative V2 import is context-sensitive and exhaustive:
