#import "../shared.typ": *

== Handler type

Core handler value：

$
  "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
$

含义：

- handler action 属于 Owner region $rho_h$；
- handled computation 正常返回 $A$；
- handler action 返回 $B$；
- clause 自身可能产生 residual row $epsilon_h$；
- $(S_i,p_i,a_i).C_h$ 保存对 actual installation stack、prompt与精确
  handled entry抽象的 mode、site constraints、
  answer-world、suspension、
  path-specific result-summary、handler environment evidence 与 parking
  contract；
- $P_h$ 是具体 instance 的 semantic policy 与 trust origin。

Handler 是 lexical deep handler：`resume` 后重新进入同一 handler；不相关
effect entry 自动 forwarding。

== Operation-site suffix 与 clause checking

First-class handler定义时看不到未来 perform site 的 evaluation context，所以
不能在 `check_clause` 中调用一个虚构的 `capturesOfSuffix` oracle。Typed
Core先 A-normalize；安装 delimiter时，对 handled body做一次从右向左的
结构递归分析：

$
  K;I;Phi@Theta
  ⊢ "sites"(e,a,p) ⇓ bar(kappa)
$

每个 site contract：

$
  kappa =
  ⟨ell_k,p,a,o_k,Theta_"entry",D_k,Pi_k,chi_k,u_k,
    Theta_"answer",Xi_k,O_k,Q_k^"call",Q_k^"install"⟩
$

$ell_k$ 是 alpha-normalized stable lexical site slot；reroute时保留它但不把
旧 prompt或旧实例化环境当作新 contract。
$D_k=⟨epsilon_k,Delta_k,w_k,s_k,delta_k,R_k,Phi_k,F_k⟩$ 是 captured continuation
contract。$w_k$ 是从 operation site恢复到整个 handled computation answer 的*完整*
world transformer：它包含 operation自己的 $zeta$ 和其后 suffix 的
transformer；$chi_k$ 是 live-across-site capture；$u_k$ 是 suffix中的
latent usage；$R_k$ 给出 continuation answer的 result summary。$Xi_k$
保存该 site已经类型化的 actual arguments摘要：每项至少含 type、nominal
index、provenance与 result capture；它不保存任意 runtime value。对 deep
handler，$epsilon_k$ 已按同一 delimiter消除递归出现的 handled entry。
$o_k$ 是 resolved operation selector；它与 $a$ 一起唯一确定被哪一个
clause schema处理；$p$ 唯一确定本次 installation route，同一 handler
value的两次安装拥有不同 $p$。$Theta_"entry"$ 是 arguments求值完毕、operation
transfer control给 clause时的 actual temporal world；ClauseSchema对它
参数化，不能使用 handler定义点的 world代替。
$Pi_k="provenanceLive"("suffix",Theta)$ 是每个
live-across-site binder的
type/provenance map；它与 $chi_k$ 分开保存，因为 borrow可以有空 capture。
$O_k$ 是该 site 的 freshly instantiated operation signature；
$Q_k^"call"/Q_k^"install"$ 分别保存已在 call stage discharge的证据与仍需
installation delimiter discharge的 obligations。$F_k=⟨epsilon_k^"fin",
Delta_k^"fin",zeta_k^"fin",s_k^"fin",delta_k^"fin"⟩$
是丢弃该 continuation时必须执行一次的 cleanup contract；它同样来自 typed
suffix，不能由 T-Finalize伪装成纯操作。

分析按 typed ANF evaluation context递归：

```text
suffix(return)             = identity world, empty captures
site entry                 = world after all actual arguments,
                             before operation transfers control
suffix(let x = hole; rest) = operation transition
                              ; transition(rest)
                              + live captures/usage of rest
suffix(branches)           = branch-indexed contracts
suffix(lambda body)        = latent in function contract, not current suffix
suffix(inner handler)      = stop or transform at that delimiter
```

它是 checker的第二个有限 pass；不会执行程序，也不依赖 runtime handler。
Separate compilation保存 $C_h$ 对 $kappa$ 的约束，而不是保存某个定义点
suffix。

对每个 polymorphic operation：

$
  forall bar(alpha). (bar(A)) -> R
