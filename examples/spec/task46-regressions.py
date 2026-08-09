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


def legacy_type(value: dict[str, Any]) -> dict[str, Any]:
    return {"kind": "LegacyTypeRefV2", "value": copy.deepcopy(value)}


def int_type() -> dict[str, Any]:
    return legacy_type({"kind": "BuiltinTypeV1", "name": "Int"})


def quantified_owner_type(owner_slot: int) -> dict[str, Any]:
    return {
        "kind": "ForAllOwnerTypeV2",
        "binder": {"owner_slot": owner_slot},
        "body": {
            "kind": "OwnerTypeV2",
            "owner": {"namespace": "Owner", "slot": owner_slot},
        },
    }


def later_contract() -> dict[str, Any]:
    return {
        "capture": {
            "kind": "LegacyCaptureExprV2",
            "value": {"kind": "NoCaptureV1"},
        },
        "provenance": {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "StableV1"},
        },
        "required_phase": {
            "allowed_phases": ["Pure", "Compute", "Action", "Commit"],
            "current_owner": None,
            "required_authorities": [],
        },
        "semantic_summary": {"kind": "PureV1"},
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


def with_result(type_ref: dict[str, Any]) -> dict[str, Any]:
    contract = load("apply-later-function-contract.json")
    contract["declaration_kind"]["result_type"] = copy.deepcopy(type_ref)
    return contract


def quantified_and_capability_roots() -> None:
    for label, type_ref in (
        (
            "empty QuantifiedIdentityBinderV2",
            {
                "kind": "ForAllIdentityTypeV2",
                "binder": {},
                "body": int_type(),
            },
        ),
        (
            "empty QuantifiedContractBinderV2",
            {
                "kind": "ForAllContractTypeV2",
                "binder": {},
                "body": int_type(),
            },
        ),
        (
            "empty QuantifiedOwnerBinderV1",
            {
                "kind": "ForAllOwnerTypeV2",
                "binder": {},
                "body": int_type(),
            },
        ),
        (
            "empty quantified clock and summary binders",
            {
                "kind": "ExistsClockPackageTypeV2",
                "clock_binder": {},
                "summary_binder": {},
                "body": int_type(),
            },
        ),
    ):
        expect_diagnostic(
            label,
            "contract-component-kind-mismatch",
            lambda type_ref=type_ref: v.validate_function_contract(
                with_result(type_ref)
            ),
        )

    choice = legacy_type(nominal_effect("Choice"))
    quantified_identity = {
        "kind": "ForAllIdentityTypeV2",
        "binder": {
            "identity_slot": 777,
            "clock_refinement": None,
            "family": copy.deepcopy(choice),
            "owner": {"namespace": "Owner", "slot": 0},
        },
        "body": {
            "kind": "CapabilityTypeV2",
            "identity": {"namespace": "Identity", "slot": 777},
            "family": copy.deepcopy(choice),
        },
    }
    v.validate_function_contract(with_result(quantified_identity))

    unbound_quantified_identity = copy.deepcopy(quantified_identity)
    unbound_quantified_identity["body"]["identity"]["slot"] = 4242
    expect_diagnostic(
        "quantified Identity body reference is unbound",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            with_result(unbound_quantified_identity)
        ),
    )

    frame = legacy_type(frame_clock_family())
    quantified_clock_identity = {
        "kind": "ForAllIdentityTypeV2",
        "binder": {
            "identity_slot": 777,
            "clock_refinement": {
                "clock_slot": 778,
                "identity": {"namespace": "Identity", "slot": 777},
            },
            "family": copy.deepcopy(frame),
            "owner": {"namespace": "Owner", "slot": 0},
        },
        "body": {
            "kind": "NextTypeV2",
            "clock": {"namespace": "Clock", "slot": 778},
            "payload": int_type(),
            "later_contract": later_contract(),
        },
    }
    v.validate_function_contract(with_result(quantified_clock_identity))

    unbound_quantified_clock = copy.deepcopy(quantified_clock_identity)
    unbound_quantified_clock["body"]["clock"]["slot"] = 4242
    expect_diagnostic(
        "quantified Clock body reference is unbound",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            with_result(unbound_quantified_clock)
        ),
    )

    function_kind = {
        "kind": "FunctionContractKindV2",
        "parameter_type": int_type(),
        "result_type": int_type(),
        "visible_row": {"kind": "EmptyV1"},
    }
    quantified_contract = {
        "kind": "ForAllContractTypeV2",
        "binder": {
            "contract_slot": 777,
            "kind": copy.deepcopy(function_kind),
        },
        "body": {
            "kind": "FunctionTypeV2",
            "parameter": int_type(),
            "result": int_type(),
            "contract": {"slot": 777, "kind": copy.deepcopy(function_kind)},
        },
    }
    v.validate_function_contract(with_result(quantified_contract))

    unbound_quantified_contract = copy.deepcopy(quantified_contract)
    unbound_quantified_contract["body"]["contract"]["slot"] = 4242
    expect_diagnostic(
        "quantified Contract body reference is unbound",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            with_result(unbound_quantified_contract)
        ),
    )

    quantified_owner = {
        "kind": "ForAllOwnerTypeV2",
        "binder": {"owner_slot": 777},
        "body": {
            "kind": "OwnerTypeV2",
            "owner": {"namespace": "Owner", "slot": 777},
        },
    }
    v.validate_function_contract(with_result(quantified_owner))

    unbound_quantified_owner = copy.deepcopy(quantified_owner)
    unbound_quantified_owner["body"]["owner"]["slot"] = 4242
    expect_diagnostic(
        "quantified Owner body reference is unbound",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            with_result(unbound_quantified_owner)
        ),
    )

    quantified_next = {
        "kind": "NextTypeV2",
        "clock": {"namespace": "Clock", "slot": 778},
        "payload": int_type(),
        "later_contract": later_contract(),
    }
    clock_package = {
        "kind": "ExistsClockPackageTypeV2",
        "clock_binder": {
            "identity_slot": 777,
            "clock_refinement": {
                "clock_slot": 778,
                "identity": {"namespace": "Identity", "slot": 777},
            },
            "family_witness": {
                "kind": "CanonicalFrameClockV2",
                "module": ["cire", "temporal"],
                "name": "FrameClock",
                "sealed_origin": "cire.temporal:FrameClock",
            },
            "owner": {"namespace": "Owner", "slot": 0},
        },
        "summary_binder": {
            "contract_slot": 779,
            "kind": {
                "kind": "ClockPackageSummaryKindV2",
                "clock": {"namespace": "Clock", "slot": 778},
                "payload_type": copy.deepcopy(quantified_next),
            },
        },
        "body": copy.deepcopy(quantified_next),
    }
    v.validate_function_contract(with_result(clock_package))

    exact_alpha_package = copy.deepcopy(clock_package)
    exact_alpha_package["summary_binder"]["kind"]["payload_type"] = (
        quantified_owner_type(900)
    )
    exact_alpha_package["body"] = quantified_owner_type(900)
    v.validate_function_contract(with_result(exact_alpha_package))

    renamed_alpha_package = copy.deepcopy(exact_alpha_package)
    renamed_alpha_package["body"] = quantified_owner_type(901)
    v.validate_function_contract(with_result(renamed_alpha_package))

    nonalpha_package = copy.deepcopy(exact_alpha_package)
    nonalpha_package["body"] = quantified_owner_type(901)
    nonalpha_package["body"]["body"]["owner"]["slot"] = 0
    expect_diagnostic(
        "clock-package payload is not alpha-equivalent",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(with_result(nonalpha_package)),
    )

    exact_packed = load("clock-package-paths.json")
    exact_packed["package"]["summary_binder"]["kind"]["payload_type"] = (
        quantified_owner_type(910)
    )
    exact_packed["package"]["body"]["payload"] = quantified_owner_type(910)
    v.validate_document(exact_packed, INTERFACES)

    renamed_packed = copy.deepcopy(exact_packed)
    renamed_packed["package"]["body"]["payload"] = (
        quantified_owner_type(911)
    )
    v.validate_document(renamed_packed, INTERFACES)

    def embedded_contract(type_slot: int) -> dict[str, Any]:
        local_oracle = load("local-function-call.json")
        contract = copy.deepcopy(
            local_oracle["local_declarations"][0]["contract"]
        )
        contract["binders"]["type_binders"] = [
            {"slot": type_slot, "kind": "Type"}
        ]
        contract["closure_environment"] = [
            {
                "slot": {"namespace": "ClosureCapture", "slot": 55},
                "type": {"kind": "TypeParameterV2", "slot": type_slot},
                "provenance": {
                    "kind": "LegacyProvenanceExprV2",
                    "value": {"kind": "StableV1"},
                },
                "capture": {
                    "kind": "LegacyCaptureExprV2",
                    "value": {"kind": "NoCaptureV1"},
                },
            }
        ]
        v.validate_function_contract(contract)
        return contract

    def embedded_function_type(type_slot: int) -> dict[str, Any]:
        contract = embedded_contract(type_slot)
        return {
            "kind": "FunctionTypeV2",
            "parameter": copy.deepcopy(
                contract["declaration_kind"]["parameter_type"]
            ),
            "result": copy.deepcopy(
                contract["declaration_kind"]["result_type"]
            ),
            "contract": contract,
        }

    embedded_left = embedded_function_type(700)
    embedded_right = embedded_function_type(701)
    exact_embedded_package = copy.deepcopy(clock_package)
    exact_embedded_package["summary_binder"]["kind"]["payload_type"] = (
        copy.deepcopy(embedded_left)
    )
    exact_embedded_package["body"] = copy.deepcopy(embedded_left)
    v.validate_function_contract(with_result(exact_embedded_package))

    renamed_embedded_package = copy.deepcopy(exact_embedded_package)
    renamed_embedded_package["body"] = copy.deepcopy(embedded_right)
    v.validate_function_contract(with_result(renamed_embedded_package))

    unbound_package_summary_clock = copy.deepcopy(clock_package)
    unbound_package_summary_clock["summary_binder"]["kind"]["clock"][
        "slot"
    ] = 4242
    expect_diagnostic(
        "clock-package summary references an unbound Clock",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            with_result(unbound_package_summary_clock)
        ),
    )

    matching_capability = {
        "kind": "CapabilityTypeV2",
        "identity": {"namespace": "Identity", "slot": 0},
        "family": copy.deepcopy(frame),
    }
    v.validate_function_contract(with_result(matching_capability))

    unbound_capability = copy.deepcopy(matching_capability)
    unbound_capability["identity"]["slot"] = 4242
    expect_diagnostic(
        "unbound CapabilityTypeV2 Identity",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(with_result(unbound_capability)),
    )

    wrong_capability = copy.deepcopy(matching_capability)
    wrong_capability["family"] = legacy_type(nominal_effect("IoFailure"))
    expect_diagnostic(
        "CapabilityTypeV2 Identity family mismatch",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(with_result(wrong_capability)),
    )


