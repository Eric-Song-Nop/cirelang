#!/usr/bin/env python3
"""Execute the Cire-TR₀ V2 JSON interface, mutation, and runtime oracles.

This is a small normative test decoder for the frozen corpus, not a compiler
implementation. It deliberately evaluates each mutation through the decoder
named by the case and checks the exact diagnostic that decoder emits.
"""

from __future__ import annotations

import copy
import hashlib
import json
import sys
import unicodedata
from pathlib import Path
from typing import Any, Callable, Iterable


ROOT = Path(__file__).resolve().parent
INTERFACES = ROOT / "interfaces"
MUTATIONS = ROOT / "mutations" / "v1-rejects-v2-tags.json"
RUNTIME = ROOT / "runtime" / "packed-next-lease-runtime.json"
PROFILE = "Cire-TR₀/2026-08-01"


class Diagnostic(Exception):
    def __init__(self, diagnostic_id: str):
        super().__init__(diagnostic_id)
        self.diagnostic_id = diagnostic_id


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def reject(condition: bool, diagnostic_id: str) -> None:
    if condition:
        raise Diagnostic(diagnostic_id)


def exact_fields(value: dict[str, Any], expected: set[str], label: str) -> None:
    require(set(value) == expected, f"{label} fields: expected {sorted(expected)}, got {sorted(value)}")


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def check_nfc(value: Any, where: str = "$") -> None:
    if isinstance(value, str):
        require(unicodedata.normalize("NFC", value) == value, f"non-NFC string at {where}")
        require(not any(0xD800 <= ord(char) <= 0xDFFF for char in value), f"surrogate scalar at {where}")
    elif isinstance(value, list):
        for index, member in enumerate(value):
            check_nfc(member, f"{where}/{index}")
    elif isinstance(value, dict):
        for key, member in value.items():
            check_nfc(key, f"{where}/<key>")
            check_nfc(member, f"{where}/{key}")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8", newline="") as handle:
        value = json.load(handle, object_pairs_hook=unique_object)
    check_nfc(value)
    return value


def utf16_key(value: str) -> bytes:
    return value.encode("utf-16-be", "strict")


def jcs(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        raise ValueError("the V2 wire domain forbids floating-point numbers")
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(jcs(member) for member in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=utf16_key)
        return "{" + ",".join(jcs(key) + ":" + jcs(value[key]) for key in keys) + "}"
    raise TypeError(f"unsupported JSON value: {type(value).__name__}")


def canonical_hash(value: Any) -> str:
    encoded = jcs(value).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def walk(value: Any) -> Iterable[Any]:
    yield value
    if isinstance(value, dict):
        for member in value.values():
            yield from walk(member)
    elif isinstance(value, list):
        for member in value:
            yield from walk(member)


def pointer_tokens(pointer: str) -> list[str]:
    require(pointer == "" or pointer.startswith("/"), f"invalid JSON pointer: {pointer!r}")
    if not pointer:
        return []
    return [token.replace("~1", "/").replace("~0", "~") for token in pointer[1:].split("/")]


def pointer_get(value: Any, pointer: str) -> Any:
    current = value
    for token in pointer_tokens(pointer):
        current = current[int(token)] if isinstance(current, list) else current[token]
    return current


def pointer_parent(value: Any, pointer: str) -> tuple[Any, str]:
    tokens = pointer_tokens(pointer)
    require(tokens, "a patch operation may not replace the document root")
    current = value
    for token in tokens[:-1]:
        current = current[int(token)] if isinstance(current, list) else current[token]
    return current, tokens[-1]


def apply_patch(document: Any, operations: list[dict[str, Any]]) -> Any:
    result = copy.deepcopy(document)
    for operation in operations:
        op = operation["op"]
        parent, token = pointer_parent(result, operation["path"])
        if op == "remove":
            if isinstance(parent, list):
                del parent[int(token)]
            else:
                del parent[token]
        elif op in {"add", "replace", "copy"}:
            replacement = copy.deepcopy(pointer_get(result, operation["from"])) if op == "copy" else copy.deepcopy(operation["value"])
            if isinstance(parent, list):
                index = len(parent) if token == "-" else int(token)
                if op == "add":
                    parent.insert(index, replacement)
                else:
                    parent[index] = replacement
            else:
                parent[token] = replacement
        else:
            raise AssertionError(f"unsupported JSON Patch operation: {op}")
    return result


def slot(namespace: str, number: int) -> dict[str, Any]:
    return {"namespace": namespace, "slot": number}


def validate_type_v2(type_ref: Any) -> None:
    require(isinstance(type_ref, dict), "TypeRefV2 must be an object")
    kind = type_ref.get("kind")
    require(isinstance(kind, str) and kind.endswith("V2"), f"bare/non-V2 type node: {kind!r}")
    if kind == "LegacyTypeRefV2":
        require(isinstance(type_ref.get("value"), dict), "LegacyTypeRefV2.value missing")
        reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(type_ref["value"])), "unsupported-contract-schema-version")
    elif kind in {"ApplyTypeV2", "NominalTypeV2"}:
        for argument in type_ref.get("arguments", []):
            validate_type_v2(argument)
    elif kind == "FunctionTypeV2":
        validate_type_v2(type_ref["parameter"])
        validate_type_v2(type_ref["result"])
        contract = type_ref["contract"]
        require(
            contract.get("artifact") == "FunctionContractV2"
            or isinstance(contract.get("slot"), int)
            or contract.get("kind") in {"ImportedFunctionRefV2", "LocalFunctionRefV2", "ContractParameterRefV2"},
            "FunctionTypeV2 contract must be concrete, a ContractParameterV2, or a ContractRefV2",
        )
    elif kind == "NextTypeV2":
        require(type_ref["clock"].get("namespace") == "Clock", "NextTypeV2 clock namespace")
        validate_type_v2(type_ref["payload"])
        later = type_ref["later_contract"]
        if not isinstance(later.get("slot"), int):
            require(later["provenance"].get("kind") in {"LegacyProvenanceExprV2", "ReturnProvenanceV2", "EnvironmentV2", "JoinProvenanceV2"}, "NextTypeV2 has a bare V1 Later provenance")
            require(later["capture"].get("kind") in {"LegacyCaptureExprV2", "ReturnCaptureV2", "UnionCaptureV2"}, "NextTypeV2 has a bare V1 Later capture")
    elif kind == "ResumeTypeRefV2":
        validate_resume(type_ref["value"])
    else:
        for key in ("payload", "value", "answer", "argument", "input", "result", "body"):
            if isinstance(type_ref.get(key), dict) and str(type_ref[key].get("kind", "")).endswith("V2"):
                validate_type_v2(type_ref[key])
        for argument in type_ref.get("arguments", []):
            if isinstance(argument, dict) and str(argument.get("kind", "")).endswith("V2"):
                validate_type_v2(argument)


