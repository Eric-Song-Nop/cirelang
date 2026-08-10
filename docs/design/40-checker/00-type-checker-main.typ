#import "../shared.typ": *

= 算法化 type checker

== 返回对象

```text
CheckResult {
  type
  flow: nonempty set of
      Returns(temporal_context_out, provenance, result_captures)
      | Aborts
      | Transfers(ParkContractV2)
  provenance
  residual_row
  attributed_demand
  attributed_suspension
  semantic_summary
  result_captures
  usage_context_out
  latent_site_evidence
  typed_core
  evidence
}
```

`type` 是所有 `Returns` entries 的共同 supertype；provenance/capture/world
保存在各 return entry并在需要单一 normal结果时 join。`Aborts` 与
`Transfers` entries仍共享 row、attributed demand、suspension、summary、
usage、typed Core与 site evidence。`Transfers` 额外保存 sealed
`ParkContractV2`。集合可以同时包含 return/abort/transfer；只有 set中确实有
`Returns` 才能读取 normal result，terminal entries永远不会被存在一个
normal branch的事实抹掉。

每个 `CheckResult` 还维持
`residual_row == eraseDemand(attributed_demand)`；所有 row elimination都先
partition demand，再重算 public row。

`evidence` 保存：

- kind/row normalization；
- operation/handler contract refinement；
- temporal stability与 boundary checks；
- sealed/trusted policy witness；
- generative identity scope；
- phase gate；
- inserted finalize/park disposition；
- surface-to-Core origin。

== 互递归入口

```text
synth(ctx, expr) -> CheckResult
check(ctx, expr, expected_type) -> CheckResult
check_value(ctx, value) -> ValueResult
check_value_as(ctx, value, expected_type) -> ValueResult
check_body_flow(ctx, expr, expected_type) -> CheckResult
check_args(ctx, args, parameter_types) -> CheckResult
check_block(ctx, items) -> CheckResult
check_handler(ctx, effect, clauses) -> HandlerResult
check_return_clause_schema_v2(ctx, handler_shape, clause)
  -> (ContractComputationV2, [AppliedContractV2])
check_clause_schema_v2(
  ctx, handler_shape, operation_signature, clause, application_slot_supply)
  -> (ClauseComputationV2, [AppliedContractV2])
analyze_sites(typed_core, delimiter_entry, installation_prompt,
              answer_contract) -> SiteContracts
install_handler(prompt_stack, installation_prompt, handler_contract, policy,
                handled_entry, site_contracts, body_flow)
  -> InstallEvidence
```

`ctx` 包含：

```text
K, I, Φ, Ω, Θ
prompt stack: fresh installation prompts with handled entry
route stage: Call normally; HandlerInstall only in handler schemas
expected answer type
current Owner is an explicit field of Φ
constraint worklists
```

== 主递归

每个 strict-position recursive call都经过同一个 path-bind combinator：

```text
strict_bind(result, typed_prefix, continue_return):
  prepared = map(result.flow, path =>:
    match path:
      Returns(Θ, π, χ, Ω):
        path
      Aborts | Transfers(_) | Delegates(_):
        compose_terminal_prefix(typed_prefix, path))
  continue = path =>:
    Returns(Θ, π, χ, Ω) = path
    continue_return(
      return_projection(result, path, Θ, π, χ, Ω))
  bound = PathBind(prepared, continue)
  return aggregate_check_result(
    bound, result.evidence,
    path_bind_evidence(typed_prefix, prepared, continue, bound))
```

`return_projection` 只暴露该 Returns path自己的 type/π/χ/Θ/Ω。
`prepared` 只给既有 terminal path附加已经执行的 typed prefix；
`PathBind` 的第二参数始终是 Returns→flow continuation，因此每个 terminal
prefix只 composition一次，也不会作为 continuation list再次展开。
`aggregate_check_result` 只在所有 path-local Q/R/usage/site检查完成后汇总
row、suspension与 summary evidence；汇总值绝不作为后续 strict context。
因此没有 `join_returns` 的 distributivity假设；terminal path除恰好一次
已执行 prefix composition外原样保留。
`check_args` 是从左到右的有限 fold；每个 argument都立刻经过
`strict_bind`，
若某一步没有 return path就立即返回已经执行的 argument prefix；若同时有
return与terminal path，只让 return entries继续检查后续 argument并保存
terminal entries。所以 site node中的 $Xi_k$ 恰好只来自可达、已类型化的
actual argument。

