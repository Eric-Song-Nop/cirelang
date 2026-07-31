# Cire-TR₀ 完整表面语法

> **Profile:** `Cire-TR₀/2026-07-31`
>
> 本文是实现无关的 canonical grammar。未来 parser 必须实现这里定义的 token
> language、优先级、附着和恢复边界；parser 的既有行为不能修改本文含义。
> `def` 只声明具名函数/方法；`fn` 只构造匿名函数值或写显式泛型函数值类型；
> `fun` 只表示 effect 的唯一尾恢复 mode。

本文使用 PEG 记号：`/` 为有序选择，`*`、`+`、`?` 为重复，`&` / `!` 为
正/负 lookahead，`CUT` 表示识别到判别 token 后不回退。大写名字是 token，
CamelCase 名字是 grammar rule。语义验证写在 grammar 后，不伪装成 parsing。

## 1. 词法

源码是 Unicode text。位置使用 UTF-16 code-unit 的半开区间；这只影响
artifact/LSP，不改变 token language。

```peg
SourceFile     <- Trivia TopLevelItem* EOF
Trivia         <- (Whitespace / LineComment / BlockComment)*
Whitespace     <- UnicodeWhiteSpace+
LineComment    <- "//" (!LineTerminator .)* LineTerminator?
BlockComment   <- "/*" (BlockComment / !"*/" .)* "*/"

Identifier     <- XID_Start XID_Continue*
                / "_" XID_Continue+
LowerIdent     <- Identifier whose first cased scalar is lowercase
UpperIdent     <- Identifier whose first cased scalar is uppercase
DiscardIdent   <- "_"

DecDigits      <- DecDigit ("_"? DecDigit)*
HexDigits      <- HexDigit ("_"? HexDigit)*
OctDigits      <- OctDigit ("_"? OctDigit)*
BinDigits      <- BinDigit ("_"? BinDigit)*

IntLiteral     <- "0x" HexDigits / "0o" OctDigits / "0b" BinDigits / DecDigits
FloatLiteral   <- DecDigits "." DecDigits Exponent?
                / DecDigits Exponent
Exponent       <- ("e" / "E") ("+" / "-")? DecDigits
CharLiteral    <- "'" CharElement "'"
StringLiteral  <- '"' StringElement* '"'
CharElement    <- Escape / !("'" / LineTerminator) .
StringElement  <- Escape / !('"' / LineTerminator) .
Escape         <- "\\" ("n" / "r" / "t" / "0" / "\\" / "'" / '"'
                 / "u{" HexDigit+ "}")
BoolLiteral    <- TRUE / FALSE

LineTerminator <- "\r\n" / "\n" / "\r" / "\u{2028}" / "\u{2029}"
DecDigit       <- [0-9]
HexDigit       <- [0-9A-Fa-f]
OctDigit       <- [0-7]
BinDigit       <- [01]
```

关键字不能作为普通 identifier：

```text
ability abort as break cap const continue ctl def defer effect else enum false
effects fn for fun handler if impl in let loop match may_suspend mut next pub
resumes return struct trait true type while with once open
```

Keyword token采用 Unicode identifier boundary；下列名字是后续 grammar 使用的
significant token kind：

