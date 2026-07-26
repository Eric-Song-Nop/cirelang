///|
fn test_source(text : String) -> @source.SourceSnapshot {
  @source.SourceSnapshot::new(
    @source.SourceId::new(11),
    @source.SourceRevision::initial(),
    "lexer_test.cire",
    text,
  )
}

///|
fn token_kinds(snapshot : @lexer.LexSnapshot) -> Array[@syntax.SyntaxKind] {
  snapshot.tokens().tokens().map(token => token.kind())
}

///|
test "lexer is lossless across trivia and UTF-16 text" {
  let text = "let value = \"😀\" // 😀\r\n/* outer\n/* inner */ end */\t"
  let snapshot = @lexer.lex(test_source(text))
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  let tokens = snapshot.tokens().tokens()
  let mut string_seen = false
  let mut line_comment_seen = false
  for token in tokens {
    if token.kind() == StringLiteral {
      string_seen = true
      assert_eq(token.text(), "\"😀\"")
      assert_eq(token.range().length(), 4)
    }
    if token.kind() == LineComment {
      line_comment_seen = true
      assert_eq(token.text(), "// 😀")
      assert_eq(token.range().length(), 5)
    }
  }
  assert_true(string_seen)
  assert_true(line_comment_seen)
}

///|
test "quoted literals consume escaped delimiters" {
  let text = "\"a\\\"b\" '\\n' '\\''"
  let snapshot = @lexer.lex(test_source(text))
  assert_eq(snapshot.source_text(), text)
  assert_eq(snapshot.diagnostics(), [])
  assert_eq(
    snapshot
    .tokens()
    .tokens()
    .filter(token => !token.is_trivia())
    .map(token => token.kind()),
    [StringLiteral, CharLiteral, CharLiteral, Eof],
  )
}

///|
test "newline tokens distinguish LF CR and CRLF from whitespace" {
  let snapshot = @lexer.lex(test_source(" \t\n\r\r\n  "))
  assert_eq(token_kinds(snapshot), [
    Whitespace,
    Newline,
    Newline,
    Newline,
    Whitespace,
    Eof,
  ])
  let tokens = snapshot.tokens().tokens()
  assert_eq(tokens[1].text(), "\n")
  assert_eq(tokens[2].text(), "\r")
  assert_eq(tokens[3].text(), "\r\n")
}

///|
test "keywords identifiers numbers and punctuation use longest match" {
  let snapshot = @lexer.lex(
    test_source(
      "effect Read read _ _value 1 1.25 1e+2 :: -> => == != <= >= && || .. @",
    ),
  )
  assert_eq(snapshot.diagnostics(), [])
  let significant = snapshot
    .tokens()
    .tokens()
    .filter(token => !token.is_trivia())
    .map(token => token.kind())
  assert_eq(significant, [
    KwEffect,
    UpperIdentifier,
    LowerIdentifier,
    Underscore,
    Identifier,
    IntLiteral,
    FloatLiteral,
    FloatLiteral,
    ColonColon,
    Arrow,
    FatArrow,
    EqEq,
    BangEq,
    LessEq,
    GreaterEq,
    AmpAmp,
    PipePipe,
    DotDot,
    At,
    Eof,
  ])
  for index, token in snapshot.tokens().tokens() {
    assert_eq(token.id().value(), index)
  }
}

///|
test "numeric boundaries do not swallow ranges or malformed exponents" {
  let snapshot = @lexer.lex(test_source("1..2 1e 1e+"))
  assert_eq(
    snapshot
    .tokens()
    .tokens()
    .filter(token => !token.is_trivia())
    .map(token => token.kind()),
    [
      IntLiteral,
      DotDot,
      IntLiteral,
      IntLiteral,
      LowerIdentifier,
      IntLiteral,
      LowerIdentifier,
      Plus,
      Eof,
    ],
  )
  assert_eq(snapshot.source_text(), "1..2 1e 1e+")
}

