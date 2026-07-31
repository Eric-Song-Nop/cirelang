#set page(
  paper: "a4",
  margin: (x: 22mm, y: 20mm),
  numbering: "1",
)
#set text(size: 10pt, lang: "zh")
#set par(justify: true, leading: 0.72em)
#set heading(numbering: "1.1")
#set table(
  stroke: 0.5pt + luma(190),
  inset: (x: 6pt, y: 4pt),
)

#show raw.where(block: true): it => block(
  width: 100%,
  fill: luma(246),
  inset: 8pt,
  radius: 3pt,
  breakable: true,
  it,
)

#let status(name, body) = block(
  width: 100%,
  fill: rgb("#f4f7fb"),
  stroke: (left: 3pt + rgb("#476a92")),
  inset: (left: 10pt, right: 8pt, y: 7pt),
  radius: 2pt,
  [
    *#name* \
    #body
  ],
)

#let warning(body) = block(
  width: 100%,
  fill: rgb("#fff8e8"),
  stroke: (left: 3pt + rgb("#b88016")),
  inset: (left: 10pt, right: 8pt, y: 7pt),
  radius: 2pt,
  body,
)

#let irule(name, premises, conclusion) = block(
  breakable: false,
  inset: (y: 0.45em),
  align(center, [
    $ frac(
      #stack(spacing: 0.3em, ..premises),
      #conclusion,
    ) #h(0.7em) #text(size: 8pt, fill: gray)[#name] $
  ]),
)

#align(center)[
  #text(size: 22pt, weight: "bold")[
    Cire Temporal、Effect 与 Incremental Core
  ]

  #v(5pt)
  #text(size: 15pt)[版本化类型形式化、算法化检查与 PEG 语法]

  #v(14pt)
  #text(fill: luma(90))[Canonical design profile · $"Cire-TR"_0$ · 2026-07-31]
]

#v(18pt)

#status(
  [文档状态],
  [
    本文是 `Cire-TR₀/2026-07-31` 的 canonical semantic baseline。它固定术语、
    judgment、规则边界、PEG 识别形状和待证明性质；仍开放的选择被显式参数化。
    其中的 theorem 是陈述或证明义务，不代表已经完成机械化证明。

    仓库当前不包含编译器或 runtime。完整 concrete syntax 由
    `surface-grammar.md` 定义；未来 parser 与 conformance tests必须服从规范，
    不能反向定义语言。
  ],
)

#v(8pt)

#status(
  [本轮模型选择],
  [
    $"Cire-TR"_0$ 采用纯 `Next`、Fitch-style clock lock、world-indexed
    resumption、独立 suspension summary、handler-instance law、
    Owner-bound one-shot disposition，以及动态 single-claim `CommitGate`。
    它不加入一般 affine value calculus，也不把 `Task`、`Live` 与 `Next`
    合并。
  ],
)

#v(16pt)
#outline(indent: auto)
#pagebreak()

= 范围、目标与非目标

== 目标

本文把以下设计写成可以逐规则检查的候选 calculus：

- generative named clock identity；
- `Next[frame, A]`、`delay[frame] { ... }` 与 `advance(...)`；
- effect row、具名 capability 与四种 resumption mode；
- successful resumption 的 logical-world transition；
- suspension、handler semantic summary 与 residual row 的分离；
- capture、temporal provenance、Owner、generation 与 one-shot disposition；
- `Source`、`Live`、`Event`、`Signal`、`Task`、`Resource` 的第一方契约；
- fixed-Epoch、continuation cut、candidate replacement 与 Commit gate；
- 一个结构递归、双向、算法化的 type checker；
- 以 profile id导入 canonical surface grammar 的 elaboration boundary。

== 非目标

本文不提供：

- 编译器、runtime 或 Wasm lowering 实现；
- mechanized proof；
- 一般 dependent type；
- 一般 linear/affine user value；
- 任意 effectful `Later`；
- scheduler fairness 或宿主最终产生 frame 的证明；
- 通用 Derived DAG 或 cycle convergence 语义；
- 当前所有 MoonBit 风格表达式的完整语言规范。

普通 Cire 语法仅形式化到本 calculus 所需的 fragment。未列出的 ADT、
pattern、trait、method resolution 等构造按现有语言设计正交组合。

== 参数化的开放选择

本模型把仍未冻结的设计写成参数，而不是隐藏成假定：

#table(
  columns: (1.1fr, 2.5fr, 2.6fr),
  [*参数*], [*候选值*], [*本文使用方式*],
  [`clock-repr`], [`singleton-cap` / `fresh-phantom`],
  [规则写 `singleton-cap`；替换表示必须保持 freshness 与 escape theorem。],
  [`checkpoint-profile`], [`trusted-ctl` / `sealed-checkpoint`],
  [静态 surface 仍是 `ctl`；增量定理只对满足 sealed/trusted protocol 的 runner 成立。],
  [`capture-refinement`], [`declared-max` / `lexical-handler`],
  [基线按 operation 声明的最大 mode 检查；词法 specialization 是可选扩展。],
  [`task-outcome`], [`Result` / effect / discontinuation],
  [Core 使用抽象结果类型 $R$，不冻结 surface error channel。],
  [`commit-linearity`], [`dynamic-claim` / future affine value],
  [本模型只证明动态 claim 的 at-most-once，不声称 capability 静态线性。],
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
- PEG repetition 必须消费至少一个 significant token，禁止无进展递归。

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

= Token-oriented PEG 的形式语义 <peg-semantics>

== 识别关系

未来 parser 采用手写 token-oriented PEG。本文忽略 missing-token insertion
与 recovery，仅形式化正常 recognition language。令 token stream 为
$sigma = t_0 ... t_n$，parser expression 为 $p$，则：

$
  G ; sigma ⊢ p @ j ⇓ r
$

归纳对象为：

$
  p ::= epsilon_p | a | N | p_1 p_2 | p_1 / p_2
      | &p | !p | p^* | "CUT"
$

其中 $a$ 是 significant terminal，$N$ 是 nonterminal。Sugar：

$
  p? = p / epsilon_p
  quad
  p^+ = p p^*
$

Grammar well-formedness $"WF"(G)$ 要求每个 nonterminal有唯一 body、
不存在未推进 significant cursor就回到同一 nonterminal的 recursion cycle，
并且 repetition body不 nullable；本 profile因此不接受任何直接或间接
left recursion。实际 parser还用 active call key $(N,j,"flavor")$ 拒绝同
rule/position/flavor 的递归重入，作为实现层保险。

结果为：

$
  r ::= "ok"(j', c) | "fail"(j, X, c)
$

其中 $c in {0, 1}$ 表示当前 rule-local branch 是否已经经过 `CUT`；
$X$ 是 expectation 集。Cursor 在匹配 terminal 前跳过 trivia，但消费成功时
把 trivia 与 significant token 一并送入 lossless CST event stream。

`CUT` 是一个零宽 parser meta-expression，而不是 Cire token。它把当前
ordered-choice branch 的 commit bit 置为 $1$；sequence 会把该 bit 传播到
后续失败。Lookahead 在 probe sandbox 中运行，既不消费 token，也不把
probe 内部的 commit bit泄漏到外层。

== 基本 PEG 规则

#irule(
  [PEG-Empty],
  (),
  [$G;sigma ⊢ epsilon_p @j ⇓ "ok"(j,0)$],
)

#irule(
  [PEG-Terminal],
  (
    [$"nextSig"(sigma, j) = (j_s, t) quad "kind"(t) = a$],
  ),
  [$G; sigma ⊢ a @ j ⇓ "ok"(j_s + 1, 0)$],
)

#irule(
  [PEG-Terminal-Fail],
  (
    [$"nextSig"(sigma,j)=(j_s,t)$],
    [$"kind"(t) != a$],
  ),
  [$G;sigma ⊢ a @j ⇓ "fail"(j_s,{a},0)$],
)

#irule(
  [PEG-Seq],
  (
    [$G; sigma ⊢ p_1 @ j ⇓ "ok"(j_1, c_1)$],
    [$G; sigma ⊢ p_2 @ j_1 ⇓ "ok"(j_2, c_2)$],
  ),
  [$G; sigma ⊢ p_1 p_2 @ j ⇓ "ok"(j_2, c_1 or c_2)$],
)

#irule(
  [PEG-Seq-Fail-L],
  (
    [$G;sigma ⊢ p_1 @j ⇓ "fail"(j_1,X,c_1)$],
  ),
  [$G;sigma ⊢ p_1 p_2 @j ⇓ "fail"(j_1,X,c_1)$],
)

#irule(
  [PEG-Seq-Fail-R],
  (
    [$G;sigma ⊢ p_1 @j ⇓ "ok"(j_1,c_1)$],
    [$G;sigma ⊢ p_2 @j_1 ⇓ "fail"(j_2,X,c_2)$],
  ),
  [$G;sigma ⊢ p_1 p_2 @j ⇓ "fail"(j_2,X,c_1 or c_2)$],
)

#irule(
  [PEG-Choice-L],
  (
    [$G; sigma ⊢ p_1 @ j ⇓ "ok"(j', c)$],
  ),
  [$G; sigma ⊢ p_1 / p_2 @ j ⇓ "ok"(j', c)$],
)

#irule(
  [PEG-Choice-R],
  (
    [$G; sigma ⊢ p_1 @ j ⇓ "fail"(j_1, X, 0)$],
    [$G; sigma ⊢ p_2 @ j ⇓ r$],
  ),
  [$G; sigma ⊢ p_1 / p_2 @ j ⇓ r$],
)

#irule(
  [PEG-Choice-Cut],
  (
    [$G; sigma ⊢ p_1 @ j ⇓ "fail"(j_1, X, 1)$],
  ),
  [$G; sigma ⊢ p_1 / p_2 @ j ⇓ "fail"(j_1, X, 1)$],
)

#irule(
  [PEG-Cut],
  (),
  [$G; sigma ⊢ "CUT" @ j ⇓ "ok"(j,1)$],
)

#irule(
  [PEG-Lookahead-OK],
  (
    [$G; sigma ⊢ p @ j ⇓ "ok"(j', c)$],
  ),
  [$G; sigma ⊢ &p @ j ⇓ "ok"(j, 0)$],
)

#irule(
  [PEG-Lookahead-Fail],
  (
    [$G;sigma ⊢ p @j ⇓ "fail"(j',X,c)$],
  ),
  [$G;sigma ⊢ &p @j ⇓ "fail"(j,X,0)$],
)

#irule(
  [PEG-Negative-OK],
  (
    [$G;sigma ⊢ p @j ⇓ "fail"(j',X,c)$],
  ),
  [$G;sigma ⊢ !p @j ⇓ "ok"(j,0)$],
)

#irule(
  [PEG-Negative-Fail],
  (
    [$G;sigma ⊢ p @j ⇓ "ok"(j',c)$],
  ),
  [$G;sigma ⊢ !p @j ⇓ "fail"(j,emptyset,0)$],
)

#irule(
  [PEG-Star-Stop],
  (
    [$G;sigma ⊢ p @j ⇓ "fail"(j',X,0)$],
  ),
  [$G;sigma ⊢ p^* @j ⇓ "ok"(j,0)$],
)

#irule(
  [PEG-Star-Step],
  (
    [$G;sigma ⊢ p @j ⇓ "ok"(j_1,c_1) quad j_1 > j$],
    [$G;sigma ⊢ p^* @j_1 ⇓ "ok"(j_2,c_2)$],
  ),
  [$G;sigma ⊢ p^* @j ⇓ "ok"(j_2,c_1 or c_2)$],
)

#irule(
  [PEG-Star-Cut-Fail],
  (
    [$G;sigma ⊢ p @j ⇓ "fail"(j',X,1)$],
  ),
  [$G;sigma ⊢ p^* @j ⇓ "fail"(j',X,1)$],
)

#irule(
  [PEG-Nonterminal],
  (
    [$G(N)=p$],
    [$G;sigma ⊢ p @j ⇓ r$],
    [$r'="leaveRule"(r)$],
  ),
  [$G;sigma ⊢ N @j ⇓ r'$],
)

Rule-local cut在成功返回 nonterminal时不能泄漏给 caller：

$
  "leaveRule"("ok"(j,c)) = "ok"(j,0)
$

$
  "leaveRule"("fail"(j,X,c)) = "fail"(j,X,c)
$

失败保留 commit bit，成功则清零；这对应规范要求的 rule frame。若只想
内联一个 expression而不建立 rule frame，应写 expression本身而不是
`PEG-Nonterminal`。

若 `PEG-Star-Step` 的第一次 premise成功但 $j_1=j$，parser 报
no-progress bug而不是递归。EOF mismatch 与 token-stream末尾都视为
`PEG-Terminal-Fail`。Expectation 的 farthest-position merge只影响诊断，
不改变 success/failure 或 commit；为简洁未写进以上 recognition rules。
两种 lookahead都在 probe sandbox中静默丢弃内部 commit；negative
lookahead还丢弃内部 expectation。

由有序选择可直接得到：

#status(
  [PEG determinism],
  [
    对固定 $G$、$sigma$、$p$ 与 $j$，recognition result 至多一个。
    证明按 $p$ 的结构归纳；ordered choice 永远优先选择第一个成功且未被回滚的
    branch。
  ],
)

= Canonical surface fragment 与 temporal delta

== Calculus 使用的 canonical grammar import

本 calculus 不复制第二份 PEG。它按 profile id
`Cire-TR₀/2026-07-31` 导入 `surface-grammar.md` 的 token/rule table，并只对
下列 canonical rule产生的 CST node定义 elaboration：

```text
Declaration, GenericClauses, Type, RowExpr, FunctionDecl, OperationDecl,
LambdaExpr, CallArguments, HandlerExpr, HandlerClause, ReturnClause,
WithExpr, DelayExpr, Block
```

因此 `GenericClauses` 的非空分支、`fn(value)` 的 inferred
`LambdaParameter`、label-first lookahead、`RowUnion` 和 single-final-tail
约束都由同一 canonical grammar裁决。形式化中的
`SurfaceTR0(profile,node)` premise表示 node必须来自该 rule table；本文
没有第二个 recognizer，也没有“只比较成功语言”的兼容后门。

== 目标 temporal surface

`CAP`、`RESUMES`、`NEXT` 与 `MAY_SUSPEND` 是 canonical keyword token，
不是 contextual `LowerIdent`。`delay`、`advance` 与 `Next` 保持 canonical
grammar规定的 sealed prelude name：resolver只有在完整 intrinsic
shape/evidence成立时才产生 `DelayExpr`、`advance` Kernel node 与 hidden
`Next[i,A,L]` contract。这个 resolver delta不修改 token language。

`advance(e)` 保持普通 call grammar。Resolver 只在 callee 绑定到 sealed
prelude intrinsic 时降为 Core `advance`；同名用户函数仍是普通函数。

`Next[frame, A]` 被识别为普通 type application。
Kind/lowering 阶段只对 sealed `Next` constructor 把首个 lower-name argument
重分类为 capability identity；这不是一般 dependent type。

`cap FrameClock` 是 target capability binder/type marker；在 parameter位置
lowering 会创建 restricted singleton identity quantifier。`Next` 只供
resolver识别 sealed constructor，不另建 parser branch。

== Profile boundary

#warning([
  `Cire-TR₀/2026-07-31` 只接受 canonical `with ... in ...` chain，不接受历史
  `with operand { block }` 形状。实现若需要迁移诊断，应把 legacy token
  sequence作为拒绝 case，而不是并行的语言 profile。
])

建议新增的 CST node：

```text
DelayExpression
CapabilityType
OperationContract
ResumeTransition
SuspensionAnnotation
WithChain
WithEntry
```

`Next` 可继续使用 `TypeReference/TypeArgumentList`；`advance` 可继续使用
`CallExpression`，由 resolver 产生专用 Kernel HIR。

= Surface 到 Core 的语法与 elaboration

== Kinds

$
  kappa ::= "Type" | "Effect" | "EffectRow" | "CapId" | "ClockId"
          | "OwnerRegion" | "Phase" | "Evidence"
          | kappa_1 -> kappa_2
$

`CapId(F,ρ)` 是一般、受限的生成式 capability identity kind；只有
`freshcap`/handler application可以引入。`ClockId(ρ)` 是
`CapId(F,ρ)` 连同 sealed `F : FrameClock` evidence 的 refinement，不是所有
capability的共同 kind。普通 term 不能出现在 type 中。

== Core types

$
  P ::= "LaterContract"(i,A)
      | "FnContract"(A,B)
      | "ClockPackageSummary"(i,A)
$

#align(center)[
  $A,B ::= alpha | "Unit" | "Never"
    | forall i:"CapId"(F,rho).A
    | forall p:P.A
    | exists i:"CapId"(F,rho),
        S:"ClockPackageSummary"(i,A).A$ \
  $quad | forall rho:"OwnerRegion".A
    | A arrow.r.long^(C) B
    | "Cap"[i,F]
    | "Next"[i,A,L]$ \
  $quad | "Task"[rho,R]
    | "Source"[rho,A]
    | "Live"[rho,A]
    | "Event"[rho,A]$ \
  $quad | "Signal"[i,A]
    | "Resource"[rho,A,B]
    | "Plan"[A]
    | "Owner"[rho]$ \
  $quad | "CompletionSource"[rho,R]
    | "CompletionPort"[rho,R]
    | "CommitTicket"[rho] | "CommitGate"[rho]
    | "Resume"[q,D,A,B,Pi,chi,rho]
    | "HandlerTemplate"[F,rho,A,B,epsilon,(p).C,P]$
]

函数 contract：

$
  C =
  ⟨epsilon,hat(zeta),r_f,s,delta,Pi_"closure",chi_"closure",
    u,hat(R)_"out",Phi_"req",Q,Lambda⟩
$

其中 $hat(zeta)$ 是 normal logical temporal-context transformer或 $bot$，
$r_f in {"MayReturn","NoReturn"}$ 记录是否存在 normal return；$s$ 是 suspension
上界，$delta$ 保存 handler-instance semantic summary，
$Pi_"closure"$ 与 $chi_"closure"$ 分别是 closure environment的
provenance map与 authority capture，$u$ 是每次调用的 latent usage map，
$hat(R)_"out"$ 把实参的 provenance/capture summary映射为结果，或在
`NoReturn` 时为 $bot$。普通 case映射结果为
$(pi_"out",chi_"out")$；$Phi_"req"$ 是完整的
phase/authority/current-Owner invocation precondition，而不只是 phase
grade $phi$。
$Q$ 是对 argument provenance/capture、nominal indices与 Owner/outlives的
finite parametric obligation set；
$Lambda$ 是跨 abstraction序列化的 latent operation-site/coeffect schemas；
Surface function type 通常只显示 $epsilon$；其余字段必须写入 Typed HIR
与 interface artifact。

每个 $C$ 还带派生但必须序列化的
$"flow"(C):"FlowSetV1"$：`r_f=MayReturn` 当且仅当该 set含 `Returns`，
`NoReturn` 当且仅当不含；`Aborts/Transfers` entries无论是否同时存在 normal
return都保留。$hat(zeta)$ 与 $hat(R)_"out"$ 只描述 Returns projection，
不能替代整个 flow set。

跨模块 artifact 不以裸字母作为 wire format。第一版稳定 schema 为：

```text
FunctionContractV1 {
  profile: "Cire-TR₀/2026-07-31"
  schema_version: 1
  row: RowExprV1
  transition: TransitionV1
  flow_summary: FlowSetV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  capture_slots: [CaptureSlotV1]
  usage: [UsageV1]
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  ParametricObligations: [ObligationV1]
  LatentSites: [LatentSiteV1]
}

CaptureSlotV1 {
  slot: u32                  // alpha-normalized declaration-order slot
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
}

ObligationV1 =
    BoundarySafeV1      { id, stage, slots, boundary, origin }
  | StableAcrossV1      { id, stage, slots, clock_slot, worlds, origin }
  | OutlivesV1          { id, stage, shorter, longer, origin }
  | PhaseAllowsV1       { id, stage, required_phase, origin }
  | DuplicableEnvV1     { id, stage, slots, site_slot, origin }
  | ReplayableCleanupV1 { id, stage, site_slot, cleanup, origin }
  | TickWitnessV1       { id, stage, clock_slot, site_slot, origin }
  | OwnerParkingV1      { id, stage, owner_slot, site_slot, origin }
  | RowLacksV1          { id, stage, row_slot, entry, origin }

LatentSiteV1 {
  site_slot: u32             // alpha-normalized lexical-site slot
  stage: Call | HandlerInstall
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  argument_slots: [u32]
  suffix: SuffixContractV1
  secondary_sites: [SecondarySiteV1]
  obligation_ids: [u32]
  origin: SourceOriginV1
}

SecondarySiteV1 {
  site_slot: u32
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1 | AnyOperationOfEntry
  route: RouteSelectorV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  origin: SourceOriginV1
}

RouteSelectorV1 =
    ResolveAtCall
  | ResolveAtInstallation
  | InstallationPrompt { prompt_slot: u32 }
  | OuterOf { prompt_slot: u32 }

StageV1 = Call | HandlerInstall
```

本文内部仍用 $Q/Lambda$ 简写这两个字段。`id`、capture/site/prompt slot
都在 declaration boundary按 source order alpha-normalize；wire equality不依赖
source变量名或运行时地址。每个 secondary site有自己的 receiver和 route，
不能继承 primary route。未知 schema version、variant tag、route selector或
悬空 slot/id必须拒绝，不能默默丢字段。

`Call` obligation 在 T-App 实例化和 discharge；`HandlerInstall`
obligation与对应 `LatentSiteV1` 原样保留到 fresh delimiter prompt存在时的
`InstallOK`。调用者不得仅因跨模块 call成功就把后一阶段清空。

与 hidden $L$ 相同，surface `(A) -> B ! ε` 先 elaboration为
$A arrow.r.long^(?C) B$，不是把未显示字段填成 `pure/same`。有 initializer
的 declaration求解 $?C$；高阶 input binder把未由 annotation约束的字段
泛化为 rigid contract parameter，并把调用时用到的 row、world、phase、
result transformer、$Q/Lambda$ 投影进 enclosing function contract。
Declaration boundary不能留下未解 metavariable，interface必须序列化 solved
contract或其显式 quantified binder。

Core lambda binder携带显式、已 elaborated 的 annotation：

$
  eta_f ::= ⟨A,B,Phi_f⟩
$

其中 $A/B$ 是参数/结果类型，$Phi_f$ 是调用所需 phase/authority。基线中的普通
first-class closure一律按 many-call 检查；one-call closure必须等将来有
quantity-aware function binder后再加入，不能靠局部优化证据偷偷放宽。

`frame : cap FrameClock` 的完整 Core binder不是普通 dependent term：

$
  forall i:"CapId"("FrameClock",rho).
  "Cap"[i,"FrameClock"] arrow.r.long^C "Next"[i,A,L_f]
$

$L_f$ 是从 function body求解并写入 interface的 sealed result contract。
若 `Next[i,A]` 出现在 parameter位置，则 declaration boundary反而引入：

$
  forall L:"LaterContract"(i,A).
  "Next"[i,A,L] arrow.r.long^C B
$

调用时 generative/implicit identity与 contract binder实例化，且受相同 escape
check。
Owner region也用 restricted region quantifier；二者都不是任意 term index。

`CommitTicket`、`CommitGate`、`Resume`、`Task` 等运行时对象内部携带实际
$(rho,g)$ token，但 $g$ 不出现在普通 type equality 中。静态系统检查
Owner region、phase、capture 与 boundary；stale generation 由运行时
原子验证。这一分层避免在没有一般 dependent type 的情况下伪造
`CurrentGeneration(ρ) = g` 之类的静态命题。

Surface 仍打印 `Next[i,A]`；第三个参数 $L$ 是只存在于 Typed
HIR/interface的 sealed later contract：

$
  L = ⟨pi_A,chi_A,delta_"body",Phi_"force"⟩
$

它随 `Next` type经过变量、ADT、函数返回与模块 interface传播，source不能
构造或模式匹配。Surface annotation中的缺省 $L$ 是一个 typed elaboration
hole而不是通配符：

```text
local synthesis from delay   produces an exact L
checking a result annotation solves ?L from the RHS
an input binder with no RHS  generalizes a rigid ∀L
an ADT field                 retains that hidden type parameter
module interface             serializes the solved/generalized binder
```

因此 `Next[i,A]` 绝不等于“存在某个运行时不可知的契约然后把它忘掉”。
不同 control-flow分支只能通过 sealed `joinLaterContract` 合并。对
$L_j="joinLaterContract"(L_1,L_2)$：

$
  L_j=
  ⟨"Stable",chi_1∪chi_2,
    delta_1⊔delta_2,
    "RequireBoth"(Phi_1,Phi_2)⟩
$

且 join evidence要求两个 branch的 common payload supertype成立、branch
cell capture分别包含 $chi_1/chi_2$。`RequireBoth` 的语义是：
`PhaseAllows(Φ, RequireBoth(Φ₁,Φ₂))` 当且仅当两项都允许；semantic
summary 的 $⊔$ 是保守上界。没有这些 proof就不能为了 branch join丢字段。

== Effect rows、capture 与 provenance

$
  a ::= "Anon"(F) | "Named"(i, F)
$

$
  epsilon ::= emptyset | mu | {a} | epsilon_1 ⊔ epsilon_2
  quad
  C_epsilon ::= emptyset | {"Lacks"(epsilon,a)} | C_1 ∪ C_2
$

$
  Delta ::= emptyset
    | {"Demand"(kappa,p,a,o,q)}
    | Delta_1 ∪ Delta_2
$

这里 $p$ 是一次 handler *installation* 的 fresh prompt（或 outer/root
route），$q$ 是 `Primary` 或稳定的 secondary-site slot；handler value本身
不是 route。

$
  chi ::= emptyset
    | {i}
    | {"owner"(rho)}
    | {"resume"(k)}
    | {"borrow"(beta)}
    | {"claim"(c)}
    | chi_1 ∪ chi_2
$

$
  pi ::= "Stable" | "Region"(r) | "Callback"(c)
       | "Owner"(rho) | "GenerationBound"(rho) | "Env"(Pi)
$

$
  Pi ::= emptyset | {x ↦ (A,pi,chi)} | Pi_1 ∪ Pi_2
$

Rows 是带约束的 AC-idempotent union algebra；`Anon(F)` 与 `Named(ι,F)`
不相等。Surface row elaboration judgment 为：

$
  K;I ⊢ R_"surface" ⇝ epsilon ⊣ C_epsilon
$

#irule(
  [Row-Ref],
  ([$K(mu)="EffectRow"$],),
  [$K;I ⊢ mu ⇝ mu ⊣ emptyset$],
)

#irule(
  [Row-Extend],
  (
    [$K;I ⊢ R ⇝ epsilon ⊣ C$],
    [$K;I ⊢ a:"EffectEntry"$],
  ),
  [$K;I ⊢ {a,..R} ⇝ {a} ⊔ epsilon
    ⊣ C∪{"Lacks"(epsilon,a)}$],
)

#irule(
  [Row-Union],
  (
    [$K;I ⊢ R_1 ⇝ epsilon_1 ⊣ C_1$],
    [$K;I ⊢ R_2 ⇝ epsilon_2 ⊣ C_2$],
  ),
  [$K;I ⊢ R_1 | R_2 ⇝
    epsilon_1 ⊔ epsilon_2 ⊣ C_1∪C_2$],
)

`RowNormalize(ε,Cε)` 按 identity排序已知 entry、保留所有 rigid row
variable和 `Lacks` constraint；它不把 `E1 | E2` 假装成单一 tail。
Surface literal的 grammar仍只允许一个 final tail，所以
`{..E1,..E2}` 被拒绝；`E1 | E2` 则由 `Row-Union` 合法进入 Core union
algebra。

Demand splitting是对 attribution做的可判定 partition：

$
  "RowSplit"(Delta,p)
  =
  ⟨Delta_"here",Delta_"out"⟩
$

其中 $Delta_"here"={d in Delta | "route"(d)=p}$，
$Delta_"out"=Delta - Delta_"here"$，并满足
$"eraseDemand"(Delta)=
  "eraseDemand"(Delta_"here") ⊔ "eraseDemand"(Delta_"out")$。
因此 public row由 `$epsilon="eraseDemand"(Delta)$` 导出，不再作为与
$Delta$ 可独立漂移的第二项事实。

$Delta$ 是 attributed demand：$kappa$ 是稳定 call site，$p$ 是
installation prompt route，$a/o$ 是 resolved entry/operation，$q$ 区分
primary 与各 secondary-site slot。每个 secondary site先实例化自己的
$(kappa_q,a_q,o_q)$，再由当前 prompt stack独立运行 `resolveRoute(a_q)`；
它不能继承 primary demand 的 route。Exact handling只移除
`RowSplit(Δ,p).here`，不是对 family 名做 raw set subtraction。
同 family forwarding 在 Surface 尚无冻结拼写；Kernel 必须显式产生
`forward[p_outer](a,o,args)`，把 primary demand route更新到 outer prompt并保留原
identity/site。它不能用“先删 `{a}`、再加 `{a}`”模拟，否则 nested
same-family handler 与 secondary demand会失去 attribution。
空 residual row 只表示没有 operation 向外请求：

$
  epsilon = emptyset quad ⇏ quad "TemporalPure"(delta)
$

== Core expressions

#align(center)[
  $e ::= x | lambda^[eta_f] x.e | e_1(e_2)
    | "let" x=e_1;e_2$ \
  $quad | "CapAbs"(i,v) | v[j]
    | "packClock"[j](v) " as "
        (exists i:"CapId"(F,rho),
          S:"ClockPackageSummary"(i,A).A)$ \
  $quad | "unpackClock" [i,x]=p " in " e
    | "OwnerAbs"(rho,v) | v[rho]$ \
  $quad | "freshcap" i:F@rho " in " e
    | "capref"(i)
    | "delay"_i(e) | "advance"(e)$ \
  $quad | "op"[a]("name",bar(e))
    | "forward"[r](a,"name",bar(e))
    | "handler"[F]{bar(c)}
    | "freshprompt" p " in " "handle"[p,h,i?](e)$ \
  $quad | "resume"(k,v)
    | "finalize"(k)
    | "park"("src",o,k)$ \
  $quad | "intrinsic"(n,bar(e))$
]

