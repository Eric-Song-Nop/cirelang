# 开放问题与原型验证计划

> **Open-question registry:** [`Cire-TR₀/2026-07-31`](spec-status.md)。只有本文
> 明确列为开放的项目才允许多候选；仓库当前没有实现。

## 1. 已经可以依赖的结论

下游设计目前可以把以下内容当作工作约束：

1. Cire 是通用、严格求值、面向 WebAssembly 的函数式语言。
2. 代数效应、effect row、effect polymorphism 与可组合 handler 属于语言核心。
3. 表面恢复模式是 `abort / once / fun / ctl`。
4. `fun` 与 `ctl` 保持 Koka 的核心语义。
5. `once` 表示显式、至多处置一次的恢复权；跨 callback 只能经 sealed
   completion source 转交，不能保存 raw `Resume`。
6. 第一版数量检查聚焦恢复权，不让所有普通变量默认 affine。
7. 具名 capability、capture analysis、Owner 与 generation 各有独立职责。
8. Capture 信息由编译器推导，保存在 artifact 并用于诊断。
9. 被保存或放弃的 continuation 必须有明确 finalization 语义。
10. 增量计算是第一方库，最小核心为 `Source + Trace + Queue + Epoch`。
11. 响应式 UI 是第一方框架；stable key、reconciliation 与 DOM renderer 不属于语言核心。
12. Wasm 是编译目标，不会替代增量调度算法。
13. 表面语法以 MoonBit 为基线。普通泛型写 `[...]`；effect family、
    effect constructor 与 row 使用独立的 `![...]`。单 effect 写 `![F]`
    或 `![F : Reader[A]]`，整行写 `![..E]`。双列表已接受为继续细化的
    设计基线；仓库当前没有 parser。
14. Named capability identity 由普通 term binder 或 `as app` 绑定，在源
    row 中写 `{app}`；`Read[app]` 只允许作为诊断展开。Capability type
    当前工作写法为 `app : cap F`，`cap` 关键词仍可调整。
15. `once`/`ctl` clause 使用 `as k`；`TR₀` 处置写成
    `k.resume(value)`、`k.finalize()` 或 sealed
    `source.park(k, under = owner)`。`discontinue` 不在本 profile。
16. `with` 把 scoped computation transformer 应用到 computation thunk；
    effect handler 是主要用途，但普通同形高阶 wrapper 也可使用。
17. Effect visibility 镜像 trait：`effect`、`pub effect`、`pub(open) effect`。
18. Cire 不做宏系统；UI DSL 使用普通函数、labelled argument 与 Kotlin/Koka 风格 trailing lambda。
19. Capability capture 与 Owner 责任转移必须有编译器静态分析，不能退化成
    未经检查的库约定。
20. Capture safety 要么以一致的核心规则整体实现，要么整体延后，不能只补少数特例后默认其余程序安全。
21. Parser 使用手写 PEG，不维护 EBNF 或依赖 parser generator。
22. Compiler interface 从 parser 阶段起以可序列化 diagnostic/artifact、immutable snapshot、增量 query 与 LSP 直接复用为约束。
23. Effect abstraction 分为 ability、具体 effect family 与 named
    capability identity；匿名 `{F}` 与具名 `{app}` 共享 ability evidence。
24. Effect row constraint 使用独立 row predicate/solver，不把整行 effect
    伪装成拥有 operation 的普通 trait。

## 2. 表面语法

**已决定**

- operation declaration、effect row、handler、`as k` 与 continuation disposition 采用 [表面语法设计说明](surface-syntax.md)中的写法；
- Named capability 的源 row 写 `{app}`；`Read[app]` 仅用于诊断；
- `with h in body` 降为 `h(fn() { body })`；
- 连续 `with h1 with h2 in body` 是有序 chain，第一项最外层，只在末尾写
  一个 `in`；
- 每个 operand 先求值得到 transformer value，`with` 不把 action 偷偷追加
  成 operand 中某个 call 的普通最后参数；right-fold 保持内层 operand 的
  latent evaluation；
- `with h as app in body` 降为 `h(fn(app) { body })`，其中 `app` 是生成式
  identity，并对后续 entry 和 body 可见；
