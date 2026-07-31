# 16　Cire 语法索引

> 本索引服从 [`Cire-TR₀/2026-08-01`](../spec-status.md) 与
> [完整表面语法](../surface-grammar.md)；仓库当前没有 parser。

本章是教程的速查表，不替代完整 grammar。Cire 的 grammar 使用手写 PEG；
最终规则以 [完整表面语法](../surface-grammar.md) 为准；未来 parser 与
conformance corpus必须服从它。

## 1. 顶层声明

### 函数

```cire
def name(parameters) -> ResultType {
  body
}

pub def[A : Trait] name(...) -> Result ! {Effect} {
  ...
}
```

普通泛型位于 `def` 之后、函数名之前：`def[A, B] name(...)`。

### Struct 与 enum

```cire
struct Pair[A, B] {
  first : A
  second : B
}

enum Option[A] {
  None
  Some(A)
}
```

### Method

```cire
def User::display_name(self : User) -> String {
  self.name
}
```

### Trait

```cire
pub(open) trait Show {
  def to_string(self : Self) -> String
}

pub impl Show for User {
  def to_string(self : User) -> String {
    self.name
  }
}
```

普通 trait/impl 已进入 profile grammar；仓库当前没有 parser/checker。

### Ability 与 effect

```cire
pub(open) ability Reader[A] {
  fun read() -> A
}

pub(open) effect State[A]
  : Reader[A] {
  fun reset(value : A) -> Unit
}
```

`ability` 是 effect family 的静态 operation contract；`effect` 声明一个
具体、名义化的 family。

## 2. Visibility

```text
普通声明：
  默认       当前 package
  pub        对外公开

trait/effect：
  默认       当前 package
  pub        外部可使用，定义 package 控制新实现
  pub(open)  外部也可提供实现/handler
```

普通数据类型是否还区分 abstract/readonly/fully-public 表示，仍需随 package
设计冻结。

## 3. 值与 binding

```cire
let name = expression
let name : Type = expression
let mut count = 0
count = count + 1
```

Block 的最后一个表达式是结果：

```cire
{
  let value = work()
  value + 1
}
```

结构化退出动作：

```cire
defer cleanup()
```

## 4. 常用表达式

```cire
callee(arg1, arg2)
receiver.method(arg)
Type::qualified(arg)
@package::name(arg)

if condition {
  consequent
} else {
  alternative
}

match value {
  Pattern => result
  Pattern if guard => result
}
```

循环工作形式：

```cire
for value in values { ... }
while condition { ... }
loop { ... }
return value
break
continue
```

完整 loop result、label 和 operator precedence 仍需冻结。

## 5. Literal 与 aggregate

```cire
()
true
42
3.14
'a'
"text"

(left, right)
[first, second]
{ field: value }
```

Numeric suffix、raw/multiline string、interpolation、byte literal、tuple
边界、struct update 和 index/update 的精确规则仍是普通语法开放项。

## 6. Pattern

工作基线：

```cire
_
42
Some(value)
{ name, active: true, .. }
(left, right)
[first, ..rest]
left | right
pattern as whole
```

Constructor、record、array、or-pattern、guard、typed pattern 和 rest pattern
需要在完整 PEG 中冻结优先级与 binder 规则。

## 7. 函数类型与 lambda

```cire
(A) -> B
(A, B) -> C
(A) -> B ! {Logger}

fn(value) {
  body
}
```

Generic function value 的工作形式：

```cire
mapper : fn[B]![..E](A) -> B ! E
```

## 8. Labelled parameter 与 argument

```cire
def connect(host : String, port~ : Int) -> Connection {
  ...
}

connect("example.com", port=443)
connect("example.com", port~)
```

`port~` 在 call 中是 label punning。可选和默认参数尚未冻结。

## 9. Trailing lambda

```cire
callee(args) {
  body
}

callee { value =>
  body
}
```

一个 trailing lambda 只能是最后一个参数；newline/comment 不打断附着；
显式 `;` 才把 call 与独立 block 分开。

## 10. 普通 generic

