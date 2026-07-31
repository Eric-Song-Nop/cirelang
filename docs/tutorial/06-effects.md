# 06　第一个 effect

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

## 1. Effect 是向上下文发出的请求

先看一个没有固定实现的时钟：

```cire
pub(open) effect Clock {
  fun now() -> Instant
}
```

`Clock::now()` 的意思不是“直接调用某个全局系统函数”，而是：

```text
这里需要当前上下文提供一个 Clock.now 操作
```

生产环境可以返回系统时间，测试环境可以永远返回固定时间。业务函数只声明
自己需要什么，不把实现方式写死。

```cire
def expired(deadline : Instant) -> Bool ! {Clock} {
  Clock::now() >= deadline
}
```

返回类型后的 `! {Clock}` 是 effect row。它表示调用 `expired` 时，仍有
`Clock` 请求需要由外层处理。

## 2. 纯函数省略空 row

```cire
def add(left : Int, right : Int) -> Int {
  left + right
}
```

纯函数不写 `! {}`。如果想展开类型，可以把它理解成：

```text
(Int, Int) -> Int ! {}
```

省略空 row 让普通代码保持和 MoonBit 一样简洁；只有存在未处理 effect 时，
签名才增加可见信息。

## 3. 多个 effect

```cire
def load_profile(id : UserId) -> Profile
  ! {Network, Clock, Error[LoadError]} {
  let started = Clock::now()
  let profile = Network::get_profile(id)

  if Clock::now() - started > 5.seconds() {
    Error::raise(Timeout)
  }

  profile
}
```

Row 是集合式类型信息，书写顺序不影响类型相等。它回答的是：

```text
运行这段计算，还可能向上下文请求哪些操作？
```

它不是执行日志。某条运行路径没有调用 `Error::raise`，也不改变函数类型中
“可能请求 Error”的事实。

## 4. 声明 operation

Effect body 中列出 operation：

```cire
pub(open) effect Logger {
  fun log(level : Level, message : String) -> Unit
}

pub(open) effect Error[E] {
  abort[A] raise(error : E) -> A
}
```

Operation 由四部分组成：

```text
mode [普通类型参数] 名称(参数) -> 结果类型
```

`Error::raise` 的 `[A]` 表示它可以出现在任意结果类型的位置：

```cire
def require_name(name : String) -> String ! {Error[InputError]} {
  if name == "" {
    Error::raise(MissingName)
  }
  name
}
```

这里的 `A` 是普通类型参数，不是 effect 参数。因为 `abort` 不继续执行调用点
之后的程序，operation 不需要真的构造一个 `String`。

## 5. 为什么调用时不写 `perform`

Cire 让 operation 保持普通的限定调用或点调用外观：

```cire
Clock::now()
Logger::log(Info, "started")
app.read()
```

Parser 只建立 call；resolver 和 type checker 再判断目标是普通函数、method
还是 effect operation。这样有几个好处：

- 未完成代码仍然能形成完整 CST；
- method 与 operation 的参数、label 和 trailing lambda 规则一致；
- LSP 不需要在 parser 阶段先知道每个名称的类型。

`Clock::now()` 选择当前匿名 `Clock` handler；`app.read()` 精确选择一个具名
capability。后者在第 9 章解释。

## 6. Error effect 与 `Result`

同一个失败可以有两种表示。

作为普通数据：

```cire
def parse_age(text : String) -> Result[Int, ParseError] {
  ...
}
```

作为上下文请求：

```cire
def parse_age(text : String) -> Int ! {Error[ParseError]} {
  ...
}
```

选择标准：

- 失败结果要被存入集合、延迟处理或作为协议数据传递时，用 `Result`；
- 当前控制流要把处理决定交给外层上下文时，用 `Error[E]`；
- handler 可以在两者之间转换，因此不需要把一种宣布为“唯一正确”。

`try/catch`、`raise` 等专用糖尚未冻结。核心语言先把 `Error[E]` 当作普通
abortive effect，避免便捷语法反过来定义不一致的错误语义。

## 7. Effect visibility

Effect 的可见性镜像 trait：

```cire
effect Local { ... }
pub effect Sealed { ... }
pub(open) effect Open { ... }
```

- `effect`：只在当前 package 可见；
- `pub effect`：外部可调用，但只有定义 package 可以提供新的 handler；
- `pub(open) effect`：外部也可以提供 handler。

这让库作者可以公开一个稳定操作协议，同时决定第三方是否能改变它的解释。

## 8. 处理前与处理后

函数调用会把 effect 需求向外传播：

```cire
def report_deadline(deadline : Instant) -> Unit
  ! {Clock, Console} {
  if expired(deadline) {
    Console::print_line("expired")
  }
}
```

`expired` 需要 `Clock`，`print_line` 需要 `Console`，所以调用者的 row 包含两者。

Handler 可以消除自己处理的 effect：

```text
计算：A ! {Clock, ..E}
Clock handler
结果：A ! E
```

`..E` 表示“可能还有别的 effect”。下一章会正式介绍 open row 和 effect
polymorphism，第 8 章再写第一个 handler。

## 当前状态

Effect declaration、四种 mode、identity-aware row、secondary row 与
operation call 都属于 profile grammar/semantics。仓库没有 parser、resolver、
effect inference 或 checker。

上一章：[泛型、trait 与包](05-generics-traits-and-packages.md)　下一章：[Effect 多态](07-effect-polymorphism.md)
