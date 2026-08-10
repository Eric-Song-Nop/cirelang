#import "../shared.typ": *

== Core contract elaboration <core-contract-elaboration>

与 hidden $L$ 相同，surface `(A) -> B ! ε` 先 elaboration为
$A arrow.r.long^(?C) B$，不是把未显示字段填成 `pure/same`。有 initializer
的 declaration求解 $?C$；高阶 input binder把未由 annotation约束的字段
泛化为 rigid contract parameter，并创建单一 `AppliedContractV2`，把调用时
用到的 row/world/flow/result/suspension/summary/usage/phase、$Q/Lambda$ 通过
同一 `InvokeV2`/`PathBindV2` computation投影进 enclosing function contract。
Declaration boundary不能留下未解 metavariable，interface必须序列化 solved
contract或其显式 quantified binder。

Core lambda binder携带显式、已 elaborated 的 annotation：

$
  eta_f ::= ⟨A,B,Phi_f⟩
$

其中 $A/B$ 是参数/结果类型，$Phi_f$ 是调用所需 phase/authority。基线中的普通
first-class closure一律按 many-call 检查；one-call closure必须等将来有
quantity-aware function binder后再加入，不能靠局部优化证据偷偷放宽。

Successor direct parameter `frame : FrameClock`（历史 `cap` token稳定拒绝）的完整 Core
binder不是普通 dependent term：

$
  forall i:"CapId"("FrameClock",rho).
  "Cap"[i,"FrameClock"] arrow.r.long^C "Next"[i,A,L_f]
$

$L_f$ 是从 function body求解并写入 interface的 sealed result contract。
该 universal的 wire projection使用一个 `QuantifiedIdentityBinderV1`：
`identity_slot` 供 `CapabilityTypeV1.identity`，必填的
`clock_refinement.clock_slot` 供 `NextTypeV1.clock` 与 Later contract；
`clock_refinement.identity` 显式回指前者。两种 namespace view因 witness
表示同一个 $i$，而不是因 slot数字相同而 alias。
若 `Next[i,A]` 出现在 parameter位置，则 declaration boundary反而引入：

$
  forall L:"LaterContract"(i,A).
  "Next"[i,A,L] arrow.r.long^C B
$

调用时 generative/implicit identity与 contract binder实例化，且受相同 escape
check。
Owner region也用 restricted region quantifier；二者都不是任意 term index。

`CommitTicket`、`CommitGate`、`Resume`、`Task` 等运行时对象内部携带实际
$(rho,g)$ token，但 $g$ 不出现在普通 type equality 中。静态系统检查
Owner region、phase、capture 与 boundary；stale generation 由运行时
原子验证。这一分层避免在没有一般 dependent type 的情况下伪造
`CurrentGeneration(ρ) = g` 之类的静态命题。

Surface 仍打印 `Next[i,A]`；第三个参数 $L$ 是只存在于 Typed
HIR/interface的 sealed later contract：

$
  L = ⟨pi_A,chi_A,delta_"body",Phi_"force"⟩
$

它随 `Next` type经过变量、ADT、函数返回与模块 interface传播，source不能
构造或模式匹配。Surface annotation中的缺省 $L$ 是一个 typed elaboration
hole而不是通配符：

```text
local synthesis from delay   produces an exact L
checking a result annotation solves ?L from the RHS
an input binder with no RHS  generalizes a rigid ∀L
an ADT field                 retains that hidden type parameter
module interface             serializes the solved/generalized binder
```

因此 `Next[i,A]` 绝不等于“存在某个运行时不可知的契约然后把它忘掉”。
不同 control-flow分支只能通过 sealed `joinLaterContract` 合并。对
$L_j="joinLaterContract"(L_1,L_2)$：

$
  L_j=
  ⟨"Stable",chi_1∪chi_2,
    delta_1⊔delta_2,
    "RequireBoth"(Phi_1,Phi_2)⟩
$

且 join evidence要求两个 branch的 common payload supertype成立、branch
cell capture分别包含 $chi_1/chi_2$。`RequireBoth` 的语义是：
`PhaseAllows(Φ, RequireBoth(Φ₁,Φ₂))` 当且仅当两项都允许；semantic
summary 的 $⊔$ 是保守上界。没有这些 proof就不能为了 branch join丢字段。