```peg
ABILITY     <- "ability" !XID_Continue
ABORT       <- "abort" !XID_Continue
AS          <- "as" !XID_Continue
BREAK       <- "break" !XID_Continue
CAP         <- "cap" !XID_Continue
CONST       <- "const" !XID_Continue
CONTINUE    <- "continue" !XID_Continue
CTL         <- "ctl" !XID_Continue
DEF         <- "def" !XID_Continue
DEFER       <- "defer" !XID_Continue
EFFECT      <- "effect" !XID_Continue
EFFECTS     <- "effects" !XID_Continue
ELSE        <- "else" !XID_Continue
ENUM        <- "enum" !XID_Continue
FALSE       <- "false" !XID_Continue
FN          <- "fn" !XID_Continue
FOR         <- "for" !XID_Continue
FUN         <- "fun" !XID_Continue
HANDLER     <- "handler" !XID_Continue
IF          <- "if" !XID_Continue
IMPL        <- "impl" !XID_Continue
IN          <- "in" !XID_Continue
LET         <- "let" !XID_Continue
LOOP        <- "loop" !XID_Continue
MATCH       <- "match" !XID_Continue
MAY_SUSPEND <- "may_suspend" !XID_Continue
MUT         <- "mut" !XID_Continue
NEXT        <- "next" !XID_Continue
ONCE        <- "once" !XID_Continue
OPEN        <- "open" !XID_Continue
PUB         <- "pub" !XID_Continue
RESUMES     <- "resumes" !XID_Continue
RETURN      <- "return" !XID_Continue
STRUCT      <- "struct" !XID_Continue
TRAIT       <- "trait" !XID_Continue
TRUE        <- "true" !XID_Continue
TYPE        <- "type" !XID_Continue
WHILE       <- "while" !XID_Continue
WITH        <- "with" !XID_Continue

ARROW       <- "->"
FAT_ARROW   <- "=>"
COLONCOLON  <- "::"
DOTDOT      <- ".."
EQEQ        <- "=="
NEQ         <- "!="
LE          <- "<="
GE          <- ">="
ANDAND      <- "&&"
OROR        <- "||"

AT          <- "@"
BANG        <- "!" !"="
COLON       <- ":" !":"
COMMA       <- ","
DOT         <- "." !"."
EQUAL       <- "=" !("=" / ">")
LT          <- "<" !"="
GT          <- ">" !"="
LBRACE      <- "{"
RBRACE      <- "}"
LBRACKET    <- "["
RBRACKET    <- "]"
LPAREN      <- "("
RPAREN      <- ")"
MINUS       <- "-" !">"
PERCENT     <- "%"
PIPE        <- "|" !"|"
PLUS        <- "+"
SEMICOLON   <- ";"
SLASH       <- "/"
STAR        <- "*"
TILDE       <- "~"
UNDERSCORE  <- "_" !XID_Continue
EOF         <- !.
```

Lexer 在同一 offset 先消费 `Trivia`，再按最长匹配产生一个 significant token；
等长时 keyword/literal token优先于 `Identifier`。`CUT` 是 parser
meta-operation，不是 source token。

`delay`、`advance` 和 `Next` 是 sealed prelude 名称，不是无条件保留的关键字：
只有完整 temporal shape 或 resolver evidence 才赋予 intrinsic 含义。

换行属于 trivia，不触发 semicolon insertion，也不改变 trailing lambda 或
`with` chain 的附着。

## 2. 名称、可见性与声明

