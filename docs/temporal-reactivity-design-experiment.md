# Temporal modality、代数效应与增量计算：语法实验和反例审查

## 0. 文档状态

> **Profile companion:** [`Cire-TR₀/2026-07-31`](spec-status.md)
>
> 本文保存 canonical profile 的设计动机、反例和取舍，不独立裁决语法或
> Core rule。规范结论以[状态矩阵](spec-status.md)、
> [完整表面语法](surface-grammar.md)和
> [Cire-TR₀ 形式化](temporal-reactivity-formalization.typ)为准。

本文在现有 Cire 设计上做一次小型语言设计实验，目标不是尽快实现
`Signal` 或 reactive variable，而是回答：

1. 哪些语言特性真正帮助第一方响应式与增量计算；
2. modal time、代数效应、capture tracking、resumption quantity、Owner
   应如何组合；
3. 哪些看似统一的写法会混淆不同语义；
4. 一组覆盖同步、异步、effect、replay、Event、State 与 Wasm 边界的程序
   应该被接受还是拒绝。

本文沿用：

- [代数效应与恢复模式](effects-and-resumptions.md)；
- [Named capability、Owner 与结构化清理](capabilities-and-finalization.md)；
- [第一方增量计算库](incremental-computation.md)；
- [第一方响应式 UI 框架](reactive-ui.md)；
- [Cire 表面语法设计说明](surface-syntax.md)。

本文的规则化版本见
[Cire Temporal、Effect 与 Incremental Core：Typst 形式化](temporal-reactivity-formalization.typ)。
该文档把这里的直觉拆成 kinding、bidirectional typing、suffix-site
analysis、Owner/Commit 协议和独立 incremental machine，是当前 canonical
semantic baseline；显式参数与 theorem 仍分别保持“开放”和“证明义务”状态。

下文的 `Next`、`delay`、`advance` 和 operation transition 写法已由 profile
grammar 收敛；`protocol checkpoint` 仍是参数化的 Core contract，其中
checkpoint 目前只建议出现在 Kernel
contract/dump，不是第五个 surface mode。例子中的 `live`、`resource`、
`Event`、`Signal` 仍可只是第一方库 API 和 trailing-lambda 语法，不因此
成为语言关键字。

## 1. 本轮结论

最值得继续研究的组合不是“语言级 reactive variable + 一个大运行时”，而是
三个彼此连接、但不互相冒充的层：

```text
纯 temporal core
  Next[clock, A] + delay[clock] + advance
  用于 causality、guarded feedback 和纯粹的下一时刻值

普通 control/effect core
  effect row + abort/once/fun/ctl
  + world-indexed resumption
  + capture / quantity / Owner checking

第一方 persistent protocols
  Live / Source / Event / Task / Resource
  + Epoch snapshot + replacement Trace + Commit gate
```

核心判断应至少在内部保留四个正交维度：

```text
Γ @ m0 ⊢ e : A @ m1 ! ε ▷ δ
  captures χ
```

| 维度 | 回答的问题 |
|---|---|
| `m0 → m1` | 计算从哪个 logical world / phase / suspension segment 到哪个位置 |
| `ε` | 执行会请求哪些 operation |
| `δ` | 计算对环境的要求或静态上界，例如 clock、source class、replay policy |
| `χ` | 值、闭包、continuation 实际保留了哪些 capability、Owner 与 authority |

运行时本轮精确读取了哪些 `Source`，仍由 trace 动态记录；它不应被伪装成
静态 effect row 或 capture set。

这轮例子还给出五个明确的否定结论：

1. 不应把 logical tick、Task completion 和 incremental Epoch 都叫
   `Later`。
2. 不应假定 handler 与 `Next` 自动交换。
3. 不应让普通 `Later[A]` 隐藏未来 effect。
4. 不应把 `ReplaySafe` 只挂在 effect family 上；性质属于具体 handler
   instance 或 runner。
5. 不应把 `ctl` 的任意 multi-shot 等同于增量系统需要的 generation
   replacement。

### 1.1 Verse 的计划中 Live Variables：值得借什么

