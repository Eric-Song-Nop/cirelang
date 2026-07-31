# 07　Effect 多态与 ability

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

## 1. 高阶函数为什么需要 effect 多态

先写一个只接受纯 callback 的 `map`：

```cire
def[A, B] map(
  values : Array[A],
  transform : (A) -> B,
) -> Array[B] {
  ...
}
```

如果 callback 要记录日志：

```cire
users.map { user =>
  Logger::log(Debug, user.name)
  user.id
}
```

`map` 自己没有额外 effect，但 callback 有。把 `Logger` 固定写进 `map` 会让
它无法精确处理 `Network`、`Clock` 或纯 callback。正确的抽象是让 callback
的整行 effect 成为参数：

```cire
def[A, B]![..E] map_effectful(
  values : Array[A],
  transform : (A) -> B ! E,
) -> Array[B] ! E {
  ...
}
```

`E` 是调用者提供的任意 effect row。传入纯函数时 `E = {}`；传入日志
callback 时 `E = {Logger}`。

## 2. 双泛型列表

Cire 把普通类型和 effect 参数分开：

```text
[...]   普通类型参数与普通 trait constraint
![...]  effect family、effect constructor 与 effect row 参数
```

常见 binder：

| 写法 | 类别 | 含义 |
|---|---|---|
| `[A]` | `Type` | 一个普通值类型 |
| `![F]` | `Effect` | 一个完整的原子 effect |
| `![F : Reader[A]]` | `Effect` | 满足 ability 的原子 effect |
| `![F[_]]` | `Type -> Effect` | effect constructor |
| `![..E]` | `EffectRow` | 零个或多个 row item |

形状本身就能区分类别，不需要把所有东西写成：

```text
A : Type
F : Effect
E : EffectRow
```

## 3. Closed row、open row 与精确 row

```cire
! {}
! {Network, Error[HttpError]}
! {Logger, ..E}
! E
```

- `! {}` 是 closed empty row，纯函数通常省略；
- `! {Network, Error[HttpError]}` 是 closed row；
- `! {Logger, ..E}` 在未知 row 上增加 `Logger`；
- `! E` 表示结果恰好是 row variable `E`。

一个 row literal 最多放一个 open tail。两个未知 row 的组合使用 row
formula：

```cire
def[A, B, C]![..E1, ..E2] compose(
  first : (A) -> B ! E1,
  second : (B) -> C ! E2,
) -> (A) -> C ! (E1 | E2) {
  fn(value) { second(first(value)) }
}
```

`E1 | E2` 是 row union 的工作形式。

## 4. Ability：effect family 的 trait

普通 trait 约束一个值类型能做什么；ability 约束一个 effect family
提供哪些 operation：

```cire
pub(open) ability Reader[A] {
  fun read() -> A
}

pub(open) ability Writer[A] {
  fun write(value : A) -> Unit
}

pub(open) ability ReadWrite[A]
  : Reader[A] + Writer[A] {}
```

具体 effect 可以满足这些 ability：

```cire
pub(open) effect State[A]
  : Reader[A] + Writer[A] {}
```

现在可以对任意 Reader family 编程：

```cire
def[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}
```

`{F}` 是匿名 effect demand：调用者需要提供某个满足 `Reader[A]` 的 `F`
handler。

## 5. 普通 trait 与 ability 同样强，但 kind 不同

下面的函数同时约束普通值和 effect family：

```cire
def[
  A : Eq + Show,
]![
  Input : Reader[A],
  Output : Writer[A],
  ..E,
] transfer(
  log : (String) -> Unit ! E,
) -> Bool ! {Input, Output, ..E} {
  let value = Input::read()
  Output::write(value)
  log(value.to_string())
  Input::read() == value
}
```

这里有四层抽象：

```text
A       普通类型
Input   一个满足 Reader[A] 的 effect
Output  一个满足 Writer[A] 的 effect
E       剩余的 effect row
```

普通 trait 与 ability 可以共享 constraint solver、associated item 和
coherence 基础设施，但 resolver 不能把 `Type` 和 `Effect` 当成同一个 kind。

## 6. Operation 级多态

Operation 自己也可以有两套 generic：

```cire
ability Traversable[A] {
  fun[B]![..E] traverse(
    transform : (A) -> B ! E,
  ) -> Array[B]
}
```

`[B]` 是 operation 的普通输出类型，`![..E]` 只量化 callback function
contract 内的 latent row。TR₀ 的 operation 自身 secondary annotation必须是
finite closed row；不能把同一个 `E` 写成 `) -> Array[B] ! E`。

