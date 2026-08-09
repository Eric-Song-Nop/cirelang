#import "../shared.typ": *

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
PrivateCheckpointPayload(A) if Shareable(A)  // sealed runner evidence only
Shareable(A ->^C B)
  only if the closure contract says
    DuplicableEnv(C.provenance, C.captures)
  and its provenance passes the requested storage boundary
```

`Cap`、`Owner`、`Resume`、`CompletionSource`、`CompletionPort` 与 sealed private
commit claim不因“机器上可以复制几个 bits”而成为
broadcast payload。`CompletionSource` 是不可复制的 introduction
authority；`CompletionPort` 的多个宿主 handle可共享同一 CAS claim，因而
capture可满足 `Duplicable`，但它不是 `Shareable(R)` 的结果广播。
Private claim的多个 runtime refs可共享同一原子 state，但它没有 user value/type；它受
generation boundary约束且不满足 `Shareable`。第一方容器若要声明额外 `Shareable` instance，
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
