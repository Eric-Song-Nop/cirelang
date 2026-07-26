///|
fn range(start : Int, end : Int) -> @source.TextRange {
  @source.TextRange::new(
    @source.TextOffset::new(start),
    @source.TextOffset::new(end),
  )
}

///|
fn fix_decode_is_rejected(encoded : String) -> Bool {
  try {
    let _decoded : @diagnostic.Fix = @json.from_json(@json.parse(encoded))
    false
  } catch {
    _ => true
  }
}

///|
fn diagnostic_decode_is_rejected(encoded : String) -> Bool {
  try {
    let _decoded : @diagnostic.Diagnostic = @json.from_json(
      @json.parse(encoded),
    )
    false
  } catch {
    _ => true
  }
}

///|
test "artifact envelope has an exact versioned JSON shape" {
  inspect(
    @diagnostic.DiagnosticCode::new("P0001").to_json().stringify(),
    content="\"P0001\"",
  )
  let envelope = @diagnostic.ArtifactEnvelope::new(
    "cire.parse/1",
    "0.0.0-dev",
    @diagnostic.ArtifactSource::new(
      "tests/parser/effect.cire",
      @source.SourceRevision::new(3),
      "cire-fnv1a64-utf8-v1:0123456789abcdef",
    ),
    ["SourceFile"],
    [],
  )
  let encoded = envelope.to_json().stringify()
  inspect(
    encoded,
    content="{\"schema\":\"cire.parse/1\",\"offset_encoding\":\"utf-16\",\"compiler\":\"0.0.0-dev\",\"source\":{\"file\":\"tests/parser/effect.cire\",\"revision\":3,\"content_hash\":\"cire-fnv1a64-utf8-v1:0123456789abcdef\"},\"payload\":[\"SourceFile\"],\"diagnostics\":[]}",
  )
  let decoded : @diagnostic.ArtifactEnvelope[Array[String]] = @json.from_json(
    @json.parse(encoded),
  )
  assert_eq(decoded, envelope)
}

///|
fn artifact_envelope_decode_is_rejected(encoded : String) -> Bool {
  try {
    let _decoded : @diagnostic.ArtifactEnvelope[Array[String]] = @json.from_json(
      @json.parse(encoded),
    )
    false
  } catch {
    _ => true
  }
}

///|
test "stable envelope decoding enforces protocol invariants" {
  let source = @diagnostic.ArtifactSource::new(
    "tests/parser/effect.cire",
    @source.SourceRevision::new(3),
    "cire-fnv1a64-utf8-v1:0123456789abcdef",
  )
  let diagnostic = @diagnostic.ArtifactDiagnostic::new(
    @diagnostic.DiagnosticCode::new("P0001"),
    Parse,
    Error,
    "expected an effect declaration",
    [
      @diagnostic.ArtifactLabel::primary(
        @diagnostic.ArtifactSpan::new(source, range(0, 0)),
        "declaration starts here",
      ),
    ],
    [],
    [],
  )
  let encoded = @diagnostic.ArtifactEnvelope::new(
      "cire.parse/1",
      "0.0.0-dev",
      source,
      ["SourceFile"],
      [diagnostic],
    )
    .to_json()
    .stringify()
  assert_true(
    artifact_envelope_decode_is_rejected(
      encoded.replace(old="\"utf-16\"", new="\"utf-8\""),
    ),
  )
  assert_true(
    artifact_envelope_decode_is_rejected(
      encoded.replace(old="\"cire.parse/1\"", new="\"cire.parse\""),
    ),
  )
  assert_true(
    artifact_envelope_decode_is_rejected(
      encoded.replace(old="\"Primary\"", new="\"Secondary\""),
    ),
  )
}

