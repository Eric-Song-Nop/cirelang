#import "../shared.typ": *

= Cire-v1.0 implementation 与 mechanization handoff <implementation-handoff-v1>

== 仓库状态

当前仓库只有：

```text
canonical specification-candidate profile
canonical surface grammar
formal Core judgments
source-design accept/reject examples
```

当前没有：

```text
lexer / parser / lossless CST
typed CST
Surface HIR
Kernel HIR
resolver/type/effect/capture checker
runtime / Wasm backend / LSP
```

所以本文只提供 implementation 必须满足的 lowering/checking/runtime contract。当前仓库没有
artifact model、finite checker或能从规范生成它们的 generator。历史实现不能作为 grammar或
静态语义的权威。

== Retained implementation field sketch（non-normative）

下表只是旧 TR0 checker 的 implementation sketch。Successor producer 必须首先实现
@package-interface-v1、@function-contract-v3 与 @successor-origin-registry 的 exact schema；不得把下列
field list 当作另一个 wire root。

```text
TypedExpr {
  type
  flow
  provenance
  normalized_effect_row
  attributed_demand
  world_in
  world_out
  suspension
  semantic_summary
  captures
  usage_in
  usage_out
  latent_site_evidence
  phase
  owner_region
  evidence
}

OperationSignature {
  mode
  type_parameters
  parameters
  result
  resume_transition
  secondary_site_set       // retained V2 closed form; successor consumes it through M3
  secondary_suspension
  secondary_summary
  suspension_bound
  result_summary_transformer
  required_phase
  site_obligations
}

TypedFunctionContractHIR {
  effect_row
  world_transformer
  returnability
  flow_summary
  suspension
  semantic_summary
  closure_provenance
  closure_captures
  latent_usage
  result_summary_transformer
  required_phase
  ParametricObligations
  LatentSites
}

HandlerEvidence {
  effect
  exact_entry
  prompt_template_slot
  installation_prompt
  actual_mode
  policy
  trust_origin
  handler_environment_provenance
  handler_environment_captures
  return_contract
  clause_schemas
}

TemporalValueEvidence {
  clock_identity
  origin_zone
  stability
  cross_world_captures
  shareability
  later_contract
  clock_package_summary
}
```

== Imported surface conformance handoff

唯一 surface authority至少提供以下 CST/HIR tests，本文只核对其 verified normalized HIR与
elaboration结果：

```text
delay[frame] { 1 }
delay [frame] /*comment*/ { 1 }
delay(x)                         ordinary function call
advance(value)                   ordinary parse, intrinsic resolve
Next[frame, Int]                 type application + kind reclassification

once yield() -> Unit resumes next may_suspend
once await(task : Task[A]) -> A may_suspend
duplicate resumes annotation     parse succeeds, validation rejects
abort raise(...) -> A resumes next
                                  parse succeeds, validation rejects

with h1 as c1
with h2
in { body }

old single-item with syntax
                                  rejects with profile migration diagnostic
```

Surface parser不负责判断：

- `frame` 是否真是 FrameClock identity；
- `advance` 是否解析到 sealed intrinsic；
- operation annotation是否合法；
- named capability是否逃逸；
- handler是否 temporal-pure。

这些属于 lowering/resolver/type checking。

== Type checker conformance cases

本文的 accept/reject程序在真实 frontend/checker 存在后应转成 reproducible golden suite；
当前仓库只记录 source shape 与 expected stable diagnostic，不得报告为 parser/typechecker
execution。未来每个 case保存：

```text
surface source
resolved identity graph
normalized Core
expected type
expected flow
expected provenance
expected residual row
expected world transition
expected suspension
expected semantic summary
expected captures
expected usage transition
expected latent site schemas
expected diagnostic rule id
```

Rule id例如 `T-Delay`、`T-Advance`、`T-Live` 应进入高级 diagnostic trace，
但普通错误信息仍使用用户术语。
