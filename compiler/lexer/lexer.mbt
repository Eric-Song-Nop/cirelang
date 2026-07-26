///|
priv struct Lexer {
  source : @source.SourceSnapshot
  text : String
  mut cursor : Int
  tokens : Array[@syntax.Token]
  diagnostics : Array[@diagnostic.Diagnostic]
}

///|
fn Lexer::new(source : @source.SourceSnapshot) -> Lexer {
  { source, text: source.text(), cursor: 0, tokens: [], diagnostics: [] }
}

///|
fn Lexer::current(self : Lexer) -> Char? {
  self.text.get_char(self.cursor)
}

///|
fn Lexer::char_at(self : Lexer, offset : Int) -> Char? {
  self.text.get_char(offset)
}

///|
fn Lexer::advance_scalar(self : Lexer) -> Unit {
  guard self.current() is Some(char) else { return }
  self.cursor = self.cursor + char.utf16_len()
}

///|
fn Lexer::matches_ascii_pair(self : Lexer, first : Char, second : Char) -> Bool {
  self.char_at(self.cursor) == Some(first) &&
  self.char_at(self.cursor + 1) == Some(second)
}

///|
fn Lexer::slice(self : Lexer, start : Int, end : Int) -> String {
  self.text.get_view(start~, end~).unwrap().to_owned()
}

///|
fn Lexer::emit(self : Lexer, kind : @syntax.SyntaxKind, start : Int) -> Unit {
  let end = self.cursor
  let range = @source.TextRange::new(
    @source.TextOffset::new(start),
    @source.TextOffset::new(end),
  )
  self.tokens.push(
    @syntax.Token::new(
      @syntax.TokenId::new(self.tokens.length()),
      kind,
      range,
      self.slice(start, end),
    ),
  )
}

///|
fn Lexer::report(
  self : Lexer,
  code : String,
  message : String,
  label_message : String,
  start : Int,
  end : Int,
) -> Unit {
  let range = @source.TextRange::new(
    @source.TextOffset::new(start),
    @source.TextOffset::new(end),
  )
  self.diagnostics.push(
    @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new(code),
      Lex,
      Error,
      message,
      @diagnostic.Label::primary(
        @source.Span::new(self.source.id(), range),
        label_message,
      ),
      self.source.revision(),
    ),
  )
}

///|
fn is_ascii_lower(char : Char) -> Bool {
  char >= 'a' && char <= 'z'
}

///|
fn is_ascii_upper(char : Char) -> Bool {
  char >= 'A' && char <= 'Z'
}

///|
fn is_ascii_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
fn is_identifier_continue(char : Char) -> Bool {
  is_ascii_lower(char) ||
  is_ascii_upper(char) ||
  is_ascii_digit(char) ||
  char == '_'
}

///|
fn is_horizontal_whitespace(char : Char) -> Bool {
  char == ' ' || char == '\t' || char == '\u{000b}' || char == '\u{000c}'
}

///|
fn Lexer::scan_whitespace(self : Lexer) -> Unit {
  while self.current() is Some(char) && is_horizontal_whitespace(char) {
    self.cursor = self.cursor + 1
  }
}

///|
fn Lexer::scan_newline(self : Lexer) -> Unit {
  if self.matches_ascii_pair('\r', '\n') {
    self.cursor = self.cursor + 2
  } else {
    self.cursor = self.cursor + 1
  }
}

///|
fn Lexer::scan_line_comment(self : Lexer) -> Unit {
  self.cursor = self.cursor + 2
  while self.current() is Some(char) && char != '\r' && char != '\n' {
    self.advance_scalar()
  }
}

///|
fn Lexer::scan_block_comment(self : Lexer, start : Int) -> Unit {
  self.cursor = self.cursor + 2
  let mut depth = 1
  while self.cursor < self.text.length() && depth > 0 {
    if self.matches_ascii_pair('/', '*') {
      depth = depth + 1
      self.cursor = self.cursor + 2
    } else if self.matches_ascii_pair('*', '/') {
      depth = depth - 1
      self.cursor = self.cursor + 2
    } else {
      self.advance_scalar()
    }
  }
  if depth > 0 {
    self.report(
      "CIRE-L0004",
      "unterminated block comment",
      "this block comment is not closed",
      start,
      self.cursor,
    )
  }
}

