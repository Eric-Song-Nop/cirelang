#import "../shared.typ": *

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
  [`Resource[ρ,K,A,E]`], [Live key 到 outcome Task generation 的桥],
  [`SwitchLatest + keep-last-good`；K/A/E boundary-safe],
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

普通 `ctl` 只授予 general control。`Cire-v1.0` 固定只由 sealed first-party checkpoint
runner获得额外 Kernel contract：

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
  frame : FrameClock,
  input : Signal[frame, A],
  transform : (A) -> B,
) -> Signal[frame, B] ! {} {
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

== Event nominal（legacy generic subscription excluded）

#warning([
  `Event[rho,E]` nominal与 Shareable/order/multiplicity facts保留；本小节下列 `on/on_async` signatures
  只记录旧候选，不属于 `Cire-v1.0` source、registry或 CallableInterface。Successor唯一 event entry是
  @signal-ui-protocol-v1 的 typed UI occurrence；实现不得从这段恢复 generic subscription。
])

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

== Resource legacy sketch（由 successor protocol替换）

#warning([
  下列 `Resource[rho,K,R]` policy-parameter sketch已被 @resource-protocol-v1 的 exact
  `Resource[rho,K,A,E]` SwitchLatest + keep-last-good machine替换。Successor没有 policy parameter或
  implementation自由选择。
])

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

== Legacy generic Compute / Commit proof notation

#warning([
  本节以下 Plan/Ticket/Gate rule只供旧 incremental proof anchor。`Cire-v1.0`无 public Plan/Commit
  type、operation或 interface；唯一可执行 meaning是 @checkpoint-runner-v1 与
  @signal-ui-protocol-v1 的 sealed private single-claim machines。
])

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
