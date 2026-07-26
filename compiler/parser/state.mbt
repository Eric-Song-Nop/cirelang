///|
priv struct RuleFrame {
  key : MemoKey
  label : String
  committed : Bool
  entry_cut_epoch : Int
  entry_failure_committed : Bool
}

///|
priv struct ParserCheckpoint {
  raw_index : Int
  event_count : Int
  rewrite_count : Int
  diagnostic_count : Int
  failure : FailureSummary?
  failure_committed : Bool
  cut_epoch : Int
  node_depth : Int
  marker_depth : Int
  rule_frames : Array[RuleFrame]
  active_rules : Array[MemoKey]
  contexts : Array[String]
}

///|
priv struct ProgressMark {
  raw_index : Int
}

///|
/// Mutable state shared by handwritten grammar functions.
///
/// Grammar files live in this package and use the focused cursor, event,
/// choice, and rule-scope methods below. Rules remain ordinary MoonBit
/// functions; this type is deliberately not a parser-combinator DSL.
priv struct Parser {
  tokens : @syntax.TokenSnapshot
  mut raw_index : Int
  pending_events : Array[PendingEvent]
  event_rewrites : Array[EventRewrite]
  diagnostics : Array[@diagnostic.Diagnostic]
  mut failure : FailureSummary?
  mut failure_committed : Bool
  mut cut_epoch : Int
  mut node_depth : Int
  mut marker_depth : Int
  mut rule_frames : Array[RuleFrame]
  mut active_rules : Array[MemoKey]
  mut contexts : Array[String]
}

///|
fn Parser::new(tokens : @syntax.TokenSnapshot) -> Parser {
  {
    tokens,
    raw_index: 0,
    pending_events: [],
    event_rewrites: [],
    diagnostics: [],
    failure: None,
    failure_committed: false,
    cut_epoch: 0,
    node_depth: 0,
    marker_depth: 0,
    rule_frames: [],
    active_rules: [],
    contexts: [],
  }
}

///|
fn Parser::token_snapshot(self : Parser) -> @syntax.TokenSnapshot {
  self.tokens
}

///|
/// Index of the next non-trivia token, or `TokenSnapshot::length()` when the
/// cursor is exhausted.
fn Parser::significant_index(self : Parser) -> Int {
  for index = self.raw_index; index < self.tokens.length(); index = index + 1 {
    match self.tokens.token_at(index) {
      Some(token) => if !token.is_trivia() { return index }
      None => return self.tokens.length()
    }
  } nobreak {
    self.tokens.length()
  }
}

///|
fn Parser::current_token(self : Parser) -> @syntax.Token? {
  self.tokens.token_at(self.significant_index())
}

///|
fn Parser::current_kind(self : Parser) -> @syntax.SyntaxKind? {
  self.current_token().map(token => token.kind())
}

///|
fn Parser::at(self : Parser, kind : @syntax.SyntaxKind) -> Bool {
  self.current_kind() == Some(kind)
}

///|
fn Parser::current_offset(self : Parser) -> @source.TextOffset {
  match self.current_token() {
    Some(token) => token.range().start()
    None =>
      match self.tokens.token_at(self.tokens.length() - 1) {
        Some(token) => token.range().end()
        None => @source.TextOffset::zero()
      }
  }
}

///|
/// Returns defensive copies suitable for building a green tree or a parse
/// artifact after the grammar entry point completes.
fn Parser::events(self : Parser) -> Array[@syntax.TreeEvent] {
  guard self.node_depth == 0 && self.marker_depth == 0
  lower_pending_events(self.pending_events)
}

///|
fn Parser::diagnostics(self : Parser) -> Array[@diagnostic.Diagnostic] {
  self.diagnostics.copy()
}

///|
fn Parser::failure(self : Parser) -> FailureSummary? {
  self.failure
}

///|
fn Parser::checkpoint(self : Parser) -> ParserCheckpoint {
  {
    raw_index: self.raw_index,
    event_count: self.pending_events.length(),
    rewrite_count: self.event_rewrites.length(),
    diagnostic_count: self.diagnostics.length(),
    failure: self.failure,
    failure_committed: self.failure_committed,
    cut_epoch: self.cut_epoch,
    node_depth: self.node_depth,
    marker_depth: self.marker_depth,
    rule_frames: self.rule_frames.copy(),
    active_rules: self.active_rules.copy(),
    contexts: self.contexts.copy(),
  }
}

///|
/// Restores every part of speculative parser state. Events and diagnostics
/// are truncated in place so speculative output can never escape.
fn Parser::rollback(self : Parser, checkpoint : ParserCheckpoint) -> Unit {
  self.raw_index = checkpoint.raw_index
  for index = self.event_rewrites.length() - 1
      index >= checkpoint.rewrite_count
      index = index - 1 {
    let rewrite = self.event_rewrites[index]
    self.pending_events[rewrite.index] = rewrite.previous
  }
  self.event_rewrites.truncate(checkpoint.rewrite_count)
  self.pending_events.truncate(checkpoint.event_count)
  self.diagnostics.truncate(checkpoint.diagnostic_count)
  self.failure = checkpoint.failure
  self.failure_committed = checkpoint.failure_committed
  self.cut_epoch = checkpoint.cut_epoch
  self.node_depth = checkpoint.node_depth
  self.marker_depth = checkpoint.marker_depth
  self.rule_frames = checkpoint.rule_frames.copy()
  self.active_rules = checkpoint.active_rules.copy()
  self.contexts = checkpoint.contexts.copy()
}

///|
fn Parser::progress_mark(self : Parser) -> ProgressMark {
  { raw_index: self.raw_index }
}

///|
/// A repetition loop must stop when this returns `false`. The recorded
/// expectation makes a zero-width grammar bug visible without hanging.
fn Parser::require_progress(
  self : Parser,
  mark : ProgressMark,
  context : String,
) -> Bool {
  if self.raw_index > mark.raw_index {
    true
  } else {
    self.fail_expected("progress while parsing \{context}")
  }
}
