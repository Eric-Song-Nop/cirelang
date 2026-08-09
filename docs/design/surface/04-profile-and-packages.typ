#import "../shared.typ": *

== 不采用宏系统 <surface-9>

*已决定*

Cire 不设计 token macro、AST macro 或 typed hygienic macro。以下都不成为宏：

- UI component；
- `state`、`resource`、`boundary`；
- `with`；
- trailing lambda；
- stable lexical site；
- interpolation、derive、inline handler、`while`/`for`。

UI widget constructor 是普通 adapter call，但只能出现在 #ref(<surface-8>) 的 exact
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

== Canonical grammar <surface-10>

本文 #ref(<surface-appendix-a>) 的完整表面语法统一规定：

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

== Explicit profile-boundary registry <surface-11>

#metadata("R06-no-generic-event-on") <rule-r06-no-generic-event-on>

这一节是 `Cire-v1.0` 的 closed boundary registry。下列项目没有
implementation-defined含义；excluded spelling最多进入 recovery CST。

#table(
  columns: (1.4fr, 3.6fr),
  [*Boundary*],
  [*Cire-v1.0 status*],
  [parameter `~` / call punning],
  [Removed；`surface-tilde-label-removed`。],
  [surface `cap F`],
  [Removed；direct capability binder只写 `app : F`，其它裸 Effect-kind value位置拒绝。],
  [`defer`],
  [Reserved/rejected；只允许 sealed `@control::finally` runner。],
  [`val` / builtin `yield` / builtin `try`],
  [Excluded；programmable control由 algebraic effects表达。],
  [explicit forwarding / masking],
  [Excluded；只有 exact automatic ForwardContract。],
  [public raw completion port / Resume callback],
  [Excluded；只暴露 generation-bound opaque port/gate。],
  [multi-shot local mutation],
  [Closed rejection；live mutable place不能跨 `ctl`，没有隐式 snapshot/clone/share。],
  [general one-call/many-call marker],
  [Excluded；one-shot只存在于 sealed resumption machinery。],
  [general existential/rank-2/`OwnedNext`],
  [Excluded；只公开 shared sealed `PackedNext[A]`。],
  [generic `Event::on/on_async`],
  [Excluded；Event nominal可由未来显式 bridge使用，UI只经 typed ActionPlan。],
  [public generic `Plan`/`CommitTicket`/`CommitGate`],
  [Excluded；UI plan/commit authority scheme-private。],
  [typed `discontinue`],
  [Excluded；没有 payload/world/cleanup/terminal rule。],
  [shallow handler / user macro / user operator],
  [Excluded。],
  [wildcard import / dependency scan / implicit extension activation],
  [Excluded。],
  [GAT / trait object / specialization / negative impl / `Drop` / `Try`],
  [Excluded。],
  [general `as` cast / implicit numeric conversion],
  [Excluded；只用 exact named conversion。],
  [null / truthiness / raw pointer / pointer-sized integer / builtin SIMD],
  [Excluded。],
  [explicit `Has` / `All` / `Only` row predicate],
  [Grammar-reserved、RowWF拒绝；v1只冻结 `Lacks`。],
  [independent ability `impl`],
  [Grammar-reserved、profile-rejected；ordinary trait `impl` accepted。],
  [Effectful `Later` / general affine values / portable general handlers],
  [Excluded research boundary，不是 implementation freedom。],
  [generic checkpoint API],
  [Excluded；Source/Live使用 sealed fixed-Epoch first-party checkpoint runner。],
)

未来接受任何 excluded项必须 mint新 profile，并原子补齐 grammar、elaboration、Core、
wire、diagnostic与 conformance；parser recovery不能把它升级为 language feature。

== Package-qualified callable metadata 与 profile resolution <surface-12>

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
rank-2 evidence，v1按 #ref(<surface-2-3>)拒绝。

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
#ref(<function-contract-v3>) 所定义的唯一
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

当前 repository是纯 specification repository，没有 compiler/runtime/LSP，也没有
可执行 conformance gate。未来 implementation release仍需同一 frontend、
checker、backend/runtime、Component adapter 与 LSP 通过本入口所列 contract 的
独立实现 gates。