```peg
Name              <- LowerIdent / UpperIdent
PackagePath       <- AT Name (DOT Name)*
QualifiedName     <- PackagePath COLONCOLON Name
                     (COLONCOLON Name)*
                   / Name (COLONCOLON Name)*
TypeName          <- (PackagePath COLONCOLON)?
                     UpperIdent (COLONCOLON UpperIdent)*
ValueName         <- QualifiedName
Visibility        <- PUB (LPAREN OPEN RPAREN)?

TopLevelItem      <- Visibility? Declaration
Declaration       <- FunctionDecl
                   / StructDecl
                   / EnumDecl
                   / TraitDecl
                   / AbilityDecl
                   / EffectDecl
                   / ImplDecl
                   / TypeAliasDecl
                   / ConstDecl

TypeHead          <- UpperIdent TypeParams?
TypeAliasDecl     <- TYPE TypeHead EQUAL Type SEMICOLON?
ConstDecl         <- CONST LowerIdent COLON Type EQUAL Expr SEMICOLON?

StructDecl        <- STRUCT TypeHead SuperTraits?
                     LBRACE FieldDecl* RBRACE
FieldDecl         <- Visibility? LowerIdent COLON Type
                     (EQUAL Expr)? (COMMA / SEMICOLON)?

EnumDecl          <- ENUM TypeHead SuperTraits?
                     LBRACE VariantDecl* RBRACE
VariantDecl       <- UpperIdent VariantPayload?
                     (COMMA / SEMICOLON)?
VariantPayload    <- LPAREN TypeList? RPAREN
                   / LBRACE NamedTypeList? RBRACE

TraitDecl         <- TRAIT TypeHead SuperTraits?
                     LBRACE TraitItem* RBRACE
TraitItem         <- FunctionSignature
                   / AssociatedTypeDecl
AssociatedTypeDecl <- TYPE UpperIdent TypeParams?
                      (COLON TypeConstraintList)?
                      (EQUAL Type)? SEMICOLON?

AbilityDecl       <- ABILITY TypeHead SuperAbilities?
                     LBRACE AbilityItem* RBRACE
AbilityItem       <- OperationDecl
                   / AssociatedTypeDecl
                   / AssociatedEffectDecl
                   / AssociatedRowDecl
AssociatedEffectDecl <- EFFECT UpperIdent TypeParams?
                        (COLON AbilityConstraintList)?
                        (EQUAL Type)? SEMICOLON?
AssociatedRowDecl <- EFFECTS UpperIdent
                     (COLON RowConstraintList)?
                     (EQUAL RowExpr)? SEMICOLON?

EffectDecl        <- EFFECT TypeHead EffectConformance?
                     LBRACE OperationDecl* RBRACE
EffectConformance <- COLON AbilityRef (PLUS AbilityRef)*

ImplDecl          <- IMPL GenericClauses? Type FOR Type
                     LBRACE ImplItem* RBRACE
ImplItem          <- FunctionDecl
                   / AssociatedTypeBinding
                   / AssociatedEffectBinding
                   / AssociatedRowBinding
AssociatedTypeBinding   <- TYPE UpperIdent EQUAL Type SEMICOLON?
AssociatedEffectBinding <- EFFECT UpperIdent EQUAL Type SEMICOLON?
AssociatedRowBinding    <- EFFECTS UpperIdent EQUAL RowExpr SEMICOLON?

SuperTraits       <- COLON Type (PLUS Type)*
SuperAbilities    <- COLON AbilityRef (PLUS AbilityRef)*
AbilityRef        <- Type
```

Package identity and dependency selection belong to the package manifest. 源文件通过
`@package.name` 和 `Type::member` 使用 package-qualified name；本 profile
不增加会在文件内改变解析环境的 wildcard import。

## 3. 形参、实参与约束

表面的 `[...]` / `![...]` 是**形参绑定列表**，不是量词语法：

```peg
GenericClauses       <- TypeParams EffectParams? / EffectParams
TypeParams           <- LBRACKET TypeParam
                        (COMMA TypeParam)* COMMA? RBRACKET
TypeParam            <- UpperIdent (COLON TypeConstraintList)?
TypeConstraintList   <- Type (PLUS Type)*

EffectParams         <- BANG LBRACKET EffectParam
                        (COMMA EffectParam)* COMMA? RBRACKET
EffectParam          <- RowParam / EffectConstructorParam / EffectAtomParam
RowParam             <- DOTDOT UpperIdent (COLON RowConstraintList)?
EffectConstructorParam
                     <- UpperIdent BinderHoles
                        (COLON AbilityConstraintList)?
EffectAtomParam      <- UpperIdent (COLON AbilityConstraintList)?
BinderHoles          <- LBRACKET UNDERSCORE
                        (COMMA UNDERSCORE)* RBRACKET
AbilityConstraintList <- AbilityRef (PLUS AbilityRef)*
RowConstraintList    <- RowPredicate (PLUS RowPredicate)*
RowPredicate         <- UpperIdent LBRACKET PredicateArgList? RBRACKET
PredicateArgList     <- PredicateArg (COMMA PredicateArg)* COMMA?
PredicateArg         <- Type / RowExpr

TypeArgs             <- LBRACKET TypeArg
                        (COMMA TypeArg)* COMMA? RBRACKET
TypeArg              <- Type / LowerIdent
EffectArgs           <- BANG LBRACKET EffectArg
                        (COMMA EffectArg)* COMMA? RBRACKET
EffectArg            <- RowExpr / Type
```

`F`、`F[_]`、`..E` 分别绑定 `Effect`、effect constructor、`EffectRow`；
这由 binder shape 唯一决定。`app : cap F` 是 term binder，不进入 generic
list。

## 4. 类型与 effect-row 表达式