def validate_value_summary(summary: dict[str, Any]) -> None:
    exact_fields(summary, {"source", "type", "nominal_index", "provenance", "capture", "usage", "origin"}, "ValueSummaryExprV2")
    validate_type_v2(summary["type"])
    require(summary["nominal_index"].get("kind") in {"LegacyNominalIndexExprV2", "ReturnNominalIndexV2"}, "ValueSummaryExprV2 nominal index is not recursive V2")
    require(summary["provenance"].get("kind") in {"LegacyProvenanceExprV2", "ReturnProvenanceV2", "EnvironmentV2", "JoinProvenanceV2"}, "ValueSummaryExprV2 provenance is not V2")
    require(summary["capture"].get("kind") in {"LegacyCaptureExprV2", "ReturnCaptureV2", "UnionCaptureV2"}, "ValueSummaryExprV2 capture is not V2")
    usage = summary.get("usage")
    require(usage is None or usage.get("kind") in {"LegacyUsageExprV2", "ReturnUsageV2"}, "ValueSummaryExprV2 usage is not recursive V2")


def contains_return_ref(value: Any, return_slot: int) -> bool:
    for node in walk(value):
        if isinstance(node, dict) and node.get("return_slot") == return_slot and node.get("kind") in {
            "ReturnSlotRefV2", "ReturnWorldV2", "ReturnProvenanceV2", "ReturnCaptureV2", "ReturnNominalIndexV2", "ReturnUsageV2", "ReturnBoundResultV2"
        }:
            return True
    return False


def validate_return_binder(binder: dict[str, Any]) -> None:
    expected = {"slot", "type", "world", "nominal_index", "provenance", "capture", "usage"}
    exact_fields(binder, expected, "ReturnBinderV2")
    validate_type_v2(binder["type"])
    require(binder["nominal_index"].get("kind") in {"LegacyNominalIndexExprV2", "ReturnNominalIndexV2"}, "ReturnBinderV2 nominal index")
    require(not contains_return_ref({key: value for key, value in binder.items() if key != "slot"}, binder["slot"]), "ReturnBinderV2 is self-referential")


def validate_resume(resumption: dict[str, Any]) -> None:
    require(resumption["usage"] in {"Zero", "Once", "Many"}, "ResumeTypeV2 usage")
    validate_type_v2(resumption["argument"])
    validate_type_v2(resumption["answer"])
    suffix = resumption["continuation"]
    validate_type_v2(suffix["answer_type"])
    validate_computation(suffix["computation"], {app["application_slot"] for app in suffix.get("applications", [])})
    for binding in suffix.get("live_bindings", []):
        validate_type_v2(binding["type"])
        usage = binding["usage"]["kind"]
        require(usage in {"Zero", "Once", "Many"}, "LiveAcrossSiteV2 usage")
        require(usage == "Zero" or binding["type"].get("kind") == "ResumeTypeRefV2", "ordinary live data cannot carry authority usage")


