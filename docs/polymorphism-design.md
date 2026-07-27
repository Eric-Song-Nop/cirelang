# 多态与 effect abstraction 工作设计

## 1. 文档状态

本文记录 2026-07-27 讨论形成的多态设计基线。

当前状态分成三层：

- **已接受为细化基线**：普通泛型与 effect 泛型使用双列表；
- **设计方向**：effect ability、具名 capability type、associated
  effect/row、row constraint 与 generative handler application；
- **仍可调整**：`ability`、`cap` 等具体关键词，以及 row formula
  的运算符。

本文只描述语言设计，没有对应 parser、类型检查器或运行时实现。当前 parser
仍只认识旧的单列表 `Fx : Effect` / `Eff : EffectRow` baseline；不能因为
本文出现了新语法，就把它标记为“parser 已支持”。

## 2. 设计目标

新的多态语法必须同时满足：

1. 保留 MoonBit 风格的方括号普通泛型；
2. 一眼区分普通类型参数、单 effect family 与 effect row；
3. 普通 trait 与 effect abstraction 都能约束 operation、supertrait 和
   associated item；
4. 匿名 effect 与具名 capability 使用同一份 effect constraint；
5. effect row 能表达转发、union、contains/lacks 和 entry constraint；
6. named handler 的 fresh identity 与 capture 不能被普通
   let-polymorphism 抹掉；
7. 常见签名保持短，只有确实需要高级多态时才展开复杂信息；
8. CST、HIR、diagnostic 和 LSP 能保留每一种 binder 的真实类别。

旧写法：

```moonbit
fn[A, Fx : Effect, Eff : EffectRow] relay(...)
```

有两个问题：

- `Fx : Effect` 只表达 kind，不提供可调用的 operation；
- 普通类型、effect family 与 row 混在一个列表中，区分依赖冗长 kind
  名称和后续语义分析。

双列表设计让语法形状本身承担分类责任。

## 3. 双泛型列表

### 3.1 基本规则

```text
[...]   普通类型参数与普通 trait constraint
![...]  effect family、effect constructor 与 effect row 参数
```

最小例子：

```moonbit
fn[A] identity(value : A) -> A

fn[A]![F : Reader[A]] read() -> A ! {F}

fn[A, B]![..E] map(
  xs : Array[A],
  f : (A) -> B ! E,
) -> Array[B] ! E
```

在 effect 列表中：

```text
F                    一个完整的原子 effect family
F : Reader[A]        满足 ability constraint 的原子 effect
F[_]                 Type -> Effect 的 effect constructor
..E                  一个 effect row
..E : Lacks[Block]   带 row constraint 的 effect row
```

因此新的设计不再要求用户写：

```moonbit
F : Effect
E : EffectRow
```

只转发任意原子 effect 时写：

```moonbit
fn![F] forward(body : () -> Unit ! {F}) -> Unit ! {F} {
  body()
}
```

只转发任意 row 时写：

```moonbit
fn[A]![..E] forward_row(
  body : () -> A ! E,
) -> A ! E {
  body()
}
```

### 3.2 多类参数同时出现

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

这段签名同时量化：

```text
A       普通类型
Input   单 effect family
Output  另一个单 effect family
E       effect row
input   具体 capability identity
output  另一个 capability identity
```

`A` 的 constraint 属于普通 trait；`Input`、`Output` 的 constraint 属于
effect abstraction。Resolver 不能用变量名称猜类别。

### 3.3 显式泛型实参

声明：

```moonbit
fn[A]![F : Reader[A], ..E] consume(
  app : cap F,
  after : (A) -> Unit ! E,
) -> Unit ! {app, ..E} {
  after(app.read())
}
```

显式调用的工作形式：

```moonbit
consume[Int]![State[Int], {Log}](app, log_value)
```

两个实参列表与声明一一对应：

```text
[Int]                 普通类型实参
![State[Int], {Log}]  effect family 与 effect row 实参
```

通常由编译器全部推导：

```moonbit
consume(app, log_value)
```

## 4. Effect abstraction 的三层词汇

为了不再使用冗长且重复的 `effect trait` / `Capability[Fx]`，当前设计方向
使用三个层次：

```text
ability   effect family 的静态接口
effect    具体、名义化的 effect family
cap F     family F 的一个具名 capability instance
```

这些关键词仍可调整，但三层语义需要保留。

### 4.1 Ability

