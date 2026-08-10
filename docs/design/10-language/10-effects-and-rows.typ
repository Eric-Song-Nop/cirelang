#import "../shared.typ": *

== Effect 声明 <surface-3>

=== Operation mode <surface-3-1>

*已决定*

```moonbit
pub(open) ability Raise[E] {
  abort[A] raise(error : E) -> A
}

pub(open) ability SuspendOnce[A] {
  once wait(request : Deferred[A]) -> A
}

pub(open) ability Reader[R] {
  fun ask() -> R
}

pub(open) ability Search[A] {
  ctl[A] choose(values : Array[A]) -> A
}

pub(open) effect Error[E] : Raise[E] {}
pub(open) effect Waiting[A] : SuspendOnce[A] {}
pub(open) effect Environment[R] : Reader[R] {}
pub(open) effect Choice[A] : Search[A] {}
```

operation 的形式为：

```text
mode [type parameters] operation(parameters) -> result type
```

四个 mode 的核心含义为：

#table(
  columns: (1.4fr, 1.8fr, 2.8fr),
  [*mode*],
  [*clause 是否得到 continuation*],
  [*允许的处置*],
  [`abort`],
  [否],
  [不恢复],
  [`fun`],
  [否],
  [自动、恰好一次、尾恢复],
  [`once`],
  [是],
  [至多一次],
  [`ctl`],
  [是],
  [零次、一次或多次],
)

mode 写在类型参数之前，例如 `once[A] await(...)`，与具名函数的
`def[A] name(...)` 保持同一视觉顺序。

=== Effect visibility <surface-3-2>

*已决定*

Effect visibility 镜像 trait visibility：

```moonbit
effect Local { ... }
pub effect Sealed { ... }
pub(open) effect Open { ... }
```

- `effect`：只在当前 package 中可见；
- `pub effect`：其他 package 可以引用并调用，但只有定义 package 可以提供新的 handler 实现；
- `pub(open) effect`：其他 package 也可以提供 handler 实现。

可见性控制的是谁可以命名、调用和实现 effect，不改变 operation 的恢复模式。

=== Operation 的普通多态 <surface-3-3>

*已决定*

Operation 自己的方括号参数默认仍是 `Type`：

```moonbit
effect Choice {
  ctl[A] choose(values : Array[A]) -> A
}

effect Error[E] {
  abort[A] raise(error : E) -> A
}
```

- `Choice` 没有泛型参数；
- `Error[E]` 的 `E` 是 effect constructor 的普通类型参数；
- `choose` 和 `raise` 的 `[A]` 是每次 operation call 独立实例化的普通类型参数。

Handler clause 第一版不重复书写这些参数：

```moonbit
handler Choice {
  ctl choose(values) as k => values.first()
}
```

Typechecker 根据 operation declaration 找到 clause 后，为 declaration 中的
`A` 创建 fresh type skolem，并以该 skolem 检查参数、结果和 continuation。
Clause 不能假定某个具体 `A`，也不能把它和外层同名 type parameter 偶然
合并。高级 HIR dump 可以显示这个由 declaration 引入的 fresh skolem，但
Surface 不增加
`ctl[A] choose(...)` 的 clause 表面写法。

当前 profile 不允许 operation-own effect constructor、effect atom、row generic或 ordinary-trait
constraint；operation generic列表只能是上述无 constraint的 `[A, ...]` 普通 Type parameters。
因此早期实验形
`ctl[A]![..E] run(...)` 不进入 accepted grammar/HIR，也不产生一个无 wire image的
`OperationSignatureV2`。Higher-order operation仍可接收具有 concrete closed row的 callback；要求
row-polymorphic callback的 API必须改写为 ordinary named function/trait method boundary。

== Effect row <surface-4>

=== Closed 与 open row <surface-4-1>

*已决定*

```moonbit
def load(url : Url) -> Data
  ! {Network, Async, Error[HttpError]} {
  ...
}

def[A, B]![..E] map_effectful(
  xs : Array[A],
  f : (A) -> B ! E,
) -> Array[B] ! E {
  ...
}

def[A]![..E] observe_then(
  body : () -> A ! {Observe, ..E},
) -> A ! {Observe, ..E} {
  ...
}
```