def validate_park(park: dict[str, Any]) -> None:
    exact_fields(park, {"owner_slot", "site_slot", "claim_cell_slot", "source", "completion_port", "claim", "disposition", "required_phase", "origin"}, "ParkContractV2")
    owner = slot("Owner", park["owner_slot"])
    source = park["source"]
    port = park["completion_port"]
    disposition = park["disposition"]
    resumption = disposition["resumption"]
    require(source["owner"] == owner == port["owner"] == resumption["owner"], "ParkContractV2 Owner mismatch")
    reject(source["value_type"] != port["value_type"] or source["value_type"] != resumption["argument"], "park-source-payload-mismatch")
    reject(resumption["answer"] != resumption["continuation"]["answer_type"], "park-resumption-type-mismatch")
    claim_slot = park["claim_cell_slot"]
    require(claim_slot == port["claim_cell_slot"] == disposition["claim_cell_slot"] == park["claim"]["claim_cell_slot"], "ParkContractV2 claim-cell mismatch")
    require(park["site_slot"] == disposition["continuation_site_slot"], "ParkContractV2 site mismatch")
    require(resumption["usage"] == "Once", "ParkContractV2 disposition must be one-shot")
    validate_resume(resumption)


def obligation_value(obligation: dict[str, Any]) -> dict[str, Any]:
    return obligation["value"] if obligation.get("kind") == "LegacyObligationV2" else obligation


def validate_path(path: dict[str, Any]) -> None:
    exact_fields(path, {"outcome", "residual_row", "attributed_demand", "suspension", "semantic_summary", "usage", "required_phase", "ParametricObligations", "LatentSites"}, "PathContractV2")
    q = [obligation_value(obligation) for obligation in path.get("ParametricObligations", [])]
    q_keys = {(entry["stage"], entry["id"]) for entry in q}
    for latent in path.get("LatentSites", []):
        for summary in latent.get("actual_arguments", []):
            validate_value_summary(summary)
        for local_id in latent.get("call_obligation_ids", []):
            reject(("Call", local_id) not in q_keys, "projected-obligation-stage-lost")
        for local_id in latent.get("install_obligation_ids", []):
            reject(("HandlerInstall", local_id) not in q_keys, "projected-obligation-stage-lost")
    outcome = path["outcome"]
    if outcome["kind"] == "TransfersV2":
        validate_park(outcome["park_contract"])


def validate_computation(computation: dict[str, Any], application_slots: set[int]) -> None:
    kind = computation.get("kind")
    if kind == "LiteralPathsV2":
        require(bool(computation.get("paths")), "LiteralPathsV2 must be nonempty")
        for path in computation["paths"]:
            validate_path(path)
    elif kind == "InvokeV2":
        require(computation["application_slot"] in application_slots, "InvokeV2 references an unknown application")
    elif kind == "PathBindV2":
        reject(computation.get("terminal_policy") != "PreserveTerminalV2", "path-bind-terminal-not-preserved")
        validate_computation(computation["prefix"], application_slots)
        validate_return_binder(computation["return_binder"])
        validate_computation(computation["continuation"], application_slots)
    elif kind == "JoinV2":
        require(bool(computation.get("members")), "JoinV2 must be nonempty")
        for member in computation["members"]:
            validate_computation(member, application_slots)
    else:
        raise Diagnostic("path-bind-terminal-not-preserved")


def binder_kind(binder: dict[str, Any]) -> dict[str, Any]:
    require(binder.get("kind") == "FunctionContractBinderV2", "expected a FunctionContractBinderV2")
    return {
        "kind": "FunctionContractKindV2",
        "parameter_type": binder["parameter_type"],
        "result_type": binder["result_type"],
        "visible_row": binder["visible_row"],
    }


def unique_slots(bindings: list[dict[str, Any]], key: str, label: str) -> set[int]:
    values = [binding[key] for binding in bindings]
    require(len(values) == len(set(values)), f"duplicate {label} slot")
    return set(values)


def validate_declaration_binders(binders: dict[str, Any], closure_environment: list[dict[str, Any]]) -> None:
    exact_fields(
        binders,
        {"parameter_binders", "type_binders", "row_binders", "contract_binders", "owner_binders", "clock_binders", "identity_binders", "prompt_binders"},
        "DeclarationBindersV2",
    )
    parameters = unique_slots(binders["parameter_binders"], "slot", "Parameter")
    owners = unique_slots(binders["owner_binders"], "slot", "Owner")
    identities = unique_slots(binders["identity_binders"], "identity_slot", "Identity")
    clocks = unique_slots(binders["clock_binders"], "slot", "Clock")
    unique_slots(binders["contract_binders"], "slot", "Contract")
    closure_slots = {binding["slot"]["slot"] for binding in closure_environment if binding["slot"]["namespace"] == "ClosureCapture"}
    for owner in binders["owner_binders"]:
        source = owner["source"]
        require(
            (source["namespace"] == "Parameter" and source["slot"] in parameters)
            or (source["namespace"] == "ClosureCapture" and source["slot"] in closure_slots),
            "Owner binder source is out of scope",
        )
    for identity in binders["identity_binders"]:
        require(identity["owner"] == slot("Owner", identity["owner"]["slot"]) and identity["owner"]["slot"] in owners, "Identity Owner is out of scope")
    identity_by_slot = {binding["identity_slot"]: binding for binding in binders["identity_binders"]}
    for clock in binders["clock_binders"]:
        identity_ref = clock["identity"]
        require(identity_ref["namespace"] == "Identity" and identity_ref["slot"] in identities, "Clock identity is out of scope")
        require(clock["owner"] == identity_by_slot[identity_ref["slot"]]["owner"], "Clock/Identity Owner mismatch")
    require(all(clock >= 0 for clock in clocks), "Clock slot must be u32")


