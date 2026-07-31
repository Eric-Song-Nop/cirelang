# 第一方增量计算库

> **First-party contract:** [`Cire-TR₀/2026-07-31`](spec-status.md)。本文定义
> `Source`/`Live` replacement 协议，不把它们变成语言关键字。

## 1. 定位

**已决定**

增量计算不是语言求值语义，也没有 `Signal` 关键字。它是建立在代数效应、受控续体、Owner 和结构化清理上的第一方库。

语言提供：

- 在 `read` operation 处取得后续计算；
- 保存和恢复续体；
- 检查恢复次数与捕获环境；
- 在续体被替换、取消或 Owner 关闭时清理；
- 可靠地跨 handler 和宿主边界保存必要上下文。

增量库仍负责：

- 本轮运行实际读取了哪些 Source；
- 哪些 cut 因输入变化而失效；
- 多个失效 cut 中应该恢复哪个；
- 旧依赖何时被新依赖替换；
- 更新如何合批并保持一致性。

核心边界是：

> 语言使增量算法可以安全、直接地操作续体；它不会替增量库决定哪个输入变了、哪段程序应该重算。

## 2. 最小公共 API

**设计方向**

第一版公共 API 应保持很小：

```text
Source[A]
Live[A]

source(initial : A) -> Source[A]

read(source : Source[A]) -> A
  ! {Observe}

write(source : Source[A], value : A)
  ! {Update}

live(computation : () -> A ! {Observe}) -> Live[A]

batch(action: () -> Unit ! {Update})
```

例子：

```text
let price = source(10)
let count = source(2)

let total = live {
  read(price) * read(count)
}
```

`Live` 属于当前 Owner：

```text
owner close
  → 停止后续重算
  → 删除依赖
  → finalize 保存的续体
```

第一版可以令：

```text
derived(f) = live(f)
```

无需立刻引入完全独立的 `Derived` 抽象。`Live` 如何读取当前结果、订阅输出或报告错误仍需补齐；上面列的是最小增量机制，不是已经冻结的完整产品 API。

第一方生态不应把所有时间相关对象都压成万能 `Observable[A]`：

```text
Source[A]        可写的当前输入
Live[A]          持续维护的当前派生结果
Event[E]         一批中的有序 occurrence，不是“当前值”
Task[Outcome[A, E]] 至多完成一次的异步计算
Resource[K,A,E]  由 Owner、key 与 policy 管理的异步状态
```

`Event` 不能像 state 一样随意 lazy pull，否则会漏掉 occurrence；`Task` 的 one-shot 完成也不同于会重复变化的 Source。具体 `Event/Task/Resource` API 属于更高层标准库。

## 3. 核心直觉：读取产生 continuation cut

考虑：

```text
let a = read(A)
let b = read(B)
a + b
```

每次 `read` 把直接风格程序切成：

```text
已经完成的前缀 + 可恢复的后缀
```

形成支配关系：

```text
root
└── read(A) → kA
    └── read(B) → kB
        └── return
```

- 只有 `B` 变化：恢复 `kB`，复用旧 `a`。
- 只有 `A` 变化：恢复 `kA`，旧 `kB` 成为失效后代，并在新执行中重建。
- `A`、`B` 同一批都变化：只恢复支配 `kB` 的 `kA`。

这修正了“每个 Source 拥有一个彼此独立 callback”的幼稚模型。真正的 continuation cut 具有父子关系；祖先失效会吸收后代通知。

## 4. 动态控制流

```text
live {
  let use_a = read(flag)

  if use_a {
    read(a)
  } else {
    read(b)
  }
}
```

第一次运行可能依赖：

```text
{flag, a}
```

下一次可能依赖：

```text
{flag, b}
```

类型系统无法预先决定分支，因此库必须记录本轮 trace。恢复 `flag` 的 cut 会：

1. 建立候选的新分支 trace；
2. 注册新分支实际读取的 Source；
3. 移除旧分支的 cut 与订阅；
4. finalize 旧分支持有的续体和资源。

动态依赖记录是问题本身，不是语言缺少某个类型特性。

## 5. 最小内部结构

**设计方向**

第一版内核可以压缩为四类结构：

```text
Source
  当前值
  指向订阅 cut 的唤醒索引

Trace
  一次 Live 执行产生的 continuation cut 树

Queue
  已去重、等待恢复的最早失效 cut

Epoch
  一批输入更新使用的一致版本
```

### 5.1 所有权安排

长期 Source 不应强引用并拥有短命续体。更安全的关系是：

```text
Trace
  └── 真正拥有 Cut 与 continuation

Source
  └── 保存 WeakWakeToken(owner, generation, cut_id)
```

