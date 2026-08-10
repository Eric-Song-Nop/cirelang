#import "../shared.typ": *

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

一个典型 retained TR₀ owner-park case 的关键推导链是：

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
配套的 answer-transform derivation 另外固定
$A="Int" != B="Array"["Int"]$，避免 identity suffix掩盖 source/answer
接线错误；这里陈述的是 retained Core proof case，不要求 v1 source suite 暴露 raw
completion-source API。

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
