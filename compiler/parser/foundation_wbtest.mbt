///|
fn test_token(
  id : Int,
  kind : @syntax.SyntaxKind,
  start : Int,
  text : String,
) -> @syntax.Token {
  @syntax.Token::new(
    @syntax.TokenId::new(id),
    kind,
    @source.TextRange::new(
      @source.TextOffset::new(start),
      @source.TextOffset::new(start + text.length()),
    ),
    text,
  )
}

///|
fn test_snapshot(
  entries : Array[(@syntax.SyntaxKind, String)],
) -> @syntax.TokenSnapshot {
  let tokens : Array[@syntax.Token] = []
  let mut offset = 0
  for index, entry in entries {
    let (kind, text) = entry
    tokens.push(test_token(index, kind, offset, text))
    offset = offset + text.length()
  }
  @syntax.TokenSnapshot::new(
    @source.SourceId::new(1),
    @source.SourceRevision::initial(),
    tokens,
  )
}

///|
fn test_diagnostic() -> @diagnostic.Diagnostic {
  let source = @source.SourceId::new(1)
  let revision = @source.SourceRevision::initial()
  @diagnostic.Diagnostic::new(
    @diagnostic.DiagnosticCode::new("PTEST"),
    Parse,
    Error,
    "speculative parser diagnostic",
    @diagnostic.Label::primary(
      @source.Span::new(
        source,
        @source.TextRange::empty(@source.TextOffset::zero()),
      ),
      "speculative",
    ),
    revision,
  )
}

///|
fn simple_snapshot() -> @syntax.TokenSnapshot {
  test_snapshot([(LowerIdentifier, "value"), (Plus, "+"), (Eof, "")])
}

///|
test "ordered choice keeps only the farthest failure" {
  let parser = Parser::new(simple_snapshot())
  let matched = parser.ordered_choice([
    parser => {
      ignore(parser.bump())
      parser.fail_expected("a type argument")
    },
    parser => parser.fail_expected("an expression"),
  ])
  assert_false(matched)
  guard parser.failure() is Some(failure)
  assert_eq(failure.token_index(), 1)
  assert_eq(failure.offset().value(), 5)
  assert_eq(failure.expected(), ["a type argument"])
}

///|
test "equal-position expectations retain grammar order" {
  let parser = Parser::new(simple_snapshot())
  assert_false(
    parser.ordered_choice([
      parser => parser.fail_expected("an identifier"),
      parser => parser.fail_expected("`(`"),
      parser => parser.fail_expected("an identifier"),
      parser => parser.fail_expected("a literal"),
    ]),
  )
  guard parser.failure() is Some(failure)
  assert_eq(failure.expected(), ["an identifier", "`(`", "a literal"])
}

///|
test "cut excludes ordered-choice siblings" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.enter_rule(
      RuleId::new("declaration"),
      AllowTrailingBlock,
      "declaration",
    ),
  )
  let matched = parser.ordered_choice([
    parser => {
      parser.cut()
      parser.fail_expected("an effect name")
    },
    parser => parser.fail_expected("a function name"),
  ])
  parser.leave_rule(matched)
  assert_false(matched)
  guard parser.failure() is Some(failure)
  assert_true(failure.is_committed())
  assert_eq(failure.expected(), ["an effect name"])
  assert_eq(failure.contexts(), ["declaration"])
}

///|
test "silent probe cannot pollute parser state or public failure" {
  let parser = Parser::new(simple_snapshot())
  assert_false(parser.fail_expected("outer expectation"))
  let before = parser.checkpoint()
  assert_false(
    parser.probe(parser => {
      parser.start_node(Name)
      ignore(parser.bump())
      parser.emit_diagnostic(test_diagnostic())
      parser.fail_expected("probe-only expectation")
    }),
  )
  assert_eq(parser.raw_index, before.raw_index)
  assert_eq(parser.events().length(), before.event_count)
  assert_eq(parser.diagnostics().length(), before.diagnostic_count)
  guard parser.failure() is Some(failure)
  assert_eq(failure.expected(), ["outer expectation"])
}

