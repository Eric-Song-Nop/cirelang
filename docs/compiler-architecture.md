# 编译器前端架构

> **Future architecture:** [`Cire-TR₀/2026-07-31`](spec-status.md)。仓库当前
> 没有编译器实现；本文规定未来实现怎样服从规范，而不是记录已完成代码。

## 1. 目标

编译器前端从第一天起同时服务：

- 命令行编译；
- parser 与类型系统的 golden/property test；
- 结构化编译日志；
- 机器可读错误报告；
- 增量编译；
- Cire 自己的 LSP server；
- 后续解释器、Wasm backend 与工具链。

因此 parser 不能是“读入字符串，失败就打印一行错误”的一次性函数。前端的基本产物是带 revision、可序列化、可恢复、可增量查询的 immutable snapshot。

## 2. 分层

```text
Workspace / SourceDb
  └─ SourceSnapshot + TextEdit + LineIndex
      └─ lossless lexer
          └─ TokenSnapshot
              └─ handwritten PEG parser
                  └─ lossless CST + parse diagnostics
                      └─ syntax lowering
                          └─ Surface HIR
                              └─ sugar elaboration
                                  └─ Kernel HIR
                                      └─ resolver
                                          └─ Resolved HIR
                                              └─ type/effect/capture checking
                                                  └─ Typed HIR / Core
```

每层只依赖前一层的稳定接口：

- CST 保留用户写了什么；
- Surface HIR 表达用户想写的构造；
- Kernel HIR 消除 `with`、trailing lambda 等糖；
- Resolved HIR 绑定 package、type、value、effect 与 capability identity；
- Typed HIR/Core 保存 effect row、resumption mode、capture dependency、
  capability binding scope 与 elaboration evidence。

Formatter 使用 CST，不格式化反糖后的 HIR。LSP 的 syntax feature 可以只依赖 CST；hover、definition、rename 等 semantic feature 复用 resolver/typechecker query。

## 3. Source model

### 3.1 Immutable snapshot

一个编译请求固定观察一个 workspace revision：

```text
WorkspaceSnapshot
  revision : WorkspaceRevision
  files : Map[SourceId, SourceSnapshot]
  package_graph
  compiler_options
```

`SourceSnapshot` 至少保存：

```text
SourceId
normalized logical path
revision : SourceRevision
validated Unicode source text
content hash
LineIndex
```

`SourceId` 只在一个 workspace session 内有效。`SourceRevision` 只描述单个
文件的不可变版本；`WorkspaceRevision` 固定一次跨文件查询看到的整体状态。
三者不能复用同一个裸 `Revision` 类型。持久 artifact 不序列化
session-local `SourceId`，而使用 normalized path、`SourceRevision` 与
versioned content hash 标识内容。

MoonBit 的 `String` 与 LSP 的默认 position encoding 都以 UTF-16 code unit
计数。编译器内部因此统一使用 UTF-16 code-unit offset 的半开区间
`[start, end)`：

- `String::length()`、lexer cursor、token range、CST range 与 `TextEdit`
  使用同一单位；
- `LineIndex` 保存每一行的 UTF-16 起始与内容结束 offset，统一处理
  LF、CRLF 与 lone CR；
- LSP UTF-16 position 可以直接映射；
- CLI renderer、采用其他 position encoding 的 LSP client，以及需要
  UTF-8 byte offset 的宿主接口通过 `LineIndex`/source adapter 转换。

source loader 负责把文件的 UTF-8 bytes 验证并解码成 `String`。非法 UTF-8
属于 load diagnostic；lexer 不接受一个已经静默替换非法序列的字符串。
不得在 lexer、parser、diagnostic renderer 和 LSP 中各自实现一套 offset
换算。

所有 range 必须落在 Unicode scalar boundary 上，不能指向 surrogate pair
中间。扫描器通过 `get_char(cursor)` 取得字符，并按 `Char::utf16_len()`
推进；不能把 `String::iter2()` 返回的字符序号当成 source offset。

机器可读 artifact 必须显式写：

```json
{ "offset_encoding": "utf-16" }
```

