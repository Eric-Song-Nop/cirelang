# Cire 表面语法规范

## 1. 状态与目标

> **Profile:** [`Cire-TR₀/2026-08-01`](spec-status.md)
>
> 本文是表面 grammar 与 elaboration 的唯一规范来源；完整、实现无关的
> token/PEG grammar 收录在本文 Appendix A。

本文把 profile baseline 与仍需研究的语义边界分开：

- 标为 **Profile baseline** 的写法是当前规范；
- 标为**工作语法**的写法已有唯一 grammar/elaboration，但拼写仍可调整；
- 标为**开放问题**的部分不得被未来编译器悄悄赋予偶然语义。

Cire 的基本外观遵循 MoonBit：

- 泛型参数和泛型实参使用方括号；
- 函数、方法、ADT、模式匹配、labelled argument、包限定名尽量沿用 MoonBit 的形状；
- block 是表达式，最后一个表达式是结果；
- Cire 只为 effect、handler、continuation 与 named capability 增加必要语法。

规范先于实现。未来 parser 与 conformance test 必须服从本文 Appendix A，
不能反向裁决语言。

## 2. MoonBit 风格基线

**已决定**

```moonbit
enum Option[A] {
  None
  Some(A)
}

struct Pair[A, B] {
  first : A
  second : B
}

def[A, B] map(
  xs : Array[A],
  f : (A) -> B,
) -> Array[B] {
  ...
}
```

统一采用：

| 概念 | Cire 写法 |
|---|---|
| 类型实参 | `Array[A]` |
| 具名函数类型参数 | `def[A] map(...)` |
| 函数类型 | `(A) -> B`、`(A, B) -> C` |
| 可变局部绑定 | `let mut value = ...` |
| 方法声明 | `def Type::method(self : Type, ...)` |
| package-qualified name | `@pkg::name`（多段 package path 可写 `@org.pkg::name`） |
| labelled parameter | `key~ : Key` |
| labelled argument | `key=value` 或 label punning |
| 结构化退出动作 | `defer cleanup()` |

纯函数省略 effect row。无参数具名函数写 `def name() { ... }`；匿名函数值写
`fn() { ... }`。Lambda parameter 使用独立 grammar，既可推导
`fn(value) { ... }`，也可显式写 `fn(value : Int) { ... }`；它不复用要求
类型 annotation 的 declaration `ParamList`，也不会引入单独的 procedure
语法。

## 3. Effect 声明

### 3.1 Operation mode

**已决定**

```moonbit
pub(open) ability Raise[E] {
  abort[A] raise(error : E) -> A
}

pub(open) ability Await[A] {
  once[A] await(task : Task[A]) -> A
}

pub(open) ability Reader[R] {
  fun ask() -> R
}

pub(open) ability Search[A] {
  ctl[A] choose(values : Array[A]) -> A
}

pub(open) effect Error[E] : Raise[E] {}
pub(open) effect Async[A] : Await[A] {}
pub(open) effect Environment[R] : Reader[R] {}
pub(open) effect Choice[A] : Search[A] {}
```

operation 的形式为：

```text
mode [type parameters] operation(parameters) -> result type
```

四个 mode 的核心含义为：

| mode | clause 是否得到 continuation | 允许的处置 |
|---|---:|---|
| `abort` | 否 | 不恢复 |
| `fun` | 否 | 自动、恰好一次、尾恢复 |
| `once` | 是 | 至多一次 |
| `ctl` | 是 | 零次、一次或多次 |

mode 写在类型参数之前，例如 `once[A] await(...)`，与具名函数的
`def[A] name(...)` 保持同一视觉顺序。

### 3.2 Effect visibility

**已决定**

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

### 3.3 Operation 的普通多态

**已决定**

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

如果 operation 需要接收 effect-polymorphic callback，可以在自己的 generic
列表中声明 effect row。普通参数与 effect 参数使用双列表：

```moonbit
effect Scope {
  ctl[A]![..E] run(
    body : () -> A ! E,
  ) -> A
}
```

`[A]` 是普通类型参数，`![..E]` 是 effect row 参数。是否把这种
higher-order operation 限制为特定 resumption mode，留给
type/effect safety 规则决定。

## 4. Effect row

### 4.1 Closed 与 open row

**已决定**

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

- `! {}` 是空 row，但纯函数应省略它；
- `..E` 是 open row tail；
- row 的顺序不影响类型相等性；
- formatter 可以采用稳定顺序，但不得改变 source 中 capability binder 的身份。

### 4.2 Named capability

**已决定：row 中写 identity；`cap F` 是仍可调整的工作形式**

源程序在 row 中直接写 capability 的 term identity：

```moonbit
def read_app(app : cap Read[Int]) -> Int ! {app} {
  app.read()
}
```

`{app}` 是最终的源语法。`app` 不是字符串，也不是用户可构造的全局名字，而是安装 handler 时生成的不可伪造身份。

编译器可以在高级诊断、类型展开或调试 dump 中把它显示为：

```text
Read[app]
```

`Read[app]` **只是一种诊断展开**，不能写进源程序，也不是泛型类型应用。诊断 UI 应优先显示用户写过的 `{app}`，只有在多个 capability 同名、来源不清或需要解释 effect family 时才展开为 `Read[app]`。

匿名 family effect 与 named capability 可以出现在同一 row：

```moonbit
def sync(app : cap Read[Model]) -> Unit
  ! {Network, Error[SyncError], app} {
  ...
}
```

### 4.3 普通类型、effect 与 capability 多态

**Profile baseline**

Cire 使用两个相邻但职责不同的 generic list：

```text
[...]   普通类型参数与普通 trait constraint
![...]  effect family、effect constructor 与 effect row 参数
```

Effect 列表中的 binder 由自身形状分类：

| Binder | Kind | 含义 | 典型出现位置 |
|---|---|---|---|
| `A` | `Type` | 普通值类型 | `[A]`、`Array[A]` |
| `F` | `Effect` | 一个完整原子 effect | `![F]`、row item `{F}` |
| `F : Reader[A]` | `Effect` | 满足 ability 的原子 effect | `F::read()` |
| `F[_]` | `Type -> Effect` | effect constructor | `F[A]` |
| `..E` | `EffectRow` | 零个或多个 row item | `![..E]`、`! E`、`..E` |
| `app : cap F` | capability term | `F` 的一个具体 instance | `app.read()`、`{app}` |

完整例子：

```moonbit
def[
  A : Eq + Show,
]![
  Input : Reader[A],
  Output : Writer[A],
  ..E,
] transfer(
  input : cap Input,
  output : cap Output,
  log : (String) -> Unit ! E,
) -> Bool ! {input, output, ..E} {
  let value = input.read()
  output.write(value)
  log(value.to_string())
  input.read() == value
}
```

Effect constraint 使用 ability。`ability`、`effect` 与 `cap` 的当前设计
职责是：

```text
ability   effect family 的静态 operation contract
effect    具体、名义化的 effect family
cap F     family F 的具名 capability value
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
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

Core 必须继续区分：

```text
{F}    Anonymous(F)
{app}  Named(app, F)
```

`app` 是普通 term binder 产生的 singleton identity，不写进 generic list。
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
] schedule(task : () -> Unit ! E) -> Task ! E {
  ...
}
```

`Lacks` 是本 profile 唯一冻结的 row predicate；它不是可调用 operation 的
ability。`Has`、`All` 与 `Only` 只有 grammar-reserved CST，没有 TR₀
solver/schema 语义，见 §4.6。

显式调用也使用双列表：

```moonbit
consume[Int]![State[Int], {Log}](app, log_value)
```

普通类型实参和 effect/row 实参不会再依靠位置上的 kind marker 混合解释。

Ability 的 associated type/effect/row 与 Core 展开由本文和 temporal
formalization共同定义。Higher-kinded effect constructor只有 Appendix A 已冻结的
`F[_]` binder shape；一般 `fresh`/one-call function type仍在 §11 的 profile
boundary registry 中，不属于 TR₀。

完整 binder、argument 与 `RowExpr` grammar 见 Appendix A.3。表面的两个形参列表
是不同 kind domain 的参数绑定；只有 elaboration/generalization 明确引入
Core binder 时才讨论量词。

### 4.4 Associated Type、Effect 与 EffectRow

**Profile baseline**

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

