#import "../shared.typ": *

=== Pattern <surface-a-6>

```peg
Pattern             <- OrPattern
OrPattern           <- AliasPattern (PIPE AliasPattern)*
AliasPattern        <- AtomicPattern (AS LowerIdent)?
AtomicPattern       <- UNDERSCORE
                     / LowerIdent
                     / LiteralPattern
                     / ConstructorPattern
                     / TuplePattern
                     / RecordPattern
                     / ArrayPattern

LiteralPattern      <- SignedIntPattern / CharLiteral / ByteLiteral
                     / PatternStringLiteral / BoolLiteral
SignedIntPattern    <- MINUS? IntLiteral
PatternStringLiteral <- '"' PatternStringPart* '"'
PatternStringPart   <- Escape / EscapedDollar / StringScalar
ConstructorPattern  <- TypeName
                       (LPAREN PatternList? RPAREN / RecordPattern)?
TuplePattern        <- LPAREN PatternList? RPAREN
PatternList         <- Pattern (COMMA Pattern)* COMMA?
RecordPattern       <- LBRACE RecordPatternFields? RBRACE
RecordPatternFields <- RecordPatternField
                       (COMMA RecordPatternField)*
                       (COMMA DOTDOT)? COMMA?
                     / DOTDOT COMMA?
RecordPatternField  <- LowerIdent (COLON Pattern)?
ArrayPattern        <- LBRACKET ArrayPatternItems? RBRACKET
ArrayPatternItems   <- Pattern (COMMA Pattern)*
                       (COMMA DOTDOT LowerIdent)? COMMA?
                     / DOTDOT LowerIdent COMMA?
RemovedFloatPattern <- MINUS? FloatLiteral
```

`RemovedFloatPattern` 只属于 recovery grammar，不可从 `Pattern`到达。
Or-pattern 两侧必须绑定相同名字和兼容类型；同一 pattern 不得重复绑定。
Guard 只属于 `match` arm，不是 pattern 的一部分。

`SignedIntPattern` 与表达式中的 signed constant 使用同一 range rule：若有
`MINUS`，它与 `IntLiteral` 的 source spans 必须紧邻，二者合并后再做
expected integer type 的 range check，因而 minimum signed value 可写。正负 Float literal
pattern都进入专用 recovery node并报 `float-pattern-not-in-cire-v1`。
`ByteLiteral` pattern按解码后的 exact byte sequence 比较 `Bytes`，
`PatternStringLiteral` 按 exact Unicode-scalar/String value比较；两者都不调用
`Eq`、trait或 effect。其余 Pattern 同样不调用 `Eq`/trait/effect。`let`、parameter、`for`与 handler clause要求
irrefutable；refutable pattern只在 `match`。Resolver按 nominal constructor/privacy
检查 record field，typechecker以 constructor matrix证明 exhaustiveness/usefulness；
guard不贡献 coverage。

=== 表达式与优先级 <surface-a-7>

表达式采用固定 precedence ladder。数字越小结合越晚：

#table(
  columns: (1.4fr, 1.8fr, 2.8fr),
  [*层*],
  [*构造*],
  [*结合*],
  [1],
  [assignment `=`],
  [右结合],
  [2],
  [`||`],
  [左结合、短路],
  [3],
  [`&&`],
  [左结合、短路],
  [4],
  [`== !=`],
  [不可串联],
  [5],
  [`< <= > >=`],
  [不可串联],
  [6],
  [`+ -`],
  [左结合],
  [7],
  [`* / %`],
  [左结合],
  [8],
  [prefix `! -`],
  [右结合],
  [9],
  [call/method/index/field/trailing lambda],
  [左结合],
)

本 profile 不允许用户声明新 operator。

