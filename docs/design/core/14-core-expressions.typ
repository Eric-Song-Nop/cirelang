#import "../shared.typ": *

== Effect rows、capture 与 provenance

$
  a ::= "Anon"(F) | "Named"(i, F)
$

$
  epsilon ::= emptyset | mu | {a} | epsilon_1 ⊔ epsilon_2
  quad
  C_epsilon ::= emptyset | {"Lacks"(epsilon,a)} | C_1 ∪ C_2
$

$
  Delta ::= emptyset
    | {"Demand"(kappa,p,a,o,q)}
    | Delta_1 ∪ Delta_2
$

每个 demand 有稳定的 suspension attribution key：

$
  r_s ::= ⟨kappa,p,a,o,q⟩
  quad
  "demandKey"("Demand"(kappa,p,a,o,q))=r_s
$

`demandKeys(Δ)` 是逐项应用 `demandKey` 得到的 finite set。相同 entry
但不同 site、installation prompt、operation 或 primary/secondary slot
会得到不同 key。

这里 $p$ 是一次 handler *installation* 的 fresh prompt（或 outer/root
route），$q$ 是 `Primary` 或稳定的 secondary-site slot；handler value本身
不是 route。

$
  chi ::= emptyset
    | {i}
    | {"owner"(rho)}
    | {"resume"(k)}
    | {"borrow"(beta)}
    | {"claim"(c)}
    | chi_1 ∪ chi_2
$

$
  pi ::= "Stable" | "Region"(r) | "Callback"(c)
       | "Owner"(rho) | "GenerationBound"(rho) | "Env"(Pi)
$

$
  Pi ::= emptyset | {x ↦ (A,pi,chi)} | Pi_1 ∪ Pi_2
$

Rows 是带约束的 AC-idempotent union algebra；`Anon(F)` 与 `Named(ι,F)`
不相等。Surface row elaboration judgment 为：

$
  K;I ⊢ R_"surface" ⇝ epsilon ⊣ C_epsilon
$

#irule(
  [Row-Empty],
  ([$"wellFormedRowLiteral"("{}")$],),
  [$K;I ⊢ {} ⇝ emptyset ⊣ emptyset$],
)

#irule(
  [Row-Ref],
  ([$K(mu)="EffectRow"$],),
  [$K;I ⊢ mu ⇝ mu ⊣ emptyset$],
)

#irule(
  [Row-Closed],
  (
    [$n >= 1$],
    [$forall j in 1..n. K;I ⊢ a_j:"EffectEntry"$],
    [$"DistinctEntries"(a_1,...,a_n)$],
  ),
  [$K;I ⊢ {a_1,...,a_n} ⇝
    "foldRowEntries"(a_1,...,a_n) ⊣ emptyset$],
)

#irule(
  [Row-Tail],
  (
    [$K;I ⊢ R ⇝ epsilon ⊣ C$],
  ),
  [$K;I ⊢ {..R} ⇝ epsilon ⊣ C$],
)

#irule(
  [Row-Open],
  (
    [$n >= 1$],
    [$K;I ⊢ R ⇝ epsilon ⊣ C$],
    [$forall j in 1..n. K;I ⊢ a_j:"EffectEntry"$],
    [$"DistinctEntries"(a_1,...,a_n)$],
  ),
  [$K;I ⊢ {a_1,...,a_n,..R} ⇝
    "foldRowEntries"(a_1,...,a_n) ⊔ epsilon
    ⊣ C∪"lacksAll"(epsilon,a_1,...,a_n)$],
)

#irule(
  [Row-Union],
  (
    [$K;I ⊢ R_1 ⇝ epsilon_1 ⊣ C_1$],
    [$K;I ⊢ R_2 ⇝ epsilon_2 ⊣ C_2$],
  ),
  [$K;I ⊢ R_1 | R_2 ⇝
    epsilon_1 ⊔ epsilon_2 ⊣ C_1∪C_2$],
)

`RowNormalize(ε,Cε)` 按 identity排序已知 entry、保留所有 rigid row
variable summand和 `Lacks` constraint；Core union没有“最多一个开放
tail”的限制，也不把 `E1 | E2` 假装成单一 tail。Surface literal的 grammar
仍只允许一个 final tail，所以
`{..E1,..E2}` 被拒绝；`E1 | E2` 则由 `Row-Union` 合法进入 Core union
algebra。

Demand splitting是对 attribution做的可判定 partition：

$
  "RowSplit"(Delta,p)
  =
  ⟨Delta_"here",Delta_"out"⟩
$

其中 $Delta_"here"={d in Delta | "route"(d)=p}$，
$Delta_"out"=Delta - Delta_"here"$，并满足
$"eraseDemand"(Delta)=
  "eraseDemand"(Delta_"here") ⊔ "eraseDemand"(Delta_"out")$。
因此 public row由 `$epsilon="eraseDemand"(Delta)$` 导出，不再作为与
$Delta$ 可独立漂移的第二项事实。

$Delta$ 是 attributed demand：$kappa$ 是稳定 call site，$p$ 是
installation prompt route，$a/o$ 是 resolved entry/operation，$q$ 区分
primary 与各 secondary-site slot。每个 secondary site先实例化自己的
$(kappa_q,a_q,o_q)$，再由显式 $S$ 独立运行 `resolveRoute(S,a_q)`；
它不能继承 primary demand 的 route。Exact handling只移除
`RowSplit(Δ,p).here`，不是对 family 名做 raw set subtraction。
同 family forwarding 在 Surface 尚无冻结拼写；Kernel 必须显式产生
`forward[p_outer](a,o,args)`，把 primary demand route更新到 outer prompt并保留原
identity/site。它不能用“先删 `{a}`、再加 `{a}`”模拟，否则 nested
same-family handler 与 secondary demand会失去 attribution。