| declaration | associated kind | projection position |
|---|---|---|
| `type Key` | `Type` | ordinary type, such as `S::Key` |
| `effect Fail` | `Effect` | atomic row entry, such as `{S::Fail}` |
| `effects Extra` | `EffectRow` | row/tail, such as `..S::Extra` or `S::Extra` |

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
  store : cap S,
  key : S::Key,
) -> A ! ({store, S::Fail} | S::Extra) {
  store.get(key)
}
```

Elaboration先按 ability declaration解析 named argument，再产生
`AssocEq(S,item,value,kind)` evidence；不能把 `Fail = IoFailure` 当普通
positional type argument，也不能在三个 kind间互换 projection。这里有两个不同、
不可混用的 completion context：

- generic constraint `S : Store[Value = A]` 的 named map是 **partial**。Resolver
  按全部 associated declaration一次性给 `S::Key/Value/Fail/Extra` 分配确定 hidden
  binder；显式 `Value=A` 只增加对应等式，未写出的 item保持 symbolic且仍可投影。
  Generic omission **不应用 declaration default**；否则 `Extra={}` 会错误禁止合法
  concrete witness覆写该 default；
- concrete effect header的 map是 **total**。每个 item必须显式给出一次，或取声明处
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
repository complete roots以可消费的 `EffectFamilyDeclarationsV1`冻结该环境。
Importer对 Effect-kind substitution在 family position解包 nominal V2 legacy envelope，
并对替换后的完整 function kind（含 public row）重做 WF；public与
contract-binder row中的每个 `TailV1`都必须引用当前 Row binder。Identity
substitution还必须把 target identity binder的已实例化 family与 caller live
identity declaration逐一比较，并用 caller identity/handler-contract table重查
instantiated public row中的每个 selector。Handler oracle的外层 declaration
binders就是 handler contract的 caller scope；同一 scope还递归约束 handled entry、
residual row与 handler application实例化后的 public row。

TR₀ 当前 wire只可为 associated EffectRow携带 `Lacks[e]`：generic hidden
`RowBinderV1`继承该 evidence，concrete explicit/default row必须证明它。Appendix A
为了稳定 recovery仍识别 associated Type constraint、associated Effect ability
constraint与 nonempty associated `TypeParams`，但这些 evidence/arity尚无 retained
wire表示，必须在 body/default检查前分别稳定拒绝
`associated-declaration-constraint-not-in-profile` 与
`associated-parameterization-not-in-profile`。TR₀ 也没有 `where` clause、递归
associated equality或 higher-ranked associated item；未来 profile不得由实现私自扩展。

### 4.5 Effect-header ability conformance 与独立 `impl`

**Profile baseline：只冻结 effect header conformance**

```moonbit
effect State[A] : Reader[A] + Writer[A] {}
```

这个 header 在 effect定义 package内产生 local ability witness。每个 ability
只可在同一 header出现一次；associated argument按 §4.4 exact检查；ability的
每个 operation经 substitution后必须与 effect自身或已继承 operation具有相同
参数/结果、secondary contract与 resumption mode。两个 ability若导出同名
operation，只有完整 substituted signature和 mode相同才可合并为同一 operation；
否则 conformance拒绝。Result visibility不能超过 effect与 ability两者中较窄的
一方，因此 header不能绕过 `pub` / `pub(open)` sealing。Duplicate ability、
signature/mode conflict或 visibility widening统一稳定报告
`effect-header-conformance-mismatch`。

Appendix A 仍为 ordinary trait实现保留 `impl` declaration，并能构造
ability-target `ImplDecl` CST；但 **独立 ability `impl` 不属于 TR₀**。Resolver
一旦确认 `impl` 左侧是 ability，必须稳定拒绝
`independent-ability-impl-not-in-profile`。因此 orphan/coherence、overlap、
specialization、operation adapter、associated binding uniqueness、mode
compatibility和跨 package visibility没有“先实现再决定”的隐含规则；它们必须在
新 profile一起冻结后，独立 ability `impl` 才能成为 accepted form。普通 trait
target仍可形成 `ImplDecl` CST，但不能产生 ability evidence；其 ordinary
non-effect语义属于 formalization明确声明的 out-of-semantic-scope fragment，不能
被用来绕过这条 effect-profile边界。

### 4.6 Row algebra 与 predicate status

**Profile baseline**

Row是 identity-aware finite set加 rigid row-variable summand。`|` 是唯一
surface union；normalization flatten union、删除已知重复 entry、按 stable
identity排序，并保留 rigid summand。`Anon(F)` 与 `Named(app,F)` 是不同 entry，
同 family不自动合并。

`Lacks[Elt]` 是唯一冻结的显式 row predicate。`..E : Lacks[X]` 给 constraint
environment加入 `Lacks(E,X)` evidence；literal extension `{X, ..E}` 必须从该
environment或已知 closed-row normalization证明同一 obligation，不能对未知 tail
静默去重。Union本身不制造 `Lacks` evidence；intersection、difference与 raw
family subtraction不属于本 profile。

Appendix A 为 profile evolution保留通用 `RowPredicate` CST，但显式
`Has[...]`、`All[...]`、`Only[...]` 在 TR₀ 一律由 RowWF稳定拒绝
`row-predicate-not-in-profile`。它们没有 builtin-name特判、solver、wire schema或
隐含 diagnostic contract；未来若加入，必须以新 profile同时定义上述四项。

## 5. Operation 调用

**工作形式**

不增加 `perform` 关键字。调用沿用普通方法和限定名外观：

```moonbit
let choice = Choice::choose([false, true])
let value = app.read()
```

- `Choice::choose(...)` 由类型环境解析到当前匿名 `Choice` handler；
- `app.read()` 明确选择 named capability `app`，并给 row 贡献 `{app}`；
- parser 只建立普通的 qualified call 或 method call；resolver/typechecker 决定它是否是 effect operation。

这样 parser 不必提前知道某个名称是不是 operation，LSP 的未解析语法树也保持完整。

## 6. Handler 与 clause

### 6.1 Handler expression

**工作形式**

Handler 是值。一个 handler expression 接受 handled computation 的 thunk：

```moonbit
let all_choices = handler Choice {
  ctl choose(_values) as k => {
    let left = k.resume(false)
    let right = k.resume(true)
    left + right
  }

  return(value) => value
}
```

`handler EffectType { ... }` 建立 handler value，而不是立即运行其后的代码。

### 6.2 Continuation binder

**已决定**

`once` 和 `ctl` clause 使用 `as k` 显式绑定 continuation：

```moonbit
once await(task) as k => {
  task.completion_source.park(k, under = task.owner)
}