def quantified_import_and_handler_boundary_roots() -> None:
    base = load("handler-forward-contract.json")
    target = load("choose-once-function-contract.json")
    function_type = {
        "kind": "FunctionTypeV2",
        "parameter": copy.deepcopy(
            target["declaration_kind"]["parameter_type"]
        ),
        "result": copy.deepcopy(
            target["declaration_kind"]["result_type"]
        ),
        "contract": copy.deepcopy(
            base["handler_contract"]["applications"][0]["contract"]
        ),
    }

    def validate_environment_type(type_ref: dict[str, Any]) -> None:
        root = copy.deepcopy(base)
        root["binders"]["type_binders"].append(
            {"slot": 0, "kind": "Type"}
        )
        root["handler_contract"]["handler_environment"] = [
            {
                "slot": {"namespace": "Parameter", "slot": 0},
                "type": copy.deepcopy(type_ref),
                "provenance": {
                    "kind": "LegacyProvenanceExprV2",
                    "value": {
                        "kind": "ArgumentV1",
                        "argument": {
                            "namespace": "Parameter",
                            "slot": 0,
                        },
                    },
                },
                "capture": {
                    "kind": "LegacyCaptureExprV2",
                    "value": {
                        "kind": "ArgumentCaptureV1",
                        "argument": {
                            "namespace": "Parameter",
                            "slot": 0,
                        },
                    },
                },
            }
        ]
        v.validate_handler_oracle(root, INTERFACES)

    validate_environment_type(function_type)
    quantified_import = {
        "kind": "ForAllContractTypeV2",
        "binder": {
            "contract_slot": 777,
            "kind": {
                "kind": "FunctionContractKindV2",
                "parameter_type": copy.deepcopy(function_type),
                "result_type": int_type(),
                "visible_row": {"kind": "ClosedV1", "entries": []},
            },
        },
        "body": int_type(),
    }
    validate_environment_type(quantified_import)

    shadowed = load("choose-once-function-contract.json")
    type_parameter = {"kind": "TypeParameterV2", "slot": 0}
    shadowed["binders"]["contract_binders"].append(
        {
            "answer_type": copy.deepcopy(type_parameter),
            "family": legacy_type(nominal_effect("IoFailure")),
            "input_type": copy.deepcopy(type_parameter),
            "kind": "HandlerContractBinderV2",
            "slot": 999,
        }
    )

    def function_kind(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "kind": "FunctionContractKindV2",
            "parameter_type": copy.deepcopy(type_parameter),
            "result_type": copy.deepcopy(type_parameter),
            "visible_row": copy.deepcopy(row),
        }

    shadowed["declaration_kind"]["result_type"] = {
        "kind": "ForAllContractTypeV2",
        "binder": {
            "contract_slot": 999,
            "kind": function_kind({"kind": "ClosedV1", "entries": []}),
        },
        "body": {
            "kind": "ForAllContractTypeV2",
            "binder": {
                "contract_slot": 998,
                "kind": function_kind(
                    {
                        "kind": "ClosedV1",
                        "entries": [
                            {
                                "kind": "HandlerEntryParameterV1",
                                "contract_slot": 999,
                            }
                        ],
                    }
                ),
            },
            "body": copy.deepcopy(type_parameter),
        },
    }
    expect_diagnostic(
        "nested Function Contract shadows outer Handler classification",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(shadowed),
    )

    malformed = load("handler-forward-contract.json")
    malformed["handler_contract"]["handler_environment"] = [
        {
            "slot": {"namespace": "Parameter", "slot": 0},
            "type": {"kind": "ForAllOwnerTypeV2", "body": int_type()},
            "provenance": {
                "kind": "LegacyProvenanceExprV2",
                "value": {
                    "kind": "ArgumentV1",
                    "argument": {"namespace": "Parameter", "slot": 0},
                },
            },
            "capture": {
                "kind": "LegacyCaptureExprV2",
                "value": {
                    "kind": "ArgumentCaptureV1",
                    "argument": {"namespace": "Parameter", "slot": 0},
                },
            },
        }
    ]
    expect_diagnostic(
        "handler environment malformed quantifier is total",
        "contract-component-kind-mismatch",
        lambda: v.validate_handler_oracle(malformed, INTERFACES),
    )


def operation_signature_contract_scope_roots() -> None:
    local_oracle = load("local-function-call.json")
    declaration = local_oracle["local_declarations"][0]
    target = declaration["contract"]
    target_kind = target["declaration_kind"]
    artifact_hash = v.canonical_hash(target)
    imports = v.single_import_scope(
        artifact_hash,
        target,
        tuple(declaration["module"]),
        declaration["name"],
    )
    local_functions = {declaration["declaration_slot"]: target}

    def function_type(reference: dict[str, Any]) -> dict[str, Any]:
        return {
            "kind": "FunctionTypeV2",
            "parameter": copy.deepcopy(target_kind["parameter_type"]),
            "result": copy.deepcopy(target_kind["result_type"]),
            "contract": copy.deepcopy(reference),
        }

    imported_type = function_type(
        {
            "kind": "ImportedFunctionRefV2",
            "module": copy.deepcopy(declaration["module"]),
            "name": declaration["name"],
            "artifact_hash": artifact_hash,
        }
    )
    local_type = function_type(
        {
            "kind": "LocalFunctionRefV2",
            "declaration_slot": declaration["declaration_slot"],
        }
    )
    v.validate_type_v2(imported_type, imports=imports)
    v.validate_type_v2(local_type, local_functions=local_functions)

    signature_template = load("handler-forward-contract.json")[
        "handler_contract"
    ]["clause_computations"][0]["computation"]["continuation"][
        "paths"
    ][0]["LatentSites"][0]["instantiated_signature"]

    def signature_with(type_ref: dict[str, Any]) -> dict[str, Any]:
        signature = copy.deepcopy(signature_template)
        signature["type_binders"] = []
        signature["parameters"] = [copy.deepcopy(type_ref)]
        signature["result"] = copy.deepcopy(target_kind["result_type"])
        return signature

    v.validate_operation_signature(
        signature_with(imported_type), {}, imports=imports,
    )
    v.validate_operation_signature(
        signature_with(local_type), {}, local_functions=local_functions,
    )