== 关键 elaboration

```text
Next[frame, A]
  ↦ Next[ιframe, A, ?L]

?L is solved from an initializer/result;
an annotation-only input position generalizes rigid ∀L.

delay[frame] { e }
  ↦ delay_ιframe(elab(e))

advance(e)
  ↦ advance(elab(e))
    only when `advance` resolves to the sealed intrinsic

with h1 as c1
with h2
in e
  ↦ ScopedApply(
      elab(h1), c1,
      thunk { ScopedApply(elab(h2), none, thunk { elab(e) }) },
    )

handler F { operation clauses }
  ↦ handler F {
      operation clauses
      return(value) => value
    }
    when Surface omitted `return`;
    this normalization runs before clause partition/exactness

def f(p1, ..., pn) { e }
  ↦ a named recursive binding whose value is one Core function over
    an immutable n-ary argument tuple

def f(...) { items; result }
  ↦ ordinary named-function return of elab(result);
    no hidden resumption is introduced

fun op(...) => { items; result }
  ↦ items; let value = elab(result) in resume(hidden_k, value)
    on every normal exit; abortive exits run the hidden disposition cleanup

f(a_source1, ..., a_sourcen)
  ↦ let x1 = elab(a_source1) in ... let xn = elab(a_sourcen) in
    f(tupleByParameterOrder(x1, ..., xn))
    after labels are resolved; source evaluation order is unchanged

resolver:
  ScopedApply(handlerValue : HandlerTemplate[...], cap, bodyThunk)
    ↦ let h = handlerValue in
      freshprompt p in handle[p, h, cap](bodyThunk())

  ScopedApply(ordinaryTransformer, none, bodyThunk)
    ↦ ordinaryTransformer(bodyThunk)

frame.yield()
  ↦ op[Named(ιframe, FrameClock)](yield, [])

live { e }
  ↦ first-party intrinsic/library boundary, not a new parser form
```

`with ... as cap` 的 identity 不能按普通 lambda parameter generalize。
Surface HIR先保留统一的 `ScopedApply`，以保证 operand evaluation order与
inner thunk调用次数；resolver证明 operand具有 `HandlerTemplate[...]`
type后才降为
Kernel `handle`。普通 scoped transformer仍是函数调用，不能被错误地赋予
effect-row elimination。Kernel `freshprompt p; handle[p,h,i]` 每次安装
生成 route prompt，并自己引入 generative identity，在结果处执行 escape
check。

Synthetic identity return 强制 $B=A$，contract 为 same-world、empty row、
`NoSuspend`、`Pure`，并把输入 summary逐字保留：

$
  R_"identity"(pi,chi)=(pi,chi)
$

它不能把结果洗成 `Stable/∅`。若 handler做 answer-type transformation，例如
$A -> "Result"[A,E]$，则不能省略 return。

= 静态域与代数

== Effect row

Row equality 忽略顺序，但保留 entry identity：

$
  "Named"(i, F) != "Named"(j, F) quad "when" quad i != j
$

$
  "Anon"(F) != "Named"(i, F)
$

定义 normalization $"nf"_epsilon$：展开已知 row formula、按稳定 identity
排序、删除同一 entry 的重复项，并保留最多一个开放 tail。算法化 equality
是：

$
  epsilon_1 ≡ epsilon_2
  quad "iff" quad
  "nf"_epsilon(epsilon_1) = "nf"_epsilon(epsilon_2)
$

Handler 消除一个 entry：

$
  epsilon - a
$

只删除精确的 $a$，不能用 family 相等删除另一个 named instance。

== Attributed suspension summary

$
  "NoSuspend" <= "MaySuspend"
$

只存一个 scalar grade 无法正确表达 handler refinement：若 operation 的
`MaySuspend` 已经无条件 join 进 body，外层 sealed synchronous handler就再也
不能把它收紧。故 $s$ 是按请求来源归因的有限 map：

$
  s ::= "direct"(d) | "request"(a,d) | s_1 ⊔ s_2
  quad d in {"NoSuspend","MaySuspend"}
$

`grade(s)` 对全部分量取最大值。普通顺序组合与分支 join 使用 $⊔$；
operation call加入 `"request"(a,d)`。Handler elimination定义：

$
  "handleSusp"(s,a,C_h)
  =
  (s - "request"(a,_))
  ⊔ "direct"("handledGrade"(C_h))
  ⊔ "residualSusp"(C_h)
$

`handledGrade` 只替换被处理 entry自己的声明上界；
`residualSusp(C_h)` 保存 clause对其他 entry的 attributed request。只有
sealed/derived contract能证明 `handledGrade(C_h)=NoSuspend`；普通 handler
取 operation 声明上界，且 clause自己的 await等 suspension仍保留。删除
effect row entry本身并不删除 suspension，
必须同时通过 `handleSusp` 处理同一 entry。需要 scalar 的 premise一律写
`grade(s)=NoSuspend` 或 `grade(s)=MaySuspend`。

== Semantic summary

$delta$ 是有限的 handler-instance certificate sequence，而不是 effect-family
集合。每个 certificate 至少记录：

```text
temporal      Pure | HostObservable
replayOrigin  Fresh | Snapshot | SharedPersistent
fork          Forbid | Copy | Share | Merge
publish       None | CandidateBuffered | CommitOnly | Immediate
suspend       StackOnly | OwnerBound | Portable
trust         Derived | Sealed(module) | TrustedUnsafe
```

顺序组合写作 $delta_1 ⊗ delta_2$，分支组合写作
$delta_1 ⊔ delta_2$。本 calculus 只要求以下 predicate 可判定且对
interface serialization 稳定：

$
  "TemporalPure"(delta)
$

$
  "ReplaySafe"(delta)
$

$
  "TraceNeutral"(delta)
$

$
  "SuspensionStable"(rho, delta, Pi, chi)
$

$
  "CommutesWithNext"(i, delta)
$

对 `pub(open)` effect，第三方普通 trait implementation 不能构造
`Sealed` certificate。

== Phase 与 authority

$
  phi ::= "Pure" | "Compute" | "Action" | "Commit"
$

$Phi = ⟨phi, A_u, rho_o⟩$，其中 $A_u$ 是当前 named authority 集，
$rho_o$ 是可选 current Owner。`CurrentOwner(Φ)=ρ` 只在该字段存在且相等时
成立；phase transformer必须显式说明是否保留或更换 Owner。

#table(
  columns: (1fr, 1.4fr, 3.2fr),
  [*phase*], [*允许的核心行为*], [*禁止或需专门 runner 的行为*],
  [`Pure`], [纯值、纯函数、`Next` 构造], [Observe、Source write、host publish],
  [`Compute`], [Observe、candidate-local declaration], [HostWrite、Commit、MaySuspend],
  [`Action`], [Task、Event action、受控 Source update], [把旧 Commit gate 带入未来],
  [`Commit`], [generation-checked `try_publish`、finalization], [checkpoint、MaySuspend],
)

定义 $"Allowed"(Phi, epsilon, s, delta)$ 为 phase gate。它是 type checking
premise，不是运行时建议；其中 suspension 检查读取 `grade(s)`。

== Temporal context

$
  Theta ::= Gamma | Theta, "lock"_i, Gamma
$

$Gamma$ 是一个有序 binder zone。定义：

```text
pushLock(Θ, ι)     = Θ, lock_ι, ·
splitRight(Θ, ι)   = Θ0, lock_ι, Θ1
dropBinder(Θ, x)   = remove lexical binder x, preserve every lock
hideIdentity(Θ, ι) = remove binder/capability ι and every private lock_ι
locks(Θ)           = erase all lexical binders, preserve ordered locks
```

`splitRight` 选择最右侧 matching lock。不同 clock 的 lock 不互相消去；
同一 clock 的两个 lock 表示两个 tick。

新 `let` binder 总是加入最右 zone。函数参数也属于调用发生时的最右 zone，
因此一个在 tick 之后才传入 helper 的 `Next` 参数不会被误认为来自 tick
之前。这是基线 calculus 的保守 availability discipline。

Lexical scope退出时必须调用 `dropBinder`；否则局部变量会污染可组合 world
输出。Fresh named handler退出时调用 `hideIdentity`：body内部可使用
`lock_ι`，但 private clock 的 lock不能泄漏到 scope外。比较“body没有额外
world transition”时比较 `locks(Θ)`，而不是要求两个含局部 binder的
$Theta$ 字面相等。

== Usage algebra

基础 usage grade：

$
  q ::= 0 | 1 | omega
$

顺序组合使用饱和加法：

$
  0 + q = q
$

$
  1 + 1 = omega
$

$
  omega + q = omega
$

互斥 branch 使用 join：

$
  0 ⊔ 1 = 1
  quad
  1 ⊔ omega = omega
$

Closure capture 乘以 closure call grade：

$
"use"(k, lambda^[eta_f] x.e) =
omega dot "use"(k, e)
$

若 closure 是 many-call，则任何非零 one-shot capture 都提升为 $omega$ 并被
拒绝。

数量预算和 terminal disposition是两件事。$Omega$ 中每个 continuation
状态为：

$
  Omega(k) ::= "Open"(q) | "Closed" | "Transferred"(rho,g,c)
$

`once` resume令 `Open(1) → Closed`；`ctl` resume令
`Open(ω) → Open(ω)`；`finalize` 令任意 `Open(q) → Closed`；
`park` 令其变为 `Transferred(ρ,g,c)`，其中 $c$ 是 sealed completion
port identity。因此 `finalize(ctl_k)` 后不能利用
$omega-1=omega$ 再次 resume。

函数 contract保存 latent usage map $u_f$。构造 closure只分析、并不消费
外层 $Omega$；每次 T-App 按 $u_f$ 更新当前预算。基线所有 first-class
closure都是 many-call；若 $u_f$ 对某个 one-shot entry非零，closure
construction即被拒绝。未来的一般 affine function type见文末开放参数。

四种 mode 的 contract：

#table(
  columns: (1fr, 1.3fr, 1.4fr, 2.5fr),
  [*mode*], [*usage interval*], [*position*], [*handler-visible continuation*],
  [`abort`], [$0$], [`arbitrary`], [无],
  [`fun`], [$1$], [`tail`], [无；compiler 自动尾恢复],
  [`once`], [$0..1$], [`arbitrary`], [有],
  [`ctl`], [$0..omega$], [`arbitrary`], [有],
)

Mode refinement 偏序：

$
  "abort" <= "once" <= "ctl"
$

$
  "fun" <= "once" <= "ctl"
$

`abort` 与 `fun` 不可比较。

= Kinding、identity 与 well-formedness

== 基本 kinding judgment

$
  K ; I ⊢ A : "Type"
$

$
  K ⊢ F : "Effect"
$

$
  K ; I ⊢ epsilon : "EffectRow"
$

$
  I ⊢ i : F @ rho
$

#irule(
  [K-Cap],
  (
    [$I ⊢ i:F@rho$],
    [$K ⊢ F : "Effect"$],
  ),
  [$K; I ⊢ "Cap"[i, F] : "Type"$],
)

#irule(
  [K-Next],
  (
    [$I ⊢ i : "FrameClock" @ rho$],
    [$K; I ⊢ A : "Type"$],
    [$K;I ⊢ L:"LaterContract"(i,A)$],
  ),
  [$K; I ⊢ "Next"[i,A,L] : "Type"$],
)

只有 sealed `Next` constructor 接受带 `FrameClock` evidence 的
`CapId` argument。一般 type constructor仍只能接受其声明 kind 的参数。

下文使用 capture-avoiding abbreviation：

$
  "ClockPkg"[F,rho,A]
  = exists i:"CapId"(F,rho),
      S:"ClockPackageSummary"(i,A).A
$

#irule(
  [K-Cap-All],
  (
    [$K ⊢ F:"Effect" quad K ⊢ rho:"OwnerRegion"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho ⊢ A:"Type"$],
  ),
  [$K;I ⊢ (forall i:"CapId"(F,rho).A):"Type"$],
)

#irule(
  [K-Evidence-All],
  (
    [$K;I ⊢ P:"Evidence" quad p ∉ "dom"(K)$],
    [$K,p:P;I ⊢ A:"Type"$],
  ),
  [$K;I ⊢ (forall p:P.A):"Type"$],
)

#irule(
  [K-Cap-Exists],
  (
    [$K ⊢ F:"Effect" quad K ⊢ rho:"OwnerRegion"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho ⊢ A:"Type"$],
    [$K;I,i:F@rho ⊢ "ClockPackageSummary"(i,A):"Evidence"$],
  ),
  [$K;I ⊢ "ClockPkg"[F,rho,A]:"Type"$],
)

Evidence kind只量化满足下式的 sealed summary：

$
  S=⟨pi_A,chi_A,F_"lease",P_"owner"⟩
  quad
  F_"lease"=⟨emptyset,"same","direct"("NoSuspend"),delta_"release"⟩
$

$P_"owner"$ 证明 shared child-Owner handle、lease acquire/release线性化和
最终 dispose幂等。因而 T-Clock-Unpack可以保持 body的 $epsilon/s$ 不变，
但必须把 $delta_"release"$ 组合进输出 summary。

#irule(
  [T-Cap-Intro],
  (
    [$K ⊢ F:"Effect" quad K ⊢ rho:"OwnerRegion"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
    [$i ∉ "fv"(pi,chi)$],
  ),
  [$K;I;Phi@Theta ⊢_v "CapAbs"(i,v) ⇒ (forall i:"CapId"(F,rho).A) @[pi] ▷ chi$],
)

#irule(
  [T-Cap-Elim],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ (forall i:"CapId"(F,rho).A) @[pi] ▷ chi$],
    [$I ⊢ j:F@rho$],
  ),
  [$K;I;Phi@Theta ⊢_v v[j] ⇒ A[j/i] @[pi] ▷ chi$],
)

#irule(
  [T-Clock-Pack],
  (
    [$I ⊢ j:F@rho$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A[j/i] @[pi_v] ▷ chi_v$],
    [$"ClockPackageSafe"(rho,j,A[j/i],pi_v,chi_v) ⇓ S_j$],
    [$S_i="closeClockSummary"(j⇒i,S_j)$],
    [$chi_p="sealClockCapture"(j,rho,chi_v,S_j) quad j ∉ "fv"(chi_p)$],
  ),
  [$K;I;Phi@Theta ⊢_v "packClock"[j](v) " as " "ClockPkg"[F,rho,A] ⇒ "ClockPkg"[F,rho,A] @["Owner"(rho)] ▷ chi_p$],
)

#irule(
  [T-Clock-Unpack],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "ClockPkg"[F,rho,A] @[pi_p] ▷ chi_p$],
    [$i ∉ "dom"(I) quad S:"ClockPackageSummary"(i,A) " fresh hidden"$],
    [$"openClockLease"(p,Theta,i,S)=Theta_p$],
    [$"packagePayload"(S)=(pi_x,chi_x) quad Theta_x="bind"(Theta_p,x:A @[pi_x] ▷ chi_x)$],
    [$K;I,i:F@rho;Phi;Omega@Theta_x ⊢ e ⇒ B @[pi_B] ! epsilon ▷ s;delta;chi_B @Theta_e⊣Omega'$],
    [$i ∉ "fv"(B,pi_B,epsilon,s,delta,chi_B,Omega')$],
    [$"PackageResultBoundarySafe"(S,B,pi_B,chi_B)$],
    [$(Theta_o,Omega_o,delta_o)="ClockPackageScopeExit"(S,i,"dropBinder"(Theta_e,x),Omega',delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "unpackClock"[i,x](p,e) ⇒ B @[pi_B] ! epsilon ▷ s;delta_o;chi_B @Theta_o⊣Omega_o$],
)

#irule(
  [T-Clock-Unpack-Abort],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "ClockPkg"[F,rho,A] @[pi_p] ▷ chi_p$],
    [$i ∉ "dom"(I) quad S:"ClockPackageSummary"(i,A) " fresh hidden"$],
    [$"openClockLease"(p,Theta,i,S)=Theta_p$],
    [$"packagePayload"(S)=(pi_x,chi_x) quad Theta_x="bind"(Theta_p,x:A @[pi_x] ▷ chi_x)$],
    [$K;I,i:F@rho;Phi;Omega@Theta_x ⊢_"abort" e ! epsilon ▷ s;delta ⊣Omega'$],
    [$"NoIdentityInAbortEvidence"(i,e,epsilon,s,delta,Omega')$],
    [$(Omega_o,delta_o)="AbortClockPackageScopeExit"(S,i,Omega',delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" "unpackClock"[i,x](p,e) ! epsilon ▷ s;delta_o ⊣Omega_o$],
)

#irule(
  [K-Owner-All],
  (
    [$rho ∉ "dom"(K)$],
    [$K,rho:"OwnerRegion";I ⊢ A:"Type"$],
  ),
  [$K;I ⊢ (forall rho:"OwnerRegion".A):"Type"$],
)

#irule(
  [T-Owner-Intro],
  (
    [$rho ∉ "dom"(K)$],
    [$K,rho:"OwnerRegion";I;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
    [$rho ∉ "fv"(pi,chi)$],
  ),
  [$K;I;Phi@Theta ⊢_v "OwnerAbs"(rho,v) ⇒ (forall rho:"OwnerRegion".A) @[pi] ▷ chi$],
)

#irule(
  [T-Owner-Elim],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ (forall rho:"OwnerRegion".A) @[pi] ▷ chi$],
    [$K ⊢ rho':"OwnerRegion"$],
  ),
  [$K;I;Phi@Theta ⊢_v v[rho'] ⇒ A[rho'/rho] @[pi] ▷ chi$],
)

Surface `x : cap F` 参数同时引入 implicit $i$ 和
`x:Cap[i,F]`，等价于 T-Cap-Intro 后再用 T-Lambda。`freshcap` scope内，
`capref(i)` 是唯一 value introduction：

#irule(
  [T-Cap-Ref],
  (
    [$I ⊢ i:F@rho$],
    [$"AuthorityFor"(Phi,i)$],
  ),
  [$K;I;Phi@Theta ⊢_v "capref"(i) ⇒ "Cap"[i,F] @["Region"(rho)] ▷ {i}$],
)

调用以实参 capability identity应用 T-Cap-Elim。Named operation必须消费
实际 `Cap[i,F]`/authority witness，不能仅凭 AST 中出现 `Named(i,F)` 伪造
identity。`ClockPackageSafe` 是 sealed predicate：它要求
package强拥有对应 runner、Owner与 dispose责任，并把 payload
provenance/capture与 dispose contract写入 $S$；因此裸
$exists i."Signal"[i,A]$ 不能仅靠 T-Clock-Pack 延长 clock lifetime。
`closeClockSummary` 把 concrete witness $j$ alpha-abstract为 existential
binder $i$；`sealClockCapture` 只可依据同一 sealed ownership evidence把
raw $j$ capture折叠为 Owner-owned package capture。Evidence binder $S$
与 identity $i$ 一起 existentially封装；surface省略的是 binder spelling，
不是 interface evidence。

TR₀ 的普通 value可复制，所以 package不是一个伪装成普通值的 affine token。
`ClockPackageSafe` 必须证明 container强拥有一个可共享的 child-Owner
handle；alias共享同一 runner，`openClockLease` 取得 scoped lease，
scope exit只原子 release该 lease。最终 dispose由 child Owner在最后一个
handle/lease退出后执行且幂等。若未来选择 affine package，必须把 quantity
传播到 alias、ADT与 closure；本文不偷偷假设那套尚未定义的规则。
T-Clock-Unpack 的 non-escape premise保证打开 package后不能把 private
identity、row entry、lock或 capture再次泄漏出去。正常与 abortive exit
分别由 `ClockPackageScopeExit` / `AbortClockPackageScopeExit` 执行 $S$
中的 non-suspending、empty-row lease-release contract并隐藏 identity；
其 semantic summary仍组合进 $delta_o$。`PackageResultBoundarySafe` 还
拒绝虽不含 $i$、却借 child Owner/callback越过 lease lifetime的结果。
generic T-Ctx-Abort不能跳过这个 delimiter。Owner quantifier同样只量化
静态 region name，不量化 runtime generation。Surface existential省略
$S$ 的拼写，但 Core binder、变量与 module interface不省略。

#irule(
  [K-Task],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$K;I ⊢ R:"Type"$],
    [$"Shareable"(R)$],
    [$"AsyncBoundarySafe"(rho,R)$],
  ),
  [$K;I ⊢ "Task"[rho,R]:"Type"$],
)

#irule(
  [K-Broadcast],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$K;I ⊢ A:"Type"$],
    [$"Shareable"(A)$],
    [$X in {"Source","Live","Event"}$],
  ),
  [$K;I ⊢ X[rho,A]:"Type"$],
)

#irule(
  [K-Signal],
  (
    [$I ⊢ i:"FrameClock"@rho$],
    [$K;I ⊢ A:"Type"$],
    [$"Shareable"(A)$],
  ),
  [$K;I ⊢ "Signal"[i,A]:"Type"$],
)

#irule(
  [K-Resource],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$K;I ⊢ A:"Type" quad K;I ⊢ B:"Type"$],
    [$"Shareable"(A) quad "Shareable"(B)$],
    [$"AsyncBoundarySafe"(rho,B)$],
  ),
  [$K;I ⊢ "Resource"[rho,A,B]:"Type"$],
)

#irule(
  [K-Runtime-Authority],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$X in {"Owner","CommitTicket","CommitGate"}$],
  ),
  [$K;I ⊢ X[rho]:"Type"$],
)

#irule(
  [K-Resume],
  (
    [$q in {1,omega}$],
    [$K;I ⊢ A:"Type" quad K;I ⊢ B:"Type"$],
    [$K;I ⊢ D:"ContinuationContract"$],
    [$K;I ⊢ Pi:"ProvenanceMap" quad K;I ⊢ chi:"CaptureSet"$],
    [$K ⊢ rho:"OwnerRegion"$],
  ),
  [$K;I ⊢ "Resume"[q,D,A,B,Pi,chi,rho]:"Type"$],
)

`Plan[A]` 在 $K;I ⊢ A:"Type"$ 且 `Shareable(A)` 时成型。
`HandlerTemplate[F,ρ,A,B,ε,(p).C,P]` 在 family、origin region、
answer types、row、prompt-abstract contract 与 policy
分别 well formed 时成型。以上类型内部可携带 opaque runtime token，
但 kinding 不比较运行时 generation。
`ContinuationContract` formation还要求其中的 cleanup contract $F_k$
well formed：row、world transformer、attributed suspension与 semantic
summary都必须显式给出，且只能由可信 suffix analysis构造。

Core subtyping 必须保留所有名义 index：

#irule(
  [S-Fun],
  (
    [$K;I ⊢ A_2 <: A_1 quad K;I ⊢ B_1 <: B_2$],
    [$"ContractEq"(C_1,C_2)$],
  ),
  [$K;I ⊢ (A_1 arrow.r.long^(C_1) B_1) <: (A_2 arrow.r.long^(C_2) B_2)$],
)

`ContractEq` 对 normalized
$(epsilon,hat(zeta),r_f,s,delta,Pi,chi,u,hat(R)_"out",Phi_"req",Q,Lambda)$
逐字段 invariant（capture slot与 bound identity允许 alpha-renaming）。
TR₀ 暂不提供 effect/phase/summary contract subtyping；将来若放宽，必须给完整
refinement proof，不能删除 `MaySuspend`、Action phase、latent site或
boundary obligation。