```moonbit
pub(open) ability Reader[A] {
  fun read() -> A
}

pub(open) ability Writer[A] {
  fun write(value : A) -> Unit
}

pub(open) ability ReadWrite[A]
  : Reader[A] + Writer[A] {}
```

普通 trait 与 ability 使用相同的 constraint 基础设施，但约束不同 kind：

```text
Eq          : Type -> Constraint
Reader[A]   : Effect -> Constraint
```

Ability 的 operation mode 是接口的一部分：

```moonbit
ability Environment[A] {
  fun ask() -> A
}

ability Await[A] {
  once await(task : Task[A]) -> A
}

ability Search[A] {
  ctl choose(values : Array[A]) -> A
}
```

具体 effect 或 handler 不能在 conformance 过程中偷偷获得比 ability
contract 更强的 continuation 控制权。`abort`、`fun`、`once`、`ctl` 的
正式能力偏序仍需在 Core 类型规则中定义。

### 4.2 Concrete effect

```moonbit
pub(open) effect State[A]
  : Reader[A] + Writer[A] {}
```

`State[A]` 是具体的 effect family。它继承 ability 的 operation contract，
handler 必须实现这些 operation。

一个 effect 也可以直接声明自身独有的 operation：

```moonbit
pub(open) effect Clock {
  fun now() -> Instant
}
```

Header 中的 conformance 是简写。Core 应保存独立的 effect definition 与
constraint evidence，不能只把 ability 的 operation 文本复制进 effect。

### 4.3 Named capability

工作写法：

```moonbit
app : cap F
```

`cap F` 表示 family `F` 的具名 capability value。它应在 Core 中携带：

```text
family
singleton identity
origin
```

常见用法：

