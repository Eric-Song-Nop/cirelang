# Cire

Cire 是一门正在设计中的通用编程语言。它面向 WebAssembly，并把类型化
代数效应、受控续体、具名 capability 和 temporal/Owner safety 作为核心能力。

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及具名 capability 为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

当前仓库是**纯规范与 conformance 仓库**，不包含编译器、运行时或标准库实现。
唯一 authority 顺序、canonical 状态和逐文件 keep/merge/delete 清单见
[`Cire-TR₀/2026-08-01` manifest](docs/spec-status.md)。表面语言由
[`docs/surface-syntax.md`](docs/surface-syntax.md)定义；Core 静态/动态语义由
[`docs/temporal-reactivity-formalization.typ`](docs/temporal-reactivity-formalization.typ)
定义；[`examples/spec/`](examples/spec/)只提供可消费 goldens 与 reference gates。

本 README 只是项目入口，不定义语言语义。