```text
resolve_route_for_stage(stage, prompts, entry):
  if stage == Call:
    return resolve_route_at_call(prompts, entry)
  if top_prompt(prompts).entry == entry:
    return InstallationPrompt(top_prompt(prompts).prompt)
  return ResolveAtInstallation(on_missing = RootOfEntry)

build_operation_path_algorithm(
  ctx, κ, a, o, sig, ra, call_evidence, install_obligations):
  require call_evidence is discharged for
    (sig.obligations, ra.argument_summaries, ctx.I, ra.Θ_out)
  require phase_allows(ctx.Φ, sig.required_phase)
  p = resolve_route_for_stage(
    ctx.route_stage, ctx.prompts, a)
  primary = Demand(κ, p, a, o, Primary)
  require sig.secondary_site_set.kind == Closed
  secondary = instantiate_secondary_sites(
    sig.secondary_site_set.sites,
    parent_site = κ,
    prompt_stack = ctx.prompts)
  Δ = union(ra.attributed_demand, {primary},
            secondary.attributed_demand)
  s = join(
    ra.suspension,
    request(demand_key(primary), sig.suspension),
    secondary.attributed_suspension)
  require attributed_ok(Δ, s)
  δ = ra.summary ⊗ secondary.semantic_summary
  require Allowed(ctx.Φ, eraseDemand(Δ), s, δ)
  record_site_node(
    site_slot = κ, route = p, entry = a, operation = o,
    instantiated_signature = sig,
    actual_argument_summaries = ra.argument_summaries,
    call_obligations = call_evidence,
    install_obligations = install_obligations,
    secondary_sites = secondary.site_evidence)
  if sig.mode == abort:
    require sig.world == abortive
    return single_path_result(
      Aborts, ra.Ω_out, Δ, s, δ,
      {primary} ∪ secondary.site_evidence)
  Θ = apply_transition(sig.world, ra.Θ_out)
  (π, χ) = sig.result_summary(
    ra.argument_provenance, ra.argument_captures)
  return single_path_result(
    Returns(Θ, π, χ), ra.Ω_out, Δ, s, δ,
    {primary} ∪ secondary.site_evidence)

instantiate_call_result_paths(
  rf, ra, contract, call_flow, Ω, Δ, s, Λinstall):
  for path in call_flow:
    match path:
      Returns(transition, result_transformer):
        emit Returns(
          apply_transition(transition, ra.Θ_out),
          apply_result_transformer(
            result_transformer, ra.π, ra.χ))
      Aborts:
        emit Aborts
      Transfers(P):
        emit Transfers(instantiate_park_contract(P, ra))
  return aggregate_call_paths(
    rf, ra, emitted paths, Ω, Δ, s, Λinstall)

synth(ctx, e):
  match e:
    Var(x):
      return lift_value_to_check_result(
        lookup_available(ctx.Θ, x),
        row = ∅, suspension = direct(NoSuspend),
        summary = pure, Θ_out = ctx.Θ, Ω_out = ctx.Ω)

    Lambda(x, A, B, Φrequired, body):
      require well_formed(A, B, Φrequired)
      symbolic = fresh_rigid_usage_and_argument_summary(A)
      Scall = fresh_symbolic_prompt_stack()
      call_ctx =
        ctx.with_prompts(Scall).with_route_stage(Call)
      rb_symbolic = check_body_flow(
        bind(call_ctx.with_phase(Φrequired).with_usage(symbolic.Ω),
             x, A, symbolic.π, symbolic.χ),
        body, B)
      rb = abstract_lambda_call_context(
        rb_symbolic, Scall,
        unresolved_route_stage = Call)
      require rb contains no concrete prompt selected from ctx.prompts
      χclosure = capture_fv(body - x, ctx.Θ)
      Πclosure = provenance_fv(body - x, ctx.Θ)
      u = latent_usage(symbolic.Ω, rb.Ω_out)
      Λ = abstract_sites(rb.typed_core, x)
      require many_call_safe(Πclosure, u, χclosure)
      Fabs = abstract_parametric_flow(
        symbolic_call_stack = Scall,
        argument_provenance = symbolic.π,
        argument_capture = symbolic.χ,
        definition_world = ctx.Θ,
        parameter = x,
        complete_flow = rb.flow)
      require Fabs.flow_summary == abstract_flow(rb.flow)
      require Fabs.obligations == normalized_union(
        obligations_of_every_path(rb.flow))
      Cterm = abstract_contract_computation_v2(
        complete_flow = rb.flow,
        path_evidence = rb.path_evidence,
        obligations = Fabs.obligations,
        latent_sites = Λ)
      require observers(Cterm) == Fabs
      return value(function_contract_v2(
        binders = generalized_binders(symbolic, Fabs),
        applications = Cterm.applications,
        computation = Cterm,
        closure_environment =
          environment_ledger(Πclosure, χclosure, u)))

    App(f, arg):
      return strict_bind(synth(ctx, f), empty_prefix, rf =>:
        (A, contract, B) = instantiate_function(rf.type)
        require rf.type is FunctionTypeV2(
          parameter = A, result = B, contract = contract.ref)
        require resolve_contract_ref(contract.ref) has exact
          FunctionContractKindV2(
            parameter_type = A,
            result_type = B,
            visible_row = visible_row(contract))
        strict_bind(
          check(context_of(rf), arg, A), prefix(rf), ra =>:
            application = build_applied_contract_v2(
              contract_ref = contract.ref,
              callee_summary = value_summary(rf),
              actual_arguments = [value_summary(ra)],
              substitution = solve_complete_substitution(contract, rf, ra),
              entry_world = ra.Θ_out,
              origin = source_origin(f))
            require application.callee_summary.type ==
              FunctionTypeV2(A, B, application.contract)
            require application is atomic and
              no_field_has_independent_actuals(application)
            invoked = InvokeV2(application.application_slot)
            require phase_allows(ctx.Φ, phase(invoked))
            Qcall = instantiate(
              stageCall(obligations(invoked)), application)
            discharge(Qcall)
            Qinstall = instantiate(
              stageHandlerInstall(obligations(invoked)), application)
            Ω3 = apply_usage(ra.Ω_out, usage(invoked))
            (Δcall, scall, Λinstall) =
              instantiate_latent_contract(
                row(invoked), suspension(invoked),
                latent_sites(invoked), application,
                current_prompt_stack = ctx.prompts)
            require eraseDemand(Δcall) ==
              row(invoked)
            require attributed_ok(Δcall, scall)
            preserve_until_install(Qinstall, Λinstall)
            call_flow = evaluate_contract_computation(
              invoked, application)
            return instantiate_call_result_paths(
              rf, ra, application, call_flow, Ω3,
              Δcall, scall, Λinstall)))

    Let(x, first, rest):
      return strict_bind(
        synth(ctx, first), empty_prefix, r1 =>:
          strict_bind(
            synth(bind(context_of(r1), x, r1.type, r1.π, r1.χ),
                  rest),
            prefix(r1), r2 =>:
              return drop_flow_binder(
                compose_sequence_path(r1, r2), x)))

    Delay(clock, body):
      ι = resolve_clock_identity(clock)
      Φsym = fresh_symbolic_required_phase()
      inner = synth(push_lock(ctx.with_phase(Φsym), ι), body)
      require inner.flow == {Returns(_)}
        or diagnose "delay body must have one normal payload and no terminal side path"
      require inner.Ω_out == ctx.Ω
      require inner.row == ∅
      require grade(inner.suspension) == NoSuspend
      require locks(inner.Θ_out) == locks(push_lock(ctx.Θ, ι))
      require TemporalPure(inner.summary)
      require TemporalStable(ι, free_values(body), ctx.Θ)
      χdelay = capture_fv(body, ctx.Θ)
      require CrossWorldSafe(ι, χdelay)
      require Shareable(inner.type)
      require TemporalPayloadSafe(
        ι, inner.type, inner.π, inner.χ, χdelay)
      Φforce = solve_and_generalize_required_phase(
        Φsym, inner.phase_constraints)
      L = LaterContract(
        inner.π, inner.χ, inner.summary, Φforce)
      return CheckResult(
        type = Next[ι, inner.type, L],
        flow = {Returns(ctx.Θ, Stable, χdelay)},
        provenance = Stable,
        residual_row = ∅,
        attributed_demand = ∅,
        attributed_suspension = direct(NoSuspend),
        semantic_summary = δ_alloc,
        result_captures = χdelay,
        usage_context_out = ctx.Ω)

    Advance(value):
      Next[ι, A, L] = shape_type_without_availability(value)
        or diagnose "advance expects a Next value"
      (Θ0, lock_ι, Θ1) = split_right(ctx.Θ, ι)
        or diagnose "no matching tick"
      rv = check_value_as(
        ctx.with_Θ(Θ0), value, Next[ι, A, L])
      require phase_allows(ctx.Φ, L.required_phase)
      require Allowed(ctx.Φ, ∅, NoSuspend, L.summary)
      require L.payload_captures ⊆ rv.χ
      return CheckResult(
        type = A,
        flow = {Returns(ctx.Θ, L.payload_provenance, rv.χ)},
        provenance = L.payload_provenance,
        residual_row = ∅,
        attributed_demand = ∅,
        attributed_suspension = direct(NoSuspend),
        semantic_summary = L.summary ⊗ δ_force,
        result_captures = rv.χ,
        usage_context_out = ctx.Ω)

    Operation(receiver, op, args):
      sig = instantiate_fresh(resolve_operation(receiver, op))
      a = row_entry(receiver)
      o = sig.resolved_selector
      κ = fresh_site_slot()
      args_result = check_args(ctx, args, sig.parameters)
      return strict_bind(
        args_result, evaluated_arg_prefix, ra =>:
          build_operation_path_algorithm(
            ctx, κ, a, o, sig, ra,
            call_evidence = discharge_and_seal(instantiate(
              stageCall(sig.obligations),
              ra.argument_summaries, ctx.I, ra.Θ_out)),
            install_obligations = instantiate(
              stageHandlerInstall(sig.obligations),
              ra.argument_summaries, ctx.I, ra.Θ_out)))

    Forward(current_site, outer_prompt, receiver, op, args):
      κ = require_current_primary_site(current_site)
      k = require_open_disposition_for(κ, ctx.Ω)
      require tail_position_in_clause()
      require κ.entry == resolve_exact_entry(receiver)
      require κ.operation == resolve_exact_operation(receiver, op)
      require strictly_outer_live_prompt(
        ctx.prompts, κ.installation_prompt, outer_prompt, κ.entry)
      sig = κ.instantiated_signature
      arg_paths = check_args(ctx, args, sig.parameters)
      forwarded_paths = []
      forward_evidence = []
      for r in arg_paths.returning_paths:
        require r.Ω_out[k] is Open(_)
        call_obligations = discharge_and_seal(instantiate(
          stageCall(sig.obligations), r.argument_summaries,
          ctx.identities, r.Θ_out))
        install_obligations = instantiate(
          stageHandlerInstall(sig.obligations),
          r.argument_summaries, ctx.identities, r.Θ_out)
        κf_header = prepare_forward_site(
          stable_site_slot = κ.site_slot,
          installation_prompt = outer_prompt,
          entry = κ.entry,
          operation = κ.operation,
          continuation = κ.continuation,
          entry_world = r.Θ_out,
          actual_argument_summaries = r.argument_summaries,
          instantiated_signature = sig,
          call_obligations = call_obligations,
          install_obligations = install_obligations)
        require sig.secondary_site_set.kind == Closed
        secondary = instantiate_secondary_sites(
          sig.secondary_site_set.sites,
          parent_site = κf_header,
          prompt_stack = ctx.prompts)
        require attributed_ok(
          secondary.attributed_demand,
          secondary.attributed_suspension)
        κf = seal_forward_site(
          κf_header,
          secondary_sites = secondary.contract_set)
        primary = Demand(
          κf.site_slot, κf.installation_prompt, κf.entry,
          κf.operation, Primary)
        primary_suspension =
          request(demand_key(primary), sig.suspension)
        Δf = union(r.attributed_demand, {primary},
                   secondary.attributed_demand)
        sf = join(
          r.suspension, primary_suspension,
          secondary.attributed_suspension)
        require attributed_ok(Δf, sf)
        δf = r.summary ⊗ secondary.semantic_summary
        require phase_allows(ctx.Φ, sig.required_phase)
        require Allowed(ctx.Φ, eraseDemand(Δf), sf, δf)
        Ωf = forward_disposition(r.Ω_out, k, κf)
        require type(k) == ResumeTypeRefV2(value = ResumeTypeV2(
          usage = quantity_for_mode(sig.mode),
          continuation = κf.continuation,
          argument = sig.result,
          answer = expected_clause_type,
          live_provenance = continuation_provenance(κf.continuation),
          live_capture = continuation_capture(κf.continuation),
          owner = continuation_owner(κf.continuation)))
        forward_contract_v2 = ForwardContractV2(
          site_slot = κf.site_slot,
          route = InstallationPromptV1(outer_prompt),
          entry = κf.entry,
          operation = κf.operation,
          continuation = κf.continuation,
          entry_world = LegacyWorldExprV2(r.Θ_out),
          actual_argument_summaries =
            value_summaries_v2(κf.actual_argument_summaries),
          instantiated_signature = signature_v2(sig),
          call_obligation_ids = ids(call_obligations),
          install_obligation_ids = ids(install_obligations),
          secondary_sites = κf.secondary_sites,
          origin = source_origin(current_site))
        record_forward_node(
          site_contract = forward_contract_v2,
          stable_site_slot = κf.site_slot,
          previous_prompt = κ.installation_prompt,
          routed_prompt = κf.installation_prompt,
          actual_argument_summaries = κf.actual_argument_summaries,
          instantiated_signature = κf.instantiated_signature,
          call_obligations = κf.call_obligations,
          install_obligations = κf.install_obligations,
          primary = primary,
          secondary_sites = κf.secondary_sites,
          usage_context_out = Ωf)
        disposition_evidence = seal_forward_disposition_evidence(
          inner_disposition = k,
          original_site = κ,
          forward_contract = forward_contract_v2,
          input_usage = r.Ω_out,
          output_usage = Ωf,
          continuation_transfer = ExclusiveToForwardContract)
        forwarded_paths += PathContractV2(
          outcome = DelegatesV2(
            forward_contract = forward_contract_v2,
            disposition_evidence = disposition_evidence),
          residual_row = eraseDemand(Δf),
          attributed_demand = Δf,
          suspension = sf,
          semantic_summary = δf,
          usage = usage_exprs_v2(Ωf),
          required_phase = join_required_phase(
            Action, sig.required_phase),
          ParametricObligations =
            obligations_v2(call_obligations, install_obligations),
          LatentSites = latent_sites_v2(κf))
        forward_evidence +=
          (Δf, sf, δf, Ωf, {primary} ∪ secondary.site_evidence)
      flow = union(arg_paths.terminal_paths, forwarded_paths)
      evidence = aggregate_path_evidence(
        flow, arg_paths.evidence, forward_evidence)
      return ClauseCheckResult(
        type = expected_clause_type,
        flow = flow,
        provenance = bottom,
        residual_row = eraseDemand(evidence.attributed_demand),
        attributed_demand = evidence.attributed_demand,
        attributed_suspension = evidence.attributed_suspension,
        semantic_summary = evidence.semantic_summary,
        result_captures = bottom,
        usage_context_out = evidence.usage_context_out,
        latent_site_evidence = evidence.latent_site_evidence)

    Handle(handler, optional_cap_binder, body):
      rh = check_value(ctx, handler)
      require rh.type has shape
        HandlerTemplate[F, ρh, A, B, εh, (S, prompt, entry).Ch, Ph]
      p = fresh_prompt()
      if optional_cap_binder:
        require handler_origin_ok(ctx.Φ, rh.origin_owner)
        ι = fresh_identity(rh.effect, rh.origin_owner)
        a = Named(ι, rh.effect)
        ctxι = ctx.extend_identity(ι).add_authority(a)
                  .push_prompt(p, a)
                  .bind(
                    optional_cap_binder,
                    Cap[ι, rh.effect],
                    Region(rh.origin_owner),
                    captures = {ι})
        require phase_allows(ctxι.Φ, rh.required_phase)
        rb = check_body_flow(
          ctxι, body, rh.handled_input,
          core_prefix =
            let optional_cap_binder = capref(ι))
        sites = analyze_sites(
          rb.typed_core, a, p, rb.answer_contract)
        install = install_handler(
          ctxι.prompts, p, rh, rh.policy, a, sites, rb)
        result = eliminate_entry_with_contract(
          p, rh, rb, a, sites, install)
        require no_open_private_disposition(ι, result.Ω_out)
        result.Ω_out = hide_identity_usage(result.Ω_out, ι)
        result.flow = drop_flow_binder(
          result.flow, optional_cap_binder)
        require no_escape_in_flow_evidence(
          ι, result.row, result.attributed_demand, result.suspension,
          result.summary, result.Ω_out)
        for return in returns(result.flow):
          require no_escape(
            ι, result.type, return.π,
            result.row, result.attributed_demand,
            result.summary, return.χ)
          return.Θ_out = hide_identity(return.Θ_out, ι)
      else:
        require phase_allows(ctx.Φ, rh.required_phase)
        a = Anon(rh.effect)
        ctxp = ctx.push_prompt(p, a)
        rb = check_body_flow(ctxp, body, rh.handled_input)
        sites = analyze_sites(
          rb.typed_core, a, p, rb.answer_contract)
        install = install_handler(
          ctxp.prompts, p, rh, rh.policy, a, sites, rb)
        result = eliminate_entry_with_contract(
          p, rh, rb, a, sites, install)
      return result

    Resume(k, value):
      require Ω[k] == Open(q)
      rv = check_value_as(ctx, value, resume_argument(k))
      require phase_allows(ctx.Φ, continuation(k).required_phase)
      Θ2 = apply_transition(continuation(k).full_world, ctx.Θ)
      Ω2 = resume_state(Ω, k, q)
      (πB, χB) = continuation(k).answer_summary(rv)
      return CheckResult(
        type = continuation(k).answer_type,
        flow = {Returns(Θ2, πB, χB)},
        provenance = πB,
        residual_row = continuation(k).residual_row,
        attributed_demand = continuation(k).attributed_demand,
        attributed_suspension = continuation(k).suspension,
        semantic_summary =
          continuation(k).summary ⊗ δ_resume,
        result_captures = χB,
        usage_context_out = Ω2)

    Park(source, owner, k):
      require ctx.Ω[k] == Open(1)
      A = resume_argument(k)
      B = resume_answer(k)
      require source : CompletionSource[ρ, A]
      require owner : Owner[ρ]
      require phase_allows(ctx.Φ, Action)
      require owner_authorized(ctx.Φ, owner, ρ)
      Dk = continuation(k)
      require outlives(Dk.owner_region, ρ)
      require suspension_stable(
        ρ, Dk.summary, Dk.provenance_live, Dk.captures_live)
      require owner_bound_parking(ρ, Dk)
      park_site = fresh_site_slot()
      claim_cell_slot = fresh_claim_cell_slot()
      (runtime_ticket, runtime_claim_cell, port,
       source_contract, port_contract) =
        seal_completion(source, owner, k, claim_cell_slot)
      require port : CompletionPort[ρ, A]
      suspension = ownerBound(park_site, ρ, MaySuspend)
      require Allowed(
        ctx.Φ, ∅, suspension, δpark)
      resumption = ResumeTypeV2(
        usage = Once,
        continuation = Dk,
        argument = A,
        answer = B,
        live_provenance = Dk.provenance_live,
        live_capture = Dk.captures_live,
        owner = Dk.owner_region)
      claim = GenerationCASV1(
        claim_cell_slot = claim_cell_slot,
        source_generation = ClaimTicketGeneration,
        completion_generation_gate = EqualCurrentGeneration,
        finalization_generation_gate =
          EqualCurrentGenerationOrOwnerRetireAuthority,
        completion_transition = UnclaimedToCompleted,
        finalization_transition = UnclaimedToFinalized,
        generation_transition = PreserveGeneration,
        failure_transition = NoStateChange)
      disposition = OneShotDispositionV2(
        continuation_site_slot = park_site,
        claim_cell_slot = claim_cell_slot,
        resumption = resumption,
        states = {Unclaimed, Completed, Finalized},
        completion_transition = UnclaimedToCompleted,
        finalization_transition = UnclaimedToFinalized)
      contract = ParkContractV2(
        site_slot = park_site,
        owner_slot = alpha_owner_slot(ρ),
        claim_cell_slot = claim_cell_slot,
        source = source_contract,
        completion_port = port_contract,
        claim = claim,
        disposition = disposition,
        required_phase = required_phase_for(Action, owner, ρ),
        origin = source_origin(source.park))
      require contract.source.value_type
        == contract.completion_port.value_type
        == contract.disposition.resumption.argument
      require contract.disposition.resumption.answer == Dk.answer_type
      require contract.disposition.resumption.continuation == Dk
      require contract.claim.claim_cell_slot
        == contract.claim_cell_slot
        == contract.completion_port.claim_cell_slot
        == contract.disposition.claim_cell_slot
      return transferring_flow(
        flow = {Transfers(contract)},
        residual_row = ∅,
        attributed_demand = ∅,
        suspension = suspension,
        summary = δpark,
        usage_context_out =
          transfer_disposition(
            ctx.Ω, k, ρ, runtime_ticket, runtime_claim_cell))

    Intrinsic(name, args):
      dispatch to the named syntax-directed procedure; in particular:
        PackNext(owner, builder) =>
          check_pack_next(ctx, owner, builder)
        TryOpenPackedNext(packed, body) =>
          check_try_open_packed_next(ctx, packed, body)
        DisposePackedNext(packed) =>
          check_dispose_packed_next(ctx, packed)
```