这样 offset 单位不会依赖消费者猜测。只有展示层把内部 range 转换为：

- 行/列；
- terminal 中的 Unicode-aware visual column。

### 3.2 Text edit

编辑通过有 revision 前提的 `TextEdit` 表达：

```text
TextEdit {
  file
  expected_revision
  delete : [start, end)
  insert : String
}
```

过期 edit 必须失败或重放到新 snapshot，不能静默应用到不同文本。LSP adapter 负责把客户端 edit 转换为这一统一结构。

## 4. Handwritten PEG parser

### 4.1 为什么是手写 PEG

**已决定**

- 使用 Parsing Expression Grammar；
- parser 由项目自己手写；
- 不维护 EBNF 作为第二份规范；
- 不依赖 parser generator 生成不可控的错误恢复代码。

PEG 的 ordered choice 让 grammar author 明确控制优先级。手写实现则允许 parser 同时控制：

- lossless CST；
- commit/cut；
- contextual expectation；
- error recovery；
- subtree reuse；
- trace event；
- cancellation。

### 4.2 Token-oriented PEG

第一层 lexer 产生包含 trivia 的 token：

```text
Token {
  id
  kind
  range
  text
}
```

Whitespace、newline 与 comment 都平铺为同一 lossless stream 中的普通
trivia token，而不是挂在相邻 token 上的可变数组。PEG cursor 默认观察下一
个 non-trivia token，并在真正消费它时把此前 trivia 一并送入 CST event
stream。Lexer 也必须 deterministic、可恢复，并为非法字符生成 token 与
diagnostic，而不是停止。

Token-oriented PEG 的好处：

- keyword 与 identifier 边界只处理一次；
- comment、换行和 source range 可无损保留；
- incremental relex 可以先按安全窗口重做；
- parser expectation 使用稳定 token kind，而不是任意字符串。

### 4.3 Rule contract

每条 rule 的概念结果为：

```text
RuleResult[T] =
  Matched {
    value : T
    next
    failure_summary
  }
  / Failed {
    furthest
    expected
    contexts
    committed
  }
```

成功分支也携带探索期间的最远失败摘要，因为外层稍后失败时它可能提供最准确的 expectation。

Parser 需要：

- ordered choice；
- positive/negative lookahead；
- repetition，且拒绝对零宽 rule 做无穷 repetition；
- rule label；
- commit/cut；
- selective memoization；
- recursion guard；
- cancellation check。

`cut` 是 parser 内部 primitive，不是 Cire 语言关键字。遇到足以判定构造的 token 后应 commit，例如读到 `effect` 后，不应回退并把整段解释成 expression。

### 4.4 Expression parsing

PEG grammar 不直接写左递归 expression rule。Expression parser 分成：

```text
prefix
primary
postfix loop
precedence-level infix loop
assignment/control expressions
```

postfix loop 统一处理：

- argument list；
- method/field access；
- type argument；
- indexing；
- trailing lambda。

这仍是手写 PEG parser 的一部分：每个入口、ordered choice、lookahead 和 commit 都由同一 parser state 管理，不引入另一棵临时 AST。

### 4.5 Memoization

Packrat memo key 至少包括：

```text
(rule_id, token_offset, parse_mode)
```

第一版只 memoize 容易重复探索或复杂度高的 rule。不能假定“PEG 必须缓存所有 rule”；全量缓存会放大编辑器常驻内存。

缓存项不得捕获 mutable parser 指针。它只保存可重用的 immutable result、failure summary 和所依赖 token slice 的 fingerprint。

## 5. Lossless CST

### 5.1 Tree requirements

CST 必须包含：

- 每个 token；
- comment 和 whitespace trivia；
- delimiter；
- missing token；
- unexpected token；
- error node；
- 用户选择的糖形式；
- 精确 source range。

即使输入不完整：

```moonbit
pub(open) effect Read[A] {
  fun read( ->
```

parser 也返回一棵可遍历的 tree 和一组 diagnostics，而不是 `None`。

### 5.2 Green tree 与 typed view

推荐表示：

