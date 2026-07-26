///|
/// Immutable lexer output pinned to one source revision.
///
/// Tokens and diagnostics are copied at the package boundary so an editor or
/// LSP request can safely retain an older snapshot while a newer revision is
/// being processed.
///
/// Its JSON codec is a validated, session-local debug snapshot and therefore
/// includes `SourceId`. Persistent artifacts must use an explicit artifact
/// payload inside `ArtifactEnvelope`, never this representation directly.
pub struct LexSnapshot {
  priv source : @source.SourceId
  priv revision : @source.SourceRevision
  priv tokens : @syntax.TokenSnapshot
  priv diagnostics : Array[@diagnostic.Diagnostic]
} derive(Debug, Eq, ToJson)

///|
struct LexSnapshotRaw {
  source : @source.SourceId
  revision : @source.SourceRevision
  tokens : @syntax.TokenSnapshot
  diagnostics : Array[@diagnostic.Diagnostic]
} derive(FromJson)

///|
pub impl @json.FromJson for LexSnapshot with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> LexSnapshot raise @json.JsonDecodeError {
  let raw : LexSnapshotRaw = @json.from_json(json, path~)
  if raw.tokens.source() != raw.source ||
    raw.tokens.revision() != raw.revision ||
    !lex_diagnostics_are_valid(
      raw.source,
      raw.revision,
      raw.tokens.source_text().length(),
      raw.diagnostics,
    ) {
    lexer_json_decode_error(
      path, "LexSnapshot: token and diagnostic metadata are inconsistent",
    )
  } else {
    {
      source: raw.source,
      revision: raw.revision,
      tokens: raw.tokens,
      diagnostics: raw.diagnostics.copy(),
    }
  }
}

///|
fn LexSnapshot::new(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  tokens : @syntax.TokenSnapshot,
  diagnostics : Array[@diagnostic.Diagnostic],
) -> LexSnapshot {
  guard tokens.source() == source &&
    tokens.revision() == revision &&
    lex_diagnostics_are_valid(
      source,
      revision,
      tokens.source_text().length(),
      diagnostics,
    )
  { source, revision, tokens, diagnostics: diagnostics.copy() }
}

///|
fn lex_diagnostics_are_valid(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  source_length : Int,
  diagnostics : Array[@diagnostic.Diagnostic],
) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.stage() != Lex ||
      diagnostic.revision() != revision ||
      diagnostic.message().is_empty() {
      return false
    }
    let labels = diagnostic.labels()
    if labels.is_empty() {
      return false
    }
    let mut has_primary = false
    for label in labels {
      if label.span().source() != source ||
        label.span().range().end().value() > source_length {
        return false
      }
      if label.style() == Primary {
        has_primary = true
      }
    }
    if !has_primary {
      return false
    }
    for note in diagnostic.notes() {
      if note.is_empty() {
        return false
      }
    }
    for fix in diagnostic.fixes() {
      if fix.title().is_empty() || fix.edits().is_empty() {
        return false
      }
      for edit in fix.edits() {
        if edit.source() != source ||
          edit.expected_revision() != revision ||
          edit.delete().end().value() > source_length {
          return false
        }
      }
    }
  }
  true
}

///|
fn[T] lexer_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
pub fn LexSnapshot::source(self : LexSnapshot) -> @source.SourceId {
  self.source
}

///|
pub fn LexSnapshot::revision(self : LexSnapshot) -> @source.SourceRevision {
  self.revision
}

///|
pub fn LexSnapshot::tokens(self : LexSnapshot) -> @syntax.TokenSnapshot {
  self.tokens
}

///|
pub fn LexSnapshot::diagnostics(
  self : LexSnapshot,
) -> Array[@diagnostic.Diagnostic] {
  self.diagnostics.copy()
}

///|
pub fn LexSnapshot::source_text(self : LexSnapshot) -> String {
  self.tokens.source_text()
}

///|
/// Incremental-lexer entry point shared by batch compilation and the future
/// LSP server.
///
/// The initial implementation intentionally performs a full re-lex. Keeping
/// the old snapshot and revision-checked edit in this API lets a later
/// implementation add safe restart points and token prefix/suffix reuse
/// without changing callers or the observable result.
pub(all) suberror RelexError {
  EditWrongSource(expected~ : @source.SourceId, actual~ : @source.SourceId)
  EditStaleRevision(
    expected~ : @source.SourceRevision,
    actual~ : @source.SourceRevision
  )
  EditInvalidRange(@source.TextRange)
  EditInvalidUnicodeBoundary(@source.TextRange)
  UpdatedSourceMismatch(
    expected~ : @source.SourceId,
    actual~ : @source.SourceId
  )
  UpdatedRevisionMismatch(
    expected~ : @source.SourceRevision,
    actual~ : @source.SourceRevision
  )
  UpdatedTextMismatch
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn relex(
  previous : LexSnapshot,
  source : @source.SourceSnapshot,
  edit : @source.TextEdit,
) -> LexSnapshot raise RelexError {
  if source.id() != previous.source() {
    raise UpdatedSourceMismatch(expected=previous.source(), actual=source.id())
  }
  let previous_source = @source.SourceSnapshot::new(
    previous.source(),
    previous.revision(),
    source.logical_path(),
    previous.source_text(),
  )
  let expected = previous_source.apply_edit(edit) catch {
    WrongSource(expected~, actual~) => raise EditWrongSource(expected~, actual~)
    StaleRevision(expected~, actual~) =>
      raise EditStaleRevision(expected~, actual~)
    InvalidRange(range) => raise EditInvalidRange(range)
    InvalidUnicodeBoundary(range) => raise EditInvalidUnicodeBoundary(range)
  }
  if source.revision() != expected.revision() {
    raise UpdatedRevisionMismatch(
      expected=expected.revision(),
      actual=source.revision(),
    )
  }
  if source.text() != expected.text() {
    raise UpdatedTextMismatch
  }
  lex(source)
}