def validate_application_instantiation(application: dict[str, Any]) -> None:
    exact_fields(application, {"application_slot", "contract", "callee_summary", "actual_arguments", "substitution", "entry_world", "origin"}, "AppliedContractV2")
    for summary in [application["callee_summary"], *application["actual_arguments"]]:
        validate_value_summary(summary)
    type_arguments = application["substitution"].get("type_arguments", [])
    actuals = application.get("actual_arguments", [])
    if len(type_arguments) == 1 and len(actuals) == 1:
        actual_type = actuals[0]["type"]
        if actual_type.get("kind") == "LegacyTypeRefV2" and actual_type["value"].get("kind") == "ApplyTypeV1":
            expected = actual_type["value"].get("arguments", [None])[0]
            supplied = type_arguments[0]["value"]
            supplied_v1 = supplied.get("value") if supplied.get("kind") == "LegacyTypeRefV2" else None
            reject(expected != supplied_v1, "contract-parameter-inconsistent-instantiation")


def validate_function_contract(contract: dict[str, Any]) -> None:
    exact_fields(contract, {"artifact", "profile", "schema_version", "declaration_kind", "binders", "applications", "computation", "closure_environment"}, "FunctionContractV2")
    require(contract.get("artifact") == "FunctionContractV2", "not a FunctionContractV2")
    require(contract.get("profile") == PROFILE and contract.get("schema_version") == 2, "wrong FunctionContractV2 profile")
    require("declaration_kind" in contract, "FunctionContractV2 declaration_kind missing")
    binders = contract["binders"]
    validate_declaration_binders(binders, contract.get("closure_environment", []))
    contract_binders = {binder["slot"]: binder for binder in binders.get("contract_binders", [])}
    declaration_kind = contract["declaration_kind"]
    if declaration_kind is not None:
        require(declaration_kind.get("kind") == "FunctionContractKindV2", "FunctionContractV2 declaration kind")
        validate_type_v2(declaration_kind["parameter_type"])
        validate_type_v2(declaration_kind["result_type"])
    for binder in contract_binders.values():
        require(binder.get("kind") == "FunctionContractBinderV2", "unsupported ContractBinderV2 in fixture")
        validate_type_v2(binder["parameter_type"])
        validate_type_v2(binder["result_type"])
    for parameter in binders.get("parameter_binders", []):
        validate_type_v2(parameter["type"])
    for binding in contract.get("closure_environment", []):
        validate_type_v2(binding["type"])
    slots: set[int] = set()
    for application in contract["applications"]:
        app_slot = application["application_slot"]
        require(app_slot not in slots, "duplicate AppliedContractV2 slot")
        slots.add(app_slot)
        validate_application_instantiation(application)
        reference = application["contract"]
        if reference["kind"] == "ContractParameterRefV2":
            parameter = reference["parameter"]
            require(parameter["slot"] in contract_binders, "unbound ContractParameterRefV2")
            require(parameter["kind"] == binder_kind(contract_binders[parameter["slot"]]), "ContractParameterRefV2 kind mismatch")
    validate_computation(contract["computation"], slots)
    for node in walk(contract):
        if isinstance(node, dict) and {"source", "type", "nominal_index", "provenance", "capture", "usage", "origin"} <= set(node):
            validate_value_summary(node)
        if isinstance(node, dict) and node.get("kind") == "NextTypeV2":
            validate_type_v2(node)


