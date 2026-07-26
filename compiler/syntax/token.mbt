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
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Token::new(
  id : TokenId,
  kind : SyntaxKind,
  range : @source.TextRange,
  text : String,
) -> Token {
  guard kind.is_token() && range.length() == text.length()
  { id, kind, range, text }
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
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn TokenSnapshot::new(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  tokens : Array[Token],
) -> TokenSnapshot {
  { source, revision, tokens: tokens.copy() }
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
