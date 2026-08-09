#import "../shared.typ": *

== Cire-v1.0 complete grammar <surface-appendix-a>


#status(
  [Profile],
  [
    `Cire-v1.0`
        本文是实现无关的 canonical grammar。未来 parser 必须实现这里定义的 token
    language、优先级、附着和恢复边界；parser 的既有行为不能修改本文含义。
    `def` 只声明具名函数/方法；`fn` 构造匿名函数值，或在 #ref(<surface-2-3>) 唯一允许的 local-let
    annotation写显式 rank-1 scheme；
    `fun` 只表示 effect 的唯一尾恢复 mode。
  ],
)

本文使用 PEG 记号：`/` 为有序选择，`*`、`+`、`?` 为重复，`&` / `!` 为
正/负 lookahead，`CUT` 表示识别到判别 token 后不回退。大写名字是 token，
CamelCase 名字是 grammar rule。语义验证写在 grammar 后，不伪装成 parsing。

=== 词法 <surface-a-1>

源码先 strict UTF-8 decode；BOM拒绝。每个 token同时记录 UTF-8 byte 与 UTF-16
code-unit 半开区间，且两者都落在 scalar boundary；这只影响 origin/artifact/LSP，
不改变 token language。

`UnicodeWhiteSpace`、`XID_Start` 与 `XID_Continue` 是这里声明的三个 external
lexical terminal，分别精确取 Unicode 16.0.0 UCD 的 binary property
`White_Space`、`XID_Start` 与 `XID_Continue` scalar set；surrogate永不属于 terminal。
升级 UCD 版本会改变 tokenization，必须版本化 language profile，不能静默跟随 host
library。除这三个已声明 terminal与 PEG meta operator `CUT` 外，#ref(<surface-appendix-a>)不得引用
未定义 nonterminal。

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

IntLiteral     <- ("0x" HexDigits / "0o" OctDigits / "0b" BinDigits / DecDigits)
                  IntSuffix?
IntSuffix      <- "i8" / "i16" / "i32" / "i64"
                / "u8" / "u16" / "u32" / "u64"
FloatLiteral   <- DecDigits "." DecDigits Exponent?
                  FloatSuffix?
                / DecDigits Exponent FloatSuffix?
FloatSuffix    <- "f32" / "f64"
Exponent       <- ("e" / "E") ("+" / "-")? DecDigits
CharLiteral    <- "'" CharElement "'"
StringLiteral  <- '"' StringPart* '"'
StringPart     <- Escape / EscapedDollar / Interpolation / StringScalar
EscapedDollar  <- "\\$"
Interpolation  <- "${" Expr "}"
ByteLiteral    <- 'b"' ByteElement* '"'
CharElement    <- Escape / !("'" / LineTerminator) .
StringScalar   <- !("\\" / "$" / '"' / LineTerminator) .
ByteElement    <- !"${" (PrintableAsciiExceptQuoteBackslash
                / "\\" ("n" / "r" / "t" / "0" / "\\" / '"')
                / "\\x" HexDigit HexDigit)
PrintableAsciiExceptQuoteBackslash <- [\u{20}-\u{7E}] except '"' and "\\"
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
ability abort as break cap const continue ctl def defer derive effect else enum
extend false effects fn for fun handler if impl in let loop match may_suspend mut
newtype next opaque pub resumes return struct trait true type use while with once open
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
DERIVE      <- "derive" !XID_Continue
EFFECT      <- "effect" !XID_Continue
EFFECTS     <- "effects" !XID_Continue
ELSE        <- "else" !XID_Continue
ENUM        <- "enum" !XID_Continue
EXTEND      <- "extend" !XID_Continue
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
NEWTYPE     <- "newtype" !XID_Continue
NEXT        <- "next" !XID_Continue
ONCE        <- "once" !XID_Continue
OPAQUE      <- "opaque" !XID_Continue
OPEN        <- "open" !XID_Continue
PUB         <- "pub" !XID_Continue
RESUMES     <- "resumes" !XID_Continue
RETURN      <- "return" !XID_Continue
STRUCT      <- "struct" !XID_Continue
TRAIT       <- "trait" !XID_Continue
TRUE        <- "true" !XID_Continue
TYPE        <- "type" !XID_Continue
USE         <- "use" !XID_Continue
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

`Interpolation` hole 使用与主 lexer相同的 token规则并以 nested-brace depth
匹配 closing `}`；string/comment/char内部 brace不改变 depth。lexer不得把 hole
作为 raw String token。`ByteLiteral`拒绝 raw non-ASCII、Unicode escape、`${` 与
line break。`CAP`、`DEFER`、`TILDE`仍保留 token仅供 recovery diagnostic，不能
出现在 accepted production。

=== 名称、可见性与声明 <surface-a-2>

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

