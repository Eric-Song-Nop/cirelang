# 语言定位与特性总览

## 1. 定位

**已决定**

Cire 是通用编程语言，不是 UI DSL：

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及可推导的能力生命周期为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

整体分层为：

```text
通用语言核心
  数据、函数、模块、效应、续体、能力与生命周期
                    ↓
第一方通用协议与库
  Owner、结构化并发、增量计算、宿主互操作
                    ↓
第一方应用框架
  响应式 UI、DOM、Canvas、SSR、测试后端
```

响应式 UI 的作用是把语言的控制流、生命周期、增量性和宿主互操作同时推到极限，从而成为设计是否成立的旗舰验证，而不是反过来定义整门语言。

## 2. 常规语言基础

**已决定**

作为通用语言，至少需要：

- 代数数据类型与模式匹配；
- 参数多态与高阶函数；
- traits/interfaces 或同等级的抽象机制；
- 模块、包、信息隐藏和 package-qualified identity；
- 明确、稳定、确定的求值顺序；
- 默认不可变数据与明确的局部可变状态；
- 项目级构建、包管理和 LSP 模型；
- 可靠的 JavaScript、DOM、WASI 和 C 互操作；
- **以 WebAssembly 为首要编译目标**，而不只是提供一个 Wasm FFI。

内存管理采用 tracing GC、引用计数还是混合模型仍是开放问题。

## 3. 最具辨识度的语言能力

### 3.1 类型化、可组合的代数效应

**已决定**

函数类型记录未被处理的效应：

```text
fn load(url: Url) -> Data
  ! {Async, Network, Error<HttpError>}
```

需要支持：

- 用户声明 effect；
- 词法、可组合的 handler；
- effect row 与 effect polymorphism；
- forwarding、局部覆盖和 masking；
- handler 消除 effect 后，计算可以重新表现为纯计算。

### 3.2 具名、生成式的效应能力

**设计方向**

仅知道“使用了状态”不够，还应知道使用的是哪一个具体状态域或 handler：

```text
Read<app>
Write<app>

Read<test>
Write<test>
```

handler 实例产生不可伪造的生成式身份。闭包与续体捕获了哪些具体实例，应进入 capture checking。

这避免一种 effect row 自身无法阻止的“权限清洗”：代码不能只因为在内部安装并消除了一个 `Write` handler，就凭空获得另一个状态域的 `Write<other>` 权限。

### 3.3 四种恢复模式

**已决定**

表面语言使用：

```text
abort / once / fun / ctl
```

而不是把 `0..1`、`0..ω` 等数量区间暴露在普通 effect 声明中。

| 模式 | handler 对后续计算的权力 |
|---|---|
| `abort` | 不恢复后续计算。 |
| `once` | 获得一个可保存、但至多处置一次的恢复能力。 |
| `fun` | 不显式获得续体；返回操作结果后自动、恰好、尾部恢复一次。 |
| `ctl` | 获得一般控制能力，可以恢复零次、一次或多次。 |

`fun` 与 `ctl` 应保持 Koka 的核心含义。`abort` 与 `once` 是对一般 `ctl` 控制权的静态细化。

`val` 可以作为无参数 `fun` operation 的语法糖；是否正式保留该糖仍未冻结。

### 3.4 续体专用的数量检查

**已决定**

第一版不采用“所有普通变量默认 affine”的 Rust 式设计。数量系统首先约束 handler 获得的恢复能力：

```text
abort  → 没有 k，使用量 0
once   → k 的使用量至多为 1
fun    → 不暴露 k；恰好一次且必须尾恢复
ctl    → k 的使用量可以为 0..ω
```

它应检查：

- 顺序代码不能处置同一个 `once k` 两次；
- 两个互斥分支可以各自出现一次对 `k` 的处置；
- 捕获 `k` 的闭包会继承相应的调用次数限制；
- 可多次调用的闭包不能捕获 one-shot 恢复权；
- multi-shot 恢复不能复制不可重放或只能使用一次的能力。

这里被“仿射”的是恢复权在类型环境中的使用额度，不是把运行时栈对象包装成某种 Rust 风格 move-only 对象。

通用 affine 用户类型可在以后用于文件、socket、锁和宿主资源，但不是第一版增量 UI 的前提。

### 3.5 Capture-and-lifetime system

**设计方向**

语言最值得研究的中心不是重新实现 Koka，而是把代数效应与生命周期接起来：

