///|
fn is_name_kind(kind : @syntax.SyntaxKind) -> Bool {
  match kind {
    Identifier | LowerIdentifier | UpperIdentifier | Underscore => true
    _ => false
  }
}

///|
fn is_operation_mode(kind : @syntax.SyntaxKind) -> Bool {
  match kind {
    KwAbort | KwOnce | KwFun | KwCtl => true
    _ => false
  }
}

///|
fn Parser::significant_token_at(
  self : Parser,
  distance : Int,
) -> @syntax.Token? {
  guard distance >= 0
  let tokens = self.token_snapshot()
  let mut remaining = distance
  for index = self.significant_index()
      index < tokens.length()
      index = index + 1 {
    guard tokens.token_at(index) is Some(token) else { continue }
    if !token.is_trivia() {
      if remaining == 0 {
        return Some(token)
      }
      remaining = remaining - 1
    }
  }
  None
}

///|
fn Parser::significant_kind_at(
  self : Parser,
  distance : Int,
) -> @syntax.SyntaxKind? {
  self.significant_token_at(distance).map(token => token.kind())
}

///|
fn Parser::visibility_follower(self : Parser) -> @syntax.SyntaxKind? {
  guard self.at(KwPub) else { return self.current_kind() }
  if self.significant_kind_at(1) == Some(LParen) &&
    self.significant_kind_at(2) == Some(KwOpen) &&
    self.significant_kind_at(3) == Some(RParen) {
    self.significant_kind_at(4)
  } else {
    self.significant_kind_at(1)
  }
}

///|
fn Parser::span(self : Parser, range : @source.TextRange) -> @source.Span {
  @source.Span::new(self.token_snapshot().source(), range)
}

///|
fn Parser::point_range(self : Parser) -> @source.TextRange {
  @source.TextRange::empty(self.current_offset())
}

///|
fn Parser::report(
  self : Parser,
  code : String,
  message : String,
  range : @source.TextRange,
  label_message : String,
) -> Unit {
  self.emit_diagnostic(
    @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new(code),
      Parse,
      Error,
      message,
      @diagnostic.Label::primary(self.span(range), label_message),
      self.token_snapshot().revision(),
    ),
  )
}

///|
fn Parser::report_unexpected(self : Parser, context : String) -> Unit {
  let range = match self.current_token() {
    Some(token) => token.range()
    None => self.point_range()
  }
  self.report(
    "CIRE-P0002",
    "unexpected token while parsing \{context}",
    range,
    "this token is not valid in \{context}",
  )
}

///|
/// Consumes exactly one unexpected significant token as an error node.
///
/// List recovery uses this as its final bug guard after normal stop-before-sync
/// recovery and delimiter handling both failed to move the cursor.
fn Parser::recover_one(self : Parser) -> Bool {
  self.clear_failure_commit()
  guard !self.at(Eof) && self.current_kind() is Some(_) else { return false }
  self.start_node(ErrorNode)
  ignore(self.bump())
  self.finish_node()
  true
}

///|
fn Parser::expect_or_missing(
  self : Parser,
  kind : @syntax.SyntaxKind,
  expected : String,
) -> Bool {
  if self.eat(kind) {
    true
  } else {
    ignore(self.fail_expected(expected))
    self.missing(kind)
    self.report(
      "CIRE-P0001",
      "expected \{expected}",
      self.point_range(),
      "insert \{expected} here",
    )
    false
  }
}

///|
fn Parser::parse_name(self : Parser, expected : String) -> Bool {
  self.start_node(Name)
  let matched = match self.current_kind() {
    Some(kind) if is_name_kind(kind) => {
      ignore(self.bump())
      true
    }
    _ => {
      ignore(self.fail_expected(expected))
      self.report(
        "CIRE-P0001",
        "expected \{expected}",
        self.point_range(),
        "write \{expected} here",
      )
      false
    }
  }
  self.finish_node()
  matched
}

///|
fn Parser::parse_visibility(self : Parser) -> Unit {
  guard self.at(KwPub) else { return }
  self.start_node(Visibility)
  ignore(self.bump())
  if self.eat(LParen) {
    ignore(self.expect_or_missing(KwOpen, "`open`"))
    ignore(self.expect_or_missing(RParen, "`)`"))
  }
  self.finish_node()
}

///|
fn Parser::parse_type_parameter_list(self : Parser) -> Unit {
  guard self.at(LBracket) else { return }
  self.start_node(TypeParameterList)
  ignore(self.bump())
  while !self.at(RBracket) && !self.at(Eof) {
    let mark = self.progress_mark()
    self.start_node(TypeParameter)
    let has_name = self.parse_name("a type parameter")
    let has_bound = if self.eat(Colon) {
      self.parse_type_reference()
    } else {
      true
    }
    if (!has_name || !has_bound) &&
      !self.at(Comma) &&
      !self.at(RBracket) &&
      !self.at(Eof) {
      ignore(self.recover_until([Comma, RBracket, Eof]))
    }
    self.finish_node()
    if self.eat(Comma) {
      ()
    } else if !self.at(RBracket) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "type parameter list") {
      ignore(self.recover_one())
    }
  }
  ignore(self.expect_or_missing(RBracket, "`]`"))
  self.finish_node()
}