ctl choose(values) as k => {
  values.map { value => k.resume(value) }
}
```

`abort` 与 `fun` clause 不允许 `as k`，因为它们不向用户暴露 continuation：

```moonbit
abort raise(error) => report(error)
fun ask() => current_environment
```

Continuation disposition 使用方法外观：

```moonbit
k.resume(value)
k.finalize()
```

这些不是可覆盖的普通方法。resolver 将它们识别为 `Resume` 与 `Finalize`，
因此不能通过定义同名 method 改变控制语义。`k.discontinue(error)` 不属于
`Cire-TR₀`：失败由显式 abort effect 表达，取消由 Owner/finalize 协议表达。

`source.park(k, under = owner)` 只在 operand 带 sealed completion-source
evidence 时降为 Core T-Park。它消耗当前 clause 的处置责任，产生
`Transfers(ParkContractV2)` 并终止当前 path；它不是返回 `Unit` 的普通容器
插入函数。source/port只传 operation result `A`，完整 resumption保存
`A -> B` answer transform；宿主 callback不能捕获 raw `Resume`。

### 6.3 Return 与 forwarding

**工作形式**

```moonbit
handler Reader[Int] {
  fun ask() => 42
  return(value) => value
}
```

- 省略 `return` 时，Surface elaboration 先合成
  `return(value) => value`；Core exactness checking 因而始终看到恰好一个
  return clause；
- 不属于当前 handled effect 的 operation 自动向外层 handler 转发；
- 当前 effect 中没有 clause 的 operation 默认产生穷尽性诊断；
- 显式 forwarding 的最终关键字和 clause 形式仍是开放问题。

第一版 handler 是 lexical deep handler。Shallow handler 不进入第一版语法。

## 7. 本质形式与语法糖

语法糖最终必须降到少量稳定的 Kernel HIR 形式；CST 和 Surface HIR 始终
保留用户原始写法，以供 formatter、诊断与 LSP 使用。`with` chain 可以先
结构化地 right-fold 成统一的 `ScopedApply`，但普通 wrapper、effect handler
和 generative application 的最终区分要等 resolver/type validation 提供
足够 evidence 后完成。

### 7.1 `with` 是 scoped computation application 的糖

**已决定**

`with` 不表示一个额外的核心控制构造。它把一组有序的 scoped computation
transformer 应用到 `in` 后面的计算。Effect handler 是最重要的 transformer，
但不是唯一来源；普通高阶函数只要接收一个 computation thunk，也可以使用同一
外观。

```moonbit
with all_choices
in {
  Choice::choose([false, true])
}
```

降为：

```moonbit
all_choices(fn() {
  Choice::choose([false, true])
})
```

匿名 entry 的类型形状可以概括为：

```text
body       : () -> A ! Ein
transformer(body) : B ! Eout
```

它不要求 `A = B` 或 `Ein = Eout`。Handler 可以消除 effect、加入 effect，
或通过 `return` clause 改变结果类型。

`with` 语法本身不授予 wrapper 任意复制 action 的权限。Wrapper 能否零次、
一次或多次调用 thunk，仍由 action function 的 usage/capture 类型与普通调用
规则决定；具名 `ScopedApply` 经 Kernel handler lowering 后还要满足
generativity 和 capability escape 检查。

Evaluation order 以展开后的普通调用为准：先求值当前最外层 transformer
expression，再构造包含其余 chain 的 thunk，然后调用它。内层 operand 不会
预先求值；只有外层 transformer 调用 action thunk 时才求值。外层若调用
action 多次，内层 operand 也会随之重新求值多次。

连续的 `with` entry 共用链末尾的一个 `in`：

```moonbit
with retry(3)
with transaction(db)
with trace("save")
in {
  save_order(order)
}
```

第一项是最外层，最后一项最靠近 computation：

```moonbit
(retry(3))(fn() {
  (transaction(db))(fn() {
    (trace("save"))(fn() {
      save_order(order)
    })
  })
})
```

因此 entry 顺序具有语义。`with retry(3)` 放在 `with transaction(db)` 外面，
表示每次 retry 可以建立新的 transaction；调换顺序则表示同一个 transaction
包住全部 retry。

这里 `retry(3)`、`transaction(db)` 和 `trace("save")` 都求值得到
transformer value；`with` 再把 action thunk 传给该值。它不会偷偷把 action
追加成原调用的普通最后一个 argument。

换行不参与 chain 语义；下面两种 token sequence 等价：

```moonbit
with retry(3) with transaction(db) in save_order(order)
```

```moonbit
with retry(3)
with transaction(db)
in save_order(order)
```

Formatter 对多 entry chain 默认每行放一个 `with`。

每层都写 `in` 仍然是合法的显式嵌套：

```moonbit
with retry(3) in
  with transaction(db) in
    save_order(order)
```

它由两个单 entry `WithChain` 构成，不是一个双 entry chain。规范写法对连续
组合只在末尾写一次 `in`；formatter 保留用户明确写出的嵌套边界和其上的
comment，不擅自把两棵 CST 合并。

Named capability binder 把生成式 action 参数写得更自然：

```moonbit
with read_42 as app
in {
  read_app(app)
}
```

降为：

```text
ScopedApply(
  transformer = read_42,
  binder = app,
  body = read_app(app),
)
```

若 transformer 类型证明它是 handler application，Kernel 再降为
`freshprompt p` + `handle[p,...]`，并用 `capref(ι)` 绑定 `app`。普通
transformer 降为高阶调用且没有 named capability binder。Handler 的类型为
`app` 创建 fresh generative identity；这里不能把 `app` 当作普通未受约束的
函数参数。

在同一个 chain 中，entry 创建的 identity 对后续 entry operand 和最终
computation 可见，但不在创建它的 operand 内可见：

```moonbit
with open_database(config) as db
with traced_database(db)
in {
  db.query("select * from users")
}
```

Inline handler：

```moonbit
with handler Read[Int] {
  fun read() => 42
} as app
in {
  read_app(app)
}
```

先保留为 scoped application：

```text
let generated_handler = handler Read[Int] {
  fun read() => 42
}
ScopedApply(generated_handler, binder = app, body = read_app(app))
```

临时绑定只用于说明求值顺序，编译器不必实际生成可观察的名称。

`with` operand 不要求是 `handler E { ... }` 产生的值。下面这些库式
computation wrapper 都可以使用同一语法：

```moonbit
with timeout(200.ms)
with trace("render")
with ui_scheduler
in render_page()
```

它们可以由 effect handler 实现，也可以只是普通高阶函数。类型检查只要求
每个 entry 能接收当前内层 computation，并产生下一层 computation；不同 entry
可以消除 effect、加入 effect 或改变结果类型。

`as name` 不随之泛化成普通 binding。它只允许用于能建立 fresh named
capability 的 handler application。普通运行时值继续使用普通 API 和 trailing
lambda：

```moonbit
Owner::scope { owner =>
  use(owner)
}
```

`with` 也不复用于 record update、trait/effect constraint、普通对象 receiver
scope、import 或 match clause。它始终只表示“用 scoped transformer 包住一段
computation”。

### 7.2 Trailing lambda

**已决定**

Cire 不做宏系统。UI DSL 依靠普通函数、labelled argument 和 Kotlin/Koka 风格 trailing lambda：

```moonbit
Column(gap=8) {
  Text("Profile")
  Button("Save") {
    save()
  }
}
```

降为：

```moonbit
Column(
  gap=8,
  fn() {
    Text("Profile")
    Button("Save", fn() {
      save()
    })
  },
)
```

带参数的 trailing lambda：

```moonbit
users.for_each { user =>
  UserRow(user)
}
```

降为：

```moonbit
users.for_each(fn(user) {
  UserRow(user)
})
```

规则是：

- 一个 trailing lambda 只能作为调用的最后一个实参；
- `callee(args) { ... }` 与 `callee { ... }` 都允许；
- `{ params => body }` 提供参数，`{ body }` 表示零参数 thunk；
- call 与 trailing block 之间的 whitespace、newline 或 comment 不打断附着，
  因而 formatter 可以安全换行；若要把 call 与后续独立 block 分开，必须写
  显式 `;`；
- 它不获得 AST、调用点源码或卫生名称访问权；
- 需要 lexical site 的第一方 API 必须使用编译器定义的稳定 site 机制，而不是偷偷实现宏展开。

`in` 已经明确分开 operand 区和 computation，因此 `with` operand 可以正常
包含 trailing lambda：

```moonbit
with make_handler(1) {
  configure()
}
in {
  run()
}
```

这里第一个 block 属于 `make_handler(1)`；`in` 后面的 block 才是被包裹的
computation。若 operand 自身是一个顶层 `with` expression，仍需用括号明确其
边界：

```moonbit
with (
  with configure_runtime
  in make_handler()
)
in {
  run()
}
```

### 7.3 不属于语法糖的构造

以下语义不能降为不受编译器理解的普通库调用：

- handler expression 与 operation dispatch；
- `k.resume`、`k.finalize`；
- fresh named capability identity；
- continuation usage/capture checking；
- sealed source park 的 terminal responsibility transfer；
- continuation-aware `defer`。

它们可以有普通调用的表面外观，但 HIR 必须保留专用节点和 source origin。

## 8. Named capability capture 与 Owner

### 8.1 Handler binding scope

**已决定**

Named capability 的有效范围由 handler application 的 binder 决定。第一方
Owner API 可以保持库式外观：

```moonbit
Owner::scope { owner =>
  let cell = owner.cell(0)
  ...
}
```

Surface HIR 先保留中立的 scoped application：

```text
ScopedApply {
  transformer
  optional_binder
  body
}
```

只有类型检查确认 transformer 是 handler 后，Kernel HIR 才产生
`FreshPrompt + Handle + CapRef`；普通 transformer继续使用 closure call。
编译器负责：

- 为 capability binder 生成 fresh、不可伪造的 identity；
- 推导闭包、handler 与 continuation 的 capture；
- 检查 return、closure、aggregate 与 storage boundary 上的 escape；
- 检查 continuation 被 sealed source park 后的唯一处置责任；
- 把静态 capability identity 与运行时 Owner/generation 区分开。

源码只使用 `{app}`。Capture 结果保存在 HIR、接口摘要和诊断中。

### 8.2 Capture safety gate

**Profile baseline 的实现原则**

Capture safety 要么作为一组一致的核心规则实现，要么整组延后；不能先接受程序，再只检查少数 UI 或 `once` 特例。

在正式启用前，至少需要共同定义：

- capture inference 与传递闭包；
- capability binder escape；
- `once` usage 在 closure、ADT 与 existential 中的传播；
- multi-shot replayability；
- mutable authority 的 replay 语义；
- handler mode weakening 对 capture safety 的影响；
- Owner park/CAS 与 finalization 的唯一责任。

如果这些规则尚未完成，编译器应通过 feature gate 或明确的“尚未支持”诊断拒绝依赖它们的程序，而不是运行一个静默不安全的宽松模式。

### 8.3 PackedNext 的 sealed scope

**已决定**

TR₀ 不增加一般 existential 或 rank-2 类型语法。跨越 generative FrameClock
lifetime 使用 shared `PackedNext[A]` 与三个 sealed first-party origin：

```cire
let packed = @temporal::pack_next(under=owner) { frame =>
  delay[frame] { 42 }
}

