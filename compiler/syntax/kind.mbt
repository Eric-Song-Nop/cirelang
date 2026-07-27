///|
/// The stable lexical and concrete-syntax vocabulary shared by the lexer,
/// parser, formatter, and syntax-only LSP features.
///
/// Token kinds and node kinds intentionally share one enum so parser events
/// can be represented without an additional tag translation.
pub(all) enum SyntaxKind {
  // Lossless lexical stream.
  InvalidToken
  Eof
  Whitespace
  Newline
  LineComment
  BlockComment
  Identifier
  LowerIdentifier
  UpperIdentifier
  Underscore
  IntLiteral
  FloatLiteral
  StringLiteral
  CharLiteral
  // Keywords.
  KwAbort
  KwAs
  KwAsync
  KwBreak
  KwConst
  KwContinue
  KwCtl
  KwDefer
  KwEffect
  KwElse
  KwEnum
  KwExtern
  KwFalse
  KwFn
  KwFor
  KwFun
  KwHandler
  KwIf
  KwImpl
  KwIn
  KwLet
  KwLoop
  KwMatch
  KwMut
  KwOnce
  KwOpen
  KwPriv
  KwPub
  KwReturn
  KwStruct
  KwTest
  KwTrait
  KwTrue
  KwType
  KwUsing
  KwWhile
  KwWith
  // Delimiters and punctuation.
  At
  Bang
  Question
  Hash
  Dollar
  LParen
  RParen
  LBracket
  RBracket
  LBrace
  RBrace
  Comma
  Colon
  Semicolon
  Dot
  DotDot
  ColonColon
  Arrow
  FatArrow
  Equals
  EqEq
  BangEq
  Less
  LessEq
  Greater
  GreaterEq
  Plus
  Minus
  Star
  Slash
  Percent
  Amp
  AmpAmp
  Pipe
  PipePipe
  Caret
  Tilde
  // Lossless CST nodes.
  SourceFile
  ErrorNode
  Name
  QualifiedName
  Visibility
  TypeParameterList
  TypeParameter
  ConstraintList
  TypeArgumentList
  ParameterList
  Parameter
  ArgumentList
  Argument
  LabelledArgument
  PatternList
  TypeReference
  FunctionType
  EffectAnnotation
  EffectRow
  EffectRowItem
  EffectFamilyRowItem
  NamedCapabilityRowItem
  OpenEffectRowItem
  DiagnosticEffectRowItem
  EffectDeclaration
  EffectTraitDeclaration
  OperationDeclaration
  FunctionDeclaration
  StructDeclaration
  EnumDeclaration
  TraitDeclaration
  ImplDeclaration
  BlockExpression
  ParenthesizedExpression
  LiteralExpression
  NameExpression
  CallExpression
  MethodExpression
  IndexExpression
  LambdaExpression
  TrailingLambdaExpression
  HandlerExpression
  HandlerClause
  ContinuationBinder
  ReturnClause
  WithExpression
  IfExpression
  MatchExpression
  MatchArm
  LetStatement
  ExpressionStatement
  Pattern
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn SyntaxKind::is_node(self : SyntaxKind) -> Bool {
  match self {
    SourceFile
    | ErrorNode
    | Name
    | QualifiedName
    | Visibility
    | TypeParameterList
    | TypeParameter
    | ConstraintList
    | TypeArgumentList
    | ParameterList
    | Parameter
    | ArgumentList
    | Argument
    | LabelledArgument
    | PatternList
    | TypeReference
    | FunctionType
    | EffectAnnotation
    | EffectRow
    | EffectRowItem
    | EffectFamilyRowItem
    | NamedCapabilityRowItem
    | OpenEffectRowItem
    | DiagnosticEffectRowItem
    | EffectDeclaration
    | EffectTraitDeclaration
    | OperationDeclaration
    | FunctionDeclaration
    | StructDeclaration
    | EnumDeclaration
    | TraitDeclaration
    | ImplDeclaration
    | BlockExpression
    | ParenthesizedExpression
    | LiteralExpression
    | NameExpression
    | CallExpression
    | MethodExpression
    | IndexExpression
    | LambdaExpression
    | TrailingLambdaExpression
    | HandlerExpression
    | HandlerClause
    | ContinuationBinder
    | ReturnClause
    | WithExpression
    | IfExpression
    | MatchExpression
    | MatchArm
    | LetStatement
    | ExpressionStatement
    | Pattern => true
    _ => false
  }
}

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  !self.is_node()
}