TopLevelItem      <- UseDecl / ImplDecl / Visibility? NonImplDeclaration
NonImplDeclaration <- FunctionDecl
                   / ConstFunctionDecl
                   / ExtensionFunctionDecl
                   / StructDecl
                   / EnumDecl
                   / NewtypeDecl
                   / OpaqueTypeDecl
                   / TraitDecl
                   / AbilityDecl
                   / EffectDecl
                   / TypeAliasDecl
                   / ConstDecl

TypeHead          <- UpperIdent TypeParams?
TypeAliasDecl     <- TYPE TypeHead EQUAL Type SEMICOLON?
ConstDecl         <- CONST LowerIdent COLON Type EQUAL Expr SEMICOLON?
ConstFunctionDecl <- CONST FunctionDecl
ExtensionFunctionDecl <- ValidExtensionFunctionDecl
                       / InvalidExtensionSelfDecl
ValidExtensionFunctionDecl <- EXTEND DEF GenericClauses? LowerIdent
                              ExtensionParamList ARROW Type EffectAnnotation Block
InvalidExtensionSelfDecl <- EXTEND DEF GenericClauses?
                            (FunctionOwner COLONCOLON LowerIdent ParamList
                            / LowerIdent
                              (LPAREN RPAREN
                              / LPAREN !(LowerIdent COLON) Parameter
                                (COMMA Parameter)* COMMA? RPAREN))
                            ARROW Type EffectAnnotation Block
ExtensionParamList    <- LPAREN ExtensionSelfParameter
                         (COMMA Parameter)* COMMA? RPAREN
ExtensionSelfParameter <- LowerIdent COLON Type
UseDecl           <- USE UseTarget (AS LowerIdent)? SEMICOLON?
UseTarget         <- PackagePath COLONCOLON Name (COLONCOLON Name)*

StructDecl        <- STRUCT TypeHead LBRACE FieldDecl* RBRACE DeriveClause?
FieldDecl         <- Visibility? LowerIdent COLON Type
                     (EQUAL Expr)? (COMMA / SEMICOLON)?

EnumDecl          <- ENUM TypeHead LBRACE VariantDecl* RBRACE DeriveClause?
NewtypeDecl       <- NEWTYPE TypeHead LBRACE FieldDecl RBRACE DeriveClause?
OpaqueTypeDecl    <- OPAQUE TYPE TypeHead EQUAL Type SEMICOLON?
DeriveClause      <- DERIVE LPAREN TypeName
                     (COMMA TypeName)* COMMA? RPAREN
VariantDecl       <- UpperIdent VariantPayload?
                     (COMMA / SEMICOLON)?
VariantPayload    <- LPAREN TypeList? RPAREN
                   / LBRACE FieldDecl* RBRACE

TraitDecl         <- TRAIT TypeHead LBRACE TraitItem* RBRACE
TraitItem         <- MemberFunctionDecl
                   / MemberFunctionSignature
                   / TraitAssociatedTypeDecl
TraitAssociatedTypeDecl <- TYPE UpperIdent
                           (COLON TypeConstraintList)?
                           (EQUAL Type)? SEMICOLON?

AbilityDecl       <- ABILITY TypeHead LBRACE AbilityItem* RBRACE
AbilityItem       <- OperationDecl
                   / AbilityAssociatedTypeDecl
                   / AssociatedEffectDecl
                   / AssociatedRowDecl
AbilityAssociatedTypeDecl <- TYPE UpperIdent TypeParams?
                             (COLON TypeConstraintList)?
                             (EQUAL Type)? SEMICOLON?
AssociatedEffectDecl <- EFFECT UpperIdent TypeParams?
                        (COLON AbilityConstraintList)?
                        (EQUAL Type)? SEMICOLON?
AssociatedRowDecl <- EFFECTS UpperIdent
                     (COLON RowConstraintList)?
                     (EQUAL RowExpr)? SEMICOLON?

EffectDecl        <- EFFECT TypeHead EffectConformance?
                     LBRACE OperationDecl* RBRACE
EffectConformance <- COLON AbilityRef (PLUS AbilityRef)*

ImplDecl          <- Visibility? IMPL GenericClauses? Type FOR Type
                     LBRACE ImplItem* RBRACE
ImplItem          <- Visibility? (MemberFunctionDecl
                   / AssociatedTypeBinding
                   / AssociatedEffectBinding
                   / AssociatedRowBinding)
AssociatedTypeBinding   <- TYPE UpperIdent EQUAL Type SEMICOLON?
AssociatedEffectBinding <- EFFECT UpperIdent EQUAL Type SEMICOLON?
AssociatedRowBinding    <- EFFECTS UpperIdent EQUAL RowExpr SEMICOLON?