let opened = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

@temporal::dispose(packed)
```

`try_with_packed_next` 的 result是 `Option[B]`：Closing/Closed acquisition返回
`None`；成功 body的 Returns映射为 `Some`；Aborts/Transfers保持 terminal tag，
但必须先证明 private frame/Next/Later/lease没有通过任何 outward evidence逃逸，
再 exactly-once release。Handle可复制，alias共享
`Open(n)|Closing(n)|Closed` cell；dispose幂等、NoSuspend、非 Pure；
`Open(0)` 立即唯一 close，有 active lease时只进入 Closing而不等待归零。
三段 block是 contextual HIR，不是用户可声明的普通 callback
contract；同名用户函数无 privileged lowering。

## 9. 不采用宏系统

**已决定**

Cire 不设计 token macro、AST macro 或 typed hygienic macro。以下都不成为宏：

- UI component；
- `state`、`resource`、`boundary`；
- `with`；
- trailing lambda；
- stable lexical site。

UI API 由普通声明和函数组成：

```moonbit
def user_pane(user : Source[User]) -> View ! {Observe} {
  Column {
    Text(user.read().name)
    Button("Refresh") {
      refresh(user)
    }
  }
}
```

这会牺牲任意语法扩展能力，但换来：

- 单一 parser 与单一语义树；
- 不需要宏展开前后的双重 name resolution；
- 诊断位置与 source edit 更稳定；
- incremental compiler 与 LSP 不需要执行用户宏；
- UI DSL 仍可通过 trailing lambda 获得嵌套结构。

## 10. Canonical grammar

本文 Appendix A 的完整表面语法统一规定：

- Unicode token、nested comment、关键字与 trivia；
- declaration、普通/effect 形参、type 与 kinded `RowExpr`；
- function/operation secondary effect、pattern 与 handler clause；
- 固定 operator precedence、call、label、postfix 和 trailing lambda；
- layout-independent block item 与 final-result 规则；
- brace disambiguation、`with` terminator flavor 和 temporal surface。

其中几个容易被实现偶然行为掩盖的决定是：

- row literal 最多一个 open tail，`..S::Extra` 是合法 projection，多 row 用
  `! (E1 | E2)`；
- labelled argument 必须在 positional argument 后，且一律按源码顺序求值；
- argument 起点的 `name=` / `name~` 先识别为 label，不会被 assignment
  expression吞掉；positional assignment 必须写成 `(slot = value)`；
- anonymous `fn` 使用可推导/可标注的 lambda parameter grammar，不复用
  具名声明的 typed `ParamList`；
- `factory() { ... }` 给当前 call 追加 lambda，不调用返回值；
- 换行只是 trivia；block 由 maximal expression boundary 分项，最后一个未加
  `;` 的表达式才是结果；
- handler clause 使用 `PatternList`，不是 declaration `ParamList`；
- operation declaration 可以携带 closed secondary effect 与 temporal
  contract；`TR₀` 不接受 open secondary row tail。

## 11. Explicit profile-boundary registry

这一节是 `Cire-TR₀/2026-08-01` 的唯一 surface open-boundary registry。它合并
了旧 surface document 与旧 standalone grammar 的两份清单。下列项目没有
“implementation-defined”含义；除明确写成当前 profile baseline者外，parser、
resolver与 typechecker都不得接受候选拼写或自行选择语义。

| Boundary | TR₀ status |
|---|---|
| `ability` / `cap` keyword choice | 本 profile 的 canonical spelling；只有新 profile 可以改名，当前实现不得接受 alias。 |
| `val` as zero-parameter `fun` sugar | Excluded；grammar 没有 `VAL` token/production。 |
| explicit forwarding / masking | Surface spelling open；只有 Kernel `forward` 与现有 automatic forwarding contract，用户语法不得猜测。 |
| public completion-source/port API | Open；TR₀ 只暴露 sealed `park` / PackedNext路径与 formalization中的 trusted constructors，不提供可自行构造的 library surface。 |
| multi-shot local mutation | 没有 snapshot/clone/share 的额外语义；不能满足既有 replayability/capture premise 的 mutable local 必须拒绝。任何更宽语义需要新 profile。 |
| general one-call/many-call function marker | Excluded；first-class closure按 many-call检查，one-call只存在于 sealed completion/resumption machinery。 |
| stable lexical-site identity across edits | Artifact内使用 alpha-normalized lexical slot；跨编辑、重构或 incremental rebuild 的持久 identity仍开放，不能由路径/offset偶然定义。 |
| typed `discontinue` | Excluded；`k.discontinue(e)` 以既有 stable reject处理。新 profile必须一起定义 payload、world、cleanup与terminal flow。 |
| shallow handlers | Excluded；grammar与elaboration只有当前 deep handler。 |
| user-defined operators | Excluded；Appendix A 的 precedence/operator set封闭。 |
| wildcard imports | Excluded；package-qualified resolution不允许文件内 wildcard改变环境。 |
| explicit `Has` / `All` / `Only` row predicates | Grammar-reserved but profile-rejected，精确规则与 diagnostic见 §§4.6/A.3。 |
| independent ability `impl` | Grammar-reserved but profile-rejected；effect-header conformance是唯一冻结形态，见 §4.5。 |

这些 boundary 中的“open”只表示未来设计空间，不表示当前程序可依靠某种行为。
候选若要变成 accepted surface，必须改变 profile id，并同时补齐 grammar、
elaboration、Core rule、wire/schema（若可序列化）、stable diagnostics 与 conformance
case。实现不能因为 parser能够恢复出 CST 就把它当作当前语言。

## Appendix A — Cire-TR₀ complete grammar


> **Profile:** `Cire-TR₀/2026-08-01`
>
> 本文是实现无关的 canonical grammar。未来 parser 必须实现这里定义的 token
> language、优先级、附着和恢复边界；parser 的既有行为不能修改本文含义。
> `def` 只声明具名函数/方法；`fn` 只构造匿名函数值或写显式泛型函数值类型；
> `fun` 只表示 effect 的唯一尾恢复 mode。

本文使用 PEG 记号：`/` 为有序选择，`*`、`+`、`?` 为重复，`&` / `!` 为
正/负 lookahead，`CUT` 表示识别到判别 token 后不回退。大写名字是 token，
CamelCase 名字是 grammar rule。语义验证写在 grammar 后，不伪装成 parsing。

### A.1 词法

源码是 Unicode text。位置使用 UTF-16 code-unit 的半开区间；这只影响
artifact/LSP，不改变 token language。

```peg
SourceFile     <- Trivia TopLevelItem* EOF
Trivia         <- (Whitespace / LineComment / BlockComment)*
Whitespace     <- UnicodeWhiteSpace+
LineComment    <- "//" (!LineTerminator .)* LineTerminator?
BlockComment   <- "/*" (BlockComment / !"*/" .)* "*/"

Identifier     <- XID_Start XID_Continue*
                / "_" XID_Continue+
LowerIdent     <- Identifier whose first cased scalar is lowercase
UpperIdent     <- Identifier whose first cased scalar is uppercase
DiscardIdent   <- "_"

DecDigits      <- DecDigit ("_"? DecDigit)*
HexDigits      <- HexDigit ("_"? HexDigit)*
OctDigits      <- OctDigit ("_"? OctDigit)*
BinDigits      <- BinDigit ("_"? BinDigit)*

