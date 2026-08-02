# Cire specification authority and repository manifest

Profile: `Cire-TR₀/2026-08-01`.

This file is the sole authority/status manifest. Repository `main` is a
candidate stream; a commit becomes a canonical teaching baseline only after an
independent exact-SHA review approves it. Until that happens,
`71c631605ae7b16795f2490123230048f68d1c3f` remains the approved teaching
baseline.

## Authority order

1. [Surface grammar and elaboration](surface-syntax.md) is the only source for
   tokens, grammar, precedence, surface scopes, and lowering.
2. [Temporal formalization](temporal-reactivity-formalization.typ) is the only
   source for Core typing, effects, provenance/capture/world/usage judgments,
   operational transitions, and the frozen V2 wire meaning.
3. [Consumable conformance artifacts](../examples/spec/README.md) are goldens
   and executable checks of those two sources. They do not define new language
   semantics.

A parser, compiler, runtime, tutorial, or test that disagrees with this order is
wrong. This repository intentionally contains no second prose specification
and no compiler/runtime implementation.

## Exact keep/merge/delete manifest

### Keep

- `README.md` — project entry point; non-normative.
- `docs/spec-status.md` — this sole authority/status manifest.
- `docs/surface-syntax.md` — surface grammar plus Appendix A PEG/elaboration.
- `docs/temporal-reactivity-formalization.typ` — static/dynamic semantics.
- `examples/spec/README.md` — conformance artifact index and gate commands.
- `examples/spec/validate-oracles.py` — reference decoder/evaluator/gate.
- `examples/spec/task35-regressions.py` — 13 complete-root adjacent regressions.
- `examples/spec/diagnostics-v2.json`.
- `examples/spec/mutations/v1-rejects-v2-tags.json`.
- `examples/spec/runtime/packed-next-lease-runtime.json`.
- `examples/spec/interfaces/*.json` and
  `examples/spec/interfaces/choose-once.cire`.
- `examples/spec/accept/*.cire` and `examples/spec/reject/*.cire`.

### Merge

- `docs/surface-grammar.md` -> `docs/surface-syntax.md` Appendix A. The
  source file is deleted after the merge.
- Normative fragments formerly repeated across the domain/design notes below
  are already represented in the temporal formalization or surface source.
  No independent rule survives only in a deleted file.

### Delete

- `docs/README.md`
- `docs/capabilities-and-finalization.md`
- `docs/compiler-architecture.md`
- `docs/effects-and-resumptions.md`
- `docs/incremental-computation.md`
- `docs/kokaine-case-study.md`
- `docs/language-overview.md`
- `docs/open-questions.md`
- `docs/polymorphism-design.md`
- `docs/prior-art.md`
- `docs/reactive-ui.md`
- `docs/temporal-reactivity-design-experiment.md`
- `docs/webassembly-and-host-interop.md`
- `docs/simple/README.md`
- `docs/simple/examples.md`
- `docs/simple/progress.md`
- `docs/tutorial/README.md`
- `docs/tutorial/00-how-to-read.md`
- `docs/tutorial/01-first-program.md`
- `docs/tutorial/02-values-and-expressions.md`
- `docs/tutorial/03-functions-and-control-flow.md`
- `docs/tutorial/04-data-and-patterns.md`
- `docs/tutorial/05-generics-traits-and-packages.md`
- `docs/tutorial/06-effects.md`
- `docs/tutorial/07-effect-polymorphism.md`
- `docs/tutorial/08-handlers-and-with.md`
- `docs/tutorial/09-named-capabilities.md`
- `docs/tutorial/10-resumptions.md`
- `docs/tutorial/11-cleanup-owner-and-concurrency.md`
- `docs/tutorial/12-incremental-computation.md`
- `docs/tutorial/13-ui-and-trailing-lambdas.md`
- `docs/tutorial/14-wasm-and-interop.md`
- `docs/tutorial/15-complete-example.md`
- `docs/tutorial/16-syntax-index.md`

No tutorial is retained in this profile; therefore no tutorial can silently
become a stale second specification.

## Closure and release gate

A replacement candidate must have zero references to every deleted path, pass
Markdown link/fence closure over all surviving Markdown, compile the Typst
formalization, validate all JSON/JCS/import hashes, pass the reference decoder
and task-29/30/31/33/34/35 runners, validate PEG definitions, corpus metadata,
diagnostic registry, runtime traces, Python compilation/Ruff, and
`git diff --check`. The handoff records the exact commit/parent/tree, archive
hash, surviving file inventory, and gate outputs.
