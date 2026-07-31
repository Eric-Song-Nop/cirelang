# 11　清理、Owner 与结构化并发

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

## 1. GC 解决不了“什么时候结束”

Cire 是 GC 语言。对象不可达后，GC 可以回收内存，但它不能决定：

- 什么时候取消网络请求；
- 什么时候移除 DOM listener；
- 被放弃的 continuation 何时运行退出动作；
- 浏览器队列里的旧 callback 是否还允许修改状态；
- 一个 cleanup 失败后，其他 cleanup 是否继续。

这些是控制流和权限问题，不是“内存还可不可达”的问题。

## 2. `defer`

普通结构化退出使用：

```cire
def read_file(path : Path) -> Bytes ! {FileSystem} {
  let file = FileSystem::open(path)
  defer file.close()

  file.read_all()
}
```

`defer cleanup()` 注册退出动作。一个 scope 中有多个 defer 时，按 LIFO 执行：

```cire
let outer = open_outer()
defer outer.close()

let inner = open_inner()
defer inner.close()

// 先 close inner，再 close outer
```

它不是把普通函数调用简单移动到 block 末尾。遇到 abort、取消、continuation
capture 或 finalization 时，compiler/runtime 必须仍然知道 cleanup 属于哪段
动态控制范围。

## 3. Continuation-aware cleanup

如果执行在 `await` 处暂停：

```cire
let connection = connect()
defer connection.close()

let response = Async::await(request(connection))
use(response)
```

`connection.close()` 不能在暂停瞬间运行，因为恢复后仍要使用 connection；
也不能永远等 GC，因为 task 可能被取消或后续计算被放弃。

目标语义：

```text
capture k
  相关 cleanup segment 跟随 k

resume k
  重新进入这段动态 scope

finalize k
  展开并执行 cleanup

park source k under owner
  sealed completion port 接管最终处置责任
```

## 4. Owner 是关闭责任树

Owner 是第一方运行时协议，概念上拥有：

```text
Owner
├── child owners
├── tasks
├── saved resumptions
├── subscriptions
├── resources
└── cleanup actions
```

库式外观：

```cire
Owner::scope { owner =>
  let task = owner.spawn {
    work()
  }
  use(task)
}
```

`Owner::scope` 和 `owner.spawn` 是普通 API 外观，不是新语法。Compiler 仍要
理解其中涉及的 capability capture、one-shot 责任转移和 finalization。

## 5. Sealed `source.park`

`once` clause 把 continuation 保存到未来时，不能只放进一个全局表：

```cire
handler Async {
  once await(task) as k => {
    task.completion_source.park(k, under = task.owner)
  }
}
```

Park 的静态含义：

- 当前 clause 失去对 `k` 的处置权；
- 当前 path 得到 terminal `Transfers(ParkContract)`，不是 `Unit`；
- 宿主只拿到 generation-bound completion port，不拿 raw `Resume`；
- completion（含 `Result/Outcome` 失败值）、cancel 和 close 竞争同一个 CAS；
- Owner 关闭会 finalize 尚未处置的 `k`；

`source.park(k, under = owner)` 需要 sealed source evidence，不能退化成普通
容器的 `push` 或用户自定义同名 method，否则 checker 无法证明责任只转移一次。

## 6. Generation 防止旧 callback 复活

考虑搜索框被销毁后又用同一个业务 key 创建：

```text
旧实例：key = 42, generation = 7
新实例：key = 42, generation = 8
旧网络请求现在才返回
```

只比较 key 会误把旧结果写入新实例。宿主 callback 因此携带：

```text
(owner_id, generation)
```

入口先检查 Owner 仍存活且 generation 匹配。静态 capture checking 阻止
明显逃逸；generation 处理宿主队列、FFI 和真实竞态。

## 7. 两阶段关闭

Owner 关闭分两阶段。

第一阶段“封门”：

```text
标记子树 closing/dead
撤销 resume、callback 与新注册权限
seal 并 detach child、resumption、cleanup
```

第二阶段“打扫”：

```text
child-first 关闭子 Owner
每个 Owner 内 LIFO cleanup
一个 cleanup 失败仍继续 sibling cleanup
最后聚合报告错误
```

先撤销控制能力，再调用可能失败或同步重入的宿主 disposer，可以防止 cleanup
在即将结束的 Owner 下偷偷注册新任务。

## 8. 结构化并发

Task group 或 nursery 建立在 Owner 上：

```cire
TaskGroup::scope { group =>
  let user = group.spawn {
    load_user()
  }

  let settings = group.spawn {
    load_settings()
  }

  combine(user.await(), settings.await())
}
```

目标保证：

- 父 scope 结束前知道所有 child 的结局；
- 父 Owner 关闭会撤销 child 继续影响外部世界的资格；
- timeout/race 的输家不会留下未处置 continuation；
- 完成、失败和取消只会有一个结果赢得 one-shot slot。

Task group 是第一方库，不需要 `async`、`nursery` 等大量特殊关键字。

## 9. 取消

取消不是“随便返回一个错误字符串”。它需要：

- 撤销继续提交结果的权限；
- 让 cancel/close 对 parked continuation 的 claim 做 CAS，并由胜者 finalize；
- child-first 清理任务与资源；
- 避免普通 catch-all 意外吞掉结构化取消。

取消最终采用独立 abortive effect、typed error 还是分层协议仍需原型决定。
教程不提前发明 `cancel` 语法。

## 10. Portable handler context

宿主稍后调用 callback 时，原来的动态栈已经不存在。Cire 不会默认保存并重装
整个 handler stack。

需要区分：

```text
stack-only handler
portable handler
reentrant handler
```

只有被允许 portable/reentrant，并且 capture checking 接受其全部 capability
的 context 才能跨宿主 callback。精确 type 表示和 ABI 仍是开放设计。

## 当前状态

`defer` 是表面 grammar 基线，但 reduction calculus 仍是明确的证明义务。
Owner、generation、sealed completion source/port、task group 和 callback
adapter 是第一方协议契约。仓库没有 runtime；continuation-aware cleanup、
两阶段关闭、结构化取消和 portable context 都尚未实现。

上一章：[四种恢复模式](10-resumptions.md)　下一章：[增量计算](12-incremental-computation.md)
