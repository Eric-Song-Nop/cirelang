#import "../shared.typ": *

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
