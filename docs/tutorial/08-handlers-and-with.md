# 08　Handler 与 `with`

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

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
def test_expired() -> Bool {
  with fixed_clock
  in {
    expired(Instant::from_seconds(900))
  }
}
```

`expired` 原本需要 `Clock`，但 `with fixed_clock` 在内部处理了它，因此整个
`test_expired` 可以是纯函数。

从本质上看：

```cire
with fixed_clock
in {
  body()
}
```

近似展开为：

```cire
fixed_clock(fn() {
  body()
})
```

所以 `with` 是 scoped computation application 的糖，不是额外的核心控制
机制。Effect handler 是最重要的用途，但任何接收 computation thunk 的
高阶 wrapper 都可以使用同一外观。

`with ... in ...` 本身是表达式，不是只能放在 block 顶层的 statement：

```cire
let result =
  with catch_parse_error
  in parse(input)
```

它也可以直接出现在 `match` 分支、函数 argument 或其他需要 expression 的
位置。`in` 后面接受任意 expression；多条语句时才使用 `{ ... }` block。

## 3. Inline handler

只用一次时可以直接写：

```cire
def test_expired() -> Bool {
  with handler Clock {
    fun now() => Instant::from_seconds(1000)
  }
  in {
    expired(Instant::from_seconds(900))
  }
}
```

`in` 明确分开 handler operand 与实际 computation，因此不会出现相邻的
`} {`，parser 也不需要猜哪一个 block 是 action。Lossless CST 会保留
inline handler、`in` 和 body 的来源，以便 formatter 和诊断准确定位。

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
def attempt[A, E]![..Rest](
  body : () -> A ! {Error[E], ..Rest},
) -> Result[A, E] ! Rest {
  with handler Error[E] {
    abort raise(error) => Err(error)
    return(value) => Ok(value)
  }
  in {
    body()
  }
}
```

输入 computation 可能请求 `Error[E]`；handler 消除它，并把成功与失败都
收进 `Result[A, E]`。`Rest` 中的其他 effect 继续向外传播。

这个例子也说明 handler 不是简单的“回调表”：它能够解释控制流，并改变整段
计算的结果类型。

## 6. 一个作用域同时处理多个 effect

实际程序通常不只需要一个 effect：

```cire
def load_page() -> Page
  ! {Clock, Logger, Error[LoadError]} {
  ...
}
```

为测试准备三个 handler：

```cire
let quiet_logger = handler Logger {
  fun log(_level, _message) => ()
}

let catch_load_error = handler Error[LoadError] {
  abort raise(error) => Err(error)
  return(page) => Ok(page)
}
```

`fixed_clock` 沿用本章开头的定义。

处理多个 effect 的标准写法是一个扁平、有序的 `with` chain：

```cire
with fixed_clock
with quiet_logger
with catch_load_error
in {
  load_page()
}
```

这一个作用域同时处理了 `Clock`、`Logger` 和 `Error[LoadError]`。它不是三个
互不相干的阶段；`load_page()` 在三层 handler 共同构成的上下文中运行。
第一项是最外层，最后一项最靠近 `in` 后面的 computation，因此它等价于：

```cire
fixed_clock(fn() {
  quiet_logger(fn() {
    catch_load_error(fn() {
      load_page()
    })
  })
})
```

连续 entry 只在末尾写一次 `in`。每层都写 `in` 仍然合法，但表示显式构造
多个嵌套的单项 chain：

```cire
with fixed_clock in
  with quiet_logger in
    with catch_load_error in
      load_page()
```

两种写法在这个例子中结果相同；教程和 formatter 生成的新代码优先采用前一种
扁平形式。显式嵌套仍可用于强调独立 scope，formatter 不应越过 comment
擅自合并 CST。

从 row 变化来看：

```text
load_page
  Page ! {Clock, Logger, Error[LoadError]}

with catch_load_error
  Result[Page, LoadError] ! {Clock, Logger}

with quiet_logger
  Result[Page, LoadError] ! {Clock}

with fixed_clock
  Result[Page, LoadError]
```

最内层 `catch_load_error` 先改变结果类型；外面的两个 handler 保持结果类型，
只消除自己的 effect。

当前工作语法中，一个 `handler Effect { ... }` literal 负责一个 effect
family。处理多个 family 不需要第二种 multi-handler literal；组合发生在
普通 handler application 上。

如果直接设计：

```text
handler {Clock, Logger, Error[LoadError]} { ... }
```

仍然必须回答 handler 的先后顺序、只有一个还是多个 `return` clause、一个
clause 发出的 effect 由谁处理。显式组合已经把这些答案写进嵌套结构。以后即使
增加 multi-handler 糖，也应无歧义地展开成这种有序组合，而不是获得另一套
控制语义。

## 7. 把组合封装成可复用 handler

因为 `with h in body` 本质上把 `body` thunk 交给 `h`，普通高阶函数也可以
封装整套 handler：

```cire
def[A]![..E] test_runtime(
  action : () -> A
    ! {Clock, Logger, Error[LoadError], ..E},
) -> Result[A, LoadError] ! E {
  with fixed_clock
  with quiet_logger
  with catch_load_error
  in {
    action()
  }
}
```

调用者只看到一个组合后的 handler：

```cire
with test_runtime
in {
  load_page()
}
```

展开后就是：

```cire
test_runtime(fn() {
  load_page()
})
```

`test_runtime` 同时消除三个 effect，并原样转发 `E` 中不认识的其他 effect。
这也是“handler 是值”和“effect row 多态”结合后的价值：库可以提供
`test_runtime`、`server_runtime`、`browser_runtime`，而语言不需要为每种
组合增加关键字。

## 8. 组合顺序为什么重要

下面两个嵌套顺序不一定等价：

```cire
with logger
with errors
in {
  action()
}
```

```cire
with errors
with logger
in {
  action()
}
```

原因有两个：

- handler 可以通过 `return` 改变整段计算的结果类型；
- 一个 handler 的 clause 自己也可能请求另一个 effect。

例如 error handler 在捕获错误时调用 `Logger::log`，就应把 Logger handler
放在它外面：

```cire
with logger
with errors_that_log
in {
  action()
}
```

这样 error clause 发出的日志仍处于 Logger handler 的范围内。组合器的公开
类型应明确展示它消除了什么、保留了什么、最终返回什么，不能只靠名称猜测。

## 9. 自动 forwarding

一个 handler 只处理自己的 effect。action 中的其他 effect 自动向外层转发：

```cire
with fixed_clock
in {
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

## 10. 嵌套、覆盖与 masking

同一 effect 的 handler 嵌套时，普通 operation 先交给最内层：

```cire
with outer_logger
with inner_logger
in {
  Logger::log(Info, "inner handles this")
}
```

有些组合器需要暂时跳过最内层 handler，或完全覆盖 action 原本可见的实现。
这需要明确的 forwarding/masking 规则，也会影响 row 中是否保留重复 demand。
Cire 已把这种能力列入 effect 组合模型，但不在核心规则完成前照搬 Koka 的
`mask`/`override` 拼写。

普通库代码不应通过保存一个全局 handler 指针绕过词法作用域。

## 11. Lexical deep handler

第一版 handler 是 lexical deep handler。被恢复的计算再次请求同一 effect
时，仍由当前 handler 处理：

```text
with h
in {
  operation()
  // operation 之后恢复的代码仍在 h 里面
}
```

Deep handler 让局部解释在整个 action 的动态执行期间保持一致。Shallow
handler 会把恢复后的代码放到 handler 外侧，组合规则更难；第一版不为它增加
表面语法。

## 12. `with` 不只包 handler

`with` 的统一含义是“用 scoped computation transformer 包住后面的计算”。
所以 transaction、retry、timeout、trace 或 scheduler 之类的普通高阶
wrapper 也可以使用：

```cire
with retry(3)
with transaction(db)
with trace("save-order")
in {
  save_order(order)
}
```

它的近似展开是：

```cire
(retry(3))(fn() {
  (transaction(db))(fn() {
    (trace("save-order"))(fn() {
      save_order(order)
    })
  })
})
```

也就是说，`retry(3)` 先产生一个 transformer value，`with` 再把 action
thunk 传给它；`with` 不会把 action 偷偷追加成 `retry` 调用的普通参数。

顺序仍然重要。上面的程序表示每次 retry 都可以建立一个新 transaction；
如果把 `transaction(db)` 放在第一项，则一个 transaction 会包住全部 retry。

这也影响 operand 的求值时机。外层 wrapper 先求值并收到一个 action thunk；
内层 operand 只有在这个 thunk 被调用时才求值。因此 `retry(3)` 多次调用
action 时，`transaction(db)` 也会为每次尝试重新求值。若确实要先创建一次
并复用同一个 wrapper，应在 chain 外显式绑定：

```cire
let tx = transaction(db)
with retry(3)
with tx
in {
  save_order(order)
}
```

这些 wrapper 可以在内部使用 algebraic effect，也可以只是普通高阶函数。
`with` 不关心实现方式，只检查每一层的 computation 输入、输出、结果类型和
effect 是否能顺序连接。

这个泛化有明确边界。`with` 不用于 record update、trait constraint、普通
对象 receiver scope、import 或普通变量绑定。特别是 `as app` 仍只创建 fresh
named capability，不能替代 `let` 或普通 trailing-lambda parameter。

## 13. `with` operand 与 trailing lambda

因为 `in` 明确标出 computation 的开始，operand 自己可以包含 trailing
lambda：

```cire
with make_handler(1) {
  configure()
}
in {
  run()
}
```

这里第一个 block 是 `make_handler(1)` 的最后一个参数。若 operand 自己是
顶层 `with` expression，则使用括号明确嵌套边界：

```cire
with (
  with configure_runtime
  in make_handler()
)
in {
  run()
}
```

PEG 将 `with`、`as` 和 `in` 作为 chain-level 恢复点。缺少 `in` 时，诊断
应指向整个 chain，并说明还没有开始被包裹的 computation，而不是把最后一个
block 猜成 action。

## 14. Named application 预览

匿名 `Clock::now()` 由当前同 family handler 解释。有时同一 family 的两个
实例必须同时存在：

```cire
with fixed_clock as test_clock
in {
  test_clock.now()
}
```

`as test_clock` 让 handler application 产生一个 fresh capability identity。
这是下一章的主题。

## 当前状态

Handler、clause、implicit `return`、ordered `with ... in ...` chain 与
named binder 都属于 profile grammar/elaboration。仓库没有 parser、HIR、
handler checker 或 runtime。

上一章：[Effect 多态](07-effect-polymorphism.md)　下一章：[具名 capability](09-named-capabilities.md)