```text
GreenToken / GreenNode
  immutable
  parent-free
  content-addressable or fingerprinted

SyntaxNode view
  green node + parent/offset context

Typed CST wrappers
  EffectDeclSyntax
  HandlerExprSyntax
  ...
```

第一版可以不完成 subtree reuse，但公共接口不应暴露只能由 mutable parent pointer 实现的结构。

Node identity 分两类：

- `SyntaxNodeId`：只在一个 snapshot 或被复用的 green subtree 中稳定；
- semantic identity：由 resolver 根据 package、declaration path 与定义来源建立。

不能把 text offset 当作跨编辑永远稳定的声明 identity。

## 6. 错误恢复与诊断

### 6.1 Parser failure 不是 diagnostic

PEG 探索中的失败大多只是 ordered choice 的内部控制流。只有某个构造被 commit、或顶层 rule 确认无法继续时，才把 failure summary 物化为 diagnostic。

这避免把每次失败 lookahead 都报告给用户。

### 6.2 Furthest failure

每个 failure summary 保存：

```text
furthest token offset
expected token/rule labels
context stack
whether committed
```

合并规则：

- 更远位置覆盖更近位置；
- 同一位置合并 expectation；
- 用户可理解的 rule label 优先于内部 helper 名；
- expectation 集合按稳定、人类可读顺序输出；
- 被 commit 排除的 alternative 不再污染 expectation。

不要直接打印“expected 37 alternatives”。Renderer 应归并为如：

```text
expected an operation name or `}`
```

### 6.3 Recovery

Recovery 在已经识别出的语法边界执行：

- top-level declaration：同步到下一个声明 keyword 或 EOF；
- block item：同步到 `;`、换行边界、`}` 或明确 item starter；
- parameter/argument list：同步到 `,`、`)`；
- effect/handler clause：同步到下一个 mode、`return` 或 `}`。

Recovery 产生 `ErrorNode`，并保证每次循环至少消费一个 token。Recovery rule 不得作为普通 ordered-choice 的首选成功分支，否则会掩盖真实 grammar bug。

### 6.4 Diagnostic data model

所有阶段使用同一结构化模型：

```text
Diagnostic {
  code
  stage
  severity
  message
  primary : Label
  secondary : Array[Label]
  notes : Array[String]
  fixes : Array[Fix]
  related : Array[RelatedDiagnostic]
  source_revision
}

Label {
  span
  message
}

Fix {
  title
  applicability
  edits : Array[TextEdit]
}
```

约束：

- diagnostic code 稳定，例如 parser 使用 `Pxxxx`；
- message 可以改善，但 code 不能随措辞变化；
- fix 带 expected revision，防止应用到过期文本；
- parser、CLI 和 LSP 不各自拼装错误字符串；
- primary/secondary span 可以跨文件；
- renderer 不修改 diagnostic 的语义内容。

对 PEG expectation，应优先给局部修复：

```text
missing `]` to close type arguments
`Read[app]` is diagnostic notation; write `{app}` in an effect row
`as k` is only valid on `once` and `ctl` clauses
```

其中后两项可在 syntax lowering/validation 阶段报告，因为 parser 应尽可能保留结构。

## 7. Core 与 sugar elaboration

### 7.1 两棵语义表示

Surface HIR 保留：

```text
WithChain
WithEntry
TrailingLambdaCall
ImplicitReturnClause
Method-shapedDisposition
OwnerScopeCall
```

`WithChain` 的可序列化形状至少保留：

```text
WithChain {
  entries : [WithEntry {
    operand
    capability_binder?
    origin
  }]
  in_origin
  body
  origin
}
```

`with h1 with h2 in body` 是一个含两个 entry 的节点；
`with h1 in with h2 in body` 是两个嵌套节点。CST/HIR 不能因为最终语义相同
就抹掉这个差别，否则 formatter、comment ownership、selection range 和
incremental subtree identity 都会不稳定。

Surface HIR 额外保留 `ScopedApply`；resolver/type checker 取得 operand
evidence 后必须消除它。Kernel HIR 只保留：

```text
Call
Lambda
Handler
FreshPrompt / Handle / CapRef
OperationCall
Resume / Finalize / Park
```

