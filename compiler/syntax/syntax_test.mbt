///|
fn test_range(start : Int, end : Int) -> @source.TextRange {
  @source.TextRange::new(
    @source.TextOffset::new(start),
    @source.TextOffset::new(end),
  )
}

///|
test "syntax kinds expose stable lexical metadata" {
  assert_true(@syntax.KwEffect.is_keyword())
  assert_true(@syntax.LBrace.is_punctuation())
  assert_true(@syntax.Whitespace.is_trivia())
  assert_true(@syntax.Newline.is_trivia())
  assert_true(@syntax.SourceFile.is_node())
  assert_eq(@syntax.keyword_kind("effect"), Some(KwEffect))
  assert_eq(@syntax.keyword_kind("Read"), None)
  inspect(@syntax.EffectDeclaration.wire_name(), content="effect_declaration")
}

///|
test "lossless token snapshot and JSON round-trip" {
  let tokens = [
    @syntax.Token::new(
      @syntax.TokenId::new(0),
      KwEffect,
      test_range(0, 6),
      "effect",
    ),
    @syntax.Token::new(
      @syntax.TokenId::new(1),
      Whitespace,
      test_range(6, 7),
      " ",
    ),
    @syntax.Token::new(
      @syntax.TokenId::new(2),
      UpperIdentifier,
      test_range(7, 11),
      "Read",
    ),
    @syntax.Token::new(@syntax.TokenId::new(3), Eof, test_range(11, 11), ""),
  ]
  let snapshot = @syntax.TokenSnapshot::new(
    @source.SourceId::new(2),
    @source.SourceRevision::new(4),
    tokens,
  )
  inspect(snapshot.source_text(), content="effect Read")
  let encoded = snapshot.to_json().stringify()
  let decoded : @syntax.TokenSnapshot = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, snapshot)
  try
    (
      @json.from_json(
        @json.parse(encoded.replace(old="\"KwEffect\"", new="\"SourceFile\"")),
      ) : @syntax.TokenSnapshot)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected a node-kind token to be rejected")
  }
}

///|
test "green builder preserves UTF-16 text and missing tokens" {
  let events : Array[@syntax.TreeEvent] = [
    Start(SourceFile),
    Start(EffectDeclaration),
    Token(
      @syntax.Token::new(
        @syntax.TokenId::new(0),
        KwEffect,
        test_range(0, 6),
        "effect",
      ),
    ),
    Token(
      @syntax.Token::new(
        @syntax.TokenId::new(1),
        Whitespace,
        test_range(6, 7),
        " ",
      ),
    ),
    Token(
      @syntax.Token::new(
        @syntax.TokenId::new(2),
        Identifier,
        test_range(7, 9),
        "😀",
      ),
    ),
    Missing(LBrace),
    Finish,
    Token(
      @syntax.Token::new(@syntax.TokenId::new(3), Eof, test_range(9, 9), ""),
    ),
    Finish,
  ]
  let root = @syntax.build_green(events)
  inspect(root.text_length(), content="9")
  inspect(root.source_text(), content="effect 😀")
  inspect(
    root.to_sexpr(),
    content=(
      #|(source_file (effect_declaration (kw_effect "effect") (whitespace " ") (identifier "😀") (missing l_brace)) (eof ""))
    ),
  )
  let encoded = root.to_json().stringify()
  let decoded : @syntax.GreenNode = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, root)
}

///|
test "red views derive exact UTF-16 ranges and snapshot-local IDs" {
  let child = @syntax.GreenNode::new(NameExpression, [
    Token(
      @syntax.GreenToken::from_token(
        @syntax.Token::new(
          @syntax.TokenId::new(0),
          Identifier,
          test_range(0, 2),
          "😀",
        ),
      ),
    ),
  ])
  let root = @syntax.GreenNode::new(SourceFile, [
    Node(child),
    Token(
      @syntax.GreenToken::from_token(
        @syntax.Token::new(@syntax.TokenId::new(1), Eof, test_range(2, 2), ""),
      ),
    ),
  ])
  let tree = @syntax.SyntaxTree::new(
    @source.SourceId::new(8),
    @source.SourceRevision::initial(),
    root,
  )
  inspect(tree.root().range().end().value(), content="2")
  guard tree.root().children()[0] is Node(name) else {
    fail("expected a child node")
  }
  inspect(name.id().value(), content="1")
  inspect(name.range().start().value(), content="0")
  inspect(name.range().end().value(), content="2")
}