Source 变化时：

1. 触发 weak wake token；
2. 验证 Owner、generation 与 cut 仍有效；
3. 从 Trace 取得续体；
4. 把 cut 加入 Queue。

这让全局 Source 不会意外保持已经关闭的 `Live` 或 UI Owner。

## 6. 概念执行流程

`Observe.read` 可以由标准库声明为允许一般控制的 operation：

```text
effect Observe {
  ctl[A] read(source : Source[A]) -> A
}
```

跟踪 handler 的概念流程是：

```text
read(source)
  → 捕获当前 continuation
  → 创建 Cut(parent, source, continuation)
  → 将 weak wake token 挂到 source
  → 把 Cut 记录进当前 Trace
  → 用 source 在当前 Epoch 中的值继续一次
```

写入：

```text
write(source, value)
  → 更新下一批的 source value
  → 将所有仍有效的订阅 cut 加入 Queue
```

刷新：

```text
flush(epoch)
  → 固定本轮可见输入
  → 从 Queue 中删除有待执行祖先的后代
  → 恢复剩余 frontier cuts
  → 建立 replacement Trace 子树
  → 处置被替换的旧子树
  → 本轮产生的新写入进入下一 Epoch
```

真实实现是否先构造候选子树、成功后再替换旧子树，取决于错误与暂停语义；这一点不能由上述伪代码偷偷决定。

## 7. Earliest invalidation frontier

一批写入可能同时让许多 cut 失效：

```text
dirtyCuts =
  所有读取过已变化 Source 的有效 cut
```

只保留没有 dirty 祖先的节点：

```text
frontier =
  { cut ∈ dirtyCuts | cut 没有 dirty ancestor }
```

这解决：

- 同一批更新中的重复重算；
- 祖先恢复后继续恢复陈旧后代；
- 已被替换 continuation 的重复执行；
- 动态分支中旧依赖继续收到通知。

Frontier scheduler 是最小增量算法不可删除的部分。

## 8. Snapshot 与 Epoch

**设计方向**

第一版无需完整 MVCC。可以采用单线程事件循环模型：

```text
batch 中的写入
  → 在批末形成一个 Epoch

同一 flush 的所有恢复
  → 只读取该 Epoch 的固定输入

flush 中发生的新写入
  → 排入下一 Epoch
```

这避免一段重算在执行中看到不断移动的世界，并为 glitch freedom 提供最小基础。

以后若需要并行求值、可抢占 candidate 或跨线程读写，再引入更强的 snapshot isolation。

## 9. 正确性标准

**已决定**

增量执行的核心正确性标准是 from-scratch consistency：

> 给定同一确定输入快照，增量执行的可观察结果应等价于从头执行同一程序。允许的差异只有缓存、性能，以及被明确声明为跨重算持久化的状态。

这要求：

- 动态依赖与本轮控制流一致；
- 被祖先替换的后代不能恢复；
- 一轮中所有读取来自一致 Epoch；
- 推测执行不能泄漏未声明的外部效果；
- Owner 和 generation 已失效的结果不能提交；
- 清理与资源声明不会因为增量路径而丢失。

## 10. Replay safety

恢复 continuation 会重新执行后缀，所以 `live` 不能接受任意外部效果：

```text
live {
  let amount = read(total)
  charge_credit_card(amount)
}
```

这会在每次变化时重复收费，必须拒绝或要求显式改写协议。

第一版可以用 effect row 与 capture checking 限制 `live`：

```text
live(computation: () -> A ! {Observe})
```

受管理的资源声明、staged plan 等可以通过专门 capability 被允许，但它们必须满足：

- candidate 被放弃时不会泄漏已发布外部效果；
- replacement 时旧资源可确定地 retired；
- multi-shot continuation 不复制一次性 authority。

“空 effect row”也不自动等于 replay-safe，因为闭包仍可能捕获具体可变或短命 capability。

### 10.1 `ctl` 不等于增量 replay

`ctl` 只说明当前 handler 拥有一般续体控制权。它可以用于同一逻辑时刻的搜索：

```text
resume k left
resume k right
```

增量 replay 则是更高层协议：

```text
跨越未来 Epoch 保存 cut
+ Source invalidation
+ Owner/generation validity
+ 固定 snapshot
+ replacement Trace
+ old child finalization
```

因此：

- 一个 `ctl` search handler 不自动是增量计算；
- 增量库可以使用 `ctl`，但还必须建立上述协议；
- “可多次恢复”不自动证明后缀适合在未来输入版本中重放；
- 当前没有决定增加名为 `replay` 的第五种 operation mode。

