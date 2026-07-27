# Named capability、Owner 与结构化清理

## 1. 设计中心

**设计方向**

代数效应描述“这段计算会请求什么”；具名 capability 进一步指出请求会发往
哪个具体 handler。被保存的闭包、任务或续体如果保留了某个 capability，
编译器必须从该 term identity 继续追踪依赖，并检查它没有逃出有效的 handler
绑定范围。

源码只使用已经确定的 named row：

```moonbit
fn read_app(app : cap Read[Int]) -> Int ! {app} {
  app.read()
}
```

不增加另一套标注。编译器从 `app` 的绑定、函数体和返回值推导依赖，并把结果
保存在 HIR、接口摘要与诊断中。

完整模型由静态分析与运行时协议合作：

```text
静态：
  named capability identity
  + inferred capture dependency
  + handler-binding escape checking
  + resumption usage/replay checking

运行时：
  Owner tree
  + generation/revocation token
  + deterministic cleanup
```

## 2. 五个容易混淆的问题

| 机制 | 回答的问题 |
|---|---|
| Effect row | 调用它时还可能执行什么？ |
| Named capability identity | 操作会发往哪个具体 handler？ |
| Capture analysis | 被保存的值已经保留了哪些具体能力？ |
| Quantity/linearity | 某项能力可以使用几次？ |
| Generation | 它现在仍属于当前有效的那一代吗？ |
| Owner | 谁负责终止任务、处置续体并执行清理？ |

这些信息可以共享约束求解基础设施，但不能互相替代。

## 3. Named capability 与捕获

`with ... as app` 创建不可伪造的 capability identity：

```moonbit
with read_42 as app
in {
  let read_later = fn() {
    app.read()
  }

  use(read_later)
}
```

`read_later` 的函数类型包含 `! {app}`，编译器也记录它保留了 `app`。如果该值
被返回、写入更外层存储或包装进另一个逃逸对象，检查沿聚合、闭包和调用结果
继续传播，直到证明它仍在该 handler 绑定内使用，否则拒绝。

```moonbit
with read_42 as app
in {
  return fn() {
    app.read()
  }
}
```

诊断应直接指出被带走的 capability：

```text
cannot return this closure

it retains `app`, whose handler is installed by this `with`
the handler is no longer installed after the action returns
```

普通不可变的 `Int`、`String` 或不可变 ADT 不贡献 capability capture。需要
继续传播的内容包括：

- 具体 handler capability；
- mutable authority；
- Owner、task 或 resource authority；
- DOM/host capability；
- 另一个闭包已经保留的 capability。

Capture 是传递的：

```text
f retains g
g retains app

therefore f retains app
```

这项信息默认不需要新的源代码记号。公开接口需要保留它时，编译器把
capability identity 与约束写入序列化接口摘要；LSP 和诊断复用同一结果。

## 4. 匿名 effect 与具体 capability 不能互相替代

```text
匿名 effect：
  调用 closure 时，它需要某个满足 Reader[Int] 的 handler

具体 capability：
  调用 closure 时，它明确向 app 请求 read
```

例如：

```moonbit
fn use_reader(
  app : cap Read[Int],
  callback : () -> Unit ! {app, HostWrite},
) -> Unit ! {app, HostWrite} {
  callback()
}
```

这里 `{app}` 同时保留 effect family 的操作约束与具体 handler identity。
`Read[app]` 只允许作为诊断展开。

响应式依赖集合不是 capture：

```text
if read(flag) {
  read(a)
} else {
  read(b)
}
```

本轮动态依赖可能是 `{flag, a}`，下一轮可能是 `{flag, b}`。这是增量 handler
运行时收集的数据；capture analysis 描述的是闭包或续体已经保留的 authority。

## 5. 编译器内部判断

语言内部至少需要表达：

```text
Γ ⊢ computation : A ! ε
```

计算运行时会请求 `ε` 中的 operation。

```text
Γ ⊢ value : T with captures χ
```

值已经保留 capability 集合 `χ`。这是 HIR/类型检查器判断，不是表面语法。

```text
Γ ⊢ χ valid at storage boundary b
```

保存、返回、闭包转换、trait object 包装和 continuation capture 都会产生
storage boundary。检查器必须逐个 capability identity 验证该位置可用。

把续体标记为可重放还需要：

```text
ReplayableEffects(effects(k))
ReplayableCaptures(captures(k))
NoNonduplicableAuthority(k)
```

## 6. Owner 与 generation

### 6.1 Owner 的职责

Owner 是运行时结构化关闭的负责人：

```text
Owner
├── child owners
├── tasks
├── saved resumptions
├── subscriptions
├── resources
└── cleanup actions
```