```cire
def[A] identity(value : A) -> A
def[A : Eq + Show] explain(value : A) -> String

Array[Int]
Result[Profile, LoadError]
identity[Int](1)
```

`[...]` 只放普通类型参数和普通 trait constraint。

## 11. Effect generic

```cire
def![F] forward(...)
def[A]![F : Reader[A]] read(...)
def[A]![..E] map_effectful(...)
def[A]![F[_] : Raise[_]] fail(...)
```

```text
F                    Effect
F : Reader[A]        constrained Effect
F[_]                 Type -> Effect
..E                  EffectRow
```

显式实参工作形式：

```cire
consume[Int]![State[Int], {Logger}](...)
```

## 12. Effect annotation 与 row

```cire
! {}
! {Network, Error[HttpError]}
! E
! {F}
! {app}
! {F, app, ..E}
! (E1 | E2)
```

含义：

```text
! E             精确 row variable
! {F}           匿名 effect family
! {app}         具名 capability identity
! {..E}         open row tail
E1 | E2         row union 工作形式
```

一个 row literal 最多一个 open tail。

## 13. Row constraint

```cire
def![
  ..E : Has[Logger] + Lacks[Blocking] + All[Replayable],
] schedule(...) -> Task ! E {
  ...
}
```

`Has`、`Lacks`、`All`、`Only` 是 compiler-known row predicate 的工作设计，
不是 ability operation。

## 14. Associated item

```cire
ability Store {
  type Key
  type Value
  effect Fail : Raise[StoreError]
  effects Extra : All[Replayable] = {}
}
```

Projection：

```cire
S::Key
S::Value
S::Fail
S::Extra
```

Conformance：

```cire
effect FileStore
  : Store[
      Key = Path,
      Value = Bytes,
      Fail = IoFailure,
      Extra = {Async},
    ] {}
```

独立 ability implementation：

```cire
impl[A] Reader[A] for LegacyState[A] {
  def read(self : LegacyState[A]) -> A {
    self.get()
  }
}
```

## 15. Operation declaration

```cire
mode[TypeParameters]![EffectParameters]
  operation(parameters) -> ResultType
```

例子：

```cire
abort[A] raise(error : E) -> A
fun ask() -> R
once[A] await(task : Task[A]) -> A
ctl[A] choose(values : Array[A]) -> A
ctl[A]![..E] run(body : () -> A ! E) -> A
```

## 16. Operation call

```cire
Choice::choose([false, true]) // 匿名 family
app.read()                    // 具名 capability
```

Cire 不增加 `perform` 关键字。Resolver 根据类型环境识别 operation。

## 17. Capability type 与 named row

```cire
def[A]![F : Reader[A]] read_from(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

`cap F` 是工作 type syntax；`{app}` 是已决定的源 row 语法。

下面只允许出现在诊断中：

```text
Read[app]
```

它不能写进源程序。

## 18. Handler

```cire
handler EffectType {
  abort operation(patterns) => expression
  fun operation(patterns) => expression
  once operation(patterns) as k => expression
  ctl operation(patterns) as k => expression
  return(value) => expression
}
```

`abort`/`fun` 不允许 `as k`；`once`/`ctl` 显式绑定 continuation。
省略 `return` 等价于 identity。

## 19. `with`

匿名 application：

```cire
with handler_value
in action
```

具名 application：

```cire
with handler_value as app
in action
```

Surface HIR：

```text
ScopedApply(handler_value, binder = none, body = action)
ScopedApply(handler_value, binder = app, body = action)
```

若类型证明 transformer 是 handler，Kernel 使用 fresh prompt；第二种还以
`CapRef` 创建 fresh identity，不能按普通无约束 lambda 参数处理。普通
transformer才降为 closure call。整个 `with ... in ...` 是 expression；
`in` 后可直接跟单个 expression或 `{ ... }` block。

组合处理多个 effect 使用有序 chain；第一项最外层，最后一项最靠近 action：

```cire
with clock_handler
with logger_handler
with error_handler
in {
  action()
}
```

每层都写 `in` 表示显式嵌套的多个单项 chain，也合法：

```cire
with clock_handler in
  with logger_handler in
    with error_handler in {
      action()
    }
