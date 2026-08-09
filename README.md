# Cire

Cire 是一门正在设计中的通用编程语言。它面向 WebAssembly，并把类型化
代数效应、受控续体、具名 capability 和 temporal/Owner safety 作为核心能力。

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及具名 capability 为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

当前仓库是**纯规范仓库**，不包含编译器、生产运行时、标准库或 LSP 实现。
当前设计 profile 是 `Cire-v1.0`。
[`docs/cire-lang-design.typ`](docs/cire-lang-design.typ) 是语言设计的唯一入口，按顺序
组合 `docs/design/surface/` 与 `docs/design/core/` 中的 Typst 章节。章节文件只负责
模块化组织，不是互相竞争的第二份规范。

[`examples/spec/`](examples/spec/) 是重新整理的 source-first accept/reject 样例集；
仓库尚无 Cire 编译器，因此它当前记录预期 source shape 与 stable diagnostic，
不冒充可执行 conformance runner。

构建设计文档：

```sh
typst compile docs/cire-lang-design.typ
```

本 README 只是项目入口，不定义语言语义。
