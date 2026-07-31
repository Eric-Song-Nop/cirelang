# Cire 表面语法规范

## 1. 状态与目标

> **Profile:** [`Cire-TR₀/2026-08-01`](spec-status.md)
>
> 本文定义表面构造的含义；完整、实现无关的 token/PEG grammar 见
> [Cire-TR₀ 完整表面语法](surface-grammar.md)。

本文把 profile baseline 与仍需研究的语义边界分开：

- 标为 **Profile baseline** 的写法是当前规范；
- 标为**工作语法**的写法已有唯一 grammar/elaboration，但拼写仍可调整；
- 标为**开放问题**的部分不得被未来编译器悄悄赋予偶然语义。

Cire 的基本外观遵循 MoonBit：

- 泛型参数和泛型实参使用方括号；
- 函数、方法、ADT、模式匹配、labelled argument、包限定名尽量沿用 MoonBit 的形状；
- block 是表达式，最后一个表达式是结果；
- Cire 只为 effect、handler、continuation 与 named capability 增加必要语法。

规范先于实现。未来 parser 与 conformance test 必须服从
[完整表面语法](surface-grammar.md)，不能反向裁决语言。

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
| package-qualified name | `@pkg.name` |
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

Effect row constraint 的工作形式：

```moonbit
def![
  ..E : Has[Log] + Lacks[Blocking] + All[Replayable],
] schedule(task : () -> Unit ! E) -> Task ! E {
  ...
}
```

`Has`、`Lacks`、`All` 是 row predicate，不是可调用 operation 的 ability。

显式调用也使用双列表：

```moonbit
consume[Int]![State[Int], {Log}](app, log_value)
```

普通类型实参和 effect/row 实参不会再依靠位置上的 kind marker 混合解释。

Ability 的 associated type/effect/row、higher-kinded binder、`fresh` function
type 与 Core 展开见[多态与 effect abstraction 工作设计](polymorphism-design.md)。

完整 binder、argument 与 `RowExpr` grammar 见
[完整表面语法](surface-grammar.md#3-形参实参与约束)。表面的两个形参列表
是不同 kind domain 的参数绑定；只有 elaboration/generalization 明确引入
Core binder 时才讨论量词。

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
`Open(n)|Closing(n)|Closed` cell；dispose幂等、NoSuspend、非 Pure，并不等待
active lease归零。三段 block是 contextual HIR，不是用户可声明的普通 callback
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

[Cire-TR₀ 完整表面语法](surface-grammar.md)统一规定：

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

## 11. 当前仍需讨论

以下问题没有因本规范而自动解决：

1. `val` 是否保留为零参数 `fun` operation 的糖；
2. 同一 effect 中未列 operation 的 explicit forwarding/masking 拼写；
3. Owner sealed completion source/port 的库 API 细节；
4. multi-shot 下局部 mutation 的唯一一致语义；
5. one-call/many-call closure 是否需要显式 surface marker；
6. stable lexical site 的跨编辑、重构和增量编译身份规则；
7. `discontinue` 是否在完整 typed control/world/cleanup contract 后进入新
   profile；
8. shallow handler 是否永远只作为低层能力，或完全不提供。

这些问题应先在 Core/HIR 类型规则中回答，再增加表面写法。