```peg
Type                <- GenericFunctionType / ArrowType
GenericFunctionType <- FN GenericClauses ParamTypeList
                       ARROW Type EffectAnnotation?
ArrowType           <- TypePrimary
                       (ARROW Type EffectAnnotation?)?
TypePrimary         <- CapabilityType
                     / TupleOrGroupedType
                     / TypeReference
CapabilityType      <- CAP CUT TypePrimary
TupleOrGroupedType  <- LPAREN TypeList? RPAREN
TypeList            <- Type (COMMA Type)* COMMA?
NamedTypeList       <- LowerIdent COLON Type
                       (COMMA LowerIdent COLON Type)* COMMA?
TypeReference       <- TypeName TypeArgs?

ParamTypeList       <- LPAREN TypeList? RPAREN
EffectAnnotation    <- BANG RowExpr

RowExpr             <- RowUnion
RowUnion            <- RowPrimary (PIPE RowPrimary)*
RowPrimary          <- RowLiteral / RowReference
                     / LPAREN RowExpr RPAREN
RowReference        <- QualifiedName TypeArgs?
RowLiteral          <- LBRACE RowLiteralBody? RBRACE
RowLiteralBody      <- RowEntry (COMMA RowEntry)*
                       (COMMA RowTail)? COMMA?
                     / RowTail COMMA?
RowEntry            <- LowerIdent / TypeReference
RowTail             <- DOTDOT RowReference
```

规则：

- `! E` 表示精确 row variable；`! {F, app, ..E}` 表示 literal extension；
- 一个 literal 最多有一个 tail，且 tail 必须最后出现；
- `..S::Extra` 是合法 associated-row projection；
- 多个未知 row 用 `! (E1 | E2)`，不写 `{..E1, ..E2}`；
- `|` 在 `RowExpr` 中左结合，优先级低于 literal/path；没有 surface row
  intersection 或 subtraction；
- normalization 展开已知 projection/union、去除重复 entry、按稳定 identity
  排序，并保留未知 tail；
- `{F, ..E}` 同时产生 `Lacks(E,F)`；若不能证明 tail 不含同 identity entry，
  extension 不能通过。TR₀ 只有 extension 与 union，没有 subtraction；
- `{F}` 与 `{app}` 分别解析到 anonymous family 与 named identity，不能互换；
- `Read[app]` 不是源语法。诊断可以用它解释 `{app}` 的 family。

`Next[frame,A]` 使用普通 `TypeReference` / `TypeArgs` CST；kind checking 将
`frame` 解释为受限 clock identity。它不会把所有 lower identifier 都提升成
一般 dependent type。

## 5. 函数、operation 与参数

```peg
FunctionDecl       <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation? Block
FunctionSignature  <- DEF GenericClauses? FunctionName ParamList
                      ARROW Type EffectAnnotation? SEMICOLON?
FunctionName       <- LowerIdent
                    / FunctionOwner COLONCOLON LowerIdent
FunctionOwner      <- (PackagePath COLONCOLON)?
                      UpperIdent (COLONCOLON UpperIdent)* TypeArgs?

ParamList          <- LPAREN Parameter
                      (COMMA Parameter)* COMMA? RPAREN
                    / LPAREN RPAREN
Parameter          <- LabelledParameter / PositionalParameter
PositionalParameter <- Pattern COLON Type
LabelledParameter  <- LowerIdent TILDE COLON Type
                      (EQUAL Expr)?

Mode               <- ABORT / FUN / ONCE / CTL
OperationDecl      <- Mode GenericClauses? LowerIdent ParamList
                      ARROW Type EffectAnnotation?
                      OperationContractItem* SEMICOLON?
OperationContractItem <- RESUMES NEXT / MAY_SUSPEND
```

Operation 的 secondary effect annotation 是 clause/handler 聚合的一部分，不能
因为 family row 最终被消除而丢失。对
`once read() -> A ! {Log}`，`{Log}` 就是 `SecondaryRow`；调用 row 是
argument rows、operation dispatch entry 与该 annotation 的 union。Checker
另存带 call-site/prompt route 的 attributed demand `Δ`，public row只是其
擦除。

`def` 是具名、可递归 declaration/generalization boundary；`fn` 只在
`LambdaExpr` 和 `GenericFunctionType` 中出现；`fun` 仅是 operation mode。
`def` 在 expression 或 type 位置必须拒绝。

