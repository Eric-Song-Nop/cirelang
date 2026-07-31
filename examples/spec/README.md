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

`interfaces/choose-once-function-contract.json` 是可独立导入的
`FunctionContractV2`，实际含 nonempty Q与 `LatentSiteV2`；
`interfaces/q-lambda-call-install.json` 是
`CireSpecInterfaceOracleV2` envelope。其 `FunctionContractV2` 以两个
`AppliedContractV2` 和一个有序 `PathBindV2` 固定同一 imported callback的
两次调用：每次 Call Q在自己的 application处 discharge，HandlerInstall Q
与 Lambda exact key以 `(application_slot,local_id)` 保留，两个 invocation
site id不得 alias；每个 callee summary均为与同一 ImportedFunctionRef及其
instantiated declaration kind一致的 `FunctionTypeV2`，prefix terminal path
必须 byte-for-byte旁路第二次调用。
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
解析该 local declaration。其 composition probe另外固定 NextWorld+SameWorld、
Once+Once=Many，以及覆盖 prompt slot的 collision-free application/local-id
pairing。
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
decoder验证，不能从被验证 certificate自身反向提取信任。
`interfaces/handler-forward-contract.json` 是正向
`HandlerContractV2`/`DelegatesV2`/`ForwardContractV2` fixture：handler-level
application ledger、clause disposition lexical scope、exclusive
Open→Forwarded evidence，以及 return-bound Resume在 path usage、live-site
usage和 V2 Q slot中的引用全部由同一 context-sensitive decoder检查。Forward
route必须是 nearest lexical outer prompt；entry/operation使用封闭 variant，且
mode quantity精确为 fun/once→Once、ctl→Many、abort→Zero。
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
origin/outer Owner/certificate trust、control protocol及runtime schema/initial/table
破坏。JSON oracle的 `canonical_json`
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

`diagnostics-v2.json` 冻结 corpus oracle可引用的 diagnostic id与产生 stage；
新增或重命名 id需要新 registry version，不能让 parser recovery改变同一
profile的静态诊断接口。

这些 case 是首批 corpus。完整规则来源：

- [状态矩阵](../../docs/spec-status.md)
- [完整表面语法](../../docs/surface-grammar.md)
- [Cire-TR₀ 形式化](../../docs/temporal-reactivity-formalization.typ)