```moonbit
fn[A]![F : Reader[A]] read_from(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

两个相同 family 的 capability 仍然是不同 identity：

```moonbit
fn[A : Eq]![F : Reader[A]] same_value(
  left : cap F,
  right : cap F,
) -> Bool ! {left, right} {
  left.read() == right.read()
}
```

`cap F` 与 `Cap[F]` 哪一种最终更符合 MoonBit 外观仍可讨论；本文使用
`cap F`，因为它短且不会把 capability 与普通 ADT 混淆。

## 5. 匿名 effect 与 named capability 的对称性

匿名 effect：

```moonbit
fn[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}
```

具名 capability：

```moonbit
fn[A]![F : Reader[A]] read_named(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

两者共享同一份 `Reader[A]` evidence：

```text
F::read()   选择匿名 F handler     row 贡献 {F}
app.read()  选择 app 指定的 handler row 贡献 {app}
```

Core row entry 必须继续区分：

```text
Anonymous(F)
Named(app, F)
```

源码写 `{app}`。`Read[app]` 只用于诊断展开，不能作为源语法。

多个 ability 提供同名 operation 时，点调用必须产生歧义诊断。限定调用的
最终写法尚未冻结，候选包括：

```moonbit
Reader::read(app)
Reader::read[F]()
```

前者用于 named capability，后者用于匿名 family。

## 6. Associated type、effect 与 row

Ability 需要和普通 trait 一样支持 associated item，但必须显式区分其 kind：

```moonbit
pub(open) ability Store {
  type Key
  type Value

  effect Fail : Raise[StoreError]
  effects Extra : All[Replayable] = {}

  fun get(key : Key) -> Value
    ! {Fail, ..Extra}

  fun put(key : Key, value : Value) -> Unit
    ! {Fail, ..Extra}

  once watch(key : Key) -> Value
    ! {Fail, ..Extra}
}
```

这里：

```text
Key、Value  associated Type
Fail        associated Effect
Extra       associated EffectRow
```

当前推荐直接使用 `type`、`effect`、`effects` 三种声明，而不是写：

```moonbit
type Fail : Effect
type Extra : EffectRow
```

这样读者不需要先判断 `type` 后面的 kind marker。

具体 effect 使用 named associated arguments：

```moonbit
pub(open) effect FileStore
  : Store[
      Key = Path,
      Value = Bytes,
      Fail = IoFailure,
      Extra = {Async},
    ] {}
```

泛型代码使用 projection：

```moonbit
fn![S : Store] load(
  store : cap S,
  key : S::Key,
) -> S::Value
  ! {store, S::Fail, ..S::Extra} {
  store.get(key)
}
```

常见 associated equality 直接写入 constraint argument：

```moonbit
fn[A]![S : Store[Value = A]] load_as(
  store : cap S,
  key : S::Key,
) -> A ! {store, S::Fail, ..S::Extra} {
  store.get(key)
}
```

两个 effect 参数可以共享关联项：

```moonbit
fn![
  Left : Store,
  Right : Store[
    Key = Left::Key,
    Value = Left::Value,
  ],
] copy_store(
  left : cap Left,
  right : cap Right,
  key : Left::Key,
) -> Unit
  ! {
    left,
    right,
    Left::Fail,
    Right::Fail,
    ..Left::Extra,
    ..Right::Extra,
  } {
  right.put(key, left.get(key))
}
```

复杂 equality、递归 constraint 与不适合写成 named argument 的关系仍可使用
`where`；简单 projection equality 不需要额外拉出一大段 clause。

## 7. Effect row algebra

### 7.1 Row construction

现有 row literal 和 open tail 保留：

```moonbit
! {}
! {Network}
! {app}
! {Network, app, ..E}
```

`..E` 在 effect binder 与 row literal 中保持同一种视觉含义：

```moonbit
fn![..E] ...
! {Log, ..E}
```

### 7.2 多 row 组合

一个 row literal 仍应最多有一个开放 tail。两个未知 row 的组合使用 row
formula：

```moonbit
fn[A, B, C]![..E1, ..E2] compose(
  first : (A) -> B ! E1,
  second : (B) -> C ! E2,
) -> (A) -> C ! (E1 | E2) {
  value => second(first(value))
}
```

当前运算符方向：

```text
E1 | E2   union
E1 & E2   intersection
E - X     difference
```

`|` 用于 row union，`+` 用于 constraint conjunction：

```moonbit
F : Reader[A] + Writer[A]
```

这样两个运算不会承担相同含义。

### 7.3 Row constraint

Row constraint 不提供 operation method，也不伪装成 ability。工作设计使用
compiler-known predicates：

```text
Has[Log]
Lacks[Blocking]
All[Replayable]
Only[UIEffect]
```

例子：

```moonbit
fn![
  ..E : Has[Log] + Lacks[Blocking] + All[Replayable],
] schedule(
  task : () -> Unit ! E,
) -> Task ! E {
  ...
}
```

这些 predicate 最终应进入统一 row constraint solver，而不是通过名称特判
几个库类型。

## 8. Operation 级多态

Operation 可以同时拥有普通参数和 effect 参数：

```moonbit
ability Traversable[A] {
  fun[B]![..E] traverse(
    f : (A) -> B ! E,
  ) -> Array[B] ! E
}
```

这里：

```text
[B]    operation 的普通类型参数
![..E] operation 的 effect row 参数
```

Polymorphic abort operation 仍然使用普通参数：

```moonbit
effect Error[E] {
  abort[A] raise(error : E) -> A
}
```

`A` 是调用点结果类型，不是 effect 或 row 参数。

## 9. Higher-kinded effect constructor

完整 effect family：

```moonbit
![F]
```

`Type -> Effect` constructor 使用 binder hole：

```moonbit
![Err[_] : Raise[_]]
```

概念含义：

```text
Err      : Type -> Effect
Err[T]   satisfies Raise[T] for every T
```

例子：

```moonbit
fn[A]![Err[_] : Raise[_]] fail(
  error : A,
) -> Never ! {Err[A]} {
  Err[A]::raise(error)
}
```

`_` 在 binder pattern 中表示 constructor parameter 位置，不是普通表达式
inference hole。Higher-kinded constraint 的量化与 coherence 仍需形式化。

## 10. Generic function value 与 handler generativity

普通函数类型继续保持简洁：

```moonbit
(A) -> B ! E
```

只有函数值自身是泛型时才显式写 `fn`：

```moonbit
mapper : fn[B]![..E](A) -> B ! E
```

Named handler 还需要比普通泛型更强的生成性，但它属于 handler application
的类型规则：

```moonbit
with handler as app
in {
  app.read()
}
```

每次 application 都创建新的 capability identity。Kernel HIR 必须保存
generativity，不能把 `app` 降成普通、不受约束的 lambda parameter。
Handler value 的序列化签名使用专用 `HandlerAction` 表示这一规则。

## 11. Capability capture

源码使用已经确定的 capability term 与 named row：

```moonbit
fn[A]![F : Reader[A]] make_reader(
  app : cap F,
) -> () -> A ! {app} {
  fn() { app.read() }
}
```

`{app}` 保留具体 handler identity。编译器从 term binder、闭包环境、聚合值
和调用结果推导传递 capture，并在 handler action、return 和 storage boundary
检查 escape。

Capture 信息写入 HIR、序列化接口摘要和诊断，源码不增加另一套 binder 或
函数类型后缀。Owner/capture safety 仍由编译器静态检查，不能因为 `cap`
看起来像普通库类型就退化成库约定。

## 12. Conformance 与 `impl`

Effect header 中的常见 conformance：

```moonbit
effect State[A] : Reader[A] + Writer[A] {}
```

可以视为局部、coherent `impl` 的糖。

为已有 effect 增加 ability 时，可复用普通 `impl` 外形，由 constraint kind
决定它是普通 trait impl 还是 effect ability impl：

```moonbit
impl[A] Reader[A] for LegacyState[A] {
  read = LegacyState::get
}
```

带 associated item：

```moonbit
impl Store for LegacyDatabase {
  type Key = String
  type Value = Record

  effect Fail = DatabaseError
  effects Extra = {Network}

  get = LegacyDatabase::fetch
  put = LegacyDatabase::save
}
```

开放独立 `impl` 前必须冻结：

- orphan/coherence；
- overlap；
- associated item 唯一性；
- operation adapter；
- mode compatibility；
- visibility。

第一阶段也可以只接受 effect header conformance，把独立 ability `impl`
延后；这不影响泛型使用方的语法。

## 13. 表面糖与 Core 表示

设计时必须区分方便书写的表面形式和不可丢失的核心信息：

| 表面形式 | Core/HIR 含义 |
|---|---|
| `[A]` | `TypeParamId` |
| `![F : Reader[A]]` | `EffectParamId` + ability evidence |
| `![..E]` | `RowParamId` |
| `app : cap F` | `CapabilityId` + family `F` + binder origin |
| `{F}` | `Anonymous(F)` |
| `{app}` | `Named(app, F)` |
| `F::read()` | anonymous operation selection |
| `app.read()` | named operation selection |
| `with h as app in ...` | fresh rank-2 handler application |
| `Read[app]` | diagnostic-only expansion |

这些类别在 serialization、trace、diagnostic、LSP hover 和 incremental query
中都必须使用不同 tag。

## 14. Parser-facing PEG 工作形状

以下只记录未来 parser 需要识别的 PEG 形状，不表示已经实现：

```peg
GenericClauses
  <- TypeParameters? EffectParameters?

TypeParameters
  <- '[' TypeParameter (',' TypeParameter)* ','? ']'

EffectParameters
  <- '!' '[' EffectParameter (',' EffectParameter)* ','? ']'

EffectParameter
  <- RowBinder RowConstraints?
   / EffectConstructorBinder AbilityConstraints?
   / EffectBinder AbilityConstraints?

RowBinder
  <- '..' Name

EffectBinder
  <- Name

EffectConstructorBinder
  <- Name '[' BinderHoles ']'

AbilityConstraints
  <- ':' AbilityConstraint ('+' AbilityConstraint)*

RowConstraints
  <- ':' RowConstraint ('+' RowConstraint)*
```

PEG 只保存语法，不负责：

- 判断 `Reader` 是否 ability；
- 检查 `F`、`E` 的 kind；
- 验证 associated argument；
- 求解 row formula；
- 建立 capability identity；
- 检查 capability capture 与 escape。

这些工作属于 resolver、kind checker、constraint solver 和后续静态分析。

## 15. 当前仍需细化

双列表已经是后续讨论基线；以下内容仍可改进：

1. `ability` 是否为最终关键词，还是使用更接近 trait 的单词；
2. `cap F` 与 `Cap[F]` 的最终外形；
3. associated effect/row 是否使用 `effect` / `effects`；
4. named associated argument 是否统一使用 `Store[Value = A]`；
5. row union 是否最终使用 `|`；
6. `Has`、`Lacks`、`All`、`Only` 是否为 compiler-known predicate；
7. 多 ability 同名 operation 的限定调用；
8. higher-kinded binder hole `_` 的作用域与诊断；
9. 独立 ability `impl` 是否进入第一阶段；
10. 显式 effect generic argument 在所有 call/method 位置的附着规则。

这些细节可以继续修改，但不能退回到把普通 type、effect family、effect row
和 capability identity 混成同一种泛型变量。