- `with h1 in with h2 in body` 仍可作为两个显式嵌套的单项 chain；
- 整个构造是 expression，`in` 后接受任意 expression，不强制 block；
- `callee(args) { body }` 与 `callee { value => body }` 是最后一个 lambda argument 的糖；
- newline/comment 不打断 trailing lambda 附着；显式 `;` 才把 call 与后续
  block 分开；
- `in` 分隔 operand chain 与 computation，因而 `with` operand 可以正常包含
  trailing lambda；只有顶层 operand 自身是 `with` expression 时需要括号；
- `with` 不复用于 record update、constraint、普通 receiver scope 或普通
  variable binding；`as` 只建立 fresh named capability；
- effect visibility 镜像 trait visibility；
- 不设计宏系统；
- grammar 采用 PEG，并由项目手写 parser。

**仍然开放**

- sealed completion source/port 的标准库命名与 ergonomics（Core
  `Transfers(ParkContract)` 已冻结）；
- `val` 是否正式保留为无参数 `fun`；
- one-call/many-call closure 是否需要显式 surface marker；
- Owner 的第一方 API 如何提供 sealed source/port；
- same-effect operation 的显式 forwarding 拼写；
- stable lexical site 由编译器 intrinsic 还是模块级声明身份产生；
- `Error[E]` 的 `raise`、`try/catch` 专用糖；
- shallow handler 是否提供；
- local let-polymorphism 在 `ctl`、mutation 和 capture 下的
  generalization/value-restriction 规则；
- `ability`、`cap`、associated `effect`/`effects` 是否为最终关键词；
- 用户是否需要普通显式 higher-rank type；
- higher-kinded effect constructor binder `![F[_] : Reader[_]]` 的精确
  作用域、generalization 与诊断；
- `|` union 与 extension 产生的 `Lacks` 已冻结；显式 `Has`/`All`/`Only`
  predicate 的完整 solver/diagnostic 是否进入首版；
- 多 ability 提供同名 operation 时的限定调用；
- 独立 ability `impl` 是否进入第一阶段，以及 coherence/orphan 规则；
- 显式 generic call 中 effect/row argument 的最终写法；当前工作形式为
  `f[Int]![State[Int], {Network, app}](...)`。

语法糖不能先于核心类型规则获得独立语义。CST 保留糖，Surface HIR 到 Kernel HIR 的 elaboration 必须可检查、可序列化并保留 source origin。

### 2.1 Parser 推进前后还要冻结的普通语法

以下问题不改变 effect 核心，但会直接影响 lexer、错误恢复、formatter 与
LSP。首个 parser slice 不应偷偷替整个语言作出不可逆决定：

1. **标识符**：第一版 scanner 可以只接受 ASCII lower/upper identifier，
   但最终要决定 Unicode XID、关键字转义和 package name 的规则。暂时遇到
   非 ASCII identifier 应产生可恢复 diagnostic，不能静默按 ASCII 截断。
2. **换行与分隔符**：newline 先作为 lossless trivia 和 recovery boundary，
   不承担自动插入分号的语义。仍需冻结 block 中 declaration、statement、
   final expression 以及连续 expression 的分隔规则。
3. **labelled argument**：需要在 `key=value`、label punning、可选参数和
   默认值之间给出完整且无歧义的 call/parameter grammar。
4. **括号与 tuple**：`()`、`(x)`、`(x,)`、多元素 tuple，以及 function type
   参数 tuple 的关系需要一次性定清。
5. **operator**：先使用固定 precedence/associativity 表；是否允许
   user-defined operator、pipe operator 与 assignment expression 仍开放。
   首版不引入会改变 parser grammar 的 operator declaration。
6. **literal**：numeric suffix、raw/multiline string、interpolation、byte
   literal 与 escape validation 需要独立 lexical spec。
7. **pattern**：constructor、record、array、or-pattern、guard、typed pattern
   和 rest pattern 的优先级尚未形成完整 PEG。
8. **item/module syntax**：import、package alias、attribute/doc comment、
   generic constraint 与 `where` 风格约束仍需和 MoonBit 基线逐项对齐。
9. **handler body**：`return` clause 是否必须最后、clause 间如何分隔，
   parser 可以先宽松保留 CST，再由 syntax validation 给定向错误。

这些项目进入实现时应分别有 valid、malformed、lossless、UTF-16 range 和
recovery fixture；“MoonBit-like”不能替代 Cire 自己的可测试规范。

