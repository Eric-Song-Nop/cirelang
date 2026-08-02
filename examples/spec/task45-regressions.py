#!/usr/bin/env python3
"""Task #45 complete-root and associated-evidence regressions."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable


if len(sys.argv) != 2:
    raise SystemExit("usage: task45-regressions.py /path/to/cirelang-root")

ROOT = Path(sys.argv[1]).resolve()
SPEC = ROOT / "examples" / "spec"
INTERFACES = SPEC / "interfaces"

module_spec = importlib.util.spec_from_file_location(
    "cire_validate_task45", SPEC / "validate-oracles.py"
)
assert module_spec is not None and module_spec.loader is not None
v = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(v)


def load(name: str) -> dict[str, Any]:
    return v.load_json(INTERFACES / name)


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


ITEMS = {
    "Key": {"kind": "Type", "default": None},
    "Value": {"kind": "Type", "default": None},
    "Fail": {"kind": "Effect", "default": None},
    "Extra": {
        "kind": "EffectRow",
        "default": frozenset(),
        "lacks": frozenset({"Blocking"}),
    },
}
HIDDEN = {
    "Key": ("Type", 100),
    "Value": ("Type", 101),
    "Fail": ("Effect", 102),
    "Extra": ("EffectRow", 103),
}


def named_map(
    arguments: list[tuple[str, str, Any]],
) -> dict[str, tuple[str, Any]]:
    result: dict[str, tuple[str, Any]] = {}
    for name, kind, value in arguments:
        if name not in ITEMS or name in result or ITEMS[name]["kind"] != kind:
            raise v.Diagnostic("associated-contract-mismatch")
        result[name] = (kind, value)
    return result


def generic_ability(
    arguments: list[tuple[str, str, Any]],
) -> tuple[dict[str, tuple[str, int]], dict[str, Any]]:
    supplied = named_map(arguments)
    equalities = {name: value for name, (_, value) in supplied.items()}
    # Generic omission never applies a declaration default.  The evidence is
    # nevertheless total because every declaration has a deterministic symbol.
    return copy.deepcopy(HIDDEN), equalities


def header_evidence(
    arguments: list[tuple[str, str, Any]],
) -> dict[str, Any]:
    supplied = named_map(arguments)
    evidence: dict[str, Any] = {}
    for name, declaration in ITEMS.items():
        if name in supplied:
            value = supplied[name][1]
        elif declaration["default"] is not None:
            value = declaration["default"]
        else:
            raise v.Diagnostic("associated-contract-mismatch")
        if declaration.get("lacks") and declaration["lacks"] & frozenset(value):
            raise v.Diagnostic("associated-contract-mismatch")
        evidence[name] = value
    return evidence


def apply_generic(
    equalities: dict[str, Any],
    header: dict[str, Any],
    type_substitution: dict[str, Any],
) -> None:
    for name, expected in equalities.items():
        expected = type_substitution.get(expected, expected)
        if header[name] != expected:
            raise v.Diagnostic("associated-contract-mismatch")


def semantic_controls() -> None:
    hidden, equalities = generic_ability([("Value", "Type", "A")])
    assert hidden == HIDDEN
    assert equalities == {"Value": "A"}
    assert hidden["Extra"] == ("EffectRow", 103)

    explicit = header_evidence(
        [
            ("Key", "Type", "Path"),
            ("Value", "Type", "Bytes"),
            ("Fail", "Effect", "IoFailure"),
            ("Extra", "EffectRow", frozenset({"Async"})),
        ]
    )
    defaulted = header_evidence(
        [
            ("Key", "Type", "Path"),
            ("Value", "Type", "Bytes"),
            ("Fail", "Effect", "IoFailure"),
        ]
    )
    assert explicit["Extra"] == frozenset({"Async"})
    assert defaulted["Extra"] == frozenset()
    apply_generic(equalities, explicit, {"A": "Bytes"})


def semantic_rejects() -> None:
    expect_diagnostic(
        "concrete header missing nondefault Fail",
        "associated-contract-mismatch",
        lambda: header_evidence(
            [("Key", "Type", "Path"), ("Value", "Type", "Bytes")]
        ),
    )
    expect_diagnostic(
        "generic application equality mismatch",
        "associated-contract-mismatch",
        lambda: apply_generic(
            {"Value": "A"},
            {"Key": "Path", "Value": "Bytes", "Fail": "IoFailure", "Extra": frozenset()},
            {"A": "Int"},
        ),
    )
    for label, arguments in (
        ("unknown associated argument", [("Unknown", "Type", "Int")]),
        (
            "duplicate associated argument",
            [("Value", "Type", "Bytes"), ("Value", "Type", "Bytes")],
        ),
        ("cross-kind associated argument", [("Fail", "EffectRow", frozenset())]),
    ):
        expect_diagnostic(
            label,
            "associated-contract-mismatch",
            lambda arguments=arguments: generic_ability(arguments),
        )
    expect_diagnostic(
        "associated row violates Lacks",
        "associated-contract-mismatch",
        lambda: header_evidence(
            [
                ("Key", "Type", "Path"),
                ("Value", "Type", "Bytes"),
                ("Fail", "Effect", "IoFailure"),
                ("Extra", "EffectRow", frozenset({"Blocking"})),
            ]
        ),
    )


def kind_root() -> dict[str, Any]:
    contract = load("choose-once-function-contract.json")
    contract["binders"]["type_binders"].append({"slot": 999, "kind": "Effect"})
    effect_family = {"kind": "TypeParameterV2", "slot": 999}
    contract["binders"]["row_binders"].append(
        {
            "slot": 999,
            "lacks": [{"kind": "AnonV1", "family": copy.deepcopy(effect_family)}],
        }
    )
    members = [
        {
            "kind": "ClosedV1",
            "entries": [{"kind": "AnonV1", "family": effect_family}],
        },
        {"kind": "TailV1", "row_slot": {"namespace": "Row", "slot": 999}},
    ]
    contract["declaration_kind"]["visible_row"] = {
        "kind": "UnionV1",
        "members": sorted(members, key=v.jcs),
    }
    return contract


def replace_scalar(value: Any, old: str, new: str) -> Any:
    if isinstance(value, list):
        return [replace_scalar(member, old, new) for member in value]
    if isinstance(value, dict):
        return {
            key: replace_scalar(member, old, new)
            for key, member in value.items()
        }
    return new if value == old else value


def effect_substitution(value: dict[str, Any]) -> None:
    imported = load("choose-once-function-contract.json")
    oracle = load("handler-forward-contract.json")
    old_hash = oracle["imports"][0]["artifact_hash"]
    imported["binders"]["type_binders"].append({"slot": 999, "kind": "Effect"})
    new_hash = "sha256:" + hashlib.sha256(v.jcs(imported).encode()).hexdigest()
    oracle = replace_scalar(oracle, old_hash, new_hash)
    oracle["handler_contract"]["applications"][0]["substitution"][
        "type_arguments"
    ].append(
        {
            "binder_slot": 999,
            "value": value,
        }
    )
    with tempfile.TemporaryDirectory(prefix="cire-task45-kind-root.") as name:
        directory = Path(name)
        (directory / "choose-once-function-contract.json").write_text(
            v.jcs(imported) + "\n", encoding="utf-8"
        )
        v.validate_handler_oracle(oracle, directory)


def decoder_controls_and_rejects() -> None:
    v.validate_function_contract(kind_root())
    effect_substitution(
        {
            "kind": "LegacyTypeRefV2",
            "value": {
                "arguments": [],
                "kind": "NominalTypeV1",
                "module": ["library"],
                "name": "IoFailure",
            },
        }
    )

    type_as_effect = kind_root()
    type_as_effect["declaration_kind"]["visible_row"]["members"][0]["entries"][0][
        "family"
    ] = {"kind": "TypeParameterV2", "slot": 0}
    expect_diagnostic(
        "Type binder used as Effect family",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(type_as_effect),
    )

    effect_as_type = kind_root()
    effect_as_type["declaration_kind"]["result_type"] = {
        "kind": "TypeParameterV2",
        "slot": 999,
    }
    expect_diagnostic(
        "Effect binder used in Type position",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(effect_as_type),
    )
    expect_diagnostic(
        "wrong-kind Effect substitution",
        "contract-component-kind-mismatch",
        lambda: effect_substitution(
            {
                "kind": "LegacyTypeRefV2",
                "value": {"kind": "BuiltinTypeV1", "name": "Int"},
            }
        ),
    )
    expect_diagnostic(
        "ordinary nominal Type substituted for Effect binder",
        "contract-component-kind-mismatch",
        lambda: effect_substitution(
            {
                "kind": "LegacyTypeRefV2",
                "value": {
                    "arguments": [],
                    "kind": "NominalTypeV1",
                    "module": ["library"],
                    "name": "NotAnEffectDeclaration",
                },
            }
        ),
    )

    unbound_lacks = kind_root()
    unbound_lacks["binders"]["row_binders"][0]["lacks"][0]["family"] = {
        "kind": "TypeParameterV2",
        "slot": 4242,
    }
    expect_diagnostic(
        "unbound Lacks family",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound_lacks),
    )

    for label, lacks in (
        ("malformed Lacks container", 0),
        ("malformed Lacks entry", [0]),
        (
            "builtin Type used as Lacks family",
            [{"kind": "AnonV1", "family": {"kind": "BuiltinTypeV1", "name": "Int"}}],
        ),
    ):
        malformed = kind_root()
        malformed["binders"]["row_binders"][0]["lacks"] = lacks
        expect_diagnostic(
            label,
            "contract-component-kind-mismatch",
            lambda malformed=malformed: v.validate_function_contract(malformed),
        )

    nominal_type_as_effect = kind_root()
    nominal_type_as_effect["declaration_kind"]["visible_row"]["members"][0][
        "entries"
    ][0]["family"] = {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": ["library"],
        "name": "NotAnEffectDeclaration",
    }
    expect_diagnostic(
        "ordinary nominal Type used as Effect family",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(nominal_type_as_effect),
    )


semantic_controls()
semantic_rejects()
decoder_controls_and_rejects()
print("PASS: 21 task-45 associated-evidence/kind complete-root probes")
