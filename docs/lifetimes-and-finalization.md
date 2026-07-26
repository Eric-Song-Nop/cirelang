# Owner、Region、capture set 与结构化清理

## 1. 设计中心

**设计方向**

代数效应擅长描述“这段计算会请求什么”；生命周期系统还必须描述：

> 一个被保存的闭包、任务或续体已经携带了哪些具体能力，这些能力能活多久，以及不再继续时谁负责收尾。

这不是一个单独的 `captures {ρ}` 记号就能解决的问题。完整模型需要静态信息与运行时协议合作：

```text
静态：
  named capability + capture set + generative region

运行时：
  Owner tree + generation/revocation token + deterministic cleanup
```

## 2. 五个容易混淆的问题

| 机制 | 回答的问题 |
|---|---|
| Effect row | 调用它时还可能执行什么？ |
| Capture set | 保存它时，它已经随身携带了谁？ |
| Region/lifetime | 它最长允许被存放到哪里？ |
| Quantity/linearity | 某项能力可以使用几次？ |
| Generation | 它现在仍属于当前有效的那一代吗？ |

简写为：

```text
quantity   解决“几次”
lifetime   解决“多久”
generation 解决“还是不是当前那一个”
capture    解决“依赖谁”
```

Typestate 还可以描述 mounted、suspended、closing、disposed 等状态，但不应让所有普通值都背负完整状态机。

## 3. Owner、Region 与 capture set

### 3.1 Owner

Owner 是运行时生命周期负责人：

```text
Owner
├── child owners
├── tasks
├── saved resumptions
├── subscriptions
├── resources
└── cleanup actions
```

关闭 Owner 的含义不是“释放一个对象”，而是撤销整组能力、终止子任务、处置续体并执行全部清理。

### 3.2 Region

Region 是 Owner 或局部能力在类型系统中的生成式身份：

```text
owner |ρ| {
  let cell: Cell<ρ, Int>
  let task: Task<ρ, Result>
}
```

`ρ` 不是字符串、业务 key 或内存地址。它是不可伪造的类型身份。

### 3.3 Capture set

Capture set 是闭包、任务或续体所携带的“能力与生命周期摘要”：

```text
let read_later = fn() {
  cell.get()
}

read_later : (() -> Int) captures {ρ}
```

如果 `read_later` 逃出 `ρ`：

```text
owner |ρ| {
  let cell = Cell<ρ>(1)
  return fn() { cell.get() }
}
```

编译器应拒绝，因为返回的闭包可能比 `ρ` 活得更久。

普通不可变的 `Int`、`String` 或不可变 ADT 通常不需要出现在 capture set 中。需要记录的是：

- region-bound reference；
- mutable capability；
- 具体 effect handler instance；
- task/resource ownership；
- DOM/host capability；
- 另一个闭包传递进来的 capture。

Capture 应是传递的：

```text
f captures g
g captures State<ρ>

因此 f captures {ρ}
```

## 4. Effect row 与 capture set 不能互相替代

```text
Effect row：
  调用 closure 时，它还可能请求 Write<ρ>

Capture set：
  即使现在不调用，closure 已经持有属于 ρ 的引用或 capability
```

例如：

```text
handler :
  () -> Unit
  ! {HostWrite<dom>}
  captures {ρ}
```

它同时说明：

- 调用时会写宿主；
- 作为值保存时依赖 `ρ`；
- 因而不能被放进比 `ρ` 更长寿的全局 callback 表。

相反，响应式依赖集合不是 capture set：

```text
if read(flag) {
  read(a)
} else {
  read(b)
}
```

本轮动态依赖可能是 `{flag, a}`，下一轮可能是 `{flag, b}`。这是增量 handler 在运行时收集的依赖；capture set 只描述闭包或续体携带的能力来源。

## 5. 概念上的类型判断

语言内部至少需要表达三类判断：

```text
Γ ⊢ computation : A ! ε
```

计算运行时会请求 `ε` 中的 operation。

```text
Γ ⊢ value : T captures χ
```

值已经携带 capture set `χ`。

```text
Γ ⊢ χ valid-under ρ
```

这些捕获允许被保存在 `ρ` 管理的位置。

于是：

```text
store_in_ownerρ(value)
```

要求：

```text
captures(value) ⊆ capabilities-valid-under(ρ)
```

把续体标记为可重放还需要：