$

clause checker创建 fresh skolems $bar(a)$，而不是复用外层同名 type variable。

`once` 或 `ctl` clause 中 continuation 类型：

$
  k :
  "Resume"[q_m, D_k, sigma(R), B, Pi_k, chi_k, rho_h]
$

其中 $A$ 是 raw handled computation的 normal return type，$B$ 才是 deep
handler（return clause已经在 delimiter内）的 answer type；因此 `resume`
expression返回 $B$。Clause schema对
fresh skolems与满足 $C_h$ constraints 的 $kappa$ 参数化：

$
  K;I;Phi;Omega,k:"Open"(q_m)@Theta
  ⊢ "clause"[kappa] ⇐ B @[pi_h] ! epsilon_h
  ▷ s_h;delta_h;chi_h @Theta_h⊣Omega_h
$

并检查：

$
  "usage"(k, "clause") <= q_m
$

若声明 mode 为 `ctl`，基线 profile `declared-max` 还要求：

```text
DuplicableEnv(Πk, χk)
EnvValidAt(Πk, χk, MultiShot)
ReplayableCleanup(Fk, Πk, χk)
WorldForkSafe(wk)
```

即使某个未知运行时 handler 最终只 resume 一次，也不能用这个偶然事实绕过
open-world safety。词法已知 handler specialization 需要单独 preservation
证明。

Return clause本身也是对安装点 normal-exit world参数化的 schema：

#irule(
  [T-Return-Clause],
  (
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩ quad Theta_"entry" " fresh symbolic"$],
    [$Theta_h="ImportHandlerEnv"(Theta_"entry",H_h)$],
    [$(pi_x,xi_x)="freshRigidSummaryVars"(A)$],
    [$Theta_x="bind"(Theta_h,x:A @[pi_x] ▷ xi_x)$],
    [$K;I;Phi_h;Omega_"sym"@Theta_x;S_i ⊢
      "body"_B(e) ⇓ cal(F)_r !
      epsilon_r;Delta_r;s_r;delta_r ⊣Omega_r$],
    [$cal(F)_o="dropReturnBinder"(cal(F)_r,x)$],
    [$"AbstractReturnContract"(
      S_i,p_i,a_i,Theta_"entry",pi_x,xi_x,
      cal(F)_o,epsilon_r,Delta_r,s_r,delta_r) ⇓ C_"ret"$],
  ),
  [$"ReturnClauseOK"(
    K,I,Phi_h,H_h,S_i,p_i,a_i,"return"(x:A,e),A) ⇓ C_"ret"$],
)

这里及以下的 `SchemaRouteStage(Si)` 是为 handler clause构造的 nested
typing context字段，不是定义 handler value的外层 route stage，也不由
$S_i$ 推断；它必须恰为 `HandlerInstall`。因此
`TopPrompt(Si)=⟨pi,ai⟩` 把 symbolic installation stack、该 stage所解析的
prompt与 handled entry连成同一组参数，body中的所有 residual route都在
`;Si` 下检查。
`AbstractReturnContract` 对 rigid input summary与 symbolic
$Theta_"entry"$ 普遍抽象出 world/result transformer及 constraints；它不把
handler定义点 lock写进 contract。