Core 一律是一元函数。`def f(p1, ..., pn)` elaboration为一个接收 immutable
n-tuple 的递归 Core binding；call 仍先按源码顺序求值 callee 和各 argument，
再按 resolved parameter/label 顺序组装 tuple。它不等于 currying，也不提供
隐式 partial application；需要高阶返回值时必须显式返回 `fn`。

## 6. Pattern

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

LiteralPattern      <- IntLiteral / FloatLiteral / CharLiteral
                     / StringLiteral / BoolLiteral
ConstructorPattern  <- TypeName
                     / TypeName LPAREN PatternList? RPAREN
                     / TypeName RecordPattern
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
```

Or-pattern 两侧必须绑定相同名字和兼容类型；同一 pattern 不得重复绑定。
Guard 只属于 `match` arm，不是 pattern 的一部分。

## 7. 表达式与优先级

表达式采用固定 precedence ladder。数字越小结合越晚：

| 层 | 构造 | 结合 |
|---:|---|---|
| 1 | assignment `=` | 右结合 |
| 2 | `||` | 左结合、短路 |
| 3 | `&&` | 左结合、短路 |
| 4 | `== !=` | 不可串联 |
| 5 | `< <= > >=` | 不可串联 |
| 6 | `+ -` | 左结合 |
| 7 | `* / %` | 左结合 |
| 8 | prefix `! -` | 右结合 |
| 9 | call/method/index/field/trailing lambda | 左结合 |

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

PrimaryExpr      <- WithExpr
                  / HandlerExpr
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
                  / StringLiteral / BoolLiteral
TupleOrGroupedExpr <- LPAREN ArgumentExprList? RPAREN
ArgumentExprList <- Expr (COMMA Expr)* COMMA?
ArrayExpr        <- LBRACKET ArgumentExprList? RBRACKET

RecordExpr       <- TypeName LBRACE
                    (RecordField (COMMA RecordField)* COMMA?)? RBRACE
                  / LBRACE &RecordFieldStart
                    RecordField (COMMA RecordField)* COMMA? RBRACE
RecordFieldStart <- LowerIdent (COLON / COMMA / RBRACE) / DOTDOT
RecordField      <- LowerIdent (COLON Expr)?
                  / DOTDOT Expr

LambdaExpr       <- FN GenericClauses? ParamList Block
LambdaPatternList <- Pattern (COMMA Pattern)* COMMA?

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
完成。`return`、`break` 的目标由 control-flow resolver 确定。

### 7.1 调用参数

```peg
ArgList          <- LPAREN CallArguments? RPAREN
CallArguments    <- PositionalArgs (COMMA LabelledArgs)? COMMA?
                  / LabelledArgs COMMA?
PositionalArgs   <- Expr (COMMA Expr)*
LabelledArgs     <- LabelledArg (COMMA LabelledArg)*
LabelledArg      <- LowerIdent EQUAL Expr
                  / LowerIdent TILDE
```

- positional argument 必须在 labelled argument 之前；
- label 在一次调用中必须唯一，resolve 后 unknown label 是错误；
- `name~` 展开为 `name=name`；
- callee、显式 argument 按源码从左到右求值，不能按 parameter 顺序重排；
- 缺省 labelled parameter 在进入 callee 后按声明顺序求值；
- generic argument 只属于后面紧邻的 call；index suffix 不会被猜成泛型调用。

### 7.2 Trailing lambda

```peg
TrailingLambda   <- LBRACE LambdaHead? BlockElement* RBRACE
LambdaHead       <- LambdaPatternList FAT_ARROW
```

`callee(args) { ... }` 与 `callee { ... }` 都把 lambda 作为**该 call** 的最后一个
argument。换行和 comment 不脱附；要在 call 后开始独立 block，必须写 `;`。

`factory() { body }` 给 `factory` 这次调用追加 lambda，不调用 `factory()` 的
返回值。调用返回的 callable 必须显式写 `factory()(fn() { body })`。

## 8. Block 与 brace 判定

```peg
Block            <- LBRACE BlockElement* RBRACE
BlockElement     <- LetItem / DeferItem / Expr SEMICOLON?
LetItem          <- LET MUT? Pattern (COLON Type)? EQUAL Expr SEMICOLON?
DeferItem        <- DEFER Expr SEMICOLON?
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
expression 的值被丢弃。若最后一个 element 是 `let`、`defer` 或带 `;` 的
expression，block result 是 `Unit`。