///|
fn Lexer::scan_identifier(self : Lexer, start : Int) -> @syntax.SyntaxKind {
  self.cursor = self.cursor + 1
  while self.current() is Some(char) && is_identifier_continue(char) {
    self.cursor = self.cursor + 1
  }
  let view = self.text.get_view(start~, end=self.cursor).unwrap()
  match @syntax.keyword_kind(view) {
    Some(kind) => return kind
    None => ()
  }
  let first = self.text.get_char(start).unwrap()
  if is_ascii_lower(first) {
    LowerIdentifier
  } else if is_ascii_upper(first) {
    UpperIdentifier
  } else if self.cursor == start + 1 {
    Underscore
  } else {
    Identifier
  }
}

///|
fn Lexer::scan_ascii_digits(self : Lexer) -> Unit {
  while self.current() is Some(char) && (is_ascii_digit(char) || char == '_') {
    self.cursor = self.cursor + 1
  }
}

///|
fn Lexer::has_exponent_digits(self : Lexer, marker : Int) -> Bool {
  let mut offset = marker + 1
  match self.char_at(offset) {
    Some('+') | Some('-') => offset = offset + 1
    _ => ()
  }
  match self.char_at(offset) {
    Some(char) => is_ascii_digit(char)
    None => false
  }
}

///|
fn Lexer::scan_number(self : Lexer) -> @syntax.SyntaxKind {
  self.scan_ascii_digits()
  let mut is_float = false
  if self.char_at(self.cursor) == Some('.') &&
    self.char_at(self.cursor + 1) is Some(next) &&
    is_ascii_digit(next) {
    is_float = true
    self.cursor = self.cursor + 1
    self.scan_ascii_digits()
  }
  match self.char_at(self.cursor) {
    Some('e') | Some('E') if self.has_exponent_digits(self.cursor) => {
      is_float = true
      self.cursor = self.cursor + 1
      match self.current() {
        Some('+') | Some('-') => self.cursor = self.cursor + 1
        _ => ()
      }
      self.scan_ascii_digits()
    }
    _ => ()
  }
  if is_float {
    FloatLiteral
  } else {
    IntLiteral
  }
}

///|
fn Lexer::scan_quoted(
  self : Lexer,
  start : Int,
  quote : Char,
  kind : @syntax.SyntaxKind,
  diagnostic_code : String,
  diagnostic_message : String,
) -> Unit {
  self.cursor = self.cursor + 1
  let mut terminated = false
  while self.cursor < self.text.length() && !terminated {
    match self.current() {
      Some(char) if char == quote => {
        self.cursor = self.cursor + 1
        terminated = true
      }
      Some('\\') => {
        self.cursor = self.cursor + 1
        match self.current() {
          Some('\r') | Some('\n') | None => ()
          Some(_) => self.advance_scalar()
        }
      }
      Some('\r') | Some('\n') | None => ()
      Some(_) => self.advance_scalar()
    }
    if !terminated {
      match self.current() {
        Some('\r') | Some('\n') | None => break
        _ => ()
      }
    }
  }
  self.emit(kind, start)
  if !terminated {
    self.report(
      diagnostic_code,
      diagnostic_message,
      "this literal is not closed",
      start,
      self.cursor,
    )
  }
}