```peg
Expr             <- AssignExpr
AssignExpr       <- LogicOrExpr (EQUAL AssignExpr)?
LogicOrExpr      <- LogicAndExpr (OROR LogicAndExpr)*
LogicAndExpr     <- EqualityExpr (ANDAND EqualityExpr)*
EqualityExpr     <- CompareExpr ((EQEQ / NEQ) CompareExpr)?
CompareExpr      <- AddExpr ((LT / LE / GT / GE) AddExpr)?
AddExpr          <- MulExpr ((PLUS / MINUS) MulExpr)*
MulExpr          <- PrefixExpr ((STAR / SLASH / PERCENT) PrefixExpr)*
PrefixExpr       <- (BANG / MINUS) PrefixExpr / PostfixExpr

PostfixExpr      <- PrimaryExpr PostfixPart*
PostfixPart      <- GenericCallSuffix
                  / CallSuffix
                  / BareTrailingCall
                  / MethodSuffix
                  / FieldSuffix
                  / IndexSuffix
GenericCallSuffix <- TypeArgs? EffectArgs ArgList TrailingLambda?
                   / TypeArgs EffectArgs? ArgList TrailingLambda?
CallSuffix       <- ArgList TrailingLambda?
BareTrailingCall <- TrailingLambda
MethodSuffix     <- DOT LowerIdent
                   (TypeArgs? EffectArgs? ArgList TrailingLambda?
                   / TrailingLambda)
FieldSuffix      <- DOT LowerIdent
IndexSuffix      <- LBRACKET Expr RBRACKET

PrimaryExpr      <- WithExpr / NonWithPrimaryExpr
NonWithPrimaryExpr <- HandlerExpr
                  / TraitUfcsExpr
                  / IfExpr
                  / MatchExpr
                  / LoopExpr
                  / LambdaExpr
                  / DelayExpr
                  / ReturnExpr
                  / BreakExpr
                  / ContinueExpr
                  / RecordExpr
                  / ArrayExpr
                  / TupleOrGroupedExpr
                  / Block
                  / Literal
                  / ValueName

Literal          <- IntLiteral / FloatLiteral / CharLiteral
                  / StringLiteral / ByteLiteral / BoolLiteral
TupleOrGroupedExpr <- LPAREN ArgumentExprList? RPAREN
ArgumentExprList <- Expr (COMMA Expr)* COMMA?
ArrayExpr        <- LBRACKET ArgumentExprList? RBRACKET

RecordExpr       <- TypeName LBRACE RecordBody? RBRACE
                  / LBRACE &RecordFieldStart
                    RecordBody RBRACE
RecordFieldStart <- LowerIdent (COLON / COMMA / RBRACE) / DOTDOT
RecordBody       <- RecordFields (COMMA RecordUpdateTail)? COMMA?
                  / RecordUpdateTail COMMA?
RecordFields     <- RecordField (COMMA RecordField)*
RecordField      <- LowerIdent (COLON Expr)?
RecordUpdateTail <- DOTDOT Expr

TraitUfcsExpr    <- LT Type AS QualifiedName GT COLONCOLON LowerIdent
                    TypeArgs? EffectArgs? ArgList TrailingLambda?

LambdaExpr       <- FN GenericClauses? LambdaParamList Block
LambdaParamList  <- LPAREN LambdaParameter
                    (COMMA LambdaParameter)* COMMA? RPAREN
                  / LPAREN RPAREN
LambdaParameter  <- Pattern (COLON Type)?
LambdaPatternList <- LambdaParameter
                     (COMMA LambdaParameter)* COMMA?

IfExpr           <- IF Expr Block (ELSE (IfExpr / Block))?
MatchExpr        <- MATCH Expr LBRACE MatchArm* RBRACE
MatchArm         <- Pattern (IF Expr)? FAT_ARROW Expr
                    (COMMA / SEMICOLON)?
LoopExpr         <- WHILE Expr Block
                  / FOR Pattern IN Expr Block
                  / LOOP Block
ReturnExpr       <- RETURN Expr?
BreakExpr        <- BREAK Expr?
ContinueExpr     <- CONTINUE
```

Assignment 左侧必须是 mutable place；这一点在 syntax validation/type checking
完成。Selector与 RHS严格按 #ref(<surface-2-6>)求值。Record update最多一个且 final
`RecordUpdateTail`；enum variant/unknown nominal update在 Kind阶段拒绝。
`return`、`break` 的目标由 control-flow resolver绑定 fresh lexical identity。
`while`/`for`在 Normalize stage唯一展开为 `loop`，其中 `for` source只求值一次并
显式传递新的 iterator state；它们不引入 public effect row。

==== 调用参数 <surface-a-7-1>

```peg
ArgList          <- LPAREN CallArguments? RPAREN
CallArguments    <- PositionalArgs (COMMA LabelledArgs)? COMMA?
                  / LabelledArgs COMMA?
PositionalArgs   <- PositionalArg (COMMA PositionalArg)*
PositionalArg    <- !LabelledArgStart Expr
LabelledArgs     <- LabelledArg (COMMA LabelledArg)*
LabelledArgStart <- LowerIdent EQUAL
LabelledArg      <- LowerIdent EQUAL Expr

RemovedLabelPunningArgument <- LowerIdent TILDE
```

- positional argument 必须在 labelled argument 之前；
- label 在一次调用中必须唯一，resolve 后 unknown label 是错误；
- 没有 label punning；同名 value也必须写 `name = name`；
- callee、显式 argument、最后的 trailing lambda按源码从左到右各求值一次，
  之后只重排 pure temporary reference形成 parameter-order tuple；