## 3. 恢复模式与类型系统

### 3.1 Operation 最大模式与实际 handler

operation 声明给出最大控制能力，handler 可以采用更弱 clause。需要决定 multi-shot capture safety 按什么检查：

- 按 operation 声明的最大模式；
- 按词法上已知 handler 的实际模式；
- 通过 effect polymorphism 携带 handler mode constraint；
- 默认保守，允许局部 specialization。

这直接影响一个声明为 `ctl`、但当前由 `fun` handler 处理的 operation 是否能出现在捕获 affine capability 的后缀之前。

**实现门槛**

在这一问题与 capture/replay 规则形成一致 Core 前，不启用“部分安全”的
capture checker。编译器可以暂时不支持相关程序，但不能接受程序后只对
`once` 或 UI API 做 ad-hoc 检查。

### 3.2 `fun` 的尾位置

需要形式化：

- tail position 相对于 clause 的哪一层；
- `try/finally`、handler nesting 与 tail resume 如何交互；
- effectful clause body 能否被优化成普通调用；
- `fun` operation 的 handler 是否只允许 `fun` clause。

### 3.3 `once` 的闭包传播

需要定义：

- 一个 closure 捕获 `once k` 后，其调用数量如何推导；
- closure 被放入 ADT、trait object 或多态容器时如何保留数量；
- 两个 callback 如何通过 generation-bound completion port 的 CAS竞争；
- callback never called 时谁 finalize；
- standard API 的 source/port 命名与 host adapter ergonomics。Core park 是
  checker理解的 terminal ownership transfer，不再开放。

### 3.4 Multi-shot 与可变状态

需要选择：

- shared store；
- captured store snapshot；
- generation-local mutation；
- 禁止捕获 mutation authority；
- 显式 replayable cell。

正确选择应同时满足可解释性、实现成本和增量 UI 需求。

### 3.5 通用 affine user type

第一版不需要全局 affine 变量，但以后可能需要：

```text
File
Socket
Lock
AbortController
GPUBuffer
CommitAuthority
OwnershipLease
```

需要判断续体专用 quantity context 是否能自然推广，还是应保持两个层次：

```text
核心：resumption usage
扩展：general resource ownership
```

## 4. Capability capture 与动态 Owner

### 4.1 Capture inference

需要形式化：

- 哪些值贡献 capture；
- immutable aggregate 如何传播 capability；
- trait object/existential package 如何隐藏 capture；
- effect instance 本身的 capture；
- transitive closure 与 capture polymorphism；
- module abstraction 如何保留或隐藏具体 capability identity；
- 错误诊断如何从抽象集合还原成人能理解的资源来源。

### 4.2 Handler binding 与动态 Owner

需要证明：

- 下一轮执行如何安全重新打开同一 Owner；
- handler action 的 capability binder 如何约束 closure escape；
- parent/child Owner 的关闭顺序；
- Owner promotion、weak reference 与 detach；
- Owner close 期间禁止新注册的类型/运行时保证。

编译器必须为 named capability 建立稳定 identity、推导 capture 并检查
storage boundary；库负责 Owner 的运行时协议。

### 4.3 Generation subtyping

Old committed 与 candidate 可能并存：

```text
Owner
├── committed γ0
└── candidate γ1
```

需要决定：

- candidate-only authority 如何防止逃到 persistent state；
- transition 中旧、新 generation 同时可读时的 capability；
- generation token 是否能被用户观察；
- ABA 防御如何映射到 host handle。

## 5. Finalization 与并发

### 5.1 Continuation-aware cleanup

需要规定：

- capture 时哪些 cleanup segment 随 continuation 移动；
- deep/shallow handler 的差异；
- multi-shot 分叉如何复制动态 extent；
- `resume` 正常返回后何时运行退出动作；
- 若未来引入 `discontinue`，其 typed payload/world/cleanup contract 与普通
  Error effect 的关系；
- `finalize` 是否可以 suspend；
- finalizer 抛错或执行 final control 时如何继续清理；
- trap 后有哪些保证仍成立。

### 5.2 Owner 两阶段关闭

需要原型验证：