///|
fn Parser::parse_type_argument_list(self : Parser) -> Unit {
  guard self.at(LBracket) else { return }
  self.start_node(TypeArgumentList)
  ignore(self.bump())
  while !self.at(RBracket) && !self.at(Eof) {
    let mark = self.progress_mark()
    if !self.parse_type_reference() &&
      !self.at(Comma) &&
      !self.at(RBracket) &&
      !self.at(Eof) {
      ignore(self.recover_until([Comma, RBracket, Eof]))
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(RBracket) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "type argument list") {
      ignore(self.recover_one())
    }
  }
  ignore(self.expect_or_missing(RBracket, "`]`"))
  self.finish_node()
}

///|
fn Parser::parse_qualified_type_name(self : Parser) -> Bool {
  self.start_node(QualifiedName)
  let mut matched = false
  if self.eat(At) {
    matched = self.parse_name("a package name")
    while self.eat(Dot) {
      ignore(self.parse_name("a qualified name segment"))
    }
  } else {
    matched = self.parse_name("a type name")
    while self.eat(ColonColon) {
      ignore(self.parse_name("a qualified name segment"))
    }
  }
  self.finish_node()
  matched
}

///|
fn Parser::parse_function_type(self : Parser) -> Bool {
  self.start_node(FunctionType)
  ignore(self.expect_or_missing(LParen, "`(`"))
  while !self.at(RParen) && !self.at(Eof) {
    let mark = self.progress_mark()
    if !self.parse_type_reference() &&
      !self.at(Comma) &&
      !self.at(RParen) &&
      !self.at(Arrow) &&
      !self.at(Eof) {
      ignore(self.recover_until([Comma, RParen, Arrow, Eof]))
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(RParen) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "function parameter types") {
      ignore(self.recover_one())
    }
  }
  ignore(self.expect_or_missing(RParen, "`)`"))
  ignore(self.expect_or_missing(Arrow, "`->`"))
  let result = self.parse_type_reference()
  self.parse_effect_annotation()
  self.finish_node()
  result
}

///|
fn Parser::parse_type_reference(self : Parser) -> Bool {
  self.start_node(TypeReference)
  let matched = if self.at(LParen) {
    self.parse_function_type()
  } else {
    match self.current_kind() {
      Some(At)
      | Some(Identifier)
      | Some(LowerIdentifier)
      | Some(UpperIdentifier)
      | Some(Underscore) => {
        let named = self.parse_qualified_type_name()
        self.parse_type_argument_list()
        named
      }
      _ => {
        ignore(self.fail_expected("a type"))
        self.report(
          "CIRE-P0001",
          "expected a type",
          self.point_range(),
          "write a type here",
        )
        false
      }
    }
  }
  self.finish_node()
  matched
}

///|
fn Parser::parse_parameter_list(self : Parser) -> Unit {
  self.start_node(ParameterList)
  ignore(self.expect_or_missing(LParen, "`(`"))
  while !self.at(RParen) && !self.at(Eof) {
    let mark = self.progress_mark()
    self.start_node(Parameter)
    let has_name = self.parse_name("a parameter name")
    ignore(self.eat(Tilde))
    ignore(self.expect_or_missing(Colon, "`:`"))
    let has_type = self.parse_type_reference()
    if (!has_name || !has_type) &&
      !self.at(Comma) &&
      !self.at(RParen) &&
      !self.at(Eof) {
      ignore(self.recover_until([Comma, RParen, Eof]))
    }
    self.finish_node()
    if self.eat(Comma) {
      ()
    } else if !self.at(RParen) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "parameter list") {
      ignore(self.recover_one())
    }
  }
  ignore(self.expect_or_missing(RParen, "`)`"))
  self.finish_node()
}

///|
fn Parser::is_diagnostic_read_capability(self : Parser) -> Bool {
  guard self.significant_token_at(0) is Some(family) &&
    family.kind() == UpperIdentifier &&
    family.text() == "Read" &&
    self.significant_kind_at(1) == Some(LBracket) &&
    self.significant_token_at(2) is Some(capability) &&
    capability.kind() == LowerIdentifier &&
    self.significant_kind_at(3) == Some(RBracket) else {
    return false
  }
  match self.significant_kind_at(4) {
    Some(Comma) | Some(RBrace) => true
    _ => false
  }
}

