///|
/// A syntax node identity scoped to one `SyntaxTree` snapshot.
///
/// IDs use deterministic pre-order within a snapshot. They are not stable
/// declaration identities and may change after an edit.
pub struct SyntaxNodeId(Int) derive(Debug, Eq)

///|
pub fn SyntaxNodeId::root() -> SyntaxNodeId {
  SyntaxNodeId(0)
}

///|
pub fn SyntaxNodeId::value(self : SyntaxNodeId) -> Int {
  self.0
}

///|
pub impl ToJson for SyntaxNodeId with fn to_json(self : SyntaxNodeId) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for SyntaxNodeId with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SyntaxNodeId raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    syntax_json_decode_error(
      path, "SyntaxNodeId: expected a non-negative integer",
    )
  } else {
    SyntaxNodeId(value)
  }
}

///|
/// A position-bearing view of a parent-free green token.
pub struct SyntaxToken {
  priv green : GreenToken
  priv range : @source.TextRange
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn SyntaxToken::kind(self : SyntaxToken) -> SyntaxKind {
  self.green.kind()
}

///|
pub fn SyntaxToken::text(self : SyntaxToken) -> String {
  self.green.text()
}

///|
pub fn SyntaxToken::is_missing(self : SyntaxToken) -> Bool {
  self.green.is_missing()
}

///|
pub fn SyntaxToken::range(self : SyntaxToken) -> @source.TextRange {
  self.range
}

///|
/// A position-bearing, parent-free view of a green node.
pub struct SyntaxNode {
  priv id : SyntaxNodeId
  priv green : GreenNode
  priv offset : @source.TextOffset
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SyntaxElement {
  Token(SyntaxToken)
  Node(SyntaxNode)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn SyntaxNode::id(self : SyntaxNode) -> SyntaxNodeId {
  self.id
}

///|
pub fn SyntaxNode::kind(self : SyntaxNode) -> SyntaxKind {
  self.green.kind()
}

///|
pub fn SyntaxNode::green(self : SyntaxNode) -> GreenNode {
  self.green
}

///|
pub fn SyntaxNode::range(self : SyntaxNode) -> @source.TextRange {
  @source.TextRange::new(
    self.offset,
    self.offset.advance(self.green.text_length()),
  )
}

///|
pub fn SyntaxElement::range(self : SyntaxElement) -> @source.TextRange {
  match self {
    Token(token) => token.range()
    Node(node) => node.range()
  }
}

///|
pub fn SyntaxElement::kind(self : SyntaxElement) -> SyntaxKind {
  match self {
    Token(token) => token.kind()
    Node(node) => node.kind()
  }
}

///|
fn GreenNode::node_count(self : GreenNode) -> Int {
  self
  .children()
  .fold(init=1, (count, child) => {
    match child {
      Token(_) => count
      Node(node) => count + node.node_count()
    }
  })
}

///|
/// Returns child views with exact half-open UTF-16 ranges.
pub fn SyntaxNode::children(self : SyntaxNode) -> Array[SyntaxElement] {
  let result : Array[SyntaxElement] = []
  let mut offset = self.offset
  let mut next_node_id = self.id.value() + 1
  for child in self.green.children() {
    match child {
      Token(token) => {
        let end = offset.advance(token.text_length())
        result.push(
          Token({ green: token, range: @source.TextRange::new(offset, end) }),
        )
        offset = end
      }
      Node(node) => {
        result.push(
          Node({ id: SyntaxNodeId(next_node_id), green: node, offset }),
        )
        offset = offset.advance(node.text_length())
        next_node_id = next_node_id + node.node_count()
      }
    }
  }
  result
}

///|
/// A serializable concrete-syntax snapshot pinned to one source revision.
pub struct SyntaxTree {
  priv source : @source.SourceId
  priv revision : @source.SourceRevision
  priv root : GreenNode
} derive(Debug, Eq, ToJson)

///|
struct SyntaxTreeRaw {
  source : @source.SourceId
  revision : @source.SourceRevision
  root : GreenNode
} derive(FromJson)

///|
pub impl @json.FromJson for SyntaxTree with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SyntaxTree raise @json.JsonDecodeError {
  let raw : SyntaxTreeRaw = @json.from_json(json, path~)
  if raw.root.kind() != SourceFile {
    syntax_json_decode_error(
      path.add_key("root"),
      "SyntaxTree: root must be a source_file node",
    )
  } else {
    { source: raw.source, revision: raw.revision, root: raw.root }
  }
}

///|
pub fn SyntaxTree::new(
  source : @source.SourceId,
  revision : @source.SourceRevision,
  root : GreenNode,
) -> SyntaxTree {
  guard root.kind() == SourceFile
  { source, revision, root }
}

///|
pub fn SyntaxTree::source(self : SyntaxTree) -> @source.SourceId {
  self.source
}

///|
pub fn SyntaxTree::revision(self : SyntaxTree) -> @source.SourceRevision {
  self.revision
}

///|
pub fn SyntaxTree::green(self : SyntaxTree) -> GreenNode {
  self.root
}

///|
pub fn SyntaxTree::root(self : SyntaxTree) -> SyntaxNode {
  {
    id: SyntaxNodeId::root(),
    green: self.root,
    offset: @source.TextOffset::zero(),
  }
}

///|
pub fn SyntaxTree::source_text(self : SyntaxTree) -> String {
  self.root.source_text()
}

///|
pub fn SyntaxTree::to_sexpr(self : SyntaxTree) -> String {
  self.root.to_sexpr()
}
