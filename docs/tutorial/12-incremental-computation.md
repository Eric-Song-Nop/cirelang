# 12　第一方增量计算

> 本章示例属于 [`Cire-TR₀/2026-08-01`](../spec-status.md) 第一方契约。

## 1. 这不是新的语言语法

Cire 核心没有 `Signal`、`reactive` 或 `computed` 关键字。增量计算是建立在：

```text
effect + controlled resumption + Owner + cleanup
```

之上的第一方库。

语言负责安全地捕获、恢复和清理后续计算；增量库仍负责判断哪个输入变了、
哪些依赖失效、从哪个位置重算。

## 2. 最小公共 API

目标 API 保持很小：

```cire
Source[A]
Live[A]

source(initial : A) -> Source[A]

read(source : Source[A]) -> A ! {Observe}
write(source : Source[A], value : A) -> Unit ! {Update}

live(
  computation : () -> A ! {Observe},
) -> Live[A]

batch(
  action : () -> Unit ! {Update},
) -> Unit
```

使用：

```cire
let price = source(10)
let count = source(2)

let total = live {
  read(price) * read(count)
}
```

`total` 初始为 `20`。以后 `price` 或 `count` 变化，库只重算依赖它们的部分。

这里的 `live { ... }` 是普通 trailing lambda call，不是关键字。

## 3. Read 产生 continuation cut

```cire
let a = read(source_a)
let b = read(source_b)
a + b
```

每次 `read` 把直接风格程序分成已完成前缀和可恢复后缀：

```text
root
└── read(A) → kA
    └── read(B) → kB
        └── return
```

- 只有 B 变化：恢复 `kB`，复用旧 `a`；
- A 变化：恢复 `kA`，旧 `kB` 是失效后代；
- A、B 同批变化：只恢复支配 `kB` 的 `kA`。

这比“每个 source 保存一个独立 callback”精确，因为 cut 之间有控制支配关系。

## 4. 动态依赖

```cire
let selected = live {
  if read(use_primary) {
    read(primary)
  } else {
    read(secondary)
  }
}
```

一次运行可能读取：

```text
{use_primary, primary}
```

下一次可能变成：

```text
{use_primary, secondary}
```

类型系统不能提前知道运行时分支，因此库记录本轮 trace。分支变化时建立候选
trace，成功后替换旧依赖，并 finalize 旧分支持有的 cut 和资源。

动态依赖不是类型系统失败，而是问题本身包含运行时控制流。

## 5. 四个最小内部结构

```text
Source
  当前值与订阅 cut 的唤醒索引

Trace
  一次 Live 执行形成的 continuation cut 树

Queue
  去重后的最早失效 cut

Epoch
  一批更新使用的一致版本
```

`Source + Trace + Queue + Epoch` 足以建立第一版内核。共享 DAG、差量代数、
demand tracking 和 MVCC 可以等真实需求出现再增加。

## 6. Batch 与一致快照

```cire
batch {
  write(price, 12)
  write(count, 3)
}
```

两个更新属于同一 Epoch。`total` 不应先发布 `24` 再发布 `36`；它应基于同一
逻辑快照重算并发布 `36`。

增量结果的核心正确性标准是：

```text
增量执行结果
=
在同一快照上从头执行的结果
```

优化不能改变这条等式。

## 7. `ctl` 不自动等于“可安全增量”

`Observe.read` 可能使用一般控制 operation 获取 continuation，但能够
multi-shot 恢复不代表后缀一定可重放。

增量库还需要检查或约束：

- 后缀使用的 effect 是否 replayable；
- 捕获的 capability 是否允许重复执行；
- 宿主写入是否被隔离到 commit 阶段；
- cleanup 能否被替换或分叉；
- mutation 属于共享状态、候选状态还是禁止捕获。

因此 continuation mode 与 replay policy 必须分开建模。

## 8. `Source`、`Live`、`Event` 和 `Task` 不相同

```text
Source[A]        可写的当前输入
Live[A]          持续维护的当前派生结果
Event[E]         一批中的有序 occurrence
Task[A, E]       至多完成一次的异步计算
Resource[K,A,E]  由 Owner、key 与 policy 管理的异步状态
```

把它们都压成万能 `Observable[A]` 会丢失：

- 有没有当前值；
- 是否允许重复发生；
- 是否只完成一次；
- 何时取消和清理；
- key 改变时替换、并行还是排队。

## 9. Owner 关闭

`Live` 属于当前 Owner：

```text
Owner close
  → 停止后续重算
  → 删除 Source 依赖
  → 从 Queue 移除 wake token
  → finalize 保存的 continuation
```

Source 应持有弱唤醒入口，而不是强行让整个 UI 或服务对象永远存活。

## 当前状态

本章全部是第一方库设计，不是已实现 API。增量内核、runtime continuation、
Owner 和 replay checking 都尚未实现；语言核心不会为它增加新的表面关键字。

上一章：[清理、Owner 与并发](11-cleanup-owner-and-concurrency.md)　下一章：[UI 与 trailing lambda](13-ui-and-trailing-lambdas.md)
