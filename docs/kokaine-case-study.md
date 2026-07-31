# Kokaine 案例研究

> **Rationale:** 本文是 [`Cire-TR₀/2026-08-01`](spec-status.md) 的案例依据，
> 不独立定义语法或 Core rule。

## 1. 目的与范围

这份记录来自 2026-07-26 对独立 Kokaine 仓库的源码、架构文档、测试与提交历史的调研。数字是当时快照的近似值，后续仓库变化不会自动更新本页。

调研问题不是“如何移植 Kokaine”，而是：

> Kokaine 为了让裸代数效应与续体可靠驱动增量 UI，在哪些地方手工实现了本可由新语言统一提供的控制流、撤销和结构化关闭保证？

结论是：

> Kokaine 最大的成本不是 Signal，也不是在 `get` 处捕获续体，而是在库中手工补出了一套带所有权、撤销、结构化关闭和宿主重入的控制能力系统。

Kokaine 同时证明了两点：

1. continuation cut 可以有效驱动细粒度增量 UI；
2. 裸续体远远不足以承担真实 UI、异步和 DOM 的关闭与撤销协议。

## 2. 代码投入分布

排除预编译产物后的近似 authored lines：

| 部分 | 行数 | 观察 |
|---|---:|---|
| 测试 | 约 16.6k | 接近 runtime 的两倍，反映状态组合和失败路径很多 |
| Playground/CLI/tooling | 约 9.6k | Wasm 编译、LSP、预览、包发现与配置 |
| Runtime | 约 8.4k | 响应式、异步、资源、DOM 与 SSR |
| 示例 | 约 4.7k | |
| 文档 | 约 4.0k | |

Runtime 内部也没有一个孤立的“大坏文件”：

| Runtime 部分 | 行数 |
|---|---:|
| 响应式内核与 integration | 2,762 |
| Async、structured concurrency 与 Resource | 2,566 |
| DOM、HTML、keyed、SSR 与 window | 2,549 |
| registry、index 等公共设施 | 547 |

复杂度横穿三个子系统：

```text
continuation lifecycle
+ ownership / cancellation
+ transaction / host reentry
```

源码中当时约有：

- 43 处 `finally`；
- 172 处 `ref<global, ...>`；
- 65 处显式 `mask<...>`。

它们集中在 reactive scheduler/ownership internals、异步 runtime 与
`dom.kk` 等模块。

## 3. 续体不是一种统一对象

Kokaine 实际需要的控制行为至少包括：

| 用途 | 真实要求 |
|---|---|
| bootstrap | one-shot |
| tracked-read suffix | 可长期重复恢复；串行；pending/running/dead；失败可重试 |
| async await | one-shot；完成、失败与取消竞争 |
| DOM event | Owner 存活期内 many-shot；允许同步嵌套重入；之后可撤销 |
| resource finalizer | 底层处置恰好执行一次 |

Reactive continuation 本来就要跨多次更新恢复，因此不应该被错误地设计成 affine。相反，异步 task 在 `async/internal/one-shot-task.kk` 等位置手写了完整的一次性状态机。

### 语言可以内化

- `abort / once / fun / ctl` 恢复模式；
- `once` 恢复权的分支敏感数量检查；
- 保存到 Owner 后的处置责任转移；
- 被遗弃续体的 finalization；
- multi-shot 捕获不可重放能力的静态拒绝。

### 库仍需实现

- reactive cut 的 pending/running/retryable 调度协议；
- Source 订阅索引；
- 同一轮只恢复一次的 queue claim；
- replacement 失败后的产品策略。

`SerialRetryable` 是建立在 `ctl` 之上的增量 typestate，而不是所有 continuation 的语言固有语义。

## 4. 依赖关系与 Owner 关系不是同一棵树

Kokaine 分别维护：

- continuation gate；
- frame；
- Owner；
- child registry；
- finalizer registry。

相关逻辑主要位于 reactive model 与 ownership internals。

这揭示：

```text
dependency/cut relation  决定何时失效与从哪里重放
Owner relation           决定任务、资源与 callback 跟谁死亡
```

祖先 cut 被替换不一定表示 logical UI item 应被销毁；相反，一个 Owner 关闭时必须撤销其内部所有仍挂起的 cut。

### 语言/标准协议可以内化

- 具名 capability identity；
- 推导式 capture analysis；
- 动态 Owner tree；
- generation/revocation token；
- 两阶段关闭；
- child-first/LIFO cleanup；
- cleanup 错误聚合。

### 增量/UI 仍需实现

- cut 的父子关系；
- stable name/key 协调；
- candidate 与 committed generation 策略；
- DOM 与 logical Owner 的映射。

## 5. Candidate scope 与失败路径

Kokaine 多次出现这一模式：

```text
completed = false

finally {
  if !completed {
    rollback()
  }
} {
  build()
  completed = true
}
```

它出现在 continuation capture、resume transaction、provision 和 DOM keyed transaction 等路径，例如 `reactive/internal/capture.kk` 与 integration provision 模块。

原因是：

- 普通异常可捕获；
- abortive final control 可能根本不返回；
- candidate 可能部分建立 child、subscription 与 cleanup；
- replacement 失败时旧版本仍需保持有效。

### 可以内化为通用协议

```text
candidate next under current {
  build in next
  commit once
}
```

需要保证：

- normal return、error、cancel 与 abortive control 最终只能走一次 commit 或 abort；
- abort 自动关闭 candidate Owner；
- commit authority 只能消费一次；
- 原 reactive cut 是否继续 pending 由增量协议决定；
- source write 是否回滚仍由增量引擎决定。

这不是 ACID transaction，而是“未发布 generation 的结构化所有权事务”。它适合作为第一方协议，不一定需要语言关键字。

## 6. Effect row 会隐藏已经执行过的权限

