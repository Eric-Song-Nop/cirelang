#!/usr/bin/env python3
"""Task #46 exact-schema, Row-scope, selector, and Effect-substitution roots."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable


if len(sys.argv) != 2:
    raise SystemExit("usage: task46-regressions.py /path/to/cirelang-root")

ROOT = Path(sys.argv[1]).resolve()
SPEC = ROOT / "examples" / "spec"
INTERFACES = SPEC / "interfaces"

module_spec = importlib.util.spec_from_file_location(
    "cire_validate_task46", SPEC / "validate-oracles.py"
)
assert module_spec is not None and module_spec.loader is not None
v = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(v)


def load(name: str) -> dict[str, Any]:
    return v.load_json(INTERFACES / name)


def nominal_effect(name: str) -> dict[str, Any]:
    return {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": ["library"],
        "name": name,
    }


def expect_diagnostic(
    label: str,
    diagnostic_id: str,
    action: Callable[[], None],
) -> None:
    try:
        action()
    except v.Diagnostic as error:
        if error.diagnostic_id != diagnostic_id:
            raise AssertionError(
                f"{label}: expected {diagnostic_id}, got {error.diagnostic_id}"
            ) from error
    else:
        raise AssertionError(f"{label}: expected {diagnostic_id}, got ACCEPT")


def catalog_roots() -> None:
    catalog = load("effect-family-declarations.json")
    v.validate_effect_family_declarations(catalog)

    missing = copy.deepcopy(catalog)
    del missing["artifact"]
    expect_diagnostic(
        "catalog missing artifact",
        "contract-component-kind-mismatch",
        lambda: v.validate_effect_family_declarations(missing),
    )

    extra = copy.deepcopy(catalog)
    extra["unknown"] = None
    expect_diagnostic(
        "catalog unknown field",
        "contract-component-kind-mismatch",
        lambda: v.validate_effect_family_declarations(extra),
    )


def row_scope_roots() -> None:
    bound = load("choose-once-function-contract.json")
    bound["binders"]["row_binders"].append({"slot": 999, "lacks": []})
    bound["declaration_kind"]["visible_row"] = {
        "kind": "TailV1",
        "row_slot": {"namespace": "Row", "slot": 999},
    }
    v.validate_function_contract(bound)

    unbound = load("choose-once-function-contract.json")
    unbound["declaration_kind"]["visible_row"] = {
        "kind": "TailV1",
        "row_slot": {"namespace": "Row", "slot": 4242},
    }
    expect_diagnostic(
        "unbound public visible Row tail",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound),
    )

    bound_contract_binder = load("choose-once-function-contract.json")
    bound_contract_binder["binders"]["row_binders"].append(
        {"slot": 999, "lacks": []}
    )
    bound_contract_binder["binders"]["contract_binders"].append(
        {
            "kind": "FunctionContractBinderV2",
            "slot": 999,
            "parameter_type": {"kind": "TypeParameterV2", "slot": 0},
            "result_type": {"kind": "TypeParameterV2", "slot": 0},
            "visible_row": {
                "kind": "TailV1",
                "row_slot": {"namespace": "Row", "slot": 999},
            },
        }
    )
    v.validate_function_contract(bound_contract_binder)

    unbound_contract_binder = load("choose-once-function-contract.json")
    unbound_contract_binder["binders"]["contract_binders"].append(
        {
            "kind": "FunctionContractBinderV2",
            "slot": 999,
            "parameter_type": {"kind": "TypeParameterV2", "slot": 0},
            "result_type": {"kind": "TypeParameterV2", "slot": 0},
            "visible_row": {
                "kind": "TailV1",
                "row_slot": {"namespace": "Row", "slot": 4242},
            },
        }
    )
    expect_diagnostic(
        "unbound contract-binder visible Row tail",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound_contract_binder),
    )

    nested_unbound = load("choose-once-function-contract.json")
    nested_members = [
        {"kind": "EmptyV1"},
        {
            "kind": "TailV1",
            "row_slot": {"namespace": "Row", "slot": 4242},
        },
    ]
    nested_unbound["declaration_kind"]["visible_row"] = {
        "kind": "UnionV1",
        "members": sorted(nested_members, key=v.jcs),
    }
    expect_diagnostic(
        "nested Union has unbound Row tail",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(nested_unbound),
    )


def add_handler_contract_binder(contract: dict[str, Any], slot: int) -> None:
    contract["binders"]["contract_binders"].append(
        {
            "answer_type": {"kind": "TypeParameterV2", "slot": 0},
            "family": {
                "kind": "LegacyTypeRefV2",
                "value": nominal_effect("IoFailure"),
            },
            "input_type": {"kind": "TypeParameterV2", "slot": 0},
            "kind": "HandlerContractBinderV2",
            "slot": slot,
        }
    )


def handler_entry_lacks_roots() -> None:
    ordinary = load("choose-once-function-contract.json")
    ordinary["binders"]["row_binders"].append(
        {
            "slot": 999,
            "lacks": [
                {"kind": "HandlerEntryParameterV1", "contract_slot": 4242}
            ],
        }
    )
    expect_diagnostic(
        "handler entry selector in ordinary function scope",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(ordinary),
    )

    bound = load("choose-once-function-contract.json")
    add_handler_contract_binder(bound, 999)
    bound["binders"]["row_binders"].append(
        {
            "slot": 999,
            "lacks": [
                {"kind": "HandlerEntryParameterV1", "contract_slot": 999}
            ],
        }
    )
    v.validate_function_contract(bound)


def add_named_identity(
    contract: dict[str, Any],
    slot: int,
    family: str,
) -> None:
    contract["binders"]["owner_binders"].append(
        {
            "slot": slot,
            "source": {"namespace": "Parameter", "slot": 0},
        }
    )
    contract["binders"]["identity_binders"].append(
        {
            "identity_slot": slot,
            "family": nominal_effect(family),
            "owner": {"namespace": "Owner", "slot": slot},
            "binder": "FreshCap",
        }
    )


def add_named_lacks(
    contract: dict[str, Any],
    row_slot: int,
    identity_slot: int,
    family: str,
) -> None:
    contract["binders"]["row_binders"].append(
        {
            "slot": row_slot,
            "lacks": [
                {
                    "kind": "NamedV1",
                    "identity": {
                        "namespace": "Identity",
                        "slot": identity_slot,
                    },
                    "family": nominal_effect(family),
                }
            ],
        }
    )


def named_lacks_roots() -> None:
    unbound = load("choose-once-function-contract.json")
    add_named_lacks(unbound, 999, 4242, "IoFailure")
    expect_diagnostic(
        "unbound Named Lacks identity",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound),
    )

    matching = load("choose-once-function-contract.json")
    add_named_identity(matching, 999, "Choice")
    add_named_lacks(matching, 999, 999, "Choice")
    v.validate_function_contract(matching)

    mismatch = load("choose-once-function-contract.json")
    add_named_identity(mismatch, 999, "Choice")
    add_named_lacks(mismatch, 999, 999, "IoFailure")
    expect_diagnostic(
        "Named Lacks identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(mismatch),
    )


def public_selector_scope_roots() -> None:
    matching = load("choose-once-function-contract.json")
    add_named_identity(matching, 999, "Choice")
    matching["declaration_kind"]["visible_row"] = {
        "kind": "ClosedV1",
        "entries": [
            {
                "kind": "NamedV1",
                "identity": {"namespace": "Identity", "slot": 999},
                "family": nominal_effect("Choice"),
            }
        ],
    }
    v.validate_function_contract(matching)

    mismatch = copy.deepcopy(matching)
    mismatch["declaration_kind"]["visible_row"]["entries"][0]["family"] = (
        nominal_effect("IoFailure")
    )
    expect_diagnostic(
        "public Named selector identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(mismatch),
    )

    handler_only = load("choose-once-function-contract.json")
    handler_only["declaration_kind"]["visible_row"] = {
        "kind": "ClosedV1",
        "entries": [
            {"kind": "HandlerEntryParameterV1", "contract_slot": 4242}
        ],
    }
    expect_diagnostic(
        "handler-only selector in ordinary public row",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(handler_only),
    )


def replace_scalar(value: Any, old: str, new: str) -> Any:
    if isinstance(value, list):
        return [replace_scalar(member, old, new) for member in value]
    if isinstance(value, dict):
        return {
            key: replace_scalar(member, old, new)
            for key, member in value.items()
        }
    return new if value == old else value


def used_nominal_effect_root() -> tuple[dict[str, Any], dict[str, Any]]:
    imported = load("choose-once-function-contract.json")
    imported["binders"]["type_binders"].append(
        {"slot": 999, "kind": "Effect"}
    )
    imported["declaration_kind"]["visible_row"]["entries"].append(
        {
            "kind": "AnonV1",
            "family": {"kind": "TypeParameterV2", "slot": 999},
        }
    )
    imported["declaration_kind"]["visible_row"]["entries"].sort(key=v.jcs)

    oracle = load("handler-forward-contract.json")
    old_hash = oracle["imports"][0]["artifact_hash"]
    new_hash = "sha256:" + hashlib.sha256(
        v.jcs(imported).encode("utf-8")
    ).hexdigest()
    oracle = replace_scalar(oracle, old_hash, new_hash)
    oracle["handler_contract"]["applications"][0]["substitution"][
        "type_arguments"
    ].append(
        {
            "binder_slot": 999,
            "value": {
                "kind": "LegacyTypeRefV2",
                "value": nominal_effect("IoFailure"),
            },
        }
    )
    return imported, oracle


def used_nominal_effect_roots() -> None:
    imported, oracle = used_nominal_effect_root()
    v.validate_function_contract(imported)
    with tempfile.TemporaryDirectory(prefix="cire-task46-effect-root.") as name:
        directory = Path(name)
        (directory / "choose-once-function-contract.json").write_text(
            v.jcs(imported) + "\n", encoding="utf-8"
        )
        v.validate_handler_oracle(oracle, directory)

    substitution = oracle["handler_contract"]["applications"][0][
        "substitution"
    ]
    instantiated = v.substitute_contract_kind(
        imported["declaration_kind"], substitution
    )
    v.validate_row_expr(instantiated["visible_row"])
    assert any(
        entry.get("family") == nominal_effect("IoFailure")
        for entry in instantiated["visible_row"]["entries"]
    )


def frame_clock_family() -> dict[str, Any]:
    return {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": ["cire", "temporal"],
        "name": "FrameClock",
    }


def imported_identity_target() -> dict[str, Any]:
    target = load("apply-later-function-contract.json")
    target["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": frame_clock_family(),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    target["declaration_kind"]["visible_row"]["entries"].append(
        {
            "family": frame_clock_family(),
            "identity": {"namespace": "Identity", "slot": 999},
            "kind": "NamedV1",
        }
    )
    target["declaration_kind"]["visible_row"]["entries"].sort(key=v.jcs)
    v.validate_function_contract(target)
    return target


def identity_consumer_root(
    target: dict[str, Any],
    actual_family: dict[str, Any],
) -> dict[str, Any]:
    oracle = load("hof-mixed-later.json")
    old_hash = next(
        item["artifact_hash"]
        for item in oracle["imports"]
        if item["file"] == "apply-later-function-contract.json"
    )
    new_hash = "sha256:" + hashlib.sha256(
        v.jcs(target).encode("utf-8")
    ).hexdigest()
    oracle = replace_scalar(oracle, old_hash, new_hash)
    consumer = oracle["consumer_contract"]
    consumer["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": actual_family,
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    consumer["applications"][0]["substitution"][
        "identity_arguments"
    ].append(
        {
            "binder_slot": 999,
            "value": {"namespace": "Identity", "slot": 999},
        }
    )
    return oracle


def validate_identity_consumer(
    oracle: dict[str, Any],
    target: dict[str, Any],
) -> None:
    callback = load("mixed-next-callback-function-contract.json")
    with tempfile.TemporaryDirectory(prefix="cire-task46-identity-root.") as name:
        directory = Path(name)
        (directory / "apply-later-function-contract.json").write_text(
            v.jcs(target) + "\n", encoding="utf-8"
        )
        (directory / "mixed-next-callback-function-contract.json").write_text(
            v.jcs(callback) + "\n", encoding="utf-8"
        )
        imports = v.resolve_imports(oracle, directory)
        v.validate_function_contract(
            oracle["consumer_contract"], imports=imports
        )


def imported_identity_substitution_roots() -> None:
    target = imported_identity_target()
    same_family = identity_consumer_root(target, frame_clock_family())
    validate_identity_consumer(same_family, target)

    wrong_family = identity_consumer_root(target, nominal_effect("IoFailure"))
    expect_diagnostic(
        "imported Named identity substitution family mismatch",
        "contract-component-kind-mismatch",
        lambda: validate_identity_consumer(wrong_family, target),
    )


def handler_identity_target() -> dict[str, Any]:
    target = load("choose-once-function-contract.json")
    target["binders"]["owner_binders"].append(
        {
            "slot": 999,
            "source": {"namespace": "Parameter", "slot": 0},
        }
    )
    target["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": nominal_effect("Choice"),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 999},
        }
    )
    target["declaration_kind"]["visible_row"]["entries"].append(
        {
            "family": nominal_effect("Choice"),
            "identity": {"namespace": "Identity", "slot": 999},
            "kind": "NamedV1",
        }
    )
    target["declaration_kind"]["visible_row"]["entries"].sort(key=v.jcs)
    v.validate_function_contract(target)
    return target


def handler_identity_oracle(
    target: dict[str, Any],
    caller_family: str,
) -> dict[str, Any]:
    oracle = load("handler-forward-contract.json")
    old_hash = oracle["imports"][0]["artifact_hash"]
    oracle = replace_scalar(oracle, old_hash, v.canonical_hash(target))
    oracle["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": nominal_effect(caller_family),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    substitution = oracle["handler_contract"]["applications"][0][
        "substitution"
    ]
    substitution["owner_arguments"].append(
        {
            "binder_slot": 999,
            "value": {"namespace": "Owner", "slot": 0},
        }
    )
    substitution["identity_arguments"].append(
        {
            "binder_slot": 999,
            "value": {"namespace": "Identity", "slot": 999},
        }
    )
    return oracle


def validate_handler_identity_oracle(
    oracle: dict[str, Any],
    target: dict[str, Any],
) -> None:
    with tempfile.TemporaryDirectory(prefix="cire-task46-handler-scope.") as name:
        directory = Path(name)
        (directory / "choose-once-function-contract.json").write_text(
            v.jcs(target) + "\n", encoding="utf-8"
        )
        v.validate_handler_oracle(oracle, directory)


def handler_caller_scope_roots() -> None:
    target = handler_identity_target()
    same_family = handler_identity_oracle(target, "Choice")
    validate_handler_identity_oracle(same_family, target)

    wrong_family = handler_identity_oracle(target, "IoFailure")
    expect_diagnostic(
        "handler caller imported identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: validate_handler_identity_oracle(wrong_family, target),
    )

    residual = load("handler-forward-contract.json")
    residual["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": nominal_effect("Choice"),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    residual["handler_contract"]["residual_row"] = {
        "kind": "ClosedV1",
        "entries": [
            {
                "family": nominal_effect("IoFailure"),
                "identity": {"namespace": "Identity", "slot": 999},
                "kind": "NamedV1",
            }
        ],
    }
    expect_diagnostic(
        "handler residual row Named identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: v.validate_handler_oracle(residual, INTERFACES),
    )


def handler_scope_family(name: str) -> dict[str, Any]:
    return {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": ["library"],
        "name": name,
    }


def handler_scope_named_row(family_name: str) -> dict[str, Any]:
    return {
        "entries": [
            {
                "family": handler_scope_family(family_name),
                "identity": {"namespace": "Identity", "slot": 999},
                "kind": "NamedV1",
            }
        ],
        "kind": "ClosedV1",
    }


def add_handler_scope_identity(
    document: dict[str, Any],
    family: dict[str, Any],
) -> None:
    document["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": family,
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )


def validate_handler_scope_root(document: dict[str, Any]) -> None:
    v.validate_handler_oracle(document, INTERFACES)


def embedded_handler_function_root() -> tuple[
    dict[str, Any], dict[str, Any], Any
]:
    handler_oracle = load("handler-forward-contract.json")
    imports = v.resolve_imports(handler_oracle, INTERFACES)
    handler = copy.deepcopy(handler_oracle["handler_contract"])
    handler["clause_computations"] = []
    handler_family = copy.deepcopy(handler["handled_entry"]["family"])
    handler["handled_entry"] = {
        "family": handler_family,
        "identity": {"namespace": "Identity", "slot": 999},
        "kind": "NamedV1",
    }

    function = load("apply-later-function-contract.json")
    add_handler_scope_identity(function, handler_family)
    function["closure_environment"].append(
        {
            "capture": {
                "kind": "LegacyCaptureExprV2",
                "value": {"kind": "NoCaptureV1"},
            },
            "provenance": {
                "kind": "LegacyProvenanceExprV2",
                "value": {"kind": "StableV1"},
            },
            "slot": {"namespace": "ClosureCapture", "slot": 999},
            "type": {
                "answer": {
                    "kind": "LegacyTypeRefV2",
                    "value": {"kind": "BuiltinTypeV1", "name": "Int"},
                },
                "contract": handler,
                "family": handler_family,
                "input": {
                    "kind": "LegacyTypeRefV2",
                    "value": {"kind": "BuiltinTypeV1", "name": "Int"},
                },
                "kind": "HandlerTemplateTypeV2",
                "owner": {"namespace": "Owner", "slot": 0},
                "policy": "PersistentTemplateV1",
                "residual_row": {"kind": "EmptyV1"},
            },
        }
    )
    return function, handler, imports


def validate_embedded_handler_function_root() -> None:
    function, handler, imports = embedded_handler_function_root()
    binders = function["binders"]
    v.validate_handler_contract(
        copy.deepcopy(handler),
        imports=imports,
        type_parameter_kinds={
            binder["slot"]: binder["kind"]
            for binder in binders["type_binders"]
        },
        row_binders={
            binder["slot"]: binder for binder in binders["row_binders"]
        },
        contract_binders={
            binder["slot"]: binder
            for binder in binders["contract_binders"]
        },
        identity_binders={
            binder["identity_slot"]: binder
            for binder in binders["identity_binders"]
        },
        handler_contract_binders={
            binder["slot"]
            for binder in binders["contract_binders"]
            if binder.get("kind") == "HandlerContractBinderV2"
        },
    )
    v.validate_function_contract(function, imports=imports)


def validate_inline_function_fresh_scope_root() -> None:
    """An inline function owns its Row table instead of capturing the outer one."""

    function = load("apply-later-function-contract.json")
    nested = load("apply-later-function-contract.json")
    nested["binders"]["row_binders"].append({"slot": 999, "lacks": []})
    nested_row_members = [
        copy.deepcopy(nested["declaration_kind"]["visible_row"]),
        recursive_scope_tail(999),
    ]
    nested["declaration_kind"]["visible_row"] = {
        "kind": "UnionV1",
        "members": sorted(nested_row_members, key=v.jcs),
    }
    v.validate_function_contract(nested)
    function["closure_environment"].append(
        {
            "capture": {
                "kind": "LegacyCaptureExprV2",
                "value": {"kind": "NoCaptureV1"},
            },
            "provenance": {
                "kind": "LegacyProvenanceExprV2",
                "value": {"kind": "StableV1"},
            },
            "slot": {"namespace": "ClosureCapture", "slot": 999},
            "type": {
                "contract": nested,
                "kind": "FunctionTypeV2",
                "parameter": copy.deepcopy(
                    nested["declaration_kind"]["parameter_type"]
                ),
                "result": copy.deepcopy(
                    nested["declaration_kind"]["result_type"]
                ),
            },
        }
    )
    v.validate_function_contract(function)


def handler_computation_scope_roots() -> None:
    same_family = load("handler-forward-contract.json")
    add_handler_scope_identity(same_family, handler_scope_family("Choice"))
    same_family["handler_contract"]["return_computation"]["continuation"][
        "paths"
    ][0]["residual_row"] = handler_scope_named_row("Choice")
    validate_handler_scope_root(same_family)

    wrong_return_family = copy.deepcopy(same_family)
    wrong_return_family["handler_contract"]["return_computation"][
        "continuation"
    ]["paths"][0]["residual_row"] = handler_scope_named_row("IoFailure")
    expect_diagnostic(
        "wrong-family handler return-computation Named selector",
        "contract-component-kind-mismatch",
        lambda: validate_handler_scope_root(wrong_return_family),
    )

    wrong_clause_family = copy.deepcopy(same_family)
    wrong_clause_family["handler_contract"]["clause_computations"][0][
        "computation"
    ]["prefix"]["paths"][0]["residual_row"] = handler_scope_named_row(
        "IoFailure"
    )
    expect_diagnostic(
        "wrong-family handler clause-computation Named selector",
        "contract-component-kind-mismatch",
        lambda: validate_handler_scope_root(wrong_clause_family),
    )

    unbound_return_tail = load("handler-forward-contract.json")
    unbound_return_tail["handler_contract"]["return_computation"][
        "continuation"
    ]["paths"][0]["residual_row"] = {
        "kind": "TailV1",
        "row_slot": {"namespace": "Row", "slot": 4242},
    }
    expect_diagnostic(
        "unbound handler return-computation Row tail",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(unbound_return_tail),
    )

    validate_embedded_handler_function_root()


def recursive_scope_nominal(
    module: list[str], name: str,
) -> dict[str, Any]:
    return {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": module,
        "name": name,
    }


def recursive_scope_tail(slot_number: int) -> dict[str, Any]:
    return {
        "kind": "TailV1",
        "row_slot": {"namespace": "Row", "slot": slot_number},
    }


def recursive_scope_union(slot_number: int) -> dict[str, Any]:
    members = [{"kind": "EmptyV1"}, recursive_scope_tail(slot_number)]
    return {"kind": "UnionV1", "members": sorted(members, key=v.jcs)}


def recursive_scope_receiver(document: dict[str, Any]) -> dict[str, Any]:
    return document["handler_contract"]["clause_computations"][0][
        "computation"
    ]["continuation"]["paths"][0]["LatentSites"][0]


def recursive_scope_clause_path(document: dict[str, Any]) -> dict[str, Any]:
    return document["handler_contract"]["clause_computations"][0][
        "computation"
    ]["continuation"]["paths"][0]


def recursive_scope_return_path(document: dict[str, Any]) -> dict[str, Any]:
    return document["handler_contract"]["return_computation"]["continuation"][
        "paths"
    ][0]


def recursive_scope_row_target() -> tuple[dict[str, Any], dict[str, Any]]:
    target = load("choose-once-function-contract.json")
    target["binders"]["row_binders"].append({"slot": 999, "lacks": []})
    original_row = copy.deepcopy(target["declaration_kind"]["visible_row"])
    members = [original_row, recursive_scope_tail(999)]
    target["declaration_kind"]["visible_row"] = {
        "kind": "UnionV1",
        "members": sorted(members, key=v.jcs),
    }
    v.validate_function_contract(target)

    oracle = load("handler-forward-contract.json")
    old_hash = oracle["imports"][0]["artifact_hash"]
    oracle = replace_scalar(oracle, old_hash, v.canonical_hash(target))
    return target, oracle


def validate_recursive_scope_target(
    oracle: dict[str, Any], target: dict[str, Any]
) -> None:
    with tempfile.TemporaryDirectory(prefix="cire-task46-recursive-scope.") as name:
        directory = Path(name)
        (directory / "choose-once-function-contract.json").write_text(
            v.jcs(target) + "\n", encoding="utf-8"
        )
        v.validate_handler_oracle(oracle, directory)


def handler_recursive_descendant_scope_roots() -> None:
    baseline = load("handler-forward-contract.json")
    validate_handler_scope_root(baseline)

    top_bound = load("handler-forward-contract.json")
    top_bound["binders"]["row_binders"].append({"slot": 999, "lacks": []})
    top_bound["handler_contract"]["residual_row"] = recursive_scope_union(999)
    validate_handler_scope_root(top_bound)

    top_unbound = load("handler-forward-contract.json")
    top_unbound["handler_contract"]["residual_row"] = recursive_scope_union(
        4242
    )
    expect_diagnostic(
        "top-level handler residual Union has unbound Tail",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(top_unbound),
    )

    return_bound = load("handler-forward-contract.json")
    return_bound["binders"]["row_binders"].append(
        {"slot": 999, "lacks": []}
    )
    recursive_scope_return_path(return_bound)["residual_row"] = (
        recursive_scope_union(999)
    )
    validate_handler_scope_root(return_bound)

    return_unbound = load("handler-forward-contract.json")
    recursive_scope_return_path(return_unbound)["residual_row"] = (
        recursive_scope_union(4242)
    )
    expect_diagnostic(
        "return computation residual Union has unbound Tail",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(return_unbound),
    )

    clause_unbound = load("handler-forward-contract.json")
    recursive_scope_clause_path(clause_unbound)["residual_row"] = (
        recursive_scope_union(4242)
    )
    expect_diagnostic(
        "clause computation residual Union has unbound Tail",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(clause_unbound),
    )

    cleanup_unbound = load("handler-forward-contract.json")
    recursive_scope_receiver(cleanup_unbound)["suffix"]["cleanup"][
        "residual_row"
    ] = recursive_scope_tail(4242)
    expect_diagnostic(
        "nested suffix cleanup has unbound Row tail",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(cleanup_unbound),
    )

    receiver_same = load("handler-forward-contract.json")
    forwarding = recursive_scope_nominal(["fixtures"], "Forwarding")
    add_handler_scope_identity(receiver_same, forwarding)
    recursive_scope_receiver(receiver_same)["receiver"] = {
        "kind": "NamedV1",
        "identity": {"namespace": "Identity", "slot": 999},
        "family": forwarding,
    }
    validate_handler_scope_root(receiver_same)

    receiver_wrong = load("handler-forward-contract.json")
    add_handler_scope_identity(
        receiver_wrong, recursive_scope_nominal(["library"], "IoFailure")
    )
    recursive_scope_receiver(receiver_wrong)["receiver"] = {
        "kind": "NamedV1",
        "identity": {"namespace": "Identity", "slot": 999},
        "family": forwarding,
    }
    expect_diagnostic(
        "latent receiver Named identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: validate_handler_scope_root(receiver_wrong),
    )

    receiver_unbound = load("handler-forward-contract.json")
    recursive_scope_receiver(receiver_unbound)["receiver"] = {
        "kind": "NamedV1",
        "identity": {"namespace": "Identity", "slot": 4242},
        "family": forwarding,
    }
    expect_diagnostic(
        "latent receiver has unbound Identity",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(receiver_unbound),
    )

    receiver_handler_only = load("handler-forward-contract.json")
    recursive_scope_receiver(receiver_handler_only)["receiver"] = {
        "kind": "HandlerEntryParameterV1",
        "contract_slot": 4242,
    }
    expect_diagnostic(
        "latent receiver has unbound handler selector",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(receiver_handler_only),
    )

    target, application_unbound = recursive_scope_row_target()
    application_unbound["handler_contract"]["applications"][0][
        "substitution"
    ]["row_arguments"].append(
        {"binder_slot": 999, "value": recursive_scope_tail(4242)}
    )
    expect_diagnostic(
        "handler application public row receives unbound caller Tail",
        "contract-projection-escapes-scope",
        lambda: validate_recursive_scope_target(application_unbound, target),
    )

    target, nested_unbound = recursive_scope_row_target()
    top_application = nested_unbound["handler_contract"]["applications"][0]
    top_application["substitution"]["row_arguments"].append(
        {"binder_slot": 999, "value": {"kind": "EmptyV1"}}
    )
    nested_application = copy.deepcopy(top_application)
    nested_application["application_slot"] = 777
    nested_application["entry_world"] = {
        "kind": "ApplicationEntryWorldV2",
        "application_slot": 777,
    }
    nested_application["substitution"]["row_arguments"] = [
        {"binder_slot": 999, "value": recursive_scope_tail(4242)}
    ]
    recursive_scope_receiver(nested_unbound)["suffix"]["applications"].append(
        nested_application
    )
    expect_diagnostic(
        "nested suffix application receives unbound caller Tail",
        "contract-projection-escapes-scope",
        lambda: validate_recursive_scope_target(nested_unbound, target),
    )


catalog_roots()
row_scope_roots()
handler_entry_lacks_roots()
named_lacks_roots()
public_selector_scope_roots()
used_nominal_effect_roots()
imported_identity_substitution_roots()
handler_caller_scope_roots()
handler_computation_scope_roots()
handler_recursive_descendant_scope_roots()
validate_inline_function_fresh_scope_root()
print("PASS: 43 task-46 exact-schema/scope/substitution complete-root probes")
