#import "../shared.typ": *

```text
import_contract_computation_v2(node, applications, returns, delegates):
  match exact_variant(node):
    LiteralPathsV2(paths):
      require paths nonempty
      return map(paths, p => import_path_v2(
        p, applications, returns, delegates))
    CurrentDispositionPathsV2(paths):
      require delegates is HandlerClauseOnly(disposition_binder)
        or diagnose path-bind-literal-prefix-forbidden
      require this node is the immediate PathBindV2 prefix
      require paths nonempty
      return CurrentDispositionPaths(
        map(paths, p => import_path_v2(
          p, applications, returns, delegates)), disposition_binder)
    InvokeV2(slot):
      require unique slot in applications
      return Invoke(slot)
    PathBindV2(prefix, binder, continuation, PreserveTerminalV2):
      p = import_contract_computation_v2(
        prefix, applications, returns, delegates)
      require binder.slot not in returns
      b = import_return_binder_v2(binder, returns)
      prefix_types = derive_return_types(
        p, applications, delegates.current_disposition)
      require prefix_types is defined
        or diagnose path-bind-literal-prefix-forbidden
      require every t in prefix_types has b.type == t
      require every Returns path r in p has
        b.world/provenance/capture == project_return(r, applications)
      c = import_contract_computation_v2(
        continuation, applications, returns + {binder.slot -> b}, delegates)
      return PathBind(p, b, c, PreserveTerminal)
    JoinV2(members):
      require members nonempty
      return map(members, m => import_contract_computation_v2(
        m, applications, returns, delegates))
    otherwise:
      diagnose unknown-contract-computation-variant

import_path_outcome_v2(outcome, applications, returns, delegates):
  match exact_variant(outcome):
    ReturnsV2(transition, transformer):
      return Returns(import_transition_v1_exact(transition),
        import_result_transformer_v2(transformer, returns))
    AbortsV2(origin): return Aborts(origin)
    TransfersV2(park):
      return Transfers(import_park_contract_v2(park, applications, returns))
    DelegatesV2(forward, evidence):
      require delegates is HandlerClauseOnly(disposition_binder)
        or diagnose delegates-outside-handler-clause
      require evidence.inner_disposition ==
        SlotRefV1(SuffixLive, disposition_binder.slot)
      return Delegates(
        import_forward_contract_v2(forward, applications, returns),
        import_forward_disposition_v2(evidence, disposition_binder))
    otherwise:
      diagnose unknown-path-outcome-v2
```

Every recursive V2 expression importer receives the same `returns` map;
`Return*V2(slot)` requires an exact entry and `ReturnUsageV2(slot)` additionally
requires that entry's type be `ResumeTypeRefV2`. Root Function/Suffix and handler
return calls pass `delegates=Forbidden`; only the corresponding clause call passes
`HandlerClauseOnly`. Unknown tags and extra/missing variant fields are errors,
never extension points for this frozen profile.

`Call` obligation 在 T-App 实例化和 discharge；`HandlerInstall`
obligation与对应 `LatentSiteV2` 原样保留到 fresh delimiter prompt存在时的
`InstallOK`。调用者不得仅因跨模块 call成功就把后一阶段清空。

Legacy V2 exactness diagnostic id 由本 retained subsection 独立冻结，只支配 legacy
decoder；仓库不再保留一份 examples 下的平行 JSON authority。@successor-diagnostics 的
`CireDiagnosticsV3` 是 exact closed 133-entry successor artifact：它保留 frozen V2 的全部 70 个
ID；初始 successor set 含 71 个 ID，其中 8 个与 V2 重合、63 个为 successor-only，因此 union
基数为 133。重合 ID 的
successor 六字段 metadata 由 @successor-diagnostics 唯一决定；old-only ID 也已逐项映射到 successor
stage、causal cluster、origin role、notes 与 fix safety，不能用 blanket stage或通用 note代替。
Legacy decoder仍只读取 frozen V2 registry meaning；successor producer只读取 V3 registry。两者共享稳定
ID不等于合并 wire artifact，也不得借 profile迁移删除、alias或无 ledger重解释任何 legacy rejection。
Clock/PackedNext legacy importer至少区分
`clock-package-private-identity-escape`、
`clock-package-transfer-captures-private-identity`、
`clock-package-family-not-clock-indexing`、
`packed-next-builder-result-mismatch`；Park exactness区分
`park-source-payload-mismatch` 与 `park-resumption-type-mismatch`；contract
term区分 kind/instantiation/scope/cycle、terminal bind、return-flow、Q stage
与 Lambda key错误；context/exhaustiveness另外区分
`delegates-outside-handler-clause`、
`unknown-contract-computation-variant` 与 `unknown-path-outcome-v2`。V1
decoder看到 V2 field/tag必须产生
`unsupported-contract-schema-version`，不能忽略或回填。
closed Q/source/u32 exactness另固定 `unknown-obligation-stage`、
`unknown-obligation-variant`、`term-actual-source-unavailable` 与
`wire-u32-out-of-range`。
本轮 exactness diagnostics另外固定 summary/HOF、ContractRef/T-App、
Handler/Forward、Park/Packed/runtime各自的稳定 id：
`semantic-summary-not-normalized`、`hof-complete-path-observer-mismatch`、
`imported-function-export-mismatch`、`local-function-ref-unresolved`、
`application-arity-mismatch`、`application-argument-type-mismatch`、
`handler-disposition-escapes-scope`、`forward-operation-mismatch`、
`forward-route-mismatch`、`forward-application-arity-type-mismatch`、
`park-generation-protocol-mismatch`、`park-disposition-protocol-mismatch`、
`park-required-phase-mismatch`、`park-owner-outlives-missing`、
`clock-package-path-observer-mismatch`、`packed-next-control-protocol-mismatch`、
`packed-next-pack-phase-mismatch` 与 `packed-next-runtime-protocol-mismatch`。

与 hidden $L$ 相同，surface `(A) -> B ! ε` 先 elaboration为
$A arrow.r.long^(?C) B$，不是把未显示字段填成 `pure/same`。有 initializer
的 declaration求解 $?C$；高阶 input binder把未由 annotation约束的字段
泛化为 rigid contract parameter，并创建单一 `AppliedContractV2`，把调用时
用到的 row/world/flow/result/suspension/summary/usage/phase、$Q/Lambda$ 通过
同一 `InvokeV2`/`PathBindV2` computation投影进 enclosing function contract。
Declaration boundary不能留下未解 metavariable，interface必须序列化 solved
contract或其显式 quantified binder。

Core lambda binder携带显式、已 elaborated 的 annotation：
