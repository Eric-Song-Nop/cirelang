#import "../shared.typ": *

=== Handler、resumption 与 `with` <surface-a-9>

```peg
HandlerExpr       <- HANDLER Type HandlerBody
HandlerBody       <- LBRACE HandlerMember* RBRACE
HandlerMember     <- ReturnClause / HandlerClause
HandlerClause     <- Mode LowerIdent ClausePatternList
                     ContinuationBinder? FAT_ARROW Expr
                     (COMMA / SEMICOLON)?
ClausePatternList <- LPAREN PatternList? RPAREN
ContinuationBinder <- AS LowerIdent
ReturnClause      <- RETURN LPAREN Pattern RPAREN FAT_ARROW Expr
                     (COMMA / SEMICOLON)?

WithExpr          <- WithEntry+ IN Expr
WithEntry         <- WITH WithOperand (AS LowerIdent)?
WithOperand       <- &InlineHandlerStart InlineHandlerOperand
                   / &MissingModeClauseWitness MissingModeInlineRecovery
                   / WithOperandExpr
WithOperandExpr   <- WithOperandAssignExpr
WithOperandAssignExpr <- WithOperandLogicOrExpr
                         (EQUAL WithOperandAssignExpr)?
WithOperandLogicOrExpr <- WithOperandLogicAndExpr
                          (OROR WithOperandLogicAndExpr)*
WithOperandLogicAndExpr <- WithOperandEqualityExpr
                           (ANDAND WithOperandEqualityExpr)*
WithOperandEqualityExpr <- WithOperandCompareExpr
                           ((EQEQ / NEQ) WithOperandCompareExpr)?
WithOperandCompareExpr <- WithOperandAddExpr
                          ((LT / LE / GT / GE) WithOperandAddExpr)?
WithOperandAddExpr <- WithOperandMulExpr
                      ((PLUS / MINUS) WithOperandMulExpr)*
WithOperandMulExpr <- WithOperandPrefixExpr
                      ((STAR / SLASH / PERCENT) WithOperandPrefixExpr)*
WithOperandPrefixExpr <- (BANG / MINUS) WithOperandPrefixExpr
                       / WithOperandPostfixExpr
WithOperandPostfixExpr <- NonWithPrimaryExpr PostfixPart*
InlineHandlerOperand <- Type LBRACE HandlerMember+ RBRACE
InlineHandlerStart <- Type LBRACE
                      (OperationClauseStart / ReturnClauseStart)
OperationClauseStart <- Mode LowerIdent ClausePatternList
                         ContinuationBinder? FAT_ARROW
ReturnClauseStart <- RETURN LPAREN Pattern RPAREN FAT_ARROW
MissingModeInlineRecovery <- Type LBRACE MissingModeClause
                              HandlerMember* RBRACE
MissingModeClause <- LowerIdent ClausePatternList ContinuationBinder?
                     FAT_ARROW Expr (COMMA / SEMICOLON)?
MissingModeClauseWitness <- Type LBRACE LowerIdent ClausePatternList
                             ContinuationBinder? FAT_ARROW
```

`ClausePatternList` 使用 pattern，不复用 declaration `ParamList`。
`as k` 只允许在 `once` / `ctl` clause。Surface 允许省略 `return`；
elaboration 必须先合成 `return(value) => value`，然后 Core exactness 才检查
“恰好一个 return、每个 operation 恰好一个 clause、无 extra/duplicate”。

`k.resume(value)` 与 `k.finalize()` 由 resolver 降为 resumption primitive。
`k.discontinue(error)` 不属于本 profile。

Inline branch只有完整 lookahead（含 `RPAREN`、optional continuation binder与
`FAT_ARROW`）成功后才 commit。合法 branch复用同一 `HandlerMember`；missing-mode
witness只产生一个 `handler-clause-mode-required`。空/comment-only body、typed
record、普通 trailing lambda与不完整首 clause都走 ordinary `Expr` fallback。

第一方 completion source 的普通 method spelling
`source.park(k, under = owner)` 由 resolver/type checker在 sealed evidence
下降为 Core `park(source, owner, k)`。它产生
`Transfers(ParkContractV2)` 并终止当前 path，不返回 `Unit`。source/port的
payload必须精确等于 operation result `A`；保存的完整 resumption再执行
`A -> B` answer transform。普通用户 method、
closure 或容器不能伪造该 lowering，也不能把 raw `Resume` 捕获进 host
callback。

