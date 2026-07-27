# Cire 语言教程

这是一套从零开始、按顺序阅读的 Cire language tour。它先介绍普通的值、函数、
数据类型和模块，再逐步进入 Cire 最重要的部分：类型化代数效应、effect
polymorphism、handler、具名 capability、受控续体和结构化清理。

教程假设读者写过一点程序，但不要求了解函数式编程、代数效应或类型系统。

## 阅读路线

| 章节 | 主题 | 学完以后能回答 |
|---|---|---|
| [00](00-how-to-read.md) | 如何阅读与实现状态 | 哪些是语言设计，哪些现在已经能被 compiler 处理？ |
| [01](01-first-program.md) | 第一个程序 | Cire 程序由什么组成？ |
| [02](02-values-and-expressions.md) | 值、绑定与表达式 | `let`、可变局部值和 block 如何求值？ |
| [03](03-functions-and-control-flow.md) | 函数与控制流 | 函数、lambda、`if`、循环如何组合？ |
| [04](04-data-and-patterns.md) | 数据与模式匹配 | 如何用 struct、enum 和 pattern 建模？ |
| [05](05-generics-traits-and-packages.md) | 泛型、trait 与包 | 如何写可复用、可抽象的普通代码？ |
| [06](06-effects.md) | 第一个 effect | effect row 为什么比“这个函数有副作用”更精确？ |
| [07](07-effect-polymorphism.md) | Effect 多态与 ability | 普通泛型、effect family 和 effect row 如何同时抽象？ |
| [08](08-handlers-and-with.md) | Handler 与 `with` | operation 的意义如何由调用上下文提供？ |
| [09](09-named-capabilities.md) | 具名 capability | 如何区分同一种 effect 的两个具体实例？ |
| [10](10-resumptions.md) | 四种恢复模式 | `abort`、`fun`、`once`、`ctl` 分别允许什么？ |
| [11](11-cleanup-owner-and-concurrency.md) | 清理、Owner 与并发 | 暂停、取消或放弃计算时，谁负责善后？ |
| [12](12-incremental-computation.md) | 增量计算 | 为什么增量计算是第一方库，而不是特殊语法？ |
| [13](13-ui-and-trailing-lambdas.md) | UI 与 trailing lambda | 没有宏系统时，UI DSL 如何保持简洁？ |
| [14](14-wasm-and-interop.md) | WebAssembly 与互操作 | capability、callback 与宿主对象如何跨边界？ |
| [15](15-complete-example.md) | 完整示例 | 这些特性如何在一个小程序里协作？ |
| [16](16-syntax-index.md) | 语法索引 | 某种写法在哪里讲过，它当前是什么状态？ |

第一次阅读时，建议按编号顺序读到第 11 章。第 12 至 14 章主要解释第一方库与
宿主平台；已经理解语言核心后可以按兴趣选择。

## 教程中的状态

教程描述的是 Cire 当前的目标语言，不等于当前 compiler 已经全部实现。

- **已决定**：后续设计和实现应遵守的语法或语义。
- **工作形式**：当前最完整的写法，仍允许在兼容性承诺前调整。
- **库设计**：普通 Cire API 的目标形状，不是语言关键字。
- **尚未实现**：教程可以用于讨论和设计，但现在还不能编译运行。

每一章末尾都有“当前状态”。如果只想知道 parser 现在能处理什么，请直接看
[实现进度](../simple/progress.md)。

## 教学方法与参考

本教程采用几种经过验证的教学顺序：

- 像 [OCaml Tour](https://ocaml.org/docs/tour-of-ocaml) 一样，先用值、函数和
  模式匹配建立表达式语言的直觉；
- 像 [MoonBit Fundamentals](https://docs.moonbitlang.com/en/latest/language/fundamentals.html)
  一样，把 ADT、method、trait 和 package 放在 effect 之前；
- 像 [Effekt Effects Tour](https://effekt-lang.org/tour/effects) 一样，把
  operation 解释成“向上下文发出的请求”；
- 像 [Koka Book](https://koka-lang.github.io/koka/doc/book.html) 一样，用
  effect type、handler、effect polymorphism 和 `with` 把高级控制流逐步展开。

这些资料影响的是教学次序和例子的解释方式。所有代码仍然是 Cire 语法；
语言规则以[表面语法工作规范](../surface-syntax.md)和
[多态设计](../polymorphism-design.md)为准。
