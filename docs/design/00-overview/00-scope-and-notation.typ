#import "../shared.typ": *

= 范围、目标与非目标

== 目标

本文把以下设计写成可以逐规则检查的 canonical calculus：

- generative named clock identity；
- `Next[frame, A]`、`delay[frame] { ... }` 与 `advance(...)`；
- effect row、具名 capability 与四种 resumption mode；
- successful resumption 的 logical-world transition；
- suspension、handler semantic summary 与 residual row 的分离；
- capture、temporal provenance、Owner、generation 与 one-shot disposition；
- `Source`、`Live`、`Event`、`Signal`、`Task`、`Resource` 的第一方契约；
- fixed-Epoch、continuation cut、candidate replacement 与 Commit gate；
- 一个结构递归、双向、算法化的 type checker；
- 完整普通语言 foundation、package/API exact schema、Component boundary；
- 以 profile id 导入 canonical surface grammar 的唯一 elaboration boundary。

== 非目标

本文不提供：

- 编译器、runtime 或 Wasm lowering 实现；
- mechanized proof；
- 一般 dependent type；
- 一般 linear/affine user value；
- 任意 effectful `Later`；
- scheduler fairness 或宿主最终产生 frame 的证明；
- 通用 Derived DAG 或 cycle convergence 语义；
- native-async Component ABI、Wasm threads/GC/exception/stack-switching；
- 通用 `Event::on` / `Event::on_async` 或 public generic Plan/Commit API。

Surface spelling 由唯一 surface authority 固定；本文对其 normalized HIR 中所有
`Cire-v1.0` declaration/expression/pattern 类别给出静态、wire 与 runtime meaning。
任何未列入本 profile 的 spelling、schema tag、registry entry 或 host behavior 都是拒绝，
不能由历史文档、实现惯例或所谓“现有语言设计”补齐。

== 已冻结的 profile 选择

旧 TR0 的开放轴在 successor profile 中全部固定；下表是 exact profile fact，不是实现参数：

#table(
  columns: (1.1fr, 2.5fr, 2.6fr),
  [*参数*], [*候选值*], [*本文使用方式*],
  [`clock-repr`], [`restricted singleton capability`],
  [Direct `app : F` binder 引入 fresh identity；surface 不使用 `cap` marker。],
  [`checkpoint-profile`], [`sealed fixed-Epoch first-party runner`],
  [Generic public checkpoint/Plan/Commit 不存在；runner 使用 private one-shot claim。],
  [`capture-refinement`], [`declared-max`],
  [按 operation 声明的最大 mode 检查；没有 lexical specialization profile。],
  [`task-outcome`], [`TaskOutcome[A,E]`],
  [`Task` 是 multi-waiter broadcast completion；cancel reason 与 result exact typed。],
  [`commit-linearity`], [`sealed dynamic single-claim`],
  [claim 是 runtime protocol authority，不作为一般 user affine value。],
)

= 记号、归纳对象与推导高度

== 元变量

#table(
  columns: (0.9fr, 2.2fr, 3fr),
  [*记号*], [*类别*], [*含义*],
  [$A, B, tau$], [type], [普通值类型],
  [$F$], [effect family], [名义 effect 或满足 ability 的 effect 参数],
  [$iota$], [capability identity], [generative、不可伪造的 term identity],
  [$rho$], [Owner region], [静态 lifetime/ownership region],
  [$g$], [generation], [运行时 incarnation；不由静态 region 替代],
  [$epsilon$], [effect row], [尚未被当前 handler 消除的 operation 请求],
  [$chi$], [result capture set], [表达式结果可达的 capability、Owner 或 authority],
  [$chi_k$], [suffix capture set], [被 continuation/checkpoint 保留的动态后缀环境],
  [$Pi_k$], [suffix provenance map], [live-across-site binder 的 type/provenance，独立于 capture],
  [$delta$], [semantic summary], [handler law、host observability 与 replay evidence],
  [$s$], [attributed suspension summary], [direct grade及按 effect entry归因的 suspension],
  [$q$], [usage grade], [$0$、$1$ 或 $omega$],
  [$u$], [latent usage map], [一次调用某 closure 会使用哪些 one-shot authority],
  [$pi$], [provenance], [表达式结果的 lifetime / callback / generation 来源],
  [$Pi$], [provenance environment], [逐 binder 保存 type、provenance 与 capture],
  [$Phi$], [phase/authority], [`Pure`、`Compute`、`Action`、`Commit` 及其 authority],
  [$Theta$], [temporal context], [值 zone 与 clock lock 的有序序列],
  [$Omega$], [usage context], [one-shot resumption/disposition 的剩余责任],
)

== 推导是有限树

每个 typing judgment 都由本文件中的 inference rule 归纳生成。若 $D$ 是一棵
推导树，定义其高度：

$
  "height"(D) =
  cases(
    1, &D " has no premises",
    1 + max_(D_i in "premises"(D)) "height"(D_i), &"otherwise",
  )
$

因此：

- 对 typing derivation 的性质使用 $"height"(D)$ 归纳；
- 算法化 checker 对 AST 大小结构递归；
- row normalization、kind checking 和 unification 使用独立的有限 worklist；
- Surface progress由 imported canonical surface artifact及其 conformance proof承担；本文不定义 PEG。

== 静态上下文

主要上下文为：

$
  K ; I ; Phi ; Omega @ Theta
$

其中：

#table(
  columns: (0.8fr, 4.8fr),
  [$K$], [kind、type constructor、ability、effect signature、row evidence 与 sealed witness。],
  [$I$], [identity context，映射 $iota ↦ (F, rho, "origin", "trust")$。],
  [$Phi$], [$(phi,A_u,rho_o)$：当前 phase、可用 authority 与 current Owner。],
  [$Omega$], [resumption 的 open/closed disposition state与剩余 call budget。],
  [$Theta$], [Fitch temporal context；形如 $Gamma_0, "lock"_i, Gamma_1, ...$。],
)

定义 $I ⊢ i:F@rho$ 当且仅当存在 $o,t$ 使
$I(i)=⟨F,rho,o,t⟩$。后文示例写 $I(i)=(F,rho)$ 时只是省略不参与该推导的
origin/trust字段。

一个 value binder 写作：

$
  x : A @[pi] ▷ chi
$

$pi$ 是 provenance，例如 `Stable`、`Region(r)`、`Callback(c)`、
`Owner(ρ)` 或 `GenerationBound(ρ)`。最后一项只表示“受 Owner 当前运行时
generation 约束”，不把具体运行时 generation $g$ 提升为 type index。
普通 immutable ADT 可以有 $chi = emptyset$，但仍可能因为
$pi = "Callback"(c)$ 而不能跨 temporal/suspension boundary。

本文中的 $chi$ 只描述*结果可达 capture*，不再兼任“执行时碰过什么
authority”。Operation receiver、handler policy 与临时参数分别由
$epsilon$、$delta$ 和 typing derivation记录；被挂起后缀的 authority由独立
judgment：

$
  K;I;Phi@Theta ⊢ "suffix"(E) ▷ Pi_k ; chi_k ; u_k
$

计算。这样 `let x = use_cap(); 0` 的结果不必伪称 capture `cap`，而
closure/checkpoint 真正保存 `cap` 时仍会被 boundary checker发现。
