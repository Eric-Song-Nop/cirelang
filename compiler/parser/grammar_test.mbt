///|
fn parser_test_source(text : String) -> @source.SourceSnapshot {
  @source.SourceSnapshot::new(
    @source.SourceId::new(23),
    @source.SourceRevision::initial(),
    "parser_test.cire",
    text,
  )
}

///|
fn parser_test_parse(text : String) -> @parser.ParseSnapshot {
  @parser.parse(parser_test_source(text))
}

///|
fn parse_snapshot_json_is_rejected(encoded : String) -> Bool {
  try {
    let _decoded : @parser.ParseSnapshot = @json.from_json(@json.parse(encoded))
    false
  } catch {
    _ => true
  }
}

///|
fn find_token_range(
  node : @syntax.SyntaxNode,
  kind : @syntax.SyntaxKind,
) -> @source.TextRange? {
  for element in node.children() {
    match element {
      Token(token) if token.kind() == kind => return Some(token.range())
      Token(_) => ()
      Node(child) =>
        match find_token_range(child, kind) {
          Some(range) => return Some(range)
          None => ()
        }
    }
  }
  None
}

///|
test "empty and trivia-only files produce lossless source roots" {
  let empty = parser_test_parse("")
  assert_eq(empty.source_text(), "")
  assert_eq(empty.diagnostics(), [])
  inspect(empty.to_sexpr(), content="(source_file (eof \"\"))")
  let trivia_text = " // only trivia 😀\r\n\t"
  let trivia = parser_test_parse(trivia_text)
  assert_eq(trivia.source_text(), trivia_text)
  assert_eq(trivia.diagnostics(), [])
  assert_eq(trivia.tree().root().range().end().value(), trivia_text.length())
}

///|
test "canonical Choice parses ctl operation generics losslessly" {
  let text =
    #|pub(open) effect Choice {
    #|  ctl[A] choose(values : Array[A]) -> A
    #|}
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  assert_eq(snapshot.failure(), None)
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(effect_declaration "))
  assert_true(sexpr.contains("(visibility "))
  assert_true(sexpr.contains("(operation_declaration "))
  assert_true(sexpr.contains("(kw_ctl \"ctl\")"))
  assert_true(sexpr.contains("(type_parameter_list "))
}

///|
test "Reader fun operation and all operation modes share one grammar" {
  let text =
    #|pub(open) effect Reader[R] {
    #|  fun ask() -> R
    #|  abort[A] fail(error : R) -> A
    #|  once[A] await(task : Task[A]) -> A
    #|  ctl[A] choose(values : Array[A]) -> A
    #|}
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(kw_fun \"fun\")"))
  assert_true(sexpr.contains("(kw_abort \"abort\")"))
  assert_true(sexpr.contains("(kw_once \"once\")"))
  assert_true(sexpr.contains("(kw_ctl \"ctl\")"))
}

///|
test "function types, named capabilities, family rows, and open tails parse" {
  let text =
    #|fn[A, Eff : EffectRow] read_app(
    #|  app : Read[Int],
    #|  transform : (A) -> A ! Eff,
    #|) -> Int ! {Read[Int], app, ..Eff} {
    #|  // body is intentionally opaque to this grammar slice 😀
    #|}
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(function_type "))
  assert_true(sexpr.contains("(effect_annotation "))
  assert_true(sexpr.contains("(effect_family_row_item "))
  assert_true(sexpr.contains("(named_capability_row_item "))
  assert_true(sexpr.contains("(open_effect_row_item "))
  assert_true(sexpr.contains("(block_expression "))
}

///|
test "generic kinds keep effect rows and capability identities distinct" {
  let text =
    #|fn[A, Fx : Effect, Eff : EffectRow] relay(
    #|  app : Fx,
    #|  body : () -> A ! {Fx, app, ..Eff},
    #|) -> A ! {Fx, app, ..Eff} {
    #|  body()
    #|}
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(upper_identifier \"A\")"))
  assert_true(sexpr.contains("(upper_identifier \"Fx\")"))
  assert_true(sexpr.contains("(upper_identifier \"Effect\")"))
  assert_true(sexpr.contains("(upper_identifier \"Eff\")"))
  assert_true(sexpr.contains("(upper_identifier \"EffectRow\")"))
  assert_true(sexpr.contains("(effect_family_row_item "))
  assert_true(sexpr.contains("(named_capability_row_item "))
  assert_true(sexpr.contains("(open_effect_row_item "))
}

///|
test "Read capability expansion gets a targeted node and always-applicable fix" {
  let text = "fn read(app : Read[Int]) -> Int ! {Read[app]} {}"
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.to_sexpr().contains("(diagnostic_effect_row_item "))
  assert_eq(snapshot.diagnostics().length(), 1)
  let diagnostic = snapshot.diagnostics()[0]
  assert_eq(diagnostic.code().value(), "CIRE-P0101")
  assert_eq(diagnostic.stage(), Parse)
  assert_eq(diagnostic.fixes().length(), 1)
  let fix = diagnostic.fixes()[0]
  assert_eq(fix.applicability(), Always)
  assert_eq(fix.edits().length(), 1)
  let edit = fix.edits()[0]
  assert_eq(edit.insert(), "app")
  assert_eq(parser_test_source(text).slice(edit.delete()), Some("Read[app]"))
}

