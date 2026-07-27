# Cire 多态设计：从 kind 标注到 effect trait

本文专门回答四个问题：

1. Cire 到底有哪些不同种类的多态变量；
2. 旧的 `Fx : Effect` 为什么不够；
3. 匿名 effect 与具名 capability 怎样获得和普通 trait 一样强的约束；
4. Koka、Flix、Scala、Rust、Haskell 的相关设计分别能给 Cire 什么启发。

文中的“新设计”是当前工作规范。Parser 可以先无损保留这些语法；kind、
constraint、associated item 与 coherence 由后续 typed CST/HIR 阶段检查。

## 1. 旧设计的问题

旧文档主要使用：

```moonbit
fn[A, Fx : Effect, Eff : EffectRow] relay(
  app : Fx,
  body : () -> A ! {app, ..Eff},
) -> A ! {app, ..Eff} {
  body()
}
```

它确实区分了四个东西：

```text
A     普通类型变量
Fx    单个 effect family 变量
Eff   effect row 变量
app   具体 capability identity
```

但 `Fx : Effect` 只说明 `Fx` 的 kind，不说明它有什么 operation。因此下面的
核心代码无法检查：

```moonbit
fn[Fx : Effect](app : Fx) -> Int ! {app} {
  app.read() // 错误：Fx 没有声明 read
}
```

它也不能表达：

- `Fx` 必须同时提供 `read` 和 `write`；
- `read` 的结果类型由 `Fx` 决定；
- `Fx` 的失败 effect 或附加 effect row 由实现决定；
- `Fx` 的 operation 是 `fun`、`once` 还是 `ctl`；
- 两个 effect 参数的关联类型必须相同；
- 一个开放 row 不得包含 `Blocking`；
- 一个具名 capability 与匿名 effect 参数应满足同一套接口约束。

所以旧设计只有 **kinded effect polymorphism**，还没有
**constrained effect polymorphism**。前者可以转发未知 effect，后者才允许
泛型代码真正调用它的 operation。

## 2. 当前采用的分层

Cire 不再把 kind 与 trait 混成一件事：

| 层 | 例子 | 负责什么 |
|---|---|---|
| kind | `Type`、`Effect`、`EffectRow` | 变量属于哪一类 |
| constraint | `Eq`、`Reader[A]`、`Store` | 泛型代码能使用什么接口 |
| row algebra | `{Fx, app, ..Eff}` | 尚未处理的 effect/capability 集合 |
| identity | `app` | 请求哪一个具体 capability |
| capture/Region | 编译器推导 | capability 能否被保存、恢复或逃逸 |

普通 trait 约束普通类型；`effect trait` 约束 effect family。解析名称后，
constraint resolver 可以由 trait 的种类反推出 binder kind：

```moonbit
fn[A, T : Eq, Fx : Reader[A], Eff : EffectRow](...)
```

这里：

- `A` 默认为 `Type`；
- `T : Eq` 是普通 type trait 约束，因此 `T : Type`；
- `Fx : Reader[A]` 是 effect trait 约束，因此 `Fx : Effect`；
- `Eff : EffectRow` 是整行变量。

真正需要“任意单个 effect，但不调用 operation”时仍可写
`Fx : Effect`。它主要用于转发、存储编译器元数据或通用 handler
基础设施；业务 API 应优先使用有意义的 effect trait。

## 3. Effect trait

### 3.1 声明与组合

`effect trait` 的外形跟 MoonBit trait 保持一致：

```moonbit
pub(open) effect trait Reader[A] {
  fun read() -> A
}

pub(open) effect trait Writer[A] {
  fun write(value : A) -> Unit
}

pub(open) effect trait ReadWrite[A] : Reader[A] + Writer[A] {}
```

这里的 operation mode 是接口的一部分。`fun read`、`once read` 与
`ctl read` 不是可以静默互换的三个签名。

一个具体 effect 可以声明自己满足这些约束：

```moonbit
pub(open) effect State[A] : Reader[A] + Writer[A] {}
```

`State[A]` 继承两个 effect trait 的 operation signature。运行时 handler
仍然针对具体的 `State[A]` 实现 operation；effect trait 只提供静态
constraint evidence，不制造全局 handler。

第一阶段只允许在具体 effect 声明处建立 conformance。将来若开放独立
`impl`，必须同时冻结 orphan/coherence、operation adapter 和 visibility
规则，不能先放开重叠实例。

### 3.2 匿名 effect 多态

匿名调用通过 effect family 参数选择 handler：

