///|
/// Stable artifact offsets are always UTF-16 code units.
pub const OFFSET_ENCODING : String = "utf-16"

///|
/// Stable identity for the primary input of an artifact.
///
/// `file` is a normalized workspace-relative logical path. Unlike
/// `@source.SourceId`, it is meaningful across compiler processes.
pub struct ArtifactSource {
  file : String
  revision : @source.SourceRevision
  content_hash : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactSource::new(
  file : String,
  revision : @source.SourceRevision,
  content_hash : String,
) -> ArtifactSource {
  guard !file.is_empty() && !content_hash.is_empty()
  { file, revision, content_hash }
}

///|
pub fn ArtifactSource::file(self : ArtifactSource) -> String {
  self.file
}

///|
pub fn ArtifactSource::revision(
  self : ArtifactSource,
) -> @source.SourceRevision {
  self.revision
}

///|
pub fn ArtifactSource::content_hash(self : ArtifactSource) -> String {
  self.content_hash
}

///|
/// A stable, cross-process source span.
///
/// This type embeds the full stable source identity: labels may refer to files
/// other than the envelope's primary source, and a process-local revision is
/// not sufficient to identify their contents after a compiler restart.
pub struct ArtifactSpan {
  source : ArtifactSource
  range : @source.TextRange
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactSpan::new(
  source : ArtifactSource,
  range : @source.TextRange,
) -> ArtifactSpan {
  guard artifact_source_is_valid(source)
  { source, range }
}

///|
pub fn ArtifactSpan::source(self : ArtifactSpan) -> ArtifactSource {
  self.source
}

///|
pub fn ArtifactSpan::range(self : ArtifactSpan) -> @source.TextRange {
  self.range
}

///|
/// A stable edit. `range` is the half-open UTF-16 range to replace.
pub struct ArtifactEdit {
  source : ArtifactSource
  range : @source.TextRange
  insert : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactEdit::new(
  source : ArtifactSource,
  range : @source.TextRange,
  insert : String,
) -> ArtifactEdit {
  guard artifact_source_is_valid(source)
  { source, range, insert }
}

///|
pub fn ArtifactEdit::source(self : ArtifactEdit) -> ArtifactSource {
  self.source
}

///|
pub fn ArtifactEdit::range(self : ArtifactEdit) -> @source.TextRange {
  self.range
}

///|
pub fn ArtifactEdit::insert(self : ArtifactEdit) -> String {
  self.insert
}

///|
pub struct ArtifactLabel {
  span : ArtifactSpan
  style : LabelStyle
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactLabel::primary(
  span : ArtifactSpan,
  message : String,
) -> ArtifactLabel {
  guard artifact_span_is_valid(span)
  { span, style: Primary, message }
}

///|
pub fn ArtifactLabel::secondary(
  span : ArtifactSpan,
  message : String,
) -> ArtifactLabel {
  guard artifact_span_is_valid(span)
  { span, style: Secondary, message }
}

///|
pub fn ArtifactLabel::span(self : ArtifactLabel) -> ArtifactSpan {
  self.span
}

///|
pub fn ArtifactLabel::style(self : ArtifactLabel) -> LabelStyle {
  self.style
}

///|
pub fn ArtifactLabel::message(self : ArtifactLabel) -> String {
  self.message
}

///|
pub struct ArtifactFix {
  title : String
  applicability : Applicability
  edits : Array[ArtifactEdit]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactFix::new(
  title : String,
  applicability : Applicability,
  edits : Array[ArtifactEdit],
) -> ArtifactFix {
  guard !title.is_empty() &&
    !edits.is_empty() &&
    artifact_edits_are_valid(edits)
  { title, applicability, edits: [..edits] }
}

///|
pub fn ArtifactFix::title(self : ArtifactFix) -> String {
  self.title
}

///|
pub fn ArtifactFix::applicability(self : ArtifactFix) -> Applicability {
  self.applicability
}

///|
pub fn ArtifactFix::edits(self : ArtifactFix) -> Array[ArtifactEdit] {
  [..self.edits]
}

///|
pub struct ArtifactDiagnostic {
  code : DiagnosticCode
  stage : Stage
  severity : Severity
  message : String
  labels : Array[ArtifactLabel]
  notes : Array[String]
  fixes : Array[ArtifactFix]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn ArtifactDiagnostic::new(
  code : DiagnosticCode,
  stage : Stage,
  severity : Severity,
  message : String,
  labels : Array[ArtifactLabel],
  notes : Array[String],
  fixes : Array[ArtifactFix],
) -> ArtifactDiagnostic {
  guard !message.is_empty() &&
    !labels.is_empty() &&
    artifact_labels_have_primary(labels) &&
    artifact_labels_are_valid(labels) &&
    artifact_notes_are_valid(notes) &&
    artifact_fixes_are_valid(fixes)
  {
    code,
    stage,
    severity,
    message,
    labels: [..labels],
    notes: [..notes],
    fixes: [..fixes],
  }
}

///|
fn artifact_labels_have_primary(labels : Array[ArtifactLabel]) -> Bool {
  for label in labels {
    if label.style() == Primary {
      return true
    }
  }
  false
}

///|
pub fn ArtifactDiagnostic::code(self : ArtifactDiagnostic) -> DiagnosticCode {
  self.code
}

///|
pub fn ArtifactDiagnostic::stage(self : ArtifactDiagnostic) -> Stage {
  self.stage
}

///|
pub fn ArtifactDiagnostic::severity(self : ArtifactDiagnostic) -> Severity {
  self.severity
}

///|
pub fn ArtifactDiagnostic::message(self : ArtifactDiagnostic) -> String {
  self.message
}

///|
pub fn ArtifactDiagnostic::labels(
  self : ArtifactDiagnostic,
) -> Array[ArtifactLabel] {
  [..self.labels]
}

///|
pub fn ArtifactDiagnostic::notes(self : ArtifactDiagnostic) -> Array[String] {
  [..self.notes]
}

///|
pub fn ArtifactDiagnostic::fixes(
  self : ArtifactDiagnostic,
) -> Array[ArtifactFix] {
  [..self.fixes]
}

///|
/// Versioned stable JSON boundary for compiler artifacts.
///
/// Internal IDs and diagnostics are converted to the artifact DTOs before this
/// envelope is constructed. Direct nested DTO decoding is intended only for
/// debug tooling; stable consumers decode this envelope so all nested
/// invariants are checked recursively.
pub struct ArtifactEnvelope[A] {
  schema : String
  offset_encoding : String
  compiler : String
  source : ArtifactSource
  payload : A
  diagnostics : Array[ArtifactDiagnostic]
} derive(Debug, Eq, ToJson)

///|
/// Raw decoding shape. Validation happens only when constructing the public
/// stable envelope below.
struct ArtifactEnvelopeRaw[A] {
  schema : String
  offset_encoding : String
  compiler : String
  source : ArtifactSource
  payload : A
  diagnostics : Array[ArtifactDiagnostic]
} derive(FromJson)

///|
pub impl[A : @json.FromJson] @json.FromJson for ArtifactEnvelope[A] with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ArtifactEnvelope[A] raise @json.JsonDecodeError {
  let raw : ArtifactEnvelopeRaw[A] = @json.from_json(json, path~)
  if !artifact_schema_is_versioned(raw.schema) {
    artifact_decode_error(
      path.add_key("schema"),
      "ArtifactEnvelope: schema must have the form `<name>/<version>`",
    )
  }
  if raw.offset_encoding != OFFSET_ENCODING {
    artifact_decode_error(
      path.add_key("offset_encoding"),
      "ArtifactEnvelope: offset_encoding must be `utf-16`",
    )
  }
  if raw.compiler.is_empty() {
    artifact_decode_error(
      path.add_key("compiler"),
      "ArtifactEnvelope: compiler must not be empty",
    )
  }
  validate_artifact_source(raw.source, path.add_key("source"))
  for index, diagnostic in raw.diagnostics {
    validate_artifact_diagnostic(
      diagnostic,
      path.add_key("diagnostics").add_index(index),
    )
  }
  ArtifactEnvelope::new(
    raw.schema,
    raw.compiler,
    raw.source,
    raw.payload,
    raw.diagnostics,
  )
}

///|
fn artifact_schema_is_versioned(schema : String) -> Bool {
  guard schema.split_once("/") is Some((name, version)) else { false }
  !name.is_empty() &&
  !version.is_empty() &&
  !version.contains("/") &&
  version.all(char => char.is_ascii_digit())
}

///|
fn artifact_source_is_valid(source : ArtifactSource) -> Bool {
  !source.file.is_empty() && !source.content_hash.is_empty()
}

///|
fn artifact_span_is_valid(span : ArtifactSpan) -> Bool {
  artifact_source_is_valid(span.source)
}

///|
fn artifact_edit_is_valid(edit : ArtifactEdit) -> Bool {
  artifact_source_is_valid(edit.source)
}

///|
fn artifact_edits_are_valid(edits : Array[ArtifactEdit]) -> Bool {
  for edit in edits {
    if !artifact_edit_is_valid(edit) {
      return false
    }
  }
  true
}

///|
fn artifact_label_is_valid(label : ArtifactLabel) -> Bool {
  artifact_span_is_valid(label.span)
}

///|
fn artifact_labels_are_valid(labels : Array[ArtifactLabel]) -> Bool {
  for label in labels {
    if !artifact_label_is_valid(label) {
      return false
    }
  }
  true
}

///|
fn artifact_notes_are_valid(notes : Array[String]) -> Bool {
  for note in notes {
    if note.is_empty() {
      return false
    }
  }
  true
}

///|
fn artifact_fix_is_valid(fix : ArtifactFix) -> Bool {
  !fix.title.is_empty() &&
  !fix.edits.is_empty() &&
  artifact_edits_are_valid(fix.edits)
}

///|
fn artifact_fixes_are_valid(fixes : Array[ArtifactFix]) -> Bool {
  for fix in fixes {
    if !artifact_fix_is_valid(fix) {
      return false
    }
  }
  true
}

///|
fn artifact_diagnostic_is_valid(diagnostic : ArtifactDiagnostic) -> Bool {
  !diagnostic.message.is_empty() &&
  !diagnostic.labels.is_empty() &&
  artifact_labels_have_primary(diagnostic.labels) &&
  artifact_labels_are_valid(diagnostic.labels) &&
  artifact_notes_are_valid(diagnostic.notes) &&
  artifact_fixes_are_valid(diagnostic.fixes)
}

///|
fn artifact_diagnostics_are_valid(
  diagnostics : Array[ArtifactDiagnostic],
) -> Bool {
  for diagnostic in diagnostics {
    if !artifact_diagnostic_is_valid(diagnostic) {
      return false
    }
  }
  true
}

///|
fn[T] artifact_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
fn validate_artifact_source(
  source : ArtifactSource,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  if source.file.is_empty() {
    artifact_decode_error(
      path.add_key("file"),
      "ArtifactSource: file must not be empty",
    )
  }
  if source.content_hash.is_empty() {
    artifact_decode_error(
      path.add_key("content_hash"),
      "ArtifactSource: content_hash must not be empty",
    )
  }
}

///|
fn validate_artifact_span(
  span : ArtifactSpan,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  validate_artifact_source(span.source, path.add_key("source"))
}

///|
fn validate_artifact_edit(
  edit : ArtifactEdit,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  validate_artifact_source(edit.source, path.add_key("source"))
}

///|
fn validate_artifact_label(
  label : ArtifactLabel,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  validate_artifact_span(label.span, path.add_key("span"))
}

///|
fn validate_artifact_fix(
  fix : ArtifactFix,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  if fix.title.is_empty() {
    artifact_decode_error(
      path.add_key("title"),
      "ArtifactFix: title must not be empty",
    )
  }
  if fix.edits.is_empty() {
    artifact_decode_error(
      path.add_key("edits"),
      "ArtifactFix: edits must not be empty",
    )
  }
  for index, edit in fix.edits {
    validate_artifact_edit(edit, path.add_key("edits").add_index(index))
  }
}

///|
fn validate_artifact_diagnostic(
  diagnostic : ArtifactDiagnostic,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  if diagnostic.message.is_empty() {
    artifact_decode_error(
      path.add_key("message"),
      "ArtifactDiagnostic: message must not be empty",
    )
  }
  if diagnostic.labels.is_empty() {
    artifact_decode_error(
      path.add_key("labels"),
      "ArtifactDiagnostic: labels must not be empty",
    )
  }
  if !artifact_labels_have_primary(diagnostic.labels) {
    artifact_decode_error(
      path.add_key("labels"),
      "ArtifactDiagnostic: labels must contain a primary label",
    )
  }
  for index, label in diagnostic.labels {
    validate_artifact_label(label, path.add_key("labels").add_index(index))
  }
  for index, note in diagnostic.notes {
    if note.is_empty() {
      artifact_decode_error(
        path.add_key("notes").add_index(index),
        "ArtifactDiagnostic: notes must not contain an empty note",
      )
    }
  }
  for index, fix in diagnostic.fixes {
    validate_artifact_fix(fix, path.add_key("fixes").add_index(index))
  }
}

///|
pub fn[A] ArtifactEnvelope::new(
  schema : String,
  compiler : String,
  source : ArtifactSource,
  payload : A,
  diagnostics : Array[ArtifactDiagnostic],
) -> ArtifactEnvelope[A] {
  guard artifact_schema_is_versioned(schema) &&
    !compiler.is_empty() &&
    artifact_source_is_valid(source) &&
    artifact_diagnostics_are_valid(diagnostics)
  {
    schema,
    offset_encoding: OFFSET_ENCODING,
    compiler,
    source,
    payload,
    diagnostics: [..diagnostics],
  }
}

///|
pub fn[A] ArtifactEnvelope::schema(self : ArtifactEnvelope[A]) -> String {
  self.schema
}

///|
pub fn[A] ArtifactEnvelope::offset_encoding(
  self : ArtifactEnvelope[A],
) -> String {
  self.offset_encoding
}

///|
pub fn[A] ArtifactEnvelope::compiler(self : ArtifactEnvelope[A]) -> String {
  self.compiler
}

///|
pub fn[A] ArtifactEnvelope::source(
  self : ArtifactEnvelope[A],
) -> ArtifactSource {
  self.source
}

///|
pub fn[A] ArtifactEnvelope::payload(self : ArtifactEnvelope[A]) -> A {
  self.payload
}

///|
pub fn[A] ArtifactEnvelope::diagnostics(
  self : ArtifactEnvelope[A],
) -> Array[ArtifactDiagnostic] {
  [..self.diagnostics]
}

///|
/// A deterministic compiler trace event.
///
/// Timing and thread metadata belong to telemetry sinks, not this stable DTO.
/// Any optional source location uses `ArtifactSpan`, never a session-local
/// `SourceId`.
pub struct CompilerEvent {
  sequence : Int
  workspace_revision : @source.WorkspaceRevision
  request_id : String
  stage : Stage
  event : String
  query_key : String
  outcome : String
  parent : Int?
  span : ArtifactSpan?
  payload : Json
} derive(Debug, Eq, ToJson)

///|
pub fn CompilerEvent::new(
  sequence : Int,
  workspace_revision : @source.WorkspaceRevision,
  request_id : String,
  stage : Stage,
  event : String,
  query_key : String,
  outcome : String,
  parent : Int?,
  span : ArtifactSpan?,
  payload : Json,
) -> CompilerEvent {
  guard sequence >= 0 &&
    !request_id.is_empty() &&
    !event.is_empty() &&
    !query_key.is_empty() &&
    !outcome.is_empty()
  guard parent is None ||
    (parent is Some(parent_sequence) && parent_sequence >= 0)
  guard span is None ||
    (span is Some(location) && artifact_span_is_valid(location))
  {
    sequence,
    workspace_revision,
    request_id,
    stage,
    event,
    query_key,
    outcome,
    parent,
    span,
    payload,
  }
}

///|
pub fn CompilerEvent::sequence(self : CompilerEvent) -> Int {
  self.sequence
}

///|
pub fn CompilerEvent::workspace_revision(
  self : CompilerEvent,
) -> @source.WorkspaceRevision {
  self.workspace_revision
}

///|
pub fn CompilerEvent::request_id(self : CompilerEvent) -> String {
  self.request_id
}

///|
pub fn CompilerEvent::stage(self : CompilerEvent) -> Stage {
  self.stage
}

///|
pub fn CompilerEvent::event(self : CompilerEvent) -> String {
  self.event
}

///|
pub fn CompilerEvent::query_key(self : CompilerEvent) -> String {
  self.query_key
}

///|
pub fn CompilerEvent::outcome(self : CompilerEvent) -> String {
  self.outcome
}

///|
pub fn CompilerEvent::parent(self : CompilerEvent) -> Int? {
  self.parent
}

///|
pub fn CompilerEvent::span(self : CompilerEvent) -> ArtifactSpan? {
  self.span
}

///|
pub fn CompilerEvent::payload(self : CompilerEvent) -> Json {
  self.payload
}
