///|
fn is_expression_start(kind : @syntax.SyntaxKind) -> Bool {
  match kind {
    At
    | Identifier
    | LowerIdentifier
    | UpperIdentifier
    | IntLiteral
    | FloatLiteral
    | StringLiteral
    | CharLiteral
    | KwTrue
    | KwFalse
    | LParen
    | LBrace => true
    _ => false
  }
}

///|
fn is_pattern_start(kind : @syntax.SyntaxKind) -> Bool {
  match kind {
    Identifier
    | LowerIdentifier
    | UpperIdentifier
    | Underscore
    | IntLiteral
    | FloatLiteral
    | StringLiteral
    | CharLiteral
    | KwTrue
    | KwFalse => true
    _ => false
  }
}

///|
fn Parser::report_expected_expression(self : Parser, context : String) -> Unit {
  ignore(self.fail_expected("an expression"))
  self.report(
    "CIRE-P0001",
    "expected an expression",
    self.point_range(),
    "write an expression \{context}",
  )
}

///|
fn Parser::parse_expression(
  self : Parser,
  flavor : ParseFlavor,
) -> CompletedMarker? {
  let entered = self.enter_rule(RuleId::new("expression"), flavor, "expression")
  guard entered else { return None }
  let result = self.parse_postfix_expression(flavor)
  self.leave_rule(result is Some(_))
  result
}

///|
fn Parser::parse_postfix_expression(
  self : Parser,
  flavor : ParseFlavor,
) -> CompletedMarker? {
  guard self.parse_primary_expression() is Some(initial) else { return None }
  let mut expression = initial
  for ;; {
    if self.at(Dot) {
      let marker = self.precede(expression)
      ignore(self.bump())
      ignore(self.parse_name("a member name"))
      expression = self.complete_marker(marker, MethodExpression)
    } else if self.at(LParen) {
      let marker = self.precede(expression)
      self.parse_argument_list()
      if flavor == AllowTrailingBlock && self.at(LBrace) {
        self.parse_trailing_lambda_expression()
      }
      expression = self.complete_marker(marker, CallExpression)
    } else if flavor == AllowTrailingBlock && self.at(LBrace) {
      let marker = self.precede(expression)
      self.parse_trailing_lambda_expression()
      expression = self.complete_marker(marker, CallExpression)
    } else {
      break
    }
  }
  Some(expression)
}

///|
fn Parser::parse_primary_expression(self : Parser) -> CompletedMarker? {
  match self.current_kind() {
    Some(kind) if kind.is_literal() => {
      let marker = self.start_marker()
      ignore(self.bump())
      Some(self.complete_marker(marker, LiteralExpression))
    }
    Some(At)
    | Some(Identifier)
    | Some(LowerIdentifier)
    | Some(UpperIdentifier) => Some(self.parse_name_expression())
    Some(LParen) => Some(self.parse_parenthesized_expression())
    Some(LBrace) => self.parse_block_expression()
    _ => None
  }
}

///|
fn Parser::parse_name_expression(self : Parser) -> CompletedMarker {
  let marker = self.start_marker()
  self.start_node(QualifiedName)
  if self.eat(At) {
    ignore(self.parse_name("a package name"))
    while self.eat(Dot) {
      ignore(self.parse_name("a qualified name segment"))
    }
  } else {
    ignore(self.parse_name("a name"))
    while self.eat(ColonColon) {
      ignore(self.parse_name("a qualified name segment"))
    }
  }
  self.finish_node()
  self.complete_marker(marker, NameExpression)
}

///|
fn Parser::parse_parenthesized_expression(self : Parser) -> CompletedMarker {
  let marker = self.start_marker()
  ignore(self.bump())
  if self.parse_expression(AllowTrailingBlock) is None {
    self.report_expected_expression("inside these parentheses")
  }
  ignore(self.expect_or_missing(RParen, "`)`"))
  self.complete_marker(marker, ParenthesizedExpression)
}

///|
fn Parser::parse_argument_list(self : Parser) -> Unit {
  self.start_node(ArgumentList)
  ignore(self.expect_or_missing(LParen, "`(`"))
  let mut saw_argument = false
  while !self.at(RParen) && !self.at(Eof) && !(saw_argument && self.at(LBrace)) {
    let mark = self.progress_mark()
    if self.at(Comma) {
      self.report_expected_expression("before this comma")
    } else {
      self.parse_argument()
      saw_argument = true
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(RParen) && !(saw_argument && self.at(LBrace)) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "argument list") {
      ignore(self.recover_with_progress_until([Comma, RParen, LBrace, Eof]))
      ignore(self.eat(Comma))
    }
  }
  ignore(self.expect_or_missing(RParen, "`)`"))
  self.finish_node()
}