```text
ReplayableEffects(effects(k))
ReplayableCaptures(captures(k))
NoNonduplicableAuthority(k)
```

## 6. 动态 Owner 与 generation

### 6.1 为什么词法 region 不够

很多生命周期不是一个函数调用的花括号：

- task 在创建函数返回后继续存在；
- UI owner 跨越很多轮重新求值；
- keyed item 会被反复重新进入；
- 取消、超时或宿主卸载会让 Owner 提前死亡。

因此 Region 提供静态品牌，Owner 提供动态生命周期。

### 6.2 Generation 防止陈旧能力复活

仅比较业务 key 会产生 ABA 问题：

```text
SearchBox(key = 42, generation = 7)  被销毁
SearchBox(key = 42, generation = 8)  被重新创建
generation 7 的旧请求返回
```

旧请求不能因为 key 仍是 `42` 就修改新实例。运行时 callback 需要携带并验证：

```text
(owner_id, generation)
```

Region/capture checking 能阻止程序主动把短命值存到明显过长的位置；generation token 则处理：

- 浏览器已经排队的回调；
- 完成与取消的真实竞态；
- FFI 不遵守本语言类型规则；
- owner 销毁后同 key 重建；
- candidate 被抢占或废弃。

二者缺一不可。

### 6.3 弱引用与显式提升

如果计算确实要比 Owner 活得更久，应显式改变关系：

```text
spawn_global {
  if let live = weak(owner).upgrade() {
    live.update(result)
  }
}
```

这使“对象可能已经死亡”进入类型与控制流，而不是隐藏成 `isMounted` 约定。

另一种情况是把资源所有权提升给更长寿的 Owner：

```text
promote(resource, from = child, to = parent)
```

提升必须转交唯一清理责任，不能让两个 Owner 同时认为自己负责关闭同一资源。

## 7. 动态 keyed Owner

**设计方向**

UI 等动态容器需要用稳定名字重新找到逻辑 Owner：

```text
Name =
  ParentName
  × LexicalSite
  × ExplicitKey
```

注册表可以概念化为：

```text
Registry : Name -> exists ρ. Owner<ρ, Generation>
```

每次重算遇到同一 `Name` 时，框架重新打开存在类型包装的 Owner，而不是让业务代码伪造 `ρ`：

```text
enter existing owner as |ρ, live| {
  ...
}
```

动态列表中每一项都可以具有隐藏的独立 region：

```text
SomeRow =
  exists ρ.
  {
    owner: Owner<ρ>,
    state: State<ρ>,
    tasks: TaskGroup<ρ>
  }
```

容器不需要知道 `ρ` 的具体名字，但不能把两行内部的 capability 混在一起。

Stable name/key 的协调算法属于 UI 或通用 keyed container；语言最多提供 generative name、存在类型和稳定词法 site 等基础设施。

## 8. Owner 与 candidate generation 必须分开

一个长期 Owner 可以同时包含：

```text
Owner ρ
├── committed generation γ0
└── candidate generation γ1
```

不同对象的生命周期不同：

```text
State<ρ, T>               跨重算保留
Task<ρ, A>                通常跟随 Owner
DependencyEdge<ρ, γ>      只属于一次求值
ViewPlan<ρ, γ>            只属于一个 candidate
Resumption<ρ, γ, A, R>    只在 Owner 和 generation 都有效时恢复
```

因此 capture set 可能包含：

```text
captures {ρ}
```

表示可跨 Owner 的多轮求值存在；或者：

```text
captures {ρ, γ}
```

表示 candidate 被放弃后立即失效。

Candidate generation 是第一方增量/UI 协议，不是必须硬编码进语言的关键字。

## 9. One-shot 恢复权的处置

**设计方向**

`once` clause 对 `k` 有三类终结操作：

```text
resume k value
discontinue k error
finalize k
```

如果 `k` 被保存到未来，则必须：

```text
park/adopt k under owner
```

责任转移后：

- 当前 clause 不再拥有恢复权；
- Owner 关闭前必须恢复、终止或 finalize；
- Owner 关闭会自动 finalize 尚未处置的 `k`；
- 宿主 callback 的重复调用只能有一次成功 claim。

这比“把裸续体扔进全局表，等待 GC”具有明确得多的资源语义。

## 10. 跟随续体的结构化清理

### 10.1 为什么普通 `finally` 不够

有续体后，动态调用栈可能：

