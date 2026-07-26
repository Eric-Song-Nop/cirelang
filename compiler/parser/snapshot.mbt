///|
/// Immutable parser output pinned to one source revision.
///
/// The syntax tree is lossless even when parsing reports errors. Diagnostics
/// are ordered deterministically: lexer diagnostics first, followed by parser
/// diagnostics in source traversal order.
pub struct ParseSnapshot {
  priv source : @source.SourceId
  priv revision : @source.SourceRevision
  priv tree : @syntax.SyntaxTree
  priv diagnostics : Array[@diagnostic.Diagnostic]
  priv failure : FailureSummary?
} derive(Debug, Eq, ToJson)

///|
struct ParseSnapshotRaw {
  source : @source.SourceId
  revision : @source.SourceRevision
  tree : @syntax.SyntaxTree
  diagnostics : Array[@diagnostic.Diagnostic]
  failure : FailureSummary?
} derive(FromJson)

///|
pub impl @json.FromJson for ParseSnapshot with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ParseSnapshot raise @json.JsonDecodeError {
  let raw : ParseSnapshotRaw = @json.from_json(json, path~)
  if !parse_snapshot_shape_is_valid(
      raw.source,
      raw.revision,
      raw.tree,
      raw.diagnostics,
      raw.failure,
    ) {
    parser_json_decode_error(
      path, "ParseSnapshot: source, tree, diagnostics, or failure disagree",
    )
  } else {
    {
      source: raw.source,
      revision: raw.revision,
      tree: raw.tree,
      diagnostics: raw.diagnostics.copy(),
      failure: raw.failure,
    }
  }
}

///|
fn ParseSnapshot::new(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  tree : @syntax.SyntaxTree,
  diagnostics : Array[@diagnostic.Diagnostic],
  failure : FailureSummary?,
) -> ParseSnapshot {
  guard parse_snapshot_shape_is_valid(
    source, revision, tree, diagnostics, failure,
  )
  { source, revision, tree, diagnostics: diagnostics.copy(), failure }
}

///|
fn parse_snapshot_shape_is_valid(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  tree : @syntax.SyntaxTree,
  diagnostics : Array[@diagnostic.Diagnostic],
  failure : FailureSummary?,
) -> Bool {
  if tree.source() != source ||
    tree.revision() != revision ||
    tree.root().kind() != SourceFile {
    return false
  }
  let source_length = tree.source_text().length()
  for diagnostic in diagnostics {
    if diagnostic.revision() != revision ||
      (diagnostic.stage() != Lex && diagnostic.stage() != Parse) {
      return false
    }
    let labels = diagnostic.labels()
    if labels.is_empty() {
      return false
    }
    for label in labels {
      if label.span().source() != source ||
        label.span().range().end().value() > source_length {
        return false
      }
    }
    for fix in diagnostic.fixes() {
      for edit in fix.edits() {
        if edit.source() != source ||
          edit.expected_revision() != revision ||
          edit.delete().end().value() > source_length {
          return false
        }
      }
    }
  }
  match failure {
    Some(item) => failure_matches_tree(item, tree, source_length)
    None => true
  }
}

///|
fn failure_matches_tree(
  failure : FailureSummary,
  tree : @syntax.SyntaxTree,
  source_length : Int,
) -> Bool {
  let token_ranges : Array[@source.TextRange] = []
  collect_concrete_token_ranges(tree.root(), token_ranges)
  let index = failure.token_index()
  if index < token_ranges.length() {
    failure.offset() == token_ranges[index].start()
  } else {
    index == token_ranges.length() && failure.offset().value() == source_length
  }
}

///|
fn collect_concrete_token_ranges(
  node : @syntax.SyntaxNode,
  ranges : Array[@source.TextRange],
) -> Unit {
  for child in node.children() {
    match child {
      Token(token) => if !token.is_missing() { ranges.push(token.range()) }
      Node(child_node) => collect_concrete_token_ranges(child_node, ranges)
    }
  }
}

///|
pub fn ParseSnapshot::source(self : ParseSnapshot) -> @source.SourceId {
  self.source
}

///|
pub fn ParseSnapshot::revision(self : ParseSnapshot) -> @source.SourceRevision {
  self.revision
}

///|
pub fn ParseSnapshot::tree(self : ParseSnapshot) -> @syntax.SyntaxTree {
  self.tree
}

///|
pub fn ParseSnapshot::diagnostics(
  self : ParseSnapshot,
) -> Array[@diagnostic.Diagnostic] {
  self.diagnostics.copy()
}

///|
pub fn ParseSnapshot::failure(self : ParseSnapshot) -> FailureSummary? {
  self.failure
}

///|
pub fn ParseSnapshot::source_text(self : ParseSnapshot) -> String {
  self.tree.source_text()
}

///|
pub fn ParseSnapshot::to_sexpr(self : ParseSnapshot) -> String {
  self.tree.to_sexpr()
}