///|
test "rollback truncates token, missing, and diagnostic output" {
  let parser = Parser::new(
    test_snapshot([(Whitespace, " "), (LowerIdentifier, "x"), (Eof, "")]),
  )
  let checkpoint = parser.checkpoint()
  parser.start_node(Name)
  ignore(parser.bump())
  parser.missing(RParen)
  parser.finish_node()
  parser.emit_diagnostic(test_diagnostic())
  assert_eq(parser.raw_index, 2)
  assert_eq(parser.events().length(), 5)
  assert_eq(parser.diagnostics().length(), 1)
  parser.rollback(checkpoint)
  assert_eq(parser.raw_index, 0)
  assert_eq(parser.events().length(), 0)
  assert_eq(parser.diagnostics().length(), 0)
}

///|
test "recovery advances and retains trivia in a lossless error node" {
  let snapshot = test_snapshot([
    (Whitespace, " "),
    (LowerIdentifier, "oops"),
    (Plus, "+"),
    (Eof, ""),
  ])
  let parser = Parser::new(snapshot)
  parser.start_node(SourceFile)
  let start = parser.raw_index
  assert_true(parser.recover_until([Plus]))
  assert_true(parser.raw_index > start)
  assert_true(parser.at(Plus))
  ignore(parser.bump())
  ignore(parser.bump())
  parser.finish_node()
  let tree = @syntax.build_green(parser.events())
  assert_eq(tree.source_text(), " oops+")
}

///|
test "progress and recursion guards reject zero-width loops" {
  let parser = Parser::new(simple_snapshot())
  let mark = parser.progress_mark()
  assert_false(parser.require_progress(mark, "parameter list"))
  guard parser.failure() is Some(progress_failure)
  assert_eq(progress_failure.expected(), [
    "progress while parsing parameter list",
  ])
  let rule = RuleId::new("expression")
  assert_true(parser.enter_rule(rule, StopBeforeTrailingBlock, "expression"))
  assert_false(parser.enter_rule(rule, StopBeforeTrailingBlock, "expression"))
  parser.leave_rule(false)
}

///|
test "memo keys include trailing-block flavor and failures round trip" {
  let rule = RuleId::new("expression")
  let allow = MemoKey::new(rule, 3, AllowTrailingBlock)
  let stop = MemoKey::new(rule, 3, StopBeforeTrailingBlock)
  assert_false(allow == stop)
  let failure = FailureSummary::new(
    3,
    @source.TextOffset::new(8),
    ["an expression", "`}`"],
    ["source file", "block"],
    true,
  )
  let encoded = failure.to_json().stringify()
  let decoded : FailureSummary = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, failure)
  try
    (
      @json.from_json(
        @json.parse(
          encoded.replace(old="\"token_index\":3", new="\"token_index\":-1"),
        ),
      ) : FailureSummary)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected a negative failure token index to be rejected")
  }
}

///|
test "recovery stops before delimiters and force recovery guarantees progress" {
  let snapshot = test_snapshot([
    (Comma, ","),
    (LowerIdentifier, "next"),
    (Eof, ""),
  ])
  let parser = Parser::new(snapshot)
  parser.start_node(SourceFile)
  assert_false(parser.recover_until([Comma]))
  assert_eq(parser.raw_index, 0)
  assert_true(parser.at(Comma))
  assert_true(parser.recover_with_progress_until([LowerIdentifier]))
  assert_eq(parser.raw_index, 1)
  assert_eq(parser.current_token().map(token => token.text()), Some("next"))
  ignore(parser.bump())
  ignore(parser.bump())
  parser.finish_node()
  assert_eq(@syntax.build_green(parser.events()).source_text(), ",next")
}

///|
test "recovery can synchronize on raw newline trivia" {
  let snapshot = test_snapshot([
    (LowerIdentifier, "bad"),
    (Newline, "\n"),
    (LowerIdentifier, "next"),
    (Eof, ""),
  ])
  let parser = Parser::new(snapshot)
  parser.start_node(SourceFile)
  assert_true(parser.recover_until([Newline]))
  assert_eq(parser.raw_index, 1)
  assert_eq(
    parser
    .token_snapshot()
    .token_at(parser.raw_index)
    .map(token => token.kind()),
    Some(Newline),
  )
  ignore(parser.bump())
  ignore(parser.bump())
  parser.finish_node()
  assert_eq(@syntax.build_green(parser.events()).source_text(), "bad\nnext")
}