- `! {}` 是空 row；每个具名 `def` 都必须显式写它，省略时报
  `named-function-effect-row-required`；
- `..E` 是 open row tail；
- row 的顺序不影响类型相等性；
- formatter 可以采用稳定顺序，但不得改变 source 中 capability binder 的身份。

=== Named capability <surface-4-2>

#metadata("R06-capability-identity") <rule-r06-capability-identity>

*已决定：row 中写 identity；direct binder 不写 `cap` marker*

源程序在 row 中直接写 capability 的 term identity：

```moonbit
def read_app(app : Read[Int]) -> Int ! {app} {
  app.read()
}
```

`{app}` 是最终的源语法。`app` 不是字符串，也不是用户可构造的全局名字，而是安装 handler 时生成的不可伪造身份。

编译器可以在高级诊断、类型展开或调试 dump 中把它显示为：

```text
Read[app]
```

`Read[app]` *只是一种诊断展开*，不能写进源程序，也不是泛型类型应用。诊断 UI 应优先显示用户写过的 `{app}`，只有在多个 capability 同名、来源不清或需要解释 effect family 时才展开为 `Read[app]`。

匿名 family effect 与 named capability 可以出现在同一 row：

```moonbit
def sync(app : Read[Model]) -> Unit
  ! {Network, Error[SyncError], app} {
  ...
}
```

=== 普通类型、effect 与 capability 多态 <surface-4-3>

*Profile baseline*

Cire 使用两个相邻但职责不同的 generic list：

```text
[...]   普通类型参数与普通 trait constraint
![...]  effect family、effect constructor 与 effect row 参数
```

Effect 列表中的 binder 由自身形状分类：

#table(
  columns: (1.2fr, 1.1fr, 1.7fr, 2fr),
  [*Binder*],
  [*Kind*],
  [*含义*],
  [*典型出现位置*],
  [`A`],
  [`Type`],
  [普通值类型],
  [`[A]`、`Array[A]`],
  [`F`],
  [`Effect`],
  [一个完整原子 effect],
  [`![F]`、row item `{F}`],
  [`F : Reader[A]`],
  [`Effect`],
  [满足 ability 的原子 effect],
  [`F::read()`],
  [`F[_]`],
  [`Type -> Effect`],
  [effect constructor],
  [`F[A]`],
  [`..E`],
  [`EffectRow`],
  [零个或多个 row item],
  [`![..E]`、`! E`、`..E`],
  [direct binder `app : F`],
  [capability term],
  [`F` 的一个具体 instance],
  [`app.read()`、`{app}`],
)

完整例子：

```moonbit
def[
  A : Eq + Show,
]![
  Input : Reader[A],
  Output : Writer[A],
  ..E,
] transfer(
  input : Input,
  output : Output,
  log : (String) -> Unit ! E,
) -> Bool ! {input, output, ..E} {
  let value = input.read()
  output.write(value)
  log(value.to_string())
  input.read() == value
}
```

Effect constraint 使用 ability。`ability`、`effect` 与 direct binder 的
职责是：

```text
ability   effect family 的静态 operation contract
effect    具体、名义化的 effect family
app : F   仅在 direct parameter binder 位置引入 family F 的具名 capability value
```

示例：

```moonbit
ability Reader[A] {
  fun read() -> A
}

ability Writer[A] {
  fun write(value : A) -> Unit
}

effect State[A] : Reader[A] + Writer[A] {}
```

同一份 ability evidence 同时支持匿名和具名调用：

```moonbit
def[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}

def[A]![F : Reader[A]] read_from(
  app : F,
) -> A ! {app} {
  app.read()
}
```

Core 必须继续区分：

```text
{F}    Anonymous(F)
{app}  Named(app, F)
```