`WithOperand` 使用 terminator-aware expression flavor：它允许 operand 内部的
call、trailing lambda、`if`、`match` 和带括号的 nested `with`，但在当前
chain 深度的下一 `with`、binder `as` 或最终 `in` 前停止。较早 entry 的
`as` binder 对后续 operand 和 body 可见，不在自己的 operand 中可见。

Normalize先展开 inline handler，再合成 omitted return，再将 chain right-fold；
没有第二套 clause semantics或 Core/wire node。

`with` 先保留有序 `ScopedApply`。只有 handler evidence 才允许 `as binder`
并降为
`freshprompt p in handle[p,h,ι](let binder=capref(ι); body)`；匿名 handler
省略 term binder但仍有 fresh prompt。普通 transformer降为普通 thunk call。

=== Temporal surface <surface-a-10>

```peg
DelayTail         <- LBRACKET LowerIdent RBRACKET &LBRACE
DelayExpr         <- "delay" &DelayTail CUT
                     LBRACKET LowerIdent RBRACKET Block
```

- `delay[frame] { e }` 是 dedicated temporal expression；
- `advance(e)` 保持普通 call，只有 sealed prelude binding 才降为 intrinsic；
- `Next[frame,A]` 保持普通 type application CST，由 kind checker 重分类；
- `resumes next` 和 `may_suspend` 只出现在 operation contract；
- handler 与 `Next` 不默认交换，相关 evidence 属于静态语义而非 grammar。

Cire-v1.0 不增加 existential/rank-2 grammar。Clock package只通过三个 sealed
first-party package-qualified value进入 surface：

```cire
let packed = @temporal::pack_next(under = owner) { frame =>
  delay[frame] { 42 }
}

let value = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

let close = @temporal::dispose(packed)
```

三者使用现有 `QualifiedName`、labelled argument与 trailing-lambda CST；只有
resolver确认 exact sealed origin时才产生 contextual HIR。builder/open block
不是普通 first-class callback type：前者获得 fresh FrameClock，后者只在
lexical scope内获得 raw `frame` 与 surface `Next[frame,A]`；hidden Later
contract $L$ 只存在于 Core/interface，不能在 source type中拼写。
`PackedNext[A]` 是 copyable shared handle；hidden storage Owner不进入 source
type arguments。`try_with_packed_next` 的
Closing/Closed path显式返回 `None`，成功 body的 Returns映射为 `Some`，而
安全的 Aborts/Transfers在完整 identity-nonescape后 exactly-once release并
保持 terminal tag。普通同名函数不享有这些 binder或 lowering。
`dispose` 精确返回 `CloseReceipt[DisposeReport]`；repeated request共享 identity，
receipt只有 `CloseReceipt::await` 这个 Async/MaySuspend observer operation。

=== Syntax validation 与静态语义边界 <surface-a-11>

Parser 必须产出 lossless CST；下列检查在 syntax validation/resolver/type
checker 中完成：

- identifier kind、visibility 适用范围和 duplicate declaration；
- 每个单独 introduction list 中 source binder name injective：`TypeParams`、atomic/
  constructor Effect params、row binders、callable/operation/lambda parameters 与每个 pattern binder set都拒绝
  duplicate；nested lexical scope可以按普通 shadowing 规则重用外层名称；
- type/effect/row binder domain 与 kind；
- ability conformance、associated binding/kind/default exactness；
- only-`Lacks` row predicate profile check，以及 ability-target independent
  `impl` profile check；
- package-instance/name/visibility/import resolution，ordinary trait orphan/overlap/
  associated normalization、inherent/trait/extension unique lookup与 UFCS；
- primitive literal/range/conversion、byte/interpolation/Show、local generalization与
  explicit named-function boundary；
- nominal constructor/update/default/privacy/derive、pattern binder exactness、
  irrefutability、or-pattern binder equality、match exhaustiveness/usefulness；
- assignment place/mutable escape/replay、label matching、default prologue、final-formal
  trailing lambda 和 generic arity；