AbilityRef        <- Type
```

Package identity and dependency selection belong to the package manifest. 源文件通过
`@package::name` 和 `Type::member` 使用 package-qualified name；本 profile
不增加 wildcard import。`UseDecl`只绑定一个 exact declaration identity；若它是
extension function，该 local name（或 alias）也是唯一 enabled dot-name。Import
ordinary type/trait不会隐式激活 extension或 impl。

`ImplDecl` 是 ordinary trait与 ability target共享的 lossless CST shape。两个 optional
`Visibility` 只为 committed recovery保留；canonical impl与其每个 item都要求 modifier absent，
否则在 CST→HIR前报 `impl-visibility-not-allowed`。因此 `pub impl`/`pub(open) impl` 与
`impl T for U { pub def ... }` 都可稳定到同一 registered diagnostic，而不会退化为 generic parse error。
Resolver若把左侧 `Type` 解析为 ability，v1 必须在进入 body typechecking前拒绝
`independent-ability-impl-not-in-profile`；只有 #ref(<surface-4-5>) 的 effect-header
`EffectConformance` 产生 ability evidence。Parser recovery或 ordinary trait
target不能改变这个 kind-directed profile boundary。

`Visibility=pub(open)` 只适用于 trait/ability/effect；其它 declaration稳定
`open-visibility-not-applicable`。`NewtypeDecl`必须恰好一个 named stored field。
`OpaqueTypeDecl`只有 owner package可见 representation。`DeriveClause`只允许在
`StructDecl | EnumDecl | NewtypeDecl` closing brace后出现，trait path无重复；opaque/alias
的 Formal `derives` 必须为 `[]`。Component import/export
由 manifest选择 exact `pub def` path，不增加 source declaration production。
`ExtensionSelfParameter` 的 `LowerIdent` lexeme必须精确为 `self`，其 type就是
extension 的 resolved receiver `Self`；extension name不得是 qualified owner form。
缺失/改名该第一 parameter 或使用 qualified extension name 报
`extension-self-parameter-required`。
`InvalidExtensionSelfDecl` 只为这个 committed recovery存在：accepted branch先匹配 exact
unqualified name + nonempty first parameter；empty `()` 或 qualified `ValueName` 落入 recovery并报同一
diagnostic，node绝不进入 Surface HIR。`ValidExtensionFunctionDecl` 中 first parameter名不是 `self` 也在
CST→HIR gate拒绝。
Extension receiver可为任意 well-formed type，包括 primitive、tuple、function、
foreign nominal、capability与当前 generic type parameter；它不继承 trait impl的
orphan、nominal-head或 local-type限制。

Source declaration name sets必须 injective：同一 struct/newtype/record variant的 field、同一 enum的
variant、同一 trait的 associated Type与 method各自在自己的 namespace唯一；ability的 associated
Type/Effect/EffectRow共享一个 associated namespace，operation另成 namespace；effect own operation
name唯一。Associated item与 operation可因 kinded syntax不同而同 spelling；其它重复在 HIR
publication前确定性拒绝，不能靠 ordinal或后写覆盖。
每个 callable/trait method/operation/lambda 的 simple parameter source name同样 pairwise distinct，
因而产生的 `NamedOrPositionalV1.public_label` 也 pairwise distinct；两个同名 slot不能借
type、position或 default来消除 labelled-call 歧义。Pattern parameter仍按其 pattern binder-set exactness检查。

=== 形参、实参与约束 <surface-a-3>

表面的 `[...]` / `![...]` 是*形参绑定列表*，不是量词语法：

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
EffectConstructorParam <- UpperIdent BinderHoles
EffectAtomParam      <- UpperIdent (COLON AbilityConstraintList)?
BinderHoles          <- LBRACKET UNDERSCORE
                        (COMMA UNDERSCORE)* RBRACKET
AbilityConstraintList <- AbilityRef (PLUS AbilityRef)*
RowConstraintList    <- RowPredicate (PLUS RowPredicate)*
RowPredicate         <- UpperIdent LBRACKET PredicateArgList? RBRACKET
PredicateArgList     <- PredicateArg (COMMA PredicateArg)* COMMA?
GenericValueEnd      <- &(COMMA / RBRACKET)
PredicateArg         <- RowExpr GenericValueEnd / Type GenericValueEnd

TypeArgs             <- LBRACKET TypeArg
                        (COMMA TypeArg)* COMMA? RBRACKET
TypeArg              <- AssociatedArgument / Type / LowerIdent
AssociatedArgument   <- UpperIdent EQUAL AssociatedArgumentValue
AssociatedArgumentValue <- RowExpr GenericValueEnd / Type GenericValueEnd
EffectArgs           <- BANG LBRACKET EffectArg
                        (COMMA EffectArg)* COMMA? RBRACKET
EffectArg            <- RowExpr GenericValueEnd / Type GenericValueEnd

RemovedLabelledParameter <- LowerIdent TILDE COLON Type (EQUAL Expr)?
RemovedCapabilityMarker  <- CAP Type
```