[The Book of Verse 的 Live Variables 章节](https://verselang.github.io/book/15_live_variables/)
明确标注为**尚未发布的计划特性**，因此它更适合作为设计样本，而不是已经由
实现或形式化证明验证的先例。它提出 `var live`、`set live`、动态且传递的
依赖，以及 `await`/`upon`/`when` 等观察构造；还把几个重要边界放进语言
语义：

- guard 不允许执行 write；
- `batch` 延迟通知，并让观察者看到批次最终的一致快照；
- cancellation 会移除依赖关系；
- failure rollback 不发布失败路径建立的依赖或通知；
- live cycle 可能不收敛，因此 live write 会带来 divergence。

Cire 值得借的是这些**一致性义务**，尤其是 batch、取消、失败和依赖生命周期
必须一起定义；不宜直接复制的是“普通变量加一个 `live` 修饰符”这一统一表面。
它容易把至少四件事叠成一个概念：当前值、无损 occurrence、可重放计算、可变
存储。Cire 的 `Source`/`Live`/`Event`/`Task` 分型可以更明确地说明：

```text
Source write 产生 revision
Live replay 维护当前派生值
Event 保留 occurrence 的顺序与 multiplicity
Task 表示一次完成、失败或取消
```

如果以后提供 `live var` sugar，也应 elaboration 到这些协议之一，而不是让每个
变量都隐式拥有 dependency graph、scheduler 和通知语义。

## 2. 先把三种“时间”分开

### 2.1 Logical clock

`Next[frame, A]` 表示 `A` 不早于 `frame` 的下一 logical tick 可用。

它适合：

- 同步 Signal；
- guarded feedback；
- animation/frame step；
- 对 causality 的静态检查。

它不承诺宿主一定产生下一 tick。因此：

```text
guarded productivity
≠ scheduler fairness
≠ clock 最终会 tick
```

### 2.2 Task completion

本文为简洁沿用现有表面文档中的示意 `Task[A]`；它不冻结错误通道。正式设计
仍须在 `Task[A, E] -> Result[A, E]`、显式 `Error[E]`/`Cancel` effect 或
typed discontinuation 之间作出选择。

`Task` 表示一次性异步工作：

- 可能立即 ready；
- 可能未来完成；
- 可能失败或取消；
- 可能永不完成。

`await(task)` 是 `once` suspension point，不是 `Next[frame, A]` 的消去规则。
静态检查可以保守地把每个 `await` 当成可能跨 suspension segment，即使运行时
存在 ready fast path。

### 2.3 Incremental revision / Epoch

`Live[A]` 表示持续维护的**当前值**。它在 Source 变化后，以固定输入快照进行
replay，并替换旧 trace generation。

Epoch 不是用户可以任意 `advance` 的 logical clock：

- 同一批更新可以 coalesce；
- 一次 replay 可以读取多个 Source；
- candidate 可能失败、暂停、被抢占或放弃；
- committed 与 candidate generation 可以并存。

因此 `Live[A]` 不应被定义成 `Signal[frame, A]` 的别名。

### 2.4 四种第一方对象保持异型

```text
Signal[frame, A]
  每个 logical tick 的时间展开

Live[A]
  当前派生值；输入 revision 变化后维护

Event[E]
  有序 occurrence；不能任意 coalesce

Task[A]
  至多完成一次；可能永不完成
```

广播型 `Signal`、`Live` 与 `Event` 的元素必须满足 `Shareable`。若 payload
包含 affine authority、one-shot continuation 或短命 host borrow，应使用
不同的 single-consumer、Owner-bound stream/task 类型，不能借普通 Event
广播复制。

显式 bridge 可以存在，例如：

```text
Event::from_task(owner, task)
Signal::hold(initial, event)
changes(live) -> Event[Revision[A]]
```

但不提供四者之间的隐式 coercion。

## 3. 建议继续推演的最小表面语法

### 3.1 Generative clock 沿用 named capability

不增加顶层 `clock` 声明。第一方 runner 用现有 `with ... as ...` 产生不可伪造
的 clock identity：

```cire
with Frame::run(owner) as frame
in {
  // frame : cap FrameClock
  ...
}
```

工作类型：

```cire
Next[frame, A]
Signal[frame, A]
```

这里 `frame` 是受限 singleton identity，不是普通类型参数。Cire 已允许
函数的 effect row 依赖 term binder：

```cire
def read_app(app : cap Read[Int]) -> Int ! {app}
```

让 `Next[frame, A]` 使用同一 identity 基础设施，比引入一般 dependent type
更窄。不过它仍会影响 kind checking、泛型、ADT、存在封装和接口序列化，必须
通过独立原型验证。

一个 fresh `frame` 不能裸逃逸：

```cire
let leaked =
  with Frame::run(owner) as frame
  in {
    make_signal(frame)
  }

use_after_frame_scope(leaked)
```

`with` action 的 inferred result 若是 `Signal[frame, Int]`，其中的 `frame`
在 action 返回处已经没有 binder，程序应被拒绝。存在封装只能隐藏 identity，
不能延长 runner 或 Owner 的 lifetime。第一方容器必须同时拥有 clock runner、
child Owner 和显式 `dispose`；裸 `exists frame. Signal[frame, A]` 仍不能
安全逃逸。

### 3.2 `Next`、`delay`、`advance`

工作语法：

```cire
Next[frame, A]

delay[frame] {
  expression
}

advance(value)
```

含义：

- `delay[frame]` 的 body 在 `frame` 的下一 world 中检查；
- `advance(x)` 只有在类型上下文已经跨过 `x` 对应 clock 的 tick 后才合法；
- `Next` 是共享、memoized 的纯 modal cell，不是每次 `advance` 都重新执行的
  一般 thunk；
- `delay` 是 sealed temporal construct，不是用户可任意拦截的 effect
  operation；
- `advance` 不等待宿主时间，也不主动驱动 scheduler。

最小规则可以写成：

```text
Γ, lock(frame) ⊢ e : A ! {}
TemporalPure(e)
TemporalStable(frame, free_values(e))
CrossWorldSafe(frame, captures(e))
Shareable(A)
────────────────────────────────────────
Γ ⊢ delay[frame] { e } : Next[frame, A]

Γ @ after(frame) ⊢ x : Next[frame, A]
────────────────────────────────────────
Γ @ after(frame) ⊢ advance(x) : A
```

`Shareable(A)` 是必要限制：如果 `advance` 可以多次返回缓存值，那么结果不能
包含 one-shot continuation、唯一 socket 或 Commit authority。第一阶段宁可
拒绝这种 `A`，也不立即把一般 affine type 语法传播到所有 Signal API。

`TemporalPure(e)` 是 effect 被 handler 消除后仍保留的执行摘要。否则：

```cire
delay[frame] {
  with Console::host()
  in {
    Console::print_line("surprise")
  }
}
```

虽然 residual effect row 已为空，未来仍会发布宿主写入。第一阶段应拒绝。
`Error::result`、纯 Reader、封闭 local State 或纯 Choice handler 可以由具体
handler instance 提供 `TemporalPure` 证据；真实 IO handler 不可以。

`TemporalStable(frame, free_values(e))` 是 modal/coeffect 检查，不等于现有
capability capture set。现有 `χ` 有意忽略普通 immutable ADT；但一个不保留
capability 的值仍可能只属于当前 temporal region，例如当前 frame 的
borrowed view。这样的值即使 `χ = {}` 也不能越过 Fitch lock。

第一阶段不一定需要表面 `Box`；typed HIR 可以为 free value 保留
stable/current-world provenance。普通复制出来的 `Int`、immutable snapshot
和被证明 stable 的 closure 可以跨 lock，current-world borrow 不可以。

泛型与 separate compilation 不能只依赖调用点的局部 HIR。公开函数如果让
closure 或结果跨 world，其 interface artifact 必须序列化
`TemporalStable`、`CrossWorldSafe`、`Shareable` 与 capture-polymorphic
约束；表面可推断省略，但诊断和链接时检查不能省略。

`CrossWorldSafe(frame, χ)` 则复用 capture/outlives/quantity checker。它至少
拒绝：

- 只在当前 callback 有效的 host reference；
- stack-only handler；
- candidate-local Commit authority；
- 不可复制 cleanup segment；
- 会在 tick 前关闭的 Owner/capability。

### 3.3 第一版 `Next` 只保存纯结果

下面这个看似自然的类型是不完整的：

```cire
def hide_charge(
  frame : cap FrameClock,
) -> Next[frame, Unit] {
  delay[frame] {
    charge_credit_card()
  }
}
```

如果 `charge_credit_card` 不出现在构造调用的 effect row 中，effect 被洗掉；
如果出现在构造调用的 row 中，又错误地声称 effect 现在执行。

完整 Core 至少需要：

```text
Later[frame] { A ! E } captures χ
```

它还必须回答：

- delayed computation 可执行一次还是多次；
- 哪个未来 handler instance 解释 `E`；
- 丢弃时谁执行 cleanup；
- 它是否绑定 Owner；
- 返回值或 continuation 是否 affine。

因此本轮更保守的建议是：

```text
第一阶段：
  Next[frame, A] 的 residual effect 必须为空

以后：
  单独研究 Owner-bound、one-shot 的 Scheduled computation
  不把普通可复制 Next 直接扩成任意 effectful Later
```

Effect 可以在 `delay` 内被彻底处理：

```cire
delay[frame] {
  with Error::result()
  in {
    parse(text)
  }
}
```

结果是：

```text
Next[frame, Result[Value, ParseError]]
```

### 3.4 Handler 不默认穿过 temporal boundary

下面两段程序刻意不同：

```cire
delay[frame] {
  with Error::result()
  in {
    parse(text)
  }
}
```

```cire
with Error::result()
in {
  delay[frame] {
    parse(text)
  }
}
```

第一段在未来 world 中安装 handler，residual row 为空，可以接受。

第二段的外层 handler 只处理当前 computation；它不会自动被搬进未来 world。
第一阶段应拒绝第二段，并可提示：

```text
handler `Error::result()` does not enter delayed computation
install it inside `delay`, or use an explicit portable-handler bridge
```

以后若某种 handler 确实满足交换律，可以让具体 handler value 提供
`CommutesWithNext[frame]` witness。不能为所有 effect 假定：

```text
Next(A ! E)  ≅  (Next A) ! E
```

### 3.5 Operation contract 需要记录 world transition

`abort / once / fun / ctl` 只记录 continuation 的使用上界，不足以描述
continuation 在哪个 world 恢复。

Kernel resumption 应接近：

```text
Resume[
  quantity,
  source_mode => resume_mode,
  argument,
  answer,
  captures,
  owner_generation,
]
```

普通 operation 在 successful resumption 时的 transition 是
`same => same`；`abort` 没有 resume transition。`TR₀` 的 logical clock
operation使用以下 profile-fixed annotation：

```cire
pub effect FrameClock {
  once yield() -> Unit
    resumes next
    may_suspend
}
```

带 `resumes next` 的 operation 只能通过 named capability 调用：

```cire
frame.yield()
```

目标 clock 就是 `frame` 的 identity；匿名 `FrameClock::yield()` 不合法。
Clause 中的 continuation 只能在该实例的合法 next-world witness 下恢复。
这个 effect 应 sealed；普通用户 handler 不能伪造 tick。

异步不是 `next(self)`。可以在 operation contract 中记录独立 suspension
属性：

```cire
pub(open) effect Async {
  once[A] await(task : Task[A]) -> A
    may_suspend
}
```

`may_suspend` 是工作拼写。重要的是它属于 ability operation contract，不能
在某个 `impl` 中从 same-world 偷换成 suspension，泛型 forwarding 也不能把
它抹掉。具体 handler 可以提供更精确的执行摘要：例如一个纯、同步完成的 mock
handler 可以证明 `NoSuspend`；Browser/host runner 即使消除了 residual
`Async` row，仍保留 `MaySuspend`。这与 handler 可以收紧 resumption quantity
上界兼容，不能简单把“row 已消失”当成“从未跨 segment”。

### 3.6 增量 continuation 需要 replacement contract

当前：

```cire
effect Observe {
  ctl[A] read(source : Source[A]) -> A
}
```

只能说明 handler 可以零到多次恢复 `k`。它不能静态表达：

- 同一 generation 最多恢复一次；
- 恢复会消费旧 checkpoint；
- 新执行产生 replacement subtree；
- 旧后代全部失效；
- resume 和 commit 都必须验证 generation。

如果目标只是“可信第一方库用一般 continuation 实现增量算法”，`ctl` 足够。
如果目标是“语言核心帮助保证第一方增量 replay 正确”，值得研究一个
**第一方 sealed checkpoint contract**。Quantity 仍写 `ctl`，另加一个正交
的 Kernel protocol：

```cire
pub effect Observe {
  ctl[A] read(source : Source[A]) -> A
    protocol checkpoint
}
```

`protocol checkpoint` 是工作用的 Core dump 写法，不是已建议冻结的 effect
源语法，也不是第五种一般 continuation quantity。它给可信 handler 的不是
任意 `Resume`，而是近似：

```text
Cut[A, R] {
  begin(epoch, value) -> Candidate[A, R]
  close()
}

Candidate[A, R] {
  publish(replacement_trace) -> NewGenerationLease
  park(owner) -> PendingCandidate[A, R]
  abort() -> CurrentGenerationLease
}
```

`Cut` 拥有可跨 revision 使用的 continuation template；一次 `begin` 只取得
candidate generation 的 one-shot lease，不会先销毁当前 committed
generation。Candidate 成功时，`publish` 原子安装 replacement trace、retire
旧后代并产生下一张 lease；暂停时 `park` 让 Owner 接管 candidate，同时保留
旧 committed generation；失败或被抢占时，`abort` 保留/重新武装当前
committed cut。这样多次 revision 通过连续 generation 工作，而不是在同一
generation 中任意 fork。

这仍不会自动实现 Source 索引、frontier、snapshot 或 trace tree；它只是把
最危险的恢复协议从库约定提升为可检查接口。是否值得增加这项 Core 能力，是
本文建议优先做演算原型的问题之一。

### 3.7 `live`、`transaction`、`async scope` 是 scoped constructs

以下构造都接收一段 computation，并建立新的 Owner、handler stack、snapshot
或 commit boundary：

```cire
live {
  ...
}

atomic {
  ...
}

Owner::scope {
  ...
}

resource(owner, key=key, policy=SwitchLatest) {
  ...
}
```

它们不应被强行编码成一个普通一阶 `perform Operation(value)`。表面仍可全部
是普通函数和 trailing lambda；Core elaboration 则需要保留 scoped
computation 的边界。

### 3.8 本轮收敛后的工作语法

真正新增到用户表面的候选只有：

```text
Type
  Next[clock_capability, A]

Expression
  delay[clock_capability] { expression }
  advance(expression)

Operation contract
  resumes next
  may_suspend
```

`advance` 的 clock 由参数的 `Next[frame, A]` 类型唯一确定，不再重复写
`advance[frame](x)`；若 identity 被 existential 隐藏，必须先在拥有 runner 的
scope 内 unpack。`resumes next` 只用于 named call，receiver identity 就是
目标 clock。`protocol checkpoint` 只保留为 Kernel dump 候选，不进入这份
surface grammar。

不新增：

```text
reactive var
effectful Later
await-as-advance
隐式 handler transport
```

`Signal`、`Live`、`Source`、`Event`、`Task`、`Resource`、`feedback`、
`live_result` 和 async occurrence policy 都先是第一方库/runner 名字。这样可
先验证 temporal/effect 核心，而不把某个响应式 runtime 的对象模型冻结进语法。

## 4. Handler instance 的 replay policy

### 4.1 Policy 在 effect 被消除后仍存在

Effect family 只描述可调用的 operation。以下三个 handler 都处理 `State`，
却有不同 replay 语义：

```text
State::shared
  replay 共享并继续累加

State::branch_snapshot
  multi-shot branch 各自取得快照

State::candidate
  candidate-local；成功后发布，失败或 replacement 时丢弃
```

因此不能只写：

```text
Replayable(State)
```

更接近所需信息的是具体 handler/runner instance 提供一组正交 laws：

```text
HandlerPolicy(handler) = {
  temporal : Pure | HostObservable,
  replay_origin : Fresh | Snapshot | SharedPersistent,
  fork : Forbid | Copy | Share | Merge,
  publish : None | CandidateBuffered | CommitOnly | Immediate,
  suspend : StackOnly | OwnerBound | Portable,
}
```

这些名称不是拟议的表面 record。`TemporalPure`、`ReplaySafe`、
`TraceCompatibleFork`、`SuspensionStable` 等是对这组 law 的约束，而不是
互斥标签；例如一个 handler 可以同时是 `Snapshot`、`Fork=Copy` 且
`CandidateBuffered`。

`live` 检查在 handler 消除 effect row 之后仍须保留这类摘要。否则下面的
`State` effect 虽然从最终 row 消失，编译器却失去了 replay 是否安全的信息。

这些 law 也不能全靠普通 trait 由用户自报：

```text
compiler-derived
  residual row、capture、quantity、Owner outlives、world/suspend summary

sealed witness
  TemporalPure host runner、CommutesWithNext、TraceCompatibleFork、
  candidate publish/abort law

explicit trusted/unsafe contract
  第三方 handler、FFI 或无法由类型结构证明的语义律
```

尤其对 `pub(open)` effect，第三方 handler 若能随意声称
`CommutesWithNext`，就可以伪造语言 soundness。会参与安全证明的 witness
constructor 应由 compiler 或 sealed first-party module 掌握；开放扩展只能
走显式 trusted/unsafe 边界。interface abstraction、泛型实例化和 FFI wrapper
必须保留这些摘要，不能因实现隐藏而退化为“row 为空”。

### 4.2 Compute / Commit 是独立 phase

Compute/Commit 不是 `Next` 的两个 tick，也不是两个同名 effect handler。
它们是 mode 中独立的 phase 坐标：

```text
Compute
  可 read/checkpoint
  可建立 candidate-local state/resource plan
  可 replay、abort、replace
  拿不到 HostWrite/Commit authority

Commit
  消费某个 revision 的 Commit authority
  不允许 checkpoint fork
  不允许把 authority 保存回 candidate
  由受限 runner 执行外部发布与 finalization
```

表面可以继续只用 named capability：

```cire
def compute_view(
  observe : cap Observe,
  declare : cap Declare,
) -> ViewPlan ! {observe, declare} {
  ...
}

def publish(
  commit : cap Commit,
  plan : ViewPlan,
) -> Unit ! {commit} {
  commit.publish(plan)
}
```

这里必须区分目标语义和当前类型能力。现有 `cap Commit` 本身仍是可复制值，
现有 quantity 只约束 operation resumption；不能声称 capture/quantity
checker 已静态证明 capability “最多消费一次”。

完整的静态方案需要未来的 affine authority（工作记法可想成
`once cap Commit`）以及 quantity 在值、closure 和容器中的传播。较窄的第一版
可以使用 sealed、可复制但共享同一原子 claim 的 `CommitGate`：

```cire
def try_publish(
  gate : CommitGate,
  revision : RevisionId,
  plan : ViewPlan,
) -> CommitResult ! {Commit}
```

复制 gate 只复制同一 claim 的句柄；`try_publish` 原子验证 generation，并只让
一次调用得到 `Committed`。这提供动态 at-most-once，而不是伪装成已有的静态
线性保证。Commit phase 仍禁止 checkpoint、`may_suspend` 和把 gate 保存进
candidate。

一个 handler 可以解释 Compute 内的 `Declare` 或 buffered log，但不能凭空
制造合法的 Commit authority。Multi-shot/checkpoint continuation 若捕获
未来 affine commit authority，必须被拒绝；若使用共享 gate，则重复调用只会
得到 `Stale`/`AlreadyCommitted`。

## 5. 例子矩阵

下表先给出结论，后文逐项展开：

| 场景 | 结论 | 主要理由 |
|---|---|---|
| 普通纯函数 | 接受 | 不受 temporal/reactive 机制影响 |
| 普通代数效应 | 接受 | 仍使用现有 effect row |
| 纯 `Next` | 接受 | clock、capture 和 shareability 可检查 |
| 过早或错 clock `advance` | 拒绝 | 违反 temporal availability |
| `delay` 隐藏未处理 effect | 拒绝 | effect laundering |
| `delay` 内部处理 effect | 有证据时接受 | residual row 为空且 handler 是 `TemporalPure` |
| 同步 Signal map | 接受 | tail 经 `Next` guarded |
| 一般递归假装 guarded | 不作保证 | Cire 仍允许 divergence |
| 普通 `await` | 接受 | `once` + Owner + suspension checks |
| `Next` 内直接 `await` | 第一阶段拒绝 | Task completion 不是 logical tick |
| 纯 `live`/动态依赖 | 接受 | runtime trace 记录精确依赖 |
| `live` 中外部写入 | 拒绝 | replay 重复外部行为 |
| candidate-local State | 扩展 API 中有证据时接受 | policy 属于 handler instance |
| Choice 包住 `read` | 第一阶段拒绝 | fork 了 cut、trace 与 candidate |
| `read` 后的纯局部 Choice | 有证据时接受 | 没有复制 checkpoint 后缀 |
| `live` 中直接 `await` | 第一阶段拒绝 | 会混合或长期保留 Epoch |
| Resource + Live | 接受 | 异步完成转为受 Owner 管理的输入 |
| Event occurrence | 接受 | 每次 occurrence 启动独立 action |
| Event 隐式当 Source coalesce | 拒绝 | 会无声明地丢 occurrence/order |
| Compute 直接 DOM/网络写 | 拒绝 | candidate 可被放弃 |
| Plan + single-claim Commit gate | 接受 | generation 验证和 at-most-once claim |

### 5.1 非响应、无 effect

```cire
def square(x : Int) -> Int {
  x * x
}
```

接受。普通程序没有 clock、scheduler 或 reactive runtime 语义。

### 5.2 非响应、普通 effect

```cire
def report() -> Unit ! {WallClock, Console} {
  let now = WallClock::now()
  Console::print_line(now.to_string())
}
```

接受。`WallClock` 是外部时间读取 effect，不是 modal logical clock。

普通 handler 组合不需要 `Next`：

```cire
with Console::buffered()
with Error::result()
in {
  report_job()
}
```

### 5.3 一个纯粹的下一时刻值

```cire
def next_double(
  frame : cap FrameClock,
  value : Int,
) -> Next[frame, Int] {
  delay[frame] {
    value * 2
  }
}
```

接受。`Int` 与 immutable capture 可以跨 tick。

过早打开：

```cire
def too_early(
  frame : cap FrameClock,
  value : Next[frame, Int],
) -> Int {
  advance(value)
}
```

拒绝：

```text
cannot advance value for `frame` in the current world
the value becomes available after one `frame` tick
```

在下一 world 中使用：

```cire
def after_one(
  frame : cap FrameClock,
  value : Next[frame, Int],
) -> Next[frame, Int] {
  delay[frame] {
    advance(value) + 1
  }
}
```

接受。

### 5.4 不同 clock 不能偶然对齐

```cire
delay[animation] {
  advance(network_value)
}
```

若：

```text
network_value : Next[network, A]
```

则拒绝。未来可以研究显式 clock inclusion/alignment witness，但不能默认
`animation` tick 推进 `network`。

同一 clock 的两层 delay 也不能自动压平：

```cire
let two_steps : Next[frame, Next[frame, Int]] =
  delay[frame] {
    delay[frame] {
      42
    }
  }
```

取得 `42` 需要两个 `frame` tick。默认提供：

```text
Next[frame, Next[frame, A]]
≠ Next[frame, A]
```

否则 guarded program 可以把任意多步未来压回一步，破坏 causality。

world-changing operation 的最小正例：

```cire
let value =
  delay[frame] {
    42
  }

frame.yield()
let answer = advance(value)
```

`frame.yield()` 后的 continuation 在 `next(frame)` world 检查，因此
`advance(value)` 合法。下面的伪 handler 不能被接受：

```cire
let bad_frame = handler FrameClock {
  once yield() as k =>
    k.resume(())
}

with bad_frame as frame
in {
  let value = delay[frame] { 42 }
  frame.yield()
  advance(value)
}
```

第一版 `FrameClock` 是 sealed，普通用户根本不能构造该 handler；即使在定义
package 内，`k.resume(())` 也因没有合法的 `next(frame)` witness 而被
typechecker 拒绝，不能在 current world 同步伪造 tick。

这个变化不能只写进 set-like effect row。以下是 typed-HIR 的示意签名，不是
冻结的表面语法：

```text
forward_yield :
  (frame : cap FrameClock)
  -> Unit ! {frame}
  @ same => next(frame)
```

高阶参数、effect-polymorphic forwarding function 和 interface artifact 都
必须保留 `pre => post` transformer；若把它降成普通 `() -> Unit ! {frame}`，
调用者便可能错误地提前 `advance`。

### 5.5 同步 Signal

概念类型：

```text
Signal[frame, A]
  ≅ Step(A, Next[frame, Signal[frame, A]])
```

纯 `map`：

```cire
def[A, B] map_signal(
  frame : cap FrameClock,
  input : Signal[frame, A],
  transform : (A) -> B,
) -> Signal[frame, B] {
  match input {
    Step(value, tail) =>
      Step(
        transform(value),
        delay[frame] {
          map_signal(frame, advance(tail), transform)
        },
      )
  }
}
```

它不是对任意 `B` 都成立：`B` 必须满足 `Shareable`，否则整个
`Signal[frame, B]` 不能成为可重复观察的 `Next` 结果。`transform` 本身还要
通过 `TemporalStable(frame, free_values(transform))` 与
`CrossWorldSafe(frame, captures(transform))`。

捕获短命 host event：

```cire
Host::on_event { event_ref =>
  let payload_view = event_ref.borrow_payload()

  let transform = fn(x) {
    pure_hash(payload_view, x)
  }

  map_signal(frame, input, transform)
}
```

拒绝。即使 `borrow_payload` 和 `pure_hash` 都没有 effect，
`payload_view : CallbackLocal[Payload]` 也只在本次 callback generation
有效；这个例子专门测试 temporal provenance，而不是先被 Host effect row
拒绝。

先取稳定快照：

```cire
Host::on_event { event_ref =>
  let event = event_ref.snapshot()

  let transform = fn(x) {
    inspect(event, x)
  }

  map_signal(frame, input, transform)
}
```

若 `snapshot()` 产生 deep-owned、immutable 且 `Shareable` 的副本，则接受；
只复制一个仍指向 host buffer 的浅句柄不够。

### 5.6 Guarded feedback 与一般递归

可以用 sealed combinator 暴露 guarded fixed point：

```cire
def naturals(
  frame : cap FrameClock,
) -> Signal[frame, Int] {
  @temporal.feedback(frame) { self =>
    Step(
      0,
      delay[frame] {
        map_signal(frame, advance(self), fn(x) { x + 1 })
      },
    )
  }
}
```

其中：

```text
self : Next[frame, Signal[frame, Int]]
```

只允许在 `delay[frame]` 后 `advance`。

也可以研究可选 certification：

```cire
guarded[frame] def from(n : Int) -> Signal[frame, Int] {
  Step(
    n,
    delay[frame] {
      from(n + 1)
    },
  )
}
```

但 Cire 是允许一般递归与 divergence 的通用语言：

```cire
def bad(
  frame : cap FrameClock,
) -> Signal[frame, Int] {
  bad(frame)
}
```

仅加入 `guarded` 不能让整个语言突然获得 totality/productivity theorem。
第一阶段更适合把保证局限在 `feedback` 或被检查的 `guarded` 定义。

### 5.7 Reader 与 `Next`

现在读取、未来使用：

```cire
with Reader::value(10) as reader
in {
  let value = reader.ask()

  delay[frame] {
    value + 1
  }
}
```

接受。未来值捕获的是普通 `Int`。

把 handler capability 带进未来：

```cire
with Reader::value(10) as reader
in {
  delay[frame] {
    reader.ask() + 1
  }
}
```

第一阶段拒绝：外层 handler 不自动跨 temporal boundary。若 handler 明确
提供 portable/commuting witness，以后可以由显式 bridge 支持。

### 5.8 Error 与 `Next`

在未来内部处理：

```cire
let parsed =
  delay[frame] {
    with Error::result()
    in {
      parse(text)
    }
  }
```

接受：

```text
parsed : Next[frame, Result[Value, ParseError]]
```

在现在外部处理：

```cire
with Error::result()
in {
  delay[frame] {
    parse(text)
  }
}
```

第一阶段拒绝。两种 handler placement 不能由优化器重排。

### 5.9 Local State 与 `Next`

未来内部创建、处理并关闭 local State：

```cire
delay[frame] {
  with State::local(10) as state
  in {
    state.set(state.get() + 1)
    state.get()
  }
}
```

若 handler 的正常返回值不捕获 `state`，结果是纯 `11`，可以接受。

从现在捕获 persistent mutable authority：

```cire
with State::shared(10) as state
in {
  delay[frame] {
    state.set(11)
    state.get()
  }
}
```

拒绝。它既跨 tick 捕获 mutable authority，又让普通可复制 `Next` 隐藏未来
写入。

### 5.10 Nondeterminism 与 `Next`

现在分支、未来使用分支值：

```cire
with Choice::all()
in {
  let value = Choice::choose([1, 2])

  delay[frame] {
    value * 10
  }
}
```

结果近似：

```text
Array[Next[frame, Int]]
```

未来才分支，但在未来内部彻底处理：

```cire
delay[frame] {
  with Choice::all()
  in {
    Choice::choose([1, 2]) * 10
  }
}
```

结果近似：

```text
Next[frame, Vector[Int]]
```

这里假设 `Choice::all` 返回 persistent `Vector`，且具体 handler 提供
`TemporalPure`；两段都可接受，但不等价。

Multi-shot continuation 捕获 one-shot authority：

```cire
effect OneShot {
  once obtain() -> Int
}

let bad = handler OneShot {
  once obtain() as k => {
    with Choice::all()
    in {
      let value = Choice::choose([1, 2])
      k.resume(value)
    }
  }
}
```

拒绝。`Choice::choose` 的 multi-shot continuation 捕获了 `once k`，因此会
尝试复制 one-shot resumption。这个例子没有 IO 或 residual Host effect，
专门验证 control-flow quantity 与 capture checking。

### 5.11 普通 async/await

```cire
Owner::scope { owner =>
  with BrowserAsync::run(owner)
  in {
    let connection = connect()
    defer connection.close()

    let response = Async::await(request(connection))
    use(response)
  }
}
```

接受，前提是：

- `await` continuation 是 `once`；
- Owner 接管 parked continuation 和 cleanup；
- completion、failure、cancel 竞争同一个 one-shot disposition；
- continuation captures 在 suspension boundary 后仍有效；
- resume 时重新验证 Owner/generation。

这里的“接受”只覆盖 control/lifetime 形状；Task error/cancellation 最终采用
`Result`、effect 还是 typed discontinuation，仍是独立的表面设计问题。

事务不能跨 `await`：

```cire
atomic {
  let result = Async::await(task)
  state.set(result)
}
```

拒绝。应拆成：

```cire
let request_version = atomic {
  saving.set(true)
  state.version()
}

let outcome = Async::await_outcome(task)

atomic {
  saving.set(false)

  match outcome {
    Completed(value) if state.version() == request_version =>
      state.set(value)
    Completed(_) | Failed(_) | Cancelled =>
      ()
  }
}
```

`await_outcome` 是错误通道尚未冻结前的示意 API。关键是失败/取消也要走清理
路径，而且成功发布要重新验证 version/Owner。若 cancellation 采用
discontinuation，等价的 `defer` 必须拥有第二段原子清理责任。

### 5.12 `Next` 不是 `Task`

第一阶段拒绝：

```cire
delay[frame] {
  Async::await(task)
}
```

理由不是语法实现困难，而是语义不匹配：

- 一个 frame tick 不保证 task 完成；
- task 可能永不完成；
- `Next` 的可复制/缓存语义不适合隐藏一次性异步 continuation；
- future handler 与 cleanup owner 未被类型表达。

即使在 `delay` 内安装一个会真正停车的 handler，row 消失也不能洗掉
`MaySuspend`：

```cire
delay[frame] {
  with BrowserAsync::run(owner)
  in {
    Async::await(task)
  }
}
```

仍拒绝。相反，先完成异步、再构造纯未来值是合法的：

```cire
let value = Async::await(task)

let next =
  delay[frame] {
    pure_transform(value)
  }
```

若 `value` 与 transform 的 captures 都是 `Shareable`、`TemporalStable` 和
`CrossWorldSafe`，接受。

显式 bridge：

```cire
let completion = Event::from_task(owner, task)
```

或下一 frame 只产生纯 command：

```cire
let request_plan =
  delay[frame] {
    FetchPlan::new(request)
  }

Frame::once_next(frame, owner) {
  let plan = advance(request_plan)
  Async::await(execute(plan))
}
```

`once_next` 是 one-shot callback；它在获得合法 tick evidence 的上下文中
检查。异步 effect 发生在独立 action 中，没有藏进 `Next`。持续订阅应使用
名字明确的 `on_each_tick`，不能让同一 request plan 每帧重复执行。

Async handler 的位置同样可观察。最近的 Async delimiter 内侧 handler 会被
parked continuation 捕获，只有满足 `SuspensionStable` 且受 Owner 管理时才能
跨 await：

```cire
with BrowserAsync::run(owner)
in {
  with Error::result()
  in {
    let value = Async::await(task)
    parse(value)
  }
}
```

外侧 handler 默认只围住 runner 的当前调用，不能自动被假定进入 parked
continuation；若 runner 要携带 outer context，必须在 contract 中明确。

Choice 在 await 之前且其 multi-shot continuation 包含 await，默认拒绝：

```cire
with Choice::all()
in {
  let endpoint = Choice::choose(endpoints)
  Async::await(fetch(endpoint))
}
```

它需要显式定义 Task、Owner、取消和结果的 fork/merge policy。先 await，随后
安装并完全处理一个纯 Choice，则可以接受：

```cire
let response = Async::await(task)

with Choice::all()
in {
  decode_as(Choice::choose(formats), response)
}
```

### 5.13 基本 `Live`

```cire
let total =
  live {
    read(price) * read(count)
  }
```

接受。这里不需要 `Next`。

动态依赖：

```cire
let selected =
  live {
    if read(flag) {
      read(primary)
    } else {
      read(secondary)
    }
  }
```

接受。本轮依赖集合由 trace 动态记录：

```text
revision r0: {flag, primary}
revision r1: {flag, secondary}
```

类型系统只记录允许读取的能力和 replay/capture 上界。

一个 batch 同时更新多个 Source 时，单个 candidate 必须固定在同一最终 Epoch：

```cire
batch {
  price.set(12)
  count.set(3)
}
```

`total` 可以跳过中间组合，但不能短暂发布 `12 * old_count`。这是一项
glitch-free snapshot obligation，不由 `Next` 或普通 effect row 自动提供。

当前最小 API 只让 `Live` 读取 `Source`，并不表达下面这种 shared
Derived-to-Derived 互读。若未来加入一般 DAG 或语言级 live variable，这个
扩展不能靠“也许会收敛”取得定义：

```cire
let left  = live { read(right) + 1 }
let right = live { read(left) - 1 }
```

届时必须把 cycle rejection 或 runaway guard 与扩展一起设计；当前第一方最小
实现不因此承诺通用 DAG/cycle detection。需要固定点时，应使用明确的
`feedback`/iteration API，选择初值、收敛判定、迭代上限和失败策略；这也避免
把 Verse 式可能 diverge 的 live write 隐藏在普通 assignment 中。

### 5.14 `Live` 中的外部写入

```cire
live {
  let amount = read(total)
  charge_credit_card(amount)
}
```

拒绝。Source 每次变化都会重放收费。

即时读取后回写：

```cire
live {
  let value = read(counter)
  write(counter, value + 1)
}
```

也拒绝。它形成未显式延迟的反馈，并会不断产生新 Epoch。

正确拆分 Compute 和 Commit：

```cire
let plan =
  live {
    ViewPlan::text(read(name))
  }

Renderer::mount(owner, plan)
```

Renderer 内部拥有 single-consumer revision queue 和当前 `CommitGate`。公开
的 `changes(plan) : Event[Revision[ViewPlan]]` 至多携带 shareable 的
`(revision_id, plan)`；绝不把 affine authority 放进可广播 Event payload。
renderer 取 revision、验证当前 generation，再以共享原子 claim
`try_publish`。如果未来有 affine commit authority，也只能进入 sealed
single-consumer runner。

Commit gate 不能跨异步暂停：

```cire
Commit::run(revision) { gate =>
  let asset = Async::await(load_asset())
  gate.try_publish(revision.id, render(plan, asset))
}
```

第一版拒绝。暂停期间 revision 可能已经过期；`once` 只保证 continuation 不
复制，并不保证 authority 仍新鲜。正确顺序是先通过 Resource/Task 产出纯 plan，
resume 后重新验证 revision，再取得 fresh gate；需要乐观协议时只能显式使用
`try_publish -> Committed | Stale`。

### 5.15 `Live` 与 State handler

最小第一方签名应近似：

```text
live : (() -> A ! {Observe}) -> Live[A]
```

因此捕获外层 State/Async/Error handler 的程序首先就会因 row、capture 或
lifetime 被拒绝。下面仍列出交叉例子，是为了审查一个未来可能的
`live_with(handler, body)` 扩展，以及“handler 在 body 内消除 row”时必须保留
的 replay 摘要；它们不是在扩大最小 `live`。

外层 shared State：

```cire
live_with(State::shared(0)) { state =>
    let input = read(source)
    state.set(state.get() + input)
    state.get()
}
```

拒绝。每次 replay 都在旧累计值上继续，不满足 from-scratch consistency。

仅仅把 handler 放到 `live` 内也不自动安全：

```cire
live {
  with State::local(0) as state
  in {
    let input = read(source)
    state.set(state.get() + input)
    state.get()
  }
}
```

`read` cut 可能捕获 State handler 的内部状态；恢复时是共享、复制还是回滚，
由具体 handler 语义决定。只有明确提供 candidate policy 时接受：

```cire
live {
  with State::candidate(0) as state
  in {
    let input = read(source)
    state.set(state.get() + input)
    state.get()
  }
}
```

其 contract 至少是：

```text
candidate start  -> fresh/snapshotted state
candidate abort  -> discard
candidate commit -> publish once
checkpoint fork  -> prohibited or precisely defined
```

### 5.16 Error handler 与 `Live`

在 replay body 内安装：

```cire
let parsed =
  live {
    with Error::result()
    in {
      parse(read(text))
    }
  }
```

接受，结果：

```text
Live[Result[Value, ParseError]]
```

外层 handler：

```cire
with Error::result()
in {
  live {
    parse(read(text))
  }
}
```

第一阶段硬拒绝。外层 handler 只包围 `live` 的创建调用，不能自动成为未来
每次 replay 的 portable handler。第一方可以提供语义明确、每轮重新安装
handler 的 `live_result` combinator。

### 5.17 Nondeterminism 与 `Live`

```cire
live {
  with Choice::all()
  in {
    let branch = Choice::choose([left, right])
    read(branch.source)
  }
}
```

即使 `Choice` 被内部 handler 消除，第一阶段仍拒绝：

- 每个 branch 是否有独立 trace；
- State、Owner 和 resource 是否 fork；
- 哪些 branch 可以 commit；
- branch 消失时如何 finalize；
- source invalidation 如何映射到 branch frontier；

都尚未定义。以后可以让一个专用 search handler 提供
`TraceCompatibleFork` witness，不能从空 residual row 推断安全。

但不能按 effect family 一刀切。如果 `read` 已完成，之后才安装并完全处理纯
Choice，而且被复制的 continuation 后缀不再包含 Observe、Resource 或 Commit，
则可以接受：

```cire
live {
  let x = read(source)

  with Choice::all()
  in {
    x + Choice::choose([1, 2])
  }
}
```

结果近似 `Live[Vector[Int]]`，前提是具体 Choice handler 是
`TemporalPure`、`TraceNeutral`，结果 `Shareable`。局部 State 同理：先完成
最后一个 `read`，再安装并关闭 fresh local State，且没有后续 cut 时可以安全；
真正决定判定的是 handler 是否进入 checkpoint continuation，而不是
`Choice`/`State` 这个 family 名。

### 5.18 为什么普通 `live` 不直接允许 `await`

危险例子：

```cire
live {
  let x = read(a)
  let y = Async::await(fetch(x))
  let z = read(b)
  x + y + z
}
```

若等待期间输入从 Epoch 1 走到 Epoch 3，有三种互不等价的选择：

1. 直接续跑：`x@1 + y + z@3`，混合 snapshot；
2. 保留 Epoch 1：保持一致，但可能长期保留旧世界和资源；
3. 回到 Epoch 3 重跑：需要取消/去重 task，并验证结果是否仍适用。

不能给普通 `live` 偷偷选择其中一种。第一阶段应让 `live` 的允许 row 排除
`Async`。即使局部 handler 把 `Async` 从 residual row 消除，
`may_suspend` 或 world-transition 摘要也不能随之消失；只有显式
async-live policy 才能消费这项摘要。

推荐让普通库式 Resource 接受一个 `Live[Key]`，避免 trailing-lambda 参数在
进入 resource scope 前就执行 `read`：

```cire
let selected =
  live {
    read(selected_user)
  }

let profile =
  resource(
    owner,
    key=selected,
    policy=SwitchLatest,
  ) { user_id =>
    load_user(user_id)
  }
```

Resource completion 更新自己的 Source/Event，再触发一个使用固定 Epoch 的
纯 `live`。

以后若需要 `live_async`，必须显式选择：

```text
Restart
  依赖变化即取消/废弃旧 continuation，从新 Epoch 重跑

RetainSnapshot
  continuation 保留旧 snapshot；需要资源上界

Validate
  恢复后验证 await 前依赖；不匹配则重启
```

不提供隐式默认。

### 5.19 Observe 与 Await 的顺序

[reactive-ui.md](reactive-ui.md) 中的 `read; await` / `await; read` 是 richer
UI candidate/resource runner 的概念控制顺序，不是最小 `live` 可直接接受的
源码；以下把同一意图改写成具有明确 lifetime/policy 的第一方 API。

“Observe 在 Await 前”应通过 Resource key 表达：

```cire
let key =
  live {
    read(selected_user)
  }

resource(owner, key=key, policy=SwitchLatest) {
  user_id => load_user(user_id)
}
```

`resource` 订阅 `Live[Key]`；key 变化会替换旧 task generation。另一种可行
设计是把 `resource` 定义为真正的 scoped elaboration，并明确 key expression
在 Observe scope 中求值；本文优先保留普通函数/trailing-lambda，因此采用
`Live[Key]` API。

“Await 在 Observe 前”可先把 Task completion 变成稳定输入：

```cire
let config = Resource::once(owner) {
  load_config()
}

let view =
  live {
    let ready_config = read(config.value)
    let theme = read(theme_source)
    render(ready_config, theme)
  }
```

之后 `theme` 变化只重算 render 后缀，不重新发起 `load_config`。

### 5.20 Event action 不是永久续体

```cire
clicks.on(owner) { _ =>
  atomic {
    counter.update(fn(count) { count + 1 })
  }

  Console::print_line("clicked")
}
```

接受：

- listener 在 Owner 存活期间 many-shot；
- 每个 occurrence 启动新的 action；
- 每个 action 的 `await` continuation 若存在，仍是独立 `once`；
- `snapshot` 不建立长期 invalidation dependency。

这里使用原子 `update` 而不是 `snapshot` 后 `write`，避免并发 occurrence
lost update；`snapshot` 仍适合 read-only action。

下面应拒绝或诊断：

```cire
clicks.on(owner) { _ =>
  read(counter)
}
```

Event action 需要当前快照，不应因一次偶然 `read` 偷偷建立长期订阅。

many-shot listener 也不能捕获未来 affine authority：

```cire
Commit::run(revision) { gate =>
  clicks.on(owner) { _ =>
    gate.try_publish(revision.id, plan)
  }
}
```

若 gate 是未来的 affine value，closure 会被 many-shot 调用，静态拒绝；若是
当前的共享原子 `CommitGate`，注册动作本身仍因 gate 逃离 Commit phase 而
拒绝。

Event action 内的 await 必须显式选择 occurrence concurrency：

```text
clicks.on_async(owner, policy=Merge)       // 每次 occurrence 独立并发
clicks.on_async(owner, policy=SwitchLatest)// 新 occurrence 取消/废弃旧 action
clicks.on_async(owner, policy=Concat)      // 保序串行
clicks.on_async(owner, policy=Exhaust)     // 忙时忽略新 occurrence
```

普通 `.on` 不应偷偷选择其中之一。类似地，Event 到 Source 并非永远非法，但
丢失语义必须出现在 API 名或类型中：

```text
Source::hold_latest_lossy(initial, event)
Queue::from_event(owner, event)
Source::fold(initial, event, reduce)
```

被拒绝的是无声明、却声称 lossless 的 implicit coalescing。

### 5.21 `sample` 必须有两种时序语义

考虑：

```cire
batch {
  value.set(1)
  trigger.emit(())
}
```

与：

```cire
batch {
  trigger.emit(())
  value.set(1)
}
```

不能只提供一个含糊的 `sample(trigger, value)`。

可以区分：

```text
sample_epoch(trigger, value)
  occurrence 读取本批固定的最终 snapshot；batch 成功时两段都得到 1

with_latest_from(trigger, value)
  按 occurrence 顺序读取当时的前沿值；两段结果可能不同
```

这也要求运行时区分三种 dependency：

```text
invalidating read
  Source 变化会让 Live 重算

snapshot/validation read
  只在触发时读取，不自行唤醒

occurrence wake
  Event 到达时运行，保留顺序和 multiplicity
```

一个可在普通 `live` 中随意使用的 `peek` 会制造永久 stale 结果，应被限制在
event/snapshot capability 中。

### 5.22 Handler ordering 仍然可观察

```cire
with Logger::run()
with Error::logs()
in {
  action()
}
```

Error clause 发出的日志能到达外层 Logger。

反序：

```cire
with Error::logs()
with Logger::run()
in {
  action()
}
```

Error handler 自己已经位于 Logger 动态范围外，可能留下未处理日志。

Temporal 和 replay 系统不能以“优化”为由重排 handler。

类似地：

```text
State outside Choice  与  State inside Choice
```

通常分别表达 shared state 与 branch-local state。具体 instance 还须声明
fork/replay policy，ordering 不能替代 policy。

### 5.23 Owner、cancellation 与 stale completion

```cire
Owner::scope { owner =>
  let task = start(owner)
  let value = Async::await(task)
  Commit::try_current(owner, value)
}
```

completion、cancel、timeout 必须原子竞争同一个 one-shot claim。检查不能只在
callback 入队时发生；至少在：

```text
enqueue
resume
commit
```

三处验证 `(owner generation, candidate generation, continuation generation)`。

Cancellation 不是一个 catch 后便可恢复旧 Commit authority 的普通 Error。
即使业务代码捕获取消，revocation 仍永久有效。

branch replacement 关闭的 resource/defer 必须 exactly-once：candidate abort
只清理 candidate 新建的 segment，成功 publish 才 retire 被替换的 committed
后代；Owner close 再与两者竞争同一 disposition claim。

### 5.24 Wasm host callback 边界

```cire
Frame::once_next(frame, owner) {
  update_animation()
}
```

浏览器 callback 不应直接持有一个可以无条件恢复的裸 continuation。它携带的
应是：

```text
weak owner token
+ generation
+ scheduler wake token
```

回调只向拥有 continuation 的 scheduler 投递 wakeup。这样 modal/effect
设计不依赖 Wasm 提供原生 stack capture，也不要求线程或 GC 才能表达语义。

这里的语言设计约束是 continuation/capture/Owner 可显式描述，而不是预先
冻结某种 Wasm runtime 实现。

两个 capture 判定不依赖具体 Wasm lowering：

```cire
Host::with_memory_slice { borrowed =>
  let value = Async::await(task)
  decode(borrowed, value)
}
```

拒绝：borrowed JS callback ref、Wasm linear-memory slice 或会因 memory growth
失效的 view 不能跨 `await`、`Next` 或 checkpoint。先 deep-copy 成 owned
immutable bytes，或使用由 Owner root 且明确可移动/可持久化的 `externref`，
再跨 boundary，才可接受。

会恢复 async/replay cut 的 JS 同步 reentrancy 不能 inline 恢复当前 cut；
这类 host callback 只能 enqueue 下一 scheduler turn/Epoch。普通、不接触
parked/replay continuation 的同步 FFI callback 不受此限制。Promise completion
在 Owner close 后到达时，由 generation gate 丢弃。这样同一 trace 不会在
尚未完成 replacement 时递归进入自己。

## 6. 对抗性 review：从诱人的 v0 到较稳的 v1

### 6.1 v0：一个万能 `Later`

最初容易写成：

```text
Later[clock, A]
later[clock] { e }
advance(x)

Live[A] ≈ Signal[clock, A]
await(task) : Later[clock, A]
read(source) : Later[clock, A]
```

这套设计在简单 demo 中很漂亮，但被例子击穿：

| 反例 | v0 的问题 | v1 修订 |
|---|---|---|
| `later { charge() }` | latent effect 被洗掉 | `Next` 第一阶段只允许 residual-pure body |
| ready/never task | Task 不是严格下一 tick | Task 与 Next 分离 |
| `live { read; await; read }` | 混合 Epoch | 普通 Live 排除 Async，使用 Resource |
| outer handler + delay | handler lifetime 不明确 | handler 不默认穿过 modality |
| `ctl read` | 同代可任意 fork | 研究 sealed checkpoint/replacement contract |
| shared State in Live | family 名相同但 replay 语义不同 | policy 属于 handler instance |
| `advance` affine result twice | 复制 authority | `Shareable(A)` 或未来传播 quantity |
| two clocks | 一个 global Later 泄漏抽象 | generative clock identity |

### 6.2 仍然保留的成本

v1 不是免费午餐：

1. `Next[frame, A]` 让 term identity 进入受限类型位置。
2. `delay` 外的 handler 不进入 future，对初学者需要好诊断。
3. effectful delayed computation 暂时不够直接。
4. `TemporalStable`、`CrossWorldSafe`、`Shareable` 和 handler policy 会
   增加 Core 判断。
5. 一般 recursion 意味着只能对受控 feedback 子语言给强 productivity 保证。
6. `checkpoint` 若进入 Core，会增加一种不属于普通 quantity lattice 的协议。

这些成本仍比“所有变量都 reactive、所有异步都是 Later、所有 handler 自动
可 replay”更局部，也更容易分别证明。

## 7. 哪些属于语言，哪些属于第一方协议

### 7.1 语言/Core 负责

- effect row 与 effect polymorphism；
- `abort / once / fun / ctl`；
- continuation 的 source/resume world；
- named capability identity；
- capture、outlives、quantity 与 storage-boundary checking；
- sealed `Next/delay/advance`（若采纳）；
- handler transition 与 portability contract；
- 可能的 sealed checkpoint continuation contract；
- multi-shot/world crossing 不复制 one-shot resumption；未来若引入 affine
  value/authority，quantity 还须传播到一般 capture；
- 在此之前，Commit 由 sealed `CommitGate` 的 generation validation 与共享
  原子 claim 动态保证 at-most-once。

### 7.2 第一方增量/runtime 负责

- Source 到 cut 的 wake index；
- dependency trace 与 ancestor dominance；
- earliest invalidation frontier；
- fixed Epoch snapshot；
- candidate generation 与 replacement subtree；
- task/resource policy；
- event ordering 与 multiplicity；
- commit gate、renderer protocol 和 retry；
- cycle detection、fairness 与调度。

### 7.3 用户默认不应看到

普通业务函数不需要写 world judgment、capture set 或 replay policy。它们进入：

- typed HIR；
- interface artifact；
- generic constraint 求解；
- storage-boundary diagnostics；
- 高级 IDE/type dump。

只有 clock identity 真正影响表面类型时，才出现 `Next[frame, A]`；但公开泛型
API 的 interface artifact 还必须保存推导出的 `Shareable`、temporal
stability、capture polymorphism、handler law 和 world transformer 约束，
即使源代码省略了它们。

## 8. 与本设计最相关的研究

### 8.1 Modal FRP

- [Simply RaTT](https://arxiv.org/abs/1903.05879) 用 Fitch-style modality
  保证同步 FRP 的 causality/productivity，并研究无隐式 space/time leak 的
  执行。
- [Lively RaTT](https://arxiv.org/abs/2003.03170) 的关键提醒是：
  它把 LTL 的 time-step modality 作为 guarded-recursion step modality 的
  submodality；两者有关联，但不能简单视为同一个 operator。
- [Async RaTT](https://arxiv.org/abs/2303.03170) 去掉单一 global clock，
  让异步输出在运行时关联实际依赖的输入 channel，并静态估计依赖上界。
- [When Programs Have to Watch Paint Dry](https://arxiv.org/abs/2210.07738)
  直接把 time-graded Fitch modality 与 temporally aware algebraic effects
  放在同一 calculus 中；operation 的 continuation 知道 operation 消耗了多少
  时间。这是 world-changing operation 最直接的参照。

这些工作共同启发 next-step modality、非全局或 dependency-indexed clock 和
time-aware continuation；它们没有验证本文具体的 `Next[frame, A]` singleton
capability encoding，也不提供 Cire 所需的 incremental replacement trace。

工程经验也值得区分强弱：

- [Modal FRP for All](https://doi.org/10.1017/S0956796822000132) 通过 Haskell
  library/compiler plugin 实现 Rattus，说明 Fitch 检查可以与现有通用语言
  生态共存。
- [Asynchronous Reactive Programming with Modal Types in Haskell](https://doi.org/10.1007/978-3-031-52038-9_2)
  实现 Async Rattus，并推断会动态变化的 clock。
- [Compiled Async RaTT / ComRaTT](https://bahr.io/students/Compiled%20Async%20RaTT.pdf)
  是把 Async RaTT 子集直接编译到 Wasm 的 proof-of-concept。它很贴近 Cire 的
  backend 约束，但语言子集有限、缺完整自动内存管理，不能当成完整 correctness
  或生产实现证据。

### 8.2 Modal types 与 algebraic effects

- [Contextual Modal Types for Algebraic Effects and Handlers](https://arxiv.org/abs/2103.02976)
  把 effect theory 当作 contextual modal type 的上下文，handler 则是上下文
  之间的 witness。
- [Modal Effect Types](https://arxiv.org/abs/2407.11816) 与
  [Rows and Capabilities as Modal Effects](https://arxiv.org/abs/2507.10301)
  说明 modal presentation 可以减少显式 effect polymorphism 的表面负担，
  并连接 row 与 capability。
- [Combining Effects and Coeffects via Grading](https://www.repository.cam.ac.uk/items/23e2f7fa-cda6-445c-9af8-d57ae5f43452)
  区分“改变上下文”的 effect 与“要求上下文”的 coeffect，并用 graded
  distributive law 描述二者交互。它为 effect 与环境需求分轴提供语义类比；
  动态 dependency discovery 和 capability lifetime 仍是本文额外设计。
- [What Monads Can and Cannot Do with a Few Extra Pages](https://arxiv.org/abs/2311.15919)
  系统研究 guarded/coinductive delay monad 与其他 effect monad 的
  distributive-law 组合。它是“不要默认 effects 与 delay 交换”的有力警告，
  但不是关于本文 Fitch `Next` 与 Cire handler 的直接定理。

### 8.3 World-indexed computation 与 handler

- [Parameterised Notions of Computation](https://bentnib.org/param-notions.html)
  用前后索引描述状态或协议变化。
- [Unifying graded and parameterised monads](https://arxiv.org/abs/2001.10274)
  用 category-graded monad 统一 effect grade 与 pre/post index。
- [Category-Graded Algebraic Theories and Effect Handlers](https://arxiv.org/abs/2212.07015)
  进一步让 operation 和 handler 都携带 category morphism，接近
  `same → next(clock)` 的 operation contract。
- [Answer Refinement Modification](https://arxiv.org/abs/2307.15463)
  表明 effect handler 的 continuation 类型可以精确反映 effect 的顺序以及
  answer refinement 的变化。把 phase/world 当成类似 pre/post index 是本文
  的进一步类比，仍需独立 calculus 和 preservation proof。
- [First-Class Names for Effect Handlers](https://doi.org/10.1145/3563289)
  与 [A Type System for Effect Handlers and Dynamic Labels](https://doi.org/10.1007/978-3-031-30044-8_9)
  更直接覆盖 generative handler identity、name escape、aliasing 与 effect
  polymorphism。它们支持 Cire 继续复用 named capability infrastructure，
  但没有验证把动态 term identity 直接放进 `Next` 类型索引。

### 8.4 Capture、linearity 与 resource boundary

- [Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402)
  是“值实际捕获了哪些 capability”的直接类型系统依据。
- [Effects, Capabilities, and Boxes](https://se.informatik.uni-tuebingen.de/publications/brachthaeuser22effects/)
  更接近用 boxing 协调 effect、capability 与 escape；它为 modal storage
  boundary 提供相邻设计，而非同一结论的重复证明。
- [Soundly Handling Linearity](https://arxiv.org/abs/2307.09383) 说明
  continuation 的使用次数必须服从其捕获资源的 linearity；这直接覆盖
  multi-shot、one-shot authority 与 cleanup 的组合。
- [Runners in Action](https://arxiv.org/abs/1910.11629) 把 runner 用于外部
  资源与 finalization，并保证资源线性使用，适合作为 Compute 之外受限 Commit
  runner 的参照。

### 8.5 Scoped、latent 与 asynchronous effects

- [Structured Handling of Scoped Effects](https://arxiv.org/abs/2201.10287)
  与 [A Framework for Higher-Order Effects & Handlers](https://arxiv.org/abs/2302.01415)
  说明 `live { computation }`、`transaction { computation }` 和 delay 在源
  语义上具有 higher-order/scoped boundary；即使 elaboration 到一阶
  operations，也必须显式保留 scope 和 handler interaction。
- [Latent Effects](https://arxiv.org/abs/2108.11155) 专门研究 defer、lazy 和
  staging 的语义编码，可作为一般 effectful `Later` 的 encoding pattern；
  它不直接给出 Cire 的 capture、Owner 或 lifetime 规则。
- [Asynchronous Effects](https://arxiv.org/abs/2003.02110) 区分主动
  operation call 与外部 signal/interrupt；这支持让 host completion 先进入
  scheduler，而不是直接从浏览器 callback 恢复裸 continuation。Owner 与
  generation validation 是本文基于 Cire 资源模型作出的额外推论。
- [Structured Asynchrony with Algebraic Effects](https://www.microsoft.com/en-us/research/publication/structured-asynchrony-algebraic-effects/)
  和 [Higher-Order Asynchronous Effects](https://arxiv.org/abs/2307.13795)
  提供 cancellation、timeout、async scope 与外部 signal 的更直接参照。
- [Versatile Event Correlation with Algebraic Effects](https://doi.org/10.1145/3236762)
  用 handler 解释异步 event notification 和可定制 joins，说明 Event
  correlation 确实可建立在 algebraic effects 上；它也提醒我们
  `combineLatest`、zip、cartesian/fork 等 policy 不是同一个默认行为。

### 8.6 Incremental computation

- [Incremental Computation with Names](https://arxiv.org/abs/1503.07792)
  论证并实证 first-class names 对复用效率的重要性，并在其 calculus 中证明
  from-scratch consistency。
- [A Consistent Semantics of Self-Adjusting Computation](https://arxiv.org/abs/1106.0478)
  直接组合 mutation、memoization 与 change propagation，并证明一致性与相对
  纯函数执行的正确性；它是 replacement runtime 的重要 correctness 基线。
- [Fungi](https://arxiv.org/abs/1808.07826) 进一步用类型与 effect 静态验证
  name 的正确使用。它提醒我们 cache node identity、handler identity 与
  Source identity 是三类不同名字。
- [A Theory of Changes for Higher-Order Languages](https://arxiv.org/abs/1312.0658)
  通过静态 differentiation 产生 change propagation。它可作为将来的
  `Change[A]`/differential layer，但不替代 continuation cut。
- [Build Systems à la Carte](https://simon.peytonjones.org/assets/pdfs/build-systems-original.pdf)
  对 static 与 dynamic dependencies 的区分，支持以后分别提供可 AOT 分析的
  static graph 与一般动态 `live`，而不是强迫一种模型覆盖全部程序。
- [Differential Execution with Lexical Tracing](https://pl.ipd.kit.edu/papers/paper-lexicaltracing.pdf)
  说明 lexical identity 能在一些前置控制流变化下保持稳定。由此得到的 Cire
  设计推论是：lexical path 适合默认 identity，但 collection reorder 仍应
  要求 explicit key；后一句不是论文自身的 theorem。
- [Incr](https://www.usenix.org/conference/osdi26/presentation/xie-yizheng)
  从进程/壳层级展示隔离 effect tracing，以及 replayable/external effects 的
  分类处理；它是 runtime policy 的系统经验，不是 handler-instance law 的
  形式依据。
- [Tempo](https://arxiv.org/abs/2607.23550) 用 OCaml 5 deep handler 重建
  synchronous reactive scheduler。这是 2026-07-26 才提交的很新预印本，可
  作为“handler 足以承载某类 scheduler”的架构证据；“仍需另外证明 causality
  与 FSC”是本文的设计推论，不是该论文宣称的缺陷。
- [Reactive Programming with Reactive Variables](https://doi.org/10.1145/2892664.2892666)
  是对“直接加入 reactive variable”最贴近的对照：用 lexical scope 限定
  dependency，并禁止 reactive update 修改 global state，以保持 acyclic graph
  与一致性。这种限制恰好说明 sugar 背后仍需要严格的 compute boundary。
- [Glitch](https://www.microsoft.com/en-us/research/publication/glitch-a-live-programming-model/)
  允许 replay 中的 shared-state programming，但要求相关操作可撤销且可交换。
  这是 replay law 属于具体操作/handler 的有用先例，不意味着一般 State 安全。

另一个容易误判的标题是
[Algebraic Temporal Effects](https://doi.org/10.1145/3704914)。它研究的是
高阶递归程序的 temporal safety/liveness verification；其中 “algebraic”
修饰 temporal effect abstraction，并不等同于 runtime algebraic handler。
不过它与未来静态 temporal-protocol/`δ` layer 比标题初看更直接，适合用来
研究 phase protocol 和 liveness obligation。

### 8.7 未来 calculus 的语义工具

- [A Metalanguage for Guarded Iteration](https://arxiv.org/abs/1807.11256)
  在 effects 存在时统一讨论 guarded 与 unguarded iteration。
- [Guarded Interaction Trees](https://arxiv.org/abs/2307.08514) 为
  higher-order effects 提供已在 Coq/Iris 中形式化的 modular denotational
  domain 和 reasoning framework。

它们适合承载下一步小 calculus 的模型与 mechanization，但都没有直接给出
FRP dependency trace 或 incremental replacement correctness。

最重要的研究空白是：现有工作分别覆盖了这些组件，却没有一篇证明下面的完整
组合：

```text
generative named clock
× Fitch Next
× world-indexed resumption
× capture / quantity / Owner
× fixed-Epoch replacement trace
```

因此本文组合不能靠“把几篇论文拼起来”自动获得 soundness；它正是 Cire 需要
自行建立的 calculus 与证明义务。

## 9. 建议的设计分层

### 9.1 可以先冻结为方向

1. logical `Next`、Task completion、incremental Epoch 三分。
2. ordinary function/operation 默认 same-world。
3. resumption 保存 quantity、world transition、captures 和 Owner/generation。
4. handler 不自动穿过 temporal/replay boundary。
5. replay safety 属于具体 handler/runner instance。
6. Event、Live、Signal、Task 保持不同数据类型和时序语义。
7. Compute 无 Commit authority；外部发布必须通过 generation-gated Commit。

### 9.2 应先做 calculus/prototype 再冻结语法

1. `Next[frame, A]` 使用 singleton capability identity，还是 fresh phantom
   type。
2. `Shareable(A)` 是否足够，还是 temporal container 必须传播一般 quantity。
3. `checkpoint` 是新的 sealed Core contract，还是可信第一方库在 `ctl` 上
   建立的协议。
4. handler portability/commutation evidence 的表示。
5. operation transition 的表面拼写：

   ```text
   resumes next
   may_suspend
   ```

   其中目标 identity 来自 named call `frame.yield()`，不是匿名 `self` binder。

6. `feedback` combinator 与可选 `guarded[frame] def` 的关系。

### 9.3 现在不建议加入

1. 普通变量默认 reactive。
2. 任意 effectful `Later[frame] { A ! E }`。
3. `Live[A]` 与 `Signal[frame, A]` 的统一类型。
4. `await(task)` 与 `advance(next)` 的统一 elimination。
5. 普通 `live` 中隐式 async policy。
6. family 级 `Replayable(State)`。
7. 一个语义含糊的 `sample(event, value)`。
8. 把 liveness/fairness 从 guarded productivity 中自动推出。

## 10. 需要分别证明的性质

不要试图用一个“大一统 soundness”口号掩盖不同责任。至少应拆成：

```text
Temporal core
  advance 不早于对应 clock
  feedback causality
  被认证 fragment 的 productivity/space safety

Effect + temporal
  handler preservation
  world transition preservation
  latent effect 不丢失

Capture + control
  no capability escape
  multi-shot 不复制 nonduplicable authority
  suspension 后 handler/Owner 仍有效

Incremental protocol
  fixed-Epoch snapshot
  replacement generation safety
  from-scratch consistency

Commit protocol
  stale candidate cannot publish
  accepted revision commits at most once
  cleanup/finalization 不因 replacement 丢失
```

Scheduler fairness、Task 最终完成、浏览器最终产生 frame 都是额外 liveness
假设，不属于上述 safety theorem。

## 11. 当前推荐

如果只选一条下一步研究主线，建议不是先做 reactive variable，而是写一个很小
的 Core calculus，包含：

```text
generative clock identity
Next + delay + advance
world-indexed Resume
capture/quantity constraints
一个 sealed checkpoint/replacement protocol
```

然后用本文例子作为 accept/reject suite。

如果这个 Core 无法同时解释：

- handler placement；
- two clocks；
- multi-shot + affine capture；
- async suspension；
- fixed-Epoch Live；
- candidate Commit；

就不应先把对应表面语法加入语言。反过来，如果这些例子能在不引入一般
dependent type、全局 linear type 和万能 reactive runtime 的前提下得到清楚
判断，那么它才是对第一方增量计算真正有帮助的语言特性。
