///|
fn expression_test_parse(text : String) -> @parser.ParseSnapshot {
  @parser.parse(
    @source.SourceSnapshot::new(
      @source.SourceId::new(41),
      @source.SourceRevision::initial(),
      "expression_test.cire",
      text,
    ),
  )
}

///|
test "postfix calls methods and trailing lambdas nest around their lhs" {
  let text = "fn run() -> Unit { f()(x).m(y) { z => z } }"
  let snapshot = expression_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(
    sexpr.contains(
      "(call_expression (method_expression (call_expression (call_expression (name_expression",
    ),
  )
  assert_true(sexpr.contains("(trailing_lambda_expression "))
  assert_true(sexpr.contains("(pattern_list (pattern "))
}

///|
test "MoonBit-like UI calls support labels and nested trailing lambdas" {
  let text =
    #|fn view() -> View {
    #|  Column(gap=8) {
    #|    Text("Profile")
    #|    users.for_each { user => UserRow(user) }
    #|    Button("Save") { save() }
    #|  }
    #|}
  let snapshot = expression_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(labelled_argument "))
  assert_true(sexpr.contains("(method_expression "))
  assert_true(sexpr.contains("(lower_identifier \"user\")"))
  assert_true(sexpr.contains("(string_literal \"\\\"Profile\\\"\")"))
}

///|
test "newline and comments do not break trailing-lambda attachment" {
  let text =
    #|fn run() -> Unit {
    #|  task()
    #|  // attached to the same call 😀
    #|  { value }
    #|}
  let snapshot = expression_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(trailing_lambda_expression "))
  assert_true(sexpr.contains("(line_comment "))
  assert_eq(snapshot.tree().root().range().end().value(), text.length())
}

///|
test "label punning is retained as a labelled argument" {
  let text = "fn view() -> View { Column(gap~, width=8) {} }"
  let snapshot = expression_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(tilde \"~\")"))
  assert_true(sexpr.contains("(equals \"=\")"))
}

///|
test "a missing call close preserves the following trailing lambda" {
  let text = "fn view() -> View { Button(\"Save\" { save() } }"
  let snapshot = expression_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.diagnostics().length() >= 1)
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(missing r_paren)"))
  assert_true(sexpr.contains("(trailing_lambda_expression "))
  assert_true(sexpr.contains("(lower_identifier \"save\")"))
  assert_false(
    snapshot
    .diagnostics()
    .any(diagnostic => diagnostic.code().value() == "CIRE-P9999"),
  )
}
