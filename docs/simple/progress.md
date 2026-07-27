# Cire 实现设计与进度

更新基线：2026-07-27。

## 编译器怎么分层

```text
源码
  → lossless lexer
  → 手写 PEG parser
  → lossless CST + diagnostics
  → Surface HIR
  → 去糖后的 Kernel HIR
  → 名字解析、类型/effect/capture 检查
  → Wasm 后端
```

LSP 不会另写一套 parser 和类型系统。它将直接复用同一份 snapshot、
diagnostic、resolver 和 type query。

## 现在已经完成

- 带 revision 的不可变源码快照、UTF-16 range、行列索引和 edit 校验；
- 可序列化 diagnostic、fix，以及通用 trace 数据结构和 sink；
- 保留空白、换行和注释的 lossless lexer；
- 自己编写的 token-oriented PEG parser 基础；
- ordered choice、lookahead、局部 cut、最远失败和错误恢复；
- lossless CST、missing token、error node 和确定性 JSON/S-expression；
- effect、operation mode、函数签名、类型和 effect row；
- 旧单列表 `A`、`Fx : Effect`、`Eff : EffectRow` 与 `app : Fx` 的
  parser baseline；
- `{app}` 与错误写法 `Read[app]` 的定向修复；
- call、method、labelled argument、trailing lambda、handler 和 `with`；
- `reparse` correctness baseline：先校验 revision/edit，再保证结果等价于完整重解析。

Parser 还没有发出 trace event。当前基线在 MoonBit 的 wasm、wasm-gc、
JavaScript 和 native target 上各有 74 项测试，全部通过。

## 现在能做什么

给 parser 一段源码，它可以：

1. 产生保留全部原文的 token 和 CST；
2. 遇到错误时插入 missing token 或 error node，然后继续解析；
3. 返回机器可读、带 source range 和 fix 的诊断；
4. 把 snapshot 序列化，方便测试、日志和以后接 LSP；
5. 校验一次 edit 的 revision 后重新解析；测试会把结果和从头解析作比较。

## 现在还不能做什么

- 还不能完成名字解析、类型检查或 effect row 推导；
- 还不能解析最新设计的双泛型列表 `[...]![...]`、`ability`、`cap`、
  associated effect/row、row formula 或 `fresh`；
- 还不能验证 generic parameter 的 `Type`/`Effect`/`EffectRow` kind；
- 还不能检查 capture、Region、Owner 和 continuation safety；
- 还没有 Surface HIR、Kernel HIR 和正式的语法糖展开；
- 还没有完整的 `let`、`if`、`match`、pattern、ADT 和运算符优先级语法；
- `reparse` 还允许 full fallback，没有真正复用 subtree；
- 还没有 formatter、LSP、解释器、运行时和 Wasm code generation；
- 还不能编译并运行一个完整 Cire 程序。

## 为什么先做序列化和错误恢复

Parser 不只是给命令行编译器使用。以后编辑器会不断发送不完整代码和小编辑。
如果 snapshot、range、diagnostic、fix 和 revision 一开始不统一，LSP 和增量
编译就会被迫复制另一套逻辑。

所以当前顺序是先把“数据边界和错误行为”做稳定，再扩大语法覆盖。

## 接下来的实现顺序

1. 补齐常用表达式、声明、pattern 和优先级；
2. 建立 typed CST view、Surface HIR 和 Kernel HIR；
3. 在语法继续细化后实现双列表、ability constraint，再进入 generic kind
   checking、名字解析、类型推导和 effect row；
4. 一次性建立一致的 capture、Region、Owner 和 continuation safety 规则；
5. 加入 query cache、reparse island、subtree reuse 和 cancellation；
6. 让 CLI、测试和 LSP 复用同一个 compiler workspace API；
7. 再进入运行时与 Wasm 后端。

## 还需要讨论的语法

比较重要但尚未完全冻结的部分：

- 换行、分号和独立 block 的完整规则；
- 运算符优先级和用户是否能定义运算符；
- tuple、record、array、index 和 update 的具体形状；
- `let`、`if`、`match`、loop 与完整 pattern；
- module、import、visibility 和 package-qualified name 的细节；
- handler forwarding 和未覆盖 operation 的最终写法；
- stable lexical site 给 UI/增量库使用时的表面接口；
- 部分便捷写法究竟是核心语法、普通语法糖，还是第一方库 API。

更完整的状态表在[编译器前端架构](../compiler-architecture.md#11-parser-first-implementation-plan)，
具体语法依据在[表面语法工作规范](../surface-syntax.md)。
多态新设计在[多态与 effect abstraction 工作设计](../polymorphism-design.md)。
