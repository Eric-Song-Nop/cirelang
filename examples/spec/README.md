# Cire-TR₀ conformance corpus

> **Profile:** `Cire-TR₀/2026-07-31`

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
| `accept/owner-park.cire` | accept | sealed completion source、terminal `Transfers(ParkContract)` |
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
| `reject/open-secondary-row.cire` | reject | TR₀ operation secondary row 必须 closed |
| `reject/bare-open-secondary-row.cire` | reject | bare `! E` 经 recovery CST 到 closed-only WF |

`interfaces/q-lambda-call-install.json` 是
`CireSpecInterfaceOracleV1` envelope：`subject/source/expectation` 是 corpus
metadata，真正 wire payload只在 `contract` 字段，且必须符合
`FunctionContractV1`。它关联 `interfaces/choose-once.cire`；call只能
discharge `stage=Call` 的 obligation，而 `HandlerInstall` obligation和
latent site必须保留到 fresh prompt存在的 installation。
`interfaces/flow-abort-transfer-owner.json` 则逐 variant固定
`Aborts`、`Transfers(ParkContractV1)`、`OwnerBoundV1`、root route以及
Owner/generation-CAS wire形状；它是 union-variant oracle，不伪装成某个
FunctionContract source projection。

`diagnostics-v1.json` 冻结 corpus oracle可引用的 diagnostic id与产生 stage；
新增或重命名 id需要新 registry version，不能让 parser recovery改变同一
profile的静态诊断接口。

这些 case 是首批 corpus。完整规则来源：

- [状态矩阵](../../docs/spec-status.md)
- [完整表面语法](../../docs/surface-grammar.md)
- [Cire-TR₀ 形式化](../../docs/temporal-reactivity-formalization.typ)
