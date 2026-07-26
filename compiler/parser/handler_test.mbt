///|
fn handler_test_parse(text : String) -> @parser.ParseSnapshot {
  @parser.parse(
    @source.SourceSnapshot::new(
      @source.SourceId::new(57),
      @source.SourceRevision::initial(),
      "handler_test.cire",
      text,
    ),
  )
}

///|
fn handler_test_diagnostic(
  snapshot : @parser.ParseSnapshot,
  code : String,
) -> @diagnostic.Diagnostic? {
  for item in snapshot.diagnostics() {
    if item.code().value() == code {
      return Some(item)
    }
  }
  None
}

///|
test "handler and with preserve their surface sugar boundary" {
  let text =
    #|fn run() -> Int {
    #|  with handler Choice {
    #|    ctl choose(value) as k => k.resume(value)
    #|    return(value) => value
    #|  } {
    #|    Choice::choose(1)
    #|  }
    #|}
  let snapshot = handler_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(with_expression "))
  assert_true(sexpr.contains("(handler_expression "))
  assert_true(sexpr.contains("(handler_clause "))
  assert_true(sexpr.contains("(continuation_binder "))
  assert_true(sexpr.contains("(return_clause "))
  assert_false(sexpr.contains("(trailing_lambda_expression "))
}

///|
test "with named capability parses its operand in stop-before-block flavor" {
  let text =
    #|fn read() -> Int {
    #|  with make_reader(42) as app {
    #|    app.read()
    #|  }
    #|}
  let snapshot = handler_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(with_expression "))
  assert_true(sexpr.contains("(lower_identifier \"app\")"))
  assert_true(sexpr.contains("(method_expression "))
  assert_false(sexpr.contains("(trailing_lambda_expression "))
}

///|
test "parentheses explicitly allow a trailing lambda in a with operand" {
  let text =
    #|fn run() -> Unit {
    #|  with (make_handler(1) { configure() }) {
    #|    run()
    #|  }
    #|}
  let snapshot = handler_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(parenthesized_expression "))
  assert_true(sexpr.contains("(trailing_lambda_expression "))
  assert_true(sexpr.contains("(with_expression "))
}

///|
test "continuation binder rules produce targeted diagnostics and fixes" {
  let missing = handler_test_parse(
    "fn f() -> Int { handler Choice { ctl choose(x) => x return(v) => v } }",
  )
  let missing_diagnostic = handler_test_diagnostic(missing, "CIRE-P0201")
  guard missing_diagnostic is Some(missing_item)
  assert_eq(missing_item.fixes().length(), 1)
  assert_eq(missing_item.fixes()[0].applicability(), MaybeIncorrect)
  assert_true(missing.to_sexpr().contains("(missing kw_as)"))
  let illegal = handler_test_parse(
    "fn f() -> Int { handler Error { abort fail(e) as k => report(e) return(v) => v } }",
  )
  let illegal_diagnostic = handler_test_diagnostic(illegal, "CIRE-P0202")
  guard illegal_diagnostic is Some(illegal_item)
  assert_eq(illegal_item.fixes().length(), 1)
  assert_eq(illegal_item.fixes()[0].applicability(), Always)
  assert_eq(illegal_item.fixes()[0].edits()[0].insert(), "")
}

///|
test "handler and with recovery preserve later structured input" {
  let text =
    #|fn run() -> Int {
    #|  with {
    #|    handler Choice {
    #|      ???
    #|      ctl choose(x) as k => k.resume(x)
    #|      return(v) => v
    #|    }
    #|  }
    #|}
  let snapshot = handler_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.diagnostics().length() >= 2)
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(with_expression "))
  assert_true(sexpr.contains("(missing lower_identifier)"))
  assert_true(sexpr.contains("(error_node "))
  assert_true(sexpr.contains("(handler_clause "))
  assert_true(sexpr.contains("(return_clause "))
  assert_false(
    snapshot.diagnostics().any(item => item.code().value() == "CIRE-P9999"),
  )
}