典型展开：

```text
with h in body
  → ScopedApply(h, none, thunk body)

with h as app in body
  → ScopedApply(h, binder app, thunk body)

with h1
with h2
in body
  → ScopedApply(h1, none,
      thunk { ScopedApply(h2, none, thunk body) })

resolver, when h : HandlerTemplate:
  ScopedApply(h, binder app, thunk body)
  → freshprompt p in
      handle[p,h,ι](let app = capref(ι) in body)

resolver, when h is an ordinary transformer:
  ScopedApply(h, none, thunk body)
  → h(fn() { body })

f(args) { body }
  → f(args, fn() { body })

xs.each { x => body }
  → xs.each(fn(x) { body })
```

`WithChain` 在 Surface HIR 中保留扁平 entry、每个 operand/binder 的 origin、
末尾 `in` 和 body origin。结构 lowering 对 entries 做 right fold，先统一
产生 `ScopedApply`，不在未解析类型时猜 operand 类别。Resolver/type checker
取得 evidence 后，匿名普通 wrapper 可以在 Typed HIR/Core 中成为 `Call`；
effect handler 和 fresh capability binder 即使具有普通调用外观，也必须保留
`FreshPrompt`/`Handle`/`CapRef` 语义节点。Kernel 中不存在
`HandlerApply`/`HandlerAction` variant。

### 7.2 Evaluation order

Elaboration 必须显式保持：

- callee 先于 argument 求值；
- 普通 argument 由左到右求值；
- trailing lambda 只构造 closure，不提前执行 body；
- `with` chain 先求值最外层 transformer，再构造包含其余 chain 的 thunk
  并调用它；内层 operand 只在外层调用 action 时求值；
- 外层若零次或多次调用 action，内层 operand 相应地零次或多次求值，不能在
  lowering 时把全部 entry operand 提前到 chain 外；
- fresh capability 只在 action thunk 及允许的 handler scope 中可见。

如果简单 AST rewrite 会复制、删除或重排 effectful expression，必须先引入临时绑定。

### 7.3 Source origin

每个 HIR node 保存：

```text
Origin =
  Direct(SyntaxNodeId)
  / Desugared {
      source : SyntaxNodeId
      kind
      parent_origin
    }
```

没有宏系统不等于不需要 origin map。类型错误应指向用户写的 `with` 或 trailing block，而不是不存在于源码中的合成 `fn()`。

## 8. Serialization-first

### 8.1 原则

在 parser 功能扩展前，先稳定可序列化边界：

- token dump；
- CST dump；
- Surface/Kernel HIR dump；
- diagnostics；
- query/cache event；
- compiler trace。

序列化 DTO 与内部 arena/object 分开。内部可以优化表示，外部 schema 不暴露 pointer、hash table iteration order 或进程随机 ID。

### 8.2 Versioned envelope

所有机器可读 artifact 使用版本化 envelope：

```json
{
  "schema": "cire.parse/1",
  "offset_encoding": "utf-16",
  "compiler": "0.0.0-dev",
  "source": {
    "file": "tests/parser/effect.cire",
    "revision": 3,
    "content_hash": "..."
  },
  "payload": {},
  "diagnostics": []
}
```

要求：

- object field 与数组顺序 deterministic；
- 测试路径规范化为 workspace-relative path；
- 不序列化 wall-clock time、内存地址或随机 hash seed；
- ID 在 schema 中注明作用域，例如 snapshot-local；
- range 统一为 UTF-16 code-unit 的半开区间；
- schema breaking change 增加版本；
- compiler telemetry 与 deterministic test dump 分开。

MoonBit `derive(ToJson, FromJson)` 可以用于内部 snapshot DTO 与
round-trip test，但持久 cache、LSP/debug protocol 的稳定 wire shape
不能直接依赖内部 struct 字段名。稳定协议使用显式 adapter、固定 tag 和
`schema` 版本。默认 `Hash::hash` 也不能用作跨进程 fingerprint；持久 hash
必须由 Cire 固定算法及版本。

