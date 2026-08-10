#import "../shared.typ": *

== Ordinary typing、inference、data 与 control judgments <ordinary-foundation-v1>

本节只给出 Surface-owned source decision 进入 Kernel 后的 typed-Core judgment 与 wire/runtime
enforcement；source declaration WF、local-inference boundary、nominal/pattern spelling 与
trait/extension method resolution仍由 Surface 的对应 `FND-*` anchors唯一决定。本节不得作为
第二份 source grammar、lookup或 elaboration规则。

Successor 在下文既有 judgment product上增加普通 constraint集合 $C_o$ 与 trap fact $t$：

$
  K;I;Phi;Omega@Theta;Gamma |- e => A ! epsilon ; s ; chi ; u ; pi ; f ; C_o ; t
$

其中 $t in {"NoTrap","MayTrap"}$；它不是 row member或 `Flow` variant。既有 row、flow、world、
capture、usage、Owner rules原样组合，普通 rule不得擦除这些分量。

=== Local rank-1 inference

Immutable local `let` 可 generalize Type、EffectRow、coherent principal ordinary-trait constraint与
一个完整 atomic hidden `FnContract` binder；永不只 generalize function contract 的 row projection。
Generalization同时要求：initializer为 non-expansive pure construction、empty authority capture、stable
duplicable environment、`ManyCallSafe`、无 reachable mutable cell/borrow/resumption/claim/non-replayable
cleanup、无 generative identity/Owner/clock quantification、constraints closed。否则 metas保持 weak
monomorphic。Lambda construction可 pure/generalize，即使 body effectful；执行 effectful initializer不可。
没有 higher-rank/impredicative inference、polymorphic recursion、global API inference或 implicit conversion。
Surface `GenericFunctionType` 只在 immutable simple-name let的完整 annotation形成一个 local rank-1
scheme，且 initializer是 matching generic lambda；它唯一物化为 `LocalFunctionDeclarationV3`，每次 use
fresh实例化其 `M3(DeclarationBindersV2)` 与完整 hidden contract。该 node不得递归出现在 field、parameter、
result、type argument、container、alias、mutable let或 outward value type，也不得 store/pass/return generic
lambda；因此 package declaration无需递归 scheme artifact，`FunctionTypeV2` 也不承载 rank-2 binder。

=== Data、construction 与 patterns

`struct/enum/newtype/opaque type` 是 nominal；`type` alias transparent且无 constructor/orphan identity。
不存在 anonymous structural record type。Construction必须解析 exact nominal constructor；tuple/
field initializer各求值一次、严格 source order；written field无重复，missing field只使用 declaration中
pure const default，所有 initializer成功后才 publish。Functional update恰一个 final `..base`：explicit
fields先 source-order、base最后一次；omitted fields只 projection，不重跑 default；enum不 update。

Pattern pure且 type-directed，不调用 Eq/trait/extension/effect。Constructor arity与 record visibility/
coverage exact；float literal pattern拒绝；or-pattern alternatives必须绑定同名、同 type、同 quantity并
join原 provenance/capture/usage。Refutable pattern只允许 match；let、parameter、for、handler operation/
return clause都要求 irrefutable。Alias spelling保持既有 postfix：`pattern as name`；prefix
`name @ pattern` 或新 alias grammar不属于 v1。每个 match运行 constructor-matrix usefulness/
exhaustiveness；guard不贡献 coverage。

=== Ordinary traits、extensions 与 resolution

Ordinary trait是 coherent static evidence，不是 ability/effect/handler/cleanup/error channel。Associated
item只允许 zero-arity Type；其 `AssociatedTypeDeclarationV1.constraints` 可以包含 ordinary
`TraitGoalV1`（例如 `IntoIterator` 对关联 `Item` 的 constraint），并按普通 coherence/normalization
检查。它不触发 ability-only 的 `associated-declaration-constraint-not-in-profile` 或
`associated-parameterization-not-in-profile`。无 GAT、trait object、Drop、Try、specialization、negative impl。
Ordinary trait 与 ability inheritance/supertrait clause同样不属于 v1；
`TraitDeclarationV1` 与 `AbilityDeclarationV1` 都没有 supertrait field，Formal不合成
supertrait entailment。Effect 对 ability 的实现关系只来自 exact effect-header conformance，
不是 declaration inheritance，也不能作为 ordinary-trait requirement的替代。
`pub trait` package-sealed，`pub(open) trait` downstream-open。透明 alias expansion后，impl package必须
拥有 exact trait或 target最外层 nominal constructor；builtin/array/tuple/function为 foreign head。
两个 header只要 first-order unification可使 exact trait args与 target相等即 overlap；constraint、result、
effect、import、specificity都不消歧。

`ImplDecl` 及其 associated type/method items 都不能带任何 visibility modifier；impl 本身不是
source export identity，可见性由 trait/type openness、orphan/coherence 与 package-level `ImplEvidenceV1`
closure决定。任一 `pub`/`pub(open)` 或其他 visibility token 稳定
`impl-visibility-not-allowed`，不得将它降级为 ignored modifier。

