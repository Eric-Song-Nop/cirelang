#import "../shared.typ": *

== Usage分析

```text
usage(sequence e1; e2) = usage(e1) + usage(e2)
usage(if c { e1 } else { e2 }) =
  usage(c) + join(usage(e1), usage(e2))
usage(match ...) =
  usage(scrutinee) + join(branch usages)
usage(many-call closure capturing k) =
  ω when usage(body, k) > 0
```

分析是 per-resumption map，不是一个全局数字。

== 终止 measure

对互递归 checker使用 lexicographic measure：

$
  mu=⟨n_"ast",n_"type",n_"row",n_"clause",n_"site"⟩_"lex"
$

五个分量依次是 remaining AST node、remaining type structure、unsolved row
constraint、unchecked clause 与 unsolved site schema 的有限数量。

- `synth/check` 的 recursive call进入严格 AST 子树；
- `check` 转 `synth` 后立即进行有限 subtype/unification；
- occurs check禁止无限 type；
- row normalization对有限 entry集合终止；
- handler clause list逐项缩短；
- site pass只遍历 finite Typed Core；跨module $Lambda$ worklist memoize，
  recursive SCC要求 finite annotation而不递归展开；
- Imported `CanonicalSurfaceV1` input已经是 finite normalized HIR；surface producer的 progress
  由唯一 surface authority单独证明。

在 kind、row predicate、trait/effect resolution均可判定的假设下，
`Cire-v1.0` type checking可判定。

== Interface serialization

Public signature即使省略 hidden semantic fields，也必须序列化完整 contract；named `def` 的
parameter/result/generic/effect row本身不得省略：

```text
normalized effect row
normal-returnability + world transformer
suspension attribution + upper bound
result provenance/capture transformer
sealed LaterContract L carried by every internal Next[ι, A, L]
sealed ClockPackageSummary S existentially bound by every clock package
solved or generalized Evidence binders for hidden C / L / S
closure/handler environment provenance + captures + latent one-shot usage
required invocation phase / authority
finite parametric boundary/stability/outlives obligations Q
finite latent operation-site schemas Λ
TemporalStable / Shareable constraints
handler certificate requirements and trust origin
generative identity binders
Owner/outlives constraints
```

否则 separate compilation会把安全判断降级成“本地 HIR 碰巧知道”。
