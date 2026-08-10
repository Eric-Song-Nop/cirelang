#import "../shared.typ": *

= 算法化 typing judgment <typing-judgments>

== Synthesis 与 checking

Synthesis：

$
  K; I; Phi; Omega @ Theta; S
  ⊢ e ⇒ A @[pi] ! epsilon;Delta ▷ s; delta; chi
  @ Theta' ⊣ Omega'
$

Checking：

$
  K; I; Phi; Omega @ Theta; S
  ⊢ e ⇐ A @[pi] ! epsilon;Delta ▷ s; delta; chi
  @ Theta' ⊣ Omega'
$

Value judgment：

$
  K; I; Phi @ Theta
  ⊢_v v ⇒ A @[pi] ▷ chi
$

$pi$ 与 $chi$ 都描述结果；所有 derivation 维持
$epsilon="eraseDemand"(Delta)$，所以 row不能脱离 route/site attribution
单独变化。Branch provenance使用最小安全上界
`joinProv`；capture union后做 binder substitution。Rule中省略
$@[pi]$ 只允许在紧邻文字明确结果为 `Stable` 时使用。

$S$ 是显式 lexical prompt stack，并随 expression、args、abort、transfer、
body与 clauseBody judgment结构性线程化。后文为排版省略 `;S` 的 rule，
只表示所有 premises与 conclusion携带同一个未修改的 $S$；创建 delimiter的
rule必须显式写 `pushPrompt(S,p,a)`，创建 demand的 rule必须显式 fresh
lexical site slot并调用 `resolveRoute(S,a)`。`promptStack` 不是全局变量。

为保持长规则可读，后文旧式 `! ε ▷ ...` 只是一种排版缩写：它必须从该
rule的 typed subderivations/site constructors结构性计算唯一 $Delta$，并同时
证明 `ε=eraseDemand(Δ)`；它绝不表示“没有 Δ 字段”或允许事后用
side-effecting recorder修改全局状态。T-App、T-Operation、handler、resume/finalize
与 flow rules显式写出 $Delta$，因为这些正是 attribution发生变化的边界。

Checking rule：

#irule(
  [T-Check],
  (
    [$K;I;Phi;Omega@Theta;S ⊢ e ⇒
      A' @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
    [$K;I ⊢ A' <: A$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ e ⇐
    A @[pi] ! epsilon;Delta ▷ s;delta;chi @Theta'⊣Omega'$],
)

#irule(
  [T-Value],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A @[pi] ▷ chi$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ v ⇒ A @[pi] !
    emptyset;emptyset ▷
    "direct"("NoSuspend");delta_"pure";chi @Theta⊣Omega$],
)

== Variables

#irule(
  [T-Var],
  (
    [$x : A @[pi] ▷ chi_x in Theta$],
    [$"Available"(pi, Theta, x)$],
  ),
  [$K;I;Phi@Theta ⊢_v x ⇒ A @[pi] ▷ chi_x$],
)

