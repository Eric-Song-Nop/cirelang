#!/usr/bin/env python3
"""Execute the Cire-TR₀ V2 JSON interface, mutation, and runtime oracles.

This is the executable reference decoder for the frozen V2 wire profile, not a
compiler implementation. Its computation/outcome import is exhaustive and
threads application, return-binder, and Handler-clause disposition scope. It
also evaluates each mutation through the named decoder and checks the exact
diagnostic that decoder emits.
"""

from __future__ import annotations

import copy
import hashlib
import json
import sys
import unicodedata
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parent
INTERFACES = ROOT / "interfaces"
MUTATIONS = ROOT / "mutations" / "v1-rejects-v2-tags.json"
RUNTIME = ROOT / "runtime" / "packed-next-lease-runtime.json"
DIAGNOSTICS = ROOT / "diagnostics-v2.json"
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


def ordered_unique(values: Iterable[Any]) -> list[Any]:
    result: list[Any] = []
    seen: set[str] = set()
    for value in values:
        key = jcs(value)
        if key not in seen:
            result.append(copy.deepcopy(value))
            seen.add(key)
    return result


def normalize_summary_sequence(*summaries: dict[str, Any]) -> dict[str, Any]:
    members: list[dict[str, Any]] = []
    for summary in summaries:
        if summary.get("kind") == "SequenceSummaryV1":
            members.extend(summary["members"])
        else:
            members.append(summary)
    members = [copy.deepcopy(member) for member in members if member.get("kind") != "PureV1"]
    if not members:
        return {"kind": "PureV1"}
    if len(members) == 1:
        return members[0]
    return {"kind": "SequenceSummaryV1", "members": members}


def validate_summary_normal_form(summary: dict[str, Any]) -> None:
    kind = summary.get("kind")
    if kind == "PureV1":
        exact_fields(summary, {"kind"}, kind)
    elif kind == "CertificateV1":
        exact_fields(
            summary,
            {"kind", "temporal", "replay_origin", "fork", "publish", "suspend", "trust", "origin"},
            kind,
        )
    elif kind == "SequenceSummaryV1":
        exact_fields(summary, {"kind", "members"}, kind)
        reject(len(summary["members"]) < 2, "semantic-summary-not-normalized")
        for member in summary["members"]:
            reject(member.get("kind") in {"PureV1", "SequenceSummaryV1"}, "semantic-summary-not-normalized")
            validate_summary_normal_form(member)
    elif kind == "JoinSummaryV1":
        exact_fields(summary, {"kind", "members"}, kind)
        members = summary["members"]
        reject(len(members) < 2, "semantic-summary-not-normalized")
        reject(members != sorted(ordered_unique(members), key=jcs), "semantic-summary-not-normalized")
        for member in members:
            reject(member.get("kind") == "JoinSummaryV1", "semantic-summary-not-normalized")
            validate_summary_normal_form(member)
    else:
        raise Diagnostic("semantic-summary-not-normalized")


def validate_phase_requirement(phase: dict[str, Any]) -> None:
    exact_fields(phase, {"allowed_phases", "required_authorities", "current_owner"}, "PhaseRequirementV1")
    allowed = phase["allowed_phases"]
    require(allowed == [item for item in PHASE_ORDER if item in set(allowed)], "PhaseRequirementV1 phase order/duplicates")
    authorities = phase["required_authorities"]
    require(authorities == sorted(ordered_unique(authorities), key=jcs), "PhaseRequirementV1 authority order/duplicates")
    if phase["current_owner"] is not None:
        validate_slot_v1(phase["current_owner"], "Owner")