def empty_substitution() -> dict[str, list[dict[str, Any]]]:
    return {
        "type_arguments": [],
        "row_arguments": [],
        "contract_arguments": [],
        "owner_arguments": [],
        "identity_arguments": [],
        "clock_arguments": [],
    }


def capture_avoiding_substitution_roots() -> None:
    owner_kind = {
        "kind": "FunctionContractKindV2",
        "parameter_type": {
            "kind": "ForAllOwnerTypeV2",
            "binder": {"owner_slot": 0},
            "body": {
                "kind": "ApplyTypeV2",
                "constructor": {
                    "kind": "BuiltinConstructorV1",
                    "name": "Pair",
                },
                "arguments": [
                    {
                        "kind": "OwnerTypeV2",
                        "owner": {"namespace": "Owner", "slot": 999},
                    },
                    {
                        "kind": "OwnerTypeV2",
                        "owner": {"namespace": "Owner", "slot": 0},
                    },
                ],
            },
        },
        "result_type": int_type(),
        "visible_row": {"kind": "ClosedV1", "entries": []},
    }
    noncolliding = empty_substitution()
    noncolliding["owner_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Owner", "slot": 1},
        }
    ]
    noncolliding_result = v.substitute_contract_kind(
        owner_kind, noncolliding,
    )["parameter_type"]
    assert [
        item["owner"]["slot"]
        for item in noncolliding_result["body"]["arguments"]
    ] == [1, 0]

    colliding = empty_substitution()
    colliding["owner_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Owner", "slot": 0},
        }
    ]
    colliding_result = v.substitute_contract_kind(
        owner_kind, colliding,
    )["parameter_type"]
    owner_slots = [
        item["owner"]["slot"]
        for item in colliding_result["body"]["arguments"]
    ]
    assert owner_slots == [0, 1], owner_slots

    frame = legacy_type(frame_clock_family())
    identity_kind = {
        "kind": "FunctionContractKindV2",
        "parameter_type": {
            "kind": "ForAllIdentityTypeV2",
            "binder": {
                "identity_slot": 0,
                "clock_refinement": {
                    "clock_slot": 0,
                    "identity": {"namespace": "Identity", "slot": 0},
                },
                "family": copy.deepcopy(frame),
                "owner": {"namespace": "Owner", "slot": 0},
            },
            "body": {
                "kind": "ApplyTypeV2",
                "constructor": {
                    "kind": "BuiltinConstructorV1",
                    "name": "Tuple4",
                },
                "arguments": [
                    {
                        "kind": "CapabilityTypeV2",
                        "identity": {"namespace": "Identity", "slot": 999},
                        "family": copy.deepcopy(frame),
                    },
                    {
                        "kind": "CapabilityTypeV2",
                        "identity": {"namespace": "Identity", "slot": 0},
                        "family": copy.deepcopy(frame),
                    },
                    {
                        "kind": "SignalTypeV2",
                        "clock": {"namespace": "Clock", "slot": 999},
                        "payload": int_type(),
                    },
                    {
                        "kind": "SignalTypeV2",
                        "clock": {"namespace": "Clock", "slot": 0},
                        "payload": int_type(),
                    },
                ],
            },
        },
        "result_type": int_type(),
        "visible_row": {"kind": "ClosedV1", "entries": []},
    }
    identity_substitution = empty_substitution()
    identity_substitution["identity_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Identity", "slot": 0},
        }
    ]
    identity_substitution["clock_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Clock", "slot": 0},
        }
    ]
    identity_result = v.substitute_contract_kind(
        identity_kind, identity_substitution,
    )["parameter_type"]
    arguments = identity_result["body"]["arguments"]
    assert [item["identity"]["slot"] for item in arguments[:2]] == [0, 1]
    assert [item["clock"]["slot"] for item in arguments[2:]] == [0, 1]

    contract_kind = {
        "kind": "FunctionContractKindV2",
        "parameter_type": int_type(),
        "result_type": int_type(),
        "visible_row": {"kind": "ClosedV1", "entries": []},
    }
    contract_type = {
        "kind": "ForAllContractTypeV2",
        "binder": {
            "contract_slot": 0,
            "kind": copy.deepcopy(contract_kind),
        },
        "body": {
            "kind": "ApplyTypeV2",
            "constructor": {
                "kind": "BuiltinConstructorV1",
                "name": "Pair",
            },
            "arguments": [
                {
                    "kind": "FunctionTypeV2",
                    "parameter": int_type(),
                    "result": int_type(),
                    "contract": {
                        "slot": 999,
                        "kind": copy.deepcopy(contract_kind),
                    },
                },
                {
                    "kind": "FunctionTypeV2",
                    "parameter": int_type(),
                    "result": int_type(),
                    "contract": {
                        "slot": 0,
                        "kind": copy.deepcopy(contract_kind),
                    },
                },
            ],
        },
    }
    contract_substitution = empty_substitution()
    contract_substitution["contract_arguments"] = [
        {
            "binder_slot": 999,
            "contract": {
                "kind": "ContractParameterRefV2",
                "parameter": {
                    "slot": 0,
                    "kind": copy.deepcopy(contract_kind),
                },
            },
        }
    ]
    contract_result = v.substitute_contract_kind(
        {
            "kind": "FunctionContractKindV2",
            "parameter_type": contract_type,
            "result_type": int_type(),
            "visible_row": {"kind": "ClosedV1", "entries": []},
        },
        contract_substitution,
    )["parameter_type"]
    assert contract_result["body"]["arguments"][0]["contract"][
        "parameter"
    ]["slot"] == 0
    assert contract_result["body"]["arguments"][1]["contract"]["slot"] == 1

    signature = {
        "type_binders": [{"slot": 0, "kind": "Type"}],
        "parameters": [
            {"kind": "TypeParameterV2", "slot": 999},
            {"kind": "TypeParameterV2", "slot": 0},
        ],
        "result": int_type(),
        "mode": "fun",
        "transition": {"kind": "SameWorldV1"},
        "suspension": {"atoms": [], "grade": "NoSuspend"},
        "result_transformer": {"kind": "SyntheticTransformer"},
        "required_phase": {},
        "obligation_ids": [],
        "secondary_sites": {},
    }
    type_substitution = empty_substitution()
    type_substitution["type_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"kind": "TypeParameterV2", "slot": 0},
        }
    ]
    signature_result = v.substitute_contract_kind(
        {
            "kind": "FunctionContractKindV2",
            "parameter_type": {
                "kind": "SyntheticSignatureTypeV2",
                "signature": signature,
            },
            "result_type": int_type(),
            "visible_row": {"kind": "ClosedV1", "entries": []},
        },
        type_substitution,
    )["parameter_type"]["signature"]
    assert [item["slot"] for item in signature_result["parameters"]] == [0, 1]

    signature_fields = {
        "type_binders", "parameters", "result", "mode", "transition",
        "suspension", "result_transformer", "required_phase",
        "obligation_ids", "secondary_sites",
    }
    legacy_signature = next(
        copy.deepcopy(node)
        for node in v.walk(load("handler-forward-contract.json"))
        if isinstance(node, dict) and set(node) == signature_fields
    )
    legacy_signature["type_binders"] = [{"slot": 0, "kind": "Type"}]
    legacy_signature["parameters"] = [
        {
            "kind": "LegacyTypeRefV2",
            "value": {"kind": "TypeParameterV1", "slot": 0},
        },
        {"kind": "TypeParameterV2", "slot": 999},
    ]
    legacy_signature["result"] = int_type()
    signature_scope = v.DeclarationScope(
        type_parameter_kinds={0: "Type", 1: "Type", 999: "Type"},
        row_binders={},
        contract_binders={},
        identity_binders={},
        handler_contract_binders=set(),
        owner_binders={},
        clock_binders={},
        parameter_binders=set(),
        closure_capture_binders=set(),
    )
    v.validate_operation_signature(
        legacy_signature, {}, declaration_scope=signature_scope,
    )

    def legacy_signature_slots(actual_slot: int) -> tuple[int, int, int]:
        substitution = empty_substitution()
        substitution["type_arguments"] = [
            {
                "binder_slot": 999,
                "value": {"kind": "TypeParameterV2", "slot": actual_slot},
            }
        ]
        result = v.substitute_contract_kind(
            {"signature": legacy_signature}, substitution,
        )["signature"]
        return (
            result["type_binders"][0]["slot"],
            result["parameters"][0]["value"]["slot"],
            result["parameters"][1]["slot"],
        )

    assert legacy_signature_slots(1) == (0, 0, 1)
    assert legacy_signature_slots(0) == (1, 1, 0)