PackedNext的三个算法分支不从 surface type反推丢失的 existential。
它们与 serializer/importer共享同一 binder顺序、wire和 path observer：

```text
check_pack_next(ctx, owner_expr, builder):
  owner = check_value_as(ctx, owner_expr, Owner[ρ])
  Φpack = required_phase_for(Action, owner, ρ)
  require phase_allows(ctx.Φ, Φpack) and
    owner_authorized(ctx.Φ, owner, ρ)
  (ρc, owner_child, j, i, runner, handle, child_witness, Θc) =
    create_packed_frame(owner)
  δallocate = PackedAllocateSummaryV2(HostObservable, NoSuspend)
  δterminal_close =
    PackedTerminalCloseSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend), δallocate)
  require child_witness == ChildOwnerWitnessV2(
    parent = ρ, child = ρc, relation = DirectChild,
    sealed_origin = "cire.temporal:pack_next")
  Ic = ctx.I + Identity(j, FrameClock, ρc) + ClockView(i, j, ρc)
  L = infer_later_contract_v2(i, expected_payload(builder), builder)
  require later_contract_wf(L, i, expected_payload(builder))
  body_ctx = ctx.with_I(Ic).with_Θ(
    bind(extend_child_owner(Θc, owner_child),
         frame, Cap[j, FrameClock], Region(ρc), {j, i}))
  body = check_body_flow(
    body_ctx, builder, Next[i, expected_payload(builder), L])
  for path in body.flow:
    require pack_next_path_safe(
      ρc, j, i, handle, body.type.payload, L, path,
      path.evidence)
    expected_summary =
      if path is Returns then
        OrderedSummaryNF(δallocate, path.summary)
      else
        OrderedSummaryNF(
          δallocate, path.summary, δterminal_close)
    require Allowed(
      ctx.Φ, path.row, path.suspension, expected_summary)
  Sp = seal_packed_summary(i, body.type.payload, L, body.flow)
  wire = serialize_packed_next_package_v2(
    storage_owner = OwnerRef(ρ),
    child_owner_binder = QuantifiedOwnerBinderV1(
      owner_slot = slot(ρc)),
    owner_relation = child_witness,
    clock_binder = QuantifiedClockBinderV2(
      identity_slot = slot(j),
      clock_refinement = {
        clock_slot = slot(i), identity = ref(j)},
      family_witness = CanonicalFrameClockV2,
      owner = ref(ρc)),
    summary_binder = QuantifiedContractBinderV2(
      contract_slot = slot(Sp),
      kind = ClockPackageSummaryKindV2(
        clock = ClockRef(i), payload_type = body.type.payload)),
    body = Next[i, body.type.payload, L],
    control_protocol = canonical_packed_next_control_v2,
    sealed_origin = "cire.temporal:pack_next")
  imported = import_packed_next_package_v2(ctx.K, ctx.I, wire)
  require imported ==
    exists ρc. exists j. exists i. exists Sp.
      Next[i, body.type.payload, L]
  paths = map(body.flow, path =>
    seal_or_close_pack_path(
      allocate_summary = δallocate,
      terminal_close_summary = δterminal_close,
      owner, owner_child, ρc, j, i, runner, handle, wire, path))
  require every paired (body_path, packed_path) satisfies
    packed_path.tag == body_path.tag and
    packed_path.row == hide_private(body_path.row) and
    packed_path.attributed_demand ==
      hide_private(body_path.attributed_demand) and
    packed_path.suspension == body_path.suspension and
    packed_path.usage == hide_private(body_path.usage) and
    packed_path.required_phase == RequireBoth(
      hide_private(body_path.required_phase), Φpack) and
    packed_path.Q == hide_private(body_path.Q) and
    packed_path.Lambda == hide_private(body_path.Lambda) and
    packed_path.summary ==
      (if body_path is Returns then
        OrderedSummaryNF(δallocate, body_path.summary)
       else
        OrderedSummaryNF(
          δallocate, body_path.summary, δterminal_close)) and
    (body_path is Returns or packed_path.close_action == CloseChildOnce)
  require no_free_outward(paths, {ρc, j, i, L, Sp, owner_child})
  return aggregate_check_result(
    normalize(paths), body.evidence,
    packed_package_evidence(wire, imported, child_witness))

check_try_open_packed_next(ctx, packed_expr, body):
  packed = check_value_as(ctx, packed_expr, PackedNext[ρ, A])
  require phase_allows(ctx.Φ, Action)
  δacquire = PackedAcquireSummaryV2(HostObservable, NoSuspend)
  δrelease = PackedReleaseSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend),
                  OrderedSummaryNF(δacquire, δrelease))
  lost = AcquireLostNonePath(
    summary = δacquire, world = ctx.Θ,
    provenance = Stable, capture = ∅)
  won_paths = []
  when try_acquire_packed(packed) returns (lease, wire):
    package = import_packed_next_package_v2(ctx.K, ctx.I, wire)
    unpack package as (ρc, j, i, L, Sp, child_witness,
                       Next[i, A, L])
    require child_witness == DirectChild(ρ, ρc)
    (owner_child, frame, pending) =
      open_packed_runtime(packed, lease, wire)
    open_ctx = ctx
      .extend_owner(ρc, child_witness)
      .extend_identity(j, FrameClock, ρc)
      .extend_clock(i, paired_identity = j, owner = ρc)
      .extend_contract(Sp, ClockPackageSummaryKindV2(i, A))
      .bind(frame, Cap[j, FrameClock], Region(ρc), {j, i})
      .bind(pending, Next[i, A, L],
            summary_provenance(Sp), summary_capture(Sp))
    checked = check_body_flow(open_ctx, body, expected_body_type)
    for path in checked.flow:
      require packed_next_outward_safe(
        ρc, j, i, L, Sp, checked.type, path, path.evidence)
      expected_summary = OrderedSummaryNF(
        δacquire, path.summary, δrelease)
      require Allowed(
        ctx.Φ, path.row, path.suspension,
        expected_summary)
      won_paths += acquire_release_map_some_path(
        acquire_summary = δacquire,
        body_path = path,
        release_summary = δrelease,
        normalized_summary = expected_summary,
        release_action = ExactlyOnceRelease,
        hidden = {ρc, j, i, L, Sp, owner_child})
  paths = normalize({lost} ∪ won_paths)
  require summary(lost) == δacquire and
    every paired (body_path, won_path) satisfies
      won_path.tag == map_some_or_preserve_terminal(body_path.tag) and
      won_path.row == hide_private(body_path.row) and
      won_path.attributed_demand ==
        hide_private(body_path.attributed_demand) and
      won_path.suspension == body_path.suspension and
      won_path.usage == hide_private(body_path.usage) and
      won_path.required_phase ==
        require_action_and_hide_private(body_path.required_phase) and
      won_path.Q == hide_private(body_path.Q) and
      won_path.Lambda == hide_private(body_path.Lambda) and
      won_path.summary == OrderedSummaryNF(
        δacquire, body_path.summary, δrelease)
  return aggregate_check_result(
    paths, packed.evidence,
    packed_acquire_release_evidence(paths))

check_dispose_packed_next(ctx, packed_expr):
  packed = check_value_as(ctx, packed_expr, PackedNext[ρ, A])
  require phase_allows(ctx.Φ, Action)
  δdispose = PackedDisposeSummaryV2(HostObservable, NoSuspend)
  require Allowed(ctx.Φ, ∅, direct(NoSuspend), δdispose)
  transition = request_packed_close(packed)
  require transition is exactly one of
    Open(0) -> Closed + CloseChildOnce,
    Open(n+1) -> Closing(n+1),
    Closing(n) -> Closing(n),
    Closed -> Closed
  return single_path_result(
    Returns(ctx.Θ, Stable, ∅), ctx.Ω,
    row = ∅, demand = ∅,
    suspension = direct(NoSuspend), summary = δdispose,
    evidence = sealed_dispose_transition(transition))
```

