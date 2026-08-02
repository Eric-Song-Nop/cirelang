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


catalog_roots()
row_scope_roots()
handler_entry_lacks_roots()
named_lacks_roots()
public_selector_scope_roots()
used_nominal_effect_roots()
imported_identity_substitution_roots()
print("PASS: 21 task-46 exact-schema/scope/substitution complete-root probes")