Dot resolution先合成 receiver type。Matching named-capability operation走 ability dispatch；否则
accessible inherent method胜出；再否则 in-scope trait method与显式 enabled extension形成一个 candidate
set，必须恰一 declaration identity。Expected result、ambient row、handler、conversion、proximity/import
order不消歧；无 autoderef/autoref。Trait UFCS与 qualified extension call可显式选择。`extend def`仍是
ordinary named function，完整 explicit row，不生成 impl/evidence或 privileged access；dependency extension
只由 exact `use @pkg::name [as alias]`启用，无 wildcard/package scan/re-export。

能进入 dot candidate set 的 inherent/trait/extension method必须恰有第一个 parameter
`self : Self`；trait/inherent 的 `Self` 是所属 nominal/trait receiver，extension 的 `Self` 在
declaration WF 时固定为 resolved extended receiver type。第一 slot 名称、位置或 type 不 exact时，
该 declaration不是 method，不能通过类似参数或返回类型偷进 dot lookup。无 `self`
的 associated function 只能通过 trait/type/extension qualification调用，永不进入 dot candidate set。
Extension 缺失/改名第一 `self` 或使用非 exact receiver `Self` 稳定
`extension-self-parameter-required`。

=== Places、mutation 与 structural control

`let mut` 创建 monomorphic local place。Assignment先把 base/index selectors按 source order各求值一次，
再 RHS一次，再 write并返回 Unit；Formal要求 Surface-produced Kernel已带 exact
`SourceOrderTemporaryV1`。Field place必须 rooted in
visible mutable local；immutable array仅通过 sealed value-update projection写回该 place。无 implicit
reference、auto-box或 continuation snapshot。Escaping/Owner-stored/suspended/multi-shot closure不能 borrow
mutable local；one-shot boundary要求 continuation独占 place且 handler/environment无 alias。

Surface 的 `rule-fnd-control-structural` 唯一决定
`if/match/loop/return/break/continue/while/for` 的 source lowering。Formal不重选该 lowering，只接受
带 lexical terminal identity与 exact `SourceOrderTemporaryV1` 的已产生 Kernel；其中 user handler不可
intercept structural transfer，for的 source恰求值一次并满足 locked-core
`IntoIterator/Iterator` state-threaded protocol、irrefutable binder与 Many body usage。对 Surface已拒绝的
generic `yield/try` 与 `defer`，Formal不产生补充语法路径。

=== Numbers、text、MayTrap 与 defect transition <maytrap-defect-transition-v1>

`Int/UInt/Float` exact为 i32/u32/binary64。Numeric suffix为
`i8/i16/i32/i64/u8/u16/u32/u64/f32/f64`；unresolved literal在 let generalization前分别 default
Int/Float。Typed values无 implicit conversion且无 general `as`；每个 conversion只用下列 exact
policy-bearing name：

```text
T::from(x)                    exact all-values widening only
T::try_from(x) -> Option[T]   checked integer narrowing/signedness
T::wrapping_from(x) -> T      integer modulo/truncation
T::round_from_int(x) -> T     integer -> float, nearest ties-to-even
T::try_truncate(x) -> Option[T]
                              float -> integer, truncate toward zero;
                              None on NaN/infinity/out-of-range
x.to_bits() / T::from_bits(x) equal-width explicit bit conversion

checked_add/sub/mul/div/rem/neg/shift_* -> Option[T]
wrapping_add/sub/mul/neg/shift_*        -> T
saturating_add/sub/mul                  -> T
```

Ordinary integer `+ - * / %`、signed neg/abs 与 shifts 在 overflow、divide/mod-zero、
signed-min edge 或 out-of-range shift 时确定性 MayTrap；division toward zero，remainder跟 dividend
sign，ordinary shift不使用 Wasm masked count。Checked 不 trap并返 None，wrapping 用 modulo/masked
shift，saturating 只为 add/sub/mul 夹到 min/max。这些规则对 const、interpreter、optimized与
Wasm execution identical。

Float32/Float 固定 IEEE binary32/binary64 nearest-ties-to-even，无 ambient rounding、
fast-math、FTZ 或 implicit FMA，Float `%` absent。每个 arithmetic/conversion/constant/import/
`from_bits` NaN 均 canonicalize为该 width 唯一 positive quiet NaN；`to_bits` 对 NaN只返回
该 canonical bits。Raw payload-preserving interop必须使用 integer/Bytes schema。Float 只有 IEEE
PartialEq/PartialOrd/Show，不有 Eq/Ord/Hash。Locked-core nominal wrappers `TotalFloat32`/
`TotalFloat` 在构造时应用同一 canonical-NaN bit rule，Eq 比较 canonical bits（所以
`+0` 与 `-0` distinct），Ord 使用 canonical value set 上的 IEEE `totalOrder`，Hash 吸收
width tag 与 endian-neutral canonical bits；因而 `Eq => same Hash` 且 `compare==Equal <=> Eq`。

```text
ContractTrapFactV1 = "NoTrapV1" | "MayTrapV1"

DefectTransition(machine, origin, code) =
  run already-registered suffix and Owner retirement obligations
  -> emit terminal outer Wasm trap(code, origin)
```

