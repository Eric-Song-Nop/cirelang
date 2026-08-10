#import "../shared.typ": *

= Effect、operation 与 handler typing <handler-typing>

== Operation signature

Signature lookup：

$
  K(F, "op") =
  forall bar(alpha).
  (bar(A)) -> B
  @[m, zeta, d, R_o, Phi_o, P_o, Sigma_o]
$

$m$ 是最大 resumption mode，$zeta$ 是 successful resume transition，
$d$ 是 suspension 上界，$R_o$ 是 argument summary到 result
provenance/capture的 transformer，$Phi_o$ 是 invocation precondition，
$P_o$ 是 suspension/parking obligation，且
$Sigma_o=⟨Lambda_"secondary",s_"secondary",delta_"secondary"⟩$
是 operation declaration 的 secondary effect/suspension/summary contract。
每个 $Lambda_"secondary"$ entry都是带独立 stable site slot、receiver、
operation和 route selector的 `SecondarySiteV1`；实例化后产生
$Delta_"secondary"$，其 public row才是
$"eraseDemand"(Delta_"secondary")$。
其中 $s_"secondary"$ 是以相同 stable site slot为 key的 suspension
template；实例化必须同时产生
$(Delta_"secondary",s_"secondary"')$ 并证明
`AttributedOK(Δsecondary,ssecondary')`，不能只实例化 row demand后把
suspension按 entry另算。
`TR₀` 的 `OperationSecondaryAnnotation` 只接受 closed row literal。
`ElabSecondaryRow(R, operationOrigin)` 因而能对 normalized closed row中的
每个 entry生成 finite synthetic site slot和 `AnyOperationOfEntry`
selector；若以后有更精确 summary可收紧为 exact operation selector。每个
synthetic site仍独立执行 route resolution，不能共享 primary prompt。
`! E` 与 `! {Audit,..E}` 作为 operation secondary annotation由 grammar/
validation拒绝；open secondary-row slot是未来 schema version的扩展，V1
不会默默丢弃 rigid tail。

#irule(
  [WF-Operation-Secondary-Closed],
  (
    [$K;I ⊢ R_"sec" ⇝ epsilon_"sec" ⊣ C_"sec"$],
    [$"ClosedRow"(epsilon_"sec")
      quad "NoRigidRowVars"(epsilon_"sec",C_"sec")$],
    [$"ElabSecondaryRow"(epsilon_"sec","operationOrigin")
      ⇓ ⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
  ),
  [$K;I ⊢_"op-secondary" R_"sec" ⇝
    "SecondarySiteSetV1"{
      "kind":"Closed","sites":Lambda_"sec"}
    ;hat(s)_"sec";delta_"sec"$],
)

没有 annotation时使用 `$R_"sec"={}$` 的同一 rule，而不是另一条省略
检查的捷径。`OperationDecl` 必须先通过这个 WF judgment，才能进入
$K(F,"op")$ signature table。
Operation 自身不把 handler policy写入 family；
policy 来自具体 handler instance。

对 $zeta="next"(i)$，$P_o$ 还包含不可伪造的
`RequiresTickWitness(i)` obligation。T-Operation只记录“正常 continuation
若返回需要 next world”；真正 handler安装时，`InstallOK` 必须从 sealed clock
runner取得 `TickWitness(i)`。普通 clause直接 inline `resume` 不能构造该
witness。

调用点先实例化 fresh type metavariable并统一参数。Named 与 anonymous dispatch
只在 row entry 上不同：

$
  "entry"("F::op") = "Anon"(F)
$

$
  "entry"("cap.op") = "Named"(i, F)
$

== Operation call

令 `Args` judgment 按左到右顺序检查参数并组合 row、summary、capture 与
temporal context：

$
  K;I;Phi;Omega@Theta;S
  ⊢ bar(e) ⇐ bar(A)
  ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a@Theta_a⊣Omega_a
$

上式只是 all-return projection。Normative argument fold返回
`ArgsReturns(Ξ,Θ,Ω)` 与 terminal paths的 finite set：

#irule(
  [T-Args-Nil-Paths],
  ([$"emptyArgs"$],),
  [$K;I;Phi;Omega@Theta;S ⊢_"args" [] ⇓
    {"ArgsReturns"([],Theta,Omega)} !
    emptyset;emptyset;"direct"("NoSuspend");delta_"pure"$],
)

