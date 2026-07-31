# 10　四种恢复模式

> 本章示例属于 [`Cire-TR₀/2026-08-01`](../spec-status.md) 教程基线。

## 1. Operation 之后还有什么

看一段代码：

```cire
let answer = Choice::choose([1, 2])
answer * 10
```

执行到 `choose` 时，后面的计算可以概念化成函数：

```text
k(answer) = answer * 10
```

这个“尚未执行的后续计算”叫 resumption 或 continuation。Handler 能不能拿到
它、能用几次，决定了 operation 的控制能力。

## 2. 四个 mode

```cire
effect Error[E] {
  abort[A] raise(error : E) -> A
}

effect Reader[R] {
  fun ask() -> R
}

effect Async {
  once[A] await(task : Task[A]) -> A
}

effect Choice {
  ctl[A] choose(values : Array[A]) -> A
}
```

| Mode | Clause 得到 `k` | 可以怎样继续 |
|---|---:|---|
| `abort` | 否 | 不继续 |
| `fun` | 否 | 自动、恰好一次、尾恢复 |
| `once` | 是 | 零次或一次；只能经 sealed source 转交 |
| `ctl` | 是 | 零次、一次或多次 |

这四个词描述的是 handler 对后续计算拥有的最大权力。

## 3. `abort`：不恢复

```cire
handler Error[InputError] {
  abort raise(error) => Err(error)
  return(value) => Ok(value)
}
```

Clause 没有 `as k`，因为 operation 之后的计算不会继续。`abort` 适合错误、
拒绝和不可恢复取消。

Polymorphic result `abort[A] ... -> A` 不是说 handler 能制造任意 `A`，而是
调用点之后永远不会以一个 `A` 恢复。

## 4. `fun`：像动态绑定的函数

```cire
handler Reader[Int] {
  fun ask() => 42
}
```

Clause 返回 `42` 后，语言自动把它交给调用点，并在尾位置继续一次。概念上：

```text
fun ask() => body

≈

ctl ask() as k =>
  k.resume(body)
```

但 `fun` 不暴露 `k`，因此 compiler 通常可以接近普通函数调用地实现它。
Reader、Logger、Clock 这类不改变控制形状的 operation 优先使用 `fun`。

## 5. `once`：可以暂停，但至多处置一次

```cire
handler Async {
  once await(task) as k => {
    task.completion_source.park(k, under = task.owner)
  }
}
```

`once` 显式拿到 `k`，最终只能选择一条 terminal path：

```cire
k.resume(value)
k.finalize()
source.park(k, under = owner)
```

三者都会消耗同一份处置权：

- `resume` 以一个 operation 结果继续；
- `finalize` 放弃后续计算并执行相应清理。
- `park` 产生 `Transfers(ParkContractV2)`，由 generation-bound completion
  port 接管。

`park` 终止当前 path且不返回 `Unit`。Raw `k` 不会被 host callback捕获；
失败用 `Result/Outcome` 值正常恢复，或由显式 abort effect表达。

## 6. `ctl`：一般控制

```cire
let all_choices = handler Choice {
  ctl choose(values) as k => {
    values.flat_map { value =>
      k.resume(value)
    }
  }

  return(value) => [value]
}
```

对每个候选值恢复一次，会形成多条执行分支。`ctl` 也允许：

```text
零次恢复   丢弃后续
一次恢复   普通控制转移
多次恢复   搜索、回溯、非确定性
```

`ctl` 表示“允许 multi-shot”，不是“每个 handler 都必须恢复多次”。

## 7. Mode weakening

声明给出最大能力，具体 handler 可以更严格：

| Operation 声明 | Handler clause 可使用 |
|---|---|
| `abort` | `abort` |
| `fun` | `fun` |
| `once` | `abort`、`fun`、`once` |
| `ctl` | `abort`、`fun`、`once`、`ctl` |

例如一个 `ctl choose` 可以由随机 handler 只选择一次：

```cire
handler Choice {
  fun choose(values) => values.random()
}
```

`fun` 与 `abort` 彼此不能替换：前者保证继续一次，后者保证不继续。

## 8. One-shot 静态检查

顺序使用两次一定错误：

```cire
once await(task) as k => {
  k.resume(first)
  k.resume(second)
}
```

互斥分支各使用一次可以安全：

```cire
once await(task) as k => {
  match task.outcome() {
    Ok(value) => k.resume(Ok(value))
    Err(error) => k.resume(Err(error))
  }
}
```

如果 lambda 捕获 `k`，lambda 自身也不能被无限次调用：

```cire
once await(task) as k =>
  task.completion_source.park(k, under = task.owner)
```

自行构造捕获 raw `k` 的 callback 应被拒绝。Sealed completion source
内部建立 CAS one-shot slot，宿主只拿到 completion port。

## 9. Multi-shot 与 replay safety

恢复多次会复制后续控制流，但不代表所有捕获内容都可以安全复制：

```text
可重放的纯值              通常安全
普通不可变 ADT            通常安全
独占宿主句柄              不能隐式复制
one-shot capability        不能进入多条分支
局部 mutable authority     必须定义共享、快照或禁止
不可重放 cleanup           不能随意分叉
```

因此 `ctl` 的 usage rule 和 replay safety 是两套互补检查。前者允许 `k` 被
调用多次，后者判断 `k` 捕获的环境是否真的能被多次恢复。

## 10. 为什么不让所有变量都 affine

Cire 第一版只对 resumption disposition、capability capture 和相关 authority
做专门检查。普通整数、字符串和不可变 ADT 不需要 Rust 式 move 规则。

这样数量系统集中解决真正由 handler 引入的问题，而不会让所有日常代码都为
控制流机制付出语法成本。

## 当前状态

四种 mode、`as k`、resume/finalize 与 sealed park 的 profile 已确定。
仓库没有 parser、checker 或 continuation runtime；usage checking、mode
weakening、replay safety 与 Owner CAS 都是未来实现和证明义务。

上一章：[具名 capability](09-named-capabilities.md)　下一章：[清理、Owner 与并发](11-cleanup-owner-and-concurrency.md)