- 被捕获；
- 暂停很久；
- 在另一个宿主回调中恢复；
- 被注入取消或错误；
- 永远不恢复；
- 被 multi-shot 分叉；
- 被 handler 直接放弃。

因此“函数返回时执行 finally”不能完整描述资源何时结束。

### 10.2 需要的语义

```text
capture k
  → 当前相关 cleanup segment 随 k 移动

resume k
  → 重新进入这段动态作用域

discontinue/finalize k
  → 展开并执行 cleanup

adopt k under owner
  → owner 接管最终处置义务
```

如果一个 multi-shot 续体携带不可重放的 cleanup 或独占资源，捕获应被拒绝，或要求每个恢复分支建立独立资源。

### 10.3 两阶段关闭

**设计方向**

Owner 关闭采用两阶段：

```text
阶段一：封门
  标记整个待关闭子树为 closing/dead
  撤销 resume、callback 与新注册权限
  seal 并 detach child、resumption、cleanup

阶段二：打扫
  child-first 执行子 Owner 清理
  每个 Owner 内按 LIFO 执行 cleanup
  一个 cleanup 失败不能跳过其他 cleanup
  最后报告聚合后的错误
```

先撤销语言层控制能力，再调用可能抛错或同步重入的宿主 disposer。这样 cleanup 不能在一个正在死亡的 Owner 下重新注册永久存活的孩子。

### 10.4 GC 的角色

GC 可以回收不可达内存，但不能定义：

- 何时取消网络任务；
- 何时从 DOM 移除 listener；
- 被丢弃续体中的 `finally` 何时运行；
- 谁先失去提交权；
- cleanup 失败如何聚合。

这些都需要确定的语义。GC 只能作为最后的内存回收机制。

## 11. 结构化并发

**设计方向**

第一方并发协议建立在 Owner 和 `once` 上：

```text
nursery / task group
├── child task
├── child task
└── parked await resumptions
```

目标保证：

- 父任务结束前知道所有孩子的命运；
- Owner 关闭会撤销孩子继续影响外部世界的资格；
- 完成、失败和取消竞争同一 one-shot 恢复权；
- timeout/race 不会留下未处置的分支；
- handler context 只有在被声明为 portable、且 capture/lifetime 检查通过时才能跨宿主回调。

取消是独立 abortive control effect、普通错误还是分层协议，仍需原型决定。

## 12. Portable handler context

**开放问题**

宿主 callback 发生时，原来的动态调用栈已经不存在。不能默认保存并重装整个 handler stack。

需要区分：

```text
stack-only handler
portable handler under ρ
reentrant handler under ρ
```

概念 API 可能是：

```text
Context<effects, captures, ρ>
HostCallback<once-or-many, ρ, A>
```

只有显式允许 portable/reentrant、并且所有 capture 都在 `ρ` 下有效的 handler 才能进入 Context。

最终类型表示、嵌套 handler 的重装次序和跨 Wasm ABI 形式尚未决定。

## 13. 生命周期方案比较

讨论过的方案包括：

| 方案 | 优点 | 主要问题 |
|---|---|---|
| 纯运行时 Owner + generation | 简单，天然支持动态 key | 无法静态阻止逃逸或证明 replay safety |
| 显式 region/lifetime 参数 | 静态规则强 | 高阶 API 噪声大，动态 Owner 不是普通词法 scope |
| 推导式 capture set | 很适合闭包、handler 与续体 | 单独无法处理宿主竞态与动态撤销 |
| Indexed typestate/world | 最精确 | 容易造成 typestate explosion |
| 混合方案 | 每种机制只承担一个职责 | 类型系统和运行时接口需要共同设计 |

当前选择是混合方案：

```text
推导式 capture checking
+ generative region
+ 动态 Owner
+ generation/revocation token
+ structured finalization
+ 少量数量化恢复权
```

不采用到处显式书写 lifetime 的表面语言，也不把所有问题退化成运行时 `isAlive` 检查。

## 14. 期望的诊断体验

Capture 信息应主要出现在错误信息中，而不是普通代码中：

```text
cannot store this callback globally

it retains:
  State(result), owned by SearchBox
  DomRef(input), valid only while SearchBox is live

consider:
  spawning it under SearchBox.tasks
  capturing SearchBox weakly
  explicitly transferring ownership
```

类型系统的复杂度应由编译器吸收；用户首先看到的是“这个 callback 带走了一个短命对象”，而不是集合包含与 outlives 证明。