#irule(
  [T-Value-Check],
  (
    [$K;I;Phi@Theta ⊢_v v ⇒ A' @[pi] ▷ chi$],
    [$K;I ⊢ A' <: A$],
  ),
  [$K;I;Phi@Theta ⊢_v v ⇐ A @[pi] ▷ chi$],
)

`Available` 检查 binder 与使用点之间的 lock、region 和 Owner boundary。
它不只检查 $chi$。

== Functions

Lambda只有下面这条 path-set rule是 normative；旧名称 T-Lambda 与
T-Lambda-Abort 在规则后定义为它的单一路径 projection，不再各自重新检查
body。这样带 terminal transfer 的具名函数仍可形成：

#irule(
  [T-Lambda-Paths],
  (
    [$eta_f=⟨A,B,Phi_f⟩ quad
      (pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$S_f " fresh symbolic Call-stage stack"$],
    [$Theta_x="bind"(Theta,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_f;Omega_"sym"@Theta_x;S_f ⊢ "body"_B(e) ⇓
      cal(F)_b ! epsilon;Delta;s;delta ⊣Omega_b$],
    [$(Pi_c,chi_c,u,Lambda)="analyzeFlowClosure"(
      e,x,Theta,Omega_"sym",Omega_b,cal(F)_b,Delta)$],
    [$(r_f,hat(zeta),hat(R),Q)="AbstractParametricFlow"(
      S_f,pi_x,xi_x,cal(F)_b)$],
    [$C_0=⟨epsilon,hat(zeta),r_f,s,delta,Pi_c,chi_c,u,
      hat(R),Phi_f,Q,Lambda⟩$],
    [$C="attachFlow"(C_0,"abstractFlow"(cal(F)_b))$],
    [$pi_c="Env"(Pi_c) quad "ManyCallSafe"(Pi_c,u,chi_c)$],
  ),
  [$K;I;Phi@Theta ⊢_v lambda^[eta_f] x.e ⇒
    A arrow.r.long^C B @[pi_c] ▷ chi_c$],
)

若 $cal(F)_b={"Transfers"(P)}$，则
$r_f="NoReturn"$、$hat(zeta)=hat(R)=bot$，但
`flow(C)={Transfers(P)}`；它不会被改写成 abort。Surface named `def`
的一元 tuple elaboration使用同一 rule。$S_f$ 在 closure contract中抽象为
Call-stage route selectors，不捕获 lambda definition stack。
若 `flow(C)` 恰为 singleton `Returns`，其 scalar projection称为 T-Lambda；
若恰为 singleton `Aborts`，以 explicit bottom transition/result编码的
projection称为 T-Lambda-Abort。两者复用同一个 T-Lambda-Paths derivation、
$S_f$ 与 `ManyCallSafe` evidence，不存在第二条 ambient-context body premise。
$
  "T-Lambda" := "ProjectSingletonReturns"("T-Lambda-Paths")
  quad
  "T-Lambda-Abort" := "ProjectSingletonAborts"("T-Lambda-Paths")
$
`Omega_sym` 是 closure body的 symbolic usage环境；构造 closure不修改定义点
$Omega$。`freshRigidSummaryVars` 与 `AbstractParametricFlow` 对所有 admissible
argument summary、boundary/stability/outlives约束普遍抽象；T-App先 discharge
$Q$ 才能应用 result transformer。完全 abortive path不能借“不产生结果”
绕过这些约束。

后文 `$"body"_A(e) ⇓ cal(F)$` 是所有 expression都可使用的 normative
path judgment，不只用于 handler body。其 strict bind为：

$
  "PathBind"(cal(F),G)
  =
  "terminal"(cal(F))
  ∪ "unionPaths"({G(r) mid r in "returns"(cal(F))})
$

只有 `Returns` path进入 $G$；每个 `Aborts`/`Transfers` path连同
path-local usage/world/evidence原样保留。`AggregatePathEvidence` 只合并
实际执行 path的 $Delta/s/delta$，不把未执行 suffix加入 terminal prefix；
其输出必须满足 `AttributedOK(Δ,s)`。

#irule(
  [T-App],
  (
    [$C_f=⟨epsilon_f,zeta,"MayReturn",s_f,delta_f,Pi_f,chi_f,u_f,R_f,Phi_f,Q_f,Lambda_f⟩$],
    [$K;I;Phi;Omega@Theta_0;S ⊢ e_1 ⇒
      A arrow.r.long^(C_f) B @[pi_1] !
      epsilon_1;Delta_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$K;I;Phi;Omega_1@Theta_1;S ⊢ e_2 ⇐ A @[pi_2] !
      epsilon_2;Delta_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$"PhaseAllows"(Phi,Phi_f) quad "applyUsage"(Omega_2,u_f)=Omega_3$],
    [$"Discharge"("instantiate"("stageCall"(Q_f),pi_2,chi_2,I,Theta_2))$],
    [$zeta(Theta_2) = Theta_3$],
    [$R_f(pi_2,chi_2)=(pi_3,chi_3)$],
    [$(Delta_f,s_f',Lambda_"install")=
      "instantiateLatentContract"(
        epsilon_f,s_f,Lambda_f,pi_2,chi_2,Theta_2,S)$],
    [$"eraseDemand"(Delta_f)=
      "instantiateRow"(epsilon_f,pi_2,chi_2,Theta_2)
      quad "AttributedOK"(Delta_f,s_f')$],
    [$"PreserveUntilInstall"("stageHandlerInstall"(Q_f),Lambda_"install")$],
    [$cal(F)_f="instantiateFlow"("flow"(C_f),pi_2,chi_2,Theta_2)$],
    [$cal(F)_f={"Returns"(pi_3,chi_3,Theta_3)}$],
    [$Delta'=Delta_1∪Delta_2∪Delta_f
      quad epsilon'="eraseDemand"(Delta')$],
    [$s'=s_1⊔s_2⊔s_f'
      quad "AttributedOK"(Delta',s')$],
    [$"AttachFlowEvidence"("callNode",cal(F)_f)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ e_1(e_2) ⇒
    B @[pi_3] ! epsilon';Delta' ▷
    s';delta_1 ⊗ delta_2 ⊗ delta_f;chi_3
    @Theta_3⊣Omega_3$],
)

#irule(
  [T-App-Paths],
  (
    [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_(
      A arrow.r.long^C B)(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r_1 in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r_1)@"world"(r_1);S ⊢
      "body"_A(e_2) ⇓ cal(F)_2(r_1) !
      epsilon_2(r_1);Delta_2(r_1);s_2(r_1);delta_2(r_1)
      ⊣Omega_2(r_1)$],
    [$forall r_1,r_2.
      r_1 in "returns"(cal(F)_1) and
      r_2 in "returns"(cal(F)_2(r_1)) "implies"
      "InstantiateCallPath"(
        C,"summary"(r_2),I,S)
      ⇓ ⟨cal(F)_"call"(r_1,r_2),
        Delta_f(r_1,r_2),s_f(r_1,r_2),
        delta_f(r_1,r_2),Omega_f(r_1,r_2)⟩$],
    [$cal(F)_o="PathBind"(cal(F)_1,
      r_1 => "PathBind"(cal(F)_2(r_1),
        r_2 => cal(F)_"call"(r_1,r_2)))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_1,s_1,delta_1,
        {Delta_2,s_2,delta_2},
        {Delta_f,s_f,delta_f,Omega_f})$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad "FlowWellFormed"(B,cal(F)_o)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_B(e_1(e_2)) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

`InstantiateCallPath` 对单个 successful callee/argument path执行
T-App中的 phase、usage、stageCall discharge、prompt-aware latent-site
instantiation与 HandlerInstall preservation，然后调用 `instantiateFlow`。
它必须通过同一个 `instantiateLatentContract(ε,s,Λ,...)` 成对产生
attributed demand、keyed suspension与 installation evidence，并证明
`eraseDemand(Δ)=instantiateRow(ε)` 及 `AttributedOK(Δ,s)`；禁止分别实例化
row、site与 suspension。
后者对每个 `Returns` entry应用 $hat(zeta)/hat(R)$，对每个
`Transfers(P)`独立实例化 $P$，并原样保留 `Aborts`；结果可以是
`{Aborts,Transfers(P₁),Transfers(P₂)}` 或同时含 normal return的任意有限
非空 set。T-App 是恰好一个 normal path时的 projection；所有 mixed/terminal
情况使用 T-App-Paths，不能靠多个互斥 single-tag rule猜测。

函数调用必须应用 contract 中的 temporal transformer；不能把
$zeta$、$Pi_f/chi_f$、$u_f$、$R_f$、$Phi_f$、$Q_f$ 或 $Lambda_f$
从 interface artifact 中删除。
Callee
closure与argument的 capture不会自动成为结果 capture；只有 $R_f$ 声明的
转移进入 $chi_3$。$Lambda'$ 作为 call node evidence保存，外层
`sites(e,a)` 会把它与 caller suffix compose；因此 perform藏在另一个 module
的 `f()` 中也不会绕过 ctl capture、parking 或 answer-world检查。

== Let 与 block

#irule(
  [T-Let],
  (
    [$K;I;Phi;Omega@Theta_0 ⊢ e_1 ⇒ A @[pi_1] ! epsilon_1 ▷ s_1;delta_1;chi_1 @Theta_1⊣Omega_1$],
    [$Theta_x = "bind"(Theta_1,x:A @[pi_1] ▷ chi_1)$],
    [$K;I;Phi;Omega_1@Theta_x ⊢ e_2 ⇒ B @[pi_2] ! epsilon_2 ▷ s_2;delta_2;chi_2 @Theta_2⊣Omega_2$],
    [$Theta_3="dropBinder"(Theta_2,x)$],
  ),
  [$K;I;Phi;Omega@Theta_0 ⊢ "let" x=e_1;e_2 ⇒ B @[pi_2] ! epsilon_1 ∪ epsilon_2 ▷ s_1 ⊔ s_2;delta_1 ⊗ delta_2;chi_2 @Theta_3⊣Omega_2$],
)

#irule(
  [T-Let-Paths],
  (
    [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_A(e_1) ⇓
      cal(F)_1 ! epsilon_1;Delta_1;s_1;delta_1 ⊣Omega_1$],
    [$forall r in "returns"(cal(F)_1).
      Theta_x(r)="bind"("world"(r),x:A
        @["provenance"(r)] ▷ "captures"(r))$],
    [$forall r in "returns"(cal(F)_1).
      K;I;Phi;"usage"(r)@Theta_x(r);S ⊢ "body"_B(e_2) ⇓
      cal(F)_2(r) ! epsilon_2(r);Delta_2(r);s_2(r);delta_2(r)
      ⊣Omega_2(r)$],
    [$cal(F)_o="PathBind"(cal(F)_1,
      r => "dropFlowBinder"(cal(F)_2(r),x))$],
    [$(Delta_o,s_o,delta_o,Omega_o)=
      "AggregatePathEvidence"(
        cal(F)_o,Delta_1,s_1,delta_1,
        {Delta_2,s_2,delta_2,Omega_2})$],
    [$epsilon_o="eraseDemand"(Delta_o)$],
  ),
  [$K;I;Phi;Omega@Theta_0;S ⊢ "body"_B(
    "let" x=e_1;e_2) ⇓
    cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

T-Let 是 initializer与suffix都恰好一个 Returns path时的 projection。
Block 按 source order 对 expression list左折叠应用 T-Let-Paths/
T-Body-Sequence。
因此 world transition、usage budget 与 handler ordering 都不可交换。
若 $e_2$ 返回 closure/ADT并保存 $x$，capture substitution会把 $chi_1$
展开进 $chi_2$；`dropBinder` 只退出词法名字，不丢失结果 authority。