def validate_projection_evidence(oracle: dict[str, Any], source: dict[str, Any]) -> None:
    source_paths = source["computation"]["prefix"]["paths"] if source["computation"].get("kind") == "PathBindV2" else source["computation"]["paths"]
    source_q = [obligation_value(item) for item in source_paths[0]["ParametricObligations"]]
    call_ids = {item["id"] for item in source_q if item["stage"] == "Call"}
    install_ids = {item["id"] for item in source_q if item["stage"] == "HandlerInstall"}
    source_sites = {site["site_slot"] for site in source_paths[0]["LatentSites"]}
    seen: set[tuple[int, int]] = set()
    expected_source_hash = canonical_hash(source)
    for evidence in oracle["projection_evidence"]:
        app = evidence["application_slot"]
        require(evidence["source_artifact_hash"] == expected_source_hash, "projection evidence source hash mismatch")
        for key in evidence["discharged_call_keys"]:
            require(key["application_slot"] == app and key["local_id"] in call_ids, "discharged Call key mismatch")
            seen.add((app, key["local_id"]))
        for retained in evidence["retained_obligations"]:
            key = retained["key"]
            require(retained["stage"] == "HandlerInstall" and retained["source_local_id"] in install_ids, "retained obligation mismatch")
            require(key["application_slot"] == app and key["local_id"] == retained["source_local_id"], "retained obligation key mismatch")
            seen.add((app, key["local_id"]))
        for retained in evidence["retained_latent_sites"]:
            key = retained["key"]
            reject(key["application_slot"] != app or retained["source_site_slot"] not in source_sites, "projected-latent-site-key-mismatch")
            for install_key in retained["install_obligation_keys"]:
                reject(install_key["application_slot"] != app or install_key["local_id"] not in install_ids, "projected-latent-site-key-mismatch")
            seen.add((app, key["local_id"]))
    require(len({app for app, _ in seen}) == len(oracle["projection_evidence"]), "projection applications collapsed")


def source_return_path(source: dict[str, Any]) -> dict[str, Any]:
    computation = source["computation"]
    if computation["kind"] == "PathBindV2":
        computation = computation["continuation"]
    return next(path for path in computation["paths"] if path["outcome"]["kind"] == "ReturnsV2")