`defer` 的 grammar 与 LIFO intent 已固定；它在 normal/abort/resume/
finalize/park/Owner-close 路径上的 reduction calculus仍是 formal proof
obligation。未来 runtime行为不能反向定义这部分语义。

这只是普通 block 语义。UI siblings 必须由第一方 builder/effect protocol
收集，不能由 parser 把“多个表达式”魔法地变成 children。

Brace 的判定顺序：

1. handler、match、declaration 等 introducer 后按对应专用 body；
2. call 后的 `{` 按 trailing lambda；
3. `{ patterns => ... }` 按 lambda；
4. `Type { ... }`、`{ field: ... }` / `{ field, ... }` / `{ ..base }` 按 record；
5. 其余 `{ ... }` 按 block。

空 `{}` 是 Unit block；空 record 写 `Type {}`，不能依靠期待类型把同一 CST
静默改类。非空 bare record可由字段 shape建立独立 CST，再由 expected type
解析具体 constructor。

## 9. Handler、resumption 与 `with`

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
WithOperand       <- Expr[stop = WITH | AS | IN]
```

`ClausePatternList` 使用 pattern，不复用 declaration `ParamList`。
`as k` 只允许在 `once` / `ctl` clause。Surface 允许省略 `return`；
elaboration 必须先合成 `return(value) => value`，然后 Core exactness 才检查
“恰好一个 return、每个 operation 恰好一个 clause、无 extra/duplicate”。

`k.resume(value)` 与 `k.finalize()` 由 resolver 降为 resumption primitive。
`k.discontinue(error)` 不属于本 profile。

第一方 completion source 的普通 method spelling
`source.park(k, under = owner)` 由 resolver/type checker在 sealed evidence
下降为 Core `park(source, owner, k)`。它产生
`Transfers(ParkContract)` 并终止当前 path，不返回 `Unit`；普通用户 method、
closure 或容器不能伪造该 lowering，也不能把 raw `Resume` 捕获进 host
callback。

`WithOperand` 使用 terminator-aware expression flavor：它允许 operand 内部的
call、trailing lambda、`if`、`match` 和带括号的 nested `with`，但在当前
chain 深度的下一 `with`、binder `as` 或最终 `in` 前停止。较早 entry 的
`as` binder 对后续 operand 和 body 可见，不在自己的 operand 中可见。

`with` 先保留有序 `ScopedApply`。只有 handler evidence 才允许 `as binder`
并降为生成式 `handle[h,ι]`；普通 transformer 降为普通 thunk call。

## 10. Temporal surface

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

## 11. Syntax validation 与静态语义边界

Parser 必须产出 lossless CST；下列检查在 syntax validation/resolver/type
checker 中完成：

- identifier kind、visibility 适用范围和 duplicate declaration；
- type/effect/row binder domain 与 kind；
- ability conformance、associated binding 和 row predicate；
- pattern binder exactness、or-pattern binder equality、match exhaustiveness；
- assignment place、label matching、default parameter 和 generic arity；
- operation contract、mode refinement、handler clause exactness；
- named capability identity、row removal、capture/escape；
- one-shot disposition、multi-shot replay/fork 和 Owner transfer；
- temporal clock identity、phase authority 和 storage boundary。

Parser recovery 可以插入 missing token 或 error node，但恢复结果不能成为语言
语义。Canonical accept/reject 例子见 [`../examples/spec/`](../examples/spec/)。

## 12. 仍开放但不阻塞 grammar 的问题

- `ability`、`cap` 的最终关键词；
- explicit forwarding / masking 的 surface spelling；
- 一般 one-call function type 是否进入语言，还是只保留 sealed completion
  source/port；
- `discontinue` 是否在补齐 payload/world/cleanup contract 后进入新 profile；
- shallow handler、用户自定义 operator 和 wildcard import 是否永不提供。

这些问题需要新 profile 变更；未来实现不得私自接受候选拼写。