```moonbit
fn[A, Fx : Reader[A]] read_any() -> A ! {Fx} {
  Fx::read()
}
```

多个约束使用和 MoonBit supertrait 相同的 `+`：

```moonbit
fn[A, Fx : Reader[A] + Writer[A]] replace(value : A) -> A ! {Fx} {
  let old = Fx::read()
  Fx::write(value)
  old
}
```

`Fx : Reader[A]` 不只是“贴标签”。它给函数体提供：

- `read` operation 的存在性；
- 参数与结果类型；
- operation 最大恢复 mode；
- supertrait；
- 后文的关联项。

### 3.3 具名 capability 多态

同一个 `Fx` 也可以作为 capability value 的类型：

```moonbit
fn[A, Fx : Reader[A], Eff : EffectRow] read_from(
  app : Fx,
  after : (A) -> Unit ! Eff,
) -> A ! {app, ..Eff} {
  let value = app.read()
  after(value)
  value
}
```

关键对称关系是：

```text
Fx::read()   请求任意满足 Fx 的匿名 handler    row 写 {Fx}
app.read()   请求参数 app 指定的 handler       row 写 {app}
```

两者使用同一个 `Reader[A]` constraint evidence。具名 capability 不再比
匿名 effect 弱，也不需要另外发明一套“capability interface”。

如果多个 effect trait 定义了同名 operation，点调用必须报歧义，并要求
使用限定调用。限定调用的最终拼写还需和普通 trait 一起冻结；CST/HIR 必须
记录实际选择的 trait，不能靠 operation 名字猜。

两个相同接口的 capability 仍是两个不同 identity：

```moonbit
fn[A : Eq, L : Reader[A], R : Reader[A]] compare_readers(
  left : L,
  right : R,
) -> Bool ! {left, right} {
  left.read() == right.read()
}
```

即使 `L` 与 `R` 最后都实例化为 `State[Int]`，`left` 与 `right` 也不能在
row、capture set 或 Region 中合并。

### 3.4 普通 trait 与 effect trait 同时出现

```moonbit
fn[
  A : Eq + Show,
  In : Reader[A],
  Out : Writer[A],
  Eff : EffectRow,
](
  input : In,
  output : Out,
  log : (String) -> Unit ! Eff,
) -> Bool ! {input, output, ..Eff} {
  let before = input.read()
  output.write(before)
  log(before.to_string())
  input.read() == before
}
```

这个例子同时量化：

1. 普通类型 `A`；
2. 两个 effect family `In`、`Out`；
3. 两个具名 capability identity `input`、`output`；
4. 一个开放 effect row `Eff`。

类型参数与 effect 参数都使用 trait 风格约束，但 resolver 给它们分配不同
kind 和不同的 HIR ID。

## 4. 关联类型、关联 effect 与关联 row

只支持 `Reader[A]` 还不够。复杂接口需要由具体 effect 决定一部分类型和
effect 信息：

```moonbit
pub(open) effect trait Store {
  type Key
  type Value
  type Failure : Effect
  type Extra : EffectRow = {}

  fun get(key : Self::Key) -> Self::Value
    ! {Self::Failure, ..Self::Extra}

  once watch(key : Self::Key) -> Self::Value
    ! {Self::Failure, ..Self::Extra}
}
```

这里的关联项有三种不同 kind：

```text
Self::Key      : Type
Self::Failure  : Effect
Self::Extra    : EffectRow
```

具体 effect 填写它们：

```moonbit
pub(open) effect FileStore : Store {
  type Key = Path
  type Value = Bytes
  type Failure = Error[IoError]
  type Extra = {Async}
}
```

泛型函数可以直接投影关联项：

```moonbit
fn[S : Store] load(
  store : S,
  key : S::Key,
) -> S::Value ! {store, S::Failure, ..S::Extra} {
  store.get(key)
}
```

普通类型相等、原子 effect 相等和 row 相等必须是三个 kind-correct
constraint。工作语法使用 `where`：

```moonbit
fn[A, S : Store](store : S, key : S::Key) -> A
  ! {store, S::Failure, ..S::Extra}
where S::Value == A {
  store.get(key)
}
```

这里的 `==` 是类型层等式，不是运行时比较。Parser 可以共享 token，但
typed CST 必须使用独立的 `EqualityConstraint` 节点。

## 5. Effect row 多态

最常见的 row 多态仍然保持简洁：

