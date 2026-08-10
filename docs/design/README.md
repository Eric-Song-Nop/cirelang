# Cire 设计文档导航

[`../cire-lang-design.typ`](../cire-lang-design.typ) 是 `Cire-v1.0` 的唯一规范入口。
本文件只帮助维护者按目标和编译阶段定位内容，不定义新的语言语义，也不改变入口中的
authority 顺序。

## 目录划分

| 目录 | 阶段 / 目标 | 主要内容 | 主要读者 |
| --- | --- | --- | --- |
| `00-overview/` | 范围与 profile | 目标、记号、successor 集成层、结论 | 所有读者、规范维护者 |
| `10-language/` | 源语言设计 | 普通语言、effect row、handler 与 control | 语言用户、语言设计者 |
| `20-frontend/` | 前端 | token、PEG、CST/HIR、resolver、registry、elaboration、diagnostic | parser、LSP、elaborator 作者 |
| `30-static-semantics/` | 静态语义 | typed Core、kinding、typing、temporal/effect/Owner judgments | type-system 与形式化维护者 |
| `40-checker/` | 可执行检查算法 | type checker、终止、interface serialization、实现交接 | 编译器实现者 |
| `50-interfaces/` | 跨包产物与链接 | wire schema、ABI、Component、FunctionContractV3 | linker、artifact validator、package 工具作者 |
| `60-runtime/` | 运行时协议 | cleanup/receipt、PackedNext、Task、Resource、Signal/UI、增量机器 | runtime、标准库、host adapter 作者 |
| `70-assurance/` | 验证目标 | conformance closure、代表性推导、metatheory | reviewer、测试与证明维护者 |
| `90-reference/` | 兼容与保留空间 | legacy exact-decode、reserved extension | importer、迁移与后续 profile 设计者 |

Retained TR0 不等于全部失效：仍被 successor 用作 proof substrate 的规则留在其实际阶段；
只有 profile-disjoint 的旧 wire/import 内容进入 `90-reference/`。`90` 也不表示它能覆盖
前面的 successor 规则。

## 推荐阅读路径

- 语言设计：`00-overview` → `10-language` → `30-static-semantics` → `90-reference/90-reserved-extensions.typ`。
- 编译器前端与类型检查：`00-overview` → `20-frontend` → `30-static-semantics` → `40-checker`。
- 跨包与运行时：`50-interfaces` → `60-runtime`，并回看 `30-static-semantics` 中对应的 safety judgment。
- Review / conformance：入口中的 profile 与 authority → `70-assurance` → [`../../examples/spec/`](../../examples/spec/)。

## Authority 与维护规则

- 文件系统按责任划分；唯一入口中的显式 `#include` 顺序定义规范组合与
  successor-over-retained precedence。不要按目录名自动排序 include。
- `<label>`、`#ref(<label>)` 与 `@label` 是跨文件语义引用；移动章节时保持 label 稳定。
- 章节都位于 `design/` 下一层，并通过 `#import "../shared.typ": *` 共享排版组件。
- 标为 legacy/retained 的段落不能形成 `Cire-v1.0` producer language、public API 或 runtime meaning，
  除非 successor profile 明确 retain。

构建与静态检查：

```sh
typst compile docs/cire-lang-design.typ
tinymist lint docs/cire-lang-design.typ
```

本轮结构调整后的内容一致性审查见
[`70-assurance/2026-08-10-consistency-review.md`](70-assurance/2026-08-10-consistency-review.md)。
