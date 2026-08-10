#import "../shared.typ": *

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
