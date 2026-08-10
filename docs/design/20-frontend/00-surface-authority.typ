#import "../shared.typ": *

= Surface grammar authority import <surface-authority-import>

#status(
  [唯一 grammar authority],
  [
    `Cire-v1.0` 的 token、lexer mode、PEG、precedence、CUT、CST 与 recovery ownership
    全部由本入口前面的 `Cire-v1.0` surface 章节定义。Core 章节不再包含第二个 PEG
    judgment或历史 recognizer；producer、LSP与 conformance tooling只能消费该
    canonical surface authority 产生的 normalized HIR。
  ],
)

本文的 parser boundary 只有一个输入 predicate：

```text
CanonicalSurfaceV1(profile, surface_hash, normalized_hir_hash, node)
```

它成立当且仅当 `profile == "Cire-v1.0"`，`surface_hash` 指向 exact-decode、NFC、JCS
后通过 hash 验证的唯一 surface authority artifact，`normalized_hir_hash` 指向该 artifact
按 closed normalization schema 生成的 HIR，并且 `node` 是该 HIR 的可达 node。
Parser recovery node、legacy spelling 或未进入 normalized HIR 的 token sequence 不产生 semantic
judgment。本文所有写成 `SurfaceV1(node)` 的 premise 都是这个 predicate 的缩写。

= Canonical surface fragment 与 temporal delta

== Calculus 使用的 canonical grammar import

本 calculus 不复制第二份 PEG。它按 profile id `Cire-v1.0` 消费本入口 surface
章节的 token/rule table、normalized Surface HIR 与已经生成的
evidence-indexed Kernel，并只定义后两者的消费/WF judgment；下列旧 TR0 node 名只作为
temporal 子集的兼容索引：

```text
Declaration, GenericClauses, Type, RowExpr, FunctionDecl, OperationDecl,
LambdaExpr, CallArguments, HandlerExpr, HandlerClause, ReturnClause,
WithExpr, DelayExpr, Block
```

因此 `GenericClauses` 的非空分支、`fn(value)` 的 inferred
`LambdaParameter`、label-first lookahead、`RowUnion` 和 single-final-tail
约束都由同一 canonical grammar裁决。形式化中的
`SurfaceV1(profile,node)` premise表示 node必须来自该 rule table；本文
没有第二个 recognizer，也没有“只比较成功语言”的兼容后门。

== 目标 temporal surface

`CAP`、`RESUMES`、`NEXT` 与 `MAY_SUSPEND` 是 canonical keyword token，
不是 contextual `LowerIdent`。`delay`、`advance` 与 `Next` 保持 canonical
grammar规定的 sealed prelude name：Surface resolver只有在完整 intrinsic
shape/evidence成立时才产生 `DelayExpr`、`advance` Kernel node 与 hidden
`Next[i,A,L]` contract；Formal只验证这些已产生节点的 typed-Core WF。这个
Surface resolver delta不修改 token language。

`advance(e)` 保持普通 call grammar。Resolver 只在 callee 绑定到 sealed
prelude intrinsic 时降为 Core `advance`；同名用户函数仍是普通函数。

`Next[frame, A]` 被识别为普通 type application。
Surface 的 Kind/lowering boundary只对 sealed `Next` constructor把首个 lower-name
argument重分类为 capability identity；Formal消费该 identity evidence，这不是一般
dependent type。

历史 `cap FrameClock` 在 `Cire-v1.0` 稳定拒绝。Direct parameter `frame : FrameClock`
由 Surface signature/elaboration创建 restricted singleton identity quantifier；普通 value
parameter `c : Capability[FrameClock]` 不引入 identity。Formal只核对已产生 binder与对应
row/type projection。`Next` 只供 Surface resolver识别 sealed constructor，不另建 parser branch。

== Profile boundary

#warning([
  `Cire-v1.0` 只接受 canonical `with ... in ...` chain，不接受历史
  `with operand { block }` 形状。实现若需要迁移诊断，应把 legacy token
  sequence作为拒绝 case，而不是并行的语言 profile。
])

下文为陈述 temporal rules 使用 `DelayExpr`、`OperationContractV1`、
`ResumeTransitionV1`、`SuspensionSummaryV1` 与 `WithChainV1` 等说明性 HIR role；
它们只是对 canonical normalized Surface HIR field 的短名，不是新增 CST production或
第二套 parser schema。`Next` 仍由 canonical type application resolve，`advance` 仍由
canonical call resolve；只有 exact sealed identity/evidence使 Surface生成专用 Kernel node，
Formal仅接受并解释该 node。
