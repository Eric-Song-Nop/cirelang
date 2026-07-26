///|
/// A parser event stream. Every source token, including trivia and invalid
/// tokens, must appear exactly once and in source order.
pub(all) enum TreeEvent {
  Start(SyntaxKind)
  Token(Token)
  Missing(SyntaxKind)
  Finish
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror TreeBuildError {
  InvalidNodeKind(SyntaxKind)
  InvalidTokenKind(SyntaxKind)
  TokenOutOfOrder(expected~ : @source.TextOffset, actual~ : @source.TextRange)
  EventOutsideNode
  FinishWithoutStart
  MultipleRoots
  EmptyTree
  UnclosedNodes(Int)
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A lossless green-tree sink suitable for a handwritten PEG parser.
pub struct GreenBuilder {
  priv stack_kinds : Array[SyntaxKind]
  priv stack_children : Array[Array[GreenElement]]
  priv mut root : GreenNode?
  priv mut cursor : @source.TextOffset
}

///|
pub fn GreenBuilder::new() -> GreenBuilder {
  GreenBuilder::new_at(@source.TextOffset::zero())
}

///|
/// Creates a builder for a whole file or a fragment beginning at `start`.
pub fn GreenBuilder::new_at(start : @source.TextOffset) -> GreenBuilder {
  { stack_kinds: [], stack_children: [], root: None, cursor: start }
}

///|
pub fn GreenBuilder::cursor(self : GreenBuilder) -> @source.TextOffset {
  self.cursor
}

///|
pub fn GreenBuilder::start_node(
  self : GreenBuilder,
  kind : SyntaxKind,
) -> Unit raise TreeBuildError {
  if !kind.is_node() {
    raise InvalidNodeKind(kind)
  }
  if self.stack_kinds.is_empty() && self.root is Some(_) {
    raise MultipleRoots
  }
  self.stack_kinds.push(kind)
  self.stack_children.push([])
}

///|
pub fn GreenBuilder::token(
  self : GreenBuilder,
  token : Token,
) -> Unit raise TreeBuildError {
  if !token.kind().is_token() {
    raise InvalidTokenKind(token.kind())
  }
  guard self.stack_children.last() is Some(children) else {
    raise EventOutsideNode
  }
  if token.range().start() != self.cursor {
    raise TokenOutOfOrder(expected=self.cursor, actual=token.range())
  }
  children.push(Token(GreenToken::from_token(token)))
  self.cursor = token.range().end()
}

///|
pub fn GreenBuilder::missing(
  self : GreenBuilder,
  kind : SyntaxKind,
) -> Unit raise TreeBuildError {
  if !kind.is_token() || kind == Eof {
    raise InvalidTokenKind(kind)
  }
  guard self.stack_children.last() is Some(children) else {
    raise EventOutsideNode
  }
  children.push(Token(GreenToken::missing(kind)))
}

///|
pub fn GreenBuilder::finish_node(
  self : GreenBuilder,
) -> Unit raise TreeBuildError {
  guard self.stack_kinds.pop() is Some(kind) else { raise FinishWithoutStart }
  guard self.stack_children.pop() is Some(children) else {
    raise FinishWithoutStart
  }
  let node = GreenNode::new(kind, children)
  match self.stack_children.last() {
    Some(parent_children) => parent_children.push(Node(node))
    None =>
      if self.root is Some(_) {
        raise MultipleRoots
      } else {
        self.root = Some(node)
      }
  }
}

///|
pub fn GreenBuilder::push_event(
  self : GreenBuilder,
  event : TreeEvent,
) -> Unit raise TreeBuildError {
  match event {
    Start(kind) => self.start_node(kind)
    Token(token) => self.token(token)
    Missing(kind) => self.missing(kind)
    Finish => self.finish_node()
  }
}

///|
pub fn GreenBuilder::finish(
  self : GreenBuilder,
) -> GreenNode raise TreeBuildError {
  if !self.stack_kinds.is_empty() {
    raise UnclosedNodes(self.stack_kinds.length())
  }
  match self.root {
    Some(root) => root
    None => raise EmptyTree
  }
}

///|
pub fn build_green(
  events : ArrayView[TreeEvent],
) -> GreenNode raise TreeBuildError {
  build_green_at(events, @source.TextOffset::zero())
}

///|
pub fn build_green_at(
  events : ArrayView[TreeEvent],
  start : @source.TextOffset,
) -> GreenNode raise TreeBuildError {
  let builder = GreenBuilder::new_at(start)
  for event in events {
    builder.push_event(event)
  }
  builder.finish()
}