///|
fn Parser::parse_diagnostic_read_capability(self : Parser) -> Unit {
  let start = self.current_offset()
  self.start_node(DiagnosticEffectRowItem)
  ignore(self.bump())
  ignore(self.bump())
  guard self.current_token() is Some(capability)
  ignore(self.bump())
  guard self.current_token() is Some(close)
  ignore(self.bump())
  self.finish_node()
  let range = @source.TextRange::new(start, close.range().end())
  let replacement = capability.text()
  let diagnostic = @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("CIRE-P0101"),
      Parse,
      Error,
      "`Read[\{replacement}]` is diagnostic-only syntax",
      @diagnostic.Label::primary(
        self.span(range),
        "write the named capability directly in the effect row",
      ),
      self.token_snapshot().revision(),
    )
    .with_note(
      "`Read[app]` may appear in compiler explanations, but source rows use `{app}`.",
    )
    .with_fix(
      @diagnostic.Fix::new(
        "Replace with named capability `\{replacement}`",
        Always,
        [
          @source.TextEdit::new(
            self.token_snapshot().source(),
            self.token_snapshot().revision(),
            range,
            replacement,
          ),
        ],
      ),
    )
  self.emit_diagnostic(diagnostic)
}

///|
fn Parser::parse_effect_row_item(self : Parser) -> Bool {
  self.start_node(EffectRowItem)
  let matched = if self.at(DotDot) {
    self.start_node(OpenEffectRowItem)
    ignore(self.bump())
    ignore(self.parse_type_reference())
    self.finish_node()
    true
  } else if self.is_diagnostic_read_capability() {
    self.parse_diagnostic_read_capability()
    true
  } else {
    match self.current_kind() {
      Some(LowerIdentifier) => {
        self.start_node(NamedCapabilityRowItem)
        ignore(self.bump())
        self.finish_node()
        true
      }
      Some(At) | Some(Identifier) | Some(UpperIdentifier) => {
        self.start_node(EffectFamilyRowItem)
        let result = self.parse_type_reference()
        self.finish_node()
        result
      }
      _ => {
        ignore(self.fail_expected("an effect row item"))
        self.report_unexpected("an effect row")
        false
      }
    }
  }
  self.finish_node()
  matched
}

///|
fn Parser::parse_effect_row(self : Parser) -> Unit {
  self.start_node(EffectRow)
  ignore(self.expect_or_missing(LBrace, "`{`"))
  while !self.at(RBrace) && !self.at(Eof) {
    let mark = self.progress_mark()
    if !self.parse_effect_row_item() &&
      !self.at(Comma) &&
      !self.at(RBrace) &&
      !self.at(Eof) {
      ignore(self.recover_until([Comma, RBrace, Eof]))
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(RBrace) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "effect row") {
      ignore(self.recover_one())
    }
  }
  ignore(self.expect_or_missing(RBrace, "`}`"))
  self.finish_node()
}

///|
fn Parser::parse_effect_annotation(self : Parser) -> Unit {
  guard self.at(Bang) else { return }
  self.start_node(EffectAnnotation)
  ignore(self.bump())
  if self.at(LBrace) {
    self.parse_effect_row()
  } else {
    ignore(self.parse_type_reference())
  }
  self.finish_node()
}

///|
fn Parser::parse_operation_declaration(self : Parser) -> Bool {
  guard self.current_kind() is Some(mode) && is_operation_mode(mode) else {
    return false
  }
  let entered = self.enter_rule(
    RuleId::new("operation_declaration"),
    StopBeforeTrailingBlock,
    "operation declaration",
  )
  guard entered else { return false }
  self.start_node(OperationDeclaration)
  ignore(self.bump())
  self.cut()
  self.parse_type_parameter_list()
  ignore(self.parse_name("an operation name"))
  self.parse_parameter_list()
  ignore(self.expect_or_missing(Arrow, "`->`"))
  ignore(self.parse_type_reference())
  self.parse_effect_annotation()
  ignore(self.eat(Semicolon))
  self.finish_node()
  self.leave_rule(true)
  true
}

///|
fn Parser::parse_effect_declaration(self : Parser) -> Bool {
  let entered = self.enter_rule(
    RuleId::new("effect_declaration"),
    StopBeforeTrailingBlock,
    "effect declaration",
  )
  guard entered else { return false }
  self.start_node(EffectDeclaration)
  self.parse_visibility()
  ignore(self.expect_or_missing(KwEffect, "`effect`"))
  self.cut()
  ignore(self.parse_name("an effect name"))
  self.parse_type_parameter_list()
  ignore(self.expect_or_missing(LBrace, "`{`"))
  while !self.at(RBrace) && !self.at(Eof) {
    let mark = self.progress_mark()
    if is_operation_mode(self.current_kind().unwrap_or(Eof)) {
      ignore(self.parse_operation_declaration())
    } else {
      self.report_unexpected("an effect declaration")
      ignore(self.recover_until([KwAbort, KwOnce, KwFun, KwCtl, RBrace, Eof]))
    }
    if !self.require_progress(mark, "effect declaration") {
      ignore(self.recover_until([KwAbort, KwOnce, KwFun, KwCtl, RBrace, Eof]))
    }
  }
  ignore(self.expect_or_missing(RBrace, "`}`"))
  self.finish_node()
  self.leave_rule(true)
  true
}

