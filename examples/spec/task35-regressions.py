#!/usr/bin/env python3
"""Adjacent complete-root conformance probes for CireLang task #35.

Pass a fresh exact candidate archive root as argv[1].  The candidate's
reference decoder is imported read-only.  Each case validates a complete
HandlerContractV2 with its exact imported and local function-contract tables.
"""

from __future__ import annotations

import copy
import importlib.util
import sys
from pathlib import Path


ROOT = Path(sys.argv[1]).resolve()
SPEC = ROOT / "examples" / "spec"
module_spec = importlib.util.spec_from_file_location(
    "cire_validate_task35", SPEC / "validate-oracles.py"
)
assert module_spec is not None and module_spec.loader is not None
v = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(v)


def load(name: str):
    return v.load_json(SPEC / "interfaces" / name)


def slot(namespace: str, number: int):
    return {"namespace": namespace, "slot": number}


failures: list[tuple[str, str, str]] = []


def run(label: str, action, expected_kind: str, expected_detail: str | None = None) -> None:
    try:
        action()
    except v.Diagnostic as error:
        outcome_kind = "REJECT"
        outcome_detail = error.diagnostic_id
    except Exception as error:
        outcome_kind = "CRASH"
        outcome_detail = f"{type(error).__name__}: {error}"
    else:
        outcome_kind = "ACCEPT"
        outcome_detail = None

    suffix = "" if outcome_detail is None else f" {outcome_detail}"
    print(f"{label}: {outcome_kind}{suffix}")
    mismatch = outcome_kind != expected_kind or (
        expected_detail is not None and outcome_detail != expected_detail
    )
    if mismatch:
        expected_suffix = "" if expected_detail is None else f" {expected_detail}"
        expected = f"{expected_kind}{expected_suffix}"
        failures.append((label, expected, f"{outcome_kind}{suffix}"))
        print(f"  MISMATCH: expected {expected}")


