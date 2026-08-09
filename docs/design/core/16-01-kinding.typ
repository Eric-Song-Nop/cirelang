#import "../shared.typ": *

= Kinding、identity 与 well-formedness

== 基本 kinding judgment

$
  K ; I ⊢ A : "Type"
$

$
  K ⊢ F : "Effect"
$

$
  K ; I ⊢ epsilon : "EffectRow"
$

$
  I ⊢ i : F @ rho
$

#irule(
  [K-Cap],
  (
    [$I ⊢ i:F@rho$],
    [$K ⊢ F : "Effect"$],
  ),
  [$K; I ⊢ "Cap"[i, F] : "Type"$],
)

#irule(
  [K-Next],
  (
    [$I ⊢ i : "FrameClock" @ rho$],
    [$K; I ⊢ A : "Type"$],
    [$K;I ⊢ L:"LaterContract"(i,A)$],
  ),
  [$K; I ⊢ "Next"[i,A,L] : "Type"$],
)

只有 sealed `Next` constructor 接受带 `FrameClock` evidence 的
`CapId` argument。一般 type constructor仍只能接受其声明 kind 的参数。

下文使用 capture-avoiding abbreviation：

$
  "ClockPkg"[rho,A]
  = exists i:"ClockId"("FrameClock",rho),
      S:"ClockPackageSummary"(i,A).A
$

`ClockId(FrameClock,ρ)` formation需要 resolver给出的 sealed
`CanonicalFrameClockV2` witness。普通 $F:"Effect"$、同名用户 effect或伪造的
`clock_refinement` 都不能创建 Clock namespace；未来其它 clock family必须以
新 schema加入显式 `ClockFamilyWitness`。

#irule(
  [K-Cap-All],
  (
    [$K ⊢ F:"Effect" quad K ⊢ rho:"OwnerRegion"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho ⊢ A:"Type"$],
  ),
  [$K;I ⊢ (forall i:"CapId"(F,rho).A):"Type"$],
)

#irule(
  [K-Evidence-All],
  (
    [$K;I ⊢ P:"Evidence" quad p ∉ "dom"(K)$],
    [$K,p:P;I ⊢ A:"Type"$],
  ),
  [$K;I ⊢ (forall p:P.A):"Type"$],
)

#irule(
  [K-Clock-Exists],
  (
    [$K ⊢ rho:"OwnerRegion"$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:"FrameClock"@rho ⊢ A:"Type"$],
    [$K;I,i:"FrameClock"@rho ⊢ "ClockPackageSummary"(i,A):"Evidence"$],
  ),
  [$K;I ⊢ "ClockPkg"[rho,A]:"Type"$],
)

Evidence kind只量化满足下式的 sealed summary：

$
  S=⟨pi_A,chi_A,F_"lease",P_"owner"⟩
  quad
  F_"lease"=⟨emptyset,"same","direct"("NoSuspend"),delta_"release"⟩
$

$P_"owner"$ 证明 shared child-Owner handle、lease acquire/release线性化和
最终 dispose幂等。`ReleaseHidePath` 对每个动态 exit恰好顺序执行一次
$F_"lease"$；它不增加 row/demand/suspension，但把
$delta_"release"$ 顺序组合进该 path summary。private clock identity即使只藏
在另一个 entry的 route、actual summary、secondary site、Q/$Lambda$、
cleanup/live binding、Park resumption或 contract computation中，也不能借
public observer normalization逃逸。

#irule(
  [T-Cap-Intro],
  (
    [$K ⊢ F:"Effect" quad K ⊢ rho:"OwnerRegion"$],
    [$i ∉ "dom"(I)$],
    [$K;I,i:F@rho;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
    [$i ∉ "fv"(pi,chi)$],
  ),
  [$K;I;Phi@Theta ⊢_v "CapAbs"(i,v) ⇒ (forall i:"CapId"(F,rho).A) @[pi] ▷ chi$],
)

#irule(
  [T-Cap-Elim],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ (forall i:"CapId"(F,rho).A) @[pi] ▷ chi$],
    [$I ⊢ j:F@rho$],
  ),
  [$K;I;Phi@Theta ⊢_v v[j] ⇒ A[j/i] @[pi] ▷ chi$],
)

#irule(
  [T-Clock-Pack],
  (
    [$I ⊢ j:"FrameClock"@rho$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A[j/i] @[pi_v] ▷ chi_v$],
    [$"ClockPackageSafe"(rho,j,A[j/i],pi_v,chi_v) ⇓ S_j$],
    [$S_i="closeClockSummary"(j⇒i,S_j)$],
    [$chi_p="sealClockCapture"(j,rho,chi_v,S_j) quad j ∉ "fv"(chi_p)$],
  ),
  [$K;I;Phi@Theta ⊢_v "packClock"[j](v) " as " "ClockPkg"[rho,A] ⇒ "ClockPkg"[rho,A] @["Owner"(rho)] ▷ chi_p$],
)

#irule(
  [T-Clock-Unpack-Paths],
  (
    [$K;I;Phi@Theta ⊢_v p ⇒ "ClockPkg"[rho,A] @[pi_p] ▷ chi_p$],
    [$i ∉ "dom"(I) quad S_k:"ClockPackageSummary"(i,A) " fresh hidden"$],
    [$"ClockFamilyWitness"("FrameClock")="CanonicalFrameClockV2"$],
    [$"openClockLease"(p,Theta,i,S_k)=⟨Theta_p,l⟩$],
    [$"packagePayload"(S_k)=(pi_x,chi_x) quad Theta_x="bind"(Theta_p,x:A @[pi_x] ▷ chi_x)$],
    [$K;I,i:"FrameClock"@rho;Phi;Omega@Theta_x;S ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon_b;Delta_b;s_b;delta_b ⊣Omega_b$],
    [$forall t in cal(F)_b.
      "ClockPackageOutwardSafe"(i,S_k,B,t,"evidence"(t))$],
    [$t'="ReleaseHidePath"(S_k,l,i,x,t)
      quad "tag"(t')="tag"(t)$],
    [$cal(F)_o="normalize"({t' | t in cal(F)_b})$],
    [$⟨epsilon_o,Delta_o,s_o,delta_o,Omega_o⟩
      ="observeReleasedPaths"(cal(F)_o,S_k,Omega_b)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
      "unpackClock"[i,x](p,e)) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)
