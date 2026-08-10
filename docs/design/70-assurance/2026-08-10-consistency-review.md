# Cire-v1.0 文档一致性审查（2026-08-10）

本记录是一次非规范性 review。规范 authority 仍只有
[`../../cire-lang-design.typ`](../../cire-lang-design.typ)。审查覆盖入口包含的全部
Typst 章节、`examples/spec` 下的 18 个 source-first 样例，以及目录移动后的引用和构建。

## 尚未闭合的设计冲突

### 1. PackedNext successor V1 与 retained V2 仍被同一 checker 路径使用

状态：**阻塞实现，需要设计决策。**

[`../60-runtime/00-cleanup-and-packed-next.typ`](../60-runtime/00-cleanup-and-packed-next.typ)
规定 `Cire-v1.0` 只能使用 `PackedNextProtocolV1` 的
`BuildingV1/OpenV1/ClosingV1/ClosedV1`、cleanup ledger 与
`CloseReceipt[DisposeReport]`；`PackedNextPackageV2` / `PackedNextControlProtocolV2`
只能进入 legacy decoder。

但 [`../30-static-semantics/31-packed-next.typ`](../30-static-semantics/31-packed-next.typ)
中的 T-Pack/T-Try/T-Dispose 仍直接 serialize/import V2 package，使用旧
`Open(n)/Closing(n)/Closed` transition，并让 dispose 返回 `Unit`。
[`../40-checker/00-type-checker-main.typ`](../40-checker/00-type-checker-main.typ)
的三个 PackedNext 分支也仍生成/导入 V2 并按无值 Returns path检查 dispose。它们与
[`../20-frontend/11-first-party-bindings.typ`](../20-frontend/11-first-party-bindings.typ)
中 `PackedNextDisposeV1 -> CloseReceipt[DisposeReport]` 的 closed entry 不一致。

建议选择 successor 已声明的方向：为 V1 Kernel tag补齐独立 static/checker rules，并把现有
V2 rules/procedures整体降为 legacy profile；不要在原规则中只替换 artifact 名称，因为 lease、
cleanup、返回类型和状态空间都已改变。

### 2. `CloseReceipt::await` 有 registry/runtime contract，但缺 Formal operation-site rule

状态：**阻塞 checker 完整性，需要补规则。**

First-party registry 已定义 `async.await-receipt`，并降为
`OperationCallV1(family="AsyncV1", operation="await_receiptV1")`；runtime 也规定
receipt 只有这个 Async/MaySuspend observer。可是
[`../30-static-semantics/61-async-and-phase.typ`](../30-static-semantics/61-async-and-phase.typ)
的 Async declaration 和 T-Await-Site 只覆盖 `await(Task)`，并强制从 actual 读取
`taskRegion`；[`../40-checker/01-type-checker-handlers.typ`](../40-checker/01-type-checker-handlers.typ)
也只 special-case `Async.await`。Receipt 没有 task region，因此不能无损套用现有 rule。

需要补一个 distinct `await_receiptV1` signature、site rule 和 checker branch，或把它移到另一个
sealed effect family；两种方案会改变 operation identity，不能由实现自行选择。

### 3. Resource/Task formation 要求的 boundary evidence 没有进入 closed registry entry

状态：**阻塞 generic `resource.switch-latest` 的全称成立性，需要统一谓词。**

[`../30-static-semantics/31-packed-next.typ`](../30-static-semantics/31-packed-next.typ)
的 K-Task 要求 payload 同时满足 `Shareable` 与 `AsyncBoundarySafe`；K-Resource 只要求
A/E 的 async boundary safety，漏掉 K。runtime 和 structural registry 则要求 K/A/E 全部具备
exact owner-storage boundary evidence。

然而 [`../20-frontend/11-first-party-bindings.typ`](../20-frontend/11-first-party-bindings.typ)
的 `resource.switch-latest` entry 只为 K/A/E 列出 `ShareableV1`，其 loader callback却必须返回
`Task[rho_child,TaskOutcome[A,E]]`。对任意 Type binder，现有 evidence不足以证明该 Task 和
Resource 可形成。

需要定义并统一 exact `OwnerStorageBoundarySafeV1(owner,T)`（或明确它与
`AsyncBoundarySafe` 的等价关系），在 closed entry和 K-Resource中覆盖 K/A/E；同时必须说明
special loader contract如何为 child-owned Task推出相应保证。

