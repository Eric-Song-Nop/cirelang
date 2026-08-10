#import "../shared.typ": *

= Legacy incremental replacement proof machine <incremental-machine>

#warning([
  这组状态/不变量作为 fixed-Epoch与 single-claim proof lemma保留；任何 user-visible Plan/Commit、
  generic Event callback或开放 checkpoint transition已被 @checkpoint-runner-v1 删除。Successor
  runtime trace必须投影到 sealed runner state，不能直接实例化本节 legacy API。
])

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
