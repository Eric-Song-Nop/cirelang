///|
pub(all) enum Severity {
  Error
  Warning
  Information
  Hint
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Stage {
  Load
  Lex
  Parse
  Lower
  Resolve
  TypeCheck
  CaptureCheck
  Backend
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct DiagnosticCode(String) derive(Debug, Eq)

///|
pub fn DiagnosticCode::new(value : String) -> DiagnosticCode {
  guard !value.is_empty()
  DiagnosticCode(value)
}

///|
pub fn DiagnosticCode::value(self : DiagnosticCode) -> String {
  self.0
}

///|
pub impl ToJson for DiagnosticCode with fn to_json(self : DiagnosticCode) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for DiagnosticCode with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> DiagnosticCode raise @json.JsonDecodeError {
  let value : String = @json.from_json(json, path~)
  if value.is_empty() {
    raise JsonDecodeError((path, "DiagnosticCode: expected a non-empty string"))
  }
  DiagnosticCode(value)
}

///|
pub(all) enum LabelStyle {
  Primary
  Secondary
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct Label {
  span : @source.Span
  style : LabelStyle
  message : String
} derive(Debug, Eq, ToJson)

///|
struct LabelRaw {
  span : @source.Span
  style : LabelStyle
  message : String
} derive(FromJson)

///|
pub impl @json.FromJson for Label with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Label raise @json.JsonDecodeError {
  let raw : LabelRaw = @json.from_json(json, path~)
  { span: raw.span, style: raw.style, message: raw.message }
}

///|
pub fn Label::primary(span : @source.Span, message : String) -> Label {
  { span, style: Primary, message }
}

///|
pub fn Label::secondary(span : @source.Span, message : String) -> Label {
  { span, style: Secondary, message }
}

///|
pub fn Label::span(self : Label) -> @source.Span {
  self.span
}

///|
pub fn Label::style(self : Label) -> LabelStyle {
  self.style
}

///|
pub fn Label::message(self : Label) -> String {
  self.message
}

///|
pub(all) enum Applicability {
  Always
  MaybeIncorrect
  Unsafe
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct Fix {
  title : String
  applicability : Applicability
  edits : Array[@source.TextEdit]
} derive(Debug, Eq, ToJson)

///|
struct FixRaw {
  title : String
  applicability : Applicability
  edits : Array[@source.TextEdit]
} derive(FromJson)

///|
pub impl @json.FromJson for Fix with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Fix raise @json.JsonDecodeError {
  let raw : FixRaw = @json.from_json(json, path~)
  if raw.title.is_empty() {
    diagnostic_json_decode_error(
      path.add_key("title"),
      "Fix: title must not be empty",
    )
  }
  if raw.edits.is_empty() {
    diagnostic_json_decode_error(
      path.add_key("edits"),
      "Fix: edits must not be empty",
    )
  }
  { title: raw.title, applicability: raw.applicability, edits: [..raw.edits] }
}

///|
pub fn Fix::new(
  title : String,
  applicability : Applicability,
  edits : Array[@source.TextEdit],
) -> Fix {
  guard !title.is_empty() && !edits.is_empty()
  { title, applicability, edits: [..edits] }
}

///|
pub fn Fix::title(self : Fix) -> String {
  self.title
}

///|
pub fn Fix::applicability(self : Fix) -> Applicability {
  self.applicability
}

///|
pub fn Fix::edits(self : Fix) -> Array[@source.TextEdit] {
  [..self.edits]
}

///|
pub struct Diagnostic {
  code : DiagnosticCode
  stage : Stage
  severity : Severity
  message : String
  labels : Array[Label]
  notes : Array[String]
  fixes : Array[Fix]
  revision : @source.SourceRevision
} derive(Debug, Eq, ToJson)

///|
struct DiagnosticRaw {
  code : DiagnosticCode
  stage : Stage
  severity : Severity
  message : String
  labels : Array[Label]
  notes : Array[String]
  fixes : Array[Fix]
  revision : @source.SourceRevision
} derive(FromJson)

///|
pub impl @json.FromJson for Diagnostic with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Diagnostic raise @json.JsonDecodeError {
  let raw : DiagnosticRaw = @json.from_json(json, path~)
  if raw.message.is_empty() {
    diagnostic_json_decode_error(
      path.add_key("message"),
      "Diagnostic: message must not be empty",
    )
  }
  if raw.labels.is_empty() || raw.labels[0].style() != Primary {
    diagnostic_json_decode_error(
      path.add_key("labels"),
      "Diagnostic: first label must be primary",
    )
  }
  for index = 1; index < raw.labels.length(); index = index + 1 {
    if raw.labels[index].style() != Secondary {
      diagnostic_json_decode_error(
        path.add_key("labels").add_index(index),
        "Diagnostic: labels after the primary label must be secondary",
      )
    }
  }
  for index, note in raw.notes {
    if note.is_empty() {
      diagnostic_json_decode_error(
        path.add_key("notes").add_index(index),
        "Diagnostic: notes must not contain an empty note",
      )
    }
  }
  {
    code: raw.code,
    stage: raw.stage,
    severity: raw.severity,
    message: raw.message,
    labels: [..raw.labels],
    notes: [..raw.notes],
    fixes: [..raw.fixes],
    revision: raw.revision,
  }
}

///|
fn[T] diagnostic_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
pub fn Diagnostic::new(
  code : DiagnosticCode,
  stage : Stage,
  severity : Severity,
  message : String,
  primary : Label,
  revision : @source.SourceRevision,
) -> Diagnostic {
  guard !message.is_empty() && primary.style() == Primary
  {
    code,
    stage,
    severity,
    message,
    labels: [primary],
    notes: [],
    fixes: [],
    revision,
  }
}

///|
pub fn Diagnostic::with_label(self : Diagnostic, label : Label) -> Diagnostic {
  guard label.style() == Secondary
  { ..self, labels: [..self.labels, label] }
}

///|
pub fn Diagnostic::with_note(self : Diagnostic, note : String) -> Diagnostic {
  guard !note.is_empty()
  { ..self, notes: [..self.notes, note] }
}

///|
pub fn Diagnostic::with_fix(self : Diagnostic, fix : Fix) -> Diagnostic {
  { ..self, fixes: [..self.fixes, fix] }
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> DiagnosticCode {
  self.code
}

///|
pub fn Diagnostic::stage(self : Diagnostic) -> Stage {
  self.stage
}

///|
pub fn Diagnostic::severity(self : Diagnostic) -> Severity {
  self.severity
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::labels(self : Diagnostic) -> Array[Label] {
  [..self.labels]
}

///|
pub fn Diagnostic::notes(self : Diagnostic) -> Array[String] {
  [..self.notes]
}

///|
pub fn Diagnostic::fixes(self : Diagnostic) -> Array[Fix] {
  [..self.fixes]
}

///|
pub fn Diagnostic::revision(self : Diagnostic) -> @source.SourceRevision {
  self.revision
}