### 4. `Task::cancel` 的 outward type 与 runtime transition 未闭合

状态：**阻塞 public API / runtime totality，需要设计决策。**

First-party registry让 `Task::cancel` 返回 `CancelResult` 并降为 `TaskCancelV1`。但
[`../30-static-semantics/00-ordinary-foundation-and-wasm.typ`](../30-static-semantics/00-ordinary-foundation-and-wasm.typ)
的 frozen successor public nominal family没有 `CancelResult`；全库也没有定义它的 closed variants。
[`../60-runtime/10-task-and-resource-protocols.typ`](../60-runtime/10-task-and-resource-protocols.typ)
只描述 cancel 与 Pending/Resolved/OwnerClosed 的竞争，没有 `TaskCancelV1` 的 result mapping，
static/checker也没有对应 rule。

需要把 `CancelResult` 加入 public nominal catalog，冻结每个 race/state 的结果并补
static/runtime/checker rules；若 API 不需要观察结果，则应把 entry 改为另一已定义的返回类型。

### 5. Resource 初始 `Vacant` 状态没有可表示的 public `ResourceView`

状态：**高风险 totality gap，需要冻结 construction 可见性。**

`Resource::view` 返回持续有 current value 的 `Live[rho,ResourceView[K,A,E]]`。Public
`ResourceView` 只有 `Loading/Ready/FailedLoad/Closed`：前三者都需要 key，Closed需要 report。
但 [`../60-runtime/10-task-and-resource-protocols.typ`](../60-runtime/10-task-and-resource-protocols.typ)
规定 construction 先 publish `Vacant`，此时没有 key、value、error或 report。

需要增加可公开的 `Idle/Vacant` view variant，或明确并证明 `switch_latest` 在返回前同步完成首个
Live revision admission，使内部 Vacant 永不被 `Resource::view` 的 outward Live观察到。

## 本轮已修复的冲突与结构缺陷

- Temporal accept/reject 样例原先使用 `def![F : FrameClock]`，但 effect generic constraint只能指向
  ability，而规范要求 direct `frame : FrameClock` 创建 singleton clock identity。两个样例已改为
  direct parameter，使 accept case可到达 typing，也使 early-advance 的 primary rejection确实是
  `no-matching-clock-lock`。
- Surface/Formal authority 原先一处说 typed Core/wire全部由 Formal拥有，另一处又让 Surface
  first-party registry直接生成 M3/Q/Λ。总述已明确 closed registry 是唯一例外：Surface拥有确定性
  projection/template 实例化，Formal验证 exact output并定义 tag meaning。
- Generic `live { ... }` 的 T-Live 在 retained calculus中看似仍是 successor source constructor，
  但 closed 21-entry registry没有该 binding。该小节现已明确标为 retained TR0 proof notation；
  `Cire-v1.0` 不会因此暗增第 22 个 intrinsic。
- Retained Signal 小节把 `map_signal` 写成三参数 API，并使用缺少 hidden tail contract 的旧 equation，
  与 canonical 两参数 binding冲突。该小节现已明确标为 TR0 unfolding sketch；successor identity从
  input Signal解出并使用 `SignalTailContract`。
- 原 `core/13-*` 按文件大小切开了 schema、import 与 Core elaboration 的句子/公式。迁移后四个边界
  都有独立标题和完整引言，不再依赖上一文件的半句话。

## 机械一致性检查

- Typst 入口编译成功，Tinymist lint 为 0 diagnostic。
- `CireDiagnosticsV3` 表恰有 133 个唯一、严格排序的 ID；9 个 reject 样例的期望 ID全部存在。
- First-party overview 与详细 registry 各自恰有同一组 21 个 stable binding ID。
- Primitive catalog列出的 cardinality为 16，明细也是 16 项。
- 入口仍包含全部 52 个 Typst 章节；移动只改变路径，没有按目录重排 authority。
- Markdown workspace links、Typst includes、labels 与 refs 均可解析。

仓库尚无 Cire compiler，因此 accept/reject 样例只能检查 source shape、期望 diagnostic 与规范互相
对齐；它们仍不是 executable conformance proof。
