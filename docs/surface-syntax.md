# Cire 表面语法工作规范

## 1. 状态与目标

本文是 Cire 当前的**表面语法工作规范**。它把已经决定的语法与仍需形式化的语义边界分开：

- 标为**已决定**的写法可以作为 parser、formatter、测试与文档的共同输入；
- 标为**工作形式**的写法可以先实现，但在形成兼容性承诺前仍可调整；
- 标为**开放问题**的部分不得被编译器悄悄赋予偶然语义。

Cire 的基本外观遵循 MoonBit：

- 泛型参数和泛型实参使用方括号；
- 函数、方法、ADT、模式匹配、labelled argument、包限定名尽量沿用 MoonBit 的形状；
- block 是表达式，最后一个表达式是结果；
- Cire 只为 effect、handler、continuation 与 named capability 增加必要语法。

本文不是 EBNF。语法规则采用 PEG，最终以手写 parser 中的可执行规则和 conformance test 为准。

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

fn[A, B] map(
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
| 函数类型参数 | `fn[A] map(...)` |
| 函数类型 | `(A) -> B`、`(A, B) -> C` |
| 可变局部绑定 | `let mut value = ...` |
| 方法声明 | `fn Type::method(self : Type, ...)` |
| package-qualified name | `@pkg.name` |
| labelled parameter | `key~ : Key` |
| labelled argument | `key=value` 或 label punning |
| 结构化退出动作 | `defer cleanup()` |

纯函数省略 effect row。`Unit` 参数的函数仍写成 `fn() { ... }`，不会引入单独的 procedure 语法。

## 3. Effect 声明

### 3.1 Operation mode

**已决定**

```moonbit
pub(open) effect Error[E] {
  abort[A] raise(error : E) -> A
}

pub(open) effect Async {
  once[A] await(task : Task[A]) -> A
}

pub(open) effect Reader[R] {
  fun ask() -> R
}

pub(open) effect Choice {
  ctl[A] choose(values : Array[A]) -> A
}
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

mode 写在类型参数之前，例如 `once[A] await(...)`，与 MoonBit 的 `fn[A] name(...)` 保持同一视觉顺序。

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
合并。高级 HIR dump 可以显示这个隐式量化，但第一版不增加
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
fn load(url : Url) -> Data
  ! {Network, Async, Error[HttpError]} {
  ...
}

fn[A, B]![..E] map_effectful(
  xs : Array[A],
  f : (A) -> B ! E,
) -> Array[B] ! E {
  ...
}

fn[A]![..E] observe_then(
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
fn read_app(app : cap Read[Int]) -> Int ! {app} {
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
fn sync(app : cap Read[Model]) -> Unit
  ! {Network, Error[SyncError], app} {
  ...
}
```

### 4.3 普通类型、effect 与 capability 多态

**工作形式；双列表已接受为细化基线，尚未实现**

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
fn[
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
fn[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}

fn[A]![F : Reader[A]] read_from(
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
普通 `Int` value 不能出现在 effect row。`with h as app { ... }` 创建 fresh
identity，并在 Kernel HIR 中建立 rank-2/generative boundary。

四种常见 annotation：

```moonbit
! E                    // 精确 row variable
! {F}                  // 匿名 effect family
! {app}                // 具名 capability
! {F, app, ..E}        // 扩展开放 row
```

两个未知 row 使用 row formula，不在一个 literal 中放两个开放 tail：

```moonbit
fn[A, B, C]![..E1, ..E2] compose(
  first : (A) -> B ! E1,
  second : (B) -> C ! E2,
) -> (A) -> C ! (E1 | E2) {
  value => second(first(value))
}
```

Effect row constraint 的工作形式：

```moonbit
fn![
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

当前 parser 尚未支持 `![...]`、`ability`、`cap`、associated effect/row、
row formula 或 `fresh`。旧的 `Fx : Effect` / `Eff : EffectRow` parser
fixture 只代表已经完成的实现 baseline，不再代表目标表面语法。

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
  task.owner.adopt(k)
}

ctl choose(values) as k => {
  values.map(value => k.resume(value))
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
k.discontinue(error)
k.finalize()
```

这些不是可覆盖的普通方法。resolver 将它们识别为 continuation primitive，HIR 中分别保存为 `Resume`、`Discontinue` 与 `Finalize`，因此不能通过定义一个同名 method 改变控制语义。

`owner.adopt(k)` 是责任转交的当前工作拼写；名称仍可调整。无论最后采用什么拼写，adopt 都必须消耗当前 clause 的处置责任，并由编译器检查，而不能只是一个约定俗成的容器插入函数。

### 6.3 Return 与 forwarding

**工作形式**

```moonbit
handler Reader[Int] {
  fun ask() => 42
  return(value) => value
}
```

- 省略 `return` 时等价于 identity；
- 不属于当前 handled effect 的 operation 自动向外层 handler 转发；
- 当前 effect 中没有 clause 的 operation 默认产生穷尽性诊断；
- 显式 forwarding 的最终关键字和 clause 形式仍是开放问题。

第一版 handler 是 lexical deep handler。Shallow handler 不进入第一版语法。

## 7. 本质形式与语法糖

语法糖必须在 resolver 和类型检查之前降到少量稳定的 HIR 形式；CST 始终保留用户原始写法，以供 formatter、诊断与 LSP 使用。

### 7.1 `with` 是 handler application 的糖

**已决定**

与 Koka 相同，`with` 不表示一个额外的核心控制构造。Handler value 本质上是接收 computation thunk 的函数。

```moonbit
with all_choices {
  Choice::choose([false, true])
}
```

降为：

```moonbit
all_choices(fn() {
  Choice::choose([false, true])
})
```

evaluation order 以展开后的普通调用为准：先求值 handler expression，再构造 thunk，再调用 handler。

Named capability binder 也只是把显式 action 参数写得更自然：

```moonbit
with read_42 as app {
  read_app(app)
}
```

降为：

```moonbit
read_42(fn(app) {
  read_app(app)
})
```

Handler 的类型为 `app` 创建 fresh generative identity。编译器从这个 binder
推导 capture，并保证保留 `app` 的值不会逃出 handler action。这里不能把
`app` 当作普通未受约束的函数参数。

Inline handler：

```moonbit
with handler Read[Int] {
  fun read() => 42
} as app {
  read_app(app)
}
```

按两步降为：

```moonbit
let generated_handler = handler Read[Int] {
  fun read() => 42
}
generated_handler(fn(app) {
  read_app(app)
})
```

临时绑定只用于说明求值顺序，编译器不必实际生成可观察的名称。

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

`with` 的 handler operand 是这一规则的有意例外。Parser 使用
`StopBeforeTrailingBlock` flavor 解析 operand，因此：

```moonbit
with make_handler(1) { run() }
```

唯一解释为 `with` action，不会先把 `{ run() }` 附着成
`make_handler(1)` 的 trailing lambda。需要把 trailing lambda 放进 operand
时必须显式加括号：

```moonbit
with (make_handler(1) { configure() }) { run() }
```

### 7.3 不属于语法糖的构造

以下语义不能降为不受编译器理解的普通库调用：

- handler expression 与 operation dispatch；
- `k.resume`、`k.discontinue`、`k.finalize`；
- fresh named capability identity；
- continuation usage/capture checking；
- Owner adoption 的责任转移；
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

Handler application 在 Kernel HIR 中保留专用 binder：

```text
HandlerAction {
  capability : CapabilityId
  body
}
```

编译器负责：

- 为 capability binder 生成 fresh、不可伪造的 identity；
- 推导闭包、handler 与 continuation 的 capture；
- 检查 return、closure、aggregate 与 storage boundary 上的 escape；
- 检查 continuation 被 Owner adopt 后的唯一处置责任；
- 把静态 capability identity 与运行时 Owner/generation 区分开。

源码只使用 `{app}`。Capture 结果保存在 HIR、接口摘要和诊断中。

### 8.2 Capture safety gate

**已决定的实现原则**

Capture safety 要么作为一组一致的核心规则实现，要么整组延后；不能先接受程序，再只检查少数 UI 或 `once` 特例。

在正式启用前，至少需要共同定义：

- capture inference 与传递闭包；
- capability binder escape；
- `once` usage 在 closure、ADT 与 existential 中的传播；
- multi-shot replayability；
- mutable authority 的 replay 语义；
- handler mode weakening 对 capture safety 的影响；
- Owner adoption 与 finalization 的唯一责任。

如果这些规则尚未完成，编译器应通过 feature gate 或明确的“尚未支持”诊断拒绝依赖它们的程序，而不是运行一个静默不安全的宽松模式。

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
fn user_pane(user : Source[User]) -> View ! {Observe} {
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

## 10. PEG 规则片段

下面使用 PEG 的 ordered choice、repetition 与 lookahead；它们是 parser 规则的设计片段，不是 EBNF。

```peg
GenericClauses <- TypeParams? EffectParams?
TypeParams     <- LBRACKET TypeParam (COMMA TypeParam)* COMMA? RBRACKET
TypeParam      <- UpperIdent (COLON TypeConstraintList)?
EffectParams   <- BANG LBRACKET EffectParam
                  (COMMA EffectParam)* COMMA? RBRACKET
EffectParam    <- DOTDOT UpperIdent RowConstraintList?
                / EffectConstructorBinder AbilityConstraintList?
                / UpperIdent AbilityConstraintList?

TypeArgs       <- LBRACKET Type (COMMA Type)* COMMA? RBRACKET
EffectArgs     <- BANG LBRACKET EffectArg (COMMA EffectArg)* COMMA? RBRACKET
EffectArg      <- RowLiteral / Type

Visibility     <- PUB (LPAREN OPEN RPAREN)?
Mode           <- ABORT / ONCE / FUN / CTL

AbilityDecl    <- Visibility? ABILITY TypeHead SuperAbilities?
                  LBRACE AbilityItem* RBRACE
EffectDecl     <- Visibility? EFFECT TypeHead EffectConformance?
                  LBRACE EffectItem* RBRACE
OperationDecl  <- Mode GenericClauses LowerIdent ParamList ARROW Type

EffectAnnotation <- BANG (RowLiteral / Type)
RowLiteral     <- LBRACE RowItems? RBRACE
RowItems       <- RowItem (COMMA RowItem)* COMMA?
RowItem        <- DOTDOT UpperIdent / CapabilityIdent / Type
CapabilityType <- CAP Type

HandlerExpr    <- HANDLER Type HandlerBody
HandlerBody    <- LBRACE HandlerClause* ReturnClause? RBRACE
HandlerClause  <- Mode LowerIdent ParamList ContinuationBinder? FAT_ARROW Expr
ContinuationBinder <- AS LowerIdent
ReturnClause   <- RETURN LPAREN Pattern RPAREN FAT_ARROW Expr

WithExpr       <- WITH HandlerOperand (AS LowerIdent)? Block
TrailingLambda <- LBRACE LambdaHead? ExprItems RBRACE
LambdaHead     <- LambdaParams FAT_ARROW
```

Parser 必须在语义阶段额外检查：

- `[...]` 与 `![...]` 是否建立了不同的 binder domain；
- `F`、`F[_]` 与 `..E` 是否分别解析为 effect atom、effect constructor 和
  effect row binder；
- brace-less effect annotation 中的 type 是否解析为 `EffectRow`；
- `![...]` 的 row argument `{...}` 是否对应声明位置的 `..E`；
- `cap F` 是否引用一个 effect-family binder；
- polymorphic operation clause 是否以 declaration 的 fresh type skolem 检查；
- `ContinuationBinder` 只出现在 `once` 或 `ctl` clause；
- row 中的 lower identifier 是否解析为 capability；
- `Read[app]` 若出现在源代码中，应给出“诊断展开不可作为语法”的定向错误；
- `pub(open)` 是否只用于允许该 visibility 的声明；
- trailing lambda 是否确实附着到 call expression。

Expression precedence 不使用左递归 PEG 规则；手写 parser 采用明确的 precedence ladder 或 Pratt-style postfix/infix loop，同时保持 PEG 的 ordered-choice 与 commit 语义。完整 parser 设计见 [编译器前端架构](compiler-architecture.md)。

## 11. 当前仍需讨论

以下问题没有因本规范而自动解决：

1. `val` 是否保留为零参数 `fun` operation 的糖；
2. 同一 effect 中未列 operation 的显式 forwarding 拼写；
3. `owner.adopt(k)` 的最终名称；
4. Owner 的第一方 API 与责任转移操作如何组合；
5. multi-shot 下局部 mutation 的唯一一致语义；
6. operation 最大 mode 与实际 handler mode 如何共同约束 capture safety；
7. one-call/many-call closure 是否需要显式 surface marker；
8. stable lexical site 的跨编辑、重构和增量编译身份规则；
9. `Error[E]` 是否提供 `raise`、`try/catch` 的专用糖；
10. shallow handler 是否永远只作为低层能力，或完全不提供。

这些问题应先在 Core/HIR 类型规则中回答，再增加表面写法。