///|
pub fn SyntaxKind::is_trivia(self : SyntaxKind) -> Bool {
  match self {
    Whitespace | Newline | LineComment | BlockComment => true
    _ => false
  }
}

///|
pub fn SyntaxKind::is_literal(self : SyntaxKind) -> Bool {
  match self {
    IntLiteral
    | FloatLiteral
    | StringLiteral
    | CharLiteral
    | KwTrue
    | KwFalse => true
    _ => false
  }
}

///|
pub fn SyntaxKind::is_keyword(self : SyntaxKind) -> Bool {
  match self {
    KwAbort
    | KwAs
    | KwAsync
    | KwBreak
    | KwConst
    | KwContinue
    | KwCtl
    | KwDefer
    | KwEffect
    | KwElse
    | KwEnum
    | KwExtern
    | KwFalse
    | KwFn
    | KwFor
    | KwFun
    | KwHandler
    | KwIf
    | KwImpl
    | KwIn
    | KwLet
    | KwLoop
    | KwMatch
    | KwMut
    | KwOnce
    | KwOpen
    | KwPriv
    | KwPub
    | KwReturn
    | KwStruct
    | KwTest
    | KwTrait
    | KwTrue
    | KwType
    | KwUsing
    | KwWhile
    | KwWith => true
    _ => false
  }
}

///|
pub fn SyntaxKind::is_punctuation(self : SyntaxKind) -> Bool {
  match self {
    At
    | Bang
    | Question
    | Hash
    | Dollar
    | LParen
    | RParen
    | LBracket
    | RBracket
    | LBrace
    | RBrace
    | Comma
    | Colon
    | Semicolon
    | Dot
    | DotDot
    | ColonColon
    | Arrow
    | FatArrow
    | Equals
    | EqEq
    | BangEq
    | Less
    | LessEq
    | Greater
    | GreaterEq
    | Plus
    | Minus
    | Star
    | Slash
    | Percent
    | Amp
    | AmpAmp
    | Pipe
    | PipePipe
    | Caret
    | Tilde => true
    _ => false
  }
}

///|
/// Returns the source spelling for a keyword or fixed punctuation token.
pub fn SyntaxKind::fixed_text(self : SyntaxKind) -> String? {
  match self {
    KwAbort => Some("abort")
    KwAs => Some("as")
    KwAsync => Some("async")
    KwBreak => Some("break")
    KwConst => Some("const")
    KwContinue => Some("continue")
    KwCtl => Some("ctl")
    KwDefer => Some("defer")
    KwEffect => Some("effect")
    KwElse => Some("else")
    KwEnum => Some("enum")
    KwExtern => Some("extern")
    KwFalse => Some("false")
    KwFn => Some("fn")
    KwFor => Some("for")
    KwFun => Some("fun")
    KwHandler => Some("handler")
    KwIf => Some("if")
    KwImpl => Some("impl")
    KwIn => Some("in")
    KwLet => Some("let")
    KwLoop => Some("loop")
    KwMatch => Some("match")
    KwMut => Some("mut")
    KwOnce => Some("once")
    KwOpen => Some("open")
    KwPriv => Some("priv")
    KwPub => Some("pub")
    KwReturn => Some("return")
    KwStruct => Some("struct")
    KwTest => Some("test")
    KwTrait => Some("trait")
    KwTrue => Some("true")
    KwType => Some("type")
    KwUsing => Some("using")
    KwWhile => Some("while")
    KwWith => Some("with")
    At => Some("@")
    Bang => Some("!")
    Question => Some("?")
    Hash => Some("#")
    Dollar => Some("$")
    LParen => Some("(")
    RParen => Some(")")
    LBracket => Some("[")
    RBracket => Some("]")
    LBrace => Some("{")
    RBrace => Some("}")
    Comma => Some(",")
    Colon => Some(":")
    Semicolon => Some(";")
    Dot => Some(".")
    DotDot => Some("..")
    ColonColon => Some("::")
    Arrow => Some("->")
    FatArrow => Some("=>")
    Equals => Some("=")
    EqEq => Some("==")
    BangEq => Some("!=")
    Less => Some("<")
    LessEq => Some("<=")
    Greater => Some(">")
    GreaterEq => Some(">=")
    Plus => Some("+")
    Minus => Some("-")
    Star => Some("*")
    Slash => Some("/")
    Percent => Some("%")
    Amp => Some("&")
    AmpAmp => Some("&&")
    Pipe => Some("|")
    PipePipe => Some("||")
    Caret => Some("^")
    Tilde => Some("~")
    Underscore => Some("_")
    _ => None
  }
}

