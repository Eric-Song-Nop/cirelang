# 00　如何阅读这套教程

> 本章按 [`Cire-TR₀/2026-08-01`](../spec-status.md) 解释规范与第一方契约；
> 仓库当前没有实现。

## 1. 先分清三件事

Cire 还在设计和实现早期。阅读示例时，需要把三件事分开：

```text
语言设计        程序应该怎样写、怎样理解
compiler 状态   现在能解析、检查或运行到哪一步
第一方库设计    用普通语言功能提供的 Owner、增量、UI 与互操作 API
```

例如：

```cire
with read_42 as app
in {
  app.read()
}
```

`with ... as app` 的生成式 capability 语义已经确定；`cap F` 仍是工作关键词；
完整的 capability type checking 还没有实现。教程会展示目标程序，因为只有
先把完整语言讲清楚，parser、type checker 和标准库才能朝同一方向实现。

## 2. Cire 是什么

Cire 是一门严格求值、面向 WebAssembly 的通用函数式语言。它有常规的：

- 值、函数和局部可变状态；
- struct、enum 和模式匹配；
- 参数多态、高阶函数和 trait；
- package、可见性和信息隐藏。

它的特色是：

- 函数类型会记录尚未处理的 effect；
- handler 可以在词法范围内解释 effect operation；
- 普通类型、effect family 和 effect row 可以分别多态；
- 具名 capability 可以指出请求发往哪个具体 handler；
- `abort`、`fun`、`once`、`ctl` 限制 handler 对后续计算的控制权；
- Owner 与结构化清理负责异步任务、续体和宿主资源的确定性关闭。

Cire 有 GC。Owner 不是另一种内存管理器；它负责“什么时候取消任务、撤销
callback、运行清理”，而 GC 负责回收不可达内存。

## 3. 最重要的阅读顺序

不要先把 effect 想成“更复杂的异常”。先掌握这条主线：

```text
表达式返回值
  → 函数把计算封装起来
  → effect operation 向上下文请求某件事
  → handler 为请求提供解释
  → resumption 表示请求之后尚未执行的计算
  → named capability 精确选择某一个解释实例
```

后面的 Owner、增量计算和 UI 都建立在这条主线上。

## 4. 示例约定

代码围栏中的内容是 Cire：

```cire
def double(value : Int) -> Int {
  value * 2
}
```

省略号表示尚未展开的普通实现：

```cire
def connect(url : Url) -> Connection ! {Network} {
  ...
}
```

概念模型会使用 `text`：

```text
请求 + 上下文中的 handler → operation 的实际含义
```

示例优先写完整类型。实际使用时，局部变量、lambda 和许多泛型实参通常由
compiler 推导。

## 5. 语法与语法糖

Cire 刻意保持少量核心构造。比如：

```cire
with h
in {
  work()
}
```

是 scoped computation application 的糖；`h` 可以是 effect handler，也可以
是接收 computation thunk 的普通高阶 wrapper。只有后一种近似展开成：

```cire
h(fn() {
  work()
})
```

Effect handler则降为
`freshprompt p in handle[p,h,...](work())`，不能当作普通 call。

类似地，trailing lambda：

```cire
items.for_each { item =>
  show(item)
}
```

近似展开成：

```cire
items.for_each(fn(item) {
  show(item)
})
```

教程在第一次遇到糖时都会给出展开。理解展开比背关键字更重要。

## 6. 不要从示例推断尚未冻结的细节

Literal 后缀和 package manifest 等细节仍需逐项冻结；tuple、循环、pattern、
block 与 precedence 已由完整 grammar 统一。相关章节会明确区分 profile
baseline 与开放问题，示例本身不产生额外兼容性承诺。

如果教程和别的设计文档冲突，以
[完整表面语法](../surface-grammar.md)和[状态矩阵](../spec-status.md)为准。
仓库当前没有实现。

下一章：[第一个 Cire 程序](01-first-program.md)