`check_try_open_packed_next` 只能在 acquire成功后导入 wire，且导入得到的
`owner_child/frame/pending` 正是 body scope的唯一 binder来源。获胜 path
的 observer由上述有序三段 summary派生；`release_evidence` 不是可以代替
它的 detached旁证。这三个 procedure的 serializer/importer、scope、phase、
`Allowed`与非 `Pure` state-transition summary与 T-Pack/T-Try/T-Dispose逐项相同。

为避免伪代码省略被误读成“其余 Core constructor被 reject”，以下 branch是
对应具名规则的 syntax-directed transcription：

```text
CapAbs / CapApp              T-Cap-Intro / T-Cap-Elim
capref                       T-Cap-Ref
ClockPack                    T-Clock-Pack
ClockUnpack                  T-Clock-Unpack-Paths
PackNext                     T-Pack-Next-Paths
TryOpenPackedNext            T-Try-With-PackedNext-Paths
DisposePackedNext            T-Dispose-PackedNext
OwnerAbs / OwnerApp          T-Owner-Intro / T-Owner-Elim
FreshCap                     K-Fresh-Cap / K-Fresh-Cap-Abort
HandlerValue                 T-Handler + check_clause_schema_v2
Forward                      T-Forward-Delegate / T-Forward-Paths
Finalize                    T-Finalize + cleanup contract composition
Park                         T-Park
Atomic                       T-Atomic / T-Atomic-Abort
Batch                        T-Batch / T-Batch-Abort
CommitRun                    T-Commit-Run / T-Commit-Run-Abort
strict evaluation context    T-Ctx-Paths
```

每个 branch都对严格 AST 子树递归，并调用同一 finite kind/row/boundary
worklist；它们不是额外的 declarative oracle。`ClockUnpack` 的 package
operand按 Core grammar是 value $p$，因此算法也先走 `check_value`，不与
T-Clock-Unpack-Paths冲突。它只调用一次 `check_body_flow`，然后逐 path运行
`clock_package_outward_safe` 与 `release_hide_path`；不能按
`has_returns` 分叉，也不能把 Aborts/Transfers交给 generic context跳过
release。PackedNext的两个 contextual body branch复用同一 traversal；
try-open另加入固定 Returns(None) path。