第一版使用 JSON，便于 snapshot、diff、CLI 和 LSP 调试。需要性能时可以增加 binary cache format，但不能让 binary arena layout 成为公共协议。

### 8.3 Trace event

编译阶段不直接散落 `println`。统一写入可注入的 `TraceSink`：

```text
CompilerEvent {
  sequence
  workspace_revision
  request_id
  stage
  event
  query_key
  outcome
  parent
}
```

可选 sink：

- no-op；
- deterministic in-memory sink，用于测试；
- JSON Lines sink，用于调试；
- telemetry sink，用于耗时和 cache hit 分析。

耗时、线程号等非确定字段只进入 telemetry，不进入默认 golden dump。

## 9. Incremental compilation

### 9.1 Query boundary

增量单位不是“整个 compiler process”，而是可缓存 query：

```text
lex(file, revision)
parse(file, revision)
lower_surface(file, revision)
elaborate(file, revision)
collect_package_headers(package)
resolve(item)
infer(item)
diagnostics(file, revision)
```

每个 query：

- 输入是 immutable key 与 snapshot；
- 输出是 immutable、可 fingerprint 的 value；
- 记录对其他 query/source 的依赖；
- 不从未声明的全局 mutable state 读取语义信息；
- 支持 cancellation；
- 不把 cancelled result 写入共享 cache。

### 9.2 Parser 增量路线

Parser API 从第一版就接受 previous snapshot 与 edit list：

```text
parse(
  source,
  previous?,
  edits : Array[TextEdit],
  cancel,
) -> ParseSnapshot
```

第一版可以正确地 full relex/full reparse，并忽略 reuse hint；这只是性能基线，不是最终架构。

后续顺序：

1. incremental line index；
2. 从安全 lexical boundary 开始的 token-window relex；
3. unchanged token run 复用；
4. top-level/block reparse island；
5. green subtree reuse；
6. HIR/query fingerprint 复用。

任何增量路径必须满足：

```text
incremental result == from-scratch result
```

比较内容包括 CST 语义结构、token text、diagnostic code/span/fix 和 Kernel HIR；snapshot-local node ID 可以不同。

### 9.3 并发与 cancellation

Workspace snapshot 允许多个只读请求并发。新 edit 到达时：

- 旧 snapshot 仍可供已经开始的请求安全读取；
- LSP 可以取消旧 diagnostics/completion 请求；
- compiler 在 rule/query 边界检查 cancellation；
- 旧请求不得把 diagnostics 发布为新 revision 的结果。

## 10. LSP 复用

LSP server 是 compiler workspace API 的 adapter，不维护第二套 parser、symbol index 或 diagnostic model。

```text
CompilerWorkspace
  open_file
  apply_edits
  snapshot

CompilerSnapshot
  syntax_tree
  diagnostics
  hover
  definition
  references
  completion
  rename
  semantic_tokens
  format
```

接口原则：

- 所有请求显式携带 snapshot/revision；
- syntax-only 请求不强制等待全 package typecheck；
- semantic 请求复用同一 resolver/type query；
- diagnostics 直接映射到 LSP，不重新解析 message；
- rename/fix 返回带 revision 的 `TextEdit`；
- 未完成代码仍有 CST、scope 与 best-effort symbol；
- package graph、文件 overlay 和 disk source 由同一 SourceDb 管理。

CLI、test runner 和 LSP 只选择不同 adapter：

```text
same CompilerSnapshot
  ├─ terminal renderer
  ├─ JSON artifact
  ├─ snapshot test
  └─ LSP protocol objects
```

## 11. Spec-first restart plan

### 11.1 仓库状态与阶段门

仓库当前没有 compiler、runtime、标准库或 LSP implementation。历史代码已经
删除；Git history 可供研究，但不具有 grammar 或架构权威。重新实现按以下
阶段门推进：