///|
fn Parser::parse_function_declaration(self : Parser) -> Bool {
  let entered = self.enter_rule(
    RuleId::new("function_declaration"),
    StopBeforeTrailingBlock,
    "function declaration",
  )
  guard entered else { return false }
  self.start_node(FunctionDeclaration)
  self.parse_visibility()
  ignore(self.expect_or_missing(KwFn, "`fn`"))
  self.cut()
  self.parse_type_parameter_list()
  ignore(self.parse_name("a function name"))
  self.parse_parameter_list()
  ignore(self.expect_or_missing(Arrow, "`->`"))
  ignore(self.parse_type_reference())
  self.parse_effect_annotation()
  ignore(self.parse_required_block_expression("a function body"))
  self.finish_node()
  self.leave_rule(true)
  true
}

///|
fn Parser::parse_source_file(self : Parser) -> Unit {
  self.start_node(SourceFile)
  while !self.at(Eof) {
    let mark = self.progress_mark()
    let parsed = match self.current_kind() {
      Some(KwEffect) => self.parse_effect_declaration()
      Some(KwFn) => self.parse_function_declaration()
      Some(KwPub) =>
        match self.visibility_follower() {
          Some(KwEffect) => self.parse_effect_declaration()
          Some(KwFn) => self.parse_function_declaration()
          _ => false
        }
      _ => false
    }
    if !parsed {
      self.report_unexpected("the source file")
      ignore(self.recover_with_progress_until([KwPub, KwEffect, KwFn, Eof]))
    }
    if !self.require_progress(mark, "source file") {
      ignore(self.recover_with_progress_until([KwPub, KwEffect, KwFn, Eof]))
    }
  }
  ignore(self.bump())
  self.finish_node()
}

///|
fn fallback_green(tokens : @syntax.TokenSnapshot) -> @syntax.GreenNode {
  let events : Array[@syntax.TreeEvent] = [Start(SourceFile)]
  for token in tokens.tokens() {
    events.push(Token(token))
  }
  events.push(Finish)
  @syntax.build_green(events) catch {
    _ => @syntax.GreenNode::new(SourceFile, [])
  }
}

///|
fn Parser::report_internal_tree_failure(self : Parser) -> Unit {
  self.emit_diagnostic(
    @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("CIRE-P9999"),
      Parse,
      Error,
      "the parser could not construct its concrete syntax tree",
      @diagnostic.Label::primary(
        self.span(self.point_range()),
        "an internal parser invariant failed near here",
      ),
      self.token_snapshot().revision(),
    ).with_note(
      "This is a compiler bug, not a source-language error; please report it.",
    ),
  )
}

///|
pub fn parse_lexed(lexed : @lexer.LexSnapshot) -> ParseSnapshot {
  let parser = Parser::new(lexed.tokens())
  parser.parse_source_file()
  let green = @syntax.build_green(parser.events()) catch {
    _ => {
      parser.report_internal_tree_failure()
      fallback_green(lexed.tokens())
    }
  }
  let tree = @syntax.SyntaxTree::new(lexed.source(), lexed.revision(), green)
  let diagnostics = lexed.diagnostics()
  for diagnostic in parser.diagnostics() {
    diagnostics.push(diagnostic)
  }
  ParseSnapshot::new(
    lexed.source(),
    lexed.revision(),
    tree,
    diagnostics,
    parser.failure(),
  )
}

///|
pub fn parse(source : @source.SourceSnapshot) -> ParseSnapshot {
  parse_lexed(@lexer.lex(source))
}

///|
/// Incremental parser facade shared by batch and LSP clients.
///
/// This first implementation performs a complete parse after asking the
/// incremental lexer facade to validate the revision-checked edit. The API is
/// stable for future reparse-island and green-subtree reuse work.
pub fn reparse(
  previous : ParseSnapshot,
  updated : @source.SourceSnapshot,
  edit : @source.TextEdit,
) -> ParseSnapshot raise @lexer.RelexError {
  let previous_source = @source.SourceSnapshot::new(
    previous.source(),
    previous.revision(),
    updated.logical_path(),
    previous.source_text(),
  )
  let previous_lexed = @lexer.lex(previous_source)
  let updated_lexed = @lexer.relex(previous_lexed, updated, edit)
  parse_lexed(updated_lexed)
}