///|
fn Lexer::punctuation(self : Lexer) -> (@syntax.SyntaxKind, Int)? {
  if self.matches_ascii_pair('.', '.') {
    return Some((DotDot, 2))
  }
  if self.matches_ascii_pair(':', ':') {
    return Some((ColonColon, 2))
  }
  if self.matches_ascii_pair('-', '>') {
    return Some((Arrow, 2))
  }
  if self.matches_ascii_pair('=', '>') {
    return Some((FatArrow, 2))
  }
  if self.matches_ascii_pair('=', '=') {
    return Some((EqEq, 2))
  }
  if self.matches_ascii_pair('!', '=') {
    return Some((BangEq, 2))
  }
  if self.matches_ascii_pair('<', '=') {
    return Some((LessEq, 2))
  }
  if self.matches_ascii_pair('>', '=') {
    return Some((GreaterEq, 2))
  }
  if self.matches_ascii_pair('&', '&') {
    return Some((AmpAmp, 2))
  }
  if self.matches_ascii_pair('|', '|') {
    return Some((PipePipe, 2))
  }
  match self.current() {
    Some('@') => Some((At, 1))
    Some('!') => Some((Bang, 1))
    Some('?') => Some((Question, 1))
    Some('#') => Some((Hash, 1))
    Some('$') => Some((Dollar, 1))
    Some('(') => Some((LParen, 1))
    Some(')') => Some((RParen, 1))
    Some('[') => Some((LBracket, 1))
    Some(']') => Some((RBracket, 1))
    Some('{') => Some((LBrace, 1))
    Some('}') => Some((RBrace, 1))
    Some(',') => Some((Comma, 1))
    Some(':') => Some((Colon, 1))
    Some(';') => Some((Semicolon, 1))
    Some('.') => Some((Dot, 1))
    Some('=') => Some((Equals, 1))
    Some('<') => Some((Less, 1))
    Some('>') => Some((Greater, 1))
    Some('+') => Some((Plus, 1))
    Some('-') => Some((Minus, 1))
    Some('*') => Some((Star, 1))
    Some('/') => Some((Slash, 1))
    Some('%') => Some((Percent, 1))
    Some('&') => Some((Amp, 1))
    Some('|') => Some((Pipe, 1))
    Some('^') => Some((Caret, 1))
    Some('~') => Some((Tilde, 1))
    _ => None
  }
}

///|
fn Lexer::scan_one(self : Lexer) -> Unit {
  let start = self.cursor
  guard self.current() is Some(char) else { return }
  if is_horizontal_whitespace(char) {
    self.scan_whitespace()
    self.emit(Whitespace, start)
  } else if char == '\r' || char == '\n' {
    self.scan_newline()
    self.emit(Newline, start)
  } else if self.matches_ascii_pair('/', '/') {
    self.scan_line_comment()
    self.emit(LineComment, start)
  } else if self.matches_ascii_pair('/', '*') {
    self.scan_block_comment(start)
    self.emit(BlockComment, start)
  } else if is_ascii_lower(char) || is_ascii_upper(char) || char == '_' {
    let kind = self.scan_identifier(start)
    self.emit(kind, start)
  } else if is_ascii_digit(char) {
    let kind = self.scan_number()
    self.emit(kind, start)
  } else if char == '"' {
    self.scan_quoted(
      start,
      '"',
      StringLiteral,
      "CIRE-L0002",
      "unterminated string literal",
    )
  } else if char == '\'' {
    self.scan_quoted(
      start,
      '\'',
      CharLiteral,
      "CIRE-L0003",
      "unterminated character literal",
    )
  } else {
    match self.punctuation() {
      Some((kind, width)) => {
        self.cursor = self.cursor + width
        self.emit(kind, start)
      }
      None => {
        // Until Cire freezes its Unicode identifier policy, non-ASCII scalars
        // outside literals and comments are conservatively invalid. Consuming
        // one scalar (not one UTF-16 code unit) keeps all ranges well formed.
        self.advance_scalar()
        self.emit(InvalidToken, start)
        self.report(
          "CIRE-L0001",
          "invalid character",
          "this character is not valid Cire syntax",
          start,
          self.cursor,
        )
      }
    }
  }
}

///|
fn Lexer::finish(self : Lexer) -> LexSnapshot {
  let at = @source.TextOffset::new(self.cursor)
  self.tokens.push(
    @syntax.Token::new(
      @syntax.TokenId::new(self.tokens.length()),
      Eof,
      @source.TextRange::empty(at),
      "",
    ),
  )
  let token_snapshot = @syntax.TokenSnapshot::new(
    self.source.id(),
    self.source.revision(),
    self.tokens,
  )
  LexSnapshot::new(
    self.source.id(),
    self.source.revision(),
    token_snapshot,
    self.diagnostics,
  )
}

///|
/// Lexes a decoded Cire source snapshot into a lossless token stream.
///
/// The scanner cursor and every token range are measured in UTF-16 code units.
/// It advances through arbitrary text only with `String::get_char` and
/// `Char::utf16_len`, so it cannot split a surrogate pair and its offsets can
/// be passed directly to the default LSP adapter.
pub fn lex(source : @source.SourceSnapshot) -> LexSnapshot {
  let lexer = Lexer::new(source)
  while lexer.cursor < lexer.text.length() {
    lexer.scan_one()
  }
  lexer.finish()
}