def instantiate_source_result(source: dict[str, Any], application: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    path = source_return_path(source)
    outcome = path["outcome"]
    transformer = outcome["result_transformer"]
    if transformer["kind"] == "LegacyResultTransformerV2":
        value = transformer["value"]
        provenance = {"kind": "LegacyProvenanceExprV2", "value": value["provenance"]}
        capture = {"kind": "LegacyCaptureExprV2", "value": value["capture"]}
    else:
        provenance = copy.deepcopy(transformer["provenance"])
        capture = copy.deepcopy(transformer["capture"])
        actual_source = application["actual_arguments"][0]["source"]
        require(actual_source and actual_source["kind"] == "LegacySlotRefV2", "source projection needs an actual slot")
        for expression in (provenance, capture):
            for node in walk(expression):
                if isinstance(node, dict) and "argument" in node and node["argument"] == slot("Parameter", 0):
                    node["argument"] = copy.deepcopy(actual_source["value"])
    result_type = copy.deepcopy(source["declaration_kind"]["result_type"])
    if result_type.get("kind") == "TypeParameterV2":
        argument = next(item for item in application["substitution"]["type_arguments"] if item["binder_slot"] == result_type["slot"])
        result_type = copy.deepcopy(argument["value"])
    return result_type, outcome["transition"], provenance, capture


def validate_application_return_binder(source: dict[str, Any], application: dict[str, Any], binder: dict[str, Any]) -> None:
    result_type, transition, provenance, capture = instantiate_source_result(source, application)
    reject(binder["type"] != result_type or binder["provenance"] != provenance or binder["capture"] != capture, "contract-parameter-inconsistent-instantiation")
    expected_world = {
        "kind": "ApplyWorldTransitionV2",
        "input": {"application_slot": application["application_slot"], "kind": "ApplicationEntryWorldV2"},
        "transition": transition,
    }
    reject(binder["world"] != expected_world, "contract-parameter-inconsistent-instantiation")


def resolve_imports(oracle: dict[str, Any], directory: Path) -> dict[str, dict[str, Any]]:
    resolved: dict[str, dict[str, Any]] = {}
    for imported in oracle.get("imports", []):
        target = load_json(directory / imported["file"])
        require(target.get("artifact") == "FunctionContractV2", "ImportedFunctionRefV2 must target a root FunctionContractV2")
        require(target.get("declaration_kind") is not None, "imported FunctionContractV2 declaration_kind must be exact")
        require(canonical_hash(target) == imported["artifact_hash"], f"canonical import hash mismatch for {imported['file']}")
        resolved[imported["artifact_hash"]] = target
    return resolved


def validate_q_oracle(oracle: dict[str, Any], imported: dict[str, dict[str, Any]]) -> None:
    source = next(iter(imported.values()))
    require(source["declaration_kind"]["visible_row"]["entries"][0]["family"]["name"] == "Choice", "Q oracle imported wrong contract")
    validate_projection_evidence(oracle, source)
    apps = oracle["contract"]["applications"]
    require([app["application_slot"] for app in apps] == [0, 1], "Q oracle must invoke twice")
    require(apps[0]["entry_world"] != apps[1]["entry_world"], "Q oracle application worlds alias")
    binders = [oracle["contract"]["computation"]["return_binder"], oracle["contract"]["computation"]["continuation"]["return_binder"]]
    for app, binder in zip(apps, binders):
        validate_application_return_binder(source, app, binder)
    for app in apps:
        require(app["contract"]["artifact_hash"] in imported, "Q oracle application import not resolved")


def validate_hof_oracle(oracle: dict[str, Any], imported: dict[str, dict[str, Any]]) -> None:
    callback_hash = next(item["artifact_hash"] for item in oracle["imports"] if item["function_name"] == "mixed_next_callback")
    apply_later_hash = next(item["artifact_hash"] for item in oracle["imports"] if item["function_name"] == "apply_later")
    source = imported[callback_hash]
    apply_later = imported[apply_later_hash]
    require(oracle["contract"] == apply_later, "HOF embedded apply_later differs from imported root contract")
    source_kind = source["declaration_kind"]
    require(source_kind["visible_row"]["entries"][0]["family"]["name"] == "Branch", "HOF callback visible row")
    outcomes = [path["outcome"]["kind"] for path in source["computation"]["continuation"]["paths"]]
    require(outcomes == ["ReturnsV2", "AbortsV2", "TransfersV2", "TransfersV2"], "HOF callback mixed flow")
    validate_projection_evidence(oracle, source)
    contract = oracle["contract"]
    generic_binder = contract["binders"]["contract_binders"][0]
    require(binder_kind(generic_binder) == source_kind, "HOF generic callback binder/import kind mismatch")
    callback_parameter = contract["binders"]["parameter_binders"][1]["type"]
    require(callback_parameter["kind"] == "FunctionTypeV2" and callback_parameter["contract"] == {"slot": 0, "kind": source_kind}, "HOF runtime callback type is not tied to the contract binder")
    apps = contract["applications"]
    require([app["application_slot"] for app in apps] == [0, 1], "HOF substituted callback must be invoked twice")
    require(apps[0]["entry_world"] != apps[1]["entry_world"], "HOF application worlds alias")
    require(apps[0]["actual_arguments"] != apps[1]["actual_arguments"], "HOF per-application actual summaries alias")
    require(all(app["contract"]["kind"] == "ContractParameterRefV2" for app in apps), "HOF calls must share one ContractParameterRefV2")
    require(apps[0]["contract"] == apps[1]["contract"], "HOF callback ContractRef changed between invocations")
    binders = [contract["computation"]["return_binder"], contract["computation"]["continuation"]["return_binder"]]
    for app, binder in zip(apps, binders):
        validate_application_return_binder(source, app, binder)
    consumer_app = oracle["consumer_contract"]["applications"][0]
    require(consumer_app["contract"]["artifact_hash"] == apply_later_hash, "HOF consumer did not import apply_later root contract")
    require(len(consumer_app["actual_arguments"]) == 3, "HOF consumer omitted a runtime actual")
    require(consumer_app["actual_arguments"][1]["type"]["kind"] == "FunctionTypeV2", "HOF runtime callback actual missing")
    substitution = consumer_app["substitution"]["contract_arguments"]
    require(len(substitution) == 1 and substitution[0]["binder_slot"] == 0, "HOF callback substitution missing")
    require(consumer_app["substitution"]["owner_arguments"] == [{"binder_slot": 0, "value": slot("Owner", 0)}], "HOF owner substitution missing")
    require(consumer_app["substitution"]["identity_arguments"] == [{"binder_slot": 0, "value": slot("Identity", 0)}], "HOF identity substitution missing")
    require(consumer_app["substitution"]["clock_arguments"] == [{"binder_slot": 0, "value": slot("Clock", 0)}], "HOF clock substitution missing")
    reference = substitution[0]["contract"]
    require(reference["artifact_hash"] in imported, "HOF callback substitution import not resolved")
    runtime_parameter_type = oracle["consumer_contract"]["binders"]["parameter_binders"][1]["type"]
    runtime_actual_type = consumer_app["actual_arguments"][1]["type"]
    require(runtime_parameter_type == runtime_actual_type, "HOF runtime callback parameter/actual type mismatch")
    require(runtime_actual_type["contract"] == reference, "HOF runtime callback value is not tied to the substituted imported ContractRefV2")
    require(runtime_actual_type["parameter"] == source_kind["parameter_type"] and runtime_actual_type["result"] == source_kind["result_type"], "HOF runtime callback FunctionTypeV2/import declaration kind mismatch")


def validate_interface_oracle(oracle: dict[str, Any], directory: Path) -> None:
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong interface oracle profile")
    imported = resolve_imports(oracle, directory)
    validate_function_contract(oracle["contract"])
    if "consumer_contract" in oracle:
        validate_function_contract(oracle["consumer_contract"])
    for root_contract in [oracle["contract"], *([oracle["consumer_contract"]] if "consumer_contract" in oracle else [])]:
        for node in walk(root_contract):
            if isinstance(node, dict) and node.get("kind") == "ImportedFunctionRefV2":
                require(node["artifact_hash"] in imported, "ImportedFunctionRefV2 does not resolve to a declared root import")
    subject = oracle.get("subject", "")
    if subject == "consumer::invoke_choose_twice":
        validate_q_oracle(oracle, imported)
    elif subject.startswith("cross-module-HOF"):
        validate_hof_oracle(oracle, imported)


def validate_clock_package(package: dict[str, Any]) -> None:
    exact_fields(package, {"artifact", "profile", "schema_version", "storage_owner", "child_owner_binder", "owner_relation", "clock_binder", "summary_binder", "body", "control_protocol", "sealed_origin"}, "PackedNextPackageV2")
    require(package.get("artifact") == "PackedNextPackageV2" and package.get("schema_version") == 2, "PackedNext package header")
    relation = package["owner_relation"]
    child = slot("Owner", package["child_owner_binder"]["owner_slot"])
    require(relation == {"child": child, "parent": package["storage_owner"], "relation": "DirectChild", "sealed_origin": "cire.temporal:pack_next"}, "PackedNext direct-child witness")
    clock = package["clock_binder"]
    reject(clock["family_witness"] != {"kind": "CanonicalFrameClockV2", "module": ["cire", "temporal"], "name": "FrameClock", "sealed_origin": "cire.temporal:FrameClock"}, "clock-package-family-not-clock-indexing")
    require(clock["owner"] == child, "PackedNext clock Owner mismatch")
    identity = slot("Identity", clock["identity_slot"])
    clock_ref = slot("Clock", clock["clock_refinement"]["clock_slot"])
    require(clock["clock_refinement"]["identity"] == identity, "PackedNext identity/clock pairing")
    summary = package["summary_binder"]["kind"]
    require(summary["kind"] == "ClockPackageSummaryKindV2" and summary["clock"] == clock_ref, "PackedNext summary binder")
    body = package["body"]
    require(body["kind"] == "NextTypeV2" and body["clock"] == clock_ref and body["payload"] == summary["payload_type"], "PackedNext body/summary mismatch")
    validate_type_v2(body)
    protocol = package["control_protocol"]
    require(protocol["states"] == ["Open(n)", "Closing(n)", "Closed"], "PackedNext control states")
    require(len(protocol["acquire"]) == 3 and len(protocol["dispose"]) == 4 and len(protocol["release"]) == 3, "PackedNext control protocol")


def validate_clock_open(computation: dict[str, Any]) -> None:
    for path in computation["paths"]:
        for obligation in path["ParametricObligations"]:
            entry = obligation_value(obligation)
            reject(entry.get("kind") == "StableAcrossV2" and entry.get("clock_slot") == slot("Clock", 2), "clock-package-private-identity-escape")
        outcome = path["outcome"]
        reject(outcome["kind"] == "TransfersV2" and outcome["park_contract"]["source"]["owner"] == slot("Owner", 1), "clock-package-transfer-captures-private-identity")
    validate_computation(computation, set())


def validate_clock_oracle(oracle: dict[str, Any]) -> None:
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong clock oracle profile")
    validate_clock_package(oracle["package"])
    lost_summary = oracle["lost_acquire_path"]["semantic_summary"]
    require(lost_summary.get("kind") == "CertificateV1" and lost_summary.get("origin") == "cire.temporal:packed-acquire", "lost acquire must retain its non-Pure summary")
    validate_clock_open(oracle["open_computation"])
    outcomes = [path["outcome"]["kind"] for path in oracle["open_computation"]["paths"]]
    require(outcomes == ["ReturnsV2", "AbortsV2", "TransfersV2", "TransfersV2"], "PackedNext won path set")
    for path in oracle["open_computation"]["paths"]:
        summary = path["semantic_summary"]
        require(summary.get("kind") == "SequenceSummaryV1", "won path did not sequence acquire/release")
        require([member.get("origin") for member in summary["members"]] == ["cire.temporal:packed-acquire", "cire.temporal:packed-release"], "won path acquire/release order")
        require(path["required_phase"]["allowed_phases"] == ["Action"], "PackedNext try phase")
    evidence = oracle["release_evidence"]
    require(len(evidence) == len(outcomes), "PackedNext release evidence cardinality")
    for index, item in enumerate(evidence):
        require(item["path_index"] == index and item["input_tag"] == outcomes[index] == item["output_tag"], "PackedNext tag preservation")
        require(item["lease_action"] == "ExactlyOnceRelease", "PackedNext release count")


def validate_flow_oracle(oracle: dict[str, Any]) -> None:
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong flow oracle profile")
    outcomes = [path["kind"] for path in oracle["flow_summary"]]
    require(outcomes == ["AbortsV2", "TransfersV2"], "flow oracle variants")
    validate_park(oracle["flow_summary"][1]["park_contract"])


def validate_document(document: dict[str, Any], directory: Path) -> None:
    artifact = document.get("artifact")
    if artifact == "FunctionContractV2":
        validate_function_contract(document)
    elif artifact == "CireSpecInterfaceOracleV2":
        validate_interface_oracle(document, directory)
    elif artifact == "CireClockPackageOracleV2":
        validate_clock_oracle(document)
    elif artifact == "CireSpecWireVariantOracleV2":
        validate_flow_oracle(document)
    else:
        raise AssertionError(f"unknown interface artifact: {artifact}")


def validate_v1_decoder(target: dict[str, Any]) -> None:
    reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(target)), "unsupported-contract-schema-version")


