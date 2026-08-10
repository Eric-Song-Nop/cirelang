#import "../shared.typ": *

== Sealed PackedNext surface

#warning([
  本节的 static path/gate rules由 successor保留，但所有 `PackedNextPackageV2` serialization与
  `PackedNextControlProtocolV2` state text只属 legacy decoder。`Cire-v1.0` runtime及 artifact必须使用
  @packed-next-protocol-v1 的 `PackedNextProtocolV1` Building/Open/Closing/Closed machine，两个 profile
  disjoint，不能用 alias或 hash旁路混合。
])

Surface `PackedNext[A]` elaborates to opaque Core `PackedNext[ρ,A]`; $rho$ is
the storage Owner index inferred from `under`, like the hidden Owner index of
Task/CompletionSource. The public type does not expose the runner's Owner.
Legacy proof notation把 package称为 `PackedNextPackageV2`；successor sealed value carries
`PackedNextProtocolV1` private-package evidence that first binds a
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

Signature/kind stage证明为 direct capability binder的 surface `x : F` 参数同时引入
implicit $i$ 和 `x:Cap[i,F]`，等价于 T-Cap-Intro 后再用 T-Lambda。若 F 不是 resolved
Effect family或 parameter不是 direct capability position，则它只是普通 value type检查并不得引入
identity。`freshcap` scope内，
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
    [$K;I ⊢ K_t:"Type" quad K;I ⊢ A:"Type" quad K;I ⊢ E:"Type"$],
    [$"Shareable"(K_t) quad "Shareable"(A) quad "Shareable"(E)$],
    [$"AsyncBoundarySafe"(rho,A) quad "AsyncBoundarySafe"(rho,E)$],
  ),
  [$K;I ⊢ "Resource"[rho,K_t,A,E]:"Type"$],
)

#irule(
  [K-Runtime-Authority],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$X = "Owner"$],
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

Legacy private checkpoint proof中写作 `Plan[A]` 的对象在 successor只由 sealed runner内部形成；
它没有 source/public kinding rule。
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
