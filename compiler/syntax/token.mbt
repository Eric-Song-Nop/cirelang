///|
/// A snapshot-local lexical token identity.
///
/// Persistent artifacts must pair it with a source and revision; it is not a
/// declaration identity and is allowed to change after an edit.
pub struct TokenId(Int) derive(Debug, Eq)

///|
pub fn TokenId::new(value : Int) -> TokenId {
  guard value >= 0
  TokenId(value)
}

///|
pub fn TokenId::value(self : TokenId) -> Int {
  self.0
}

///|
pub impl ToJson for TokenId with fn to_json(self : TokenId) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for TokenId with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TokenId raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    syntax_json_decode_error(path, "TokenId: expected a non-negative integer")
  } else {
    TokenId(value)
  }
}

///|
fn[T] syntax_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
/// One token in the lossless lexer stream.
///
/// Trivia and invalid input are ordinary token kinds. The range and text use
/// UTF-16 code units and must have the same length. EOF is represented by an
/// empty token at the end of the source.
pub struct Token {
  priv id : TokenId
  priv kind : SyntaxKind
  priv range : @source.TextRange
  priv text : String
} derive(Debug, Eq, ToJson)

///|
struct TokenRaw {
  id : TokenId
  kind : SyntaxKind
  range : @source.TextRange
  text : String
} derive(FromJson)

///|
pub impl @json.FromJson for Token with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Token raise @json.JsonDecodeError {
  let raw : TokenRaw = @json.from_json(json, path~)
  if !token_shape_is_valid(raw.kind, raw.range, raw.text) {
    syntax_json_decode_error(
      path, "Token: kind, range, and text do not form a valid lexical token",
    )
  } else {
    { id: raw.id, kind: raw.kind, range: raw.range, text: raw.text }
  }
}

///|
pub fn Token::new(
  id : TokenId,
  kind : SyntaxKind,
  range : @source.TextRange,
  text : String,
) -> Token {
  guard token_shape_is_valid(kind, range, text)
  { id, kind, range, text }
}

///|
fn token_shape_is_valid(
  kind : SyntaxKind,
  range : @source.TextRange,
  text : String,
) -> Bool {
  kind.is_token() &&
  range.length() == text.length() &&
  (if kind == Eof {
    text.is_empty() && range.is_empty()
  } else {
    !text.is_empty()
  })
}

///|
pub fn Token::id(self : Token) -> TokenId {
  self.id
}

///|
pub fn Token::kind(self : Token) -> SyntaxKind {
  self.kind
}

///|
pub fn Token::range(self : Token) -> @source.TextRange {
  self.range
}

///|
pub fn Token::text(self : Token) -> String {
  self.text
}

///|
pub fn Token::is_trivia(self : Token) -> Bool {
  self.kind.is_trivia()
}

///|
pub fn Token::is_eof(self : Token) -> Bool {
  self.kind == Eof
}

///|
/// Immutable lexer output pinned to one source revision.
pub struct TokenSnapshot {
  priv source : @source.SourceId
  priv revision : @source.SourceRevision
  priv tokens : Array[Token]
} derive(Debug, Eq, ToJson)

///|
struct TokenSnapshotRaw {
  source : @source.SourceId
  revision : @source.SourceRevision
  tokens : Array[Token]
} derive(FromJson)

///|
pub impl @json.FromJson for TokenSnapshot with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TokenSnapshot raise @json.JsonDecodeError {
  let raw : TokenSnapshotRaw = @json.from_json(json, path~)
  if !token_stream_is_canonical(raw.tokens) {
    syntax_json_decode_error(
      path.add_key("tokens"),
      "TokenSnapshot: expected one contiguous token stream ending in EOF",
    )
  } else {
    { source: raw.source, revision: raw.revision, tokens: raw.tokens.copy() }
  }
}

///|
pub fn TokenSnapshot::new(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  tokens : Array[Token],
) -> TokenSnapshot {
  guard token_stream_is_canonical(tokens)
  { source, revision, tokens: tokens.copy() }
}

///|
fn token_stream_is_canonical(tokens : Array[Token]) -> Bool {
  if tokens.is_empty() {
    return false
  }
  let mut cursor = @source.TextOffset::zero()
  for index, token in tokens {
    if token.id().value() != index ||
      token.range().start() != cursor ||
      !token_shape_is_valid(token.kind(), token.range(), token.text()) {
      return false
    }
    if token.kind() == Eof {
      return index == tokens.length() - 1
    }
    cursor = token.range().end()
  }
  false
}

///|
pub fn TokenSnapshot::source(self : TokenSnapshot) -> @source.SourceId {
  self.source
}

///|
pub fn TokenSnapshot::revision(self : TokenSnapshot) -> @source.SourceRevision {
  self.revision
}

///|
pub fn TokenSnapshot::length(self : TokenSnapshot) -> Int {
  self.tokens.length()
}

///|
pub fn TokenSnapshot::token_at(self : TokenSnapshot, index : Int) -> Token? {
  self.tokens.get(index)
}

///|
pub fn TokenSnapshot::token(self : TokenSnapshot, id : TokenId) -> Token? {
  for token in self.tokens {
    if token.id() == id {
      return Some(token)
    }
  }
  None
}

///|
/// Returns a defensive copy so a snapshot cannot be mutated through its API.
pub fn TokenSnapshot::tokens(self : TokenSnapshot) -> Array[Token] {
  self.tokens.copy()
}

///|
/// Reconstructs the exact decoded source represented by the token stream.
pub fn TokenSnapshot::source_text(self : TokenSnapshot) -> String {
  let output = StringBuilder()
  for token in self.tokens {
    output.write_string(token.text())
  }
  output.to_string()
}