Higher-order operation 也采用同一顺序：

```cire
effect Scope {
  ctl[A]![..E] run(
    body : () -> A ! E,
  ) -> A
}
```

这类 operation 与 resumption safety 的完整规则仍需形式化。
若 operation 自身确实直接产生 secondary effect，必须枚举 closed literal，
例如 `) -> A ! {Audit, Trace}`；`! E` 与 `! {Audit, ..E}` 都在
closed-only WF gate稳定拒绝。

## 7. Associated type、effect 与 row

Ability 可以像强 trait 一样拥有不同 kind 的 associated item：

```cire
pub(open) ability Store {
  type Key
  type Value

  effect Fail : Raise[StoreError]
  effects Extra : All[Replayable] = {}

  fun get(key : Key) -> Value
    ! {Fail}

  fun put(key : Key, value : Value) -> Unit
    ! {Fail}
}
```

这里 operation 的 immediate secondary row是 finite `{Fail}`。
`Extra` 仍可出现在普通 function、callback或 returned-function contract的
open row中，但 TR₀ 不允许把 `..Extra` 放进 operation secondary annotation。

具体 effect 通过 named associated argument 选择它们：

```cire
pub(open) effect FileStore
  : Store[
      Key = Path,
      Value = Bytes,
      Fail = IoFailure,
      Extra = {Async},
    ] {}
```

泛型代码使用 projection：

```cire
def![S : Store] load(
  key : S::Key,
) -> S::Value ! {S, S::Fail, ..S::Extra} {
  S::get(key)
}
```

Associated type/effect/row 让抽象不仅能说“有一个 `get`”，还可以精确关联
key、value、失败 effect 和额外 effect。

## 8. Conformance 与独立 `impl`

Effect header 中最常见的 conformance：

```cire
effect State[A] : Reader[A] + Writer[A] {}
```

如果要让已有 effect 满足 ability，独立 `impl` 使用：

```cire
impl[A] Reader[A] for LegacyState[A] {
  def read(self : LegacyState[A]) -> A {
    self.get()
  }
}
```

带 associated item：

```cire
impl Store for LegacyDatabase {
  type Key = String
  type Value = Record
  effect Fail = DatabaseError
  effects Extra = {Network}

  def get(self : LegacyDatabase, key : String) -> Record {
    self.fetch(key)
  }

  def put(
    self : LegacyDatabase,
    key : String,
    value : Record,
  ) -> Unit {
    self.save(key, value)
  }
}
```

独立 ability `impl` 已进入 profile grammar；checker仍必须冻结并验证
coherence、orphan、overlap、associated item 唯一性、operation adapter 和
mode compatibility。仓库当前没有该 checker。

## 9. Row constraint

有时 API 不关心 row 提供哪些 operation，只关心它满足某种集合性质：

```cire
def![
  ..E : Has[Log] + Lacks[Blocking] + All[Replayable],
] schedule(
  task : () -> Unit ! E,
) -> Task ! E {
  ...
}
```

工作中的 row predicate：

```text
Has[X]          row 包含 X
Lacks[X]        row 不包含 X
All[Property]   每个 entry 都满足某性质
Only[Ability]   entry 限制在某组 ability
```

它们不是 operation contract，不能像 ability 那样调用 method。

## 10. Higher-kinded effect constructor

对 `Type -> Effect` 的构造器抽象时，用 binder hole：

```cire
def[A]![Err[_] : Raise[_]] fail(
  error : A,
) -> Never ! {Err[A]} {
  Err[A]::raise(error)
}
```

`Err[_]` 表示一个接收普通类型并产生 effect 的 constructor。这里的 `_`
不是表达式 inference hole，而是 binder pattern 中的参数位置。

## 11. 显式 generic argument

完整的工作形式让两套实参与两套声明对齐：

```cire
consume[Int]![State[Int], {Logger}](app, log_value)
```

```text
[Int]                  普通类型实参
![State[Int], {Logger}] effect family 与 row 实参
```

实际代码通常写：

```cire
consume(app, log_value)
```

让 compiler 推导所有实参。

## 当前状态

双列表、`![...]`、ability、associated effect/row、row union/predicate 与
higher-kinded effect constructor 已进入 profile grammar。仓库没有 parser
或 kind/row solver；这些例子是 conformance 目标，不是当前可运行程序。

上一章：[第一个 effect](06-effects.md)　下一章：[Handler 与 with](08-handlers-and-with.md)
