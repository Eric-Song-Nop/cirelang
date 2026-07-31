# Cire 规范状态与实现重启路线

> 更新基线：2026-08-01 · [`Cire-TR₀/2026-08-01`](../spec-status.md)

## 当前状态

仓库当前是纯设计仓库：

```text
语言规范与解释文档   已有
正负 conformance 例子  已建立首批 corpus
机械化证明            尚无
parser / type checker 尚无
runtime / Wasm backend 尚无
标准库 / LSP           尚无
```

历史 source、diagnostic、lexer、PEG parser、测试实现以及 MoonBit 专用
agent/tooling 模板已经删除。这样做是为了消除“旧 parser 能识别什么，就把
什么当成语言”的错误权威关系；历史提交仍可用于考古，但不能作为新实现的
baseline。

## 规范先行的分层

```text
版本化 profile
  → 完整 surface grammar
  → origin-preserving Surface HIR
  → 明确的 surface-to-Core elaboration
  → Kernel HIR judgments
  → kind / row / type / capture / usage / world / Owner checking
  → runtime contracts
  → Wasm lowering 与工具链
```

任何实现层都必须能指出自己对应的 profile rule 或 conformance case。

## 重启实现前的入口条件

1. surface 的词法、优先级、block、pattern、label、postfix/trailing lambda
   和 `RowExpr` 有唯一 grammar；
2. `def` n-ary tuple lowering、implicit `return`、四种 mode、`with`
   generativity、route-aware `Δ` row removal、capture/escape、once
   disposition、`Transfers(ParkContractV2)` 和 temporal contract有唯一
   elaboration；
3. `examples/spec/` 的 accept/reject case 记录预期 type、row、world、
   capture、usage、Owner obligation 或 diagnostic rule id；
4. interface schema 能以 versioned `ParametricObligations` /
   `LatentSites` 序列化 handler certificate、cleanup contract 和 `Q/Λ`；
5. 证明先覆盖 surface elaboration 与 CBV Core semantics，再覆盖
   row/Δ + handler + one-shot、world/clock、phase/Owner 与 incremental
   replacement。

## 建议实现顺序

1. immutable source、UTF-16 span、diagnostic 与 lossless CST shell；
2. 按完整 grammar 实现 token-oriented PEG，不引入 legacy syntax profile；
3. Surface HIR 与 origin-preserving elaboration；
4. kind、`RowExpr` normalization、resolver 与 handler exactness；
5. bidirectional type/effect/capture/usage checking；
6. world/clock、phase authority 与 Owner generation/claim；
7. query cache、incremental parsing、formatter 与 LSP；
8. runtime、Wasm backend 和第一方协议。

正确性验收始终是：

```text
implementation result == profile expectation
```

而不是：

```text
profile meaning == implementation accident
```

完整状态矩阵见[设计基线与状态矩阵](../spec-status.md)，未来工程约束见
[编译器前端架构](../compiler-architecture.md)。
