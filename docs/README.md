# 设计文档索引

这组文档记录了从代数效应、增量计算和响应式 UI 设计中反推出来的语言需求。
[表面语法工作规范](surface-syntax.md)中的“已决定”是稳定设计约束，“工作形式”
是可继续细化的目标语法，不保证当前 parser 已经支持。实现状态以
[编译器前端架构](compiler-architecture.md)和简明进度文档为准；其他文档中的
旧示例若与表面规范冲突，以该规范为准。

第一次了解 Cire，可以先看篇幅更短的 [Cire 简明文档](simple/README.md)。
多态、effect ability 与 named capability 的新工作设计见
[多态与 effect abstraction 工作设计](polymorphism-design.md)。该文档记录
双泛型列表基线，也明确区分已接受方向、开放语法和尚未实现的部分。

## 建议阅读顺序

1. [语言定位与特性总览](language-overview.md)
2. [表面语法工作规范](surface-syntax.md)
3. [多态与 effect abstraction 工作设计](polymorphism-design.md)
4. [代数效应与恢复模式](effects-and-resumptions.md)
5. [Owner、Region、capture set 与结构化清理](lifetimes-and-finalization.md)
6. [编译器前端架构](compiler-architecture.md)
7. [第一方增量计算库](incremental-computation.md)
8. [第一方响应式 UI 框架](reactive-ui.md)
9. [WebAssembly 与宿主互操作](webassembly-and-host-interop.md)
10. [Kokaine 案例研究](kokaine-case-study.md)
11. [相关语言与设计先例](prior-art.md)
12. [开放问题与原型验证计划](open-questions.md)

## 结论状态

文档使用以下标签：

- **已决定**：当前讨论已经明确接受，后续设计应以此为约束。
- **设计方向**：有充分理由采用，但仍需通过类型规则或运行时原型验证。
- **工作形式**：可以先进入 parser、formatter 与测试，但在形成兼容性承诺前仍可调整。
- **开放问题**：尚未决定，不能被下游设计当作事实。
- **不采用**：讨论过但已明确排除，或不应成为语言核心。

## 一句话词汇表

| 术语 | 回答的问题 |
|---|---|
| Effect row | 运行这段计算时，可能向上下文请求什么操作？ |
| Named capability | 请求的是哪个具体 handler、状态域或宿主实例？ |
| Resumption mode | handler 可以让操作之后的程序运行几次、以何种方式运行？ |
| Capture set | 一个闭包或续体已经随身带着哪些具体能力和 region？ |
| Owner | 运行时谁负责一组任务、续体、资源与清理动作的生死？ |
| Region | Owner 或局部能力在类型系统中的生成式身份。 |
| Generation | 某个运行时身份的哪一次 incarnation 或候选求值仍然有效？ |
| Continuation cut | 一次读取把直接风格程序切成已完成前缀与可恢复后缀的位置。 |
| Stable name/key | 新旧两轮执行中的对象是否是同一个逻辑对象？ |
| Structured finalization | 续体被恢复、放弃、取消或转交时，清理责任如何确定地移动和结束？ |
| Surface HIR | 保留 `with`、trailing lambda 等用户写法的语义树。 |
| Kernel HIR | 糖展开后供 resolver、类型检查与后端共同使用的少量核心构造。 |
