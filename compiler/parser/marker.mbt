///|
/// Parser-local events can point forward from an already completed left-hand
/// side to a node that is completed later. This lets postfix parsing wrap
/// `f`, then `f()`, then `f()(x)` without moving the event prefix or changing
/// the public `@syntax.TreeEvent` protocol.
priv enum PendingEvent {
  PendingStart(@syntax.SyntaxKind, Int?)
  PendingToken(@syntax.Token)
  PendingMissing(@syntax.SyntaxKind)
  PendingFinish
  PendingTombstone
} derive(Eq)

///|
priv struct EventRewrite {
  index : Int
  previous : PendingEvent
}

///|
priv struct Marker {
  index : Int
}

///|
priv struct CompletedMarker {
  index : Int
}

///|
fn Parser::start_marker(self : Parser) -> Marker {
  let index = self.pending_events.length()
  self.pending_events.push(PendingTombstone)
  self.marker_depth = self.marker_depth + 1
  { index, }
}

///|
fn Parser::complete_marker(
  self : Parser,
  marker : Marker,
  kind : @syntax.SyntaxKind,
) -> CompletedMarker {
  guard kind.is_node() &&
    marker.index >= 0 &&
    marker.index < self.pending_events.length() &&
    self.pending_events[marker.index] == PendingTombstone &&
    self.marker_depth > 0
  self.pending_events[marker.index] = PendingStart(kind, None)
  self.pending_events.push(PendingFinish)
  self.marker_depth = self.marker_depth - 1
  { index: marker.index }
}

///|
/// Starts a new marker after `completed` and links the old start forward to
/// it. Lowering follows the link and emits starts in reverse order, so the new
/// node becomes the completed node's parent.
fn Parser::precede(self : Parser, completed : CompletedMarker) -> Marker {
  guard completed.index >= 0 && completed.index < self.pending_events.length()
  guard self.pending_events[completed.index]
    is PendingStart(kind, old_forward_parent)
  let new_index = self.pending_events.length()
  self.event_rewrites.push({
    index: completed.index,
    previous: PendingStart(kind, old_forward_parent),
  })
  self.pending_events[completed.index] = PendingStart(
    kind,
    Some(new_index - completed.index),
  )
  self.pending_events.push(PendingTombstone)
  self.marker_depth = self.marker_depth + 1
  { index: new_index }
}

///|
fn lower_pending_events(
  pending : ArrayView[PendingEvent],
) -> Array[@syntax.TreeEvent] {
  let result : Array[@syntax.TreeEvent] = []
  let consumed = Array::make(pending.length(), false)
  for index = 0; index < pending.length(); index = index + 1 {
    if consumed[index] {
      continue
    }
    match pending[index] {
      PendingStart(_, _) => {
        let starts : Array[@syntax.SyntaxKind] = []
        let mut cursor = index
        for ;; {
          guard cursor >= 0 && cursor < pending.length() && !consumed[cursor]
          guard pending[cursor] is PendingStart(kind, forward_parent)
          consumed[cursor] = true
          starts.push(kind)
          match forward_parent {
            Some(distance) => {
              guard distance > 0
              cursor = cursor + distance
            }
            None => break
          }
        }
        for start_index = starts.length() - 1
            start_index >= 0
            start_index = start_index - 1 {
          result.push(Start(starts[start_index]))
        }
      }
      PendingToken(token) => result.push(Token(token))
      PendingMissing(kind) => result.push(Missing(kind))
      PendingFinish => result.push(Finish)
      PendingTombstone => {
        guard false
      }
    }
  }
  result
}
