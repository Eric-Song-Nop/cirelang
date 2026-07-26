///|
/// Identifies a source file within one compiler workspace session.
///
/// A `SourceId` is not stable across compiler processes. Persistent artifacts
/// must serialize the logical source path alongside it.
pub struct SourceId(Int) derive(Debug, Eq)

///|
pub fn SourceId::new(value : Int) -> SourceId {
  guard value >= 0
  SourceId(value)
}

///|
pub fn SourceId::value(self : SourceId) -> Int {
  self.0
}

///|
pub impl ToJson for SourceId with fn to_json(self : SourceId) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for SourceId with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SourceId raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    source_json_decode_error(path, "SourceId: expected a non-negative integer")
  } else {
    SourceId(value)
  }
}

///|
/// Identifies an immutable workspace/source snapshot.
pub struct Revision(Int) derive(Debug, Eq)

///|
pub fn Revision::new(value : Int) -> Revision {
  guard value >= 0
  Revision(value)
}

///|
pub fn Revision::initial() -> Revision {
  Revision(0)
}

///|
pub fn Revision::value(self : Revision) -> Int {
  self.0
}

///|
pub fn Revision::next(self : Revision) -> Revision {
  Revision(self.0 + 1)
}

///|
pub impl ToJson for Revision with fn to_json(self : Revision) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for Revision with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Revision raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    source_json_decode_error(path, "Revision: expected a non-negative integer")
  } else {
    Revision(value)
  }
}

///|
fn[T] source_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}
