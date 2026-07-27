# 16　Cire 语法索引

本章是教程的速查表，不替代完整 grammar。Cire 的 grammar 使用手写 PEG；
最终规则以可执行 parser 和 conformance test 为准。

## 1. 顶层声明

### 函数

```cire
fn name(parameters) -> ResultType {
  body
}

pub fn[A : Trait] name(...) -> Result ! {Effect} {
  ...
}
```

普通泛型位于函数名之后：`fn[A, B] name(...)`。

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
fn User::display_name(self : User) -> String {
  self.name
}
```

### Trait

```cire
pub(open) trait Show {
  to_string(Self) -> String
}

pub impl Show for User with to_string(self) {
  self.name
}
```

普通 trait/impl 采用 MoonBit 风格工作基线，完整 parser 尚未实现。

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
@package.name(arg)

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

value => expression
```

Generic function value 的工作形式：

```cire
mapper : fn[B]![..E](A) -> B ! E
```

## 8. Labelled parameter 与 argument

```cire
fn connect(host : String, port~ : Int) -> Connection {
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
fn[A] identity(value : A) -> A
fn[A : Eq + Show] explain(value : A) -> String

Array[Int]
Result[Profile, LoadError]
identity[Int](1)
```

`[...]` 只放普通类型参数和普通 trait constraint。

## 11. Effect generic

```cire
fn![F] forward(...)
fn[A]![F : Reader[A]] read(...)
fn[A]![..E] map_effectful(...)
fn[A]![F[_] : Raise[_]] fail(...)
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
fn![
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

独立 ability implementation 的工作形式：

```cire
impl[A] Reader[A] for LegacyState[A] {
  read = LegacyState::get
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
fn[A]![F : Reader[A]] read_from(
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
with handler_value {
  action
}
```

具名 application：

```cire
with handler_value as app {
  action
}
```

概念展开：

```cire
handler_value(fn() { action })
handler_value(fn(app) { action })
```

第二种 application 会创建 fresh identity，不能按普通无约束 lambda 参数
处理。

组合处理多个 effect 使用普通嵌套：

```cire
with clock_handler {
  with logger_handler {
    with error_handler {
      action()
    }
  }
}
```

也可以把嵌套封装成接收 action thunk 的普通高阶函数，再使用同一个 `with`
外观。当前工作语法不增加 multi-effect handler literal。

## 20. Continuation disposition

```cire
k.resume(value)
k.discontinue(error)
k.finalize()
owner.adopt(k)
```

前三个是 compiler-recognized continuation primitive。`owner.adopt(k)` 是
责任转移的工作名称，也必须由 compiler 检查。

## 21. 不是 Cire 源语法的概念

以下内容不增加关键字或 annotation：

- compiler 推导的 capability capture；
- Owner generation；
- incremental continuation cut；
- `Source`、`Live`、`Event`、`Task`、`Resource`；
- Component、DOM、Suspense、state；
- UI stable site；
- handler 的内部 rank-2/generative 表示。

它们分别是静态分析结果、runtime metadata 或第一方库概念。

## 22. 明确不提供

Cire 不设计：

- token macro；
- AST macro；
- typed hygienic macro；
- UI 专用 parser；
- `Read[app]` 源语法；
- 为 capture 增加另一套用户标注。

## 23. 尚未冻结的便捷语法

以下概念仍在讨论，不能当作可用语法：

- 无参数 `fun` operation 的 `val` 糖；
- 同一 effect operation 的显式 forwarding；
- 局部 override/masking 的最终拼写；
- `Error[E]` 的 `raise`、`try/catch` 专用糖；
- one-call/many-call closure marker；
- shallow handler；
- Owner adoption 的最终 API 名称；
- stable lexical site 的表面接口。

教程始终先使用已经定义的核心形式。

## 24. 当前 compiler 覆盖

已经有 parser baseline：

- function signature、type parameter、function type、call 和 block；
- effect declaration、四种 operation mode、基础 effect row；
- `{app}` 和错误 `Read[app]` 的定向修复；
- method/qualified call、labelled argument、label punning；
- trailing lambda、handler、`with`、`return` clause、`as k`；
- lossless CST、missing token、error node、diagnostic/fix serialization；
- revision-checked reparse correctness baseline。

尚未完成：

- 完整 ordinary expression、ADT、pattern、trait、package 和 precedence；
- 双列表、ability、`cap`、associated item、row algebra；
- name resolution、kind/type/effect/capture checking；
- Surface HIR、Kernel HIR 和正式 desugaring；
- formatter、LSP、runtime、Wasm backend。

实现状态会变化，最新清单以[简明进度](../simple/progress.md)为准。

## 25. 继续阅读

- 目标表面规则：[Cire 表面语法工作规范](../surface-syntax.md)
- 高级多态：[多态与 effect abstraction](../polymorphism-design.md)
- 恢复规则：[代数效应与恢复模式](../effects-and-resumptions.md)
- Capture/Owner：[Named capability、Owner 与结构化清理](../capabilities-and-finalization.md)
- Compiler/LSP：[编译器前端架构](../compiler-architecture.md)

上一章：[完整示例](15-complete-example.md)　回到：[教程首页](README.md)
