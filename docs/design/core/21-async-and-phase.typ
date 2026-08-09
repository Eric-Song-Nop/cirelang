#import "../shared.typ": *

= Async、suspension 与 phase

== Task result parameter 与 frozen outcome protocol

Core 使用：

$
  "Task"[rho,R]
$

$R$ 是 caller/producer选择并由 type完整固定的 result；它不是 implementation可选择的 error
channel。Generic Task只广播 exact R。需要 first-party failure/cancel时唯一 nominal form是
`TaskOutcome[A,E]=Succeeded(A)|Failed(E)|Cancelled(CancelReason)`；只有
`Task[rho,TaskOutcome[A,E]]` 可调用 sealed central `Task::cancel`。Owner close不伪装成该 enum，
也不把 failure暗中转为 Result或 effect。

`Cire-v1.0` 把 `Task[ρ,R]` 定义为可复制的 broadcast completion handle，允许多个 waiter；
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