- seal/detach 的数据结构；
- child-first 与 LIFO 的精确定义；
- language cleanup 与 untrusted host disposer 的先后；
- cleanup error aggregation 类型；
- reentrant close；
- 并发 close 的幂等性；
- close 与 completion 竞争时的唯一线性化点。

### 5.3 取消

候选方案：

- 独立 abortive control effect；
- typed `Cancelled` error；
- Owner revocation + finalize/CAS；
- shield/mask 的受控组合。

目标是避免普通 `catch _` 意外吞掉结构化取消，同时不过度特殊化语言。

### 5.4 Portable handler context

需要决定：

- 哪类 handler 可 portable；
- 哪类 handler 可 reentrant；
- Context 中保存 instance、state 与 cleanup 的边界；
- 恢复时 handler 嵌套顺序；
- stack-only capability 的诊断；
- Context 如何跨 Wasm ABI。

## 6. 增量内核

Modal time、world-indexed resumption、async 与 replay 的最新压力测试见
[Temporal modality、代数效应与增量计算：语法实验和反例审查](temporal-reactivity-design-experiment.md)。
该文档把 logical `Next`、Task completion 与 incremental Epoch 分开，并把
sealed checkpoint 作为演算候选；它仍是研究草案，不改变本节的开放状态。
逐规则的 PEG、typing judgment 与 replacement machine 见
[Cire-TR₀ Typst 形式化](temporal-reactivity-formalization.typ)。

### 6.1 `Observe.read` 的控制模式

候选包括：

- 普通 `ctl`，由 `live` 额外要求 replay-safe；
- 专门的 replay modality；
- `ctl` checkpoint + 每轮 replacement；
- 复制 continuation snapshot。

当前倾向先用 `ctl` 与 capture/effect 检查验证表达能力，不急于增加第五种 surface keyword。

### 6.2 Cut 的运行时语义

需要验证：

- 同一 continuation 被多次恢复，还是每次产生接班 cut；
- replacement 前是否保留原 checkpoint；
- 恢复失败后是否可重试；
- old child trace 何时 finalize；
- Source 只持 weak wake token 是否足够；
- cut id 与 generation 如何防止旧 queue item；
- sibling frontier 是否可以并行。

### 6.3 `Live` 产品语义

最小 API 尚缺：

- 读取当前输出；
- 订阅输出；
- 初始求值失败；
- 后续求值失败；
- pending/suspended 状态；
- equality policy；
- 手动 close 与 Owner close；
- 是否保留 last-good result。

这些应在核心机制原型稳定后设计，避免一开始引入庞大状态枚举。

### 6.4 Epoch

第一版倾向单线程 batch epoch。需要测试：

- flush 中 write 推迟到下一 Epoch；
- nested batch；
- runaway feedback；
- cycle 诊断；
- 多个 root 的协调；
- 从何时开始需要 snapshot isolation 或 MVCC。

普通即时反馈环应被诊断，而不是靠不断 flush 碰运气。合法的时间反馈可以由显式 `delay`、`fold` 或 `feedback` 协议表达；若以后需要严格 FRP，再评估 `Later[A]` 一类时间模态，而不是让它成为第一版前提。

### 6.5 扩展触发条件

只有出现真实需求时才加入：

```text
shared Derived        → dependency DAG
unused Derived        → demand tracking
same output cutoff    → equality policy
large structures      → Change/Delta
parallel evaluation   → stronger snapshot isolation
retained views        → activation states
```

## 7. UI 与 DOM

### 7.1 Stable name

需要验证：

- lexical site 在 trailing lambda、泛型与增量编译后是否稳定；
- module refactor 是否有状态迁移语义；
- 动态 key 的类型约束；
- 重复 key 的诊断；
- 存在类型 Owner registry 的实现；
- SSR/hydration 中 name 如何一致。

### 7.2 Candidate policy

需要决定：

- 最小 UI 是否先同步重算并直接 replacement；
- 何时保留 last committed generation；
- Suspend/Error 边界如何选择 fallback；
- transition 中旧、新 event handler 谁可活动；
- candidate 再次失效时如何抢占；
- 资源能否跨 candidate 复用。

### 7.3 DOM commit

需要为下列宿主行为建立失败模型：

- custom element 同步重入；
- listener/property setter 抛错；
- focus/selection/form state 保存；
- closed shadow root；
- Portal；
- 跨 realm node；
- retirement 重试；
- teardown 中宿主代码再次调用 Wasm。