关闭 Owner 的含义不是释放一个 GC 对象，而是撤销整组权限、终止子任务、
处置续体并执行全部清理。Owner 的运行时身份本身可以参与 capture analysis，
不需要出现在类型参数列表中。

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

静态 capture checking 阻止明显的 capability 逃逸；generation token 处理：

- 浏览器已经排队的回调；
- 完成与取消的真实竞态；
- FFI 不遵守本语言类型规则；
- Owner 关闭后同 key 重建；
- candidate 被抢占或废弃。

### 6.3 弱引用与显式转交

全局任务如需尝试访问某个 Owner，应显式使用弱引用：

```text
spawn_global {
  if let live = weak(owner).upgrade() {
    live.update(result)
  }
}
```

把资源从 child Owner 转交给 parent Owner 时，必须移动唯一清理责任：

```text
promote(resource, from = child, to = parent)
```

两个 Owner 不能同时认为自己负责关闭同一资源。

## 7. 动态 keyed Owner

UI 等动态容器需要用稳定名字重新找到逻辑 Owner：

```text
Name =
  ParentName
  × LexicalSite
  × ExplicitKey
```

注册表使用运行时 identity 和 generation：

```text
Registry : Name -> OwnerEntry

OwnerEntry {
  owner
  generation
  state
  tasks
}
```

容器重新遇到同一 `Name` 时，通过受控 API 重新进入对应 Owner。不同条目的
capability identity 不能混用。Stable name/key 的协调算法属于 UI 或通用
keyed container；语言只提供 named capability、可靠的 capture analysis 和
必要的稳定 lexical site。

## 8. Owner 与 candidate generation

一个长期 Owner 可以同时包含：

```text
Owner
├── committed generation
└── candidate generation
```

不同对象的有效条件不同：

```text
State             跨重算保留
Task              通常跟随 Owner
DependencyEdge    只属于一次求值
ViewPlan          只属于一个 candidate
Resumption        只在 Owner 和 generation 都有效时恢复
```

Candidate generation 是第一方增量/UI 协议，不是语言关键字。提交、回调和
恢复操作在运行时验证 generation；编译器负责 capability 和恢复权没有通过
普通闭包或抽象包装绕过协议。

## 9. One-shot 恢复权的处置

`once` clause 对 `k` 有三类终结操作：

```moonbit
k.resume(value)
k.discontinue(error)
k.finalize()
```

如果 `k` 被保存到未来，必须转交给 Owner：

```moonbit
owner.adopt(k)
```

责任转移后：

- 当前 clause 不再拥有恢复权；
- Owner 关闭前必须恢复、终止或 finalize；
- Owner 关闭会自动 finalize 尚未处置的 `k`；
- 宿主 callback 的重复调用只能有一次成功 claim。

这比把裸续体放进全局表并等待 GC 具有明确得多的资源语义。

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

如果一个 multi-shot 续体携带不可重放的 cleanup 或独占资源，捕获应被拒绝，
或要求每个恢复分支建立独立资源。

### 10.3 两阶段关闭

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

先撤销语言层控制能力，再调用可能抛错或同步重入的宿主 disposer。这样 cleanup
不能在一个正在关闭的 Owner 下注册新的长期任务。

### 10.4 GC 的角色

GC 可以回收不可达内存，但不能定义：

- 何时取消网络任务；
- 何时从 DOM 移除 listener；
- 被丢弃续体中的 `finally` 何时运行；
- 谁先失去提交权；
- cleanup 失败如何聚合。

这些都需要确定的语义。GC 只负责内存回收。

## 11. 结构化并发

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
- handler context 只有在声明为 portable 且 capture checking 通过时才能跨
  宿主回调。

取消是独立 abortive control effect、普通错误还是分层协议，仍需原型决定。

## 12. Portable handler context

宿主 callback 发生时，原来的动态调用栈已经不存在。不能默认保存并重装整个
handler stack。

需要区分：

```text
stack-only handler
portable handler
reentrant handler
```

只有显式允许 portable/reentrant，并且 capture analysis 接受其全部
capability 的 handler 才能进入 Context。最终类型表示、嵌套 handler 的重装
次序和跨 Wasm ABI 形式尚未决定。

## 13. 期望的诊断体验

Capture 信息主要出现在错误信息和高级工具视图中，而不是普通代码中：

```text
cannot store this callback globally

it retains:
  capability `app`, installed by `with read_42 as app`
  Owner `SearchBox`, which controls its tasks and cleanup

consider:
  spawning it under SearchBox.tasks
  capturing SearchBox weakly
  explicitly transferring ownership
```

用户首先看到具体被带走的 capability、对应 binder 和可采取的修复；LSP 可以
按需展开内部约束，但源码不增加额外标注。