///|
/// Maps an identifier spelling to its keyword kind, if it is reserved.
pub fn keyword_kind(text : StringView) -> SyntaxKind? {
  match text {
    "abort" => Some(KwAbort)
    "as" => Some(KwAs)
    "async" => Some(KwAsync)
    "break" => Some(KwBreak)
    "const" => Some(KwConst)
    "continue" => Some(KwContinue)
    "ctl" => Some(KwCtl)
    "defer" => Some(KwDefer)
    "effect" => Some(KwEffect)
    "else" => Some(KwElse)
    "enum" => Some(KwEnum)
    "extern" => Some(KwExtern)
    "false" => Some(KwFalse)
    "fn" => Some(KwFn)
    "for" => Some(KwFor)
    "fun" => Some(KwFun)
    "handler" => Some(KwHandler)
    "if" => Some(KwIf)
    "impl" => Some(KwImpl)
    "in" => Some(KwIn)
    "let" => Some(KwLet)
    "loop" => Some(KwLoop)
    "match" => Some(KwMatch)
    "mut" => Some(KwMut)
    "once" => Some(KwOnce)
    "open" => Some(KwOpen)
    "priv" => Some(KwPriv)
    "pub" => Some(KwPub)
    "return" => Some(KwReturn)
    "struct" => Some(KwStruct)
    "test" => Some(KwTest)
    "trait" => Some(KwTrait)
    "true" => Some(KwTrue)
    "type" => Some(KwType)
    "using" => Some(KwUsing)
    "while" => Some(KwWhile)
    "with" => Some(KwWith)
    _ => None
  }
}

