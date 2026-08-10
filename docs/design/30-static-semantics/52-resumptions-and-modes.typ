#import "../shared.typ": *

== Resumption primitives

#irule(
  [T-Resume],
  (
    [$k:"Resume"[q,D_k,A,B,Pi_k,chi_k,rho] quad D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$Omega(k)="Open"(q) quad "PhaseAllows"(Phi,Phi_k)$],
    [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi_v] ▷ chi_v$],
    [$w_k(Theta)=Theta' quad R_k(pi_v,chi_v)=(pi_B,chi_B)$],
    [$Omega'="resumeState"(Omega,k,q)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "resume"(k,v) ⇒ B @[pi_B] ! epsilon_k;Delta_k ▷ s_k;delta_k ⊗ delta_"resume";chi_B @Theta'⊣Omega'$],
)

#irule(
  [T-Finalize],
  (
    [$k:"Resume"[q,D_k,A,B,Pi_k,chi_k,rho]$],
    [$Omega(k)="Open"(q)$],
    [$"cleanup"(D_k)=F_k=⟨epsilon_f,Delta_f,zeta_f,s_f,delta_f⟩$],
    [$zeta_f(Theta)=Theta' quad "Allowed"(Phi,epsilon_f,s_f,delta_f)$],
  ),
  [$K;I;Phi;Omega@Theta ⊢ "finalize"(k) ⇒ "Unit" @["Stable"] ! epsilon_f;Delta_f ▷ s_f;delta_f ⊗ delta_"finalize";emptyset @Theta'⊣Omega[k↦"Closed"]$],
)

TR₀ 不暴露 `discontinue(k,e)`：在没有把 error payload type、异常路径
transformer与 cleanup组合写入 $D_k$ 前，给它一个假装完整的 Core
constructor是不严谨的。Error recovery使用显式 abort operation/clause；
cancel使用 Owner/finalize protocol。`resumeState` 定义为：

```text
resumeState(Ω, k, 1) = Ω[k ↦ Closed]
resumeState(Ω, k, ω) = Ω[k ↦ Open(ω)]
```

若 clause正常退出且 $k$ 仍 `Open`、也未被 park，elaboration在该路径插入
`finalize(k)`。因此每条运行路径最终只有一个 disposition owner；`ctl`
可以 resume多次，但一旦 finalize/park就不能再 resume。
自动插入的 finalizer参与 clause contract聚合，所以 Atomic/Delay会看到真实
cleanup effect与 suspension，而不会获得虚假的 `NoSuspend`。

== Handler mode refinement

#table(
  columns: (1.2fr, 3.8fr),
  [*operation 最大 mode*], [*允许的 clause mode*],
  [`abort`], [`abort`],
  [`fun`], [`fun`],
  [`once`], [`abort`、`fun`、`once`],
  [`ctl`], [`abort`、`fun`、`once`、`ctl`],
)

这只允许收紧控制权。Clause 还必须满足：

```text
resume target agrees with operation transition
actual suspension ≤ declared suspension
all one-shot paths own exactly one disposition
tail-resumptive `fun` has no code after implicit resume
semantic-law witness has an allowed trust origin
every normally returning clause agrees with the captured answer world
may_suspend clause either resumes synchronously or transfers to its Owner
```

`fun` 与 `abort` 不是 checker里共享一个无 continuation 的 `else` 分支。
Clause schema对 abstract site $kappa$ 参数化，并使用两个不同 elaboration：

```text
fun clause op(args) { e }
  ↦ hidden kκ in resume(kκ, e)
  where e checks against the operation result
  and the resume is the unique tail action

abort clause op(args) { e }
  ↦ hidden discardκ in
      let answer = e in discardκ; answer
  where e checks against the handler answer
  and discardκ executes κ.D.cleanup exactly once
```

令 handler schema environment：

$
  H_h=⟨rho_h,B,Pi_h,chi_h⟩
$

`ImportHandlerEnv(Θentry,Hh)` 只把 $Pi_h/chi_h$ 描述的 captured bindings
导入 symbolic operation-site world；它不复制定义点的 lock。以下 judgment
对 $Theta_"entry"$、operation skolems、完整 symbolic installation
$(S_i,p_i,a_i)$ 和 $kappa$ 普遍量化，且
`TopPrompt(Si)=⟨pi,ai⟩` 且 route stage固定为 `HandlerInstall`；
`AdmissibleSite` 必须证明
`route(κ)=pi`、`entry(κ)=ai`，不能只按
handler value或 family匹配。

#irule(
  [T-Clause-Once-Ctl],
  (
    [$m_h in {"once","ctl"} quad q_"once"=1 quad q_"ctl"=omega$],
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad "AdmissibleSite"(kappa,O_k,H_h)$],
    [$"clauseMode"=m_h quad m_h <= "mode"(O_k)$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):"params"(O_k),Xi_k)$],
    [$k:"Resume"[q_(m_h),D_k,"result"(O_k),B,Pi_k,chi_k,rho_h]$],
    [$b_k="BindClauseDisposition"(k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega[k↦"Open"(q_(m_h))]@Theta_k;S_i ⊢
      "clauseBody"_B(e) ⇓ cal(F)_c !
      epsilon_c;Delta_c;s_c;delta_c ⊣Omega_c$],
    [$"PathUsage"(cal(F)_c,k) <= q_(m_h)$],
    [$"DispositionComplete"(m_h,k,cal(F)_c,Omega_c) ⇓ cal(F)_d$],
    [$"ExtractClauseContract"(cal(F)_d,Delta_c,Xi_k,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "resumptiveClause"(O,m_h,e) ⇓
    "ResumeSchema"(kappa,b_k,H_c)$],
)

`DispositionComplete` 对 `once` 的每个 exit插入/验证 resume、finalize或显式
Owner-bound park/Kernel delegation恰好一个。`Delegates(κf)` path必须且只
能对应 `Ω(k)=Forwarded(κf)`；其他 path不得携带该 state。对 `ctl` 可有多次
resume，但 exit前必须以 finalize或唯一 delegation结束，T-Park不接受
`Resume[ω,…]`。`Closed`、`Transferred`、`Forwarded` 都没有后继 disposition
transition。插入动作的 row、suspension、summary与 usage都进入 $f_d$。

#irule(
  [T-Clause-Fun],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad O_k=(bar(A)_k)->R_k^o
      @[m,zeta_k,d_k,R_k^"op",Phi_k^"op",P_k,Sigma_k]$],
    [$"AdmissibleSite"(kappa,O_k,H_h)$],
    [$"clauseMode"="fun" quad "fun" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_k,Xi_k)$],
    [$k:"Resume"[1,D_k,R_k^o,B,Pi_k,chi_k,rho_h]$],
    [$b_k="BindClauseDisposition"(k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega,k:"Open"(1)@Theta_k;S_i ⊢
      e ⇐ R_k^o @[pi_R] ! epsilon_e;Delta_e ▷
      s_e;delta_e;chi_R @Theta_R⊣Omega_R$],
    [$Theta_y="bind"(Theta_R,y:R_k^o @[pi_R] ▷ chi_R)$],
    [$K;I;Phi_h;Omega_R@Theta_y;S_i ⊢
      "resume"(k,y) ⇒ B @[pi_B] ! epsilon_k;Delta_k ▷
      s_k;delta_k ⊗ delta_"resume";chi_B @Theta_r⊣Omega'$],
    [$"dropBinder"(Theta_r,y)=Theta_"answer"$],
    [$"TailOnly"("let" y=e;"resume"(k,y)) quad Omega'(k)="Closed"$],
    [$"ExtractClauseContract"(
      "typedFunPath",Xi_k,pi_B,chi_B,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "funClause"(O,e) ⇓ "FunSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Abort],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$kappa=⟨ell_k,p_i,a_i,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
      Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩$],
    [$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$],
    [$"siteInstanceOf"(O_k,O)
      quad O_k=(bar(A)_k)->R_k^o
      @[m,zeta_k,d_k,R_k^"op",Phi_k^"op",P_k,Sigma_k]$],
    [$"AdmissibleSite"(kappa,O_k,H_h)$],
    [$F_k=⟨epsilon_f,Delta_f,zeta_f,s_f,delta_f⟩$],
    [$"clauseMode"="abort" quad "abort" <= m$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$Theta_k="bindArgs"(Theta_h,bar(x):bar(A)_k,Xi_k)$],
    [$k_kappa:"Resume"[1,D_k,R_k^o,B,Pi_k,chi_k,rho_h] quad Omega_k=Omega[k_kappa↦"Open"(1)]$],
    [$b_k="BindClauseDisposition"(
      k_kappa,kappa,"type"(k_kappa))$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      e ⇐ B @[pi_B] ! epsilon_e;Delta_e ▷
      s_e;delta_e;chi_B @Theta_B⊣Omega_B$],
    [$Theta_y="bind"(Theta_B,y:B @[pi_B] ▷ chi_B)$],
    [$K;I;Phi_h;Omega_B@Theta_y;S_i ⊢
      "finalize"(k_kappa) ⇒ "Unit" @["Stable"] !
      epsilon_f;Delta_f ▷ s_f;delta_f ⊗ delta_"finalize";
      emptyset @Theta_f⊣Omega'$],
    [$K;I;Phi_h@Theta_f ⊢_v y ⇒ B @[pi_o] ▷ chi_o$],
    [$"dropBinder"(Theta_f,y)=Theta_"answer" quad Omega'(k_kappa)="Closed"$],
    [$"ExtractClauseContract"(
      "typedAbortPath",Xi_k,pi_o,chi_o,b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "abortClause"(O,e) ⇓ "AbortSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Fun-Paths],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"PrepareClauseSite"(S_i,p_i,a_i,kappa,O,H_h,"fun") ⇓
      ⟨Theta_k,k,D_k,R_sigma,B,Omega_k,b_k⟩$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      "clauseBody"_(R_sigma)(e) ⇓ cal(F)_e !
      epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$cal(F)_r="TailResumeReturns"(
      cal(F)_e,k,D_k,R_sigma,B)$],
    [$"DispositionComplete"(
      "fun",k,cal(F)_r,Omega_e) ⇓ cal(F)_d$],
    [$"ExtractClauseContract"(
      cal(F)_d,Delta_e,"actualArguments"(kappa),b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "funClausePaths"(O,e) ⇓ "FunSchema"(kappa,b_k,H_c)$],
)

#irule(
  [T-Clause-Abort-Paths],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"PrepareClauseSite"(S_i,p_i,a_i,kappa,O,H_h,"abort") ⇓
      ⟨Theta_k,k,D_k,R_sigma,B,Omega_k,b_k⟩$],
    [$K;I;Phi_h;Omega_k@Theta_k;S_i ⊢
      "clauseBody"_B(e) ⇓ cal(F)_e !
      epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$cal(F)_f="FinalizeReturnPaths"(
      cal(F)_e,k,"cleanup"(D_k),B)$],
    [$"AbortScopeExitOnTerminalPaths"(
      cal(F)_f,k,D_k,Omega_e) ⇓ cal(F)_d$],
    [$"DispositionComplete"(
      "abort",k,cal(F)_d,"usage"(cal(F)_d))$],
    [$"ExtractClauseContract"(
      cal(F)_d,Delta_e,"actualArguments"(kappa),b_k) ⇓ H_c$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "abortClausePaths"(O,e) ⇓ "AbortSchema"(kappa,b_k,H_c)$],
)

这里的 hidden $k_kappa$ / `discardκ` 只存在于 Kernel elaboration，source
clause不能引用。`fun` 因此仍受完整 $w_k$、TickWitness与 answer-world
检查；`abort` 不执行 suffix，但其 cleanup和最终 normal world仍必须通过
`InstallOK`。`discardκ` 是 T-Finalize 对 abstract site contract
$kappa$ 的 Kernel-only specialization：它消费同一个 disposition，并执行
$"cleanup"(D_k)$，不是另一条可绕过 usage检查的 primitive。若 clause body
自身走 abortive flow，`AbortClauseScopeExit` 在传播 abort前执行同一
cleanup；该路径不贡献 normal
answer-world premise。
`AdmissibleSite` 是结构化 refinement：除 resolved $(a,o_k)$ 与 $Xi_k$
逐参数 type/nominal index外，它还验证 $D_k$ 的 first transition确为
operation $zeta_sigma$、cleanup/answer world一致，并携带全部
$P_sigma$ obligation；它不能只比较 selector。`ExtractClauseContract`
从完整 typed `let/resume` 或 `let/finalize/return` derivation投影
$H_c=⟨m_h,Q_"site",d_h,Delta_"res",s_"res",delta_h,R_h,P_"park"⟩$，所以
actual argument与 handler environment的 provenance/capture transformer
$R_h$ 不会丢失。
`BindClauseDisposition(k,κ,type(k))` 为这个 clause schema建立唯一
$b_k$：它把 internal resumption/discard token $k$ alpha-normalize成
`ClauseDispositionBinderV2`，记录原 `κ.site_slot` 与完整
`ResumeTypeRefV2 { value: ResumeTypeV2 }`，
并让同一个 clause flow内每个 `Delegates` 的 `inner_disposition` 只能引用
该 binder。$b_k$ 的 scope不越过所属 `ClauseComputationV2`，也不能从
$D_k$、continuation或 live bindings重建。
`PrepareClauseSite` 只是 T-Clause-Fun/Abort共同的 site admissibility、
exact stored $O_k$ signature、environment/argument bind与 `Open(1)`
premises以及同一 $b_k$ declaration的排版缩写；它不重新实例化 operation
type arguments。
`TailResumeReturns` 只给每个 Returns path追加 hidden tail resume；
`FinalizeReturnPaths` 只给每个 Returns path追加 hidden finalize/return；
两者都保留 abort/transfer/delegate side paths，并由
`DispositionComplete`/`AbortScopeExitOnTerminalPaths`逐 path完成 disposition。
因此上面两条 path rule是 normative，旧 T-Clause-Fun/Abort只是恰好一个
Returns path时的投影。

若任一 clause body path在产生 normal answer前 abort，runner delimiter
必须先收回该 path拥有的 disposition：

#irule(
  [T-Clause-Path-Abort],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$"route"(kappa)=p_i quad "entry"(kappa)=a_i
      quad "suffix"(kappa)=D_k$],
    [$k:"Resume"[q,D_k,A_k,B,Pi_k,chi_k,rho_h] quad Omega(k)="Open"(q)$],
    [$"ExistingClauseDisposition"(
      b_k,k,kappa,"type"(k))$],
    [$K;I;Phi_h;Omega@Theta_k;S_i ⊢_"abort" e !
      epsilon_e;Delta_e ▷ s_e;delta_e ⊣Omega_e$],
    [$(Omega_o,delta_o)="AbortClauseScopeExit"(k,D_k,Omega_e,delta_e)$],
    [$"NoOpenDisposition"(k,Omega_o)$],
    [$"ExtractAbortPathContract"(
      epsilon_e,Delta_e,s_e,delta_o,b_k) ⇓ H_a$],
  ),
  [$K;I;Phi_h;H_h;S_i;p_i;a_i ⊢
    "clauseAbortPath"(kappa,k,b_k,e) ⇓ "Aborts"(H_a,Omega_o)$],
)

Clause schema对 normal rules与 T-Clause-Path-Abort 的 reachable path做有限
join；all-abort schema没有 $R_h$ normal branch，但仍保留 residual row、
suspension、semantic summary与 cleanup evidence。该 rule同样覆盖
`fun` argument计算、`once/ctl` clause body以及 hidden abort-clause
disposition的 abortive path。这里的 $b_k$ 是 enclosing clause schema已经
建立的同一 binder；`ExistingClauseDisposition` 逐字段匹配 enclosing
`BindClauseDisposition` 的结果并禁止为 abort path另建 slot。
因此该 path在 `;Si` 与固定 HandlerInstall stage下产生的 residual route、
cleanup以及 disposition evidence都并入同一个 `ClauseComputationV2`；
其 `InvokeV2` 只从 enclosing `HandlerContractV2.applications` ledger解析。

Handled body使用 path-set辅助 judgment：

$
  t ::= "Aborts"
    | "Returns"(pi,chi,Theta)
    | "Transfers"("ParkContractV2")
  quad
  cal(F) ::= {t_1,...,t_n}
$

$cal(F)$ 是 reachable outcomes 的有限非空集合，不是单一 tag；因此同一
branching computation可以同时保存 `Returns`、`Aborts` 与一个或多个
`Transfers(ParkContractV2)`。Normal return entries只有在 result type兼容且
world可 join时合并；transfer contract不能被 join成 abort。

$
  K;I;Phi;Omega@Theta;S
  ⊢ "body"_A(e) ⇓ cal(F) ! epsilon;Delta;s;delta
  ⊣ Omega'
$

它要求所有 normal path返回 $A$ 并 join其 provenance/capture/world；
完全 abortive body得到 `${Aborts}`。`Transfers(ParkContractV2)` 是经过
T-Park验证的 terminal ownership transfer，不是 `Unit` result，也不能进入
sequence 的 suffix。三类 flow都保留 typed Core、operation sites、row、
suspension、summary 与 attributed demand。$S$ 与 typing context中的 route
stage在所有 body premises/conclusions间原样线程；普通 checking使用 `Call`，
handler clause由 enclosing premise固定为 `HandlerInstall`。

Clause checking使用严格扩展而不扩大 public flow：

$
  t_c ::= t | "Delegates"("ForwardContract")
  quad cal(F)_c ::= {t_(c_1),...,t_(c_n)}
$

`clauseBody` 复用以下 return/abort/transfer/branch/sequence规则，并额外允许
T-Forward-Delegate/T-Forward-Paths。`Delegates` 只能出现在 handler schema
内部；它携带 `Forwarded(κf)` disposition evidence，不能进入
`FunctionContractV2.computation` 的 public path set。

#irule(
  [T-Body-Return],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ e ⇐ A @[pi] !
      epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Returns"(pi,chi,Theta')} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Abort],
  (
    [$K;I;Phi;Omega@Theta;S ⊢_"abort" e !
      epsilon;Delta ▷ s;delta ⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Aborts"} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Transfer],
  (
    [$K;I;Phi;Omega@Theta;S ⊢_"transfer" e ⇓
      "Transfers"(P) ! epsilon;Delta ▷ s;delta @Theta'⊣Omega'$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e) ⇓
    {"Transfers"(P)} ! epsilon;Delta;s;delta ⊣Omega'$],
)

#irule(
  [T-Body-Branch],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_"Bool"(c) ⇓
      cal(F)_c ! epsilon_c;Delta_c;s_c;delta_c ⊣Omega_c$],
    [$forall r in "returns"(cal(F)_c).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢ "body"_A(e_1) ⇓
      cal(F)_1(r) ! epsilon_1(r);Delta_1(r);
      s_1(r);delta_1(r) ⊣Omega_1(r)$],
    [$forall r in "returns"(cal(F)_c).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢ "body"_A(e_2) ⇓
      cal(F)_2(r) ! epsilon_2(r);Delta_2(r);
      s_2(r);delta_2(r) ⊣Omega_2(r)$],
    [$cal(F)_b(r)=cal(F)_1(r)∪cal(F)_2(r)
      quad cal(F)_o="PathBind"(cal(F)_c,
        r => cal(F)_b(r))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_c,s_c,delta_c,
        {Delta_1,s_1,delta_1,Omega_1},
        {Delta_2,s_2,delta_2,Omega_2})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(
    "if" c {e_1} "else" {e_2}) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

#irule(
  [T-Body-Sequence],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ "body"_X(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r)@"world"(r);S ⊢
      "body"_A(e_2) ⇓ cal(F)_2(r) !
      epsilon_2(r);Delta_2(r);s_2(r);delta_2(r)
      ⊣Omega_2(r)$],
    [$cal(F)_o=
      "terminal"(cal(F)_1) ∪
      "unionPaths"({cal(F)_2(r) mid
        r in "returns"(cal(F)_1)})$],
    [$Delta_o=Delta_1∪
      "unionDemand"({Delta_2(r) mid
        r in "returns"(cal(F)_1)})
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$Omega_o="joinPathUsage"(
      "terminalUsage"(cal(F)_1),
      {Omega_2(r) mid r in "returns"(cal(F)_1)})$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_A(e_1;e_2) ⇓
    cal(F)_o ! epsilon_o;Delta_o;
    s_1⊔"joinSusp"({s_2(r) mid r in "returns"(cal(F)_1)});
    delta_1⊗"joinSummary"(
      {delta_2(r) mid r in "returns"(cal(F)_1)})
    ⊣Omega_o$],
)

`T-Body-Branch` 对任意 finite path set取 union；`T-Body-Sequence` 只把
`Returns` entries送入 suffix，并原样保留 prefix 的 `Aborts`、多个
`Transfers(P)` 以及 clause-internal `Delegates(κf)` 与它们的 path-local
usage evidence。若 prefix没有
Returns，indexed union为空且 suffix完全不检查。这样 operation clause中的
`park`通过 T-Body-Transfer进入 clause schema，再经 handler congruence向外
传播，不会被错误重标为 abort。

Handler installation是一个有输出的 judgment：

$
  E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩
  quad
  "InstallOK"(S,p,h,P_h,a,bar(kappa),E_e,C_h)
  ⇓ E_i
$

`InstallOK` 不产生新的自由 demand output；它验证并 path-map body/schema，
唯一 demand输入仍是 $Delta_e$。sealed $E_i$ 同时保存
`publicFlow(E_i)`、`semanticSummary(E_i)` 与
`handlerResidual(E_i)`；最后一项由实际
$(C_h,p,S,bar(kappa),E_e)$（包括 Forward contract/evidence）唯一构造，
不能只凭抽象 template和 prompt恢复。
先令 $(Pi_"handler",chi_"handler")="handlerEnv"(C_h)$。其中
`handlerEnv` 是 T-Handler 写入并跨 interface保存的 sealed projection。
其中 result summary按可达 normal exit path计算：

```text
HandleResultSummary =
  join(
    applyReturnContract(C_h, πe, χe, Θe).result
      for each Returns(πe, χe, Θe) in ℱe,
    clauseSummary(C_h, operation(κ))(
      Ξκ, Πκ, χκ, Πhandler, χhandler)
      for each reachable κ whose clause has a normal exit,
  )
```

`applyReturnContract` 同时把 $C_"ret"$ 的 world transformer加入
answer-world集合。Semantic summary也按相同 reachable-path集合计算：

$
  delta_o =
  "handleSummary"(delta_e,a,C_h,P_h,bar(kappa),cal(F)_e)
$

它保留 unhandled body summary，并加入实际可能执行的 return/clause
summary与 handler policy；不能用单独的 $P_h$ 替代 $C_h$。

所以 abort clause从 actual argument（例如 `Raise.throw(err)` 的 `err`）带入
结果的 provenance/capture不会从 normal body summary中消失。
`InstallOK` 对 $cal(F)_e$ 逐 path映射：return path应用 return/clause
contract，abort path保留 `Aborts`，transfer path保留同一个
`Transfers(ParkContractV2)` 并验证该 installation不窃取 disposition。它同时
要求所有 normal exit产生可 join 的输出 $Theta_o$；没有 normal exit时
set中仍保留 abort/transfer而不是压成 `NoReturn`。Clause可以通过 full $w_k$ resume到该 world，
也可执行等价 sealed transition；无 resume 的 abort path若 normal return
却没有该 world evidence，就失败。`RequiresTickWitness`、
`OwnerBoundParking` 等 $P_o$ obligation也在这里 discharge。

若被选择的 clause schema含 `Delegates(κf)`，`InstallOK` 必须在 public
输出前消费它：验证 clause schema已经把 $kappa_f$ 的 primary/secondary
demand与 site evidence写入本次 sealed install evidence 的
`handlerResidual(E_i)`，并以其唯一持有的原 $D_k$
中 public continuation flow替换该 internal path。outer handler之后
resume时只消费 $kappa_f$ 拥有的
同一个 disposition；inner token已经是 `Forwarded(κf)`，不能再次处置。
因此 `Delegates` 不会出现在 $cal(F)_o$ 或跨模块 `FlowSetV2`，同时 forwarding
也不会被误压成 abort/no-return。