只有 signature/kind stage证明为 direct capability parameter binder 的 `app : F`
才产生 abstract singleton identity并 lowering 为 `Cap[i_app,F]`。它不能有 default，
不能被 `ProvidedOrOmitted` 包装。普通 field/result/nested type 中的裸 Effect-kind
`F` 报 `capability-identity-required`；surface `cap F` 报
`surface-cap-marker-removed`。Alias `let other = app` 保留同一 identity，不生成新 one。

`app` 是 term binder 产生的 singleton identity，不写进 generic list。
普通 `Int` value 不能出现在 effect row。`with h as app in ...` 创建 fresh
identity，并在 Kernel HIR 中建立 rank-2/generative boundary；具体 lowering
是 `freshprompt p in handle[p,h,ι](let app=capref(ι); body)`，所以 body的
`app.read()` 有真实 lexical value binder，不是只向 identity/authority
context添加一个不可引用的名字。

四种常见 annotation：

```moonbit
! E                    // 精确 row variable
! {F}                  // 匿名 effect family
! {app}                // 具名 capability
! {F, app, ..E}        // 扩展开放 row
```

两个未知 row 使用 row formula，不在一个 literal 中放两个开放 tail：

```moonbit
def[A, B, C]![..E1, ..E2] compose(
  first : (A) -> B ! E1,
  second : (B) -> C ! E2,
) -> (A) -> C ! (E1 | E2) {
  fn(value) { second(first(value)) }
}
```

Effect row constraint 的 profile 形式：

```moonbit
def![
  ..E : Lacks[Blocking],
] schedule(task : () -> Unit ! E) -> Unit ! E {
  ...
}
```

`Lacks` 是本 profile 唯一冻结的 row predicate；它不是可调用 operation 的
ability。`Has`、`All` 与 `Only` 只有 grammar-reserved CST，没有 v1
solver/schema 语义，见 #ref(<surface-4-6>)。

显式调用也使用双列表：

```moonbit
consume[Int]![State[Int], {Log}](app, log_value)
```

普通类型实参和 effect/row 实参不会再依靠位置上的 kind marker 混合解释。

Ability 的 associated type/effect/row 与 Core 展开由本文和 temporal
formalization共同定义。Higher-kinded effect constructor只有 #ref(<surface-appendix-a>) 已冻结的
`F[_]` binder shape；一般 `fresh`/one-call function type仍在 #ref(<surface-11>) 的 profile
boundary registry 中，不属于 v1。

完整 binder、argument 与 `RowExpr` grammar 见 #ref(<surface-a-3>)。表面的两个形参列表
是不同 kind domain 的参数绑定；只有 elaboration/generalization 明确引入
Core binder 时才讨论量词。

=== Associated Type、Effect 与 EffectRow <surface-4-4>

*Profile baseline*

Ability 可以声明三种不同 kind 的 associated item；声明关键字就是 kind
判别器，resolver不得根据右侧拼写猜 kind：

```moonbit
pub(open) ability Store {
  type Key
  type Value
  effect Fail
  effects Extra : Lacks[Blocking] = {}

  fun get(key : Key) -> Value ! {Fail}
  fun put(key : Key, value : Value) -> Unit ! {Fail}
}
```

#table(
  columns: (1.4fr, 1.8fr, 2.8fr),
  [*declaration*],
  [*associated kind*],
  [*projection position*],
  [`type Key`],
  [`Type`],
  [ordinary type, such as `S::Key`],
  [`effect Fail`],
  [`Effect`],
  [atomic row entry, such as `{S::Fail}`],
  [`effects Extra`],
  [`EffectRow`],
  [row/tail, such as `..S::Extra` or `S::Extra`],
)

Ability constraint和 effect header使用具名 associated argument；左侧必须是
该 ability恰好一个已声明 item，右侧按声明 kind检查：

```moonbit
pub(open) effect FileStore
  : Store[
      Key = Path,
      Value = Bytes,
      Fail = IoFailure,
      Extra = {Async},
    ] {}

def[A]![S : Store[Value = A]] load_as(
  store : S,
  key : S::Key,
) -> A ! ({store, S::Fail} | S::Extra) {
  store.get(key)
}
```