#irule(
  [S-Next],
  (
    [$I ⊢ i:"FrameClock"@rho$],
    [$K;I ⊢ A <: B$],
    [$"LaterContractRefines"(L_A,A,L_B,B)$],
  ),
  [$K;I ⊢ "Next"[i,A,L_A] <: "Next"[i,B,L_B]$],
)

TR₀ 的 refinement刻意保守。若
$L_A=⟨pi,chi,delta,Phi⟩$，则：

$
  "LaterContractRefines"(L_A,A,L_B,B)
  quad "iff" quad
  L_B="liftPayloadType"(A<:B,L_A)
$

`liftPayloadType` 只替换 type-indexed well-formedness proof；$pi$、$chi$、
$delta$ 与 $Phi$ 逐字段不变。也就是说 S-Next允许 payload nominal
covariance，但不借 subtyping削弱 required phase、semantic summary或
capture evidence。不同 branch需要更保守 contract时必须使用前文定义的
`joinLaterContract`，其方向是 capture/summary上界与 phase requirement
合取，而不是任意 subtyping。

不存在把 `Next[i,A,L]` coercion 成 `Next[j,B,L′]`（$i != j$）的规则；
`Cap[i,F]`、`Owner[ρ]`、`CommitTicket[ρ]`、`CommitGate[ρ]` 与
`Resume[...]` 的 authority/index
部分均 invariant。本文把普通 ADT 与 function subtyping留给 base language，
但 function arrow只采用上面的 S-Fun；普通 ADT substitution也不得改写
$i$、$rho$、$zeta$ 或 contract evidence。

== Identity freshness

#irule(
  [K-Fresh-Cap],
  (
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho;Phi;Omega@Theta ⊢ e ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta'⊣Omega'$],
    [$i ∉ "fv"(A,pi,epsilon,s,delta,chi,Omega')$],
    [$Theta_o="hideIdentity"(Theta',i)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "freshcap" i:F@rho " in " e ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta_o⊣Omega'$],
)

#irule(
  [K-Fresh-Cap-Abort],
  (
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho;Phi;Omega@Theta ⊢_"abort" e ! epsilon ▷ s;delta ⊣Omega'$],
    [$"NoIdentityInAbortEvidence"(i,e,epsilon,s,delta,Omega')$],
    [$(Omega_o,delta_o)="AbortScopeExit"(i,Omega',delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" ("freshcap" i:F@rho " in " e) ! epsilon ▷ s;delta_o ⊣Omega_o$],
)

第三个 premise 是 rank-2/generative escape gate。合法 existential packaging
必须同时封装：

```text
exists ι.
  OwnerContainer[ρ, ι, A]
```

并让 container 拥有 runner、child Owner 与 `dispose`。裸
$exists i. "Signal"[i,A]$ 不能延长 runner lifetime。
Abortive exit使用 K-Fresh-Cap-Abort：它先 revoke/finalize private
identity，再把 flow交给外层；private site/row/summary/usage evidence不能
跨 scope。

== Contract well-formedness

Operation contract：

$
  O = ⟨m,bar(alpha),bar(A)->B,zeta,d,R_o,Phi_o,P_o,Sigma_o⟩
$

Handler clause contract：

$
  H_c = ⟨m_h,Q_"site",d_h,Delta_"res",s_"res",delta_h,R_h,P_"park"⟩
$

Refinement judgment：

$
  K; I ⊢ H_c ⊑ O
$

要求：

- $m_h <= m$；
- 基线若 $m="ctl"$，则 operation $zeta="same"$；非恒等 world fork只有在
  将来引入 sealed branch-world algebra后才可声明；
- handler获得的 captured continuation必须以 operation $zeta$ 为首个
  successful transition，不能把它改成别的 clock；
- $d_h <= d$，且收紧 suspension 必须有可信 evidence；
- $s_"res"$ 精确保留 clause对其他 effect entry产生的 suspension；
- `abort` 没有 successful resume transition；
- handler semantic law 的 witness 具有允许的 trust origin；
- operation 的每个 polymorphic type parameter在 clause 中 fresh skolemize。
- `may_suspend` 的 $P_"park"$ 必须证明同步 resume或 Owner-bound transfer。
- clause residual attributed demand、suspension与 summary 必须包含
  $Sigma_o$ 的 secondary contract，不能因 exact family handling而擦除。

== Shareability、duplicability 与 boundary safety

这三个 predicate 不等价：

$
  "Shareable"(A)
$

值可以被广播/缓存并多次观察。

`Shareable` 是 sealed、结构归纳的 predicate，而不是任意第三方可伪造的
marker trait。最小闭包为：

```text
Shareable(Unit / Bool / Int / immutable String)
Shareable(T[A1, ..., An])
  if T is an immutable data constructor
  and every stored Ai is Shareable
Shareable(Next[ι, A, L])
  if Shareable(A) and LaterContractWF(ι, A, L)
Shareable(Plan[A])     if Shareable(A)
Shareable(A ->^C B)
  only if the closure contract says
    DuplicableEnv(C.provenance, C.captures)
  and its provenance passes the requested storage boundary
```

`Cap`、`Owner`、`Resume`、`CompletionSource`、`CompletionPort`、
`CommitTicket` 与 `CommitGate` 不因“机器上可以复制几个 bits”而成为
broadcast payload。`CompletionSource` 是不可复制的 introduction
authority；`CompletionPort` 的多个宿主 handle可共享同一 CAS claim，因而
capture可满足 `Duplicable`，但它不是 `Shareable(R)` 的结果广播。
`CommitGate` 的多个 handle可以
共享同一原子 claim，所以相关 capture 可满足 `Duplicable`；它仍受
generation boundary约束且不满足 `Shareable`。`CommitTicket` 也只允许交给
sealed commit runner消费。第一方容器若要声明额外 `Shareable` instance，
必须给出逐字段 sealed derivation。

$
  "Duplicable"(chi)
$

捕获环境可被 multi-shot continuation 安全复制或共享。

$
  K; I ⊢ chi " valid-at " b
$

所有 capture 在 storage boundary $b$ 仍 outlive、可处置且 authority 合法。

对会延迟执行的 closure-like value，还必须检查 free environment provenance：

令 $B_x="binding"(Theta,x)$。则：

$
  "EnvBoundarySafe"(X,Theta,b)
  quad "iff" quad
  forall x in X.
  B_x=(A_x,pi_x,chi_x)
$

且每个这样的 $x$ 都满足：

$
  "ProvenanceValid"(A_x,pi_x,Theta,b)
  and K;I ⊢ chi_x " valid-at " b
$

`provenanceFV(X,Θ)` 保存这张逐 binder map，不能把它提前 join成
`Owner(ρ)`。这是必要的，因为 callback/region borrow可能有空 capture set。
Map key在 Typed HIR/interface中是 canonical capture-slot index，不是 source
变量名；equality与 serialization先按 slot alpha-normalize。

新增的 `Env(Π)` cases是 pointwise且可判定的：

```text
StableAcross(ι, Env(Π), n)
  iff every (A, π, χ) in Π satisfies
      StableAcross(ι, π, n) and CrossWorldSafe(ι, χ, I)

ProvenanceValid(Aclosure, Env(Π), Θ, b)
  iff every slot (Ax, πx, χx) in Π satisfies
      ProvenanceValid(Ax, πx, Θ, b)
      and K;I ⊢ χx valid-at b

joinProv(Env(Π1), Env(Π2))
  = Env(pointwise-normalize(Π1 ∪ Π2))
joinProv(Env(Π), π)
  = Env(pointwise-normalize(Π ∪ singleton(π)))
Env(∅) normalizes to Stable
```

`joinProv` 对两个 scalar provenance也先作 singleton embedding。Function
contract中的 $Pi_"closure"$ 在 subtype/equality checking中 invariant
（modulo capture-slot alpha-renaming）；没有把 `Callback` 自动弱化成
`Owner` 的规则。

Boundary 包括 return、closure、ADT、trait object、global storage、
continuation capture、temporal lock、suspension 与 FFI。

= 算法化 typing judgment <typing-judgments>

== Synthesis 与 checking

Synthesis：

$
  K; I; Phi; Omega @ Theta
  ⊢ e ⇒ A @[pi] ! epsilon;Delta ▷ s; delta; chi
  @ Theta' ⊣ Omega'
$

Checking：

$
  K; I; Phi; Omega @ Theta
  ⊢ e ⇐ A @[pi] ! epsilon;Delta ▷ s; delta; chi
  @ Theta' ⊣ Omega'
$

Value judgment：

$
  K; I; Phi @ Theta
  ⊢_v v ⇒ A @[pi] ▷ chi
$

$pi$ 与 $chi$ 都描述结果；所有 derivation 维持
$epsilon="eraseDemand"(Delta)$，所以 row不能脱离 route/site attribution
单独变化。Branch provenance使用最小安全上界
`joinProv`；capture union后做 binder substitution。Rule中省略
$@[pi]$ 只允许在紧邻文字明确结果为 `Stable` 时使用。

为保持长规则可读，后文旧式 `! ε ▷ ...` 只是一种排版缩写：它必须从该
rule的 typed subderivations/site constructors结构性计算唯一 $Delta$，并同时
证明 `ε=eraseDemand(Δ)`；它绝不表示“没有 Δ 字段”或允许事后用
side-effecting recorder修改全局状态。T-App、T-Operation、handler、resume/finalize
与 flow rules显式写出 $Delta$，因为这些正是 attribution发生变化的边界。

Checking rule：

#irule(
  [T-Check],
  (
    [$K;I;Phi;Omega@Theta ⊢ e ⇒ A' @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
    [$K;I ⊢ A' <: A$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ e ⇐ A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
)

#irule(
  [T-Value],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ v ⇒ A @[pi] ! emptyset ▷ "direct"("NoSuspend");delta_"pure";chi @Theta⊣Omega$],
)

== Variables

#irule(
  [T-Var],
  (
    [$x : A @[pi] ▷ chi_x in Theta$],
    [$"Available"(pi, Theta, x)$],
  ),
  [$K;I;Phi@Theta ⊢_v x ⇒ A @[pi] ▷ chi_x$],
)

#irule(
  [T-Value-Check],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A' @[pi] ▷ chi$],
    [$K;I ⊢ A' <: A$],
  ),
  [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi] ▷ chi$],
)

`Available` 检查 binder 与使用点之间的 lock、region 和 Owner boundary。
它不只检查 $chi$。

== Functions

#irule(
  [T-Lambda],
  (
    [$eta_f=⟨A,B,Phi_f⟩$],
    [$(pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x = "bind"(Theta,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_f;Omega_"sym"@Theta_x ⊢ e ⇒ B @[pi_B] ! epsilon ▷ s;delta;chi_B @Theta_b⊣Omega_b$],
    [$Theta_o="dropBinder"(Theta_b,x)$],
    [$chi_c="captureFV"(e-{x},Theta) quad Pi_c="provenanceFV"(e-{x},Theta)$],
    [$pi_c="Env"(Pi_c)$],
    [$u="latentUsage"(Omega_"sym",Omega_b) quad zeta="abstractLocks"(Theta,Theta_o)$],
    [$Lambda="abstractSites"("typed"(e),x)$],
    [$"AbstractParametricSummary"(pi_x,xi_x,pi_B,chi_B,"evidence"(e))=(Q,R_"out")$],
    [$"ManyCallSafe"(Pi_c,u,chi_c)$],
  ),
  [$K;I;Phi@Theta ⊢_v lambda^[eta_f] x.e ⇒ A arrow.r.long^⟨epsilon,zeta,"MayReturn",s,delta,Pi_c,chi_c,u,R_"out",Phi_f,Q,Lambda⟩ B @[pi_c] ▷ chi_c$],
)

`Omega_sym` 是 closure body的符号 usage环境；构造 closure不修改定义点的
$Omega$。`ManyCallSafe` 要求 $u$ 不使用任何 one-shot entry，并同时验证
$Pi_c$ / $chi_c$ 中 provenance与 authority可由 many-call closure共享；
T-Lambda否则拒绝。
`freshRigidSummaryVars` 不能被 rule-schema实例化为 `Stable/∅`；
`AbstractParametricSummary` 对所有 admissible argument summary普遍抽象，
把 derivation产生的 boundary/stability/outlives constraints存入 $Q$，
并把 symbolic result存成 $R_"out"$。T-App先 discharge $Q$ 后才能应用
$R_"out"$。
`abstractLocks` 只抽象 lock transformer，局部 binder已经被 `dropBinder`
删除。

#irule(
  [T-Lambda-Abort],
  (
    [$eta_f=⟨A,B,Phi_f⟩ quad (pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x="bind"(Theta,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_f;Omega_"sym"@Theta_x ⊢_"abort" e ! epsilon ▷ s;delta ⊣Omega_b$],
    [$(Pi_c,chi_c,u,Lambda)="analyzeAbortClosure"(e,x,Theta,Omega_"sym",Omega_b)$],
    [$Q="AbstractParametricAbortObligations"(pi_x,xi_x,"evidence"(e))$],
    [$pi_c="Env"(Pi_c) quad "ManyCallSafe"(Pi_c,u,chi_c)$],
  ),
  [$K;I;Phi@Theta ⊢_v lambda^[eta_f] x.e ⇒ A arrow.r.long^⟨epsilon,bot,"NoReturn",s,delta,Pi_c,chi_c,u,bot,Phi_f,Q,Lambda⟩ B @[pi_c] ▷ chi_c$],
)

`NoReturn` contract没有 normal $zeta/R_"out"$；其中的 $bot$ 不能被
T-App当作任意 world transformer。`analyzeAbortClosure` 只是
`captureFV`、`provenanceFV`、latent usage与site extraction的打包写法，
不是新 oracle。参数相关的 boundary/stability/outlives obligation仍由
`AbstractParametricAbortObligations` 对 rigid $(pi_x,xi_x)$ 普遍抽象为
$Q$；abortive body不能借“不产生结果”绕过实参相关的前缀安全条件。

T-Lambda 与 T-Lambda-Abort 是下列 path-set rule 的单一路径投影；真正
checker使用后者，所以带 terminal transfer 的具名函数仍可形成：

#irule(
  [T-Lambda-Paths],
  (
    [$eta_f=⟨A,B,Phi_f⟩ quad
      (pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x="bind"(Theta,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_f;Omega_"sym"@Theta_x ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon;Delta;s;delta ⊣Omega_b$],
    [$(Pi_c,chi_c,u,Lambda)="analyzeFlowClosure"(
      e,x,Theta,Omega_"sym",Omega_b,cal(F)_b,Delta)$],
    [$(r_f,hat(zeta),hat(R),Q)="AbstractParametricFlow"(
      pi_x,xi_x,cal(F)_b)$],
    [$C_0=⟨epsilon,hat(zeta),r_f,s,delta,Pi_c,chi_c,u,
      hat(R),Phi_f,Q,Lambda⟩$],
    [$C="attachFlow"(C_0,"abstractFlow"(cal(F)_b))$],
    [$pi_c="Env"(Pi_c) quad "ManyCallSafe"(Pi_c,u,chi_c)$],
  ),
  [$K;I;Phi@Theta ⊢_v lambda^[eta_f] x.e ⇒
    A arrow.r.long^C B @[pi_c] ▷ chi_c$],
)

若 $cal(F)_b={"Transfers"(P)}$，则
$r_f="NoReturn"$、$hat(zeta)=hat(R)=bot$，但
`flow(C)={Transfers(P)}`；它不会被改写成 abort。Surface named `def`
的一元 tuple elaboration使用同一 rule。

#irule(
  [T-App],
  (
    [$C_f=⟨epsilon_f,zeta,"MayReturn",s_f,delta_f,Pi_f,chi_f,u_f,R_f,Phi_f,Q_f,Lambda_f⟩$],
    [$K;I;Phi;Omega@Theta_0 ⊢ e_1 ⇒ A arrow.r.long^(C_f) B @[pi_1] ! epsilon_1;Delta_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$K;I;Phi;Omega_1@Theta_1 ⊢ e_2 ⇐ A @[pi_2] ! epsilon_2;Delta_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$"PhaseAllows"(Phi,Phi_f) quad "applyUsage"(Omega_2,u_f)=Omega_3$],
    [$"Discharge"("instantiate"("stageCall"(Q_f),pi_2,chi_2,I,Theta_2))$],
    [$zeta(Theta_2) = Theta_3$],
    [$R_f(pi_2,chi_2)=(pi_3,chi_3)$],
    [$(Delta_f,Lambda_"install")="instantiateLatentSites"(Lambda_f,Theta_2)$],
    [$"PreserveUntilInstall"("stageHandlerInstall"(Q_f),Lambda_"install")$],
    [$cal(F)_f="instantiateFlow"("flow"(C_f),pi_2,chi_2,Theta_2)$],
    [$Delta'=Delta_1∪Delta_2∪Delta_f
      quad epsilon'="eraseDemand"(Delta')$],
    [$"AttachFlowEvidence"("callNode",cal(F)_f)$],
  ),
  [$K;I;Phi;Omega@Theta_0 ⊢ e_1(e_2) ⇒ B @[pi_3] ! epsilon';Delta' ▷ s_1 ⊔ s_2 ⊔ s_f;delta_1 ⊗ delta_2 ⊗ delta_f;chi_3 @Theta_3⊣Omega_3$],
)

#irule(
  [T-App-Abort],
  (
    [$C_f=⟨epsilon_f,bot,"NoReturn",s_f,delta_f,Pi_f,chi_f,u_f,bot,Phi_f,Q_f,Lambda_f⟩$],
    [$"flow"(C_f)={"Aborts"}$],
    [$K;I;Phi;Omega@Theta_0 ⊢ e_1 ⇒ A arrow.r.long^(C_f) B @[pi_1] ! epsilon_1;Delta_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$K;I;Phi;Omega_1@Theta_1 ⊢ e_2 ⇐ A @[pi_2] ! epsilon_2;Delta_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$"PhaseAllows"(Phi,Phi_f) quad "applyUsage"(Omega_2,u_f)=Omega_3$],
    [$"Discharge"("instantiate"("stageCall"(Q_f),pi_2,chi_2,I,Theta_2))$],
    [$(Delta_f,Lambda_"install")="instantiateLatentSites"(Lambda_f,Theta_2)$],
    [$"PreserveUntilInstall"("stageHandlerInstall"(Q_f),Lambda_"install")$],
    [$Delta'=Delta_1∪Delta_2∪Delta_f
      quad epsilon'="eraseDemand"(Delta')$],
  ),
  [$K;I;Phi;Omega@Theta_0 ⊢_"abort" e_1(e_2) ! epsilon';Delta' ▷ s_1⊔s_2⊔s_f;delta_1⊗delta_2⊗delta_f ⊣Omega_3$],
)

#irule(
  [T-App-Transfer],
  (
    [$C_f=⟨epsilon_f,bot,"NoReturn",s_f,delta_f,Pi_f,chi_f,u_f,bot,Phi_f,Q_f,Lambda_f⟩$],
    [$"flow"(C_f)={"Transfers"(P_f)}$],
    [$K;I;Phi;Omega@Theta_0 ⊢ e_1 ⇒
      A arrow.r.long^(C_f) B @[pi_1] !
      epsilon_1;Delta_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$K;I;Phi;Omega_1@Theta_1 ⊢ e_2 ⇐
      A @[pi_2] ! epsilon_2;Delta_2 ▷
      s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$"Discharge"("instantiate"("stageCall"(Q_f),
      pi_2,chi_2,I,Theta_2))$],
    [$(Delta_f,Lambda_"install")=
      "instantiateLatentSites"(Lambda_f,Theta_2)$],
    [$"PreserveUntilInstall"(
      "stageHandlerInstall"(Q_f),Lambda_"install")$],
    [$P="instantiateParkContract"(P_f,pi_2,chi_2,Theta_2)$],
    [$Delta'=Delta_1∪Delta_2∪Delta_f
      quad epsilon'="eraseDemand"(Delta')$],
  ),
  [$K;I;Phi;Omega@Theta_0 ⊢_"transfer" e_1(e_2) ⇓
    "Transfers"(P) ! epsilon';Delta' ▷
    s_1⊔s_2⊔s_f;delta_1⊗delta_2⊗delta_f
    @Theta_2⊣Omega_2$],
)

函数调用必须应用 contract 中的 temporal transformer；不能把
$zeta$、$Pi_f/chi_f$、$u_f$、$R_f$、$Phi_f$、$Q_f$ 或 $Lambda_f$
从 interface artifact 中删除。
Callee
closure与argument的 capture不会自动成为结果 capture；只有 $R_f$ 声明的
转移进入 $chi_3$。$Lambda'$ 作为 call node evidence保存，外层
`sites(e,a)` 会把它与 caller suffix compose；因此 perform藏在另一个 module
的 `f()` 中也不会绕过 ctl capture、parking 或 answer-world检查。

== Let 与 block

#irule(
  [T-Let],
  (
    [$K;I;Phi;Omega@Theta_0 ⊢ e_1 ⇒ A @[pi_1] ! epsilon_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$Theta_x = "bind"(Theta_1,x:A @[pi_1] ▷ chi_1)$],
    [$K;I;Phi;Omega_1@Theta_x ⊢ e_2 ⇒ B @[pi_2] ! epsilon_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$Theta_3="dropBinder"(Theta_2,x)$],
  ),
  [$K;I;Phi;Omega@Theta_0 ⊢ "let" x=e_1;e_2 ⇒ B @[pi_2] ! epsilon_1 ∪ epsilon_2 ▷ s_1 ⊔ s_2;delta_1 ⊗ delta_2;chi_2 @Theta_3⊣Omega_2$],
)

Block 按 source order 对 expression list 左折叠应用 T-Let/T-Sequence。
因此 world transition、usage budget 与 handler ordering 都不可交换。
若 $e_2$ 返回 closure/ADT并保存 $x$，capture substitution会把 $chi_1$
展开进 $chi_2$；`dropBinder` 只退出词法名字，不丢失结果 authority。

= Temporal typing

== Temporal stability

定义：

$
  "StableAcross"(i, pi, n)
$

表示 provenance $pi$ 可跨 clock $i$ 的 $n$ 个 lock。至少：

```text
Stable                 true
immutable deep copy    true
Next cell              true
Callback(c)            false after callback boundary
Region(r)              only while r outlives the target
Owner(ρ)               only with explicit CrossWorldSafe witness
Commit candidate       false
```

Free-value 检查：

$
  "TemporalStable"(i,X,Theta)
  quad "iff" quad
  forall x in X. exists A,pi,chi,n.
$

并同时满足：

#align(center)[
  $"binding"(Theta,x)=(A,pi,chi)$ \
  $n="locksBetween"(Theta,x,i)$ \
  $"StableAcross"(i,pi,n)$
]

Capture 检查：

$
  "CrossWorldSafe"(i, chi, I)
$

二者必须分开，因为普通 borrow 可以有 $chi = emptyset$。
`captureFV(e,Θ)` 对 free variable的 result capture取并集，并加入直接出现的
capability；它不是从 body结果 $chi_e$ 猜出来的。

`Next` 是 sealed Core type，且公开构造值的唯一规则是 T-Delay。其 payload
predicate不是一个可丢弃的 side condition，而定义为：

$
  "TemporalPayloadSafe"(i,A,pi_A,chi_A,chi_"cell")
  quad "iff" quad
  pi_A="Stable"
  and chi_A subset.eq chi_"cell"
  and "CrossWorldSafe"(i,chi_A,I)
$

上述 witness及 delayed body的 semantic/phase contract都进入 type index
$L$。因而 elimination虽保守返回整个 cell capture，也不会把 payload
provenance、authority或 semantic summary洗成 `Stable/∅/pure`。若未来允许
future scope创建新的 owned payload，必须扩展 $L$ 与 Owner semantics，
而不能直接删除 subset premise。

== Delay <rule-delay>

#irule(
  [T-Delay],
  (
    [$I ⊢ i : "FrameClock" @ rho$],
    [$Theta_n = "pushLock"(Theta, i)$],
    [$Phi_d " fresh symbolic" quad "RequiredPhaseEvidence"(e,Phi_d)$],
    [$K;I;Phi_d;Omega@Theta_n ⊢ e ⇒ A @[pi_A] ! emptyset ▷ s_e;delta_e;chi_A @Theta_e⊣Omega$],
    [$"grade"(s_e)="NoSuspend" quad "locks"(Theta_e)="locks"(Theta_n)$],
    [$"TemporalPure"(delta_e)$],
    [$"TemporalStable"(i, "fv"(e), Theta)$],
    [$chi_d="captureFV"(e,Theta) quad "CrossWorldSafe"(i,chi_d,I)$],
    [$"Shareable"(A) quad "TemporalPayloadSafe"(i,A,pi_A,chi_A,chi_d)$],
    [$L_d=⟨pi_A,chi_A,delta_e,Phi_d⟩ quad K;I ⊢ L_d:"LaterContract"(i,A)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "delay"_i(e) ⇒ "Next"[i,A,L_d] @["Stable"] ! emptyset ▷ "direct"("NoSuspend");delta_"alloc";chi_d @Theta⊣Omega$],
)

Body 在未来 lock 下检查，但构造 `Next` 不推进当前 world。`delta_alloc`
只描述 pure modal-cell allocation；body 的 certificate 随 Typed HIR proof
保存，而不是作为现在执行的 effect。
`Phi_d fresh symbolic` 与 `RequiredPhaseEvidence` 合起来表示先收集 body的
phase/authority/current-Owner constraints，再求解并泛化最小 admissible
requirement；未解 metavariable不能进入 $L_d$ 或 interface。

第一版要求 body 的 lock projection仍等于 $Theta_n$ 的 lock projection，
因此局部 `let` 可以正常出 scope，但 body不能偷偷执行额外 world-changing
operation。

== Advance <rule-advance>

定义：

$
  "splitRight"(Theta, i) = Theta_0, "lock"_i, Theta_1
$

#irule(
  [T-Advance],
  (
    [$"splitRight"(Theta, i) = Theta_0, "lock"_i, Theta_1$],
    [$K;I;Phi@Theta_0 ⊢_v v ⇒ "Next"[i,A,L_d] @[pi_v] ▷ chi_v$],
    [$L_d=⟨pi_A,chi_A,delta_e,Phi_d⟩ quad chi_A subset.eq chi_v$],
    [$"PhaseAllows"(Phi,Phi_d)$],
    [$"Allowed"(Phi,emptyset,"direct"("NoSuspend"),delta_e)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "advance"(v) ⇒ A @[pi_A] ! emptyset ▷ "direct"("NoSuspend");delta_e ⊗ delta_"force";chi_v @Theta⊣Omega$],
)

基线只允许 value operand。一般 `advance(e)` 先在 tick 之前 let-bind：

```cire
let pending = compute_next()
frame.yield()
advance(pending)
```

这避免在当前 world 执行一个“假装属于旧 prefix”的 effectful operand。

如果不存在 matching lock，T-Advance 无法应用；这就是“过早 advance”的
静态拒绝。

== Nested 与 distinct clocks

