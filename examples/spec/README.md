# Cire-v1.0 source examples

这里保存一组小而自包含的 Cire-v1.0 源码样例，用来说明
[`docs/cire-lang-design.typ`](../../docs/cire-lang-design.typ) 冻结的表面形状与错误边界。

- `accept/` 中的文件记录应被接受的源码形状。
- `reject/` 中的文件各自隔离一个稳定诊断；首部的 `expect` 给出诊断 ID。
- 除 temporal 样例明确标注的 sealed prelude 外，每个文件都声明自己使用的
  ability、effect 与 nominal type。

本仓库目前没有 Cire 编译器，因此这些文件不是可执行 conformance gate，也没有
Python/JSON 模型替代编译器做语义判断。未来的 runner 应直接把每个 `.cire` 文件交给
真实编译器，并按目录与 `expect` 检查结果。

当前集合覆盖 ordinary data/call/trait、四种 operation mode、handler、named
capability、effect row、associated item、closed secondary row、temporal `Next`，
以及与这些构造相邻的九个稳定拒绝边界。