Elaboration先按 ability declaration解析 named argument，再产生
`AssocEq(S,item,value,kind)` evidence；不能把 `Fail = IoFailure` 当普通
positional type argument，也不能在三个 kind间互换 projection。这里有两个不同、
不可混用的 completion context：

- generic constraint `S : Store[Value = A]` 的 named map是 *partial*。Resolver
  按全部 associated declaration一次性给 `S::Key/Value/Fail/Extra` 分配确定 hidden
  binder；显式 `Value=A` 只增加对应等式，未写出的 item保持 symbolic且仍可投影。
  Generic omission *不应用 declaration default*；否则 `Extra={}` 会错误禁止合法
  concrete witness覆写该 default；
- concrete effect header的 map是 *total*。每个 item必须显式给出一次，或取声明处
  same-kind default；missing-without-default稳定拒绝。完成后才可生成 total header
  evidence并 substitute operation signature；
- generic application用 concrete header的 total vector实例化全部 hidden binder，再在
  ordinary type/row substitution之后验证 generic显式等式。因此 `Store[Value=A]`
  applied to `FileStore[Value=Bytes]` 要求 `A=Bytes`。

Unknown、duplicate与 kind mismatch在两个 context都拒绝；missing只对 concrete
header拒绝。Projection只有在同 declaration-identity 的 generic或header evidence
可见时成立，不只比较短名字；同一 binder从两个 ability得到同名 item且 surface无
ability qualifier时也拒绝。这些 failure统一在 Kind阶段稳定报告
`associated-contract-mismatch`，不能 fall through成普通 positional generic或
unknown member诊断。

Interface lowering不新增第二个 `AssociatedProjection` wire tag。对每个带 generic
ability evidence的 Effect binder，exporter按 `(effect-binder slot, ability
declaration identity, associated declaration ordinal)` 排序，一次性在现有 namespace
分配 hidden binder：associated Type/Effect进入 `TypeBinderV1` 且保留各自 kind，
associated EffectRow进入 `RowBinderV1`。Projection分别改写成现有
`TypeParameterV2`、Effect-kind family reference或 `TailV1`；named equality/default
进入同一 `ContractSubstitutionV2` 的 type/row argument；generic omission仍产生
symbolic slot，不产生 default equality。Concrete effect header则在 export前完成
explicit/default total substitution。这样 import hash、alpha qualification与 scope沿用现有
wire contract，不会因 source projection增加未版本化 variant；所有 hidden binder的
origin仍指回原 projection/ability declaration。Effect-family position中的
nominal reference还必须由 producer/import declaration environment按 module-qualified
identity解析为 Effect且 arity exact，不能仅凭 `NominalTypeV1` shape猜 kind；
successor complete roots只从 package graph的 exact `EffectDeclarationV1` declaration closure冻结该
环境。Retained `EffectFamilyDeclarationsV1` 是 profile-disjoint TR0 fixture，不得提供 v1 identity。
Importer对 Effect-kind substitution在 family position解包 nominal V2 legacy envelope，
并对替换后的完整 function kind（含 public row）重做 WF；public与
contract-binder row中的每个 `TailV1`都必须引用当前 Row binder。Identity
substitution还必须把 target identity binder的已实例化 family与 caller live
identity declaration逐一比较，并用 caller identity/handler-contract table重查
instantiated public row中的每个 selector。Handler oracle的外层 declaration
binders就是 handler contract的 caller scope；同一 complete type/Row/Contract/
Identity/handler-contract table递归约束 handled entry、header residual row、return与
clause computation的每条 path、latent site、suffix/cleanup、application substitution
及其 instantiated public row，也传入普通 nested type中的 inline
`HandlerContractV2`。`PathBindV2` Return与 clause disposition仍只扩展各自 local
subtree；inline `FunctionContractV3`建立自己的 declaration scope，imported/local
function target也只在自身 declaration下验证，caller只验证 reference、substitution与
实例化后的 public row。

这里以及本文其它位置保留的 `ContractSubstitutionV2`、`HandlerContractV2`、
`PathBindV2` 等 V2-named composite，都精确指形式化 `M3` 对其 enclosing V3 root
递归变换后的 occurrence；任何深度的 raw `ContractRefV2` 或
`FunctionContractV2` 都不是 successor input，不能借保留的 tag spelling绕过 M3。

