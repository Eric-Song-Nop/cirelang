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
  #text(fill: luma(90))[Canonical design profile · $"Cire-TR"_0$ · 2026-08-01]
]

#v(18pt)

#status(
  [文档状态],
  [
    本文是 `Cire-TR₀/2026-08-01` 的 canonical semantic baseline。它固定术语、
    judgment、规则边界、PEG 识别形状和待证明性质；仍开放的选择被显式参数化。
    其中的 theorem 是陈述或证明义务，不代表已经完成机械化证明。

    仓库当前不包含编译器或 runtime。完整 concrete syntax 由
    `surface-syntax.md` 的完整 grammar appendix定义；未来 parser 与 conformance tests必须服从规范，
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
pattern、ordinary trait与 method-resolution细节在本文中是明确的
out-of-semantic-scope surface nodes；本 profile不能引用已删除文档或所谓“现有语言
设计”给它们补规则，也不对未写出的 behavior作 acceptance claim。需要这些规则的
compiler-complete profile必须另行冻结并改变 profile id。本文实际使用的 nominal
type/member facts必须作为 $K$ 中已解析的 opaque declaration-identity evidence输入，
且不能产生本节未定义的 effect、ability或 temporal judgment。

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
`Cire-TR₀/2026-08-01` 导入 `surface-syntax.md` 的 token/rule table，并只对
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
  `Cire-TR₀/2026-08-01` 只接受 canonical `with ... in ...` chain，不接受历史
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
`freshcap`/handler application可以引入。TR₀ 的 `ClockId(FrameClock,ρ)` 是
`CapId(FrameClock,ρ)` 连同 canonical sealed `FrameClock` family witness 的
refinement；普通 effect、同名用户类型或裸 `clock_refinement` 都不够。
普通 term 不能出现在 type 中。

== Associated-item 与 ability conformance 静态契约

这一节冻结普通 temporal judgment 使用之前所需的 non-temporal static
contract；它不是把已删除设计文档作为隐含前提。令
`AbilitySignature(B)` 保存 declaration identity、visibility、associated-item
map 与 operation map。每个 associated item恰有一个 declared kind：

$
  "AssocDecl"(B,x) = (kappa_x,c_x,a_x,d_x?)
  quad
  kappa_x in {"Type","Effect","EffectRow"}
$

`type`、`effect`、`effects` 分别且唯一引入上述三个 kind；$c_x$ 是 declaration
constraint，$a_x$ 是 parameter arity。Default $d_x$ 若存在，必须在 declaration
scope满足 $K ⊢ d_x:kappa_x$。TR₀ 要求 $a_x=0$；nonzero arity稳定拒绝
`associated-parameterization-not-in-profile`。本 profile只为
$kappa_x="EffectRow"$ 编码 finite `Lacks[e]` constraint到 `RowBinderV1.lacks`；
associated Type constraint或 associated Effect ability constraint稳定拒绝
`associated-declaration-constraint-not-in-profile`，不能丢弃证据后继续。

Named associated argument先形成一个 declaration-indexed partial map $P$。
Unknown、duplicate或 $K ⊬ P(x):kappa_x$ 在 Kind阶段稳定返回
`associated-contract-mismatch`。Completion明确分成两个 judgment：

$
  "GenericAbility"(K,F,B,P)
  => "AbilityEvidence"(K,F,B,theta_g) + "Eq"(P)
$

Exporter按 `(effect-binder slot, ability declaration identity, associated ordinal)`
为每个 `AssocDecl(B,x)` 分配 deterministic hidden binder $H(F,B,x)$，令
$theta_g(x)=H(F,B,x)$，所以 $theta_g$ 是 total symbolic vector。若 $x=W$ 显式
出现，`Eq(P)` 加入 $H(F,B,x)=W$；omitted item保持 symbolic，即使声明有 default
也不得把 default加入 generic equality。

$
  "HeaderImpl"(K,D,B,P)
  => "AbilityEvidence"(K,D,B,theta_h)
$

Concrete header逐 item选择唯一 explicit same-kind value，否则选择 declaration
default，否则 `associated-contract-mismatch`；row value还必须证明 $c_x$ 中每个
`Lacks`。因此 $theta_h$ 在 operation substitution与header export前 total且
concrete。Generic application用 $theta_h$ 的完整 vector实例化 $theta_g$，再在
ordinary type/row substitution后逐条证明 `Eq(P)`；例如 `Value=A` 对
`Value=Bytes` 要求 $A="Bytes"$。同 binder的两个 ability evidence若导出同 short
name而 surface没有 ability qualifier，projection不唯一并同样拒绝。

`AbilityEvidence(K,F,B,theta)` 始终表示 $theta$ 对 $B$ 的全部 associated item
exact/total；generic evidence的值可以是上述 hidden symbolic binder，header
evidence则必须 concrete。Projection formation是 kind-preserving的：

#irule(
  [K-Assoc-Projection],
  (
    [$"AbilityEvidence"(K,F,B,theta)$],
    [$"AssocDecl"(B,x)=(kappa_x,c_x,a_x,d_x?)$],
    [$theta(x)=W$],
    [$K ⊢ W:kappa_x$],
  ),
  [$K ⊢ F::x:kappa_x$],
)

所以 `S::Key`、`S::Fail` 与 `S::Extra` 分别只能进入 Type、atomic Effect
entry 与 EffectRow位置；相同 short name或相同 wire object不能跨 kind充当
evidence。Constraint `S : B[Value = A]` 只把相应 hidden-binder equality加入
$K$，不要求 generic site提供 omitted `Key/Fail/Extra`，也不把它降为 positional
type argument。

Interface normalization不增加 `AssociatedProjection` variant。对每个带
`AbilityEvidence` 的 Effect-kind declaration binder，先按
`(effect-binder slot, ability declaration identity, associated ordinal)` 全批次排序；
Type/Effect associated item各分配现有 `TypeBinderV1` slot并保留 declared kind，
EffectRow item分配现有 `RowBinderV1` slot。随后：

```text
F::TypeItem   -> TypeParameterV2(hidden Type slot)
F::EffectItem -> TypeParameterV2(hidden Effect slot), used as Anon family
F::RowItem    -> TailV1(hidden Row slot)
```

Named equality与 application witness成为同一 `ContractSubstitutionV2` 的 type/row
argument；generic omitted item仍有 hidden slot，concrete effect header的 explicit/
default vector在 export前直接 substitution。Associated EffectRow hidden binder把
声明处 `Lacks` evidence复制到自己的 `RowBinderV1.lacks`，concrete row必须先证明
同一 predicate。现有 bounded fresh-u32 allocator
对整批 hidden slots做 collision/exhaustion检查，importer继续按 declaration kind与
substitution arity exact-check。因此这个 static contract不改变 wire schema version，
也不允许 exporter把 source projection作为 nominal sentinel泄漏。

TR₀ 只接受 local effect declaration header产生的上述 concrete witness；也就是
`HeaderImpl(K,D,B,P)` 另有 premise `LocalDefinition(D)`。

同一 header不得重复 $B$。$B$ 的每个 operation经 $theta_h$ substitution后，必须
与 $D$ 中同名 operation在 parameter/result、secondary contract与 resumption
mode上 exact相等；从多个 ability继承的同名 operation也只能在这四项 exact
相等时合并。Witness visibility取 $D$ 与 $B$ visibility的 meet，不能扩大
sealing。这给 effect-header sugar一个 local、non-overlapping、无 adapter 的
coherent meaning。Duplicate ability、signature/mode conflict或 visibility
widening稳定返回 `effect-header-conformance-mismatch`。

Independent ability-target `impl` 在本 profile没有 orphan、overlap、
specialization、adapter或跨 package visibility规则；因此它不是一个带任意实现
选择的 judgment。Resolver识别 ability target后必须在 body checking前返回
`independent-ability-impl-not-in-profile`。普通 trait `impl` 是
out-of-semantic-scope CST fragment，不产生 `AbilityEvidence`，也不从
已删除authority导入静态规则。未来 profile若启用独立 ability `impl`，必须一次性
定义上述五项以及 associated uniqueness和 mode compatibility。

== Row normal form 与冻结 predicate

Row entry identity是 `Anon(F)` 或 `Named(i,F)`；二者即使 family相同也不相等。
令 $"RowNF"(epsilon)$ flatten $|$、删除已知重复 entry、按 stable identity排序，
并保留每个 rigid row-variable summand。TR₀ 没有 intersection、difference或
raw family subtraction。

#irule(
  [K-Row-Union],
  (
    [$K ⊢ epsilon_1:"EffectRow"$],
    [$K ⊢ epsilon_2:"EffectRow"$],
  ),
  [$K ⊢ "RowNF"(epsilon_1 | epsilon_2):"EffectRow"$],
)

#irule(
  [K-Lacks-Closed],
  (
    [$K ⊢ epsilon:"EffectRow"$],
    [$K ⊢ e:"RowEntry"$],
    [$e in.not "RowNF"(epsilon)$],
    [$"closed"(epsilon)$],
  ),
  [$K ⊢ "Lacks"(epsilon,e):"Evidence"$],
)

#irule(
  [K-Lacks-Rigid],
  ([$"Lacks"(E,e) in K$],),
  [$K ⊢ "Lacks"(E,e):"Evidence"$],
)

#irule(
  [K-Row-Extend],
  (
    [$K ⊢ epsilon:"EffectRow"$],
    [$K ⊢ e:"RowEntry"$],
    [$K ⊢ "Lacks"(epsilon,e):"Evidence"$],
  ),
  [$K ⊢ "RowNF"(lr("{", e, dots epsilon, "}")):"EffectRow"$],
)

`Lacks` 是唯一冻结的显式 row predicate；extension对 rigid tail产生/消费同一
obligation，union不凭空制造 evidence。通用 surface `RowPredicate` CST中的
`Has`、`All`、`Only` 或其它名称没有 TR₀ solver/schema judgment，必须稳定返回
`row-predicate-not-in-profile`。因此它们是显式保留的新-profile空间，不是
compiler-known builtin或已实现语言功能。

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
    | exists i:"ClockId"("FrameClock",rho),
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
    | "PackedNext"[rho,A]
    | "CommitTicket"[rho] | "CommitGate"[rho]
    | "Resume"[q,D,A,B,Pi,chi,rho]
    | "HandlerTemplate"[F,rho,A,B,epsilon,(S,p,a).C,P]$
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
$"flow"(C):"FlowSetV2"$：`r_f=MayReturn` 当且仅当该 set含 `Returns`，
`NoReturn` 当且仅当不含；`Aborts/Transfers` entries无论是否同时存在 normal
return都保留。$hat(zeta)$ 与 $hat(R)_"out"$ 只描述 Returns projection，
不能替代整个 flow set。

跨模块 artifact 不以裸字母作为 wire format。新 profile使用原子 contract
application/computation schema；V1 concrete field envelope只作为显式 legacy
输入，不能原地接受 V2 tag。稳定 schema 为：