def decode_named(decoder: str, target: dict[str, Any], document: dict[str, Any], directory: Path) -> None:
    if decoder in {"FunctionContractV1", "ParkContractV1"}:
        validate_v1_decoder(target)
    elif decoder == "FunctionContractV2":
        validate_function_contract(target)
    elif decoder == "CireSpecInterfaceOracleV2":
        validate_interface_oracle(target, directory)
    elif decoder == "ParkContractV2":
        validate_park(target)
    elif decoder == "PackedNextPackageV2":
        validate_clock_package(target)
    elif decoder == "T-Clock-Unpack-Paths":
        validate_clock_open(target)
    else:
        raise AssertionError(f"unknown mutation decoder: {decoder}")


def validate_mutations() -> tuple[int, int]:
    oracle = load_json(MUTATIONS)
    require(oracle.get("artifact") == "CireMutationOracleV2", "mutation oracle header")
    for index, case in enumerate(oracle["cases"], 1):
        require(case.get("result") == "reject" and isinstance(case.get("decoder_target"), str), f"mutation {index}: incomplete decoder contract")
        base_path = (MUTATIONS.parent / case["base_file"]).resolve()
        document = apply_patch(load_json(base_path), case["mutations"])
        target = pointer_get(document, case["decoder_target"])
        try:
            decode_named(case["decoder"], target, document, base_path.parent)
        except Diagnostic as error:
            require(error.diagnostic_id == case["diagnostic"], f"mutation {index}: expected {case['diagnostic']}, got {error.diagnostic_id}")
        else:
            raise AssertionError(f"mutation {index}: decoder accepted malformed payload")
    return len(oracle["cases"]), sum(len(case["mutations"]) for case in oracle["cases"])


