# Cire

Cire 是一门正在设计和实现中的通用编程语言。它的语法尽量接近 MoonBit，
面向 WebAssembly，并把代数效应、受控续体和具名 capability 作为核心能力。

> 一门严格求值、面向 WebAssembly 的通用函数式语言，以类型化代数效应、受控续体以及具名 capability 为核心。增量计算是第一方库，响应式 UI 是旗舰框架；二者都不是语言关键字。

当前仓库已经有 source/diagnostic 基础设施、lossless lexer 和手写 PEG parser。
Parser 能保留原始文本、恢复错误并产生可序列化 CST；类型检查、HIR、
capability capture、Owner 静态规则、Wasm 后端和 LSP 仍待实现。因此它现在
是一个前端原型，还不是可以编译应用的完整工具链。

想快速了解项目，请先读 [Cire 简明文档](docs/simple/README.md)；需要完整设计
依据时，再看 [设计文档索引](docs/README.md)。
