# Cire

Cire 是一门正在设计中的通用编程语言。它面向 WebAssembly，并把类型化
代数效应、受控续体、具名 capability 和 temporal/Owner safety 作为核心能力。

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及具名 capability 为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

当前仓库是**纯设计仓库**，不包含编译器、运行时、标准库实现或旧工具链模板。
语言设计统一采用版本化基线
[`Cire-TR₀/2026-07-31`](docs/spec-status.md)：形式化规范定义语言，未来 parser
和测试必须服从规范，不能反向决定语言。

想从零学习语言，请按顺序阅读
[Cire 语言教程](docs/tutorial/README.md)；想快速了解项目，可以看
[Cire 简明文档](docs/simple/README.md)；需要完整设计依据时，再看
[设计文档索引](docs/README.md)。