///|
/// A deterministic snake-case name used by syntax snapshots.
pub fn SyntaxKind::wire_name(self : SyntaxKind) -> String {
  match self {
    InvalidToken => "invalid_token"
    Eof => "eof"
    Whitespace => "whitespace"
    Newline => "newline"
    LineComment => "line_comment"
    BlockComment => "block_comment"
    Identifier => "identifier"
    LowerIdentifier => "lower_identifier"
    UpperIdentifier => "upper_identifier"
    Underscore => "underscore"
    IntLiteral => "int_literal"
    FloatLiteral => "float_literal"
    StringLiteral => "string_literal"
    CharLiteral => "char_literal"
    KwAbort => "kw_abort"
    KwAs => "kw_as"
    KwAsync => "kw_async"
    KwBreak => "kw_break"
    KwConst => "kw_const"
    KwContinue => "kw_continue"
    KwCtl => "kw_ctl"
    KwDefer => "kw_defer"
    KwEffect => "kw_effect"
    KwElse => "kw_else"
    KwEnum => "kw_enum"
    KwExtern => "kw_extern"
    KwFalse => "kw_false"
    KwFn => "kw_fn"
    KwFor => "kw_for"
    KwFun => "kw_fun"
    KwHandler => "kw_handler"
    KwIf => "kw_if"
    KwImpl => "kw_impl"
    KwIn => "kw_in"
    KwLet => "kw_let"
    KwLoop => "kw_loop"
    KwMatch => "kw_match"
    KwMut => "kw_mut"
    KwOnce => "kw_once"
    KwOpen => "kw_open"
    KwPriv => "kw_priv"
    KwPub => "kw_pub"
    KwReturn => "kw_return"
    KwStruct => "kw_struct"
    KwTest => "kw_test"
    KwTrait => "kw_trait"
    KwTrue => "kw_true"
    KwType => "kw_type"
    KwUsing => "kw_using"
    KwWhile => "kw_while"
    KwWith => "kw_with"
    At => "at"
    Bang => "bang"
    Question => "question"
    Hash => "hash"
    Dollar => "dollar"
    LParen => "l_paren"
    RParen => "r_paren"
    LBracket => "l_bracket"
    RBracket => "r_bracket"
    LBrace => "l_brace"
    RBrace => "r_brace"
    Comma => "comma"
    Colon => "colon"
    Semicolon => "semicolon"
    Dot => "dot"
    DotDot => "dot_dot"
    ColonColon => "colon_colon"
    Arrow => "arrow"
    FatArrow => "fat_arrow"
    Equals => "equals"
    EqEq => "eq_eq"
    BangEq => "bang_eq"
    Less => "less"
    LessEq => "less_eq"
    Greater => "greater"
    GreaterEq => "greater_eq"
    Plus => "plus"
    Minus => "minus"
    Star => "star"
    Slash => "slash"
    Percent => "percent"
    Amp => "amp"
    AmpAmp => "amp_amp"
    Pipe => "pipe"
    PipePipe => "pipe_pipe"
    Caret => "caret"
    Tilde => "tilde"
    SourceFile => "source_file"
    ErrorNode => "error_node"
    Name => "name"
    QualifiedName => "qualified_name"
    Visibility => "visibility"
    TypeParameterList => "type_parameter_list"
    TypeParameter => "type_parameter"
    ConstraintList => "constraint_list"
    TypeArgumentList => "type_argument_list"
    ParameterList => "parameter_list"
    Parameter => "parameter"
    ArgumentList => "argument_list"
    Argument => "argument"
    LabelledArgument => "labelled_argument"
    PatternList => "pattern_list"
    TypeReference => "type_reference"
    FunctionType => "function_type"
    EffectAnnotation => "effect_annotation"
    EffectRow => "effect_row"
    EffectRowItem => "effect_row_item"
    EffectFamilyRowItem => "effect_family_row_item"
    NamedCapabilityRowItem => "named_capability_row_item"
    OpenEffectRowItem => "open_effect_row_item"
    DiagnosticEffectRowItem => "diagnostic_effect_row_item"
    EffectDeclaration => "effect_declaration"
    EffectTraitDeclaration => "effect_trait_declaration"
    OperationDeclaration => "operation_declaration"
    FunctionDeclaration => "function_declaration"
    StructDeclaration => "struct_declaration"
    EnumDeclaration => "enum_declaration"
    TraitDeclaration => "trait_declaration"
    ImplDeclaration => "impl_declaration"
    BlockExpression => "block_expression"
    ParenthesizedExpression => "parenthesized_expression"
    LiteralExpression => "literal_expression"
    NameExpression => "name_expression"
    CallExpression => "call_expression"
    MethodExpression => "method_expression"
    IndexExpression => "index_expression"
    LambdaExpression => "lambda_expression"
    TrailingLambdaExpression => "trailing_lambda_expression"
    HandlerExpression => "handler_expression"
    HandlerClause => "handler_clause"
    ContinuationBinder => "continuation_binder"
    ReturnClause => "return_clause"
    WithExpression => "with_expression"
    IfExpression => "if_expression"
    MatchExpression => "match_expression"
    MatchArm => "match_arm"
    LetStatement => "let_statement"
    ExpressionStatement => "expression_statement"
    Pattern => "pattern"
  }
}