///|
test "empty source has one canonical EOF token" {
  let snapshot = @lexer.lex(test_source(""))
  let tokens = snapshot.tokens().tokens()
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].id().value(), 0)
  assert_eq(tokens[0].kind(), Eof)
  assert_eq(
    tokens[0].range(),
    @source.TextRange::empty(@source.TextOffset::zero()),
  )
}

///|
test "malformed input preserves tokens and reports deterministic diagnostics" {
  // Non-ASCII identifiers remain deliberately conservative until Cire's
  // identifier policy is specified; each Unicode scalar is one invalid token.
  let text = "😀 \"open\n'x\n/* nested /* inner */"
  let snapshot = @lexer.lex(test_source(text))
  assert_eq(snapshot.source_text(), text)
  let diagnostics = snapshot.diagnostics()
  assert_eq(diagnostics.length(), 4)
  assert_eq(diagnostics[0].code().value(), "CIRE-L0001")
  assert_eq(diagnostics[1].code().value(), "CIRE-L0002")
  assert_eq(diagnostics[2].code().value(), "CIRE-L0003")
  assert_eq(diagnostics[3].code().value(), "CIRE-L0004")
  assert_eq(
    diagnostics[0].labels()[0].span().range(),
    @source.TextRange::new(
      @source.TextOffset::new(0),
      @source.TextOffset::new(2),
    ),
  )
  assert_eq(diagnostics[0].revision(), @source.SourceRevision::initial())
  assert_eq(diagnostics[0].stage(), Lex)
  assert_eq(diagnostics[0].severity(), Error)
}

///|
test "lexer snapshot JSON round-trip" {
  let snapshot = @lexer.lex(test_source("pub fn answer() -> Int { 42 }\n"))
  let encoded = snapshot.to_json().stringify()
  let decoded : @lexer.LexSnapshot = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, snapshot)
  try
    (
      @json.from_json(
        @json.parse(
          encoded.replace(
            old="\"revision\":0,\"tokens\"",
            new="\"revision\":1,\"tokens\"",
          ),
        ),
      ) : @lexer.LexSnapshot)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected inconsistent snapshot metadata to be rejected")
  }
}

///|
test "relex API is observationally equivalent to a full lex" {
  let source = test_source("let answer = 1")
  let previous = @lexer.lex(source)
  let edit = @source.TextEdit::new(
    source.id(),
    source.revision(),
    @source.TextRange::new(
      @source.TextOffset::new(13),
      @source.TextOffset::new(14),
    ),
    "42",
  )
  let edited = source.apply_edit(edit)
  assert_eq(@lexer.relex(previous, edited, edit), @lexer.lex(edited))
}

///|
test "relex rejects stale edits and mismatched updated snapshots" {
  let source = test_source("let answer = 1")
  let previous = @lexer.lex(source)
  let stale = @source.TextEdit::new(
    source.id(),
    @source.SourceRevision::new(2),
    @source.TextRange::empty(@source.TextOffset::zero()),
    "",
  )
  try @lexer.relex(previous, source, stale) catch {
    EditStaleRevision(..) => ()
    _ => fail("expected EditStaleRevision")
  } noraise {
    _ => fail("expected stale relex input to be rejected")
  }
  let edit = @source.TextEdit::new(
    source.id(),
    source.revision(),
    @source.TextRange::new(
      @source.TextOffset::new(13),
      @source.TextOffset::new(14),
    ),
    "42",
  )
  let wrong_text = @source.SourceSnapshot::new(
    source.id(),
    source.revision().next(),
    source.logical_path(),
    "let answer = 99",
  )
  try @lexer.relex(previous, wrong_text, edit) catch {
    UpdatedTextMismatch => ()
    _ => fail("expected UpdatedTextMismatch")
  } noraise {
    _ => fail("expected mismatched relex text to be rejected")
  }
}
