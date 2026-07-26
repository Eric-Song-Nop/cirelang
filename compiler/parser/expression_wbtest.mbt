///|
test "expression flavor controls whether a trailing block attaches" {
  let tokens = test_snapshot([
    (LowerIdentifier, "handler"),
    (LParen, "("),
    (IntLiteral, "1"),
    (RParen, ")"),
    (Whitespace, " "),
    (LBrace, "{"),
    (LowerIdentifier, "run"),
    (LParen, "("),
    (RParen, ")"),
    (RBrace, "}"),
    (Eof, ""),
  ])
  let stop = Parser::new(tokens)
  guard stop.parse_expression(StopBeforeTrailingBlock) is Some(_)
  assert_true(stop.at(LBrace))
  assert_false(
    stop.events().any(event => event == Start(TrailingLambdaExpression)),
  )
  let allow = Parser::new(tokens)
  guard allow.parse_expression(AllowTrailingBlock) is Some(_)
  assert_true(allow.at(Eof))
  assert_true(
    allow.events().any(event => event == Start(TrailingLambdaExpression)),
  )
}
