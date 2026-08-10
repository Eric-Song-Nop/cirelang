#import "../shared.typ": *

= Retained TR0 calculus：Cire-v1.0 subordinate proof substrate <retained-tr0-calculus>

#status(
  [Successor stacking rule],
  [
    从本 anchor 至文档结尾保留 approved TR0 calculus 的定义、算法草图、例子与 proof
    anchors。后续同级标题不会重启 TR0 authority。`Cire-v1.0` 读取它们时必须先应用
    本章的 M3、package identity、ordinary-foundation、registry 与 first-party protocol delta。
    任一写成 TR0、V1/V2-only、generic Plan/Commit、三参数 Resource 或开放 checkpoint 的 fragment
    只属 legacy decoder/proof profile，不能覆盖 @cire-v1-profile 的 schema、surface、
    diagnostic、API 或 runtime meaning。冲突时只有 @successor-rule-anchors-v1 是 canonical landing point。
  ],
)

本 retained substrate 原标题为“Surface 到 Core 的语法与 elaboration”；它现在只保留 temporal/
effect proof notation。Source grammar、normalization 与 complete successor elaboration 的唯一 authority是
@surface-authority-import 及本入口前面的 surface 章节。

== Kinds

$
  kappa ::= "Type" | "Effect" | "EffectRow" | "CapId" | "ClockId"
          | "OwnerRegion" | "Phase" | "Evidence"
          | kappa_1 -> kappa_2
$

`CapId(F,ρ)` 是一般、受限的生成式 capability identity kind；只有
`freshcap`/handler application可以引入。Retained calculus 的 `ClockId(FrameClock,ρ)` 是
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
scope满足 $K ⊢ d_x:kappa_x$。`Cire-v1.0` 要求 $a_x=0$；nonzero arity稳定拒绝
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