def handler_with_nested_return_projection(*, use_local_return: bool) -> None:
    """Validate a suffix whose nested PathBind locally binds Return/11.

    The nested Return reference is lexical to the PathBind continuation.  It
    is therefore not a free suffix dependency and must not appear in the
    suffix's `live_bindings` projection.
    """

    oracle = load("handler-forward-contract.json")
    imported_source = load("choose-once-function-contract.json")
    local_oracle = load("local-function-call.json")
    local_source = copy.deepcopy(local_oracle["local_declarations"][0]["contract"])
    local_application = copy.deepcopy(local_oracle["contract"]["applications"][0])

    imported_hash = oracle["imports"][0]["artifact_hash"]
    imports = v.single_import_scope(
        imported_hash,
        imported_source,
        tuple(oracle["imports"][0]["module"]),
        oracle["imports"][0]["function_name"],
    )
    local_functions = {0: local_source}

    handler = oracle["handler_contract"]
    clause = handler["clause_computations"][0]
    disposition_type = clause["disposition_binder"]["type"]
    forward = clause["computation"]["continuation"]["paths"][0]["outcome"][
        "forward_contract"
    ]
    suffix = forward["continuation"]
    path_template = copy.deepcopy(suffix["computation"]["paths"][0])

    return_slot = 11
    return_binder = v.concrete_return_binder(
        local_source,
        local_application,
        return_slot,
        imports=imports,
        local_functions=local_functions,
    )
    continuation = v.pure_return_continuation(path_template, return_slot)
    if use_local_return:
        continuation["paths"][0]["outcome"]["result_transformer"] = {
            "kind": "ParametricResultV2",
            "provenance": {
                "kind": "ReturnProvenanceV2",
                "return_slot": return_slot,
            },
            "capture": {
                "kind": "ReturnCaptureV2",
                "return_slot": return_slot,
            },
        }
    else:
        continuation["paths"][0]["outcome"]["result_transformer"] = {
            "kind": "LegacyResultTransformerV2",
            "value": {
                "kind": "ParametricResultV1",
                "provenance": {"kind": "StableV1"},
                "capture": {"kind": "NoCaptureV1"},
            },
        }

    suffix["applications"] = [local_application]
    suffix["computation"] = {
        "kind": "PathBindV2",
        "prefix": {
            "kind": "InvokeV2",
            "application_slot": local_application["application_slot"],
        },
        "return_binder": return_binder,
        "continuation": continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    assert suffix["live_bindings"] == []

    # The disposition and outer CurrentDisposition return binder must exactly
    # agree with the now-modified forwarded continuation.
    disposition_type["value"]["continuation"] = copy.deepcopy(suffix)
    clause["computation"]["return_binder"]["type"] = copy.deepcopy(
        clause["disposition_binder"]["type"]
    )

    v.validate_function_contract(local_source, local_functions=local_functions)
    v.validate_handler_contract(
        handler,
        imports=imports,
        local_functions=local_functions,
        nearest_outer_prompt_slot=1,
    )


def function_with_nested_return_projection() -> None:
    """Repeat the lexical Return probe in an independent FunctionContract root."""

    document = load("mixed-next-callback-function-contract.json")
    handler = load("handler-forward-contract.json")
    resume_type = copy.deepcopy(
        handler["handler_contract"]["clause_computations"][0][
            "disposition_binder"
        ]["type"]
    )
    suffix = resume_type["value"]["continuation"]
    local = load("local-function-call.json")
    callee = copy.deepcopy(local["local_declarations"][0]["contract"])
    application = copy.deepcopy(local["contract"]["applications"][0])
    local_functions = {0: callee}
    return_slot = 10
    binder = v.concrete_return_binder(
        callee,
        application,
        return_slot,
        imports=v.ImportScope(),
        local_functions=local_functions,
    )
    continuation = v.pure_return_continuation(
        copy.deepcopy(suffix["computation"]["paths"][0]), return_slot
    )
    continuation["paths"][0]["outcome"]["result_transformer"] = {
        "kind": "ParametricResultV2",
        "provenance": {
            "kind": "ReturnProvenanceV2",
            "return_slot": return_slot,
        },
        "capture": {
            "kind": "ReturnCaptureV2",
            "return_slot": return_slot,
        },
    }
    suffix["applications"] = [application]
    suffix["computation"] = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": binder,
        "continuation": continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    assert suffix["live_bindings"] == []
    document["closure_environment"].append(
        {
            "slot": slot("ClosureCapture", 1),
            "type": resume_type,
            "provenance": copy.deepcopy(resume_type["value"]["live_provenance"]),
            "capture": copy.deepcopy(resume_type["value"]["live_capture"]),
        }
    )
    v.validate_function_contract(document, local_functions=local_functions)


def hidden_used_application_environment() -> None:
    """A used suffix application ledger is part of the suffix live support."""

    source = load("choose-once-function-contract.json")
    local = load("local-function-call.json")
    callee = copy.deepcopy(local["local_declarations"][0]["contract"])
    application = copy.deepcopy(local["contract"]["applications"][0])
    actual = application["actual_arguments"][0]
    actual["provenance"] = {
        "kind": "LegacyProvenanceExprV2",
        "value": {"kind": "OwnerV1", "owner": slot("Owner", 0)},
    }
    actual["capture"] = {
        "kind": "LegacyCaptureExprV2",
        "value": {
            "kind": "CaptureSlotsV1",
            "slots": [slot("Owner", 0)],
        },
    }
    source["binders"]["owner_binders"] = [
        {"slot": 0, "source": slot("Parameter", 0)}
    ]
    suffix = source["computation"]["paths"][0]["LatentSites"][0]["suffix"]
    continuation = copy.deepcopy(suffix["computation"])
    local_functions = {0: callee}
    binder = v.concrete_return_binder(
        callee,
        application,
        50,
        imports=v.ImportScope(),
        local_functions=local_functions,
    )
    suffix["applications"] = [application]
    suffix["computation"] = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": binder,
        "continuation": continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    assert suffix["live_bindings"] == []
    v.validate_function_contract(source, local_functions=local_functions)


def forged_suffix_binding(field: str) -> None:
    """Keep the right live key while forging one projected summary field."""

    source = load("choose-once-function-contract.json")
    handler = load("handler-forward-contract.json")
    site = source["computation"]["paths"][0]["LatentSites"][0]
    resume_type = copy.deepcopy(
        handler["handler_contract"]["clause_computations"][0][
            "disposition_binder"
        ]["type"]
    )
    source["binders"]["owner_binders"] = [
        {"slot": 0, "source": slot("Parameter", 0)}
    ]
    stable = {
        "kind": "LegacyProvenanceExprV2",
        "value": {"kind": "StableV1"},
    }
    no_capture = {
        "kind": "LegacyCaptureExprV2",
        "value": {"kind": "NoCaptureV1"},
    }
    source["closure_environment"] = [
        {
            "slot": slot("ClosureCapture", 0),
            "type": copy.deepcopy(resume_type),
            "provenance": copy.deepcopy(stable),
            "capture": copy.deepcopy(no_capture),
        }
    ]
    binding = {
        "slot": {
            "kind": "LegacySlotRefV2",
            "value": slot("ClosureCapture", 0),
        },
        "type": copy.deepcopy(resume_type),
        "provenance": copy.deepcopy(stable),
        "capture": copy.deepcopy(no_capture),
        "usage": {
            "kind": "LegacyUsageExprV2",
            "value": {
                "slot": slot("ClosureCapture", 0),
                "kind": "Once",
            },
        },
    }
    site["suffix"]["live_bindings"] = [binding]
    transformer = site["suffix"]["computation"]["paths"][0]["outcome"][
        "result_transformer"
    ]["value"]
    transformer["provenance"] = {
        "kind": "ArgumentV1",
        "argument": slot("ClosureCapture", 0),
    }
    transformer["capture"] = {
        "kind": "CaptureSlotsV1",
        "slots": [slot("ClosureCapture", 0)],
    }
    if field == "type":
        binding["type"] = {
            "kind": "LegacyTypeRefV2",
            "value": {"kind": "BuiltinTypeV1", "name": "Int"},
        }
    elif field == "provenance":
        binding["provenance"] = {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "CallbackV1", "site_slot": 999},
        }
    elif field == "capture":
        binding["capture"] = {
            "kind": "LegacyCaptureExprV2",
            "value": {
                "kind": "OperationResultCaptureV1",
                "site_slot": 999,
            },
        }
    else:
        raise AssertionError(field)
    v.validate_function_contract(source)


