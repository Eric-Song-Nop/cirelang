///|
fn Parser::is_rule_active(self : Parser, key : MemoKey) -> Bool {
  for active in self.active_rules {
    if active == key {
      return true
    }
  }
  false
}

///|
/// Enters a rule at the current significant token. Re-entering the same rule,
/// token position, and parse flavor is rejected as left recursion/no progress.
fn Parser::enter_rule(
  self : Parser,
  rule : RuleId,
  flavor : ParseFlavor,
  label : String,
) -> Bool {
  guard !label.is_empty()
  let key = MemoKey::new(rule, self.significant_index(), flavor)
  if self.is_rule_active(key) {
    self.fail_expected("non-recursive \{label}")
  } else {
    let entry_cut_epoch = self.cut_epoch
    let entry_failure_committed = self.failure_committed
    self.failure_committed = false
    self.active_rules.push(key)
    self.rule_frames.push({
      key,
      label,
      committed: false,
      entry_cut_epoch,
      entry_failure_committed,
    })
    self.contexts.push(label)
    true
  }
}

///|
/// Leaves the innermost rule and propagates a failed rule's commit bit through
/// its `FailureSummary`. A successful nested rule never leaks its local cut
/// into its caller.
fn Parser::leave_rule(self : Parser, matched : Bool) -> Unit {
  guard self.rule_frames.pop() is Some(frame)
  guard self.active_rules.pop() is Some(active) && active == frame.key
  guard self.contexts.pop() is Some(label) && label == frame.label
  let local_failure_committed = self.failure_committed || frame.committed
  self.cut_epoch = frame.entry_cut_epoch
  self.failure_committed = if matched {
    frame.entry_failure_committed
  } else {
    frame.entry_failure_committed || local_failure_committed
  }
  let parent_committed = match self.rule_frames.last() {
    Some(parent) => parent.committed
    None => false
  }
  match self.failure {
    Some(failure) =>
      self.failure = Some(
        failure.with_committed(
          if matched {
            parent_committed
          } else {
            failure.is_committed() ||
            local_failure_committed ||
            parent_committed
          },
        ),
      )
    None => ()
  }
}

///|
/// Commits only the current rule invocation. The bit is discarded if that
/// rule succeeds and is restored by speculative rollback.
fn Parser::cut(self : Parser) -> Unit {
  guard self.rule_frames.last() is Some(frame)
  let index = self.rule_frames.length() - 1
  self.rule_frames[index] = { ..frame, committed: true }
  self.cut_epoch = self.cut_epoch + 1
}

///|
fn Parser::current_rule_committed(self : Parser) -> Bool {
  match self.rule_frames.last() {
    Some(frame) => frame.committed
    None => false
  }
}

///|
fn Parser::fail_expected(self : Parser, expected : String) -> Bool {
  guard !expected.is_empty()
  let failure = FailureSummary::new(
    self.significant_index(),
    self.current_offset(),
    [expected],
    self.contexts,
    self.current_rule_committed(),
  )
  self.failure = merge_optional_failure(self.failure, Some(failure))
  false
}

///|
/// PEG ordered choice. Each uncommitted failed branch is completely rolled
/// back before the next branch. A committed failure excludes all siblings.
///
/// Rules remain ordinary functions; closures are used here only to delimit
/// the state transaction of each alternative.
fn Parser::ordered_choice(
  self : Parser,
  alternatives : ArrayView[(Parser) -> Bool],
) -> Bool {
  let baseline = self.checkpoint()
  let mut aggregate = baseline.failure
  for alternative in alternatives {
    self.rollback(baseline)
    self.failure_committed = false
    let matched = alternative(self)
    let branch_failure = self.failure
    aggregate = merge_optional_failure(aggregate, branch_failure)
    if matched {
      guard self.node_depth == baseline.node_depth &&
        self.marker_depth == baseline.marker_depth
      self.failure_committed = baseline.failure_committed
      self.failure = aggregate
      return true
    }
    let branch_committed = self.failure_committed ||
      self.cut_epoch > baseline.cut_epoch
    if branch_committed {
      self.rollback(baseline)
      self.failure_committed = true
      self.failure = aggregate.map(item => item.with_committed(true))
      return false
    }
  }
  self.rollback(baseline)
  self.failure = aggregate
  false
}

///|
/// Runs silent positive lookahead. Cursor, events, diagnostics, failures,
/// active recursion guards, and cut state are always restored.
fn Parser::probe(self : Parser, rule : (Parser) -> Bool) -> Bool {
  let checkpoint = self.checkpoint()
  let matched = rule(self)
  self.rollback(checkpoint)
  matched
}