`MayTrapV1` 是普通 contract fact：checker从 typed primitive/check nodes及 imported package-level
`CallableContractFactEvidenceV1`作 join，public boundary把结果写入同名 exact package evidence。
它不向 V3 object增加 field/tag；它绝不
加入 effect row，绝不成为 `Returns/Aborts/Transfers` 的第四个 Flow tag，也不能被 handler、Raise、
Result或 finally catch。Cire-generated check发生 defect时先走 meta-level `DefectTransition`；cleanup
完成后 outer Wasm trap终止 instance path。Imported engine/host trap或 allocator failure是 catastrophic
instance failure，只依赖 embedding root teardown，不承诺任意 user finalizer。

=== ConstSafe 与 standard protocols

`const name : T = e`由 build-time evaluator执行；reusable body只能 `const def`，并显式写 `! {}`。
`ConstSafe` 额外要求 empty residual row/demand、NoSuspend、TemporalPure、Pure/no-authority、stable
capture-free result/environment与 Returns-only。允许 literal、immutable ADT/array、projection、exhaustive
match/if/let、primitive op与 ConstSafe call；拒绝 mutation、assignment、unbounded loop、handler/with、
effect、temporal/Owner/capability/resumption/task/resource、FFI/host。Termination只接受 acyclic call graph
或对 syntactically smaller ADT field的 direct structural recursion；definite trap是 compile diagnostic。

`PartialEq/Eq/PartialOrd/Ord/Hash/Show/Iterator/IntoIterator` 是 ordinary trait且其 standard methods
满足 ProtocolPure。Float没有 Eq/Ord/Hash；state-threaded iterator返回
`IterStep[A,S]=Done|Yield(A,S)`，不能把 hidden mutable cursor跨 iteration/effect/suspension/replay。
Task/Source/Event/Signal/Owner-backed stream不实现这个 ordinary iterator protocol。

== Wasm 与 Component boundary judgment <component-boundary-v1>

Initial target固定 Wasm 3.0 validation、memory32、single-thread、non-shared；允许 multi-value、bulk
memory与 ordinary indirect call，不假定 memory64、GC identity、EH、native continuation/stack switch、
tail-call semantic、SIMD、thread/atomic。Private layout不是 source semantics。

```text
ComponentSafeV1(T) iff T is a closed monomorphic combination of
  supported scalar | String->component string/UTF-8
  | Bytes->component list<u8> | immutable list | tuple/record | closed variant
  | Option | Result | explicit ComponentResource
```

Capability、Owner、resumption、handler、closure、temporal value、borrowed view、opaque private layout、
open generic/trait/row不直接跨 boundary。Component export建立 per-call child Owner并在每个 Cire
Returns/Aborts path关闭；resource own/borrow adapter使用 instance handle table与 Owner generation。
Borrowed input具 FFI/callback provenance，未经 owned copy不能 escape/suspend/store。Raw component
`result<T,E>`只映射 ordinary Result；转 Raise必须显式 match。Host import生成 sealed capability contract，
row中保留 HostObservable，annotation不能 laundering为 ProtocolPure/ConstSafe。

== Successor first-party type boundary <first-party-type-boundary-v1>

`Cire-v1.0` 的 public nominal family固定为：

```text
Task[rho,R]
TaskOutcome[A,E] = Succeeded(A) | Failed(E) | Cancelled(CancelReason)
CancelReason = ExplicitCancel
CloseReceipt[R]
PackedNext[rho,A]              // surface hides rho: PackedNext[A]
Resource[rho,K,A,E]
Previous[K,A] = { key: K, value: A }
LoadFailure[E] = Failed(E) | Cancelled(CancelReason)
ResourceView[K,A,E] =
    Loading { key: K, previous: Option[Previous[K,A]] }
  | Ready { key: K, value: A }
  | FailedLoad { key: K, error: LoadFailure[E],
                 previous: Option[Previous[K,A]] }
  | Closed { report: DisposeReport }
Source[rho,A]
Live[rho,A]
Event[rho,E]
Signal[i,A]
UiMount[rho]
```

`ResourceTypeV2(owner,value,cleanup_result)`是 legacy TR0 form；successor Resource 的 key/value/error
三 ordinary parameters必须全部出现于 M3 nominal/type template，不能压回旧二参数 shape。
`Event[rho,E]` nominal继续存在以表达 exact event identity/data edge，但 v1 registry没有 generic
`Event::on` 或 `Event::on_async`，也没有任意 user callback subscription API。Event callback只可由
sealed UI/component adapter在下述 typed occurrence protocol中安装。

旧 `PlanTypeV1/V2`、public `Plan[A]`、`CommitTicket`、`CommitGate` 与 generic public Plan/Commit API
不属于 successor source/API/interface。Runtime可使用 private `ViewPlan[gamma]`、
`ActionPlan[gamma,E]`、prepared transaction与 single-claim states；它们没有 public
`CallableInterfaceV1`，不能存储、导出、导入或由 user type name构造。