$
  "Next"[i,"Next"[i,A,L_1],L_2] != "Next"[i,A,L]
$

$
  "lock"_i != "lock"_j quad "when" quad i != j
$

两层同 clock `delay` 需要两次 matching lock。`network` lock 不能打开
`animation` 的 `Next`。

== World-changing operation

Transition contract：

$
  zeta ::= "same" | "next"(i) | zeta_1 ∘ zeta_2
$

$
  hat(zeta) ::= zeta | bot
  quad
  hat(R) ::= R | bot
$

$bot$ 不是可以应用的 transformer。Function contract WF要求：

```text
r_f = MayReturn  iff  ζ̂ ≠ ⊥ and R̂out ≠ ⊥
r_f = NoReturn   iff  ζ̂ = ⊥ and R̂out = ⊥
Returns(_) ∈ flow(C) iff r_f = MayReturn
Aborts/Transfers entries remain independent of r_f
```

Operation signature同理：`mode=abort` 当且仅当 normal transition为
$bot$；其他 mode必须给出普通 $zeta$。这使 T-App/T-Operation的 normal与
abortive rule在 sort上互斥。

应用：

$
  "same"(Theta) = Theta
$

$
  "next"(i)(Theta) = "pushLock"(Theta, i)
$

`FrameClock.yield` 的 named operation signature：

```cire
pub effect FrameClock {
  once yield() -> Unit
    resumes next
}
```

`yield` 没有一条与 generic operation竞争的特殊 synthesis rule。它只是
后文 T-Operation在下列 profile-fixed signature下的派生实例：

$
  O_"yield" =
  () -> "Unit"
  @[
    "once",
    "next"(i),
    "MaySuspend",
    R_"unit",
    Phi_"yield"(i),
    {"RequiresTickWitness"(i),
     "OwnerBoundParking"(i)}
  ]
$

其中 $R_"unit"()=("Stable",emptyset)$，
$Phi_"yield"(i)$ 要求当前 $Phi$ 持有 named clock authority $i$。
因此唯一结果是 row `{a}`、
`request(a,MaySuspend)`、空 result capture以及
`pushLock(Θ,i)`；`delta_clock` 只在 sealed runner handler policy被安装后
加入，而不是由 perform site凭空加入。

只有 sealed clock runner 能 discharge `{a}` 并产生合法 next-world witness。
定义 package 内的 handler 若在 current world 直接 `resume`，不满足
operation contract refinement。`MaySuspend` 是 public declared maximum；
具体 sealed runner只有在证明宿主等待完全封装于 world transition、且不跨
语言级 Owner/storage boundary时，才可把 actual handler suspension收紧为
`NoSuspend`。没有该 witness就必须 discharge `OwnerBoundParking`。

== Handler 与 Next 不默认交换

T-Delay 的 body premise在 handler 消除它的外层 rule之前成立。因此：

```cire
with Error::result()
in {
  delay[frame] { parse(text) }
}
```

在 T-Delay 处仍看到非空 Error row，拒绝。

```cire
delay[frame] {
  with Error::result()
  in { parse(text) }
}
```

先由内部 handler 消除 Error，再满足 T-Delay。未来 bridge 必须显式提供：

$
  "CommutesWithNext"(i, delta_h)
$

且该 witness 必须 sealed/trusted。

= Effect、operation 与 handler typing <handler-typing>

== Operation signature

Signature lookup：

$
  K(F, "op") =
  forall bar(alpha).
  (bar(A)) -> B
  @[m, zeta, d, R_o, Phi_o, P_o, Sigma_o]
$

$m$ 是最大 resumption mode，$zeta$ 是 successful resume transition，
$d$ 是 suspension 上界，$R_o$ 是 argument summary到 result
provenance/capture的 transformer，$Phi_o$ 是 invocation precondition，
$P_o$ 是 suspension/parking obligation，且
$Sigma_o=⟨Lambda_"secondary",s_"secondary",delta_"secondary"⟩$
是 operation declaration 的 secondary effect/suspension/summary contract。
每个 $Lambda_"secondary"$ entry都是带独立 stable site slot、receiver、
operation和 route selector的 `SecondarySiteV1`；实例化后产生
$Delta_"secondary"$，其 public row才是
$"eraseDemand"(Delta_"secondary")$。
`ElabSecondaryRow(R, operationOrigin)` 对 normalized row中的每个 entry生成
synthetic site slot和 `AnyOperationOfEntry` selector；若以后有更精确 summary
可收紧为 exact operation selector。每个 synthetic site仍独立执行
route resolution，不能共享 primary prompt。
Operation 自身不把 handler policy写入 family；
policy 来自具体 handler instance。

对 $zeta="next"(i)$，$P_o$ 还包含不可伪造的
`RequiresTickWitness(i)` obligation。T-Operation只记录“正常 continuation
若返回需要 next world”；真正 handler安装时，`InstallOK` 必须从 sealed clock
runner取得 `TickWitness(i)`。普通 clause直接 inline `resume` 不能构造该
witness。

调用点先实例化 fresh type metavariable并统一参数。Named 与 anonymous dispatch
只在 row entry 上不同：

$
  "entry"("F::op") = "Anon"(F)
$

$
  "entry"("cap.op") = "Named"(i, F)
$

== Operation call

令 `Args` judgment 按左到右顺序检查参数并组合 row、summary、capture 与
temporal context：

$
  K;I;Phi;Omega@Theta
  ⊢ bar(e) ⇐ bar(A)
  ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a@Theta_a⊣Omega_a
$

以下 normal-returning rule只适用于 $m != "abort"$：

