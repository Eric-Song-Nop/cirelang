///|
/// An offset measured in UTF-16 code units.
///
/// This is the canonical coordinate used by the compiler, CST, diagnostics,
/// edits, and the default LSP adapter.
pub struct TextOffset(Int) derive(Debug, Eq, Compare)

///|
pub fn TextOffset::new(value : Int) -> TextOffset {
  guard value >= 0
  TextOffset(value)
}

///|
pub fn TextOffset::zero() -> TextOffset {
  TextOffset(0)
}

///|
pub fn TextOffset::value(self : TextOffset) -> Int {
  self.0
}

///|
pub fn TextOffset::advance(self : TextOffset, code_units : Int) -> TextOffset {
  guard code_units >= 0
  TextOffset(self.0 + code_units)
}

///|
pub impl ToJson for TextOffset with fn to_json(self : TextOffset) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for TextOffset with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TextOffset raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    source_json_decode_error(
      path, "TextOffset: expected a non-negative integer",
    )
  } else {
    TextOffset(value)
  }
}

///|
/// A half-open UTF-16 code-unit range `[start, end)`.
pub struct TextRange {
  start : TextOffset
  end : TextOffset
} derive(Debug, Eq, ToJson)

///|
struct TextRangeJson {
  start : TextOffset
  end : TextOffset
} derive(FromJson)

///|
pub impl @json.FromJson for TextRange with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TextRange raise @json.JsonDecodeError {
  let decoded : TextRangeJson = @json.from_json(json, path~)
  if decoded.start > decoded.end {
    source_json_decode_error(path, "TextRange: start must not exceed end")
  } else {
    { start: decoded.start, end: decoded.end }
  }
}

///|
pub fn TextRange::new(start : TextOffset, end : TextOffset) -> TextRange {
  guard start.value() <= end.value()
  { start, end }
}

///|
pub fn TextRange::empty(at : TextOffset) -> TextRange {
  { start: at, end: at }
}

///|
pub fn TextRange::start(self : TextRange) -> TextOffset {
  self.start
}

///|
pub fn TextRange::end(self : TextRange) -> TextOffset {
  self.end
}

///|
pub fn TextRange::length(self : TextRange) -> Int {
  self.end.value() - self.start.value()
}

///|
pub fn TextRange::is_empty(self : TextRange) -> Bool {
  self.start == self.end
}

///|
pub fn TextRange::contains(self : TextRange, offset : TextOffset) -> Bool {
  self.start <= offset && offset < self.end
}

///|
pub fn TextRange::contains_inclusive(
  self : TextRange,
  offset : TextOffset,
) -> Bool {
  self.start <= offset && offset <= self.end
}

///|
pub fn TextRange::contains_range(self : TextRange, other : TextRange) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
pub fn TextRange::intersects(self : TextRange, other : TextRange) -> Bool {
  self.start < other.end && other.start < self.end
}

///|
pub fn TextRange::cover(self : TextRange, other : TextRange) -> TextRange {
  {
    start: if self.start <= other.start {
      self.start
    } else {
      other.start
    },
    end: if self.end >= other.end {
      self.end
    } else {
      other.end
    },
  }
}

///|
/// A source-aware range. It never stores line/column information.
pub struct Span {
  source : SourceId
  range : TextRange
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn Span::new(source : SourceId, range : TextRange) -> Span {
  { source, range }
}

///|
pub fn Span::source(self : Span) -> SourceId {
  self.source
}

///|
pub fn Span::range(self : Span) -> TextRange {
  self.range
}

///|
/// An LSP-compatible zero-based UTF-16 position.
pub struct LineColumn {
  line : Int
  character : Int
} derive(Debug, Eq, ToJson)

///|
struct LineColumnJson {
  line : Int
  character : Int
} derive(FromJson)

///|
pub impl @json.FromJson for LineColumn with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> LineColumn raise @json.JsonDecodeError {
  let decoded : LineColumnJson = @json.from_json(json, path~)
  if decoded.line < 0 || decoded.character < 0 {
    source_json_decode_error(
      path,
      "LineColumn: line and character must be non-negative",
    )
  } else {
    { line: decoded.line, character: decoded.character }
  }
}

///|
pub fn LineColumn::new(line : Int, character : Int) -> LineColumn {
  guard line >= 0 && character >= 0
  { line, character }
}

///|
pub fn LineColumn::line(self : LineColumn) -> Int {
  self.line
}

///|
pub fn LineColumn::character(self : LineColumn) -> Int {
  self.character
}