///|
test "cross-file labels and fixes never serialize session source ids" {
  let main_revision = @source.SourceRevision::new(7)
  let library_revision = @source.SourceRevision::new(2)
  let main_source = @diagnostic.ArtifactSource::new(
    "src/main.cire", main_revision, "cire-fnv1a64-utf8-v1:fedcba9876543210",
  )
  let library_source = @diagnostic.ArtifactSource::new(
    "src/library.cire", library_revision, "cire-fnv1a64-utf8-v1:1234567890abcdef",
  )
  let labels = [
    @diagnostic.ArtifactLabel::primary(
      @diagnostic.ArtifactSpan::new(main_source, range(12, 20)),
      "operation is used here",
    ),
    @diagnostic.ArtifactLabel::secondary(
      @diagnostic.ArtifactSpan::new(library_source, range(4, 11)),
      "capability is declared here",
    ),
  ]
  let edits = [
    @diagnostic.ArtifactEdit::new(library_source, range(11, 11), "[app]"),
  ]
  inspect(
    labels[1].span().to_json().stringify(),
    content="{\"source\":{\"file\":\"src/library.cire\",\"revision\":2,\"content_hash\":\"cire-fnv1a64-utf8-v1:1234567890abcdef\"},\"range\":{\"start\":4,\"end\":11}}",
  )
  inspect(
    edits[0].to_json().stringify(),
    content="{\"source\":{\"file\":\"src/library.cire\",\"revision\":2,\"content_hash\":\"cire-fnv1a64-utf8-v1:1234567890abcdef\"},\"range\":{\"start\":11,\"end\":11},\"insert\":\"[app]\"}",
  )
  let fixes = [
    @diagnostic.ArtifactFix::new("name the capability", Always, edits),
  ]
  let diagnostic = @diagnostic.ArtifactDiagnostic::new(
    @diagnostic.DiagnosticCode::new("EFFECT0004"),
    TypeCheck,
    Error,
    "anonymous capability cannot satisfy this use",
    labels,
    ["artifact locations use logical paths and revisions"],
    fixes,
  )
  let envelope = @diagnostic.ArtifactEnvelope::new(
    "cire.check/1",
    "0.0.0-dev",
    main_source,
    ["TypedModule"],
    [diagnostic],
  )
  labels.push(
    @diagnostic.ArtifactLabel::secondary(
      @diagnostic.ArtifactSpan::new(
        @diagnostic.ArtifactSource::new(
          "ignored.cire",
          @source.SourceRevision::initial(),
          "cire-fnv1a64-utf8-v1:0000000000000000",
        ),
        range(0, 0),
      ),
      "must not leak through the constructor",
    ),
  )
  edits.push(
    @diagnostic.ArtifactEdit::new(
      @diagnostic.ArtifactSource::new(
        "ignored.cire",
        @source.SourceRevision::initial(),
        "cire-fnv1a64-utf8-v1:0000000000000000",
      ),
      range(0, 0),
      "",
    ),
  )
  assert_eq(envelope.diagnostics()[0].labels().length(), 2)
  assert_eq(envelope.diagnostics()[0].fixes()[0].edits().length(), 1)
  let returned_labels = envelope.diagnostics()[0].labels()
  returned_labels.push(returned_labels[0])
  assert_eq(envelope.diagnostics()[0].labels().length(), 2)
  let encoded = envelope.to_json().stringify()
  assert_false(encoded.contains("source_id"))
  assert_false(encoded.contains("\"source\":7"))
  assert_true(encoded.contains("\"file\":\"src/main.cire\""))
  assert_true(encoded.contains("\"file\":\"src/library.cire\""))
  assert_true(encoded.contains("cire-fnv1a64-utf8-v1:1234567890abcdef"))
  let decoded : @diagnostic.ArtifactEnvelope[Array[String]] = @json.from_json(
    @json.parse(encoded),
  )
  assert_eq(decoded, envelope)
  assert_eq(decoded.diagnostics()[0].code().value(), "EFFECT0004")
  assert_eq(
    decoded.diagnostics()[0].labels()[1].span().source().file(),
    "src/library.cire",
  )
  assert_eq(
    decoded.diagnostics()[0].fixes()[0].edits()[0].source().file(),
    "src/library.cire",
  )
}

///|
test "internal diagnostics retain session spans and edits" {
  let source_id = @source.SourceId::new(42)
  let revision = @source.SourceRevision::new(9)
  let span = @source.Span::new(source_id, range(2, 6))
  let edit = @source.TextEdit::new(source_id, revision, range(6, 6), "}")
  let diagnostic = @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("P0001"),
      Parse,
      Error,
      "expected `}`",
      @diagnostic.Label::primary(span, "this block is not closed"),
      revision,
    )
    .with_note("parser recovery inserted a missing token")
    .with_fix(@diagnostic.Fix::new("insert `}`", Always, [edit]))
  assert_eq(diagnostic.labels()[0].span().source(), source_id)
  assert_eq(diagnostic.fixes()[0].edits()[0].source(), source_id)
}