Koka 的 effect row 描述哪些 effect 从函数中逃出。函数内部可以执行某个 operation，再通过局部 handler 把 effect 从最终 row 中消掉。

Kokaine 因而需要类似 `pure-plane-depth` 的全局动态检查，防止：

- derive 中隐藏写状态；
- 跨 reactive root 注册；
- handler 把 effect 类型“洗干净”后仍修改外部世界。

相关状态出现在 `reactive/internal/model.kk` 等位置。

### 语言可以改进

让 operation 依赖不可伪造的具名 authority：

```text
read_root  : cap Read
write_root : cap Write
own_root   : cap Own
reenter    : cap Reenter
host_write : cap HostWrite
```

`derive/live` 的 row 只包含 `{read_root}`。局部安装一个同名 handler 不会凭空
制造 `{write_root}`。

因此需要同时保留：

```text
effect row      尚未处理的行为
capture set     已经固定携带的具体 capability
authority       当前阶段实际授予的权限
```

## 7. 资源所有权转移

Kokaine 的 Resource 与 Fetch 需要手工维护：

- active/latest ownership；
- request generation；
- active flag；
- completion/cancel claim；
- release closure；
- AbortController 从 request 转交给 response，再转交给 body task。

代表路径包括 `resource.kk` 与 `async/web.kk`。

### 设计洞察

资源本身不必成为语言特殊对象；真正需要保证的是唯一清理责任的转移：

```text
Lease[request, AbortController]
  --promote-->
Lease[response, AbortController]
  --promote-->
Lease[body_task, AbortController]
```

如果以后引入通用 affine user type，`promote` 应消费旧 ownership capability。第一版也可以先由受信任标准库在 Owner 协议内部封装这一规则。

未转移成功的资源随当前 child Owner 自动关闭；宿主 completion/cancel 的真实竞争仍需要运行时 one-shot slot。

## 8. Handler context 与宿主重入

Kokaine 的宿主 callback 需要手工保存 root、gate 和 frame，再重装框架自己的 handler。任意外层 lexical handler 无法自然恢复，因此 event/async API 被迫收紧 effect row。

代表路径包括 integration reentry 模块与 `html.kk`。

### 语言可以提供

- stack-only 与 portable handler 的区分；
- capability capture checking；
- Owner-bound `Context`；
- `once`/`many` host callback modality；
- generation revocation；
- reentrant callback 的明确规则。

不能隐式保存整个动态 handler stack。Context 的最终类型与 ABI 仍是开放问题。

事件对象还可能需要 turn-local capability：

```text
EventSnapshot  可长期保存的普通数据
EventRef       只能在当前宿主回调中使用
EventControl   preventDefault / stopPropagation
```

这比把宿主原始事件暴露成无约束 `any` 更能阻止过期操作。

## 9. 结构化清理

Kokaine 大量 `finally` 不是偶然样板，而是在补以下语义：

- capture 后 cleanup 归谁；
- resume/finalize/park 时如何展开或转交；
- final control 如何触发 rollback；
- Owner close 时先撤销还是先调用宿主 disposer；
- 一个 finalizer 抛错后如何继续清理兄弟；
- cleanup 同步重入时如何禁止在 dying Owner 下重新注册。

这直接支持 [Named capability、Owner 与结构化清理](capabilities-and-finalization.md) 中的两阶段关闭与 continuation-aware finalization。

## 10. 不应内化进语言核心

Kokaine 的以下复杂度是领域算法或宿主防御，不能通过增加语言关键字消失：

### 增量运行时

- source-local continuation index；
- equality、version 与 invalidation；
- earliest-pending-ancestor frontier；
- targeted settlement；
- cycle detection；
- pure/effect plane 的具体调度顺序；
- retry 与 stabilization policy。

### UI/DOM backend

- keyed diff、key map 与 move 策略；
- marker range；
- focus、selection 与表单值保存；
- custom element；
- closed shadow root；
- cross-realm 检查；
- event delegation；
- DOM retirement retry policy。

### 工具链

- Wasm 编译和预览；
- package discovery；
- package-qualified module identity；
- manifest；
- 编辑器配置与 LSP。

新语言的第一方工具链能减少 Kokaine 约 9.6k 行 tooling 中的重复基础设施，但这不是效应类型系统本身的成果。

## 11. DOM 不可被语言包装成原子事务

Kokaine 对 DOM 的大量防御揭示：

- DOM mutation 后可能同步重入用户代码；
- custom element callback 可能抛错；
- 部分 host state 不可见或不可恢复；
- retirement 可能需要重试。

语言最多提供：

```text
validate
prepare
irrevocable
publish
retire
```

以及 capability、Owner 和 cleanup 保证。它不能承诺任意 DOM 操作完全回滚。

## 12. 对 Cire 设计的最终影响

Kokaine 案例支持把以下能力提升到语言或第一方标准协议：

1. `abort / once / fun / ctl`。
2. 针对恢复权的数量检查。
3. 具名 effect capability。
4. 推导式 capability capture 与 handler-binding escape checking。
5. 动态 Owner/generation 与 revocation。
6. 续体感知的结构化 finalization。
7. portable/reentrant handler context。
8. 自动 effect forwarding/weakening，减少框架手写 masking。
9. 统一的 Wasm/host callback ABI。

它同时支持把这些内容留在库/框架：

1. Source、Trace、Queue、Epoch。
2. Frontier scheduler 与 retry policy。
3. shared Derived DAG。
4. stable key 和 reconciliation。
5. DOM renderer 与宿主防御。
6. Suspense、transition 和 resource policy。

最简洁的总结是：

> 内化“续体能做几次、携带谁、归谁管、如何结束以及如何跨宿主回来”；不要内化 Signal、DOM 或具体增量调度算法。
