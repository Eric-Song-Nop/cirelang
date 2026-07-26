///|
/// Injectable destination for deterministic compiler trace events.
///
/// Compiler stages depend on this trait instead of printing directly.
pub(open) trait TraceSink {
  fn emit(Self, CompilerEvent) -> Unit
}

///|
/// A trace sink for normal runs where tracing is disabled.
pub struct NoopTraceSink(Unit)

///|
pub fn NoopTraceSink::new() -> NoopTraceSink {
  NoopTraceSink(())
}

///|
pub impl TraceSink for NoopTraceSink with fn emit(
  _self : NoopTraceSink,
  _event : CompilerEvent,
) -> Unit {
  ()
}

///|
/// An append-only deterministic JSON Lines sink for tests and debug tooling.
///
/// Events are serialized immediately so the sink never retains a mutable
/// `Json` value supplied by a caller.
pub struct MemoryTraceSink {
  lines : Array[String]
}

///|
pub fn MemoryTraceSink::new() -> MemoryTraceSink {
  { lines: [] }
}

///|
pub impl TraceSink for MemoryTraceSink with fn emit(
  self : MemoryTraceSink,
  event : CompilerEvent,
) -> Unit {
  self.lines.push(event.to_json().stringify())
}

///|
pub fn MemoryTraceSink::length(self : MemoryTraceSink) -> Int {
  self.lines.length()
}

///|
pub fn MemoryTraceSink::is_empty(self : MemoryTraceSink) -> Bool {
  self.lines.is_empty()
}

///|
/// Returns a defensive copy in event sequence order.
pub fn MemoryTraceSink::lines(self : MemoryTraceSink) -> Array[String] {
  [..self.lines]
}