- operation contract、mode refinement、handler clause exactness；
- named capability identity、row removal、capture/escape；
- one-shot disposition、multi-shot replay/fork 和 Owner transfer；
- temporal clock identity、phase authority 和 storage boundary；
- PackedNext sealed origin、shared lease state、完整 path nonescape/release；
- ConstSafe/termination、ProtocolPure、ComponentSafe/borrow nonescape/host authority；
- exact `IntrinsicRegistryRootV1` identity、callback scheme/evidence、Resource input
  cursor、Task/receipt waiter、UI generation/action-payload/occurrence lease constraints。

Parser recovery 可以插入 missing token 或 error node，但恢复结果不能成为语言
语义。`examples/spec/` 是重新写过的 source-first Cire-v1.0 accept/reject 样例集；
仓库尚无 compiler，所以这些样例目前固定 source shape 与 stable diagnostic expectation，
不能冒充 parser-executed conformance proof。

=== Diagnostic ownership、origin 与 acceptance boundary <surface-a-12>

External artifact先 exact Decode，成功后才进入 ContractWF。Source causal cluster的
precedence固定：

```text
Lex > Parse > Syntax > Resolve > Kind > Type > Row > HandlerWF
    > Flow > Capture > Usage > World > Phase > Owner > ContractWF
```

同一 cluster后续发现只作 secondary note。Successor diagnostic registry每项精确保存
`id/stage/causal_cluster/primary_origin_role/required_notes/fix_safety`；CLI/LSP必须
一致且不得泄漏 host exception。

#metadata("R06-origin-arena") <rule-r06-origin-arena>

Origin arena是 frontend authority拥有的 closed contract；它不是实现可选的 debug
metadata：

```text
OriginId = u32  // exact index in ElaborationOriginMapV1.nodes
DirectOriginId = OriginId
  where nodes[OriginId].node_kind == "DirectV1"

ElaborationOriginV1 =
  {
    node_kind: "DirectV1",
    file_id: String,
    subject: String,
    source_digest: "sha256:" + 64 lowercase hex,
    utf8_range: { start: u32, end: u32 },
    utf16_range: { start: u32, end: u32 }
  }
| {
    node_kind: "DerivedV1",
    derivation_kind: DerivedKindV1,
    anchor: DirectOriginId,
    parents: [{ role: OriginRoleV1, target: u32 }],
    ordinal: u32
  }

DerivedKindV1 =
    "TrailingLambdaArgumentV1"
  | "InlineHandlerExpansionV1"
  | "ImplicitHandlerReturnV1"
  | "SourceOrderTemporaryV1"
  | "CallEntryTupleV1"
  | "DefaultPrologueV1"
  | "ParameterTupleV1"
  | "WithRightFoldV1"
  | "FreshPromptV1"
  | "FreshCapabilityV1"
  | "HiddenTailResumeV1"
  | "HiddenFinalizeV1"
  | "SealedIntrinsicV1"

OriginRoleV1 =
    "PrincipalV1" | "ArgumentV1" | "DeclarationV1" | "SynthesisBasisV1"

ElaborationOriginMapV1 = {
  artifact: "ElaborationOriginMapV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  nodes: [ElaborationOriginV1 in OriginId order],
  sites: [{ site_id: CanonicalSiteIdV1, origin_id: u32 }]
}

CanonicalSiteIdV1 = {
  root_binding_slot: u32,
  kernel_node_preorder: u32,
  role: OriginRoleV1,
  field_path: [u32]
}
```

`DerivedKindV1` 与 `OriginRoleV1` 的 enum order严格等于上列出现顺序，不按
literal string 的 lexical order 重排。
所有 object exact-field；unknown field/tag、duplicate edge、out-of-range ID/range、
非 Direct anchor、非 canonical order均稳定 Decode拒绝。`file_id` 是 NFC、`/`
分隔的 module-relative POSIX path；禁止 absolute prefix、空 segment、`.`、`..`、
`:` 与 control character。`source_digest`绑定 parser输入的原始 strict-UTF-8 bytes；
BOM拒绝，不做 newline或 whole-file NFC rewrite。UTF-8 byte与 UTF-16 code-unit
range均为半开区间，显式要求 `start <= end`，落在 code-point boundary并可从
同 digest内容双向换算。`OriginId` 的 wire lexical encoding 是 JSON u32，且必须恰为
`nodes` array index；`DirectOriginId` 还必须指向 `node_kind == "DirectV1"` 的 entry。