#irule(
  [T-Args-Cons-Paths],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$forall r in "returns"(cal(F)_e).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢_"args"
      bar(e) ⇐ bar(A) ⇓ cal(F)_"rest"(r) !
      epsilon_r(r);Delta_r(r);s_r(r);delta_r(r)$],
    [$cal(F)_o="PathBind"(cal(F)_e,
      r => "prependArgSummary"(
        "summary"(r),cal(F)_"rest"(r)))$],
    [$(Delta_o,s_o,delta_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_e,s_e,delta_e,
        {Delta_r,s_r,delta_r})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"args"
    (e,bar(e)) ⇐ (A,bar(A)) ⇓ cal(F)_o !
    epsilon_o;Delta_o;s_o;delta_o$],
)

`ArgsReturns.Ξ` 保留每个 actual argument的 type/nominal identity、
provenance/capture与 path-local world；abort/transfer path没有伪造的
argument vector，后续 operation dispatch不会执行。

以下 normal-returning rule只适用于 $m != "abort"$：

#irule(
  [T-Operation],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @[m,zeta,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$m != "abort"$],
    [$sigma = "freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @[m,zeta_sigma,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_sigma
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad p="resolveRoute"(S,a)
      quad zeta_a="instantiateReceiver"(zeta_sigma,a)$],
    [$zeta_a(Theta_a)=Theta'$],
    [$R_sigma(bar(pi_a),bar(chi_a))=(pi_B,chi_B)$],
    [$Xi_k="ActualSummaries"(
      bar(A)_sigma,bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_k^"call"="instantiate"(
      "stageCall"(P_sigma),Xi_k,I,Theta_a)
      quad "Discharge"(Q_k^"call")$],
    [$Q_k^"install"="instantiate"(
      "stageHandlerInstall"(P_sigma),Xi_k,I,Theta_a)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$(Delta_"sec",s_"sec")=
      "instantiateSecondaryContract"(
        Lambda_"sec",hat(s)_"sec",kappa,S)$],
    [$"AttributedOK"(Delta_"sec",s_"sec")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"("demandKey"(d_0),d_sigma) ⊔ s_"sec"
      quad "AttributedOK"(Delta_"call",s')$],
    [$"PhaseAllows"(Phi,Phi_sigma)$],
    [$"Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa,a,Q_k^"call",Q_k^"install",Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "op"[a]("op",bar(e)) ⇒
    B_sigma @[pi_B] ! epsilon_"call";Delta_"call" ▷
    s';delta_a⊗delta_"sec";chi_B @Theta'⊣Omega_a$],
)

`abort` operation 没有 successful $Theta'$。为避免用任意 world伪造正常
返回，另设 abortive flow judgment：

$
  K;I;Phi;Omega@Theta;S
  ⊢_"abort" e ! epsilon;Delta ▷ s;delta ⊣ Omega'
$

#irule(
  [T-Operation-Abort],
  (
    [$K(F,"op")=O quad O=forall bar(alpha).(bar(A))->B @["abort",bot,d_o,R_o,Phi_o,P_o,Sigma_o]$],
    [$sigma="freshInstantiation"(bar(alpha))$],
    [$sigma(O)=(bar(A)_sigma)->B_sigma @["abort",bot,d_sigma,R_sigma,Phi_sigma,P_sigma,Sigma_sigma]$],
    [$Sigma_sigma=⟨Lambda_"sec",hat(s)_"sec",delta_"sec"⟩$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_sigma
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad p="resolveRoute"(S,a)$],
    [$Xi_k="ActualSummaries"(
      bar(A)_sigma,bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_k^"call"="instantiate"(
      "stageCall"(P_sigma),Xi_k,I,Theta_a)
      quad "Discharge"(Q_k^"call")$],
    [$Q_k^"install"="instantiate"(
      "stageHandlerInstall"(P_sigma),Xi_k,I,Theta_a)$],
    [$d_0="Demand"(kappa,p,a,"op","Primary")$],
    [$(Delta_"sec",s_"sec")=
      "instantiateSecondaryContract"(
        Lambda_"sec",hat(s)_"sec",kappa,S)$],
    [$"AttributedOK"(Delta_"sec",s_"sec")$],
    [$Delta_"call"=Delta_a∪{d_0}∪Delta_"sec"
      quad epsilon_"call"="eraseDemand"(Delta_"call")$],
    [$s'=s_a ⊔ "request"("demandKey"(d_0),d_sigma) ⊔ s_"sec"
      quad "AttributedOK"(Delta_"call",s')$],
    [$"PhaseAllows"(Phi,Phi_sigma) quad "Allowed"(Phi,epsilon_"call",s',delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa,a,Q_k^"call",Q_k^"install",Lambda_"sec")$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢_"abort"
    "op"[a]("op",bar(e)) !
    epsilon_"call";Delta_"call" ▷
    s';delta_a⊗delta_"sec" ⊣Omega_a$],
)

#irule(
  [T-Operation-Paths],
  (
    [$K(F,"op")=O quad
      sigma="freshInstantiation"("typeParams"(O))
      quad B_sigma="result"(sigma(O))$],
    [$kappa="freshLexicalSite"(S)
      quad a="entry"("receiver",F)
      quad o="resolvedOperation"(F,"op")$],
    [$K;I;Phi;Omega@Theta;S ⊢_"args"
      bar(e) ⇐ "params"(sigma(O)) ⇓ cal(F)_"args" !
      epsilon_a;Delta_a;s_a;delta_a$],
    [$forall r in "argReturns"(cal(F)_"args").
      "BuildOperationPath"(
        kappa,a,o,sigma(O),"summaryVector"(r),"world"(r),
        "usage"(r),I,S)
      ⇓ ⟨cal(F)_"op"(r),Delta_"op"(r),
        s_"op"(r),delta_"op"(r)⟩$],
    [$cal(F)_o="terminal"(cal(F)_"args") ∪
      "unionPaths"({cal(F)_"op"(r) mid
        r in "argReturns"(cal(F)_"args")})$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_a,s_a,delta_a,
        {Delta_"op",s_"op",delta_"op"})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(B_sigma,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_(B_sigma)(
    "op"[a]("op",bar(e))) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`BuildOperationPath` 是 T-Operation/T-Operation-Abort 对一个完整
`ArgsReturns` path的共同 suffix：它建立 primary/secondary demand与
suspension、执行 phase/Allowed检查、附加 site obligations，并按 mode产生
`Returns` 或 `Aborts`。两条 single-flow rule只是这个 judgment在 arguments
没有 side path时的 projection。$kappa/a/o$ 在 argument PathBind外固定；
所有 returning paths共享同一个 alpha-normalized lexical site slot，同时
仍以 exact receiver entry区分 named与anonymous demand。每个 builder还以
该 path的 actual summaries/world和 $I$ 实例化并 discharge
`stageCall(Pσ)`；site保存已验证的 call evidence/ids，并保留使用同一
actual环境实例化但尚未 discharge 的 `stageHandlerInstall(Pσ)`。

Kernel forwarding只允许在正在处理的 primary site内使用。令当前
$kappa$ 携带 route $p$：

#irule(
  [T-Forward-Delegate],
  (
    [$kappa=⟨ell,p,a,o,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$"CurrentDisposition"(k,kappa)
      quad Omega(k)="Open"(q)$],
    [$"StrictOuterPrompt"(S,p,p_"outer",a)$],
    [$"TailOnly"("forward"[p_"outer"](a,o,bar(e)))$],
    [$O_k=(bar(A)_k)->B_k
      @[m,zeta_k,d_k,R_k,Phi_k,P_k,Sigma_k]$],
    [$K;I;Phi;Omega@Theta;S ⊢ bar(e) ⇐ bar(A)_k
      ⊣ bar(pi_a);bar(chi_a);epsilon_a;Delta_a;s_a;delta_a
      @Theta_a⊣Omega_a$],
    [$Omega_a(k)="Open"(q_a)$],
    [$Xi_f="ActualSummaries"(
      "params"(O_k),bar(pi_a),bar(chi_a),Theta_a)$],
    [$Q_f^"call"="instantiate"(
      "stageCall"(P_k),Xi_f,I,Theta_a)
      quad "Discharge"(Q_f^"call")$],
    [$Q_f^"install"="instantiate"(
      "stageHandlerInstall"(P_k),Xi_f,I,Theta_a)$],
    [$h_f="ForwardSiteHeader"(
      "stableSiteSlot":ell,
      "installationPrompt":p_"outer",
      "entry":a,"operation":o,
      "continuation":"continuation"(kappa),
      "entryWorld":Theta_a,
      "actualArgumentSummaries":Xi_f,
      "instantiatedSignature":O_k,
      "callObligations":Q_f^"call",
      "installObligations":Q_f^"install")$],
    [$(Delta_"sec",s_"sec",delta_"sec",Sigma_f)=
      "instantiateSecondaryContract"(
        Sigma_k,h_f,S)$],
    [$kappa_f="SealForwardSite"(
      h_f,"secondarySites":Sigma_f)$],
    [$d_f="Demand"("siteSlot"(kappa_f),p_"outer",a,o,"Primary")
      quad s_"primary"="request"("demandKey"(d_f),d_k)$],
    [$Delta_o=Delta_a∪{d_f}∪Delta_"sec"
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$s_o=s_a⊔s_"primary"⊔s_"sec"
      quad "AttributedOK"(Delta_o,s_o)$],
    [$"PhaseAllows"(Phi,Phi_k)
      quad "Allowed"(Phi,epsilon_o,s_o,delta_a⊗delta_"sec")$],
    [$"AttachSiteObligations"(
      kappa_f,a,Q_f^"call",Q_f^"install",
      Sigma_f)$],
    [$Omega_f=Omega_a[k↦"Forwarded"(kappa_f)]$],
    [$e_f="SealForwardDispositionEvidence"(
      k,kappa,kappa_f,Omega_a,Omega_f)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "clauseBody"_X(
    "forward"[p_"outer"](a,o,bar(e))) ⇓
    {"Delegates"(kappa_f,e_f)} ! epsilon_o;Delta_o;
    s_o;delta_a⊗delta_"sec" ⊣Omega_f$],
)

#irule(
  [T-Forward-Paths],
  (
    [$kappa=⟨ell,p,a,o,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$O_k="instantiatedSignature"(kappa)
      quad B_k="result"(O_k)
      quad "CurrentDisposition"(k,kappa)
      quad Omega(k)="Open"(q)$],
    [$"StrictOuterPrompt"(S,p,p_"outer",a)$],
    [$"TailOnly"("forward"[p_"outer"](a,o,bar(e)))$],
    [$K;I;Phi;Omega@Theta;S ⊢_"args"
      bar(e) ⇐ "params"(O_k) ⇓ cal(F)_"args" !
      epsilon_a;Delta_a;s_a;delta_a$],
    [$forall r in "argReturns"(cal(F)_"args").
      "usage"(r)(k)="Open"(q_r) and
      "BuildForwardPath"(
        k,kappa,p_"outer",O_k,
        "summaryVector"(r),"world"(r),"usage"(r),S)
      ⇓ ⟨cal(F)_f(r),kappa_f(r),
        Delta_f(r),s_f(r),delta_f(r),Omega_f(r)⟩$],
    [$cal(F)_o="terminal"(cal(F)_"args") ∪
      "unionPaths"({cal(F)_f(r) mid
        r in "argReturns"(cal(F)_"args")})$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_a,s_a,delta_a,
        {Delta_f,s_f,delta_f,Omega_f})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "ForwardSites"(cal(F)_o)={kappa_f(r)}$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "clauseBody"_(B_k)(
    "forward"[p_"outer"](a,o,bar(e))) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`StrictOuterPrompt(S,p,pouter,a)` 要求两个 prompt都 live、`pouter` 在 stack
中严格位于 $p$ 外层且仍处理精确 entry $a$；family相同不够。Source
没有任意 prompt操作，这两个 rule只服务 resolver生成的 Kernel forward。
`ForwardSiteHeader` 保留 lexical `siteSlot(κ)` 作为 stable slot；
secondary重新路由后，`SealForwardSite` 创建完整 routed contract
$kappa_f$：它的 installation prompt 是 $p_"outer"$，
entry world与 actual summaries来自本次 transformed arguments；它严格复用
原 site已经实例化的 exact $O_k$（包括同一次 invocation的 type arguments），
再以新 summaries 重建分阶段的 call/install evidence。Forward绝不对
`K(F,o)` 或 $O_k$ 执行 fresh instantiation，因此 nullary polymorphic
operation也不能在 reroute时换 type arguments。secondary site以
header为 parent重新路由；它不沿用 inner prompt或旧 $Xi_k$，最终 exact
`SecondarySiteSetV1` 封入 `κf.secondary_sites`。side evidence只能由
该 sealed field投影，不能成为缺字段的第二来源。

Forward 采用 delegation 语义，不是普通 returning subcall：
$kappa_f$ 唯一取得原 $D_k$ 的处置权，flow产生 terminal
`Delegates(κf,ef)`（正文省略 evidence参数时仍指该 pair），且原 token由
`Open(q)` 原子转换为 `Forwarded(κf)`。
`DispositionComplete` 把 `Forwarded` 视为已经完整处置；inner clause随后
不能再次 resume、finalize或 park。`BuildForwardPath` 执行同一原子转移；
argument evaluation产生 mixed flow时，T-Forward-Paths保留每条 terminal
argument path，并只在该 path-local usage仍为 `Open(q)` 时把
`ArgsReturns` path原子变成 `Delegates`。argument自身已经 finalize、park
或 forward当前 $k$ 的 returning path因此没有推导。

Algorithmic `CheckResult.flow` 因而是这些 outcome 的有限 path set。
Abortive flow可以在 expected type下使用，但不产生 normal output world；
sequence只把 `Returns` entries送入 suffix，并保留既有
`Aborts/Transfers/Delegates` entries；branch join取 set union并只对 Returns projection
做 world/result join。这样 `abort` 既不是普通
`Never → A` coercion，也不能贡献一个虚假的 clock lock。

令 $E_s$ 是不跨越 `handle`、`delay`、`live` 或其他 runner delimiter 的
left-to-right strict evaluation context。`Prefix` 只总结到 hole之前已经
执行的部分：

$
  "Prefix"(E_s,Theta,Omega)
  =
  ⟨Theta_h,Omega_h,Delta_p,s_p,delta_p⟩
$

#irule(
  [T-Ctx-Paths],
  (
    [$"Prefix"(E_s,Theta,Omega)=
      ⟨Theta_h,Omega_h,Delta_p,s_p,delta_p⟩$],
    [$K;I;Phi;Omega_h@Theta_h;S ⊢ "body"_X(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$forall r in "returns"(cal(F)_e).
      "FrameStep"(E_s,r,S) ⇓
      cal(F)_"frame"(r) !
      Delta_"frame"(r);s_"frame"(r);delta_"frame"(r)
      ⊣Omega_"frame"(r)$],
    [$cal(F)_"hole"="attachPrefix"(
      cal(F)_e,Delta_p,s_p,delta_p)$],
    [$cal(F)_o="PathBind"(cal(F)_"hole",
      r => cal(F)_"frame"(r))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_p,s_p,delta_p,
        Delta_e,s_e,delta_e,
        {Delta_"frame",s_"frame",
          delta_"frame",Omega_"frame"})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(A,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(E_s[e]) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`FrameStep` 是把某个 `Returns` path的 value/world/usage/evidence填回
strict frame后，对尚未执行的 callee/argument、`let` suffix或 argument
suffix继续使用同一 path judgment；`attachPrefix` 则把 hole之前已经执行的
evidence附到每条 hole path。于是一个 hole可以同时返回
`Returns`、`Aborts` 与多个 `Transfers(P)`；只有 `Returns` 进入 frame，
每个 terminal path都跳过 hole之后的 suffix。旧的 T-Ctx-Abort 与
T-Ctx-Transfer 都只是本 rule 的 singleton projection，不是独立的
single-tag congruence。Core `resume(k,v)` 保持 value operand；surface
`resume(k,e)` 先 ANF 成 `let x=e; resume(k,x)`，所以 argument abort由
initializer context传播。到最近 delimiter 后改由 T-Handle 的 path-aware
body judgment处理。
