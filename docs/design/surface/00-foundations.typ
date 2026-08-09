#import "../shared.typ": *

= Cire v1 表面语法与唯一 elaboration 规范 <surface-language>

== 状态与目标 <surface-1>

#status(
  [Profile],
  [
    `Cire-v1.0`
        本文是 token、lossless CST、表面 scope、grammar 以及 Surface 到
    evidence-indexed Kernel HIR elaboration 的唯一规范来源；完整、实现无关的
    PEG 收录在 #ref(<surface-appendix-a>)。typed Core、静态 judgment、wire 与 runtime protocol
    从 Kernel 边界起只由形式化文档定义。
  ],
)

本文中的 reachable production 全部属于 profile baseline。明确排除的 spelling
只可进入 recovery CST 并产生注册诊断；不存在“工作语法”或由实现自行决定的
开放分支。尚未进入 v1 的能力列在 #ref(<surface-11>)，不能被 parser、标准库或 backend 偶然实现。

Cire 的基本外观沿用 MoonBit 的熟悉形状，但下列规则属于 Cire 本身：

- 泛型参数和泛型实参使用方括号；
- 函数、方法、ADT、模式匹配、labelled argument、包限定名尽量沿用 MoonBit 的形状；
- block 是表达式，最后一个表达式是结果；
- Cire 为 effect、handler、continuation、named capability、ordinary trait、
  nominal data 与 package identity 增加必要且唯一的语法；
- 所有求值严格从左到右，每个 source expression 恰好求值一次；
- 所有具名 `def`（public/private、method、trait/default/impl/extension、`const def`）
  都显式写完整 generic、参数、结果与 effect row；纯函数写 `! {}`。

规范先于实现。未来 parser 与 conformance test 必须服从本文 #ref(<surface-appendix-a>)，
不能反向裁决语言。

== MoonBit 风格基线 <surface-2>

*已决定*

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

#table(
  columns: (1.4fr, 3.6fr),
  [*概念*],
  [*Cire 写法*],
  [类型实参],
  [`Array[A]`],
  [具名函数类型参数],
  [`def[A] map(...)`],
  [函数类型],
  [`(A) -> B`、`(A, B) -> C`],
  [可变局部绑定],
  [`let mut value = ...`],
  [方法声明],
  [`def Type::method(self : Type, ...)`],
  [package-qualified name],
  [`@pkg::name`（多段 package path 可写 `@org.pkg::name`）],
  [ordinary parameter],
  [`key : Key`（可按位置或 `key = expr` 传入）],
  [destructuring parameter],
  [`pattern : Type`（只可按位置传入）],
  [labelled argument],
  [`key = expr`（没有 punning）],
  [结构化 cleanup],
  [sealed `with @control::finally(cleanup) in body`],
)

具名函数的 result 与 row 都不能省略：`def name() -> Unit ! {} { ... }`。
匿名函数值写 `fn() { ... }`。Lambda parameter 使用独立 grammar，既可推导
`fn(value) { ... }`，也可显式写 `fn(value : Int) { ... }`；它不复用要求
类型 annotation 的 declaration `ParamList`，也不会引入单独的 procedure
语法。

`~`、surface `cap`、`defer` 与 generic `discontinue` 都是保留但不可达的
v1 spelling，分别产生稳定 profile diagnostic。它们不是旧写法的 alias。

=== Primitive、literal 与 conversion <surface-2-1>

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

=== Char、String、Bytes 与 interpolation <surface-2-2>

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

=== Local inference 与 declaration boundary <surface-2-3>

#metadata("FND-local-inference-boundary") <rule-fnd-local-inference-boundary>
#metadata("FND-explicit-named-rows") <rule-fnd-explicit-named-rows>

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

=== Nominal data、construction、pattern 与 derive <surface-2-4>

#metadata("FND-nominal-data") <rule-fnd-nominal-data>
#metadata("FND-pattern-matrix") <rule-fnd-pattern-matrix>
#metadata("FND-postfix-derive") <rule-fnd-postfix-derive>

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

=== Ordinary trait、UFCS 与 extension <surface-2-5>

#metadata("FND-trait-coherence") <rule-fnd-trait-coherence>
#metadata("FND-method-resolution") <rule-fnd-method-resolution>

Ordinary trait 是 coherent static evidence，不是 ability/effect/handler/capability、
cleanup hook 或 error channel。v1 只支持 zero-arity associated `Type` item；没有
GAT、implicit trait object、specialization、negative impl、`Drop` 或 `Try`。
v1 同样没有 ordinary trait 或 ability inheritance/supertrait clause，也不生成隐式
supertrait entailment或 dictionary edge；`trait T : U { ... }` 与
`ability A : B { ... }` 都不进入 accepted grammar。共享 ordinary requirement必须在使用点的
ordinary trait constraint或 zero-arity associated Type constraint中显式写出；effect 对 ability
的实现关系只由 #ref(<surface-4-5>) 的 exact effect header conformance产生，不能借作 declaration inheritance。
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

=== Place、structural control 与 sealed finally <surface-2-6>

#metadata("FND-control-structural") <rule-fnd-control-structural>

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
将 source 求值一次，使用 #ref(<surface-2-7>) 的 pure state-threaded iterator；binder irrefutable，
body usage乘 `Many`。

通用 `defer` 不可达。唯一 general scoped cleanup source form 是：

```cire
with @control::finally(cleanup) in body
```

它只在 exact structural intrinsic identity + `FinalizerSafe`/Replayable evidence下展开，
把 cleanup append 到既有 suffix ledger。Cleanup 必须 NoSuspend、全路径 Returns Unit、
无 outward Abort/Transfer，并在 finalization phase满足 Owner/capture/one-shot责任；typed
failure必须在 cleanup 内处理。它不是 destructor、ordinary trait 或第二套 error model。

=== Package、const、ordinary protocol 与 Component boundary <surface-2-7>

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
