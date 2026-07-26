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
} derive(Debug, Eq, ToJson, FromJson)

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
} derive(Debug, Eq, ToJson, FromJson)

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
} derive(Debug, Eq, ToJson, FromJson)

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