///|
fn Parser::parse_argument(self : Parser) -> Unit {
  self.start_node(Argument)
  let labelled = self.current_kind() == Some(LowerIdentifier) &&
    (
      self.significant_kind_at(1) == Some(Equals) ||
      self.significant_kind_at(1) == Some(Tilde)
    )
  if labelled {
    self.start_node(LabelledArgument)
    ignore(self.parse_name("an argument label"))
    if self.eat(Equals) {
      if self.parse_expression(AllowTrailingBlock) is None {
        self.report_expected_expression("after `=`")
      }
    } else {
      ignore(self.expect_or_missing(Tilde, "`~`"))
    }
    self.finish_node()
  } else if self.parse_expression(AllowTrailingBlock) is None {
    self.report_expected_expression("in this argument list")
    if !self.at(Comma) && !self.at(RParen) && !self.at(Eof) {
      ignore(self.recover_until([Comma, RParen, Eof]))
    }
  }
  self.finish_node()
}

///|
fn Parser::lambda_head_ahead(self : Parser) -> Bool {
  self.probe(parser => {
    guard parser.current_kind() is Some(kind) && is_pattern_start(kind) else {
      return false
    }
    ignore(parser.bump())
    while parser.eat(Comma) {
      if parser.at(FatArrow) {
        return true
      }
      guard parser.current_kind() is Some(next) && is_pattern_start(next) else {
        return false
      }
      ignore(parser.bump())
    }
    parser.at(FatArrow)
  })
}

///|
fn Parser::parse_pattern(self : Parser) -> Bool {
  self.start_node(Pattern)
  let matched = match self.current_kind() {
    Some(kind) if is_pattern_start(kind) => {
      ignore(self.bump())
      true
    }
    _ => {
      ignore(self.fail_expected("a pattern"))
      false
    }
  }
  self.finish_node()
  matched
}

///|
fn Parser::parse_lambda_head(self : Parser) -> Unit {
  self.start_node(PatternList)
  while !self.at(FatArrow) && !self.at(RBrace) && !self.at(Eof) {
    let mark = self.progress_mark()
    if !self.parse_pattern() {
      self.report(
        "CIRE-P0001",
        "expected a lambda parameter",
        self.point_range(),
        "write a parameter here",
      )
      ignore(self.recover_until([Comma, FatArrow, RBrace, Eof]))
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(FatArrow) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "lambda parameter list") {
      ignore(self.recover_with_progress_until([Comma, FatArrow, RBrace, Eof]))
    }
  }
  self.finish_node()
  ignore(self.expect_or_missing(FatArrow, "`=>`"))
}

///|
fn Parser::parse_trailing_lambda_expression(self : Parser) -> Unit {
  self.start_node(TrailingLambdaExpression)
  ignore(self.expect_or_missing(LBrace, "`{`"))
  if self.lambda_head_ahead() {
    self.parse_lambda_head()
  }
  self.parse_block_items()
  ignore(self.expect_or_missing(RBrace, "`}`"))
  self.finish_node()
}

///|
fn Parser::parse_block_items(self : Parser) -> Unit {
  while !self.at(RBrace) && !self.at(Eof) {
    let mark = self.progress_mark()
    if self.eat(Semicolon) {
      ()
    } else if self.current_kind().map(is_expression_start).unwrap_or(false) {
      self.start_node(ExpressionStatement)
      ignore(self.parse_expression(AllowTrailingBlock))
      ignore(self.eat(Semicolon))
      self.finish_node()
    } else {
      self.report_unexpected("a block")
      ignore(
        self.recover_with_progress_until([Newline, Semicolon, RBrace, Eof]),
      )
      ignore(self.eat(Semicolon))
    }
    if !self.require_progress(mark, "block") {
      ignore(
        self.recover_with_progress_until([Newline, Semicolon, RBrace, Eof]),
      )
    }
  }
}

///|
fn Parser::parse_block_expression(self : Parser) -> CompletedMarker? {
  guard self.at(LBrace) else { return None }
  let marker = self.start_marker()
  ignore(self.bump())
  self.parse_block_items()
  ignore(self.expect_or_missing(RBrace, "`}`"))
  Some(self.complete_marker(marker, BlockExpression))
}

///|
fn Parser::parse_required_block_expression(
  self : Parser,
  context : String,
) -> CompletedMarker {
  match self.parse_block_expression() {
    Some(block) => block
    None => {
      let marker = self.start_marker()
      ignore(self.fail_expected("a block"))
      self.missing(LBrace)
      self.report(
        "CIRE-P0001",
        "expected \{context}",
        self.point_range(),
        "insert `{ ... }` here",
      )
      self.missing(RBrace)
      self.complete_marker(marker, BlockExpression)
    }
  }
}