def compose_phase(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    allowed = [phase for phase in PHASE_ORDER if phase in left["allowed_phases"] and phase in right["allowed_phases"]]
    require(bool(allowed), "incompatible sequential phase requirements")
    left_owner, right_owner = left["current_owner"], right["current_owner"]
    require(left_owner is None or right_owner is None or left_owner == right_owner, "incompatible current Owner requirements")
    owner = copy.deepcopy(left_owner if left_owner is not None else right_owner)
    authorities = sorted(ordered_unique([*left["required_authorities"], *right["required_authorities"]]), key=jcs)
    return {"allowed_phases": allowed, "required_authorities": authorities, "current_owner": owner}


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


ReturnScope = dict[int, dict[str, Any]]
ApplicationScope = dict[int, dict[str, Any]]
LocalFunctionScope = dict[int, dict[str, Any]]


class ImportScope(dict[str, dict[str, Any]]):
    """Hash-indexed imported contracts plus their exact exported identities."""

    def __init__(self) -> None:
        super().__init__()
        self.exports: dict[str, tuple[tuple[str, ...], str]] = {}


PHASE_ORDER = ["Pure", "Compute", "Action", "Commit"]
PACKED_CONTROL_PROTOCOL = {
    "states": ["Open(n)", "Closing(n)", "Closed"],
    "acquire": ["Open(n)->Open(n+1)", "Closing(n)->None", "Closed->None"],
    "dispose": [
        "Open(0)->Closed+CloseChild",
        "Open(n+1)->Closing(n+1)",
        "Closing(n)->Closing(n)",
        "Closed->Closed",
    ],
    "release": [
        "Open(n+1)->Open(n)",
        "Closing(1)->Closed+CloseChild",
        "Closing(n+1)->Closing(n),n>=1",
    ],
}


def packed_summary(origin: str, *, replay_origin: str, fork: str, suspend: str) -> dict[str, Any]:
    return {
        "fork": fork,
        "kind": "CertificateV1",
        "origin": origin,
        "publish": "None",
        "replay_origin": replay_origin,
        "suspend": suspend,
        "temporal": "HostObservable",
        "trust": {"kind": "Sealed", "module": ["cire", "temporal"]},
    }


PACKED_ACQUIRE_SUMMARY = packed_summary(
    "cire.temporal:packed-acquire",
    replay_origin="SharedPersistent",
    fork="Share",
    suspend="StackOnly",
)
PACKED_RELEASE_SUMMARY = packed_summary(
    "cire.temporal:packed-release",
    replay_origin="SharedPersistent",
    fork="Share",
    suspend="StackOnly",
)


RETURN_KINDS = {
    "ReturnSlotRefV2",
    "ReturnWorldV2",
    "ReturnProvenanceV2",
    "ReturnCaptureV2",
    "ReturnNominalIndexV2",
    "ReturnUsageV2",
    "ReturnBoundResultV2",
}


def validate_slot_v1(value: dict[str, Any], namespace: str | None = None) -> None:
    exact_fields(value, {"namespace", "slot"}, "SlotRefV1")
    require(isinstance(value["slot"], int) and value["slot"] >= 0, "SlotRefV1 slot")
    if namespace is not None:
        require(value["namespace"] == namespace, f"SlotRefV1 namespace must be {namespace}")


def validate_return_ref(value: dict[str, Any], returns: ReturnScope) -> dict[str, Any]:
    exact_fields(value, {"kind", "return_slot"}, value.get("kind", "ReturnRefV2"))
    reject(value["return_slot"] not in returns, "contract-projection-escapes-scope")
    return returns[value["return_slot"]]


def validate_slot_v2(value: dict[str, Any], returns: ReturnScope) -> None:
    kind = value.get("kind")
    if kind == "LegacySlotRefV2":
        exact_fields(value, {"kind", "value"}, kind)
        validate_slot_v1(value["value"])
    elif kind == "ReturnSlotRefV2":
        validate_return_ref(value, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_contract_kind(kind: dict[str, Any], returns: ReturnScope) -> None:
    tag = kind.get("kind")
    fields = {
        "FunctionContractKindV2": {"kind", "parameter_type", "result_type", "visible_row"},
        "LaterContractKindV2": {"kind", "clock", "payload_type"},
        "ContinuationContractKindV2": {"kind", "argument_type", "answer_type"},
        "HandlerContractKindV2": {"kind", "family", "input_type", "answer_type"},
        "ClockPackageSummaryKindV2": {"kind", "clock", "payload_type"},
    }
    require(tag in fields, f"unknown ContractKindV2: {tag!r}")
    exact_fields(kind, fields[tag], tag)
    for key in ("parameter_type", "result_type", "payload_type", "argument_type", "answer_type", "family", "input_type"):
        if key in kind:
            validate_type_v2(kind[key], returns=returns)
    if "clock" in kind:
        validate_slot_v1(kind["clock"], "Clock")


def validate_contract_parameter(parameter: dict[str, Any], returns: ReturnScope) -> None:
    exact_fields(parameter, {"slot", "kind"}, "ContractParameterV2")
    require(isinstance(parameter["slot"], int), "ContractParameterV2 slot")
    validate_contract_kind(parameter["kind"], returns)


def validate_contract_ref(
    reference: dict[str, Any],
    returns: ReturnScope,
    *,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
) -> None:
    tag = reference.get("kind")
    if tag == "ImportedFunctionRefV2":
        exact_fields(reference, {"kind", "module", "name", "artifact_hash"}, tag)
        reject(reference["artifact_hash"] not in imports, "contract-component-kind-mismatch")
        expected_export = imports.exports.get(reference["artifact_hash"])
        reject(
            expected_export != (tuple(reference["module"]), reference["name"]),
            "imported-function-export-mismatch",
        )
    elif tag == "LocalFunctionRefV2":
        exact_fields(reference, {"kind", "declaration_slot"}, tag)
        reject(reference["declaration_slot"] not in local_functions, "local-function-ref-unresolved")
        target = local_functions[reference["declaration_slot"]]
        reject(
            target.get("artifact") != "FunctionContractV2"
            or target.get("declaration_kind", {}).get("kind") != "FunctionContractKindV2",
            "local-function-ref-unresolved",
        )
    elif tag == "ContractParameterRefV2":
        exact_fields(reference, {"kind", "parameter"}, tag)
        validate_contract_parameter(reference["parameter"], returns)
        slot_number = reference["parameter"]["slot"]
        reject(slot_number not in contract_binders, "contract-projection-escapes-scope")
        reject(reference["parameter"]["kind"] != binder_kind(contract_binders[slot_number]), "contract-component-kind-mismatch")
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_later_contract(later: dict[str, Any], returns: ReturnScope) -> None:
    exact_fields(later, {"provenance", "capture", "semantic_summary", "required_phase"}, "LaterContractV2")
    validate_provenance(later["provenance"], returns)
    validate_capture(later["capture"], returns)
    validate_summary_normal_form(later["semantic_summary"])
    validate_phase_requirement(later["required_phase"])


def validate_type_v2(
    type_ref: Any,
    *,
    returns: ReturnScope | None = None,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    returns = returns or {}
    applications = applications or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    require(isinstance(type_ref, dict), "TypeRefV2 must be an object")
    kind = type_ref.get("kind")
    schemas = {
        "LegacyTypeRefV2": {"kind", "value"},
        "TypeParameterV2": {"kind", "slot"},
        "NominalTypeV2": {"kind", "module", "name", "arguments"},
        "ApplyTypeV2": {"kind", "constructor", "arguments"},
        "FunctionTypeV2": {"kind", "parameter", "result", "contract"},
        "CapabilityTypeV2": {"kind", "identity", "family"},
        "NextTypeV2": {"kind", "clock", "payload", "later_contract"},
        "OwnerTypeV2": {"kind", "owner"},
        "OwnerIndexedTypeV2": {"kind", "constructor", "owner", "payload"},
        "ResourceTypeV2": {"kind", "owner", "value", "cleanup_result"},
        "SignalTypeV2": {"kind", "clock", "payload"},
        "PlanTypeV2": {"kind", "payload"},
        "ResumeTypeRefV2": {"kind", "value"},
        "HandlerTemplateTypeV2": {"kind", "family", "owner", "input", "answer", "residual_row", "contract", "policy"},
        "ForAllIdentityTypeV2": {"kind", "binder", "body"},
        "ForAllContractTypeV2": {"kind", "binder", "body"},
        "ForAllOwnerTypeV2": {"kind", "binder", "body"},
        "ExistsClockPackageTypeV2": {"kind", "clock_binder", "summary_binder", "body"},
        "PackedNextTypeV2": {"kind", "owner", "payload"},
    }
    require(kind in schemas, f"unknown TypeRefV2 variant: {kind!r}")
    exact_fields(type_ref, schemas[kind], kind)
    if kind == "LegacyTypeRefV2":
        require(isinstance(type_ref["value"], dict), "LegacyTypeRefV2.value missing")
        reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(type_ref["value"])), "unsupported-contract-schema-version")
    elif kind in {"NominalTypeV2", "ApplyTypeV2"}:
        for argument in type_ref["arguments"]:
            validate_type_v2(argument, returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    elif kind == "FunctionTypeV2":
        validate_type_v2(type_ref["parameter"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        validate_type_v2(type_ref["result"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        contract = type_ref["contract"]
        if contract.get("artifact") == "FunctionContractV2":
            validate_function_contract(contract, imports=imports, local_functions=local_functions)
            resolved_kind = contract["declaration_kind"]
            check_shape = True
        elif isinstance(contract.get("kind"), dict) and isinstance(contract.get("slot"), int):
            validate_contract_parameter(contract, returns)
            reject(contract["slot"] not in contract_binders, "contract-projection-escapes-scope")
            resolved_kind = binder_kind(contract_binders[contract["slot"]])
            reject(contract["kind"] != resolved_kind, "contract-component-kind-mismatch")
            check_shape = True
        else:
            validate_contract_ref(
                contract,
                returns,
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
            )
            resolved_kind, _ = resolve_contract_target(contract, imports, contract_binders, local_functions)
            # An AppliedContractV2 may carry an instantiated imported/local
            # FunctionType; its exact shape is checked against that
            # application's substitution below.
            check_shape = False
        reject(resolved_kind is None or resolved_kind.get("kind") != "FunctionContractKindV2", "contract-component-kind-mismatch")
        reject(check_shape and (
            type_ref["parameter"] != resolved_kind["parameter_type"]
            or type_ref["result"] != resolved_kind["result_type"]),
            "contract-component-kind-mismatch",
        )
    elif kind == "CapabilityTypeV2":
        validate_slot_v1(type_ref["identity"], "Identity")
        validate_type_v2(type_ref["family"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    elif kind == "NextTypeV2":
        validate_slot_v1(type_ref["clock"], "Clock")
        validate_type_v2(type_ref["payload"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        later = type_ref["later_contract"]
        if isinstance(later.get("kind"), dict):
            validate_contract_parameter(later, returns)
            reject(later["slot"] not in contract_binders, "contract-projection-escapes-scope")
            reject(later["kind"] != binder_kind(contract_binders[later["slot"]]), "contract-component-kind-mismatch")
        else:
            validate_later_contract(later, returns)
    elif kind in {"OwnerTypeV2", "OwnerIndexedTypeV2", "ResourceTypeV2", "PackedNextTypeV2"}:
        validate_slot_v1(type_ref["owner"], "Owner")
        for key in ("payload", "value", "cleanup_result"):
            if type_ref.get(key) is not None:
                validate_type_v2(type_ref[key], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        if kind == "OwnerIndexedTypeV2":
            no_payload = type_ref["constructor"] in {"CommitTicket", "CommitGate"}
            require((type_ref["payload"] is None) == no_payload, "OwnerIndexedTypeV2 payload")
    elif kind == "SignalTypeV2":
        validate_slot_v1(type_ref["clock"], "Clock")
        validate_type_v2(type_ref["payload"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    elif kind == "PlanTypeV2":
        validate_type_v2(type_ref["payload"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    elif kind == "ResumeTypeRefV2":
        validate_resume(type_ref["value"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    elif kind == "HandlerTemplateTypeV2":
        for key in ("family", "input", "answer"):
            validate_type_v2(type_ref[key], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        validate_slot_v1(type_ref["owner"], "Owner")
        contract = type_ref["contract"]
        if isinstance(contract.get("kind"), dict):
            validate_contract_parameter(contract, returns)
        else:
            validate_handler_contract(contract, imports=imports, local_functions=local_functions)
    elif kind.startswith("ForAll") or kind == "ExistsClockPackageTypeV2":
        validate_type_v2(type_ref["body"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)


def validate_world(world: dict[str, Any], returns: ReturnScope) -> None:
    kind = world.get("kind")
    if kind == "LegacyWorldExprV2":
        exact_fields(world, {"kind", "value"}, kind)
    elif kind == "ReturnWorldV2":
        validate_return_ref(world, returns)
    elif kind == "ApplicationEntryWorldV2":
        exact_fields(world, {"kind", "application_slot"}, kind)
    elif kind == "ApplyWorldTransitionV2":
        exact_fields(world, {"kind", "input", "transition"}, kind)
        validate_world(world["input"], returns)
    elif kind == "JoinWorldsV2":
        exact_fields(world, {"kind", "members"}, kind)
        for member in world["members"]:
            validate_world(member, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_nominal_index(index: dict[str, Any], returns: ReturnScope) -> None:
    if index.get("kind") == "LegacyNominalIndexExprV2":
        exact_fields(index, {"kind", "value"}, "LegacyNominalIndexExprV2")
    elif index.get("kind") == "ReturnNominalIndexV2":
        validate_return_ref(index, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_provenance(provenance: dict[str, Any], returns: ReturnScope) -> None:
    kind = provenance.get("kind")
    if kind == "LegacyProvenanceExprV2":
        exact_fields(provenance, {"kind", "value"}, kind)
    elif kind == "ReturnProvenanceV2":
        validate_return_ref(provenance, returns)
    elif kind == "EnvironmentV2":
        exact_fields(provenance, {"kind", "bindings"}, kind)
        for binding in provenance["bindings"]:
            validate_environment_binding(binding, returns)
    elif kind == "JoinProvenanceV2":
        exact_fields(provenance, {"kind", "members"}, kind)
        for member in provenance["members"]:
            validate_provenance(member, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_capture(capture: dict[str, Any], returns: ReturnScope) -> None:
    kind = capture.get("kind")
    if kind == "LegacyCaptureExprV2":
        exact_fields(capture, {"kind", "value"}, kind)
    elif kind == "ReturnCaptureV2":
        validate_return_ref(capture, returns)
    elif kind == "UnionCaptureV2":
        exact_fields(capture, {"kind", "members"}, kind)
        for member in capture["members"]:
            validate_capture(member, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_usage(
    usage: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    kind = usage.get("kind")
    if kind == "LegacyUsageExprV2":
        exact_fields(usage, {"kind", "value"}, kind)
        exact_fields(usage["value"], {"slot", "kind"}, "UsageV1")
        validate_slot_v1(usage["value"]["slot"])
        require(usage["value"]["kind"] in {"Zero", "Once", "Many"}, "UsageV1 kind")
        usage_slot = usage["value"]["slot"]
        if usage_slot["namespace"] == "SuffixLive":
            reject(
                disposition_binder is None or usage_slot["slot"] != disposition_binder["slot"],
                "handler-disposition-escapes-scope",
            )
    elif kind == "ReturnUsageV2":
        binder = validate_return_ref(usage, returns)
        reject(binder["type"].get("kind") != "ResumeTypeRefV2", "contract-component-kind-mismatch")
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_result_transformer(transformer: dict[str, Any], returns: ReturnScope) -> None:
    kind = transformer.get("kind")
    if kind == "LegacyResultTransformerV2":
        exact_fields(transformer, {"kind", "value"}, kind)
    elif kind == "ParametricResultV2":
        exact_fields(transformer, {"kind", "provenance", "capture"}, kind)
        validate_provenance(transformer["provenance"], returns)
        validate_capture(transformer["capture"], returns)
    elif kind == "ReturnBoundResultV2":
        validate_return_ref(transformer, returns)
    elif kind == "PathJoinResultV2":
        exact_fields(transformer, {"kind", "paths"}, kind)
        for path in transformer["paths"]:
            validate_result_transformer(path, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_environment_binding(binding: dict[str, Any], returns: ReturnScope) -> None:
    exact_fields(binding, {"slot", "type", "provenance", "capture"}, "EnvironmentBindingV2")
    validate_slot_v1(binding["slot"])
    validate_type_v2(binding["type"], returns=returns)
    validate_provenance(binding["provenance"], returns)
    validate_capture(binding["capture"], returns)


def validate_value_summary(
    summary: dict[str, Any],
    returns: ReturnScope | None = None,
    *,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    returns = returns or {}
    exact_fields(summary, {"source", "type", "nominal_index", "provenance", "capture", "usage", "origin"}, "ValueSummaryExprV2")
    if summary["source"] is not None:
        validate_slot_v2(summary["source"], returns)
    validate_type_v2(summary["type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_nominal_index(summary["nominal_index"], returns)
    validate_provenance(summary["provenance"], returns)
    validate_capture(summary["capture"], returns)
    if summary["usage"] is not None:
        validate_usage(summary["usage"], returns, disposition_binder=disposition_binder)


def contains_return_ref(value: Any, return_slot: int) -> bool:
    return any(isinstance(node, dict) and node.get("kind") in RETURN_KINDS and node.get("return_slot") == return_slot for node in walk(value))


def validate_return_binder(
    binder: dict[str, Any],
    returns: ReturnScope,
    *,
    applications: ApplicationScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
) -> None:
    exact_fields(binder, {"slot", "type", "world", "nominal_index", "provenance", "capture", "usage"}, "ReturnBinderV2")
    reject(binder["slot"] in returns, "contract-projection-escapes-scope")
    reject(contains_return_ref({key: value for key, value in binder.items() if key != "slot"}, binder["slot"]), "contract-projection-escapes-scope")
    validate_type_v2(binder["type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_world(binder["world"], returns)
    validate_nominal_index(binder["nominal_index"], returns)
    validate_provenance(binder["provenance"], returns)
    validate_capture(binder["capture"], returns)
    if binder["usage"] is not None:
        validate_usage(binder["usage"], returns)


def validate_cleanup(cleanup: dict[str, Any]) -> None:
    exact_fields(cleanup, {"residual_row", "attributed_demand", "transition", "suspension", "semantic_summary"}, "CleanupContractV1")
    validate_summary_normal_form(cleanup["semantic_summary"])


def validate_application_ledger(
    ledger: list[dict[str, Any]],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
) -> ApplicationScope:
    applications: ApplicationScope = {}
    for application in ledger:
        application_slot = application["application_slot"]
        require(application_slot not in applications, "duplicate AppliedContractV2 slot")
        applications[application_slot] = application
    for application in ledger:
        validate_application_instantiation(
            application,
            returns=returns,
            applications=applications,
            imports=imports,
            contract_binders=contract_binders,
            local_functions=local_functions,
        )
    return applications


def validate_suffix(
    suffix: dict[str, Any],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    exact_fields(suffix, {"answer_type", "applications", "computation", "cleanup", "live_bindings"}, "SuffixContractV2")
    applications = validate_application_ledger(suffix["applications"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_type_v2(suffix["answer_type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_cleanup(suffix["cleanup"])
    for binding in suffix["live_bindings"]:
        exact_fields(binding, {"slot", "type", "provenance", "capture", "usage"}, "LiveAcrossSiteV2")
        validate_slot_v2(binding["slot"], returns)
        validate_type_v2(binding["type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        validate_provenance(binding["provenance"], returns)
        validate_capture(binding["capture"], returns)
        validate_usage(binding["usage"], returns, disposition_binder=disposition_binder)
    validate_computation(
        suffix["computation"], applications,
        returns=returns, context="suffix", imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        disposition_binder=disposition_binder,
    )


def validate_resume(
    resumption: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    exact_fields(resumption, {"usage", "continuation", "argument", "answer", "live_provenance", "live_capture", "owner"}, "ResumeTypeV2")
    require(resumption["usage"] in {"Zero", "Once", "Many"}, "ResumeTypeV2 usage")
    validate_type_v2(resumption["argument"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_type_v2(resumption["answer"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_provenance(resumption["live_provenance"], returns)
    validate_capture(resumption["live_capture"], returns)
    validate_slot_v1(resumption["owner"], "Owner")
    validate_suffix(resumption["continuation"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)


def validate_park(
    park: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    exact_fields(park, {"owner_slot", "site_slot", "claim_cell_slot", "source", "completion_port", "claim", "disposition", "required_phase", "origin"}, "ParkContractV2")
    owner = slot("Owner", park["owner_slot"])
    source, port, claim, disposition = park["source"], park["completion_port"], park["claim"], park["disposition"]
    exact_fields(source, {"owner", "value_type", "generation_model", "write_authority"}, "SourceContractV2")
    exact_fields(port, {"owner", "value_type", "port_slot", "claim_cell_slot"}, "CompletionPortV2")
    exact_fields(
        claim,
        {
            "claim_cell_slot", "source_generation", "completion_generation_gate",
            "finalization_generation_gate", "completion_transition", "finalization_transition",
            "generation_transition", "failure_transition",
        },
        "GenerationCASV1",
    )
    exact_fields(disposition, {"continuation_site_slot", "claim_cell_slot", "resumption", "states", "completion_transition", "finalization_transition"}, "OneShotDispositionV2")
    resumption = disposition["resumption"]
    require(source["owner"] == owner == port["owner"], "ParkContractV2 parked Owner mismatch")
    validate_slot_v1(resumption["owner"], "Owner")
    reject(
        source["generation_model"] != "Unsigned64NoWrap"
        or source["write_authority"] != "OwnerExecutorOnly"
        or claim
        != {
            "claim_cell_slot": park["claim_cell_slot"],
            "source_generation": "ClaimTicketGeneration",
            "completion_generation_gate": "EqualCurrentGeneration",
            "finalization_generation_gate": "EqualCurrentGenerationOrOwnerRetireAuthority",
            "completion_transition": "UnclaimedToCompleted",
            "finalization_transition": "UnclaimedToFinalized",
            "generation_transition": "PreserveGeneration",
            "failure_transition": "NoStateChange",
        },
        "park-generation-protocol-mismatch",
    )
    reject(
        disposition["states"] != ["Unclaimed", "Completed", "Finalized"]
        or disposition["completion_transition"] != "UnclaimedToCompleted"
        or disposition["finalization_transition"] != "UnclaimedToFinalized",
        "park-disposition-protocol-mismatch",
    )
    reject(source["value_type"] != port["value_type"] or source["value_type"] != resumption["argument"], "park-source-payload-mismatch")
    reject(resumption["answer"] != resumption["continuation"]["answer_type"], "park-resumption-type-mismatch")
    claim_slot = park["claim_cell_slot"]
    require(claim_slot == port["claim_cell_slot"] == disposition["claim_cell_slot"] == claim["claim_cell_slot"], "ParkContractV2 claim-cell mismatch")
    require(park["site_slot"] == disposition["continuation_site_slot"], "ParkContractV2 site mismatch")
    require(resumption["usage"] == "Once", "ParkContractV2 disposition must be one-shot")
    required_phase = park["required_phase"]
    validate_phase_requirement(required_phase)
    expected_authority = {"kind": "OwnerAuthorityV1", "owner": owner}
    reject(
        required_phase != {
            "allowed_phases": ["Action"],
            "required_authorities": [expected_authority],
            "current_owner": owner,
        },
        "park-required-phase-mismatch",
    )
    validate_type_v2(source["value_type"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_type_v2(port["value_type"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    validate_resume(resumption, returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    return owner, resumption["owner"]


def obligation_value(obligation: dict[str, Any]) -> dict[str, Any]:
    return obligation["value"] if obligation.get("kind") == "LegacyObligationV2" else obligation


def validate_obligation(obligation: dict[str, Any], returns: ReturnScope) -> None:
    kind = obligation.get("kind")
    if kind == "LegacyObligationV2":
        exact_fields(obligation, {"kind", "value"}, kind)
        return
    fields = {
        "BoundarySafeV2": {"kind", "id", "stage", "slots", "boundary", "origin"},
        "StableAcrossV2": {"kind", "id", "stage", "slots", "clock_slot", "worlds", "origin"},
        "OutlivesV2": {"kind", "id", "stage", "shorter", "longer", "origin"},
        "PhaseAllowsV2": {"kind", "id", "stage", "required_phase", "origin"},
        "DuplicableEnvV2": {"kind", "id", "stage", "slots", "site_slot", "origin"},
        "ReplayableCleanupV2": {"kind", "id", "stage", "site_slot", "cleanup", "origin"},
        "TickWitnessV2": {"kind", "id", "stage", "clock_slot", "site_slot", "origin"},
        "OwnerParkingV2": {"kind", "id", "stage", "owner_slot", "site_slot", "origin"},
        "RowLacksV2": {"kind", "id", "stage", "row_slot", "entry", "origin"},
    }
    require(kind in fields, f"unknown ObligationV2: {kind!r}")
    exact_fields(obligation, fields[kind], kind)
    for reference in obligation.get("slots", []):
        validate_slot_v2(reference, returns)
    for key in ("shorter", "longer"):
        if key in obligation:
            validate_slot_v2(obligation[key], returns)
    for world in obligation.get("worlds", []):
        validate_world(world, returns)


def validate_operation_signature(signature: dict[str, Any], returns: ReturnScope) -> None:
    exact_fields(signature, {"type_binders", "parameters", "result", "mode", "transition", "suspension", "result_transformer", "required_phase", "obligation_ids", "secondary_sites"}, "OperationSignatureV2")
    for parameter in signature["parameters"]:
        validate_type_v2(parameter, returns=returns)
    validate_type_v2(signature["result"], returns=returns)
    require(signature["mode"] in {"fun", "once", "ctl", "abort"}, "OperationSignatureV2 mode")
    require(signature["secondary_sites"].get("kind") == "Closed", "operation secondary sites must be closed")


def validate_latent_site(
    latent: dict[str, Any],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    exact_fields(latent, {"site_slot", "stage", "receiver", "operation", "route", "actual_arguments", "instantiated_signature", "suffix", "secondary_sites", "call_obligation_ids", "install_obligation_ids", "origin"}, "LatentSiteV2")
    for summary in latent["actual_arguments"]:
        validate_value_summary(summary, returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, disposition_binder=disposition_binder)
    validate_operation_signature(latent["instantiated_signature"], returns)
    require(
        [summary["type"] for summary in latent["actual_arguments"]]
        == latent["instantiated_signature"]["parameters"],
        "LatentSiteV2 actual/signature type mismatch",
    )
    validate_suffix(latent["suffix"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, disposition_binder=disposition_binder)


def validate_forward_contract(
    forward: dict[str, Any],
    evidence: dict[str, Any],
    disposition_binder: dict[str, Any],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    clause_operation: dict[str, Any],
    handled_entry: dict[str, Any],
    handler_prompt_slot: int,
) -> None:
    exact_fields(forward, {"site_slot", "route", "entry", "operation", "continuation", "entry_world", "actual_argument_summaries", "instantiated_signature", "call_obligation_ids", "install_obligation_ids", "secondary_sites", "origin"}, "ForwardContractV2")
    exact_fields(evidence, {"inner_disposition", "input_state", "output_state", "forward_site_slot", "continuation_transfer"}, "ForwardDispositionEvidenceV2")
    validate_slot_v1(evidence["inner_disposition"], "SuffixLive")
    require(evidence["inner_disposition"] == slot("SuffixLive", disposition_binder["slot"]), "Forward disposition binder mismatch")
    require(evidence["input_state"] == "Open" and evidence["output_state"] == "Forwarded", "Forward disposition states")
    require(evidence["forward_site_slot"] == forward["site_slot"], "Forward site mismatch")
    require(evidence["continuation_transfer"] == "ExclusiveToForwardContract", "Forward transfer must be exclusive")
    reject(forward["operation"] != clause_operation, "forward-operation-mismatch")
    reject(forward["entry"] != handled_entry, "forward-operation-mismatch")
    reject(forward["site_slot"] != disposition_binder["site_slot"], "forward-operation-mismatch")
    route = forward["route"]
    reject(
        route.get("kind") != "InstallationPromptV1"
        or set(route) != {"kind", "prompt_slot"}
        or route["prompt_slot"] == handler_prompt_slot,
        "forward-route-mismatch",
    )
    validate_world(forward["entry_world"], returns)
    reject(
        forward["entry_world"]
        != {"kind": "LegacyWorldExprV2", "value": {"kind": "EntryWorldV1", "site_slot": forward["site_slot"]}},
        "forward-route-mismatch",
    )
    for summary in forward["actual_argument_summaries"]:
        validate_value_summary(summary, returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, disposition_binder=disposition_binder)
    validate_operation_signature(forward["instantiated_signature"], returns)
    reject(
        [summary["type"] for summary in forward["actual_argument_summaries"]]
        != forward["instantiated_signature"]["parameters"],
        "forward-application-arity-type-mismatch",
    )
    obligation_ids = set(forward["instantiated_signature"]["obligation_ids"])
    projected_ids = [*forward["call_obligation_ids"], *forward["install_obligation_ids"]]
    reject(
        len(projected_ids) != len(set(projected_ids))
        or set(projected_ids) != obligation_ids,
        "forward-obligation-projection-mismatch",
    )
    require(forward["secondary_sites"].get("kind") == "Closed", "Forward secondary sites must be closed")
    validate_suffix(forward["continuation"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, disposition_binder=disposition_binder)
    resume_type = disposition_binder["type"]
    require(resume_type.get("kind") == "ResumeTypeRefV2", "ClauseDispositionBinderV2 type")
    require(resume_type["value"]["continuation"] == forward["continuation"], "Forward continuation/disposition mismatch")
    reject(
        resume_type["value"]["argument"] != forward["instantiated_signature"]["result"]
        or resume_type["value"]["answer"] != forward["continuation"]["answer_type"],
        "forward-application-arity-type-mismatch",
    )
    quantities = {"fun": "Once", "once": "Once", "ctl": "Many", "abort": "Once"}
    require(resume_type["value"]["usage"] == quantities[forward["instantiated_signature"]["mode"]], "Forward disposition quantity mismatch")


def validate_path(
    path: dict[str, Any],
    *,
    applications: ApplicationScope,
    returns: ReturnScope,
    context: str,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None = None,
    clause_operation: dict[str, Any] | None = None,
    handled_entry: dict[str, Any] | None = None,
    handler_prompt_slot: int | None = None,
) -> None:
    exact_fields(path, {"outcome", "residual_row", "attributed_demand", "suspension", "semantic_summary", "usage", "required_phase", "ParametricObligations", "LatentSites"}, "PathContractV2")
    validate_summary_normal_form(path["semantic_summary"])
    validate_phase_requirement(path["required_phase"])
    for usage in path["usage"]:
        validate_usage(usage, returns, disposition_binder=disposition_binder)
    for obligation in path["ParametricObligations"]:
        validate_obligation(obligation, returns)
    q = [obligation_value(obligation) for obligation in path["ParametricObligations"]]
    q_keys = {(entry["stage"], entry["id"]) for entry in q}
    for latent in path["LatentSites"]:
        validate_latent_site(latent, returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, disposition_binder=disposition_binder)
        for local_id in latent["call_obligation_ids"]:
            reject(("Call", local_id) not in q_keys, "projected-obligation-stage-lost")
        for local_id in latent["install_obligation_ids"]:
            reject(("HandlerInstall", local_id) not in q_keys, "projected-obligation-stage-lost")
    outcome = path["outcome"]
    kind = outcome.get("kind")
    if kind == "ReturnsV2":
        exact_fields(outcome, {"kind", "transition", "result_transformer"}, kind)
        validate_result_transformer(outcome["result_transformer"], returns)
    elif kind == "AbortsV2":
        exact_fields(outcome, {"kind", "origin"}, kind)
    elif kind == "TransfersV2":
        exact_fields(outcome, {"kind", "park_contract"}, kind)
        parked_owner, resumption_owner = validate_park(
            outcome["park_contract"], returns=returns, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
        )
        if parked_owner != resumption_owner:
            expected_shorter = {"kind": "LegacySlotRefV2", "value": resumption_owner}
            expected_longer = {"kind": "LegacySlotRefV2", "value": parked_owner}
            reject(
                not any(
                    item.get("kind") == "OutlivesV2"
                    and item.get("shorter") == expected_shorter
                    and item.get("longer") == expected_longer
                    for item in q
                ),
                "park-owner-outlives-missing",
            )
    elif kind == "DelegatesV2":
        reject(context != "handler_clause" or disposition_binder is None, "delegates-outside-handler-clause")
        require(clause_operation is not None and handled_entry is not None and handler_prompt_slot is not None, "handler clause context missing")
        exact_fields(outcome, {"kind", "forward_contract", "disposition_evidence"}, kind)
        validate_forward_contract(
            outcome["forward_contract"], outcome["disposition_evidence"], disposition_binder,
            returns=returns, imports=imports, contract_binders=contract_binders,
            local_functions=local_functions, clause_operation=clause_operation,
            handled_entry=handled_entry, handler_prompt_slot=handler_prompt_slot,
        )
    else:
        raise Diagnostic("unknown-path-outcome-v2")


def validate_computation(
    computation: dict[str, Any],
    applications: ApplicationScope | set[int],
    *,
    returns: ReturnScope | None = None,
    context: str = "function",
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    disposition_binder: dict[str, Any] | None = None,
    clause_operation: dict[str, Any] | None = None,
    handled_entry: dict[str, Any] | None = None,
    handler_prompt_slot: int | None = None,
) -> None:
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    if isinstance(applications, set):
        applications = {number: {"application_slot": number} for number in applications}
    kind = computation.get("kind")
    if kind == "LiteralPathsV2":
        exact_fields(computation, {"kind", "paths"}, kind)
        require(bool(computation["paths"]), "LiteralPathsV2 must be nonempty")
        for path in computation["paths"]:
            validate_path(
                path, applications=applications, returns=returns, context=context,
                imports=imports, contract_binders=contract_binders,
                local_functions=local_functions, disposition_binder=disposition_binder,
                clause_operation=clause_operation, handled_entry=handled_entry,
                handler_prompt_slot=handler_prompt_slot,
            )
    elif kind == "InvokeV2":
        exact_fields(computation, {"kind", "application_slot"}, kind)
        require(computation["application_slot"] in applications, "InvokeV2 references an unknown application")
    elif kind == "PathBindV2":
        reject(computation.get("terminal_policy") != "PreserveTerminalV2", "path-bind-terminal-not-preserved")
        exact_fields(computation, {"kind", "prefix", "return_binder", "continuation", "terminal_policy"}, kind)
        validate_computation(
            computation["prefix"], applications, returns=returns, context=context,
            imports=imports, contract_binders=contract_binders, local_functions=local_functions,
            disposition_binder=disposition_binder, clause_operation=clause_operation,
            handled_entry=handled_entry, handler_prompt_slot=handler_prompt_slot,
        )
        binder = computation["return_binder"]
        validate_return_binder(
            binder, returns, applications=applications, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
        )
        continuation_returns = dict(returns)
        continuation_returns[binder["slot"]] = binder
        validate_computation(
            computation["continuation"], applications, returns=continuation_returns,
            context=context, imports=imports, contract_binders=contract_binders,
            local_functions=local_functions, disposition_binder=disposition_binder,
            clause_operation=clause_operation, handled_entry=handled_entry,
            handler_prompt_slot=handler_prompt_slot,
        )
    elif kind == "JoinV2":
        exact_fields(computation, {"kind", "members"}, kind)
        require(bool(computation["members"]), "JoinV2 must be nonempty")
        for member in computation["members"]:
            validate_computation(
                member, applications, returns=returns, context=context,
                imports=imports, contract_binders=contract_binders,
                local_functions=local_functions, disposition_binder=disposition_binder,
                clause_operation=clause_operation, handled_entry=handled_entry,
                handler_prompt_slot=handler_prompt_slot,
            )
    else:
        raise Diagnostic("unknown-contract-computation-variant")


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


def substitute_contract_kind(kind: dict[str, Any], substitution: dict[str, Any]) -> dict[str, Any]:
    type_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["type_arguments"]}
    owner_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["owner_arguments"]}
    identity_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["identity_arguments"]}
    clock_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["clock_arguments"]}
    contract_arguments = {entry["binder_slot"]: entry["contract"] for entry in substitution["contract_arguments"]}

    def replace(value: Any) -> Any:
        if isinstance(value, list):
            return [replace(member) for member in value]
        if not isinstance(value, dict):
            return value
        if value.get("kind") == "TypeParameterV2" and value.get("slot") in type_arguments:
            return copy.deepcopy(type_arguments[value["slot"]])
        if set(value) == {"namespace", "slot"}:
            table = {"Owner": owner_arguments, "Identity": identity_arguments, "Clock": clock_arguments}.get(value["namespace"])
            if table is not None and value["slot"] in table:
                return copy.deepcopy(table[value["slot"]])
        if isinstance(value.get("kind"), dict) and value.get("slot") in contract_arguments:
            return copy.deepcopy(contract_arguments[value["slot"]])
        if value.get("kind") == "ContractParameterRefV2":
            parameter = value.get("parameter", {})
            if parameter.get("slot") in contract_arguments:
                return copy.deepcopy(contract_arguments[parameter["slot"]])
        return {key: replace(member) for key, member in value.items()}

    return replace(kind)


def resolve_contract_target(
    reference: dict[str, Any],
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
) -> tuple[dict[str, Any], dict[str, Any] | None]:
    if reference["kind"] == "ImportedFunctionRefV2":
        reject(reference["artifact_hash"] not in imports, "contract-component-kind-mismatch")
        target = imports[reference["artifact_hash"]]
        return target["declaration_kind"], target
    if reference["kind"] == "LocalFunctionRefV2":
        reject(reference["declaration_slot"] not in local_functions, "local-function-ref-unresolved")
        target = local_functions[reference["declaration_slot"]]
        reject(
            target.get("artifact") != "FunctionContractV2"
            or target.get("declaration_kind", {}).get("kind") != "FunctionContractKindV2",
            "local-function-ref-unresolved",
        )
        return target["declaration_kind"], target
    if reference["kind"] == "ContractParameterRefV2":
        parameter = reference["parameter"]
        reject(parameter["slot"] not in contract_binders, "contract-projection-escapes-scope")
        expected = binder_kind(contract_binders[parameter["slot"]])
        reject(parameter["kind"] != expected, "contract-component-kind-mismatch")
        return expected, None
    raise Diagnostic("contract-component-kind-mismatch")


def application_parameter_types(parameter_type: dict[str, Any]) -> list[dict[str, Any]]:
    constructor = parameter_type.get("constructor", {})
    if (
        parameter_type.get("kind") == "ApplyTypeV2"
        and constructor.get("kind") == "NominalConstructorV1"
        and str(constructor.get("name", "")).endswith("Arguments")
    ):
        return parameter_type["arguments"]
    return [parameter_type]


def substitution_slots(substitution: dict[str, Any], field: str) -> list[int]:
    slots = [entry["binder_slot"] for entry in substitution[field]]
    require(len(slots) == len(set(slots)), f"duplicate {field} binder slot")
    return slots


def validate_application_instantiation(
    application: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    returns = returns or {}
    applications = applications or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    exact_fields(application, {"application_slot", "contract", "callee_summary", "actual_arguments", "substitution", "entry_world", "origin"}, "AppliedContractV2")
    validate_contract_ref(
        application["contract"], returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
    )
    for summary in [application["callee_summary"], *application["actual_arguments"]]:
        validate_value_summary(summary, returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    substitution = application["substitution"]
    exact_fields(substitution, {"type_arguments", "row_arguments", "contract_arguments", "owner_arguments", "identity_arguments", "clock_arguments"}, "ContractSubstitutionV2")
    validate_world(application["entry_world"], returns)
    reject(
        application["entry_world"]
        != {"kind": "ApplicationEntryWorldV2", "application_slot": application["application_slot"]},
        "contract-parameter-inconsistent-instantiation",
    )
    for field, expected_fields in {
        "type_arguments": {"binder_slot", "value"},
        "row_arguments": {"binder_slot", "value"},
        "contract_arguments": {"binder_slot", "contract"},
        "owner_arguments": {"binder_slot", "value"},
        "identity_arguments": {"binder_slot", "value"},
        "clock_arguments": {"binder_slot", "value"},
    }.items():
        substitution_slots(substitution, field)
        for entry in substitution[field]:
            exact_fields(entry, expected_fields, field)
    for entry in substitution["type_arguments"]:
        validate_type_v2(entry["value"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    for entry in substitution["contract_arguments"]:
        validate_contract_ref(entry["contract"], returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    for field, namespace in (("owner_arguments", "Owner"), ("identity_arguments", "Identity"), ("clock_arguments", "Clock")):
        for entry in substitution[field]:
            validate_slot_v1(entry["value"], namespace)

    kind, target = resolve_contract_target(application["contract"], imports, contract_binders, local_functions)
    reject(kind.get("kind") != "FunctionContractKindV2", "contract-component-kind-mismatch")
    if target is not None:
        binders = target["binders"]
        expected_domains = {
            "type_arguments": {entry["slot"] for entry in binders["type_binders"]},
            "row_arguments": {entry["slot"] for entry in binders["row_binders"]},
            "contract_arguments": {entry["slot"] for entry in binders["contract_binders"]},
            "owner_arguments": {entry["slot"] for entry in binders["owner_binders"]},
            "identity_arguments": {entry["identity_slot"] for entry in binders["identity_binders"]},
            "clock_arguments": {entry["slot"] for entry in binders["clock_binders"]},
        }
        for field, expected_slots in expected_domains.items():
            reject(set(substitution_slots(substitution, field)) != expected_slots, "contract-parameter-inconsistent-instantiation")

    instantiated = substitute_contract_kind(kind, substitution)
    expected_callee_type = {
        "contract": application["contract"],
        "kind": "FunctionTypeV2",
        "parameter": instantiated["parameter_type"],
        "result": instantiated["result_type"],
    }
    reject(application["callee_summary"]["type"].get("kind") != "FunctionTypeV2", "contract-component-kind-mismatch")
    reject(application["callee_summary"]["type"] != expected_callee_type, "contract-parameter-inconsistent-instantiation")
    expected_actual_types = application_parameter_types(instantiated["parameter_type"])
    actual_types = [summary["type"] for summary in application["actual_arguments"]]
    reject(len(actual_types) != len(expected_actual_types), "application-arity-mismatch")
    reject(actual_types != expected_actual_types, "application-argument-type-mismatch")


def validate_function_contract(
    contract: dict[str, Any],
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    imports = imports or ImportScope()
    local_functions = local_functions or {}
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
        validate_type_v2(declaration_kind["parameter_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        validate_type_v2(declaration_kind["result_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    for binder in contract_binders.values():
        require(binder.get("kind") == "FunctionContractBinderV2", "unsupported ContractBinderV2 in fixture")
        validate_type_v2(binder["parameter_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
        validate_type_v2(binder["result_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    for parameter in binders.get("parameter_binders", []):
        validate_type_v2(parameter["type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    for binding in contract.get("closure_environment", []):
        validate_type_v2(binding["type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions)
    applications = validate_application_ledger(
        contract["applications"], returns={}, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
    )
    validate_computation(
        contract["computation"], applications, context="function", imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
    )


def validate_handler_contract(
    contract: dict[str, Any],
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    exact_fields(contract, {"handled_entry", "prompt_slot", "residual_row", "attributed_demand", "suspension", "semantic_summary", "required_phase", "handler_environment", "applications", "return_computation", "clause_computations"}, "HandlerContractV2")
    for binding in contract["handler_environment"]:
        validate_environment_binding(binding, {})
    validate_summary_normal_form(contract["semantic_summary"])
    validate_phase_requirement(contract["required_phase"])
    applications = validate_application_ledger(
        contract["applications"], returns={}, imports=imports,
        contract_binders={}, local_functions=local_functions,
    )
    validate_computation(
        contract["return_computation"], applications, context="handler_return",
        imports=imports, local_functions=local_functions,
    )
    seen_operations: set[str] = set()
    for clause in contract["clause_computations"]:
        exact_fields(clause, {"operation", "disposition_binder", "computation"}, "ClauseComputationV2")
        operation_key = jcs(clause["operation"])
        require(operation_key not in seen_operations, "duplicate HandlerContractV2 operation")
        seen_operations.add(operation_key)
        disposition = clause["disposition_binder"]
        exact_fields(disposition, {"slot", "site_slot", "type"}, "ClauseDispositionBinderV2")
        validate_type_v2(disposition["type"], imports=imports, local_functions=local_functions)
        require(disposition["type"].get("kind") == "ResumeTypeRefV2", "ClauseDispositionBinderV2 type")
        validate_computation(
            clause["computation"], applications, context="handler_clause", imports=imports,
            local_functions=local_functions, disposition_binder=disposition,
            clause_operation=clause["operation"], handled_entry=contract["handled_entry"],
            handler_prompt_slot=contract["prompt_slot"],
        )


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


def resolve_imports(oracle: dict[str, Any], directory: Path) -> ImportScope:
    resolved = ImportScope()
    for imported in oracle.get("imports", []):
        exact_fields(imported, {"artifact_hash", "file", "module", "function_name"}, "FunctionImportV2")
        target = load_json(directory / imported["file"])
        require(target.get("artifact") == "FunctionContractV2", "ImportedFunctionRefV2 must target a root FunctionContractV2")
        require(target.get("declaration_kind") is not None, "imported FunctionContractV2 declaration_kind must be exact")
        require(canonical_hash(target) == imported["artifact_hash"], f"canonical import hash mismatch for {imported['file']}")
        require(imported["artifact_hash"] not in resolved, "duplicate imported artifact hash")
        resolved[imported["artifact_hash"]] = target
        resolved.exports[imported["artifact_hash"]] = (tuple(imported["module"]), imported["function_name"])
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


def outcome_event(application_slot: int, outcome: dict[str, Any]) -> tuple[int, str, int | None]:
    kind = outcome["kind"]
    site = outcome["park_contract"]["site_slot"] if kind == "TransfersV2" else None
    return application_slot, kind, site


def compose_row(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    if left.get("kind") == "EmptyV1":
        return copy.deepcopy(right)
    if right.get("kind") == "EmptyV1":
        return copy.deepcopy(left)
    if left.get("kind") == right.get("kind") == "ClosedV1":
        entries = sorted(ordered_unique([*left["entries"], *right["entries"]]), key=jcs)
        return {"kind": "ClosedV1", "entries": entries}
    require(left == right, "evaluator cannot normalize incompatible rows")
    return copy.deepcopy(left)


def compose_suspension(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    atoms = sorted(ordered_unique([*left["atoms"], *right["atoms"]]), key=jcs)
    grade = "MaySuspend" if left["grade"] == "MaySuspend" or right["grade"] == "MaySuspend" else "NoSuspend"
    return {"atoms": atoms, "grade": grade}


def compose_path_contracts(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    require(left["outcome"]["kind"] == "ReturnsV2", "only ReturnsV2 enters a PathBind continuation")
    return {
        "LatentSites": sorted(ordered_unique([*left["LatentSites"], *right["LatentSites"]]), key=lambda item: item["site_slot"]),
        "ParametricObligations": sorted(
            ordered_unique([*left["ParametricObligations"], *right["ParametricObligations"]]),
            key=lambda item: (obligation_value(item)["stage"], obligation_value(item)["id"]),
        ),
        "attributed_demand": sorted(ordered_unique([*left["attributed_demand"], *right["attributed_demand"]]), key=jcs),
        "outcome": copy.deepcopy(right["outcome"]),
        "required_phase": compose_phase(left["required_phase"], right["required_phase"]),
        "residual_row": compose_row(left["residual_row"], right["residual_row"]),
        "semantic_summary": normalize_summary_sequence(left["semantic_summary"], right["semantic_summary"]),
        "suspension": compose_suspension(left["suspension"], right["suspension"]),
        "usage": sorted(ordered_unique([*left["usage"], *right["usage"]]), key=jcs),
    }


def qualify_application_locals(value: Any, application_slot: int) -> Any:
    def qualified(number: int) -> int:
        return (application_slot + 1) * 1000 + number

    def rewrite(node: Any) -> Any:
        if isinstance(node, list):
            return [rewrite(member) for member in node]
        if not isinstance(node, dict):
            return node
        result: dict[str, Any] = {}
        is_obligation = node.get("stage") in {"Call", "HandlerInstall"} and isinstance(node.get("id"), int)
        for key, member in node.items():
            if key == "id" and is_obligation:
                result[key] = qualified(member)
            elif key in {"site_slot", "park_site_slot", "continuation_site_slot", "forward_site_slot", "claim_cell_slot", "port_slot"} and isinstance(member, int):
                result[key] = qualified(member)
            elif key in {"call_obligation_ids", "install_obligation_ids", "obligation_ids"} and isinstance(member, list):
                result[key] = [qualified(number) for number in member]
            else:
                result[key] = rewrite(member)
        return result

    return rewrite(value)


def instantiate_invoked_path(path: dict[str, Any], application: dict[str, Any]) -> dict[str, Any]:
    instantiated = qualify_application_locals(
        substitute_contract_kind(path, application["substitution"]),
        application["application_slot"],
    )
    instantiated["ParametricObligations"] = [
        obligation
        for obligation in instantiated["ParametricObligations"]
        if obligation_value(obligation)["stage"] != "Call"
    ]
    for latent in instantiated["LatentSites"]:
        latent["call_obligation_ids"] = []
    return instantiated


def substitute_return_binder(value: Any, binder: dict[str, Any]) -> Any:
    def rewrite(node: Any) -> Any:
        if isinstance(node, list):
            return [rewrite(member) for member in node]
        if not isinstance(node, dict):
            return node
        if node.get("return_slot") != binder["slot"]:
            return {key: rewrite(member) for key, member in node.items()}
        kind = node.get("kind")
        projections = {
            "ReturnWorldV2": "world",
            "ReturnProvenanceV2": "provenance",
            "ReturnCaptureV2": "capture",
            "ReturnNominalIndexV2": "nominal_index",
            "ReturnUsageV2": "usage",
        }
        if kind == "ReturnBoundResultV2":
            return {
                "kind": "ParametricResultV2",
                "provenance": copy.deepcopy(binder["provenance"]),
                "capture": copy.deepcopy(binder["capture"]),
            }
        if kind in projections:
            projected = binder[projections[kind]]
            require(projected is not None, f"return binder has no {projections[kind]} projection")
            return copy.deepcopy(projected)
        require(kind != "ReturnSlotRefV2", "evaluator cannot materialize a return value slot outside its PathBind")
        return {key: rewrite(member) for key, member in node.items()}

    return rewrite(value)


def evaluate_contract_computation(
    contract: dict[str, Any],
    *,
    imports: ImportScope,
    contract_environment: dict[int, dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Evaluate V2 computation to complete normalized PathContractV2 values."""

    contract_environment = contract_environment or {}
    applications = {application["application_slot"]: application for application in contract["applications"]}

    def evaluate(node: dict[str, Any]) -> list[dict[str, Any]]:
        kind = node["kind"]
        if kind == "LiteralPathsV2":
            return [
                {
                    "path": copy.deepcopy(path),
                    "trace": [],
                }
                for path in node["paths"]
            ]
        if kind == "InvokeV2":
            application = applications[node["application_slot"]]
            reference = application["contract"]
            if reference["kind"] == "ImportedFunctionRefV2":
                source = imports[reference["artifact_hash"]]
                nested_environment: dict[int, dict[str, Any]] = {}
                for entry in application["substitution"]["contract_arguments"]:
                    actual = entry["contract"]
                    require(actual["kind"] == "ImportedFunctionRefV2", "evaluator requires resolved contract substitution")
                    nested_environment[entry["binder_slot"]] = imports[actual["artifact_hash"]]
            elif reference["kind"] == "ContractParameterRefV2":
                parameter_slot = reference["parameter"]["slot"]
                require(parameter_slot in contract_environment, "evaluator has no contract-parameter actual")
                source = contract_environment[parameter_slot]
                nested_environment = {}
            else:
                raise AssertionError("evaluator cannot resolve LocalFunctionRefV2")
            paths = evaluate_contract_computation(source, imports=imports, contract_environment=nested_environment)
            return [
                {
                    "path": instantiate_invoked_path(path["path"], application),
                    "trace": [outcome_event(application["application_slot"], path["path"]["outcome"]), *path["trace"]],
                }
                for path in paths
            ]
        if kind == "PathBindV2":
            prefix = evaluate(node["prefix"])
            terminal = [path for path in prefix if path["path"]["outcome"]["kind"] != "ReturnsV2"]
            continued: list[dict[str, Any]] = []
            continuation = evaluate(node["continuation"])
            for returning in (path for path in prefix if path["path"]["outcome"]["kind"] == "ReturnsV2"):
                for suffix in continuation:
                    substituted_suffix = substitute_return_binder(suffix["path"], node["return_binder"])
                    continued.append(
                        {
                            "path": compose_path_contracts(returning["path"], substituted_suffix),
                            "trace": [*returning["trace"], *suffix["trace"]],
                        }
                    )
            return [*terminal, *continued]
        if kind == "JoinV2":
            return [path for member in node["members"] for path in evaluate(member)]
        raise AssertionError(f"evaluator saw unknown computation: {kind}")

    return evaluate(contract["computation"])


def format_evaluated_trace(path: dict[str, Any]) -> str:
    parts = []
    for application_slot, kind, site in path["trace"]:
        suffix = f"(site={site})" if site is not None else ""
        parts.append(f"app{application_slot}:{kind}{suffix}")
    return ">".join(parts)


def validate_hof_oracle(oracle: dict[str, Any], imported: ImportScope) -> None:
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
    evaluated = evaluate_contract_computation(
        apply_later,
        imports=imported,
        contract_environment={0: source},
    )
    evaluated_labels = [format_evaluated_trace(path) for path in evaluated]
    require(len(evaluated) == 7, "twice-invoked mixed callback must evaluate to seven paths")
    require(evaluated_labels == oracle["expectation"]["evaluated_pathbind_paths"], "HOF PathBind evaluation does not match seven-path golden")
    evaluated_contracts = []
    observer_counts = oracle["expectation"]["evaluated_observer_counts"]
    require(observer_counts == [1, 1, 1, 2, 2, 2, 2], "HOF observer-count golden")
    expected_phase = source["computation"]["prefix"]["paths"][0]["required_phase"]
    for item, observer_count in zip(evaluated, observer_counts):
        path = item["path"]
        exact_fields(
            path,
            {"outcome", "residual_row", "attributed_demand", "suspension", "semantic_summary", "usage", "required_phase", "ParametricObligations", "LatentSites"},
            "evaluated PathContractV2",
        )
        validate_path(
            path, applications={}, returns={}, context="function", imports=imported,
            contract_binders={}, local_functions={},
        )
        require(path["residual_row"] == source_kind["visible_row"], "HOF evaluated row observer lost")
        require(len(path["attributed_demand"]) == observer_count, "HOF evaluated demand observer lost")
        require(
            path["suspension"]["grade"] == "NoSuspend"
            and len(path["suspension"]["atoms"]) == observer_count,
            "HOF evaluated suspension observer lost",
        )
        require(path["semantic_summary"] == {"kind": "PureV1"}, "HOF evaluated summary normalization")
        require(path["usage"] == [] and path["required_phase"] == expected_phase, "HOF evaluated usage/phase observer lost")
        require(
            len(path["ParametricObligations"]) == observer_count
            and all(obligation_value(obligation)["stage"] == "HandlerInstall" for obligation in path["ParametricObligations"]),
            "HOF evaluated Q observer lost",
        )
        require(len(path["LatentSites"]) == observer_count, "HOF evaluated Lambda observer lost")
        evaluated_contracts.append(
            {
                "trace": format_evaluated_trace(item),
                "path_hash": canonical_hash(path),
            }
        )
    reject(
        evaluated_contracts != oracle["expectation"]["evaluated_path_contracts"],
        "hof-complete-path-observer-mismatch",
    )


def validate_interface_oracle(oracle: dict[str, Any], directory: Path) -> None:
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong interface oracle profile")
    imported = resolve_imports(oracle, directory)
    validate_function_contract(oracle["contract"], imports=imported)
    if "consumer_contract" in oracle:
        validate_function_contract(oracle["consumer_contract"], imports=imported)
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
    exact_fields(package["child_owner_binder"], {"owner_slot"}, "QuantifiedOwnerBinderV1")
    exact_fields(relation, {"child", "parent", "relation", "sealed_origin"}, "ChildOwnerWitnessV2")
    child = slot("Owner", package["child_owner_binder"]["owner_slot"])
    require(relation == {"child": child, "parent": package["storage_owner"], "relation": "DirectChild", "sealed_origin": "cire.temporal:pack_next"}, "PackedNext direct-child witness")
    clock = package["clock_binder"]
    exact_fields(clock, {"identity_slot", "clock_refinement", "family_witness", "owner"}, "QuantifiedClockBinderV2")
    exact_fields(clock["clock_refinement"], {"clock_slot", "identity"}, "QuantifiedClockRefinementV1")
    reject(clock["family_witness"] != {"kind": "CanonicalFrameClockV2", "module": ["cire", "temporal"], "name": "FrameClock", "sealed_origin": "cire.temporal:FrameClock"}, "clock-package-family-not-clock-indexing")
    require(clock["owner"] == child, "PackedNext clock Owner mismatch")
    identity = slot("Identity", clock["identity_slot"])
    clock_ref = slot("Clock", clock["clock_refinement"]["clock_slot"])
    require(clock["clock_refinement"]["identity"] == identity, "PackedNext identity/clock pairing")
    summary = package["summary_binder"]["kind"]
    exact_fields(package["summary_binder"], {"contract_slot", "kind"}, "QuantifiedContractBinderV2")
    exact_fields(summary, {"kind", "clock", "payload_type"}, "ClockPackageSummaryKindV2")
    require(summary["kind"] == "ClockPackageSummaryKindV2" and summary["clock"] == clock_ref, "PackedNext summary binder")
    body = package["body"]
    require(body["kind"] == "NextTypeV2" and body["clock"] == clock_ref and body["payload"] == summary["payload_type"], "PackedNext body/summary mismatch")
    validate_type_v2(body)
    protocol = package["control_protocol"]
    exact_fields(protocol, {"states", "acquire", "dispose", "release"}, "PackedNextControlProtocolV2")
    reject(protocol != PACKED_CONTROL_PROTOCOL, "packed-next-control-protocol-mismatch")


def validate_clock_open(computation: dict[str, Any]) -> None:
    for path in computation["paths"]:
        for obligation in path["ParametricObligations"]:
            entry = obligation_value(obligation)
            reject(entry.get("kind") == "StableAcrossV2" and entry.get("clock_slot") == slot("Clock", 2), "clock-package-private-identity-escape")
        outcome = path["outcome"]
        reject(outcome["kind"] == "TransfersV2" and outcome["park_contract"]["source"]["owner"] == slot("Owner", 1), "clock-package-transfer-captures-private-identity")
        if outcome["kind"] == "TransfersV2":
            park = outcome["park_contract"]
            owner_atom = {
                "grade": "MaySuspend",
                "kind": "OwnerBoundV1",
                "origin": park["origin"],
                "owner_slot": park["owner_slot"],
                "park_site_slot": park["site_slot"],
            }
            reject(
                path["suspension"] != {"atoms": [owner_atom], "grade": "MaySuspend"}
                or path["required_phase"] != park["required_phase"]
                or path["semantic_summary"]
                != normalize_summary_sequence(
                    PACKED_ACQUIRE_SUMMARY,
                    packed_summary(
                        park["origin"],
                        replay_origin="Fresh",
                        fork="Forbid",
                        suspend="OwnerBound",
                    ),
                    PACKED_RELEASE_SUMMARY,
                ),
                "clock-package-path-observer-mismatch",
            )
        else:
            reject(
                path["required_phase"]["allowed_phases"] != ["Action"]
                or path["semantic_summary"]
                != normalize_summary_sequence(PACKED_ACQUIRE_SUMMARY, PACKED_RELEASE_SUMMARY),
                "clock-package-path-observer-mismatch",
            )
    validate_computation(computation, set())


def validate_clock_oracle(oracle: dict[str, Any]) -> None:
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong clock oracle profile")
    validate_clock_package(oracle["package"])
    validate_path(
        oracle["lost_acquire_path"], applications={}, returns={}, context="function",
        imports=ImportScope(), contract_binders={}, local_functions={},
    )
    lost_summary = oracle["lost_acquire_path"]["semantic_summary"]
    require(lost_summary.get("kind") == "CertificateV1" and lost_summary.get("origin") == "cire.temporal:packed-acquire", "lost acquire must retain its non-Pure summary")
    validate_clock_open(oracle["open_computation"])
    outcomes = [path["outcome"]["kind"] for path in oracle["open_computation"]["paths"]]
    require(outcomes == ["ReturnsV2", "AbortsV2", "TransfersV2", "TransfersV2"], "PackedNext won path set")
    body_observers = oracle["body_observers"]
    require(len(body_observers) == len(outcomes), "PackedNext body observer cardinality")
    observer_fields = {
        "residual_row", "attributed_demand", "suspension", "semantic_summary",
        "usage", "required_phase", "ParametricObligations", "LatentSites",
    }
    for index, (body, path) in enumerate(zip(body_observers, oracle["open_computation"]["paths"])):
        require(body["path_index"] == index and body["input_tag"] == outcomes[index], "PackedNext body path correspondence")
        if outcomes[index] == "TransfersV2":
            require(path["outcome"]["park_contract"]["site_slot"] == body["terminal_site"], "PackedNext Park body/site mismatch")
        for field in observer_fields - {"semantic_summary", "required_phase"}:
            require(path[field] == body[field], f"PackedNext body observer lost: {field} on path {index}")
        expected_phase = copy.deepcopy(body["required_phase"])
        require("Action" in expected_phase["allowed_phases"], f"PackedNext body path {index} is not Action-admissible")
        expected_phase["allowed_phases"] = ["Action"]
        require(path["required_phase"] == expected_phase, f"PackedNext body phase/authority lost on path {index}")
        summary = path["semantic_summary"]
        expected_summary = normalize_summary_sequence(
            oracle["lost_acquire_path"]["semantic_summary"],
            body["semantic_summary"],
            oracle["release_evidence"][index]["release_summary"],
        )
        require(summary == expected_summary, f"won path canonical acquire/body/release summary mismatch on path {index}")
    pack_observers = oracle["pack_observers"]
    require(len(pack_observers) == len(body_observers), "T-Pack observer cardinality")
    for index, (body, packed) in enumerate(zip(body_observers, pack_observers)):
        require(packed["path_index"] == index and packed["input_tag"] == body["input_tag"] == packed["output_tag"], "T-Pack terminal tag preservation")
        allocate = next(
            member for member in walk(packed["semantic_summary"])
            if isinstance(member, dict) and member.get("origin") == "cire.temporal:packed-allocate"
        )
        owner = oracle["package"]["storage_owner"]
        pack_phase = {
            "allowed_phases": ["Action"],
            "current_owner": owner,
            "required_authorities": [{"kind": "OwnerAuthorityV1", "owner": owner}],
        }
        reject(
            packed["required_phase"] != compose_phase(body["required_phase"], pack_phase),
            "packed-next-pack-phase-mismatch",
        )
        if body["input_tag"] == "ReturnsV2":
            expected_summary = normalize_summary_sequence(allocate, body["semantic_summary"])
            require(packed["close_action"] is None and packed["semantic_summary"] == expected_summary, "T-Pack Returns observer sequence")
        else:
            require(packed["close_action"] == "CloseChildOnceBeforeExit", "T-Pack terminal close action missing")
            terminal_close = next(
                member for member in walk(packed["semantic_summary"])
                if isinstance(member, dict) and member.get("origin") == "cire.temporal:packed-terminal-close"
            )
            expected_summary = normalize_summary_sequence(allocate, body["semantic_summary"], terminal_close)
            require(packed["semantic_summary"] == expected_summary, "T-Pack terminal observer sequence")
    evidence = oracle["release_evidence"]
    require(len(evidence) == len(outcomes), "PackedNext release evidence cardinality")
    for index, item in enumerate(evidence):
        require(item["path_index"] == index and item["input_tag"] == outcomes[index] == item["output_tag"], "PackedNext tag preservation")
        require(item["lease_action"] == "ExactlyOnceRelease", "PackedNext release count")


def validate_flow_oracle(oracle: dict[str, Any]) -> None:
    exact_fields(
        oracle,
        {"artifact", "profile", "schema_version", "binders", "flow_summary", "park_obligations", "suspension", "route_examples", "expectation"},
        "CireSpecWireVariantOracleV2",
    )
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong flow oracle profile")
    validate_declaration_binders(oracle["binders"], [])
    outcomes = [path["kind"] for path in oracle["flow_summary"]]
    require(outcomes == ["AbortsV2", "TransfersV2"], "flow oracle variants")
    parked_owner, resumption_owner = validate_park(oracle["flow_summary"][1]["park_contract"])
    for obligation in oracle["park_obligations"]:
        validate_obligation(obligation, {})
    if parked_owner != resumption_owner:
        reject(
            not any(
                obligation.get("kind") == "OutlivesV2"
                and obligation["shorter"] == {"kind": "LegacySlotRefV2", "value": resumption_owner}
                and obligation["longer"] == {"kind": "LegacySlotRefV2", "value": parked_owner}
                for obligation in oracle["park_obligations"]
            ),
            "park-owner-outlives-missing",
        )


def validate_handler_oracle(oracle: dict[str, Any], directory: Path) -> None:
    exact_fields(oracle, {"artifact", "profile", "schema_version", "subject", "binders", "imports", "handler_contract", "outward_function_contract", "expectation"}, "CireHandlerContractOracleV2")
    require(oracle["profile"] == PROFILE and oracle["schema_version"] == 2, "wrong handler oracle profile")
    validate_declaration_binders(oracle["binders"], [])
    prompt_slots = [binder["prompt_slot"] for binder in oracle["binders"]["prompt_binders"]]
    require(len(prompt_slots) == len(set(prompt_slots)) and {0, 1} <= set(prompt_slots), "handler oracle prompt scope")
    imported = resolve_imports(oracle, directory)
    validate_handler_contract(oracle["handler_contract"], imports=imported)
    validate_function_contract(oracle["outward_function_contract"])
    applications = oracle["handler_contract"]["applications"]
    require(
        [application["application_slot"] for application in applications]
        == oracle["expectation"]["clause_application_ledger"],
        "handler oracle application ledger",
    )
    return_computation = oracle["handler_contract"]["return_computation"]
    require(
        return_computation["kind"] == "PathBindV2"
        and return_computation["prefix"] == {"kind": "InvokeV2", "application_slot": applications[0]["application_slot"]},
        "handler oracle return application not consumed",
    )
    source = imported[applications[0]["contract"]["artifact_hash"]]
    validate_application_return_binder(source, applications[0], return_computation["return_binder"])
    clause = oracle["handler_contract"]["clause_computations"][0]
    continuation_path = clause["computation"]["continuation"]["paths"][0]
    require(continuation_path["outcome"]["kind"] == "DelegatesV2", "handler oracle positive DelegatesV2")
    forward = continuation_path["outcome"]["forward_contract"]
    require(
        forward["route"]["prompt_slot"] in prompt_slots
        and forward["route"]["prompt_slot"] != oracle["handler_contract"]["prompt_slot"],
        "handler oracle Forward outer route is unbound",
    )
    return_slot = oracle["expectation"]["return_bound_authority_slot"]
    surfaces = {
        "PathContractV2.usage": any(item.get("kind") == "ReturnUsageV2" and item.get("return_slot") == return_slot for item in continuation_path["usage"]),
        "BoundarySafeV2.slots": any(node.get("kind") == "ReturnSlotRefV2" and node.get("return_slot") == return_slot for node in walk(continuation_path["ParametricObligations"]) if isinstance(node, dict)),
        "LiveAcrossSiteV2.usage": any(node.get("kind") == "ReturnUsageV2" and node.get("return_slot") == return_slot for node in walk(continuation_path["LatentSites"]) if isinstance(node, dict)),
    }
    require(all(surfaces.values()) and set(surfaces) == set(oracle["expectation"]["return_usage_surfaces"]), "return-bound authority surfaces incomplete")


def validate_local_contract_oracle(oracle: dict[str, Any]) -> None:
    exact_fields(
        oracle,
        {"artifact", "profile", "schema_version", "subject", "local_declarations", "contract", "expectation"},
        "CireLocalContractOracleV2",
    )
    require(oracle["profile"] == PROFILE and oracle["schema_version"] == 2, "wrong local contract oracle profile")
    local_functions: LocalFunctionScope = {}
    for declaration in oracle["local_declarations"]:
        exact_fields(declaration, {"declaration_slot", "module", "name", "contract"}, "LocalFunctionDeclarationV2")
        declaration_slot = declaration["declaration_slot"]
        require(declaration_slot not in local_functions, "duplicate local function declaration slot")
        local_functions[declaration_slot] = declaration["contract"]
    for contract in local_functions.values():
        validate_function_contract(contract, local_functions=local_functions)
    validate_function_contract(oracle["contract"], local_functions=local_functions)
    applications = oracle["contract"]["applications"]
    require(
        [application["contract"]["declaration_slot"] for application in applications] == oracle["expectation"]["resolved_local_slots"],
        "local FunctionContractRef resolution expectation",
    )


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
    elif artifact == "CireHandlerContractOracleV2":
        validate_handler_oracle(document, directory)
    elif artifact == "CireLocalContractOracleV2":
        validate_local_contract_oracle(document)
    else:
        raise AssertionError(f"unknown interface artifact: {artifact}")


def validate_v1_decoder(target: dict[str, Any]) -> None:
    reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(target)), "unsupported-contract-schema-version")


def decode_named(decoder: str, target: dict[str, Any], document: dict[str, Any], directory: Path) -> None:
    if decoder in {"FunctionContractV1", "ParkContractV1"}:
        validate_v1_decoder(target)
    elif decoder == "FunctionContractV2":
        imported = resolve_imports(document, directory) if document.get("artifact") in {"CireSpecInterfaceOracleV2", "CireHandlerContractOracleV2"} else {}
        validate_function_contract(target, imports=imported)
    elif decoder == "CireSpecInterfaceOracleV2":
        validate_interface_oracle(target, directory)
    elif decoder == "CireClockPackageOracleV2":
        validate_clock_oracle(target)
    elif decoder == "CireSpecWireVariantOracleV2":
        validate_flow_oracle(target)
    elif decoder == "CireLocalContractOracleV2":
        validate_local_contract_oracle(target)
    elif decoder == "CireRuntimeModelOracleV2":
        validate_runtime_oracle(target)
    elif decoder == "ParkContractV2":
        validate_park(target)
    elif decoder == "PackedNextPackageV2":
        validate_clock_package(target)
    elif decoder == "T-Clock-Unpack-Paths":
        validate_clock_open(target)
    elif decoder == "HandlerContractV2":
        imported = resolve_imports(document, directory) if document.get("artifact") == "CireHandlerContractOracleV2" else {}
        validate_handler_contract(target, imports=imported)
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


def validate_diagnostics() -> int:
    registry = load_json(DIAGNOSTICS)
    exact_fields(registry, {"artifact", "profile", "schema_version", "diagnostics"}, "CireDiagnosticRegistryV2")
    require(
        registry["artifact"] == "CireDiagnosticRegistryV2"
        and registry["profile"] == PROFILE
        and registry["schema_version"] == 2,
        "diagnostic registry header",
    )
    identifiers = []
    for diagnostic in registry["diagnostics"]:
        exact_fields(diagnostic, {"id", "stage"}, "DiagnosticV2")
        identifiers.append(diagnostic["id"])
    require(len(identifiers) == len(set(identifiers)), "duplicate diagnostic registry id")
    mutation_ids = {case["diagnostic"] for case in load_json(MUTATIONS)["cases"]}
    require(mutation_ids <= set(identifiers), "mutation oracle uses an unregistered diagnostic")
    return len(identifiers)


def runtime_table_from_control(protocol: dict[str, Any]) -> list[dict[str, Any]]:
    table: list[dict[str, Any]] = []
    for event in ("acquire", "dispose", "release"):
        for encoded in protocol[event]:
            source, target = encoded.split("->", 1)
            constraint = None
            if "," in target:
                target, constraint = target.split(",", 1)
            transition: dict[str, Any] = {"event": event, "from": source, "to": target}
            if constraint is not None:
                transition["from"] += f", {constraint}"
            if target == "None":
                transition["result"] = "None"
                transition["to"] = source
            elif target.endswith("+CloseChild"):
                transition["to"] = target.removesuffix("+CloseChild")
                transition["side_effect"] = "CloseChildOnce"
            table.append(transition)
    return table


def match_state_pattern(pattern: str, state: tuple[str, int]) -> int | None:
    kind, leases = state
    expression, _, constraint = pattern.partition(", ")
    if expression == "Closed":
        return 0 if kind == "Closed" else None
    expected_kind, argument = expression.removesuffix(")").split("(", 1)
    if kind != expected_kind:
        return None
    if argument == "0":
        return 0 if leases == 0 else None
    if argument == "1":
        return 0 if leases == 1 else None
    if argument == "n":
        n = leases
    elif argument == "n+1":
        if leases < 1:
            return None
        n = leases - 1
    else:
        raise AssertionError(f"unknown PackedNext state pattern: {pattern}")
    if constraint == "n>=1" and n < 1:
        return None
    return n


def instantiate_state_pattern(pattern: str, n: int) -> tuple[str, int]:
    if pattern == "Closed":
        return "Closed", 0
    kind, argument = pattern.removesuffix(")").split("(", 1)
    if argument == "0":
        leases = 0
    elif argument == "1":
        leases = 1
    elif argument == "n":
        leases = n
    elif argument == "n+1":
        leases = n + 1
    else:
        raise AssertionError(f"unknown PackedNext target pattern: {pattern}")
    return kind, leases


def step_packed(
    transition_table: list[dict[str, Any]],
    state: tuple[str, int],
    event: str,
) -> tuple[tuple[str, int], int, int, str | None, str | None]:
    close = release = 0
    result = tag = None
    protocol_event = next((name for name in ("acquire", "dispose", "release") if event.startswith(name)), event)
    if protocol_event in {"acquire", "dispose", "release"}:
        matches = []
        for transition in transition_table:
            if transition["event"] != protocol_event:
                continue
            n = match_state_pattern(transition["from"], state)
            if n is not None:
                matches.append((transition, n))
        require(len(matches) == 1, f"PackedNext protocol is non-total or ambiguous for {state}/{protocol_event}")
        transition, n = matches[0]
        state = instantiate_state_pattern(transition["to"], n)
        close = int(transition.get("side_effect") == "CloseChildOnce")
        release = int(protocol_event == "release")
        result = transition.get("result")
    elif event.startswith("body-Returns"):
        result = "Some"
    elif event.startswith("body-Aborts"):
        tag = "Aborts"
    elif event.startswith("body-Transfers"):
        tag = event.removeprefix("body-")
    else:
        raise AssertionError(f"unknown PackedNext event: {event}")
    return state, close, release, result, tag


def state_text(state: tuple[str, int]) -> str:
    return "Closed" if state[0] == "Closed" else f"{state[0]}({state[1]})"


def validate_runtime_oracle(oracle: dict[str, Any]) -> int:
    exact_fields(oracle, {"artifact", "profile", "schema_version", "subject", "initial_state", "transition_table", "traces"}, "CireRuntimeModelOracleV2")
    require(oracle.get("artifact") == "CireRuntimeModelOracleV2" and oracle.get("profile") == PROFILE, "runtime oracle header")
    exact_fields(oracle["initial_state"], {"kind", "leases"}, "PackedNextRuntimeStateV2")
    reject(oracle["initial_state"] != {"kind": "Open", "leases": 0}, "packed-next-runtime-protocol-mismatch")
    package_oracle = load_json(INTERFACES / "clock-package-paths.json")
    validate_clock_package(package_oracle["package"])
    expected_table = runtime_table_from_control(package_oracle["package"]["control_protocol"])
    for transition in oracle["transition_table"]:
        require(set(transition) in ({"event", "from", "to"}, {"event", "from", "to", "result"}, {"event", "from", "to", "side_effect"}), "runtime transition fields")
    reject(oracle["transition_table"] != expected_table, "packed-next-runtime-protocol-mismatch")
    for trace in oracle["traces"]:
        state = (oracle["initial_state"]["kind"], oracle["initial_state"]["leases"])
        close_count = release_count = 0
        result = tag = None
        observed_states: list[str] = []
        for event in trace["events"]:
            state, close, release, step_result, step_tag = step_packed(oracle["transition_table"], state, event)
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


def validate_runtime() -> int:
    return validate_runtime_oracle(load_json(RUNTIME))


def main() -> int:
    interface_paths = sorted(INTERFACES.glob("*.json"))
    for path in interface_paths:
        validate_document(load_json(path), path.parent)
    diagnostic_count = validate_diagnostics()
    mutation_cases, mutation_operations = validate_mutations()
    runtime_count = validate_runtime()
    print(
        f"PASS: {len(interface_paths)} interface artifacts, "
        f"{mutation_cases} decoder mutation cases/{mutation_operations} RFC 6902 operations, "
        f"{runtime_count} runtime traces, {diagnostic_count} diagnostic ids"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
