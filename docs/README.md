# 设计文档索引

这组文档共同实现版本化设计基线
[`Cire-TR₀/2026-07-31`](spec-status.md)。先阅读状态矩阵：它规定文档权威层级、
设计状态、证明状态和实现状态。仓库当前不包含实现；未来 parser、conformance
test 和编译器必须服从规范，不能反向定义语言。

第一次系统学习 Cire，请从分章节的
[Cire 语言教程](tutorial/README.md)开始；只想快速了解当前方向和项目状态，
可以看篇幅更短的 [Cire 简明文档](simple/README.md)。
多态、effect ability 与 named capability 的规则见
[多态与 effect abstraction 设计](polymorphism-design.md)。
Temporal modality、world-indexed resumption 与增量 replacement 的研究设计见
[语法实验和反例审查](temporal-reactivity-design-experiment.md)；对应的
versioned calculus、PEG recognition rules 与算法化检查写在
[Typst 形式化](temporal-reactivity-formalization.typ)中。形式化是当前
canonical semantic baseline，其中的开放参数和证明义务仍保持显式。

## 建议阅读顺序

1. [设计基线与状态矩阵](spec-status.md)
2. [Cire 语言教程](tutorial/README.md)
3. [语言定位与特性总览](language-overview.md)
4. [完整、实现无关的 surface grammar](surface-grammar.md)
5. [表面语法设计说明](surface-syntax.md)
6. [多态与 effect abstraction 设计](polymorphism-design.md)
7. [代数效应与恢复模式](effects-and-resumptions.md)
8. [Named capability、Owner 与结构化清理](capabilities-and-finalization.md)
9. [Cire-TR₀ 形式化与 PEG 语法（Typst）](temporal-reactivity-formalization.typ)
10. [第一方增量计算库](incremental-computation.md)
11. [第一方响应式 UI 框架](reactive-ui.md)
12. [Temporal modality、效应与增量计算：设计实验](temporal-reactivity-design-experiment.md)
13. [WebAssembly 与宿主互操作](webassembly-and-host-interop.md)
14. [未来编译器前端架构](compiler-architecture.md)
15. [Kokaine 案例研究](kokaine-case-study.md)
16. [相关语言与设计先例](prior-art.md)
17. [开放问题与验证计划](open-questions.md)

首批正负规范例子在 [`examples/spec/`](../examples/spec/)。

## 结论状态

文档使用以下标签：

- **Profile baseline**：当前版本中下游可以依赖的设计。
- **工作语法**：已有唯一 grammar/elaboration，拼写仍可调整。
- **参数化**：语义边界固定，但 profile 保留有限候选。
- **开放问题**：尚未决定，不能被下游设计当作事实。
- **第一方契约**：由普通语言和 sealed protocol 提供，不是关键字。
- **证明义务**：已经陈述待证明性质，不表示已有证明。

## 一句话词汇表

| 术语 | 回答的问题 |
|---|---|
| Effect row | 运行这段计算时，可能向上下文请求什么操作？ |
| Named capability | 请求的是哪个具体 handler、状态域或宿主实例？ |
| Resumption mode | handler 可以让操作之后的程序运行几次、以何种方式运行？ |
| Capture analysis | 一个闭包或续体已经随身带着哪些具体 capability？ |
| Owner | 运行时谁负责一组任务、续体、资源与清理动作的生死？ |
| Generation | 某个运行时身份的哪一次 incarnation 或候选求值仍然有效？ |
| Continuation cut | 一次读取把直接风格程序切成已完成前缀与可恢复后缀的位置。 |
| Stable name/key | 新旧两轮执行中的对象是否是同一个逻辑对象？ |
| Structured finalization | 续体被恢复、放弃、取消或转交时，清理责任如何确定地移动和结束？ |
| Surface HIR | 保留 `with`、trailing lambda 等用户写法的语义树。 |
| Kernel HIR | 糖展开后供 resolver、类型检查与后端共同使用的少量核心构造。 |