| 阶段 | 入口条件 | 交付物 |
|---|---|---|
| S0 profile | `spec-status`、完整 grammar、Core judgments 一致 | versioned profile 与开放参数 registry |
| S1 conformance | surface/Core elaboration规则可引用 | `examples/spec` 正负 corpus + rule id |
| I0 source/lexer | S0/S1 review 完成 | immutable snapshot、UTF-16 span、lossless token stream |
| I1 parser | grammar 无未定义 nonterminal | lossless CST、recovery、from-scratch conformance |
| I2 elaboration | n-ary/label/block/handler lowering已形式化 | Typed CST、Surface HIR、Kernel HIR、origin map |
| I3 checker | versioned obligations/site schema已冻结 | kind/row/Δ/type/world/capture/usage/Owner checker |
| I4 runtime | CBV + Owner/park CAS operational semantics可验证 | handler runtime、completion source/port、Wasm ABI |
| I5 incremental/LSP | correctness oracle已存在 | reparse/query reuse、diagnostics、IDE adapters |

任何 reuse 优化都必须满足 incremental result 与 from-scratch result 等价；
但在 I1 之前不预先承诺旧 parser 的节点形状或兼容行为。

### 11.2 多态与 named capability 的前端表示

目标表面语法把 ordinary generic `[...]` 与 effect generic `![...]` 分开；
effect 列表再用 `F`、`F[_]`、`..E` 的 binder shape 区分 atom、
constructor 与 row。Parser 只负责无损保留这些形状；Typed CST/Surface HIR
应把 binder 降成互不混用的 ID：

```text
GenericParam =
  TypeParam(TypeParamId)
  EffectParam(EffectParamId)
  EffectConstructorParam(EffectConstructorParamId)
  RowParam(RowParamId)

CapabilityBinder {
  id : CapabilityId
  family : EffectAtom
  binding_scope : ScopeId
  origin
}

ConstraintEvidence =
  TypeTrait(TypeTraitId, arguments)
  Ability(AbilityId, arguments, associated_equalities)
  RowPredicate(RowPredicateId, arguments)
```

其中：

- `[A : Eq]` 产生 `TypeParamId` 和普通 trait evidence；
- `![F : Reader[A]]` 产生 `EffectParamId` 和 ability evidence；
- `![F[_] : Reader[_]]` 产生 `EffectConstructorParamId`；
- `![..E : Lacks[Blocking]]` 产生 `RowParamId` 和 row predicate；
- `app : cap F` 或 `as app` 是 term binder，产生 `CapabilityId`，不能复用
  generic parameter ID；
- polymorphic operation 的普通 type parameter 在 handler clause 中以
  fresh skolem 打开，不能按名称与外层 binder 合并。

未来 parser 必须直接识别 canonical grammar。`Fx : Effect` /
`Eff : EffectRow` 等历史 shape 不属于 `TR₀`；若要提供 migration
diagnostic，必须作为明确的 reject fixture，不能进入 Typed HIR。

Effect row 的 typed representation 至少区分：

```text
EffectAtom =
  ConcreteEffect(definition, type_arguments)
  EffectParameter(EffectParamId)

EffectRowEntry =
  Anonymous(EffectAtom)
  Named(CapabilityId, EffectAtom)

EffectRow {
  entries
  tail : RowParamId?
}
```

因此 `{F}`、`{app}` 和 `..E` 在序列化、unification、diagnostic 与 LSP
hover 中始终有不同 tag。`Read[app]` 可以由
`Named(app, ConcreteEffect(Read, ...))` 生成用于诊断，但 parser 不接受它
作为源 row item。

Kind checking 必须早于 effect-row unification：

1. 解析 generic binder 与 scope；
2. 根据普通/effect generic list 与 binder shape 建立初始 kind；
3. resolve 普通 trait、ability、associated argument 和 row predicate；
4. 为 capability term 建立稳定 identity、family 与 binding scope；
5. 做 row normalization/unification、operation resolution 和 handler
   elimination；
6. 最后把 fixed capability dependency 交给统一的 capture/escape checker。

Generalization 也按类别分开：

- `TypeParamId`、`EffectParamId`、`RowParamId` 可以按正式的
  let/top-level generalization 规则量化；
- `CapabilityId` 是 term-indexed identity，普通 let-generalization 不能
  把它提升成任意 capability；
- `with ... as app in ...` 的 fresh identity 在 Kernel HIR 中使用 rank-2 action
  boundary；任何保留 `app` 的值都必须在该 boundary 内消费。