IntLiteral     <- "0x" HexDigits / "0o" OctDigits / "0b" BinDigits / DecDigits
FloatLiteral   <- DecDigits "." DecDigits Exponent?
                / DecDigits Exponent
Exponent       <- ("e" / "E") ("+" / "-")? DecDigits
CharLiteral    <- "'" CharElement "'"
StringLiteral  <- '"' StringElement* '"'
CharElement    <- Escape / !("'" / LineTerminator) .
StringElement  <- Escape / !('"' / LineTerminator) .
Escape         <- "\\" ("n" / "r" / "t" / "0" / "\\" / "'" / '"'
                 / "u{" HexDigit+ "}")
BoolLiteral    <- TRUE / FALSE

LineTerminator <- "\r\n" / "\n" / "\r" / "\u{2028}" / "\u{2029}"
DecDigit       <- [0-9]
HexDigit       <- [0-9A-Fa-f]
OctDigit       <- [0-7]
BinDigit       <- [01]
```

关键字不能作为普通 identifier：

```text
ability abort as break cap const continue ctl def defer effect else enum false
effects fn for fun handler if impl in let loop match may_suspend mut next pub
resumes return struct trait true type while with once open
```

Keyword token采用 Unicode identifier boundary；下列名字是后续 grammar 使用的
significant token kind：

```peg
ABILITY     <- "ability" !XID_Continue
ABORT       <- "abort" !XID_Continue
AS          <- "as" !XID_Continue
BREAK       <- "break" !XID_Continue
CAP         <- "cap" !XID_Continue
CONST       <- "const" !XID_Continue
CONTINUE    <- "continue" !XID_Continue
CTL         <- "ctl" !XID_Continue
DEF         <- "def" !XID_Continue
DEFER       <- "defer" !XID_Continue
EFFECT      <- "effect" !XID_Continue
EFFECTS     <- "effects" !XID_Continue
ELSE        <- "else" !XID_Continue
ENUM        <- "enum" !XID_Continue
FALSE       <- "false" !XID_Continue
FN          <- "fn" !XID_Continue
FOR         <- "for" !XID_Continue
FUN         <- "fun" !XID_Continue
HANDLER     <- "handler" !XID_Continue
IF          <- "if" !XID_Continue
IMPL        <- "impl" !XID_Continue
IN          <- "in" !XID_Continue
LET         <- "let" !XID_Continue
LOOP        <- "loop" !XID_Continue
MATCH       <- "match" !XID_Continue
MAY_SUSPEND <- "may_suspend" !XID_Continue
MUT         <- "mut" !XID_Continue
NEXT        <- "next" !XID_Continue
ONCE        <- "once" !XID_Continue
OPEN        <- "open" !XID_Continue
PUB         <- "pub" !XID_Continue
RESUMES     <- "resumes" !XID_Continue
RETURN      <- "return" !XID_Continue
STRUCT      <- "struct" !XID_Continue
TRAIT       <- "trait" !XID_Continue
TRUE        <- "true" !XID_Continue
TYPE        <- "type" !XID_Continue
WHILE       <- "while" !XID_Continue
WITH        <- "with" !XID_Continue

ARROW       <- "->"
FAT_ARROW   <- "=>"
COLONCOLON  <- "::"
DOTDOT      <- ".."
EQEQ        <- "=="
NEQ         <- "!="
LE          <- "<="
GE          <- ">="
ANDAND      <- "&&"
OROR        <- "||"

AT          <- "@"
BANG        <- "!" !"="
COLON       <- ":" !":"
COMMA       <- ","
DOT         <- "." !"."
EQUAL       <- "=" !("=" / ">")
LT          <- "<" !"="
GT          <- ">" !"="
LBRACE      <- "{"
RBRACE      <- "}"
LBRACKET    <- "["
RBRACKET    <- "]"
LPAREN      <- "("
RPAREN      <- ")"
MINUS       <- "-" !">"
PERCENT     <- "%"
PIPE        <- "|" !"|"
PLUS        <- "+"
SEMICOLON   <- ";"
SLASH       <- "/"
STAR        <- "*"
TILDE       <- "~"
UNDERSCORE  <- "_" !XID_Continue
EOF         <- !.
```

Lexer 在同一 offset 先消费 `Trivia`，再按最长匹配产生一个 significant token；
等长时 keyword/literal token优先于 `Identifier`。`CUT` 是 parser
meta-operation，不是 source token。

`delay`、`advance` 和 `Next` 是 sealed prelude 名称，不是无条件保留的关键字：
只有完整 temporal shape 或 resolver evidence 才赋予 intrinsic 含义。

换行属于 trivia，不触发 semicolon insertion，也不改变 trailing lambda 或
`with` chain 的附着。

### A.2 名称、可见性与声明

```peg
Name              <- LowerIdent / UpperIdent
PackagePath       <- AT Name (DOT Name)*
QualifiedName     <- PackagePath COLONCOLON Name
                     (COLONCOLON Name)*
                   / Name (COLONCOLON Name)*
TypeName          <- (PackagePath COLONCOLON)?
                     UpperIdent (COLONCOLON UpperIdent)*
ValueName         <- QualifiedName
Visibility        <- PUB (LPAREN OPEN RPAREN)?

TopLevelItem      <- Visibility? Declaration
Declaration       <- FunctionDecl
                   / StructDecl
                   / EnumDecl
                   / TraitDecl
                   / AbilityDecl
                   / EffectDecl
                   / ImplDecl
                   / TypeAliasDecl
                   / ConstDecl

TypeHead          <- UpperIdent TypeParams?
TypeAliasDecl     <- TYPE TypeHead EQUAL Type SEMICOLON?
ConstDecl         <- CONST LowerIdent COLON Type EQUAL Expr SEMICOLON?

StructDecl        <- STRUCT TypeHead SuperTraits?
                     LBRACE FieldDecl* RBRACE
FieldDecl         <- Visibility? LowerIdent COLON Type
                     (EQUAL Expr)? (COMMA / SEMICOLON)?

EnumDecl          <- ENUM TypeHead SuperTraits?
                     LBRACE VariantDecl* RBRACE
VariantDecl       <- UpperIdent VariantPayload?
                     (COMMA / SEMICOLON)?
VariantPayload    <- LPAREN TypeList? RPAREN
                   / LBRACE NamedTypeList? RBRACE

TraitDecl         <- TRAIT TypeHead SuperTraits?
                     LBRACE TraitItem* RBRACE
TraitItem         <- FunctionSignature
                   / AssociatedTypeDecl
AssociatedTypeDecl <- TYPE UpperIdent TypeParams?
                      (COLON TypeConstraintList)?
                      (EQUAL Type)? SEMICOLON?

AbilityDecl       <- ABILITY TypeHead SuperAbilities?
                     LBRACE AbilityItem* RBRACE
AbilityItem       <- OperationDecl
                   / AssociatedTypeDecl
                   / AssociatedEffectDecl
                   / AssociatedRowDecl
AssociatedEffectDecl <- EFFECT UpperIdent TypeParams?
                        (COLON AbilityConstraintList)?
                        (EQUAL Type)? SEMICOLON?
AssociatedRowDecl <- EFFECTS UpperIdent
                     (COLON RowConstraintList)?
                     (EQUAL RowExpr)? SEMICOLON?

EffectDecl        <- EFFECT TypeHead EffectConformance?
                     LBRACE OperationDecl* RBRACE
EffectConformance <- COLON AbilityRef (PLUS AbilityRef)*

ImplDecl          <- IMPL GenericClauses? Type FOR Type
                     LBRACE ImplItem* RBRACE
ImplItem          <- FunctionDecl
                   / AssociatedTypeBinding
                   / AssociatedEffectBinding
                   / AssociatedRowBinding
AssociatedTypeBinding   <- TYPE UpperIdent EQUAL Type SEMICOLON?
AssociatedEffectBinding <- EFFECT UpperIdent EQUAL Type SEMICOLON?
AssociatedRowBinding    <- EFFECTS UpperIdent EQUAL RowExpr SEMICOLON?