- 缺省 labelled parameter 在进入 callee 后按声明顺序求值；
- generic argument 只属于后面紧邻的 call；index suffix 不会被猜成泛型调用。
- `LowerIdent =` 在 argument 起点先判为 label；若确实要把赋值
  作为 positional argument，必须加括号，例如 `f((slot = value))`。
- `LowerIdent TILDE` 只由 recovery parser构造
  `RemovedLabelPunningArgument`并报 `surface-tilde-label-removed`；它不是
  `CallArguments` 的 accepted branch。

因此 corpus 中 `panel(make_title(), enabled=is_enabled(), gap=measure_gap())`
产生一个 positional 与两个 labelled argument；`connect("host",
secure=true, 443)` 在进入 labels 后遇到 positional token，必须拒绝。这里不
依赖 PEG choice偶然先把 `enabled=is_enabled()` 吞成 assignment。

同理，`fn(value) { ... }` 由 `LambdaParamList` 接受并推导 parameter type；
`fn(value : Int) { ... }` 也合法。具名 `def` 仍使用必须标注类型的
`ParamList`。

Label/default call必须解析到 exact static callable metadata；structural function
value只可 positional/trailing。Trailing lambda在 signature resolution后只填 final
non-receiver formal，final duplicate优先报错；它不搜索未填 slot。

==== Trailing lambda <surface-a-7-2>

```peg
TrailingLambda   <- LBRACE LambdaHead? BlockElement* RBRACE
LambdaHead       <- LambdaPatternList FAT_ARROW
```

`callee(args) { ... }` 与 `callee { ... }` 都把 lambda 作为*该 call* 的最后一个
argument。换行和 comment 不脱附；要在 call 后开始独立 block，必须写 `;`。

Lossless PEG 保留 `PostfixPart*` 中的 error form，但 normalization 必须左到右
记录前一个 postfix 是否已以 `TrailingLambda` 结尾。若下一个 postfix 立即是
`BareTrailingCall`，则第二个 `{` 在 signature resolution 后稳定拒绝为
`trailing-lambda-target-not-callable`，不得把它重解释为调用返回值。因此 `f { } { }` 与
`f() { } { }` 都拒绝；只有中间出现新的显式 call target/参数列表（例如
`f() { }(fn() { body })`）才能继续调用结果。该拒绝与已填 final slot 的
duplicate 使用同一 precedence，早于返回值 callable/type 推断。

`factory() { body }` 给 `factory` 这次调用追加 lambda，不调用 `factory()` 的
返回值。调用返回的 callable 必须显式写 `factory()(fn() { body })`。

=== Block 与 brace 判定 <surface-a-8>

```peg
Block            <- LBRACE BlockElement* RBRACE
BlockElement     <- LetItem / Expr SEMICOLON?
LetItem          <- LET MUT? Pattern (COLON Type)? EQUAL Expr SEMICOLON?
RemovedDeferItem <- DEFER CUT Expr SEMICOLON?
```

Parser 对每个 `Expr` 使用上节的 maximal expression parse；换行不是分隔符。
当下一个 token 不能继续当前表达式、却能开始新的 `BlockElement` 时，新 item
开始。因此 UI 风格的连续 call 不依赖 layout：

```cire
{
  Text("A")
  Button("B") { save() }
}
```

Block 从左到右求值。最后一个没有 `;` 的 expression 是 block result；其余
expression 的值被丢弃。若最后一个 element 是 `let` 或带 `;` 的
expression，block result 是 `Unit`。

`DEFER`只由 recovery parser构造 `RemovedDeferItem`，并稳定拒绝
`defer-not-in-cire-v1`；该 node不能进入 accepted Surface HIR。cleanup只经
#ref(<surface-2-6>) 的 sealed finally runner。`LetItem` pattern必须 irrefutable；`let mut`
永远 monomorphic且其 reachable place facts进入 capture/replay检查。

这只是普通 block 语义。UI siblings 必须由第一方 builder/effect protocol
收集，不能由 parser 把“多个表达式”魔法地变成 children。

Brace 的判定顺序：

+ handler、match、declaration 等 introducer 后按对应专用 body；
+ call 后的 `{` 按 trailing lambda；
+ `{ patterns => ... }` 按 lambda；
+ `Type { ... }`、`{ field: ... }` / `{ field, ... }` / `{ ..base }` 按 record；
+ 其余 `{ ... }` 按 block。

空 `{}` 是 Unit block；空 record 写 `Type {}`，不能依靠期待类型把同一 CST
静默改类。非空 bare record可由字段 shape建立独立 CST，再由 expected type
解析具体 constructor。