///|
test "malformed declarations preserve skipped input and always recover" {
  let text =
    #|effect Broken {
    #|  ctl choose(value Int) ->
    #|}
    #|???
    #|fn recovered() -> Unit {
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.diagnostics().length() >= 3)
  assert_true(snapshot.failure() is Some(_))
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(error_node "))
  assert_true(sexpr.contains("(missing colon)"))
  assert_true(sexpr.contains("(missing r_brace)"))
  assert_true(sexpr.contains("(function_declaration "))
}

///|
test "top-level recovery consumes an unrecognized declaration starter" {
  let text =
    #|pub const broken = 1
    #|fn recovered() -> Unit {}
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.diagnostics().length() >= 1)
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(error_node "))
  assert_true(sexpr.contains("(kw_const \"const\")"))
  assert_true(sexpr.contains("(function_declaration "))
  assert_true(sexpr.contains("(lower_identifier \"recovered\")"))
}

///|
test "list recovery preserves delimiters and following items" {
  let text = "fn f(, x : A) -> Unit ! {Read, , app} {}"
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.source_text(), text)
  assert_true(snapshot.diagnostics().length() >= 2)
  let sexpr = snapshot.to_sexpr()
  assert_true(sexpr.contains("(lower_identifier \"x\")"))
  assert_true(sexpr.contains("(upper_identifier \"A\")"))
  assert_true(sexpr.contains("(upper_identifier \"Read\")"))
  assert_true(sexpr.contains("(named_capability_row_item "))
  assert_true(sexpr.contains("(lower_identifier \"app\")"))
}

///|
test "missing-token position follows pending trivia like its diagnostic" {
  let text = "fn f()  Unit {}"
  let snapshot = parser_test_parse(text)
  guard find_token_range(snapshot.tree().root(), Arrow) is Some(range)
  assert_true(range.is_empty())
  assert_eq(range.start().value(), 8)
  let mut found = false
  for diagnostic in snapshot.diagnostics() {
    if diagnostic.code().value() == "CIRE-P0001" {
      assert_eq(diagnostic.labels()[0].span().range().start().value(), 8)
      found = true
      break
    }
  }
  assert_true(found)
}

///|
test "UTF-16 emoji trivia ranges survive parser tree construction" {
  let text = "// 😀\neffect Reader { fun ask() -> Int }"
  let snapshot = parser_test_parse(text)
  assert_eq(snapshot.diagnostics(), [])
  guard find_token_range(snapshot.tree().root(), LineComment) is Some(range)
  assert_eq(range.start().value(), 0)
  assert_eq(range.end().value(), 5)
  assert_eq(range.length(), "// 😀".length())
  assert_eq(snapshot.tree().root().range().end().value(), text.length())
}

///|
test "parse snapshots have deterministic JSON and sexpr round trips" {
  let text = "effect Reader { fun ask() -> Int }"
  let first = parser_test_parse(text)
  let second = parser_test_parse(text)
  assert_eq(first.to_sexpr(), second.to_sexpr())
  let encoded = first.to_json().stringify()
  assert_eq(encoded, second.to_json().stringify())
  let decoded : @parser.ParseSnapshot = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, first)
  let leaked = first.diagnostics()
  leaked.push(
    @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("TEST"),
      Parse,
      Error,
      "caller-owned diagnostic",
      @diagnostic.Label::primary(
        @source.Span::new(
          first.source(),
          @source.TextRange::empty(@source.TextOffset::zero()),
        ),
        "test",
      ),
      first.revision(),
    ),
  )
  assert_eq(first.diagnostics(), [])
}

///|
test "parse snapshot JSON validates its tree and failure position" {
  let snapshot = parser_test_parse("fn broken( -> Unit {}")
  guard snapshot.failure() is Some(failure)
  let encoded = snapshot.to_json().stringify()
  assert_true(
    parse_snapshot_json_is_rejected(
      encoded.replace(
        old="\"token_index\":\{failure.token_index()}",
        new="\"token_index\":9999",
      ),
    ),
  )
  let wrong_offset = if failure.offset().value() == 0 { 1 } else { 0 }
  assert_true(
    parse_snapshot_json_is_rejected(
      encoded.replace(
        old="\"offset\":\{failure.offset().value()}",
        new="\"offset\":\{wrong_offset}",
      ),
    ),
  )
  assert_true(
    parse_snapshot_json_is_rejected(
      encoded.replace(
        old="\"kind\":\"SourceFile\"",
        new="\"kind\":\"BlockExpression\"",
      ),
    ),
  )
}

///|
test "reparse validates an edit and matches a complete parse" {
  let original = "fn f() -> Unit {}"
  let source = parser_test_source(original)
  let previous = @parser.parse(source)
  let edit = @source.TextEdit::new(
    source.id(),
    source.revision(),
    @source.TextRange::new(
      @source.TextOffset::new(3),
      @source.TextOffset::new(4),
    ),
    "read",
  )
  let updated = source.apply_edit(edit)
  let incremental = @parser.reparse(previous, updated, edit)
  let complete = @parser.parse(updated)
  assert_eq(incremental, complete)
  assert_eq(incremental.source_text(), "fn read() -> Unit {}")
}
