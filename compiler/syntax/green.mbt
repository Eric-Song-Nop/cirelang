///|
/// A position-independent token stored in a green tree.
///
/// Missing tokens have empty text and do not shift later UTF-16 ranges.
pub struct GreenToken {
  priv kind : SyntaxKind
  priv text : String
  priv missing : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn GreenToken::from_token(token : Token) -> GreenToken {
  { kind: token.kind(), text: token.text(), missing: false }
}

///|
pub fn GreenToken::missing(kind : SyntaxKind) -> GreenToken {
  guard kind.is_token() && kind != Eof
  { kind, text: "", missing: true }
}

///|
pub fn GreenToken::kind(self : GreenToken) -> SyntaxKind {
  self.kind
}

///|
pub fn GreenToken::text(self : GreenToken) -> String {
  self.text
}

///|
pub fn GreenToken::is_missing(self : GreenToken) -> Bool {
  self.missing
}

///|
pub fn GreenToken::text_length(self : GreenToken) -> Int {
  self.text.length()
}

///|
pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// An immutable, parent-free concrete syntax node.
///
/// Child arrays are copied on construction and access. Absolute positions are
/// supplied by `SyntaxNode` views, allowing a green subtree to be reused after
/// text before it moves.
pub struct GreenNode {
  priv kind : SyntaxKind
  priv children : Array[GreenElement]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn GreenNode::new(
  kind : SyntaxKind,
  children : Array[GreenElement],
) -> GreenNode {
  guard kind.is_node()
  { kind, children: children.copy() }
}

///|
pub fn GreenNode::kind(self : GreenNode) -> SyntaxKind {
  self.kind
}

///|
pub fn GreenNode::child_count(self : GreenNode) -> Int {
  self.children.length()
}

///|
pub fn GreenNode::child(self : GreenNode, index : Int) -> GreenElement? {
  self.children.get(index)
}

///|
/// Returns a defensive copy so green nodes remain immutable to consumers.
pub fn GreenNode::children(self : GreenNode) -> Array[GreenElement] {
  self.children.copy()
}

///|
pub fn GreenToken::to_sexpr(self : GreenToken) -> String {
  let output = StringBuilder()
  write_green_token_sexpr(self, output)
  output.to_string()
}

///|
pub fn GreenElement::text_length(self : GreenElement) -> Int {
  match self {
    Token(token) => token.text_length()
    Node(node) => node.text_length()
  }
}

///|
pub fn GreenNode::text_length(self : GreenNode) -> Int {
  self.children.fold(init=0, (length, child) => length + child.text_length())
}

///|
pub fn GreenNode::source_text(self : GreenNode) -> String {
  let output = StringBuilder()
  write_green_source(self, output)
  output.to_string()
}

///|
/// Renders a compact deterministic snapshot independent of derived `Debug`
/// formatting. Token text uses JSON string escaping.
pub fn GreenNode::to_sexpr(self : GreenNode) -> String {
  let output = StringBuilder()
  write_green_node_sexpr(self, output)
  output.to_string()
}

///|
fn write_green_source(node : GreenNode, output : StringBuilder) -> Unit {
  for child in node.children {
    match child {
      Token(token) => output.write_string(token.text())
      Node(child_node) => write_green_source(child_node, output)
    }
  }
}

///|
fn write_green_token_sexpr(token : GreenToken, output : StringBuilder) -> Unit {
  output.write_char('(')
  if token.is_missing() {
    output.write_string("missing ")
    output.write_string(token.kind().wire_name())
  } else {
    output.write_string(token.kind().wire_name())
    output.write_char(' ')
    output.write_string(token.text().to_json().stringify())
  }
  output.write_char(')')
}

///|
fn write_green_node_sexpr(node : GreenNode, output : StringBuilder) -> Unit {
  output.write_char('(')
  output.write_string(node.kind().wire_name())
  for child in node.children {
    output.write_char(' ')
    match child {
      Token(token) => write_green_token_sexpr(token, output)
      Node(child_node) => write_green_node_sexpr(child_node, output)
    }
  }
  output.write_char(')')
}