```

`with` operand 也可以是接收 computation thunk 的普通高阶 wrapper：

```cire
with retry(3)
with transaction(db)
in {
  save()
}
```

`as app` 只允许建立 fresh named capability，不是普通 variable binding。
当前工作语法不增加 multi-effect handler literal。

PEG 工作形状：

```peg
WithExpr    <- WithEntry+ IN Expr
WithEntry   <- WITH WithOperand (AS LowerIdent)?
```

`in` 分隔 operand chain 与 computation，所以 operand 可以正常带 trailing
lambda：

```cire
with make_handler {
  configure()
}
in {
  run()
}
```

顶层 operand 自身若是 `with` expression，需要括号：

```cire
with (
  with configure_runtime
  in make_handler()
)
in {
  run()
}
```

## 20. Continuation disposition

```cire
k.resume(value)
k.finalize()
source.park(k, under = owner)
```

前两个降为 Core resumption primitive。第三个只在 sealed completion-source
evidence 下产生 terminal `Transfers(ParkContractV2)`；它不返回 `Unit`，宿主
只得到 generation-bound completion port。

若 `k : Resume[Once,Dk,A,B]`，source/port payload必须为 `A`；保存的 `Dk`
才把 completion value继续变成 answer `B`。

## 21. Sealed `PackedNext` ABI

```cire
@temporal::pack_next(under=owner) { frame => body }
@temporal::try_with_packed_next(packed) { frame, pending => body }
@temporal::dispose(packed)
```

它们使用普通 qualified call、label与 trailing-lambda CST，但只有解析到
exact sealed first-party origin才产生 contextual HIR。第二个调用返回
`Option[B]`；failed acquire是 `None`，won path在 private identity nonescape
之后 exactly-once release。不存在一般 existential/rank-2 source syntax。

## 22. 不是 Cire 源语法的概念

以下内容不增加关键字或 annotation：

- compiler 推导的 capability capture；
- Owner generation；
- incremental continuation cut；
- `Source`、`Live`、`Event`、`Task`、`Resource`；
- Component、DOM、Suspense、state；
- UI stable site；
- handler 的内部 rank-2/generative 表示。

它们分别是静态分析结果、runtime metadata 或第一方库概念。

## 23. 明确不提供

Cire 不设计：

- token macro；
- AST macro；
- typed hygienic macro；
- UI 专用 parser；
- `Read[app]` 源语法；
- 为 capture 增加另一套用户标注。

## 24. 尚未冻结的便捷语法

以下概念仍在讨论，不能当作可用语法：

- 无参数 `fun` operation 的 `val` 糖；
- 同一 effect operation 的显式 forwarding；
- 局部 override/masking 的最终拼写；
- `Error[E]` 的 `raise`、`try/catch` 专用糖；
- one-call/many-call closure marker；
- shallow handler；
- Owner completion source/port 的库 API 细节；
- stable lexical site 的表面接口。

教程始终先使用已经定义的核心形式。

## 25. 仓库实现状态

仓库当前没有 parser、checker、runtime、标准库、formatter、LSP 或 backend。
本索引描述 `Cire-TR₀/2026-08-01` 的目标语法；正负样例位于
[`examples/spec/`](../../examples/spec/)，但它们是 conformance 规范，
不是已通过的测试。重新实现的入口条件见[状态矩阵](../spec-status.md)。

## 26. 继续阅读

- 表面构造说明：[Cire 表面语法设计说明](../surface-syntax.md)
- 高级多态：[多态与 effect abstraction](../polymorphism-design.md)
- 恢复规则：[代数效应与恢复模式](../effects-and-resumptions.md)
- Capture/Owner：[Named capability、Owner 与结构化清理](../capabilities-and-finalization.md)
- Compiler/LSP：[编译器前端架构](../compiler-architecture.md)

上一章：[完整示例](15-complete-example.md)　回到：[教程首页](README.md)