`subject` 是 resolver分配的 `CanonicalSubjectV1`：named declaration/member使用
NFC lexical export path；unnamed Direct site使用
`<nearest-named-subject>#direct@<normalized-HIR-preorder-u32>`；shadowed local
binder在 path尾部增加 `@<canonical-binder-slot>`。Semantic string sort按 NFC
UTF-8 bytes，integer按 unsigned numeric ascending，tuple逐 element；JCS object
property仍按 RFC 8785 UTF-16 code-unit order，二者不可混用。

Canonical allocation是总函数：

+ Direct node按
   `(file_id,source_digest,utf8_start,utf8_end,utf16_start,utf16_end,subject)`
   去重、lexicographic sort，从 0 连续分配 ID。
+ 在 producer临时 graph先 cycle-check并算 depth：Direct=0；Derived的 anchor必须
   是 depth-0 Direct，node depth为 `1 + max(0,parent depths)`。一个 normalized-HIR
   node对同一 `(anchor,derivation_kind)` 至多产生一个 occurrence；occurrence按
   `(anchor canonical key,kind order,normalized-HIR preorder)`排序，并在每个
   `(anchor,kind)`内从 0 连续分配 ordinal。
+ Derived按 depth递增处理；该层 edge按 `(role order,target-id)` exact sort，node按
   `(depth,anchor-id,kind order,ordinal,edge-vector)`排序并连续分配 ID。每个 parent
   必须有更小 depth/ID；只有完整 structural tuple相等才可去重。Object address、
   random ID、hash/map traversal order不得参与。

`root_binding_slot`按 normalized-HIR preorder连续分配；每个 root内
`kernel_node_preorder`连续分配；`field_path`按 exact Kernel schema field order及
list index形成 numeric path（principal node为空）。`sites`按
`(root_binding_slot,kernel_node_preorder,role order,field_path)` exact sort，site ID
不得重复，origin ID必须在 `nodes`内。完整 object先递归 NFC再 RFC 8785/JCS；
semantic Char/String/Bytes value本身按 scalar/byte encoding保存，不能被 NFC改值。

向既有 `SourceOriginV1=file:subject` 的投影同样唯一。Direct使用自己的
`file_id/subject`；Derived使用 anchor Direct的 `file_id`，subject是
`<anchor-subject>#<lower-kebab-kind-tag>@<ordinal>`。13个 tag依 enum order为
`trailing-lambda-argument`, `inline-handler-expansion`,
`implicit-handler-return`, `source-order-temporary`, `call-entry-tuple`,
`default-prologue`, `parameter-tuple`, `with-right-fold`, `fresh-prompt`,
`fresh-capability`, `hidden-tail-resume`, `hidden-finalize`, `sealed-intrinsic`。
两部分各自把不在 `[A-Za-z0-9._/@#-]` 的 UTF-8 byte做 uppercase `%HH`
encoding，再以唯一未编码 `:` 连接；ordinal是无 `+`、无 leading zero的 ASCII
decimal。每个 wire site只投影其 `sites` entry，不沿 parent猜 primary。

Foundation-derived mapping固定为：interpolation/finally/derive →
`SealedIntrinsicV1`；while/for、numeric trap checks、place/assignment temporaries →
`SourceOrderTemporaryV1`；Component adapter由 manifest origin拥有，不伪造 source
DAG node。Core alpha-equivalence下，binder slot按 normalized-HIR preorder分配；
同一 source node产生多个 binder时按 origin ordinal。Public parameter label是 ABI
string，不是 alpha-renamable binder。

Accepted program必须沿同一 frontend snapshot产生 lossless CST、resolved identity、
normalized Surface、signature/kind evidence与 Kernel；不能只有 parser accept。当前仓库
的 v1 source examples只记录设计形状与 representative boundaries；在真实
frontend/checker存在前，它们不构成 parser、typechecker或 runtime conformance evidence。
