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
/// Identifies an immutable revision of one source file.
///
/// This is deliberately distinct from the revision of a whole compiler
/// workspace snapshot.
pub struct SourceRevision(Int) derive(Debug, Eq)

///|
pub fn SourceRevision::new(value : Int) -> SourceRevision {
  guard value >= 0
  SourceRevision(value)
}

///|
pub fn SourceRevision::initial() -> SourceRevision {
  SourceRevision(0)
}

///|
pub fn SourceRevision::value(self : SourceRevision) -> Int {
  self.0
}

///|
pub fn SourceRevision::next(self : SourceRevision) -> SourceRevision {
  guard self.0 < @int.MAX_VALUE
  SourceRevision(self.0 + 1)
}

///|
pub impl ToJson for SourceRevision with fn to_json(self : SourceRevision) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for SourceRevision with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SourceRevision raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    source_json_decode_error(
      path, "SourceRevision: expected a non-negative integer",
    )
  } else {
    SourceRevision(value)
  }
}

///|
/// Identifies one immutable view of the complete compiler workspace.
///
/// A workspace revision may advance when any source, package graph, overlay,
/// or compiler option changes. It must not be substituted for a file's
/// `SourceRevision`.
pub struct WorkspaceRevision(Int) derive(Debug, Eq)

///|
pub fn WorkspaceRevision::new(value : Int) -> WorkspaceRevision {
  guard value >= 0
  WorkspaceRevision(value)
}

///|
pub fn WorkspaceRevision::initial() -> WorkspaceRevision {
  WorkspaceRevision(0)
}

///|
pub fn WorkspaceRevision::value(self : WorkspaceRevision) -> Int {
  self.0
}

///|
pub fn WorkspaceRevision::next(self : WorkspaceRevision) -> WorkspaceRevision {
  guard self.0 < @int.MAX_VALUE
  WorkspaceRevision(self.0 + 1)
}

///|
pub impl ToJson for WorkspaceRevision with fn to_json(self : WorkspaceRevision) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for WorkspaceRevision with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> WorkspaceRevision raise @json.JsonDecodeError {
  let value : Int = @json.from_json(json, path~)
  if value < 0 {
    source_json_decode_error(
      path, "WorkspaceRevision: expected a non-negative integer",
    )
  } else {
    WorkspaceRevision(value)
  }
}

///|
fn[T] source_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}
