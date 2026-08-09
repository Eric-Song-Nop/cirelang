#import "../shared.typ": *

== Handler schema 与安装点递归

```text
check_handler(ctx, effect, clauses):
  (return_clause, operation_clause_map) =
    partition_exact_handler_clauses(effect, clauses)
  require exactly one return clause
  require domain(operation_clause_map) == operations(effect)
  require no duplicate or extra operation clause
  (A, B) = resolve_handler_answer_types(effect, return_clause)
  Φsym = fresh_symbolic_required_phase()
  Πenv = provenance_fv(clauses, ctx.Θ)
  χenv = capture_fv(clauses, ctx.Θ)
  owner = current_owner(ctx)
  require owner_authorized(ctx.Φ, owner)
  require env_boundary_safe(
    free_values(clauses), ctx.Θ, OwnerStorage(owner))
  Sinst = fresh_symbolic_installation_stack()
  pinst = fresh_symbolic_prompt_slot()
  ainst = fresh_symbolic_entry_selector(effect)
  require top_prompt(Sinst) == (pinst, ainst)
  schema_ctx =
    ctx.with_prompts(Sinst)
       .with_route_stage(HandlerInstall)
  shape = { input = A, answer = B, owner = owner,
            phase_symbol = Φsym,
            env_provenance = Πenv, env_captures = χenv,
            installation_stack = Sinst,
            installation_prompt = pinst,
            handled_entry = ainst }
  (Creturn, Areturn) = check_return_clause_schema_v2(
    schema_ctx, shape, return_clause)
  schemas = {}
  application_ledger = Areturn
  for op in operations(effect):
    clause = operation_clause_map[op]
    (schemas[op], Aop) =
      check_clause_schema_v2(
        schema_ctx, shape, op.signature, clause,
        fresh_application_slots_after(application_ledger))
    require disjoint(application_slots(application_ledger),
                     application_slots(Aop))
    application_ledger += Aop
  C0 = aggregate_handler_v2(
    applications = application_ledger,
    return_computation = Creturn,
    clause_computations = schemas)
  C0.required_phase = solve_and_generalize_required_phase(
    Φsym, Creturn.constraints ∪ schemas.constraints)
  C = attach_handler_env(C0, Πenv, χenv)
  P = resolve_sealed_handler_policy(effect, clauses)
  require PolicyOK(P) and Origin(P) == shape.owner
  return HandlerResult(
    type = HandlerTemplate[effect, shape.owner, A, B,
                           C.residual_row, (Sinst, pinst, ainst).C, P],
    contract_template = (Sinst, pinst, ainst).C,
    policy = P,
    provenance = Owner(shape.owner),
    captures = χenv,
    clause_schemas = schemas)

check_return_clause_schema_v2(ctx, handler_shape, clause):
  Θentry = fresh_symbolic_temporal_context()
  return_ctx = import_handler_env(
    ctx.with_phase(handler_shape.phase_symbol).with_Θ(Θentry),
    handler_shape.env_provenance,
    handler_shape.env_captures,
    handler_shape.owner)
  arg = fresh_rigid_argument_summary(handler_shape.input)
  body = check_body_flow(
    bind(return_ctx, clause.parameter,
         handler_shape.input, arg.π, arg.χ),
    clause.body, handler_shape.answer)
  return abstract_return_contract_v2(
    Θentry, arg, body,
    unresolved_route_stage = HandlerInstall), body.applications
    universally quantified over
      handler_shape.installation_stack,
      handler_shape.installation_prompt,
      handler_shape.handled_entry, Θentry and arg

check_clause_schema_v2(
    ctx, handler_shape, op_sig, clause, application_slot_supply):
  skolems = fresh_skolems(op_sig.type_parameters)
  opσ = instantiate(op_sig, skolems)
  arg_summaries =
    fresh_rigid_argument_summaries(opσ.parameters)
  params = bind_parameters(opσ.parameters, arg_summaries)
  Θentry = fresh_symbolic_temporal_context()
  p = handler_shape.installation_prompt
  clause_ctx = import_handler_env(
    ctx.with_phase(handler_shape.phase_symbol).with_Θ(Θentry),
    handler_shape.env_provenance,
    handler_shape.env_captures,
    handler_shape.owner)
  κ = fresh_abstract_site_contract(
    stable_site_slot = fresh_site_slot(),
    installation_prompt = p,
    entry = handler_shape.handled_entry,
    operation = opσ.resolved_selector,
    entry_world = Θentry,
    first_transition = opσ.resume_transition,
    instantiated_signature = opσ,
    call_obligations = stageCall(opσ.site_obligations),
    install_obligations = stageHandlerInstall(opσ.site_obligations),
    secondary_contract = opσ.secondary_contract,
    actual_argument_summaries = arg_summaries,
  )

  if clause.mode in {once, ctl}:
    q = clause_mode_budget(clause.mode)
    k = Resume[q, κ.D, opσ.result, handler_shape.answer,
               κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
    result = check_body_flow(
      clause_ctx + params + k:Open(q),
      clause.body, handler_shape.answer)
    require path_sensitive_usage(result, k) <= q
    result =
      disposition_complete_paths(
        result, k, disposition_binder, clause.mode)
  else if clause.mode == fun:
    k = hidden Resume[1, κ.D, opσ.result,
                      handler_shape.answer,
                      κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
    value_flow = check_body_flow(
      clause_ctx + params + k:Open(1),
      clause.body, opσ.result)
    normal_flow = tail_resume_each_normal_exit(
      k, value_flow, κ.answer_world)
    abort_flow = abort_scope_exit_each_abort(
      value_flow, k, κ.D.cleanup)
    result = merge_path_contracts(normal_flow, abort_flow)
    require exactly_one_hidden_tail_resume_per_normal_exit(result, k)
  else if clause.mode == abort:
    k = hidden Resume[1, κ.D, opσ.result,
                      handler_shape.answer,
                      κ.Π, κ.χ, handler_shape.owner]
    disposition_binder = bind_clause_disposition(
      fresh_suffix_live_slot(), κ.site_slot, type(k))
    body_flow = check_body_flow(
      clause_ctx + params + k:Open(1),
      clause.body, handler_shape.answer)
    result = append_hidden_disposition_on_every_exit(
      body_flow, k, κ.D.cleanup)
    require every normal result world == κ.answer_world

  require clause_contract(result) refines opσ.contract
  require every Delegates(κf) path in result carries exactly
    OpenToForwardedExclusive(k, κf.site_slot, κf.continuation)
  wire_computation = serialize_contract_computation_v2(
    clause_contract(result),
    disposition_substitution = {
      k -> LegacySlotRefV2(
        SlotRefV1(SuffixLive, disposition_binder.slot)) },
    allowed_delegates = OnlyThisHandlerClause,
    application_ledger = result.applications)
  require every InvokeV2 in wire_computation resolves uniquely in
    result.applications
  return ClauseComputationV2(
    operation = opσ.resolved_selector,
    disposition_binder = disposition_binder,
    computation = wire_computation), result.applications
    universally quantified over
      handler_shape.installation_stack,
      handler_shape.handled_entry, skolems, p and κ

disposition_complete_paths(result, k, disposition_binder, mode):
  return map_paths(result, path =>:
    match path:
      Delegates(κf):
        require disposition_binder.type == type(k)
        require path.disposition_evidence ==
          OpenToForwardedExclusive(k, κf.site_slot, κf.continuation)
        require path.usage_context[k] == Forwarded(κf)
        preserve path
      Returns | Aborts | Transfers(_):
        require path.usage_context[k] is not Forwarded(_)
        if mode == once:
          close_or_explicitly_park_on_exit(path, k)
        else:
          synchronous_resume_or_finalize_on_exit(path, k))

install_handler(
  prompt_stack, prompt, handler, policy, handled_entry, sites, body_flow):
  installed = instantiate_handler_contract(
    handler.contract_template,
    prompt_stack, prompt, handled_entry)
  require every ResolveAtInstallation route in installed was resolved
    against prompt_stack to the nearest exact-entry prompt or RootOfEntry
  normal_summaries = []
  answer_worlds = []
  semantic_paths = []
  delegation_evidence = []
  outcomes = {}
  accumulate_body_path(path):
    match path:
      Returns(Θ, π, χ):
        ret = apply_return_contract(
          installed.return_contract, π, χ, Θ)
        normal_summaries += (ret.π, ret.χ)
        answer_worlds += ret.Θ
        semantic_paths += ret.summary
      Aborts:
        outcomes += Aborts
      Transfers(P):
        require preserves_park_contract(prompt, installed, policy, P)
        outcomes += Transfers(P)
  accumulate_continuation_path(path, D):
    match path:
      Returns(Θ, π, χ):
        ret = apply_continuation_contract(D, π, χ, Θ)
        normal_summaries += (ret.π, ret.χ)
        answer_worlds += ret.Θ
        semantic_paths += ret.summary
      Aborts:
        outcomes += Aborts
      Transfers(P):
        require preserves_park_contract(prompt, installed, policy, P)
        outcomes += Transfers(P)
  for path in body_flow.flow:
    accumulate_body_path(path)
  for κ in sites:
    require κ.installation_prompt == prompt
    require κ.route == prompt
    wire_clause = instantiate installed matching ClauseComputationV2 with
      operation skolems, prompt, κ.entry_world, κ
    internal_disposition = disposition_for(κ)
    clause_scope = resolve_clause_disposition_binder(
      binder = wire_clause.disposition_binder,
      required_namespace = SuffixLive,
      expected_site_slot = κ.site_slot,
      expected_type = type(internal_disposition),
      internal_token = internal_disposition)
    require clause_scope is exactly {
      SlotRefV1(SuffixLive,
        wire_clause.disposition_binder.slot)
        -> internal_disposition }
    clause = import_contract_computation_v2(
      wire_clause.computation,
      application_scope = installed.applications,
      return_scope = ∅,
      delegates_scope =
        HandlerClauseOnly(wire_clause.disposition_binder),
      disposition_scope = clause_scope)
    require every clause-level disposition evidence/usage reference
      resolves uniquely in clause_scope and none escapes that
      ClauseComputationV2; nested SuffixContractV2 live bindings use their
      own lexical scopes
    discharge imported handler environment is valid
      at κ.entry_world
    if κ.instantiated_signature.mode == ctl:
      discharge DuplicableEnv(κ.Π, κ.χ)
      discharge EnvValidAt(κ.Π, κ.χ, MultiShot)
      discharge ReplayableCleanup(κ.D.cleanup, κ.Π, κ.χ)
      discharge WorldForkSafe(κ.D.world)
    require κ.call_obligations is the sealed discharged evidence
      produced at this exact call or forward node
    require κ.install_obligations.instantiation_key ==
      (stageHandlerInstall(
         κ.instantiated_signature.obligation_ids),
       κ.actual_argument_summaries, κ.entry_world)
    discharge every obligation in κ.install_obligations using
      policy, κ.actual_argument_summaries, κ.entry_world
    for secondary in κ.secondary_sites.sites:
      require secondary.route ==
        resolve_route_at_installation(
          secondary.route_selector, prompt, prompt_stack)
      preserve secondary unless secondary.route == prompt
    for Async.await:
      derive task region from κ.actual_argument_summaries
      check install-await-site(κ, policy)
    for path in clause.flow:
      match path:
        Returns(_, π, χ):
          normal_summaries += clause.result_summary(
            κ.actual_argument_summaries, κ.Π, κ.χ,
            handler.env_provenance, handler.captures)
          answer_worlds += clause.answer_world
          semantic_paths += clause.summary
        Aborts:
          outcomes += Aborts
        Transfers(P):
          require clause owns the disposition recorded by P
          outcomes += Transfers(P)
        Delegates(κf):
          require κf.instantiated_signature ==
            κ.instantiated_signature
          require path.disposition_evidence.inner_disposition ==
            internal_disposition
          require path.disposition_evidence ==
            OpenToForwardedExclusive(
              internal_disposition, κf.site_slot, κf.continuation)
          require path.usage_context[
            internal_disposition] == Forwarded(κf)
          forward_evidence = derive_forward_residual_evidence(
            installed, prompt_stack, prompt, κf)
          require attributed_ok(
            forward_evidence.attributed_demand,
            forward_evidence.attributed_suspension)
          public_flow = consume_delegation(
            internal_path = path,
            routed_site = κf,
            original_continuation = κ.D)
          require public_flow ==
            project_public_continuation_flow(κ.D, κf)
          delegation_evidence += sealed_forward_evidence(
            κ, κf, public_flow, forward_evidence)
          for public_path in public_flow:
            require public_path is FlowPathV1
            accumulate_continuation_path(public_path, κ.D)
  require all answer_worlds are equal
  if normal_summaries is not empty:
    (πo, χo) = join(normal_summaries)
    outcomes += Returns(the unique answer_world, πo, χo)
  δout = handle_summary(
    body_flow.summary, handled_entry, installed,
    policy, sites, body_flow.flow, semantic_paths)
  require no outcome is Delegates
  Δhandler = instantiate_handler_residual(
    installed, prompt_stack, prompt,
    sites, body_flow, delegation_evidence)
  return sealed evidence(
    outcomes = outcomes,
    semantic_summary = δout,
    handler_residual = Δhandler)

eliminate_entry_with_contract(
  prompt, handler, body, entry, sites, install):
  (Δhere, Δouter) =
    partition(body.attributed_demand,
              demand.route == prompt)
  require every primary site in Δhere is in sites
  Δhandler = install.handler_residual
  Δout = union(Δouter, Δhandler)
  εout = eraseDemand(Δout)
  sout = handle_install_suspension(
    body.suspension, Δhere, install)
  require attributed_ok(Δout, sout)
  return body with
    type = handler.answer_type
    flow = install.outcomes
    row = εout
    attributed_demand = Δout
    suspension = sout
    summary = install.semantic_summary
    typed_core =
      fresh_prompt_node(
        prompt, handled_node(prompt, body.typed_core, handler))
```

