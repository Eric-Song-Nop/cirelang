# 08　Handler 与 `with`

## 1. Handler 给请求赋予含义

Effect declaration 只说明可以请求什么：

```cire
effect Clock {
  fun now() -> Instant
}
```

Handler 决定请求在某个词法范围内怎样执行：

```cire
let fixed_clock = handler Clock {
  fun now() => Instant::from_seconds(1000)
}
```

这不是修改全局 `Clock`。`fixed_clock` 是一个普通值，可以传给函数、存入
struct，也可以在不同测试中创建不同实例。

## 2. 使用 `with`

```cire
fn test_expired() -> Bool {
  with fixed_clock {
    expired(Instant::from_seconds(900))
  }
}
```

`expired` 原本需要 `Clock`，但 `with fixed_clock` 在内部处理了它，因此整个
`test_expired` 可以是纯函数。

从本质上看：

```cire
with fixed_clock {
  body()
}
```

近似展开为：

```cire
fixed_clock(fn() {
  body()
})
```

所以 `with` 是 handler application 的糖，不是额外的核心控制机制。

## 3. Inline handler

只用一次时可以直接写：

```cire
fn test_expired() -> Bool {
  with handler Clock {
    fun now() => Instant::from_seconds(1000)
  } {
    expired(Instant::from_seconds(900))
  }
}
```

Parser 必须知道第一个 block 属于 `handler`，第二个 block 是 `with` 的
action。Lossless CST 会保留两层来源，以便 formatter 和诊断准确定位。

## 4. `return` clause

Handler 不只处理 operation，也可以转换整段计算的正常结果：

```cire
let collect = handler Logger {
  fun log(_level, message) => {
    messages.push(message)
  }

  return(value) => {
    (value, messages.freeze())
  }
}
```

`return(value)` 在 action 正常产生最终值时运行。省略时等价于 identity：

```cire
return(value) => value
```

`return` clause 与 operation clause 的结果类型必须共同满足 handler 的整体
类型，不能各自返回互不相关的结果。

## 5. Handler 可以改变结果类型

Abortive error handler 可以把控制 effect 转换成普通数据：

```cire
fn attempt[A, E]![..Rest](
  body : () -> A ! {Error[E], ..Rest},
) -> Result[A, E] ! Rest {
  with handler Error[E] {
    abort raise(error) => Err(error)
    return(value) => Ok(value)
  } {
    body()
  }
}
```

输入 computation 可能请求 `Error[E]`；handler 消除它，并把成功与失败都
收进 `Result[A, E]`。`Rest` 中的其他 effect 继续向外传播。

这个例子也说明 handler 不是简单的“回调表”：它能够解释控制流，并改变整段
计算的结果类型。

## 6. 自动 forwarding

一个 handler 只处理自己的 effect。action 中的其他 effect 自动向外层转发：

```cire
with fixed_clock {
  Logger::log(Info, "checking")
  expired(deadline)
}
```

`Clock` 被消除，`Logger` 仍保留在外层 row。一般形状是：

```text
输入：A ! {Clock, ..E}
处理 Clock
输出：B ! E
```

当前 effect 中缺少 operation clause 应产生穷尽性诊断；显式 forwarding
同一个 effect operation 的最终语法尚未冻结。

## 7. 嵌套、覆盖与 masking

同一 effect 的 handler 嵌套时，普通 operation 先交给最内层：

```cire
with outer_logger {
  with inner_logger {
    Logger::log(Info, "inner handles this")
  }
}
```

有些组合器需要暂时跳过最内层 handler，或完全覆盖 action 原本可见的实现。
这需要明确的 forwarding/masking 规则，也会影响 row 中是否保留重复 demand。
Cire 已把这种能力列入 effect 组合模型，但不在核心规则完成前照搬 Koka 的
`mask`/`override` 拼写。

普通库代码不应通过保存一个全局 handler 指针绕过词法作用域。

## 8. Lexical deep handler

第一版 handler 是 lexical deep handler。被恢复的计算再次请求同一 effect
时，仍由当前 handler 处理：

```text
with h {
  operation()
  // operation 之后恢复的代码仍在 h 里面
}
```

Deep handler 让局部解释在整个 action 的动态执行期间保持一致。Shallow
handler 会把恢复后的代码放到 handler 外侧，组合规则更难；第一版不为它增加
表面语法。

## 9. `with` operand 与 trailing lambda

下面的写法唯一解释为“创建 handler，然后运行 action”：

```cire
with make_handler(1) {
  run()
}
```

Parser 不会先把 block 吸收到 `make_handler(1)` 当作 trailing lambda。如果
handler operand 自己确实需要 trailing lambda，必须加括号：

```cire
with (make_handler(1) {
  configure()
}) {
  run()
}
```

这个局部规则避免 `with h { ... }` 与 UI 风格调用产生结构歧义。

## 10. Named application 预览

匿名 `Clock::now()` 由当前同 family handler 解释。有时同一 family 的两个
实例必须同时存在：

```cire
with fixed_clock as test_clock {
  test_clock.now()
}
```

`as test_clock` 让 handler application 产生一个 fresh capability identity。
这是下一章的主题。

## 当前状态

Handler expression、clause、`return`、`with`、named binder 和相关定向错误
已进入 parser。Handler typing、effect elimination、deep resumption 和
desugaring HIR 尚未实现。

上一章：[Effect 多态](07-effect-polymorphism.md)　下一章：[具名 capability](09-named-capabilities.md)
