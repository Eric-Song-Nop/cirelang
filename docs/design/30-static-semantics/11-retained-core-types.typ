#import "../shared.typ": *

== Core types

#warning([
  下列 compact grammar 是 retained TR0 proof notation。Successor substitution固定为
  `Resource[rho,K,A,E]`；`Plan[A]`、`CommitTicket`、`CommitGate`只可解释为 sealed runtime-private
  checkpoint/UI state，不能形成 source type、package declaration、CallableInterface或 public TypeRef。
  `Event[rho,A]` nominal保留，但没有 generic `on/on_async` formation rule。
])

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
