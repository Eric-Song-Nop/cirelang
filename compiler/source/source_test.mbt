///|
test "UTF-16 offsets and line positions" {
  let source = @source.SourceSnapshot::new(
    @source.SourceId::new(7),
    @source.SourceRevision::initial(),
    "unicode.cire",
    "a😀中\nxy",
  )
  inspect(source.length().value(), content="7")
  assert_true(source.is_scalar_boundary(@source.TextOffset::new(1)))
  assert_false(source.is_scalar_boundary(@source.TextOffset::new(2)))
  assert_true(source.is_scalar_boundary(@source.TextOffset::new(3)))
  let position = source.line_index().position(@source.TextOffset::new(5))
  guard position is Some(position) else { fail("expected a position") }
  inspect(position.line(), content="1")
  inspect(position.character(), content="0")
  assert_eq(
    source.line_index().offset(position),
    Some(@source.TextOffset::new(5)),
  )
  assert_eq(source.position(@source.TextOffset::new(2)), None)
  assert_eq(source.offset(@source.LineColumn::new(0, 2)), None)
  assert_eq(
    source.offset(@source.LineColumn::new(0, 3)),
    Some(@source.TextOffset::new(3)),
  )
}

///|
test "line index handles CRLF and excludes line terminators" {
  let index = @source.LineIndex::new("a\r\n😀\r中\n")
  inspect(index.line_count(), content="4")
  assert_eq(index.line_start(1), Some(@source.TextOffset::new(3)))
  assert_eq(index.line_end(1), Some(@source.TextOffset::new(5)))
  assert_eq(
    index.position(@source.TextOffset::new(2)),
    Some(@source.LineColumn::new(0, 1)),
  )
  assert_eq(
    index.offset(@source.LineColumn::new(1, 2)),
    Some(@source.TextOffset::new(5)),
  )
  assert_eq(index.offset(@source.LineColumn::new(1, 3)), None)
}

///|
test "revision-checked source edit" {
  let source = @source.SourceSnapshot::new(
    @source.SourceId::new(1),
    @source.SourceRevision::initial(),
    "edit.cire",
    "let value = 1",
  )
  let edit = @source.TextEdit::new(
    source.id(),
    source.revision(),
    @source.TextRange::new(
      @source.TextOffset::new(12),
      @source.TextOffset::new(13),
    ),
    "42",
  )
  let edited = source.apply_edit(edit)
  inspect(edited.text(), content="let value = 42")
  inspect(edited.revision().value(), content="1")
}

///|
test "source edits reject stale snapshots and split surrogate pairs" {
  let source = @source.SourceSnapshot::new(
    @source.SourceId::new(1),
    @source.SourceRevision::initial(),
    "edit.cire",
    "a😀b",
  )
  let split_scalar = @source.TextEdit::new(
    source.id(),
    source.revision(),
    @source.TextRange::new(
      @source.TextOffset::new(2),
      @source.TextOffset::new(3),
    ),
    "",
  )
  try source.apply_edit(split_scalar) catch {
    InvalidUnicodeBoundary(_) => ()
    _ => fail("expected InvalidUnicodeBoundary")
  } noraise {
    _ => fail("expected an invalid Unicode boundary to be rejected")
  }
  let stale = @source.TextEdit::new(
    source.id(),
    @source.SourceRevision::new(9),
    @source.TextRange::empty(@source.TextOffset::zero()),
    "",
  )
  try source.apply_edit(stale) catch {
    StaleRevision(..) => ()
    _ => fail("expected StaleRevision")
  } noraise {
    _ => fail("expected a stale edit to be rejected")
  }
}

///|
test "source protocol JSON round-trip" {
  let range = @source.TextRange::new(
    @source.TextOffset::new(2),
    @source.TextOffset::new(5),
  )
  let encoded = range.to_json().stringify()
  let decoded : @source.TextRange = @json.from_json(@json.parse(encoded))
  assert_eq(decoded, range)
  json_inspect(@source.Span::new(@source.SourceId::new(3), range), content={
    "source": 3,
    "range": { "start": 2, "end": 5 },
  })
}

///|
test "source protocol rejects values that violate invariants" {
  try
    (@json.from_json(@json.parse("{\"start\":5,\"end\":2}")) : @source.TextRange)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an invalid range to be rejected")
  }
  try
    (
      @json.from_json(@json.parse("{\"line\":-1,\"character\":0}")) :
      @source.LineColumn)
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an invalid position to be rejected")
  }
  try (@json.from_json(@json.parse("-1")) : @source.SourceId) catch {
    _ => ()
  } noraise {
    _ => fail("expected an invalid source id to be rejected")
  }
  let workspace = @source.WorkspaceRevision::new(3)
  let decoded_workspace : @source.WorkspaceRevision = @json.from_json(
    workspace.to_json(),
  )
  assert_eq(decoded_workspace, workspace)
}