#irule(
  [T-Operation],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @[m,zeta,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$m != "abort"$],
    [$sigma = "freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @[m,zeta_sigma,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",s_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta ⊢ bar(e) ⇐ bar(A)_sigma ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a@Theta_a⊣Omega_a$],
    [$a = "entry"("receiver",F) quad p="resolveRoute"(a) quad zeta_a = "instantiateReceiver"(zeta_sigma,a)$],
    [$zeta_a(Theta_a)=Theta'$],
    [$R_sigma(bar(pi_a),bar(chi_a))=(pi_B,chi_B)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$Delta_"sec"="instantiateSecondarySites"(Lambda_"sec",kappa,"promptStack")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"(a,d_sigma) ⊔ s_"sec" quad "PhaseAllows"(Phi,Phi_sigma)$],
    [$"Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(kappa,a,P_sigma,Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "op"[a]("op",bar(e)) ⇒ B_sigma @[pi_B] ! epsilon_"call";Delta_"call" ▷ s';delta_a⊗delta_"sec";chi_B @Theta'⊣Omega_a$],
)

`abort` operation 没有 successful $Theta'$。为避免用任意 world伪造正常
返回，另设 abortive flow judgment：

$
  K;I;Phi;Omega@Theta
  ⊢_"abort" e ! epsilon;Delta ▷ s;delta ⊣ Omega'
$

#irule(
  [T-Operation-Abort],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @["abort",bot,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$sigma="freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @["abort",bot,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",s_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta ⊢ bar(e) ⇐ bar(A)_sigma ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a@Theta_a⊣Omega_a$],
    [$a="entry"("receiver",F) quad p="resolveRoute"(a)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$Delta_"sec"="instantiateSecondarySites"(Lambda_"sec",kappa,"promptStack")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"(a,d_sigma) ⊔ s_"sec"$],
    [$"PhaseAllows"(Phi,Phi_sigma) quad "Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(kappa,a,P_sigma,Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" "op"[a]("op",bar(e)) ! epsilon_"call";Delta_"call" ▷ s';delta_a⊗delta_"sec" ⊣Omega_a$],
)

Algorithmic `CheckResult.flow` 因而是这些 outcome 的有限 path set。
Abortive flow可以在 expected type下使用，但不产生 normal output world；
sequence只把 `Returns` entries送入 suffix，并保留既有
`Aborts/Transfers` entries；branch join取 set union并只对 Returns projection
做 world/result join。这样 `abort` 既不是普通
`Never → A` coercion，也不能贡献一个虚假的 clock lock。

令 $E_s$ 是不跨越 `handle`、`delay`、`live` 或其他 runner delimiter 的
left-to-right strict evaluation context。`Prefix` 只总结到 hole之前已经
执行的部分：

$
  "Prefix"(E_s,Theta,Omega)
  =
  ⟨Theta_h,Omega_h,Delta_p,s_p,delta_p⟩
$

#irule(
  [T-Ctx-Abort],
  (
    [$"Prefix"(E_s,Theta,Omega)=⟨Theta_h,Omega_h,Delta_p,s_p,delta_p⟩$],
    [$K;I;Phi;Omega_h@Theta_h ⊢_"abort" e ! epsilon_e;Delta_e ▷ s_e;delta_e ⊣Omega'$],
    [$Delta_o=Delta_p∪Delta_e
      quad epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" E_s[e] ! epsilon_o;Delta_o ▷ s_p⊔s_e;delta_p⊗delta_e ⊣Omega'$],
)

这一个 congruence rule覆盖 callee/argument、`let` initializer与 operation
arguments中的 abort；hole之后的 suffix不执行，故不错误加入 row、world
或 usage。Core `resume(k,v)` 保持 value operand；surface
`resume(k,e)` 先 ANF 成 `let x=e; resume(k,x)`，所以 argument abort由
initializer context传播。到最近 delimiter 后改由 T-Handle 的 path-aware
body judgment处理。

== Handler type

Core handler value：

$
  "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(p).C_h,P_h]
$

含义：

- handler action 属于 Owner region $rho_h$；
- handled computation 正常返回 $A$；
- handler action 返回 $B$；
- clause 自身可能产生 residual row $epsilon_h$；
- $(p).C_h$ 保存对 installation prompt抽象的 mode、site constraints、
  answer-world、suspension、
  path-specific result-summary、handler environment evidence 与 parking
  contract；
- $P_h$ 是具体 instance 的 semantic policy 与 trust origin。

Handler 是 lexical deep handler：`resume` 后重新进入同一 handler；不相关
effect entry 自动 forwarding。

== Operation-site suffix 与 clause checking

First-class handler定义时看不到未来 perform site 的 evaluation context，所以
不能在 `check_clause` 中调用一个虚构的 `capturesOfSuffix` oracle。Typed
Core先 A-normalize；安装 delimiter时，对 handled body做一次从右向左的
结构递归分析：

$
  K;I;Phi@Theta
  ⊢ "sites"(e,a,p) ⇓ bar(kappa)
$

每个 site contract：

$
  kappa =
  ⟨p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
    Theta_"answer",Xi_k⟩
$

$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$ 是 captured continuation
contract。$w_k$ 是从 operation site恢复到整个 handled computation answer 的*完整*
world transformer：它包含 operation自己的 $zeta$ 和其后 suffix 的
transformer；$chi_k$ 是 live-across-site capture；$u_k$ 是 suffix中的
latent usage；$R_k$ 给出 continuation answer的 result summary。$Xi_k$
保存该 site已经类型化的 actual arguments摘要：每项至少含 type、nominal
index、provenance与 result capture；它不保存任意 runtime value。对 deep
handler，$epsilon_k$ 已按同一 delimiter消除递归出现的 handled entry。
$o_k$ 是 resolved operation selector；它与 $a$ 一起唯一确定被哪一个
clause schema处理；$p$ 唯一确定本次 installation route，同一 handler
value的两次安装拥有不同 $p$。$Theta_"entry"$ 是 arguments求值完毕、operation
transfer control给 clause时的 actual temporal world；ClauseSchema对它
参数化，不能使用 handler定义点的 world代替。
$Pi_k="provenanceLive"("suffix",Theta)$ 是每个
live-across-site binder的
type/provenance map；它与 $chi_k$ 分开保存，因为 borrow可以有空 capture。
$F_k=⟨epsilon_k^"fin",Delta_k^"fin",zeta_k^"fin",s_k^"fin",delta_k^"fin"⟩$
是丢弃该 continuation时必须执行一次的 cleanup contract；它同样来自 typed
suffix，不能由 T-Finalize伪装成纯操作。

分析按 typed ANF evaluation context递归：

```text
suffix(return)             = identity world, empty captures
site entry                 = world after all actual arguments,
                             before operation transfers control
suffix(let x = hole; rest) = operation transition
                              ; transition(rest)
                              + live captures/usage of rest
suffix(branches)           = branch-indexed contracts
suffix(lambda body)        = latent in function contract, not current suffix
suffix(inner handler)      = stop or transform at that delimiter
```

它是 checker的第二个有限 pass；不会执行程序，也不依赖 runtime handler。
Separate compilation保存 $C_h$ 对 $kappa$ 的约束，而不是保存某个定义点
suffix。

对每个 polymorphic operation：

$
  forall bar(alpha). (bar(A)) -> R
$

clause checker创建 fresh skolems $bar(a)$，而不是复用外层同名 type variable。

`once` 或 `ctl` clause 中 continuation 类型：

$
  k :
  "Resume"[q_m, D_k, sigma(R), B, Pi_k, chi_k, rho_h]
$

其中 $A$ 是 raw handled computation的 normal return type，$B$ 才是 deep
handler（return clause已经在 delimiter内）的 answer type；因此 `resume`
expression返回 $B$。Clause schema对
fresh skolems与满足 $C_h$ constraints 的 $kappa$ 参数化：

$
  K;I;Phi;Omega,k:"Open"(q_m)@Theta
  ⊢ "clause"[kappa] ⇐ B @[pi_h] ! epsilon_h
  ▷ s_h;delta_h;chi_h @Theta_h⊣Omega_h
$

并检查：

$
  "usage"(k, "clause") <= q_m
$

若声明 mode 为 `ctl`，基线 profile `declared-max` 还要求：

```text
DuplicableEnv(Πk, χk)
EnvValidAt(Πk, χk, MultiShot)
ReplayableCleanup(Fk, Πk, χk)
WorldForkSafe(wk)
```

即使某个未知运行时 handler 最终只 resume 一次，也不能用这个偶然事实绕过
open-world safety。词法已知 handler specialization 需要单独 preservation
证明。

Return clause本身也是对安装点 normal-exit world参数化的 schema：

#irule(
  [T-Return-Clause],
  (
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩ quad Theta_"entry" " fresh symbolic"$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$(pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x="bind"(Theta_h,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_h;Omega_"sym"@Theta_x ⊢ "body"_B(e) ⇓ cal(F)_r ! epsilon_r;Delta_r;s_r;delta_r ⊣Omega_r$],
    [$cal(F)_o="dropReturnBinder"(cal(F)_r,x)$],
    [$"AbstractReturnContract"(Theta_"entry",pi_x,xi_x,cal(F)_o,epsilon_r,Delta_r,s_r,delta_r) ⇓ C_"ret"$],
  ),
  [$"ReturnClauseOK"(K,I,Phi_h,H_h,"return"(x:A,e),A) ⇓ C_"ret"$],
)

`AbstractReturnContract` 对 rigid input summary与 symbolic
$Theta_"entry"$ 普遍抽象出 world/result transformer及 constraints；它不把
handler定义点 lock写进 contract。

#irule(
  [T-Handler],
  (
    [$"PartitionClauses"(F,bar(c)) ⇓ (c_"ret",M_"op")$],
    [$"dom"(M_"op")="ops"(F) quad "ExactAndUnique"(M_"op")$],
    [$chi_h="captureFV"(bar(c),Theta) quad Pi_h="provenanceFV"(bar(c),Theta)$],
    [$"EnvBoundarySafe"("fv"(bar(c)),Theta,"OwnerStorage"(rho_h))$],
    [$Phi_h " fresh symbolic"$],
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩$],
    [$"ReturnClauseOK"(K,I,Phi_h,H_h,c_"ret",A) ⇓ C_"ret"$],
    [$S_h="checkClauseSchemas"(K,I,Phi_h,H_h,F,M_"op")$],
    [$forall O in "ops"(F). "ClauseSchemaOK"(O,S_h(O),H_h)$],
    [$"AggregateHandler"(C_"ret",S_h)=(epsilon_h,C_0)$],
    [$Phi_"req"="SolveHandlerPhase"(Phi_h,C_"ret",S_h)$],
    [$C_1="setRequiredPhase"(C_0,Phi_"req")$],
    [$"PolicyOK"(P_h) quad "Origin"(P_h)=rho_h$],
    [$C_h="attachHandlerEnv"(C_1,Pi_h,chi_h)$],
    [$"returnContract"(C_h)=C_"ret" quad "clauseSummaries"(C_h)=S_h$],
  ),
  [$K;I;Phi@Theta ⊢_v "handler"[F]{bar(c)} ⇒
    "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(p).C_h,P_h]
    @["Owner"(rho_h)] ▷ chi_h$],
)

输入 T-Handler 前，Surface normalization 已为省略的 return 合成 identity
clause；显式写多个 return 仍是错误。`PartitionClauses` 同时保证恰好一个
return clause、每个
$O in "ops"(F)$ 恰好一个 operation clause，且没有 duplicate或 extra
clause。`ReturnClauseOK` 对具体 $c_"ret"$ 的 parameter、body type、row、
attributed suspension、semantic summary、world transformer、result
transformer与 required invocation phase完整检查，产生
$C_"ret"=⟨epsilon_"ret",w_"ret",s_"ret",delta_"ret",
R_"ret",Phi_"ret"⟩$。它和 operation clause都在 fresh symbolic
$Theta_"entry"$ 下检查，并通过 $H_h$ 导入经过 boundary check的 definition
environment；定义点 $Theta$ 本身不进入 clause world。
`checkClauseSchemas` 返回以 operation entry为键的
finite schema map $S_h$；`AggregateHandler` 把具体 return contract与这些
schema的 residual row、suspension、summary、path-specific result
transformer和 required phase逐项合并。它保留各 path，而不把 operation
clause伪装成 return clause。
因此 conclusion 中的 $epsilon_h$、$(p).C_h$ 都由已检查 clause决定，而不是
游离的 annotation。$Pi_h$ 进入 handler construction evidence；
`EnvBoundarySafe` 成立后才允许把 value自身 provenance记为
`Owner(ρ_h)`。`attachHandlerEnv` 把 $Pi_h/chi_h$ 封入 $C_h$ 的 sealed
construction evidence并序列化到 interface；所以 handler经变量或模块传递
后，`InstallOK` 仍可由 `handlerEnv(C_h)` 取得它们。

Handler value只保存以 prompt slot $p$ 参数化的 template；它没有 concrete
route。每次 `with` installation由 `freshprompt p` 实例化一次，所以同一个
handler value嵌套安装会得到不同 prompt，site/secondary demand不会混层。

`ClauseSchemaOK` 只产生/验证 site constraints。真正的
`Duplicable(χ_k)`、cleanup replay、world answer与 Owner-bound parking
obligation在 T-Handle 的 `InstallOK` 中对每个实际 site discharge。

== Resumption primitives

#irule(
  [T-Resume],
  (
    [$k:"Resume"[q,D_k,A,B,Pi_k,chi_k,rho] quad D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$Omega(k)="Open"(q) quad "PhaseAllows"(Phi,Phi_k)$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi_v] ▷ chi_v$],
    [$w_k(Theta)=Theta' quad R_k(pi_v,chi_v)=(pi_B,chi_B)$],
    [$Omega'="resumeState"(Omega,k,q)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "resume"(k,v) ⇒ B @[pi_B] ! epsilon_k;Delta_k ▷ s_k;delta_k ⊗ delta_"resume";chi_B @Theta'⊣Omega'$],
)

#irule(
  [T-Finalize],
  (
    [$k:"Resume"[q,D_k,A,B,Pi_k,chi_k,rho]$],
    [$Omega(k)="Open"(q)$],
    [$"cleanup"(D_k)=F_k=⟨epsilon_f,Delta_f,zeta_f,s_f,delta_f⟩$],
    [$zeta_f(Theta)=Theta' quad "Allowed"(Phi,epsilon_f,s_f,delta_f)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "finalize"(k) ⇒ "Unit" @["Stable"] ! epsilon_f;Delta_f ▷ s_f;delta_f ⊗ delta_"finalize";emptyset @Theta'⊣Omega[k↦"Closed"]$],
)

TR₀ 不暴露 `discontinue(k,e)`：在没有把 error payload type、异常路径
transformer与 cleanup组合写入 $D_k$ 前，给它一个假装完整的 Core
constructor是不严谨的。Error recovery使用显式 abort operation/clause；
cancel使用 Owner/finalize protocol。`resumeState` 定义为：

```text
resumeState(Ω, k, 1) = Ω[k ↦ Closed]
resumeState(Ω, k, ω) = Ω[k ↦ Open(ω)]
```

若 clause正常退出且 $k$ 仍 `Open`、也未被 park，elaboration在该路径插入
`finalize(k)`。因此每条运行路径最终只有一个 disposition owner；`ctl`
可以 resume多次，但一旦 finalize/park就不能再 resume。
自动插入的 finalizer参与 clause contract聚合，所以 Atomic/Delay会看到真实
cleanup effect与 suspension，而不会获得虚假的 `NoSuspend`。

== Handler mode refinement

#table(
  columns: (1.2fr, 3.8fr),
  [*operation 最大 mode*], [*允许的 clause mode*],
  [`abort`], [`abort`],
  [`fun`], [`fun`],
  [`once`], [`abort`、`fun`、`once`],
  [`ctl`], [`abort`、`fun`、`once`、`ctl`],
)

这只允许收紧控制权。Clause 还必须满足：

```text
resume target agrees with operation transition
actual suspension ≤ declared suspension
all one-shot paths own exactly one disposition
tail-resumptive `fun` has no code after implicit resume
semantic-law witness has an allowed trust origin
every normally returning clause agrees with the captured answer world
may_suspend clause either resumes synchronously or transfers to its Owner
```

`fun` 与 `abort` 不是 checker里共享一个无 continuation 的 `else` 分支。
Clause schema对 abstract site $kappa$ 参数化，并使用两个不同 elaboration：

```text
fun clause op(args) { e }
  ↦ hidden kκ in resume(kκ, e)
  where e checks against the operation result
  and the resume is the unique tail action

abort clause op(args) { e }
  ↦ hidden discardκ in
      let answer = e in discardκ; answer
  where e checks against the handler answer
  and discardκ executes κ.D.cleanup exactly once
```

令 handler schema environment：

$
  H_h=⟨rho_h,B,Pi_h,chi_h⟩
$

`ImportHandlerEnv(Θentry,Hh)` 只把 $Pi_h/chi_h$ 描述的 captured bindings
导入 symbolic operation-site world；它不复制定义点的 lock。以下 judgment
对 $Theta_"entry"$、operation skolems、installation prompt $p$ 和
$kappa$ 普遍量化；`AdmissibleSite` 必须证明 `route(κ)=p`，不能只按
handler value或 family匹配。

#irule(
  [T-Clause-Once-Ctl],
  (
    [$m_h in {"once","ctl"} quad q_"once"=1 quad q_"ctl"=omega$],
    [$kappa=⟨p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,Theta_"answer",Xi_k⟩$],
    [$sigma="freshInstantiation"("typeParams"(O)) quad "AdmissibleSite"(kappa,sigma(O),H_h)$],
    [$"clauseMode"=m_h quad m_h <= "mode"(sigma(O))$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):"params"(sigma(O)),Xi_k)$],
    [$k:"Resume"[q_(m_h),D_k,"result"(sigma(O)),B,Pi_k,chi_k,rho_h]$],
    [$K;I;Phi_h;Omega[k↦"Open"(q_(m_h))]@Theta_k ⊢ "body"_B(e) ⇓ cal(F)_c ! epsilon_c;Delta_c;s_c;delta_c ⊣Omega_c$],
    [$"PathUsage"(cal(F)_c,k) <= q_(m_h)$],
    [$"DispositionComplete"(m_h,k,cal(F)_c,Omega_c) ⇓ cal(F)_d$],
    [$"ExtractClauseContract"(cal(F)_d,Delta_c,Xi_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h ⊢ "resumptiveClause"(O,m_h,e) ⇓ "ResumeSchema"(kappa,H_c)$],
)

`DispositionComplete` 对 `once` 的每个 exit插入/验证 resume、finalize或显式
Owner-bound park恰好一个；对 `ctl` 可有多次 resume，但 exit前只能
finalize，T-Park不接受 `Resume[ω,…]`。插入动作的 row、suspension、
summary与 usage都进入 $f_d$。

#irule(
  [T-Clause-Fun],
  (
    [$kappa=⟨p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,Theta_"answer",Xi_k⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$sigma="freshInstantiation"("typeParams"(O))$],
    [$sigma(O)=(bar(A)_sigma)->R_sigma @[m,zeta_sigma,d_sigma,R_sigma^o,Phi_sigma,P_sigma]$],
    [$"AdmissibleSite"(kappa,sigma(O),H_h)$],
    [$"clauseMode"="fun" quad "fun" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_sigma,Xi_k)$],
    [$k:"Resume"[1,D_k,R_sigma,B,Pi_k,chi_k,rho_h]$],
    [$K;I;Phi_h;Omega,k:"Open"(1)@Theta_k ⊢ e ⇐ R_sigma @[pi_R] ! epsilon_e;Delta_e ▷ s_e;delta_e;chi_R @Theta_R⊣Omega_R$],
    [$Theta_y="bind"(Theta_R,y:R_sigma @[pi_R] ▷ chi_R)$],
    [$K;I;Phi_h;Omega_R@Theta_y ⊢ "resume"(k,y) ⇒ B @[pi_B] ! epsilon_k;Delta_k ▷ s_k;delta_k ⊗ delta_"resume";chi_B @Theta_r⊣Omega'$],
    [$"dropBinder"(Theta_r,y)=Theta_"answer"$],
    [$"TailOnly"("let" y=e;"resume"(k,y)) quad Omega'(k)="Closed"$],
    [$"ExtractClauseContract"("typedFunPath",Xi_k,pi_B,chi_B) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h ⊢ "funClause"(O,e) ⇓ "FunSchema"(kappa,H_c)$],
)

#irule(
  [T-Clause-Abort],
  (
    [$kappa=⟨p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,Theta_"answer",Xi_k⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$sigma="freshInstantiation"("typeParams"(O))$],
    [$sigma(O)=(bar(A)_sigma)->R_sigma @[m,zeta_sigma,d_sigma,R_sigma^o,Phi_sigma,P_sigma]$],
    [$"AdmissibleSite"(kappa,sigma(O),H_h)$],
    [$F_k=⟨epsilon_f,Delta_f,zeta_f,s_f,delta_f⟩$],
    [$"clauseMode"="abort" quad "abort" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_sigma,Xi_k)$],
    [$k_kappa:"Resume"[1,D_k,R_sigma,B,Pi_k,chi_k,rho_h] quad Omega_k=Omega[k_kappa↦"Open"(1)]$],
    [$K;I;Phi_h;Omega_k@Theta_k ⊢ e ⇐ B @[pi_B] ! epsilon_e;Delta_e ▷ s_e;delta_e;chi_B @Theta_B⊣Omega_B$],
    [$Theta_y="bind"(Theta_B,y:B @[pi_B] ▷ chi_B)$],
    [$K;I;Phi_h;Omega_B@Theta_y ⊢ "finalize"(k_kappa) ⇒ "Unit" @["Stable"] ! epsilon_f;Delta_f ▷ s_f;delta_f ⊗ delta_"finalize";emptyset @Theta_f⊣Omega'$],
    [$K;I;Phi_h@Theta_f ⊢_v y ⇒ B @[pi_o] ▷ chi_o$],
    [$"dropBinder"(Theta_f,y)=Theta_"answer" quad Omega'(k_kappa)="Closed"$],
    [$"ExtractClauseContract"("typedAbortPath",Xi_k,pi_o,chi_o) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h ⊢ "abortClause"(O,e) ⇓ "AbortSchema"(kappa,H_c)$],
)

这里的 hidden $k_kappa$ / `discardκ` 只存在于 Kernel elaboration，source
clause不能引用。`fun` 因此仍受完整 $w_k$、TickWitness与 answer-world
检查；`abort` 不执行 suffix，但其 cleanup和最终 normal world仍必须通过
`InstallOK`。`discardκ` 是 T-Finalize 对 abstract site contract
$kappa$ 的 Kernel-only specialization：它消费同一个 disposition，并执行
$"cleanup"(D_k)$，不是另一条可绕过 usage检查的 primitive。若 clause body
自身走 abortive flow，`AbortClauseScopeExit` 在传播 abort前执行同一
cleanup；该路径不贡献 normal
answer-world premise。
`AdmissibleSite` 是结构化 refinement：除 resolved $(a,o_k)$ 与 $Xi_k$
逐参数 type/nominal index外，它还验证 $D_k$ 的 first transition确为
operation $zeta_sigma$、cleanup/answer world一致，并携带全部
$P_sigma$ obligation；它不能只比较 selector。`ExtractClauseContract`
从完整 typed `let/resume` 或 `let/finalize/return` derivation投影
$H_c=⟨m_h,Q_"site",d_h,Delta_"res",s_"res",delta_h,R_h,P_"park"⟩$，所以
actual argument与 handler environment的 provenance/capture transformer
$R_h$ 不会丢失。

若任一 clause body path在产生 normal answer前 abort，runner delimiter
必须先收回该 path拥有的 disposition：

#irule(
  [T-Clause-Path-Abort],
  (
    [$k:"Resume"[q,D_k,A_k,B,Pi_k,chi_k,rho_h] quad Omega(k)="Open"(q)$],
    [$K;I;Phi_h;Omega@Theta_k ⊢_"abort" e ! epsilon_e;Delta_e ▷ s_e;delta_e ⊣Omega_e$],
    [$(Omega_o,delta_o)="AbortClauseScopeExit"(k,D_k,Omega_e,delta_e)$],
    [$"NoOpenDisposition"(k,Omega_o)$],
    [$"ExtractAbortPathContract"(epsilon_e,Delta_e,s_e,delta_o) ⇓ H_a$],
  ),
  [$K;I;Phi_h;H_h ⊢ "clauseAbortPath"(k,e) ⇓ "Aborts"(H_a,Omega_o)$],
)

Clause schema对 normal rules与 T-Clause-Path-Abort 的 reachable path做有限
join；all-abort schema没有 $R_h$ normal branch，但仍保留 residual row、
suspension、semantic summary与 cleanup evidence。该 rule同样覆盖
`fun` argument计算、`once/ctl` clause body以及 hidden abort-clause
disposition的 abortive path。

Handled body使用 path-set辅助 judgment：

$
  t ::= "Aborts"
    | "Returns"(pi,chi,Theta)
    | "Transfers"("ParkContract")
  quad
  cal(F) ::= {t_1,...,t_n}
$

$cal(F)$ 是 reachable outcomes 的有限非空集合，不是单一 tag；因此同一
branching computation可以同时保存 `Returns`、`Aborts` 与一个或多个
`Transfers(ParkContract)`。Normal return entries只有在 result type兼容且
world可 join时合并；transfer contract不能被 join成 abort。

$
  K;I;Phi;Omega@Theta
  ⊢ "body"_A(e) ⇓ cal(F) ! epsilon;Delta;s;delta
  ⊣ Omega'
$

它要求所有 normal path返回 $A$ 并 join其 provenance/capture/world；
完全 abortive body得到 `${Aborts}`。`Transfers(ParkContract)` 是经过
T-Park验证的 terminal ownership transfer，不是 `Unit` result，也不能进入
sequence 的 suffix。三类 flow都保留 typed Core、operation sites、row、
suspension、summary 与 attributed demand。

#irule(
  [T-Body-Return],
  (
    [$K;I;Phi;Omega@Theta ⊢ e ⇐ A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "body"_A(e) ⇓
    {"Returns"(pi,chi,Theta')} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Abort],
  (
    [$K;I;Phi;Omega@Theta ⊢_"abort" e ! epsilon;Delta ▷ s;delta ⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "body"_A(e) ⇓
    {"Aborts"} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Transfer],
  (
    [$K;I;Phi;Omega@Theta ⊢_"transfer" e ⇓
      "Transfers"(P) ! epsilon;Delta ▷ s;delta @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "body"_A(e) ⇓
    {"Transfers"(P)} ! epsilon;Delta;s;delta ⊣Omega'$],
)

`T-Body-Branch` 取各 branch 的 set union；`T-Body-Sequence` 只把
`Returns` entry送入 suffix，并原样保留 prefix 的 `Aborts/Transfers`
entries。这样 operation clause中的 `park`通过 T-Body-Transfer进入 clause
schema，再经 handler congruence向外传播，不会被错误重标为 abort。

Handler installation是一个有输出的 judgment：

$
  E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩
  quad
  "InstallOK"(p,h,P_h,a,bar(kappa),E_e,C_h)
  ⇓ ⟨cal(F)_o,Delta_o,delta_o⟩
$

先令 $(Pi_"handler",chi_"handler")="handlerEnv"(C_h)$。其中
`handlerEnv` 是 T-Handler 写入并跨 interface保存的 sealed projection。
其中 result summary按可达 normal exit path计算：

```text
HandleResultSummary =
  join(
    applyReturnContract(C_h, πe, χe, Θe).result
      for each Returns(πe, χe, Θe) in ℱe,
    clauseSummary(C_h, operation(κ))(
      Ξκ, Πκ, χκ, Πhandler, χhandler)
      for each reachable κ whose clause has a normal exit,
  )
```

`applyReturnContract` 同时把 $C_"ret"$ 的 world transformer加入
answer-world集合。Semantic summary也按相同 reachable-path集合计算：

$
  delta_o =
  "handleSummary"(delta_e,a,C_h,P_h,bar(kappa),cal(F)_e)
$

它保留 unhandled body summary，并加入实际可能执行的 return/clause
summary与 handler policy；不能用单独的 $P_h$ 替代 $C_h$。

所以 abort clause从 actual argument（例如 `Raise.throw(err)` 的 `err`）带入
结果的 provenance/capture不会从 normal body summary中消失。
`InstallOK` 对 $cal(F)_e$ 逐 path映射：return path应用 return/clause
contract，abort path保留 `Aborts`，transfer path保留同一个
`Transfers(ParkContract)` 并验证该 installation不窃取 disposition。它同时
要求所有 normal exit产生可 join 的输出 $Theta_o$；没有 normal exit时
set中仍保留 abort/transfer而不是压成 `NoReturn`。Clause可以通过 full $w_k$ resume到该 world，
也可执行等价 sealed transition；无 resume 的 abort path若 normal return
却没有该 world evidence，就失败。`RequiresTickWitness`、
`OwnerBoundParking` 等 $P_o$ obligation也在这里 discharge。

== Anonymous handling

#irule(
  [T-Handle-Anon-Paths],
  (
    [$K;I;Phi@Theta ⊢_v h ⇒
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(p).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$a="Anon"(F) quad p ∉ "prompts"("promptStack")$],
    [$S_p="pushPrompt"("promptStack",p,a)$],
    [$K;I;Phi;Omega@Theta;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I;Phi@Theta;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$"InstallOK"(p,h,P_h,a,bar(kappa),E_e,C_h)
      ⇓ ⟨cal(F)_o,Delta_i,delta_o⟩$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi,"requiredPhase"(C_h))$],
    [$"RowSplit"(Delta_i,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$Delta_h="instantiateHandlerResidual"(C_h,p)$],
    [$Delta_o=Delta_"out"∪Delta_h
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$s_o="handleSusp"(s_e,a,C_h)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "body"_B(
    "freshprompt" p " in " "handle"[p,h,"anon"](e))
    ⇓ cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_e$],
)

`RowSplit` 只消费 route恰为 fresh $p$ 的 demand；同 family outer demand、
explicit forwarding 与每个独立路由的 secondary demand都留在
$Delta_"out"$。`InstallOK` 的 path map逐项保留 transfer，因此这条 rule同时
是 return、abort 与 T-Handle-Transfer congruence，不再用 “NoReturn ⇒
Aborts” 的错误二分。

Handler 消除对应 prompt demand，但 $P_h$ 仍进入 $delta$。所以：

```text
handled row becomes empty
```

不能推出：

```text
computation is temporal-pure or replay-safe
```

== Generative named handling

#irule(
  [T-Handle-Named-Paths],
  (
    [$K;I;Phi@Theta ⊢_v h ⇒
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(p).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$"HandlerOriginOK"(Phi,rho_h) quad i ∉ "dom"(I)
      quad p ∉ "prompts"("promptStack")$],
    [$a="Named"(i,F) quad I'=I,i:F@rho_h quad Phi_i="addAuthority"(Phi,a)$],
    [$S_p="pushPrompt"("promptStack",p,a)$],
    [$K;I';Phi_i;Omega@Theta;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I';Phi_i@Theta;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$"InstallOK"(p,h,P_h,a,bar(kappa),E_e,C_h)
      ⇓ ⟨cal(F)_h,Delta_i,delta_o⟩$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi_i,"requiredPhase"(C_h))$],
    [$"RowSplit"(Delta_i,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$Delta_h="instantiateHandlerResidual"(C_h,p)
      quad Delta_o=Delta_"out"∪Delta_h$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad cal(F)_o="hideIdentityFlow"(cal(F)_h,i)$],
    [$s_o="handleSusp"(s_e,a,C_h)$],
    [$"NoOpenPrivateDisposition"(i,Omega_e)$],
    [$Omega_o="hideIdentityUsage"(Omega_e,i)$],
    [$i ∉ "fv"(B,cal(F)_o,epsilon_o,Delta_o,s_o,delta_o,Omega_o)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "body"_B(
    "freshprompt" p " in " "handle"[p,h,i](e))
    ⇓ cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

最后一个 premise 同时检查：

- result type 不泄漏 identity；
- residual row 不泄漏 `{i}`；
- closure/capture 不保留 `i`；
- private temporal lock 由 `hideIdentity` 在 runner边界投影掉；
- handler origin 的 Owner 仍 outlive 结果。

合法 existential container 使用单独的 packaging rule，不能删除 escape
premise。

== Handler ordering

Nested `with` 按 elaboration 后的普通 evaluation order和 T-Handle 规则
right-fold：

$
  "freshprompt" p_1."handle"[p_1](h_1,
    "freshprompt" p_2."handle"[p_2](h_2,e))
  !=
  "freshprompt" p_2."handle"[p_2](h_2,
    "freshprompt" p_1."handle"[p_1](h_1,e))
$

Typing 不对 handler stack 排序；optimizer 也不能仅凭 row set equality交换。

= Capture、storage boundary 与 Owner

== Capture inference

Capture function按 value 结构递归：

```text
cap(x)               = capture annotation of x
cap(λx.e)            = cap(e) \ cap(x)
cap((v1, ..., vn))   = ⋃ cap(vi)
cap(Cap[ι,F])        = {ι}
cap(Owner[ρ])        = {owner(ρ)}
cap(Resume[k])       = {resume(k)} ∪ capturedSuffix(k)
```

普通 immutable `Int`、`String` 和 owned immutable ADT 不贡献 capability
capture；它们的 temporal provenance 仍须另外检查。

== Storage boundary

#irule(
  [T-Store-Boundary],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
    [$K;I ⊢ chi " valid-at " b$],
    [$"ProvenanceValid"(A,pi,Theta,b)$],
    [$"QuantityValid"(A,chi,b)$],
  ),
  [$K;I;Phi@Theta ⊢ "store"_b(v) : A$],
)

典型拒绝：

- callback-local borrow 保存到 `Next`；
- stack-only handler 保存进 Task continuation；
- one-shot resumption 放进 many-call closure；
- candidate-local Commit gate 保存回 candidate；
- child Owner capability 返回到 parent scope外；
- nonduplicable cleanup segment 被 `ctl` continuation 捕获。

== Multi-shot capture

#irule(
  [T-Capture-Ctl],
  (
    [$"maxUses"(m)=omega$],
    [$kappa in "sites"(e,a,p) quad "route"(kappa)=p
      quad "provenance"(kappa)=Pi_k quad "captures"(kappa)=chi_k$],
    [$"DuplicableEnv"(Pi_k,chi_k)$],
    [$"EnvValidAt"(Pi_k,chi_k,"MultiShot")$],
    [$"ReplayableCleanup"("cleanup"(kappa),Pi_k,chi_k)$],
    [$"WorldForkSafe"("world"(kappa))$],
  ),
  [$K;I ⊢ "install-site"[e,a,m,kappa] " ok"$],
)

TR₀ 中 `WorldForkSafe(w)` 当且仅当 $w$ 对 lock projection是恒等变换。
这比只检查 operation自己的 $zeta$ 更强：suffix中的 `yield` 也会使整个
$w_k$ 非恒等，因而不能被 multi-shot resume两次。未来若设计显式
branch-world join，可用 sealed witness扩展此 predicate；基线不会把第一次
resume产生的 lock当成第二次 resume的输入。

这条规则解释以下拒绝，而不依赖 Host effect：

```cire
effect OneShot {
  once obtain() -> Int
}

let bad = handler OneShot {
  once obtain() as k => {
    with Choice::all()
    in {
      let value = Choice::choose([1, 2])
      k.resume(value)
    }
  }
}
```

`Choice` 的 multi-shot suffix 捕获 `once k`，使其 usage 从 $1$ 提升到
$omega$。

== Owner-bound parking

#irule(
  [T-Park],
  (
    [$"src":"CompletionSource"[rho,B] in Theta$],
    [$o:"Owner"[rho] in Theta$],
    [$k:"Resume"[1,D_k,A,B,Pi_k,chi_k,rho_k] quad Omega(k)="Open"(1)$],
    [$"Outlives"(rho,rho_k)$],
    [$"SuspensionStable"(rho,"summary"(D_k),Pi_k,chi_k)$],
    [$"OwnerBoundParking"(rho,D_k)$],
    [$"SealCompletion"("src",o,k) ⇓ ⟨g,c,"port"⟩$],
    [$P="ParkContract"(rho,g,c,"port",D_k,Pi_k,chi_k)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"transfer" "park"("src",o,k) ⇓
    "Transfers"(P) ! emptyset;emptyset ▷
    "request"("Owner"(rho),"MaySuspend");delta_"park"
    @Theta⊣Omega[k↦"Transferred"(rho,g,c)]$],
)

Surface 第一方协议把 `source.park(k, under = owner)` elaboration为
`park(src,o,k)`。它消耗 clause 当前 disposition ownership并终止当前 path；
因此不能伪装成 `Unit` 后继续执行 suffix。Owner runtime随后只向宿主暴露
generation-bound `CompletionPort[ρ,B]`，并对 resume/finalize承担唯一责任。
Raw `Resume` 不会被普通 host callback捕获；只有 sealed completion source
能构造 port 和 $P$。

`examples/spec/accept/owner-park.cire` 的关键推导链是：

```text
Async::await site
  → Demand(κ, p, Async, await, Primary)
  → once clause owns k : Open(1)
  → T-Park changes k to Transferred(ρ,g,c)
  → T-Body-Transfer yields {Transfers(ParkContract)}
  → T-Handle-*-Paths preserves that path
  → RowSplit(Δ,p) removes the handled Async demand
  → function body has declared_type Int, flow={Transfers}, row={}
```

这里没有任何一步把 transfer构造成 `Unit`、`Returns` 或 `Aborts`。

TR₀ 只允许 park `once` resumption；
`ctl` 必须在 clause内同步使用并最终 finalize。若未来要 transfer multi-shot
continuation，Owner machine必须另加 q-indexed `CtlOpen/CtlClosed` protocol。

== Owner runtime state

Owner machine state：

$
  O_r(rho,g) ::= "Open" | "Closing" | "Closed"
$

One-shot disposition：

$
  d ::= "Unclaimed" | "Completed" | "Finalized"
$

合法 transition：

```text
port-complete:
  Open(ρ,g) × Unclaimed(c) → Open(ρ,g) × Completed(c)

claim-finalize:
  (Open | Closing) × Unclaimed → state × Finalized

stale/duplicate completion:
  any nonmatching generation or claimed c → no state change

close:
  Open → Closing
  revoke all new resume/callback/register authority
  detach children, resumptions, cleanup
  child-first cleanup; per-owner LIFO
  Closing → Closed
```

`CompletionPort.complete(outcome)` 与 Owner close/cancel 对同一 $c$ 做 CAS；
胜者执行 captured continuation 或 cleanup，败者只得到
`Stale | AlreadyCompleted | OwnerClosed`。Port 不是 `Shareable(R)` 的广播
容器，也没有复制 continuation 的 API；可复制的 `Task` completion handle
建立在这个 sealed source之上，而不是反过来。

所有 callback、resume 和 commit 在使用前验证：

$
  (rho, g_"captured") = (rho, g_"current")
$

静态 region 防止明显 escape；generation gate 处理 FFI、ABA、已排队 callback
和真实 completion/cancel race。

== Cleanup invariants

```text
capture k
  cleanup segment moves with k

resume k
  re-enter the dynamic cleanup segment

finalize k
  unwind that segment exactly once

park source owner k
  seal a generation-bound completion port and transfer final disposition
```

GC 只回收不可达内存，不决定网络取消、listener 移除或 continuation cleanup
的时机。

= Async、suspension 与 phase

== Task outcome 保持抽象

Core 使用：

$
  "Task"[rho,R]
$

$R$ 已经是任务对等待者产生的完整 outcome。Surface 可以选择：

#block(breakable: false)[
```text
R = A
  with Error/Cancel effects

R = Result[A, E]

R = Outcome[A, E, Cancelled]
```
]

这不会改变 suspension、Owner 或 one-shot continuation 的规则。

第一版把 `Task[ρ,R]` 定义为可复制的 completion handle，允许多个 waiter；
因此 formation要求 `Shareable(R)` 与 `AsyncBoundarySafe(ρ,R)`。未来若要
支持 affine/borrowed outcome，必须另设 single-consumer task并引入一般
quantity规则，不能让普通 `Task` 暗中复制它。

== Await contract

```cire
pub(open) effect Async {
  once[R] await(task : Task[R]) -> R
    may_suspend
}
```

其 logical transition 是 `same`；`may_suspend` 不增加 clock lock。

`await(t)` 的 synthesis完全使用 T-Operation，signature额外要求
`Φ_req=Action`，产生：

```text
row contribution        Anon(Async)
suspension contribution request(Anon(Async), MaySuspend)
world transition        same
result summary          sealed OutcomeSummary(t)
```

在实际 Async delimiter安装处，每个 await site还必须满足：

#irule(
  [T-Await-Site],
  (
    [$kappa in "sites"(e,"Anon"("Async"))$],
    [$"taskRegion"(Xi(kappa))=rho$],
    [$"CurrentOwner"(Phi)=rho_o quad "Outlives"(rho_o,rho)$],
    [$Pi_k="provenance"(kappa) quad chi_k="captures"(kappa)$],
    [$"SuspensionStable"(rho_o,"summary"(kappa),Pi_k,chi_k)$],
    [$"OwnerBoundParking"(rho_o,P_h)$],
  ),
  [$K;I;Phi ⊢ "install-await-site"(kappa,P_h):"OK"$],
)

Ready fast path 仍按 `MaySuspend` 检查，因为 static semantics 不能依赖运行时
是否恰好 ready。`pub(open)` 第三方 handler只有在持有可信
`OwnerBoundParking` certificate时才能离开 clause并保持 parked；否则必须在
返回前同步 resume/finalize。`taskRegion` 只从 $Xi_k$ 中实际
`Task[ρ,R]` argument的 nominal type读取；$P_h$ 则显式来自当前 delimiter，
二者不会被错误地塞进 body-only suffix分析。

== Handler placement

最近 Async delimiter 内侧的 handler如果进入 parked suffix，必须满足：

$
  Pi_h="provenanceFV"("handler-env",Theta)
  quad
  "SuspensionStable"(rho, delta_h, Pi_h, chi_h)
$

Async runner 外侧的 stack-only handler不自动进入 parked continuation。
Runner 若携带 outer context，必须通过 `Portable` certificate 和 capture
checking 显式声明。

== Atomic

#irule(
  [T-Atomic],
  (
    [$Phi'="enterAtomic"(Phi)$],
    [$K;I;Phi';Omega@Theta ⊢ e ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta'⊣Omega'$],
    [$"grade"(s)="NoSuspend" quad "locks"(Theta')="locks"(Theta)$],
    [$"AtomicAllowed"(epsilon,delta,chi)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "atomic"(e) ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta'⊣Omega'$],
)

#irule(
  [T-Atomic-Abort],
  (
    [$Phi'="enterAtomic"(Phi)$],
    [$K;I;Phi';Omega@Theta ⊢_"abort" e ! epsilon ▷ s;delta ⊣Omega'$],
    [$"grade"(s)="NoSuspend" quad "AbortWorldNeutral"("evidence"(e))$],
    [$"AtomicAllowed"(epsilon,delta,emptyset)$],
    [$delta_o="rollbackAtomic"(delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" "atomic"(e) ! epsilon ▷ s;delta_o ⊣Omega'$],
)

若 body 推出 `MaySuspend`、clock transition 或 Commit publication，
T-Atomic 不可应用。因此 transaction 不跨 await。Abortive path只有在
`AbortWorldNeutral` 证明已执行 prefix没有 clock transition时可离开；
sealed rollback summary保留已执行/回滚行为。

== Await 与 Next

T-Delay 明确要求 `NoSuspend`。所以即使 Browser handler消除了 Async row：

```cire
delay[frame] {
  with BrowserAsync::run(owner)
  in {
    Async::await(task)
  }
}
```

若 Browser handler的 `actualSusp` 是 `MaySuspend`，则
`grade(handleSusp(s,Async,C_h))=MaySuspend`，T-Delay仍失败。只有真正
同步、带 sealed evidence 的 handler才能收紧成 `NoSuspend`。

先 await 再 delay：

```cire
let value = Async::await(task)
delay[frame] {
  pure_transform(value)
}
```

在 `value` 的 provenance、capture 与 result type满足
`TemporalStable`、`CrossWorldSafe`、`Shareable` 时可推导。

== Choice 与 await

若 multi-shot Choice continuation包含 await，基线 profile要求显式
Task/Owner fork policy：

$
  "ForkTaskSafe"(P_"choice", rho, Pi_k, chi_k)
$

默认不存在该 witness，因此拒绝：

```cire
with Choice::all()
in {
  let endpoint = Choice::choose(endpoints)
  Async::await(fetch(endpoint))
}
```

await 后才安装并完全处理纯 Choice，不复制 parked continuation，可以接受。

= 第一方 reactive/incremental 类型契约

这些对象是第一方 library/runner contract，不是新增 parser keyword。Core
给它们专用 intrinsic rule，只为了保留 phase、capture、trace 与 Owner
evidence；普通 API 可保持 trailing-lambda 外观。

== 对象分类

#table(
  columns: (1.2fr, 2.2fr, 2.8fr),
  [*类型*], [*时序语义*], [*关键约束*],
  [`Source[ρ,A]`], [可写输入、产生 revision], [`Shareable(A)`；写入进入下一 Epoch],
  [`Live[ρ,A]`], [持续维护的 committed current value], [`Shareable(A)`；属于 Owner ρ],
  [`Event[ρ,E]`], [有序 occurrence], [`Shareable(E)`；保留顺序与 multiplicity],
  [`Signal[ι,A]`], [按 clock ι 展开], [`Shareable(A)`；tail 是 `Next`],
  [`Task[ρ,R]`], [至多完成一次], [Owner/generation、one-shot claim],
  [`Resource[ρ,K,R]`], [Live key 到 Task generation 的桥], [显式 concurrency/replacement policy],
)

Affine payload、one-shot resumption 和 callback borrow 不进入广播
`Live`/`Event`/`Signal`；它们使用 separate single-consumer Owner-bound type。

== Source

Kinding：

#irule(
  [K-Source],
  (
    [$K;I ⊢ A:"Type"$],
    [$"Shareable"(A)$],
    [$K ⊢ rho:"OwnerRegion"$],
  ),
  [$K;I ⊢ "Source"[rho,A]:"Type"$],
)

Snapshot read 与 invalidating read 是不同 operation：

```text
Observe.read(source)
  invalidating; records a Cut

Snapshot.read(source)
  reads current fixed snapshot; does not subscribe
```

Source write 需要 Action/Atomic authority，且其可见值进入下一 Epoch，不能修改
当前正在 replay 的 snapshot。

#irule(
  [T-Source-Write],
  (
    [$a_w="Anon"("SourceUpdate") quad s_w="request"(a_w,"NoSuspend")$],
    [$K;I;Phi@Theta ⊢_v s ⇒ "Source"[rho,A] @[pi_s] ▷ chi_s$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi_v] ▷ chi_v$],
    [$"ActionOrAtomicWrite"(Phi) quad "SourceBoundarySafe"(rho,A,pi_v,chi_v)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "sourceWrite"(s,v) ⇒ "Unit" @["Stable"] ! {a_w} ▷ s_w;delta_"pending-write";emptyset @Theta⊣Omega$],
)

第一方 Action runner消除 `SourceUpdate` 并按 INC-Write写入 $P$ 或 batch
journal。`Snapshot.read` 具有 `same` world、`NoSuspend` 与 sealed
fixed-Epoch certificate；它不产生 Observe site，也不登记 dependency。

== Observe

Surface operation：

```cire
pub effect Observe {
  ctl[A] read(source : Source[A]) -> A
}
```

普通 `ctl` 只授予 general control。若
`checkpoint-profile = sealed-checkpoint`，resolver 给可信第一方 handler
额外的 Kernel contract：

$
  "CheckpointLease"[A,B,rho]
$

它内部携带 opaque candidate/Owner generation，但运行时 $g$ 不进入 type
equality。它不能被普通用户构造，也不改变四种 surface mode。

== Live <rule-live>

Core typing rule让 Owner 显式出现；surface `Live[A]` 可以把当前 Owner region
作为 inferred/captured parameter 隐藏：

```text
elab_liveρ(e):
  create hidden ιo : Observe @ ρ
  in e, resolve the first-party contextual form read(source)
    to op[Named(ιo, Observe)]("read", source)
  ιo is not introduced into surface name lookup
```

因此本文示例中的 bare `read(...)` 精确产生 $a_o$，不是
`Anon(Observe)`。显式调用其他 anonymous Observe instance不会被悄悄
重绑定，仍会因 residual row premise而被拒绝。

#irule(
  [T-Live],
  (
    [$"CurrentOwner"(Phi)=rho$],
    [$i_o ∉ "dom"(I) quad I'=I,i_o:"Observe"@rho$],
    [$a_o="Named"(i_o,"Observe") quad Phi_c=⟨"Compute",{a_o},rho⟩$],
    [$K;I';Phi_c;Omega@Theta ⊢ e ⇒ A @[pi_e] ! epsilon_e ▷ s_e;delta_e;chi_e @Theta_e⊣Omega$],
    [$epsilon_e subset.eq {a_o} quad "grade"(s_e)="NoSuspend" quad "locks"(Theta_e)="locks"(Theta)$],
    [$K;I';Phi_c@Theta ⊢ "sites"(e,a_o) ⇓ bar(kappa_o)$],
    [$"InstallCheckpointOK"(bar(kappa_o),rho) ⇓ E_o quad "ReplaySafe"(delta_e)$],
    [$i_o ∉ "fv"(A,pi_e,chi_e,delta_e)$],
    [$chi_"raw"="captureFV"(e,Theta)$],
    [$chi_"env"="hideIdentityCapture"(chi_"raw",i_o,rho,E_o)$],
    [$Pi_"raw"="provenanceFV"("fv"(e),Theta)$],
    [$Pi_l="hideIdentityProvenance"(Pi_"raw",i_o,rho,E_o)$],
    [$chi_l={"owner"(rho)} ∪ chi_"env" ∪ chi_e$],
    [$"EnvBoundarySafe"("fv"(e),Theta,"OwnerStorage"(rho))$],
    [$"TraceCaptureSafe"(rho,chi_l) quad "StorageBoundarySafe"(rho,A,pi_e,chi_e)$],
    [$"Shareable"(A) quad i_o ∉ "fv"(Pi_l,chi_l)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "live"_rho(e) ⇒ "Live"[rho,A] @["Owner"(rho)] ! emptyset ▷ "direct"("NoSuspend");delta_"live" ⊗ delta_e;chi_l @Theta⊣Omega$],
)

关键点：

- body residual row不含 hidden Observe以外的 entry；`live { 42 }` 因而合法；
- body 不 suspend；
- handler 被消除后留下的 $delta_e$ 仍必须 replay-safe；
- runtime Source dependency不进入 $epsilon$ 或 $chi$；
- suffix capture来自 `sites` backward pass，不能拿 body结果 $chi_e$ 代替；
- raw environment capture中的 hidden $i_o$ 只有在
  `InstallCheckpointOK` 产生 sealed $E_o$ 后，才可抽象成 Owner-owned
  internal runner evidence；body result中的 $i_o$ 仍直接拒绝；
- replay closure的 free environment同时保存 $Pi_l$ 并逐 binder通过
  `EnvBoundarySafe`；空 capture的 callback borrow也不能漏过；
- result capture当前 Owner、body environment与stored payload，因此 `Live`
  不能无主逃逸。

这里的 $epsilon_e subset.eq {a_o}$ 是 normalized closed-row inclusion；
未解开的 open tail不能被假定为空，必须先由 row constraint证明其余 entry
不存在。

最小 surface 可近似：

```text
live : (() -> A ! {Observe}) -> Live[A]
```

== Live 中的其他 handler

State、Choice、Error 是否安全由具体 instance 与 checkpoint相对位置决定。

内部 `Error::result`：

```cire
live {
  with Error::result()
  in {
    parse(read(text))
  }
}
```

若 handler certificate 是 replay-safe，则接受。

外层 Error：

```cire
with Error::result()
in {
  live { parse(read(text)) }
}
```

不满足 T-Live 的 future replay handler scope，拒绝；`live_result` 必须每轮
显式重装 handler。

Choice 包住 Observe cut：

```cire
live {
  with Choice::all()
  in {
    let branch = Choice::choose([left, right])
    read(branch.source)
  }
}
```

需要 `TraceCompatibleFork`，基线无 witness，拒绝。

最后一个 `read` 之后的纯局部 Choice：

```cire
live {
  let x = read(source)
  with Choice::all()
  in {
    x + Choice::choose([1, 2])
  }
}
```

若具体 handler满足 `TemporalPure`、`TraceNeutral` 且结果 `Shareable`，
则 checkpoint suffix未被复制，可以接受。

== Signal

概念 coinductive equation：

$
  "Signal"[i,A]
  ≅
  "Step"(A, "Next"[i,"Signal"[i,A]])
$

要求 `Shareable(A)`。纯 map：

```cire
def[A, B] map_signal(
  frame : cap FrameClock,
  input : Signal[frame, A],
  transform : (A) -> B,
) -> Signal[frame, B] {
  match input {
    Step(value, tail) =>
      Step(
        transform(value),
        delay[frame] {
          map_signal(frame, advance(tail), transform)
        },
      )
  }
}
```

#block(breakable: false)[
还需：

$
  "Shareable"(B)
$

$
  "TemporalStable"(i, "fv"("transform"), Theta)
$

$
  "CrossWorldSafe"(i, "captures"("transform"), I)
$
]

== Event

同步 subscription contract：

```text
on :
  Owner[ρ]
  × Event[ρ,E]
  × (E -> Unit ! ε)
  -> Subscription[ρ] ! ε
```

Listener 是 many-shot，因此：

$
  "DuplicableEnv"(
    "provenanceEnv"(pi_"listener"),
    "captures"("listener")
  )
$

同步 `on` 还要求 listener contract的
`grade(s)=NoSuspend`、latent usage不含 one-shot entry、
`PhaseAllows(Action, Φ_req)`、
$"ProvenanceValid"(E arrow.r "Unit",pi_"listener",Theta,
"OwnerStorage"(rho))$ 与
$K;I ⊢ chi_"listener" " valid-at " "OwnerStorage"(rho)$；
结果 `Subscription[ρ]` capture当前 Owner。`on_async` 使用同一 callback
检查，但把每次 invocation产生的 Task register到 $rho$，并把 policy写入
$delta$。这组 premise是第一方 intrinsic contract的一部分，不能由普通
function type中被省略的字段猜测。

若 action 可 suspend，必须换成：

```text
on_async(owner, policy, event, action)

policy ∈ { Merge, SwitchLatest, Concat, Exhaust }
```

Policy进入 $delta$ 与 Owner runtime，不允许普通 `.on` 隐式选择。

Event 到 current value 的 bridge必须显示 loss/order policy：

```text
hold_latest_lossy
queue_from_event
fold_event
```

== Resource

Core contract：

$
  "resource" :
  "Owner"[rho]
  × "Live"[rho,K]
  × P_"resource"
  × (K arrow.r.long^C "Task"[rho,R])
  -> "Resource"[rho,K,R]
$

要求：

```text
Shareable(K)
loader runs in Action phase
task is registered with Owner ρ
completion validates key-generation and owner-generation
policy explicitly defines replacement/concurrency
```

普通函数 API 接受 `Live[K]`，而不是在普通 argument evaluation 中偷偷执行
`read(keySource)`。

== Compute / Commit

Compute 只能产生 pure/shareable plan：

$
  "Plan"[A]
$

#irule(
  [T-Plan],
  (
    [$Phi."phase"="Compute"$],
    [$K;I;Phi;Omega@Theta ⊢ e ⇒ A @[pi] ! emptyset ▷ s;delta;chi @Theta'⊣Omega$],
    [$"grade"(s)="NoSuspend" quad "TemporalPure"(delta) quad "locks"(Theta')="locks"(Theta)$],
    [$"Shareable"(A) quad "CommitBoundarySafe"(A,pi,chi)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "plan"(e) ⇒ "Plan"[A] @["Stable"] ! emptyset ▷ s;delta;chi @Theta'⊣Omega$],
)

Commit gate：

$
  "CommitTicket"[rho]
  quad
  "CommitGate"[rho]
$

`CommitTicket` 是 INC-Publish为某个 slot/revision产生的 sealed invocation
ticket；`CommitGate` 是由 runner从 ticket派生、指向同一 opaque
$(rho,"slot","revision",g)$ 原子 claim 的可复制 handle，不是 affine
capability；这些 runtime字段不参与 type equality。

#irule(
  [T-Try-Publish],
  (
    [$a_c="Anon"("Commit") quad s_c="request"(a_c,"NoSuspend")$],
    [$Phi."phase"="Commit"$],
    [$K;I;Phi@Theta ⊢_v "gate" ⇒ "CommitGate"[rho] @[pi_g] ▷ chi_g$],
    [$K;I;Phi@Theta ⊢_v "plan" ⇒ "Plan"[A] @[pi_p] ▷ chi_p$],
    [$"GateAuthorized"(Phi,"gate") quad "CommitBoundarySafe"(A,pi_p,chi_p)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "tryPublish"("gate","plan") ⇒ "CommitResult" @["Stable"] ! {a_c} ▷ s_c;delta_"publish";emptyset @Theta⊣Omega$],
)

#irule(
  [T-Commit-Run],
  (
    [$K;I;Phi@Theta ⊢_v t ⇒ "CommitTicket"[rho] @[pi_t] ▷ chi_t$],
    [$"TicketBoundarySafe"(rho,pi_t,chi_t)$],
    [$c " fresh" quad Phi_c=⟨"Commit",{"Anon"("Commit")},rho⟩$],
    [$"GateFromTicket"(t,c) quad "CommitAdequacy"(t,c)$],
    [$Theta_g="bind"(Theta,"gate":"CommitGate"[rho] @["GenerationBound"(rho)] ▷ {"claim"(c)})$],
    [$K;I;Phi_c;Omega@Theta_g ⊢ e ⇒ B @[pi_B] ! epsilon_e ▷ s_e;delta_e;chi_B @Theta_e⊣Omega'$],
    [$epsilon_e subset.eq {"Anon"("Commit")} quad "grade"(s_e)="NoSuspend"$],
    [$Theta_o="dropBinder"(Theta_e,"gate")$],
    [$"claim"(c) ∉ chi_B quad "ProvenanceValid"(B,pi_B,Theta_o,"CommitExit"(rho))$],
    [$s_o="handleSusp"(s_e,"Anon"("Commit"),C_"commit") quad delta_o=delta_e ⊗ P_"commit"$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "commitRun"_rho(t,"gate".e) ⇒ B @[pi_B] ! emptyset ▷ s_o;delta_o;chi_B @Theta_o⊣Omega'$],
)

#irule(
  [T-Commit-Run-Abort],
  (
    [$K;I;Phi@Theta ⊢_v t ⇒ "CommitTicket"[rho] @[pi_t] ▷ chi_t$],
    [$"TicketBoundarySafe"(rho,pi_t,chi_t)$],
    [$c " fresh" quad Phi_c=⟨"Commit",{"Anon"("Commit")},rho⟩$],
    [$"GateFromTicket"(t,c) quad "CommitAdequacy"(t,c)$],
    [$Theta_g="bind"(Theta,"gate":"CommitGate"[rho] @["GenerationBound"(rho)] ▷ {"claim"(c)})$],
    [$K;I;Phi_c;Omega@Theta_g ⊢_"abort" e ! epsilon_e ▷ s_e;delta_e ⊣Omega'$],
    [$epsilon_e subset.eq {"Anon"("Commit")} quad "grade"(s_e)="NoSuspend"$],
    [$"AbortWorldNeutral"("evidence"(e)) quad "NoClaimInAbortEvidence"(c,e)$],
    [$(Omega_o,delta_r)="abortCommitScope"(c,Omega',delta_e)$],
    [$s_o="handleSusp"(s_e,"Anon"("Commit"),C_"commit") quad delta_o=delta_r ⊗ P_"commit"$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" "commitRun"_rho(t,"gate".e) ! emptyset ▷ s_o;delta_o ⊣Omega_o$],
)

运行时原子结果：

```text
Committed
Stale
AlreadyCommitted
```

`CommitAdequacy` 是 sealed runner witness：它把静态 fresh claim $c$ 对应到
ticket内部的 runtime $(ell,r)$ 与 $J(ell,r)$，但不声称该 revision仍
current。Currentness不在 typing premise中；运行时 opaque token决定上述
三个结果。
复制 gate 不复制 claim。普通 broadcast `Event[Revision[Plan[A]]]` 只能携带
shareable revision id 与 plan，不能携带 authority。

Commit phase禁止 `MaySuspend`：

```cire
Commit::run(ticket) { gate =>
  let asset = Async::await(load_asset())
  gate.try_publish(render(plan, asset))
}
```

Async.await operation contract的 `Action` phase premise与 T-Try-Publish的
`Commit` phase premise之间无法形成合法推导。

== Batch

#irule(
  [T-Batch],
  (
    [$Phi_b="enterBatch"(Phi)$],
    [$K;I;Phi_b;Omega@Theta ⊢ e ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta'⊣Omega'$],
    [$"grade"(s)="NoSuspend" quad "locks"(Theta')="locks"(Theta)$],
    [$"BatchAllowed"(epsilon,delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "batch"(e) ⇒ A @[pi] ! epsilon ▷ s;delta;chi @Theta'⊣Omega'$],
)

#irule(
  [T-Batch-Abort],
  (
    [$Phi_b="enterBatch"(Phi)$],
    [$K;I;Phi_b;Omega@Theta ⊢_"abort" e ! epsilon ▷ s;delta ⊣Omega'$],
    [$"grade"(s)="NoSuspend" quad "AbortWorldNeutral"("evidence"(e))$],
    [$"BatchAllowed"(epsilon,delta)$],
    [$delta_o="rollbackBatchJournal"(delta)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort" "batch"(e) ! epsilon ▷ s;delta_o ⊣Omega'$],
)

Batch 只推迟 write/notification；最外层成功结束后把最终 journal合入 pending
queue，随后一次 Freeze才形成 snapshot。失败 rollback不发布失败路径建立的
dependencies/notifications；T-Batch-Abort 是该声明的 static counterpart。
Batch 内禁止 suspend。

= Incremental replacement machine <incremental-machine>

普通 expression semantics 与增量 runtime 分开。Machine configuration：

$
  M =
  ⟨V,W,P,N,E,T,Q,O,C,G,H,B,R_t⟩
$

#table(
  columns: (0.8fr, 4.8fr),
  [$V$], [committed Source map；$V(x)=(nu,v)$ 保存 version/value],
  [$W$], [只含 committed generation 的 weak wake-token index],
  [$P$], [pending writes；尚未进入当前 Epoch],
  [$N$], [outer batch成功后、等待相应 snapshot freeze/delivery 的 notifications],
  [$E$], [$(e_"cur",Sigma)$：当前 epoch 与仍被 candidate pin住的 immutable snapshots],
  [$T$], [committed value/Trace forest；强拥有 Cut、continuation template 与 cleanup],
  [$Q$], [dirty cut到最新 invalidation token/epoch 的 map],
  [$O$], [Owner state、generation、children、tasks、parked resumptions],
  [$C$], [完整 candidate state及其 candidate-local buffer],
  [$G$], [分槽的 committed-cut、candidate、Owner 与 revision generation table],
  [$H$], [$⟨J,L⟩$：Commit claim table与已接受 publication log],
  [$B$], [可选 batch write/notification journal],
  [$R_t$], [detached subtree / cleanup retire queue],
)

Machine transition：

$
  M arrow.r^l_"inc" M'
$

其中 label $l$ 记录 `write`、`batch`、`freeze`、`wake`、`begin`、`read`、
`ready`、`publish`、`abort`、`park`、`close` 或 `commit`。

== Cut 与 candidate 状态

$
  "CutState" ::=
  "Committed"(g,v,T_c,W_c)
  | "Closed"
$

$
  b ::= ⟨T_"stage",W_"stage",R_"readver",J_"cleanup",J_"effect"⟩
$

$
  "CandidateState" ::=
  "Running"(g_c,e,r,b)
  | "Parked"(g_c,e,r,b,rho,g_o,k)
  | "Ready"(g_c,e,r,v,b)
  | "Published"
  | "Aborted"(d_a)
$

$
  d_a ::= "stale-input" | "cancel" | "error"
  | "obsolete" | "owner-closed"
$

一个 candidate开始时旧 committed tuple $(g,v,T_c,W_c)$ 仍然有效。
Candidate-local $b$ 保存 speculative trace、wake registration、cleanup与
bufferable effect；只有 publish原子安装。Abort丢弃 $b$ 并保留旧 committed
tuple。

== Source write

#irule(
  [INC-Write],
  (
    [$B=[] quad P'=P[x↦v]$],
  ),
  [$M arrow.r^"write"(x,v)_"inc" M[P↦P']$],
)

当前 Epoch $E$ 不变化。Flush/replay 内发生的新写入也只进入 $P$。

Batch 内的 write只进入 journal：

```text
INC-Batch-Begin:
  B → B · Batch(∅writes, ∅notifications)

INC-Batch-Write:
  B · Batch(Jw, Jn)
    --write(x,v)→ B · Batch(Jw[x ↦ v], Jn)

INC-Batch-Commit-Inner:
  B · Batch(Jw0, Jn0) · Batch(Jw1, Jn1)
    → B · Batch(merge(Jw0,Jw1), merge(Jn0,Jn1))

INC-Batch-Commit-Outer:
  [Batch(Jw, Jn)] → []
  atomically merge Jw into P and Jn into N

INC-Batch-Rollback:
  B · Batch(Jw, Jn) → B
  discard the top journal
```

这些 transition与 T-Batch 的 `NoSuspend` premise配对；失败路径不会把 journal
内容送入 $P$、$W$ 或 notification queue。Freeze把 $N$ 中对应 outer
commit的 notifications标记为 epoch $e'$；`INC-Notify` 只在该 snapshot
committed后按序 delivery并从 $N$ 移除。Notification handler若失败，其错误
进入独立 Action/Owner路径，不回滚已经 committed 的 Source snapshot。

== Freeze Epoch

令：

$
  V' = "applyPending"(V,P)
$

$
  D = {c | exists x in "changed"(V,V'). "validWake"(W,x,c,O,G)}
$

#irule(
  [INC-Freeze],
  (
    [$B=[] quad P != emptyset$],
    [$e'="currentEpoch"(E)+1 quad E'="addSnapshot"(E,e',V')$],
    [$Q'="markDirty"(Q,D,e')$],
    [$N'="attachEpoch"(N,e')$],
  ),
  [$M arrow.r^"freeze"_"inc" M[V↦V',P↦emptyset,N↦N',E↦E',Q↦Q']$],
)

Snapshot $Sigma(e)$ 在所有持有该 epoch lease的 candidate结束前保留。同一
candidate的所有 `Observe.read` 都读取它在 Begin时 pin住的 $Sigma(e)$；
后续 Freeze可以增加新 snapshot，但不能修改旧 snapshot。

#irule(
  [INC-Notify],
  (
    [$n in N quad "notificationReady"(n,E,T)$],
    [$N'=N-{n}$],
  ),
  [$M arrow.r^"notify"(n)_"inc" M[N↦N']$],
)

Outer batch没有 write时，其 notifications在 commit时直接标记当前 epoch；
否则由 INC-Freeze的 `attachEpoch` 标记。只有对应 snapshot已经 committed的
notification满足 `notificationReady`。

== Earliest invalidation frontier

$
  "frontier"(Q,T)
  =
  {c in "dom"(Q) |
    not exists a in "dom"(Q). "ancestor"_T(a,c)}
$

Scheduler 只为 frontier cut开始 candidate；有 dirty ancestor 的后代将由祖先
replacement处理，不能继续恢复旧 continuation。

== Begin candidate

#irule(
  [INC-Begin],
  (
    [$T(c)="Committed"(g,v_c,T_c,W_c)$],
    [$"frontierMember"(c,Q,T)$],
    [$"ownerValid"(c,O,G)$],
    [$"noActiveCandidate"(C,c)$],
    [$g_c="freshCandidateGeneration"(c,G) quad e="currentEpoch"(E)$],
    [$r=Q(c) quad b_0="emptyBuffer"(c,g_c)$],
    [$C'=C[c↦"Running"(g_c,e,r,b_0)]$],
    [$G'="setCandidateSlot"(G,c,g_c)$],
  ),
  [$M arrow.r^"begin"(c,g_c)_"inc" M[C↦C',G↦G',E↦"pin"(E,e)]$],
)

`begin` 不改 committed generation $g$，也不先销毁 $T_c$；candidate
generation写入独立 slot。`noActiveCandidate` 是 CAS premise，防止重复
Begin覆盖尚待 cleanup 的 candidate。

== Observe read

Candidate $c$ 在 Epoch $e$ 执行：

#irule(
  [INC-Read],
  (
    [$C(c)="Running"(g_c,e,r,b)$],
    [$"snapshotAt"(E,e)(x)=(nu,v)$],
    [$d="freshStagedCut"(c,g_c,x,G)$],
    [$b'="stageRead"(b,d,x,nu,"ownerGen"(c))$],
  ),
  [$M arrow.r^"read"(c,x,v)_"inc" M[C↦C[c↦"Running"(g_c,e,r,b')]]$],
)

依赖 edge 与 weak wake token只写入 $b$；它们在 publish前既不属于 $T$，
也不属于 $W$。依赖仍由本轮实际控制流产生，不进入 type-level
$epsilon$ 或 $chi$。

== Candidate completion

#irule(
  [INC-Ready],
  (
    [$C(c)="Running"(g_c,e,r,b)$],
    [$"candidateStepToValue"(c,e,b)=(v,b')$],
    [$"candidateValid"(c,g_c,O,G)$],
  ),
  [$M arrow.r^"ready"(c,v)_"inc" M[C↦C[c↦"Ready"(g_c,e,r,v,b')]]$],
)

`candidateStepToValue` 是 typed source evaluation与 trace recorder的抽象
simulation boundary；它不能直接修改 committed $T/W/V$。

== Candidate publish

#irule(
  [INC-Publish],
  (
    [$C(c)="Ready"(g_c,e,r,v',b)$],
    [$T(c)="Committed"(g,v,T_c,W_c)$],
    [$"candidateValid"(c,g_c,O,G)$],
    [$"stagedReadVersionsCurrent"(b,V)$],
    [$(T',W',G',H',R_t',t)="atomicReplace"(c,g_c,v',b,T,W,G,H,R_t)$],
    [$Q'="ackAndRetireDescendants"(Q,c,r,T_c)$],
    [$C'=C[c ↦ "Published"]$],
  ),
  [$M arrow.r^"publish"(c,g_c,t)_"inc" M[T↦T',W↦W',G↦G',H↦H',R_t↦R_t',C↦C',Q↦Q',E↦"unpin"(E,e)]$],
)

`atomicReplace` 的线性化点同时：

1. 安装 committed value、replacement subtree与 staged wake registrations；
2. 使旧后代 generation失效；
3. 产生下一 committed cut lease、`CommitTicket`及对应 revision/OpenClaim；
4. 从 $W$ 移除旧 registrations，并把旧 subtree放入 $R_t$；
5. 只在 $Q(c)=r$ 时 acknowledge本轮 invalidation；若之后又被标脏则保留；
6. 随后由 Owner/finalizer exactly-once retire旧资源。

Host publication不在 INC-Publish 中发生；它还要经过 Commit gate。
Publish transition的输出 label携带 sealed ticket $t$，runner只能把这个
输出交给 T-Commit-Run 对应的 commit callback；surface program没有 ticket
constructor。`CommitAdequacy(t,c)` 正是该 label中 runtime
slot/revision/OpenClaim 与静态 fresh claim之间的桥。

若 candidate运行期间发生了后续 Freeze，$W$ 尚未包含 staged dependency，
所以 publish必须原子验证 $b$ 记录的 Source versions仍等于当前 $V$。失败按
`reason=stale-input` 走 INC-Abort/rearm，避免“新依赖在 publish前变化却漏掉
wake”的竞态。

$
  "stagedReadVersionsCurrent"(b,V)
  quad "iff" quad
  forall (x,nu) in R_"readver"(b).
  "version"(V,x)=nu
$

== Candidate abort

#irule(
  [INC-Abort],
  (
    [$"tag"(C(c)) in {"Running","Parked","Ready"}$],
    [$d_a in "AbortReason"$],
    [$(g_c,e,r,b)="candidateFields"(C(c))$],
    [$C'=C[c↦"Aborted"(d_a)]$],
    [$Q'="abortQueue"(Q,T,c,r,d_a)$],
    [$R_t'=R_t+"candidateCleanup"(b)$],
  ),
  [$M arrow.r^"abort"(c,d_a)_"inc" M[C↦C',Q↦Q',R_t↦R_t',G↦"clearCandidateSlot"(G,c,g_c),E↦"unpin"(E,e)]$],
)

`AbortReason` 是上式 $d_a$ 的有限语法；`abortQueue` 是总函数：

```text
stale-input / cancel:
  if c is still a live committed cut, preserve or rearm its newest dirty token
  otherwise remove its invalidated queue entry
error:
  if c is still live, retain an error marker; otherwise remove the entry
obsolete / owner-closed:
  remove c and invalidated descendants; never rearm them
```

Abort不清理仍 committed且仍 live的旧 subtree，也不发布 candidate buffer。
Semantic error在 $Q$ 中留下 error marker，所以这种状态不算 successful
quiescence。被 ancestor replacement淘汰或 Owner关闭的 cut已经不再可调度，
因此不能重新放回 $Q$。

== Park 与 stale completion

#irule(
  [INC-Park],
  (
    [$C(c)="Running"(g_c,e,r,b)$],
    [$k="currentContinuation"(c)$],
    [$"ownerValid"(rho,g_o,O)$],
    [$"candidateValid"(c,g_c,O,G)$],
  ),
  [$M arrow.r^"park"(c,rho,g_o)_"inc" M[C↦C[c↦"Parked"(g_c,e,r,b,rho,g_o,k)]]$],
)

普通最小 `Live` 不触发 Park；该 transition只供 richer candidate/resource
runner。Completion恢复前验证：

$
  "ownerValid"(rho,g_o,O)
  and
  "candidateValid"(c,g_c,O,G)
$

两者成立时 `INC-Unpark` 恢复为 `Running(g_c,e,r,b)`；失败则转
`INC-Unpark-Invalid` 并只 finalize completion payload，不恢复旧
continuation。

#irule(
  [INC-Unpark],
  (
    [$C(c)="Parked"(g_c,e,r,b,rho,g_o,k)$],
    [$"ownerValid"(rho,g_o,O) quad "candidateValid"(c,g_c,O,G)$],
    [$b'="resumeParked"(b,k,v)$],
  ),
  [$M arrow.r^"complete"(k,v)_"inc" M[C↦C[c↦"Running"(g_c,e,r,b')]]$],
)

#irule(
  [INC-Unpark-Invalid],
  (
    [$C(c)="Parked"(g_c,e,r,b,rho,g_o,k)$],
    [$not ("ownerValid"(rho,g_o,O) and "candidateValid"(c,g_c,O,G))$],
    [$d_a="invalidCompletionReason"(rho,g_o,c,g_c,O,G)$],
    [$d_a in {"owner-closed","obsolete"}$],
    [$Q'="abortQueue"(Q,T,c,r,d_a)$],
    [$R_t'=R_t+"candidateCleanup"(b)+"completionCleanup"(k,v)$],
    [$C_a=C[c↦"Aborted"(d_a)]$],
    [$M_a=M[C↦C_a,Q↦Q',R_t↦R_t']$],
    [$M_o=M_a[G↦"clearCandidateSlot"(G,c,g_c),E↦"unpin"(E,e)]$],
  ),
  [$M arrow.r^"complete/discard"(k,v,d_a)_"inc" M_o$],
)

`invalidCompletionReason` 在 handler Owner generation失效时返回
`owner-closed`，否则返回 `obsolete`。这两个分支都只 cleanup/drop queue；
把它们误记成 `stale-input` 会制造永远不再满足 INC-Begin 的垃圾项。

== Commit claim

Claim state：

$
  J(ell,r) ::= "OpenClaim" | "CommittedClaim" | "RevokedClaim"
$

$ell$ 是 publication slot，$r$ 是 revision；Owner generation、candidate
generation与 revision是不同 namespace。$H=⟨J,L⟩$，$L$ 是已经通过 claim
linearization point 的抽象 host publication log。

#irule(
  [INC-Commit],
  (
    [$H=⟨J,L⟩ quad J(ell,r)="OpenClaim"$],
    [$"currentRevision"(ell,O,G)=r$],
    [$J'=J[(ell,r)↦"CommittedClaim"]$],
    [$L'=L dot "publish"(ell,r,p)$],
  ),
  [$M arrow.r^"tryPublish"(ell,r,p)_"inc" M[H↦⟨J',L'⟩]$],
)

#irule(
  [INC-Commit-Already],
  (
    [$H=⟨J,L⟩ quad J(ell,r)="CommittedClaim"$],
  ),
  [$M arrow.r^"tryPublish/AlreadyCommitted"(ell,r,p)_"inc" M$],
)

#irule(
  [INC-Commit-Stale],
  (
    [$H=⟨J,L⟩$],
    [$J(ell,r)="RevokedClaim" " or " (J(ell,r)="OpenClaim" and "currentRevision"(ell,O,G) != r)$],
  ),
  [$M arrow.r^"tryPublish/Stale"(ell,r,p)_"inc" M$],
)

失败 transition显式返回 `AlreadyCommitted`/`Stale` 且 $J/L$ 都不变化。
由原子 compare-and-swap得到 accepted
publication的动态 at-most-once。若真实 host delivery可在 linearization后
失败，adapter还需幂等 key $(ell,r)$ 或 `Publishing/Delivered` protocol；
本文不把外部网络 exactly-once混同于 claim safety。

== Owner close

Owner close transition分两阶段：

```text
revoke:
  Open → Closing
  revoke resume/callback/register/commit authority
  change every owned OpenClaim to RevokedClaim
  seal and detach children, candidates, resumptions, cleanup

cleanup:
  close children first
  finalize parked resumptions
  abort owned candidates
  cancel tasks/resources
  run per-owner cleanup in LIFO order
  aggregate failures
  Closing → Closed
```

Host disposer可抛错或同步重入，所以必须先 revoke 再调用。

#irule(
  [INC-Close-Revoke],
  (
    [$"ownerState"(O,rho)="Open"$],
    [$(O',E',T',W',Q',C',G',H',R_t')="revokeOwner"(rho,O,E,T,W,Q,C,G,H,R_t)$],
  ),
  [$M arrow.r^"close/revoke"(rho)_"inc" M[O↦O',E↦E',T↦T',W↦W',Q↦Q',C↦C',G↦G',H↦H',R_t↦R_t']$],
)

`revokeOwner` 是一个原子 abstract operation：它先把 Owner设为 `Closing`
并推进 generation；把所属 OpenClaim改为 `RevokedClaim`；关闭或 detach
所属 cut；移除其 committed wake/dirty entries；把 live candidate改为
`Aborted(owner-closed)`、清除 candidate slots并 unpin其 epochs；最后把
resumption、child与 cleanup责任移入 $R_t$。任何 user disposer都只会在
这个线性化点之后运行。

#irule(
  [INC-Retire],
  (
    [$r_t in R_t$],
    [$"cleanupReady"(r_t,O)$],
    [$(O',R_t')="runOneRetire"(r_t,O,R_t)$],
  ),
  [$M arrow.r^"retire"(r_t)_"inc" M[O↦O',R_t↦R_t']$],
)

`runOneRetire` 在调用 user disposer前已原子 claim该 entry；失败被聚合进
$O'$，不会把 entry放回可再次调用状态。

#irule(
  [INC-Close-Done],
  (
    [$"ownerState"(O,rho)="Closing"$],
    [$"ownerRetireComplete"(rho,O,R_t)$],
    [$O'="markOwnerClosed"(O,rho)$],
  ),
  [$M arrow.r^"close/done"(rho)_"inc" M[O↦O']$],
)

== Machine invariants

#block(breakable: false)[
#table(
  columns: (1.1fr, 4.9fr),
  [`I-WEAK`], [$W$ 只含 committed weak token；candidate token在 $b$ 中，Trace/Owner强拥有 continuation。],
  [`I-EPOCH`], [一次 flush中的每个 invalidating read来自同一 fixed Epoch。],
  [`I-FRONTIER`], [同批开始执行的 cuts构成 ancestor antichain。],
  [`I-CANDIDATE`], [每个 committed cut generation至多一个 live candidate。],
  [`I-ISOLATE`], [publish前 candidate buffer与 committed $T/W/V$ 不相交。],
  [`I-VERSION`], [staged read version不再 current的 candidate不能 publish，只能 rearm。],
  [`I-REPLACE`], [成功 candidate原子替换 value/trace/wakes；失败 candidate不改变 committed tuple。],
  [`I-STALE`], [失效 Owner/candidate/revision generation不能 resume 或 commit。],
  [`I-DISPOSE-S`], [每个 one-shot resumption、claim 和 cleanup segment至多 claim/invoke一次。],
  [`I-DISPOSE-L`], [只在 cleanup fairness与successful quiescence假设下，retire queue最终被清空。],
)
]

== Static/runtime adequacy boundary

T-Live本身不证明某个任意 library实现满足上述 machine。第一方 runner必须带
sealed witness：

$
  "ImplementsLive"(R,P_"checkpoint",arrow.r_"inc")
$

它证明 surface/Core `Observe.read` site与 INC-Read simulation、candidate
buffer隔离、Owner/generation checks和 publish linearization对应。
`trusted-ctl` profile把该证明作为 trusted runtime assumption；
`sealed-checkpoint` profile让 `CheckpointLease` 缩小可实现状态空间。FSC
只对拥有这个 witness的 runner陈述。

= 算法化 type checker

== 返回对象

```text
CheckResult {
  type
  flow: nonempty set of
      Returns(temporal_context_out, provenance, result_captures)
      | Aborts
      | Transfers(ParkContract)
  provenance
  residual_row
  attributed_demand
  attributed_suspension
  semantic_summary
  result_captures
  usage_context_out
  latent_site_evidence
  typed_core
  evidence
}
```

`type` 是所有 `Returns` entries 的共同 supertype；provenance/capture/world
保存在各 return entry并在需要单一 normal结果时 join。`Aborts` 与
`Transfers` entries仍共享 row、attributed demand、suspension、summary、
usage、typed Core与 site evidence。`Transfers` 额外保存 sealed
`ParkContract`。集合可以同时包含 return/abort/transfer；只有 set中确实有
`Returns` 才能读取 normal result，terminal entries永远不会被存在一个
normal branch的事实抹掉。

每个 `CheckResult` 还维持
`residual_row == eraseDemand(attributed_demand)`；所有 row elimination都先
partition demand，再重算 public row。

`evidence` 保存：

- kind/row normalization；
- operation/handler contract refinement；
- temporal stability与 boundary checks；
- sealed/trusted policy witness；
- generative identity scope；
- phase gate；
- inserted finalize/park disposition；
- surface-to-Core origin。

== 互递归入口

```text
synth(ctx, expr) -> CheckResult
check(ctx, expr, expected_type) -> CheckResult
check_value(ctx, value) -> ValueResult
check_value_as(ctx, value, expected_type) -> ValueResult
check_body_flow(ctx, expr, expected_type) -> CheckResult
check_args(ctx, args, parameter_types) -> CheckResult
check_block(ctx, items) -> CheckResult
check_handler(ctx, effect, clauses) -> HandlerResult
check_return_clause_schema(ctx, handler_shape, clause) -> ReturnContract
check_clause_schema(ctx, handler_shape, operation_signature, clause)
  -> ClauseSchema
analyze_sites(typed_core, delimiter_entry, answer_contract) -> SiteContracts
install_handler(handler_contract, policy, handled_entry,
                site_contracts, body_flow)
  -> InstallEvidence
```

`ctx` 包含：

```text
K, I, Φ, Ω, Θ
prompt stack: fresh installation prompts with handled entry
expected answer type
current Owner is an explicit field of Φ
constraint worklists
```

== 主递归

每个 strict-position recursive call都经过同一个 early-return combinator：

```text
strict?(result, typed_prefix):
  if no Returns(_) in result.flow:
    return compose_terminal_prefix(typed_prefix, result)
  return {
    normal = join_returns(result.flow),
    side_flow = result.flow - Returns(_),
    evidence = result
  }
```

因此只有 `strict?` 产生 `normal` 后才可读取 `type/π/χ/Θ_out`；其
`side_flow` 在 sequence composition中原样 union回结果。Runner delimiter
body不用这个 helper，而逐 path处理完整 set。
`check_args` 是从左到右的有限 fold；每个 argument都立刻经过 `strict?`，
若某一步没有 return path就立即返回已经执行的 argument prefix；若同时有
return与terminal path，只让 return entries继续检查后续 argument并保存
terminal entries。所以 site node中的 $Xi_k$ 恰好只来自可达、已类型化的
actual argument。

```text
synth(ctx, e):
  match e:
    Var(x):
      return lift_value_to_check_result(
        lookup_available(ctx.Θ, x),
        row = ∅, suspension = direct(NoSuspend),
        summary = pure, Θ_out = ctx.Θ, Ω_out = ctx.Ω)

    Lambda(x, A, B, Φrequired, body):
      require well_formed(A, B, Φrequired)
      symbolic = fresh_rigid_usage_and_argument_summary(A)
      rb = check_body_flow(
        bind(ctx.with_phase(Φrequired).with_usage(symbolic.Ω),
             x, A, symbolic.π, symbolic.χ),
        body, B)
      χclosure = capture_fv(body - x, ctx.Θ)
      Πclosure = provenance_fv(body - x, ctx.Θ)
      u = latent_usage(symbolic.Ω, rb.Ω_out)
      Λ = abstract_sites(rb.typed_core, x)
      require many_call_safe(Πclosure, u, χclosure)
      if has_returns(rb.flow):
        normal = join_returns(rb.flow)
        (Q, Rresult) = abstract_parametric_summary(
          symbolic.π, symbolic.χ, normal, x)
        Θout = drop_binder(normal.Θ_out, x)
        return value(function_contract(
          rb.row, abstract_locks(ctx.Θ, Θout), MayReturn,
          rb.suspension, rb.summary, Πclosure, χclosure,
          u, Rresult, Φrequired, Q, Λ,
          flow_summary = abstract_flow(rb.flow)))
      Q = abstract_parametric_terminal_obligations(
        symbolic.π, symbolic.χ, rb.flow, x)
      return value(function_contract(
        rb.row, bottom, NoReturn,
        rb.suspension, rb.summary, Πclosure, χclosure,
        u, bottom, Φrequired, Q, Λ,
        flow_summary = abstract_flow(rb.flow)))

    App(f, arg):
      rf = strict?(synth(ctx, f), empty_prefix)
      (A, contract, B) = instantiate_function(rf.type)
      ra = strict?(check(rf.ctx_out, arg, A), prefix(rf))
      require phase_allows(ctx.Φ, contract.required_phase)
      Qcall = instantiate(stageCall(contract.obligations),
                          ra.normal.π, ra.normal.χ,
                          ctx.I, ra.normal.Θ_out)
      discharge(Qcall)
      Qinstall = instantiate(stageHandlerInstall(contract.obligations),
                             ra.normal.π, ra.normal.χ,
                             ctx.I, ra.normal.Θ_out)
      Ω3 = apply_usage(ra.Ω_out, contract.latent_usage)
      (Δcall, Λinstall) = instantiate_latent_sites(
        contract.Λ, ra.normal,
        current_prompt_stack = ctx.prompts)
      preserve_until_install(Qinstall, Λinstall)
      side = union(rf.side_flow, ra.side_flow,
                   instantiate_flow(contract.flow_summary, ra.normal))
      if contract.returnability == NoReturn:
        return compose_terminal_call(
          rf, ra, contract, Ω3, side, Δcall, Λinstall)
      Θ3 = apply_transition(contract.world, ra.normal.Θ_out)
      (π3, χ3) = contract.result_summary(
        ra.normal.π, ra.normal.χ)
      return compose_call(
        rf, ra, contract, π3, χ3, Ω3, Θ3,
        side, Δcall, Λinstall)

    Let(x, first, rest):
      r1 = strict?(synth(ctx, first), empty_prefix)
      r2 = strict?(
        synth(bind(r1.ctx_out, x, r1.type, r1.π, r1.χ), rest),
        prefix(r1))
      r2.Θ_out = drop_binder(r2.Θ_out, x)
      return compose_sequence(r1, r2)

    Delay(clock, body):
      ι = resolve_clock_identity(clock)
      Φsym = fresh_symbolic_required_phase()
      inner = synth(push_lock(ctx.with_phase(Φsym), ι), body)
      require inner.flow == {Returns(_)}
        or diagnose "delay body must have one normal payload and no terminal side path"
      require inner.Ω_out == ctx.Ω
      require inner.row == ∅
      require grade(inner.suspension) == NoSuspend
      require locks(inner.Θ_out) == locks(push_lock(ctx.Θ, ι))
      require TemporalPure(inner.summary)
      require TemporalStable(ι, free_values(body), ctx.Θ)
      χdelay = capture_fv(body, ctx.Θ)
      require CrossWorldSafe(ι, χdelay)
      require Shareable(inner.type)
      require TemporalPayloadSafe(
        ι, inner.type, inner.π, inner.χ, χdelay)
      Φforce = solve_and_generalize_required_phase(
        Φsym, inner.phase_constraints)
      L = LaterContract(
        inner.π, inner.χ, inner.summary, Φforce)
      return CheckResult(
        type = Next[ι, inner.type, L],
        flow = {Returns(ctx.Θ, Stable, χdelay)},
        provenance = Stable,
        residual_row = ∅,
        attributed_demand = ∅,
        attributed_suspension = direct(NoSuspend),
        semantic_summary = δ_alloc,
        result_captures = χdelay,
        usage_context_out = ctx.Ω)

    Advance(value):
      Next[ι, A, L] = shape_type_without_availability(value)
        or diagnose "advance expects a Next value"
      (Θ0, lock_ι, Θ1) = split_right(ctx.Θ, ι)
        or diagnose "no matching tick"
      rv = check_value_as(
        ctx.with_Θ(Θ0), value, Next[ι, A, L])
      require phase_allows(ctx.Φ, L.required_phase)
      require Allowed(ctx.Φ, ∅, NoSuspend, L.summary)
      require L.payload_captures ⊆ rv.χ
      return CheckResult(
        type = A,
        flow = {Returns(ctx.Θ, L.payload_provenance, rv.χ)},
        provenance = L.payload_provenance,
        residual_row = ∅,
        attributed_demand = ∅,
        attributed_suspension = direct(NoSuspend),
        semantic_summary = L.summary ⊗ δ_force,
        result_captures = rv.χ,
        usage_context_out = ctx.Ω)

    Operation(receiver, op, args):
      sig = instantiate_fresh(resolve_operation(receiver, op))
      ra = strict?(
        check_args(ctx, args, sig.parameters), evaluated_arg_prefix)
      require phase_allows(ctx.Φ, sig.required_phase)
      a = row_entry(receiver)
      p = resolve_route(ctx.prompts, a)
      κ = fresh_site_slot()
      primary = Demand(κ, p, a, sig.resolved_selector, Primary)
      secondary = instantiate_secondary_sites(
        sig.secondary_sites,
        parent_site = κ,
        prompt_stack = ctx.prompts)
      Δ2 = union(ra.attributed_demand, {primary},
                 secondary.attributed_demand)
      ε2 = eraseDemand(Δ2)
      s2 = join(ra.suspension,
                request(a, sig.suspension),
                secondary.suspension)
      δ2 = ra.summary ⊗ secondary.semantic_summary
      require Allowed(ctx.Φ, ε2, s2, δ2)
      record_site_node(
        site_slot = κ,
        route = p,
        entry = a,
        operation = sig.resolved_selector,
        instantiated_signature = sig,
        secondary_sites = secondary.site_evidence,
        actual_argument_summaries = ra.argument_summaries,
        call_obligations = stageCall(sig.obligations),
        install_obligations = stageHandlerInstall(sig.obligations))
      if sig.mode == abort:
        require sig.world == abortive
        return aborting_flow(
          ra, flow = union(ra.side_flow, {Aborts}),
          attributed_demand = Δ2, residual_row = ε2,
          suspension = s2, summary = δ2)
      Θ2 = apply_transition(sig.world, ra.Θ_out)
      (πr, χr) = sig.result_summary(ra.πs, ra.χs)
      return CheckResult(
        type = sig.result,
        flow = union(ra.side_flow, {Returns(Θ2, πr, χr)}),
        provenance = πr,
        residual_row = ε2,
        attributed_demand = Δ2,
        attributed_suspension = s2,
        semantic_summary = δ2,
        result_captures = χr,
        usage_context_out = ra.Ω_out,
        latent_site_evidence = {primary} ∪ secondary.site_evidence)

    Handle(handler, optional_cap, body):
      rh = check_value(ctx, handler)
      require rh.type has shape
        HandlerTemplate[F, ρh, A, B, εh, (prompt).Ch, Ph]
      p = fresh_prompt()
      if optional_cap:
        require handler_origin_ok(ctx.Φ, rh.origin_owner)
        ι = fresh_identity(rh.effect, rh.origin_owner)
        a = Named(ι, rh.effect)
        ctxι = ctx.extend_identity(ι).add_authority(a)
                  .push_prompt(p, a)
        require phase_allows(ctxι.Φ, rh.required_phase)
        rb = check_body_flow(ctxι, body, rh.handled_input)
        sites = analyze_sites(
          rb.typed_core, a, p, rb.answer_contract)
        install = install_handler(
          p, rh, rh.policy, a, sites, rb)
        result = eliminate_entry_with_contract(
          p, rh, rb, a, sites, install)
        require no_open_private_disposition(ι, result.Ω_out)
        result.Ω_out = hide_identity_usage(result.Ω_out, ι)
        require no_escape_in_flow_evidence(
          ι, result.row, result.attributed_demand, result.suspension,
          result.summary, result.Ω_out)
        for return in returns(result.flow):
          require no_escape(
            ι, result.type, return.π,
            result.row, result.attributed_demand,
            result.summary, return.χ)
          return.Θ_out = hide_identity(return.Θ_out, ι)
      else:
        require phase_allows(ctx.Φ, rh.required_phase)
        a = Anon(rh.effect)
        ctxp = ctx.push_prompt(p, a)
        rb = check_body_flow(ctxp, body, rh.handled_input)
        sites = analyze_sites(
          rb.typed_core, a, p, rb.answer_contract)
        install = install_handler(
          p, rh, rh.policy, a, sites, rb)
        result = eliminate_entry_with_contract(
          p, rh, rb, a, sites, install)
      return result

    Resume(k, value):
      require Ω[k] == Open(q)
      rv = check_value_as(ctx, value, resume_argument(k))
      require phase_allows(ctx.Φ, continuation(k).required_phase)
      Θ2 = apply_transition(continuation(k).full_world, ctx.Θ)
      Ω2 = resume_state(Ω, k, q)
      (πB, χB) = continuation(k).answer_summary(rv)
      return CheckResult(
        type = continuation(k).answer_type,
        flow = {Returns(Θ2, πB, χB)},
        provenance = πB,
        residual_row = continuation(k).residual_row,
        attributed_demand = continuation(k).attributed_demand,
        attributed_suspension = continuation(k).suspension,
        semantic_summary =
          continuation(k).summary ⊗ δ_resume,
        result_captures = χB,
        usage_context_out = Ω2)

    Intrinsic(name, args):
      dispatch to Live / SourceWrite / Plan / TryPublish /
                  Atomic / Batch / CommitRun rules
```

为避免伪代码省略被误读成“其余 Core constructor被 reject”，以下 branch是
对应具名规则的 syntax-directed transcription：

```text
CapAbs / CapApp              T-Cap-Intro / T-Cap-Elim
capref                       T-Cap-Ref
ClockPack                    T-Clock-Pack
ClockUnpack                  T-Clock-Unpack / T-Clock-Unpack-Abort
OwnerAbs / OwnerApp          T-Owner-Intro / T-Owner-Elim
FreshCap                     K-Fresh-Cap / K-Fresh-Cap-Abort
HandlerValue                 T-Handler + check_clause_schema
Finalize                    T-Finalize + cleanup contract composition
Park                         T-Park
Atomic                       T-Atomic / T-Atomic-Abort
Batch                        T-Batch / T-Batch-Abort
CommitRun                    T-Commit-Run / T-Commit-Run-Abort
aborting strict context      T-Ctx-Abort
```

每个 branch都对严格 AST 子树递归，并调用同一 finite kind/row/boundary
worklist；它们不是额外的 declarative oracle。`ClockUnpack` 的 package
operand按 Core grammar是 value $p$，因此算法也先走 `check_value`，不与
T-Clock-Unpack冲突。

== Handler schema 与安装点递归

```text
check_handler(ctx, effect, clauses):
  (return_clause, operation_clause_map) =
    partition_exact_handler_clauses(effect, clauses)
  require exactly one return clause
  require domain(operation_clause_map) == operations(effect)
  require no duplicate or extra operation clause
  (A, B) = resolve_handler_answer_types(effect, return_clause)
  Φsym = fresh_symbolic_required_phase()
  Πenv = provenance_fv(clauses, ctx.Θ)
  χenv = capture_fv(clauses, ctx.Θ)
  owner = current_owner(ctx)
  require env_boundary_safe(
    free_values(clauses), ctx.Θ, OwnerStorage(owner))
  shape = { input = A, answer = B, owner = owner,
            phase_symbol = Φsym,
            env_provenance = Πenv, env_captures = χenv }
  Creturn = check_return_clause_schema(
    ctx, shape, return_clause)
  schemas = {}
  for op in operations(effect):
    clause = operation_clause_map[op]
    schemas[op] =
      check_clause_schema(ctx, shape, op.signature, clause)
  C0 = aggregate_handler(Creturn, schemas)
  C0.required_phase = solve_and_generalize_required_phase(
    Φsym, Creturn.constraints ∪ schemas.constraints)
  C = attach_handler_env(C0, Πenv, χenv)
  P = resolve_sealed_handler_policy(effect, clauses)
  require PolicyOK(P) and Origin(P) == shape.owner
  return HandlerResult(
    type = HandlerTemplate[effect, shape.owner, A, B,
                           C.residual_row, (prompt).C, P],
    contract_template = (prompt).C,
    policy = P,
    provenance = Owner(shape.owner),
    captures = χenv,
    clause_schemas = schemas)

check_return_clause_schema(ctx, handler_shape, clause):
  Θentry = fresh_symbolic_temporal_context()
  return_ctx = import_handler_env(
    ctx.with_phase(handler_shape.phase_symbol).with_Θ(Θentry),
    handler_shape.env_provenance,
    handler_shape.env_captures,
    handler_shape.owner)
  arg = fresh_rigid_argument_summary(handler_shape.input)
  body = check_body_flow(
    bind(return_ctx, clause.parameter,
         handler_shape.input, arg.π, arg.χ),
    clause.body, handler_shape.answer)
  return abstract_return_contract(Θentry, arg, body)
    universally quantified over Θentry and arg

check_clause_schema(ctx, handler_shape, op_sig, clause):
  skolems = fresh_skolems(op_sig.type_parameters)
  opσ = instantiate(op_sig, skolems)
  arg_summaries =
    fresh_rigid_argument_summaries(opσ.parameters)
  params = bind_parameters(opσ.parameters, arg_summaries)
  Θentry = fresh_symbolic_temporal_context()
  p = fresh_symbolic_prompt_slot()
  clause_ctx = import_handler_env(
    ctx.with_phase(handler_shape.phase_symbol).with_Θ(Θentry),
    handler_shape.env_provenance,
    handler_shape.env_captures,
    handler_shape.owner)
  κ = fresh_abstract_site_contract(
    installation_prompt = p,
    operation = opσ.resolved_selector,
    entry_world = Θentry,
    first_transition = opσ.resume_transition,
    obligations = opσ.site_obligations,
    secondary_contract = opσ.secondary_contract,
    actual_arguments = arg_summaries,
  )

  if clause.mode in {once, ctl}:
    q = clause_mode_budget(clause.mode)
    k = Resume[q, κ.D, opσ.result, handler_shape.answer,
               κ.Π, κ.χ, handler_shape.owner]
    result = check_body_flow(
      clause_ctx + params + k:Open(q),
      clause.body, handler_shape.answer)
    require path_sensitive_usage(result, k) <= q
    if clause.mode == once:
      result =
        close_or_explicitly_park_on_every_exit(result, k)
    else:
      result =
        synchronous_resume_or_finalize_on_every_exit(result, k)
  else if clause.mode == fun:
    k = hidden Resume[1, κ.D, opσ.result,
                      handler_shape.answer,
                      κ.Π, κ.χ, handler_shape.owner]
    value_flow = check_body_flow(
      clause_ctx + params + k:Open(1),
      clause.body, opσ.result)
    normal_flow = tail_resume_each_normal_exit(
      k, value_flow, κ.answer_world)
    abort_flow = abort_scope_exit_each_abort(
      value_flow, k, κ.D.cleanup)
    result = merge_path_contracts(normal_flow, abort_flow)
    require exactly_one_hidden_tail_resume_per_normal_exit(result, k)
  else if clause.mode == abort:
    body_flow = check_body_flow(
      clause_ctx + params, clause.body, handler_shape.answer)
    result = append_hidden_disposition_on_every_exit(
      body_flow, κ, κ.D.cleanup)
    require every normal result world == κ.answer_world

  require clause_contract(result) refines opσ.contract
  return schema universally quantified over skolems, p and κ

install_handler(prompt, handler, policy, handled_entry, sites, body_flow):
  normal_summaries = []
  answer_worlds = []
  semantic_paths = []
  outcomes = {}
  for path in body_flow.flow:
    match path:
      Returns(Θ, π, χ):
        ret = apply_return_contract(
          handler.return_contract, π, χ, Θ)
        normal_summaries += (ret.π, ret.χ)
        answer_worlds += ret.Θ
        semantic_paths += ret.summary
      Aborts:
        outcomes += Aborts
      Transfers(P):
        require preserves_park_contract(prompt, handler, policy, P)
        outcomes += Transfers(P)
  for κ in sites:
    require κ.installation_prompt == prompt
    require κ.route == prompt
    clause = instantiate matching clause schema with
      operation skolems, prompt, κ.entry_world, κ
    discharge imported handler environment is valid
      at κ.entry_world
    if κ.instantiated_operation.max_mode == ctl:
      discharge DuplicableEnv(κ.Π, κ.χ)
      discharge EnvValidAt(κ.Π, κ.χ, MultiShot)
      discharge ReplayableCleanup(κ.D.cleanup, κ.Π, κ.χ)
      discharge WorldForkSafe(κ.D.world)
    discharge every stageHandlerInstall(κ.obligations) using policy
    require stageCall(κ.obligations) was discharged at its call node
    for secondary in κ.secondary_sites:
      require secondary.route ==
        resolve_route_at_installation(
          secondary.route_selector, prompt, κ.prompt_stack)
      preserve secondary unless secondary.route == prompt
    for Async.await:
      derive task region from κ.actual_arguments
      check install-await-site(κ, policy)
    for path in clause.flow:
      match path:
        Returns(_, π, χ):
          normal_summaries += clause.result_summary(
            κ.actual_arguments, κ.Π, κ.χ,
            handler.env_provenance, handler.captures)
          answer_worlds += clause.answer_world
          semantic_paths += clause.summary
        Aborts:
          outcomes += Aborts
        Transfers(P):
          require clause owns the disposition recorded by P
          outcomes += Transfers(P)
  require all answer_worlds are equal
  if normal_summaries is not empty:
    (πo, χo) = join(normal_summaries)
    outcomes += Returns(the unique answer_world, πo, χo)
  δout = handle_summary(
    body_flow.summary, handled_entry, handler.contract,
    policy, sites, body_flow.flow, semantic_paths)
  return sealed evidence(outcomes, δout)

eliminate_entry_with_contract(
  prompt, handler, body, entry, sites, install):
  (Δhere, Δouter) =
    partition(body.attributed_demand,
              demand.route == prompt)
  require every primary site in Δhere is in sites
  Δhandler = instantiate_handler_residual(
    handler.contract_template, prompt)
  Δout = union(Δouter, Δhandler)
  εout = eraseDemand(Δout)
  sout = handle_suspension(body.suspension, entry, handler.contract)
  return body with
    type = handler.answer_type
    flow = install.outcomes
    row = εout
    attributed_demand = Δout
    suspension = sout
    summary = install.δout
    typed_core =
      fresh_prompt_node(
        prompt, handled_node(prompt, body.typed_core, handler))
```

`analyze_sites` 对 local typed ANF结构递归；遇到 function call时读取并 compose
callee interface中的 finite $Lambda$，而不是要求内联源码。Recursive SCC
必须给 finite annotated site schema；worklist按
`(callee, entry, answer-shape)` memoize，禁止无限展开。

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
- PEG postfix/repetition由 token progress guard终止。

在 kind、row predicate、trait/effect resolution均可判定的假设下，
$"Cire-TR"_0$ type checking可判定。

== Interface serialization

Public signature即使省略 surface annotation，也必须序列化：

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

= 代表性推导与拒绝

== 纯 Next

程序：

```cire
def next_double(
  frame : cap FrameClock,
  value : Int,
) -> Next[frame, Int] {
  delay[frame] {
    value * 2
  }
}
```

假设：

$
  I(i) = ("FrameClock",rho)
$

$
  "StableAcross"(i,pi_"value",1)
  quad
  "Shareable"("Int")
$

Body derivation：

#irule(
  [T-Mul],
  (
    [$K;I;Phi@"pushLock"(Theta,i) ⊢_v "value" ⇒ "Int" @["Stable"] ▷ emptyset$],
    [$K;I;Phi@"pushLock"(Theta,i) ⊢_v 2 ⇒ "Int" @["Stable"] ▷ emptyset$],
  ),
  [$K;I;Phi;Omega@"pushLock"(Theta,i) ⊢ "value"*2 ⇒ "Int" @["Stable"] ! emptyset ▷ "direct"("NoSuspend");delta_"pure";emptyset @"pushLock"(Theta,i)⊣Omega$],
)

应用 T-Delay 得：

$
  L_"double"=⟨["Stable"],emptyset,delta_"pure",Phi⟩
$

$
  K;I;Phi;Omega@Theta
  ⊢ "delay"_i("value"*2)
  ⇒ "Next"[i,"Int",L_"double"] @["Stable"] ! emptyset
  ▷ "direct"("NoSuspend");delta_"alloc";emptyset
  @Theta⊣Omega
$

== 过早 Advance

```cire
def too_early(
  frame : cap FrameClock,
  value : Next[frame, Int],
) -> Int {
  advance(value)
}
```

当前 $Theta$ 中没有 `"lock"_i`，因此不存在：

$
  "splitRight"(Theta,i)
$

T-Advance 无法应用。建议诊断：

```text
cannot advance value for `frame` in the current temporal zone
required: one `frame` lock between value origin and this use
```

== 一次 Yield 后 Advance

```cire
let pending = delay[frame] { 42 }
frame.yield()
advance(pending)
```

顺序推导：

```text
delay:
  Θ → Θ
  pending : Next[ι, Int] is bound in the current zone

yield:
  Θ → pushLock(Θ, ι)

advance:
  splitRight(pushLock(Θ, ι), ι) succeeds
  pending is checked in the prefix Θ
```

因此得到 `Int`。

== Distinct clocks

若：

$
  v : "Next"[i_"network",A]
$

当前只有：

$
  "lock"_(i_"animation")
$

则 T-Advance 的 matching split失败。Clock family相同不意味着 identity相同。

== Handler 内外

内部 handler：

```cire
delay[frame] {
  with Error::result()
  in {
    parse(text)
  }
}
```

推导次序：

```text
T-Operation(parse)   produces {Error}
T-Handle             removes {Error}, attaches replay/temporal certificate
T-Delay              observes empty residual row and TemporalPure certificate
```

外部 handler：

```cire
with Error::result()
in {
  delay[frame] {
    parse(text)
  }
}
```

T-Delay 是 T-Handle 的 premise；它先看到 `{Error}`，因此失败。外层 rule
不能“事后”洗掉 latent effect。

== Empty row 但 HostObservable

```cire
delay[frame] {
  with Console::host()
  in {
    Console::print_line("surprise")
  }
}
```

T-Handle 可令 $epsilon=emptyset$，但：

$
  not "TemporalPure"(delta_"Console.host")
$

T-Delay 仍失败。这是 $epsilon$ 与 $delta$ 分轴的必要反例。

== Delay 内局部 Async handler

```cire
delay[frame] {
  with BrowserAsync::run(owner)
  in {
    Async::await(task)
  }
}
```

T-Operation先产生：

$
  "request"("Anon"("Async"),"MaySuspend")
$

Browser handler的 `actualSusp=MaySuspend`，所以 elimination后
`grade(s)=MaySuspend`。T-Delay要求 `NoSuspend`，因此失败。

== 基本 Live

```cire
let total =
  live {
    read(price) * read(count)
  }
```

`live` elaborator创建 hidden $i_o$。两次 `read` 的 row union normalization
仍为：

$
  {"Named"(i_o,"Observe")}
$

若 body的 attributed suspension grade为 `NoSuspend`、result
`Shareable`、summary replay-safe，则 T-Live
成立。实际 dependency `{price,count}` 只进入 Trace。

== Live 中 Host write

```cire
live {
  let amount = read(total)
  charge_credit_card(amount)
}
```

Body residual row至少包含：

$
  {"Named"(i_o,"Observe"), "HostWrite"}
$

不满足 T-Live 要求的“只可含 Observe”row；若 Host handler在内部消除 row，
其 `HostObservable/Immediate` summary仍使 `ReplaySafe` 失败。

== Commit 跨 Await

```cire
Commit::run(ticket) { gate =>
  let result = Async::await(task)
  gate.try_publish(result)
}
```

Async.await signature要求 `Action` phase，T-Try-Publish要求 `Commit`
phase；不存在不显式
退出/revalidate 的 phase derivation。此外 await使 revision可能 stale。

== 判定矩阵

#table(
  columns: (2.7fr, 1fr, 2.5fr),
  [*程序形状*], [*判定*], [*决定 premise*],
  [`delay { pure immutable computation }`], [接受], [`ε=∅`、NoSuspend、TemporalPure、Shareable],
  [`advance` without matching lock], [拒绝], [`splitRight` undefined],
  [`delay { handled host IO }`], [拒绝], [handler summary is HostObservable],
  [`delay { handled Error -> Result }`], [接受], [sealed TemporalPure handler],
  [`delay { locally handled await }`], [拒绝], [MaySuspend survives row elimination],
  [`live { Observe.read }`], [接受], [row is subset of hidden Observe + ReplaySafe],
  [`live { read; await; read }`], [拒绝], [minimal Live requires NoSuspend],
  [`Choice before Observe cut`], [拒绝], [missing TraceCompatibleFork],
  [`Observe cut before pure local Choice`], [条件接受], [TraceNeutral concrete handler],
  [`Event listener captures one-shot authority`], [拒绝], [many-shot closure violates usage],
  [`CommitGate across await`], [拒绝], [phase/suspension + stale generation],
  [`owned snapshot across Wasm callback`], [条件接受], [boundary provenance + Owner root],
)

= 元理论陈述与证明义务 <metatheory>

这些是 theorem statement，不是本文已经完成的 proof。

== Parser

#status(
  [Theorem P1 — PEG determinism],
  [
    对固定 grammar、token stream、parser expression 与起点，normal
    recognition result唯一。按 parser expression结构归纳。
  ],
)

#status(
  [Theorem P2 — parser progress],
  [
    所有 repetition和 postfix loop成功迭代时严格推进 significant cursor；
    active-rule guard拒绝同 rule、position、flavor 的无进展重入。因此正常
    recognition终止。
  ],
)

== Static semantics

Declarative relation
$K;I;Phi;Omega@Theta ⊢_"d" e:A @[pi] ! epsilon ▷ s;delta;chi
@Theta'⊣Omega'$ 由本节算法规则擦除 `⇒/⇐` 方向、normalization顺序与
evidence数据后归纳生成；function call、handler installation和 suffix site
仍保留其 existential contract premise。它不是另一套宽松规则，因此
soundness statement有明确目标。

#status(
  [Theorem T1 — algorithmic soundness],
  [
    若 algorithm返回的 path set含 `Returns(Θ′,π,χ)`，则擦除
    normalization evidence后存在对应的普通 declarative typing
    derivation；每个 `Aborts` entry存在对应
    $K;I;Phi;Omega@Theta ⊢_"abort" e ! epsilon ▷ s;delta⊣Omega'$
    derivation；每个 `Transfers(P)` entry存在唯一 T-Park derivation、
    sealed completion source 与匹配的 $P$。Terminal entries没有
    type/provenance/normal world output；同一 set可同时包含三类 outcome，
    但三类不互相 coercion。
  ],
)

#status(
  [Theorem T2 — synthesis uniqueness],
  [
    在 resolver binding、kind evidence和 handler certificate固定时，
    algorithm的 normalized flow set唯一。每个 `Returns` entry的
    type、provenance、world transformer、result capture与所有 entry共享的
    normalized row、attributed demand、attributed suspension、finite
    latent-site summary modulo alpha-renaming唯一；`Aborts` entry没有
    result字段；每个 `Transfers` entry具有唯一 sealed
    `ParkContract`/claim identity。Terminal entries不声称不存在的
    result/world唯一。这里声称的是 deterministic
    algorithm，不是任意 declarative derivation的 principal-type theorem。
  ],
)

#status(
  [Theorem T3 — decidability],
  [
    若 kind、row predicate、subtyping、ability resolution和 certificate
    lookup可判定，则 algorithmic type checking终止并可判定。
  ],
)

== Temporal safety

#status(
  [Theorem N1 — no early advance],
  [
    若 closed expression对 `advance(v)` 有 typing derivation，则 temporal
    context存在 matching clock lock，且 $v$ 可在该 lock之前的 prefix中
    typing。故 well-typed程序不能在对应 logical tick之前打开 `Next`。
  ],
)

#status(
  [Theorem N2 — clock separation],
  [
    $i != j$ 时，`lock_j` 不满足 `Next[i,A,L]` 的 elimination premise。
    Clock family相同不能替代 singleton identity相同。
  ],
)

#status(
  [Theorem N3 — no latent-effect laundering],
  [
    T-Delay要求 body在其 own future scope中 residual-effect-free、
    NoSuspend且TemporalPure。外层 handler不能在 T-Delay之后消除其 premise；
    handler消除 row也不能删除 semantic summary。
  ],
)

== Effect/control safety

#status(
  [Theorem E1 — handler contract preservation],
  [
    若 clause schema refine operation contract且每个实际 site通过
    `InstallOK`，则 resume不会获得更强 quantity、伪造不同 world target、
    绕过 Tick/parking obligation或隐藏 declared suspension上界。
  ],
)

#status(
  [Theorem E2 — one-shot disposition],
  [
    对每个 `once` resumption，任何运行路径至多一个 resume、finalize或
    park成功 claim；park后 completion、close/cancel再竞争同一个
    generation-bound atomic claim。证明结合路径敏感 usage algebra与
    runtime CAS。
  ],
)

#status(
  [Theorem E3 — no capability escape],
  [
    Fresh named handler scope的每一种 outward flow都不在 row、suspension、
    semantic summary或 usage evidence中自由出现 fresh identity；正常返回
    还要求 result type、provenance、capture与 temporal context满足同一
    条件。合法 existential container只通过将 identity绑定在 type内部，并
    同时拥有 runner/Owner/dispose responsibility而成立，并非 escape gate
    的例外。
  ],
)

#status(
  [Theorem E4 — multi-shot capture safety],
  [
    在 `declared-max` profile下，可能 multi-shot 的 operation suffix只捕获
    Duplicable authority和Replayable cleanup；因此不会复制 one-shot
    resumption或nonduplicable cleanup responsibility。
  ],
)

== Async/Owner safety

#status(
  [Theorem A1 — suspension ownership],
  [
    对通过 `OwnerBoundParking` installation 的 may-suspend handler，每个
    parked once continuation由一个 live Owner拥有；completion、cancel与
    close竞争同一 disposition claim。Owner/generation无效后不能恢复。
  ],
)

#status(
  [Theorem A2 — no borrowed boundary escape],
  [
    若 value跨 temporal lock、suspension、checkpoint或FFI storage boundary，
    则其 provenance和captures满足对应 boundary predicate；callback-local
    borrow与未rooted Wasm memory view不能通过。
  ],
)

== Incremental safety

#status(
  [Theorem I1 — fixed-Epoch reads],
  [
    一次 candidate replay中所有 invalidating Source read来自 Begin时 pin住的
    同一 $Sigma(e)$；replay期间的新 write只能进入 pending/batch journal并
    形成下一 Epoch。
  ],
)

#status(
  [Theorem I2 — replacement generation safety],
  [
    对同一 cut至多一个 active candidate slot；Begin不覆盖 committed
    generation。只有 current、owner-valid candidate能原子替换
    value/trace/wakes。被祖先替换或 generation失效的后代不能恢复或 publish。
  ],
)

#status(
  [Theorem I3 — commit at-most-once],
  [
    对固定 publication slot/revision $(ell,r)$，Commit claim状态只能从
    OpenClaim原子转为CommittedClaim一次，且抽象 accepted-publication log
    至多追加一次；其他调用返回Stale/AlreadyCommitted并且不修改 $J/L$。
    这是动态 claim theorem，不是静态 affine或外部网络 exactly-once theorem。
  ],
)

== From-scratch consistency

令 $sigma_p$ 是显式允许的 persistent state。定义从头执行：

$
  "evalFS"(e,Sigma(e_n),sigma_p) = (v_"fs",T_"fs",sigma_"fs"')
$

Representation relation：

$
  "Rep"_A(M,c_0,e,Sigma(e_o),v_o,T_o)
$

其中 $c_0$ 是该 Live computation的 designated root cut；relation表示 $M$
的 committed value/trace确实来自此前对 $e$ 的合法执行。
Successful quiescence要求：

```text
B = []
P = ∅
N = ∅
Q has no dirty or error marker
C has no active candidate
all required frontier candidates published successfully
```

从 committed $T(c_0)="Committed"(g,v,T_c,W_c)$ 读取增量结果：

$
  "evalInc"(M,c_0,e,Sigma(e_n),sigma_p)
  = (M',v_"inc",T_"inc",sigma_"inc"')
$

#status(
  [Theorem FSC — conditional from-scratch consistency],
  [
    若：

    - `e` 通过 T-Live；
    - $"WF"(M)$ 且
      $"Rep"_A(M,c_0,e,Sigma(e_o),v_o,T_o)$；
    - 本轮 Freeze产生目标 snapshot $Sigma(e_n)$；
    - runner具有 `ImplementsLive` witness；
    - handler certificates的 replay laws真实；
    - typed candidate evaluation与 source semantics互相 simulation；
    - dependency recorder对本轮控制流 sound且complete；
    - speculative trace、wake、cleanup与effect全部 candidate-buffered；
    - primitive computation deterministic于 fixed snapshot；
    - persistent state两边使用同一初态；若 handler有持久化优化，其
      certificate给出同时保持 result与control/dependency observation的
      bisimulation
      $"PersistentTraceEq"(sigma_"fs"',sigma_"inc"')$；
    - 每个 dirty frontier均成功 publish，scheduler到达 successful quiescence；

    则 $v_"inc" ≈_A v_"fs"$，且 $T_"inc"$ 与 $T_"fs"$ 的有效 dependency
    在 cut identity/generation alpha-renaming下等价。
  ],
)

Abort/error留下 dirty/error marker，因此“旧值但 Q 已清空”的状态不满足 theorem
前提。FSC 不推出 scheduler fairness、Task最终完成、retire queue liveness或
浏览器最终产生 frame。

== Proof 分层

建议 mechanization不要试图一次证明“大一统 soundness”，而按依赖分层：

```text
Surface grammar + elaboration preservation
        ↓
CBV Core operational semantics + evaluation-context determinism
        ↓
kinding + row normalization
        ↓
algorithmic typing soundness
        ↓
temporal preservation
        ↓
effect/summary/capture preservation
        ↓
one-shot + Owner runtime safety
        ↓
incremental machine invariants
        ↓
conditional FSC + Commit safety
```

Surface 层先证明 n-ary `def`/labelled call、block final expression、隐式
`return` 与 `fun` hidden tail-resume 的 elaboration preservation；随后在
CBV Core中给出 `defer`、handler delimiter、resume/finalize/park、Owner
close与 generation CAS 的小步语义。没有这两层，后续 preservation
只能算规则草图。

= 尚未冻结的 formal parameters

== `defer` reduction calculus

Surface grammar已经保留 `defer`，但 TR₀ 尚未给出足以证明 preservation 的
reduction calculus。下一版必须固定：

- defer stack的 push/pop 与 lexical block顺序；
- normal return、abort、resume、finalize、park、Owner close各自触发哪些
  segment；
- continuation capture时 cleanup segment是移动、复制还是被拒绝；
- cleanup自身 abort/suspend时 flow、row、world与 disposition如何组合。

在这些规则完成前，`defer` 是 syntax baseline + semantic proof obligation，
不能由未来 runtime的偶然 unwind行为定义。

== Clock representation

本文用 singleton capability identity。替代方案 fresh phantom type也可表达
generativity，但会改变：

- kinding与substitution；
- public API clock quantification；
- existential packaging；
- capability identity与clock identity是否共用一套基础设施。

需要原型比较。

== Fitch availability 的表达能力

本模型把函数参数绑定在调用时的当前 zone，因此保守拒绝某些“调用者已经知道
该 Next成熟、但 helper签名未携带 world evidence”的程序。未来可研究：

```text
world-polymorphic function contract
availability witness parameter
clock quantification
```

不能靠普通 effect row猜测成熟关系。

== Effectful Later

若以后加入：

$
  "Later"[i]{A ! epsilon} ▷ chi
$

必须同时定义：

- 执行次数；
- future handler instance；
- Owner；
- cleanup；
- suspension；
- result quantity；
- 丢弃语义。

它不应通过放宽 T-Delay 的 empty-row premise偶然出现。

== Handler specialization

基线按 operation最大 mode检查 capture。若希望词法已知：

```cire
with Choice::first()
in { ... }
```

享受 `fun/once` 的较弱 capture限制，需要证明：

- handler不能被 abstraction替换；
- operation dispatch确实绑定该 instance；
- specialization evidence跨module保存；
- optimizer不改变 handler ordering。

== Local mutable State under multi-shot/replay

仍需选择：

```text
shared cell
copy-on-capture
candidate-local snapshot
forbid when nonduplicable
```

Family级 `Replayable(State)` 不能解决此问题。

== Checkpoint profile

两种合法实现路线：

```text
trusted-ctl:
  ordinary ctl Resume
  first-party runner trusted to maintain replacement invariants

sealed-checkpoint:
  Kernel gives Cut/Candidate leases instead of arbitrary Resume
  more protocol safety, larger Core
```

普通用户永远只看到四种 resumption mode。需要原型衡量 sealed protocol
是否值得进入 Core。

== General affine values

本文只对 resumption disposition做 quantity analysis。若未来引入一般 affine：

```text
once cap Commit
unique Socket
affine Event payload
```

需要把 quantity传播到：

- closure call grade；
- ADT field；
- generic container；
- existential；
- trait object；
- interface artifact。

在此之前 Commit只声称 dynamic claim safety。

== Portable handlers与 finalizer

TR₀ 已冻结一点：continuation cleanup不是隐式 pure；其
$F_k=⟨epsilon^"fin",Delta^"fin",zeta^"fin",s^"fin",delta^"fin"⟩$ 必须进入
T-Finalize与 clause aggregation。仍未冻结的是：

- portable/reentrant context的类型；
- handler stack重装顺序；
- 各 runtime profile允许哪些 cleanup effect、是否提供 async cleanup executor；
- finalizer trap后的聚合保证；
- Wasm ABI中的context representation。

= 与未来编译器的映射

== 仓库状态

当前仓库只有：

```text
versioned design profile
canonical surface grammar
formal Core judgments
spec-level conformance corpus
```

当前没有：

```text
lexer / parser / lossless CST
typed CST
Surface HIR
Kernel HIR
resolver/type/effect/capture checker
runtime / Wasm backend / LSP
```

所以本文只提供未来 lowering/checking contract。历史实现不能作为 grammar
或静态语义的权威。

== 建议 HIR 字段

```text
TypedExpr {
  type
  flow
  provenance
  normalized_effect_row
  attributed_demand
  world_in
  world_out
  suspension
  semantic_summary
  captures
  usage_in
  usage_out
  latent_site_evidence
  phase
  owner_region
  evidence
}

OperationSignature {
  mode
  type_parameters
  parameters
  result
  resume_transition
  secondary_sites
  secondary_suspension
  secondary_summary
  suspension_bound
  result_summary_transformer
  required_phase
  site_obligations
}

FunctionContractV1 {
  profile
  schema_version
  effect_row
  world_transformer
  returnability
  flow_summary
  suspension
  semantic_summary
  closure_provenance
  closure_captures
  latent_usage
  result_summary_transformer
  required_phase
  ParametricObligations
  LatentSites
}

HandlerEvidence {
  effect
  exact_entry
  prompt_template_slot
  installation_prompt
  actual_mode
  policy
  trust_origin
  handler_environment_provenance
  handler_environment_captures
  return_contract
  clause_schemas
}

TemporalValueEvidence {
  clock_identity
  origin_zone
  stability
  cross_world_captures
  shareability
  later_contract
  clock_package_summary
}
```

== Parser conformance cases

Target PEG至少需要测试：

```text
delay[frame] { 1 }
delay [frame] /*comment*/ { 1 }
delay(x)                         ordinary function call
advance(value)                   ordinary parse, intrinsic resolve
Next[frame, Int]                 type application + kind reclassification

once yield() -> Unit resumes next
once await(task : Task[A]) -> A may_suspend
duplicate resumes annotation     parse succeeds, validation rejects
abort raise(...) -> A resumes next
                                  parse succeeds, validation rejects

with h1 as c1
with h2
in { body }

old single-item with syntax
                                  rejects with profile migration diagnostic
```

PEG不负责判断：

- `frame` 是否真是 FrameClock identity；
- `advance` 是否解析到 sealed intrinsic；
- operation annotation是否合法；
- named capability是否逃逸；
- handler是否 temporal-pure。

这些属于 lowering/resolver/type checking。

== Type checker conformance cases

本文的 accept/reject程序应转成 golden suite，每个 case保存：

```text
surface source
resolved identity graph
normalized Core
expected type
expected flow
expected provenance
expected residual row
expected world transition
expected suspension
expected semantic summary
expected captures
expected usage transition
expected latent site schemas
expected diagnostic rule id
```

Rule id例如 `T-Delay`、`T-Advance`、`T-Live` 应进入高级 diagnostic trace，
但普通错误信息仍使用用户术语。

= 结论

$"Cire-TR"_0$ 的最小安全核心不是“reactive variable type”，而是以下五项
可以分别检查、分别证明的结构：

```text
generative clock identity + Fitch locks
pure/shareable Next
world-aware effect resumption
capture/quantity/Owner boundary safety
fixed-Epoch candidate replacement + dynamic Commit claim
```

`Source`、`Live`、`Event`、`Signal`、`Task` 与 `Resource` 在这个核心上保持
不同类型和不同协议。语言只冻结真正跨 library abstraction无法恢复的静态
边界；scheduler、trace indexing、resource policy和renderer仍属于第一方
runtime。

下一步如果进行 mechanization，应先抽取：

`Core syntax`、`Kinding`、`T-Delay / T-Advance`、
`T-Operation / T-Handle`、`usage + capture boundary`、
small Owner machine 与 small replacement machine。

先证明 no-early-advance、handler summary preservation、identity nonescape、
one-shot disposition和fixed-Epoch replacement，再讨论 surface语法冻结。