#metadata("R06-associated-ability-profile-boundary") <rule-r06-associated-ability-profile-boundary>

successor V3/M3 wire只为 ability-associated EffectRow携带 `Lacks[e]`：generic hidden
`RowBinderV1`继承该 evidence，concrete explicit/default row必须证明它。Ordinary trait
的 zero-arity associated Type declaration可带 ordinary trait constraints，并精确进入
`AssociatedTypeDeclarationV1.constraints`；不能把 ability wire限制施加给 ordinary
trait。#ref(<surface-appendix-a>)为了稳定 recovery仍在 `AbilityItem` context识别 associated Type
constraint、associated Effect ability constraint与 nonempty associated `TypeParams`，
但这些 ability evidence/arity尚无 retained wire表示，必须在 body/default检查前分别
稳定拒绝 `associated-declaration-constraint-not-in-profile` 与
`associated-parameterization-not-in-profile`。v1 也没有 `where` clause、递归
associated equality或 higher-ranked associated item；未来 profile不得由实现私自扩展。

=== Effect-header ability conformance 与独立 `impl` <surface-4-5>

*Profile baseline：只冻结 effect header conformance*

```moonbit
effect State[A] : Reader[A] + Writer[A] {}
```

这个 header 在 effect定义 package内产生 local ability witness。每个 ability
只可在同一 header出现一次；associated argument按 #ref(<surface-4-4>) exact检查；ability的
每个 operation经 substitution后必须与 effect自身或已继承 operation具有相同
参数/结果、secondary contract与 resumption mode。两个 ability若导出同名
operation，只有完整 substituted signature和 mode相同才可合并为同一 operation；
否则 conformance拒绝。Result visibility不能超过 effect与 ability两者中较窄的
一方，因此 header不能绕过 `pub` / `pub(open)` sealing。Duplicate ability、
signature/mode conflict或 visibility widening统一稳定报告
`effect-header-conformance-mismatch`。

#ref(<surface-appendix-a>) 仍为 ordinary trait实现保留 `impl` declaration，并能构造
ability-target `ImplDecl` CST；但 *独立 ability `impl` 不属于 v1*。Resolver
一旦确认 `impl` 左侧是 ability，必须稳定拒绝
`independent-ability-impl-not-in-profile`。因此 orphan/coherence、overlap、
specialization、operation adapter、associated binding uniqueness、mode
compatibility和跨 package visibility没有“先实现再决定”的隐含规则；它们必须在
新 profile一起冻结后，独立 ability `impl` 才能成为 accepted form。普通 trait
target则按 #ref(<surface-2-5>) 的 orphan/coherence/overlap 与 associated-type规则形成 accepted
`ImplDecl`，但永远不能产生 ability evidence或绕过 effect-profile边界。

=== Row algebra 与 predicate status <surface-4-6>

*Profile baseline*

Row是 identity-aware finite set加 rigid row-variable summand。`|` 是唯一
surface union；normalization flatten union、删除已知重复 entry、按 stable
identity排序，并保留 rigid summand。`Anon(F)` 与 `Named(app,F)` 是不同 entry，
同 family不自动合并。

`Lacks[Elt]` 是唯一冻结的显式 row predicate。`..E : Lacks[X]` 给 constraint
environment加入 `Lacks(E,X)` evidence；literal extension `{X, ..E}` 必须从该
environment或已知 closed-row normalization证明同一 obligation，不能对未知 tail
静默去重。Union本身不制造 `Lacks` evidence；intersection、difference与 raw
family subtraction不属于本 profile。

#ref(<surface-appendix-a>) 为 profile evolution保留通用 `RowPredicate` CST，但显式
`Has[...]`、`All[...]`、`Only[...]` 在 v1 一律由 RowWF稳定拒绝
`row-predicate-not-in-profile`。它们没有 builtin-name特判、solver、wire schema或
隐含 diagnostic contract；未来若加入，必须以新 profile同时定义上述四项。
