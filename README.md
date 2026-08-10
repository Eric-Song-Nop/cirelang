# Cire

Cire 是一门正在设计中的通用编程语言。它面向 WebAssembly，并把类型化
代数效应、受控续体、具名 capability 和 temporal/Owner safety 作为核心能力。

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及具名 capability 为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

当前仓库是**纯规范仓库**，不包含编译器、生产运行时、标准库或 LSP 实现。
当前设计 profile 是 `Cire-v1.0`。
[`docs/cire-lang-design.typ`](docs/cire-lang-design.typ) 是语言设计的唯一入口，按顺序
组合 `docs/design/` 中按语言设计目标和编译器阶段划分的 Typst 章节。目录导航、
各阶段输入/输出与推荐阅读路径见 [`docs/design/README.md`](docs/design/README.md)。
目录只表示维护责任；规范优先级仍由唯一入口中的 include 顺序决定。

[`examples/spec/`](examples/spec/) 是重新整理的 source-first accept/reject 样例集；
仓库尚无 Cire 编译器，因此它当前记录预期 source shape 与 stable diagnostic，
不冒充可执行 conformance runner。

构建设计文档：

```sh
typst compile docs/cire-lang-design.typ
```

本 README 只是项目入口，不定义语言语义。