SuperTraits       <- COLON Type (PLUS Type)*
SuperAbilities    <- COLON AbilityRef (PLUS AbilityRef)*
AbilityRef        <- Type
```

Package identity and dependency selection belong to the package manifest. 源文件通过
`@package::name` 和 `Type::member` 使用 package-qualified name；本 profile
不增加会在文件内改变解析环境的 wildcard import。

`ImplDecl` 是 ordinary trait与 ability target共享的 lossless CST shape。
Resolver若把左侧 `Type` 解析为 ability，TR₀ 必须在进入 body typechecking前拒绝
`independent-ability-impl-not-in-profile`；只有 §4.5 的 effect-header
`EffectConformance` 产生 ability evidence。Parser recovery或 ordinary trait
target不能改变这个 kind-directed profile boundary。

### A.3 形参、实参与约束

表面的 `[...]` / `![...]` 是**形参绑定列表**，不是量词语法：

```peg
GenericClauses       <- TypeParams EffectParams? / EffectParams
TypeParams           <- LBRACKET TypeParam
                        (COMMA TypeParam)* COMMA? RBRACKET
TypeParam            <- UpperIdent (COLON TypeConstraintList)?
TypeConstraintList   <- Type (PLUS Type)*

EffectParams         <- BANG LBRACKET EffectParam
                        (COMMA EffectParam)* COMMA? RBRACKET
EffectParam          <- RowParam / EffectConstructorParam / EffectAtomParam
RowParam             <- DOTDOT UpperIdent (COLON RowConstraintList)?
EffectConstructorParam
                     <- UpperIdent BinderHoles
                        (COLON AbilityConstraintList)?
EffectAtomParam      <- UpperIdent (COLON AbilityConstraintList)?
BinderHoles          <- LBRACKET UNDERSCORE
                        (COMMA UNDERSCORE)* RBRACKET
AbilityConstraintList <- AbilityRef (PLUS AbilityRef)*
RowConstraintList    <- RowPredicate (PLUS RowPredicate)*
RowPredicate         <- UpperIdent LBRACKET PredicateArgList? RBRACKET
PredicateArgList     <- PredicateArg (COMMA PredicateArg)* COMMA?
PredicateArg         <- Type / RowExpr

TypeArgs             <- LBRACKET TypeArg
                        (COMMA TypeArg)* COMMA? RBRACKET
TypeArg              <- AssociatedArgument / Type / LowerIdent
AssociatedArgument   <- UpperIdent EQUAL AssociatedArgumentValue
AssociatedArgumentValue <- Type / RowExpr
EffectArgs           <- BANG LBRACKET EffectArg
                        (COMMA EffectArg)* COMMA? RBRACKET
EffectArg            <- RowExpr / Type
```

`F`、`F[_]`、`..E` 分别绑定 `Effect`、effect constructor、`EffectRow`；
这由 binder shape 唯一决定。`app : cap F` 是 term binder，不进入 generic
list。`AssociatedArgument` 的 `UpperIdent =` lookahead先于 positional `Type`；
resolver按 ability declaration把右侧重分类到 `Type`、`Effect` 或
`EffectRow`，并按 §4.4区分 partial generic constraint与 total concrete header；
两者都拒绝 non-ability target、unknown、duplicate与 kind mismatch，只有 concrete
header拒绝 missing-without-default。Associated Type/Effect declaration constraint与
任意 nonempty associated `TypeParams` 虽有 recovery CST，分别在 Kind阶段走本
profile的 registered stable reject。

`RowPredicate` 的通用 CST只为明确 profile boundary而保留。本 profile在 RowWF
只接受名称 `Lacks`、恰好一个可解析 row entry argument；`Has`、`All`、`Only`
以及其它名称统一拒绝 `row-predicate-not-in-profile`，不能由库中同名类型绕过。

### A.4 类型与 effect-row 表达式

```peg
Type                <- GenericFunctionType / ArrowType
GenericFunctionType <- FN GenericClauses ParamTypeList
                       ARROW Type EffectAnnotation?
ArrowType           <- TypePrimary
                       (ARROW Type EffectAnnotation?)?
TypePrimary         <- CapabilityType
                     / TupleOrGroupedType
                     / TypeReference
CapabilityType      <- CAP CUT TypePrimary
TupleOrGroupedType  <- LPAREN TypeList? RPAREN
TypeList            <- Type (COMMA Type)* COMMA?
NamedTypeList       <- LowerIdent COLON Type
                       (COMMA LowerIdent COLON Type)* COMMA?
TypeReference       <- TypeName TypeArgs?

ParamTypeList       <- LPAREN TypeList? RPAREN
EffectAnnotation    <- BANG RowExpr

RowExpr             <- RowUnion
RowUnion            <- RowPrimary (PIPE RowPrimary)*
RowPrimary          <- RowLiteral / RowReference
                     / LPAREN RowExpr RPAREN
RowReference        <- QualifiedName TypeArgs?
RowLiteral          <- LBRACE
                       (InvalidRowLiteralMultipleTails / RowLiteralBody)?
                       RBRACE
RowLiteralBody      <- RowEntry (COMMA RowEntry)*
                       (COMMA RowTail)? COMMA?
                     / RowTail COMMA?
RowEntry            <- LowerIdent / TypeReference
RowTail             <- DOTDOT RowReference
InvalidRowLiteralMultipleTails <- (RowEntry COMMA)* RowTail COMMA
                       DOTDOT CUT RowReference
                       (COMMA RowTail)* COMMA?
```

规则：

- `! E` 表示精确 row variable；`! {F, app, ..E}` 表示 literal extension；
- 一个 literal 最多有一个 tail，且 tail 必须最后出现；
- `..S::Extra` 是合法 associated-row projection；
- 多个未知 row 用 `! (E1 | E2)`，不写 `{..E1, ..E2}`；
- `|` 在 `RowExpr` 中左结合，优先级低于 literal/path；没有 surface row
  intersection 或 subtraction；
- normalization 展开已知 projection/union、去除重复 entry、按稳定 identity
  排序，并保留所有 rigid row-variable union summand；“一个 tail”只约束
  单个 literal 的 source spelling；
- `{F, ..E}` 同时产生 `Lacks(E,F)`；若不能证明 tail 不含同 identity entry，
  extension 不能通过。TR₀ 只有 extension 与 union，没有 subtraction；
- `{F}` 与 `{app}` 分别解析到 anonymous family 与 named identity，不能互换；
- `Read[app]` 不是源语法。诊断可以用它解释 `{app}` 的 family。

`InvalidRowLiteralMultipleTails` 只构造 committed recovery CST。第二个
`DOTDOT` 后的 `CUT` 保证 `{..E1, ..E2}` 不退化成不稳定 parser error；
RowWF 必须以版本化 `row-literal-has-multiple-tails` 拒绝该 node并建议
`E1 | E2`。它不把多个 literal tail接受进语言。

`Next[frame,A]` 使用普通 `TypeReference` / `TypeArgs` CST；kind checking 将
`frame` 解释为受限 clock identity。它不会把所有 lower identifier 都提升成
一般 dependent type。

### A.5 函数、operation 与参数

```peg
FunctionDecl       <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation? Block
FunctionSignature  <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation? SEMICOLON?
FunctionName       <- LowerIdent
                    / FunctionOwner COLONCOLON LowerIdent
FunctionOwner      <- (PackagePath COLONCOLON)?
                      UpperIdent (COLONCOLON UpperIdent)* TypeArgs?

ParamList          <- LPAREN Parameter
                      (COMMA Parameter)* COMMA? RPAREN
                    / LPAREN RPAREN
Parameter          <- LabelledParameter / PositionalParameter
PositionalParameter <- Pattern COLON Type
LabelledParameter  <- LowerIdent TILDE COLON Type
                      (EQUAL Expr)?

Mode               <- ABORT / FUN / ONCE / CTL
OperationDecl      <- Mode GenericClauses? LowerIdent ParamList
                      ARROW Type OperationSecondaryAnnotation?
                      OperationContractItem* SEMICOLON?
OperationSecondaryAnnotation <- BANG CUT
                      (ClosedRowLiteral / InvalidOperationSecondaryRow)