def packed_alpha_totality_roots() -> None:
    package = load("clock-package-paths.json")
    v.validate_document(copy.deepcopy(package), INTERFACES)

    malformed_quantifier = {
        "kind": "ForAllOwnerTypeV2",
        "binder": {"owner_slot": 910},
    }
    package["package"]["summary_binder"]["kind"]["payload_type"] = (
        copy.deepcopy(malformed_quantifier)
    )
    package["package"]["body"]["payload"] = copy.deepcopy(
        malformed_quantifier
    )
    expect_diagnostic(
        "packed payload alpha comparison follows exact TypeRef decode",
        "contract-component-kind-mismatch",
        lambda: v.validate_document(package, INTERFACES),
    )


def adjacent_alpha_occurrence_totality_roots() -> None:
    def function_type(contract: dict[str, Any]) -> dict[str, Any]:
        kind = contract["declaration_kind"]
        return {
            "kind": "FunctionTypeV2",
            "parameter": copy.deepcopy(kind["parameter_type"]),
            "result": copy.deepcopy(kind["result_type"]),
            "contract": copy.deepcopy(contract),
        }

    def package(
        summary_payload: dict[str, Any], body_payload: dict[str, Any],
    ) -> dict[str, Any]:
        root = load("apply-later-function-contract.json")
        root["declaration_kind"]["result_type"] = {
            "kind": "ExistsClockPackageTypeV2",
            "clock_binder": {
                "identity_slot": 777,
                "clock_refinement": {
                    "clock_slot": 778,
                    "identity": {"namespace": "Identity", "slot": 777},
                },
                "family_witness": {
                    "kind": "CanonicalFrameClockV2",
                    "module": ["cire", "temporal"],
                    "name": "FrameClock",
                    "sealed_origin": "cire.temporal:FrameClock",
                },
                "owner": {"namespace": "Owner", "slot": 0},
            },
            "summary_binder": {
                "contract_slot": 779,
                "kind": {
                    "kind": "ClockPackageSummaryKindV2",
                    "clock": {"namespace": "Clock", "slot": 778},
                    "payload_type": copy.deepcopy(summary_payload),
                },
            },
            "body": copy.deepcopy(body_payload),
        }
        return root

    def validate_renamed(
        left: dict[str, Any], right: dict[str, Any],
    ) -> None:
        v.validate_function_contract(left)
        v.validate_function_contract(right)
        v.validate_document(
            package(function_type(left), function_type(right)), INTERFACES,
        )

    def prompt_contract(prompt_slot: int) -> dict[str, Any]:
        local = load("local-function-call.json")
        contract = copy.deepcopy(local["local_declarations"][0]["contract"])
        contract["binders"]["owner_binders"] = [
            {
                "slot": 0,
                "source": {"namespace": "Parameter", "slot": 0},
            }
        ]
        contract["binders"]["prompt_binders"] = [
            {
                "binder_site_slot": 100,
                "prompt_slot": prompt_slot,
                "scope": "LexicalInstallation",
            }
        ]
        handler = copy.deepcopy(load("handler-forward-contract.json")[
            "handler_contract"
        ])
        handler["applications"] = []
        handler["clause_computations"] = []
        handler["return_computation"] = copy.deepcopy(
            handler["return_computation"]["continuation"]
        )
        handler["prompt_slot"] = prompt_slot
        contract["closure_environment"].append(
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
                    "answer": int_type(),
                    "contract": handler,
                    "family": copy.deepcopy(handler["handled_entry"]["family"]),
                    "input": int_type(),
                    "kind": "HandlerTemplateTypeV2",
                    "owner": {"namespace": "Owner", "slot": 0},
                    "policy": "PersistentTemplateV1",
                    "residual_row": {"kind": "EmptyV1"},
                },
            }
        )
        return contract

    validate_renamed(prompt_contract(0), prompt_contract(1))

    def owner_contract(owner_slot: int) -> dict[str, Any]:
        contract = load("mixed-next-callback-function-contract.json")
        contract["declaration_kind"]["result_type"] = int_type()
        if owner_slot != 0:
            for node in v.walk(contract):
                if not isinstance(node, dict):
                    continue
                if node.get("namespace") == "Owner" and node.get("slot") == 0:
                    node["slot"] = owner_slot
                if node.get("owner_slot") == 0:
                    node["owner_slot"] = owner_slot
            contract["binders"]["owner_binders"][0]["slot"] = owner_slot
        return contract

    validate_renamed(owner_contract(0), owner_contract(7))

    def indexed_contract(type_slot: int) -> dict[str, Any]:
        contract = load("mixed-next-callback-function-contract.json")
        contract["declaration_kind"]["result_type"] = int_type()
        contract["binders"]["type_binders"] = [
            {"slot": type_slot, "kind": "Type"}
        ]
        contract["computation"]["return_binder"]["nominal_index"] = {
            "kind": "LegacyNominalIndexExprV2",
            "value": {"kind": "TypeParameterIndexV1", "slot": type_slot},
        }
        return contract

    validate_renamed(indexed_contract(700), indexed_contract(701))

    malformed_prompt = prompt_contract(0)
    del malformed_prompt["binders"]["prompt_binders"][0]["prompt_slot"]
    malformed_type = function_type(malformed_prompt)
    expect_diagnostic(
        "missing inline PromptSlotDeclV1 field is stable",
        "contract-component-kind-mismatch",
        lambda: v.validate_document(
            package(malformed_type, malformed_type), INTERFACES,
        ),
    )

    local = load("local-function-call.json")
    declaration = local["local_declarations"][0]
    target = declaration["contract"]
    target_kind = target["declaration_kind"]
    artifact_hash = v.canonical_hash(target)
    imports = v.single_import_scope(
        artifact_hash,
        target,
        tuple(declaration["module"]),
        declaration["name"],
    )
    signature_fields = {
        "type_binders", "parameters", "result", "mode", "transition",
        "suspension", "result_transformer", "required_phase",
        "obligation_ids", "secondary_sites",
    }
    handler = load("handler-forward-contract.json")
    signature = next(
        copy.deepcopy(node)
        for node in v.walk(handler)
        if isinstance(node, dict) and set(node) == signature_fields
    )
    signature["type_binders"] = []
    signature["parameters"] = [
        {
            "kind": "FunctionTypeV2",
            "parameter": copy.deepcopy(target_kind["parameter_type"]),
            "result": copy.deepcopy(target_kind["result_type"]),
            "contract": 0,
        }
    ]
    signature["result"] = copy.deepcopy(target_kind["result_type"])
    expect_diagnostic(
        "scalar OperationSignature FunctionType contract is stable",
        "contract-component-kind-mismatch",
        lambda: v.validate_operation_signature(signature, {}, imports=imports),
    )


