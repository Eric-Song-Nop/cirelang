///|
/// Emits pending trivia without consuming the next significant token.
///
/// Missing tokens are positioned at the parser's significant offset, so
/// pending trivia must precede their zero-width event in the green stream.
fn Parser::flush_trivia(self : Parser) -> Unit {
  let significant = self.significant_index()
  for index in self.raw_index..<significant {
    guard self.tokens.token_at(index) is Some(token) else { continue }
    guard token.is_trivia()
    self.pending_events.push(PendingToken(token))
  }
  self.raw_index = significant
}

///|
/// Emits exactly one raw token. Recovery uses this to recognize trivia
/// synchronization points such as a newline.
fn Parser::bump_raw(self : Parser) -> @syntax.Token? {
  guard self.tokens.token_at(self.raw_index) is Some(token) else { return None }
  self.pending_events.push(PendingToken(token))
  self.raw_index = self.raw_index + 1
  Some(token)
}

///|
/// Consumes the next significant token and emits every trivia token preceding
/// it. No source token is synthesized or discarded.
fn Parser::bump(self : Parser) -> @syntax.Token? {
  let significant = self.significant_index()
  guard significant < self.tokens.length() else { return None }
  guard self.tokens.token_at(significant) is Some(result) else { return None }
  for index in self.raw_index..<=significant {
    guard self.tokens.token_at(index) is Some(token) else { continue }
    self.pending_events.push(PendingToken(token))
  }
  self.raw_index = significant + 1
  Some(result)
}

///|
fn Parser::eat(self : Parser, kind : @syntax.SyntaxKind) -> Bool {
  if self.at(kind) {
    ignore(self.bump())
    true
  } else {
    false
  }
}

///|
fn Parser::start_node(self : Parser, kind : @syntax.SyntaxKind) -> Unit {
  guard kind.is_node()
  self.pending_events.push(PendingStart(kind, None))
  self.node_depth = self.node_depth + 1
}

///|
fn Parser::finish_node(self : Parser) -> Unit {
  guard self.node_depth > 0
  self.pending_events.push(PendingFinish)
  self.node_depth = self.node_depth - 1
}

///|
fn Parser::missing(self : Parser, kind : @syntax.SyntaxKind) -> Unit {
  guard kind.is_token() && kind != Eof
  self.flush_trivia()
  self.pending_events.push(PendingMissing(kind))
  self.clear_failure_commit()
}

///|
fn Parser::emit_diagnostic(
  self : Parser,
  diagnostic : @diagnostic.Diagnostic,
) -> Unit {
  self.diagnostics.push(diagnostic)
}

///|
fn syntax_kind_in(
  kinds : ArrayView[@syntax.SyntaxKind],
  needle : @syntax.SyntaxKind,
) -> Bool {
  for kind in kinds {
    if kind == needle {
      return true
    }
  }
  false
}

///|
/// Returns whether the raw cursor is currently at a synchronization boundary.
///
/// Significant synchronization tokens own any pending leading trivia, while a
/// trivia synchronization token such as `Newline` is recognized exactly.
fn Parser::at_recovery_boundary(
  self : Parser,
  synchronization : ArrayView[@syntax.SyntaxKind],
) -> Bool {
  match self.current_kind() {
    Some(kind) if syntax_kind_in(synchronization, kind) => true
    _ =>
      match self.tokens.token_at(self.raw_index) {
        Some(token) => syntax_kind_in(synchronization, token.kind())
        None => true
      }
  }
}

///|
fn Parser::clear_failure_commit(self : Parser) -> Unit {
  if self.failure_committed {
    match self.rule_frames.last() {
      Some(frame) => {
        let index = self.rule_frames.length() - 1
        self.rule_frames[index] = { ..frame, committed: true }
        self.cut_epoch = self.cut_epoch + 1
      }
      None => ()
    }
  }
  self.failure_committed = false
  match self.failure {
    Some(failure) =>
      self.failure = Some(failure.with_committed(self.current_rule_committed()))
    None => ()
  }
}

///|
/// Preserves unexpected input in an `ErrorNode` and stops before a
/// synchronization token. It may return `false` without advancing when the
/// caller is already at a boundary; the surrounding grammar owns that token.
///
/// A `true` result always means the raw token cursor increased.
fn Parser::recover_until(
  self : Parser,
  synchronization : ArrayView[@syntax.SyntaxKind],
) -> Bool {
  self.clear_failure_commit()
  let start = self.raw_index
  guard self.current_kind() is Some(kind) && kind != Eof else { return false }
  guard !self.at_recovery_boundary(synchronization) else { return false }
  self.start_node(ErrorNode)
  while !self.at(Eof) && !self.at_recovery_boundary(synchronization) {
    ignore(self.bump_raw())
  }
  self.finish_node()
  guard self.raw_index > start
  true
}

///|
/// Recovery for a caller that cannot hand a synchronization token to an
/// enclosing loop. It consumes at least one raw token before stopping at the
/// next boundary.
fn Parser::recover_with_progress_until(
  self : Parser,
  synchronization : ArrayView[@syntax.SyntaxKind],
) -> Bool {
  self.clear_failure_commit()
  let start = self.raw_index
  guard self.current_kind() is Some(kind) && kind != Eof else { return false }
  self.start_node(ErrorNode)
  match self.tokens.token_at(self.raw_index) {
    Some(token) if token.is_trivia() &&
      syntax_kind_in(synchronization, token.kind()) => ignore(self.bump_raw())
    _ => ignore(self.bump())
  }
  while !self.at(Eof) && !self.at_recovery_boundary(synchronization) {
    ignore(self.bump_raw())
  }
  self.finish_node()
  guard self.raw_index > start
  true
}
