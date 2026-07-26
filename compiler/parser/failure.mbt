///|
/// Expression parsing uses the same token position with two different
/// interpretations of a following block. The flavor is therefore part of
/// every memoization and recursion-guard key.
priv enum ParseFlavor {
  AllowTrailingBlock
  StopBeforeTrailingBlock
} derive(Eq)

///|
/// A stable rule name used by parser traces, memo keys, and recursion guards.
priv struct RuleId(String) derive(Eq)

///|
fn RuleId::new(name : String) -> RuleId {
  guard !name.is_empty()
  RuleId(name)
}

///|

///|
/// The immutable key shape used by selective parser memoization.
///
/// `token_index` is an index in the lossless token snapshot, not a source
/// byte offset.
priv struct MemoKey {
  rule : RuleId
  token_index : Int
  flavor : ParseFlavor
} derive(Eq)

///|
fn MemoKey::new(
  rule : RuleId,
  token_index : Int,
  flavor : ParseFlavor,
) -> MemoKey {
  guard token_index >= 0
  { rule, token_index, flavor }
}

///|
/// The deterministic error information accumulated while PEG alternatives
/// are explored.
///
/// Expected tags and rule contexts retain grammar insertion order. They are
/// arrays rather than hash sets so JSON dumps and rendered diagnostics are
/// stable across processes and compiler backends.
pub struct FailureSummary {
  priv token_index : Int
  priv offset : @source.TextOffset
  priv expected : Array[String]
  priv contexts : Array[String]
  priv committed : Bool
} derive(Debug, Eq, ToJson)

///|
struct FailureSummaryRaw {
  token_index : Int
  offset : @source.TextOffset
  expected : Array[String]
  contexts : Array[String]
  committed : Bool
} derive(FromJson)

///|
pub impl @json.FromJson for FailureSummary with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> FailureSummary raise @json.JsonDecodeError {
  let raw : FailureSummaryRaw = @json.from_json(json, path~)
  if raw.token_index < 0 {
    parser_json_decode_error(
      path.add_key("token_index"),
      "FailureSummary: token_index must be non-negative",
    )
  }
  if raw.expected.is_empty() || !strings_are_nonempty(raw.expected) {
    parser_json_decode_error(
      path.add_key("expected"),
      "FailureSummary: expected tags must be non-empty",
    )
  }
  if !strings_are_nonempty(raw.contexts) {
    parser_json_decode_error(
      path.add_key("contexts"),
      "FailureSummary: contexts must not contain empty labels",
    )
  }
  FailureSummary::new(
    raw.token_index,
    raw.offset,
    raw.expected,
    raw.contexts,
    raw.committed,
  )
}

///|
fn FailureSummary::new(
  token_index : Int,
  offset : @source.TextOffset,
  expected : Array[String],
  contexts : Array[String],
  committed : Bool,
) -> FailureSummary {
  guard token_index >= 0 &&
    !expected.is_empty() &&
    strings_are_nonempty(expected) &&
    strings_are_nonempty(contexts)
  {
    token_index,
    offset,
    expected: ordered_unique(expected),
    contexts: contexts.copy(),
    committed,
  }
}

///|
fn strings_are_nonempty(values : Array[String]) -> Bool {
  for value in values {
    if value.is_empty() {
      return false
    }
  }
  true
}

///|
fn[T] parser_json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
pub fn FailureSummary::token_index(self : FailureSummary) -> Int {
  self.token_index
}

///|
pub fn FailureSummary::offset(self : FailureSummary) -> @source.TextOffset {
  self.offset
}

///|
pub fn FailureSummary::expected(self : FailureSummary) -> Array[String] {
  self.expected.copy()
}

///|
pub fn FailureSummary::contexts(self : FailureSummary) -> Array[String] {
  self.contexts.copy()
}

///|
pub fn FailureSummary::is_committed(self : FailureSummary) -> Bool {
  self.committed
}

///|
fn FailureSummary::with_committed(
  self : FailureSummary,
  committed : Bool,
) -> FailureSummary {
  { ..self, committed, }
}

///|
/// Merges PEG failures by keeping the farther failure and taking an
/// insertion-ordered union when both failures occur at the same position.
fn FailureSummary::merge(
  self : FailureSummary,
  other : FailureSummary,
) -> FailureSummary {
  let position_order = compare_failure_position(self, other)
  if position_order > 0 {
    self
  } else if position_order < 0 {
    other
  } else {
    {
      token_index: self.token_index,
      offset: self.offset,
      expected: ordered_union(self.expected, other.expected),
      contexts: common_context_prefix(self.contexts, other.contexts),
      committed: self.committed || other.committed,
    }
  }
}

///|
/// A context is a rule stack, not a set. Equal-position alternatives retain
/// only the frames that are true for both paths.
fn common_context_prefix(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<limit {
    if left[index] == right[index] {
      result.push(left[index])
    } else {
      break
    }
  }
  result
}

///|
fn compare_failure_position(
  left : FailureSummary,
  right : FailureSummary,
) -> Int {
  if left.token_index < right.token_index {
    -1
  } else if left.token_index > right.token_index {
    1
  } else if left.offset.value() < right.offset.value() {
    -1
  } else if left.offset.value() > right.offset.value() {
    1
  } else {
    0
  }
}

///|
fn ordered_unique(values : Array[String]) -> Array[String] {
  ordered_union([], values)
}

///|
fn ordered_union(left : Array[String], right : Array[String]) -> Array[String] {
  let result = left.copy()
  for value in right {
    if !array_contains_string(result, value) {
      result.push(value)
    }
  }
  result
}

///|
fn array_contains_string(values : Array[String], needle : String) -> Bool {
  for value in values {
    if value == needle {
      return true
    }
  }
  false
}

///|
fn merge_optional_failure(
  left : FailureSummary?,
  right : FailureSummary?,
) -> FailureSummary? {
  match (left, right) {
    (None, None) => None
    (Some(failure), None) | (None, Some(failure)) => Some(failure)
    (Some(left), Some(right)) => Some(left.merge(right))
  }
}