```moonbit
fn[A, B, Eff : EffectRow] map_effectful(
  xs : Array[A],
  f : (A) -> B ! Eff,
) -> Array[B] ! Eff
```

开放 row 可以同时包含匿名 effect 与具名 capability：

```moonbit
fn[A, Fx : Reader[A], Eff : EffectRow] relay(
  app : Fx,
  body : () -> A ! {Fx, app, ..Eff},
) -> A ! {Fx, app, ..Eff} {
  body()
}
```

`EffectRow` 是集合/row kind，不是 operation interface。因此 row 的强约束
不应伪装成普通 trait method。它需要独立的 row algebra：

```moonbit
where Eff excludes {Blocking}
where Eff includes {Log}
where Eff entries : Replayable
```

三条约束分别表示：

- row 中不能出现某些 effect；
- row 至少包含某些 effect；
- row 中每个原子 effect 都满足 marker effect trait。

这部分语义已经确定要有，但 `excludes/includes/entries` 是否采用以上最终
拼写仍是开放语法问题。实现时先建立规范化 row formula 与 constraint
solver，再冻结糖；不能只在 parser 里接受几个关键字。

## 6. 更多 Cire 多态例子

### 6.1 普通参数多态

```moonbit
fn[A](value : A) -> A {
  value
}
```

### 6.2 普通 trait 约束

```moonbit
fn[A : Eq](left : A, right : A) -> Bool {
  left == right
}
```

### 6.3 高阶 row 多态

```moonbit
fn[A, B, C, E1 : EffectRow, E2 : EffectRow] compose(
  first : (A) -> B ! E1,
  second : (B) -> C ! E2,
) -> (A) -> C ! {..E1, ..E2} {
  value => second(first(value))
}
```

这里出现两个 row tail 时，表面语法会被规范化为 row union。当前 parser
只实现单 tail；多 tail 是 solver 能力，不应靠 CST 顺序决定语义。

### 6.4 多个匿名 effect 参数

```moonbit
fn[
  A,
  Input : Reader[A],
  Output : Writer[A],
]() -> Unit ! {Input, Output} {
  Output::write(Input::read())
}
```

### 6.5 匿名 effect 加剩余 row

```moonbit
fn[A, Fx : Reader[A], Eff : EffectRow] read_then(
  next : (A) -> Unit ! Eff,
) -> Unit ! {Fx, ..Eff} {
  next(Fx::read())
}
```

### 6.6 具名 capability 加剩余 row

```moonbit
fn[A, Fx : Reader[A], Eff : EffectRow] read_named_then(
  app : Fx,
  next : (A) -> Unit ! Eff,
) -> Unit ! {app, ..Eff} {
  next(app.read())
}
```

### 6.7 同一 family 的两个实例

```moonbit
fn[A, Fx : Reader[A]] choose_left(
  left : Fx,
  right : Fx,
) -> A ! {left, right} {
  let _preview = right.read()
  left.read()
}
```

`left` 和 `right` 的静态 family 相同，但 identity 不同。

### 6.8 多约束 effect

```moonbit
fn[A, Fx : Reader[A] + Writer[A]] modify(
  app : Fx,
  f : (A) -> A,
) -> Unit ! {app} {
  app.write(f(app.read()))
}
```

### 6.9 关联失败 effect

```moonbit
fn[S : Store](store : S, key : S::Key) -> Option[S::Value]
  ! {store, S::Failure, ..S::Extra} {
  Some(store.get(key))
}
```

### 6.10 Operation 自身的普通多态

```moonbit
pub(open) effect Error[E] {
  abort[A] raise(error : E) -> A
}
```

这里的 `A` 是 operation result 的普通参数多态。它既不是 effect family
变量，也不是 row 变量。

### 6.11 Effect constructor 的普通参数

```moonbit
pub(open) effect Read[A] : Reader[A] {}
```

这里 `Read : Type -> Effect`。`A` 是 effect constructor 的普通类型参数；
`Read` 自身不是 `Effect`，`Read[Int]` 才是完整的 `Effect`。

### 6.12 Named handler 的生成式多态

```moonbit
fn run() -> Int {
  with handler Read[Int] {
    fun read() => 42
  } as app {
    read_from(app, value => ())
  }
}
```

`app` 的 identity 每次安装 handler 都是 fresh 的。第一阶段由
`with ... as app` 建立编译器内部 rank-2 boundary，不把 fresh identity
错误地做普通 let-generalization。是否开放用户可写的 `forall`/rank-N
function type，仍需单独设计。

### 6.13 Trait alias 式组合

