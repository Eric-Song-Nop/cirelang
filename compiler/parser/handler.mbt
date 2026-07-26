///|
fn Parser::parse_lower_name(self : Parser, expected : String) -> Bool {
  self.start_node(Name)
  let matched = match self.current_kind() {
    Some(LowerIdentifier) | Some(Identifier) => {
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
fn Parser::parse_clause_pattern_list(self : Parser) -> Unit {
  self.start_node(PatternList)
  ignore(self.expect_or_missing(LParen, "`(`"))
  while !self.at(RParen) &&
        !self.at(KwAs) &&
        !self.at(FatArrow) &&
        !self.at(RBrace) &&
        !self.at(Eof) {
    let mark = self.progress_mark()
    if !self.parse_pattern() {
      self.report(
        "CIRE-P0001",
        "expected a clause pattern",
        self.point_range(),
        "write a pattern here",
      )
      ignore(self.recover_until([Comma, RParen, KwAs, FatArrow, RBrace, Eof]))
    }
    if self.eat(Comma) {
      ()
    } else if !self.at(RParen) {
      ignore(self.expect_or_missing(Comma, "`,`"))
    }
    if !self.require_progress(mark, "handler clause patterns") {
      ignore(
        self.recover_with_progress_until([
          Comma,
          RParen,
          KwAs,
          FatArrow,
          RBrace,
          Eof,
        ]),
      )
    }
  }
  ignore(self.expect_or_missing(RParen, "`)`"))
  self.finish_node()
}

///|
fn Parser::report_missing_continuation_binder(self : Parser) -> Unit {
  let range = self.point_range()
  self.start_node(ContinuationBinder)
  self.missing(KwAs)
  self.missing(LowerIdentifier)
  self.finish_node()
  self.emit_diagnostic(
    @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("CIRE-P0201"),
      Parse,
      Error,
      "`once` and `ctl` clauses require a continuation binder",
      @diagnostic.Label::primary(
        self.span(range),
        "add `as` and a continuation name here",
      ),
      self.token_snapshot().revision(),
    ).with_fix(
      @diagnostic.Fix::new("Insert a continuation binder", MaybeIncorrect, [
        @source.TextEdit::new(
          self.token_snapshot().source(),
          self.token_snapshot().revision(),
          range,
          " as k",
        ),
      ]),
    ),
  )
}

///|
fn Parser::parse_continuation_binder(self : Parser, allowed : Bool) -> Unit {
  guard self.at(KwAs) else { return }
  guard self.current_token() is Some(start_token)
  self.start_node(ContinuationBinder)
  ignore(self.bump())
  ignore(self.parse_lower_name("a continuation name"))
  let end = match self.current_token() {
    Some(next) => next.range().start()
    None => self.current_offset()
  }
  self.finish_node()
  if !allowed {
    let range = @source.TextRange::new(start_token.range().start(), end)
    self.emit_diagnostic(
      @diagnostic.Diagnostic::new(
        @diagnostic.DiagnosticCode::new("CIRE-P0202"),
        Parse,
        Error,
        "`abort` and `fun` clauses do not expose a continuation",
        @diagnostic.Label::primary(
          self.span(range),
          "remove this continuation binder",
        ),
        self.token_snapshot().revision(),
      ).with_fix(
        @diagnostic.Fix::new("Remove the continuation binder", Always, [
          @source.TextEdit::new(
            self.token_snapshot().source(),
            self.token_snapshot().revision(),
            range,
            "",
          ),
        ]),
      ),
    )
  }
}

///|
fn Parser::parse_handler_clause(self : Parser) -> Bool {
  guard self.current_kind() is Some(mode) && is_operation_mode(mode) else {
    return false
  }
  self.start_node(HandlerClause)
  ignore(self.bump())
  ignore(self.parse_lower_name("an operation name"))
  self.parse_clause_pattern_list()
  let exposes_continuation = mode == KwOnce || mode == KwCtl
  if self.at(KwAs) {
    self.parse_continuation_binder(exposes_continuation)
  } else if exposes_continuation {
    self.report_missing_continuation_binder()
  }
  ignore(self.expect_or_missing(FatArrow, "`=>`"))
  if self.parse_expression(AllowTrailingBlock) is None {
    self.report_expected_expression("after `=>`")
  }
  ignore(self.eat(Semicolon))
  self.finish_node()
  true
}

///|
fn Parser::parse_return_clause(self : Parser) -> Bool {
  guard self.at(KwReturn) else { return false }
  self.start_node(ReturnClause)
  ignore(self.bump())
  self.parse_clause_pattern_list()
  ignore(self.expect_or_missing(FatArrow, "`=>`"))
  if self.parse_expression(AllowTrailingBlock) is None {
    self.report_expected_expression("after the return clause arrow")
  }
  ignore(self.eat(Semicolon))
  self.finish_node()
  true
}

///|
fn Parser::parse_handler_expression(self : Parser) -> CompletedMarker? {
  guard self.at(KwHandler) else { return None }
  let entered = self.enter_rule(
    RuleId::new("handler_expression"),
    StopBeforeTrailingBlock,
    "handler expression",
  )
  guard entered else { return None }
  let marker = self.start_marker()
  ignore(self.bump())
  self.cut()
  if !self.parse_type_reference() {
    self.report(
      "CIRE-P0001",
      "expected an effect type after `handler`",
      self.point_range(),
      "write the handled effect type here",
    )
  }
  ignore(self.expect_or_missing(LBrace, "`{`"))
  let mut seen_return = false
  while !self.at(RBrace) && !self.at(Eof) {
    let mark = self.progress_mark()
    let starts_return = self.at(KwReturn)
    let starts_operation = self
      .current_kind()
      .map(is_operation_mode)
      .unwrap_or(false)
    if starts_return {
      if seen_return {
        self.report(
          "CIRE-P0203",
          "a handler may contain only one return clause",
          self.current_token().unwrap().range(),
          "this return clause is duplicated",
        )
      }
    } else if starts_operation && seen_return {
      self.report(
        "CIRE-P0204",
        "the return clause must be the final handler clause",
        self.current_token().unwrap().range(),
        "move this operation clause before `return`",
      )
    }
    let parsed_member = self.ordered_choice([
      parser => parser.parse_return_clause(),
      parser => parser.parse_handler_clause(),
    ])
    if parsed_member {
      if starts_return {
        seen_return = true
      }
    } else {
      self.report_unexpected("a handler body")
      ignore(
        self.recover_with_progress_until([
          KwAbort,
          KwOnce,
          KwFun,
          KwCtl,
          KwReturn,
          RBrace,
          Eof,
        ]),
      )
    }
    if !self.require_progress(mark, "handler body") {
      ignore(
        self.recover_with_progress_until([
          KwAbort,
          KwOnce,
          KwFun,
          KwCtl,
          KwReturn,
          RBrace,
          Eof,
        ]),
      )
    }
  }
  ignore(self.expect_or_missing(RBrace, "`}`"))
  let result = self.complete_marker(marker, HandlerExpression)
  self.leave_rule(true)
  Some(result)
}

///|
fn Parser::missing_with_operand(self : Parser) -> CompletedMarker {
  let marker = self.start_marker()
  self.start_node(QualifiedName)
  self.start_node(Name)
  self.missing(LowerIdentifier)
  self.finish_node()
  self.finish_node()
  self.report(
    "CIRE-P0001",
    "expected a handler expression after `with`",
    self.point_range(),
    "write a handler value before this action block",
  )
  self.complete_marker(marker, NameExpression)
}

///|
fn Parser::parse_with_expression(self : Parser) -> CompletedMarker? {
  guard self.at(KwWith) else { return None }
  let entered = self.enter_rule(
    RuleId::new("with_expression"),
    StopBeforeTrailingBlock,
    "with expression",
  )
  guard entered else { return None }
  let marker = self.start_marker()
  ignore(self.bump())
  self.cut()
  if self.at(LBrace) {
    ignore(self.missing_with_operand())
  } else if self.parse_expression(StopBeforeTrailingBlock) is None {
    self.report_expected_expression("after `with`")
    ignore(self.missing_with_operand())
  }
  if self.eat(KwAs) {
    ignore(self.parse_lower_name("a named capability binder"))
  }
  ignore(self.parse_required_block_expression("a `with` action block"))
  let result = self.complete_marker(marker, WithExpression)
  self.leave_rule(true)
  Some(result)
}