```text
FunctionContractV1 {
  artifact: "FunctionContractV1"
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
  binders: DeclarationBindersV1
}

FunctionContractV2 {
  artifact: "FunctionContractV2"
  profile: "Cire-TR₀/2026-08-01"
  schema_version: 2
  declaration_kind: FunctionContractKindV2 | null
  binders: DeclarationBindersV2
  applications: [AppliedContractV2]
  computation: ContractComputationV2
  closure_environment: [EnvironmentBindingV2]
}

AppliedContractV2 {
  application_slot: u32
  contract: ContractRefV2
  callee_summary: ValueSummaryExprV2
  actual_arguments: [ValueSummaryExprV2]
  substitution: ContractSubstitutionV2
  entry_world: WorldExprV2
  origin: SourceOriginV2
}

AppliedProjectionEvidenceV2 {
  application_slot: u32
  source_artifact_hash: StringV1
  discharged_call_keys: [QualifiedLocalKeyV2]
  retained_obligations: [RetainedObligationV2]
  retained_latent_sites: [RetainedLatentSiteV2]
}
QualifiedLocalKeyV2 { application_slot: u32, local_id: u32 }
RetainedObligationV2 {
  key: QualifiedLocalKeyV2
  source_local_id: u32
  stage: HandlerInstall
}
RetainedLatentSiteV2 {
  key: QualifiedLocalKeyV2
  source_site_slot: u32
  install_obligation_keys: [QualifiedLocalKeyV2]
}

ContractRefV2 =
    ContractParameterRefV2 { parameter: ContractParameterV2 }
  | ImportedFunctionRefV2 {
      module: ModulePathV1,
      name: IdentifierV1,
      artifact_hash: StringV1
    }
  | LocalFunctionRefV2 { declaration_slot: u32 }

ContractSubstitutionV2 {
  type_arguments: [TypeSubstitutionV2]
  row_arguments: [RowSubstitutionV2]
  contract_arguments: [ContractSubstitutionEntryV2]
  owner_arguments: [OwnerSubstitutionV2]
  identity_arguments: [IdentitySubstitutionV2]
  clock_arguments: [ClockSubstitutionV2]
}

TypeSubstitutionV2 { binder_slot: u32, value: TypeRefV2 }
RowSubstitutionV2 { binder_slot: u32, value: RowExprV1 }
ContractSubstitutionEntryV2 { binder_slot: u32, contract: ContractRefV2 }
OwnerSubstitutionV2 { binder_slot: u32, value: SlotRefV1 }
IdentitySubstitutionV2 { binder_slot: u32, value: SlotRefV1 }
ClockSubstitutionV2 { binder_slot: u32, value: SlotRefV1 }

`type_arguments` 覆盖 `TypeBinderV1` 的 Type与Effect两个 value-carrying domain，
但 importer必须先由 target binder map取 declared kind，再按 position解码 `value`：
Type binder只接受 TypeRefV2，Effect binder只接受 `EffectFamilyRefV2` 的 V2
encoding；若 nominal Effect在 `TypeSubstitutionV2.value`中以
`LegacyTypeRefV2(NominalTypeV1)` 承载，只在 Effect-family position取其内层
`NominalTypeV1`，Type position则保留 wrapper。两个 domain不得按相同
object shape互换。替换后 importer必须对完整 instantiated
`FunctionContractKindV2`（包括 `visible_row`）重跑 exact/kind/row WF，不能只比较
parameter/result。每个 `IdentitySubstitutionV2.binder_slot` 先在 target identity
binder table解析，其 family在同一 type substitution下实例化；`value` 必须引用 caller
live Identity declaration且 family结构相等，否则稳定
`contract-component-kind-mismatch`。完整 instantiated `visible_row`随后还必须用 caller
identity/handler-contract table重跑 selector scope/family WF。OwnerRegion binder不由
`type_arguments` 实例化。Substitution domain exactness之后仍须检查 caller lexical
scope；unbound projection稳定拒绝，wrong-kind value稳定
`contract-component-kind-mismatch`。

ValueSummaryExprV2 {
  source: SlotRefV2 | null
  type: TypeRefV2
  nominal_index: NominalIndexExprV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2 | null
  origin: SourceOriginV2
}

SlotRefV2 =
    LegacySlotRefV2 { value: SlotRefV1 }
  | ReturnSlotRefV2 { return_slot: u32 }

WorldExprV2 =
    LegacyWorldExprV2 { value: WorldExprV1 }
  | ReturnWorldV2 { return_slot: u32 }
  | ApplicationEntryWorldV2 { application_slot: u32 }
  | ApplyWorldTransitionV2 {
      input: WorldExprV2,
      transition: TransitionV1
    }
  | JoinWorldsV2 { members: [WorldExprV2] }

ContractComputationV2 =
    LiteralPathsV2 { paths: nonempty [PathContractV2] }
  | CurrentDispositionPathsV2 { paths: nonempty [PathContractV2] }
  | InvokeV2 { application_slot: u32 }
  | PathBindV2 {
      prefix: ContractComputationV2,
      return_binder: ReturnBinderV2,
      continuation: ContractComputationV2,
      terminal_policy: PreserveTerminalV2
    }
  | JoinV2 { members: nonempty [ContractComputationV2] }

ReturnBinderV2 {
  slot: u32
  type: TypeRefV2
  world: WorldExprV2
  nominal_index: NominalIndexExprV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2 | null
}

PathContractV2 {
  outcome: PathOutcomeV2
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  usage: [UsageExprV2]
  required_phase: PhaseRequirementV1
  ParametricObligations: [ObligationV2]
  LatentSites: [LatentSiteV2]
}

PathOutcomeV2 =
    ReturnsV2 {
      transition: TransitionV1,
      result_transformer: ResultTransformerV2
    }
  | AbortsV2 { origin: SourceOriginV1 }
  | TransfersV2 { park_contract: ParkContractV2 }
  | DelegatesV2 {
      forward_contract: ForwardContractV2,
      disposition_evidence: ForwardDispositionEvidenceV2
    } // HandlerContractV2 clause computations only

DeclarationBindersV1 {
  parameter_binders: [ParameterBinderV1]
  type_binders: [TypeBinderV1]
  row_binders: [RowBinderV1]
  contract_binders: [ContractBinderV1]
  owner_binders: [OwnerBinderV1]
  clock_binders: [ClockBinderV1]
  identity_binders: [IdentitySlotDeclV1]
  prompt_binders: [PromptSlotDeclV1]
}

DeclarationBindersV2 {
  parameter_binders: [ParameterBinderV2]
  type_binders: [TypeBinderV1]
  row_binders: [RowBinderV1]
  contract_binders: [ContractBinderV2]
  owner_binders: [OwnerBinderV1]
  clock_binders: [ClockBinderV1]
  identity_binders: [IdentitySlotDeclV1]
  prompt_binders: [PromptSlotDeclV1]
}

ParameterBinderV1 { slot: u32, type: TypeRefV1 }
ParameterBinderV2 { slot: u32, type: TypeRefV2 }
TypeBinderV1     { slot: u32, kind: Type | Effect | OwnerRegion }
RowBinderV1      { slot: u32, lacks: [EffectEntrySelectorV1] }
ContractBinderV1 =
    FunctionContractBinderV1 {
      slot: u32, parameter_type: TypeRefV1, result_type: TypeRefV1
    }
  | LaterContractBinderV1 {
      slot: u32,
      clock: SlotRefV1,                  // Clock namespace
      payload_type: TypeRefV1
    }
  | ContinuationContractBinderV1 {
      slot: u32, argument_type: TypeRefV1, answer_type: TypeRefV1
    }
  | HandlerContractBinderV1 {
      slot: u32, family: TypeRefV1,
      input_type: TypeRefV1, answer_type: TypeRefV1
    }

ContractBinderV2 =
    FunctionContractBinderV2 {
      slot: u32,
      parameter_type: TypeRefV2,
      result_type: TypeRefV2,
      visible_row: RowExprV1
    }
  | LaterContractBinderV2 {
      slot: u32,
      clock: SlotRefV1,
      payload_type: TypeRefV2
    }
  | ContinuationContractBinderV2 {
      slot: u32,
      argument_type: TypeRefV2,
      answer_type: TypeRefV2
    }
  | HandlerContractBinderV2 {
      slot: u32,
      family: TypeRefV2,
      input_type: TypeRefV2,
      answer_type: TypeRefV2
    }
OwnerBinderV1    { slot: u32, source: SlotRefV1 }
ClockBinderV1 {
  slot: u32
  identity: SlotRefV1                  // paired Identity namespace
  owner: SlotRefV1                     // Owner namespace
}

RowExprV1 =
    EmptyV1
  | ClosedV1 { entries: [EffectEntrySelectorV1] }
  | TailV1 { row_slot: SlotRefV1 }       // Row namespace
  | UnionV1 { members: [RowExprV1] }

TransitionV1 =
    BottomTransitionV1
  | SameWorldV1
  | NextWorldV1 { clock: SlotRefV1 }     // Clock namespace
  | SequenceTransitionV1 { steps: [TransitionV1] }
  | PathJoinTransitionV1 { paths: [TransitionV1] }

WorldExprV1 =
    EntryWorldV1 { site_slot: u32 }
  | WorldParameterV1 { contract_slot: u32 }
  | ApplyWorldTransitionV1 {
      input: WorldExprV1,
      transition: TransitionV1
    }
  | JoinWorldsV1 { members: [WorldExprV1] }

ResultTransformerV1 =
    BottomResultV1
  | ParametricResultV1 {
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1
    }
  | PathJoinResultV1 { paths: [ParametricResultV1] }

ResultTransformerV2 =
    LegacyResultTransformerV2 { value: ResultTransformerV1 }
  | ParametricResultV2 {
      provenance: ProvenanceExprV2,
      capture: CaptureExprV2
    }
  | ReturnBoundResultV2 { return_slot: u32 }
  | PathJoinResultV2 { paths: [ResultTransformerV2] }

SummaryV1 =
    PureV1
  | CertificateV1 {
      temporal: Pure | HostObservable,
      replay_origin: Fresh | Snapshot | SharedPersistent,
      fork: Forbid | Copy | Share | Merge,
      publish: None | CandidateBuffered | CommitOnly | Immediate,
      suspend: StackOnly | OwnerBound | Portable,
      trust: Derived | Sealed { module: ModulePathV1 } | TrustedUnsafe,
      origin: SourceOriginV1
    }
  | SequenceSummaryV1 { members: [SummaryV1] }
  | JoinSummaryV1 { members: [SummaryV1] }

ProvenanceExprV1 =
    BottomProvenanceV1
  | StableV1
  | ArgumentV1 { argument: SlotRefV1 }
  | RegionV1 { owner: SlotRefV1 }
  | CallbackV1 { site_slot: u32 }
  | OwnerV1 { owner: SlotRefV1 }
  | GenerationBoundV1 { owner: SlotRefV1 }
  | EnvironmentV1 { bindings: [EnvironmentBindingV1] }
  | ArrayElementProvenanceV1 { argument: SlotRefV1 }
  | OperationResultProvenanceV1 { site_slot: u32 }
  | JoinProvenanceV1 { members: [ProvenanceExprV1] }

CaptureExprV1 =
    BottomCaptureV1
  | NoCaptureV1
  | CaptureSlotsV1 { slots: [SlotRefV1] }
  | ArgumentCaptureV1 { argument: SlotRefV1 }
  | ArrayElementCaptureV1 { argument: SlotRefV1 }
  | OperationResultCaptureV1 { site_slot: u32 }
  | UnionCaptureV1 { members: [CaptureExprV1] }

ProvenanceExprV2 =
    LegacyProvenanceExprV2 { value: ProvenanceExprV1 }
  | ReturnProvenanceV2 { return_slot: u32 }
  | EnvironmentV2 { bindings: [EnvironmentBindingV2] }
  | JoinProvenanceV2 { members: [ProvenanceExprV2] }

CaptureExprV2 =
    LegacyCaptureExprV2 { value: CaptureExprV1 }
  | ReturnCaptureV2 { return_slot: u32 }
  | UnionCaptureV2 { members: [CaptureExprV2] }

EnvironmentBindingV1 {
  slot: SlotRefV1
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
}

EnvironmentBindingV2 {
  slot: SlotRefV1
  type: TypeRefV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
}

UsageV1 {
  slot: SlotRefV1
  kind: Zero | Once | Many
}

UsageExprV2 =
    LegacyUsageExprV2 { value: UsageV1 }
  | ReturnUsageV2 { return_slot: u32 }

PhaseRequirementV1 {
  allowed_phases: [Pure | Compute | Action | Commit]
  required_authorities: [
    OwnerAuthorityV1
    | IdentityAuthorityV1
    | AnonymousEffectAuthorityV1
  ]
  current_owner: SlotRefV1 | null        // Owner namespace
}

OwnerAuthorityV1    { owner: SlotRefV1 }     // Owner namespace
IdentityAuthorityV1 { identity: SlotRefV1 }  // Identity namespace
AnonymousEffectAuthorityV1 { family: TypeRefV1 }

TypeRefV1 =
    BuiltinTypeV1 { name: Unit | Never | Bool | Int | String }
  | TypeParameterV1 { slot: u32 }
  | NominalTypeV1 {
      module: ModulePathV1,
      name: IdentifierV1,
      arguments: [TypeRefV1]
    }
  | ApplyTypeV1 {
      constructor: TypeConstructorRefV1,
      arguments: [TypeRefV1]
    }
  | FunctionTypeV1 {
      parameter: TypeRefV1,
      result: TypeRefV1,
      contract: FunctionContractV1 | ContractParameterV1
    }
  | CapabilityTypeV1 {
      identity: SlotRefV1,               // Identity namespace
      family: TypeRefV1
    }
  | NextTypeV1 {
      clock: SlotRefV1,                  // Clock namespace
      payload: TypeRefV1,
      later_contract: LaterContractV1 | ContractParameterV1
    }
  | OwnerTypeV1 { owner: SlotRefV1 }
  | OwnerIndexedTypeV1 {
      constructor: Task | Source | Live | Event
                 | CompletionSource | CompletionPort
                 | CommitTicket | CommitGate,
      owner: SlotRefV1,                  // Owner namespace
      payload: TypeRefV1 | null
    }
  | ResourceTypeV1 {
      owner: SlotRefV1,                  // Owner namespace
      value: TypeRefV1,
      cleanup_result: TypeRefV1
    }
  | SignalTypeV1 {
      clock: SlotRefV1,                  // Clock namespace
      payload: TypeRefV1
    }
  | PlanTypeV1 { payload: TypeRefV1 }
  | ResumeTypeV1 {
      usage: Zero | Once | Many,
      continuation: SuffixContractV1 | ContractParameterV1,
      argument: TypeRefV1,
      answer: TypeRefV1,
      live_provenance: ProvenanceExprV1,
      live_capture: CaptureExprV1,
      owner: SlotRefV1                   // Owner namespace
    }
  | HandlerTemplateTypeV1 {
      family: TypeRefV1,
      owner: SlotRefV1,                  // Owner namespace
      input: TypeRefV1,
      answer: TypeRefV1,
      residual_row: RowExprV1,
      contract: HandlerContractV1 | ContractParameterV1,
      policy: SummaryV1
    }
  | ForAllIdentityTypeV1 {
      binder: QuantifiedIdentityBinderV1,
      body: TypeRefV1
    }
  | ForAllContractTypeV1 {
      binder: QuantifiedContractBinderV1,
      body: TypeRefV1
    }
  | ExistsClockPackageTypeV1 {
      clock_binder: QuantifiedClockBinderV1,
      summary_binder: QuantifiedContractBinderV1,
      body: TypeRefV1
    }
  | ForAllOwnerTypeV1 {
      binder: QuantifiedOwnerBinderV1,
      body: TypeRefV1
    }

TypeRefV2 =
    LegacyTypeRefV2 { value: TypeRefV1 }
  | TypeParameterV2 { slot: u32 }
  | NominalTypeV2 {
      module: ModulePathV1,
      name: IdentifierV1,
      arguments: [TypeRefV2]
    }
  | ApplyTypeV2 {
      constructor: TypeConstructorRefV1,
      arguments: [TypeRefV2]
    }
  | FunctionTypeV2 {
      parameter: TypeRefV2,
      result: TypeRefV2,
      contract: FunctionContractV2 | ContractParameterV2 | ContractRefV2
    }
  | CapabilityTypeV2 {
      identity: SlotRefV1,
      family: TypeRefV2
    }
  | NextTypeV2 {
      clock: SlotRefV1,
      payload: TypeRefV2,
      later_contract: LaterContractV2 | ContractParameterV2
    }
  | OwnerTypeV2 { owner: SlotRefV1 }
  | OwnerIndexedTypeV2 {
      constructor: Task | Source | Live | Event
                 | CompletionSource | CompletionPort
                 | CommitTicket | CommitGate,
      owner: SlotRefV1,
      payload: TypeRefV2 | null
    }
  | ResourceTypeV2 {
      owner: SlotRefV1,
      value: TypeRefV2,
      cleanup_result: TypeRefV2
    }
  | SignalTypeV2 { clock: SlotRefV1, payload: TypeRefV2 }
  | PlanTypeV2 { payload: TypeRefV2 }
  | ResumeTypeRefV2 { value: ResumeTypeV2 }
  | HandlerTemplateTypeV2 {
      family: TypeRefV2,
      owner: SlotRefV1,
      input: TypeRefV2,
      answer: TypeRefV2,
      residual_row: RowExprV1,
      contract: HandlerContractV2 | ContractParameterV2,
      policy: SummaryV1
    }
  | ForAllIdentityTypeV2 {
      binder: QuantifiedIdentityBinderV2,
      body: TypeRefV2
    }
  | ForAllContractTypeV2 {
      binder: QuantifiedContractBinderV2,
      body: TypeRefV2
    }
  | ForAllOwnerTypeV2 {
      binder: QuantifiedOwnerBinderV1,
      body: TypeRefV2
    }
  | ExistsClockPackageTypeV2 {
      clock_binder: QuantifiedClockBinderV2,
      summary_binder: QuantifiedContractBinderV2,
      body: TypeRefV2
    }
  | PackedNextTypeV2 {
      owner: SlotRefV1,
      payload: TypeRefV2
    }

PackedNextPackageV2 {
  artifact: "PackedNextPackageV2"
  profile: "Cire-TR₀/2026-08-01"
  schema_version: 2
  storage_owner: SlotRefV1
  child_owner_binder: QuantifiedOwnerBinderV1
  owner_relation: ChildOwnerWitnessV2
  clock_binder: QuantifiedClockBinderV2
  summary_binder: QuantifiedContractBinderV2
  body: NextTypeV2
  control_protocol: PackedNextControlProtocolV2
  sealed_origin: SourceOriginV2
}

ChildOwnerWitnessV2 {
  parent: SlotRefV1
  child: SlotRefV1
  relation: DirectChild
  sealed_origin: SourceOriginV2
}

PackedNextControlProtocolV2 {
  states: [Open(u32), Closing(u32), Closed]
  acquire: [Open(n) -> Open(n+1), Closing(n) -> None, Closed -> None]
  dispose: [Open(0) -> Closed+CloseChild,
            Open(n+1) -> Closing(n+1),
            Closing(n) -> Closing(n), Closed -> Closed]
  release: [Open(n+1) -> Open(n),
            Closing(1) -> Closed+CloseChild,
            Closing(n+1) -> Closing(n) where n>=1]
}

PackedNextExitEvidenceV2 {
  path_index: u32
  input_tag: ReturnsV2 | AbortsV2 | TransfersV2
  output_tag: ReturnsV2 | AbortsV2 | TransfersV2
  lease_action: ExactlyOnceRelease
  release_summary: SummaryV1
}

QuantifiedIdentityBinderV1 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1 | null
  family: TypeRefV1
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedIdentityBinderV2 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1 | null
  family: TypeRefV2
  owner: SlotRefV1
}

QuantifiedClockBinderV1 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1
  family: TypeRefV1
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedClockRefinementV1 {
  clock_slot: u32
  identity: SlotRefV1                    // local paired Identity namespace
}

ClockFamilyWitnessV2 = CanonicalFrameClockV2 {
  module: ["cire", "temporal"],
  name: "FrameClock",
  sealed_origin: SourceOriginV1
}

QuantifiedClockBinderV2 {
  identity_slot: u32
  clock_refinement: QuantifiedClockRefinementV1
  family_witness: ClockFamilyWitnessV2
  owner: SlotRefV1                       // enclosing Owner namespace
}

QuantifiedOwnerBinderV1 { owner_slot: u32 }

QuantifiedContractBinderV1 {
  contract_slot: u32
  kind:
      FunctionContractKindV1 {
        parameter_type: TypeRefV1,
        result_type: TypeRefV1
      }
    | LaterContractKindV1 {
        clock: SlotRefV1,                // enclosing Clock namespace
        payload_type: TypeRefV1
      }
    | ClockPackageSummaryKindV1 {
        clock: SlotRefV1,                // paired local Clock namespace
        payload_type: TypeRefV1
      }
}

QuantifiedContractBinderV2 {
  contract_slot: u32
  kind:
      FunctionContractKindV2 {
        parameter_type: TypeRefV2,
        result_type: TypeRefV2,
        visible_row: RowExprV1
      }
    | LaterContractKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
    | ClockPackageSummaryKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
}

TypeConstructorRefV1 =
    BuiltinConstructorV1 { name: Array | Option | Result }
  | NominalConstructorV1 {
      module: ModulePathV1,
      name: IdentifierV1
    }

ContractParameterV1 {
  slot: u32
  kind: Function | Later | Continuation | Handler | ClockPackageSummary
}

ContractParameterV2 {
  slot: u32
  kind:
      FunctionContractKindV2 {
        parameter_type: TypeRefV2,
        result_type: TypeRefV2,
        visible_row: RowExprV1
      }
    | LaterContractKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
    | ContinuationContractKindV2 {
        argument_type: TypeRefV2,
        answer_type: TypeRefV2
      }
    | HandlerContractKindV2 {
        family: TypeRefV2,
        input_type: TypeRefV2,
        answer_type: TypeRefV2
      }
    | ClockPackageSummaryKindV2 {
        clock: SlotRefV1,
        payload_type: TypeRefV2
      }
}
LaterContractV1 {
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
}
LaterContractV2 {
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
}
HandlerContractV1 {
  handled_entry: EffectEntrySelectorV1
  prompt_slot: u32
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  handler_environment: [EnvironmentBindingV1]
  return_flow: FlowSetV1
  clause_flows: [ClauseFlowSetV1]
}
HandlerContractV2 {
  handled_entry: EffectEntrySelectorV1
  prompt_slot: u32
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  required_phase: PhaseRequirementV1
  handler_environment: [EnvironmentBindingV2]
  applications: [AppliedContractV2]
  return_computation: ContractComputationV2
  clause_computations: [ClauseComputationV2]
}
ClauseComputationV2 {
  operation: OperationSelectorV1
  disposition_binder: ClauseDispositionBinderV2
  computation: ContractComputationV2
}
ClauseDispositionBinderV2 {
  slot: u32
  site_slot: u32
  type: TypeRefV2                    // must be ResumeTypeRefV2
}
ClauseFlowSetV1 {
  operation: OperationSelectorV1
  disposition_binder: ClauseDispositionBinderV1
  flow: [ClauseFlowPathV1]
}
ClauseDispositionBinderV1 {
  slot: u32                             // declares a SuffixLive slot
  site_slot: u32
  type: TypeRefV1                       // must be ResumeTypeV1
}
IdentifierV1 = validated NFC UTF-8 identifier string
ModulePathV1 = nonempty [IdentifierV1]
StringV1 = NFC UTF-8 string

NominalIndexExprV1 =
    NoNominalIndexV1
  | TypeParameterIndexV1 { slot: u32 }
  | IdentityIndexV1 { identity: SlotRefV1 }
  | OwnerIndexV1 { owner: SlotRefV1 }

NominalIndexExprV2 =
    LegacyNominalIndexExprV2 { value: NominalIndexExprV1 }
  | ReturnNominalIndexV2 { return_slot: u32 }

OperationSignatureV1 {
  type_binders: [TypeBinderV1]
  parameters: [TypeRefV1]
  result: TypeRefV1
  mode: fun | once | ctl | abort
  transition: TransitionV1
  suspension: SuspensionV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
}

OperationSignatureV2 {
  type_binders: [TypeBinderV1]
  parameters: [TypeRefV2]
  result: TypeRefV2
  mode: fun | once | ctl | abort
  transition: TransitionV1
  suspension: SuspensionV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
}

SourceOriginV1 = canonical `file:subject` StringV1
SourceOriginV2 = SourceOriginV1

FlowSetV1 = nonempty [FlowPathV1]

FlowSetV2 = normalize(nonempty [PathOutcomeV2])

FlowPathV1 =
    Returns {
      transition: TransitionV1,
      result_transformer: ResultTransformerV1
    }
  | Aborts {
      origin: SourceOriginV1
    }
  | Transfers {
      park_contract: ParkContractV1
    }

ParkContractV1 {
  owner_slot: u32
  site_slot: u32
  claim_cell_slot: u32
  source: SourceContractV1
  completion_port: CompletionPortV1
  claim: GenerationCASV1
  disposition: OneShotDispositionV1
  required_phase: PhaseRequirementV1
  origin: SourceOriginV1
}

ParkContractV2 {
  owner_slot: u32
  site_slot: u32
  claim_cell_slot: u32
  source: SourceContractV2
  completion_port: CompletionPortV2
  claim: GenerationCASV1
  disposition: OneShotDispositionV2
  required_phase: PhaseRequirementV1
  origin: SourceOriginV1
}

SourceContractV1 {
  owner: SlotRefV1              // Owner namespace
  value_type: TypeRefV1
  generation_model: MonotoneGenerationV1
  write_authority: SingleWriterV1
}

CompletionPortV1 {
  owner: SlotRefV1              // same Owner as source
  result_type: TypeRefV1
  port_slot: u32
  claim_cell_slot: u32
}

SourceContractV2 {
  owner: SlotRefV1              // Owner namespace
  value_type: TypeRefV2         // exact resumption argument A
  generation_model: MonotoneGenerationV1
  write_authority: SingleWriterV1
}

CompletionPortV2 {
  owner: SlotRefV1              // same Owner as source
  value_type: TypeRefV2         // exact resumption argument A
  port_slot: u32
  claim_cell_slot: u32
}

GenerationCASV1 {
  claim_cell_slot: u32
  source_generation: ClaimTicketGeneration
  completion_generation_gate: EqualCurrentGeneration
  finalization_generation_gate:
    EqualCurrentGenerationOrOwnerRetireAuthority
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
  generation_transition: PreserveGeneration
  failure_transition: NoStateChange
}

OneShotDispositionV1 {
  continuation_site_slot: u32
  claim_cell_slot: u32
  continuation: SuffixContractV1
  states: [Unclaimed, Completed, Finalized]
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
}

OneShotDispositionV2 {
  continuation_site_slot: u32
  claim_cell_slot: u32
  resumption: ResumeTypeV2
  states: [Unclaimed, Completed, Finalized]
  completion_transition: UnclaimedToCompleted
  finalization_transition: UnclaimedToFinalized
}

ResumeTypeV2 {
  usage: Zero | Once | Many
  continuation: SuffixContractV2
  argument: TypeRefV2
  answer: TypeRefV2
  live_provenance: ProvenanceExprV2
  live_capture: CaptureExprV2
  owner: SlotRefV1                  // Owner namespace
}

MonotoneGenerationV1 = Unsigned64NoWrap
SingleWriterV1 = OwnerExecutorOnly

ForwardContractV1 {
  site_slot: u32
  route: InstallationPromptV1 { prompt_slot: u32 }
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  continuation: ContinuationContractV1
  entry_world: WorldExprV1
  actual_argument_summaries: [ActualArgumentSummaryExprV1]
  instantiated_signature: OperationSignatureV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
  origin: SourceOriginV1
}

ForwardContractV2 {
  site_slot: u32
  route: InstallationPromptV1 { prompt_slot: u32 }
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  continuation: ContinuationContractV2
  entry_world: WorldExprV2
  actual_argument_summaries: [ValueSummaryExprV2]
  instantiated_signature: OperationSignatureV2
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  secondary_sites: SecondarySiteSetV1
  origin: SourceOriginV2
}

ForwardDispositionEvidenceV2 {
  inner_disposition: SlotRefV1       // SuffixLive namespace
  input_state: Open
  output_state: Forwarded
  forward_site_slot: u32
  continuation_transfer: ExclusiveToForwardContract
}

ClauseFlowPathV1 =
    FlowPathV1
  | Delegates {
      forward_contract: ForwardContractV1,
      disposition_evidence: ForwardDispositionEvidenceV1
    }

ForwardDispositionEvidenceV1 {
  inner_disposition: SlotRefV1           // authority-bearing SuffixLive slot
  input_state: Open
  output_state: Forwarded
  forward_site_slot: u32
  continuation_transfer: ExclusiveToForwardContract
}

SuspensionV1 {
  grade: SuspensionGradeV1
  atoms: [SuspensionAtomV1]
}

SuspensionGradeV1 = NoSuspend | MaySuspend

SuspensionAtomV1 =
    DirectV1 {
      grade: MaySuspend,
      origin: SourceOriginV1
    }
  | RequestV1 {
      site_slot: u32,
      route: RouteSelectorV1,
      entry: EffectEntrySelectorV1,
      operation: OperationSelectorV1,
      site_role: Primary | Secondary { secondary_slot: u32 },
      grade: SuspensionGradeV1,
      origin: SourceOriginV1
    }
  | OwnerBoundV1 {
      park_site_slot: u32,
      owner_slot: u32,
      grade: SuspensionGradeV1,
      origin: SourceOriginV1
    }

SlotRefV1 {
  namespace: Parameter | ClosureCapture | OperationArgument
             | SuffixLive | Clock | Owner | Row | Identity
  slot: u32
}

PromptSlotDeclV1 {
  prompt_slot: u32
  binder_site_slot: u32
  scope: LexicalInstallation
}

IdentitySlotDeclV1 {
  identity_slot: u32
  family: EffectFamilyRefV2
  owner: SlotRefV1                       // Owner namespace
  binder: FreshCap | NamedHandler
}

EffectFamilyRefV2 =
    NominalTypeV1 resolved as an Effect declaration
  | TypeParameterV1 whose slot has kind Effect
  | TypeParameterV2 whose slot has kind Effect

EffectFamilyDeclarationsV1 {
  artifact: "EffectFamilyDeclarationsV1",
  profile: "Cire-TR₀/2026-08-01",
  schema_version: 1,
  families: [{ module: [IdentifierV1], name: IdentifierV1, arity: u32 }]
}

Catalog是 exact object；`families`按整个 declaration的 JCS encoding递增且
module-qualified identity唯一，`module`非空，`arity`在 wire-u32 domain。

EffectEntrySelectorV1 =
    AnonV1 {
      family: EffectFamilyRefV2
    }
  | NamedV1 {
      identity: SlotRefV1,       // Identity namespace
      family: EffectFamilyRefV2
    }
  | HandlerEntryParameterV1 {
      contract_slot: u32         // Handler contract binder
    }

OperationSelectorV1 =
    ExactOperationV1 {
      family: EffectFamilyRefV2,
      name: IdentifierV1
    }
  | AnyOperationOfEntry

ActualArgumentSummaryExprV1 =
    SlotArgumentV1 {
      source: SlotRefV1,
      type: TypeRefV1,
      nominal_index: NominalIndexExprV1,
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1
    }
  | ComputedArgumentV1 {
      type: TypeRefV1,
      nominal_index: NominalIndexExprV1,
      provenance: ProvenanceExprV1,
      capture: CaptureExprV1,
      origin: SourceOriginV1
    }

DemandV1 {
  site_slot: u32
  route: RouteSelectorV1
  entry: EffectEntrySelectorV1
  operation: OperationSelectorV1
  site_role: Primary | Secondary { secondary_slot: u32 }
}

LiveAcrossSiteV1 {
  slot: SlotRefV1              // SuffixLive namespace
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
  usage: UsageV1
}

LiveAcrossSiteV2 {
  slot: SlotRefV2              // SuffixLive or an in-scope return binder
  type: TypeRefV2
  provenance: ProvenanceExprV2
  capture: CaptureExprV2
  usage: UsageExprV2?          // null is canonical Zero/non-authority
}

CleanupContractV1 {
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  transition: TransitionV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
}

SuffixContractV1 {
  residual_row: RowExprV1
  attributed_demand: [DemandV1]
  flow: FlowSetV1
  transition: TransitionV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  result_transformer: ResultTransformerV1
  required_phase: PhaseRequirementV1
  cleanup: CleanupContractV1
  live_bindings: [LiveAcrossSiteV1]
}

SuffixContractV2 {
  answer_type: TypeRefV2
  applications: [AppliedContractV2]
  computation: ContractComputationV2
  cleanup: CleanupContractV1
  live_bindings: [LiveAcrossSiteV2]
}

ContinuationContractV1 = SuffixContractV1
ContinuationContractV2 = SuffixContractV2

CaptureSlotV1 {
  slot: SlotRefV1            // namespace must be ClosureCapture
  type: TypeRefV1
  provenance: ProvenanceExprV1
  capture: CaptureExprV1
}

ObligationV1 =
    BoundarySafeV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      boundary: BoundaryKindV1, origin: SourceOriginV1
    }
  | StableAcrossV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      clock_slot: SlotRefV1, worlds: [WorldExprV1],
      origin: SourceOriginV1
    }
  | OutlivesV1 {
      id: u32, stage: StageV1,
      shorter: SlotRefV1, longer: SlotRefV1,
      origin: SourceOriginV1
    }
  | PhaseAllowsV1 {
      id: u32, stage: StageV1,
      required_phase: PhaseRequirementV1,
      origin: SourceOriginV1
    }
  | DuplicableEnvV1 {
      id: u32, stage: StageV1, slots: [SlotRefV1],
      site_slot: u32, origin: SourceOriginV1
    }
  | ReplayableCleanupV1 {
      id: u32, stage: StageV1, site_slot: u32,
      cleanup: CleanupContractV1, origin: SourceOriginV1
    }
  | TickWitnessV1 {
      id: u32, stage: StageV1,
      clock_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV1
    }
  | OwnerParkingV1 {
      id: u32, stage: StageV1,
      owner_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV1
    }
  | RowLacksV1 {
      id: u32, stage: StageV1,
      row_slot: SlotRefV1, entry: EffectEntrySelectorV1,
      origin: SourceOriginV1
    }

ObligationV2 =
    LegacyObligationV2 { value: ObligationV1 }
  | BoundarySafeV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      boundary: BoundaryKindV1, origin: SourceOriginV2
    }
  | StableAcrossV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      clock_slot: SlotRefV1, worlds: [WorldExprV2],
      origin: SourceOriginV2
    }
  | OutlivesV2 {
      id: u32, stage: StageV1,
      shorter: SlotRefV2, longer: SlotRefV2,
      origin: SourceOriginV2
    }
  | PhaseAllowsV2 {
      id: u32, stage: StageV1,
      required_phase: PhaseRequirementV1,
      origin: SourceOriginV2
    }
  | DuplicableEnvV2 {
      id: u32, stage: StageV1, slots: [SlotRefV2],
      site_slot: u32, origin: SourceOriginV2
    }
  | ReplayableCleanupV2 {
      id: u32, stage: StageV1, site_slot: u32,
      cleanup: CleanupContractV1, origin: SourceOriginV2
    }
  | TickWitnessV2 {
      id: u32, stage: StageV1,
      clock_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV2
    }
  | OwnerParkingV2 {
      id: u32, stage: StageV1,
      owner_slot: SlotRefV1, site_slot: u32,
      origin: SourceOriginV2
    }
  | RowLacksV2 {
      id: u32, stage: StageV1,
      row_slot: SlotRefV1, entry: EffectEntrySelectorV1,
      origin: SourceOriginV2
    }

BoundaryKindV1 =
    CallArgument | Return | Closure | Aggregate | OwnerStorage
  | ContinuationCapture | TemporalLock | Suspension | FFI

LatentSiteV1 {
  site_slot: u32             // alpha-normalized lexical-site slot
  stage: Call | HandlerInstall
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  actual_arguments: [ActualArgumentSummaryExprV1]
  instantiated_signature: OperationSignatureV1
  suffix: SuffixContractV1
  secondary_sites: SecondarySiteSetV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  origin: SourceOriginV1
}

LatentSiteV2 {
  site_slot: u32
  stage: Call | HandlerInstall
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  actual_arguments: [ValueSummaryExprV2]
  instantiated_signature: OperationSignatureV2
  suffix: SuffixContractV2
  secondary_sites: SecondarySiteSetV1
  call_obligation_ids: [u32]
  install_obligation_ids: [u32]
  origin: SourceOriginV2
}

SecondarySiteSetV1 {
  kind: Closed
  sites: [SecondarySiteV1]
}

SecondarySiteV1 {
  site_slot: u32
  receiver: EffectEntrySelectorV1
  operation: OperationSelectorV1
  route: RouteSelectorV1
  suspension: SuspensionV1
  semantic_summary: SummaryV1
  origin: SourceOriginV1
}

RouteSelectorV1 =
    ResolveAtCallV1 { on_missing: MissingRoutePolicyV1 }
  | ResolveAtInstallationV1 { on_missing: MissingRoutePolicyV1 }
  | InstallationPromptV1 { prompt_slot: u32 }
  | OuterOfV1 { prompt_slot: u32 }
  | RootOfEntryV1

MissingRoutePolicyV1 = RootOfEntryV1
StageV1 = Call | HandlerInstall
```

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

`Cire-TR₀/2026-08-01` 的 canonical envelope 是
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
不能仅根据 `NominalTypeV1` object shape推测。Repository complete roots把该
environment冻结为上述 `EffectFamilyDeclarationsV1`；真实 importer的同一 obligation由
已解析 declaration table提供。`TypeParameterV1/V2`必须引用当前 lexical
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
contract/identity table必须传入 applications与 computation ContractWF；
`handled_entry`、`residual_row`以及每个 instantiated target public row都用同一
identity/handler-contract table递归检查 selector scope与 family。V2
serializer/importer不得把其中任何一段降级成
`ClauseFlowSetV1`、`SuffixContractV1` 或从旧 flow字段重建。

Normative V2 import is context-sensitive and exhaustive:

```text
import_contract_computation_v2(node, applications, returns, delegates):
  match exact_variant(node):
    LiteralPathsV2(paths):
      require paths nonempty
      return map(paths, p => import_path_v2(
        p, applications, returns, delegates))
    CurrentDispositionPathsV2(paths):
      require delegates is HandlerClauseOnly(disposition_binder)
        or diagnose path-bind-literal-prefix-forbidden
      require this node is the immediate PathBindV2 prefix
      require paths nonempty
      return CurrentDispositionPaths(
        map(paths, p => import_path_v2(
          p, applications, returns, delegates)), disposition_binder)
    InvokeV2(slot):
      require unique slot in applications
      return Invoke(slot)
    PathBindV2(prefix, binder, continuation, PreserveTerminalV2):
      p = import_contract_computation_v2(
        prefix, applications, returns, delegates)
      require binder.slot not in returns
      b = import_return_binder_v2(binder, returns)
      prefix_types = derive_return_types(
        p, applications, delegates.current_disposition)
      require prefix_types is defined
        or diagnose path-bind-literal-prefix-forbidden
      require every t in prefix_types has b.type == t
      require every Returns path r in p has
        b.world/provenance/capture == project_return(r, applications)
      c = import_contract_computation_v2(
        continuation, applications, returns + {binder.slot -> b}, delegates)
      return PathBind(p, b, c, PreserveTerminal)
    JoinV2(members):
      require members nonempty
      return map(members, m => import_contract_computation_v2(
        m, applications, returns, delegates))
    otherwise:
      diagnose unknown-contract-computation-variant

import_path_outcome_v2(outcome, applications, returns, delegates):
  match exact_variant(outcome):
    ReturnsV2(transition, transformer):
      return Returns(import_transition_v1_exact(transition),
        import_result_transformer_v2(transformer, returns))
    AbortsV2(origin): return Aborts(origin)
    TransfersV2(park):
      return Transfers(import_park_contract_v2(park, applications, returns))
    DelegatesV2(forward, evidence):
      require delegates is HandlerClauseOnly(disposition_binder)
        or diagnose delegates-outside-handler-clause
      require evidence.inner_disposition ==
        SlotRefV1(SuffixLive, disposition_binder.slot)
      return Delegates(
        import_forward_contract_v2(forward, applications, returns),
        import_forward_disposition_v2(evidence, disposition_binder))
    otherwise:
      diagnose unknown-path-outcome-v2
```

Every recursive V2 expression importer receives the same `returns` map;
`Return*V2(slot)` requires an exact entry and `ReturnUsageV2(slot)` additionally
requires that entry's type be `ResumeTypeRefV2`. Root Function/Suffix and handler
return calls pass `delegates=Forbidden`; only the corresponding clause call passes
`HandlerClauseOnly`. Unknown tags and extra/missing variant fields are errors,
never extension points for this frozen profile.

`Call` obligation 在 T-App 实例化和 discharge；`HandlerInstall`
obligation与对应 `LatentSiteV2` 原样保留到 fresh delimiter prompt存在时的
`InstallOK`。调用者不得仅因跨模块 call成功就把后一阶段清空。

新 profile 的 stable diagnostic registry是
`examples/spec/diagnostics-v2.json`。Clock/PackedNext importer至少区分
`clock-package-private-identity-escape`、
`clock-package-transfer-captures-private-identity`、
`clock-package-family-not-clock-indexing`、
`packed-next-builder-result-mismatch`；Park exactness区分
`park-source-payload-mismatch` 与 `park-resumption-type-mismatch`；contract
term区分 kind/instantiation/scope/cycle、terminal bind、return-flow、Q stage
与 Lambda key错误；context/exhaustiveness另外区分
`delegates-outside-handler-clause`、
`unknown-contract-computation-variant` 与 `unknown-path-outcome-v2`。V1
decoder看到 V2 field/tag必须产生
`unsupported-contract-schema-version`，不能忽略或回填。
closed Q/source/u32 exactness另固定 `unknown-obligation-stage`、
`unknown-obligation-variant`、`term-actual-source-unavailable` 与
`wire-u32-out-of-range`。
本轮 exactness diagnostics另外固定 summary/HOF、ContractRef/T-App、
Handler/Forward、Park/Packed/runtime各自的稳定 id：
`semantic-summary-not-normalized`、`hof-complete-path-observer-mismatch`、
`imported-function-export-mismatch`、`local-function-ref-unresolved`、
`application-arity-mismatch`、`application-argument-type-mismatch`、
`handler-disposition-escapes-scope`、`forward-operation-mismatch`、
`forward-route-mismatch`、`forward-application-arity-type-mismatch`、
`park-generation-protocol-mismatch`、`park-disposition-protocol-mismatch`、
`park-required-phase-mismatch`、`park-owner-outlives-missing`、
`clock-package-path-observer-mismatch`、`packed-next-control-protocol-mismatch`、
`packed-next-pack-phase-mismatch` 与 `packed-next-runtime-protocol-mismatch`。

与 hidden $L$ 相同，surface `(A) -> B ! ε` 先 elaboration为
$A arrow.r.long^(?C) B$，不是把未显示字段填成 `pure/same`。有 initializer
的 declaration求解 $?C$；高阶 input binder把未由 annotation约束的字段
泛化为 rigid contract parameter，并创建单一 `AppliedContractV2`，把调用时
用到的 row/world/flow/result/suspension/summary/usage/phase、$Q/Lambda$ 通过
同一 `InvokeV2`/`PathBindV2` computation投影进 enclosing function contract。
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
该 universal的 wire projection使用一个 `QuantifiedIdentityBinderV1`：
`identity_slot` 供 `CapabilityTypeV1.identity`，必填的
`clock_refinement.clock_slot` 供 `NextTypeV1.clock` 与 Later contract；
`clock_refinement.identity` 显式回指前者。两种 namespace view因 witness
表示同一个 $i$，而不是因 slot数字相同而 alias。
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

每个 demand 有稳定的 suspension attribution key：

$
  r_s ::= ⟨kappa,p,a,o,q⟩
  quad
  "demandKey"("Demand"(kappa,p,a,o,q))=r_s
$

`demandKeys(Δ)` 是逐项应用 `demandKey` 得到的 finite set。相同 entry
但不同 site、installation prompt、operation 或 primary/secondary slot
会得到不同 key。

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
  [Row-Empty],
  ([$"wellFormedRowLiteral"("{}")$],),
  [$K;I ⊢ {} ⇝ emptyset ⊣ emptyset$],
)

#irule(
  [Row-Ref],
  ([$K(mu)="EffectRow"$],),
  [$K;I ⊢ mu ⇝ mu ⊣ emptyset$],
)

#irule(
  [Row-Closed],
  (
    [$n >= 1$],
    [$forall j in 1..n. K;I ⊢ a_j:"EffectEntry"$],
    [$"DistinctEntries"(a_1,...,a_n)$],
  ),
  [$K;I ⊢ {a_1,...,a_n} ⇝
    "foldRowEntries"(a_1,...,a_n) ⊣ emptyset$],
)

#irule(
  [Row-Tail],
  (
    [$K;I ⊢ R ⇝ epsilon ⊣ C$],
  ),
  [$K;I ⊢ {..R} ⇝ epsilon ⊣ C$],
)

#irule(
  [Row-Open],
  (
    [$n >= 1$],
    [$K;I ⊢ R ⇝ epsilon ⊣ C$],
    [$forall j in 1..n. K;I ⊢ a_j:"EffectEntry"$],
    [$"DistinctEntries"(a_1,...,a_n)$],
  ),
  [$K;I ⊢ {a_1,...,a_n,..R} ⇝
    "foldRowEntries"(a_1,...,a_n) ⊔ epsilon
    ⊣ C∪"lacksAll"(epsilon,a_1,...,a_n)$],
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
variable summand和 `Lacks` constraint；Core union没有“最多一个开放
tail”的限制，也不把 `E1 | E2` 假装成单一 tail。Surface literal的 grammar
仍只允许一个 final tail，所以
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
$(kappa_q,a_q,o_q)$，再由显式 $S$ 独立运行 `resolveRoute(S,a_q)`；
它不能继承 primary demand 的 route。Exact handling只移除
`RowSplit(Δ,p).here`，不是对 family 名做 raw set subtraction。
同 family forwarding 在 Surface 尚无冻结拼写；Kernel 必须显式产生
`forward[p_outer](a,o,args)`，把 primary demand route更新到 outer prompt并保留原
identity/site。它不能用“先删 `{a}`、再加 `{a}`”模拟，否则 nested
same-family handler 与 secondary demand会失去 attribution。

Forwarding使用一个原子 reroute pair：

$
  "reroutePrimary"(
    "Demand"(kappa,p,a,o,"Primary"),
    "request"(⟨kappa,p,a,o,"Primary"⟩,d),
    p_"outer")
  =
  ⟨
    "Demand"(kappa,p_"outer",a,o,"Primary"),
    "request"(⟨kappa,p_"outer",a,o,"Primary"⟩,d)
  ⟩
$