def nested_return_usage_undercount() -> None:
    """Two sequential uses of an outer Return authority must compose to Many."""

    document = load("handler-forward-contract.json")
    imports = v.resolve_imports(document, SPEC / "interfaces")
    contract = document["handler_contract"]
    clause = contract["clause_computations"][0]
    outer = clause["computation"]
    binder10 = copy.deepcopy(outer["return_binder"])
    binder11 = copy.deepcopy(binder10)
    binder11["slot"] = 11
    inner_prefix = copy.deepcopy(outer["prefix"])
    inner_prefix["paths"][0]["usage"] = [
        {"kind": "ReturnUsageV2", "return_slot": 10}
    ]
    template = copy.deepcopy(outer["continuation"]["paths"][0])
    inner_continuation = v.pure_return_continuation(template, 11)
    inner_continuation["paths"][0]["usage"] = [
        {"kind": "ReturnUsageV2", "return_slot": 10}
    ]
    inner = {
        "kind": "PathBindV2",
        "prefix": inner_prefix,
        "return_binder": binder11,
        "continuation": inner_continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    clause["computation"] = {
        "kind": "PathBindV2",
        "prefix": copy.deepcopy(outer["prefix"]),
        "return_binder": binder10,
        "continuation": inner,
        "terminal_policy": "PreserveTerminalV2",
    }
    v.validate_handler_contract(
        contract, imports=imports, nearest_outer_prompt_slot=1
    )
    evaluated = v.evaluate_contract_computation(
        {
            "applications": contract["applications"],
            "computation": clause["computation"],
        },
        imports=imports,
        disposition_binder=clause["disposition_binder"],
    )
    assert evaluated[0]["path"]["usage"] == [
        {
            "kind": "LegacyUsageExprV2",
            "value": {
                "kind": "Once",
                "slot": slot("SuffixLive", 0),
            },
        }
    ]


def return_usage_without_projection() -> None:
    """A validated ReturnUsage must not reach a null evaluator projection."""

    document = load("local-function-call.json")
    handler = load("handler-forward-contract.json")
    resume_type = copy.deepcopy(
        handler["handler_contract"]["clause_computations"][0][
            "disposition_binder"
        ]["type"]
    )
    callee = copy.deepcopy(document["local_declarations"][0]["contract"])
    callee["binders"]["owner_binders"] = [
        {"slot": 0, "source": slot("Parameter", 0)}
    ]
    callee["binders"]["parameter_binders"][0]["type"] = copy.deepcopy(
        resume_type
    )
    callee["declaration_kind"]["parameter_type"] = copy.deepcopy(resume_type)
    callee["declaration_kind"]["result_type"] = copy.deepcopy(resume_type)
    transformer = callee["computation"]["paths"][0]["outcome"][
        "result_transformer"
    ]["value"]
    transformer["provenance"] = {
        "kind": "ArgumentV1",
        "argument": slot("Parameter", 0),
    }
    transformer["capture"] = {
        "kind": "ArgumentCaptureV1",
        "argument": slot("Parameter", 0),
    }

    outer = copy.deepcopy(document["contract"])
    outer["binders"]["owner_binders"] = [
        {"slot": 0, "source": slot("Parameter", 0)}
    ]
    outer["binders"]["parameter_binders"][0]["type"] = copy.deepcopy(
        resume_type
    )
    outer["declaration_kind"]["parameter_type"] = copy.deepcopy(resume_type)
    outer["declaration_kind"]["result_type"] = copy.deepcopy(resume_type)
    application = outer["applications"][0]
    application["substitution"]["owner_arguments"] = [
        {"binder_slot": 0, "value": slot("Owner", 0)}
    ]
    application["callee_summary"]["type"]["parameter"] = copy.deepcopy(
        resume_type
    )
    application["callee_summary"]["type"]["result"] = copy.deepcopy(
        resume_type
    )
    actual = application["actual_arguments"][0]
    actual["source"] = {
        "kind": "LegacySlotRefV2",
        "value": slot("Parameter", 0),
    }
    actual["type"] = copy.deepcopy(resume_type)
    actual["provenance"] = {
        "kind": "LegacyProvenanceExprV2",
        "value": {"kind": "StableV1"},
    }
    actual["capture"] = {
        "kind": "LegacyCaptureExprV2",
        "value": {"kind": "NoCaptureV1"},
    }
    actual["usage"] = {
        "kind": "LegacyUsageExprV2",
        "value": {"slot": slot("Parameter", 0), "kind": "Once"},
    }
    local_functions = {0: callee}
    binder = v.concrete_return_binder(
        callee,
        application,
        10,
        imports=v.ImportScope(),
        local_functions=local_functions,
    )
    assert binder["usage"] is None
    continuation = v.pure_return_continuation(
        document["contract"]["computation"]["members"][0]["paths"][0], 10
    )
    continuation["paths"][0]["usage"] = [
        {"kind": "ReturnUsageV2", "return_slot": 10}
    ]
    outer["computation"] = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": binder,
        "continuation": continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    v.validate_function_contract(callee)
    v.validate_function_contract(outer, local_functions=local_functions)
    v.evaluate_contract_computation(
        outer, imports=v.ImportScope(), local_functions=local_functions
    )


def one_shot_return_duplicable() -> None:
    """A one-shot Resume cannot satisfy DuplicableEnv via empty capture alone."""

    document = load("local-function-call.json")
    handler = load("handler-forward-contract.json")
    resume_type = copy.deepcopy(
        handler["handler_contract"]["clause_computations"][0][
            "disposition_binder"
        ]["type"]
    )
    resume_type["value"]["usage"] = "Once"
    owner_binders = [{"slot": 0, "source": slot("Parameter", 0)}]
    base_declaration = copy.deepcopy(document["local_declarations"][0])
    base_declaration["declaration_slot"] = 1
    base = base_declaration["contract"]
    base["declaration_kind"]["result_type"] = copy.deepcopy(resume_type)
    base["binders"]["owner_binders"] = copy.deepcopy(owner_binders)
    base["computation"]["paths"][0]["outcome"]["result_transformer"] = {
        "kind": "ParametricResultV2",
        "provenance": {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "StableV1"},
        },
        "capture": {
            "kind": "LegacyCaptureExprV2",
            "value": {"kind": "NoCaptureV1"},
        },
    }
    middle = copy.deepcopy(document["contract"])
    middle["declaration_kind"]["result_type"] = copy.deepcopy(resume_type)
    middle["binders"]["owner_binders"] = copy.deepcopy(owner_binders)
    application = middle["applications"][0]
    application["contract"]["declaration_slot"] = 1
    application["callee_summary"]["type"]["contract"]["declaration_slot"] = 1
    application["callee_summary"]["type"]["result"] = copy.deepcopy(
        resume_type
    )
    application["substitution"]["owner_arguments"] = [
        {"binder_slot": 0, "value": slot("Owner", 0)}
    ]
    binder = v.concrete_return_binder(
        base,
        application,
        10,
        imports=v.ImportScope(),
        local_functions={1: base},
    )
    continuation = v.pure_return_continuation(
        copy.deepcopy(
            document["contract"]["computation"]["members"][0]["paths"][0]
        ),
        10,
    )
    continuation["paths"][0]["ParametricObligations"] = [
        {
            "kind": "DuplicableEnvV2",
            "id": 2,
            "stage": "Call",
            "slots": [{"kind": "ReturnSlotRefV2", "return_slot": 10}],
            "site_slot": 77,
            "origin": "task35:return-resume-duplicable",
        }
    ]
    middle["computation"] = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": binder,
        "continuation": continuation,
        "terminal_policy": "PreserveTerminalV2",
    }
    outer = copy.deepcopy(document["contract"])
    outer["declaration_kind"]["result_type"] = copy.deepcopy(resume_type)
    outer["binders"]["owner_binders"] = copy.deepcopy(owner_binders)
    outer_application = outer["applications"][0]
    outer_application["contract"]["declaration_slot"] = 0
    outer_application["callee_summary"]["type"]["contract"][
        "declaration_slot"
    ] = 0
    outer_application["callee_summary"]["type"]["result"] = copy.deepcopy(
        resume_type
    )
    outer_application["substitution"]["owner_arguments"] = [
        {"binder_slot": 0, "value": slot("Owner", 0)}
    ]
    local_functions = {0: middle, 1: base}
    v.validate_function_contract(base, local_functions=local_functions)
    v.validate_function_contract(middle, local_functions=local_functions)
    v.validate_function_contract(outer, local_functions=local_functions)


