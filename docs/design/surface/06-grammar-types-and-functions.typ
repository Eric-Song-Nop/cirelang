#import "../shared.typ": *

=== 类型与 effect-row 表达式 <surface-a-4>

```peg
Type                <- GenericFunctionType / FunctionArrowType / TypePrimary
GenericFunctionType <- FN GenericClauses ParamTypeList
                       ARROW Type EffectAnnotation?
FunctionArrowType   <- ParamTypeList ARROW Type EffectAnnotation?
TypePrimary         <- TupleOrGroupedType
                     / TypeReference
TupleOrGroupedType  <- LPAREN TypeList? RPAREN
TypeList            <- Type (COMMA Type)* COMMA?
TypeReference       <- TypeName TypeArgs?

ParamTypeList       <- LPAREN TypeList? RPAREN
EffectAnnotation    <- BANG RowExpr

RowExpr             <- RowUnion
RowUnion            <- RowPrimary (PIPE RowPrimary)*
RowPrimary          <- RowLiteral / RowReference
                     / LPAREN RowExpr RPAREN
RowReference        <- QualifiedName TypeArgs?
RowLiteral          <- LBRACE
                       (InvalidRowLiteralMultipleTails / RowLiteralBody)?
                       RBRACE
RowLiteralBody      <- RowEntry (COMMA RowEntry)*
                       (COMMA RowTail)? COMMA?
                     / RowTail COMMA?
RowEntry            <- LowerIdent / TypeReference
RowTail             <- DOTDOT RowReference
InvalidRowLiteralMultipleTails <- (RowEntry COMMA)* RowTail COMMA
                       DOTDOT CUT RowReference
                       (COMMA RowTail)* COMMA?
```

`GenericFunctionType` 保留一个 lossless CST node，但 accepted occurrence严格受 #ref(<surface-2-3>) 的 local
rank-1 boundary约束：它只能是 immutable simple-name `LetItem` 的整个 annotation，不能递归出现在
其它 `Type` child。对应 generic `LambdaExpr` 必须是 initializer本身，不能先经 call/record/container/
branch包装。Resolver在进入 Type/Row inference前检查该 ancestor/initializer关系；失败是确定性
frontend rejection，不能降成普通 `FunctionTypeV2` 或把 scheme binder漏进 package wire。

规则：

- `! E` 表示精确 row variable；`! {F, app, ..E}` 表示 literal extension；
- 一个 literal 最多有一个 tail，且 tail 必须最后出现；
- `..S::Extra` 是合法 associated-row projection；
- 多个未知 row 用 `! (E1 | E2)`，不写 `{..E1, ..E2}`；
- `|` 在 `RowExpr` 中左结合，优先级低于 literal/path；没有 surface row
  intersection 或 subtraction；
- normalization 展开已知 projection/union、去除重复 entry、按稳定 identity
  排序，并保留所有 rigid row-variable union summand；“一个 tail”只约束
  单个 literal 的 source spelling；
- `{F, ..E}` 同时产生 `Lacks(E,F)`；若不能证明 tail 不含同 identity entry，
  extension 不能通过。v1 只有 extension 与 union，没有 subtraction；
- `{F}` 与 `{app}` 分别解析到 anonymous family 与 named identity，不能互换；
- `Read[app]` 不是源语法。诊断可以用它解释 `{app}` 的 family。

`InvalidRowLiteralMultipleTails` 只构造 committed recovery CST。第二个
`DOTDOT` 后的 `CUT` 保证 `{..E1, ..E2}` 不退化成不稳定 parser error；
RowWF 必须以版本化 `row-literal-has-multiple-tails` 拒绝该 node并建议
`E1 | E2`。它不把多个 literal tail接受进语言。

`Next[frame,A]` 使用普通 `TypeReference` / `TypeArgs` CST；kind checking 将
`frame` 解释为受限 clock identity。它不会把所有 lower identifier 都提升成
一般 dependent type。

Effect-kind `F`只在 signature/kind stage确认 direct capability parameter位置时
可作为 `app : F` 的 source type并产生 `Cap[i_app,F]`。没有一般 source
CapabilityType production；`CAP` token只构造 `RemovedCapabilityMarker` recovery node，
稳定诊断 `surface-cap-marker-removed`。

=== 函数、operation 与参数 <surface-a-5>