```moonbit
pub(open) effect trait UiModel[A]
  : Reader[A] + Writer[A] + Notify[A] {}

fn[A, Fx : UiModel[A]] render(model : Fx) -> View ! {model} {
  Text(model.read().to_string())
}
```

### 6.14 Marker effect trait

```moonbit
pub(open) effect trait Replayable {}

pub(open) effect Choice : Replayable {
  ctl[A] choose(values : Array[A]) -> A
}
```

Marker constraint 可供 capture/replay checker 使用，但它不能覆盖核心静态
规则。是否 replay-safe 最终仍要由 operation mode、capture set、Region 与
类型组成共同验证，不能仅信任用户随意写的空 marker。

## 7. 其它语言如何处理多种多态变量

以下例子只保留与 Cire 设计直接相关的部分。

### 7.1 MoonBit：类型参数加 trait constraint

MoonBit 使用方括号与 `T : Trait`：

```moonbit
fn[X : Eq] contains(xs : Array[X], elem : X) -> Bool {
  ...
}
```

trait 支持 supertrait，generic body 可以利用约束调用 method。Cire 采用同样
外形，把普通 `trait` 与 `effect trait` 分成两个 constraint kind。

资料：[MoonBit Method and Trait](https://docs.moonbitlang.com/en/latest/language/methods.html)

### 7.2 Koka：类型、effect atom、effect row、scope

Koka 的 effect-polymorphic `map` 把普通类型变量与 effect row 变量放在同一
签名中：

```koka
fun map(xs : list<a>, f : a -> e b) : e list<b>
```

Koka 的内部 kind 还区分 value type、effect atom、effect row、heap 与
scope。Named/scoped handler 用 first-class name 和 rank-2 scope 防止
capability 逃逸。这证明“普通类型变量、单 effect、整行 effect、scope”
不能在 HIR 里只用一种 ID。

资料：[Koka book](https://koka-lang.github.io/koka/doc/book.html)、
[First-class Named Effect Handlers](https://www.microsoft.com/en-us/research/publication/first-class-named-effect-handlers/)

### 7.3 Flix：effect formula 与 associated effect

Flix 的 `map` 对 effect variable `ef` 多态：

```flix
def map(f: a -> b \ ef, l: List[a]): List[b] \ ef
```

两个回调可以合并不同 effect variable：

```flix
def >>(f: a -> b \ ef1, g: b -> c \ ef2):
  a -> c \ (ef1 + ef2)
```

Flix 还支持 union、intersection、difference 与 effect exclusion，例如
`ef - Block`。更重要的是 trait 可以声明 kind 为 `Eff` 的 associated
effect，让每个 instance 决定自己的附加 effect。

资料：[Flix Effect Polymorphism](https://doc.flix.dev/effect-polymorphism.html)、
[Associated Effects](https://doc.flix.dev/associated-effects.html)、
[Associated Types](https://doc.flix.dev/associated-types.html)

### 7.4 Scala 3 capture checking：capture-set variable 与 capability member

Scala capture checking 使用 `X^` 表示 capture-set variable：

```scala
class Source[X^]:
  private var listeners: Set[Listener^{X}]
```

它可以用具体 capability 和另一个 set variable 实例化：

```scala
val src = Source[{async1, X}]
```

capture set 还可以成为关联成员：

```scala
trait Reactor:
  type Cap^
  def onEvent(h: Event ->{this.Cap} Unit): Unit
```

这对 Cire 的启发是：`Eff`、具体 identity `app` 与将来的 capture-set
variable 必须能同时存在；关联 row/capture 也应使用 path projection，而
不是把 identity 编码进字符串或普通类型名。

资料：[Scala Capability Polymorphism](https://docs.scala-lang.org/scala3/reference/experimental/capture-checking/polymorphism.html)

### 7.5 Rust：lifetime、type、const parameter 与 trait bounds

Rust 的一个泛型列表可以包含 lifetime、type 与 const parameter：

```rust
struct Ref<'a, T> where T: 'a {
    r: &'a T
}

struct InnerArray<T, const N: usize>([T; N]);
```

`T : Trait` 不只做分类：generic body 可以调用 trait method、访问 associated
item，并继续把该约束传给别的泛型 API。这正是 Cire 的 effect parameter
需要从 `Fx : Effect` 升级到 `Fx : Reader[A]` 的原因。

资料：[Rust Generic Parameters](https://doc.rust-lang.org/reference/items/generics.html)、
[Trait and Lifetime Bounds](https://doc.rust-lang.org/stable/reference/trait-bounds.html)

### 7.6 Haskell/GHC：kind variable、Constraint 与 equality

GHC 明确区分 `Type`、用户 kind 与 `Constraint`。Class constraint、
equality constraint 和 constraint tuple 都属于 `Constraint`；PolyKinds
还能量化 kind variable。关联 type family 可以用 equality constraint
联系两个多态参数。

这提醒 Cire：

- `Effect`、`EffectRow` 是 kind，不是 trait；
- `Reader[A]` 是作用于 `Effect` 的 constraint；
- `S::Value == A` 是 constraint，不是运行时表达式；
- kind checking 必须先于 constraint solving。

资料：[GHC Constraint kind](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/constraint_kind.html)、
[Kind polymorphism](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/poly_kinds.html)、
[Equality constraints](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/equality_constraints.html)

## 8. 为什么不直接照抄其中一种语言

- Koka 的 row inference 很强，但 Cire 还要在 row 中保存具体 capability
  identity，并与 Owner/Region 相连。
- Flix 的 effect formula 很适合 row constraint，但它的 effect declaration
  与 Cire 的 named handler、恢复 mode 不同。
- Scala capture set 精确表达“值捕获谁”，但 capture set 不能替代代数效应
  operation 与 handler elimination。
- Rust/Haskell 的 constraint 系统成熟，但 Cire 需要为 `once/ctl` 与
  generative handler 增加控制流和 Region 规则。

所以 Cire 采用四层组合：

```text
MoonBit-like surface generic/trait syntax
        +
effect trait operation contract
        +
row algebra and associated effect rows
        +
compiler-checked capability identity/capture/Region
```

## 9. Parser 与编译器实现顺序

Parser 使用手写 PEG。与多态相关的首批规则是：

```peg
GenericParam
  <- Name (':' Constraint ('+' Constraint)*)?

EffectTraitDeclaration
  <- Visibility? 'effect' 'trait' Name TypeParameterList?
     (':' Constraint ('+' Constraint)*)?
     EffectTraitBody

EffectDeclaration
  <- Visibility? 'effect' Name TypeParameterList?
     (':' Constraint ('+' Constraint)*)?
     EffectBody
```

PEG 只决定 CST 形状，不根据首字母猜 kind。后续阶段按以下顺序工作：

1. name resolution 区分普通 trait、effect trait 与 compiler-known kind；
2. kind inference/checking 给 binder 分配 `TypeParamId`、`EffectParamId`、
   `RowParamId`；
3. constraint solver 建立 supertrait、associated item 与 equality evidence；
4. operation resolution 选择匿名 family 或具体 capability identity；
5. row solver 做 normalization、union、subtraction、contains/lacks；
6. handler elaboration 消除已处理 effect；
7. capture/Region checker 检查 fresh identity、continuation 与逃逸；
8. LSP 直接复用以上 query 和结构化 diagnostic。

每一步都必须输出可序列化 artifact/trace。诊断至少要区分：

- kind 错误：把 `EffectRow` 用作普通 type；
- constraint 缺失：`Fx` 没有 `Reader[A]`；
- operation 歧义：多个 effect trait 提供同名 operation；
- associated item kind 不匹配；
- row constraint 不满足；
- named capability identity 不在作用域或越过 Region；
- handler mode 不满足 trait operation contract。

## 10. 尚需继续讨论的语法

核心分层已经确定，但以下表面拼写不能草率冻结：

1. 多 trait 同名 operation 的限定调用采用 `Reader::read(app)`、
   `app.(Reader::read)()` 还是另一种 MoonBit-compatible 形式；
2. associated item equality 最终使用 `==`、`~` 还是
   `where S::Value : A` 之外的专用 token；
3. row constraint 使用 `includes/excludes/entries`，还是提供
   `+`、`&`、`-` 的完整 formula syntax；
4. 一个 concrete effect 的 trait conformance 只写在 effect header，
   还是开放 MoonBit-like 独立 `impl`；
5. 用户可写的 rank-N generic function type 是否必要；第一阶段只有
   `with ... as app` 的 compiler-generated rank-2 boundary；
6. existential capability package 怎样写，才能把 identity 与 Region
   一起保存而不伪装成普通 trait object；
7. effect trait associated capability member 是否有必要，还是由普通
   value member 加 capture/Region projection 表达。

这些问题可以分别原型验证；不能因为 parser 已经能吃下某种 token sequence
就宣称其类型语义已经决定。
