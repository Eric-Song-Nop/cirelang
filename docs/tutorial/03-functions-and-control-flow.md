# 03　函数与控制流

> 本章示例属于 [`Cire-TR₀/2026-07-31`](../spec-status.md) 教程基线。

## 1. 函数是一等值

函数可以像整数和字符串一样传入、返回和保存：

```cire
def apply_twice(
  value : Int,
  transform : (Int) -> Int,
) -> Int {
  transform(transform(value))
}
```

`(Int) -> Int` 是函数类型。调用：

```cire
apply_twice(10, fn(value) {
  value + 1
})
```

结果是 `12`。

## 2. Lambda

匿名函数使用 `fn`：

```cire
let double = fn(value : Int) {
  value * 2
}
```

参数类型通常可以从上下文推导：

```cire
numbers.map(fn(value) {
  value * 2
})
```

Lambda 可以捕获外层绑定：

```cire
def add_by(amount : Int) -> (Int) -> Int {
  fn(value) {
    value + amount
  }
}
```

返回的函数保留了 `amount`。普通值的捕获很直接；如果捕获的是具名 capability
或 one-shot resumption，compiler 还需要检查这个函数能够被保存多久、调用
几次。第 9 和第 10 章会回到这个例子。

## 3. Trailing lambda 预览

函数的最后一个参数是 lambda 时，可以移到括号外：

```cire
numbers.map { value =>
  value * 2
}
```

它只是下面写法的糖：

```cire
numbers.map(fn(value) {
  value * 2
})
```

这套规则足以支持 collection API、作用域 API 和 UI DSL，不需要宏系统。
第 13 章会讲完整的附着规则。

## 4. `if` 是表达式

```cire
def category(age : Int) -> String {
  if age < 13 {
    "child"
  } else if age < 18 {
    "teen"
  } else {
    "adult"
  }
}
```

需要结果的 `if` 必须覆盖所有路径，而且各分支类型要兼容。只有结果是 `Unit`
时才适合省略 `else`：

```cire
if debug {
  Console::print_line("debug")
}
```

## 5. 提前 `return`

最后一个表达式通常最清楚，但 guard-style 检查可以提前返回：

```cire
def safe_percent(value : Int, total : Int) -> Int {
  if total == 0 {
    return 0
  }

  value * 100 / total
}
```

`return` 退出当前函数，不是退出任意外层 handler 或 callback。错误传播通常
由 `Error[E]` effect 表达，而不是给 `return` 增加隐式异常语义。

## 6. 循环

遍历集合的工作形式：

```cire
for user in users {
  Console::print_line(user.name)
}
```

条件循环：

```cire
let mut index = 0
while index < users.length() {
  use(users[index])
  index = index + 1
}
```

需要主动结束或跳过本轮时使用 `break`、`continue`。无条件循环使用 `loop`：

```cire
loop {
  let message = receive()
  if message == Stop {
    break
  }
  handle(message)
}
```

循环是否拥有 `else`/`nobreak` 结果分支、labelled break 以及 iterator protocol
仍需冻结。教程的核心建议是：集合转换优先使用 `map`、`filter`、`fold`；
需要明确局部状态或提前退出时再使用循环。

## 7. 递归

ADT 往往通过递归处理：

```cire
def factorial(value : Int) -> Int {
  if value <= 1 {
    1
  } else {
    value * factorial(value - 1)
  }
}
```

Cire 严格求值，不保证所有递归自动变成循环。深递归算法需要尾调用保证、
显式栈或 collection combinator；这些实现承诺仍需后端验证。

## 8. 方法只是带归属的函数

方法使用 `Type::name` 声明：

```cire
struct User {
  name : String
}

def User::greet(self : User) -> String {
  "Hello, " + self.name
}
```

调用：

```cire
user.greet()
```

方法不是隐藏 dispatch 的对象成员；它是与类型构造器关联的顶层函数。
是否发生 trait dispatch 由类型和 trait constraint 决定。

## 当前状态

`def` 声明、`fn` 值、函数类型、call/method、trailing lambda、`if`、
`return`、递归、循环与 precedence 都属于 profile grammar。仓库没有
parser、elaborator 或 checker。

上一章：[值与表达式](02-values-and-expressions.md)　下一章：[数据与模式匹配](04-data-and-patterns.md)
