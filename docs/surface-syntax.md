# Cire v1 表面语法与唯一 elaboration 规范

## 1. 状态与目标

> **Profile:** [`Cire-v1.0`](spec-status.md)
>
> 本文是 token、lossless CST、表面 scope、grammar 以及 Surface 到
> evidence-indexed Kernel HIR elaboration 的唯一规范来源；完整、实现无关的
> PEG 收录在 Appendix A。typed Core、静态 judgment、wire 与 runtime protocol
> 从 Kernel 边界起只由形式化文档定义。

本文中的 reachable production 全部属于 profile baseline。明确排除的 spelling
只可进入 recovery CST 并产生注册诊断；不存在“工作语法”或由实现自行决定的
开放分支。尚未进入 v1 的能力列在 §11，不能被 parser、标准库或 backend 偶然实现。

Cire 的基本外观沿用 MoonBit 的熟悉形状，但下列规则属于 Cire 本身：

- 泛型参数和泛型实参使用方括号；
- 函数、方法、ADT、模式匹配、labelled argument、包限定名尽量沿用 MoonBit 的形状；
- block 是表达式，最后一个表达式是结果；
- Cire 为 effect、handler、continuation、named capability、ordinary trait、
  nominal data 与 package identity 增加必要且唯一的语法；
- 所有求值严格从左到右，每个 source expression 恰好求值一次；
- 所有具名 `def`（public/private、method、trait/default/impl/extension、`const def`）
  都显式写完整 generic、参数、结果与 effect row；纯函数写 `! {}`。

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
) -> Array[B] ! {} {
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
| ordinary parameter | `key : Key`（可按位置或 `key = expr` 传入） |
| destructuring parameter | `pattern : Type`（只可按位置传入） |
| labelled argument | `key = expr`（没有 punning） |
| 结构化 cleanup | sealed `with @control::finally(cleanup) in body` |

具名函数的 result 与 row 都不能省略：`def name() -> Unit ! {} { ... }`。
匿名函数值写 `fn() { ... }`。Lambda parameter 使用独立 grammar，既可推导
`fn(value) { ... }`，也可显式写 `fn(value : Int) { ... }`；它不复用要求
类型 annotation 的 declaration `ParamList`，也不会引入单独的 procedure
语法。

`~`、surface `cap`、`defer` 与 generic `discontinue` 都是保留但不可达的
v1 spelling，分别产生稳定 profile diagnostic。它们不是旧写法的 alias。

### 2.1 Primitive、literal 与 conversion

Source builtin 集合精确为：

```text
Unit, Never, Bool
Int8, Int16, Int, Int64
UInt8, UInt16, UInt, UInt64
Float32, Float
Char, String, Bytes
```

`Int`/`UInt` 固定为 32-bit，`Float` 固定为 IEEE binary64；它们不随 target
或 pointer width 改变。v1 没有 `Byte`、`usize`/`isize`、raw pointer、地址值、
builtin SIMD、null 或 truthiness。
Wasm boundary 上的 narrow integer必须 canonical sign/zero extend，`Bool`只允许
0/1，`Char`必须是 non-surrogate Unicode scalar。

Numeric suffix 精确为 `i8/i16/i32/i64`、`u8/u16/u32/u64` 与 `f32/f64`。
unsuffixed literal 先由 expected type约束，仍未解时在 local-generalization 前
分别 default 为 `Int` 与 `Float`。literal 是数学 magnitude；unary minus 与
紧邻的 literal 作为一个 signed constant 做 range check，因此 minimum signed
value 可写。Float literal pattern 不可达。

已经 typed 的 numeric value 不做 implicit conversion，也没有 general `as`：

```cire
let wide = Int64::from(small)
let maybe = UInt8::try_from(value)
let low = UInt8::wrapping_from(value)
let rounded = Float::from_int(value)
let truncated = Int::try_from_float(value)
```

ordinary integer `+ - * / %`、signed negation/abs 与 shift 会对 overflow、
division-by-zero、冻结的 signed-min edge 或 out-of-range shift 进入 private defect
path。checked/wrapping/saturating variant 只能通过 exact named operation 选择。
Float 使用固定 round-to-nearest-ties-to-even；没有 ambient fast-math、implicit FMA、
flush-to-zero 或 Float `%`。NaN 在 result/import/const/from-bits boundary canonicalize；
`Float32/Float` 不提供 `Eq`、`Ord`、`Hash`，需要 total order 时使用标准
`TotalFloat32`/`TotalFloat` wrapper；wrapper 使用 canonical bits/IEEE total order，
区分 signed zero并 coherent 实现 `Eq/Ord/Hash`。`to_bits/from_bits` 只能通过
exact named operation 显式调用。

这些规则的 privileged checks 在 Kernel 中记录 `MayTrap` 与 origin；它们不是
effect-row entry，也不能被 `Raise` handler 捕获。trap 前的 suffix/Owner retirement
由形式化中的 `DefectTransition` 负责。

### 2.2 Char、String、Bytes 与 interpolation

`Char` 是一个 Unicode scalar。`String` 是 immutable、valid UTF-8 scalar sequence；
不隐式 normalize，也没有 integer indexing、observable capacity/address/sharing。
`Bytes` 是 immutable `UInt8` sequence，没有 text claim。borrowed/zero-copy buffer
必须使用另一个 Owner-bound nominal resource type。

Byte literal 写作 `b"..."`，只接受 printable ASCII 与固定 byte escape（含
`\xNN`）；raw non-ASCII、Unicode escape、interpolation 与 line break 稳定拒绝。

String interpolation 只使用 `${expr}`，literal dollar 写 `\$`：

```cire
let line = "${name}: ${count}"
```

lexer 在 string/interpolation mode 中追踪 nested braces。Hole 严格从左到右、
各求值一次；每个 hole 在 Resolve/Kind 阶段绑定 exact `@core::Show` evidence。
Hole 自身可有 effect，但 `Show` 必须满足 `ProtocolPure`，formatting 不另加 effect。
functions、handlers、capabilities、Owners、resumptions、Task/Resource 与 `Bytes`
没有 implicit `Show`。

Normalization 将 interpolation 唯一展开为 `StructuralIntrinsicRegistryV1` 中的
sealed `BuildString` Kernel form，而不是 repeated concatenation、dynamic method
lookup、hidden global state 或 `defer`。semantic String/Char/Bytes const payload
在 interface 中用 scalar/byte encoding 表示，绝不因 artifact 的 NFC canonicalization
改变程序值。

### 2.3 Local inference 与 declaration boundary

<a id="rule-fnd-local-inference-boundary"></a>
<a id="rule-fnd-explicit-named-rows"></a>

Local checker 是 bidirectional rank-1。immutable local `let` 可以 generalize
`Type`、`EffectRow`、coherent principal ordinary-trait constraints 与一个完整 atomic
hidden `FnContract` binder；不能只 generalize contract 的 row projection。

Generalization 必须同时满足：initializer 是 non-expansive value、construction
pure、authority capture empty、closure environment stable/duplicable、
`ManyCallSafe`、没有 reachable mutable cell/borrow/resumption/claim/non-replayable
cleanup、没有 generative identity/Owner/clock quantification，且 constraints closed。
否则 meta 保持 weak monomorphic。构造 effectful lambda 可以是 pure construction；
执行 effectful initializer 不可以 generalize。

没有 higher-rank/impredicative inference、polymorphic recursion、global API inference、
numeric typeclass defaulting 或 implicit conversion insertion。所有 public interface
必须无 unsolved meta，并序列化完整 checked contract。

显式 `fn[...] (...) -> ...` 是 local rank-1 scheme annotation，不是任意 `Type` position的
first-class higher-rank value。它只允许作为 immutable simple-name `let` 的完整 type annotation，且
initializer必须是同一 binder shape的 generic `fn[...]`；generic lambda同样只允许作为该 initializer。
Field、parameter、result、type argument、container element、alias target、mutable let、capture或 return
position中的 `GenericFunctionType`，以及把 generic lambda直接作为 argument/store/return，都在
CanonicalSurfaceV1前确定性拒绝。Ordinary non-generic function type/lambda不受此限制。Accepted local
scheme唯一 lowering为一个 `LocalFunctionDeclarationV3`；每次 local use fresh实例化其完整 scheme，
所以没有递归 scheme wire、rank-2 parameter或多态值逃逸。
为使 enclosing generic requirement/evidence 可用唯一 `(declaration_slot,application_slot)` 定位，
每个 source `LambdaExpr`（generic 或 ordinary）都在 normalized HIR 中恰好 lift一次到最近的 local/evidence
boundary：ordinary callable body进入 enclosing `FunctionContractV3.local_declarations`；trait method
signature default expression则进入该 signature的 `TraitDefaultPrologueProgramV1.local_declarations`。
原 expression使用 `LocalFunctionRefV2` 及其 exact closure environment。
Ordinary lambda仍是 monomorphic value，不因 lifting获得 scheme；source lambda不嵌一个 slot-0重置的
nested V3 root。两种 boundary都固定 root slot 0、按同一 lexical preorder分配 local slots，并对
requirement scope/application/trait-use做 complete coverage。

### 2.4 Nominal data、construction、pattern 与 derive

<a id="rule-fnd-nominal-data"></a>
<a id="rule-fnd-pattern-matrix"></a>
<a id="rule-fnd-postfix-derive"></a>

`struct`、`enum`、`newtype` 与 `opaque type` 创建 nominal identity；`type` alias
transparent，不能拥有 constructor/impl/orphan identity，alias expansion graph 必须
acyclic。v1 没有 anonymous structural record type。

```cire
pub struct Point {
  pub x : Int
  pub y : Int = 0
} derive(Eq, Hash)

newtype UserId { value : UInt64 }
pub opaque type Token = Bytes
type Pair[A] = (A, A)
```

`derive(...)` 精确位于 declaration closing brace 之后；括号内是无重复的 exact
ordinary trait path list，且只允许在 `struct | enum | newtype` closing brace后出现；
`opaque type` 与 transparent `type` alias的 derive set固定为空，不能借 artifact field伪造。
它只生成 sealed compiler impl，并以 declaration field/
variant order 访问 stored values。handwritten 与 derived impl 重叠即拒绝；authority/
runtime-handle field 不可 derive。

Record literal/update/pattern 总是 type-directed 到一个 exact nominal constructor。
Field expression 按 source order 各求值一次。缺 field 只有在 declaration 给出 pure
const default 时合法；default 不能读取 `self`、其它 field、runtime state、capability/
Owner 或 `Default` trait。Functional update 最多有一个且必须以 final `..base`
结束；explicit fields 先求值，再求值 base 一次，省略字段从 base projection，绝不
重新应用 default。Enum variant 不可 update。

Field default在 enclosing data binders下 typecheck并由 ConstSafe evaluator求值；wire把得到的
`ConstValueV1`直接内嵌在 `StoredFieldV1`。Surface不合成 hidden named const、identity或 bare hash；
generic field default必须是对所有 instantiation都相同的 parametric const constructor。
Const value在 expected type下递归 exact-check scalar/tuple/array/Option/Result/nominal variant 与全部 field；
missing/extra/reordered field或 wrong variant/type不是可 canonical value。Opaque representation没有 const wire branch，
因而 opaque-typed const/default不进入 v1 serialized artifact；runtime owner-package construction不受此限制。

Record-shaped enum variant 的 stored field 与 struct/newtype field 使用同一个
`FieldDecl`：每个 field 可 source-spell package/public visibility 与 pure const default，
construction 的 missing-field/default 与 external visibility rule完全相同。Tuple variant
只有 positional element type，不获得 field visibility/default。

Visibility 默认 package-private。export type 不自动 export fields；external literal/
update 要求全部 stored fields public。External pattern只能提及 public field，并在
存在 hidden field 时写 `..`。public enum variant set closed，添加 variant 是 breaking。
Public alias/callable/const signature 不得透出 package-private type 或 evidence；
`opaque type` 只暴露 public nominal identity，representation 留在 owner package。
Source-facing outward gate还覆盖每个 public data/trait/ability/effect 的 TypeHead requirements，
externally visible stored field/tuple-variant element，trait associated constraint/default/method signature，ability
associated item/operation，effect conformance/declared operation，以及 importer-visible impl header与 associated/method
signature fact。它们都不得引用 private identity；hidden field或 executable default/body内部可使用
Formal package support closure，但 support身份绝不能使 source-visible occurrence变为合法。

Pattern 是 pure、type-directed，不能调用 trait/effect。refutable pattern 只允许在
`match`；`let`、named/anonymous parameter、`for`、handler operation/return clause
都要求 irrefutable。Alias spelling 保留 existing `pattern as name`，不采用 `name @ pattern`。
String pattern只允许 non-interpolating literal；`${expr}` 不得把 arbitrary
expression 带入 pattern。
Or-pattern alternatives 必须绑定同名、同 type、同 quantity 的 binder。每个 `match`
运行 constructor-matrix usefulness/exhaustiveness；guard 不贡献 coverage；缺 arm 是
`non-exhaustive-match`，先前 unguarded arm 覆盖的 arm 是 mandatory
`unreachable-pattern` warning。

### 2.5 Ordinary trait、UFCS 与 extension

<a id="rule-fnd-trait-coherence"></a>
<a id="rule-fnd-method-resolution"></a>

Ordinary trait 是 coherent static evidence，不是 ability/effect/handler/capability、
cleanup hook 或 error channel。v1 只支持 zero-arity associated `Type` item；没有
GAT、implicit trait object、specialization、negative impl、`Drop` 或 `Try`。
v1 同样没有 ordinary trait 或 ability inheritance/supertrait clause，也不生成隐式
supertrait entailment或 dictionary edge；`trait T : U { ... }` 与
`ability A : B { ... }` 都不进入 accepted grammar。共享 ordinary requirement必须在使用点的
ordinary trait constraint或 zero-arity associated Type constraint中显式写出；effect 对 ability
的实现关系只由 §4.5 的 exact effect header conformance产生，不能借作 declaration inheritance。
可用 dot 调用的 trait/inherent/extension method 的第一个 parameter 必须精确为
`self : Self`（extension 的 `Self` 是其已解析 receiver type）；不绑定
`self` 的 associated function 只能通过 qualification 调用，不进入 dot candidate set。
Bodyless trait method只产生 Formal `TraitMethodSignatureV1`；它没有可执行 computation或伪造的
`FunctionContractV3`。有 default body 时另外产生 nullable `default_body` callable edge，具体 impl body
仍由 method ordinal指向自己的 callable。Trait 的 `Self` 与每个 associated Type按 declaration order
分配 hidden Type binder，constraint/default/method signature都引用这些 slots；impl再以 target与
associated binding exact substitution。每个 trait method lexical scope还唯一产生 Formal
`OwningTraitSelfV1` evidence root，精确表达 `Self` 实现当前 trait、当前 trait arguments与全部
`Self::Associated` hidden slots；所以 default/required signature内的 sibling method call与
associated-Type bound可用，而不需要 source-spelled supertrait。具体 impl必须用自身 exact
`ImplEvidenceV1` discharge这个 synthetic root，不能把它作为 open requirement外泄。
Trait method signature可以声明 ordinary parameter default，
其 signature-level `TraitDefaultPrologueProgramV1` 与 body分离，并完整携带 default computation可达的
callable dependency、local/lambda、application、closure、requirement scope与 trait-method-use evidence；impl method不能重写
default。三种 body role、default program
与所有 hidden projection都必须分别闭合。

```cire
pub(open) trait Renderable {
  type Output
  def render(self : Self) -> Self::Output ! {}
}

impl Renderable for Point {
  type Output = String
  def render(self : Point) -> String ! {} { ... }
}

pub extend def[A] joined(
  self : Array[A],
  separator : String,
) -> String ! {} { ... }
```

`pub trait` 只允许 owner package impl；`pub(open) trait` 可由 downstream impl。
transparent alias expansion 后，impl 所在 package 必须拥有 exact trait identity 或
target outermost nominal constructor。两个 header 只要 first-order unification 可使
trait arguments 与 normalized target 相同就 overlap；constraints、result、effect、
specificity、proximity 与 import order都不能消歧。

每个 impl artifact保存一个与 source header exact相等的 normalized `TraitGoalV1`，不能只保存
trait short name/target而丢 arguments或 associated equality。Header 中 associated equality是 unique/in-range的
partial map，每项 ordinal/name/value必须与最终 total associated binding exact equal；该检查在 coherence
header digest/evidence identity前完成。Associated Type与 method按 trait ordinal
形成 total vector：唯一 explicit item优先，否则使用 declaration default；两者皆无即缺 required item
并拒绝。Unknown/duplicate/extra item，或 impl method重写 trait parameter default，同样在 coherence
publication前拒绝。每个 completed associated Type还必须满足 declaration的全部 ordinary-trait
constraints：先使用 impl的 complete generic entailment closure，否则从 exact locked package graph选唯一
coherent impl evidence；current-package private proof必须被拉入 support closure，proof dependency cycle或缺失均拒绝。

`receiver.name(args)` 先合成 receiver type。Named capability operation 保持既有
dispatch；否则 accessible inherent method 优先。没有 inherent 时，in-scope trait
methods 与显式 enabled extensions 合成一个 candidate set，必须恰好一个。没有
autoderef/autoref/implicit conversion 或 expected-result/effect tie-break。

UFCS/qualification 是确定 escape hatch：

```cire
Point::translate(point, dx, dy)
<A as @json::View>::render(value)
@text::joined(words, separator = ", ")
```

Dependency extension 只由 exact import 激活：

```cire
use @text::joined
use @debug::joined as debug_joined
```

没有 wildcard activation、package scan、import-scoped impl 或 implicit re-export。
Extension仍是 ordinary free-function identity，不产生 trait evidence或 privileged access。
Primitive operator 与 literal typing 是 closed；trait/extension 不能 hijack 它们。
Interpolation只认 exact locked-core `Show` evidence，不认同名 method。

### 2.6 Place、structural control 与 sealed finally

<a id="rule-fnd-control-structural"></a>

`let` immutable；`let mut` 引入一个 monomorphic local place。Assignment 先将
base/index selectors 从左到右各求值一次，再 RHS 一次，再 write，结果为 Unit。
Field place必须 rooted in visible mutable local；immutable array通过 sealed value-update
projection 写回该 local。没有 implicit reference、auto-box、hidden continuation snapshot
或 user `MutableIndex` dispatch。共享 identity mutation 必须显式使用 Owner-managed cell
或 named capability operation。

Non-escaping closure 可借 mutable local；escaping、Owner-stored、suspended 或 multi-shot
reachable closure 不可借。one-shot boundary要求 unique continuation拥有 place且无 alias；
`ctl` boundary捕获 live mutable place稳定拒绝。

`if`、exhaustive `match` 与 `loop` 是 structural Core boundary；`while`、`for` 是
唯一 derived forms。`return`/`break`/`continue` 绑定 fresh private lexical identity、
transfer point type 为 `Never`，用户 handler不能 intercept。`loop` join 所有 reachable
break value；无 reachable break时为 Never。`while` body 为 Unit并返回 Unit。`for`
将 source 求值一次，使用 §2.7 的 pure state-threaded iterator；binder irrefutable，
body usage乘 `Many`。

通用 `defer` 不可达。唯一 general scoped cleanup source form 是：

```cire
with @control::finally(cleanup) in body
```

它只在 exact structural intrinsic identity + `FinalizerSafe`/Replayable evidence下展开，
把 cleanup append 到既有 suffix ledger。Cleanup 必须 NoSuspend、全路径 Returns Unit、
无 outward Abort/Transfer，并在 finalization phase满足 Owner/capture/one-shot责任；typed
failure必须在 cleanup 内处理。它不是 destructor、ordinary trait 或第二套 error model。

### 2.7 Package、const、ordinary protocol 与 Component boundary

Package 是 resolution、separate checking 与 language API hash 单位；file不隐式创建
module。`@alias::path` 通过 `cire.toml` 与 canonical `cire.lock.json` 解析到 exact
`PackageInstanceId`（source/version/checksum/profile/features/dependency instances）。
没有 dependency short-name search、wildcard import 或 implicit module。两个 locked
version的同名 declaration仍是不同 nominal type。

Target-independent `CireLanguageInterfaceV1`、target/runtime-specific
`CireLinkAbiV1` 与 manifest-selected `CireComponentInterfaceV1` 是三个独立
artifact/hash，不得相互充当或因 SemVer 相同而跳过 recheck。Public
declaration/remove/rename/label 变化、扩大 row/suspension/authority、新 generic
requirement、public data/variant shape、open-trait required item、operation 或 public
const value 变化均是 breaking；收窄 requirement 可经重新 typecheck 判为
source-compatible，但 exact hash 仍必须改变。

`pub` 只导出 Cire API；`pub(open)` 只适用于 trait/ability/effect。Component export/
host import不增加 source keyword：manifest 可选择 exact zero-generic callable、public
zero-binder data mapping root或 public Owner-backed opaque resource；host import则产生唯一
ordinary-package-resolver-hidden adapter与 sealed host effect/capability row。Transparent alias在 mapping前展开且不能作为
manifest data identity，ordinary opaque只能走 resource item。第一稳定跨语言边界是 synchronous Component
Model canonical ABI、UTF-8、memory32；async/stream只经 explicit Owner-backed resource。

每个 manifest有一个不与 lockfile dependency alias冲突的 source alias；每个 host import显式提供
nonempty、可词法化且 injective 的 `source_binding`，不能从 WIT kebab-case猜 Cire spelling。
`@manifest::source_binding(args)` 在 local manifest Value namespace唯一解析 generated adapter；同一
`@manifest::source_binding` 在 Effect namespace唯一指其 sealed host Effect，因此 enclosing named def
仍显式把该 entry写进 `! row`。两者只对 owning package source可见，不是 ordinary package export、
extension或 UFCS candidate。Component export可选择 public或 package-private exact callable；选择本身不改变
Cire visibility。其 closed row只可含同一 manifest的 generated Host Effects，outer sealed component adapter
逐一 discharge到对应 WIT import并保留 `HostObservable` summary；其它 effect/open tail拒绝。

```cire
const answer : Int = 42
const def twice(value : Int) -> Int ! {} { value * 2 }
```

`const` 在 build time求值；只有 `const def` 可被 const evaluator调用。`const def`
仍显式写 `! {}`，并额外证明 `ConstSafe`。v1 const subset含 literal/immutable ADT/
array、projection、exhaustive match/if/let、primitive op与 ConstSafe call；拒绝 mutation、
unbounded loop、handler/effect/temporal/Owner/capability/resumption/Task/Resource/FFI。
Termination只接受 acyclic call graph或对 syntactically smaller ADT field的 direct
structural recursion。没有 top-level dynamic initializer或 user Wasm start hook。

`PartialEq`、`Eq`、`PartialOrd`、`Ord`、`Hash`、`Show`、`Iterator` 与
`IntoIterator` 是 ordinary traits；标准 method满足 `ProtocolPure`，不能 handle effect。
Iterator 唯一是 pure state-threaded：

```cire
pub enum IterStep[A, S] { Done, Yield(A, S) }

pub(open) trait Iterator {
  type Item
  def next(self : Self) -> IterStep[Self::Item, Self] ! {}
}

pub(open) trait IntoIterator {
  type Item
  type IntoIter : Iterator[Item = Self::Item]
  def into_iter(self : Self) -> Self::IntoIter ! {}
}
```

Iterator state必须是 stable/shareable ordinary data。
Task/Source/Event/Signal/subscription/host stream/Owner-backed cursor不伪装为这个
ordinary iterator。
Component-safe value只含 closed monomorphic scalar、String、Bytes（映射
`list<u8>`）、immutable list/tuple/record、
closed variant、Option、Result；capability、Owner、resumption、handler、closure、temporal
value、borrowed view、opaque layout、open generic/trait/row不能直接跨 boundary。Host
import保留 generated ability row与 `HostObservable`，borrowed input不能 escape/suspend/store；
synchronous export为每次 call创建 child Owner并在每个 language terminal path关闭。

## 3. Effect 声明

### 3.1 Operation mode

**已决定**

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

当前 profile 不允许 operation-own effect constructor、effect atom、row generic或 ordinary-trait
constraint；operation generic列表只能是上述无 constraint的 `[A, ...]` 普通 Type parameters。
因此早期实验形
`ctl[A]![..E] run(...)` 不进入 accepted grammar/HIR，也不产生一个无 wire image的
`OperationSignatureV2`。Higher-order operation仍可接收具有 concrete closed row的 callback；要求
row-polymorphic callback的 API必须改写为 ordinary named function/trait method boundary。

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

- `! {}` 是空 row；每个具名 `def` 都必须显式写它，省略时报
  `named-function-effect-row-required`；
- `..E` 是 open row tail；
- row 的顺序不影响类型相等性；
- formatter 可以采用稳定顺序，但不得改变 source 中 capability binder 的身份。

### 4.2 Named capability

<a id="rule-r06-capability-identity"></a>

**已决定：row 中写 identity；direct binder 不写 `cap` marker**

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

`Read[app]` **只是一种诊断展开**，不能写进源程序，也不是泛型类型应用。诊断 UI 应优先显示用户写过的 `{app}`，只有在多个 capability 同名、来源不清或需要解释 effect family 时才展开为 `Read[app]`。

匿名 family effect 与 named capability 可以出现在同一 row：

```moonbit
def sync(app : Read[Model]) -> Unit
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
| direct binder `app : F` | capability term | `F` 的一个具体 instance | `app.read()`、`{app}` |

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
solver/schema 语义，见 §4.6。

显式调用也使用双列表：

```moonbit
consume[Int]![State[Int], {Log}](app, log_value)
```

普通类型实参和 effect/row 实参不会再依靠位置上的 kind marker 混合解释。

Ability 的 associated type/effect/row 与 Core 展开由本文和 temporal
formalization共同定义。Higher-kinded effect constructor只有 Appendix A 已冻结的
`F[_]` binder shape；一般 `fresh`/one-call function type仍在 §11 的 profile
boundary registry 中，不属于 v1。

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

<a id="rule-r06-associated-ability-profile-boundary"></a>

successor V3/M3 wire只为 ability-associated EffectRow携带 `Lacks[e]`：generic hidden
`RowBinderV1`继承该 evidence，concrete explicit/default row必须证明它。Ordinary trait
的 zero-arity associated Type declaration可带 ordinary trait constraints，并精确进入
`AssociatedTypeDeclarationV1.constraints`；不能把 ability wire限制施加给 ordinary
trait。Appendix A为了稳定 recovery仍在 `AbilityItem` context识别 associated Type
constraint、associated Effect ability constraint与 nonempty associated `TypeParams`，
但这些 ability evidence/arity尚无 retained wire表示，必须在 body/default检查前分别
稳定拒绝 `associated-declaration-constraint-not-in-profile` 与
`associated-parameterization-not-in-profile`。v1 也没有 `where` clause、递归
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
ability-target `ImplDecl` CST；但 **独立 ability `impl` 不属于 v1**。Resolver
一旦确认 `impl` 左侧是 ability，必须稳定拒绝
`independent-ability-impl-not-in-profile`。因此 orphan/coherence、overlap、
specialization、operation adapter、associated binding uniqueness、mode
compatibility和跨 package visibility没有“先实现再决定”的隐含规则；它们必须在
新 profile一起冻结后，独立 ability `impl` 才能成为 accepted form。普通 trait
target则按 §2.5 的 orphan/coherence/overlap 与 associated-type规则形成 accepted
`ImplDecl`，但永远不能产生 ability evidence或绕过 effect-profile边界。

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
`Has[...]`、`All[...]`、`Only[...]` 在 v1 一律由 RowWF稳定拒绝
`row-predicate-not-in-profile`。它们没有 builtin-name特判、solver、wire schema或
隐含 diagnostic contract；未来若加入，必须以新 profile同时定义上述四项。

## 5. Operation 调用

**Profile baseline**

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

**Profile baseline**

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
`Cire-v1.0`：失败由显式 abort effect 表达，取消由 Owner/finalize 协议表达。

`source.park(k, under = owner)` 只在 operand 带 sealed completion-source
evidence 时降为 Core T-Park。它消耗当前 clause 的处置责任，产生
`Transfers(ParkContractV2)` 并终止当前 path；它不是返回 `Unit` 的普通容器
插入函数。source/port只传 operation result `A`，完整 resumption保存
`A -> B` answer transform；宿主 callback不能捕获 raw `Resume`。

### 6.3 Return 与 forwarding

**Profile baseline**

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
- v1 没有显式 forwarding source clause；缺少当前-family clause是穷尽性错误，
  非当前-family operation按 validated `ForwardContract` 自动向外层转发；

v1 handler 是 lexical deep handler。Shallow handler 不进入 v1。

### 6.4 Inline handler derived form

<a id="rule-r06-inline-handler"></a>

v1 只有一个 inline derived form：

```cire
with Logger {
  fun log(message) => emit(message)
  return(value) => value
} as logger in body(logger)
```

它在 Normalize Surface 阶段唯一展开为：

```cire
with (handler Logger {
  fun log(message) => emit(message)
  return(value) => value
}) as logger in body(logger)
```

它复用 full handler 的 `HandlerMember`、mode、pattern、continuation、return、scope
与 omitted-return规则，不新增 Core/wire node。Clause mode绝不能省略；完整但缺 mode
的 clause head只产生 `handler-clause-mode-required`。`Type { field: value }`、空/
不完整 body 与普通 trailing lambda必须走 ordinary expression fallback，不能被 inline
recovery抢走。

Full/derived pair在擦除 source-form/origin metadata并对 fresh prompt alpha-normalize
后，normalized Surface HIR、Kernel、row/flow/capture/usage/phase obligations必须相同；
origin golden则分别保留 direct form与 `InlineHandlerExpansionV1`。Formatter保留用户
原 form，不自动互转。

## 7. 本质形式与语法糖

唯一 frontend pipeline 是：

```text
UTF-8 source
  -> lossless token stream -> lossless CST -> syntax validation
  -> resolved Surface HIR -> normalized Surface HIR
  -> signature/kind-checked Surface HIR
  -> evidence-indexed Kernel HIR
  -> typed Core + Q/Λ/interface artifacts
```

Lex/Parse不读取 expected type或 symbol table；Syntax只处理 token-level shape；
Resolve选择 exact namespace/kind identity；Normalize只展开 inline handler、omitted
return、interpolation、derive、while/for 与 with right-fold；Signature/Kind选择唯一
callable/member/intrinsic signature、label/default table、direct capability binder与
sealed evidence；Kernel才生成 source-order temporaries、call-entry tuple、fresh prompt/
runtime capability与 privileged nodes。typed-Core stage只能增加 judgment evidence，
不得 reparse、重排求值或选择另一个 lowering。

CST 和 Surface HIR 保留用户原始写法。所有 synthesized Kernel node带
`ElaborationOriginMapV1` entry；interpolation/finally/derive使用
`SealedIntrinsicV1`，while/for/numeric/assignment evaluation nodes使用
`SourceOrderTemporaryV1`。同一 normalized node不得由不同 frontend获得不同
origin/binder/site allocation。

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
  consume(owner)
}
```

`with` 也不复用于 record update、trait/effect constraint、普通对象 receiver
scope、import 或 match clause。它始终只表示“用 scoped transformer 包住一段
computation”。

### 7.2 Trailing lambda

<a id="rule-r06-call-assembly"></a>

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
  gap = 8,
  body = fn() {
    Text("Profile")
    Button("Save", body = fn() {
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
- signature resolution 后它只填排除 implicit receiver 后 slot 最大的 final formal，
  绝不搜索“最后一个未填槽”；该 slot已提供时报 duplicate（先于 callable/type error），
  有 default时 trailing覆盖 default，非 callable时报
  `trailing-lambda-target-not-callable`；
- labelled/default call只允许 exact static callable metadata；只剩 structural function
  type的 value不能使用 label并报 `named-call-requires-static-signature`。

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
- sealed `BuildString` 与 `@control::finally`；
- nominal derive、state-threaded `for` 与 numeric defect checks。

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

**Profile baseline**

Capture inference 与传递 closure、capability escape、`once` usage、multi-shot
replayability、mutable-place capture、handler-mode weakening、Owner park/CAS 与
finalization responsibility 全部属于 accepted-program WF。Checker不得 feature-gate
其中子集或在缺少 evidence 时接受。ordinary mutable place的 exact boundary见 §2.6；
一般 affine value calculus仍不进入 v1。

### 8.3 PackedNext 的 sealed scope

**已决定**

Cire-v1.0 不增加一般 existential 或 rank-2 类型语法。跨越 generative FrameClock
lifetime 使用 shared `PackedNext[A]` 与三个 sealed first-party origin：

```cire
let packed = @temporal::pack_next(under = owner) { frame =>
  delay[frame] { 42 }
}

let opened = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

let receipt : CloseReceipt[DisposeReport] = @temporal::dispose(packed)
```

`try_with_packed_next` 的 result是 `Option[B]`：Closing/Closed acquisition返回
`None`；成功 body的 Returns映射为 `Some`；Aborts/Transfers保持 terminal tag，
但必须先证明 private frame/Next/Later/lease没有通过任何 outward evidence逃逸，
再 exactly-once release。Handle可复制，alias共享当前形式化的
`Building|Open|Closing|Closed` cell、construction lease、monotone lease ordinal、
唯一 cleanup reservation与 close cell；dispose 是幂等 NoSuspend request，重复调用
返回同一 `CloseReceipt[DisposeReport]`。最后一个 construction/open lease release
后才 physical close并 resolve receipt；任何 terminal path保留原 flow tag并归档 report。
三段 block是 contextual HIR，不是用户可声明的普通 callback
contract；同名用户函数无 privileged lowering。

### 8.4 Closed intrinsic registry 与 first-party surface

Compiler、LSP 与 conformance只消费一个生成的 `IntrinsicRegistryRootV1`。它包含
两个 profile-disjoint child：

1. 下文定义的 exact `FirstPartyRegistryV1`，恰好 21 个
   temporal/Owner/reactive binding；
2. `StructuralIntrinsicRegistryV1`，恰好 `BuildStringV1` 与 `FinallyV1` 两个
   compiler-owned structural elaboration。

第二个 child不改变 21-entry registry的 bytes/cardinality。BuildString没有用户可调用
binding；`@control::finally`只有 §2.6 的 exact runner signature。任何同 spelling用户
declaration、wrong package instance、missing evidence或 registry hash mismatch都走 ordinary
call或稳定拒绝，绝不按名字升级 privileged Kernel node。

21 个 binding ID按 NFC UTF-8严格排序如下；source signature中的 ordinary names均可
positional或同名 labelled传入，所有 slot nondefaultable：

| Stable binding ID | Source | Direct result / policy |
|---|---|---|
| `Cire-v1.0/intrinsic/async.await-receipt` | `CloseReceipt::await(receipt)` | `R`; Async/MaySuspend/current Owner |
| `Cire-v1.0/intrinsic/async.await-task` | `Async::await(task)` | `R`; Async/MaySuspend/current Owner, `Shareable(R)` |
| `Cire-v1.0/intrinsic/resource.dispose` | `Resource::dispose(resource)` | `CloseReceipt[DisposeReport]` |
| `Cire-v1.0/intrinsic/resource.switch-latest` | `Resource::switch_latest(under,keys){ owner,key => ... }` | `Resource[rho,K,A,E]` |
| `Cire-v1.0/intrinsic/resource.view` | `Resource::view(resource)` | `Live[rho,ResourceView[K,A,E]]` |
| `Cire-v1.0/intrinsic/signal.map` | `map_signal(input,transform)` | `Signal[i,B]`; pure transform |
| `Cire-v1.0/intrinsic/signal.track` | `Signal::track(frame){ track => ... }` | `Signal[i,A]` |
| `Cire-v1.0/intrinsic/snapshot.read-live` | `snapshot.read(live)` | fixed-revision `A` |
| `Cire-v1.0/intrinsic/snapshot.read-source` | `snapshot.read(source)` | fixed-revision `A` |
| `Cire-v1.0/intrinsic/task.cancel-outcome` | `Task::cancel(task,under)` | `CancelResult`、NoSuspend |
| `Cire-v1.0/intrinsic/temporal.pack-next` | `@temporal::pack_next(under){ frame => ... }` | `PackedNext[A]` |
| `Cire-v1.0/intrinsic/temporal.packed-next-dispose` | `@temporal::dispose(packed)` | `CloseReceipt[DisposeReport]` |
| `Cire-v1.0/intrinsic/temporal.try-with-packed-next` | `@temporal::try_with_packed_next(packed){ frame,next => ... }` | `Option[B]` |
| `Cire-v1.0/intrinsic/track.read-live` | `track.read(live)` | invalidating `A` |
| `Cire-v1.0/intrinsic/track.read-source` | `track.read(source)` | invalidating `A` |
| `Cire-v1.0/intrinsic/ui.builder-owner` | `ui.owner` | exact `Owner[rho]` projection |
| `Cire-v1.0/intrinsic/ui.candidate-action` | `candidate.action { snapshot,event => ... }` | `ActionPlan[gamma,E]` |
| `Cire-v1.0/intrinsic/ui.coalesce-latest` | `CoalesceLatest` | closed `UiBackpressureV1` literal |
| `Cire-v1.0/intrinsic/ui.mount-dispose` | `UiMount::dispose(mount)` | `CloseReceipt[DisposeReport]` |
| `Cire-v1.0/intrinsic/ui.render` | `ui.render(model){ candidate,current => ... }` | Unit; generation-checked plan |
| `Cire-v1.0/intrinsic/ui.run-signal` | `@ui::run_signal(under,backpressure){ frame,ui => ... }` | `UiMount[rho]` |

上表只是 human-readable index；它不定义简化 wire。下列 closed contract逐字段
唯一生成 registry bytes、callback scheme、evidence discharge与 Kernel lowering。
形式化只解释这些 evidence predicates与 Kernel/Core node的 WF/runtime意义，不能
维护第二张 registry或补写 Surface lowering。

<a id="rule-r06-first-party-registry"></a>

#### 8.4.1 Closed first-party binding registry

Cire-v1.0 中的 first-party source entry不得停留在例子/prose。Surface authority必须生成唯一
`FirstPartyRegistryV1`；它是 compiler/LSP/conformance共用的 exact registry，不是 public Core wire：

```text
BindingIdV1 = NFC nonempty String matching
  "Cire-v1.0/intrinsic/" + [a-z0-9]+ ("." | "-" | [a-z0-9])*

CallbackNameV1 = NFC nonempty identifier
NfcNameV1      = NFC nonempty identifier

FirstPartyRegistryV1 = {
  artifact: "FirstPartyRegistryV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  bindings: [FirstPartyBindingV1; 21]
}

FirstPartyBindingV1 = {
  kind: "FirstPartyBindingV1",
  id: BindingIdV1,
  source: FirstPartySourceV1,
  slots: [FirstPartySlotV1],
  types: [FirstPartyGenericBinderV1],
  fresh: [FirstPartyFreshBinderV1],
  direct: FirstPartyContractTemplateV1,
  callbacks: [FirstPartyCallbackV1],
  evidence: [FirstPartyEvidenceV1],
  kernel: FirstPartyKernelV1
}

FirstPartySourceV1 =
    { kind: "IntrinsicModuleFunctionV1", module: NfcNameV1, member: NfcNameV1 }
  | { kind: "UnqualifiedFunctionV1", name: NfcNameV1 }
  | { kind: "AssociatedFunctionV1", receiver: NfcNameV1, member: NfcNameV1 }
  | { kind: "AssociatedProjectionV1", receiver: NfcNameV1, member: NfcNameV1,
      surface_member: NfcNameV1 }
  | { kind: "ClosedLiteralV1", nominal: NfcNameV1, variant: NfcNameV1 }

FirstPartySlotV1 =
    { kind: "ImplicitReceiverSlotV1", slot: u32,
      passing: "ImplicitReceiverV1", type: TypePatternV1 }
  | { kind: "NamedOrPositionalSlotV1", slot: u32,
      passing: "NamedOrPositionalV1", public_label: NFC nonempty String,
      defaultable: false, type: TypePatternV1 }

FirstPartyTypeTemplateV1 =
    { kind: "BuiltinTypeTemplateV1", name: NfcNameV1 }
  | { kind: "BinderTypeTemplateV1", binder: FirstPartyBinderRefV1 }
  | { kind: "NominalTypeTemplateV1", module: [NfcNameV1], name: NfcNameV1,
      arguments: [FirstPartyTypeTemplateV1] }
  | { kind: "CapabilityTypeTemplateV1", identity: FirstPartyBinderRefV1,
      family: FirstPartyEffectFamilyTemplateV1 }
  | { kind: "FunctionTypeTemplateV1", parameters: [FirstPartyTypeTemplateV1],
      result: FirstPartyTypeTemplateV1 }

FirstPartyEffectFamilyTemplateV1 =
    { kind: "NominalEffectFamilyTemplateV1",
      module: [NfcNameV1], name: NfcNameV1,
      arguments: [FirstPartyTypeTemplateV1] }

TypePatternV1 =
    { kind: "TypeRefV1", type: FirstPartyTypeTemplateV1 }
  | { kind: "ContextualCallbackRefV1", callback_name: CallbackNameV1 }
  | { kind: "CallableCallbackRefV1", callback_name: CallbackNameV1 }

FirstPartyGenericBinderV1 =
    { kind: "KindBinderV1", binder_slot: u32,
      binder_kind: "TypeV1" | "OwnerRegionV1" | "ClockIdentityV1"
                 | "TrackEpochScopeV1" | "UiGenerationScopeV1"
                 | "EffectRowV1" }
  | { kind: "UiRevisionScopeBinderV1", binder_slot: u32,
      generation: { kind: "GenericBinderRefV1", binder_slot: u32 } }

FirstPartyBinderRefV1 =
    { kind: "GenericBinderRefV1", binder_slot: u32 }
  | { kind: "FreshBinderRefV1", fresh_slot: u32 }

FirstPartyFreshVisibilityV1 =
    { kind: "DirectOnlyV1" }
  | { kind: "CallbackOnlyV1", callback_name: CallbackNameV1 }
  | { kind: "DirectAndCallbackPrivateV1", callback_name: CallbackNameV1 }

FirstPartyFreshOriginV1 =
    { kind: "ChildOwnerRegionV1", parent: FirstPartyBinderRefV1,
      relation: "DirectChildV1" }
  | { kind: "FrameClockIdentityV1", owner: FirstPartyBinderRefV1 }
  | { kind: "ClockPackageSummaryV1", identity: FirstPartyBinderRefV1,
      payload: FirstPartyTypeTemplateV1 }
  | { kind: "InstalledTrackEpochV1" }
  | { kind: "AdmittedUiGenerationV1", owner: FirstPartyBinderRefV1 }
  | { kind: "UiRevisionOfV1", generation: FirstPartyBinderRefV1 }

FirstPartyFreshBinderV1 =
    { kind: "GenerativeFreshBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1" | "TrackEpochScopeV1"
                 | "UiGenerationScopeV1" | "UiRevisionScopeV1",
      cardinality: "PerDirectCallV1" | "PerCallbackInvocationV1"
                 | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1",
      visibility: FirstPartyFreshVisibilityV1,
      origin: FirstPartyFreshOriginV1 }
  | { kind: "DerivedCurrentOwnerBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1", derivation: "CurrentOwnerOfEntryPhaseV1",
      visibility: { kind: "DirectOnlyV1" }
                | { kind: "DirectAndCallbackPrivateV1",
                    callback_name: CallbackNameV1 } }
  | { kind: "OpenedPackedNextBinderV1", fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1",
      packed_parameter_slot: u32,
      component: "OwnerRegionV1" | "ClockIdentityV1"
               | "ClockPackageSummaryV1",
      visibility: { kind: "DirectAndCallbackPrivateV1",
                    callback_name: CallbackNameV1 } }

FirstPartyTemporalV1 =
    { kind: "PureV1" }
  | { kind: "HostObservableV1" }

FirstPartyPhaseV1 = "PureV1" | "ComputeV1" | "ActionV1" | "CommitV1"

FirstPartyRowTemplateV1 =
    { kind: "EmptyRowV1" }
  | { kind: "AnonymousAsyncRowV1" }
  | { kind: "GenericEffectRowV1", binder: FirstPartyBinderRefV1 }
  | { kind: "CallbackRowV1", callback: FirstPartyCallbackRefV1 }

FirstPartySuspensionTemplateV1 =
    { kind: "NoSuspendV1" }
  | { kind: "AsyncMaySuspendV1" }
  | { kind: "CallbackSuspensionV1", callback: FirstPartyCallbackRefV1 }

FirstPartyWorldTemplateV1 =
    { kind: "SameWorldV1" }
  | { kind: "CallbackWorldV1", callback: FirstPartyCallbackRefV1 }
  | { kind: "ProjectPrivateWorldV1", callback: FirstPartyCallbackRefV1,
      private_binders: [FirstPartyBinderRefV1] }

FirstPartyReturnMapV1 =
    { kind: "PackNextReturnMapV1", input: FirstPartyTypeTemplateV1,
      output: FirstPartyTypeTemplateV1 }
  | { kind: "AcquireOptionReturnMapV1", lost: FirstPartyTypeTemplateV1,
      input: FirstPartyTypeTemplateV1, output: FirstPartyTypeTemplateV1 }

FirstPartyFlowTemplateV1 =
    { kind: "ReturnsOnlyV1", result: FirstPartyTypeTemplateV1 }
  | { kind: "AwaitOrParkV1", result: FirstPartyTypeTemplateV1,
      park: "ParkContractV2" }
  | { kind: "CallbackFlowV1", callback: FirstPartyCallbackRefV1 }
  | { kind: "MapCallbackFlowV1", callback: FirstPartyCallbackRefV1,
      returns: FirstPartyReturnMapV1,
      preserve_terminal_tags: ["AbortsV2", "TransfersV2"] }

FirstPartyConstructionV1 = {
  kind: "CanonicalFirstPartyLiteralPathsV1",
  demand_policy: "NormalizedRowAndKernelV1",
  obligation_policy: "EvidenceArrayOrderV1",
  site_policy: "AllReferencedDirectAndProjectedCallbackSitesV1",
  result_policy: "TypeAndFlowDirectedV1",
  capture_policy: "ActualArgumentsAndCallbacksV1",
  usage_policy: "AuthoritySlotsExactV1",
  origin_policy: "ElaborationOriginProjectionV1"
}

FirstPartyContractTemplateV1 = {
  kind: "FirstPartyContractTemplateV1",
  phase: FirstPartyPhaseV1,
  row: FirstPartyRowTemplateV1,
  suspension: FirstPartySuspensionTemplateV1,
  world: FirstPartyWorldTemplateV1,
  flow: FirstPartyFlowTemplateV1,
  temporal: FirstPartyTemporalV1,
  construction: FirstPartyConstructionV1
}

FirstPartyCallbackV1 = {
  kind: "FirstPartyCallbackV1",
  name: CallbackNameV1,
  parameter_slot: u32,
  acquisition: "ContextualV1" | "CallableValueV1",
  type: FirstPartyTypeTemplateV1,
  contract: FirstPartyContractTemplateV1,
  scheme: FirstPartyCallbackSchemeV1
}

FirstPartyCallbackEntryOwnerV1 =
    { kind: "NoCallbackEntryOwnerV1" }
  | { kind: "ExactCallbackEntryOwnerV1",
      owner: FirstPartyBinderRefV1 }

FirstPartyCallbackSchemeV1 = {
  kind: "FirstPartyCallbackSchemeV1",
  trigger: "DirectInvocationV1" | "CallableInvocationV1"
         | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1"
         | "PerEventDispatchV1",
  entry_owner: FirstPartyCallbackEntryOwnerV1,
  captured_fresh_slots: [u32],
  generated_fresh_slots: [u32]
}

FirstPartyCallbackRefV1 = {
  kind: "BindingCallbackRefV1",
  callback_name: CallbackNameV1
}

FirstPartyEvidenceArgumentV1 =
    FirstPartyBinderRefV1
  | { kind: "ParameterSlotRefV1", slot: u32 }
  | FirstPartyCallbackRefV1
  | { kind: "EvidenceTypeRefV1", type: FirstPartyTypeTemplateV1 }

FirstPartyEvidenceRuleV1 =
    "CurrentOwnerV1" | "OwnerAuthorityV1" | "ChildOwnerV1"
  | "FrameClockNextSummaryCoherenceV1" | "PrivateIdentityOutwardGateV1"
  | "PackedNextPackageLeaseV1" | "ExactPackedNextOverloadV1"
  | "ExactCloseCellIdentityV1" | "OutlivesV1" | "ShareableV1"
  | "AsyncBoundarySafeV1" | "SuspensionStableV1" | "OwnerBoundParkingV1"
  | "ExactOutcomeTaskV1" | "DuplicableEnvironmentV1"
  | "OwnerStorageProvenanceV1" | "BoundarySafeCaptureV1"
  | "TemporalStableCaptureV1" | "CrossWorldSafeCaptureV1"
  | "ExactResourceRootV1" | "ExactBuilderRootV1"
  | "CompleteDependencyTraceV1" | "ContextualNonescapeV1"
  | "FixedSnapshotV1" | "NoDependencyRegistrationV1"
  | "ExactCoalesceLatestV1" | "ExactGenerationRevisionBindingV1"
  | "ActionSafeRowV1" | "EventEntryDischargeOnlyV1"
  | "EventOccurrenceStorageV1"
  | "ExactMountRootV1" | "ExactOwnerV1" | "InvalidatingDependencyV1"
  | "ExactBackpressureArgumentV1" | "ExactPackagePrivateScopeV1"
  | "ExactTaskRegionGenerationV1" | "ProjectionNonescapeV1"
  | "CandidatePlanCaptureNonescapeV1" | "PrivateFrameBuilderNonescapeV1"

ResourceLoaderContractV1 = {
  kind: "ResourceLoaderContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  generation_owner: FirstPartyBinderRefV1,
  key_type: FirstPartyTypeTemplateV1,
  value_type: FirstPartyTypeTemplateV1,
  error_type: FirstPartyTypeTemplateV1
}

SignalTailContractEvidenceV1 = {
  kind: "SignalTailContractEvidenceV1",
  callback: FirstPartyCallbackRefV1,
  clock: FirstPartyBinderRefV1,
  input_type: FirstPartyTypeTemplateV1,
  output_type: FirstPartyTypeTemplateV1
}

ActionPlanContractV1 = {
  kind: "ActionPlanContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  generation: FirstPartyBinderRefV1,
  revision: FirstPartyBinderRefV1,
  event_type: FirstPartyTypeTemplateV1,
  event_parameter_index: u32,
  occurrence_policy: "OwnerStoredExactQueuedOccurrenceV1"
}

FirstPartyRetainedInvocationScopeV1 =
    { kind: "InstalledTrackInvocationV1", epoch: FirstPartyBinderRefV1 }
  | { kind: "UiAdmissionInvocationV1", generation: FirstPartyBinderRefV1,
      revision: FirstPartyBinderRefV1 }

RetainedCallbackContractV1 = {
  kind: "RetainedCallbackContractV1",
  callback: FirstPartyCallbackRefV1,
  storage_owner: FirstPartyBinderRefV1,
  invocation_scope: FirstPartyRetainedInvocationScopeV1,
  capture_policy: "OwnerStorageBoundarySafeOutlivesV1"
}

FirstPartyEvidenceV1 =
    { kind: "ProofRuleEvidenceV1", rule: FirstPartyEvidenceRuleV1,
      arguments: [FirstPartyEvidenceArgumentV1] }
  | ResourceLoaderContractV1
  | SignalTailContractEvidenceV1
  | ActionPlanContractV1
  | RetainedCallbackContractV1

FirstPartyKernelV1 =
    { kind: "PackedNextPackV1" }
  | { kind: "PackedNextOpenV1" }
  | { kind: "PackedNextDisposeV1" }
  | { kind: "OperationCallV1", family: "AsyncV1",
      operation: "awaitV1" | "await_receiptV1" }
  | { kind: "TaskCancelV1" }
  | { kind: "ResourceSwitchLatestV1" }
  | { kind: "ResourceViewV1" }
  | { kind: "ResourceDisposeV1" }
  | { kind: "SignalMapV1" }
  | { kind: "SignalTrackV1" }
  | { kind: "TrackReadLiveV1" }
  | { kind: "TrackReadSourceV1" }
  | { kind: "SnapshotReadLiveV1" }
  | { kind: "SnapshotReadSourceV1" }
  | { kind: "UiBackpressureCoalesceLatestV1" }
  | { kind: "UiRunSignalV1" }
  | { kind: "UiBuilderOwnerV1" }
  | { kind: "UiRenderV1" }
  | { kind: "UiCandidateActionV1" }
  | { kind: "UiMountDisposeV1" }

N(n,name,T) = { kind: "NamedOrPositionalSlotV1", slot: n,
  passing: "NamedOrPositionalV1", public_label: name,
  defaultable: false, type: T }
I(n,T) = { kind: "ImplicitReceiverSlotV1", slot: n,
  passing: "ImplicitReceiverV1", type: T }
ContextualCallback(name) = {
  kind: "ContextualCallbackRefV1", callback_name: name
}
CallableCallback(name) = {
  kind: "CallableCallbackRefV1", callback_name: name
}
```

所有 object/union只允许上列 exact fields/tags。`types[*].binder_slot`、
`fresh[*].fresh_slot` 与 `slots[*].slot` 分别从 0 连续、严格递增且无重复；
每个 binder reference必须解析到同 binding中较早声明且 kind相符的 binder。
字段名 `fresh` 为 registry v1 wire兼容名；其中 `DerivedCurrentOwnerBinderV1` 明确不是
generative fresh scope，不能分配新 Owner，只解析 entry phase的 `CurrentOwner(Phi)`；
`OpenedPackedNextBinderV1` 解析 parameter中已经存在的 sealed package component，也不
generative；只有 `GenerativeFreshBinderV1` 分配新 scope且必须携带 cardinality。
`DirectAndCallbackPrivateV1` 只允许 direct template及所名 callback引用，仍必须通过
所有 outward gates，绝不成为 public type binder。

每个 `ContextualCallbackRefV1` 或 `CallableCallbackRefV1(callback_name)` 必须与 `callbacks` 中恰好一个
同名 callback双向对应；该 callback的 `parameter_slot` 必须等于引用它的 slot，
且 `type` 必须等于该 parameter slot的 exact callable type。
反向地，每个 callback必须被恰好一个 callback-typed slot引用。`callbacks` 按
`parameter_slot` 数值严格递增。`ContextualCallbackRefV1`只允许 acquisition=`ContextualV1`；
`CallableCallbackRefV1`只允许 acquisition=`CallableValueV1`。普通 `TypeRefV1` slot不能秘密关联 callback。
`scheme.captured_fresh_slots` 与 `generated_fresh_slots` 各自严格递增、无重复且互不相交；两者的 union
必须恰好等于该 callback type/contract、`scheme.entry_owner` 及其 special evidence可达的全部 fresh ref。
`entry_owner` 引用同一 fresh binder时不另加一个 slot，只要求它已经出现在正确的 captured/generated array。
Generic refs由 direct-call
substitution closure捕获，不进入这两个 array。`captured` 只能引用 direct阶段已解析的
`DerivedCurrentOwnerBinderV1`、`OpenedPackedNextBinderV1` 或 enclosing trigger已生成的 binder；
`generated` 只能引用 `GenerativeFreshBinderV1`，按 fresh slot的依赖拓扑顺序实例化。Trigger与
cardinality的 exact对应为：`DirectInvocationV1 -> PerDirectCallV1`；
`PerInstalledSubscriptionV1 -> PerInstalledSubscriptionV1`；
`PerAdmittedGenerationV1 -> PerAdmittedGenerationV1`；`CallableInvocationV1` 与
`PerEventDispatchV1` 若有 generated项则只许 `PerCallbackInvocationV1`。不匹配、漏项、把同一 ref同时
captured/generated或让 generated origin forward-reference都稳定
`first-party-callback-scheme-mismatch`。Scheme在 rigid fresh tuple下普遍检查；它不是把第一次 runtime
generation的 ref封进一个 monomorphic closure。

`scheme.entry_owner` 不是 ambient hint，而是 callback entry phase的唯一 current-Owner source。八个
callback的 exact mapping固定为：`pack_next.builder -> rho_child`、
`try_with_packed_next.body -> rho_child`、`resource.switch_latest.load -> rho_child`、
`signal.map.transform -> NoCallbackEntryOwnerV1`、`signal.track.body -> rho`、
`ui.run_signal.body -> rho`、`ui.render.transform -> rho`、
`ui.candidate_action.body -> rho`。前七个 contextual callback必须使用对应
`ExactCallbackEntryOwnerV1`；唯一 callable callback `signal.map.transform` 必须使用
`NoCallbackEntryOwnerV1`。任何漏 owner、错 owner、把 contextual改成 NoOwner、把 callable改成 exact
owner、或在相同 kind的 foreign/cross-admission owner间替换，都稳定
`first-party-callback-entry-owner-mismatch`。

每个 exact mapping还必须有唯一 authority source，不能只因 type中出现同名 `rho` 就获得 lease：
pack builder与 Resource loader的 generated child由同一 binding的
`ChildOwnerV1(parent,rho_child)` 和该 trigger原子取得的 child-entry lease共同授权；open body由同一
package的 `PackedNextPackageLeaseV1` 与
`ExactPackagePrivateScopeV1(rho_child,i,L,body)`授权；track body的 derived current `rho`由
`CurrentOwnerV1(rho)+OwnerAuthorityV1(rho)`授权；UI runner body的 `rho`由 explicit `under` actual解出、
经 `OwnerAuthorityV1(rho)`验证后由 sealed runner entry lease重绑定；render transform的 `rho`必须同时等于
`UiBuilder` receiver的 exact root、retained storage owner与 callback entry owner；candidate action body的
`rho`必须同时等于 `UiCandidate` receiver、`ActionPlanContractV1.storage_owner`、retained storage owner与
callback entry owner。少任一 authority edge、把 lease从别的 owner/generation搬来或只继承 ambient
visitor owner都按同一 diagnostic拒绝。
`ResourceLoaderContractV1.callback` 必须解析到同 binding的 `load` callback；
其 exact row、Q、Λ、capture与 usage就是匹配到的 actual callback contract对应 fields，
不存在第二份可漂移的 loader contract。`SignalTailContractEvidenceV1` 同理解析到
`transform` callback；`ActionPlanContractV1` 同理解析到 `body` callback并把其完整
row/suspension/flow/summary/capture/Q/Λ与 exact owner/generation/revision/event substitution
作为一个不可拆分 contract保存在 ActionPlan中。其 zero-based `event_parameter_index` 必须恰为 1；callback参数 0
必须恰为 `SnapshotContext[storage_owner,revision]`，参数 1 必须恰为 `event_type`，且不能有额外参数。
`occurrence_policy` 必须恰为 `OwnerStoredExactQueuedOccurrenceV1`。同一
`ActionPlanContractWF` 还必须在 evidence array中找到恰好一次
`ShareableV1(event_type)` 与
`EventOccurrenceStorageV1(storage_owner,generation,event_type)`；后者逐完整 value summary证明该值
BoundarySafe、没有可逃逸的 affine/linear Owner或 capability authority、borrow、resumption、private static
scope或 user-finalizer责任，并可作为 immutable exact value保存在 `OwnerStorage(storage_owner)` 到该
generation的 occurrence终结。该保存责任的 release是 sealed、total、NoSuspend且 infallible；它不建立
CleanupLedger reservation。ContractWF据这两项 proof与 special contract的 exact五元组
`(callback,storage_owner,generation,revision,event_type)` 派生不可伪造的
`UiEventStorageWitness[event_type]` 并保存在 erased action entry中；该 sealed value内部仍精确绑定
`(storage_owner,generation,event_type)` 三元组，只有 `event_type` 保留为 runtime type index；不得从 host
tag、declaration slot或 ambient current generation重建。index/policy/proof/type/owner/generation任一错配稳定
`first-party-action-occurrence-contract-mismatch`。`ResourceLoaderContractWF` 与
`ActionPlanContractWF` 虽各自用 special contract保存 admission/event substitution，仍必须对同一 callback/
storage owner在 evidence array找到下述 exact三项 proof；special contract不暗含、替代或重复其中任一项。
`RetainedCallbackContractWF` 不是对 `capture_policy` literal的空检查：对同一 callback/storage owner，
evidence array必须恰有 `OwnerStorageProvenanceV1(cb,owner)`、`BoundarySafeCaptureV1(cb)` 与
`OutlivesV1(cb,owner)`，并逐 capture slot证明 provenance=`OwnerStorage(owner)`、BoundarySafe且该 slot
outlives storage lifetime；short-lived borrow/capability、foreign Owner或漏任一 proof都在安装前拒绝。
其 invocation scope必须与 callback scheme generated tuple exact相等：Track为唯一 eta，UI为依赖有序
gamma/nu。`RetainTrack`/`RetainUi` 与三项 proof重复、错序引用其它 callback或只把 policy string当证明都
`first-party-retained-callback-contract-mismatch`。

下列 source pretty-print有唯一展开：`@m::f` 是
`IntrinsicModuleFunctionV1{module:m,member:f}`，裸 `map_signal` 是
`UnqualifiedFunctionV1`，`T::f` 是 `AssociatedFunctionV1`，带
``surface projection `p` ``的 `T::f` 是 `AssociatedProjectionV1`，裸
`CoalesceLatest` 是 `ClosedLiteralV1{nominal:UiBackpressureV1,
variant:CoalesceLatest}`。Kernel pretty-print同样逐 tag展开为上列 union；唯一带
payload的两项是 exact `OperationCallV1`。`types=[x:K,...]` 按 list index生成
连续 `binder_slot`；`nu:UiRevisionScope[gamma]` 唯一生成依赖 gamma ref的
`UiRevisionScopeBinderV1`。`N`/`I` 中普通 type唯一包成 `TypeRefV1`。

下列 21个 entry各自必须 materialize为一个完整 `FirstPartyBindingV1` object；
行式 contract是 closed `FirstPartyContractTemplateV1` 的 **normative lossless notation**，
不是 `M3(FunctionContractV2)` 的残缺 projection，也不是自由 prose。wire decoder只接受
上列 tagged object；文档 notation先经下述总函数展开后才能进入 canonical bytes。
Producer先构造以 `id` 为 key的 exact 21-entry
map，验证 key与 object.id相等、exact ID set、source与 kernel逐 ID匹配，再按
ID的 NFC UTF-8 bytes排序后一次 materialize `bindings`。Decoder不替调用者重排：
非严格递增输入稳定拒绝。Canonical bytes是递归 NFC后的 RFC 8785/JCS UTF-8
bytes；semantic binding sort仍按 ID的 NFC UTF-8 bytes，不改 JCS object-member
UTF-16 ordering。

Table notation只有下列 constructors；它们逐字段展开成上列 tagged AST，不进入
canonical bytes；`Pure/Compute/Action/Commit` 分别唯一展开为同名 `*V1` phase tag：

```text
C(phase,row,suspension,world,flow,temporal) = {
  kind: FirstPartyContractTemplateV1,
  phase, row, suspension, world, flow, temporal,
  construction: {
    kind: CanonicalFirstPartyLiteralPathsV1,
    demand_policy: NormalizedRowAndKernelV1,
    obligation_policy: EvidenceArrayOrderV1,
    site_policy: AllReferencedDirectAndProjectedCallbackSitesV1,
    result_policy: TypeAndFlowDirectedV1,
    capture_policy: ActualArgumentsAndCallbacksV1,
    usage_policy: AuthoritySlotsExactV1,
    origin_policy: ElaborationOriginProjectionV1
  }
}

R0                 = EmptyRowV1
RAsync             = AnonymousAsyncRowV1
RG(x)              = GenericEffectRowV1(GenericBinderRefV1(slot(x)))
RCB(name)          = CallbackRowV1(BindingCallbackRefV1(name))
S0                 = NoSuspendV1
SAsync             = AsyncMaySuspendV1
SCB(name)          = CallbackSuspensionV1(BindingCallbackRefV1(name))
W0                 = SameWorldV1
WCB(name)          = CallbackWorldV1(BindingCallbackRefV1(name))
WPrivate(name,xs)  = ProjectPrivateWorldV1(BindingCallbackRefV1(name),refs(xs))
FRet(T)            = ReturnsOnlyV1(Ty(T))
FAwait(T)          = AwaitOrParkV1(Ty(T),ParkContractV2)
FCB(name)          = CallbackFlowV1(BindingCallbackRefV1(name))
FPack(name,X,Y)    = MapCallbackFlowV1(CBRef(name),PackNextReturnMapV1(Ty(X),Ty(Y)),
                                      [AbortsV2,TransfersV2])
FOpen(name,N,X,Y)  = MapCallbackFlowV1(CBRef(name),
                       AcquireOptionReturnMapV1(Ty(N),Ty(X),Ty(Y)),
                       [AbortsV2,TransfersV2])
TPure              = PureV1
THost              = HostObservableV1

VBoth(name)        = DirectAndCallbackPrivateV1(name)
VCallback(name)    = CallbackOnlyV1(name)
GChild(n,parent,card,vis) = GenerativeFreshBinderV1(
  n,OwnerRegionV1,card,vis,ChildOwnerRegionV1(ref(parent),DirectChildV1))
GFrame(n,owner,card,vis) = GenerativeFreshBinderV1(
  n,ClockIdentityV1,card,vis,FrameClockIdentityV1(ref(owner)))
GSummary(n,identity,payload,card,vis) = GenerativeFreshBinderV1(
  n,ClockPackageSummaryV1,card,vis,
  ClockPackageSummaryV1(ref(identity),Ty(payload)))
GTrack(n,vis) = GenerativeFreshBinderV1(
  n,TrackEpochScopeV1,PerInstalledSubscriptionV1,vis,InstalledTrackEpochV1)
GGeneration(n,owner,vis) = GenerativeFreshBinderV1(
  n,UiGenerationScopeV1,PerAdmittedGenerationV1,vis,
  AdmittedUiGenerationV1(ref(owner)))
GRevision(n,generation,vis) = GenerativeFreshBinderV1(
  n,UiRevisionScopeV1,PerAdmittedGenerationV1,vis,
  UiRevisionOfV1(ref(generation)))
CurrentOwner(n,vis) = DerivedCurrentOwnerBinderV1(
  n,OwnerRegionV1,CurrentOwnerOfEntryPhaseV1,vis)
Opened(n,kind,parameter,component,name) = OpenedPackedNextBinderV1(
  n,kind,parameter,component,DirectAndCallbackPrivateV1(name))
NoEntryOwner          = NoCallbackEntryOwnerV1
EntryOwner(owner)     = ExactCallbackEntryOwnerV1(B(owner))
Scheme(trigger,owner,captured,generated) = FirstPartyCallbackSchemeV1(
  trigger,owner,sorted-u32(captured),sorted-u32(generated))
E(rule,args...)      = ProofRuleEvidenceV1(rule,[args...])
B(name)              = ref(name)
P(n)                 = ParameterSlotRefV1(n)
CBRef(name)          = BindingCallbackRefV1(name)
ET(T)                = EvidenceTypeRefV1(Ty(T))
Loader(cb,rho,child,K,A,E) = ResourceLoaderContractV1(
  CBRef(cb),B(rho),B(child),Ty(K),Ty(A),Ty(E))
Tail(cb,i,A,B)       = SignalTailContractEvidenceV1(
  CBRef(cb),B(i),Ty(A),Ty(B))
ActionContract(cb,rho,gamma,nu,E) = ActionPlanContractV1(
  CBRef(cb),B(rho),B(gamma),B(nu),Ty(E),1,
  OwnerStoredExactQueuedOccurrenceV1)
RetainTrack(cb,rho,eta) = RetainedCallbackContractV1(
  CBRef(cb),B(rho),InstalledTrackInvocationV1(B(eta)),
  OwnerStorageBoundarySafeOutlivesV1)
RetainUi(cb,rho,gamma,nu) = RetainedCallbackContractV1(
  CBRef(cb),B(rho),UiAdmissionInvocationV1(B(gamma),B(nu)),
  OwnerStorageBoundarySafeOutlivesV1)
```

`types` 的 `x:K` 与 `fresh` 的 `x := Constructor(...)` 左侧 name都只是
notation-time symbol；它们必须唯一、按 list位置等于 object slot并在 tagged object生成后擦除。
`Ty` 是 closed type-template notation，不是 string field。它先把 `types`/`fresh` 左侧 name按
list index变成 numeric `GenericBinderRefV1`/`FreshBinderRefV1`，再严格按下列 constructor matrix
生成 bytes；表中的 module path/name是 `NominalTypeTemplateV1` 的 exact field，不由 importer猜测。
`O/I/L/H/G/U/R/F` 分别是 OwnerRegion/ClockIdentity/ClockPackageSummary/TrackEpochScope/
UiGenerationScope/UiRevisionScope/EffectRow/EffectFamily kind，`T` 是 ordinary Type kind：

```text
notation                  canonical module/name                    argument kinds   target after substitution
Owner[O]                  ["cire","owner"] / "Owner"              O                OwnerTypeV2(owner)
Cap[I,F]                  closed CapabilityTypeTemplateV1          I,F              CapabilityTypeV2(identity,effect-family)
Next[I,T,L]               ["cire","temporal"] / "Next"            I,T,L            SchemeOnly
PackedNext[O,T]           ["cire","temporal"] / "PackedNext"      O,T              PackedNextTypeV2(owner,payload)
Option[T]                 ["cire","core"] / "Option"              T                NominalTypeV2
Task[O,T]                 ["cire","async"] / "Task"               O,T              OwnerIndexedTypeV2(Task,owner,payload)
TaskOutcome[T,T]          ["cire","async"] / "TaskOutcome"        T,T              NominalTypeV2
CloseReceipt[T]           ["cire","async"] / "CloseReceipt"       T                NominalTypeV2
Live[O,T]                 ["cire","reactive"] / "Live"            O,T              OwnerIndexedTypeV2(Live,owner,payload)
Source[O,T]               ["cire","reactive"] / "Source"          O,T              OwnerIndexedTypeV2(Source,owner,payload)
Resource[O,T,T,T]         ["cire","resource"] / "Resource"        O,T,T,T          NominalTypeV2(OwnerTypeV2(owner),K,A,E)
ResourceView[T,T,T]       ["cire","resource"] / "ResourceView"    T,T,T            NominalTypeV2
Signal[I,T]               ["cire","signal"] / "Signal"            I,T              SignalTypeV2(clock,payload)
TrackContext[O,I,H]       ["cire","signal"] / "TrackContext"      O,I,H            SchemeOnly
SnapshotContext[O,R]      ["cire","ui"] / "SnapshotContext"       O,R              SchemeOnly
UiBuilder[O,I]            ["cire","ui"] / "UiBuilder"             O,I              SchemeOnly
UiCandidate[O,G,R]        ["cire","ui"] / "UiCandidate"           O,G,R            SchemeOnly
ActionPlan[G,T]           ["cire","ui"] / "ActionPlan"            G,T              SchemeOnly
ViewPlan[G]               ["cire","ui"] / "ViewPlan"              G                SchemeOnly
UiMount[O]                ["cire","ui"] / "UiMount"               O                NominalTypeV2(OwnerTypeV2(owner))
CancelResult              ["cire","async"] / "CancelResult"       -                NominalTypeV2
DisposeReport             ["cire","owner"] / "DisposeReport"      -                NominalTypeV2
UiBackpressureV1          ["cire","ui"] / "UiBackpressureV1"      -                NominalTypeV2
```

`FrameClock` **不在 ordinary type matrix**；它唯一生成
`NominalEffectFamilyTemplateV1{module:["cire","temporal"],name:"FrameClock",arguments:[]}`，kind=`F`，
substitution后作为 `CapabilityTypeV2.family` 的 exact
`LegacyTypeRefV2{value:NominalTypeV1{module:["cire","temporal"],name:"FrameClock",arguments:[]}}`，且该
legacy nominal必须由 Effect-family declaration catalog解析为 Effect。把它生成为 `NominalTypeV2`、当普通
Type argument或交给非 Effect declaration都 `first-party-type-template-kind-mismatch`。
`ParkContractV2` 也不在 type matrix：它只由 `AwaitOrParkV1.park="ParkContractV2"` 生成 closed park
contract/Transfers object，任何 `Ty(ParkContractV2)` 都拒绝。

`Unit` 唯一生成 `BuiltinTypeTemplateV1{name:"Unit"}`，substitution后生成 approved
`LegacyTypeRefV2{value:BuiltinTypeV1{name:"Unit"}}`；v1不新增 `BuiltinTypeV2`。
Parenthesized function type唯一生成
`FunctionTypeTemplateV1`；它是 callback matching pattern，不自行伪造必需的
`FunctionTypeV2.contract`，只能匹配 callable actual已有的 contract或进入下述 sealed callback scheme。
`NominalTypeV2(...)` 一栏按 matrix列出的参数顺序生成 exact target；Owner/Identity/Contract/static
scope ref从不被塞进普通 type argument。`CapabilityTypeTemplateV1` 与
`NominalEffectFamilyTemplateV1` 是独立 tagged constructors，不通过 `NominalTypeTemplateV1.arguments`
偷渡 Effect kind。

`SchemeOnly` 只存在于 normalized Kernel HIR的
`FirstPartyCallbackSchemeV1`：ContractWF在 rigid scope下检查后，backend擦除 wrapper/static index；它们以及
`FirstPartyBinderRefV1` 均不得进入 `M3(TypeRefV2)`、`FunctionContractV3`、
`CallableInterfaceV1` 或 outward value。因而 callback不是一个含未表示 eta/gamma/nu 的普通 local
`FunctionContractV3`。一个本来可 materialize的 constructor只要含非 M3 scoped ref，也按 SchemeOnly处理。
其唯一 M3 runtime carrier函数 `EraseSchemeTypeV1` 先递归 erasure ordinary payload，再按下表删除全部
Owner/Identity/Clock/Contract/epoch/generation/revision index：

```text
EType(name,args) = NominalTypeV2(
  module=["cire","kernel","firstparty"], name=name, arguments=args)

Owner[O]              -> EType("ErasedOwnerHandleV1",[])
Cap[I,F]              -> EType("ErasedCapabilityHandleV1",[])
Next[I,T,L]           -> EType("ErasedNextHandleV1",[Erase(T)])
PackedNext[O,T]       -> EType("ErasedPackedNextHandleV1",[Erase(T)])
Task[O,T]             -> EType("ErasedTaskHandleV1",[Erase(T)])
Live[O,T]             -> EType("ErasedLiveHandleV1",[Erase(T)])
Source[O,T]           -> EType("ErasedSourceHandleV1",[Erase(T)])
Resource[O,K,A,E]     -> EType("ErasedResourceHandleV1",[Erase(K),Erase(A),Erase(E)])
Signal[I,T]           -> EType("ErasedSignalHandleV1",[Erase(T)])
TrackContext[O,I,H]   -> EType("ErasedTrackContextV1",[])
SnapshotContext[O,R]  -> EType("ErasedSnapshotContextV1",[])
UiBuilder[O,I]        -> EType("ErasedUiBuilderV1",[])
UiCandidate[O,G,R]    -> EType("ErasedUiCandidateV1",[])
ActionPlan[G,T]       -> EType("ErasedActionPlanV1",[Erase(T)])
ViewPlan[G]           -> EType("ErasedViewPlanV1",[])
UiMount[O]            -> EType("ErasedUiMountHandleV1",[])
```

其它不含 static ref的 builtin/Option/TaskOutcome/CloseReceipt/ResourceView/CancelResult/DisposeReport/
UiBackpressure nominal按 ordinary M3 target递归使用 `Erase(T)`；`FunctionTypeTemplateV1`只作 callback
matching pattern，不能直接请求 erasure。上列 `cire.kernel.firstparty` carrier是 closed compiler-known
nominal set，没有 source constructor、import/export、member或 `CallableInterfaceV1`；只许出现在
`SchemeActualSummaryV1.erased_runtime_view.type` 与 `FirstPartySchemeContractWF` differential。把 carrier当 public
type、少/多 payload、保留 static ref、将两个 carrier name互换或对 ordinary M3 actual使用 carrier都稳定
`first-party-static-scope-escape`。因此
`erased_runtime_view.type == EraseSchemeTypeV1(scheme_type)` 是一个总函数，
不是实现自行选择的 representation。

Unknown module/name、arity、argument kind、forward ref、wrong target variant、
SchemeOnly outward use或 bare unary arrow都拒绝。Names在 tagged object生成后擦除，所以 table notation的
alpha-renaming不改变 canonical bytes。

`PackedNext[O,T]` 是 registry/typed-Core template spelling；surface仍只显示 sealed
`PackedNext[T]`。Hidden `O` 从 package value的 exact `PackedNextTypeV2.owner`解出，不能由 caller填写，
也不能在 public pretty-print、type argument list或 overload choice中出现；pack/open/dispose三项因此都能
round-trip同一 storage owner而不发明未编码参数。
`Resource[O,K,A,E]` 明确走新 profile的 four-argument nominal target；它不借旧
`ResourceTypeV2{owner,value,cleanup_result}` 丢掉 key/error，也无二者间 implicit coercion。Importer按
module/name与四个 argument exact匹配，旧 variant只属于旧 profile。

`ProofRuleEvidenceV1` 的 arguments不是 open list。下表是 exact signature matrix，
`B/P/C/T` 分别表示 binder/parameter-slot/callback/type argument；rule不在表、arity不同或
argument sort不同都拒绝：

```text
CurrentOwnerV1(B)                         OwnerAuthorityV1(B)
ChildOwnerV1(B,B)                         FrameClockNextSummaryCoherenceV1(B,B,B,T)
PrivateIdentityOutwardGateV1(B,B,B,C)     PackedNextPackageLeaseV1(P,C)
ExactPackedNextOverloadV1(P)              ExactCloseCellIdentityV1(P)
OutlivesV1(B|C,B)                         ShareableV1(T)
AsyncBoundarySafeV1(B,T)                  SuspensionStableV1(P)
OwnerBoundParkingV1(B)                    ExactOutcomeTaskV1(P,B,T,T)
DuplicableEnvironmentV1(C)                OwnerStorageProvenanceV1(C,B)
BoundarySafeCaptureV1(C)                  TemporalStableCaptureV1(C,B)
CrossWorldSafeCaptureV1(C,B)              ExactResourceRootV1(P,B)
ExactBuilderRootV1(P,B,B)                 CompleteDependencyTraceV1(C,B)
ContextualNonescapeV1(C)                  FixedSnapshotV1(B)
NoDependencyRegistrationV1(P)             ExactCoalesceLatestV1()
ExactGenerationRevisionBindingV1(C,B,B)   ActionSafeRowV1(B,B,B)
EventEntryDischargeOnlyV1(C)              EventOccurrenceStorageV1(B,B,T)
ExactMountRootV1(P,B)
ExactOwnerV1(B)                           InvalidatingDependencyV1(B,P)
ExactBackpressureArgumentV1(P)            ExactPackagePrivateScopeV1(B,B,B,C)
ExactTaskRegionGenerationV1(P,B)          ProjectionNonescapeV1(P)
CandidatePlanCaptureNonescapeV1(C,B,B)    PrivateFrameBuilderNonescapeV1(B,C)
```

调用点输入也是 closed compiler record，不能从 ambient visitor state补字段：

```text
FirstPartyInstantiationSiteV1 = {
  kind: "FirstPartyInstantiationSiteV1",
  kernel_node_preorder: u32,
  kernel_site_slot: u32,
  entry_world: M3(WorldExprV2),
  route: M3(RouteSelectorV1),
  call_origin: SourceOriginV2,
  sealed_intrinsic_origin: SourceOriginV2,
  caller_scope: FirstPartyCallerScopeV1
}

FirstPartyScopedValueRefV1 =
    { kind: "M3OwnerValueV1", owner: SlotRefV1 }
  | { kind: "M3IdentityClockValueV1",
      identity: SlotRefV1, clock: SlotRefV1 }
  | { kind: "M3ContractValueV1", contract: M3(ContractRefV2) }
  | { kind: "SchemeFreshValueV1",
      scheme_body_preorder: u32,
      fresh_slot: u32,
      binder_kind: "OwnerRegionV1" | "ClockIdentityV1"
                 | "ClockPackageSummaryV1" | "TrackEpochScopeV1"
                 | "UiGenerationScopeV1" | "UiRevisionScopeV1" }
  | { kind: "OpenedPackedNextComponentValueV1",
      packed_parameter_slot: u32,
      packed_source: M3(SlotRefV2),
      component: "OwnerRegionV1" | "ClockIdentityV1"
               | "ClockPackageSummaryV1" }

FirstPartyCallerScopeV1 = {
  declaration_binders: M3(DeclarationBindersV2),
  entry_phase: M3(PhaseRequirementV1),
  current_owner: FirstPartyScopedValueRefV1 | null,
  frame_builder_witnesses: [FirstPartyFrameBuilderWitnessV1]
}

FirstPartyFrameBuilderWitnessV1 = {
  kind: "FirstPartyFrameBuilderWitnessV1",
  frame_source: M3(SlotRefV2),
  identity_clock: FirstPartyScopedValueRefV1,
  owner: FirstPartyScopedValueRefV1,
  builder_origin: SourceOriginV2
}

FirstPartyCallbackSourceV1 =
    { kind: "ContextualCallbackSourceV1", parameter_slot: u32,
      normalized_hir_node_preorder: u32, capture_slots: [M3(SlotRefV2)] }
  | { kind: "CallableCallbackSourceV1", parameter_slot: u32,
      actual_slot: u32 }

FirstPartyErasedRuntimeValueViewV1 = {
  kind: "FirstPartyErasedRuntimeValueViewV1",
  source: M3(SlotRefV2) | null,
  type: M3(TypeRefV2),
  origin: SourceOriginV2
}

FirstPartyActualSummaryV1 =
    { kind: "M3ActualSummaryV1", value: M3(ValueSummaryExprV2) }
  | { kind: "SchemeActualSummaryV1",
      typed_kernel_value_preorder: u32,
      erased_runtime_view: FirstPartyErasedRuntimeValueViewV1,
      scheme_body_preorder: u32,
      scheme_type: FirstPartyTypeTemplateV1,
      kernel_scope_refs: [FirstPartyScopedValueRefV1] }

FirstPartyInstantiationOutputV1 =
    { kind: "M3FirstPartyInstantiationV1",
      computation: M3(ContractComputationV2),
      callback_schemes: [FirstPartyInstantiatedCallbackSchemeV1],
      site_allocations: [FirstPartySiteAllocationV1],
      projection_items: [FirstPartyProjectionItemV1] }
  | { kind: "SchemeFirstPartyInstantiationV1",
      typed_kernel_computation_preorder: u32,
      callback_schemes: [FirstPartyInstantiatedCallbackSchemeV1],
      site_allocations: [FirstPartySiteAllocationV1],
      projection_items: [FirstPartyProjectionItemV1] }

FirstPartySolvedValueV1 =
    { kind: "SolvedTypeV1", value: M3(TypeRefV2) }
  | { kind: "SolvedOwnerV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedIdentityClockV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedContractV1", value: FirstPartyScopedValueRefV1 }
  | { kind: "SolvedRowV1", value: M3(RowExprV1) }
  | { kind: "SolvedStaticScopeV1", value: FirstPartyScopedValueRefV1 }

FirstPartySolvedBindingV1 = {
  generic_slot: u32,
  value: FirstPartySolvedValueV1
}

FirstPartyCapturedFreshV1 = {
  fresh_slot: u32,
  value: FirstPartySolvedValueV1
}

FirstPartyInstantiatedCallbackSchemeV1 = {
  kind: "FirstPartyInstantiatedCallbackSchemeV1",
  binding_id: BindingIdV1,
  callback_name: CallbackNameV1,
  trigger: "DirectInvocationV1" | "CallableInvocationV1"
         | "PerInstalledSubscriptionV1" | "PerAdmittedGenerationV1"
         | "PerEventDispatchV1",
  entry_owner: FirstPartyScopedValueRefV1 | null,
  solved_generics: [FirstPartySolvedBindingV1],
  captured_fresh: [FirstPartyCapturedFreshV1],
  rigid_fresh: [FirstPartyFreshBinderV1],
  frame_builder_witnesses: [FirstPartyFrameBuilderWitnessV1],
  erased_kernel_body_preorder: u32,
  type_template: FirstPartyTypeTemplateV1,
  contract_template: FirstPartyContractTemplateV1,
  evidence_indices: [u32]
}

FirstPartySiteKeyV1 = {
  kernel_node_preorder: u32,
  source_kind: "DirectFirstPartyCallV1" | "CallbackLexicalSiteV1",
  callback_parameter_slot: u32,
  source_local_site_slot: u32
}

FirstPartySiteAllocationV1 = {
  kind: "FirstPartySiteAllocationV1",
  key: FirstPartySiteKeyV1,
  provisional_site_slot: u32,
  final_site_slot: u32
}

FirstPartyProjectionKeyV1 = {
  kernel_node_preorder: u32,
  item_namespace: "ObligationOccurrenceV1" | "LatentSiteOccurrenceV1",
  source_kind: "DirectEvidenceV1" | "KernelSiteV1" | "CallbackProjectionV1",
  path_ordinal: u32,
  source_major: u32,
  source_minor: u32
}

FirstPartyProjectedObligationValueV1 =
    { kind: "M3ProjectedObligationValueV1",
      value: M3(ObligationV2) }
  | { kind: "SchemeObligationTemplateValueV1",
      typed_kernel_occurrence_preorder: u32,
      scoped_refs: [FirstPartyScopedValueRefV1],
      final_obligation_id: u32,
      site_key: FirstPartySiteKeyV1 | null }

FirstPartyProjectedLatentSiteValueV1 =
    { kind: "M3ProjectedLatentSiteValueV1",
      value: M3(LatentSiteV2) }
  | { kind: "SchemeLatentSiteTemplateValueV1",
      typed_kernel_occurrence_preorder: u32,
      scoped_refs: [FirstPartyScopedValueRefV1],
      site_key: FirstPartySiteKeyV1,
      final_site_slot: u32 }

FirstPartyProjectionItemV1 =
    { kind: "ProjectedObligationV1", key: FirstPartyProjectionKeyV1,
      value: FirstPartyProjectedObligationValueV1 }
  | { kind: "ProjectedLatentSiteV1", key: FirstPartyProjectionKeyV1,
      value: FirstPartyProjectedLatentSiteValueV1 }
```

`ProjectedObligationV1.key.item_namespace` 必须为 `ObligationOccurrenceV1`，
`ProjectedLatentSiteV1` 必须为 `LatentSiteOccurrenceV1`；互换不是另一种 ordering，而是 exact decode
`first-party-projection-namespace-mismatch`。

`sealed_intrinsic_origin` 不是 caller任填 string：它必须等于 §A.12 中以 call Direct node为 anchor、
`DerivedKindV1=SealedIntrinsicV1`、唯一 `PrincipalV1` parent生成的 Derived node投影；
`call_origin` 必须等于同一个 anchor的 `SourceOriginV2`（该 profile中仍是 `SourceOriginV1` alias）。
`kernel_node_preorder` 是 §A.12 normalized Kernel HIR preorder；`kernel_site_slot` 是 binding-local provisional
slot且 v1唯一合法值为0。first-party invocation的最终 Q/Λ若至少一个 field引用该 direct site，就必须
消费它并生成恰好一个 `DirectFirstPartyCallV1` site allocation；若全部 Q静态 discharge且没有 Λ，则必须
生成零 direct allocation且不消耗 final slot。`OperationCallV1` 因必有 Λ总会生成 allocation，并在该 site另外生成
`LatentSiteV2`，不是 site存在的条件。随后必须由第7步 root-wide rebase同时重写所有引用它的
Q/Λ field。它不是 caller选择的 final slot。Preorder、local zero、route、entry world与 caller
binders都由 caller ContractWF重算相等。Registry lowering直接 splice一个 `LiteralPathsV2/PathBindV2` computation；它**不**
伪造无 target artifact的 `AppliedContractV2` 或 `InvokeV2`，所以 `FunctionContractV3.applications` delta
为 `[]`。Lexical `site_slot` 与 static contract `application_slot` 是独立 namespace；分配前者不创造后者。
普通 callback body里的真实 calls仍保留各自 applications。
`FirstPartyScopedValueRefV1` 是 internal arena ref而非 Core wire。`SolvedOwnerV1`只许
`M3OwnerValueV1`、Owner-kind `SchemeFreshValueV1`或 Owner component；
`SolvedIdentityClockV1`只许 exact M3 pair、ClockIdentity-kind scheme fresh或 opened clock component；
`SolvedContractV1`只许 M3 Contract、ClockPackageSummary-kind scheme fresh或 opened summary；
`SolvedStaticScopeV1`只许相应 Track/Generation/Revision-kind scheme fresh。每个
`SchemeFreshValueV1` 必须在同一 normalized typed-Kernel arena中解析到 active或所名 enclosing callback
scheme的 `captured_fresh` **或** `rigid_fresh` 中恰好一个 exact `fresh_slot`，并由 registry fresh
declaration重算相同 `binder_kind`。解析到 captured项时继续解析它的 `FirstPartySolvedValueV1`，但不得形成
cycle；解析到 rigid项时必须是该 scheme本次 trigger将分配的 declaration。零个、两个表同时命中、引用
inactive/unreachable scheme、slot/kind不等或 capture cycle都 `first-party-callback-scheme-mismatch`；
`OpenedPackedNextComponentValueV1` 必须把 parameter、source与 sealed package component三者重算相等。
因此 opened `rho_child/i/L` 与 enclosing UiRunSignal `i` 都不伪装成普通 M3 slot。

`FirstPartyInstantiatedCallbackSchemeV1.entry_owner` 由 registry scheme owner作总替换：
`NoCallbackEntryOwnerV1 -> null`；`ExactCallbackEntryOwnerV1(B(x))` 则从
`solved_generics/captured_fresh/rigid_fresh` 中取得 x的唯一 `FirstPartyScopedValueRefV1`。它可以是
`M3OwnerValueV1`、Owner-kind `SchemeFreshValueV1` 或 opened Owner component，不能是其它 kind。
为 `M3OwnerValueV1` 时 precompiled entry phase与它必须是同一 Owner slot；为后两种 non-M3 ref时，scheme的
M3 erasure中 `entry_phase.current_owner` 必须为 null，不能伪造 Legacy slot。每次 trigger先按 rigid tuple作
capture-avoiding substitution，再用上文该 binding的 exact authority source原子取得该 owner的 entry lease，
把 callback active `entry_phase.current_owner` 设置为刚 materialize的 concrete Owner，且 nested
`FirstPartyCallerScopeV1.current_owner` 只能 exact复制该 active owner；Returns/Aborts/Transfers任一路离开都
恢复先前 entry phase。`signal.map.transform` 的 null owner不取得 lease也不重绑定其 ordinary callable
scope。任何 ambient继承、最近 owner启发式或跨 owner lease都拒绝。

Frame witness的 owner/identity_clock分别按上述 kind规则解析，`frame_source`只允许 Legacy source slot；
表按 resolved `(scheme-body-preorder,fresh-slot-or-M3-slot,owner-key,frame-source namespace,slot)`严格递增、
无重复。`UiRunSignalV1` 是唯一 producer：构造其 `body` scheme时，
`PrivateFrameBuilderNonescapeV1(i,body)` 必须生成恰好一个 witness，source为 body parameter 0的 canonical
provenance root，identity_clock为该 scheme的 `SchemeFreshValueV1(body_preorder,0,ClockIdentityV1)`，owner为
已解 `rho`，origin为同 call的 sealed derived origin；该 witness写入
`FirstPartyInstantiatedCallbackSchemeV1.frame_builder_witnesses`。其它七个 callback scheme该 array必须为空。
进入 nested call时 caller scope只可 exact复制 active scheme中 source仍可达的 witness；identity-preserving
alias通过 canonical provenance root解析，不能另造 witness。由此 `Signal::track` 的 unique-witness check有
closed producer，不读取 ambient visitor state。
`solved_generics` 必须按 generic slot严格递增并 exact覆盖 binding.types；`captured_fresh` 与
`rigid_fresh` 分别按 scheme两张 slot array严格递增且 exact相等，不能另带 binder。`evidence_indices`
严格递增并恰好列出引用该 callback的 proof/special evidence array index；body preorder必须指向同一
callback source的 normalized Kernel HIR root。每个仍被 Q/Λ引用的 direct call恰有一个 site allocation；callback graph中
每个被 Q/Λ引用的 lexical site也恰有一个 `CallbackLexicalSiteV1` allocation，key中的 callback slot与
source-local site必须解析到同一 callback typed graph。`site_allocations` 按 key严格递增，root builder把它与
其它 normalized-HIR site key合并后从0分配一个共享 lexical-site namespace，回填 `final_site_slot`。合并键统一为
`(kernel_node_preorder,site-source-kind-order,source-major,source-minor)`，kind顺序固定
`OrdinaryKernelSiteV1,DirectFirstPartyCallV1,CallbackLexicalSiteV1`；direct的 major/minor=`0/0`，callback的
major/minor=`parameter_slot/source_local_site_slot`。`FirstPartySiteAllocationV1.provisional_site_slot` 必须等于
direct的0或 callback source-local slot，不能由 map order重写。
`projection_items` 则按
`(kernel_node_preorder,item-namespace-order,source-kind-order,path_ordinal,source_major,source_minor)`严格递增；
namespace顺序固定 `ObligationOccurrenceV1,LatentSiteOccurrenceV1`。Obligation ID只在前一 namespace中过滤后
从0分配；每个 obligation/latent-site的 `site_slot` 都通过 `site_allocations` map重写，不从 projection key
猜 rank。这样 callback local obligation 0与 latent site 0可同时存在而不碰 key，也不会分配两个 lexical site。
这些 internal records与 schemes都不进入 Core wire/JCS。
`M3FirstPartyInstantiationV1` 的每个 projection value只许相应
`M3ProjectedObligationValueV1/M3ProjectedLatentSiteValueV1`；其中 `value` 必须与 M3 computation的对应
occurrence byte-for-byte相等。`SchemeFirstPartyInstantiationV1` 的每项一律用相应 scheme-template variant，
即使某一 occurrence的 `scoped_refs=[]` 也不能混入 M3 variant。其
`typed_kernel_occurrence_preorder` 必须指向同一 typed-Kernel computation中的 exact obligation/latent-site
node；`scoped_refs` 按
`(ref-kind-order,scheme-body-preorder-or-parameter-slot,fresh-slot-or-component-order)`严格递增、去重，并
exact等于该 occurrence全部 fields可达的 non-M3 scoped refs。Obligation template的
`final_obligation_id` 必须等于 root allocator给该 key的 ID，`site_key` 为 null当且仅当 occurrence不引用
lexical site，否则必须 exact指向唯一 allocation；latent template的 `site_key/final_site_slot` 必须与唯一
allocation相等。Trigger substitution把对应 typed node一次 materialize为 M3 value，保留同一 final ID/site，
不得 reallocate、retype或从 erased carrier反推。Projection item只是 allocator proof，不是第二份 contract
authority；preorder/ref/key/ID/site或 materialized byte differential不等都是 producer invariant failure。
`erased_kernel_body_preorder` 指向同一 normalized typed-Kernel arena中已经拥有完整
computation/Q/Λ/capture/usage的 callback root；scheme对该 graph做 fresh substitution。`type_template`/
`contract_template` 只是已匹配的 registry pattern，不能替代或复制 inferred contract；body ref错 root、
未 typed或 pattern与 graph observer不等都拒绝。
`M3ActualSummaryV1` 的 type必须是 matrix中可 materialize target；`SchemeActualSummaryV1` 只许在
当前 caller callback scheme内使用，`scheme_body_preorder` 必须等于该 active scheme root；
`typed_kernel_value_preorder` 必须指向该 root内完整、已 type-checked的 normalized typed-Kernel
`ValueSummary` node。这个 node是 type/source/nominal-index/provenance/capture/usage/origin的唯一 authority；
ContractWF、capture/usage、evidence和所有 semantic equality都读取它，绝不读取或补写一个伪 M3 summary。
`scheme_type` 必须与该 node的 exact type observer相等，并含 SchemeOnly constructor或 non-M3 scoped ref。
`erased_runtime_view` 只供 backend representation：source必须等于 typed node的 runtime source projection，
origin byte-for-byte相等，type必须等于 `EraseSchemeTypeV1(scheme_type)`；它没有 nominal-index、provenance、
capture或usage字段，因而不能覆盖这些 typed facts。Trigger时以 scheme tables与 concrete rigid tuple对完整
typed node作 capture-avoiding substitution，随后一次 materialize完整 M3 `ValueSummaryExprV2`；这一步从
typed node复制全部 observers，只把 static refs替成已授权 concrete M3 values，并验证 runtime-view
differential，绝不从 `erased_runtime_view` 重建语义。

`kernel_scope_refs` 只列完整 typed node可达、解析后属于所名 `scheme_body_preorder` 的 distinct
`SchemeFreshValueV1`；它按 `(scheme_body_preorder,fresh_slot,binder-kind-order)`严格递增，先遍历 active
scheme的 `solved_generics/captured_fresh/rigid_fresh` 再重算 exact closure。M3 refs与
`OpenedPackedNextComponentValueV1` 明确排除，且不得因 registry fresh slot本身存在就加入未被 node引用的
项。Canonical controls固定为：`Signal::track.body` 的 `TrackContext` actual只列
`[eta@fresh_slot=1]`，不列已解 current Owner `rho@slot=0`；`try_with_packed_next.body` 的 opened actual列
`[]`；`UiRunSignal.body` 的 frame actual列 `[i@fresh_slot=0]`。漏/多/错序、把 M3/current-owner/opened
component列入、或错 scheme preorder/kind都 `first-party-static-scope-escape`。

Output tag不只查看 direct result。Producer递归扫描实例化后的 result/type/computation/Q/Λ/evidence/
capture/usage/origins全 graph：全部 refs都可物化为 M3时唯一选择 `M3FirstPartyInstantiationV1`；任一 field
仍含 SchemeOnly constructor或 non-M3 scoped ref时唯一选择 `SchemeFirstPartyInstantiationV1`，把完整 graph
和 scheme-template projection嵌在同一 callback arena。只改变 Q、Λ、evidence、capture、usage或 origin中
任一深层 ref也必须改变选择；不允许“result可 M3所以整个 output可 M3”。Scheme output进入 root/public
FunctionContract、跨 scheme返回/存储、混入 M3 projection value或两种 output tag互换都
`first-party-static-scope-escape`。

`instantiate_first_party(binding, actuals:[FirstPartyActualSummaryV1], callback_sources:[FirstPartyCallbackSourceV1], site)` 是唯一 template→typed-Core总函数，
按下列阶段运行；`actuals` 必须与 slots一一对应，callback source按
`parameter_slot`严格递增且与 callback slots exact相等：

1. **非 callback constraints。** 先匹配 receiver/ordinary input actual，只建立 kinded equality graph；
   不读期待 result。Type/Owner/Identity/Clock/row分别只与同 kind term unify；ClockIdentity同时要求 caller
   已有 exact Identity/Clock pair。Callable callback的 existing `FunctionTypeV2.contract`在本阶段加入 graph，
   contextual body不先被强行物化。若 binding是 `Signal::track`，slot 0先解出 `i`，再要求
   `frame_builder_witnesses` 中恰好一个 entry同时满足 `frame_source == summary_source(actuals[0])`、
   `identity_clock == i`、`owner == current_owner`（均按 scoped-ref semantic equality比较）；该 owner唯一解出
   `rho`。零个、多个、foreign identity或
   non-current owner都稳定 `signal-track-builder-root-mismatch`。
2. **Direct scope。** `DerivedCurrentOwnerBinderV1` 只解析上一步已验证的 current Owner；
   `OpenedPackedNextBinderV1` 从同一个 exact `PackedNextTypeV2` actual一次取 owner/clock/summary component；
   component/package identity不等即拒绝。其三项 `captured_fresh.value` 必须分别是指向同 parameter/source的
   `OpenedPackedNextComponentValueV1(OwnerRegion/ClockIdentity/ClockPackageSummary)`；current Owner使用
   `M3OwnerValueV1`，从 enclosing scheme捕获的 binder使用 fully-qualified `SchemeFreshValueV1`。用普通
   SlotRef/ContractRef冒充 opened/scheme component拒绝。只实例化 scheme的 captured项及
   `PerDirectCallV1` binder；origin依赖尚含 unsolved Type（例如 pack-next的 `L(A)`）者保留为 rigid
   deferred equation，不猜 A。
3. **Callback skeleton与唯一求解。** 对 contextual callback建立带 kind的 parameter skeleton；
   `DirectInvocationV1` 的 generated slots复用第2步同一 direct tuple；其它 trigger的
   `scheme.generated_fresh_slots` 依 fresh-slot拓扑成为不在 direct scope实例化的 rigid skolems。Callback body在该 skeleton下做一次
   bidirectional type/row/flow/ContractWF，允许从 parameter uses、inferred Returns type与 inferred row解
   callback-only `A/B/E/epsilon_action`，仍禁止从 direct expected result猜解。Callable actual则用其已有
   type/contract加入同一 constraints。随后解全部 graph；每个 generic必须有一个完整 substitution，零解/
   多解、occurs check、kind mismatch或 deferred origin不相等都
   `first-party-registry-contract-nonunique`。因此 pack-next先由 body解 A再验证 `L(A)`，open解 B，
   Resource解 A/E，track解 A，candidate.action解 E/row；不是在 callback之前假称它们已经存在。
4. **Sealed generative scheme。** Contextual callback不生成含 eta/gamma/nu的 ordinary local
   `FunctionContractV3`。Producer生成 `FirstPartyInstantiatedCallbackSchemeV1`，保存完整 solved generic
   substitution、captured refs、rigid fresh declarations、closed frame-witness table、erased typed Kernel body、
   contract template、entry owner及 evidence。`entry_owner` 按上文 exact mapping从同一三张 substitution
   table求解；它必须同时出现在 callback body entry phase和每个 nested caller scope的 current-Owner
   observer中。Scheme在任意 fresh tuple下已通过 ContractWF；每次对应 runtime trigger才原子分配 concrete
   sealed evidence并按 fresh slot替换 type/computation/evidence/Q/Λ/capture/usage的所有 ref：Resource
   admission `{rho_child}`，track installation `{eta}`，UI admission按依赖序 `{gamma,nu=UiRevisionOf(gamma)}`。
   同一原子 trigger随后从 binding-specific authority取得 entry lease、重绑定 active current Owner，且在
   callback任何 terminal path后恢复；NoOwner callable不执行这一步。两次 admission的每个 generative
   component必须 non-alias；stale/foreign/cross-admission substitution在
   callback启动前 `first-party-callback-scheme-mismatch`。这一步是 precompiled universal scheme的
   instantiation，不在 runtime重新 type-check user source。
5. **Contract paths。** `C` normalise row/world/suspension/flow。`R0/S0/W0` 分别唯一生成 Empty、
   `SuspensionV1{grade:NoSuspend,atoms:[]}`、SameWorld；`RAsync/SAsync` 使用
   `site.kernel_site_slot/site.route/site.entry_world`生成 exact Async demand/request/park tuple。
   `TPure` 产生 Pure；`THost` 产生唯一 sealed certificate：HostObservable、replay Fresh、fork Forbid、
   publish Immediate、suspend按 template取 StackOnly或OwnerBound、trust
   `Sealed{module:["cire","intrinsic"]}`，全部新 origin用 `site.sealed_intrinsic_origin`。
   `FRet`一个 Returns；`FAwait`按 Returns、Transfers canonical tag顺序；`FCB` alpha-copy immediate
   callback paths；`FPack/FOpen`只 map Returns并原样保留每个 Abort/Transfer，FOpen lost path为 ordinal 0。
6. **Q 的 total mapping。** 每个 evidence element先按 array index验证。下列六种是唯一可能 emit
   `ObligationV2` 的 mapping；`ids(xs)`/`captures(cb)`均按 resolved source slot严格递增，emission index
   就是该顺序：

   ```text
   DuplicableEnvironmentV1(cb)       -> DuplicableEnvV2(captures(cb),kernel_site_slot)
   BoundarySafeCaptureV1(cb)         -> BoundarySafeV2(captures(cb),OwnerStorage)
   TemporalStableCaptureV1(cb,i)     -> StableAcrossV2(captures(cb),i,[entry,callback-world])
   CrossWorldSafeCaptureV1(cb,i)     -> BoundarySafeV2(captures(cb),TemporalLock)
   OutlivesV1(cb,owner)              -> one OutlivesV2(capture-slot,LegacySlotRefV2(owner)) per capture slot
   OwnerBoundParkingV1(owner)        -> OwnerParkingV2(owner,kernel_site_slot)
   ```

   每项 stage=`Call`、origin=`site.sealed_intrinsic_origin`；若 exact caller facts静态 discharge则删除，否则
   保留。`OutlivesV1(B,B)` 与 signature matrix中其余全部 rule/special evidence都是 mandatory static
   predicate：逐项成功且 emit零 Q，失败即相应 evidence diagnostic，绝不 silent drop或映成别的 variant。
   M3 owner/identity ref按上表直接 materialize；scheme-fresh ref只保存在
   `SchemeObligationTemplateValueV1` 指向的 typed-Kernel obligation occurrence，`scoped_refs`必须是该 node
   exact closure；对应 trigger实例化为 concrete M3 slot后才以已经分配的 final obligation ID/site
   materialize `ObligationV2`，不能伪造 Legacy slot、重分配 ID或把 template混进 M3 output。
   Path `required_phase` 直接由 template phase生成 exact `PhaseRequirementV1`，不伪造 Phase Q。
7. **site、Λ 与 rebasing。** 若第6步保留任何引用 direct site的 Q，或本步生成 direct Λ，先为本 invocation生成
   唯一 `FirstPartySiteAllocationV1(key={node,DirectFirstPartyCallV1,0,0},provisional=0)`；两者都没有时必须
   省略 allocation，避免无 occurrence的 final-slot gap。只有 `OperationCallV1` 新建一个 `LatentSiteV2`：site slot引用该 allocation，route/origin取
   `site`；receiver是 exact anonymous Async family；operation取 kernel enum；actual_arguments取对应
   `M3ActualSummaryV1.value`（OperationCall binding含 SchemeActual即拒绝）；signature是 Async registry在
   solved substitution下的 exact `OperationSignatureV2`；suffix取
   本 path contract；secondary sites=`Closed([])`；call obligation IDs恰为第6步仍保留且引用本 site的 IDs，
   install IDs为空。其它 kernel tag不凭名字制造 LatentSite。Immediate callback-derived path复制 actual
   callback已有 Q/Λ并保持内部 ID linkage，并把其 typed graph中所有被 Q/Λ引用的 lexical-site table entry
   投影成 `CallbackLexicalSiteV1` allocation；retained callback的 Q/Λ保存在第4步 scheme或
   `ResourceLoaderContractV1/ActionPlanContractV1` 中，**不**伪装成 direct-call `LatentSiteV2`。

   每个待投影 item先带 key
   `(kernel_node_preorder,item_namespace,source_kind,path_ordinal,source_major,source_minor)`；namespace order固定为
   `ObligationOccurrenceV1,LatentSiteOccurrenceV1`，`source_kind` enum order固定为
   `DirectEvidenceV1, KernelSiteV1, CallbackProjectionV1`，major/minor分别是 evidence-index/emission-index、
   `0/0`、callback-parameter-slot/source-local-id。Root builder与其它 normalized-HIR items一起按
   上文 `FirstPartySiteAllocationV1` 的 root-wide key ordering先分配 shared lexical-site slot；再按完整
   projection key unsigned numeric
   lexicographic sort，只从 Obligation namespace过滤后连续分配 obligation ID。Latent occurrence不另分配
   site slot，而必须引用对应 direct/callback site allocation；同时重写 `call_obligation_ids/install_obligation_ids`。
   duplicate key、dangling source-local obligation/site、一个 latent occurrence无/多于一个 allocation、或
   rebase后 ID/site不连续都稳定 ContractWF拒绝；visitor/map/object order不参与。
8. **Result/capture/usage与 output。** Callback-derived result做 exact substitution；其它 Shareable/sealed
   scalar为 Stable+NoCapture；含 live Owner/Identity/Clock index者逐 index生成 canonical provenance/capture。
   Usage只含 type/Kernel确定的 affine authority slot，Zero省略。新生成的 path/outcome/demand/summary/Q/Λ/
   transformer origin一律是 `site.sealed_intrinsic_origin`；投影 callback item保留自己的 source origin。
   M3 output的完整 `LiteralPathsV2/PathBindV2` 与 projection evidence送入现有 Decode/ContractWF；
   Scheme output的 typed-Kernel computation与 schemes送入同字段的 `FirstPartySchemeContractWF`，并在
   每次 concrete trigger substitution及 wrapper erasure后，逐 observer与 materialized M3 projection做
   differential：result/type/computation/Q/Λ/evidence/capture/usage/origin、obligation ID与site slot必须全部
   byte-for-byte相等；`erased_runtime_view` 只参与 backend source/type/origin representation comparison。
   任何 field不能唯一生成即 nonunique diagnostic。

因此 registry canonical bytes只含 closed templates；outward实例化输出是完整 M3
`ContractComputationV2`（row/demand/outcome/world/suspension/full Summary、Q/Λ、capture/usage/result
transformer/origin）并 splice进 caller `FunctionContractV3`；含 SchemeOnly type的内部实例化只进入 enclosing
callback scheme的 typed-Kernel arena，绝不进该 wire。两者都可携带不出 wire的 sealed callback schemes，
不与 registry artifact混同，也没有未声明的 `RegistryOrigin`/field ordinal或所谓 D4 allocator。

所有下列 parameter都 nondefaultable；`N` 可 positional或用该 public label传入，不引入 named-only
passing variant。`ContextualCallback` 只是在 registry slot里引用同 entry下方 exact callback contract的
closed marker，不是用户可构造 type。`fresh` 是 sealed Kernel contextual binder table，绝不开放 source
existential/rank-2 syntax。函数 spelling仍只用 `() -> R`、`(A) -> B`、`(A, B) -> C`。
`N/I` 中普通 `T` 自动包成 `TypePatternV1.TypeRefV1`；`ContextualCallback` 自动包成
`ContextualCallbackRefV1{callback_name=<同 entry callback name>}`，name必须在该 entry的 callbacks中
恰好解析一次。其它 stringly-typed type或 callback reference拒绝。
每个 direct/callback contract都逐项给出 phase、row、suspension、world、full flow与 temporal summary；
省略 field不代表实现可选。`{}` 是 empty row，`same` 是 same-world。Registry按
`id` 的 NFC UTF-8 bytes严格递增且 ID唯一；source spelling只有下列显式列出的两组 nominally-disjoint
read overload pairs可以重复，其余唯一。shadowed同 spelling value始终
走 ordinary call，不得取得 `kernel`。全部 type/callback/evidence pattern进入同一
CallableInterface/ContractWF gate。
重复检查基于完整 tagged `FirstPartySourceV1` canonical key；exact exceptions只有
`AssociatedFunctionV1(TrackContext,read)` 的 Live/Source pair与
`AssociatedFunctionV1(SnapshotContext,read)` 的 Live/Source pair，不能只比较 `member` string。

下列 blocks是 exact objects的 lossless normative table notation：`id/source/slots/types/fresh/direct/evidence/kernel`
逐列对应同名 field；`builder/body/load/transform` 行给 callback的 `name/type`，紧随的 `callback` 行给其
`contract`，`scheme` 行给其 `FirstPartyCallbackSchemeV1`，三行共同生成一个
`FirstPartyCallbackV1`。有 callback却缺任一行稳定拒绝；没有这些行的 entry显式生成
`callbacks=[]`，不能省略
field；一个 entry至多使用列出的 callback rows，不允许其它隐式 column。文中的 `stable_binding_id` 就是
object field `id`，`kernel_lowering` 就是 field `kernel`。
callback linkage的 exact全集只有：pack-next `slot 1 -> builder`、try-with-packed-next
`slot 1 -> body`、resource.switch-latest `slot 2 -> load`、signal.map `slot 1 -> transform`、
signal.track `slot 1 -> body`、ui.run-signal `slot 2 -> body`、ui.render
`slot 2 -> transform`、ui.candidate-action `slot 1 -> body`；其它13个 binding的
`callbacks=[]`。这张全集也参与 exact ID-by-ID producer validation，不能从名字启发式推断。
其中只有 signal.map 的 `transform` 是 `CallableValueV1`；其它七个都是 `ContextualV1`。

UI contextual nominal types固定为：

```text
UiBackpressureV1 = CoalesceLatest
TrackContext[rho,i,eta]
UiBuilder[rho,i]
UiCandidate[rho,gamma,nu]
SnapshotContext[rho,nu]
ActionPlan[gamma,E]
ViewPlan[gamma]
UiMount[rho]
```

`eta : TrackEpochScope`、`gamma : UiGenerationScope`、
`nu : UiRevisionScope[gamma]` 是不进入 source syntax的 fresh static scope witness；runtime
`RuntimeNat`/`FixedEpochRevision` 不进入 type equality。每个 `nu` 只携带 sealed evidence指向一个 admitted
runtime pair。`TrackContext`/`UiBuilder`/`UiCandidate`/`SnapshotContext` 都不可存储、返回或跨 contextual
callback逃逸。`ViewPlan[gamma]` 是 sealed immutable adapter value；adapter widget constructor是普通、
scheme-local function，必须在同一个 callback scheme的 pre-erasure Kernel HIR中以
Compute/empty-row/NoSuspend/same/Returns-only contract产生同 `gamma` 的 plan，并可消费同 gamma的
`ActionPlan`。它不能导出、导入或取得 `CallableInterfaceV1`（static gamma在该 wire中无 variant）；可复用的
public helper只能生产普通 Shareable adapter data，由 scheme-local constructor组装 plan。Constructor没有
独立 privileged Kernel tag、不属于本 registry；它随 `UiRenderV1` scheme整体检查/擦除，不能引入第二套 UI
language semantics。

Action callback唯一允许的 latent row predicate是：

```text
ActionSafeRow(rho,gamma,epsilon) iff
  epsilon is a normalized row containing only attributed Named(i,F) demands,
  every selected operation has required phase Action, NoSuspend, world same,
  full flow exactly Returns(Unit); no Anonymous entry,
  await, Abort, Transfer, raw Resume or generic spawn is admitted.
```

`ActionSafeRowV1` 的 exact arguments只有 `rho/gamma/epsilon`，因此它**不**检查 callback capture。
`candidate.action.body` 的 capture lifetime只由同 callback/ref的
`OwnerStorageProvenanceV1 + BoundarySafeCaptureV1 + OutlivesV1` 三项与
`ActionPlanContractWF`逐 slot检查；generation gate/occurrence lease只负责 enqueue/invocation/retire ordering，不能替代
从 plan创建到 event dispatch的静态 outlives proof。event参数也不是 capture：它必须另由同一 entry末尾的
`ShareableV1(E) + EventOccurrenceStorageV1(rho,gamma,E)` 证明并由
`ActionPlanContractWF`铸成 exact storage witness；三项 callback-capture proof不能替它。

Closed entries如下；`RCB/SCB/WCB/FCB(name)` 总是解析同一个已 type-checked callback
contract的 exact observer，不是自由 metavariable或实现选择，direct template必须按写出的
mapping逐 path保留：

```text
id       = "Cire-v1.0/intrinsic/temporal.pack-next"
source   = @temporal::pack_next
slots    = [N(0,"under",Owner[rho]), N(1,"builder",ContextualCallback("builder"))]
types    = [rho:OwnerRegion,A:Type]
fresh    = [rho_child := GChild(0,rho,PerDirectCallV1,VBoth("builder")),
            i := GFrame(1,rho_child,PerDirectCallV1,VBoth("builder")),
            L := GSummary(2,i,A,PerDirectCallV1,VBoth("builder"))]
builder  = (Cap[i,FrameClock]) -> Next[i,A,L]
callback = C(Action,RCB("builder"),SCB("builder"),WCB("builder"),
             FCB("builder"),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho_child),[],[0,1,2])
direct   = C(Action,RCB("builder"),SCB("builder"),
             WPrivate("builder",[rho_child,i,L]),
             FPack("builder",Next[i,A,L],PackedNext[rho,A]),THost)
evidence = [E(CurrentOwnerV1,B(rho)), E(OwnerAuthorityV1,B(rho)),
            E(ChildOwnerV1,B(rho),B(rho_child)),
            E(FrameClockNextSummaryCoherenceV1,B(rho_child),B(i),B(L),ET(A)),
            E(PrivateIdentityOutwardGateV1,B(rho_child),B(i),B(L),CBRef("builder"))]
kernel   = PackedNextPackV1

id       = "Cire-v1.0/intrinsic/temporal.try-with-packed-next"
source   = @temporal::try_with_packed_next
slots    = [N(0,"packed",PackedNext[rho,A]), N(1,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion,A:Type,B:Type]
fresh    = [rho_child := Opened(0,OwnerRegionV1,0,OwnerRegionV1,"body"),
            i := Opened(1,ClockIdentityV1,0,ClockIdentityV1,"body"),
            L := Opened(2,ClockPackageSummaryV1,0,ClockPackageSummaryV1,"body")]
body     = (Cap[i,FrameClock], Next[i,A,L]) -> B
callback = C(Action,RCB("body"),SCB("body"),WCB("body"),FCB("body"),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho_child),[0,1,2],[])
direct   = C(Action,RCB("body"),SCB("body"),
             WPrivate("body",[rho_child,i,L]),
             FOpen("body",Option[B],B,Option[B]),THost)
evidence = [E(PackedNextPackageLeaseV1,P(0),CBRef("body")),
            E(ExactPackagePrivateScopeV1,B(rho_child),B(i),B(L),CBRef("body")),
            E(PrivateIdentityOutwardGateV1,B(rho_child),B(i),B(L),CBRef("body"))]
kernel   = PackedNextOpenV1

id       = "Cire-v1.0/intrinsic/temporal.packed-next-dispose"
source   = @temporal::dispose
slots    = [N(0,"packed",PackedNext[rho,A])]
types    = [rho:OwnerRegion,A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactPackedNextOverloadV1,P(0)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = PackedNextDisposeV1

id       = "Cire-v1.0/intrinsic/async.await-task"
source   = Async::await
slots    = [N(0,"task",Task[rho_task,R])]
types    = [rho_task:OwnerRegion,R:Type]
fresh    = [rho_observer := CurrentOwner(0,DirectOnlyV1)]
direct   = C(Action,RAsync,SAsync,W0,FAwait(R),THost)
evidence = [E(OwnerAuthorityV1,B(rho_observer)),
            E(OutlivesV1,B(rho_observer),B(rho_task)),
            E(AsyncBoundarySafeV1,B(rho_observer),ET(R)),
            E(SuspensionStableV1,P(0)), E(OwnerBoundParkingV1,B(rho_observer)),
            E(ExactTaskRegionGenerationV1,P(0),B(rho_task)),
            E(ShareableV1,ET(R))]
kernel   = OperationCallV1(family="AsyncV1",operation="awaitV1")

id       = "Cire-v1.0/intrinsic/async.await-receipt"
source   = CloseReceipt::await
slots    = [N(0,"receipt",CloseReceipt[R])]
types    = [R:Type]
fresh    = [rho_observer := CurrentOwner(0,DirectOnlyV1)]
direct   = C(Action,RAsync,SAsync,W0,FAwait(R),THost)
evidence = [E(OwnerAuthorityV1,B(rho_observer)), E(ShareableV1,ET(R)),
            E(AsyncBoundarySafeV1,B(rho_observer),ET(R)),
            E(SuspensionStableV1,P(0)), E(OwnerBoundParkingV1,B(rho_observer))]
kernel   = OperationCallV1(family="AsyncV1",operation="await_receiptV1")

id       = "Cire-v1.0/intrinsic/task.cancel-outcome"
source   = Task::cancel
slots    = [N(0,"task",Task[rho,TaskOutcome[A,E]]), N(1,"under",Owner[rho])]
types    = [rho:OwnerRegion,A:Type,E:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CancelResult),THost)
evidence = [E(OwnerAuthorityV1,B(rho)),
            E(ExactOutcomeTaskV1,P(0),B(rho),ET(A),ET(E))]
kernel   = TaskCancelV1

id       = "Cire-v1.0/intrinsic/resource.switch-latest"
source   = Resource::switch_latest
slots    = [N(0,"under",Owner[rho]), N(1,"keys",Live[rho,K]),
            N(2,"load",ContextualCallback("load"))]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = [rho_child := GChild(0,rho,PerAdmittedGenerationV1,VCallback("load"))]
load     = (Owner[rho_child], K) -> Task[rho_child,TaskOutcome[A,E]]
callback = C(Action,RCB("load"),S0,W0,
             FRet(Task[rho_child,TaskOutcome[A,E]]),THost)
scheme   = Scheme(PerAdmittedGenerationV1,EntryOwner(rho_child),[],[0])
direct   = C(Action,R0,S0,W0,FRet(Resource[rho,K,A,E]),THost)
evidence = [E(ShareableV1,ET(K)), E(ShareableV1,ET(A)), E(ShareableV1,ET(E)),
            E(ChildOwnerV1,B(rho),B(rho_child)),
            E(DuplicableEnvironmentV1,CBRef("load")),
            E(OwnerStorageProvenanceV1,CBRef("load"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("load")),
            E(OutlivesV1,CBRef("load"),B(rho)),
            Loader("load",rho,rho_child,K,A,E)]
kernel   = ResourceSwitchLatestV1

id       = "Cire-v1.0/intrinsic/resource.view"
source   = Resource::view
slots    = [N(0,"resource",Resource[rho,K,A,E])]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = []
direct   = C(Pure,R0,S0,W0,FRet(Live[rho,ResourceView[K,A,E]]),TPure)
evidence = [E(ShareableV1,ET(ResourceView[K,A,E]))]
kernel   = ResourceViewV1

id       = "Cire-v1.0/intrinsic/resource.dispose"
source   = Resource::dispose
slots    = [N(0,"resource",Resource[rho,K,A,E])]
types    = [rho:OwnerRegion,K:Type,A:Type,E:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactResourceRootV1,P(0),B(rho)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = ResourceDisposeV1

id       = "Cire-v1.0/intrinsic/signal.map"
source   = map_signal
slots    = [N(0,"input",Signal[i,A]),
            N(1,"transform",CallableCallback("transform"))]
types    = [i:ClockIdentity,A:Type,B:Type]
fresh    = []
transform = (A) -> B
callback = C(Pure,R0,S0,W0,FRet(B),TPure)
scheme   = Scheme(CallableInvocationV1,NoEntryOwner,[],[])
direct   = C(Pure,R0,S0,W0,FRet(Signal[i,B]),TPure)
evidence = [E(ShareableV1,ET(A)), E(ShareableV1,ET(B)),
            E(DuplicableEnvironmentV1,CBRef("transform")),
            E(TemporalStableCaptureV1,CBRef("transform"),B(i)),
            E(CrossWorldSafeCaptureV1,CBRef("transform"),B(i)),
            Tail("transform",i,A,B)]
kernel   = SignalMapV1

id       = "Cire-v1.0/intrinsic/signal.track"
source   = Signal::track
slots    = [N(0,"frame",Cap[i,FrameClock]), N(1,"body",ContextualCallback("body"))]
types    = [i:ClockIdentity,A:Type]
fresh    = [rho := CurrentOwner(0,VBoth("body")),
            eta := GTrack(1,VCallback("body"))]
body     = (TrackContext[rho,i,eta]) -> A
callback = C(Compute,R0,S0,W0,FRet(A),THost)
scheme   = Scheme(PerInstalledSubscriptionV1,EntryOwner(rho),[0],[1])
direct   = C(Action,R0,S0,W0,FRet(Signal[i,A]),THost)
evidence = [E(CurrentOwnerV1,B(rho)), E(OwnerAuthorityV1,B(rho)),
            E(ExactBuilderRootV1,P(0),B(rho),B(i)), E(ShareableV1,ET(A)),
            E(DuplicableEnvironmentV1,CBRef("body")),
            E(CompleteDependencyTraceV1,CBRef("body"),B(eta)),
            E(ContextualNonescapeV1,CBRef("body")),
            E(OwnerStorageProvenanceV1,CBRef("body"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("body")),
            E(OutlivesV1,CBRef("body"),B(rho)), RetainTrack("body",rho,eta)]
kernel   = SignalTrackV1

id       = "Cire-v1.0/intrinsic/track.read-live"
source   = TrackContext::read
slots    = [I(0,TrackContext[rho,i,eta]), N(1,"input",Live[rho,A])]
types    = [rho:OwnerRegion,i:ClockIdentity,eta:TrackEpochScope,A:Type]
fresh    = []
direct   = C(Compute,R0,S0,W0,FRet(A),THost)
evidence = [E(InvalidatingDependencyV1,B(eta),P(1)), E(ExactOwnerV1,B(rho))]
kernel   = TrackReadLiveV1

id       = "Cire-v1.0/intrinsic/track.read-source"
source   = TrackContext::read
slots    = [I(0,TrackContext[rho,i,eta]), N(1,"input",Source[rho,A])]
types    = [rho:OwnerRegion,i:ClockIdentity,eta:TrackEpochScope,A:Type]
fresh    = []
direct   = C(Compute,R0,S0,W0,FRet(A),THost)
evidence = [E(InvalidatingDependencyV1,B(eta),P(1)), E(ExactOwnerV1,B(rho))]
kernel   = TrackReadSourceV1

id       = "Cire-v1.0/intrinsic/snapshot.read-live"
source   = SnapshotContext::read
slots    = [I(0,SnapshotContext[rho,nu]), N(1,"input",Live[rho,A])]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,nu:UiRevisionScope[gamma],A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(A),TPure)
evidence = [E(FixedSnapshotV1,B(nu)), E(NoDependencyRegistrationV1,P(1))]
kernel   = SnapshotReadLiveV1

id       = "Cire-v1.0/intrinsic/snapshot.read-source"
source   = SnapshotContext::read
slots    = [I(0,SnapshotContext[rho,nu]), N(1,"input",Source[rho,A])]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,nu:UiRevisionScope[gamma],A:Type]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(A),TPure)
evidence = [E(FixedSnapshotV1,B(nu)), E(NoDependencyRegistrationV1,P(1))]
kernel   = SnapshotReadSourceV1

id       = "Cire-v1.0/intrinsic/ui.coalesce-latest"
source   = CoalesceLatest
slots    = []
types    = []
fresh    = []
direct   = C(Pure,R0,S0,W0,FRet(UiBackpressureV1),TPure)
evidence = [E(ExactCoalesceLatestV1)]
kernel   = UiBackpressureCoalesceLatestV1

id       = "Cire-v1.0/intrinsic/ui.run-signal"
source   = @ui::run_signal
slots    = [N(0,"under",Owner[rho]), N(1,"backpressure",UiBackpressureV1),
            N(2,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion]
fresh    = [i := GFrame(0,rho,PerDirectCallV1,VBoth("body"))]
body     = (Cap[i,FrameClock], UiBuilder[rho,i]) -> Unit
callback = C(Action,R0,S0,W0,FRet(Unit),THost)
scheme   = Scheme(DirectInvocationV1,EntryOwner(rho),[],[0])
direct   = C(Action,R0,S0,W0,FRet(UiMount[rho]),THost)
evidence = [E(OwnerAuthorityV1,B(rho)), E(ExactBackpressureArgumentV1,P(1)),
            E(ContextualNonescapeV1,CBRef("body")),
            E(PrivateFrameBuilderNonescapeV1,B(i),CBRef("body"))]
kernel   = UiRunSignalV1

id       = "Cire-v1.0/intrinsic/ui.builder-owner"
source   = UiBuilder::owner (surface projection `owner`)
slots    = [I(0,UiBuilder[rho,i])]
types    = [rho:OwnerRegion,i:ClockIdentity]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(Owner[rho]),TPure)
evidence = [E(ExactBuilderRootV1,P(0),B(rho),B(i)), E(ProjectionNonescapeV1,P(0))]
kernel   = UiBuilderOwnerV1

id       = "Cire-v1.0/intrinsic/ui.render"
source   = UiBuilder::render
slots    = [I(0,UiBuilder[rho,i]), N(1,"model",Signal[i,A]),
            N(2,"transform",ContextualCallback("transform"))]
types    = [rho:OwnerRegion,i:ClockIdentity,A:Type]
fresh    = [gamma := GGeneration(0,rho,VBoth("transform")),
            nu := GRevision(1,gamma,VBoth("transform"))]
transform = (UiCandidate[rho,gamma,nu], A) -> ViewPlan[gamma]
callback = C(Compute,R0,S0,W0,FRet(ViewPlan[gamma]),TPure)
scheme   = Scheme(PerAdmittedGenerationV1,EntryOwner(rho),[],[0,1])
direct   = C(Action,R0,S0,W0,FRet(Unit),THost)
evidence = [E(DuplicableEnvironmentV1,CBRef("transform")),
            E(ExactBuilderRootV1,P(0),B(rho),B(i)),
            E(ExactGenerationRevisionBindingV1,CBRef("transform"),B(gamma),B(nu)),
            E(OwnerStorageProvenanceV1,CBRef("transform"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("transform")),
            E(OutlivesV1,CBRef("transform"),B(rho)),
            E(CandidatePlanCaptureNonescapeV1,CBRef("transform"),B(gamma),B(nu)),
            RetainUi("transform",rho,gamma,nu)]
kernel   = UiRenderV1

id       = "Cire-v1.0/intrinsic/ui.candidate-action"
source   = UiCandidate::action
slots    = [I(0,UiCandidate[rho,gamma,nu]), N(1,"body",ContextualCallback("body"))]
types    = [rho:OwnerRegion,gamma:UiGenerationScope,
            nu:UiRevisionScope[gamma],E:Type,epsilon_action:EffectRow]
fresh    = []
body     = (SnapshotContext[rho,nu], E) -> Unit
callback = C(Action,RG(epsilon_action),S0,W0,FRet(Unit),THost)
scheme   = Scheme(PerEventDispatchV1,EntryOwner(rho),[],[])
direct   = C(Compute,R0,S0,W0,FRet(ActionPlan[gamma,E]),TPure)
evidence = [E(ActionSafeRowV1,B(rho),B(gamma),B(epsilon_action)),
            E(DuplicableEnvironmentV1,CBRef("body")),
            E(OwnerStorageProvenanceV1,CBRef("body"),B(rho)),
            E(BoundarySafeCaptureV1,CBRef("body")),
            E(OutlivesV1,CBRef("body"),B(rho)),
            ActionContract("body",rho,gamma,nu,E),
            E(EventEntryDischargeOnlyV1,CBRef("body")),
            E(ShareableV1,ET(E)),
            E(EventOccurrenceStorageV1,B(rho),B(gamma),ET(E))]
kernel   = UiCandidateActionV1

id       = "Cire-v1.0/intrinsic/ui.mount-dispose"
source   = UiMount::dispose
slots    = [N(0,"mount",UiMount[rho])]
types    = [rho:OwnerRegion]
fresh    = []
direct   = C(Action,R0,S0,W0,FRet(CloseReceipt[DisposeReport]),THost)
evidence = [E(ExactMountRootV1,P(0),B(rho)), E(ExactCloseCellIdentityV1,P(0))]
kernel   = UiMountDisposeV1
```

上述 block是 map-entry presentation，不是 encoded array order；producer必须恰好输出下列
NFC UTF-8 ID order，decoder只接受这个顺序：

```text
Cire-v1.0/intrinsic/async.await-receipt
Cire-v1.0/intrinsic/async.await-task
Cire-v1.0/intrinsic/resource.dispose
Cire-v1.0/intrinsic/resource.switch-latest
Cire-v1.0/intrinsic/resource.view
Cire-v1.0/intrinsic/signal.map
Cire-v1.0/intrinsic/signal.track
Cire-v1.0/intrinsic/snapshot.read-live
Cire-v1.0/intrinsic/snapshot.read-source
Cire-v1.0/intrinsic/task.cancel-outcome
Cire-v1.0/intrinsic/temporal.pack-next
Cire-v1.0/intrinsic/temporal.packed-next-dispose
Cire-v1.0/intrinsic/temporal.try-with-packed-next
Cire-v1.0/intrinsic/track.read-live
Cire-v1.0/intrinsic/track.read-source
Cire-v1.0/intrinsic/ui.builder-owner
Cire-v1.0/intrinsic/ui.candidate-action
Cire-v1.0/intrinsic/ui.coalesce-latest
Cire-v1.0/intrinsic/ui.mount-dispose
Cire-v1.0/intrinsic/ui.render
Cire-v1.0/intrinsic/ui.run-signal
```

同 source spelling的 `TrackContext::read` / `SnapshotContext::read` 两对候选只按 nominal input type解析到
上列不同 stable ID，不存在 `Live|Source` implicit coercion或运行时 tag猜测。`UiDeclare` 不是 effect family、
row entry或 user value，v1不定义这个名字；ViewPlan/ActionPlan构造与 runner bookkeeping由上述 ordinary
adapter interfaces和 privileged evidence分层承担，绝不产生 `Anonymous(UiDeclare)` 或
`Named(_,UiDeclare)`。

Conformance必须包含完整21-entry canonical object与 canonical-byte golden；把 producer
输入 block顺序完全反转仍生成相同 bytes，而把 encoded `bindings` 中任意相邻 pair交换则稳定
`first-party-registry-noncanonical-order`。每个 binding分别做 id/source/slot/type/fresh/direct/
callback type/contract/scheme/evidence/kernel的 single-field mutation。至少还要独立覆盖：unknown object/union tag；
missing/extra field；duplicate/gapped/wrong-kind generic或fresh binder；pack-next删除 rho binder；
dangling binder reference；direct删除 temporal；pack-next、try-with-packed-next或
resource loader callback删除 temporal；orphan contextual/callable slot；orphan callback；duplicate callback
name；callback `parameter_slot`或 `acquisition`错连；scheme trigger/captured/generated漏项、重复、交叠、
wrong cardinality或 forward dependency；callback type与 direct parameter不等；signal.map退回普通
TypeRef transform但保留 callback；`ResourceLoaderContractV1`缺失、错 callback、错 storage/generation
owner或 K/A/E；`ActionPlanContractV1`缺失或错 owner/generation/revision/event；unknown evidence rule/argument；kernel tag与 ID不匹配；duplicate/missing/extra ID；
`ActionPlanContractV1.event_parameter_index`缺失/非 1、`occurrence_policy`缺失/错误；
NFC别名 ID；非 canonical callback顺序；非 canonical bindings顺序。所有这些必须在进入
CallableInterface/Kernel lowering前稳定 exact Decode/ContractWF拒绝。
另覆盖 type matrix每个 constructor的 wrong module/name/arity/argument kind/target M3 variant，
`Unit` exact Legacy wrapper positive与 `BuiltinTypeV2` reject，FrameClock exact Effect-family legacy nominal
positive及 ordinary `NominalTypeV2`/wrong declaration-kind rejects，并证明 `Ty(ParkContractV2)`不存在；
每个 `EraseSchemeTypeV1` carrier逐行有 positive，wrong carrier/payload/static-ref/public escape/ordinary-M3误用
逐项 reject；
function template伪造 contract、SchemeOnly进入 outward M3、unknown type/row/suspension/world/flow/construction tag、wrong evidence arity/sort、
callback actual contract与 template不匹配、opened-package component被误标 generative、
pack shared-private binder被误标单侧 visibility、flow path重排/drop/join、以及 static scope进入
outward M3 type；instantiation site wrong call/sealed origin、route/world/site/preorder、Q rule mapping、
operation LatentSite field、referenced direct site的 missing/duplicate allocation、无 Q/Λ call伪造 unused allocation、
non-operation retained Q仍为 provisional site 0、
callback obligation/local-site dangling mapping、Q-local-0与Λ-local-0同路径 collision control、wrong item namespace、
callback ID/site rebase/permutation/dangling link都须 reject；golden必须逐字段含完整
computation/Q/Λ/capture/usage/origin且证明 `applications` 无伪造 intrinsic entry。
`Signal::track.body` 与 `UiBuilder::render.transform` 另各有 missing/wrong storage owner、
short-lived borrow/capability capture、wrong eta或 stale/foreign gamma/nu invocation-scope
mutation；缺少 `RetainedCallbackContractV1` 或配套三项 lifetime proof也必须在安装前拒绝。另用同一
compiled call-site做两次 Resource admission、两次 track installation与两次 UI admission：分别证明
`rho_child₀ != rho_child₁`、`eta₀ != eta₁`、`gamma₀ != gamma₁`、每个 `nu_j=UiRevisionOf(gamma_j)`且
`nu₀ != nu₁`；把任一 first tuple ref替到 second的 type/computation/evidence/Q/Λ/capture/usage任一深度都稳定
`first-party-callback-scheme-mismatch`。Signal::track另覆盖 body不读 track仍由 unique builder witness解 rho、
missing/duplicate/foreign builder witness、UiRunSignal scheme漏/伪造 witness、ordinary M3 ref冒充 scheme fresh
identity、wrong scheme preorder/fresh slot/kind拒绝，以及 callback-only A/row constraint的零解/多解拒绝。
try-with-packed-next另逐项证明 captured opened owner/identity/summary用 exact package-component ref，换 source/
component或伪造普通 M3 slot拒绝。`candidate.action.body` 单独删除/换 owner的 Outlives proof或只保留
ActionSafeRow时必须在 plan创建前拒绝 short-lived capture；另逐项删除、复制或替换其末尾
`ShareableV1(E)` / `EventOccurrenceStorageV1(rho,gamma,E)`，把 storage owner换成 foreign rho、generation换成
stale/foreign gamma、callback参数 1换成 `E2`、action entry保存的 event witness/action plan/revision任一错配，
以及以 non-Shareable、non-BoundarySafe、含 affine Owner/capability、borrow/resumption或 private static scope的
event type实例化，都必须在 plan创建或 listener prepare前稳定拒绝。两项新增 mandatory static evidence
追加在原 evidence array尾部，既有 Q-producing evidence index不重编号；21-entry canonical object/bytes golden
仍因新 fields/evidence而必须更新。`async.await-task` 也在原 evidence array尾部追加 exact
`ShareableV1(R)`；删除、复制、换成另一 type或 non-Shareable R actual都在 `instantiate_first_party` 前拒绝，
existing OwnerParking Q evidence index保持不变。

Entry-owner conformance对七个 contextual mapping逐一做 exact positive，并逐行至少覆盖：删除
`entry_owner` field、改为 `NoCallbackEntryOwnerV1`、换成同 kind foreign owner、跨 admission复用旧 owner/lease，
以及让 nested `FirstPartyCallerScope.current_owner` 不等于 active entry owner；signal.map则做 null/no-rebind
positive和伪造 exact owner reject。pack/resource各删除 `ChildOwnerV1`，open分别删除 package lease/private
scope，track删除 CurrentOwner或OwnerAuthority，run删除 under-owner authority，render换 UiBuilder root或 storage
owner，candidate换 receiver/ActionPlan storage owner，都必须在 callback启动前稳定
`first-party-callback-entry-owner-mismatch`，并证明 Abort/Transfer path也恢复先前 entry phase。

`SchemeActualSummaryV1` 至少有三条 complete-root golden：track body的 `kernel_scope_refs=[eta@1]`、
try-open body的 `[]`、UiRun frame的 `[i@0]`。逐项 mutation typed-kernel preorder、scheme root/type、runtime
source/type/origin、ref sort/duplicate/missing/extra，以及把 current-owner M3 ref或 opened component塞进 array；
还要只改 typed node的 nominal-index/provenance/capture/usage任一 observer，证明 ContractWF读取完整 typed
authority而不是 erased view。Concrete trigger materialization必须逐 observer与 full M3 ValueSummary相等；从
erased carrier反推、保留 static ref或对 typed facts静默补默认都拒绝。

Projection/output conformance分别给纯 M3与 scheme-template Q/Λ complete root：验证 typed occurrence preorder、
sorted scoped-ref closure、final obligation ID、nullable/exact site key与 final site slot。将两种 value variant
互换、混在同一 output、错 preorder/ref/key/ID/site、trigger后 reallocate/retype或 materialized bytes不等均
拒绝。另从一个 M3-compatible result开始，分别只在 computation、Q、Λ、evidence、capture、usage与 origin
深层加入一个 non-M3 ref，七条 mutation都必须选择 `SchemeFirstPartyInstantiationV1`；删掉最后一个 non-M3
ref则必须回到 M3 output，证明选择不是 result-only heuristic。

#### 8.4.2 Structural registry 与唯一 root

```text
StructuralIntrinsicRegistryV1 = {
  artifact: "StructuralIntrinsicRegistryV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  bindings: [StructuralIntrinsicV1; 2]
}

StructuralIntrinsicV1 =
    {
      kind: "StructuralIntrinsicV1",
      id: "Cire-v1.0/structural/build-string",
      source_form: "StringInterpolationV1",
      origin_kind: "SealedIntrinsicV1",
      kernel: "BuildStringV1",
      contract: "BuildStringContractV1"
    }
  | {
      kind: "StructuralIntrinsicV1",
      id: "Cire-v1.0/structural/control-finally",
      source_form: "@control::finally",
      origin_kind: "SealedIntrinsicV1",
      kernel: "ControlFinallyV1",
      contract: "FinalizerContractV1"
    }

IntrinsicRegistryRootV1 = {
  artifact: "IntrinsicRegistryRootV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  first_party: {
    artifact: "FirstPartyRegistryV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  },
  structural: {
    artifact: "StructuralIntrinsicRegistryV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  }
}
```

Structural bindings按 ID NFC UTF-8 bytes严格递增且 exact两项。所有 object exact
fields，child hash是各 child递归 NFC后 RFC 8785/JCS UTF-8 bytes的 SHA-256；root
不内嵌或重解释 child。`BuildStringContractV1`把 literal byte segment与 hole按
source order各求值一次；hole解析 exact locked-core `Show`，保留自己的 effect/flow，
format step ProtocolPure。Functions、handlers、capability、Owner、resumption、
Task/Resource与 Bytes没有 implicit Show。

`FinalizerContractV1`建立 sealed suffix-ledger entry；cleanup NoSuspend、所有 path
Returns Unit、无 outward Abort/Transfer，并满足 phase/Owner/capture/usage；multi-shot
只在 cleanup Replayable时允许。Body的 Returns/Aborts/Transfers先执行或移交该
responsibility再保留原 tag。Derive虽用 `SealedIntrinsicV1` origin，但由 data
declaration与 `ImplEvidenceV1`闭合，不是第三个 structural binding。


`Task[rho,R]` 要求 `Shareable(R)` 与 `AsyncBoundarySafeV1(rho,R)`，
handle可复制且是 multi-waiter broadcast；只有
`Async::await`，不存在 `Task::await`。取消一个 waiter不取消 producer/其它 waiter。
Central cancel只适用于 `Task[rho,TaskOutcome[A,E]]`，且需要 exact task-owner authority；
`CancelReason` v1只有 sealed `ExplicitCancel`。`CloseReceipt[R]` 是 cleanup supervisor
完成的不可取消 latch，不是 Task；重复 close返回同一 receipt/report identity。

Resource唯一是 `SwitchLatest + LatestEpoch + keep-last-good`：

```cire
let resource = Resource::switch_latest(
  under = resource_owner,
  keys = selected_key,
) { child_owner, key =>
  load_key(key, under = child_owner)
}

let view = Resource::view(resource)
let receipt = Resource::dispose(resource)
```

Loader NoSuspend、无 Abort/Transfer并返回
`Task[rho_child,TaskOutcome[A,E]]`。严格更新 key revision stale当前 candidate，
只 retain最新 revision；last-good保持到 replacement success。Failure/cancel发布
`ResourceView.FailedLoad`并携带 previous，close/retire exactly-once。没有 merge/
concat/exhaust或 `Resource::next/snapshot`。
`K/A/E` 均必须 Shareable 并具有 exact Owner-storage boundary evidence；
loader产生的 Task 必须属于该 admission 的 direct child Owner。

唯一 Resource→Signal→UI root是：

```cire
@ui::run_signal(
  under = app_owner,
  backpressure = CoalesceLatest,
) { frame, ui =>
  let resource = Resource::switch_latest(
    under = ui.owner,
    keys = selected_key,
  ) { child_owner, key =>
    fetch(key, under = child_owner)
  }

  let model = Signal::track(frame) { track =>
    Model(
      remote = track.read(Resource::view(resource)),
    )
  }

  ui.render(model) { candidate, current =>
    let on_save = candidate.action { snapshot, event =>
      let draft = snapshot.read(draft_source)
      save_app.save(draft, event = event)
    }
    render_view(current, on_save = on_save)
  }
}
```

Surface equation固定为 `Signal[i,A] = Step(A, Next[i,Signal[i,A]])`，要求
`Shareable(A)`；sealed lowering才向 `Next` 的 evidence-indexed Kernel form插入
不可 source-spell 的第三个 `SignalTailContract[i,A]` argument。Hidden tail contract
固定 advance、capture nonescape、Owner cleanup与 full-flow release，不可由用户提供。
Signal是 pure clock-indexed value；`track.read`
唯一建立 invalidating
dependency，`snapshot.read`只读 fixed revision。`ui.render` callback必须直接返回
同 generation `ViewPlan[gamma]`; `candidate.action` callback固定
Action/NoSuspend/same-world/
Returns Unit。它可以调用已有 exact NoSuspend attributed operation，但不能 await、Abort、
Transfer、raw Resume或 generic spawn。

`map_signal` 的 transform必须 empty row、NoSuspend、Returns-only、
`TemporalStable(i,env)`、`CrossWorldSafe(i,capture)` 且 `Shareable(B)`；同名
ordinary function不能伪造该 sealed tail evidence。

每个 event type `E` 必须有 `ShareableV1(E)` 与 exact
`EventOccurrenceStorageV1(rho,gamma,E)` evidence。每个 occurrence在 generation
gate仍 Open时，立即将 exact typed payload存入
OwnerStorage并取得一个从 Queued贯穿 Running 的 linear lease。Mount-wide dispatcher按
monotone ordinal FIFO；Released传递并 release exact payload，Finalized在不调用用户代码时
release同一 payload。Close/stale先关 gate、finalize queued、等待唯一 running，再允许
listener/plan cleanup。没有 hidden host queue、late reread、shadow count、event coalescing
或 per-event CleanupLedger item。

`Event` nominal type保留给显式库协议，但 generic `on`/`on_async` 不属于 v1 reachable API；
UI event entry只由上述 typed action plan建立。Generic public `Plan`/`CommitTicket`/
`CommitGate`也不在 surface；它们若存在只能是 sealed runtime implementation detail。

## 9. 不采用宏系统

**已决定**

Cire 不设计 token macro、AST macro 或 typed hygienic macro。以下都不成为宏：

- UI component；
- `state`、`resource`、`boundary`；
- `with`；
- trailing lambda；
- stable lexical site；
- interpolation、derive、inline handler、`while`/`for`。

UI widget constructor 是普通 adapter call，但只能出现在 §8 的 exact
`ui.render` transform 内，不得重新引入单参数 `Source[User]`、generic
`Observe` row 或可导出的 bare `View` root：

```cire
ui.render(model) { candidate, current =>
  render_view(current)
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
- argument 起点的 `name =` 先识别为 label，不会被 assignment
  expression吞掉；positional assignment 必须写成 `(slot = value)`；
- anonymous `fn` 使用可推导/可标注的 lambda parameter grammar，不复用
  具名声明的 typed `ParamList`；
- function type 的 parameter list始终有括号：`(A) -> B`、
  `(A, B) -> C` 与 `() -> R`；不接受 bare unary `A -> B`；
- `factory() { ... }` 给当前 call 追加 lambda，不调用返回值；
- 换行只是 trivia；block 由 maximal expression boundary 分项，最后一个未加
  `;` 的表达式才是结果；
- handler clause 使用 `PatternList`，不是 declaration `ParamList`；
- operation declaration 可以携带 closed secondary effect 与 temporal
  contract；v1 不接受 open secondary row tail。

## 11. Explicit profile-boundary registry

<a id="rule-r06-no-generic-event-on"></a>

这一节是 `Cire-v1.0` 的 closed boundary registry。下列项目没有
implementation-defined含义；excluded spelling最多进入 recovery CST。

| Boundary | Cire-v1.0 status |
|---|---|
| parameter `~` / call punning | Removed；`surface-tilde-label-removed`。 |
| surface `cap F` | Removed；direct capability binder只写 `app : F`，其它裸 Effect-kind value位置拒绝。 |
| `defer` | Reserved/rejected；只允许 sealed `@control::finally` runner。 |
| `val` / builtin `yield` / builtin `try` | Excluded；programmable control由 algebraic effects表达。 |
| explicit forwarding / masking | Excluded；只有 exact automatic ForwardContract。 |
| public raw completion port / Resume callback | Excluded；只暴露 generation-bound opaque port/gate。 |
| multi-shot local mutation | Closed rejection；live mutable place不能跨 `ctl`，没有隐式 snapshot/clone/share。 |
| general one-call/many-call marker | Excluded；one-shot只存在于 sealed resumption machinery。 |
| general existential/rank-2/`OwnedNext` | Excluded；只公开 shared sealed `PackedNext[A]`。 |
| generic `Event::on/on_async` | Excluded；Event nominal可由未来显式 bridge使用，UI只经 typed ActionPlan。 |
| public generic `Plan`/`CommitTicket`/`CommitGate` | Excluded；UI plan/commit authority scheme-private。 |
| typed `discontinue` | Excluded；没有 payload/world/cleanup/terminal rule。 |
| shallow handler / user macro / user operator | Excluded。 |
| wildcard import / dependency scan / implicit extension activation | Excluded。 |
| GAT / trait object / specialization / negative impl / `Drop` / `Try` | Excluded。 |
| general `as` cast / implicit numeric conversion | Excluded；只用 exact named conversion。 |
| null / truthiness / raw pointer / pointer-sized integer / builtin SIMD | Excluded。 |
| explicit `Has` / `All` / `Only` row predicate | Grammar-reserved、RowWF拒绝；v1只冻结 `Lacks`。 |
| independent ability `impl` | Grammar-reserved、profile-rejected；ordinary trait `impl` accepted。 |
| Effectful `Later` / general affine values / portable general handlers | Excluded research boundary，不是 implementation freedom。 |
| generic checkpoint API | Excluded；Source/Live使用 sealed fixed-Epoch first-party checkpoint runner。 |

未来接受任何 excluded项必须 mint新 profile，并原子补齐 grammar、elaboration、Core、
wire、diagnostic与 conformance；parser recovery不能把它升级为 language feature。

## 12. Package-qualified callable metadata 与 profile resolution

Surface resolver先从 lockfile得到 exact `PackageInstanceIdV1`，再解析 namespace与
declaration path。User source没有 module/file-path declaration；所有本 package ordinary source identity
的 canonical module固定为 `['pkg-' + digest, 'root']`，top-level path是 declared name。Inherent member
在 owner path后追加 member；trait default与 impl method使用 Formal
`CanonicalCallableExport` 的 reserved、source不可写 subkey。任意 directory/file/visitor/import alias或
另一个 module/path split都不能改变 identity。这样当前 `CallableInterfaceV1` 的
`(module,export_path,interface_hash)` edge与 package-level
package-instance identity共存；不同 locked version永不因同名 module/export相等。

Package级 `CireLanguageInterfaceV1` 是唯一 separate-checking/API-hash root。它按 exact
PackageInstanceId/import table持有 primitive/data/trait/impl/extension/effect/const roots，
并对每个 exported callable持有 `CallableInterfaceV1` hash edge与精确包含
free/inherent/extension/trait-default/impl-method classification、generic trait/ability requirements、
ConstSafe/ProtocolPure/MayTrap facts的 `CallableContractFactEvidenceV1`。每个 callable仍唯一沿
`CallableInterfaceV1 -> FunctionContractV3`到 typed computation；foundation facts不
偷偷增加 V3 field，也不由 importer猜测。Public call必须先验证 package root再沿 hash edge，
raw V2/V3 Core hash不能旁路 interface。

Data/alias、ordinary trait、ability与 effect declaration分别把 `TypeHead` constraints写入自身
`requirements`；impl把 `GenericClauses` requirements与 impl-header goal分开；operation只保存自己
unconstrained Type binders，`requirements` 固定为两个 empty arrays。Public callable fact的 `requirement_scopes` 必须 exact覆盖 V3 root与每个
local declaration，并分别保存包含 lexical parent + own clauses的 complete requirement closure，与该
scope binders exact交叉核对。Package-private/local callable在 typed HIR中保留同一 facts，直到每个 local application
选择并 discharge exact impl/callable evidence，再降成 direct typed edge；它们没有 unresolved public
wire obligation，也不能把 constraint silent erase进 V3。Ability/effect identity、arity、associated
items、operation table与 header conformance只来自 package declaration closure；retained TR0 family
catalog不能参与 successor resolution。

Ordinary trait requirement不为 generic method预先分配一个 monomorphic dictionary slot。Normalized HIR
中每个 direct trait-method application各分配一个 contract slot；method-local generic arguments在该 use
fresh实例化。Exported root把 root/local declaration的这些 use按 lexical application preorder写入
`CallableContractFactEvidenceV1.trait_method_uses`，并与对应 V3 application/contract binder逐项交叉
核对；同一 method以不同 type argument调用是不同 use。Method value若离开 direct-call位置会要求
rank-2 evidence，v1按 §2.3拒绝。

Callable classification也不是 export-path convention。`FreeCallableV1` 不进入 dot candidate；
`InherentCallableV1` 记录 owner nominal与 optional exact receiver；`ExtensionCallableV1` 记录 mandatory
receiver；`TraitDefaultCallableV1` 回指 trait identity/method ordinal，`ImplMethodCallableV1` 另外回指
exact impl evidence。Bodyless trait signature没有 callable kind/edge；default body与每个 explicit impl body
分别有唯一 inverse link，不能共用一个未区分 body role 的 tag。Import `use @pkg::name` 只有在该 exact fact为 extension时才激活 dot name；importer不能从
文件名、首参数相似性或 package扫描重新分类。

Free/extension source identity使用本 package `ValueV1` path；inherent declaration owner必须是本 package
未实例化且已声明的 `StructV1 | EnumV1 | NewtypeV1 | OpaqueV1`，
`TransparentAliasV1` 必须先展开且不具有 inherent-owner identity；source `FunctionOwner` 带 TypeArgs或
foreign/alias owner在 HIR前拒绝。Public
inherent owner还必须 public。Const与 free/extension共享同一个 source value namespace，所以同
`(module,path)` 的 const/def/extend def冲突；receiver type或不同 root array不能制造 overload。
Package root除 public entries外，还 exact携带被 public V3/const/default/impl递归引用的
`PackageV1` support closure；这些 entries只供 importer WF，不进入 resolver。所有 importer-visible
coherent impl/derive是 closure seed，即使没有 public callable直接引用它。

Surface按上述 declaration/parameter rules生成 Formal
[`function-contract-v3`](temporal-reactivity-formalization.typ) 所定义的唯一
`CallableSurfaceSignatureV1` / `ParameterSurfaceSlotV1` wire；本文不复制 public
interface schema。Slots严格递增且与 Core call-entry binder set相等。`ImplicitReceiverV1`与
`PositionalOnlyV1`没有 label/defaultable field；ordinary simple parameter使用
`NamedOrPositionalV1`。Public label是 source ABI，不受 alpha rename保护。

用户 declaration 的每个 `(module,export_path)` 必须唯一；v1 不允许用
同一 public export path 表示 overload。只有 sealed member/intrinsic producer可拥有
多个 source-overload，且它们仍必须分配 distinct stable export paths；违反报
`public-overload-requires-distinct-export-path`。Public label rename只改变该 callee
interface bytes/hash；当 Core contract不变时 callee Core hash保持。但所有 caller
dependency edge必须换用新 interface hash，因而 caller Core/interface hash递归级联。
Add/remove default 同时改变 surface interface 与 Core
`ProvidedOrOmitted`/`DefaultPrologueV1`，两类 hash都必须改变。

Surface只提供 canonical normalized-HIR lexical preorder、resolved declaration identity、
source-order temporary与 default/label facts。Formal 的 `function-contract-v3` rule独自
据此分配/验证 V3 root/local slots、dependency table、`DefaultPrologueV1`、SCC与
hash；本文不复制其 wire algorithm。跨 source visitor/map/serialization order的结果
必须相同，且 public callable SCC按 Formal rule稳定拒绝。

Artifact canonicalization对 schema指定 identifier/path/label做 NFC并使用 RFC 8785/JCS。
Source semantic `String`不 normalize；public Char/String/Bytes const值分别用 scalar或
exact UTF-8/byte sequence encoding，不以可被 NFC改写的 raw JSON string承载 payload。
因此 canonical bytes不能改变程序值。

当前 repository是 specification/conformance repository，没有 compiler/runtime/LSP。
`Cire-v1.0` specification-model gate证明 closed schema、decision coverage与 finite
protocol machine；implementation release仍需同一 frontend、checker、backend/runtime、
Component adapter与 LSP通过 `spec-status.md`列出的独立 gates。

## Appendix A — Cire-v1.0 complete grammar


> **Profile:** `Cire-v1.0`
>
> 本文是实现无关的 canonical grammar。未来 parser 必须实现这里定义的 token
> language、优先级、附着和恢复边界；parser 的既有行为不能修改本文含义。
> `def` 只声明具名函数/方法；`fn` 构造匿名函数值，或在 §2.3 唯一允许的 local-let
> annotation写显式 rank-1 scheme；
> `fun` 只表示 effect 的唯一尾恢复 mode。

本文使用 PEG 记号：`/` 为有序选择，`*`、`+`、`?` 为重复，`&` / `!` 为
正/负 lookahead，`CUT` 表示识别到判别 token 后不回退。大写名字是 token，
CamelCase 名字是 grammar rule。语义验证写在 grammar 后，不伪装成 parsing。

### A.1 词法

源码先 strict UTF-8 decode；BOM拒绝。每个 token同时记录 UTF-8 byte 与 UTF-16
code-unit 半开区间，且两者都落在 scalar boundary；这只影响 origin/artifact/LSP，
不改变 token language。

`UnicodeWhiteSpace`、`XID_Start` 与 `XID_Continue` 是这里声明的三个 external
lexical terminal，分别精确取 Unicode 16.0.0 UCD 的 binary property
`White_Space`、`XID_Start` 与 `XID_Continue` scalar set；surrogate永不属于 terminal。
升级 UCD 版本会改变 tokenization，必须版本化 language profile，不能静默跟随 host
library。除这三个已声明 terminal与 PEG meta operator `CUT` 外，Appendix A不得引用
未定义 nonterminal。

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

IntLiteral     <- ("0x" HexDigits / "0o" OctDigits / "0b" BinDigits / DecDigits)
                  IntSuffix?
IntSuffix      <- "i8" / "i16" / "i32" / "i64"
                / "u8" / "u16" / "u32" / "u64"
FloatLiteral   <- DecDigits "." DecDigits Exponent?
                  FloatSuffix?
                / DecDigits Exponent FloatSuffix?
FloatSuffix    <- "f32" / "f64"
Exponent       <- ("e" / "E") ("+" / "-")? DecDigits
CharLiteral    <- "'" CharElement "'"
StringLiteral  <- '"' StringPart* '"'
StringPart     <- Escape / EscapedDollar / Interpolation / StringScalar
EscapedDollar  <- "\\$"
Interpolation  <- "${" Expr "}"
ByteLiteral    <- 'b"' ByteElement* '"'
CharElement    <- Escape / !("'" / LineTerminator) .
StringScalar   <- !("\\" / "$" / '"' / LineTerminator) .
ByteElement    <- !"${" (PrintableAsciiExceptQuoteBackslash
                / "\\" ("n" / "r" / "t" / "0" / "\\" / '"')
                / "\\x" HexDigit HexDigit)
PrintableAsciiExceptQuoteBackslash <- [\u{20}-\u{7E}] except '"' and "\\"
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
ability abort as break cap const continue ctl def defer derive effect else enum
extend false effects fn for fun handler if impl in let loop match may_suspend mut
newtype next opaque pub resumes return struct trait true type use while with once open
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
DERIVE      <- "derive" !XID_Continue
EFFECT      <- "effect" !XID_Continue
EFFECTS     <- "effects" !XID_Continue
ELSE        <- "else" !XID_Continue
ENUM        <- "enum" !XID_Continue
EXTEND      <- "extend" !XID_Continue
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
NEWTYPE     <- "newtype" !XID_Continue
NEXT        <- "next" !XID_Continue
ONCE        <- "once" !XID_Continue
OPAQUE      <- "opaque" !XID_Continue
OPEN        <- "open" !XID_Continue
PUB         <- "pub" !XID_Continue
RESUMES     <- "resumes" !XID_Continue
RETURN      <- "return" !XID_Continue
STRUCT      <- "struct" !XID_Continue
TRAIT       <- "trait" !XID_Continue
TRUE        <- "true" !XID_Continue
TYPE        <- "type" !XID_Continue
USE         <- "use" !XID_Continue
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

`Interpolation` hole 使用与主 lexer相同的 token规则并以 nested-brace depth
匹配 closing `}`；string/comment/char内部 brace不改变 depth。lexer不得把 hole
作为 raw String token。`ByteLiteral`拒绝 raw non-ASCII、Unicode escape、`${` 与
line break。`CAP`、`DEFER`、`TILDE`仍保留 token仅供 recovery diagnostic，不能
出现在 accepted production。

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

TopLevelItem      <- UseDecl / ImplDecl / Visibility? NonImplDeclaration
NonImplDeclaration <- FunctionDecl
                   / ConstFunctionDecl
                   / ExtensionFunctionDecl
                   / StructDecl
                   / EnumDecl
                   / NewtypeDecl
                   / OpaqueTypeDecl
                   / TraitDecl
                   / AbilityDecl
                   / EffectDecl
                   / TypeAliasDecl
                   / ConstDecl

TypeHead          <- UpperIdent TypeParams?
TypeAliasDecl     <- TYPE TypeHead EQUAL Type SEMICOLON?
ConstDecl         <- CONST LowerIdent COLON Type EQUAL Expr SEMICOLON?
ConstFunctionDecl <- CONST FunctionDecl
ExtensionFunctionDecl <- ValidExtensionFunctionDecl
                       / InvalidExtensionSelfDecl
ValidExtensionFunctionDecl <- EXTEND DEF GenericClauses? LowerIdent
                              ExtensionParamList ARROW Type EffectAnnotation Block
InvalidExtensionSelfDecl <- EXTEND DEF GenericClauses?
                            (FunctionOwner COLONCOLON LowerIdent ParamList
                            / LowerIdent
                              (LPAREN RPAREN
                              / LPAREN !(LowerIdent COLON) Parameter
                                (COMMA Parameter)* COMMA? RPAREN))
                            ARROW Type EffectAnnotation Block
ExtensionParamList    <- LPAREN ExtensionSelfParameter
                         (COMMA Parameter)* COMMA? RPAREN
ExtensionSelfParameter <- LowerIdent COLON Type
UseDecl           <- USE UseTarget (AS LowerIdent)? SEMICOLON?
UseTarget         <- PackagePath COLONCOLON Name (COLONCOLON Name)*

StructDecl        <- STRUCT TypeHead LBRACE FieldDecl* RBRACE DeriveClause?
FieldDecl         <- Visibility? LowerIdent COLON Type
                     (EQUAL Expr)? (COMMA / SEMICOLON)?

EnumDecl          <- ENUM TypeHead LBRACE VariantDecl* RBRACE DeriveClause?
NewtypeDecl       <- NEWTYPE TypeHead LBRACE FieldDecl RBRACE DeriveClause?
OpaqueTypeDecl    <- OPAQUE TYPE TypeHead EQUAL Type SEMICOLON?
DeriveClause      <- DERIVE LPAREN TypeName
                     (COMMA TypeName)* COMMA? RPAREN
VariantDecl       <- UpperIdent VariantPayload?
                     (COMMA / SEMICOLON)?
VariantPayload    <- LPAREN TypeList? RPAREN
                   / LBRACE FieldDecl* RBRACE

TraitDecl         <- TRAIT TypeHead LBRACE TraitItem* RBRACE
TraitItem         <- MemberFunctionDecl
                   / MemberFunctionSignature
                   / TraitAssociatedTypeDecl
TraitAssociatedTypeDecl <- TYPE UpperIdent
                           (COLON TypeConstraintList)?
                           (EQUAL Type)? SEMICOLON?

AbilityDecl       <- ABILITY TypeHead LBRACE AbilityItem* RBRACE
AbilityItem       <- OperationDecl
                   / AbilityAssociatedTypeDecl
                   / AssociatedEffectDecl
                   / AssociatedRowDecl
AbilityAssociatedTypeDecl <- TYPE UpperIdent TypeParams?
                             (COLON TypeConstraintList)?
                             (EQUAL Type)? SEMICOLON?
AssociatedEffectDecl <- EFFECT UpperIdent TypeParams?
                        (COLON AbilityConstraintList)?
                        (EQUAL Type)? SEMICOLON?
AssociatedRowDecl <- EFFECTS UpperIdent
                     (COLON RowConstraintList)?
                     (EQUAL RowExpr)? SEMICOLON?

EffectDecl        <- EFFECT TypeHead EffectConformance?
                     LBRACE OperationDecl* RBRACE
EffectConformance <- COLON AbilityRef (PLUS AbilityRef)*

ImplDecl          <- Visibility? IMPL GenericClauses? Type FOR Type
                     LBRACE ImplItem* RBRACE
ImplItem          <- Visibility? (MemberFunctionDecl
                   / AssociatedTypeBinding
                   / AssociatedEffectBinding
                   / AssociatedRowBinding)
AssociatedTypeBinding   <- TYPE UpperIdent EQUAL Type SEMICOLON?
AssociatedEffectBinding <- EFFECT UpperIdent EQUAL Type SEMICOLON?
AssociatedRowBinding    <- EFFECTS UpperIdent EQUAL RowExpr SEMICOLON?

AbilityRef        <- Type
```

Package identity and dependency selection belong to the package manifest. 源文件通过
`@package::name` 和 `Type::member` 使用 package-qualified name；本 profile
不增加 wildcard import。`UseDecl`只绑定一个 exact declaration identity；若它是
extension function，该 local name（或 alias）也是唯一 enabled dot-name。Import
ordinary type/trait不会隐式激活 extension或 impl。

`ImplDecl` 是 ordinary trait与 ability target共享的 lossless CST shape。两个 optional
`Visibility` 只为 committed recovery保留；canonical impl与其每个 item都要求 modifier absent，
否则在 CST→HIR前报 `impl-visibility-not-allowed`。因此 `pub impl`/`pub(open) impl` 与
`impl T for U { pub def ... }` 都可稳定到同一 registered diagnostic，而不会退化为 generic parse error。
Resolver若把左侧 `Type` 解析为 ability，v1 必须在进入 body typechecking前拒绝
`independent-ability-impl-not-in-profile`；只有 §4.5 的 effect-header
`EffectConformance` 产生 ability evidence。Parser recovery或 ordinary trait
target不能改变这个 kind-directed profile boundary。

`Visibility=pub(open)` 只适用于 trait/ability/effect；其它 declaration稳定
`open-visibility-not-applicable`。`NewtypeDecl`必须恰好一个 named stored field。
`OpaqueTypeDecl`只有 owner package可见 representation。`DeriveClause`只允许在
`StructDecl | EnumDecl | NewtypeDecl` closing brace后出现，trait path无重复；opaque/alias
的 Formal `derives` 必须为 `[]`。Component import/export
由 manifest选择 exact `pub def` path，不增加 source declaration production。
`ExtensionSelfParameter` 的 `LowerIdent` lexeme必须精确为 `self`，其 type就是
extension 的 resolved receiver `Self`；extension name不得是 qualified owner form。
缺失/改名该第一 parameter 或使用 qualified extension name 报
`extension-self-parameter-required`。
`InvalidExtensionSelfDecl` 只为这个 committed recovery存在：accepted branch先匹配 exact
unqualified name + nonempty first parameter；empty `()` 或 qualified `ValueName` 落入 recovery并报同一
diagnostic，node绝不进入 Surface HIR。`ValidExtensionFunctionDecl` 中 first parameter名不是 `self` 也在
CST→HIR gate拒绝。
Extension receiver可为任意 well-formed type，包括 primitive、tuple、function、
foreign nominal、capability与当前 generic type parameter；它不继承 trait impl的
orphan、nominal-head或 local-type限制。

Source declaration name sets必须 injective：同一 struct/newtype/record variant的 field、同一 enum的
variant、同一 trait的 associated Type与 method各自在自己的 namespace唯一；ability的 associated
Type/Effect/EffectRow共享一个 associated namespace，operation另成 namespace；effect own operation
name唯一。Associated item与 operation可因 kinded syntax不同而同 spelling；其它重复在 HIR
publication前确定性拒绝，不能靠 ordinal或后写覆盖。
每个 callable/trait method/operation/lambda 的 simple parameter source name同样 pairwise distinct，
因而产生的 `NamedOrPositionalV1.public_label` 也 pairwise distinct；两个同名 slot不能借
type、position或 default来消除 labelled-call 歧义。Pattern parameter仍按其 pattern binder-set exactness检查。

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
EffectConstructorParam <- UpperIdent BinderHoles
EffectAtomParam      <- UpperIdent (COLON AbilityConstraintList)?
BinderHoles          <- LBRACKET UNDERSCORE
                        (COMMA UNDERSCORE)* RBRACKET
AbilityConstraintList <- AbilityRef (PLUS AbilityRef)*
RowConstraintList    <- RowPredicate (PLUS RowPredicate)*
RowPredicate         <- UpperIdent LBRACKET PredicateArgList? RBRACKET
PredicateArgList     <- PredicateArg (COMMA PredicateArg)* COMMA?
GenericValueEnd      <- &(COMMA / RBRACKET)
PredicateArg         <- RowExpr GenericValueEnd / Type GenericValueEnd

TypeArgs             <- LBRACKET TypeArg
                        (COMMA TypeArg)* COMMA? RBRACKET
TypeArg              <- AssociatedArgument / Type / LowerIdent
AssociatedArgument   <- UpperIdent EQUAL AssociatedArgumentValue
AssociatedArgumentValue <- RowExpr GenericValueEnd / Type GenericValueEnd
EffectArgs           <- BANG LBRACKET EffectArg
                        (COMMA EffectArg)* COMMA? RBRACKET
EffectArg            <- RowExpr GenericValueEnd / Type GenericValueEnd

RemovedLabelledParameter <- LowerIdent TILDE COLON Type (EQUAL Expr)?
RemovedCapabilityMarker  <- CAP Type
```

`F`、`F[_]`、`..E` 分别绑定 `Effect`、effect constructor、`EffectRow`；
这由 binder shape 唯一决定。direct parameter `app : F` 是 term binder，不进入 generic
list。Surface为每个 `F`/`F[_]` 保留 exact constructor arity（0/underscore count），并把 atomic
`F` 的 ability constraints写入 Formal `DeclarationRequirementsV1.effect_parameters`；不能只降成一个
无 arity 的 binder。Ability constraint只允许 atomic `F : Ability[...]`；本 profile不定义
`F[_] : Ability` 的 pointwise higher-kinded evidence，constructor binder后跟 colon因此不进入
accepted grammar。每个 Type parameter的 ordinary trait constraints进入
`ordinary_traits`；每个 `..E` 与 normalized `Lacks` set进入同一 declaration的 `row_binders`。
这些三域 facts在 source order resolve 后按 Formal canonical order序列化，任何一个都不能依赖
source重读或 inferred package scan。每个 ordinary trait requirement进一步按 Formal rule分配
associated-Type hidden binders，每个 actual method use才分配自己的 monomorphic contract binder；lambda、
local declaration与 §2.3 允许的 local scheme同样携带这些 structural Core obligations，并由 owning
callable fact的 exact `requirement_scopes`覆盖，不能因没有独立 package edge而丢失。每个 `F[_]` binder在所有 root/local/lambda/local-scheme scope唯一降为
`EffectConstructorBinderV3(slot,arity)`；application唯一降为
`EffectParameterConstructorV3(slot,arity)`，wrong slot/arity
不能回退 nominal constructor。Named/generic call给该 binder的 actual唯一进入
`EffectConstructorSubstitutionV3`：nominal Effect declaration或 caller constructor parameter都必须 exact
arity，不能塞入 ordinary Type/atomic Effect或 partial constructor。`PredicateArg`、`AssociatedArgumentValue` 与 `EffectArg` 的每个有序分支都在分支内
要求 `GenericValueEnd`，因而 `E1 | E2` 不会被首个 reference 截断，`(Int) -> Int`
也会在 row 分支的 end lookahead 失败后重试为 `Type`。对于完整 bare name/path 或
parenthesized reference 这类共同 syntax，CST保留同一 token span，resolver再由 owning
predicate/binder/declaration 的期待 kind 唯一重分类；不得由 PEG 分支顺序猜 kind。
`AssociatedArgument` 的 `UpperIdent =` lookahead先于 positional `Type`，但 owning constraint
domain决定它的唯一 meaning。在 `TypeConstraintList` 中 target必须解析为 ordinary trait，且 named
argument只可指该 trait的 zero-arity associated Type；它进入 Formal
`TraitGoalV1.associated_types`。在 `AbilityConstraintList` 或 effect header中 target必须解析为
ability，resolver才按 declaration把右侧重分类到 `Type`、`Effect` 或 `EffectRow`，并按 §4.4
区分 partial generic constraint与 total concrete header。两个 domain都拒绝 wrong declaration kind、
unknown、duplicate与 value-kind mismatch，并稳定使用 `associated-contract-mismatch`；只有 concrete
ability header拒绝 missing-without-default。普通 nominal type application不能借 named argument
伪装成 constraint。只有 `AbilityItem` 中的 associated Type/Effect
declaration constraint与任意 nonempty associated `TypeParams` 走本 profile的 Kind-stage
registered stable reject；ordinary `TraitAssociatedTypeDecl` 的 zero-arity Type
constraint是 accepted trait contract。
每个 ordinary `TraitGoalV1` 的 associated equality在 resolve后按 trait item ordinal严格递增、
unique/in-range且 name/kind exact；associated-Type declaration的多个 constraint是 conjunction，按完整
normalized goal的 NFC+JCS semantic key排序且无重复，source order不得改变 wire bytes。

Recovery parser只在 parameter boundary构造
`RemovedLabelledParameter` 或 `RemovedCapabilityMarker`，并分别报
`surface-tilde-label-removed` 与 `surface-cap-marker-removed`。这两个 node
不可进入 accepted Surface HIR，也不得回退成普通 type/name parse。

`RowPredicate` 的通用 CST只为明确 profile boundary而保留。本 profile在 RowWF
只接受名称 `Lacks`、恰好一个可解析 row entry argument；`Has`、`All`、`Only`
以及其它名称统一拒绝 `row-predicate-not-in-profile`，不能由库中同名类型绕过。

### A.4 类型与 effect-row 表达式

```peg
Type                <- GenericFunctionType / FunctionArrowType / TypePrimary
GenericFunctionType <- FN GenericClauses ParamTypeList
                       ARROW Type EffectAnnotation?
FunctionArrowType   <- ParamTypeList ARROW Type EffectAnnotation?
TypePrimary         <- TupleOrGroupedType
                     / TypeReference
TupleOrGroupedType  <- LPAREN TypeList? RPAREN
TypeList            <- Type (COMMA Type)* COMMA?
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

`GenericFunctionType` 保留一个 lossless CST node，但 accepted occurrence严格受 §2.3 的 local
rank-1 boundary约束：它只能是 immutable simple-name `LetItem` 的整个 annotation，不能递归出现在
其它 `Type` child。对应 generic `LambdaExpr` 必须是 initializer本身，不能先经 call/record/container/
branch包装。Resolver在进入 Type/Row inference前检查该 ancestor/initializer关系；失败是确定性
frontend rejection，不能降成普通 `FunctionTypeV2` 或把 scheme binder漏进 package wire。

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
  extension 不能通过。v1 只有 extension 与 union，没有 subtraction；
- `{F}` 与 `{app}` 分别解析到 anonymous family 与 named identity，不能互换；
- `Read[app]` 不是源语法。诊断可以用它解释 `{app}` 的 family。

`InvalidRowLiteralMultipleTails` 只构造 committed recovery CST。第二个
`DOTDOT` 后的 `CUT` 保证 `{..E1, ..E2}` 不退化成不稳定 parser error；
RowWF 必须以版本化 `row-literal-has-multiple-tails` 拒绝该 node并建议
`E1 | E2`。它不把多个 literal tail接受进语言。

`Next[frame,A]` 使用普通 `TypeReference` / `TypeArgs` CST；kind checking 将
`frame` 解释为受限 clock identity。它不会把所有 lower identifier 都提升成
一般 dependent type。

Effect-kind `F`只在 signature/kind stage确认 direct capability parameter位置时
可作为 `app : F` 的 source type并产生 `Cap[i_app,F]`。没有一般 source
CapabilityType production；`CAP` token只构造 `RemovedCapabilityMarker` recovery node，
稳定诊断 `surface-cap-marker-removed`。

### A.5 函数、operation 与参数

```peg
FunctionDecl       <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation Block
FunctionSignature  <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation SEMICOLON?
MemberFunctionDecl <- DEF GenericClauses? LowerIdent ParamList
                      ARROW Type EffectAnnotation Block
MemberFunctionSignature <- DEF GenericClauses? LowerIdent ParamList
                           ARROW Type EffectAnnotation SEMICOLON?
FunctionName       <- LowerIdent
                    / FunctionOwner COLONCOLON LowerIdent
FunctionOwner      <- (PackagePath COLONCOLON)?
                      UpperIdent (COLONCOLON UpperIdent)* TypeArgs?

ParamList          <- LPAREN Parameter
                      (COMMA Parameter)* COMMA? RPAREN
                    / LPAREN RPAREN
Parameter          <- SimpleParameter / PatternParameter
SimpleParameter    <- LowerIdent COLON Type (EQUAL Expr)?
PatternParameter   <- !(LowerIdent COLON) Pattern COLON Type

MissingNamedFunctionRow <- CONST? DEF GenericClauses? FunctionName ParamList
                           ARROW Type !BANG Block
                         / EXTEND DEF GenericClauses? LowerIdent
                           ExtensionParamList ARROW Type !BANG Block
                         / DEF GenericClauses? FunctionName ParamList
                           ARROW Type !BANG MissingSignatureEnd
MissingSignatureEnd <- SEMICOLON / &(DEF / TYPE / RBRACE)

Mode               <- ABORT / FUN / ONCE / CTL
OperationDecl      <- Mode OperationTypeParams? LowerIdent OperationParamList
                      ARROW Type OperationSecondaryAnnotation?
                      OperationContractItem* SEMICOLON?
OperationTypeParams <- LBRACKET UpperIdent
                       (COMMA UpperIdent)* COMMA? RBRACKET
OperationParamList <- LPAREN OperationParameter
                      (COMMA OperationParameter)* COMMA? RPAREN
                    / LPAREN RPAREN
OperationParameter <- LowerIdent COLON Type
                    / !(LowerIdent COLON) Pattern COLON Type
OperationSecondaryAnnotation <- BANG CUT
                      (ClosedRowLiteral / InvalidOperationSecondaryRow)
ClosedRowLiteral   <- LBRACE (RowEntry (COMMA RowEntry)* COMMA?)? RBRACE
InvalidOperationSecondaryRow <- RowExpr
OperationContractItem <- RESUMES NEXT / MAY_SUSPEND
```

Operation 的唯一 generic domain是无 constraint的 `OperationTypeParams`，与 retained/successor
`OperationSignatureV2.type_binders` 一致；effect constructor、effect atom、row generic与 ordinary-trait
constraint只属于有 exact evidence-substitution 边的 named function/declaration contract，不能在 operation
header出现。Operation parameter可用 simple name或
irrefutable positional pattern，但没有 default；其 `CallableSurfaceSignatureV1` slot因此全部
`defaultable=false`。这些限制是 accepted grammar boundary，不由 importer猜测或 silent erase。

Operation 的 secondary effect annotation 是 clause/handler 聚合的一部分，不能
因为 family row 最终被消除而丢失。对
`once read() -> A ! {Log}`，`{Log}` 就是 `SecondaryRow`；调用 row 是
argument rows、operation dispatch entry 与该 annotation 的 union。Checker
另存带 call-site/prompt route 的 attributed demand `Δ`，public row只是其
擦除。

v1 要求 operation 的 secondary row **closed**：允许 `! {}`、
`! {Audit, Log}`，拒绝 `! E`、`! {Audit, ..E}` 与任何包含 rigid row
variable的 union。一般 function/result effect annotation仍使用完整
`RowExpr`；限制只作用于 `OperationSecondaryAnnotation`。这样 interface中的
每个 secondary demand都能序列化成 finite `SecondarySiteV1`，不会把 open
tail伪装成已经枚举完的 site set。
`CUT` 在 `!` 后固定 operation-secondary context；fallback
`InvalidOperationSecondaryRow` 只构造 recovery CST node，WF 必须以版本化
`operation-secondary-row-must-be-closed` 拒绝。它不把 open row接受进语言，
但保证 bare `! E` 与 `! {Audit, ..E}` 不会提前退化成不稳定 parser error。

`def` 是具名、可递归 declaration/generalization boundary；所有 `def`、trait/
impl/default method、extension与 `const def`都显式写 `EffectAnnotation`，pure为
`! {}`。省略只进入 `MissingNamedFunctionRow` recovery并报
`named-function-effect-row-required`。`fn` 只在
`LambdaExpr` 和 `GenericFunctionType` 中出现；`fun` 仅是 operation mode。
`def` 在 expression 或 type 位置必须拒绝。

Core 一律是一元函数。`def f(p1, ..., pn)` elaboration为一个接收 immutable
n-tuple 的递归 Core binding；call 仍先按源码顺序求值 callee 和各 argument，
再按 resolved parameter/label 顺序组装 tuple。它不等于 currying，也不提供
隐式 partial application；需要高阶返回值时必须显式返回 `fn`。

`SimpleParameter`天然有同名 source label并可有 default；`PatternParameter`只可
positional且必须 irrefutable。Receiver、destructuring与 direct capability binder
nondefaultable；后者若写 default报 `capability-binder-default-not-in-v1`。
有 default的 call-entry slot使用 sealed
`@cire::core::ProvidedOrOmitted[T_core]` wrapper，callee prologue
按 parameter declaration order求值 omitted defaults，再构造 immutable body tuple。
Default expression 只能看到 declaration generics、module scope 与已完成绑定的
前序 ordinary `SimpleParameter`；不能看到后续 slot，也不能从 receiver、
destructuring 或 direct capability binder偷建 default authority。

在 `TraitItem` 中，同一规则把 required/default method parameter default写入
`TraitMethodSignatureV1.default_program.default_prologues`，并把从这些 expression可达的 module
callable、local lambda、application/closure table、complete lexical requirement scopes与每个 trait-method use一并封闭；
即使 method body absent也保留可单独 decode/check/execute的完整 call-site语义。
在 `ImplItem` 中任何 source-spelled `= Expr` 都拒绝：impl callable从 trait signature继承 exact
defaultable slot与 default program，不能另求值、覆盖或删除 default。Concrete default/impl body的
Formal projection必须 exact equal该 signature program；对 explicit impl body，比较前先用当前 impl的
trait arguments/target 与 completed associated bindings对 generic program做 exact Self/trait/associated substitution，
method-own generic scheme不单态化。Body-only graph不得混入。

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

LiteralPattern      <- SignedIntPattern / CharLiteral / ByteLiteral
                     / PatternStringLiteral / BoolLiteral
SignedIntPattern    <- MINUS? IntLiteral
PatternStringLiteral <- '"' PatternStringPart* '"'
PatternStringPart   <- Escape / EscapedDollar / StringScalar
ConstructorPattern  <- TypeName
                       (LPAREN PatternList? RPAREN / RecordPattern)?
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
RemovedFloatPattern <- MINUS? FloatLiteral
```

`RemovedFloatPattern` 只属于 recovery grammar，不可从 `Pattern`到达。
Or-pattern 两侧必须绑定相同名字和兼容类型；同一 pattern 不得重复绑定。
Guard 只属于 `match` arm，不是 pattern 的一部分。

`SignedIntPattern` 与表达式中的 signed constant 使用同一 range rule：若有
`MINUS`，它与 `IntLiteral` 的 source spans 必须紧邻，二者合并后再做
expected integer type 的 range check，因而 minimum signed value 可写。正负 Float literal
pattern都进入专用 recovery node并报 `float-pattern-not-in-cire-v1`。
`ByteLiteral` pattern按解码后的 exact byte sequence 比较 `Bytes`，
`PatternStringLiteral` 按 exact Unicode-scalar/String value比较；两者都不调用
`Eq`、trait或 effect。其余 Pattern 同样不调用 `Eq`/trait/effect。`let`、parameter、`for`与 handler clause要求
irrefutable；refutable pattern只在 `match`。Resolver按 nominal constructor/privacy
检查 record field，typechecker以 constructor matrix证明 exhaustiveness/usefulness；
guard不贡献 coverage。

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

PrimaryExpr      <- WithExpr / NonWithPrimaryExpr
NonWithPrimaryExpr <- HandlerExpr
                  / TraitUfcsExpr
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
                  / StringLiteral / ByteLiteral / BoolLiteral
TupleOrGroupedExpr <- LPAREN ArgumentExprList? RPAREN
ArgumentExprList <- Expr (COMMA Expr)* COMMA?
ArrayExpr        <- LBRACKET ArgumentExprList? RBRACKET

RecordExpr       <- TypeName LBRACE RecordBody? RBRACE
                  / LBRACE &RecordFieldStart
                    RecordBody RBRACE
RecordFieldStart <- LowerIdent (COLON / COMMA / RBRACE) / DOTDOT
RecordBody       <- RecordFields (COMMA RecordUpdateTail)? COMMA?
                  / RecordUpdateTail COMMA?
RecordFields     <- RecordField (COMMA RecordField)*
RecordField      <- LowerIdent (COLON Expr)?
RecordUpdateTail <- DOTDOT Expr

TraitUfcsExpr    <- LT Type AS QualifiedName GT COLONCOLON LowerIdent
                    TypeArgs? EffectArgs? ArgList TrailingLambda?

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
完成。Selector与 RHS严格按 §2.6求值。Record update最多一个且 final
`RecordUpdateTail`；enum variant/unknown nominal update在 Kind阶段拒绝。
`return`、`break` 的目标由 control-flow resolver绑定 fresh lexical identity。
`while`/`for`在 Normalize stage唯一展开为 `loop`，其中 `for` source只求值一次并
显式传递新的 iterator state；它们不引入 public effect row。

#### A.7.1 调用参数

```peg
ArgList          <- LPAREN CallArguments? RPAREN
CallArguments    <- PositionalArgs (COMMA LabelledArgs)? COMMA?
                  / LabelledArgs COMMA?
PositionalArgs   <- PositionalArg (COMMA PositionalArg)*
PositionalArg    <- !LabelledArgStart Expr
LabelledArgs     <- LabelledArg (COMMA LabelledArg)*
LabelledArgStart <- LowerIdent EQUAL
LabelledArg      <- LowerIdent EQUAL Expr

RemovedLabelPunningArgument <- LowerIdent TILDE
```

- positional argument 必须在 labelled argument 之前；
- label 在一次调用中必须唯一，resolve 后 unknown label 是错误；
- 没有 label punning；同名 value也必须写 `name = name`；
- callee、显式 argument、最后的 trailing lambda按源码从左到右各求值一次，
  之后只重排 pure temporary reference形成 parameter-order tuple；
- 缺省 labelled parameter 在进入 callee 后按声明顺序求值；
- generic argument 只属于后面紧邻的 call；index suffix 不会被猜成泛型调用。
- `LowerIdent =` 在 argument 起点先判为 label；若确实要把赋值
  作为 positional argument，必须加括号，例如 `f((slot = value))`。
- `LowerIdent TILDE` 只由 recovery parser构造
  `RemovedLabelPunningArgument`并报 `surface-tilde-label-removed`；它不是
  `CallArguments` 的 accepted branch。

因此 corpus 中 `panel(make_title(), enabled=is_enabled(), gap=measure_gap())`
产生一个 positional 与两个 labelled argument；`connect("host",
secure=true, 443)` 在进入 labels 后遇到 positional token，必须拒绝。这里不
依赖 PEG choice偶然先把 `enabled=is_enabled()` 吞成 assignment。

同理，`fn(value) { ... }` 由 `LambdaParamList` 接受并推导 parameter type；
`fn(value : Int) { ... }` 也合法。具名 `def` 仍使用必须标注类型的
`ParamList`。

Label/default call必须解析到 exact static callable metadata；structural function
value只可 positional/trailing。Trailing lambda在 signature resolution后只填 final
non-receiver formal，final duplicate优先报错；它不搜索未填 slot。

#### A.7.2 Trailing lambda

```peg
TrailingLambda   <- LBRACE LambdaHead? BlockElement* RBRACE
LambdaHead       <- LambdaPatternList FAT_ARROW
```

`callee(args) { ... }` 与 `callee { ... }` 都把 lambda 作为**该 call** 的最后一个
argument。换行和 comment 不脱附；要在 call 后开始独立 block，必须写 `;`。

Lossless PEG 保留 `PostfixPart*` 中的 error form，但 normalization 必须左到右
记录前一个 postfix 是否已以 `TrailingLambda` 结尾。若下一个 postfix 立即是
`BareTrailingCall`，则第二个 `{` 在 signature resolution 后稳定拒绝为
`trailing-lambda-target-not-callable`，不得把它重解释为调用返回值。因此 `f { } { }` 与
`f() { } { }` 都拒绝；只有中间出现新的显式 call target/参数列表（例如
`f() { }(fn() { body })`）才能继续调用结果。该拒绝与已填 final slot 的
duplicate 使用同一 precedence，早于返回值 callable/type 推断。

`factory() { body }` 给 `factory` 这次调用追加 lambda，不调用 `factory()` 的
返回值。调用返回的 callable 必须显式写 `factory()(fn() { body })`。

### A.8 Block 与 brace 判定

```peg
Block            <- LBRACE BlockElement* RBRACE
BlockElement     <- LetItem / Expr SEMICOLON?
LetItem          <- LET MUT? Pattern (COLON Type)? EQUAL Expr SEMICOLON?
RemovedDeferItem <- DEFER CUT Expr SEMICOLON?
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
expression 的值被丢弃。若最后一个 element 是 `let` 或带 `;` 的
expression，block result 是 `Unit`。

`DEFER`只由 recovery parser构造 `RemovedDeferItem`，并稳定拒绝
`defer-not-in-cire-v1`；该 node不能进入 accepted Surface HIR。cleanup只经
§2.6 的 sealed finally runner。`LetItem` pattern必须 irrefutable；`let mut`
永远 monomorphic且其 reachable place facts进入 capture/replay检查。

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
WithOperand       <- &InlineHandlerStart InlineHandlerOperand
                   / &MissingModeClauseWitness MissingModeInlineRecovery
                   / WithOperandExpr
WithOperandExpr   <- WithOperandAssignExpr
WithOperandAssignExpr <- WithOperandLogicOrExpr
                         (EQUAL WithOperandAssignExpr)?
WithOperandLogicOrExpr <- WithOperandLogicAndExpr
                          (OROR WithOperandLogicAndExpr)*
WithOperandLogicAndExpr <- WithOperandEqualityExpr
                           (ANDAND WithOperandEqualityExpr)*
WithOperandEqualityExpr <- WithOperandCompareExpr
                           ((EQEQ / NEQ) WithOperandCompareExpr)?
WithOperandCompareExpr <- WithOperandAddExpr
                          ((LT / LE / GT / GE) WithOperandAddExpr)?
WithOperandAddExpr <- WithOperandMulExpr
                      ((PLUS / MINUS) WithOperandMulExpr)*
WithOperandMulExpr <- WithOperandPrefixExpr
                      ((STAR / SLASH / PERCENT) WithOperandPrefixExpr)*
WithOperandPrefixExpr <- (BANG / MINUS) WithOperandPrefixExpr
                       / WithOperandPostfixExpr
WithOperandPostfixExpr <- NonWithPrimaryExpr PostfixPart*
InlineHandlerOperand <- Type LBRACE HandlerMember+ RBRACE
InlineHandlerStart <- Type LBRACE
                      (OperationClauseStart / ReturnClauseStart)
OperationClauseStart <- Mode LowerIdent ClausePatternList
                         ContinuationBinder? FAT_ARROW
ReturnClauseStart <- RETURN LPAREN Pattern RPAREN FAT_ARROW
MissingModeInlineRecovery <- Type LBRACE MissingModeClause
                              HandlerMember* RBRACE
MissingModeClause <- LowerIdent ClausePatternList ContinuationBinder?
                     FAT_ARROW Expr (COMMA / SEMICOLON)?
MissingModeClauseWitness <- Type LBRACE LowerIdent ClausePatternList
                             ContinuationBinder? FAT_ARROW
```

`ClausePatternList` 使用 pattern，不复用 declaration `ParamList`。
`as k` 只允许在 `once` / `ctl` clause。Surface 允许省略 `return`；
elaboration 必须先合成 `return(value) => value`，然后 Core exactness 才检查
“恰好一个 return、每个 operation 恰好一个 clause、无 extra/duplicate”。

`k.resume(value)` 与 `k.finalize()` 由 resolver 降为 resumption primitive。
`k.discontinue(error)` 不属于本 profile。

Inline branch只有完整 lookahead（含 `RPAREN`、optional continuation binder与
`FAT_ARROW`）成功后才 commit。合法 branch复用同一 `HandlerMember`；missing-mode
witness只产生一个 `handler-clause-mode-required`。空/comment-only body、typed
record、普通 trailing lambda与不完整首 clause都走 ordinary `Expr` fallback。

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

Normalize先展开 inline handler，再合成 omitted return，再将 chain right-fold；
没有第二套 clause semantics或 Core/wire node。

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

Cire-v1.0 不增加 existential/rank-2 grammar。Clock package只通过三个 sealed
first-party package-qualified value进入 surface：

```cire
let packed = @temporal::pack_next(under = owner) { frame =>
  delay[frame] { 42 }
}

let value = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

let close = @temporal::dispose(packed)
```

三者使用现有 `QualifiedName`、labelled argument与 trailing-lambda CST；只有
resolver确认 exact sealed origin时才产生 contextual HIR。builder/open block
不是普通 first-class callback type：前者获得 fresh FrameClock，后者只在
lexical scope内获得 raw `frame` 与 surface `Next[frame,A]`；hidden Later
contract $L$ 只存在于 Core/interface，不能在 source type中拼写。
`PackedNext[A]` 是 copyable shared handle；hidden storage Owner不进入 source
type arguments。`try_with_packed_next` 的
Closing/Closed path显式返回 `None`，成功 body的 Returns映射为 `Some`，而
安全的 Aborts/Transfers在完整 identity-nonescape后 exactly-once release并
保持 terminal tag。普通同名函数不享有这些 binder或 lowering。
`dispose` 精确返回 `CloseReceipt[DisposeReport]`；repeated request共享 identity，
receipt只有 `CloseReceipt::await` 这个 Async/MaySuspend observer operation。

### A.11 Syntax validation 与静态语义边界

Parser 必须产出 lossless CST；下列检查在 syntax validation/resolver/type
checker 中完成：

- identifier kind、visibility 适用范围和 duplicate declaration；
- 每个单独 introduction list 中 source binder name injective：`TypeParams`、atomic/
  constructor Effect params、row binders、callable/operation/lambda parameters 与每个 pattern binder set都拒绝
  duplicate；nested lexical scope可以按普通 shadowing 规则重用外层名称；
- type/effect/row binder domain 与 kind；
- ability conformance、associated binding/kind/default exactness；
- only-`Lacks` row predicate profile check，以及 ability-target independent
  `impl` profile check；
- package-instance/name/visibility/import resolution，ordinary trait orphan/overlap/
  associated normalization、inherent/trait/extension unique lookup与 UFCS；
- primitive literal/range/conversion、byte/interpolation/Show、local generalization与
  explicit named-function boundary；
- nominal constructor/update/default/privacy/derive、pattern binder exactness、
  irrefutability、or-pattern binder equality、match exhaustiveness/usefulness；
- assignment place/mutable escape/replay、label matching、default prologue、final-formal
  trailing lambda 和 generic arity；
- operation contract、mode refinement、handler clause exactness；
- named capability identity、row removal、capture/escape；
- one-shot disposition、multi-shot replay/fork 和 Owner transfer；
- temporal clock identity、phase authority 和 storage boundary；
- PackedNext sealed origin、shared lease state、完整 path nonescape/release；
- ConstSafe/termination、ProtocolPure、ComponentSafe/borrow nonescape/host authority；
- exact `IntrinsicRegistryRootV1` identity、callback scheme/evidence、Resource input
  cursor、Task/receipt waiter、UI generation/action-payload/occurrence lease constraints。

Parser recovery 可以插入 missing token 或 error node，但恢复结果不能成为语言
语义。当前仓库没有 parser-executed Cire-v1.0 source accept/reject corpus；
[`../examples/spec/v1/`](../examples/spec/v1/) 只提供 closed artifact/model evidence。
历史 `examples/spec/accept` / `reject` source属于冻结 TR0 lane，且未被旧 validator
解析，不能作为 successor syntax evidence。

### A.12 Diagnostic ownership、origin 与 acceptance boundary

External artifact先 exact Decode，成功后才进入 ContractWF。Source causal cluster的
precedence固定：

```text
Lex > Parse > Syntax > Resolve > Kind > Type > Row > HandlerWF
    > Flow > Capture > Usage > World > Phase > Owner > ContractWF
```

同一 cluster后续发现只作 secondary note。Successor diagnostic registry每项精确保存
`id/stage/causal_cluster/primary_origin_role/required_notes/fix_safety`；CLI/LSP必须
一致且不得泄漏 host exception。

<a id="rule-r06-origin-arena"></a>

Origin arena是 frontend authority拥有的 closed contract；它不是实现可选的 debug
metadata：

```text
OriginId = u32  // exact index in ElaborationOriginMapV1.nodes
DirectOriginId = OriginId
  where nodes[OriginId].node_kind == "DirectV1"

ElaborationOriginV1 =
  {
    node_kind: "DirectV1",
    file_id: String,
    subject: String,
    source_digest: "sha256:" + 64 lowercase hex,
    utf8_range: { start: u32, end: u32 },
    utf16_range: { start: u32, end: u32 }
  }
| {
    node_kind: "DerivedV1",
    derivation_kind: DerivedKindV1,
    anchor: DirectOriginId,
    parents: [{ role: OriginRoleV1, target: u32 }],
    ordinal: u32
  }

DerivedKindV1 =
    "TrailingLambdaArgumentV1"
  | "InlineHandlerExpansionV1"
  | "ImplicitHandlerReturnV1"
  | "SourceOrderTemporaryV1"
  | "CallEntryTupleV1"
  | "DefaultPrologueV1"
  | "ParameterTupleV1"
  | "WithRightFoldV1"
  | "FreshPromptV1"
  | "FreshCapabilityV1"
  | "HiddenTailResumeV1"
  | "HiddenFinalizeV1"
  | "SealedIntrinsicV1"

OriginRoleV1 =
    "PrincipalV1" | "ArgumentV1" | "DeclarationV1" | "SynthesisBasisV1"

ElaborationOriginMapV1 = {
  artifact: "ElaborationOriginMapV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  nodes: [ElaborationOriginV1 in OriginId order],
  sites: [{ site_id: CanonicalSiteIdV1, origin_id: u32 }]
}

CanonicalSiteIdV1 = {
  root_binding_slot: u32,
  kernel_node_preorder: u32,
  role: OriginRoleV1,
  field_path: [u32]
}
```

`DerivedKindV1` 与 `OriginRoleV1` 的 enum order严格等于上列出现顺序，不按
literal string 的 lexical order 重排。
所有 object exact-field；unknown field/tag、duplicate edge、out-of-range ID/range、
非 Direct anchor、非 canonical order均稳定 Decode拒绝。`file_id` 是 NFC、`/`
分隔的 module-relative POSIX path；禁止 absolute prefix、空 segment、`.`、`..`、
`:` 与 control character。`source_digest`绑定 parser输入的原始 strict-UTF-8 bytes；
BOM拒绝，不做 newline或 whole-file NFC rewrite。UTF-8 byte与 UTF-16 code-unit
range均为半开区间，显式要求 `start <= end`，落在 code-point boundary并可从
同 digest内容双向换算。`OriginId` 的 wire lexical encoding 是 JSON u32，且必须恰为
`nodes` array index；`DirectOriginId` 还必须指向 `node_kind == "DirectV1"` 的 entry。

`subject` 是 resolver分配的 `CanonicalSubjectV1`：named declaration/member使用
NFC lexical export path；unnamed Direct site使用
`<nearest-named-subject>#direct@<normalized-HIR-preorder-u32>`；shadowed local
binder在 path尾部增加 `@<canonical-binder-slot>`。Semantic string sort按 NFC
UTF-8 bytes，integer按 unsigned numeric ascending，tuple逐 element；JCS object
property仍按 RFC 8785 UTF-16 code-unit order，二者不可混用。

Canonical allocation是总函数：

1. Direct node按
   `(file_id,source_digest,utf8_start,utf8_end,utf16_start,utf16_end,subject)`
   去重、lexicographic sort，从 0 连续分配 ID。
2. 在 producer临时 graph先 cycle-check并算 depth：Direct=0；Derived的 anchor必须
   是 depth-0 Direct，node depth为 `1 + max(0,parent depths)`。一个 normalized-HIR
   node对同一 `(anchor,derivation_kind)` 至多产生一个 occurrence；occurrence按
   `(anchor canonical key,kind order,normalized-HIR preorder)`排序，并在每个
   `(anchor,kind)`内从 0 连续分配 ordinal。
3. Derived按 depth递增处理；该层 edge按 `(role order,target-id)` exact sort，node按
   `(depth,anchor-id,kind order,ordinal,edge-vector)`排序并连续分配 ID。每个 parent
   必须有更小 depth/ID；只有完整 structural tuple相等才可去重。Object address、
   random ID、hash/map traversal order不得参与。

`root_binding_slot`按 normalized-HIR preorder连续分配；每个 root内
`kernel_node_preorder`连续分配；`field_path`按 exact Kernel schema field order及
list index形成 numeric path（principal node为空）。`sites`按
`(root_binding_slot,kernel_node_preorder,role order,field_path)` exact sort，site ID
不得重复，origin ID必须在 `nodes`内。完整 object先递归 NFC再 RFC 8785/JCS；
semantic Char/String/Bytes value本身按 scalar/byte encoding保存，不能被 NFC改值。

向既有 `SourceOriginV1=file:subject` 的投影同样唯一。Direct使用自己的
`file_id/subject`；Derived使用 anchor Direct的 `file_id`，subject是
`<anchor-subject>#<lower-kebab-kind-tag>@<ordinal>`。13个 tag依 enum order为
`trailing-lambda-argument`, `inline-handler-expansion`,
`implicit-handler-return`, `source-order-temporary`, `call-entry-tuple`,
`default-prologue`, `parameter-tuple`, `with-right-fold`, `fresh-prompt`,
`fresh-capability`, `hidden-tail-resume`, `hidden-finalize`, `sealed-intrinsic`。
两部分各自把不在 `[A-Za-z0-9._/@#-]` 的 UTF-8 byte做 uppercase `%HH`
encoding，再以唯一未编码 `:` 连接；ordinal是无 `+`、无 leading zero的 ASCII
decimal。每个 wire site只投影其 `sites` entry，不沿 parent猜 primary。

Foundation-derived mapping固定为：interpolation/finally/derive →
`SealedIntrinsicV1`；while/for、numeric trap checks、place/assignment temporaries →
`SourceOrderTemporaryV1`；Component adapter由 manifest origin拥有，不伪造 source
DAG node。Core alpha-equivalence下，binder slot按 normalized-HIR preorder分配；
同一 source node产生多个 binder时按 origin ordinal。Public parameter label是 ABI
string，不是 alpha-renamable binder。

Accepted program必须沿同一 frontend snapshot产生 lossless CST、resolved identity、
normalized Surface、signature/kind evidence与 Kernel；不能只有 parser accept。当前仓库
的 v1 specification-model corpus验证 closed artifacts与 representative derivations，
不自称 compiler/runtime implementation release。