def step_packed(state: tuple[str, int], event: str) -> tuple[tuple[str, int], int, int, str | None, str | None]:
    kind, leases = state
    close = release = 0
    result = tag = None
    if event.startswith("acquire"):
        if kind == "Open":
            state = ("Open", leases + 1)
        else:
            result = "None"
    elif event == "dispose":
        if kind == "Open" and leases == 0:
            state, close = ("Closed", 0), 1
        elif kind == "Open":
            state = ("Closing", leases)
    elif event.startswith("body-Returns"):
        result = "Some"
    elif event.startswith("body-Aborts"):
        tag = "Aborts"
    elif event.startswith("body-Transfers"):
        tag = event.removeprefix("body-")
    elif event.startswith("release"):
        require(leases > 0, "release without an active PackedNext lease")
        release = 1
        if kind == "Open":
            state = ("Open", leases - 1)
        elif kind == "Closing" and leases == 1:
            state, close = ("Closed", 0), 1
        elif kind == "Closing":
            state = ("Closing", leases - 1)
        else:
            raise AssertionError("release from Closed")
    else:
        raise AssertionError(f"unknown PackedNext event: {event}")
    return state, close, release, result, tag


def state_text(state: tuple[str, int]) -> str:
    return "Closed" if state[0] == "Closed" else f"{state[0]}({state[1]})"


def validate_runtime() -> int:
    oracle = load_json(RUNTIME)
    require(oracle.get("artifact") == "CireRuntimeModelOracleV2" and oracle.get("profile") == PROFILE, "runtime oracle header")
    for trace in oracle["traces"]:
        state = ("Open", 0)
        close_count = release_count = 0
        result = tag = None
        observed_states: list[str] = []
        for event in trace["events"]:
            state, close, release, step_result, step_tag = step_packed(state, event)
            close_count += close
            release_count += release
            result = step_result or result
            tag = step_tag or tag
            observed_states.append(state_text(state))
        expected = trace["expected"]
        require(state_text(state) == expected["state"], f"runtime trace final state: {trace['events']}")
        require(close_count == expected["close_count"] and release_count == expected["release_count"], f"runtime trace counts: {trace['events']}")
        if "result" in expected:
            require(result == expected["result"], f"runtime trace result: {trace['events']}")
        if "tag" in expected:
            require(tag == expected["tag"], f"runtime trace tag: {trace['events']}")
        if "expected_states" in trace:
            require(observed_states == trace["expected_states"], f"runtime trace state sequence: {trace['events']}")
    return len(oracle["traces"])


def main() -> int:
    interface_paths = sorted(INTERFACES.glob("*.json"))
    for path in interface_paths:
        validate_document(load_json(path), path.parent)
    mutation_cases, mutation_operations = validate_mutations()
    runtime_count = validate_runtime()
    print(
        f"PASS: {len(interface_paths)} interface artifacts, "
        f"{mutation_cases} decoder mutation cases/{mutation_operations} RFC 6902 operations, "
        f"{runtime_count} runtime traces"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