`F`、`F[_]`、`..E` 分别绑定 `Effect`、effect constructor、`EffectRow`；
这由 binder shape 唯一决定。direct parameter `app : F` 是 term binder，不进入 generic
list。Surface为每个 `F`/`F[_]` 保留 exact constructor arity（0/underscore count），并把 atomic
`F` 的 ability constraints写入 Formal `DeclarationRequirementsV1.effect_parameters`；不能只降成一个
无 arity 的 binder。Ability constraint只允许 atomic `F : Ability[...]`；本 profile不定义
`F[_] : Ability` 的 pointwise higher-kinded evidence，constructor binder后跟 colon因此不进入
accepted grammar。每个 Type parameter的 ordinary trait constraints进入
`ordinary_traits`；每个 `..E` 与 normalized `Lacks` set进入同一 declaration的 `row_binders`。
这些三域 facts在 source order resolve 后按 Formal canonical order序列化，任何一个都不能依赖
source重读或 inferred package scan。每个 ordinary trait requirement进一步按 Formal rule分配
associated-Type hidden binders，每个 actual method use才分配自己的 monomorphic contract binder；lambda、
local declaration与 #ref(<surface-2-3>) 允许的 local scheme同样携带这些 structural Core obligations，并由 owning
callable fact的 exact `requirement_scopes`覆盖，不能因没有独立 package edge而丢失。每个 `F[_]` binder在所有 root/local/lambda/local-scheme scope唯一降为
`EffectConstructorBinderV3(slot,arity)`；application唯一降为
`EffectParameterConstructorV3(slot,arity)`，wrong slot/arity
不能回退 nominal constructor。Named/generic call给该 binder的 actual唯一进入
`EffectConstructorSubstitutionV3`：nominal Effect declaration或 caller constructor parameter都必须 exact
arity，不能塞入 ordinary Type/atomic Effect或 partial constructor。`PredicateArg`、`AssociatedArgumentValue` 与 `EffectArg` 的每个有序分支都在分支内
要求 `GenericValueEnd`，因而 `E1 | E2` 不会被首个 reference 截断，`(Int) -> Int`
也会在 row 分支的 end lookahead 失败后重试为 `Type`。对于完整 bare name/path 或
parenthesized reference 这类共同 syntax，CST保留同一 token span，resolver再由 owning
predicate/binder/declaration 的期待 kind 唯一重分类；不得由 PEG 分支顺序猜 kind。
`AssociatedArgument` 的 `UpperIdent =` lookahead先于 positional `Type`，但 owning constraint
domain决定它的唯一 meaning。在 `TypeConstraintList` 中 target必须解析为 ordinary trait，且 named
argument只可指该 trait的 zero-arity associated Type；它进入 Formal
`TraitGoalV1.associated_types`。在 `AbilityConstraintList` 或 effect header中 target必须解析为
ability，resolver才按 declaration把右侧重分类到 `Type`、`Effect` 或 `EffectRow`，并按 #ref(<surface-4-4>)
区分 partial generic constraint与 total concrete header。两个 domain都拒绝 wrong declaration kind、
unknown、duplicate与 value-kind mismatch，并稳定使用 `associated-contract-mismatch`；只有 concrete
ability header拒绝 missing-without-default。普通 nominal type application不能借 named argument
伪装成 constraint。只有 `AbilityItem` 中的 associated Type/Effect
declaration constraint与任意 nonempty associated `TypeParams` 走本 profile的 Kind-stage
registered stable reject；ordinary `TraitAssociatedTypeDecl` 的 zero-arity Type
constraint是 accepted trait contract。
每个 ordinary `TraitGoalV1` 的 associated equality在 resolve后按 trait item ordinal严格递增、
unique/in-range且 name/kind exact；associated-Type declaration的多个 constraint是 conjunction，按完整
normalized goal的 NFC+JCS semantic key排序且无重复，source order不得改变 wire bytes。

Recovery parser只在 parameter boundary构造
`RemovedLabelledParameter` 或 `RemovedCapabilityMarker`，并分别报
`surface-tilde-label-removed` 与 `surface-cap-marker-removed`。这两个 node
不可进入 accepted Surface HIR，也不得回退成普通 type/name parse。

`RowPredicate` 的通用 CST只为明确 profile boundary而保留。本 profile在 RowWF
只接受名称 `Lacks`、恰好一个可解析 row entry argument；`Has`、`All`、`Only`
以及其它名称统一拒绝 `row-predicate-not-in-profile`，不能由库中同名类型绕过。
