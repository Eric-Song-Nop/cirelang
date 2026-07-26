///|
/// Maps UTF-16 offsets to zero-based line/character positions.
pub struct LineIndex {
  line_starts : Array[TextOffset]
  line_ends : Array[TextOffset]
  text_length : TextOffset
} derive(Debug, Eq, ToJson)

///|
pub fn LineIndex::new(text : String) -> LineIndex {
  let starts = [TextOffset::zero()]
  let ends : Array[TextOffset] = []
  let length = text.length()
  let mut cursor = 0
  while cursor < length {
    if text[cursor] == '\r' {
      ends.push(TextOffset::new(cursor))
      if cursor + 1 < length && text[cursor + 1] == '\n' {
        cursor = cursor + 2
      } else {
        cursor = cursor + 1
      }
      starts.push(TextOffset::new(cursor))
    } else if text[cursor] == '\n' {
      ends.push(TextOffset::new(cursor))
      cursor = cursor + 1
      starts.push(TextOffset::new(cursor))
    } else {
      cursor = cursor + 1
    }
  }
  ends.push(TextOffset::new(length))
  { line_starts: starts, line_ends: ends, text_length: TextOffset::new(length) }
}

///|
pub fn LineIndex::line_count(self : LineIndex) -> Int {
  self.line_starts.length()
}

///|
pub fn LineIndex::text_length(self : LineIndex) -> TextOffset {
  self.text_length
}

///|
pub fn LineIndex::line_start(self : LineIndex, line : Int) -> TextOffset? {
  self.line_starts.get(line)
}

///|
/// Returns the content end of a line, excluding its line terminator.
pub fn LineIndex::line_end(self : LineIndex, line : Int) -> TextOffset? {
  self.line_ends.get(line)
}

///|
pub fn LineIndex::position(
  self : LineIndex,
  offset : TextOffset,
) -> LineColumn? {
  if offset > self.text_length {
    return None
  }
  let target = offset.value()
  for low = 0, high = self.line_starts.length(); low + 1 < high; {
    let middle = low + (high - low) / 2
    if self.line_starts[middle].value() <= target {
      continue middle, high
    } else {
      continue low, middle
    }
  } nobreak {
    let start = self.line_starts[low].value()
    let end = self.line_ends[low].value()
    // Every offset within CR, LF, or CRLF maps to the preceding line end.
    let canonical = if target <= end { target } else { end }
    Some(LineColumn::new(low, canonical - start))
  }
}

///|
pub fn LineIndex::offset(
  self : LineIndex,
  position : LineColumn,
) -> TextOffset? {
  guard self.line_starts.get(position.line()) is Some(start) else {
    return None
  }
  let end = self.line_ends[position.line()]
  if position.character() > end.value() - start.value() {
    None
  } else {
    Some(start.advance(position.character()))
  }
}