它保持 $kappa/a/o/q$，只改 primary route与同 key suspension atom。
Secondary sites不经过这个 helper；它们各自按当前 prompt stack重新
`resolveRoute`。
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
        (exists i:"ClockId"("FrameClock",rho),
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
  ScopedApply(handlerValue : HandlerTemplate[...], binder cap, bodyThunk)
    ↦ let h = handlerValue in
      freshprompt p in
        handle[p, h, ι](
          let cap = capref(ι) in bodyThunk(cap))

  ScopedApply(ordinaryTransformer, none, bodyThunk)
    ↦ ordinaryTransformer(bodyThunk)

frame.yield()
  ↦ op[Named(ιframe, FrameClock)](yield, [])

live { e }
  ↦ first-party intrinsic/library boundary, not a new parser form

@temporal::pack_next(under=owner) { frame => e }
  ↦ contextual intrinsic PackNext(owner, frame, e)

@temporal::try_with_packed_next(packed) { frame, pending => e }
  ↦ contextual intrinsic TryOpenPackedNext(packed, frame, pending, e)

@temporal::dispose(packed)
  ↦ contextual intrinsic DisposePackedNext(packed)
```

Only the resolved sealed first-party origin receives these lowerings. A user
function or dependency alias with the same final identifier remains an ordinary
call/trailing lambda and cannot introduce fresh frame/lease binders.

`with ... as cap` 的 identity 不能按普通 lambda parameter generalize。
Surface HIR先保留统一的 `ScopedApply`，以保证 operand evaluation order与
inner thunk调用次数；resolver证明 operand具有 `HandlerTemplate[...]`
type后才降为
Kernel `handle`。普通 scoped transformer仍是函数调用，不能被错误地赋予
effect-row elimination。Kernel `freshprompt p; handle[p,h,i]` 每次安装
生成 route prompt和 generative identity，并立即以唯一 value introduction
`capref(i)` 把 Surface binder加入 lexical context；在结果处先 drop term
binder再执行 identity escape check。

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
排序、删除同一 entry 的重复项，并保留全部 rigid row-variable summand及其
`Lacks` constraints。只有 Surface row *literal* 限制一个 final `..tail`；
Core 的 `E1 ⊔ E2` 不合并、丢弃或伪装成单一开放 tail。算法化 equality是：

$
  epsilon_1 ≡ epsilon_2
  quad "iff" quad
  "nf"_epsilon(epsilon_1) = "nf"_epsilon(epsilon_2)
$

Core 不定义 raw `$epsilon-a$` handler elimination。Handler只能先对
attributed demand执行 `RowSplit(Δ,p)`，移除精确 route到该 installation
prompt的 $Delta_"here"$，再从 residual demand重新计算
`eraseDemand(Δout)`。即使两个 demand拥有相同 entry identity，forward到
outer prompt的那个也不能被本层删除。

== Attributed suspension summary

$
  "NoSuspend" <= "MaySuspend"
$

只存一个 scalar grade 无法正确表达 handler refinement：若 operation 的
`MaySuspend` 已经无条件 join 进 body，外层 sealed synchronous handler就再也
不能把它收紧。故 $s$ 是按请求来源归因的有限 map：

$
  s ::= "direct"(d)
    | "request"(r_s,d)
    | "ownerBound"(kappa_p,rho,d)
    | s_1 ⊔ s_2
  quad d in {"NoSuspend","MaySuspend"}
$

`grade(s)` 对全部分量取最大值。普通顺序组合与分支 join 使用 $⊔$；
operation call对每个 primary/secondary demand $d_i$ 加入
`"request"("demandKey"(d_i),grade_i)`。良构性要求：

$
  "AttributedOK"(Delta,s)
  quad "iff" quad
  "requestKeys"(s) subset.eq "demandKeys"(Delta)
$

`ownerBound(κp,ρ,d)` 是 T-Park/Owner transfer的独立 atom；它要求 stable
park site与 live Owner evidence，但不属于 effect demand，因而不出现在
`requestKeys(s)`，也不能被任意 effect handler消除。`direct(d)` 同样不是
伪造的 effect entry。

Handler 先按 prompt 对 demand 做 `RowSplit(Δ,p)`，再用完全相同的
$Delta_"here"$ keys 消除 suspension：

$
  "stripHandledSusp"(s,Delta_"here")
  =
  s - {"request"(r,_) mid r in "demandKeys"(Delta_"here")}
$

$
  "handleSusp"(s,Delta_"here",C_h,p)
  =
  "stripHandledSusp"(s,Delta_"here")
  ⊔ "handledSusp"(C_h,Delta_"here")
  ⊔ "residualSusp"(C_h,p)
$

对实际 handler installation，sealed evidence specialization为：

$
  "handleInstallSusp"(s,Delta_"here",E_i)
  =
  "stripHandledSusp"(s,Delta_"here")
  ⊔ "handledSusp"("contract"(E_i),Delta_"here")
  ⊔ "residualSusp"(E_i)
$

`handledSusp(C_h,Δhere)` 是对每个
`d ∈ Δhere` 的 `direct(handledGrade(C_h,d))` 做 finite join；
`handledGrade` 逐个替换实际由这次 installation处理的 site声明上界；
`residualSusp(E_i)` 保存本次实际 sites/Forward routes 对其他 route的
attributed request，并
满足：

$
  "requestKeys"("residualSusp"(E_i))
  subset.eq
  "demandKeys"("handlerResidual"(E_i))
$

只有
sealed/derived contract能证明 `handledGrade(C_h)=NoSuspend`；普通 handler
取 operation 声明上界，且 clause自己的 await等 suspension仍保留。删除
effect row entry本身并不删除 suspension，
必须同时通过 `handleSusp` 处理同一 $Delta_"here"$。显式 forwarding 或
同 entry、outer prompt的 secondary demand不在该 partition中，所以其
`MaySuspend` 分量不能被 inner handler擦除。需要 scalar 的 premise一律写
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
             | "Forwarded"(kappa_f)
$

`once` resume令 `Open(1) → Closed`；`ctl` resume令
`Open(ω) → Open(ω)`；`finalize` 令任意 `Open(q) → Closed`；
`park` 令其变为 `Transferred(ρ,g,c)`，其中 $c$ 是 sealed completion
port identity；Kernel `forward` 令其变为 `Forwarded(κf)`。
`Closed`、`Transferred` 与 `Forwarded` 都是 terminal disposition state，
没有 resume/finalize/park/forward 出边；这些 primitive 的 WF premise都要求
输入恰为 `Open(q)`。`Forwarded(κf)` 还要求 $kappa_f$ 唯一拥有原
continuation contract，且只可由 `InstallOK` 消费对应的 clause-internal
`Delegates(κf)` path。因此 `finalize(ctl_k)` 后不能利用
$omega-1=omega$ 再次 resume，也不能在 forwarding 后再次处置 inner token。

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
  "ClockPkg"[rho,A]
  = exists i:"ClockId"("FrameClock",rho),
      S:"ClockPackageSummary"(i,A).A
$

`ClockId(FrameClock,ρ)` formation需要 resolver给出的 sealed
`CanonicalFrameClockV2` witness。普通 $F:"Effect"$、同名用户 effect或伪造的
`clock_refinement` 都不能创建 Clock namespace；未来其它 clock family必须以
新 schema加入显式 `ClockFamilyWitness`。

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
  [K-Clock-Exists],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:"FrameClock"@rho ⊢ A:"Type"$],
    [$K;I,i:"FrameClock"@rho ⊢ "ClockPackageSummary"(i,A):"Evidence"$],
  ),
  [$K;I ⊢ "ClockPkg"[rho,A]:"Type"$],
)

Evidence kind只量化满足下式的 sealed summary：

$
  S=⟨pi_A,chi_A,F_"lease",P_"owner"⟩
  quad
  F_"lease"=⟨emptyset,"same","direct"("NoSuspend"),delta_"release"⟩
$

$P_"owner"$ 证明 shared child-Owner handle、lease acquire/release线性化和
最终 dispose幂等。`ReleaseHidePath` 对每个动态 exit恰好顺序执行一次
$F_"lease"$；它不增加 row/demand/suspension，但把
$delta_"release"$ 顺序组合进该 path summary。private clock identity即使只藏
在另一个 entry的 route、actual summary、secondary site、Q/$Lambda$、
cleanup/live binding、Park resumption或 contract computation中，也不能借
public observer normalization逃逸。

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
    [$I ⊢ j:"FrameClock"@rho$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A[j/i] @[pi_v] ▷ chi_v$],
    [$"ClockPackageSafe"(rho,j,A[j/i],pi_v,chi_v) ⇓ S_j$],
    [$S_i="closeClockSummary"(j⇒i,S_j)$],
    [$chi_p="sealClockCapture"(j,rho,chi_v,S_j) quad j ∉ "fv"(chi_p)$],
  ),
  [$K;I;Phi@Theta ⊢_v "packClock"[j](v) " as " "ClockPkg"[rho,A] ⇒ "ClockPkg"[rho,A] @["Owner"(rho)] ▷ chi_p$],
)

#irule(
  [T-Clock-Unpack-Paths],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "ClockPkg"[rho,A] @[pi_p] ▷ chi_p$],
    [$i ∉ "dom"(I) quad S_k:"ClockPackageSummary"(i,A) " fresh hidden"$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$"openClockLease"(p,Theta,i,S_k)=⟨Theta_p,l⟩$],
    [$"packagePayload"(S_k)=(pi_x,chi_x) quad Theta_x="bind"(Theta_p,x:A @[pi_x] ▷ chi_x)$],
    [$K;I,i:"FrameClock"@rho;Phi;Omega@Theta_x;S ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon_b;Delta_b;s_b;delta_b ⊣Omega_b$],
    [$forall t in cal(F)_b.
      "ClockPackageOutwardSafe"(i,S_k,B,t,"evidence"(t))$],
    [$t'="ReleaseHidePath"(S_k,l,i,x,t)
      quad "tag"(t')="tag"(t)$],
    [$cal(F)_o="normalize"({t' | t in cal(F)_b})$],
    [$⟨epsilon_o,Delta_o,s_o,delta_o,Omega_o⟩
      ="observeReleasedPaths"(cal(F)_o,S_k,Omega_b)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
      "unpackClock"[i,x](p,e)) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

== Sealed PackedNext surface

Surface `PackedNext[A]` elaborates to opaque Core `PackedNext[ρ,A]`; $rho$ is
the storage Owner index inferred from `under`, like the hidden Owner index of
Task/CompletionSource. The public type does not expose the runner's Owner.
Every sealed value carries a `PackedNextPackageV2` witness that first binds a
fresh child Owner $rho_c$, then under that binder binds exact canonical
FrameClock Identity $j$ and paired Clock view $i$, package summary $S_p$, and
body `Next[i,A,L]`, plus the shared lease protocol. Thus none of
$rho_c/j/i/L/S_p$ is free in the public
`PackedNext[ρ,A]`. User code cannot construct this nominal type or declare the
contextual callback contracts.

#irule(
  [K-PackedNext],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$K;I ⊢ A:"Type" quad "Shareable"(A)$],
  ),
  [$K;I ⊢ "PackedNext"[rho,A]:"Type"$],
)

The only privileged surface origins are
`@temporal::pack_next`, `@temporal::try_with_packed_next`, and
`@temporal::dispose` after resolver identity checking. A shadowed user function
with the same text is an ordinary call. Their CST remains ordinary labelled/
trailing-lambda syntax; resolver creates dedicated contextual HIR nodes.

#irule(
  [T-Pack-Next-Paths],
  (
    [$o:"Owner"[rho] in Theta quad
      Phi_"pack"="requiredPhase"(
        "Action","OwnerAuthority"(rho),rho) quad
      "PhaseAllows"(Phi,Phi_"pack") quad "OwnerAuthorized"(Phi,o,rho)$],
    [$rho_c,S_p ∉ "dom"(K) quad j,i ∉ "dom"(I)$],
    [$K_c=K,rho_c:"OwnerRegion"
      quad I_c=I,j:"Identity"("FrameClock")@rho_c,
        i:"ClockView"(j)@rho_c$],
    [$"CreatePackedFrame"(o) ⇓
      ⟨o_c:"Owner"[rho_c],j,i,"runner",h,w_c,Theta_c⟩$],
    [$delta_"alloc"="PackedAllocateSummaryV2"(
        "HostObservable","NoSuspend")
      quad delta_"close"="PackedTerminalCloseSummaryV2"(
        "HostObservable","NoSuspend")$],
    [$"Allowed"(Phi,emptyset,"direct"("NoSuspend"),delta_"alloc")$],
    [$w_c:"ChildOwnerWitnessV2"(rho,rho_c,"DirectChild")$],
    [$L="InferLaterContractV2"(i,A,e)
      quad "LaterContractWF"(L,i,A)$],
    [$Theta_f="bind"(Theta_c,"frame":"Cap"[j,"FrameClock"]
      @["Owner"(rho_c)] ▷ {j,i})$],
    [$K_c;I_c;Phi;Omega@Theta_f;S ⊢ "body"_("Next"[i,A,L])(e) ⇓
      cal(F)_b ! epsilon_b;Delta_b;s_b;delta_b ⊣Omega_b$],
    [$forall t in cal(F)_b.
      "PackNextPathSafe"(rho_c,j,i,h,A,L,t,"evidence"(t))$],
    [$forall t in cal(F)_b.
      "Allowed"(Phi,"row"(t),"suspension"(t),
        "PackObserverSummary"(delta_"alloc",delta_"close",t))$],
    [$"SealPackedSummary"(i,A,L,cal(F)_b) ⇓
      S_p:"ClockPackageSummary"(i,A)$],
    [$W_p="SerializePackedNextPackageV2"(
      "storage_owner"="OwnerRef"(rho),
      "child_owner_binder"="QuantifiedOwnerBinderV1"(
        "owner_slot"="slot"(rho_c)),
      "owner_relation"="ChildOwnerWitnessV2"(
        "parent"="OwnerRef"(rho),
        "child"="OwnerRef"(rho_c),
        "relation"="DirectChild",
        "sealed_origin"="cire.temporal:pack_next"),
      "clock_binder"="QuantifiedClockBinderV2"(
        "identity_slot"="slot"(j),
        "clock_refinement"=⟨"clock_slot"="slot"(i),
          "identity"="IdentityRef"(j)⟩,
        "family_witness"="CanonicalFrameClockV2",
        "owner"="OwnerRef"(rho_c)),
      "summary_binder"="QuantifiedContractBinderV2"(
        "contract_slot"="slot"(S_p),
        "kind"="ClockPackageSummaryKindV2"(
          "clock"="ClockRef"(i),"payload_type"=A)),
      "body"="Next"[i,A,L],
      "control_protocol"="CanonicalPackedNextControlV2",
      "sealed_origin"="cire.temporal:pack_next")$],
    [$"ImportPackedNextPackageV2"(K;I,W_p)
      =exists rho_c,j,i,S_p."Next"[i,A,L]$],
    [$cal(F)_p="normalize"({"SealOrClosePackPath"(
      delta_"alloc",delta_"close",
      o,o_c,rho_c,j,i,"runner",h,W_p,t) | t in cal(F)_b})$],
    [$forall t_p in cal(F)_p.
      rho_c,j,i,L,S_p ∉ "fvOutward"(t_p)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_("PackedNext"[rho,A])(
      "pack_next"(o,{"frame"[j↔i] => e})) ⇓ cal(F)_p !
    "row"(cal(F)_p);"demand"(cal(F)_p);
    "suspension"(cal(F)_p);"summary"(cal(F)_p) ⊣
    "usageOut"(cal(F)_p)$],
)

On a builder Returns path, `SealOrClosePackPath` requires exact
`Next[i,A,L]` and returns the single package bytes $W_p$ already round-tripped
through the normative importer. The wire binds child Owner, paired Identity/
Clock, package summary and body in that order and records the sealed direct-child
witness. It returns only opaque `PackedNext[ρ,A]` after hiding
$rho_c,j,i,L,S_p,o_c$.
On Aborts/Transfers it first rejects private-$i$ escape, then closes the new
runner/child Owner exactly once and preserves the terminal tag. Allocation and
close are empty-row/NoSuspend sealed summaries, but not `Pure`.
Precisely, `PackObserverSummary(δalloc,δclose,t)` is
`OrderedSummaryNF([δalloc, summary(t)])` when $t$ Returns and
`OrderedSummaryNF([δalloc, summary(t), δclose])` when $t$ Aborts/Transfers；
因此 body summary为 `PureV1` 的 Returns path直接输出 scalar $delta_"alloc"$，
不能保留含 Pure或singleton的 Sequence wrapper。
`SealOrClosePackPath` preserves every body row/demand/suspension/usage/
$Q/Lambda$ field, sets
`required_phase=RequireBoth(t.required_phase, Phi_pack)`, sequences exactly that
normalized summary, and on terminal paths records
the unique close-before-same-tag transition. `PackedAllocateSummaryV2` and
`PackedTerminalCloseSummaryV2` are sealed `CertificateV1` constructors with
origins `cire.temporal:packed-allocate` and
`cire.temporal:packed-terminal-close`; together with acquire/release/dispose
they are the only first-party PackedNext state observers and none is `PureV1`.
其完整 certificate fields是 frozen constants：allocate为
`Fresh/Share/StackOnly/HostObservable/Sealed(cire.temporal)`，terminal-close为
`Fresh/Forbid/StackOnly/HostObservable/Sealed(cire.temporal)`，publish均为
`None`。validator必须与这些常量比较，不能从待验证 payload中按 origin自行
“提取”证书后再证明它自己；把 trust改为 `Derived` 必须拒绝。

The shared cell is exactly:

```text
Open(n) | Closing(n) | Closed

acquire: Open(n) -> Open(n+1)
acquire: Closing(n) | Closed -> None
dispose: Open(0) -> Closed + unique final close
dispose: Open(n+1) -> Closing(n+1)
dispose: Closing(n) -> Closing(n); Closed -> Closed
release: Open(n+1) -> Open(n)
release: Closing(n+1) -> Closing(n), n >= 1
release: Closing(1) -> Closed + unique final close
```

上述有序 transition列表就是 `PackedNextPackageV2.control_protocol` 的 canonical
JSON事实。runtime oracle/importer必须从该 JSON逐条编译 pattern table（包括
`n>=1` guard、`None` result与 `CloseChildOnce` side effect），再用所得 table执行
trace；不得另写一份 lease count/state machine作为第二 source of truth。
`initial_state`只能是 `Open(0)`，runtime serialized `transition_table` 必须逐项
等于从 package导出的 table。任意 package transition、runtime initial state或
derived table漂移分别以 stable protocol diagnostic拒绝。runtime root还必须是
profile对应的 `schema_version=2`；版本 1不能因其余字段形状相似而进入 V2
state-machine decoder。

An acquire that linearized first is not interrupted by dispose. `dispose` is
idempotent, empty-row and NoSuspend, returns Unit after requesting Closing, and
does not promise that active leases have drained; its shared-state summary is
not `Pure`.

#irule(
  [PN-Release-Closing-Many],
  ([$n >= 1$],),
  [$"releasePacked"("Closing"(n+1)) arrow.r "Closing"(n)$],
)

#irule(
  [PN-Release-Closing-Last],
  (),
  [$"releasePacked"("Closing"(1)) arrow.r
    "Closed" + "CloseChildOnce"$],
)

#irule(
  [PN-Dispose-Open-Zero],
  (),
  [$"disposePacked"("Open"(0)) arrow.r
    "Closed" + "CloseChildOnce"$],
)

#irule(
  [T-Try-With-PackedNext-Paths],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "PackedNext"[rho,A] @[pi_p] ▷ chi_p$],
    [$"PhaseAllows"(Phi,"Action")$],
    [$delta_a="PackedAcquireSummaryV2"("HostObservable","NoSuspend")
      quad delta_r="PackedReleaseSummaryV2"("HostObservable","NoSuspend")$],
    [$"Allowed"(Phi,emptyset,"direct"("NoSuspend"),delta_a⊗delta_r)$],
    [$"tryAcquirePacked"(p) ⇓ "lost" mid
      "won"(l,W_p)$],
    [$"ImportPackedNextPackageV2"(K;I,W_p) ⇓
      ⟨rho_c,j,i,L,S_p,w_c⟩$],
    [$"openPackedRuntime"(p,l,W_p) ⇓
      ⟨o_c,"frame","pending"⟩$],
    [$rho_c,S_p ∉ "dom"(K) quad j,i ∉ "dom"(I)$],
    [$w_c:"ChildOwnerWitnessV2"(rho,rho_c,"DirectChild")$],
    [$K_c=K,rho_c:"OwnerRegion"
      quad I_c=I,j:"Identity"("FrameClock")@rho_c,
        i:"ClockView"(j)@rho_c$],
    [$"LaterContractWF"(L,i,A)
      quad K_p=K_c,S_p:"ClockPackageSummary"(i,A)$],
    [$Theta_p="bind"(
      "bind"("extendChildOwner"(Theta,o_c),
        "frame":"Cap"[j,"FrameClock"] @["Owner"(rho_c)] ▷ {j,i}),
      "pending":"Next"[i,A,L] @["summaryProvenance"(S_p)] ▷
        "summaryCapture"(S_p))$],
    [$K_p;I_c;Phi;Omega@Theta_p;S ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon_b;Delta_b;s_b;delta_b ⊣Omega_b$],
    [$forall t in cal(F)_b.
      "Allowed"(Phi,"row"(t),"suspension"(t),
        delta_a⊗"summary"(t)⊗delta_r)$],
    [$forall t in cal(F)_b.
      "PackedNextOutwardSafe"(rho_c,j,i,L,S_p,B,t,"evidence"(t))$],
    [$cal(F)_w="normalize"({
      "AcquireReleaseMapSomePath"(
        delta_a,delta_r,S_p,l,rho_c,j,i,L,t) | t in cal(F)_b})$],
    [$t_"lost"="AcquireLostNonePath"(
      delta_a,Theta,pi_"none",chi_"none")$],
    [$cal(F)_o="normalize"({t_"lost"}
      union cal(F)_w)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_("Option"[B])(
      "try_with_packed_next"(p,{"frame"[j↔i],"pending" => e})) ⇓
    cal(F)_o ! "row"(cal(F)_o);"demand"(cal(F)_o);
    "suspension"(cal(F)_o);"summary"(cal(F)_o) ⊣
    "usageOut"(cal(F)_o)$],
)

`AcquireReleaseMapSomePath` sequences the non-Pure acquire summary, the body
path summary, and the mandatory non-Pure release summary in that order. It maps
Returns($b$) to release;Returns(Some($b$)); after the full nonescape gate it maps
Aborts/Transfers to release followed by the exact same terminal tag, then hides
$rho_c$、$j$、$i$、$L$ 与 $S_p$. `AcquireLostNonePath` retains the non-Pure
acquire-attempt summary and performs no release. The acquire-lost
Returns(None) path is always reachable, so
the outer intrinsic is `MayReturn` even when the open body has no Returns.
For every won path, its residual row, attributed demand, usage, $Q$ and
$Lambda$ are the body fields after the private-binder nonescape projection;
its suspension is
`join(direct(NoSuspend), body.suspension, direct(NoSuspend))`, its required
phase is the intersection of Action with `body.required_phase` (including the
body's authorities/current Owner), and its summary is exactly
`OrderedSummaryNF([δacquire, body.semantic_summary, δrelease])`.
In particular a body `TransfersV2(ParkContractV2)` keeps its
`OwnerBoundV1(site,owner,MaySuspend)`, $delta_"park"$ and OwnerAuthority/current
Owner observers; release evidence does not replace any of them. Decoder必须对
transfer path逐字段检查 suspension、ordered summary与 phase，不能只检查 tag、
release count或 private identity nonescape。

#irule(
  [T-Dispose-PackedNext],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "PackedNext"[rho,A] @[pi_p] ▷ chi_p$],
    [$"PhaseAllows"(Phi,"Action")$],
    [$delta_d="PackedDisposeSummaryV2"("HostObservable","NoSuspend")$],
    [$"Allowed"(Phi,emptyset,"direct"("NoSuspend"),delta_d)$],
    [$"requestPackedClose"(p):
      "Open"(0)↦"Closed"+"CloseChildOnce",
      "Open"(n+1)↦"Closing"(n+1),
      "Closing"(n)↦"Closing"(n),
      "Closed"↦"Closed"$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "dispose_packed_next"(p) ⇒
    "Unit" @["Stable"] ! emptyset;emptyset ▷
    "direct"("NoSuspend");delta_d;emptyset
    @Theta⊣Omega$],
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
scope exit只原子 release该 lease。公开 handle使用
`Open(n)|Closing(n)|Closed`：有 active lease时 dispose幂等地进入 Closing且
不等待；`Open(0)` 则立即执行唯一 close并进入 Closed；
最后一个 release唯一关闭 runner/child Owner。若未来选择 affine package，必须把 quantity
传播到 alias、ADT与 closure；本文不偷偷假设那套尚未定义的规则。
T-Clock-Unpack-Paths 的 nonescape gate递归遍历所有 outward-surviving
artifacts：result type/provenance/capture/world、row/attributed demand/route、
operation/secondary sites、suspension/summary/usage/locks、Q/$Lambda$、完整
ParkContractV2/ResumeTypeV2/suffix cleanup+live bindings，以及
AppliedContractV2/ContractComputationV2。Returns还执行
`PackageResultBoundarySafe`；Aborts与Transfers保持原 tag。每个通过 gate的
path由 `ReleaseHidePath` 恰好 release一次、drop payload binder并隐藏 $i$；
generic T-Ctx-Paths不能跳过 delimiter。T-Clock-Unpack与
T-Clock-Unpack-Abort只作为 singleton projections，不再是 normative rule。
Surface不提供一般 existential spelling；sealed `PackedNext` intrinsic负责
创建/打开 V2 artifact，Core binder与 module interface evidence仍不省略。

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
`HandlerTemplate[F,ρ,A,B,ε,(S,p,a).C,P]` 在 family、origin region、
answer types、row、installation-stack/prompt/entry-abstract contract 与 policy
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

`ContractEq` 在 V2 比较 normalized declaration binders、原子
`AppliedContractV2` ledger与完整 `ContractComputationV2`（bound slot允许
alpha-renaming），再比较由同一 term派生的 canonical `FlowSetV2` observers。
`flow(C)` 不是 sidecar exception：`{AbortsV2}`、`{TransfersV2(P)}` 与任何含
Returns的 contract都互不相等。显式 legacy V1 decoder才对旧 concrete tuple
逐字段比较；它不能把 V2 computation投影回旧 12-tuple后声称相等。
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
    [$K;I,i:F@rho;Phi;Omega@Theta;S ⊢ e ⇒
      A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
    [$i ∉ "fv"(A,pi,epsilon,Delta,s,delta,chi,Omega')$],
    [$Theta_o="hideIdentity"(Theta',i)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "freshcap" i:F@rho " in " e ⇒
    A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta_o⊣Omega'$],
)

#irule(
  [K-Fresh-Cap-Abort],
  (
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho;Phi;Omega@Theta;S ⊢_"abort" e !
      epsilon;Delta ▷ s;delta ⊣Omega'$],
    [$"NoIdentityInAbortEvidence"(
      i,e,epsilon,Delta,s,delta,Omega')$],
    [$(Omega_o,delta_o)="AbortScopeExit"(i,Omega',delta)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"abort"
    ("freshcap" i:F@rho " in " e) !
    epsilon;Delta ▷ s;delta_o ⊣Omega_o$],
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
跨 scope。Normal与 abort gate都把 $Delta$ 及其中的 site/route/actual-summary
evidence作为一等 free-identity输入，不能只检查 erased $epsilon$。

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
- `"AttributedOK"(Delta_"res",s_"res")`，且 $s_"res"$ 精确保留 clause
  对其他 route/site产生的 suspension；
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

`DuplicableEnv` 判定完整 value summary，而不是只看 `capture`：若 type是
`ResumeTypeRefV2`/legacy Resume，则只有 `usage=Many` 且其 live provenance/
capture满足 multi-shot premise时才可能通过；`Once` 不能借 `Stable` 与
`NoCapture` 洗成 duplicable。serialized occurrence usage仍须与该 type quantity
一起检查。

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
  K; I; Phi; Omega @ Theta; S
  ⊢ e ⇒ A @[pi] ! epsilon;Delta ▷ s; delta; chi
  @ Theta' ⊣ Omega'
$

Checking：

$
  K; I; Phi; Omega @ Theta; S
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

$S$ 是显式 lexical prompt stack，并随 expression、args、abort、transfer、
body与 clauseBody judgment结构性线程化。后文为排版省略 `;S` 的 rule，
只表示所有 premises与 conclusion携带同一个未修改的 $S$；创建 delimiter的
rule必须显式写 `pushPrompt(S,p,a)`，创建 demand的 rule必须显式 fresh
lexical site slot并调用 `resolveRoute(S,a)`。`promptStack` 不是全局变量。

为保持长规则可读，后文旧式 `! ε ▷ ...` 只是一种排版缩写：它必须从该
rule的 typed subderivations/site constructors结构性计算唯一 $Delta$，并同时
证明 `ε=eraseDemand(Δ)`；它绝不表示“没有 Δ 字段”或允许事后用
side-effecting recorder修改全局状态。T-App、T-Operation、handler、resume/finalize
与 flow rules显式写出 $Delta$，因为这些正是 attribution发生变化的边界。

Checking rule：

#irule(
  [T-Check],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ e ⇒
      A' @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
    [$K;I ⊢ A' <: A$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ e ⇐
    A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
)

#irule(
  [T-Value],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ v ⇒ A @[pi] !
    emptyset;emptyset ▷
    "direct"("NoSuspend");delta_"pure";chi @Theta⊣Omega$],
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

Lambda只有下面这条 path-set rule是 normative；旧名称 T-Lambda 与
T-Lambda-Abort 在规则后定义为它的单一路径 projection，不再各自重新检查
body。这样带 terminal transfer 的具名函数仍可形成：

#irule(
  [T-Lambda-Paths],
  (
    [$eta_f=⟨A,B,Phi_f⟩ quad
      (pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$S_f " fresh symbolic Call-stage stack"$],
    [$Theta_x="bind"(Theta,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_f;Omega_"sym"@Theta_x;S_f ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon;Delta;s;delta ⊣Omega_b$],
    [$(Pi_c,chi_c,u,Lambda)="analyzeFlowClosure"(
      e,x,Theta,Omega_"sym",Omega_b,cal(F)_b,Delta)$],
    [$(r_f,hat(zeta),hat(R),Q)="AbstractParametricFlow"(
      S_f,pi_x,xi_x,cal(F)_b)$],
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
的一元 tuple elaboration使用同一 rule。$S_f$ 在 closure contract中抽象为
Call-stage route selectors，不捕获 lambda definition stack。
若 `flow(C)` 恰为 singleton `Returns`，其 scalar projection称为 T-Lambda；
若恰为 singleton `Aborts`，以 explicit bottom transition/result编码的
projection称为 T-Lambda-Abort。两者复用同一个 T-Lambda-Paths derivation、
$S_f$ 与 `ManyCallSafe` evidence，不存在第二条 ambient-context body premise。
$
  "T-Lambda" := "ProjectSingletonReturns"("T-Lambda-Paths")
  quad
  "T-Lambda-Abort" := "ProjectSingletonAborts"("T-Lambda-Paths")
$
`Omega_sym` 是 closure body的 symbolic usage环境；构造 closure不修改定义点
$Omega$。`freshRigidSummaryVars` 与 `AbstractParametricFlow` 对所有 admissible
argument summary、boundary/stability/outlives约束普遍抽象；T-App先 discharge
$Q$ 才能应用 result transformer。完全 abortive path不能借“不产生结果”
绕过这些约束。

后文 `$"body"_A(e) ⇓ cal(F)$` 是所有 expression都可使用的 normative
path judgment，不只用于 handler body。其 strict bind为：

$
  "PathBind"(cal(F),G)
  =
  "terminal"(cal(F))
  ∪ "unionPaths"({G(r) mid r in "returns"(cal(F))})
$

只有 `Returns` path进入 $G$；每个 `Aborts`/`Transfers` path连同
path-local usage/world/evidence原样保留。`AggregatePathEvidence` 只合并
实际执行 path的 $Delta/s/delta$，不把未执行 suffix加入 terminal prefix；
其输出必须满足 `AttributedOK(Δ,s)`。

#irule(
  [T-App],
  (
    [$C_f=⟨epsilon_f,zeta,"MayReturn",s_f,delta_f,Pi_f,chi_f,u_f,R_f,Phi_f,Q_f,Lambda_f⟩$],
    [$K;I;Phi;Omega@Theta_0;S ⊢ e_1 ⇒
      A arrow.r.long^(C_f) B @[pi_1] !
      epsilon_1;Delta_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$K;I;Phi;Omega_1@Theta_1;S ⊢ e_2 ⇐ A @[pi_2] !
      epsilon_2;Delta_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$"PhaseAllows"(Phi,Phi_f) quad "applyUsage"(Omega_2,u_f)=Omega_3$],
    [$"Discharge"("instantiate"("stageCall"(Q_f),pi_2,chi_2,I,Theta_2))$],
    [$zeta(Theta_2) = Theta_3$],
    [$R_f(pi_2,chi_2)=(pi_3,chi_3)$],
    [$(Delta_f,s_f',Lambda_"install")=
      "instantiateLatentContract"(
        epsilon_f,s_f,Lambda_f,pi_2,chi_2,Theta_2,S)$],
    [$"eraseDemand"(Delta_f)=
      "instantiateRow"(epsilon_f,pi_2,chi_2,Theta_2)
      quad "AttributedOK"(Delta_f,s_f')$],
    [$"PreserveUntilInstall"("stageHandlerInstall"(Q_f),Lambda_"install")$],
    [$cal(F)_f="instantiateFlow"("flow"(C_f),pi_2,chi_2,Theta_2)$],
    [$cal(F)_f={"Returns"(pi_3,chi_3,Theta_3)}$],
    [$Delta'=Delta_1∪Delta_2∪Delta_f
      quad epsilon'="eraseDemand"(Delta')$],
    [$s'=s_1⊔s_2⊔s_f'
      quad "AttributedOK"(Delta',s')$],
    [$"AttachFlowEvidence"("callNode",cal(F)_f)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ e_1(e_2) ⇒
    B @[pi_3] ! epsilon';Delta' ▷
    s';delta_1 ⊗ delta_2 ⊗ delta_f;chi_3
    @Theta_3⊣Omega_3$],
)

#irule(
  [T-App-Paths],
  (
    [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_(
      A arrow.r.long^C B)(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r_1 in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r_1)@"world"(r_1);S ⊢
      "body"_A(e_2) ⇓ cal(F)_2(r_1) !
      epsilon_2(r_1);Delta_2(r_1);s_2(r_1);delta_2(r_1)
      ⊣Omega_2(r_1)$],
    [$forall r_1,r_2.
      r_1 in "returns"(cal(F)_1) and
      r_2 in "returns"(cal(F)_2(r_1)) "implies"
      "InstantiateCallPath"(
        C,"summary"(r_2),I,S)
      ⇓ ⟨cal(F)_"call"(r_1,r_2),
        Delta_f(r_1,r_2),s_f(r_1,r_2),
        delta_f(r_1,r_2),Omega_f(r_1,r_2)⟩$],
    [$cal(F)_o="PathBind"(cal(F)_1,
      r_1 => "PathBind"(cal(F)_2(r_1),
        r_2 => cal(F)_"call"(r_1,r_2)))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_1,s_1,delta_1,
        {Delta_2,s_2,delta_2},
        {Delta_f,s_f,delta_f,Omega_f})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(B,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_B(e_1(e_2)) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`InstantiateCallPath` 对单个 successful callee/argument path执行
T-App中的 phase、usage、stageCall discharge、prompt-aware latent-site
instantiation与 HandlerInstall preservation，然后调用 `instantiateFlow`。
它必须通过同一个 `instantiateLatentContract(ε,s,Λ,...)` 成对产生
attributed demand、keyed suspension与 installation evidence，并证明
`eraseDemand(Δ)=instantiateRow(ε)` 及 `AttributedOK(Δ,s)`；禁止分别实例化
row、site与 suspension。
后者对每个 `Returns` entry应用 $hat(zeta)/hat(R)$，对每个
`Transfers(P)`独立实例化 $P$，并原样保留 `Aborts`；结果可以是
`{Aborts,Transfers(P₁),Transfers(P₂)}` 或同时含 normal return的任意有限
非空 set。T-App 是恰好一个 normal path时的 projection；所有 mixed/terminal
情况使用 T-App-Paths，不能靠多个互斥 single-tag rule猜测。

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

#irule(
  [T-Let-Paths],
  (
    [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_A(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r in "returns"(cal(F)_1).
      Theta_x(r)="bind"("world"(r),x:A
        @["provenance"(r)] ▷ "captures"(r))$],
    [$forall r in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r)@Theta_x(r);S ⊢ "body"_B(e_2) ⇓
      cal(F)_2(r) ! epsilon_2(r);Delta_2(r);s_2(r);delta_2(r)
      ⊣Omega_2(r)$],
    [$cal(F)_o="PathBind"(cal(F)_1,
      r => "dropFlowBinder"(cal(F)_2(r),x))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_1,s_1,delta_1,
        {Delta_2,s_2,delta_2,Omega_2})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_B(
    "let" x=e_1;e_2) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

T-Let 是 initializer与suffix都恰好一个 Returns path时的 projection。
Block 按 source order 对 expression list左折叠应用 T-Let-Paths/
T-Body-Sequence。
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
    may_suspend
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
     "OwnerBoundParking"(i)},
    Sigma_emptyset
  ]
$

其中 $R_"unit"()=("Stable",emptyset)$，
$Sigma_emptyset=⟨[], "direct"("NoSuspend"), delta_"pure"⟩$
表示没有 secondary site；
$Phi_"yield"(i)$ 要求当前 $Phi$ 持有 named clock authority $i$。
因此唯一结果是 row `{a}`、
`request(demandKey(d₀),MaySuspend)`、空 result capture以及
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
其中 $s_"secondary"$ 是以相同 stable site slot为 key的 suspension
template；实例化必须同时产生
$(Delta_"secondary",s_"secondary"')$ 并证明
`AttributedOK(Δsecondary,ssecondary')`，不能只实例化 row demand后把
suspension按 entry另算。
`TR₀` 的 `OperationSecondaryAnnotation` 只接受 closed row literal。
`ElabSecondaryRow(R, operationOrigin)` 因而能对 normalized closed row中的
每个 entry生成 finite synthetic site slot和 `AnyOperationOfEntry`
selector；若以后有更精确 summary可收紧为 exact operation selector。每个
synthetic site仍独立执行 route resolution，不能共享 primary prompt。
`! E` 与 `! {Audit,..E}` 作为 operation secondary annotation由 grammar/
validation拒绝；open secondary-row slot是未来 schema version的扩展，V1
不会默默丢弃 rigid tail。

#irule(
  [WF-Operation-Secondary-Closed],
  (
    [$K;I ⊢ R_"sec" ⇝ epsilon_"sec" ⊣ C_"sec"$],
    [$"ClosedRow"(epsilon_"sec")
      quad "NoRigidRowVars"(epsilon_"sec",C_"sec")$],
    [$"ElabSecondaryRow"(epsilon_"sec","operationOrigin")
      ⇓ ⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
  ),
  [$K;I ⊢_"op-secondary" R_"sec" ⇝
    "SecondarySiteSetV1"{
      "kind":"Closed","sites":Lambda_"sec"}
    ;hat(s)_"sec";delta_"sec"$],
)

没有 annotation时使用 `$R_"sec"={}$` 的同一 rule，而不是另一条省略
检查的捷径。`OperationDecl` 必须先通过这个 WF judgment，才能进入
$K(F,"op")$ signature table。
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
  K;I;Phi;Omega@Theta;S
  ⊢ bar(e) ⇐ bar(A)
  ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a@Theta_a⊣Omega_a
$

上式只是 all-return projection。Normative argument fold返回
`ArgsReturns(Ξ,Θ,Ω)` 与 terminal paths的 finite set：

#irule(
  [T-Args-Nil-Paths],
  ([$"emptyArgs"$],),
  [$K;I;Phi;Omega@Theta;S ⊢_"args" [] ⇓
    {"ArgsReturns"([],Theta,Omega)} !
    emptyset;emptyset;"direct"("NoSuspend");delta_"pure"$],
)

#irule(
  [T-Args-Cons-Paths],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$forall r in "returns"(cal(F)_e).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢_"args"
      bar(e) ⇐ bar(A) ⇓ cal(F)_"rest"(r) !
      epsilon_r(r);Delta_r(r);s_r(r);delta_r(r)$],
    [$cal(F)_o="PathBind"(cal(F)_e,
      r => "prependArgSummary"(
        "summary"(r),cal(F)_"rest"(r)))$],
    [$(Delta_o,s_o,delta_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_e,s_e,delta_e,
        {Delta_r,s_r,delta_r})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"args"
    (e,bar(e)) ⇐ (A,bar(A)) ⇓ cal(F)_o !
    epsilon_o;Delta_o;s_o;delta_o$],
)

`ArgsReturns.Ξ` 保留每个 actual argument的 type/nominal identity、
provenance/capture与 path-local world；abort/transfer path没有伪造的
argument vector，后续 operation dispatch不会执行。

以下 normal-returning rule只适用于 $m != "abort"$：