不能把这些问题隐藏在“原子 commit”一词后面。

### 7.4 Event validity

需要评估：

```text
EventSnapshot
EventRef
EventControl
```

需要验证 callback binder、capture checking 与运行时 revocation 是否足以阻止
在 `await` 之后调用只在同步 event turn 有效的 API。

## 8. WebAssembly 与 ABI

需要通过 ABI 原型回答：

- core Wasm、Wasm GC、component model 的支持顺序；
- continuation lowering；
- host handle table；
- callback modality metadata；
- exception/cancel/trap 映射；
- instance teardown；
- reentrant call；
- 多线程与原子 one-shot slot；
- C callback adapter；
- package/module 与 import/export identity。

Wasm 设计不能反过来迫使源语言暴露 JS Promise 或裸 DOM 对象。

## 9. 建议的原型顺序

### 原型 0：可序列化 compiler shell 与 PEG parser

先实现：

```text
SourceSnapshot + TextEdit + LineIndex
versioned JSON artifact
structured Diagnostic + Fix
TraceSink / CompilerEvent
lossless lexer + CST
handwritten PEG + recovery
Surface HIR → Kernel HIR
```

成功标准：

- 同一输入得到 deterministic、可 snapshot 的 token/CST/HIR/diagnostic JSON；
- parser 对错误输入返回 tree 与 diagnostics，不 fail-fast；
- `with`、trailing lambda、named capability 与 `as k` 有带 source origin 的展开；
- incremental parse API 从第一版存在，哪怕初版内部仍 full reparse；
- incremental 与 from-scratch 结果可 differential test；
- LSP 直接复用 SourceDb、CST 与 diagnostic model。

### 原型 1：最小 effect calculus

实现并测试：

```text
effect row
named instance
abort / once / fun / ctl
branch-sensitive resumption usage
```

成功标准：

- `fun` 可优化为普通调用；
- `once` 双恢复静态失败；
- `ctl` 可实现 search；
- handler mode weakening 有清晰规则。

### 原型 2：Capability capture

用非 UI 例子验证：

```text
closure escape
handler instance escape
once continuation parked under Owner
multi-shot captures non-replayable capability
```

成功标准：

- 诊断能指出实际捕获来源；
- 聚合、闭包和模块边界不会丢失 capability identity；
- Owner 责任转移可被静态检查。

### 原型 3：Finalization 与 structured task

覆盖：

```text
normal return
abort
explicit Error/Cancel outcome
unresumed once
Owner close
cleanup throws
host callback races cancel
```

成功标准：

- 每条路径恰当地处置 continuation；
- 没有 sibling cleanup 被跳过；
- reentrant host disposer 无法复活 dying Owner。

### 原型 4：最小增量内核

只实现：

```text
Source + Trace + Queue + Epoch
```

测试：

- 单个 read；
- 嵌套 A/B read；
- 同 batch 的祖先/后代同时失效；
- 动态分支；
- Owner close；
- 恢复失败；
- 随机更新序列与 from-scratch 对照。

成功标准：

- 公共 API 保持小；
- 不依赖通用 DAG；
- property test 证明 from-scratch consistency。

### 原型 5：Wasm host callback

实现：

- once completion；
- many event callback；
- generation revocation；
- instance teardown；
- portable context 的最小子集。

成功标准：

- 重复 completion 不会重复恢复；
- 旧 callback 不进入已销毁实例；
- Owner close 能处置 parked continuation。

### 原型 6：最小 UI backend

只做：

- logical Owner；
- stable keyed child；
- text/node plan；
- 同步 DOM commit；
- event action；
- 一种 async resource。

随后再评估 candidate generation、Suspense、transition、Derived DAG 与 Change algebra。

## 10. 评估原则

每个候选特性都应通过三个问题：

1. **表达性**：普通库没有它是否无法安全表达需求？
2. **静态价值**：它是否消除了一整类真实错误，而不只是改名？
3. **用户成本**：能否主要推导，并提供说人话的诊断？

如果一个概念只是某个 runtime 的内部状态机，就不应成为语言关键字。如果一个性质只有语言或类型系统才能统一保证，就应优先做最小、通用的语言机制。