///|
test "an earlier rule cut does not disable a later local choice" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.enter_rule(RuleId::new("outer"), AllowTrailingBlock, "outer"),
  )
  parser.cut()
  assert_true(
    parser.ordered_choice([
      parser => parser.fail_expected("the first alternative"),
      parser => parser.eat(LowerIdentifier),
    ]),
  )
  parser.leave_rule(true)
  assert_eq(parser.raw_index, 1)
  guard parser.failure() is Some(failure)
  assert_eq(failure.expected(), ["the first alternative"])
  assert_false(failure.is_committed())
}

///|
test "a successful child cut never leaks into its caller" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.enter_rule(RuleId::new("outer"), AllowTrailingBlock, "outer"),
  )
  assert_true(
    parser.ordered_choice([
      parser => {
        guard parser.enter_rule(
          RuleId::new("child"),
          AllowTrailingBlock,
          "child",
        ) else {
          return false
        }
        parser.cut()
        parser.leave_rule(true)
        parser.fail_expected("after the successful child")
      },
      parser => parser.eat(LowerIdentifier),
    ]),
  )
  parser.leave_rule(true)
  assert_eq(parser.raw_index, 1)
}

///|
test "handled committed failure cannot poison a later local choice" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.enter_rule(RuleId::new("outer"), AllowTrailingBlock, "outer"),
  )
  assert_false(
    parser.ordered_choice([
      parser => {
        guard parser.enter_rule(
          RuleId::new("child"),
          AllowTrailingBlock,
          "child",
        ) else {
          return false
        }
        parser.cut()
        let matched = parser.fail_expected("the rest of the child")
        parser.leave_rule(matched)
        matched
      },
      parser => parser.eat(Plus),
    ]),
  )
  assert_true(parser.recover_with_progress_until([Plus]))
  assert_true(
    parser.ordered_choice([
      parser => parser.fail_expected("a prefix operator"),
      parser => parser.eat(Plus),
    ]),
  )
  parser.leave_rule(true)
  assert_eq(parser.raw_index, 2)
}

///|
test "failure contexts remain stacks and merge by common prefix" {
  let recursive = FailureSummary::new(
    2,
    @source.TextOffset::new(4),
    ["an expression"],
    ["source file", "expression", "expression"],
    false,
  )
  assert_eq(recursive.contexts(), ["source file", "expression", "expression"])
  let sibling = FailureSummary::new(
    2,
    @source.TextOffset::new(4),
    ["a type"],
    ["source file", "type"],
    false,
  )
  let merged = recursive.merge(sibling)
  assert_eq(merged.expected(), ["an expression", "a type"])
  assert_eq(merged.contexts(), ["source file"])
}

///|
test "missing tokens follow pending trivia at the significant offset" {
  let snapshot = test_snapshot([
    (Whitespace, "  "),
    (LowerIdentifier, "value"),
    (Eof, ""),
  ])
  let parser = Parser::new(snapshot)
  parser.start_node(SourceFile)
  parser.missing(Arrow)
  assert_eq(parser.raw_index, 1)
  ignore(parser.bump())
  ignore(parser.bump())
  parser.finish_node()
  let green = @syntax.build_green(parser.events())
  let tree = @syntax.SyntaxTree::new(
    snapshot.source(),
    snapshot.revision(),
    green,
  )
  let children = tree.root().children()
  assert_eq(children.length(), 4)
  match children[1] {
    Token(token) => {
      assert_true(token.is_missing())
      assert_eq(token.kind(), Arrow)
      assert_eq(token.range().start().value(), 2)
      assert_eq(token.range().end().value(), 2)
    }
    Node(_) => fail("expected a missing token after trivia")
  }
}

///|
test "committed failures roll back partial event and cursor state" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.enter_rule(RuleId::new("outer"), AllowTrailingBlock, "outer"),
  )
  let matched = parser.ordered_choice([
    parser => {
      parser.start_node(Name)
      ignore(parser.bump())
      parser.cut()
      parser.fail_expected("a completed name")
    },
    parser => parser.eat(LowerIdentifier),
  ])
  assert_false(matched)
  assert_eq(parser.raw_index, 0)
  assert_eq(parser.events(), [])
  assert_eq(parser.node_depth, 0)
  guard parser.failure() is Some(failure)
  assert_true(failure.is_committed())
  parser.leave_rule(false)
}

///|
test "successful choice keeps farthest failure but only successful events" {
  let parser = Parser::new(simple_snapshot())
  assert_true(
    parser.ordered_choice([
      parser => {
        parser.start_node(Name)
        ignore(parser.bump())
        parser.finish_node()
        parser.fail_expected("a type argument")
      },
      parser => parser.eat(LowerIdentifier),
    ]),
  )
  assert_eq(parser.raw_index, 1)
  assert_eq(parser.events().length(), 1)
  guard parser.failure() is Some(failure)
  assert_eq(failure.token_index(), 1)
  assert_eq(failure.expected(), ["a type argument"])
}

