# 01　第一个 Cire 程序

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

## 1. 从一个函数开始

最小的普通函数由名称、参数、返回类型和函数体组成：

```cire
def answer() -> Int {
  42
}
```

`def` 开始具名函数声明，`answer` 是名称，`()` 表示没有参数，`Int` 是返回类型。
花括号中的 block 是一个表达式；最后一个表达式 `42` 就是整个 block 的值，
所以不需要写 `return 42`。

调用函数使用普通括号：

```cire
def doubled_answer() -> Int {
  answer() * 2
}
```

## 2. 带参数的函数

参数写成 `名称 : 类型`：

```cire
def greet(name : String) -> String {
  "Hello, " + name
}
```

Cire 是静态类型语言。`name` 在函数体中始终是 `String`；如果传入 `Int`，
错误会在编译期被指出。

顶层公共函数使用 `pub`：

```cire
pub def square(value : Int) -> Int {
  value * value
}
```

默认声明只在当前 package 内可见。先默认隐藏实现，再有意识地公开 API，
可以避免 package 边界随着项目增长而失控。

## 3. `main`

可执行 package 从 `main` 开始。概念上的 Hello World 是：

```cire
def main() -> Unit ! {Console} {
  Console::print_line("Hello, Cire!")
}
```

这里提前出现了两个稍后才解释的部分：

- `Unit` 表示“没有有意义的结果”，它仍然是一个真正的类型；
- `! {Console}` 表示函数会请求控制台操作。

`Console::print_line` 不是写死在语法里的命令。它是一个 effect operation，
由程序最外层的运行环境提供 handler。这让测试环境可以把输出收集到数组，
浏览器环境可以写入开发者控制台，命令行环境可以写到标准输出。

暂时可以把它读成：

```text
main 返回 Unit，并且需要 Console 能力
```

第 6 章会正式解释这段签名。

## 4. 注释

行注释从 `//` 开始：

```cire
// 摄氏温度转华氏温度
def fahrenheit(celsius : Double) -> Double {
  celsius * 1.8 + 32.0 // block 的最后一个表达式
}
```

文档注释和块注释的精确词法仍需随 lexer 规范冻结。普通教程示例统一使用
`//`，避免依赖尚未决定的形式。

## 5. 表达式，而不是“命令列表”

下面的 `if` 本身产生值：

```cire
def absolute(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}
```

这和“先声明一个变量，再分别赋值”相比有两个优点：

- 每个分支必须产生兼容的类型；
- `result` 不会处于“声明了但还没有值”的中间状态。

Cire 的 `match`、block 和 scoped computation application 也遵循同一个
表达式原则。

## 6. 一个常见错误

下面的两个分支返回不同类型：

```cire
def broken(flag : Bool) -> Int {
  if flag {
    1
  } else {
    "one"
  }
}
```

compiler 应同时标出两个分支，并解释 `Int` 与 `String` 无法统一，而不是只在
函数末尾报告“返回类型错误”。诊断质量是 Cire 语言体验的一部分。

## 7. 小练习

试着只看类型写出函数体：

```cire
def minutes_to_seconds(minutes : Int) -> Int {
  ...
}

def choose_name(nickname : String, use_nickname : Bool) -> String {
  ...
}
```

第二个函数可以直接把 `if` 作为结果。

## 当前状态

函数签名、调用、block、`if`、运算符与 literal 都属于 profile grammar。
仓库没有 parser 或 type checker；本章例子是规范示例，不是已运行程序。

上一章：[如何阅读](00-how-to-read.md)　下一章：[值、绑定与表达式](02-values-and-expressions.md)
