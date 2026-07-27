# 02　值、绑定与表达式

## 1. 常用基础类型

教程使用以下基础类型：

| 类型 | 例子 | 用途 |
|---|---|---|
| `Unit` | `()` | 没有有意义的结果 |
| `Bool` | `true`、`false` | 条件 |
| `Int` | `0`、`42`、`-7` | 整数 |
| `Double` | `3.14` | 浮点数 |
| `Char` | `'a'` | Unicode 字符 |
| `String` | `"hello"` | 文本 |

`Unit` 和很多语言的 `void` 不同：`()` 是一个真实的值，`Unit` 是一个真实的
类型，因此它可以出现在泛型容器或函数类型里。

精确的整数宽度、numeric suffix、raw string、插值和 byte literal 仍需在
词法规范中冻结。教程先使用最普通的 literal。

## 2. 不可变绑定

`let` 给一个值命名：

```cire
fn area(width : Int, height : Int) -> Int {
  let result = width * height
  result
}
```

`result` 的类型可以从右侧推导，也可以写出：

```cire
let result : Int = width * height
```

绑定默认不可变。不可变不是为了限制程序员，而是为了让一个名字始终表示同一
件事，从而让重构、并发和 effect 分析更可靠。

## 3. 局部可变绑定

确实需要逐步更新时使用 `let mut`：

```cire
fn sum(values : Array[Int]) -> Int {
  let mut total = 0

  for value in values {
    total = total + value
  }

  total
}
```

可变性是局部、显式的。`total` 可以更新，但 `values` 仍然是不可变绑定。
数组内容是否可变由数组 API 和类型决定，不由变量名是否 `mut` 决定。

局部 mutation 与 multi-shot continuation 的交互很重要：一段计算被恢复多次
时，多个分支共享还是复制状态不能含糊。第 10 章会解释为什么 Cire 对
multi-shot 周围的 mutation 更保守。

## 4. Block 的值

block 按从上到下的确定顺序求值，最后一个表达式成为结果：

```cire
fn discount(price : Int, member : Bool) -> Int {
  let rate = if member { 20 } else { 5 }

  {
    let saved = price * rate / 100
    price - saved
  }
}
```

内层 block 的值是 `price - saved`，所以整个函数返回这个值。

如果最后写 `()`，block 的结果就是 `Unit`：

```cire
fn ignore_result(value : Int) -> Unit {
  let doubled = value * 2
  ()
}
```

## 5. 作用域与 shadowing

内层绑定可以暂时遮蔽外层同名绑定：

```cire
fn normalize(input : String) -> String {
  let text = input.trim()

  if text == "" {
    let text = "(empty)"
    text
  } else {
    text
  }
}
```

两个 `text` 是不同的绑定。LSP 应能准确跳转到各自定义，重命名时也不能把它们
混在一起。

Shadowing 适合表达“同一概念经过一步转换”，但不应被用来隐藏完全无关的值。

## 6. Tuple 与 Array

Tuple 适合临时组合少量位置固定的值：

```cire
let point : (Int, Int) = (10, 20)
```

Array 保存同一类型的多个值：

```cire
let scores : Array[Int] = [10, 20, 30]
let first = scores[0]
```

当字段有稳定含义时，应使用下一章的 struct，而不是让调用者记住
`point.0`、`point.1` 分别代表什么。

`()`、单元素 tuple、多元素 tuple、index/update 的完整解析规则尚待冻结。
这里展示的是 MoonBit 风格目标形状。

## 7. Labelled argument

参数较多或容易混淆时，可以给参数加 label：

```cire
fn connect(
  host : String,
  port~ : Int,
  secure~ : Bool,
) -> Connection ! {Network} {
  ...
}
```

调用时写：

```cire
connect("example.com", port=443, secure=true)
```

如果局部变量与 label 同名，可以使用 label punning：

```cire
let port = 443
let secure = true
connect("example.com", port~, secure~)
```

label 让调用点说明每个布尔值和整数的意思，同时不需要引入专门的配置对象。
默认参数和可选参数的完整规则仍是开放项。

## 8. 求值顺序

Cire 严格求值，并承诺稳定、确定的顺序。对于：

```cire
combine(first(), second())
```

先求值 callee，再从左到右求值参数，最后调用函数。这个规则对普通调用、
effect operation 和语法糖展开都必须一致；否则加入日志或 handler 可能悄悄
改变程序含义。

## 当前状态

基础 type shape 和 block 已有 parser 基线。完整 `let`、`let mut`、tuple、
array、index、赋值、labelled parameter 默认值和运算符语义尚未完成。

上一章：[第一个程序](01-first-program.md)　下一章：[函数与控制流](03-functions-and-control-flow.md)