def task49_schema_scope_totality_roots() -> None:
    """Keep every distinct task-49 closure defect as a consumable root."""

    later = load("mixed-next-callback-function-contract.json")
    later["declaration_kind"]["result_type"] = int_type()
    later["binders"]["contract_binders"] = [
        {
            "kind": "LaterContractBinderV2",
            "slot": 780,
            "clock": {"namespace": "Clock", "slot": 0},
            "payload_type": int_type(),
        }
    ]
    v.validate_function_contract(later)

    continuation = load("choose-once-function-contract.json")
    continuation["binders"]["contract_binders"] = [
        {
            "kind": "ContinuationContractBinderV2",
            "slot": 781,
            "argument_type": int_type(),
            "answer_type": int_type(),
        }
    ]
    v.validate_function_contract(continuation)

    def indexed_contract(
        binder_slot: int, occurrence_slot: int | None = None,
    ) -> dict[str, Any]:
        occurrence_slot = (
            binder_slot if occurrence_slot is None else occurrence_slot
        )
        contract = load("mixed-next-callback-function-contract.json")
        contract["declaration_kind"]["result_type"] = int_type()
        contract["binders"]["type_binders"] = [
            {"slot": binder_slot, "kind": "Type"}
        ]
        contract["computation"]["return_binder"]["nominal_index"] = {
            "kind": "LegacyNominalIndexExprV2",
            "value": {
                "kind": "TypeParameterIndexV1",
                "slot": occurrence_slot,
            },
        }
        return contract

    def world_parameter_contract(contract_slot: int) -> dict[str, Any]:
        contract = indexed_contract(790)
        contract["binders"]["contract_binders"] = [
            {
                "kind": "FunctionContractBinderV2",
                "slot": contract_slot,
                "parameter_type": int_type(),
                "result_type": int_type(),
                "visible_row": {"kind": "ClosedV1", "entries": []},
            }
        ]
        contract["computation"]["prefix"]["paths"][0][
            "ParametricObligations"
        ].append(
            {
                "kind": "LegacyObligationV2",
                "value": {
                    "kind": "StableAcrossV1",
                    "id": 4240,
                    "stage": "HandlerInstall",
                    "slots": [],
                    "clock_slot": {"namespace": "Clock", "slot": 0},
                    "worlds": [
                        {
                            "kind": "WorldParameterV1",
                            "contract_slot": contract_slot,
                        }
                    ],
                    "origin": "task49.cire:world-parameter",
                },
            }
        )
        return contract

    world_left = world_parameter_contract(800)
    world_right = world_parameter_contract(801)
    v.validate_function_contract(world_left)
    v.validate_function_contract(world_right)
    if not v.alpha_equal_v2(world_left, world_right):
        raise AssertionError("WorldParameterV1 Contract alpha rename")

    def prompt_contract(
        binder_slot: int, occurrence_slot: int,
    ) -> dict[str, Any]:
        local = load("local-function-call.json")
        contract = copy.deepcopy(local["local_declarations"][0]["contract"])
        contract["binders"]["owner_binders"] = [
            {
                "slot": 0,
                "source": {"namespace": "Parameter", "slot": 0},
            }
        ]
        contract["binders"]["prompt_binders"] = [
            {
                "binder_site_slot": 4100,
                "prompt_slot": binder_slot,
                "scope": "LexicalInstallation",
            }
        ]
        handler = copy.deepcopy(load("handler-forward-contract.json")[
            "handler_contract"
        ])
        handler["applications"] = []
        handler["clause_computations"] = []
        handler["return_computation"] = copy.deepcopy(
            handler["return_computation"]["continuation"]
        )
        handler["prompt_slot"] = occurrence_slot
        contract["closure_environment"].append(
            {
                "slot": {"namespace": "ClosureCapture", "slot": 4101},
                "type": {
                    "kind": "HandlerTemplateTypeV2",
                    "family": copy.deepcopy(handler["handled_entry"]["family"]),
                    "owner": {"namespace": "Owner", "slot": 0},
                    "input": int_type(),
                    "answer": int_type(),
                    "residual_row": {"kind": "EmptyV1"},
                    "contract": handler,
                    "policy": "PersistentTemplateV1",
                },
                "provenance": {
                    "kind": "LegacyProvenanceExprV2",
                    "value": {"kind": "StableV1"},
                },
                "capture": {
                    "kind": "LegacyCaptureExprV2",
                    "value": {"kind": "NoCaptureV1"},
                },
            }
        )
        return contract

    unbound_prompt = prompt_contract(60, 61)
    expect_diagnostic(
        "unbound HandlerContractV2 prompt scalar",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound_prompt),
    )

    unbound_index = indexed_contract(760, 761)
    expect_diagnostic(
        "unbound TypeParameterIndexV1 scalar",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(unbound_index),
    )

    duplicate_type = indexed_contract(760)
    duplicate_type["binders"]["type_binders"].append(
        {"slot": 760, "kind": "Type"}
    )
    expect_diagnostic(
        "duplicate Type binder slot is diagnostic",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(duplicate_type),
    )

    local = load("local-function-call.json")
    declaration = local["local_declarations"][0]
    target = declaration["contract"]
    target_kind = target["declaration_kind"]
    artifact_hash = v.canonical_hash(target)
    imports = v.single_import_scope(
        artifact_hash,
        target,
        tuple(declaration["module"]),
        declaration["name"],
    )
    handler = load("handler-forward-contract.json")
    signature_fields = {
        "type_binders", "parameters", "result", "mode", "transition",
        "suspension", "result_transformer", "required_phase",
        "obligation_ids", "secondary_sites",
    }
    signature_template = next(
        copy.deepcopy(node)
        for node in v.walk(handler)
        if isinstance(node, dict) and set(node) == signature_fields
    )

    def malformed_signature(reference: dict[str, Any]) -> dict[str, Any]:
        signature = copy.deepcopy(signature_template)
        signature["type_binders"] = []
        signature["parameters"] = [
            {
                "kind": "FunctionTypeV2",
                "parameter": copy.deepcopy(target_kind["parameter_type"]),
                "result": copy.deepcopy(target_kind["result_type"]),
                "contract": reference,
            }
        ]
        signature["result"] = copy.deepcopy(target_kind["result_type"])
        signature["obligation_ids"] = []
        return signature

    malformed_import = {
        "kind": "ImportedFunctionRefV2",
        "module": 0,
        "name": declaration["name"],
        "artifact_hash": artifact_hash,
    }
    expect_diagnostic(
        "non-list imported module is diagnostic",
        "contract-component-kind-mismatch",
        lambda: v.validate_operation_signature(
            malformed_signature(malformed_import), {}, imports=imports,
        ),
    )

    malformed_local = {
        "kind": "LocalFunctionRefV2",
        "declaration_slot": [],
    }
    expect_diagnostic(
        "non-u32 local declaration slot is diagnostic",
        "local-function-ref-unresolved",
        lambda: v.validate_operation_signature(
            malformed_signature(malformed_local), {},
            local_functions={declaration["declaration_slot"]: target},
        ),
    )

    empty_prompt_scope = prompt_contract(60, 60)
    empty_prompt_scope["binders"]["prompt_binders"] = []
    expect_diagnostic(
        "nested HandlerContractV2 prompt rejects an empty declaration table",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(empty_prompt_scope),
    )

    latent_fields = {
        "site_slot", "stage", "receiver", "operation", "route",
        "actual_arguments", "instantiated_signature", "suffix",
        "secondary_sites", "call_obligation_ids", "install_obligation_ids",
        "origin",
    }

    def malformed_latent_root(
        field: str, replacement: Any,
    ) -> dict[str, Any]:
        root = load("choose-once-function-contract.json")
        latent = next(
            node
            for node in v.walk(root)
            if isinstance(node, dict) and set(node) == latent_fields
        )
        latent[field] = copy.deepcopy(replacement)
        return root

    expect_diagnostic(
        "LatentSite route prompt must resolve in the declaration table",
        "contract-projection-escapes-scope",
        lambda: v.validate_function_contract(
            malformed_latent_root(
                "route",
                {"kind": "InstallationPromptV1", "prompt_slot": 999},
            )
        ),
    )
    for field in ("receiver", "operation", "route"):
        expect_diagnostic(
            f"LatentSite scalar {field} is a stable diagnostic",
            "contract-component-kind-mismatch",
            lambda field=field: v.validate_function_contract(
                malformed_latent_root(field, 0)
            ),
        )
    malformed_operation_name = load("choose-once-function-contract.json")
    malformed_operation_site = next(
        node
        for node in v.walk(malformed_operation_name)
        if isinstance(node, dict) and set(node) == latent_fields
    )
    malformed_operation_site["operation"]["name"] = 0
    expect_diagnostic(
        "LatentSite operation name exact-decodes as StringV1",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(malformed_operation_name),
    )

    for malformed_stage in (0, [], None):
        expect_diagnostic(
            f"LatentSite scalar stage {malformed_stage!r}",
            "contract-component-kind-mismatch",
            lambda stage=malformed_stage: v.validate_function_contract(
                malformed_latent_root("stage", stage)
            ),
        )
    expect_diagnostic(
        "LatentSite unknown StageV1 tag",
        "unknown-obligation-stage",
        lambda: v.validate_function_contract(
            malformed_latent_root("stage", "Bogus")
        ),
    )
    expect_diagnostic(
        "ResolveAtInstallationV1 is HandlerInstall-only",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(
            malformed_latent_root("stage", "Call")
        ),
    )
    call_route_at_install = malformed_latent_root(
        "route", {"kind": "ResolveAtCallV1", "on_missing": "RootOfEntryV1"},
    )
    expect_diagnostic(
        "ResolveAtCallV1 is Call-only",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(call_route_at_install),
    )
    outer_route = malformed_latent_root(
        "route", {"kind": "OuterOfV1", "prompt_slot": 999},
    )
    outer_route["binders"]["prompt_binders"].append(
        {
            "binder_site_slot": 999,
            "prompt_slot": 999,
            "scope": "LexicalInstallation",
        }
    )
    expect_diagnostic(
        "OuterOfV1 is Kernel-Forward-only",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(outer_route),
    )

    def path_route_root(
        component: str, route: dict[str, Any],
    ) -> dict[str, Any]:
        root = load("choose-once-function-contract.json")
        path = root["computation"]["paths"][0]
        if component == "demand":
            target = path["attributed_demand"][0]
        else:
            target = next(
                atom
                for atom in path["suspension"]["atoms"]
                if atom.get("kind") == "RequestV1"
            )
        target["route"] = copy.deepcopy(route)
        return root

    bound_path_prompt = path_route_root(
        "demand", {"kind": "InstallationPromptV1", "prompt_slot": 999},
    )
    bound_path = bound_path_prompt["computation"]["paths"][0]
    next(
        atom
        for atom in bound_path["suspension"]["atoms"]
        if atom.get("kind") == "RequestV1"
    )["route"] = {"kind": "InstallationPromptV1", "prompt_slot": 999}
    bound_path["LatentSites"][0]["route"] = {
        "kind": "InstallationPromptV1",
        "prompt_slot": 999,
    }
    bound_path_prompt["binders"]["prompt_binders"].append(
        {
            "binder_site_slot": 0,
            "prompt_slot": 999,
            "scope": "LexicalInstallation",
        }
    )
    v.validate_function_contract(bound_path_prompt)

    for component in ("demand", "request"):
        expect_diagnostic(
            f"path {component} prompt route resolves in declaration scope",
            "contract-projection-escapes-scope",
            lambda component=component: v.validate_function_contract(
                path_route_root(
                    component,
                    {"kind": "InstallationPromptV1", "prompt_slot": 999},
                )
            ),
        )
        expect_diagnostic(
            f"path {component} rejects Kernel-Forward-only OuterOfV1",
            "contract-component-kind-mismatch",
            lambda component=component: v.validate_function_contract(
                path_route_root(
                    component,
                    {"kind": "OuterOfV1", "prompt_slot": 999},
                )
            ),
        )
        expect_diagnostic(
            f"path {component} route matches its attributed site",
            "contract-component-kind-mismatch",
            lambda component=component: v.validate_function_contract(
                path_route_root(component, {"kind": "RootOfEntryV1"})
            ),
        )

    scalar_atoms = load("choose-once-function-contract.json")
    scalar_atoms["computation"]["paths"][0]["suspension"]["atoms"] = 0
    expect_diagnostic(
        "SuspensionV1 atoms exact-decodes as a list",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(scalar_atoms),
    )

    wrong_grade = load("choose-once-function-contract.json")
    wrong_grade["computation"]["paths"][0]["suspension"]["grade"] = (
        "MaySuspend"
    )
    expect_diagnostic(
        "SuspensionV1 grade equals the join of atom grades",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(wrong_grade),
    )

    for field in (
        "actual_arguments", "call_obligation_ids", "install_obligation_ids",
    ):
        expect_diagnostic(
            f"LatentSite scalar {field} container",
            "contract-component-kind-mismatch",
            lambda field=field: v.validate_function_contract(
                malformed_latent_root(field, 0)
            ),
        )
    expect_diagnostic(
        "LatentSite scalar SecondarySiteSetV1",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(
            malformed_latent_root("secondary_sites", 0)
        ),
    )
    expect_diagnostic(
        "LatentSite scalar SecondarySiteSetV1 sites list",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(
            malformed_latent_root(
                "secondary_sites", {"kind": "Closed", "sites": 0},
            )
        ),
    )
    expect_diagnostic(
        "LatentSite unknown SecondarySiteSetV1 kind",
        "contract-component-kind-mismatch",
        lambda: v.validate_function_contract(
            malformed_latent_root(
                "secondary_sites", {"kind": "Open", "sites": []},
            )
        ),
    )

    malformed_hash = {
        "kind": "ImportedFunctionRefV2",
        "module": copy.deepcopy(declaration["module"]),
        "name": declaration["name"],
        "artifact_hash": [],
    }
    expect_diagnostic(
        "non-string imported artifact hash is diagnostic directly",
        "contract-component-kind-mismatch",
        lambda: v.validate_operation_signature(
            malformed_signature(malformed_hash), {}, imports=imports,
        ),
    )

    handler_binders = handler["binders"]
    handler_contract = handler["handler_contract"]
    scoped_contracts = {
        binder["slot"]: binder
        for binder in handler_binders["contract_binders"]
    }
    scoped_identities = {
        binder["identity_slot"]: binder
        for binder in handler_binders["identity_binders"]
    }
    scoped_rows = {
        binder["slot"]: binder for binder in handler_binders["row_binders"]
    }
    scoped_owners = {
        binder["slot"]: binder for binder in handler_binders["owner_binders"]
    }
    scoped_clocks = {
        binder["slot"]: binder for binder in handler_binders["clock_binders"]
    }
    declaration_scope = v.DeclarationScope(
        type_parameter_kinds={
            binder["slot"]: binder["kind"]
            for binder in handler_binders["type_binders"]
        },
        row_binders=scoped_rows,
        contract_binders=scoped_contracts,
        identity_binders=scoped_identities,
        handler_contract_binders={
            binder["slot"]
            for binder in handler_binders["contract_binders"]
            if binder.get("kind") == "HandlerContractBinderV2"
        },
        owner_binders=scoped_owners,
        clock_binders=scoped_clocks,
        prompt_binders={
            binder["prompt_slot"]
            for binder in handler_binders["prompt_binders"]
        },
        parameter_binders={
            binder["slot"] for binder in handler_binders["parameter_binders"]
        },
        closure_capture_binders=set(),
    )
    clause = handler_contract["clause_computations"][0]
    clause_path = clause["computation"]["continuation"]["paths"][0]
    latent_template = copy.deepcopy(clause_path["LatentSites"][0])
    forward_template = copy.deepcopy(
        clause_path["outcome"]["forward_contract"]
    )
    forward_evidence = copy.deepcopy(
        clause_path["outcome"]["disposition_evidence"]
    )
    disposition = copy.deepcopy(clause["disposition_binder"])
    minimal_suffix = copy.deepcopy(
        disposition["type"]["value"]["continuation"]
    )

    malformed_hash_type = {
        "kind": "FunctionTypeV2",
        "parameter": copy.deepcopy(target_kind["parameter_type"]),
        "result": copy.deepcopy(target_kind["result_type"]),
        "contract": copy.deepcopy(malformed_hash),
    }
    malformed_hash_summary = {
        "source": None,
        "type": copy.deepcopy(malformed_hash_type),
        "nominal_index": {
            "kind": "LegacyNominalIndexExprV2",
            "value": {"kind": "NoNominalIndexV1"},
        },
        "provenance": {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "StableV1"},
        },
        "capture": {
            "kind": "LegacyCaptureExprV2",
            "value": {"kind": "NoCaptureV1"},
        },
        "usage": None,
        "origin": "task49.cire:malformed-artifact-hash",
    }

    latent_hash = copy.deepcopy(latent_template)
    latent_hash["actual_arguments"] = [
        copy.deepcopy(malformed_hash_summary)
    ]
    latent_hash["instantiated_signature"] = malformed_signature(
        malformed_hash
    )
    latent_hash["call_obligation_ids"] = []
    latent_hash["install_obligation_ids"] = []
    latent_hash["suffix"] = minimal_suffix
    expect_diagnostic(
        "non-string imported artifact hash is diagnostic through LatentSite",
        "contract-component-kind-mismatch",
        lambda: v.validate_latent_site(
            latent_hash,
            returns={},
            imports=imports,
            contract_binders=scoped_contracts,
            local_functions={},
            row_binders=scoped_rows,
            declaration_scope=declaration_scope,
        ),
    )

    forward_hash = copy.deepcopy(forward_template)
    forward_hash["actual_argument_summaries"] = [
        copy.deepcopy(malformed_hash_summary)
    ]
    forward_hash["instantiated_signature"] = malformed_signature(
        malformed_hash
    )
    forward_hash["call_obligation_ids"] = []
    forward_hash["install_obligation_ids"] = []
    expect_diagnostic(
        "non-string imported artifact hash is diagnostic through Forward",
        "contract-component-kind-mismatch",
        lambda: v.validate_forward_contract(
            forward_hash,
            copy.deepcopy(forward_evidence),
            copy.deepcopy(disposition),
            returns={},
            imports=imports,
            contract_binders=scoped_contracts,
            local_functions={},
            clause_operation=copy.deepcopy(clause["operation"]),
            handled_entry=copy.deepcopy(handler_contract["handled_entry"]),
            handler_prompt_slot=handler_contract["prompt_slot"],
            nearest_outer_prompt_slot=forward_hash["route"]["prompt_slot"],
            row_binders=scoped_rows,
            declaration_scope=declaration_scope,
        ),
    )

    for malformed_kind in (0, [], None):
        malformed_parameter = {
            "kind": "ContractParameterRefV2",
            "parameter": {"slot": 0, "kind": malformed_kind},
        }
        expect_diagnostic(
            f"ContractParameterRefV2 scalar kind {malformed_kind!r}",
            "contract-component-kind-mismatch",
            lambda reference=malformed_parameter: v.validate_operation_signature(
                malformed_signature(reference), {}, imports=imports,
            ),
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


def owner_clock_substitution_roots() -> None:
    owner_target = load("choose-once-function-contract.json")
    owner_target["binders"]["owner_binders"].append(
        {
            "slot": 999,
            "source": {"namespace": "Parameter", "slot": 0},
        }
    )
    v.validate_function_contract(owner_target)
    owner_oracle = load("handler-forward-contract.json")
    owner_oracle = replace_scalar(
        owner_oracle,
        owner_oracle["imports"][0]["artifact_hash"],
        v.canonical_hash(owner_target),
    )
    owner_oracle["handler_contract"]["applications"][0]["substitution"][
        "owner_arguments"
    ] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Owner", "slot": 0},
        }
    ]
    validate_handler_identity_oracle(owner_oracle, owner_target)

    unbound_owner = copy.deepcopy(owner_oracle)
    unbound_owner["handler_contract"]["applications"][0]["substitution"][
        "owner_arguments"
    ][0]["value"]["slot"] = 4242
    expect_diagnostic(
        "unbound caller Owner substitution",
        "contract-projection-escapes-scope",
        lambda: validate_handler_identity_oracle(
            unbound_owner, owner_target
        ),
    )

    clock_target = load("choose-once-function-contract.json")
    clock_target["binders"]["owner_binders"].append(
        {
            "slot": 999,
            "source": {"namespace": "Parameter", "slot": 0},
        }
    )
    clock_target["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": frame_clock_family(),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 999},
        }
    )
    clock_target["binders"]["clock_binders"].append(
        {
            "identity": {"namespace": "Identity", "slot": 999},
            "owner": {"namespace": "Owner", "slot": 999},
            "slot": 999,
        }
    )
    v.validate_function_contract(clock_target)
    clock_oracle = load("handler-forward-contract.json")
    clock_oracle = replace_scalar(
        clock_oracle,
        clock_oracle["imports"][0]["artifact_hash"],
        v.canonical_hash(clock_target),
    )
    clock_oracle["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": frame_clock_family(),
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    clock_oracle["binders"]["clock_binders"].append(
        {
            "identity": {"namespace": "Identity", "slot": 999},
            "owner": {"namespace": "Owner", "slot": 0},
            "slot": 999,
        }
    )
    clock_substitution = clock_oracle["handler_contract"]["applications"][0][
        "substitution"
    ]
    clock_substitution["owner_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Owner", "slot": 0},
        }
    ]
    clock_substitution["identity_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Identity", "slot": 999},
        }
    ]
    clock_substitution["clock_arguments"] = [
        {
            "binder_slot": 999,
            "value": {"namespace": "Clock", "slot": 999},
        }
    ]
    validate_handler_identity_oracle(clock_oracle, clock_target)

    unbound_clock = copy.deepcopy(clock_oracle)
    unbound_clock["handler_contract"]["applications"][0]["substitution"][
        "clock_arguments"
    ][0]["value"]["slot"] = 4242
    expect_diagnostic(
        "unbound caller Clock substitution",
        "contract-projection-escapes-scope",
        lambda: validate_handler_identity_oracle(
            unbound_clock, clock_target
        ),
    )

    mismatched_identity_owner = copy.deepcopy(clock_oracle)
    mismatched_identity_owner["binders"]["owner_binders"].append(
        {
            "slot": 998,
            "source": {"namespace": "Parameter", "slot": 0},
        }
    )
    mismatched_identity_owner["binders"]["identity_binders"].append(
        {
            "binder": "OtherOwnerCap",
            "family": frame_clock_family(),
            "identity_slot": 998,
            "owner": {"namespace": "Owner", "slot": 998},
        }
    )
    mismatched_identity_owner["binders"]["clock_binders"].append(
        {
            "identity": {"namespace": "Identity", "slot": 998},
            "owner": {"namespace": "Owner", "slot": 998},
            "slot": 998,
        }
    )
    mismatch_substitution = mismatched_identity_owner["handler_contract"][
        "applications"
    ][0]["substitution"]
    mismatch_substitution["identity_arguments"][0]["value"]["slot"] = 998
    mismatch_substitution["clock_arguments"][0]["value"]["slot"] = 998
    expect_diagnostic(
        "caller Identity substitution violates formal Owner pairing",
        "contract-component-kind-mismatch",
        lambda: validate_handler_identity_oracle(
            mismatched_identity_owner, clock_target
        ),
    )

    mismatched_clock = copy.deepcopy(clock_oracle)
    mismatched_clock["binders"]["identity_binders"].append(
        {
            "binder": "OtherClockCap",
            "family": frame_clock_family(),
            "identity_slot": 998,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    mismatched_clock["binders"]["clock_binders"].append(
        {
            "identity": {"namespace": "Identity", "slot": 998},
            "owner": {"namespace": "Owner", "slot": 0},
            "slot": 998,
        }
    )
    mismatched_clock["handler_contract"]["applications"][0]["substitution"][
        "clock_arguments"
    ][0]["value"]["slot"] = 998
    expect_diagnostic(
        "caller Clock substitution violates formal Identity pairing",
        "contract-component-kind-mismatch",
        lambda: validate_handler_identity_oracle(
            mismatched_clock, clock_target
        ),
    )


def handler_environment_parameter_roots() -> None:
    binding = {
        "slot": {"namespace": "Parameter", "slot": 0},
        "type": int_type(),
        "provenance": {
            "kind": "LegacyProvenanceExprV2",
            "value": {
                "kind": "ArgumentV1",
                "argument": {"namespace": "Parameter", "slot": 0},
            },
        },
        "capture": {
            "kind": "LegacyCaptureExprV2",
            "value": {
                "kind": "ArgumentCaptureV1",
                "argument": {"namespace": "Parameter", "slot": 0},
            },
        },
    }
    bound = load("handler-forward-contract.json")
    bound["handler_contract"]["handler_environment"] = [
        copy.deepcopy(binding)
    ]
    validate_handler_scope_root(bound)

    unbound_provenance = copy.deepcopy(bound)
    unbound_provenance["handler_contract"]["handler_environment"][0][
        "provenance"
    ]["value"]["argument"]["slot"] = 4242
    expect_diagnostic(
        "handler environment provenance has unbound Parameter",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(unbound_provenance),
    )

    unbound_capture = copy.deepcopy(bound)
    unbound_capture["handler_contract"]["handler_environment"][0][
        "capture"
    ]["value"]["argument"]["slot"] = 4242
    expect_diagnostic(
        "handler environment capture has unbound Parameter",
        "contract-projection-escapes-scope",
        lambda: validate_handler_scope_root(unbound_capture),
    )


def replace_resume_answers(
    value: Any, answer_type: dict[str, Any]
) -> None:
    for node in list(v.walk(value)):
        if (
            isinstance(node, dict)
            and node.get("kind") == "ResumeTypeRefV2"
        ):
            node["value"]["answer"] = copy.deepcopy(answer_type)
            node["value"]["continuation"]["answer_type"] = copy.deepcopy(
                answer_type
            )
        elif (
            isinstance(node, dict)
            and "actual_argument_summaries" in node
            and isinstance(node.get("continuation"), dict)
        ):
            node["continuation"]["answer_type"] = copy.deepcopy(answer_type)


def evaluated_clause_and_return_boundary_roots() -> None:
    caller_scoped = load("handler-forward-contract.json")
    caller_scoped["binders"]["type_binders"].append(
        {"slot": 999, "kind": "Effect"}
    )
    caller_scoped["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": {"kind": "TypeParameterV2", "slot": 999},
            "identity_slot": 999,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    capability = {
        "kind": "CapabilityTypeV2",
        "identity": {"namespace": "Identity", "slot": 999},
        "family": {"kind": "TypeParameterV2", "slot": 999},
    }
    callback_kind = {
        "kind": "FunctionContractKindV2",
        "parameter_type": copy.deepcopy(capability),
        "result_type": copy.deepcopy(capability),
        "visible_row": {"kind": "EmptyV1"},
    }
    caller_scoped["binders"]["contract_binders"].append(
        {
            "kind": "FunctionContractBinderV2",
            "slot": 998,
            "parameter_type": copy.deepcopy(capability),
            "result_type": copy.deepcopy(capability),
            "visible_row": {"kind": "EmptyV1"},
        }
    )
    caller_function_type = {
        "kind": "FunctionTypeV2",
        "parameter": copy.deepcopy(capability),
        "result": copy.deepcopy(capability),
        "contract": {"slot": 998, "kind": copy.deepcopy(callback_kind)},
    }
    replace_resume_answers(
        caller_scoped["handler_contract"], caller_function_type
    )
    validate_handler_scope_root(caller_scoped)

    fresh_boundary = load("handler-forward-contract.json")
    fresh_boundary["binders"]["identity_binders"].append(
        {
            "binder": "FreshCap",
            "family": frame_clock_family(),
            "identity_slot": 0,
            "owner": {"namespace": "Owner", "slot": 0},
        }
    )
    fresh_boundary["binders"]["clock_binders"].append(
        {
            "identity": {"namespace": "Identity", "slot": 0},
            "owner": {"namespace": "Owner", "slot": 0},
            "slot": 0,
        }
    )
    nested = load("mixed-next-callback-function-contract.json")
    for node in v.walk(nested):
        if not isinstance(node, dict):
            continue
        if (
            "return_binder" in node
            and node["return_binder"].get("slot") == 0
        ):
            node["return_binder"]["slot"] = 10
        if (
            isinstance(node.get("kind"), str)
            and node["kind"] in v.RETURN_KINDS
            and node.get("return_slot") == 0
        ):
            node["return_slot"] = 10
    v.validate_function_contract(nested)
    nested_function_type = {
        "kind": "FunctionTypeV2",
        "parameter": copy.deepcopy(
            nested["declaration_kind"]["parameter_type"]
        ),
        "result": copy.deepcopy(
            nested["declaration_kind"]["result_type"]
        ),
        "contract": nested,
    }
    replace_resume_answers(
        fresh_boundary["handler_contract"], nested_function_type
    )
    validate_handler_scope_root(fresh_boundary)

    fresh_handler_boundary = load("handler-forward-contract.json")
    nested_handler = copy.deepcopy(
        fresh_handler_boundary["handler_contract"]
    )
    nested_handler["applications"] = []
    nested_handler["return_computation"] = copy.deepcopy(
        nested_handler["return_computation"]["continuation"]
    )
    nested_clause = nested_handler["clause_computations"][0]
    nested_clause["computation"]["continuation"] = (
        v.pure_return_continuation(
            copy.deepcopy(nested_handler["return_computation"]["paths"][0]),
            10,
        )
    )
    nested_handler_type = {
        "kind": "HandlerTemplateTypeV2",
        "family": legacy_type(
            copy.deepcopy(nested_handler["handled_entry"]["family"])
        ),
        "owner": {"namespace": "Owner", "slot": 0},
        "input": int_type(),
        "answer": int_type(),
        "residual_row": {"kind": "EmptyV1"},
        "contract": nested_handler,
        "policy": {"kind": "PureV1"},
    }
    handler_scope = v.declaration_scope_from_binders(
        fresh_handler_boundary["binders"]
    )
    v.validate_handler_contract(
        nested_handler,
        type_parameter_kinds=handler_scope.type_parameter_kinds,
        row_binders=handler_scope.row_binders,
        contract_binders=handler_scope.contract_binders,
        identity_binders=handler_scope.identity_binders,
        handler_contract_binders=handler_scope.handler_contract_binders,
        owner_binders=handler_scope.owner_binders,
        clock_binders=handler_scope.clock_binders,
        parameter_binders=handler_scope.parameter_binders,
        closure_capture_binders=handler_scope.closure_capture_binders,
    )
    assert not v.contains_return_ref(nested_handler_type, 10)


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
    function["binders"]["prompt_binders"] = copy.deepcopy(
        handler_oracle["binders"]["prompt_binders"]
    )
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
        owner_binders={
            binder["slot"]: binder for binder in binders["owner_binders"]
        },
        clock_binders={
            binder["slot"]: binder for binder in binders["clock_binders"]
        },
        prompt_binders={
            binder["prompt_slot"] for binder in binders["prompt_binders"]
        },
        parameter_binders={
            binder["slot"] for binder in binders["parameter_binders"]
        },
        closure_capture_binders={
            binding["slot"]["slot"]
            for binding in function["closure_environment"]
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
quantified_and_capability_roots()
quantified_import_and_handler_boundary_roots()
operation_signature_contract_scope_roots()
capture_avoiding_substitution_roots()
packed_alpha_totality_roots()
adjacent_alpha_occurrence_totality_roots()
task49_schema_scope_totality_roots()
row_scope_roots()
handler_entry_lacks_roots()
named_lacks_roots()
public_selector_scope_roots()
used_nominal_effect_roots()
imported_identity_substitution_roots()
handler_caller_scope_roots()
owner_clock_substitution_roots()
handler_environment_parameter_roots()
evaluated_clause_and_return_boundary_roots()
handler_computation_scope_roots()
handler_recursive_descendant_scope_roots()
validate_inline_function_fresh_scope_root()
print("PASS: 142 task-46 exact-schema/scope/substitution complete-root probes")
