///|
pub(all) suberror SourceEditError {
  WrongSource(expected~ : SourceId, actual~ : SourceId)
  StaleRevision(expected~ : SourceRevision, actual~ : SourceRevision)
  InvalidRange(TextRange)
  InvalidUnicodeBoundary(TextRange)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A revision-checked replacement edit.
pub struct TextEdit {
  source : SourceId
  expected_revision : SourceRevision
  delete : TextRange
  insert : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn TextEdit::new(
  source : SourceId,
  expected_revision : SourceRevision,
  delete : TextRange,
  insert : String,
) -> TextEdit {
  { source, expected_revision, delete, insert }
}

///|
pub fn TextEdit::source(self : TextEdit) -> SourceId {
  self.source
}

///|
pub fn TextEdit::expected_revision(self : TextEdit) -> SourceRevision {
  self.expected_revision
}

///|
pub fn TextEdit::delete(self : TextEdit) -> TextRange {
  self.delete
}

///|
pub fn TextEdit::insert(self : TextEdit) -> String {
  self.insert
}

///|
/// Immutable source text pinned to one revision.
///
/// The loader must validate UTF-8 before constructing this value.
pub struct SourceSnapshot {
  id : SourceId
  revision : SourceRevision
  logical_path : String
  text : String
  line_index : LineIndex
} derive(Debug, Eq, ToJson)

///|
pub fn SourceSnapshot::new(
  id : SourceId,
  revision : SourceRevision,
  logical_path : String,
  text : String,
) -> SourceSnapshot {
  { id, revision, logical_path, text, line_index: LineIndex::new(text) }
}

///|
pub fn SourceSnapshot::id(self : SourceSnapshot) -> SourceId {
  self.id
}

///|
pub fn SourceSnapshot::revision(self : SourceSnapshot) -> SourceRevision {
  self.revision
}

///|
pub fn SourceSnapshot::logical_path(self : SourceSnapshot) -> String {
  self.logical_path
}

///|
pub fn SourceSnapshot::text(self : SourceSnapshot) -> String {
  self.text
}

///|
pub fn SourceSnapshot::length(self : SourceSnapshot) -> TextOffset {
  self.line_index.text_length()
}

///|
pub fn SourceSnapshot::line_index(self : SourceSnapshot) -> LineIndex {
  self.line_index
}

///|
/// Converts a scalar-boundary source offset into an LSP-compatible position.
pub fn SourceSnapshot::position(
  self : SourceSnapshot,
  offset : TextOffset,
) -> LineColumn? {
  guard self.is_scalar_boundary(offset) else { return None }
  self.line_index.position(offset)
}

///|
/// Converts an LSP-compatible position into a scalar-boundary source offset.
pub fn SourceSnapshot::offset(
  self : SourceSnapshot,
  position : LineColumn,
) -> TextOffset? {
  guard self.line_index.offset(position) is Some(offset) &&
    self.is_scalar_boundary(offset) else {
    return None
  }
  Some(offset)
}

///|
pub fn SourceSnapshot::is_scalar_boundary(
  self : SourceSnapshot,
  offset : TextOffset,
) -> Bool {
  let value = offset.value()
  value == self.text.length() || self.text.get_char(value) is Some(_)
}

///|
pub fn SourceSnapshot::slice(
  self : SourceSnapshot,
  range : TextRange,
) -> String? {
  if range.end().value() > self.text.length() ||
    !self.is_scalar_boundary(range.start()) ||
    !self.is_scalar_boundary(range.end()) {
    return None
  }
  self.text
  .get_view(start=range.start().value(), end=range.end().value())
  .map(view => view.to_owned())
}

///|
pub fn SourceSnapshot::apply_edit(
  self : SourceSnapshot,
  edit : TextEdit,
) -> SourceSnapshot raise SourceEditError {
  if edit.source() != self.id {
    raise WrongSource(expected=self.id, actual=edit.source())
  }
  if edit.expected_revision() != self.revision {
    raise StaleRevision(expected=self.revision, actual=edit.expected_revision())
  }
  let delete = edit.delete()
  if delete.end().value() > self.text.length() {
    raise InvalidRange(delete)
  }
  if !self.is_scalar_boundary(delete.start()) ||
    !self.is_scalar_boundary(delete.end()) {
    raise InvalidUnicodeBoundary(delete)
  }
  let prefix = self.text
    .get_view(start=0, end=delete.start().value())
    .unwrap()
    .to_owned()
  let suffix = self.text
    .get_view(start=delete.end().value(), end=self.text.length())
    .unwrap()
    .to_owned()
  SourceSnapshot::new(
    self.id,
    self.revision.next(),
    self.logical_path,
    prefix + edit.insert() + suffix,
  )
}