`Lambda` branch保留 definition $Theta$ 以计算 lexical captures，但在检查 body前
必须用 fresh $S_"call"$ 替换 ambient prompt stack并把 route stage设为 `Call`。
`abstract_lambda_call_context` 随后把该 symbolic stack上的 route统一封成
`ResolveAtCall` 并量化 $S_"call"$；任何来自 `ctx.prompts` 的 concrete prompt
都会被拒绝。该步骤与 T-Lambda-Paths 的 $S_f$ 是同一算法，不是 optimizer。
随后唯一一次 `abstract_parametric_flow` 遍历完整 flow：Returns paths共同产生
normal world/result projection，Aborts/Transfers产生 bottom normal projection但
仍贡献参数相关 BoundarySafe/StableAcross/Outlives obligation；最终 $Q$ 是所有
path obligation的 normalized union。存在 Returns时也不得跳过 terminal paths，
`abstract_contract_computation_v2` 把这些 path-local row/demand/suspension/
summary/usage/phase/Q/$Lambda$ 一起写入 `LiteralPathsV2` 或基于同一
`AppliedContractV2` 的 Invoke/PathBind term；不存在独立 field projection。
`abstract_flow` 只保存 outcome projection，不能替代这一步 obligation
abstraction或原子 application ledger。

Handler definition只捕获 `Πenv/χenv`，不捕获 definition-site prompt stack。
`with_route_stage(HandlerInstall)` 令 schema内命中 symbolic handled entry的
site指向 $p_"inst"$，其余普通 return/clause residual site编码为
`ResolveAtInstallation`，不提前降为 definition-stack prompt或 root。
`(Sinst,pinst,ainst).C` 在每次 `Handle` 处用 actual
`(prompt_stack,prompt,handled_entry)` 一次实例化；同一个 first-class handler
在两种 outer stack安装会得到各自唯一的 residual routes。安装后才可消去
这些 route selector，`install_handler` 拒绝仍含未解析 installation route
或来自 definition stack的 concrete prompt。
同一次 instantiation还必须消费每个
`ClauseComputationV2.disposition_binder`：
`resolve_clause_disposition_binder` 逐字段检查 exact site/type与 lexical scope，
只建立一个 `SuffixLive(binder.slot) → disposition_for(κ)` 映射，然后才导入
flow/evidence/usage。后续 Delegates检查只能使用该 resolved token；再次独立
调用 `disposition_for(κ)`、按 slot数字猜 token或让该 disposition ref跨
clause scope逃逸都不是合法 importer实现；nested `SuffixContractV2` 的其他
live slot仍按各自 lexical scope独立验证。

`analyze_sites` 对 local typed ANF结构递归；遇到 function call时读取并 compose
callee interface中的 finite $Lambda$，而不是要求内联源码。Recursive SCC
必须给 finite annotated site schema；worklist按
`(callee, entry, answer-shape)` memoize，禁止无限展开。