```text
Effect row  ：计算运行时还会请求什么？
Capture set ：闭包或续体已经携带了什么具体能力？
Region      ：这些能力最长能被存放到哪里？
Owner       ：运行时谁负责它们的生死和清理？
Generation  ：这个动态权限现在还是不是当前有效的一代？
```

Capture set 应尽量由编译器推导。普通代码不应到处手写生命周期参数；高级 API 和诊断信息才需要显式展示。

### 3.6 续体感知的结构化清理

**设计方向**

清理不能只依赖普通函数返回或 GC。语言需要规定：

```text
捕获续体
  → 相应 cleanup segment 跟随续体

resume
  → 重新进入该动态清理作用域

discontinue / finalize
  → 展开并执行该分支的 cleanup

park / adopt 到 Owner
  → Owner 接管未来的处置责任
```

未被恢复、终止或转交的 `once` 恢复权在 clause 离开时自动 finalize。

### 3.7 结构化并发

**设计方向**

结构化并发主要是第一方标准协议，而不是大量特殊语法。它建立在 Owner、`once` 与结构化清理之上，提供：

- task tree / nursery；
- 父子任务生命周期；
- 结构化取消；
- timeout 与 race；
- one-shot 异步完成；
- owner-bound callback；
- 受控的 handler context 跨宿主重入。

### 3.8 其他候选基础设施

**开放问题**

以下能力可能显著改善第一方库，但尚未被确认为独立语言特性：

- block/effectful thunk 作为一等 computation；
- scoped/higher-order effect，或能安全替代它的 rank-2 computation 参数；
- lexical deep handler 作为默认、shallow handler 作为高级能力；
- typed hygienic macro；
- 宏可获得稳定但不泄漏源码路径的 lexical site token；
- generative name、存在类型和 typed namespace。

它们应由增量与 UI 原型的真实表达缺口来决定，不能只因为理论上漂亮就加入。

## 4. 第一方而非核心语法

### 4.1 增量计算

**已决定**

语言核心不认识 `Signal`。第一方库使用代数效应与续体实现：

```text
Source<A>
Live<A>
source / read / write / live / batch
```

最小运行时只需要 `Source + Trace + Queue + Epoch`。依赖 DAG、差量代数、demand tracking 与 MVCC 都是按需求增加的扩展，不是第一版公共 API。

### 4.2 响应式 UI

**已决定**

语言核心不会出现以下概念：

```text
Component
DOM
Signal
useState
Suspense
Virtual DOM
CSS
```

第一方 UI 框架组合增量库和 Owner 协议，负责：

- 组件与本地状态；
- stable/keyed identity；
- task/resource 生命周期；
- error boundary、Suspense 与 transition；
- DOM、Canvas、SSR 与测试后端；
- reconciliation、DOM range 与宿主事件。

## 5. 设计边界

语言、增量库和 UI 框架分别负责不同问题：

| 问题 | 负责层 |
|---|---|
| 如何捕获和恢复操作之后的程序 | 语言 |
| handler 最多能恢复几次 | 语言 |
| 续体携带了哪些短命能力 | 语言类型系统 |
| 被放弃的续体如何清理 | 语言 + Owner 协议 |
| 当前运行读了哪些 Source | 增量库 |
| 哪个失效 cut 应先恢复 | 增量调度算法 |
| 新旧列表项是否同一个对象 | UI/keyed 容器 |
| DOM 节点应移动、复用还是替换 | renderer |
| JS callback 是否来自已销毁实例 | Wasm/宿主运行时 |

一个重要判断标准是：

> 能用普通数据结构、函数和 handler 表达的算法应留在库中；只有库无法表达的控制语义，或必须由类型系统统一保证的性质，才进入语言。

## 6. 明确不采用的方向

**不采用**

- 不把整门语言定义成 UI-first DSL。
- 不把 Signal、Component、DOM 或事务快照做成语言关键字。
- 不把所有普通变量默认设计成 affine。
- 不照搬 Rust 的所有权表面语法来解释 one-shot 续体。
- 不在普通 operation 声明中暴露 `ctl[0..1]` 之类数量区间。
- 不把 `ctl` 简化成“multi-shot”；它表示一般控制权，multi-shot 只是其中一种用法。
- 不承诺 DOM mutation 是可回滚或真正原子的事务。
- 不假设 WebAssembly 会自动解决依赖追踪、失效传播或 UI 生命周期。