```peg
FunctionDecl       <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation Block
FunctionSignature  <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation SEMICOLON?
MemberFunctionDecl <- DEF GenericClauses? LowerIdent ParamList
                      ARROW Type EffectAnnotation Block
MemberFunctionSignature <- DEF GenericClauses? LowerIdent ParamList
                           ARROW Type EffectAnnotation SEMICOLON?
FunctionName       <- LowerIdent
                    / FunctionOwner COLONCOLON LowerIdent
FunctionOwner      <- (PackagePath COLONCOLON)?
                      UpperIdent (COLONCOLON UpperIdent)* TypeArgs?

ParamList          <- LPAREN Parameter
                      (COMMA Parameter)* COMMA? RPAREN
                    / LPAREN RPAREN
Parameter          <- SimpleParameter / PatternParameter
SimpleParameter    <- LowerIdent COLON Type (EQUAL Expr)?
PatternParameter   <- !(LowerIdent COLON) Pattern COLON Type

MissingNamedFunctionRow <- CONST? DEF GenericClauses? FunctionName ParamList
                           ARROW Type !BANG Block
                         / EXTEND DEF GenericClauses? LowerIdent
                           ExtensionParamList ARROW Type !BANG Block
                         / DEF GenericClauses? FunctionName ParamList
                           ARROW Type !BANG MissingSignatureEnd
MissingSignatureEnd <- SEMICOLON / &(DEF / TYPE / RBRACE)

Mode               <- ABORT / FUN / ONCE / CTL
OperationDecl      <- Mode OperationTypeParams? LowerIdent OperationParamList
                      ARROW Type OperationSecondaryAnnotation?
                      OperationContractItem* SEMICOLON?
OperationTypeParams <- LBRACKET UpperIdent
                       (COMMA UpperIdent)* COMMA? RBRACKET
OperationParamList <- LPAREN OperationParameter
                      (COMMA OperationParameter)* COMMA? RPAREN
                    / LPAREN RPAREN
OperationParameter <- LowerIdent COLON Type
                    / !(LowerIdent COLON) Pattern COLON Type
OperationSecondaryAnnotation <- BANG CUT
                      (ClosedRowLiteral / InvalidOperationSecondaryRow)
ClosedRowLiteral   <- LBRACE (RowEntry (COMMA RowEntry)* COMMA?)? RBRACE
InvalidOperationSecondaryRow <- RowExpr
OperationContractItem <- RESUMES NEXT / MAY_SUSPEND
```

Operation 的唯一 generic domain是无 constraint的 `OperationTypeParams`，与 retained/successor
`OperationSignatureV2.type_binders` 一致；effect constructor、effect atom、row generic与 ordinary-trait
constraint只属于有 exact evidence-substitution 边的 named function/declaration contract，不能在 operation
header出现。Operation parameter可用 simple name或
irrefutable positional pattern，但没有 default；其 `CallableSurfaceSignatureV1` slot因此全部
`defaultable=false`。这些限制是 accepted grammar boundary，不由 importer猜测或 silent erase。

Operation 的 secondary effect annotation 是 clause/handler 聚合的一部分，不能
因为 family row 最终被消除而丢失。对
`once read() -> A ! {Log}`，`{Log}` 就是 `SecondaryRow`；调用 row 是
argument rows、operation dispatch entry 与该 annotation 的 union。Checker
另存带 call-site/prompt route 的 attributed demand `Δ`，public row只是其
擦除。

v1 要求 operation 的 secondary row *closed*：允许 `! {}`、
`! {Audit, Log}`，拒绝 `! E`、`! {Audit, ..E}` 与任何包含 rigid row
variable的 union。一般 function/result effect annotation仍使用完整
`RowExpr`；限制只作用于 `OperationSecondaryAnnotation`。这样 interface中的
每个 secondary demand都能序列化成 finite `SecondarySiteV1`，不会把 open
tail伪装成已经枚举完的 site set。
`CUT` 在 `!` 后固定 operation-secondary context；fallback
`InvalidOperationSecondaryRow` 只构造 recovery CST node，WF 必须以版本化
`operation-secondary-row-must-be-closed` 拒绝。它不把 open row接受进语言，
但保证 bare `! E` 与 `! {Audit, ..E}` 不会提前退化成不稳定 parser error。

`def` 是具名、可递归 declaration/generalization boundary；所有 `def`、trait/
impl/default method、extension与 `const def`都显式写 `EffectAnnotation`，pure为
`! {}`。省略只进入 `MissingNamedFunctionRow` recovery并报
`named-function-effect-row-required`。`fn` 只在
`LambdaExpr` 和 `GenericFunctionType` 中出现；`fun` 仅是 operation mode。
`def` 在 expression 或 type 位置必须拒绝。

Core 一律是一元函数。`def f(p1, ..., pn)` elaboration为一个接收 immutable
n-tuple 的递归 Core binding；call 仍先按源码顺序求值 callee 和各 argument，
再按 resolved parameter/label 顺序组装 tuple。它不等于 currying，也不提供
隐式 partial application；需要高阶返回值时必须显式返回 `fn`。

`SimpleParameter`天然有同名 source label并可有 default；`PatternParameter`只可
positional且必须 irrefutable。Receiver、destructuring与 direct capability binder
nondefaultable；后者若写 default报 `capability-binder-default-not-in-v1`。
有 default的 call-entry slot使用 sealed
`@cire::core::ProvidedOrOmitted[T_core]` wrapper，callee prologue
按 parameter declaration order求值 omitted defaults，再构造 immutable body tuple。
Default expression 只能看到 declaration generics、module scope 与已完成绑定的
前序 ordinary `SimpleParameter`；不能看到后续 slot，也不能从 receiver、
destructuring 或 direct capability binder偷建 default authority。

在 `TraitItem` 中，同一规则把 required/default method parameter default写入
`TraitMethodSignatureV1.default_program.default_prologues`，并把从这些 expression可达的 module
callable、local lambda、application/closure table、complete lexical requirement scopes与每个 trait-method use一并封闭；
即使 method body absent也保留可单独 decode/check/execute的完整 call-site语义。
在 `ImplItem` 中任何 source-spelled `= Expr` 都拒绝：impl callable从 trait signature继承 exact
defaultable slot与 default program，不能另求值、覆盖或删除 default。Concrete default/impl body的
Formal projection必须 exact equal该 signature program；对 explicit impl body，比较前先用当前 impl的
trait arguments/target 与 completed associated bindings对 generic program做 exact Self/trait/associated substitution，
method-own generic scheme不单态化。Body-only graph不得混入。