#irule(
  [T-Operation],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @[m,zeta,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$m != "abort"$],
    [$sigma = "freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @[m,zeta_sigma,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_sigma
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad p="resolveRoute"(S,a)
      quad zeta_a="instantiateReceiver"(zeta_sigma,a)$],
    [$zeta_a(Theta_a)=Theta'$],
    [$R_sigma(bar(pi_a),bar(chi_a))=(pi_B,chi_B)$],
    [$Xi_k="ActualSummaries"(
      bar(A)_sigma,bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_k^"call"="instantiate"(
      "stageCall"(P_sigma),Xi_k,I,Theta_a)
      quad "Discharge"(Q_k^"call")$],
    [$Q_k^"install"="instantiate"(
      "stageHandlerInstall"(P_sigma),Xi_k,I,Theta_a)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$(Delta_"sec",s_"sec")=
      "instantiateSecondaryContract"(
        Lambda_"sec",hat(s)_"sec",kappa,S)$],
    [$"AttributedOK"(Delta_"sec",s_"sec")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"("demandKey"(d_0),d_sigma) ⊔ s_"sec"
      quad "AttributedOK"(Delta_"call",s')$],
    [$"PhaseAllows"(Phi,Phi_sigma)$],
    [$"Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa,a,Q_k^"call",Q_k^"install",Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "op"[a]("op",bar(e)) ⇒
    B_sigma @[pi_B] ! epsilon_"call";Delta_"call" ▷
    s';delta_a⊗delta_"sec";chi_B @Theta'⊣Omega_a$],
)

`abort` operation 没有 successful $Theta'$。为避免用任意 world伪造正常
返回，另设 abortive flow judgment：

$
  K;I;Phi;Omega@Theta;S
  ⊢_"abort" e ! epsilon;Delta ▷ s;delta ⊣ Omega'
$

#irule(
  [T-Operation-Abort],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @["abort",bot,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$sigma="freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @["abort",bot,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_sigma
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad p="resolveRoute"(S,a)$],
    [$Xi_k="ActualSummaries"(
      bar(A)_sigma,bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_k^"call"="instantiate"(
      "stageCall"(P_sigma),Xi_k,I,Theta_a)
      quad "Discharge"(Q_k^"call")$],
    [$Q_k^"install"="instantiate"(
      "stageHandlerInstall"(P_sigma),Xi_k,I,Theta_a)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$(Delta_"sec",s_"sec")=
      "instantiateSecondaryContract"(
        Lambda_"sec",hat(s)_"sec",kappa,S)$],
    [$"AttributedOK"(Delta_"sec",s_"sec")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"("demandKey"(d_0),d_sigma) ⊔ s_"sec"
      quad "AttributedOK"(Delta_"call",s')$],
    [$"PhaseAllows"(Phi,Phi_sigma) quad "Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa,a,Q_k^"call",Q_k^"install",Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"abort"
    "op"[a]("op",bar(e)) !
    epsilon_"call";Delta_"call" ▷
    s';delta_a⊗delta_"sec" ⊣Omega_a$],
)

#irule(
  [T-Operation-Paths],
  (
    [$K(F,"op")=O quad
      sigma="freshInstantiation"("typeParams"(O))
      quad B_sigma="result"(sigma(O))$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad o="resolvedOperation"(F,"op")$],
    [$K;I;Phi;Omega@Theta;S ⊢_"args"
      bar(e) ⇐ "params"(sigma(O)) ⇓ cal(F)_"args" !
      epsilon_a;Delta_a;s_a;delta_a$],
    [$forall r in "argReturns"(cal(F)_"args").
      "BuildOperationPath"(
        kappa,a,o,sigma(O),"summaryVector"(r),"world"(r),
        "usage"(r),I,S)
      ⇓ ⟨cal(F)_"op"(r),Delta_"op"(r),
        s_"op"(r),delta_"op"(r)⟩$],
    [$cal(F)_o="terminal"(cal(F)_"args") ∪
      "unionPaths"({cal(F)_"op"(r) mid
        r in "argReturns"(cal(F)_"args")})$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_a,s_a,delta_a,
        {Delta_"op",s_"op",delta_"op"})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(B_sigma,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_(B_sigma)(
    "op"[a]("op",bar(e))) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`BuildOperationPath` 是 T-Operation/T-Operation-Abort 对一个完整
`ArgsReturns` path的共同 suffix：它建立 primary/secondary demand与
suspension、执行 phase/Allowed检查、附加 site obligations，并按 mode产生
`Returns` 或 `Aborts`。两条 single-flow rule只是这个 judgment在 arguments
没有 side path时的 projection。$kappa/a/o$ 在 argument PathBind外固定；
所有 returning paths共享同一个 alpha-normalized lexical site slot，同时
仍以 exact receiver entry区分 named与anonymous demand。每个 builder还以
该 path的 actual summaries/world和 $I$ 实例化并 discharge
`stageCall(Pσ)`；site保存已验证的 call evidence/ids，并保留使用同一
actual环境实例化但尚未 discharge 的 `stageHandlerInstall(Pσ)`。

Kernel forwarding只允许在正在处理的 primary site内使用。令当前
$kappa$ 携带 route $p$：

#irule(
  [T-Forward-Delegate],
  (
    [$kappa=⟨ell,p,a,o,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$"CurrentDisposition"(k,kappa)
      quad Omega(k)="Open"(q)$],
    [$"StrictOuterPrompt"(S,p,p_"outer",a)$],
    [$"TailOnly"("forward"[p_"outer"](a,o,bar(e)))$],
    [$O_k=(bar(A)_k)->B_k
      @[m,zeta_k,d_k,R_k,Phi_k,P_k,Sigma_k]$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_k
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$Omega_a(k)="Open"(q_a)$],
    [$Xi_f="ActualSummaries"(
      "params"(O_k),bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_f^"call"="instantiate"(
      "stageCall"(P_k),Xi_f,I,Theta_a)
      quad "Discharge"(Q_f^"call")$],
    [$Q_f^"install"="instantiate"(
      "stageHandlerInstall"(P_k),Xi_f,I,Theta_a)$],
    [$h_f="ForwardSiteHeader"(
      "stableSiteSlot":ell,
      "installationPrompt":p_"outer",
      "entry":a,"operation":o,
      "continuation":"continuation"(kappa),
      "entryWorld":Theta_a,
      "actualArgumentSummaries":Xi_f,
      "instantiatedSignature":O_k,
      "callObligations":Q_f^"call",
      "installObligations":Q_f^"install")$],
    [$(Delta_"sec",s_"sec",delta_"sec",Sigma_f)=
      "instantiateSecondaryContract"(
        Sigma_k,h_f,S)$],
    [$kappa_f="SealForwardSite"(
      h_f,"secondarySites":Sigma_f)$],
    [$d_f="Demand"("siteSlot"(kappa_f),p_"outer",a,o,"Primary")
      quad s_"primary"="request"("demandKey"(d_f),d_k)$],
    [$Delta_o=Delta_a∪{d_f}∪Delta_"sec"
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$s_o=s_a⊔s_"primary"⊔s_"sec"
      quad "AttributedOK"(Delta_o,s_o)$],
    [$"PhaseAllows"(Phi,Phi_k)
      quad "Allowed"(Phi,epsilon_o,s_o,delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa_f,a,Q_f^"call",Q_f^"install",
      Sigma_f)$],
    [$Omega_f=Omega_a[k↦"Forwarded"(kappa_f)]$],
    [$e_f="SealForwardDispositionEvidence"(
      k,kappa,kappa_f,Omega_a,Omega_f)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "clauseBody"_X(
    "forward"[p_"outer"](a,o,bar(e))) ⇓
    {"Delegates"(kappa_f,e_f)} ! epsilon_o;Delta_o;
    s_o;delta_a⊗delta_"sec" ⊣Omega_f$],
)

#irule(
  [T-Forward-Paths],
  (
    [$kappa=⟨ell,p,a,o,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$O_k="instantiatedSignature"(kappa)
      quad B_k="result"(O_k)
      quad "CurrentDisposition"(k,kappa)
      quad Omega(k)="Open"(q)$],
    [$"StrictOuterPrompt"(S,p,p_"outer",a)$],
    [$"TailOnly"("forward"[p_"outer"](a,o,bar(e)))$],
    [$K;I;Phi;Omega@Theta;S ⊢_"args"
      bar(e) ⇐ "params"(O_k) ⇓ cal(F)_"args" !
      epsilon_a;Delta_a;s_a;delta_a$],
    [$forall r in "argReturns"(cal(F)_"args").
      "usage"(r)(k)="Open"(q_r) and
      "BuildForwardPath"(
        k,kappa,p_"outer",O_k,
        "summaryVector"(r),"world"(r),"usage"(r),S)
      ⇓ ⟨cal(F)_f(r),kappa_f(r),
        Delta_f(r),s_f(r),delta_f(r),Omega_f(r)⟩$],
    [$cal(F)_o="terminal"(cal(F)_"args") ∪
      "unionPaths"({cal(F)_f(r) mid
        r in "argReturns"(cal(F)_"args")})$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_a,s_a,delta_a,
        {Delta_f,s_f,delta_f,Omega_f})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "ForwardSites"(cal(F)_o)={kappa_f(r)}$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "clauseBody"_(B_k)(
    "forward"[p_"outer"](a,o,bar(e))) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`StrictOuterPrompt(S,p,pouter,a)` 要求两个 prompt都 live、`pouter` 在 stack
中严格位于 $p$ 外层且仍处理精确 entry $a$；family相同不够。Source
没有任意 prompt操作，这两个 rule只服务 resolver生成的 Kernel forward。
`ForwardSiteHeader` 保留 lexical `siteSlot(κ)` 作为 stable slot；
secondary重新路由后，`SealForwardSite` 创建完整 routed contract
$kappa_f$：它的 installation prompt 是 $p_"outer"$，
entry world与 actual summaries来自本次 transformed arguments；它严格复用
原 site已经实例化的 exact $O_k$（包括同一次 invocation的 type arguments），
再以新 summaries 重建分阶段的 call/install evidence。Forward绝不对
`K(F,o)` 或 $O_k$ 执行 fresh instantiation，因此 nullary polymorphic
operation也不能在 reroute时换 type arguments。secondary site以
header为 parent重新路由；它不沿用 inner prompt或旧 $Xi_k$，最终 exact
`SecondarySiteSetV1` 封入 `κf.secondary_sites`。side evidence只能由
该 sealed field投影，不能成为缺字段的第二来源。

Forward 采用 delegation 语义，不是普通 returning subcall：
$kappa_f$ 唯一取得原 $D_k$ 的处置权，flow产生 terminal
`Delegates(κf,ef)`（正文省略 evidence参数时仍指该 pair），且原 token由
`Open(q)` 原子转换为 `Forwarded(κf)`。
`DispositionComplete` 把 `Forwarded` 视为已经完整处置；inner clause随后
不能再次 resume、finalize或 park。`BuildForwardPath` 执行同一原子转移；
argument evaluation产生 mixed flow时，T-Forward-Paths保留每条 terminal
argument path，并只在该 path-local usage仍为 `Open(q)` 时把
`ArgsReturns` path原子变成 `Delegates`。argument自身已经 finalize、park
或 forward当前 $k$ 的 returning path因此没有推导。

Algorithmic `CheckResult.flow` 因而是这些 outcome 的有限 path set。
Abortive flow可以在 expected type下使用，但不产生 normal output world；
sequence只把 `Returns` entries送入 suffix，并保留既有
`Aborts/Transfers/Delegates` entries；branch join取 set union并只对 Returns projection
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
  [T-Ctx-Paths],
  (
    [$"Prefix"(E_s,Theta,Omega)=
      ⟨Theta_h,Omega_h,Delta_p,s_p,delta_p⟩$],
    [$K;I;Phi;Omega_h@Theta_h;S ⊢ "body"_X(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$forall r in "returns"(cal(F)_e).
      "FrameStep"(E_s,r,S) ⇓
      cal(F)_"frame"(r) !
      Delta_"frame"(r);s_"frame"(r);delta_"frame"(r)
      ⊣Omega_"frame"(r)$],
    [$cal(F)_"hole"="attachPrefix"(
      cal(F)_e,Delta_p,s_p,delta_p)$],
    [$cal(F)_o="PathBind"(cal(F)_"hole",
      r => cal(F)_"frame"(r))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_p,s_p,delta_p,
        Delta_e,s_e,delta_e,
        {Delta_"frame",s_"frame",
          delta_"frame",Omega_"frame"})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(A,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(E_s[e]) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`FrameStep` 是把某个 `Returns` path的 value/world/usage/evidence填回
strict frame后，对尚未执行的 callee/argument、`let` suffix或 argument
suffix继续使用同一 path judgment；`attachPrefix` 则把 hole之前已经执行的
evidence附到每条 hole path。于是一个 hole可以同时返回
`Returns`、`Aborts` 与多个 `Transfers(P)`；只有 `Returns` 进入 frame，
每个 terminal path都跳过 hole之后的 suffix。旧的 T-Ctx-Abort 与
T-Ctx-Transfer 都只是本 rule 的 singleton projection，不是独立的
single-tag congruence。Core `resume(k,v)` 保持 value operand；surface
`resume(k,e)` 先 ANF 成 `let x=e; resume(k,x)`，所以 argument abort由
initializer context传播。到最近 delimiter 后改由 T-Handle 的 path-aware
body judgment处理。

== Handler type

Core handler value：

$
  "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
$

含义：

- handler action 属于 Owner region $rho_h$；
- handled computation 正常返回 $A$；
- handler action 返回 $B$；
- clause 自身可能产生 residual row $epsilon_h$；
- $(S_i,p_i,a_i).C_h$ 保存对 actual installation stack、prompt与精确
  handled entry抽象的 mode、site constraints、
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
  ⟨ell_k,p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
    Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩
$

$ell_k$ 是 alpha-normalized stable lexical site slot；reroute时保留它但不把
旧 prompt或旧实例化环境当作新 contract。
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
$O_k$ 是该 site 的 freshly instantiated operation signature；
$Q_k^"call"/Q_k^"install"$ 分别保存已在 call stage discharge的证据与仍需
installation delimiter discharge的 obligations。$F_k=⟨epsilon_k^"fin",
Delta_k^"fin",zeta_k^"fin",s_k^"fin",delta_k^"fin"⟩$
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
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩ quad Theta_"entry" " fresh symbolic"$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$(pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x="bind"(Theta_h,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_h;Omega_"sym"@Theta_x;S_i ⊢
      "body"_B(e) ⇓ cal(F)_r !
      epsilon_r;Delta_r;s_r;delta_r ⊣Omega_r$],
    [$cal(F)_o="dropReturnBinder"(cal(F)_r,x)$],
    [$"AbstractReturnContract"(
      S_i,p_i,a_i,Theta_"entry",pi_x,xi_x,
      cal(F)_o,epsilon_r,Delta_r,s_r,delta_r) ⇓ C_"ret"$],
  ),
  [$"ReturnClauseOK"(
    K,I,Phi_h,H_h,S_i,p_i,a_i,"return"(x:A,e),A) ⇓ C_"ret"$],
)

这里及以下的 `SchemaRouteStage(Si)` 是为 handler clause构造的 nested
typing context字段，不是定义 handler value的外层 route stage，也不由
$S_i$ 推断；它必须恰为 `HandlerInstall`。因此
`TopPrompt(Si)=⟨pi,ai⟩` 把 symbolic installation stack、该 stage所解析的
prompt与 handled entry连成同一组参数，body中的所有 residual route都在
`;Si` 下检查。
`AbstractReturnContract` 对 rigid input summary与 symbolic
$Theta_"entry"$ 普遍抽象出 world/result transformer及 constraints；它不把
handler定义点 lock写进 contract。

#irule(
  [T-Handler],
  (
    [$"PartitionClauses"(F,bar(c)) ⇓ (c_"ret",M_"op")$],
    [$"dom"(M_"op")="ops"(F) quad "ExactAndUnique"(M_"op")$],
    [$"CurrentOwner"(Phi)=rho_h
      quad K ⊢ rho_h:"OwnerRegion"
      quad "OwnerAuthorized"(Phi,rho_h)$],
    [$chi_h="captureFV"(bar(c),Theta) quad Pi_h="provenanceFV"(bar(c),Theta)$],
    [$"EnvBoundarySafe"("fv"(bar(c)),Theta,"OwnerStorage"(rho_h))$],
    [$Phi_h " fresh symbolic"$],
    [$S_i,p_i,a_i " fresh symbolic installation parameters"$],
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩$],
    [$"ReturnClauseOK"(
      K,I,Phi_h,H_h,S_i,p_i,a_i,c_"ret",A) ⇓ C_"ret"$],
    [$M_h="checkClauseSchemas"(
      K,I,Phi_h,H_h,S_i,p_i,a_i,F,M_"op")$],
    [$forall O in "ops"(F). "ClauseSchemaOK"(O,M_h(O),H_h)$],
    [$"AggregateHandler"(C_"ret",M_h)=(Delta_h,C_0)
      quad epsilon_h="eraseDemand"(Delta_h)$],
    [$Phi_"req"="SolveHandlerPhase"(Phi_h,C_"ret",M_h)$],
    [$C_1="setRequiredPhase"(C_0,Phi_"req")$],
    [$"PolicyOK"(P_h) quad "Origin"(P_h)=rho_h$],
    [$C_h="attachHandlerEnv"(C_1,Pi_h,chi_h)$],
    [$"returnContract"(C_h)=C_"ret" quad "clauseSummaries"(C_h)=M_h$],
  ),
  [$K;I;Phi@Theta ⊢_v "handler"[F]{bar(c)} ⇒
    "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
    @["Owner"(rho_h)] ▷ chi_h$],
)

输入 T-Handler 前，Surface normalization 已为省略的 return 合成 identity
clause；显式写多个 return 仍是错误。`PartitionClauses` 同时保证恰好一个
return clause、每个
$O in "ops"(F)$ 恰好一个 operation clause，且没有 duplicate或 extra
clause。`ReturnClauseOK` 对具体 $c_"ret"$ 的 parameter、body type、row、
attributed demand/suspension、semantic summary、world transformer、result
transformer与 required invocation phase完整检查，产生
$C_"ret"=⟨epsilon_"ret",Delta_"ret",w_"ret",s_"ret",delta_"ret",
R_"ret",Phi_"ret"⟩$。它和 operation clause都在 fresh symbolic
$Theta_"entry"$ 下检查，并通过 $H_h$ 导入经过 boundary check的 definition
environment；定义点 $Theta$ 本身不进入 clause world。两者的 nested route
context都固定 `SchemaRouteStage(Si)=HandlerInstall`，并使用满足
`TopPrompt(Si)=⟨pi,ai⟩` 的 symbolic installation stack：
命中 $a_i$ 才选择 $p_i$，其余 residual demand保留
`ResolveAtInstallation`，不得读取 handler definition stack。
`checkClauseSchemas` 返回以 operation entry为键的
finite schema map $M_h$；`AggregateHandler` 把具体 return contract与这些
schema的 residual attributed demand、suspension、summary、path-specific result
transformer和 required phase逐项合并。它保留各 path，而不把 operation
clause伪装成 return clause。
因此 conclusion 中的 $epsilon_h$、$(S_i,p_i,a_i).C_h$ 都由已检查
clause决定，而不是
游离的 annotation。$Pi_h$ 进入 handler construction evidence；
`EnvBoundarySafe` 成立后才允许把 value自身 provenance记为
`Owner(ρ_h)`。这里 $rho_h$ 由 `CurrentOwner(Φ)` 与显式 authority premise
唯一绑定，不能由 rule conclusion凭空生成。`attachHandlerEnv` 把
$Pi_h/chi_h$ 封入 $C_h$ 的 sealed
construction evidence并序列化到 interface；所以 handler经变量或模块传递
后，`InstallOK` 仍可由 `handlerEnv(C_h)` 取得它们。

Handler value只保存以 installation stack、prompt与 exact entry参数化的
template；它没有 definition-site concrete route。每次 `with` installation
由 actual $(S_p,p,a)$ 实例化一次，所以同一个 handler value嵌套安装会得到
各自的 residual route，site/secondary demand不会混层。

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
对 $Theta_"entry"$、operation skolems、完整 symbolic installation
$(S_i,p_i,a_i)$ 和 $kappa$ 普遍量化，且
`TopPrompt(Si)=⟨pi,ai⟩` 且 route stage固定为 `HandlerInstall`；
`AdmissibleSite` 必须证明
`route(κ)=pi`、`entry(κ)=ai`，不能只按
handler value或 family匹配。

#irule(
  [T-Clause-Once-Ctl],
  (
    [$m_h in {"once","ctl"} quad q_"once"=1 quad q_"ctl"=omega$],
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad "AdmissibleSite"(kappa,O_k,H_h)$],
    [$"clauseMode"=m_h quad m_h <= "mode"(O_k)$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):"params"(O_k),Xi_k)$],
    [$k:"Resume"[q_(m_h),D_k,"result"(O_k),B,Pi_k,chi_k,rho_h]$],
    [$b_k="BindClauseDisposition"(k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega[k↦"Open"(q_(m_h))]@Theta_k;S_i ⊢
      "clauseBody"_B(e) ⇓ cal(F)_c !
      epsilon_c;Delta_c;s_c;delta_c ⊣Omega_c$],
    [$"PathUsage"(cal(F)_c,k) <= q_(m_h)$],
    [$"DispositionComplete"(m_h,k,cal(F)_c,Omega_c) ⇓ cal(F)_d$],
    [$"ExtractClauseContract"(cal(F)_d,Delta_c,Xi_k,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "resumptiveClause"(O,m_h,e) ⇓
    "ResumeSchema"(kappa,b_k,H_c)$],
)

`DispositionComplete` 对 `once` 的每个 exit插入/验证 resume、finalize或显式
Owner-bound park/Kernel delegation恰好一个。`Delegates(κf)` path必须且只
能对应 `Ω(k)=Forwarded(κf)`；其他 path不得携带该 state。对 `ctl` 可有多次
resume，但 exit前必须以 finalize或唯一 delegation结束，T-Park不接受
`Resume[ω,…]`。`Closed`、`Transferred`、`Forwarded` 都没有后继 disposition
transition。插入动作的 row、suspension、summary与 usage都进入 $f_d$。

#irule(
  [T-Clause-Fun],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad O_k=(bar(A)_k)->R_k^o
      @[m,zeta_k,d_k,R_k^"op",Phi_k^"op",P_k,Sigma_k]$],
    [$"AdmissibleSite"(kappa,O_k,H_h)$],
    [$"clauseMode"="fun" quad "fun" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_k,Xi_k)$],
    [$k:"Resume"[1,D_k,R_k^o,B,Pi_k,chi_k,rho_h]$],
    [$b_k="BindClauseDisposition"(k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega,k:"Open"(1)@Theta_k;S_i ⊢
      e ⇐ R_k^o @[pi_R] ! epsilon_e;Delta_e ▷
      s_e;delta_e;chi_R @Theta_R⊣Omega_R$],
    [$Theta_y="bind"(Theta_R,y:R_k^o @[pi_R] ▷ chi_R)$],
    [$K;I;Phi_h;Omega_R@Theta_y;S_i ⊢
      "resume"(k,y) ⇒ B @[pi_B] ! epsilon_k;Delta_k ▷
      s_k;delta_k ⊗ delta_"resume";chi_B @Theta_r⊣Omega'$],
    [$"dropBinder"(Theta_r,y)=Theta_"answer"$],
    [$"TailOnly"("let" y=e;"resume"(k,y)) quad Omega'(k)="Closed"$],
    [$"ExtractClauseContract"(
      "typedFunPath",Xi_k,pi_B,chi_B,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "funClause"(O,e) ⇓ "FunSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Abort],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad O_k=(bar(A)_k)->R_k^o
      @[m,zeta_k,d_k,R_k^"op",Phi_k^"op",P_k,Sigma_k]$],
    [$"AdmissibleSite"(kappa,O_k,H_h)$],
    [$F_k=⟨epsilon_f,Delta_f,zeta_f,s_f,delta_f⟩$],
    [$"clauseMode"="abort" quad "abort" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_k,Xi_k)$],
    [$k_kappa:"Resume"[1,D_k,R_k^o,B,Pi_k,chi_k,rho_h] quad Omega_k=Omega[k_kappa↦"Open"(1)]$],
    [$b_k="BindClauseDisposition"(
      k_kappa,kappa,"type"(k_kappa))$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      e ⇐ B @[pi_B] ! epsilon_e;Delta_e ▷
      s_e;delta_e;chi_B @Theta_B⊣Omega_B$],
    [$Theta_y="bind"(Theta_B,y:B @[pi_B] ▷ chi_B)$],
    [$K;I;Phi_h;Omega_B@Theta_y;S_i ⊢
      "finalize"(k_kappa) ⇒ "Unit" @["Stable"] !
      epsilon_f;Delta_f ▷ s_f;delta_f ⊗ delta_"finalize";
      emptyset @Theta_f⊣Omega'$],
    [$K;I;Phi_h@Theta_f ⊢_v y ⇒ B @[pi_o] ▷ chi_o$],
    [$"dropBinder"(Theta_f,y)=Theta_"answer" quad Omega'(k_kappa)="Closed"$],
    [$"ExtractClauseContract"(
      "typedAbortPath",Xi_k,pi_o,chi_o,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "abortClause"(O,e) ⇓ "AbortSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Fun-Paths],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"PrepareClauseSite"(S_i,p_i,a_i,kappa,O,H_h,"fun") ⇓
      ⟨Theta_k,k,D_k,R_sigma,B,Omega_k,b_k⟩$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      "clauseBody"_(R_sigma)(e) ⇓ cal(F)_e !
      epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$cal(F)_r="TailResumeReturns"(
      cal(F)_e,k,D_k,R_sigma,B)$],
    [$"DispositionComplete"(
      "fun",k,cal(F)_r,Omega_e) ⇓ cal(F)_d$],
    [$"ExtractClauseContract"(
      cal(F)_d,Delta_e,"actualArguments"(kappa),b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "funClausePaths"(O,e) ⇓ "FunSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Abort-Paths],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"PrepareClauseSite"(S_i,p_i,a_i,kappa,O,H_h,"abort") ⇓
      ⟨Theta_k,k,D_k,R_sigma,B,Omega_k,b_k⟩$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      "clauseBody"_B(e) ⇓ cal(F)_e !
      epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$cal(F)_f="FinalizeReturnPaths"(
      cal(F)_e,k,"cleanup"(D_k),B)$],
    [$"AbortScopeExitOnTerminalPaths"(
      cal(F)_f,k,D_k,Omega_e) ⇓ cal(F)_d$],
    [$"DispositionComplete"(
      "abort",k,cal(F)_d,"usage"(cal(F)_d))$],
    [$"ExtractClauseContract"(
      cal(F)_d,Delta_e,"actualArguments"(kappa),b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "abortClausePaths"(O,e) ⇓ "AbortSchema"(kappa,b_k,H_c)$],
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
`BindClauseDisposition(k,κ,type(k))` 为这个 clause schema建立唯一
$b_k$：它把 internal resumption/discard token $k$ alpha-normalize成
`ClauseDispositionBinderV2`，记录原 `κ.site_slot` 与完整
`ResumeTypeRefV2 { value: ResumeTypeV2 }`，
并让同一个 clause flow内每个 `Delegates` 的 `inner_disposition` 只能引用
该 binder。$b_k$ 的 scope不越过所属 `ClauseComputationV2`，也不能从
$D_k$、continuation或 live bindings重建。
`PrepareClauseSite` 只是 T-Clause-Fun/Abort共同的 site admissibility、
exact stored $O_k$ signature、environment/argument bind与 `Open(1)`
premises以及同一 $b_k$ declaration的排版缩写；它不重新实例化 operation
type arguments。
`TailResumeReturns` 只给每个 Returns path追加 hidden tail resume；
`FinalizeReturnPaths` 只给每个 Returns path追加 hidden finalize/return；
两者都保留 abort/transfer/delegate side paths，并由
`DispositionComplete`/`AbortScopeExitOnTerminalPaths`逐 path完成 disposition。
因此上面两条 path rule是 normative，旧 T-Clause-Fun/Abort只是恰好一个
Returns path时的投影。

若任一 clause body path在产生 normal answer前 abort，runner delimiter
必须先收回该 path拥有的 disposition：

#irule(
  [T-Clause-Path-Abort],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"route"(kappa)=p_i quad "entry"(kappa)=a_i
      quad "suffix"(kappa)=D_k$],
    [$k:"Resume"[q,D_k,A_k,B,Pi_k,chi_k,rho_h] quad Omega(k)="Open"(q)$],
    [$"ExistingClauseDisposition"(
      b_k,k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega@Theta_k;S_i ⊢_"abort" e !
      epsilon_e;Delta_e ▷ s_e;delta_e ⊣Omega_e$],
    [$(Omega_o,delta_o)="AbortClauseScopeExit"(k,D_k,Omega_e,delta_e)$],
    [$"NoOpenDisposition"(k,Omega_o)$],
    [$"ExtractAbortPathContract"(
      epsilon_e,Delta_e,s_e,delta_o,b_k) ⇓ H_a$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "clauseAbortPath"(kappa,k,b_k,e) ⇓ "Aborts"(H_a,Omega_o)$],
)

Clause schema对 normal rules与 T-Clause-Path-Abort 的 reachable path做有限
join；all-abort schema没有 $R_h$ normal branch，但仍保留 residual row、
suspension、semantic summary与 cleanup evidence。该 rule同样覆盖
`fun` argument计算、`once/ctl` clause body以及 hidden abort-clause
disposition的 abortive path。这里的 $b_k$ 是 enclosing clause schema已经
建立的同一 binder；`ExistingClauseDisposition` 逐字段匹配 enclosing
`BindClauseDisposition` 的结果并禁止为 abort path另建 slot。
因此该 path在 `;Si` 与固定 HandlerInstall stage下产生的 residual route、
cleanup以及 disposition evidence都并入同一个 `ClauseComputationV2`；
其 `InvokeV2` 只从 enclosing `HandlerContractV2.applications` ledger解析。

Handled body使用 path-set辅助 judgment：

$
  t ::= "Aborts"
    | "Returns"(pi,chi,Theta)
    | "Transfers"("ParkContractV2")
  quad
  cal(F) ::= {t_1,...,t_n}
$

$cal(F)$ 是 reachable outcomes 的有限非空集合，不是单一 tag；因此同一
branching computation可以同时保存 `Returns`、`Aborts` 与一个或多个
`Transfers(ParkContractV2)`。Normal return entries只有在 result type兼容且
world可 join时合并；transfer contract不能被 join成 abort。

$
  K;I;Phi;Omega@Theta;S
  ⊢ "body"_A(e) ⇓ cal(F) ! epsilon;Delta;s;delta
  ⊣ Omega'
$

它要求所有 normal path返回 $A$ 并 join其 provenance/capture/world；
完全 abortive body得到 `${Aborts}`。`Transfers(ParkContractV2)` 是经过
T-Park验证的 terminal ownership transfer，不是 `Unit` result，也不能进入
sequence 的 suffix。三类 flow都保留 typed Core、operation sites、row、
suspension、summary 与 attributed demand。$S$ 与 typing context中的 route
stage在所有 body premises/conclusions间原样线程；普通 checking使用 `Call`，
handler clause由 enclosing premise固定为 `HandlerInstall`。

Clause checking使用严格扩展而不扩大 public flow：

$
  t_c ::= t | "Delegates"("ForwardContract")
  quad cal(F)_c ::= {t_(c_1),...,t_(c_n)}
$

`clauseBody` 复用以下 return/abort/transfer/branch/sequence规则，并额外允许
T-Forward-Delegate/T-Forward-Paths。`Delegates` 只能出现在 handler schema
内部；它携带 `Forwarded(κf)` disposition evidence，不能进入
`FunctionContractV2.computation` 的 public path set。

#irule(
  [T-Body-Return],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ e ⇐ A @[pi] !
      epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Returns"(pi,chi,Theta')} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Abort],
  (
    [$K;I;Phi;Omega@Theta;S ⊢_"abort" e !
      epsilon;Delta ▷ s;delta ⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Aborts"} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Transfer],
  (
    [$K;I;Phi;Omega@Theta;S ⊢_"transfer" e ⇓
      "Transfers"(P) ! epsilon;Delta ▷ s;delta @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Transfers"(P)} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Branch],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_"Bool"(c) ⇓
      cal(F)_c ! epsilon_c;Delta_c;s_c;delta_c ⊣Omega_c$],
    [$forall r in "returns"(cal(F)_c).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢ "body"_A(e_1) ⇓
      cal(F)_1(r) ! epsilon_1(r);Delta_1(r);
      s_1(r);delta_1(r) ⊣Omega_1(r)$],
    [$forall r in "returns"(cal(F)_c).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢ "body"_A(e_2) ⇓
      cal(F)_2(r) ! epsilon_2(r);Delta_2(r);
      s_2(r);delta_2(r) ⊣Omega_2(r)$],
    [$cal(F)_b(r)=cal(F)_1(r)∪cal(F)_2(r)
      quad cal(F)_o="PathBind"(cal(F)_c,
        r => cal(F)_b(r))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_c,s_c,delta_c,
        {Delta_1,s_1,delta_1,Omega_1},
        {Delta_2,s_2,delta_2,Omega_2})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(
    "if" c {e_1} "else" {e_2}) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

#irule(
  [T-Body-Sequence],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_X(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢
      "body"_A(e_2) ⇓ cal(F)_2(r) !
      epsilon_2(r);Delta_2(r);s_2(r);delta_2(r)
      ⊣Omega_2(r)$],
    [$cal(F)_o=
      "terminal"(cal(F)_1) ∪
      "unionPaths"({cal(F)_2(r) mid
        r in "returns"(cal(F)_1)})$],
    [$Delta_o=Delta_1∪
      "unionDemand"({Delta_2(r) mid
        r in "returns"(cal(F)_1)})
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$Omega_o="joinPathUsage"(
      "terminalUsage"(cal(F)_1),
      {Omega_2(r) mid r in "returns"(cal(F)_1)})$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e_1;e_2) ⇓
    cal(F)_o ! epsilon_o;Delta_o;
    s_1⊔"joinSusp"({s_2(r) mid r in "returns"(cal(F)_1)});
    delta_1⊗"joinSummary"(
      {delta_2(r) mid r in "returns"(cal(F)_1)})
    ⊣Omega_o$],
)

`T-Body-Branch` 对任意 finite path set取 union；`T-Body-Sequence` 只把
`Returns` entries送入 suffix，并原样保留 prefix 的 `Aborts`、多个
`Transfers(P)` 以及 clause-internal `Delegates(κf)` 与它们的 path-local
usage evidence。若 prefix没有
Returns，indexed union为空且 suffix完全不检查。这样 operation clause中的
`park`通过 T-Body-Transfer进入 clause schema，再经 handler congruence向外
传播，不会被错误重标为 abort。

Handler installation是一个有输出的 judgment：

$
  E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩
  quad
  "InstallOK"(S,p,h,P_h,a,bar(kappa),E_e,C_h)
  ⇓ E_i
$

`InstallOK` 不产生新的自由 demand output；它验证并 path-map body/schema，
唯一 demand输入仍是 $Delta_e$。sealed $E_i$ 同时保存
`publicFlow(E_i)`、`semanticSummary(E_i)` 与
`handlerResidual(E_i)`；最后一项由实际
$(C_h,p,S,bar(kappa),E_e)$（包括 Forward contract/evidence）唯一构造，
不能只凭抽象 template和 prompt恢复。
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
`Transfers(ParkContractV2)` 并验证该 installation不窃取 disposition。它同时
要求所有 normal exit产生可 join 的输出 $Theta_o$；没有 normal exit时
set中仍保留 abort/transfer而不是压成 `NoReturn`。Clause可以通过 full $w_k$ resume到该 world，
也可执行等价 sealed transition；无 resume 的 abort path若 normal return
却没有该 world evidence，就失败。`RequiresTickWitness`、
`OwnerBoundParking` 等 $P_o$ obligation也在这里 discharge。

若被选择的 clause schema含 `Delegates(κf)`，`InstallOK` 必须在 public
输出前消费它：验证 clause schema已经把 $kappa_f$ 的 primary/secondary
demand与 site evidence写入本次 sealed install evidence 的
`handlerResidual(E_i)`，并以其唯一持有的原 $D_k$
中 public continuation flow替换该 internal path。outer handler之后
resume时只消费 $kappa_f$ 拥有的
同一个 disposition；inner token已经是 `Forwarded(κf)`，不能再次处置。
因此 `Delegates` 不会出现在 $cal(F)_o$ 或跨模块 `FlowSetV2`，同时 forwarding
也不会被误压成 abort/no-return。

== Anonymous handling

#irule(
  [T-Handle-Anon-Paths],
  (
    [$K;I;Phi@Theta ⊢_v h ⇒
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$a="Anon"(F) quad p ∉ "prompts"(S)$],
    [$S_p="pushPrompt"(S,p,a)$],
    [$K;I;Phi;Omega@Theta;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I;Phi@Theta;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$C_i=C_h[S_i,p_i,a_i:=S_p,p,a]$],
    [$"InstallOK"(S_p,p,h,P_h,a,bar(kappa),E_e,C_i)
      ⇓ E_i$],
    [$cal(F)_o="publicFlow"(E_i)
      quad delta_o="semanticSummary"(E_i)$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi,"requiredPhase"(C_i))$],
    [$"RowSplit"(Delta_e,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$"AttributedOK"(Delta_e,s_e)$],
    [$Delta_h="handlerResidual"(E_i)$],
    [$Delta_o=Delta_"out"∪Delta_h
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$s_o="handleInstallSusp"(s_e,Delta_"here",E_i)
      quad "AttributedOK"(Delta_o,s_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
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
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$"HandlerOriginOK"(Phi,rho_h) quad i ∉ "dom"(I)
      quad p ∉ "prompts"(S)$],
    [$a="Named"(i,F) quad I'=I,i:F@rho_h quad Phi_i="addAuthority"(Phi,a)$],
    [$x_"cap" " fresh" quad
      Theta_i="bind"(Theta,x_"cap":"Cap"[i,F]
        @["Region"(rho_h)] ▷ {i})$],
    [$S_p="pushPrompt"(S,p,a)$],
    [$K;I';Phi_i;Omega@Theta_i;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I';Phi_i@Theta_i;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$C_i=C_h[S_i,p_i,a_i:=S_p,p,a]$],
    [$"InstallOK"(S_p,p,h,P_h,a,bar(kappa),E_e,C_i)
      ⇓ E_i$],
    [$cal(F)_h="publicFlow"(E_i)
      quad delta_o="semanticSummary"(E_i)$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi_i,"requiredPhase"(C_i))$],
    [$"RowSplit"(Delta_e,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$"AttributedOK"(Delta_e,s_e)$],
    [$Delta_h="handlerResidual"(E_i)
      quad Delta_o=Delta_"out"∪Delta_h$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad cal(F)_b="dropFlowBinder"(cal(F)_h,x_"cap")
      quad cal(F)_o="hideIdentityFlow"(cal(F)_b,i)$],
    [$s_o="handleInstallSusp"(s_e,Delta_"here",E_i)
      quad "AttributedOK"(Delta_o,s_o)$],
    [$"NoOpenPrivateDisposition"(i,Omega_e)$],
    [$Omega_o="hideIdentityUsage"(Omega_e,i)$],
    [$i ∉ "fv"(B,cal(F)_o,epsilon_o,Delta_o,s_o,delta_o,Omega_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
    "freshprompt" p " in " "handle"[p,h,i](
      "let" x_"cap"="capref"(i);e))
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

`ReplayableCleanup` 在 TR₀ 中是封闭且可判定的 predicate，不是由
validator 为某个 fixture 提供的 sealed 特例。定义唯一的 neutral cleanup：

$
  "NeutralCleanup"(F) " iff "
  F = { "residual_row": "EmptyV1",
        "attributed_demand": [],
        "transition": "SameWorldV1",
        "suspension": { "atoms": [], "grade": "NoSuspend" },
        "semantic_summary": "PureV1" }
$

并定义 $"EmptySuffixEnv"(kappa)$ 当且仅当 suffix validation已经证明
`keys(κ.D.live_bindings) == LiveSupport(κ.D.computation)`，且两者都为空；
checker不能只信任 wire中的 `live_bindings == []`。由这个完整的 suffix
environment投影得到的 $Pi_k$ 与 $chi_k$ 因而都恰为 $emptyset$。基线 truth rule 是：

#irule(
  [ReplayableCleanup-Neutral],
  (
    [$"NeutralCleanup"(F)$],
    [$Pi=emptyset quad chi=emptyset$],
  ),
  [$"ReplayableCleanup"(F,Pi,chi)$],
)

不存在其它 TR₀ derivation。对 Call-stage
`ReplayableCleanupV1/V2 { site_slot, cleanup }`，checker还必须在携带该
obligation 的同一个 `PathContractV2.LatentSites` 中解析唯一的
$kappa$，并同时证明：`κ.site_slot == site_slot`、
`cleanup == κ.suffix.cleanup`、`EmptySuffixEnv(κ)` 以及上面的
`NeutralCleanup(cleanup)`。因此，缺失/重复 site、借用别的 site cleanup、
非 neutral cleanup或非空 $Pi_k/chi_k$ 均不能 discharge。

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
    [$"src":"CompletionSource"[rho,A] in Theta$],
    [$o:"Owner"[rho] in Theta$],
    [$Phi_"park"="requiredPhase"(
        "Action","OwnerAuthority"(rho),rho)
      quad "PhaseAllows"(Phi,Phi_"park")
      quad "OwnerAuthorized"(Phi,o,rho)$],
    [$k:"Resume"[1,D_k,A,B,Pi_k,chi_k,rho_k] quad Omega(k)="Open"(1)$],
    [$K;I ⊢ D_k:"SuffixContractV2"(A arrow.r B)$],
    [$"Outlives"(rho_k,rho)$],
    [$"SuspensionStable"(rho,"summary"(D_k),Pi_k,chi_k)$],
    [$"OwnerBoundParking"(rho,D_k)$],
    [$kappa_p="freshParkSite"(S)
      quad c_s="freshClaimCellSlot"(S)$],
    [$"SealCompletion"("src",o,k,c_s) ⇓
      ⟨tau,c_r,"port":"CompletionPort"[rho,A],S_c,P_c⟩$],
    [$S_c:"SourceContractV2"(rho,A)
      quad P_c:"CompletionPortV2"(rho,A,c_s)$],
    [$R_k="ResumeTypeV2"(1,D_k,A,B,Pi_k,chi_k,rho_k)$],
    [$G_c="CanonicalGenerationCASV1"(c_s)$],
    [$D_c="OneShotDispositionV2"(
      kappa_p,c_s,R_k,{"Unclaimed","Completed","Finalized"},
      "UnclaimedToCompleted","UnclaimedToFinalized")$],
    [$P="ParkContractV2"(
      "owner_slot"="slot"(rho), "site_slot"=kappa_p,
      "claim_cell_slot"=c_s, "source"=S_c,
      "completion_port"=P_c, "claim"=G_c,
      "disposition"=D_c, "required_phase"=Phi_"park",
      "origin"="origin"("src.park"))$],
    [$s_p="ownerBound"(kappa_p,rho,"MaySuspend")
      quad "Allowed"(Phi,emptyset,s_p,delta_"park")$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"transfer" "park"("src",o,k) ⇓
    "Transfers"(P) ! emptyset;emptyset ▷
    s_p;delta_"park"
    @Theta⊣Omega[k↦"Transferred"(rho,tau,c_r)]$],
)

Surface 第一方协议把 `source.park(k, under = owner)` elaboration为
`park(src,o,k)`。它消耗 clause 当前 disposition ownership并终止当前 path；
因此不能伪装成 `Unit` 后继续执行 suffix。Owner runtime随后只向宿主暴露
generation-bound `CompletionPort[ρ,A]`，并对 resume/finalize承担唯一责任。
Raw `Resume` 不会被普通 host callback捕获；只有 sealed completion source
能构造 port 和 $P$。
这里 `Outlives(shorter,longer)` 的参数顺序与 wire一致：$rho_k$ 是被保存的
resumption Owner（shorter），$rho$ 是承担 parked source/port lifetime的 Owner
（longer）。二者相同时该 premise由 reflexivity消去；不同时必须序列化上节的
exact `OutlivesV2` path obligation。

$tau$ 与 $c_r$ 是 runtime generation ticket/claim-cell handle，只进入
$Omega$ 的 dynamic transfer state；`ParkContractV2` 不序列化两者。
$c_s$ 只是 alpha-normalized wire slot，不是运行时地址。$S_c/P_c/G_c/D_c$ 分别是规范 schema的
`SourceContractV2`、`CompletionPortV2`、`GenerationCASV1` 与
`OneShotDispositionV2`，所以 full resumption只存在于
`P.disposition.resumption`，不存在 flat `P.resumption` 或 flattened CAS字段。

completion只接收 $v:A$；CAS成功后才把 $v$ 交给保存的 $D_k:A→B$，由 suffix
产生 answer $B$。T-Park本身不运行 $D_k$，也不因此获得 Returns path。

`examples/spec/accept/owner-park.cire` 的关键推导链是：

```text
Async::await site
  → Demand(κ, p, Async, await, Primary)
  → once clause owns k : Open(1)
  → T-Park changes k to Transferred(ρ,g,c)
  → T-Body-Transfer yields {Transfers(ParkContractV2)}
  → T-Handle-*-Paths preserves that path
  → RowSplit(Δ,p) removes the handled Async demand
  → function body has declared_type Int, flow={Transfers}, row={}
```

这里没有任何一步把 transfer构造成 `Unit`、`Returns` 或 `Aborts`。
`examples/spec/accept/owner-park-nonidentity.cire` 另外固定
$A="Int" != B="Array"["Int"]$，避免 identity suffix掩盖 source/answer
接线错误。

TR₀ 只允许 park `once` resumption；
`ctl` 必须在 clause内同步使用并最终 finalize。若未来要 transfer multi-shot
continuation，Owner machine必须另加 q-indexed `CtlOpen/CtlClosed` protocol。
TR₀ 还保守要求 Action phase与当前 Owner authority；仅有
`o:Owner[ρ]` term binder不构成 authority。`ParkContract.required_phase`
序列化 $Phi_"park"$，`ExtractClauseContract` 保留该 constraint，
`SolveHandlerPhase` 必须把它合入 handler invocation precondition。

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
completion路径必须同时满足 captured generation等于 current generation；
close/revoke路径在推进 generation并把责任移入 retire set后，凭 sealed
Owner-retire authority执行 `Unclaimed→Finalized`，不再要求旧 generation
仍是 current。两者仍竞争同一个 $c$，所以 generation advance不会阻塞
post-revoke finalizer，也不会让 stale completion获胜。

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
suspension contribution request(demandKey(await-site), MaySuspend)
world transition        same
result summary          sealed OutcomeSummary(t)
```

在实际 Async delimiter安装处，每个 await site还必须满足：

#irule(
  [T-Await-Site],
  (
    [$a="Anon"("Async")
      quad "HandlesPrompt"(S,p_"async",a)$],
    [$kappa in "sites"(e,a,p_"async")$],
    [$"taskRegion"(Xi(kappa))=rho$],
    [$"CurrentOwner"(Phi)=rho_o quad "Outlives"(rho_o,rho)$],
    [$Pi_k="provenance"(kappa) quad chi_k="captures"(kappa)$],
    [$"SuspensionStable"(rho_o,"summary"(kappa),Pi_k,chi_k)$],
    [$"OwnerBoundParking"(rho_o,P_h)$],
  ),
  [$K;I;Phi;S ⊢
    "install-await-site"(p_"async",kappa,P_h):"OK"$],
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
`grade(handleSusp(s,Δhere,C_h,p))=MaySuspend`，T-Delay仍失败。只有真正
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
    [$a_w="Anon"("SourceUpdate") quad
      kappa_w="freshLexicalSite"(S)
      quad p_w="resolveRoute"(S,a_w)$],
    [$d_w="Demand"(kappa_w,p_w,a_w,"sourceWrite","Primary")
      quad Delta_w={d_w}$],
    [$s_w="request"("demandKey"(d_w),"NoSuspend")
      quad "AttributedOK"(Delta_w,s_w)$],
    [$K;I;Phi@Theta ⊢_v s ⇒ "Source"[rho,A] @[pi_s] ▷ chi_s$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi_v] ▷ chi_v$],
    [$"ActionOrAtomicWrite"(Phi) quad "SourceBoundarySafe"(rho,A,pi_v,chi_v)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "sourceWrite"(s,v) ⇒
    "Unit" @["Stable"] ! {a_w};Delta_w ▷
    s_w;delta_"pending-write";emptyset @Theta⊣Omega$],
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
    [$p_o ∉ "prompts"(S)
      quad S_o="pushPrompt"(S,p_o,a_o)$],
    [$K;I';Phi_c;Omega@Theta;S_o ⊢ e ⇒
      A @[pi_e] ! epsilon_e;Delta_e ▷
      s_e;delta_e;chi_e @Theta_e⊣Omega$],
    [$K;I';Phi_c@Theta;S_o ⊢
      "sites"(e,a_o,p_o) ⇓ bar(kappa_o)$],
    [$"InstallCheckpointOK"(
      p_o,bar(kappa_o),rho,Delta_e,s_e) ⇓ ⟨E_o,C_o⟩
      quad "ReplaySafe"(delta_e)$],
    [$"RowSplit"(Delta_e,p_o)=
      ⟨Delta_"here",Delta_"out"⟩
      quad Delta_"out"=emptyset
      quad "AttributedOK"(Delta_e,s_e)$],
    [$s_o="handleSusp"(s_e,Delta_"here",C_o,p_o)
      quad "grade"(s_o)="NoSuspend"
      quad "AttributedOK"(emptyset,s_o)
      quad "locks"(Theta_e)="locks"(Theta)$],
    [$i_o ∉ "fv"(A,pi_e,chi_e,delta_e,Delta_"out")$],
    [$chi_"raw"="captureFV"(e,Theta)$],
    [$chi_"env"="hideIdentityCapture"(chi_"raw",i_o,rho,E_o)$],
    [$Pi_"raw"="provenanceFV"("fv"(e),Theta)$],
    [$Pi_l="hideIdentityProvenance"(Pi_"raw",i_o,rho,E_o)$],
    [$chi_l={"owner"(rho)} ∪ chi_"env" ∪ chi_e$],
    [$"EnvBoundarySafe"("fv"(e),Theta,"OwnerStorage"(rho))$],
    [$"TraceCaptureSafe"(rho,chi_l) quad "StorageBoundarySafe"(rho,A,pi_e,chi_e)$],
    [$"Shareable"(A) quad i_o ∉ "fv"(Pi_l,chi_l)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢
    "freshprompt" p_o " in " "live"_rho(e) ⇒
    "Live"[rho,A] @["Owner"(rho)] !
    emptyset;emptyset ▷
    s_o;delta_"live" ⊗ delta_e;chi_l @Theta⊣Omega$],
)

关键点：

- body在 fresh checkpoint prompt $p_o$ 下检查，只有 route精确等于 $p_o$
  的 hidden Observe demand进入 $Delta_"here"$；同 family outer/secondary
  route留在 $Delta_"out"$ 并使 empty-out premise失败；
- `handleSusp` 只消除与 $Delta_"here"$ 成对的 request atoms，输出仍需
  `AttributedOK` 且 grade为 NoSuspend；
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
    [$a_c="Anon"("Commit") quad
      kappa_c="freshLexicalSite"(S)
      quad p_c="resolveRoute"(S,a_c)$],
    [$d_c="Demand"(kappa_c,p_c,a_c,"tryPublish","Primary")
      quad Delta_c={d_c}$],
    [$s_c="request"("demandKey"(d_c),"NoSuspend")
      quad "AttributedOK"(Delta_c,s_c)$],
    [$Phi."phase"="Commit"$],
    [$K;I;Phi@Theta ⊢_v "gate" ⇒ "CommitGate"[rho] @[pi_g] ▷ chi_g$],
    [$K;I;Phi@Theta ⊢_v "plan" ⇒ "Plan"[A] @[pi_p] ▷ chi_p$],
    [$"GateAuthorized"(Phi,"gate") quad "CommitBoundarySafe"(A,pi_p,chi_p)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "tryPublish"("gate","plan") ⇒
    "CommitResult" @["Stable"] ! {a_c};Delta_c ▷
    s_c;delta_"publish";emptyset @Theta⊣Omega$],
)

#irule(
  [T-Commit-Run],
  (
    [$K;I;Phi@Theta ⊢_v t ⇒ "CommitTicket"[rho] @[pi_t] ▷ chi_t$],
    [$"TicketBoundarySafe"(rho,pi_t,chi_t)$],
    [$c " fresh" quad p_c " fresh"
      quad a_c="Anon"("Commit")
      quad Phi_c=⟨"Commit",{a_c},rho⟩$],
    [$S_c="pushPrompt"(S,p_c,a_c)$],
    [$"GateFromTicket"(t,c) quad "CommitAdequacy"(t,c)$],
    [$Theta_g="bind"(Theta,"gate":"CommitGate"[rho] @["GenerationBound"(rho)] ▷ {"claim"(c)})$],
    [$K;I;Phi_c;Omega@Theta_g;S_c ⊢ e ⇒ B @[pi_B] !
      epsilon_e;Delta_e ▷ s_e;delta_e;chi_B @Theta_e⊣Omega'$],
    [$"RowSplit"(Delta_e,p_c)=⟨Delta_"here",emptyset⟩
      quad "AttributedOK"(Delta_e,s_e)
      quad "grade"(s_e)="NoSuspend"$],
    [$Theta_o="dropBinder"(Theta_e,"gate")$],
    [$"claim"(c) ∉ chi_B quad "ProvenanceValid"(B,pi_B,Theta_o,"CommitExit"(rho))$],
    [$s_o="handleSusp"(s_e,Delta_"here",C_"commit",p_c)
      quad "AttributedOK"(emptyset,s_o)
      quad delta_o=delta_e ⊗ P_"commit"$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "commitRun"_rho(t,"gate".e) ⇒
    B @[pi_B] ! emptyset;emptyset ▷
    s_o;delta_o;chi_B @Theta_o⊣Omega'$],
)

#irule(
  [T-Commit-Run-Abort],
  (
    [$K;I;Phi@Theta ⊢_v t ⇒ "CommitTicket"[rho] @[pi_t] ▷ chi_t$],
    [$"TicketBoundarySafe"(rho,pi_t,chi_t)$],
    [$c " fresh" quad p_c " fresh"
      quad a_c="Anon"("Commit")
      quad Phi_c=⟨"Commit",{a_c},rho⟩$],
    [$S_c="pushPrompt"(S,p_c,a_c)$],
    [$"GateFromTicket"(t,c) quad "CommitAdequacy"(t,c)$],
    [$Theta_g="bind"(Theta,"gate":"CommitGate"[rho] @["GenerationBound"(rho)] ▷ {"claim"(c)})$],
    [$K;I;Phi_c;Omega@Theta_g;S_c ⊢_"abort" e !
      epsilon_e;Delta_e ▷ s_e;delta_e ⊣Omega'$],
    [$"RowSplit"(Delta_e,p_c)=⟨Delta_"here",emptyset⟩
      quad "AttributedOK"(Delta_e,s_e)
      quad "grade"(s_e)="NoSuspend"$],
    [$"AbortWorldNeutral"("evidence"(e)) quad "NoClaimInAbortEvidence"(c,e)$],
    [$(Omega_o,delta_r)="abortCommitScope"(c,Omega',delta_e)$],
    [$s_o="handleSusp"(s_e,Delta_"here",C_"commit",p_c)
      quad "AttributedOK"(emptyset,s_o)
      quad delta_o=delta_r ⊗ P_"commit"$],
  ),
  [$K;I;Phi;Omega@Theta ⊢_"abort"
    "commitRun"_rho(t,"gate".e) !
    emptyset;emptyset ▷ s_o;delta_o ⊣Omega_o$],
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
resumption、child与 cleanup责任连同 sealed Owner-retire authority移入
$R_t$。`runOneRetire` 用该 authority执行 generation-independent
`Unclaimed→Finalized` CAS；它仍与已经成功的 completion互斥。任何 user
disposer都只会在这个线性化点之后运行。

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
      | Transfers(ParkContractV2)
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
`ParkContractV2`。集合可以同时包含 return/abort/transfer；只有 set中确实有
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
check_return_clause_schema_v2(ctx, handler_shape, clause)
  -> (ContractComputationV2, [AppliedContractV2])
check_clause_schema_v2(
  ctx, handler_shape, operation_signature, clause, application_slot_supply)
  -> (ClauseComputationV2, [AppliedContractV2])
analyze_sites(typed_core, delimiter_entry, installation_prompt,
              answer_contract) -> SiteContracts
install_handler(prompt_stack, installation_prompt, handler_contract, policy,
                handled_entry, site_contracts, body_flow)
  -> InstallEvidence
```

`ctx` 包含：

```text
K, I, Φ, Ω, Θ
prompt stack: fresh installation prompts with handled entry
route stage: Call normally; HandlerInstall only in handler schemas
expected answer type
current Owner is an explicit field of Φ
constraint worklists
```

== 主递归

每个 strict-position recursive call都经过同一个 path-bind combinator：

```text
strict_bind(result, typed_prefix, continue_return):
  prepared = map(result.flow, path =>:
    match path:
      Returns(Θ, π, χ, Ω):
        path
      Aborts | Transfers(_) | Delegates(_):
        compose_terminal_prefix(typed_prefix, path))
  continue = path =>:
    Returns(Θ, π, χ, Ω) = path
    continue_return(
      return_projection(result, path, Θ, π, χ, Ω))
  bound = PathBind(prepared, continue)
  return aggregate_check_result(
    bound, result.evidence,
    path_bind_evidence(typed_prefix, prepared, continue, bound))
```

`return_projection` 只暴露该 Returns path自己的 type/π/χ/Θ/Ω。
`prepared` 只给既有 terminal path附加已经执行的 typed prefix；
`PathBind` 的第二参数始终是 Returns→flow continuation，因此每个 terminal
prefix只 composition一次，也不会作为 continuation list再次展开。
`aggregate_check_result` 只在所有 path-local Q/R/usage/site检查完成后汇总
row、suspension与 summary evidence；汇总值绝不作为后续 strict context。
因此没有 `join_returns` 的 distributivity假设；terminal path除恰好一次
已执行 prefix composition外原样保留。
`check_args` 是从左到右的有限 fold；每个 argument都立刻经过
`strict_bind`，
若某一步没有 return path就立即返回已经执行的 argument prefix；若同时有
return与terminal path，只让 return entries继续检查后续 argument并保存
terminal entries。所以 site node中的 $Xi_k$ 恰好只来自可达、已类型化的
actual argument。

```text
resolve_route_for_stage(stage, prompts, entry):
  if stage == Call:
    return resolve_route_at_call(prompts, entry)
  if top_prompt(prompts).entry == entry:
    return InstallationPrompt(top_prompt(prompts).prompt)
  return ResolveAtInstallation(on_missing = RootOfEntry)

build_operation_path_algorithm(
  ctx, κ, a, o, sig, ra, call_evidence, install_obligations):
  require call_evidence is discharged for
    (sig.obligations, ra.argument_summaries, ctx.I, ra.Θ_out)
  require phase_allows(ctx.Φ, sig.required_phase)
  p = resolve_route_for_stage(
    ctx.route_stage, ctx.prompts, a)
  primary = Demand(κ, p, a, o, Primary)
  require sig.secondary_site_set.kind == Closed
  secondary = instantiate_secondary_sites(
    sig.secondary_site_set.sites,
    parent_site = κ,
    prompt_stack = ctx.prompts)
  Δ = union(ra.attributed_demand, {primary},
            secondary.attributed_demand)
  s = join(
    ra.suspension,
    request(demand_key(primary), sig.suspension),
    secondary.attributed_suspension)
  require attributed_ok(Δ, s)
  δ = ra.summary ⊗ secondary.semantic_summary
  require Allowed(ctx.Φ, eraseDemand(Δ), s, δ)
  record_site_node(
    site_slot = κ, route = p, entry = a, operation = o,
    instantiated_signature = sig,
    actual_argument_summaries = ra.argument_summaries,
    call_obligations = call_evidence,
    install_obligations = install_obligations,
    secondary_sites = secondary.site_evidence)
  if sig.mode == abort:
    require sig.world == abortive
    return single_path_result(
      Aborts, ra.Ω_out, Δ, s, δ,
      {primary} ∪ secondary.site_evidence)
  Θ = apply_transition(sig.world, ra.Θ_out)
  (π, χ) = sig.result_summary(
    ra.argument_provenance, ra.argument_captures)
  return single_path_result(
    Returns(Θ, π, χ), ra.Ω_out, Δ, s, δ,
    {primary} ∪ secondary.site_evidence)

instantiate_call_result_paths(
  rf, ra, contract, call_flow, Ω, Δ, s, Λinstall):
  for path in call_flow:
    match path:
      Returns(transition, result_transformer):
        emit Returns(
          apply_transition(transition, ra.Θ_out),
          apply_result_transformer(
            result_transformer, ra.π, ra.χ))
      Aborts:
        emit Aborts
      Transfers(P):
        emit Transfers(instantiate_park_contract(P, ra))
  return aggregate_call_paths(
    rf, ra, emitted paths, Ω, Δ, s, Λinstall)

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
      Scall = fresh_symbolic_prompt_stack()
      call_ctx =
        ctx.with_prompts(Scall).with_route_stage(Call)
      rb_symbolic = check_body_flow(
        bind(call_ctx.with_phase(Φrequired).with_usage(symbolic.Ω),
             x, A, symbolic.π, symbolic.χ),
        body, B)
      rb = abstract_lambda_call_context(
        rb_symbolic, Scall,
        unresolved_route_stage = Call)
      require rb contains no concrete prompt selected from ctx.prompts
      χclosure = capture_fv(body - x, ctx.Θ)
      Πclosure = provenance_fv(body - x, ctx.Θ)
      u = latent_usage(symbolic.Ω, rb.Ω_out)
      Λ = abstract_sites(rb.typed_core, x)
      require many_call_safe(Πclosure, u, χclosure)
      Fabs = abstract_parametric_flow(
        symbolic_call_stack = Scall,
        argument_provenance = symbolic.π,
        argument_capture = symbolic.χ,
        definition_world = ctx.Θ,
        parameter = x,
        complete_flow = rb.flow)
      require Fabs.flow_summary == abstract_flow(rb.flow)
      require Fabs.obligations == normalized_union(
        obligations_of_every_path(rb.flow))
      Cterm = abstract_contract_computation_v2(
        complete_flow = rb.flow,
        path_evidence = rb.path_evidence,
        obligations = Fabs.obligations,
        latent_sites = Λ)
      require observers(Cterm) == Fabs
      return value(function_contract_v2(
        binders = generalized_binders(symbolic, Fabs),
        applications = Cterm.applications,
        computation = Cterm,
        closure_environment =
          environment_ledger(Πclosure, χclosure, u)))

    App(f, arg):
      return strict_bind(synth(ctx, f), empty_prefix, rf =>:
        (A, contract, B) = instantiate_function(rf.type)
        require rf.type is FunctionTypeV2(
          parameter = A, result = B, contract = contract.ref)
        require resolve_contract_ref(contract.ref) has exact
          FunctionContractKindV2(
            parameter_type = A,
            result_type = B,
            visible_row = visible_row(contract))
        strict_bind(
          check(context_of(rf), arg, A), prefix(rf), ra =>:
            application = build_applied_contract_v2(
              contract_ref = contract.ref,
              callee_summary = value_summary(rf),
              actual_arguments = [value_summary(ra)],
              substitution = solve_complete_substitution(contract, rf, ra),
              entry_world = ra.Θ_out,
              origin = source_origin(f))
            require application.callee_summary.type ==
              FunctionTypeV2(A, B, application.contract)
            require application is atomic and
              no_field_has_independent_actuals(application)
            invoked = InvokeV2(application.application_slot)
            require phase_allows(ctx.Φ, phase(invoked))
            Qcall = instantiate(
              stageCall(obligations(invoked)), application)
            discharge(Qcall)
            Qinstall = instantiate(
              stageHandlerInstall(obligations(invoked)), application)
            Ω3 = apply_usage(ra.Ω_out, usage(invoked))
            (Δcall, scall, Λinstall) =
              instantiate_latent_contract(
                row(invoked), suspension(invoked),
                latent_sites(invoked), application,
                current_prompt_stack = ctx.prompts)
            require eraseDemand(Δcall) ==
              row(invoked)
            require attributed_ok(Δcall, scall)
            preserve_until_install(Qinstall, Λinstall)
            call_flow = evaluate_contract_computation(
              invoked, application)
            return instantiate_call_result_paths(
              rf, ra, application, call_flow, Ω3,
              Δcall, scall, Λinstall)))

    Let(x, first, rest):
      return strict_bind(
        synth(ctx, first), empty_prefix, r1 =>:
          strict_bind(
            synth(bind(context_of(r1), x, r1.type, r1.π, r1.χ),
                  rest),
            prefix(r1), r2 =>:
              return drop_flow_binder(
                compose_sequence_path(r1, r2), x)))

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
      a = row_entry(receiver)
      o = sig.resolved_selector
      κ = fresh_site_slot()
      args_result = check_args(ctx, args, sig.parameters)
      return strict_bind(
        args_result, evaluated_arg_prefix, ra =>:
          build_operation_path_algorithm(
            ctx, κ, a, o, sig, ra,
            call_evidence = discharge_and_seal(instantiate(
              stageCall(sig.obligations),
              ra.argument_summaries, ctx.I, ra.Θ_out)),
            install_obligations = instantiate(
              stageHandlerInstall(sig.obligations),
              ra.argument_summaries, ctx.I, ra.Θ_out)))

    Forward(current_site, outer_prompt, receiver, op, args):
      κ = require_current_primary_site(current_site)
      k = require_open_disposition_for(κ, ctx.Ω)
      require tail_position_in_clause()
      require κ.entry == resolve_exact_entry(receiver)
      require κ.operation == resolve_exact_operation(receiver, op)
      require strictly_outer_live_prompt(
        ctx.prompts, κ.installation_prompt, outer_prompt, κ.entry)
      sig = κ.instantiated_signature
      arg_paths = check_args(ctx, args, sig.parameters)
      forwarded_paths = []
      forward_evidence = []
      for r in arg_paths.returning_paths:
        require r.Ω_out[k] is Open(_)
        call_obligations = discharge_and_seal(instantiate(
          stageCall(sig.obligations), r.argument_summaries,
          ctx.identities, r.Θ_out))
        install_obligations = instantiate(
          stageHandlerInstall(sig.obligations),
          r.argument_summaries, ctx.identities, r.Θ_out)
        κf_header = prepare_forward_site(
          stable_site_slot = κ.site_slot,
          installation_prompt = outer_prompt,
          entry = κ.entry,
          operation = κ.operation,
          continuation = κ.continuation,
          entry_world = r.Θ_out,
          actual_argument_summaries = r.argument_summaries,
          instantiated_signature = sig,
          call_obligations = call_obligations,
          install_obligations = install_obligations)
        require sig.secondary_site_set.kind == Closed
        secondary = instantiate_secondary_sites(
          sig.secondary_site_set.sites,
          parent_site = κf_header,
          prompt_stack = ctx.prompts)
        require attributed_ok(
          secondary.attributed_demand,
          secondary.attributed_suspension)
        κf = seal_forward_site(
          κf_header,
          secondary_sites = secondary.contract_set)
        primary = Demand(
          κf.site_slot, κf.installation_prompt, κf.entry,
          κf.operation, Primary)
        primary_suspension =
          request(demand_key(primary), sig.suspension)
        Δf = union(r.attributed_demand, {primary},
                   secondary.attributed_demand)
        sf = join(
          r.suspension, primary_suspension,
          secondary.attributed_suspension)
        require attributed_ok(Δf, sf)
        δf = r.summary ⊗ secondary.semantic_summary
        require phase_allows(ctx.Φ, sig.required_phase)
        require Allowed(ctx.Φ, eraseDemand(Δf), sf, δf)
        Ωf = forward_disposition(r.Ω_out, k, κf)
        require type(k) == ResumeTypeRefV2(value = ResumeTypeV2(
          usage = quantity_for_mode(sig.mode),
          continuation = κf.continuation,
          argument = sig.result,
          answer = expected_clause_type,
          live_provenance = continuation_provenance(κf.continuation),
          live_capture = continuation_capture(κf.continuation),
          owner = continuation_owner(κf.continuation)))
        forward_contract_v2 = ForwardContractV2(
          site_slot = κf.site_slot,
          route = InstallationPromptV1(outer_prompt),
          entry = κf.entry,
          operation = κf.operation,
          continuation = κf.continuation,
          entry_world = LegacyWorldExprV2(r.Θ_out),
          actual_argument_summaries =
            value_summaries_v2(κf.actual_argument_summaries),
          instantiated_signature = signature_v2(sig),
          call_obligation_ids = ids(call_obligations),
          install_obligation_ids = ids(install_obligations),
          secondary_sites = κf.secondary_sites,
          origin = source_origin(current_site))
        record_forward_node(
          site_contract = forward_contract_v2,
          stable_site_slot = κf.site_slot,
          previous_prompt = κ.installation_prompt,
          routed_prompt = κf.installation_prompt,
          actual_argument_summaries = κf.actual_argument_summaries,
          instantiated_signature = κf.instantiated_signature,
          call_obligations = κf.call_obligations,
          install_obligations = κf.install_obligations,
          primary = primary,
          secondary_sites = κf.secondary_sites,
          usage_context_out = Ωf)
        disposition_evidence = seal_forward_disposition_evidence(
          inner_disposition = k,
          original_site = κ,
          forward_contract = forward_contract_v2,
          input_usage = r.Ω_out,
          output_usage = Ωf,
          continuation_transfer = ExclusiveToForwardContract)
        forwarded_paths += PathContractV2(
          outcome = DelegatesV2(
            forward_contract = forward_contract_v2,
            disposition_evidence = disposition_evidence),
          residual_row = eraseDemand(Δf),
          attributed_demand = Δf,
          suspension = sf,
          semantic_summary = δf,
          usage = usage_exprs_v2(Ωf),
          required_phase = join_required_phase(
            Action, sig.required_phase),
          ParametricObligations =
            obligations_v2(call_obligations, install_obligations),
          LatentSites = latent_sites_v2(κf))
        forward_evidence +=
          (Δf, sf, δf, Ωf, {primary} ∪ secondary.site_evidence)
      flow = union(arg_paths.terminal_paths, forwarded_paths)
      evidence = aggregate_path_evidence(
        flow, arg_paths.evidence, forward_evidence)
      return ClauseCheckResult(
        type = expected_clause_type,
        flow = flow,
        provenance = bottom,
        residual_row = eraseDemand(evidence.attributed_demand),
        attributed_demand = evidence.attributed_demand,
        attributed_suspension = evidence.attributed_suspension,
        semantic_summary = evidence.semantic_summary,
        result_captures = bottom,
        usage_context_out = evidence.usage_context_out,
        latent_site_evidence = evidence.latent_site_evidence)

    Handle(handler, optional_cap_binder, body):
      rh = check_value(ctx, handler)
      require rh.type has shape
        HandlerTemplate[F, ρh, A, B, εh, (S, prompt, entry).Ch, Ph]
      p = fresh_prompt()
      if optional_cap_binder:
        require handler_origin_ok(ctx.Φ, rh.origin_owner)
        ι = fresh_identity(rh.effect, rh.origin_owner)
        a = Named(ι, rh.effect)
        ctxι = ctx.extend_identity(ι).add_authority(a)
                  .push_prompt(p, a)
                  .bind(
                    optional_cap_binder,
                    Cap[ι, rh.effect],
                    Region(rh.origin_owner),
                    captures = {ι})
        require phase_allows(ctxι.Φ, rh.required_phase)
        rb = check_body_flow(
          ctxι, body, rh.handled_input,
          core_prefix =
            let optional_cap_binder = capref(ι))
        sites = analyze_sites(
          rb.typed_core, a, p, rb.answer_contract)
        install = install_handler(
          ctxι.prompts, p, rh, rh.policy, a, sites, rb)
        result = eliminate_entry_with_contract(
          p, rh, rb, a, sites, install)
        require no_open_private_disposition(ι, result.Ω_out)
        result.Ω_out = hide_identity_usage(result.Ω_out, ι)
        result.flow = drop_flow_binder(
          result.flow, optional_cap_binder)
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
          ctxp.prompts, p, rh, rh.policy, a, sites, rb)
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

    Park(source, owner, k):
      require ctx.Ω[k] == Open(1)
      A = resume_argument(k)
      B = resume_answer(k)
      require source : CompletionSource[ρ, A]
      require owner : Owner[ρ]
      require phase_allows(ctx.Φ, Action)
      require owner_authorized(ctx.Φ, owner, ρ)
      Dk = continuation(k)
      require outlives(Dk.owner_region, ρ)
      require suspension_stable(
        ρ, Dk.summary, Dk.provenance_live, Dk.captures_live)
      require owner_bound_parking(ρ, Dk)
      park_site = fresh_site_slot()
      claim_cell_slot = fresh_claim_cell_slot()
      (runtime_ticket, runtime_claim_cell, port,
       source_contract, port_contract) =
        seal_completion(source, owner, k, claim_cell_slot)
      require port : CompletionPort[ρ, A]
      suspension = ownerBound(park_site, ρ, MaySuspend)
      require Allowed(
        ctx.Φ, ∅, suspension, δpark)
      resumption = ResumeTypeV2(
        usage = Once,
        continuation = Dk,
        argument = A,
        answer = B,
        live_provenance = Dk.provenance_live,
        live_capture = Dk.captures_live,
        owner = Dk.owner_region)
      claim = GenerationCASV1(
        claim_cell_slot = claim_cell_slot,
        source_generation = ClaimTicketGeneration,
        completion_generation_gate = EqualCurrentGeneration,
        finalization_generation_gate =
          EqualCurrentGenerationOrOwnerRetireAuthority,
        completion_transition = UnclaimedToCompleted,
        finalization_transition = UnclaimedToFinalized,
        generation_transition = PreserveGeneration,
        failure_transition = NoStateChange)
      disposition = OneShotDispositionV2(
        continuation_site_slot = park_site,
        claim_cell_slot = claim_cell_slot,
        resumption = resumption,
        states = {Unclaimed, Completed, Finalized},
        completion_transition = UnclaimedToCompleted,
        finalization_transition = UnclaimedToFinalized)
      contract = ParkContractV2(
        site_slot = park_site,
        owner_slot = alpha_owner_slot(ρ),
        claim_cell_slot = claim_cell_slot,
        source = source_contract,
        completion_port = port_contract,
        claim = claim,
        disposition = disposition,
        required_phase = required_phase_for(Action, owner, ρ),
        origin = source_origin(source.park))
      require contract.source.value_type
        == contract.completion_port.value_type
        == contract.disposition.resumption.argument
      require contract.disposition.resumption.answer == Dk.answer_type
      require contract.disposition.resumption.continuation == Dk
      require contract.claim.claim_cell_slot
        == contract.claim_cell_slot
        == contract.completion_port.claim_cell_slot
        == contract.disposition.claim_cell_slot
      return transferring_flow(
        flow = {Transfers(contract)},
        residual_row = ∅,
        attributed_demand = ∅,
        suspension = suspension,
        summary = δpark,
        usage_context_out =
          transfer_disposition(
            ctx.Ω, k, ρ, runtime_ticket, runtime_claim_cell))

    Intrinsic(name, args):
      dispatch to the named syntax-directed procedure; in particular:
        PackNext(owner, builder) =>
          check_pack_next(ctx, owner, builder)
        TryOpenPackedNext(packed, body) =>
          check_try_open_packed_next(ctx, packed, body)
        DisposePackedNext(packed) =>
          check_dispose_packed_next(ctx, packed)
```

PackedNext的三个算法分支不从 surface type反推丢失的 existential。
它们与 serializer/importer共享同一 binder顺序、wire和 path observer：

```text
check_pack_next(ctx, owner_expr, builder):
  owner = check_value_as(ctx, owner_expr, Owner[ρ])
  Φpack = required_phase_for(Action, owner, ρ)
  require phase_allows(ctx.Φ, Φpack) and
    owner_authorized(ctx.Φ, owner, ρ)
  (ρc, owner_child, j, i, runner, handle, child_witness, Θc) =
    create_packed_frame(owner)
  δallocate = PackedAllocateSummaryV2(HostObservable, NoSuspend)
  δterminal_close =
    PackedTerminalCloseSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend), δallocate)
  require child_witness == ChildOwnerWitnessV2(
    parent = ρ, child = ρc, relation = DirectChild,
    sealed_origin = "cire.temporal:pack_next")
  Ic = ctx.I + Identity(j, FrameClock, ρc) + ClockView(i, j, ρc)
  L = infer_later_contract_v2(i, expected_payload(builder), builder)
  require later_contract_wf(L, i, expected_payload(builder))
  body_ctx = ctx.with_I(Ic).with_Θ(
    bind(extend_child_owner(Θc, owner_child),
         frame, Cap[j, FrameClock], Region(ρc), {j, i}))
  body = check_body_flow(
    body_ctx, builder, Next[i, expected_payload(builder), L])
  for path in body.flow:
    require pack_next_path_safe(
      ρc, j, i, handle, body.type.payload, L, path,
      path.evidence)
    expected_summary =
      if path is Returns then
        OrderedSummaryNF(δallocate, path.summary)
      else
        OrderedSummaryNF(
          δallocate, path.summary, δterminal_close)
    require Allowed(
      ctx.Φ, path.row, path.suspension, expected_summary)
  Sp = seal_packed_summary(i, body.type.payload, L, body.flow)
  wire = serialize_packed_next_package_v2(
    storage_owner = OwnerRef(ρ),
    child_owner_binder = QuantifiedOwnerBinderV1(
      owner_slot = slot(ρc)),
    owner_relation = child_witness,
    clock_binder = QuantifiedClockBinderV2(
      identity_slot = slot(j),
      clock_refinement = {
        clock_slot = slot(i), identity = ref(j)},
      family_witness = CanonicalFrameClockV2,
      owner = ref(ρc)),
    summary_binder = QuantifiedContractBinderV2(
      contract_slot = slot(Sp),
      kind = ClockPackageSummaryKindV2(
        clock = ClockRef(i), payload_type = body.type.payload)),
    body = Next[i, body.type.payload, L],
    control_protocol = canonical_packed_next_control_v2,
    sealed_origin = "cire.temporal:pack_next")
  imported = import_packed_next_package_v2(ctx.K, ctx.I, wire)
  require imported ==
    exists ρc. exists j. exists i. exists Sp.
      Next[i, body.type.payload, L]
  paths = map(body.flow, path =>
    seal_or_close_pack_path(
      allocate_summary = δallocate,
      terminal_close_summary = δterminal_close,
      owner, owner_child, ρc, j, i, runner, handle, wire, path))
  require every paired (body_path, packed_path) satisfies
    packed_path.tag == body_path.tag and
    packed_path.row == hide_private(body_path.row) and
    packed_path.attributed_demand ==
      hide_private(body_path.attributed_demand) and
    packed_path.suspension == body_path.suspension and
    packed_path.usage == hide_private(body_path.usage) and
    packed_path.required_phase == RequireBoth(
      hide_private(body_path.required_phase), Φpack) and
    packed_path.Q == hide_private(body_path.Q) and
    packed_path.Lambda == hide_private(body_path.Lambda) and
    packed_path.summary ==
      (if body_path is Returns then
        OrderedSummaryNF(δallocate, body_path.summary)
       else
        OrderedSummaryNF(
          δallocate, body_path.summary, δterminal_close)) and
    (body_path is Returns or packed_path.close_action == CloseChildOnce)
  require no_free_outward(paths, {ρc, j, i, L, Sp, owner_child})
  return aggregate_check_result(
    normalize(paths), body.evidence,
    packed_package_evidence(wire, imported, child_witness))

check_try_open_packed_next(ctx, packed_expr, body):
  packed = check_value_as(ctx, packed_expr, PackedNext[ρ, A])
  require phase_allows(ctx.Φ, Action)
  δacquire = PackedAcquireSummaryV2(HostObservable, NoSuspend)
  δrelease = PackedReleaseSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend),
                  OrderedSummaryNF(δacquire, δrelease))
  lost = AcquireLostNonePath(
    summary = δacquire, world = ctx.Θ,
    provenance = Stable, capture = ∅)
  won_paths = []
  when try_acquire_packed(packed) returns (lease, wire):
    package = import_packed_next_package_v2(ctx.K, ctx.I, wire)
    unpack package as (ρc, j, i, L, Sp, child_witness,
                       Next[i, A, L])
    require child_witness == DirectChild(ρ, ρc)
    (owner_child, frame, pending) =
      open_packed_runtime(packed, lease, wire)
    open_ctx = ctx
      .extend_owner(ρc, child_witness)
      .extend_identity(j, FrameClock, ρc)
      .extend_clock(i, paired_identity = j, owner = ρc)
      .extend_contract(Sp, ClockPackageSummaryKindV2(i, A))
      .bind(frame, Cap[j, FrameClock], Region(ρc), {j, i})
      .bind(pending, Next[i, A, L],
            summary_provenance(Sp), summary_capture(Sp))
    checked = check_body_flow(open_ctx, body, expected_body_type)
    for path in checked.flow:
      require packed_next_outward_safe(
        ρc, j, i, L, Sp, checked.type, path, path.evidence)
      expected_summary = OrderedSummaryNF(
        δacquire, path.summary, δrelease)
      require Allowed(
        ctx.Φ, path.row, path.suspension,
        expected_summary)
      won_paths += acquire_release_map_some_path(
        acquire_summary = δacquire,
        body_path = path,
        release_summary = δrelease,
        normalized_summary = expected_summary,
        release_action = ExactlyOnceRelease,
        hidden = {ρc, j, i, L, Sp, owner_child})
  paths = normalize({lost} ∪ won_paths)
  require summary(lost) == δacquire and
    every paired (body_path, won_path) satisfies
      won_path.tag == map_some_or_preserve_terminal(body_path.tag) and
      won_path.row == hide_private(body_path.row) and
      won_path.attributed_demand ==
        hide_private(body_path.attributed_demand) and
      won_path.suspension == body_path.suspension and
      won_path.usage == hide_private(body_path.usage) and
      won_path.required_phase ==
        require_action_and_hide_private(body_path.required_phase) and
      won_path.Q == hide_private(body_path.Q) and
      won_path.Lambda == hide_private(body_path.Lambda) and
      won_path.summary == OrderedSummaryNF(
        δacquire, body_path.summary, δrelease)
  return aggregate_check_result(
    paths, packed.evidence,
    packed_acquire_release_evidence(paths))

check_dispose_packed_next(ctx, packed_expr):
  packed = check_value_as(ctx, packed_expr, PackedNext[ρ, A])
  require phase_allows(ctx.Φ, Action)
  δdispose = PackedDisposeSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend), δdispose)
  transition = request_packed_close(packed)
  require transition is exactly one of
    Open(0) -> Closed + CloseChildOnce,
    Open(n+1) -> Closing(n+1),
    Closing(n) -> Closing(n),
    Closed -> Closed
  return single_path_result(
    Returns(ctx.Θ, Stable, ∅), ctx.Ω,
    row = ∅, demand = ∅,
    suspension = direct(NoSuspend), summary = δdispose,
    evidence = sealed_dispose_transition(transition))
```

`check_try_open_packed_next` 只能在 acquire成功后导入 wire，且导入得到的
`owner_child/frame/pending` 正是 body scope的唯一 binder来源。获胜 path
的 observer由上述有序三段 summary派生；`release_evidence` 不是可以代替
它的 detached旁证。这三个 procedure的 serializer/importer、scope、phase、
`Allowed`与非 `Pure` state-transition summary与 T-Pack/T-Try/T-Dispose逐项相同。

为避免伪代码省略被误读成“其余 Core constructor被 reject”，以下 branch是
对应具名规则的 syntax-directed transcription：

```text
CapAbs / CapApp              T-Cap-Intro / T-Cap-Elim
capref                       T-Cap-Ref
ClockPack                    T-Clock-Pack
ClockUnpack                  T-Clock-Unpack-Paths
PackNext                     T-Pack-Next-Paths
TryOpenPackedNext            T-Try-With-PackedNext-Paths
DisposePackedNext            T-Dispose-PackedNext
OwnerAbs / OwnerApp          T-Owner-Intro / T-Owner-Elim
FreshCap                     K-Fresh-Cap / K-Fresh-Cap-Abort
HandlerValue                 T-Handler + check_clause_schema_v2
Forward                      T-Forward-Delegate / T-Forward-Paths
Finalize                    T-Finalize + cleanup contract composition
Park                         T-Park
Atomic                       T-Atomic / T-Atomic-Abort
Batch                        T-Batch / T-Batch-Abort
CommitRun                    T-Commit-Run / T-Commit-Run-Abort
strict evaluation context    T-Ctx-Paths
```

每个 branch都对严格 AST 子树递归，并调用同一 finite kind/row/boundary
worklist；它们不是额外的 declarative oracle。`ClockUnpack` 的 package
operand按 Core grammar是 value $p$，因此算法也先走 `check_value`，不与
T-Clock-Unpack-Paths冲突。它只调用一次 `check_body_flow`，然后逐 path运行
`clock_package_outward_safe` 与 `release_hide_path`；不能按
`has_returns` 分叉，也不能把 Aborts/Transfers交给 generic context跳过
release。PackedNext的两个 contextual body branch复用同一 traversal；
try-open另加入固定 Returns(None) path。

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
  require owner_authorized(ctx.Φ, owner)
  require env_boundary_safe(
    free_values(clauses), ctx.Θ, OwnerStorage(owner))
  Sinst = fresh_symbolic_installation_stack()
  pinst = fresh_symbolic_prompt_slot()
  ainst = fresh_symbolic_entry_selector(effect)
  require top_prompt(Sinst) == (pinst, ainst)
  schema_ctx =
    ctx.with_prompts(Sinst)
       .with_route_stage(HandlerInstall)
  shape = { input = A, answer = B, owner = owner,
            phase_symbol = Φsym,
            env_provenance = Πenv, env_captures = χenv,
            installation_stack = Sinst,
            installation_prompt = pinst,
            handled_entry = ainst }
  (Creturn, Areturn) = check_return_clause_schema_v2(
    schema_ctx, shape, return_clause)
  schemas = {}
  application_ledger = Areturn
  for op in operations(effect):
    clause = operation_clause_map[op]
    (schemas[op], Aop) =
      check_clause_schema_v2(
        schema_ctx, shape, op.signature, clause,
        fresh_application_slots_after(application_ledger))
    require disjoint(application_slots(application_ledger),
                     application_slots(Aop))
    application_ledger += Aop
  C0 = aggregate_handler_v2(
    applications = application_ledger,
    return_computation = Creturn,
    clause_computations = schemas)
  C0.required_phase = solve_and_generalize_required_phase(
    Φsym, Creturn.constraints ∪ schemas.constraints)
  C = attach_handler_env(C0, Πenv, χenv)
  P = resolve_sealed_handler_policy(effect, clauses)
  require PolicyOK(P) and Origin(P) == shape.owner
  return HandlerResult(
    type = HandlerTemplate[effect, shape.owner, A, B,
                           C.residual_row, (Sinst, pinst, ainst).C, P],
    contract_template = (Sinst, pinst, ainst).C,
    policy = P,
    provenance = Owner(shape.owner),
    captures = χenv,
    clause_schemas = schemas)

check_return_clause_schema_v2(ctx, handler_shape, clause):
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
  return abstract_return_contract_v2(
    Θentry, arg, body,
    unresolved_route_stage = HandlerInstall), body.applications
    universally quantified over
      handler_shape.installation_stack,
      handler_shape.installation_prompt,
      handler_shape.handled_entry, Θentry and arg

check_clause_schema_v2(
    ctx, handler_shape, op_sig, clause, application_slot_supply):
  skolems = fresh_skolems(op_sig.type_parameters)
  opσ = instantiate(op_sig, skolems)
  arg_summaries =
    fresh_rigid_argument_summaries(opσ.parameters)
  params = bind_parameters(opσ.parameters, arg_summaries)
  Θentry = fresh_symbolic_temporal_context()
  p = handler_shape.installation_prompt
  clause_ctx = import_handler_env(
    ctx.with_phase(handler_shape.phase_symbol).with_Θ(Θentry),
    handler_shape.env_provenance,
    handler_shape.env_captures,
    handler_shape.owner)
  κ = fresh_abstract_site_contract(
    stable_site_slot = fresh_site_slot(),
    installation_prompt = p,
    entry = handler_shape.handled_entry,
    operation = opσ.resolved_selector,
    entry_world = Θentry,
    first_transition = opσ.resume_transition,
    instantiated_signature = opσ,
    call_obligations = stageCall(opσ.site_obligations),
    install_obligations = stageHandlerInstall(opσ.site_obligations),
    secondary_contract = opσ.secondary_contract,
    actual_argument_summaries = arg_summaries,
  )

  if clause.mode in {once, ctl}:
    q = clause_mode_budget(clause.mode)
    k = Resume[q, κ.D, opσ.result, handler_shape.answer,
               κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
    result = check_body_flow(
      clause_ctx + params + k:Open(q),
      clause.body, handler_shape.answer)
    require path_sensitive_usage(result, k) <= q
    result =
      disposition_complete_paths(
        result, k, disposition_binder, clause.mode)
  else if clause.mode == fun:
    k = hidden Resume[1, κ.D, opσ.result,
                      handler_shape.answer,
                      κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
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
    k = hidden Resume[1, κ.D, opσ.result,
                      handler_shape.answer,
                      κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
    body_flow = check_body_flow(
      clause_ctx + params + k:Open(1),
      clause.body, handler_shape.answer)
    result = append_hidden_disposition_on_every_exit(
      body_flow, k, κ.D.cleanup)
    require every normal result world == κ.answer_world

  require clause_contract(result) refines opσ.contract
  require every Delegates(κf) path in result carries exactly
    OpenToForwardedExclusive(k, κf.site_slot, κf.continuation)
  wire_computation = serialize_contract_computation_v2(
    clause_contract(result),
    disposition_substitution = {
      k -> LegacySlotRefV2(
        SlotRefV1(SuffixLive, disposition_binder.slot)) },
    allowed_delegates = OnlyThisHandlerClause,
    application_ledger = result.applications)
  require every InvokeV2 in wire_computation resolves uniquely in
    result.applications
  return ClauseComputationV2(
    operation = opσ.resolved_selector,
    disposition_binder = disposition_binder,
    computation = wire_computation), result.applications
    universally quantified over
      handler_shape.installation_stack,
      handler_shape.handled_entry, skolems, p and κ

disposition_complete_paths(result, k, disposition_binder, mode):
  return map_paths(result, path =>:
    match path:
      Delegates(κf):
        require disposition_binder.type == type(k)
        require path.disposition_evidence ==
          OpenToForwardedExclusive(k, κf.site_slot, κf.continuation)
        require path.usage_context[k] == Forwarded(κf)
        preserve path
      Returns | Aborts | Transfers(_):
        require path.usage_context[k] is not Forwarded(_)
        if mode == once:
          close_or_explicitly_park_on_exit(path, k)
        else:
          synchronous_resume_or_finalize_on_exit(path, k))

install_handler(
  prompt_stack, prompt, handler, policy, handled_entry, sites, body_flow):
  installed = instantiate_handler_contract(
    handler.contract_template,
    prompt_stack, prompt, handled_entry)
  require every ResolveAtInstallation route in installed was resolved
    against prompt_stack to the nearest exact-entry prompt or RootOfEntry
  normal_summaries = []
  answer_worlds = []
  semantic_paths = []
  delegation_evidence = []
  outcomes = {}
  accumulate_body_path(path):
    match path:
      Returns(Θ, π, χ):
        ret = apply_return_contract(
          installed.return_contract, π, χ, Θ)
        normal_summaries += (ret.π, ret.χ)
        answer_worlds += ret.Θ
        semantic_paths += ret.summary
      Aborts:
        outcomes += Aborts
      Transfers(P):
        require preserves_park_contract(prompt, installed, policy, P)
        outcomes += Transfers(P)
  accumulate_continuation_path(path, D):
    match path:
      Returns(Θ, π, χ):
        ret = apply_continuation_contract(D, π, χ, Θ)
        normal_summaries += (ret.π, ret.χ)
        answer_worlds += ret.Θ
        semantic_paths += ret.summary
      Aborts:
        outcomes += Aborts
      Transfers(P):
        require preserves_park_contract(prompt, installed, policy, P)
        outcomes += Transfers(P)
  for path in body_flow.flow:
    accumulate_body_path(path)
  for κ in sites:
    require κ.installation_prompt == prompt
    require κ.route == prompt
    wire_clause = instantiate installed matching ClauseComputationV2 with
      operation skolems, prompt, κ.entry_world, κ
    internal_disposition = disposition_for(κ)
    clause_scope = resolve_clause_disposition_binder(
      binder = wire_clause.disposition_binder,
      required_namespace = SuffixLive,
      expected_site_slot = κ.site_slot,
      expected_type = type(internal_disposition),
      internal_token = internal_disposition)
    require clause_scope is exactly {
      SlotRefV1(SuffixLive,
        wire_clause.disposition_binder.slot)
        -> internal_disposition }
    clause = import_contract_computation_v2(
      wire_clause.computation,
      application_scope = installed.applications,
      return_scope = ∅,
      delegates_scope =
        HandlerClauseOnly(wire_clause.disposition_binder),
      disposition_scope = clause_scope)
    require every clause-level disposition evidence/usage reference
      resolves uniquely in clause_scope and none escapes that
      ClauseComputationV2; nested SuffixContractV2 live bindings use their
      own lexical scopes
    discharge imported handler environment is valid
      at κ.entry_world
    if κ.instantiated_signature.mode == ctl:
      discharge DuplicableEnv(κ.Π, κ.χ)
      discharge EnvValidAt(κ.Π, κ.χ, MultiShot)
      discharge ReplayableCleanup(κ.D.cleanup, κ.Π, κ.χ)
      discharge WorldForkSafe(κ.D.world)
    require κ.call_obligations is the sealed discharged evidence
      produced at this exact call or forward node
    require κ.install_obligations.instantiation_key ==
      (stageHandlerInstall(
         κ.instantiated_signature.obligation_ids),
       κ.actual_argument_summaries, κ.entry_world)
    discharge every obligation in κ.install_obligations using
      policy, κ.actual_argument_summaries, κ.entry_world
    for secondary in κ.secondary_sites.sites:
      require secondary.route ==
        resolve_route_at_installation(
          secondary.route_selector, prompt, prompt_stack)
      preserve secondary unless secondary.route == prompt
    for Async.await:
      derive task region from κ.actual_argument_summaries
      check install-await-site(κ, policy)
    for path in clause.flow:
      match path:
        Returns(_, π, χ):
          normal_summaries += clause.result_summary(
            κ.actual_argument_summaries, κ.Π, κ.χ,
            handler.env_provenance, handler.captures)
          answer_worlds += clause.answer_world
          semantic_paths += clause.summary
        Aborts:
          outcomes += Aborts
        Transfers(P):
          require clause owns the disposition recorded by P
          outcomes += Transfers(P)
        Delegates(κf):
          require κf.instantiated_signature ==
            κ.instantiated_signature
          require path.disposition_evidence.inner_disposition ==
            internal_disposition
          require path.disposition_evidence ==
            OpenToForwardedExclusive(
              internal_disposition, κf.site_slot, κf.continuation)
          require path.usage_context[
            internal_disposition] == Forwarded(κf)
          forward_evidence = derive_forward_residual_evidence(
            installed, prompt_stack, prompt, κf)
          require attributed_ok(
            forward_evidence.attributed_demand,
            forward_evidence.attributed_suspension)
          public_flow = consume_delegation(
            internal_path = path,
            routed_site = κf,
            original_continuation = κ.D)
          require public_flow ==
            project_public_continuation_flow(κ.D, κf)
          delegation_evidence += sealed_forward_evidence(
            κ, κf, public_flow, forward_evidence)
          for public_path in public_flow:
            require public_path is FlowPathV1
            accumulate_continuation_path(public_path, κ.D)
  require all answer_worlds are equal
  if normal_summaries is not empty:
    (πo, χo) = join(normal_summaries)
    outcomes += Returns(the unique answer_world, πo, χo)
  δout = handle_summary(
    body_flow.summary, handled_entry, installed,
    policy, sites, body_flow.flow, semantic_paths)
  require no outcome is Delegates
  Δhandler = instantiate_handler_residual(
    installed, prompt_stack, prompt,
    sites, body_flow, delegation_evidence)
  return sealed evidence(
    outcomes = outcomes,
    semantic_summary = δout,
    handler_residual = Δhandler)

eliminate_entry_with_contract(
  prompt, handler, body, entry, sites, install):
  (Δhere, Δouter) =
    partition(body.attributed_demand,
              demand.route == prompt)
  require every primary site in Δhere is in sites
  Δhandler = install.handler_residual
  Δout = union(Δouter, Δhandler)
  εout = eraseDemand(Δout)
  sout = handle_install_suspension(
    body.suspension, Δhere, install)
  require attributed_ok(Δout, sout)
  return body with
    type = handler.answer_type
    flow = install.outcomes
    row = εout
    attributed_demand = Δout
    suspension = sout
    summary = install.semantic_summary
    typed_core =
      fresh_prompt_node(
        prompt, handled_node(prompt, body.typed_core, handler))
```

`Lambda` branch保留 definition $Theta$ 以计算 lexical captures，但在检查 body前
必须用 fresh $S_"call"$ 替换 ambient prompt stack并把 route stage设为 `Call`。
`abstract_lambda_call_context` 随后把该 symbolic stack上的 route统一封成
`ResolveAtCall` 并量化 $S_"call"$；任何来自 `ctx.prompts` 的 concrete prompt
都会被拒绝。该步骤与 T-Lambda-Paths 的 $S_f$ 是同一算法，不是 optimizer。
随后唯一一次 `abstract_parametric_flow` 遍历完整 flow：Returns paths共同产生
normal world/result projection，Aborts/Transfers产生 bottom normal projection但
仍贡献参数相关 BoundarySafe/StableAcross/Outlives obligation；最终 $Q$ 是所有
path obligation的 normalized union。存在 Returns时也不得跳过 terminal paths，
`abstract_contract_computation_v2` 把这些 path-local row/demand/suspension/
summary/usage/phase/Q/$Lambda$ 一起写入 `LiteralPathsV2` 或基于同一
`AppliedContractV2` 的 Invoke/PathBind term；不存在独立 field projection。
`abstract_flow` 只保存 outcome projection，不能替代这一步 obligation
abstraction或原子 application ledger。

Handler definition只捕获 `Πenv/χenv`，不捕获 definition-site prompt stack。
`with_route_stage(HandlerInstall)` 令 schema内命中 symbolic handled entry的
site指向 $p_"inst"$，其余普通 return/clause residual site编码为
`ResolveAtInstallation`，不提前降为 definition-stack prompt或 root。
`(Sinst,pinst,ainst).C` 在每次 `Handle` 处用 actual
`(prompt_stack,prompt,handled_entry)` 一次实例化；同一个 first-class handler
在两种 outer stack安装会得到各自唯一的 residual routes。安装后才可消去
这些 route selector，`install_handler` 拒绝仍含未解析 installation route
或来自 definition stack的 concrete prompt。
同一次 instantiation还必须消费每个
`ClauseComputationV2.disposition_binder`：
`resolve_clause_disposition_binder` 逐字段检查 exact site/type与 lexical scope，
只建立一个 `SuffixLive(binder.slot) → disposition_for(κ)` 映射，然后才导入
flow/evidence/usage。后续 Delegates检查只能使用该 resolved token；再次独立
调用 `disposition_for(κ)`、按 slot数字猜 token或让该 disposition ref跨
clause scope逃逸都不是合法 importer实现；nested `SuffixContractV2` 的其他
live slot仍按各自 lexical scope独立验证。

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
  "request"(
    "demandKey"("Demand"(kappa,p,"Anon"("Async"),
      "await","Primary")),
    "MaySuspend")
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
    `ParkContractV2`/claim identity。Terminal entries不声称不存在的
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
  secondary_site_set       // Closed in TR₀; no rigid row-slot variant
  secondary_suspension
  secondary_summary
  suspension_bound
  result_summary_transformer
  required_phase
  site_obligations
}

TypedFunctionContractHIR {
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

once yield() -> Unit resumes next may_suspend
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