## 11. Continuation tree 与依赖 DAG

对一个直接风格 `Live`，continuation trace 可以同时表达：

```text
执行顺序
+ 动态控制流
+ cut 的支配关系
+ 局部失效范围
```

因此第一版不需要再建立一张内容完全重复的通用依赖 DAG。

但共享 `Derived` 会形成真正的跨计算 DAG：

```text
           Derived FullName
          /                \
    Header Live        Profile Live
```

最终分工是：

```text
Source subscription index
  找到哪些 cut 直接依赖变化输入

每个 Live 内的 continuation Trace
  决定从哪个控制位置恢复

可选的 Source/Derived DAG
  负责跨计算共享、按需与相等截断
```

因此“续体树完全取代所有依赖图”和“续体只适合 await”都过于绝对。

## 12. 重算粒度与显式边界

严格从左到右求值时：

```text
let name_view = text(read(name))
let chart_view = chart(read(chart_data))
combine(name_view, chart_view)
```

如果第一处读取的 continuation 包含整个后缀，那么 `name` 变化可能重新计算 chart。结果仍正确，但粒度较粗。

解决办法不是改变普通函数语义，而是让库或上层框架建立独立 effectful thunk/trace root：

```text
fork {
  child { text(read(name)) }
  child { chart(read(chart_data)) }
}
```

在 UI 中，动态属性、child、条件分支和 keyed item 可以自动形成这些边界。通用增量库也可以提供显式 `fork`、`live` 或 `stabilize`。

## 13. 可以推迟的功能

**已决定第一版不要求**

- 通用 `Source / Derived` 依赖 DAG；
- `Change[A]` 差量代数；
- demand tracking；
- cycle detection；
- MVCC 式 snapshot isolation；
- 跨线程或分布式调度；
- 自动 structural diff；
- stable key 与 keyed reconciliation；
- DOM commit；
- Suspense 与 transition。

其中：

- shared `Derived` 出现后再加入 DAG；
- equality cutoff、demand 与 `Change` 是性能/共享扩展；
- key 与 reconciliation 属于 UI 或其他 keyed container；
- DOM、Suspense 与 transition 属于 renderer/UI 协议。

## 14. 可选扩展

### 14.1 `Derived`

可共享的 `Derived[A]` 可以提供：

- 自己的内部 continuation trace；
- 多消费者共享；
- 输出相等时截断传播；
- lazy/demand-driven 求值；
- cycle 诊断。

### 14.2 `Change[A]`

差量协议可以是 opt-in：

```text
trait Change[A] {
  type Delta

  def zero() -> Delta
  def compose(left : Delta, right : Delta) -> Delta
  def apply(value : A, change : Delta) -> A
}
```

默认退化为：

```text
Delta = Replace[A]
```

它与 continuation cut 是互补的：

```text
continuation cut  决定从哪里重新执行
Change[A]         决定数据内部能否局部传播 patch
```

### 14.3 Keyed collection

集合是最值得第一方提供差量语义的领域：

```text
Insert(key, position, value)
Remove(key)
Move(key, position)
Update(key, delta)
```

但这是容器/UI 层扩展，不是最小增量内核。

## 15. 语言消除与无法消除的复杂度

| 语言可以统一提供 | 增量库仍必须实现 |
|---|---|
| continuation capture | 动态依赖记录 |
| once/multi-shot 使用检查 | Source 到 cut 的索引 |
| handler context 保存与恢复 | cut 父子关系 |
| Owner-bound cleanup/revocation | earliest invalidation frontier |
| replacement 的确定清理 | batch 与 Epoch |
| stale callback revocation 基础 | replacement Trace 建立 |
| multi-shot capture safety | equality、demand、DAG 等优化 |

这解释了为什么有了语言特性，第一方增量库仍然不是零代码：

> 控制流与结构化关闭样板可以被语言内化；依赖传播和失效调度仍是增量计算本身。

## 16. 待验证问题

- `Observe.read` 的 operation 声明是否必须是 `ctl`，还是需要更专门的 replay 模态？
- 一个已保存 cut 是重复恢复同一个 continuation，还是每次复制 checkpoint 并以 replacement 续体接班？
- 恢复失败时保留旧 trace、保留原 cut重试，还是让 `Live` 进入错误状态？
- 多个互不支配 frontier cut 是否允许并行恢复？
- 一个 `Live` 的输出如何暴露、订阅和比较？
- Source 写入的相等性由 Source、batch 还是 Derived 决定？
- `live` 如何表达允许的受管理 effect，而不把任意 IO 纳入 replay？
- 何时需要从单线程 Epoch 升级为 snapshot/MVCC？