稳定 artifact 不序列化裸整数冒充所有 ID。每种 ID 使用不同 tag，并记录
scope/origin；LSP hover 可以显示：

```text
A   : Type
F   : Effect; ability = Reader[A]
E   : EffectRow; constraints = Lacks[Blocking]
app : cap F; identity = app
```

完整目标与表面/Core 对照见
[多态与 effect abstraction 工作设计](polymorphism-design.md)。

### P0：Serialization shell

交付：

- `SourceId`、`SourceRevision`、`WorkspaceRevision`、`Span`、`TextEdit`；
- deterministic JSON envelope；
- common `Diagnostic`、`Label`、`Fix`；
- `TraceSink`/`CompilerEvent`；
- round-trip 与 golden tests。

通过条件：

- 同一输入重复运行得到 byte-identical deterministic JSON；
- JSON envelope 明确记录 `offset_encoding = "utf-16"`；
- path、ID 和 revision 的作用域清楚；
- CLI renderer 与 JSON renderer 使用同一个 diagnostic value。

### P1：Lossless lexer

交付：

- token kind；
- trivia；
- invalid token；
- token serialization；
- line index；
- lexer diagnostics。

通过条件：

- 拼接 token/trivia 能还原 loader 解码后的原始 source text；
- 非法字符不阻止后续 token；
- Unicode、comment、字符串和 EOF 有边界测试。

### P2：PEG infrastructure

交付：

- ordered choice/lookahead/repetition；
- labelled rule；
- failure summary；
- commit/cut；
- selective memo；
- cancellation；
- parser trace。

通过条件：

- 无零宽 repetition 死循环；
- memo on/off 结果一致；
- expectation 合并 deterministic；
- rule trace 可以序列化。

### P3：Declarations 与 types

优先实现：

- package-level item；
- visibility；
- `struct`、`enum`、`trait`、`effect`；
- square-bracket type parameter/argument；
- function signature；
- effect row；
- error recovery。

### P4：Expressions 与 patterns

优先实现：

- block、literal、name；
- call/method/index；
- lambda；
- trailing lambda；
- `if`、`match`；
- precedence；
- `handler`、多 entry `with ... in ...`、`as k` 与 continuation
  method-shaped syntax。

### P5：Surface → Kernel HIR

交付：

- typed CST view；
- origin-preserving lowering；
- sugar elaboration；
- serialized Surface/Kernel HIR；
- syntax validation diagnostics。

### P6：Incremental/LSP smoke

交付：

- file overlay/edit；
- previous parse API；
- from-scratch equivalence harness；
- syntax diagnostics publication；
- document symbols、folding range、formatting 的最小 LSP path。

## 12. 测试策略

每一层都需要：

- focused unit test；
- JSON snapshot；
- malformed-input recovery test；
- Unicode/span test；
- deterministic-order test；
- cancellation test；
- incremental versus from-scratch differential test。

Parser 额外需要：

- CST lossless round-trip；
- PEG ambiguity/ordered-choice test；
- edit at every token boundary；
- deletion of every required delimiter；
- random token mutation；
- deeply nested input 的 stack/complexity limit；
- diagnostic expectation 与 fix applicability snapshot。

Golden test 应审查结构化 artifact，而不是只比较 pretty-printed AST。Pretty renderer 本身也应有独立 snapshot，防止序列化 schema 被展示格式绑死。

## 13. 架构约束

以下做法从一开始禁止：

- parser 失败即退出；
- parser 内直接打印错误；
- AST 丢弃 comment 与 delimiter 后供 formatter 反推源码；
- 用 text offset 充当跨 revision identity；
- LSP 自己再 parse 一次；
- diagnostics 只保存最终字符串；
- sugar 展开后丢失 source origin；
- cache key 隐式依赖当前工作目录或进程随机状态；
- 为了先跑起来而静默跳过 capability capture safety；
- 引入宏展开阶段来实现 UI DSL。

前端可以先慢，但接口不能把一次性、不可恢复、不可序列化的实现方式固化下来。