#irule(
  [T-Handler],
  (
    [$"PartitionClauses"(F,bar(c)) ⇓ (c_"ret",M_"op")$],
    [$"dom"(M_"op")="ops"(F) quad "ExactAndUnique"(M_"op")$],
    [$"CurrentOwner"(Phi)=rho_h
      quad K ⊢ rho_h:"OwnerRegion"
      quad "OwnerAuthorized"(Phi,rho_h)$],
    [$chi_h="captureFV"(bar(c),Theta) quad Pi_h="provenanceFV"(bar(c),Theta)$],
    [$"EnvBoundarySafe"("fv"(bar(c)),Theta,"OwnerStorage"(rho_h))$],
    [$Phi_h " fresh symbolic"$],
    [$S_i,p_i,a_i " fresh symbolic installation parameters"$],
    [$"TopPrompt"(S_i)=⟨p_i,a_i⟩
      quad "SchemaRouteStage"(S_i)="HandlerInstall"$],
    [$H_h=⟨rho_h,B,Pi_h,chi_h⟩$],
    [$"ReturnClauseOK"(
      K,I,Phi_h,H_h,S_i,p_i,a_i,c_"ret",A) ⇓ C_"ret"$],
    [$M_h="checkClauseSchemas"(
      K,I,Phi_h,H_h,S_i,p_i,a_i,F,M_"op")$],
    [$forall O in "ops"(F). "ClauseSchemaOK"(O,M_h(O),H_h)$],
    [$"AggregateHandler"(C_"ret",M_h)=(Delta_h,C_0)
      quad epsilon_h="eraseDemand"(Delta_h)$],
    [$Phi_"req"="SolveHandlerPhase"(Phi_h,C_"ret",M_h)$],
    [$C_1="setRequiredPhase"(C_0,Phi_"req")$],
    [$"PolicyOK"(P_h) quad "Origin"(P_h)=rho_h$],
    [$C_h="attachHandlerEnv"(C_1,Pi_h,chi_h)$],
    [$"returnContract"(C_h)=C_"ret" quad "clauseSummaries"(C_h)=M_h$],
  ),
  [$K;I;Phi@Theta ⊢_v "handler"[F]{bar(c)} ⇒
    "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
    @["Owner"(rho_h)] ▷ chi_h$],
)

输入 T-Handler 前，Surface normalization 已为省略的 return 合成 identity
clause；显式写多个 return 仍是错误。`PartitionClauses` 同时保证恰好一个
return clause、每个
$O in "ops"(F)$ 恰好一个 operation clause，且没有 duplicate或 extra
clause。`ReturnClauseOK` 对具体 $c_"ret"$ 的 parameter、body type、row、
attributed demand/suspension、semantic summary、world transformer、result
transformer与 required invocation phase完整检查，产生
$C_"ret"=⟨epsilon_"ret",Delta_"ret",w_"ret",s_"ret",delta_"ret",
R_"ret",Phi_"ret"⟩$。它和 operation clause都在 fresh symbolic
$Theta_"entry"$ 下检查，并通过 $H_h$ 导入经过 boundary check的 definition
environment；定义点 $Theta$ 本身不进入 clause world。两者的 nested route
context都固定 `SchemaRouteStage(Si)=HandlerInstall`，并使用满足
`TopPrompt(Si)=⟨pi,ai⟩` 的 symbolic installation stack：
命中 $a_i$ 才选择 $p_i$，其余 residual demand保留
`ResolveAtInstallation`，不得读取 handler definition stack。
`checkClauseSchemas` 返回以 operation entry为键的
finite schema map $M_h$；`AggregateHandler` 把具体 return contract与这些
schema的 residual attributed demand、suspension、summary、path-specific result
transformer和 required phase逐项合并。它保留各 path，而不把 operation
clause伪装成 return clause。
因此 conclusion 中的 $epsilon_h$、$(S_i,p_i,a_i).C_h$ 都由已检查
clause决定，而不是
游离的 annotation。$Pi_h$ 进入 handler construction evidence；
`EnvBoundarySafe` 成立后才允许把 value自身 provenance记为
`Owner(ρ_h)`。这里 $rho_h$ 由 `CurrentOwner(Φ)` 与显式 authority premise
唯一绑定，不能由 rule conclusion凭空生成。`attachHandlerEnv` 把
$Pi_h/chi_h$ 封入 $C_h$ 的 sealed
construction evidence并序列化到 interface；所以 handler经变量或模块传递
后，`InstallOK` 仍可由 `handlerEnv(C_h)` 取得它们。

Handler value只保存以 installation stack、prompt与 exact entry参数化的
template；它没有 definition-site concrete route。每次 `with` installation
由 actual $(S_p,p,a)$ 实例化一次，所以同一个 handler value嵌套安装会得到
各自的 residual route，site/secondary demand不会混层。

`ClauseSchemaOK` 只产生/验证 site constraints。真正的
`Duplicable(χ_k)`、cleanup replay、world answer与 Owner-bound parking
obligation在 T-Handle 的 `InstallOK` 中对每个实际 site discharge。