ClosedRowLiteral   <- LBRACE (RowEntry (COMMA RowEntry)* COMMA?)? RBRACE
InvalidOperationSecondaryRow <- RowExpr
OperationContractItem <- RESUMES NEXT / MAY_SUSPEND
```

Operation 的 secondary effect annotation 是 clause/handler 聚合的一部分，不能
因为 family row 最终被消除而丢失。对
`once read() -> A ! {Log}`，`{Log}` 就是 `SecondaryRow`；调用 row 是
argument rows、operation dispatch entry 与该 annotation 的 union。Checker
另存带 call-site/prompt route 的 attributed demand `Δ`，public row只是其
擦除。

`TR₀` 要求 operation 的 secondary row **closed**：允许 `! {}`、
`! {Audit, Log}`，拒绝 `! E`、`! {Audit, ..E}` 与任何包含 rigid row
variable的 union。一般 function/result effect annotation仍使用完整
`RowExpr`；限制只作用于 `OperationSecondaryAnnotation`。这样 interface中的
每个 secondary demand都能序列化成 finite `SecondarySiteV1`，不会把 open
tail伪装成已经枚举完的 site set。
`CUT` 在 `!` 后固定 operation-secondary context；fallback
`InvalidOperationSecondaryRow` 只构造 recovery CST node，WF 必须以版本化
`operation-secondary-row-must-be-closed` 拒绝。它不把 open row接受进语言，
但保证 bare `! E` 与 `! {Audit, ..E}` 不会提前退化成不稳定 parser error。

`def` 是具名、可递归 declaration/generalization boundary；`fn` 只在
`LambdaExpr` 和 `GenericFunctionType` 中出现；`fun` 仅是 operation mode。
`def` 在 expression 或 type 位置必须拒绝。

Core 一律是一元函数。`def f(p1, ..., pn)` elaboration为一个接收 immutable
n-tuple 的递归 Core binding；call 仍先按源码顺序求值 callee 和各 argument，
再按 resolved parameter/label 顺序组装 tuple。它不等于 currying，也不提供
隐式 partial application；需要高阶返回值时必须显式返回 `fn`。

### A.6 Pattern

```peg
Pattern             <- OrPattern
OrPattern           <- AliasPattern (PIPE AliasPattern)*
AliasPattern        <- AtomicPattern (AS LowerIdent)?
AtomicPattern       <- UNDERSCORE
                     / LowerIdent
                     / LiteralPattern
                     / ConstructorPattern
                     / TuplePattern
                     / RecordPattern
                     / ArrayPattern

LiteralPattern      <- IntLiteral / FloatLiteral / CharLiteral
                     / StringLiteral / BoolLiteral
ConstructorPattern  <- TypeName
                     / TypeName LPAREN PatternList? RPAREN
                     / TypeName RecordPattern
TuplePattern        <- LPAREN PatternList? RPAREN
PatternList         <- Pattern (COMMA Pattern)* COMMA?
RecordPattern       <- LBRACE RecordPatternFields? RBRACE
RecordPatternFields <- RecordPatternField
                       (COMMA RecordPatternField)*
                       (COMMA DOTDOT)? COMMA?
                     / DOTDOT COMMA?
RecordPatternField  <- LowerIdent (COLON Pattern)?
ArrayPattern        <- LBRACKET ArrayPatternItems? RBRACKET
ArrayPatternItems   <- Pattern (COMMA Pattern)*
                       (COMMA DOTDOT LowerIdent)? COMMA?
                     / DOTDOT LowerIdent COMMA?
```

Or-pattern 两侧必须绑定相同名字和兼容类型；同一 pattern 不得重复绑定。
Guard 只属于 `match` arm，不是 pattern 的一部分。

### A.7 表达式与优先级

表达式采用固定 precedence ladder。数字越小结合越晚：

| 层 | 构造 | 结合 |
|---:|---|---|
| 1 | assignment `=` | 右结合 |
| 2 | `||` | 左结合、短路 |
| 3 | `&&` | 左结合、短路 |
| 4 | `== !=` | 不可串联 |
| 5 | `< <= > >=` | 不可串联 |
| 6 | `+ -` | 左结合 |
| 7 | `* / %` | 左结合 |
| 8 | prefix `! -` | 右结合 |
| 9 | call/method/index/field/trailing lambda | 左结合 |

本 profile 不允许用户声明新 operator。

```peg
Expr             <- AssignExpr
AssignExpr       <- LogicOrExpr (EQUAL AssignExpr)?
LogicOrExpr      <- LogicAndExpr (OROR LogicAndExpr)*
LogicAndExpr     <- EqualityExpr (ANDAND EqualityExpr)*
EqualityExpr     <- CompareExpr ((EQEQ / NEQ) CompareExpr)?
CompareExpr      <- AddExpr ((LT / LE / GT / GE) AddExpr)?
AddExpr          <- MulExpr ((PLUS / MINUS) MulExpr)*
MulExpr          <- PrefixExpr ((STAR / SLASH / PERCENT) PrefixExpr)*
PrefixExpr       <- (BANG / MINUS) PrefixExpr / PostfixExpr

PostfixExpr      <- PrimaryExpr PostfixPart*
PostfixPart      <- GenericCallSuffix
                  / CallSuffix
                  / BareTrailingCall
                  / MethodSuffix
                  / FieldSuffix
                  / IndexSuffix
GenericCallSuffix <- TypeArgs? EffectArgs ArgList TrailingLambda?
                   / TypeArgs EffectArgs? ArgList TrailingLambda?
CallSuffix       <- ArgList TrailingLambda?
BareTrailingCall <- TrailingLambda
MethodSuffix     <- DOT LowerIdent
                   (TypeArgs? EffectArgs? ArgList TrailingLambda?
                   / TrailingLambda)
FieldSuffix      <- DOT LowerIdent
IndexSuffix      <- LBRACKET Expr RBRACKET

PrimaryExpr      <- WithExpr
                  / HandlerExpr
                  / IfExpr
                  / MatchExpr
                  / LoopExpr
                  / LambdaExpr
                  / DelayExpr
                  / ReturnExpr
                  / BreakExpr
                  / ContinueExpr
                  / RecordExpr
                  / ArrayExpr
                  / TupleOrGroupedExpr
                  / Block
                  / Literal
                  / ValueName

Literal          <- IntLiteral / FloatLiteral / CharLiteral
                  / StringLiteral / BoolLiteral
TupleOrGroupedExpr <- LPAREN ArgumentExprList? RPAREN
ArgumentExprList <- Expr (COMMA Expr)* COMMA?
ArrayExpr        <- LBRACKET ArgumentExprList? RBRACKET

RecordExpr       <- TypeName LBRACE
                    (RecordField (COMMA RecordField)* COMMA?)? RBRACE
                  / LBRACE &RecordFieldStart
                    RecordField (COMMA RecordField)* COMMA? RBRACE
RecordFieldStart <- LowerIdent (COLON / COMMA / RBRACE) / DOTDOT
RecordField      <- LowerIdent (COLON Expr)?
                  / DOTDOT Expr

LambdaExpr       <- FN GenericClauses? LambdaParamList Block
LambdaParamList  <- LPAREN LambdaParameter
                    (COMMA LambdaParameter)* COMMA? RPAREN
                  / LPAREN RPAREN
LambdaParameter  <- Pattern (COLON Type)?
LambdaPatternList <- LambdaParameter
                     (COMMA LambdaParameter)* COMMA?

IfExpr           <- IF Expr Block (ELSE (IfExpr / Block))?
MatchExpr        <- MATCH Expr LBRACE MatchArm* RBRACE
MatchArm         <- Pattern (IF Expr)? FAT_ARROW Expr
                    (COMMA / SEMICOLON)?
LoopExpr         <- WHILE Expr Block
                  / FOR Pattern IN Expr Block
                  / LOOP Block
ReturnExpr       <- RETURN Expr?
BreakExpr        <- BREAK Expr?
ContinueExpr     <- CONTINUE
```

Assignment 左侧必须是 mutable place；这一点在 syntax validation/type checking
完成。`return`、`break` 的目标由 control-flow resolver 确定。

#### A.7.1 调用参数

```peg
ArgList          <- LPAREN CallArguments? RPAREN
CallArguments    <- PositionalArgs (COMMA LabelledArgs)? COMMA?
                  / LabelledArgs COMMA?
PositionalArgs   <- PositionalArg (COMMA PositionalArg)*
PositionalArg    <- !LabelledArgStart Expr
LabelledArgs     <- LabelledArg (COMMA LabelledArg)*
LabelledArgStart <- LowerIdent (EQUAL / TILDE)
LabelledArg      <- LowerIdent EQUAL Expr
                  / LowerIdent TILDE