///|
test "internal diagnostic JSON decoding preserves constructor invariants" {
  let source_id = @source.SourceId::new(17)
  let revision = @source.SourceRevision::new(4)
  let span = @source.Span::new(source_id, range(1, 2))
  let label = @diagnostic.Label::primary(span, "value starts here")
  let empty_message_label = @diagnostic.Label::secondary(span, "")
  let decoded_empty_message_label : @diagnostic.Label = @json.from_json(
    empty_message_label.to_json(),
  )
  assert_eq(decoded_empty_message_label, empty_message_label)
  let edit = @source.TextEdit::new(source_id, revision, range(2, 2), "()")
  let edits = [edit]
  let fix = @diagnostic.Fix::new("insert arguments", Always, edits)
  edits.push(@source.TextEdit::new(source_id, revision, range(0, 0), "ignored"))
  assert_eq(fix.edits().length(), 1)
  let fix_json = fix.to_json().stringify()
  let decoded_fix : @diagnostic.Fix = @json.from_json(@json.parse(fix_json))
  assert_eq(decoded_fix, fix)
  assert_true(
    fix_decode_is_rejected(
      fix_json.replace(
        old="\"title\":\"insert arguments\"",
        new="\"title\":\"\"",
      ),
    ),
  )
  assert_true(
    fix_decode_is_rejected(
      "{\"title\":\"insert arguments\",\"applicability\":\"Always\",\"edits\":[]}",
    ),
  )
  let diagnostic = @diagnostic.Diagnostic::new(
      @diagnostic.DiagnosticCode::new("P0017"),
      Parse,
      Error,
      "expected arguments",
      label,
      revision,
    )
    .with_note("calls require an argument list")
    .with_fix(fix)
  let encoded = diagnostic.to_json().stringify()
  let decoded : @diagnostic.Diagnostic = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, diagnostic)
  let returned_labels = decoded.labels()
  returned_labels.push(empty_message_label)
  let returned_notes = decoded.notes()
  returned_notes.push("caller mutation")
  let returned_fixes = decoded.fixes()
  returned_fixes.push(fix)
  let returned_edits = decoded.fixes()[0].edits()
  returned_edits.push(edit)
  assert_eq(decoded.labels().length(), 1)
  assert_eq(decoded.notes().length(), 1)
  assert_eq(decoded.fixes().length(), 1)
  assert_eq(decoded.fixes()[0].edits().length(), 1)
  assert_true(
    diagnostic_decode_is_rejected(
      encoded.replace(
        old="\"message\":\"expected arguments\"",
        new="\"message\":\"\"",
      ),
    ),
  )
  assert_true(
    diagnostic_decode_is_rejected(
      encoded.replace(old="\"Primary\"", new="\"Secondary\""),
    ),
  )
  let no_labels = encoded.replace(old=label.to_json().stringify(), new="")
  assert_true(no_labels.contains("\"labels\":[]"))
  assert_true(diagnostic_decode_is_rejected(no_labels))
  assert_true(
    diagnostic_decode_is_rejected(
      encoded.replace(
        old="\"notes\":[\"calls require an argument list\"]",
        new="\"notes\":[\"\"]",
      ),
    ),
  )
  assert_true(
    diagnostic_decode_is_rejected(
      encoded.replace(
        old="\"title\":\"insert arguments\"",
        new="\"title\":\"\"",
      ),
    ),
  )
  assert_true(
    diagnostic_decode_is_rejected(
      encoded.replace(
        old="\"labels\":[\{label.to_json().stringify()}]",
        new="\"labels\":[\{label.to_json().stringify()}," +
          "\{label.to_json().stringify()}]",
      ),
    ),
  )
  let secondary = @diagnostic.Label::secondary(span, "related location")
  let with_secondary = diagnostic.with_label(secondary)
  let decoded_with_secondary : @diagnostic.Diagnostic = @json.from_json(
    with_secondary.to_json(),
  )
  assert_eq(decoded_with_secondary, with_secondary)
}

///|
test "trace sinks are injectable, deterministic, and snapshot JSON eagerly" {
  let source = @diagnostic.ArtifactSource::new(
    "src/main.cire",
    @source.SourceRevision::new(5),
    "cire-fnv1a64-utf8-v1:fedcba9876543210",
  )
  let payload = @json.parse("{\"cached\":true}")
  let event = @diagnostic.CompilerEvent::new(
    0,
    @source.WorkspaceRevision::new(8),
    "request-1",
    Parse,
    "query.finished",
    "parse:src/main.cire",
    "cache-miss",
    None,
    Some(@diagnostic.ArtifactSpan::new(source, range(0, 4))),
    payload,
  )
  let noop = @diagnostic.NoopTraceSink::new()
  @diagnostic.TraceSink::emit(noop, event)
  let memory = @diagnostic.MemoryTraceSink::new()
  assert_true(memory.is_empty())
  @diagnostic.TraceSink::emit(memory, event)
  let first_line = memory.lines()[0]
  guard payload is Object(fields)
  fields["cached"] = Json::boolean(false)
  @diagnostic.TraceSink::emit(memory, event)
  assert_eq(memory.length(), 2)
  assert_true(first_line.contains("\"cached\":true"))
  assert_true(memory.lines()[1].contains("\"cached\":false"))
  let returned_lines = memory.lines()
  returned_lines.push("caller mutation")
  assert_eq(memory.length(), 2)
}