///|
test "forward-parent markers build nested postfix syntax without moving lhs" {
  let parser = Parser::new(
    test_snapshot([
      (LowerIdentifier, "f"),
      (LParen, "("),
      (RParen, ")"),
      (LParen, "("),
      (LowerIdentifier, "x"),
      (RParen, ")"),
      (Dot, "."),
      (LowerIdentifier, "m"),
      (LParen, "("),
      (LowerIdentifier, "y"),
      (RParen, ")"),
      (LBrace, "{"),
      (LowerIdentifier, "z"),
      (FatArrow, "=>"),
      (LowerIdentifier, "z"),
      (RBrace, "}"),
      (Eof, ""),
    ]),
  )
  parser.start_node(SourceFile)
  let name = parser.start_marker()
  ignore(parser.bump())
  let mut expression = parser.complete_marker(name, NameExpression)
  let first_call = parser.precede(expression)
  parser.start_node(ArgumentList)
  ignore(parser.bump())
  ignore(parser.bump())
  parser.finish_node()
  expression = parser.complete_marker(first_call, CallExpression)
  let second_call = parser.precede(expression)
  parser.start_node(ArgumentList)
  ignore(parser.bump())
  parser.start_node(Argument)
  parser.start_node(NameExpression)
  ignore(parser.bump())
  parser.finish_node()
  parser.finish_node()
  ignore(parser.bump())
  parser.finish_node()
  expression = parser.complete_marker(second_call, CallExpression)
  let method_marker = parser.precede(expression)
  ignore(parser.bump())
  ignore(parser.bump())
  expression = parser.complete_marker(method_marker, MethodExpression)
  let method_call = parser.precede(expression)
  parser.start_node(ArgumentList)
  ignore(parser.bump())
  parser.start_node(Argument)
  parser.start_node(NameExpression)
  ignore(parser.bump())
  parser.finish_node()
  parser.finish_node()
  ignore(parser.bump())
  parser.finish_node()
  parser.start_node(TrailingLambdaExpression)
  ignore(parser.bump())
  parser.start_node(PatternList)
  parser.start_node(Pattern)
  ignore(parser.bump())
  parser.finish_node()
  parser.finish_node()
  ignore(parser.bump())
  parser.start_node(NameExpression)
  ignore(parser.bump())
  parser.finish_node()
  ignore(parser.bump())
  parser.finish_node()
  ignore(parser.complete_marker(method_call, CallExpression))
  ignore(parser.bump())
  parser.finish_node()
  let green = @syntax.build_green(parser.events())
  assert_eq(green.source_text(), "f()(x).m(y){z=>z}")
  let sexpr = green.to_sexpr()
  assert_true(
    sexpr.contains(
      "(call_expression (method_expression (call_expression (call_expression (name_expression",
    ),
  )
  assert_true(sexpr.contains("(trailing_lambda_expression "))
}

///|
test "marker rewrites roll back across failed alternatives" {
  let parser = Parser::new(simple_snapshot())
  let marker = parser.start_marker()
  ignore(parser.bump())
  let completed = parser.complete_marker(marker, NameExpression)
  let before = parser.events()
  let checkpoint = parser.checkpoint()
  let outer = parser.precede(completed)
  ignore(parser.bump())
  ignore(parser.complete_marker(outer, CallExpression))
  parser.rollback(checkpoint)
  assert_eq(parser.events(), before)
  assert_eq(parser.marker_depth, 0)
  assert_eq(parser.raw_index, 1)
}

///|
test "probe cannot leak forward-parent links or markers" {
  let parser = Parser::new(simple_snapshot())
  let marker = parser.start_marker()
  ignore(parser.bump())
  let completed = parser.complete_marker(marker, NameExpression)
  let before = parser.events()
  assert_false(
    parser.probe(parser => {
      let outer = parser.precede(completed)
      ignore(parser.bump())
      ignore(parser.complete_marker(outer, CallExpression))
      false
    }),
  )
  assert_eq(parser.events(), before)
  assert_eq(parser.marker_depth, 0)
  assert_eq(parser.raw_index, 1)
}