```

- positional argument 必须在 labelled argument 之前；
- label 在一次调用中必须唯一，resolve 后 unknown label 是错误；
- `name~` 展开为 `name=name`；
- callee、显式 argument 按源码从左到右求值，不能按 parameter 顺序重排；
- 缺省 labelled parameter 在进入 callee 后按声明顺序求值；
- generic argument 只属于后面紧邻的 call；index suffix 不会被猜成泛型调用。
- `LowerIdent =` / `LowerIdent~` 在 argument 起点先判为 label；若确实要把赋值
  作为 positional argument，必须加括号，例如 `f((slot = value))`。

因此 corpus 中 `panel(make_title(), enabled=is_enabled(), gap=measure_gap())`
产生一个 positional 与两个 labelled argument；`connect("host",
secure=true, 443)` 在进入 labels 后遇到 positional token，必须拒绝。这里不
依赖 PEG choice偶然先把 `enabled=is_enabled()` 吞成 assignment。

同理，`fn(value) { ... }` 由 `LambdaParamList` 接受并推导 parameter type；
`fn(value : Int) { ... }` 也合法。具名 `def` 仍使用必须标注类型的
`ParamList`。

#### A.7.2 Trailing lambda

```peg
TrailingLambda   <- LBRACE LambdaHead? BlockElement* RBRACE
LambdaHead       <- LambdaPatternList FAT_ARROW
```

`callee(args) { ... }` 与 `callee { ... }` 都把 lambda 作为**该 call** 的最后一个
argument。换行和 comment 不脱附；要在 call 后开始独立 block，必须写 `;`。

`factory() { body }` 给 `factory` 这次调用追加 lambda，不调用 `factory()` 的
返回值。调用返回的 callable 必须显式写 `factory()(fn() { body })`。

### A.8 Block 与 brace 判定

```peg
Block            <- LBRACE BlockElement* RBRACE
BlockElement     <- LetItem / DeferItem / Expr SEMICOLON?
LetItem          <- LET MUT? Pattern (COLON Type)? EQUAL Expr SEMICOLON?
DeferItem        <- DEFER Expr SEMICOLON?
```

Parser 对每个 `Expr` 使用上节的 maximal expression parse；换行不是分隔符。
当下一个 token 不能继续当前表达式、却能开始新的 `BlockElement` 时，新 item
开始。因此 UI 风格的连续 call 不依赖 layout：

```cire
{
  Text("A")
  Button("B") { save() }
}
```

Block 从左到右求值。最后一个没有 `;` 的 expression 是 block result；其余
expression 的值被丢弃。若最后一个 element 是 `let`、`defer` 或带 `;` 的
expression，block result 是 `Unit`。

`defer` 的 grammar 与 LIFO intent 已固定；它在 normal/abort/resume/
finalize/park/Owner-close 路径上的 reduction calculus仍是 formal proof
obligation。未来 runtime行为不能反向定义这部分语义。

这只是普通 block 语义。UI siblings 必须由第一方 builder/effect protocol
收集，不能由 parser 把“多个表达式”魔法地变成 children。

Brace 的判定顺序：

1. handler、match、declaration 等 introducer 后按对应专用 body；
2. call 后的 `{` 按 trailing lambda；
3. `{ patterns => ... }` 按 lambda；
4. `Type { ... }`、`{ field: ... }` / `{ field, ... }` / `{ ..base }` 按 record；
5. 其余 `{ ... }` 按 block。

空 `{}` 是 Unit block；空 record 写 `Type {}`，不能依靠期待类型把同一 CST
静默改类。非空 bare record可由字段 shape建立独立 CST，再由 expected type
解析具体 constructor。

### A.9 Handler、resumption 与 `with`

```peg
HandlerExpr       <- HANDLER Type HandlerBody
HandlerBody       <- LBRACE HandlerMember* RBRACE
HandlerMember     <- ReturnClause / HandlerClause
HandlerClause     <- Mode LowerIdent ClausePatternList
                     ContinuationBinder? FAT_ARROW Expr
                     (COMMA / SEMICOLON)?
ClausePatternList <- LPAREN PatternList? RPAREN
ContinuationBinder <- AS LowerIdent
ReturnClause      <- RETURN LPAREN Pattern RPAREN FAT_ARROW Expr
                     (COMMA / SEMICOLON)?

WithExpr          <- WithEntry+ IN Expr
WithEntry         <- WITH WithOperand (AS LowerIdent)?
WithOperand       <- Expr[stop = WITH | AS | IN]
```

`ClausePatternList` 使用 pattern，不复用 declaration `ParamList`。
`as k` 只允许在 `once` / `ctl` clause。Surface 允许省略 `return`；
elaboration 必须先合成 `return(value) => value`，然后 Core exactness 才检查
“恰好一个 return、每个 operation 恰好一个 clause、无 extra/duplicate”。

`k.resume(value)` 与 `k.finalize()` 由 resolver 降为 resumption primitive。
`k.discontinue(error)` 不属于本 profile。

第一方 completion source 的普通 method spelling
`source.park(k, under = owner)` 由 resolver/type checker在 sealed evidence
下降为 Core `park(source, owner, k)`。它产生
`Transfers(ParkContractV2)` 并终止当前 path，不返回 `Unit`。source/port的
payload必须精确等于 operation result `A`；保存的完整 resumption再执行
`A -> B` answer transform。普通用户 method、
closure 或容器不能伪造该 lowering，也不能把 raw `Resume` 捕获进 host
callback。

`WithOperand` 使用 terminator-aware expression flavor：它允许 operand 内部的
call、trailing lambda、`if`、`match` 和带括号的 nested `with`，但在当前
chain 深度的下一 `with`、binder `as` 或最终 `in` 前停止。较早 entry 的
`as` binder 对后续 operand 和 body 可见，不在自己的 operand 中可见。

`with` 先保留有序 `ScopedApply`。只有 handler evidence 才允许 `as binder`
并降为
`freshprompt p in handle[p,h,ι](let binder=capref(ι); body)`；匿名 handler
省略 term binder但仍有 fresh prompt。普通 transformer降为普通 thunk call。

### A.10 Temporal surface

```peg
DelayTail         <- LBRACKET LowerIdent RBRACKET &LBRACE
DelayExpr         <- "delay" &DelayTail CUT
                     LBRACKET LowerIdent RBRACKET Block
```

- `delay[frame] { e }` 是 dedicated temporal expression；
- `advance(e)` 保持普通 call，只有 sealed prelude binding 才降为 intrinsic；
- `Next[frame,A]` 保持普通 type application CST，由 kind checker 重分类；
- `resumes next` 和 `may_suspend` 只出现在 operation contract；
- handler 与 `Next` 不默认交换，相关 evidence 属于静态语义而非 grammar。

TR₀ 不增加 existential/rank-2 grammar。Clock package只通过三个 sealed
first-party package-qualified value进入 surface：

```cire
let packed = @temporal::pack_next(under=owner) { frame =>
  delay[frame] { 42 }
}

let value = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

@temporal::dispose(packed)
```

三者使用现有 `QualifiedName`、labelled argument与 trailing-lambda CST；只有
resolver确认 exact sealed origin时才产生 contextual HIR。builder/open block
不是普通 first-class callback type：前者获得 fresh FrameClock，后者只在
lexical scope内获得 raw `frame` 与 surface `Next[frame,A]`；hidden Later
contract $L$ 只存在于 Core/interface，不能在 source type中拼写。
`PackedNext[A]` 是 copyable shared handle；`try_with_packed_next` 的
Closing/Closed path显式返回 `None`，成功 body的 Returns映射为 `Some`，而
安全的 Aborts/Transfers在完整 identity-nonescape后 exactly-once release并
保持 terminal tag。普通同名函数不享有这些 binder或 lowering。

### A.11 Syntax validation 与静态语义边界

Parser 必须产出 lossless CST；下列检查在 syntax validation/resolver/type
checker 中完成：

- identifier kind、visibility 适用范围和 duplicate declaration；
- type/effect/row binder domain 与 kind；
- ability conformance、associated binding/kind/default exactness；
- only-`Lacks` row predicate profile check，以及 ability-target independent
  `impl` profile check；
- pattern binder exactness、or-pattern binder equality、match exhaustiveness；
- assignment place、label matching、default parameter 和 generic arity；
- operation contract、mode refinement、handler clause exactness；
- named capability identity、row removal、capture/escape；
- one-shot disposition、multi-shot replay/fork 和 Owner transfer；
- temporal clock identity、phase authority 和 storage boundary；
- PackedNext sealed origin、shared lease state、完整 path nonescape/release；

Parser recovery 可以插入 missing token 或 error node，但恢复结果不能成为语言
语义。Canonical accept/reject 例子见 [`../examples/spec/`](../examples/spec/)。
