# Cire-TR₀ conformance corpus

> **Profile:** `Cire-TR₀/2026-07-31`

这里保存规范级输入，不是编译器测试实现。每个 `.cire` 文件头部记录：

```text
profile
expect
rule
```

`accept` 表示存在符合 profile 的静态推导；`reject` 表示必须由指定 rule
拒绝。未来测试 harness 应另外保存 resolved identity graph、normalized Core、
type、row、world、capture、usage 和 Owner evidence，不得只检查 parser 是否
接受。

| Case | 结论 | 核心义务 |
|---|---|---|
| `accept/named-reader.cire` | accept | 双形参列表、ability/effect/cap、implicit return |
| `accept/row-union.cire` | accept | kinded `RowExpr` union |
| `accept/label-order.cire` | accept | positional-first、label 唯一、source-order |
| `accept/four-modes.cire` | accept | mode lowering、answer transform、explicit return |
| `accept/temporal-next.cire` | accept | fresh clock、delay/advance、same clock |
| `accept/owner-park.cire` | accept | sealed completion source、terminal `Transfers(ParkContract)` |
| `accept/secondary-row.cire` | accept | operation dispatch entry ∪ `SecondaryRow` |
| `reject/two-row-tails.cire` | reject | literal 最多一个 open tail |
| `reject/positional-after-label.cire` | reject | labelled-call grammar |
| `reject/discontinue.cire` | reject | TR₀ 没有 discontinue primitive |
| `reject/named-escape.cire` | reject | generative identity nonescape |
| `reject/ctl-captures-once.cire` | reject | multi-shot 不复制 one-shot authority |
| `reject/early-advance.cire` | reject | `T-Advance` 需要对应 clock lock |
| `reject/abort-resumes-next.cire` | reject | abort operation 没有 successful resumption |
| `reject/park-is-not-unit.cire` | reject | T-Park 不产生 `Unit` 或普通 expression result |

这些 case 是首批 corpus。完整规则来源：

- [状态矩阵](../../docs/spec-status.md)
- [完整表面语法](../../docs/surface-grammar.md)
- [Cire-TR₀ 形式化](../../docs/temporal-reactivity-formalization.typ)