Forwarding使用一个原子 reroute pair：

$
  "reroutePrimary"(
    "Demand"(kappa,p,a,o,"Primary"),
    "request"(⟨kappa,p,a,o,"Primary"⟩,d),
    p_"outer")
  =
  ⟨
    "Demand"(kappa,p_"outer",a,o,"Primary"),
    "request"(⟨kappa,p_"outer",a,o,"Primary"⟩,d)
  ⟩
$

它保持 $kappa/a/o/q$，只改 primary route与同 key suspension atom。
Secondary sites不经过这个 helper；它们各自按当前 prompt stack重新
`resolveRoute`。
空 residual row 只表示没有 operation 向外请求：

$
  epsilon = emptyset quad ⇏ quad "TemporalPure"(delta)
$

== Core expressions

#align(center)[
  $e ::= x | lambda^[eta_f] x.e | e_1(e_2)
    | "let" x=e_1;e_2$ \
  $quad | "CapAbs"(i,v) | v[j]
    | "packClock"[j](v) " as "
        (exists i:"ClockId"("FrameClock",rho),
          S:"ClockPackageSummary"(i,A).A)$ \
  $quad | "unpackClock" [i,x]=p " in " e
    | "OwnerAbs"(rho,v) | v[rho]$ \
  $quad | "freshcap" i:F@rho " in " e
    | "capref"(i)
    | "delay"_i(e) | "advance"(e)$ \
  $quad | "op"[a]("name",bar(e))
    | "forward"[r](a,"name",bar(e))
    | "handler"[F]{bar(c)}
    | "freshprompt" p " in " "handle"[p,h,i?](e)$ \
  $quad | "resume"(k,v)
    | "finalize"(k)
    | "park"("src",o,k)$ \
  $quad | "intrinsic"(n,bar(e))$
]

== 关键 elaboration

```text
Next[frame, A]
  ↦ Next[ιframe, A, ?L]

?L is solved from an initializer/result;
an annotation-only input position generalizes rigid ∀L.

delay[frame] { e }
  ↦ delay_ιframe(elab(e))

advance(e)
  ↦ advance(elab(e))
    only when `advance` resolves to the sealed intrinsic

with h1 as c1
with h2
in e
  ↦ ScopedApply(
      elab(h1), c1,
      thunk { ScopedApply(elab(h2), none, thunk { elab(e) }) },
    )

handler F { operation clauses }
  ↦ handler F {
      operation clauses
      return(value) => value
    }
    when Surface omitted `return`;
    this normalization runs before clause partition/exactness

def f(p1, ..., pn) -> R ! epsilon { e }
  ↦ a named recursive binding whose value is one Core function over
    an immutable n-ary argument tuple

def f(...) -> R ! epsilon { items; result }
  ↦ ordinary named-function return of elab(result);
    no hidden resumption is introduced

fun op(...) => { items; result }
  ↦ items; let value = elab(result) in resume(hidden_k, value)
    on every normal exit; abortive exits run the hidden disposition cleanup

f(a_source1, ..., a_sourcen)
  ↦ let x1 = elab(a_source1) in ... let xn = elab(a_sourcen) in
    f(tupleByParameterOrder(x1, ..., xn))
    after labels are resolved; source evaluation order is unchanged

resolver:
  ScopedApply(handlerValue : HandlerTemplate[...], binder cap, bodyThunk)
    ↦ let h = handlerValue in
      freshprompt p in
        handle[p, h, ι](
          let cap = capref(ι) in bodyThunk(cap))

  ScopedApply(ordinaryTransformer, none, bodyThunk)
    ↦ ordinaryTransformer(bodyThunk)

frame.yield()
  ↦ op[Named(ιframe, FrameClock)](yield, [])

live { e }
  ↦ first-party intrinsic/library boundary, not a new parser form

@temporal::pack_next(under=owner) { frame => e }
  ↦ contextual intrinsic PackNext(owner, frame, e)

@temporal::try_with_packed_next(packed) { frame, pending => e }
  ↦ contextual intrinsic TryOpenPackedNext(packed, frame, pending, e)

@temporal::dispose(packed)
  ↦ contextual intrinsic DisposePackedNext(packed)
```

Only the resolved sealed first-party origin receives these lowerings. A user
function or dependency alias with the same final identifier remains an ordinary
call/trailing lambda and cannot introduce fresh frame/lease binders.

`with ... as cap` 的 identity 不能按普通 lambda parameter generalize。
Surface HIR先保留统一的 `ScopedApply`，以保证 operand evaluation order与
inner thunk调用次数；resolver证明 operand具有 `HandlerTemplate[...]`
type后才降为
Kernel `handle`。普通 scoped transformer仍是函数调用，不能被错误地赋予
effect-row elimination。Kernel `freshprompt p; handle[p,h,i]` 每次安装
生成 route prompt和 generative identity，并立即以唯一 value introduction
`capref(i)` 把 Surface binder加入 lexical context；在结果处先 drop term
binder再执行 identity escape check。

Synthetic identity return 强制 $B=A$，contract 为 same-world、empty row、
`NoSuspend`、`Pure`，并把输入 summary逐字保留：

$
  R_"identity"(pi,chi)=(pi,chi)
$

它不能把结果洗成 `Stable/∅`。若 handler做 answer-type transformation，例如
$A -> "Result"[A,E]$，则不能省略 return。
