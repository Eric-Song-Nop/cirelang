#import "../shared.typ": *

== Anonymous handling

#irule(
  [T-Handle-Anon-Paths],
  (
    [$K;I;Phi@Theta ⊢_v h ⇒
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$a="Anon"(F) quad p ∉ "prompts"(S)$],
    [$S_p="pushPrompt"(S,p,a)$],
    [$K;I;Phi;Omega@Theta;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I;Phi@Theta;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$C_i=C_h[S_i,p_i,a_i:=S_p,p,a]$],
    [$"InstallOK"(S_p,p,h,P_h,a,bar(kappa),E_e,C_i)
      ⇓ E_i$],
    [$cal(F)_o="publicFlow"(E_i)
      quad delta_o="semanticSummary"(E_i)$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi,"requiredPhase"(C_i))$],
    [$"RowSplit"(Delta_e,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$"AttributedOK"(Delta_e,s_e)$],
    [$Delta_h="handlerResidual"(E_i)$],
    [$Delta_o=Delta_"out"∪Delta_h
      quad epsilon_o="eraseDemand"(Delta_o)$],
    [$s_o="handleInstallSusp"(s_e,Delta_"here",E_i)
      quad "AttributedOK"(Delta_o,s_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
    "freshprompt" p " in " "handle"[p,h,"anon"](e))
    ⇓ cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_e$],
)

`RowSplit` 只消费 route恰为 fresh $p$ 的 demand；同 family outer demand、
explicit forwarding 与每个独立路由的 secondary demand都留在
$Delta_"out"$。`InstallOK` 的 path map逐项保留 transfer，因此这条 rule同时
是 return、abort 与 T-Handle-Transfer congruence，不再用 “NoReturn ⇒
Aborts” 的错误二分。

Handler 消除对应 prompt demand，但 $P_h$ 仍进入 $delta$。所以：

```text
handled row becomes empty
```

不能推出：

```text
computation is temporal-pure or replay-safe
```

== Generative named handling

#irule(
  [T-Handle-Named-Paths],
  (
    [$K;I;Phi@Theta ⊢_v h ⇒
      "HandlerTemplate"[F,rho_h,A,B,epsilon_h,(S_i,p_i,a_i).C_h,P_h]
      @[pi_h] ▷ chi_h$],
    [$"HandlerOriginOK"(Phi,rho_h) quad i ∉ "dom"(I)
      quad p ∉ "prompts"(S)$],
    [$a="Named"(i,F) quad I'=I,i:F@rho_h quad Phi_i="addAuthority"(Phi,a)$],
    [$x_"cap" " fresh" quad
      Theta_i="bind"(Theta,x_"cap":"Cap"[i,F]
        @["Region"(rho_h)] ▷ {i})$],
    [$S_p="pushPrompt"(S,p,a)$],
    [$K;I';Phi_i;Omega@Theta_i;S_p ⊢ "body"_A(e) ⇓
      cal(F)_e ! epsilon_e;Delta_e;s_e;delta_e ⊣Omega_e$],
    [$K;I';Phi_i@Theta_i;S_p ⊢ "sites"(e,a,p) ⇓ bar(kappa)$],
    [$E_e=⟨cal(F)_e,epsilon_e,Delta_e,s_e,delta_e⟩$],
    [$C_i=C_h[S_i,p_i,a_i:=S_p,p,a]$],
    [$"InstallOK"(S_p,p,h,P_h,a,bar(kappa),E_e,C_i)
      ⇓ E_i$],
    [$cal(F)_h="publicFlow"(E_i)
      quad delta_o="semanticSummary"(E_i)$],
    [$"PolicyOK"(P_h) quad "PhaseAllows"(Phi_i,"requiredPhase"(C_i))$],
    [$"RowSplit"(Delta_e,p)=⟨Delta_"here",Delta_"out"⟩$],
    [$"AttributedOK"(Delta_e,s_e)$],
    [$Delta_h="handlerResidual"(E_i)
      quad Delta_o=Delta_"out"∪Delta_h$],
    [$epsilon_o="eraseDemand"(Delta_o)
      quad cal(F)_b="dropFlowBinder"(cal(F)_h,x_"cap")
      quad cal(F)_o="hideIdentityFlow"(cal(F)_b,i)$],
    [$s_o="handleInstallSusp"(s_e,Delta_"here",E_i)
      quad "AttributedOK"(Delta_o,s_o)$],
    [$"NoOpenPrivateDisposition"(i,Omega_e)$],
    [$Omega_o="hideIdentityUsage"(Omega_e,i)$],
    [$i ∉ "fv"(B,cal(F)_o,epsilon_o,Delta_o,s_o,delta_o,Omega_o)$],
  ),
  [$K;I;Phi;Omega@Theta;S ⊢ "body"_B(
    "freshprompt" p " in " "handle"[p,h,i](
      "let" x_"cap"="capref"(i);e))
    ⇓ cal(F)_o ! epsilon_o;Delta_o;s_o;delta_o ⊣Omega_o$],
)

最后一个 premise 同时检查：

- result type 不泄漏 identity；
- residual row 不泄漏 `{i}`；
- closure/capture 不保留 `i`；
- private temporal lock 由 `hideIdentity` 在 runner边界投影掉；
- handler origin 的 Owner 仍 outlive 结果。

合法 existential container 使用单独的 packaging rule，不能删除 escape
premise。

== Handler ordering

Nested `with` 按 elaboration 后的普通 evaluation order和 T-Handle 规则
right-fold：

$
  "freshprompt" p_1."handle"[p_1](h_1,
    "freshprompt" p_2."handle"[p_2](h_2,e))
  !=
  "freshprompt" p_2."handle"[p_2](h_2,
    "freshprompt" p_1."handle"[p_1](h_1,e))
$

Typing 不对 handler stack 排序；optimizer 也不能仅凭 row set equality交换。