def packed_next_child_alias() -> None:
    """The fresh existential child Owner must not alias its storage parent."""

    document = load("clock-package-paths.json")
    package = document["package"]
    parent = copy.deepcopy(package["storage_owner"])
    package["child_owner_binder"]["owner_slot"] = parent["slot"]
    package["owner_relation"]["child"] = copy.deepcopy(parent)
    package["clock_binder"]["owner"] = copy.deepcopy(parent)
    v.validate_clock_oracle(document)


def packed_next_scalar_payload() -> None:
    document = load("clock-package-paths.json")
    document["package"]["summary_binder"]["kind"]["payload_type"] = 0
    document["package"]["body"]["payload"] = 0
    v.validate_clock_oracle(document)


def packed_next_scalar_later_contract() -> None:
    document = load("clock-package-paths.json")
    document["package"]["body"]["later_contract"] = 0
    v.validate_clock_oracle(document)


CASES = [
    (
        "Nested suffix PathBind with no Return projection (control)",
        lambda: handler_with_nested_return_projection(use_local_return=False),
        "ACCEPT",
        None,
    ),
    (
        "Nested suffix PathBind uses its locally bound Return provenance/capture",
        lambda: handler_with_nested_return_projection(use_local_return=True),
        "ACCEPT",
        None,
    ),
    (
        "Independent FunctionContract suffix uses its locally bound Return",
        function_with_nested_return_projection,
        "ACCEPT",
        None,
    ),
    (
        "Used suffix application hides Owner provenance/capture from live bindings",
        hidden_used_application_environment,
        "REJECT",
        None,
    ),
    (
        "Suffix live binding keeps the right key but forges its type",
        lambda: forged_suffix_binding("type"),
        "REJECT",
        None,
    ),
    (
        "Suffix live binding keeps the right key but forges its provenance",
        lambda: forged_suffix_binding("provenance"),
        "REJECT",
        None,
    ),
    (
        "Suffix live binding keeps the right key but forges its capture",
        lambda: forged_suffix_binding("capture"),
        "REJECT",
        None,
    ),
    (
        "Two sequential outer Return usages remain Once after composition",
        nested_return_usage_undercount,
        "REJECT",
        None,
    ),
    (
        "ReturnUsageV2 resolves to a null concrete usage projection",
        return_usage_without_projection,
        "REJECT",
        None,
    ),
    (
        "One-shot returned Resume satisfies Call-DuplicableEnv",
        one_shot_return_duplicable,
        "REJECT",
        "call-obligation-unsatisfied",
    ),
    (
        "PackedNext existential child Owner aliases its storage parent",
        packed_next_child_alias,
        "REJECT",
        None,
    ),
    (
        "PackedNext scalar nested payload type",
        packed_next_scalar_payload,
        "REJECT",
        "contract-component-kind-mismatch",
    ),
    (
        "PackedNext scalar nested later_contract",
        packed_next_scalar_later_contract,
        "REJECT",
        "contract-component-kind-mismatch",
    ),
]


for case_label, probe, expected_kind, expected_detail in CASES:
    run(case_label, probe, expected_kind, expected_detail)

if failures:
    print(f"FAIL: {len(failures)} conformance mismatches")
    raise SystemExit(1)

print("PASS: all specified conformance expectations met")
