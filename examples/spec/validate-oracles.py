#!/usr/bin/env python3
"""Execute the Cire-TR₀ V2 JSON interface, mutation, and runtime oracles.

This is the executable reference decoder for the frozen V2 wire profile, not a
compiler implementation. Its computation/outcome import is exhaustive and
threads application, return-binder, and Handler-clause disposition scope. It
also evaluates each mutation through the named decoder and checks the exact
diagnostic that decoder emits. Task #28-#35 and #45 regressions additionally exercise
formal-conformance clusters through complete root contracts.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any, Callable, Iterable


ROOT = Path(__file__).resolve().parent
INTERFACES = ROOT / "interfaces"
MUTATIONS = ROOT / "mutations" / "v1-rejects-v2-tags.json"
RUNTIME = ROOT / "runtime" / "packed-next-lease-runtime.json"
DIAGNOSTICS = ROOT / "diagnostics-v2.json"
TASK35_REGRESSIONS = ROOT / "task35-regressions.py"
TASK45_REGRESSIONS = ROOT / "task45-regressions.py"
TASK46_REGRESSIONS = ROOT / "task46-regressions.py"
EFFECT_FAMILY_DECLARATIONS = INTERFACES / "effect-family-declarations.json"
FORMALIZATION = ROOT.parent.parent / "docs" / "temporal-reactivity-formalization.typ"
PROFILE = "Cire-TR₀/2026-08-01"
U32_MAX = (1 << 32) - 1
WIRE_U32_FIELDS = {
    "application_slot", "arity", "binder_site_slot", "binder_slot", "claim_cell_slot",
    "clock_slot", "continuation_site_slot", "contract_slot", "declaration_slot",
    "forward_site_slot", "id", "identity_slot", "local_id", "owner_slot", "park_site_slot",
    "path_index", "port_slot", "prompt_slot", "return_slot", "secondary_slot",
    "site_slot", "slot", "source_local_id", "source_site_slot",
}
WIRE_U32_OR_SLOT_REF_FIELDS = {"clock_slot", "owner_slot", "slot"}


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


def exact_fields(value: Any, expected: set[str], label: str) -> None:
    reject(not isinstance(value, dict), "contract-component-kind-mismatch")
    reject(set(value) != expected, "contract-component-kind-mismatch")


def validate_contract_object(value: Any) -> dict[str, Any]:
    """Turn malformed recursive wire nodes into the profile's stable diagnostic."""

    reject(not isinstance(value, dict), "contract-component-kind-mismatch")
    return value


def validate_contract_list(value: Any) -> list[Any]:
    reject(not isinstance(value, list), "contract-component-kind-mismatch")
    return value


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
    for authority in authorities:
        kind = authority.get("kind")
        if kind == "OwnerAuthorityV1":
            exact_fields(authority, {"kind", "owner"}, kind)
            validate_slot_v1(authority["owner"], "Owner")
        elif kind == "IdentityAuthorityV1":
            exact_fields(authority, {"kind", "identity"}, kind)
            validate_slot_v1(authority["identity"], "Identity")
        elif kind == "AnonymousEffectAuthorityV1":
            exact_fields(authority, {"kind", "family"}, kind)
            validate_effect_family_ref(authority["family"])
        else:
            raise Diagnostic("contract-component-kind-mismatch")
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


def validate_u32(value: Any, label: str) -> None:
    reject(
        isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= U32_MAX,
        "wire-u32-out-of-range",
    )


def validate_wire_u32_fields(value: Any) -> None:
    """Range-check every field name declared u32 by the frozen wire schema."""

    if isinstance(value, list):
        for member in value:
            validate_wire_u32_fields(member)
        return
    if not isinstance(value, dict):
        return
    for key, member in value.items():
        if key in WIRE_U32_FIELDS:
            if key not in WIRE_U32_OR_SLOT_REF_FIELDS or not isinstance(member, dict):
                validate_u32(member, key)
        validate_wire_u32_fields(member)


def validate_source_origins(value: Any) -> None:
    """SourceOriginV1/V2 is always the canonical file:subject string."""

    if isinstance(value, list):
        for member in value:
            validate_source_origins(member)
        return
    if not isinstance(value, dict):
        return
    if "origin" in value:
        reject(
            not isinstance(value["origin"], str)
            or re.fullmatch(r"[^:\s]+:[^:\s]+", value["origin"]) is None,
            "contract-component-kind-mismatch",
        )
    for member in value.values():
        validate_source_origins(member)


ReturnScope = dict[int, dict[str, Any]]
ApplicationScope = dict[int, dict[str, Any]]
LocalFunctionScope = dict[int, dict[str, Any]]


class DeclarationScope:
    """The complete lexical declaration tables inherited by inline handlers."""

    def __init__(
        self,
        *,
        type_parameter_kinds: dict[int, str],
        row_binders: dict[int, dict[str, Any]],
        contract_binders: dict[int, dict[str, Any]],
        identity_binders: dict[int, dict[str, Any]],
        handler_contract_binders: set[int],
        owner_binders: dict[int, dict[str, Any]] | None = None,
        clock_binders: dict[int, dict[str, Any]] | None = None,
        prompt_binders: set[int] | None = None,
        parameter_binders: set[int] | None = None,
        closure_capture_binders: set[int] | None = None,
        enforce_ordinary_slots: bool = True,
    ) -> None:
        self.type_parameter_kinds = type_parameter_kinds
        self.row_binders = row_binders
        self.contract_binders = contract_binders
        self.identity_binders = identity_binders
        self.handler_contract_binders = handler_contract_binders
        self.owner_binders = owner_binders or {}
        self.clock_binders = clock_binders or {}
        self.prompt_binders = prompt_binders or set()
        self.parameter_binders = parameter_binders or set()
        self.closure_capture_binders = closure_capture_binders or set()
        self.enforce_ordinary_slots = enforce_ordinary_slots

    def nested(
        self,
        *,
        contract_binders: dict[int, dict[str, Any]] | None = None,
        identity_binders: dict[int, dict[str, Any]] | None = None,
        owner_binders: dict[int, dict[str, Any]] | None = None,
        clock_binders: dict[int, dict[str, Any]] | None = None,
    ) -> DeclarationScope:
        """Copy this lexical scope while replacing selected nested tables."""

        nested_contracts = (
            self.contract_binders
            if contract_binders is None
            else contract_binders
        )
        nested_handler_contracts = (
            self.handler_contract_binders
            if contract_binders is None
            else {
                slot_number
                for slot_number, binder in nested_contracts.items()
                if binder.get("kind") == "HandlerContractBinderV2"
            }
        )

        return DeclarationScope(
            type_parameter_kinds=self.type_parameter_kinds,
            row_binders=self.row_binders,
            contract_binders=nested_contracts,
            identity_binders=(
                self.identity_binders
                if identity_binders is None
                else identity_binders
            ),
            handler_contract_binders=nested_handler_contracts,
            owner_binders=(
                self.owner_binders if owner_binders is None else owner_binders
            ),
            clock_binders=(
                self.clock_binders if clock_binders is None else clock_binders
            ),
            prompt_binders=self.prompt_binders,
            parameter_binders=self.parameter_binders,
            closure_capture_binders=self.closure_capture_binders,
            enforce_ordinary_slots=self.enforce_ordinary_slots,
        )


def declaration_scope_from_binders(
    binders: dict[str, Any],
    closure_environment: list[dict[str, Any]] | None = None,
) -> DeclarationScope:
    """Project a complete declaration table from a validated root binder set."""

    contract_binders = {
        binder["slot"]: binder for binder in binders["contract_binders"]
    }
    return DeclarationScope(
        type_parameter_kinds={
            binder["slot"]: binder["kind"]
            for binder in binders["type_binders"]
        },
        row_binders={
            binder["slot"]: binder for binder in binders["row_binders"]
        },
        contract_binders=contract_binders,
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
            for binding in closure_environment or []
            if binding.get("slot", {}).get("namespace") == "ClosureCapture"
        },
    )


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
PACKED_ALLOCATE_SUMMARY = packed_summary(
    "cire.temporal:packed-allocate",
    replay_origin="Fresh",
    fork="Share",
    suspend="StackOnly",
)
PACKED_TERMINAL_CLOSE_SUMMARY = packed_summary(
    "cire.temporal:packed-terminal-close",
    replay_origin="Fresh",
    fork="Forbid",
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
    value = validate_contract_object(value)
    exact_fields(value, {"namespace", "slot"}, "SlotRefV1")
    validate_u32(value["slot"], "SlotRefV1 slot")
    reject(
        value["namespace"] not in {
            "Parameter", "ClosureCapture", "OperationArgument", "SuffixLive",
            "Clock", "Owner", "Row", "Identity",
        },
        "contract-component-kind-mismatch",
    )
    if namespace is not None:
        reject(
            value["namespace"] != namespace,
            "contract-component-kind-mismatch",
        )


def validate_effect_family_ref(
    family: Any,
    type_parameter_kinds: dict[int, str] | None = None,
) -> None:
    """Decode an Effect-family position without treating arbitrary Type refs as families."""

    family = validate_contract_object(family)
    kind = family.get("kind")
    if kind in {"TypeParameterV1", "TypeParameterV2"}:
        exact_fields(family, {"kind", "slot"}, kind)
        validate_u32(family["slot"], f"{kind} slot")
        if type_parameter_kinds is not None:
            reject(
                family["slot"] not in type_parameter_kinds,
                "contract-projection-escapes-scope",
            )
            reject(
                type_parameter_kinds[family["slot"]] != "Effect",
                "contract-component-kind-mismatch",
            )
        return
    if kind == "NominalTypeV1":
        validate_type_v1(family)
        declarations = validate_effect_family_declarations(
            load_json(EFFECT_FAMILY_DECLARATIONS)
        )
        identity = (tuple(family["module"]), family["name"])
        reject(
            identity not in declarations
            or declarations[identity] != len(family["arguments"]),
            "contract-component-kind-mismatch",
        )
        return
    raise Diagnostic("contract-component-kind-mismatch")


def validate_effect_family_declarations(
    document: Any,
) -> dict[tuple[tuple[str, ...], str], int]:
    """Decode the consumable nominal declaration environment for interface roots."""

    document = validate_contract_object(document)
    exact_fields(
        document,
        {"artifact", "families", "profile", "schema_version"},
        "EffectFamilyDeclarationsV1",
    )
    reject(
        document["artifact"] != "EffectFamilyDeclarationsV1"
        or document["profile"] != PROFILE
        or document["schema_version"] != 1,
        "contract-component-kind-mismatch",
    )
    result: dict[tuple[tuple[str, ...], str], int] = {}
    encodings: list[str] = []
    for declaration in validate_contract_list(document["families"]):
        declaration = validate_contract_object(declaration)
        exact_fields(
            declaration,
            {"arity", "module", "name"},
            "EffectFamilyDeclarationV1",
        )
        module = validate_contract_list(declaration["module"])
        reject(
            not module
            or not all(isinstance(part, str) and part for part in module)
            or not isinstance(declaration["name"], str)
            or not declaration["name"],
            "contract-component-kind-mismatch",
        )
        validate_u32(declaration["arity"], "effect family arity")
        identity = (tuple(module), declaration["name"])
        reject(identity in result, "contract-component-kind-mismatch")
        result[identity] = declaration["arity"]
        encodings.append(jcs(declaration))
    reject(
        encodings != sorted(encodings),
        "contract-component-kind-mismatch",
    )
    return result


def validate_effect_entry_selector(
    entry: Any,
    type_parameter_kinds: dict[int, str] | None = None,
    *,
    identity_binders: dict[int, dict[str, Any]] | None = None,
    handler_contract_binders: set[int] | None = None,
) -> None:
    entry = validate_contract_object(entry)
    kind = entry.get("kind")
    if kind == "AnonV1":
        exact_fields(entry, {"kind", "family"}, kind)
    elif kind == "NamedV1":
        exact_fields(entry, {"kind", "identity", "family"}, kind)
        validate_slot_v1(entry["identity"], "Identity")
    elif kind == "HandlerEntryParameterV1":
        exact_fields(entry, {"kind", "contract_slot"}, kind)
        validate_u32(entry["contract_slot"], "handler entry contract slot")
        if handler_contract_binders is not None:
            reject(
                entry["contract_slot"] not in handler_contract_binders,
                "contract-projection-escapes-scope",
            )
    else:
        raise Diagnostic("contract-component-kind-mismatch")
    if "family" in entry:
        validate_effect_family_ref(entry["family"], type_parameter_kinds)
    if kind == "NamedV1" and identity_binders is not None:
        identity_slot = entry["identity"]["slot"]
        reject(
            identity_slot not in identity_binders,
            "contract-projection-escapes-scope",
        )
        reject(
            normalized_effect_family_v2(
                identity_binders[identity_slot]["family"]
            )
            != normalized_effect_family_v2(entry["family"]),
            "contract-component-kind-mismatch",
        )


def validate_operation_selector(
    operation: Any,
    type_parameter_kinds: dict[int, str] | None = None,
) -> None:
    operation = validate_contract_object(operation)
    kind = operation.get("kind")
    if kind == "ExactOperationV1":
        exact_fields(operation, {"kind", "family", "name"}, kind)
        validate_effect_family_ref(operation["family"], type_parameter_kinds)
        reject(
            not isinstance(operation["name"], str) or not operation["name"],
            "contract-component-kind-mismatch",
        )
    elif kind == "AnyOperationOfEntry":
        exact_fields(operation, {"kind"}, kind)
    else:
        raise Diagnostic("forward-operation-mismatch")


AttributionKey = tuple[int, str, str, str, str]


def validate_route_selector(
    route: Any,
    *,
    declaration_scope: DeclarationScope | None = None,
    allow_outer: bool = False,
) -> dict[str, Any]:
    route = validate_contract_object(route)
    kind = route.get("kind")
    if kind in {"ResolveAtCallV1", "ResolveAtInstallationV1"}:
        exact_fields(route, {"kind", "on_missing"}, kind)
        reject(route["on_missing"] != "RootOfEntryV1", "contract-component-kind-mismatch")
    elif kind in {"InstallationPromptV1", "OuterOfV1"}:
        exact_fields(route, {"kind", "prompt_slot"}, kind)
        validate_u32(route["prompt_slot"], f"{kind} prompt_slot")
    elif kind == "RootOfEntryV1":
        exact_fields(route, {"kind"}, kind)
    else:
        raise Diagnostic("contract-component-kind-mismatch")

    reject(
        kind == "OuterOfV1" and not allow_outer,
        "contract-component-kind-mismatch",
    )
    if declaration_scope is not None and kind in {
        "InstallationPromptV1", "OuterOfV1",
    }:
        reject(
            route["prompt_slot"] not in declaration_scope.prompt_binders,
            "contract-projection-escapes-scope",
        )
    return route


def attribution_key(
    *,
    site_slot: int,
    route: dict[str, Any],
    entry: dict[str, Any],
    operation: dict[str, Any],
    site_role: str | dict[str, Any],
) -> AttributionKey:
    """Return the canonical key shared by demand, request, and site evidence."""

    return (
        site_slot,
        jcs(route),
        jcs(entry),
        jcs(operation),
        jcs(site_role),
    )


def validate_attributed_request_keys(
    demand_keys: list[AttributionKey],
    request_keys: list[AttributionKey],
    *,
    site_keys: list[AttributionKey] | None = None,
) -> None:
    """Enforce AttributedOK without trusting any serialized aggregate."""

    reject(
        len(demand_keys) != len(set(demand_keys))
        or len(request_keys) != len(set(request_keys))
        or set(demand_keys) != set(request_keys),
        "contract-component-kind-mismatch",
    )
    if site_keys is not None:
        reject(
            len(site_keys) != len(set(site_keys))
            or not set(request_keys).issubset(site_keys),
            "contract-component-kind-mismatch",
        )


def validate_suspension(
    suspension: Any,
    *,
    declaration_scope: DeclarationScope | None = None,
) -> list[AttributionKey]:
    suspension = validate_contract_object(suspension)
    exact_fields(suspension, {"atoms", "grade"}, "SuspensionV1")
    reject(suspension["grade"] not in {"NoSuspend", "MaySuspend"}, "contract-component-kind-mismatch")
    request_keys: list[AttributionKey] = []
    atoms = validate_contract_list(suspension["atoms"])
    for atom in atoms:
        atom = validate_contract_object(atom)
        kind = atom.get("kind")
        if kind == "DirectV1":
            exact_fields(atom, {"kind", "grade", "origin"}, kind)
            reject(atom["grade"] != "MaySuspend", "contract-component-kind-mismatch")
        elif kind == "RequestV1":
            exact_fields(
                atom,
                {"kind", "site_slot", "route", "entry", "operation", "site_role", "grade", "origin"},
                kind,
            )
            validate_u32(atom["site_slot"], "RequestV1 site_slot")
            route = validate_route_selector(
                atom["route"], declaration_scope=declaration_scope,
            )
            validate_effect_entry_selector(atom["entry"])
            validate_operation_selector(atom["operation"])
            reject(atom["grade"] not in {"NoSuspend", "MaySuspend"}, "contract-component-kind-mismatch")
            role = atom["site_role"]
            if role != "Primary":
                role = validate_contract_object(role)
                exact_fields(role, {"kind", "secondary_slot"}, "Secondary")
                reject(role["kind"] != "Secondary", "contract-component-kind-mismatch")
                validate_u32(role["secondary_slot"], "RequestV1 secondary_slot")
            request_keys.append(
                attribution_key(
                    site_slot=atom["site_slot"], route=route,
                    entry=atom["entry"], operation=atom["operation"],
                    site_role=role,
                )
            )
        elif kind == "OwnerBoundV1":
            exact_fields(atom, {"kind", "park_site_slot", "owner_slot", "grade", "origin"}, kind)
            validate_u32(atom["park_site_slot"], "OwnerBoundV1 park_site_slot")
            validate_u32(atom["owner_slot"], "OwnerBoundV1 owner_slot")
            reject(atom["grade"] not in {"NoSuspend", "MaySuspend"}, "contract-component-kind-mismatch")
        else:
            raise Diagnostic("contract-component-kind-mismatch")

    expected_grade = (
        "MaySuspend"
        if any(atom["grade"] == "MaySuspend" for atom in atoms)
        else "NoSuspend"
    )
    reject(
        suspension["grade"] != expected_grade,
        "contract-component-kind-mismatch",
    )
    return request_keys


def validate_demand(
    demand: Any,
    *,
    declaration_scope: DeclarationScope | None = None,
) -> AttributionKey:
    demand = validate_contract_object(demand)
    exact_fields(
        demand,
        {"site_slot", "route", "entry", "operation", "site_role"},
        "DemandV1",
    )
    validate_u32(demand["site_slot"], "DemandV1 site_slot")
    route = validate_route_selector(
        demand["route"], declaration_scope=declaration_scope,
    )
    validate_effect_entry_selector(demand["entry"])
    validate_operation_selector(demand["operation"])
    role = demand["site_role"]
    if role != "Primary":
        role = validate_contract_object(role)
        exact_fields(role, {"kind", "secondary_slot"}, "Secondary")
        reject(role["kind"] != "Secondary", "contract-component-kind-mismatch")
        validate_u32(role["secondary_slot"], "DemandV1 secondary_slot")
    return attribution_key(
        site_slot=demand["site_slot"], route=route,
        entry=demand["entry"], operation=demand["operation"],
        site_role=role,
    )


def validate_row_expr(row: Any) -> None:
    row = validate_contract_object(row)
    kind = row.get("kind")
    if kind == "EmptyV1":
        exact_fields(row, {"kind"}, kind)
    elif kind == "ClosedV1":
        exact_fields(row, {"kind", "entries"}, kind)
        entries = validate_contract_list(row["entries"])
        for entry in entries:
            validate_effect_entry_selector(entry)
        reject(entries != sorted(ordered_unique(entries), key=jcs), "contract-parameter-inconsistent-instantiation")
    elif kind == "TailV1":
        exact_fields(row, {"kind", "row_slot"}, kind)
        validate_slot_v1(row["row_slot"], "Row")
    elif kind == "UnionV1":
        exact_fields(row, {"kind", "members"}, kind)
        members = validate_contract_list(row["members"])
        reject(len(members) < 2, "contract-parameter-inconsistent-instantiation")
        reject(members != sorted(ordered_unique(members), key=jcs), "contract-parameter-inconsistent-instantiation")
        for member in members:
            member = validate_contract_object(member)
            reject(member.get("kind") == "UnionV1", "contract-parameter-inconsistent-instantiation")
            validate_row_expr(member)
    else:
        raise Diagnostic("contract-parameter-inconsistent-instantiation")


def validate_row_selector_scope(
    row: Any,
    *,
    type_parameter_kinds: dict[int, str],
    identity_binders: dict[int, dict[str, Any]],
    handler_contract_binders: set[int],
) -> None:
    """Resolve every selector in a decoded row against its lexical declarations."""

    row = validate_contract_object(row)
    kind = row.get("kind")
    if kind == "ClosedV1":
        for entry in validate_contract_list(row["entries"]):
            validate_effect_entry_selector(
                entry,
                type_parameter_kinds,
                identity_binders=identity_binders,
                handler_contract_binders=handler_contract_binders,
            )
    elif kind == "UnionV1":
        for member in validate_contract_list(row["members"]):
            validate_row_selector_scope(
                member,
                type_parameter_kinds=type_parameter_kinds,
                identity_binders=identity_binders,
                handler_contract_binders=handler_contract_binders,
            )


def validate_lexical_effect_selector_scope(
    value: Any,
    *,
    type_parameter_kinds: dict[int, str],
    identity_binders: dict[int, dict[str, Any]],
    handler_contract_binders: set[int],
    _root: bool = True,
) -> None:
    """Resolve every entry selector serialized in the current declaration scope."""

    if isinstance(value, list):
        for member in value:
            validate_lexical_effect_selector_scope(
                member,
                type_parameter_kinds=type_parameter_kinds,
                identity_binders=identity_binders,
                handler_contract_binders=handler_contract_binders,
                _root=False,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2" or (
        not _root and set(value) == HANDLER_CONTRACT_FIELDS
    ):
        return
    tag = value.get("kind")
    if tag == "ForAllIdentityTypeV2":
        binder = value.get("binder")
        nested_identities = dict(identity_binders)
        if isinstance(binder, dict) and isinstance(
            binder.get("identity_slot"), int
        ):
            nested_identities[binder["identity_slot"]] = binder
        validate_lexical_effect_selector_scope(
            value.get("body"),
            type_parameter_kinds=type_parameter_kinds,
            identity_binders=nested_identities,
            handler_contract_binders=handler_contract_binders,
            _root=False,
        )
        return
    if tag == "ExistsClockPackageTypeV2":
        binder = value.get("clock_binder")
        nested_identities = dict(identity_binders)
        if isinstance(binder, dict) and isinstance(
            binder.get("identity_slot"), int
        ):
            nested_identities[binder["identity_slot"]] = {
                "family": {
                    "arguments": [],
                    "kind": "NominalTypeV1",
                    "module": ["cire", "temporal"],
                    "name": "FrameClock",
                }
            }
        for member in (value.get("summary_binder"), value.get("body")):
            validate_lexical_effect_selector_scope(
                member,
                type_parameter_kinds=type_parameter_kinds,
                identity_binders=nested_identities,
                handler_contract_binders=handler_contract_binders,
                _root=False,
            )
        return
    if isinstance(tag, str) and tag in {
        "AnonV1", "NamedV1", "HandlerEntryParameterV1",
    }:
        validate_effect_entry_selector(
            value,
            type_parameter_kinds,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
        )
        return
    for member in value.values():
        validate_lexical_effect_selector_scope(
            member,
            type_parameter_kinds=type_parameter_kinds,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
        )


def validate_lexical_row_scope(
    value: Any,
    *,
    row_binders: dict[int, dict[str, Any]],
    _root: bool = True,
) -> None:
    """Resolve Row references without crossing an inline function declaration."""

    if isinstance(value, list):
        for member in value:
            validate_lexical_row_scope(
                member, row_binders=row_binders, _root=False,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2" or (
        not _root and set(value) == HANDLER_CONTRACT_FIELDS
    ):
        return
    if set(value) == {"namespace", "slot"} and value.get("namespace") == "Row":
        reject(
            value.get("slot") not in row_binders,
            "contract-projection-escapes-scope",
        )
        return
    for member in value.values():
        validate_lexical_row_scope(
            member, row_binders=row_binders, _root=False,
        )


def validate_lexical_slot_scope(
    value: Any,
    *,
    slot_scopes: dict[str, set[int]],
    _root: bool = True,
) -> None:
    """Close ordinary slot references at the current declaration boundary."""

    if isinstance(value, list):
        for member in value:
            validate_lexical_slot_scope(
                member, slot_scopes=slot_scopes, _root=False,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2":
        return
    tag = value.get("kind")
    if set(value) == HANDLER_CONTRACT_FIELDS:
        prompt_scope = slot_scopes.get("Prompt", set())
        reject(
            value.get("prompt_slot") not in prompt_scope,
            "contract-projection-escapes-scope",
        )
        for key, member in value.items():
            if key != "prompt_slot":
                validate_lexical_slot_scope(
                    member, slot_scopes=slot_scopes, _root=False,
                )
        return
    if tag == "WorldParameterV1" and set(value) == {
        "kind", "contract_slot",
    }:
        if "Contract" in slot_scopes:
            reject(
                value.get("contract_slot") not in slot_scopes["Contract"],
                "contract-projection-escapes-scope",
            )
        return
    if tag == "TypeParameterIndexV1" and set(value) == {"kind", "slot"}:
        if "Type" in slot_scopes:
            reject(
                value.get("slot") not in slot_scopes["Type"],
                "contract-projection-escapes-scope",
            )
        return
    if tag == "ForAllIdentityTypeV2":
        binder = value.get("binder")
        if isinstance(binder, dict):
            for member in (binder.get("family"), binder.get("owner")):
                validate_lexical_slot_scope(
                    member, slot_scopes=slot_scopes, _root=False,
                )
        nested = {key: set(slots) for key, slots in slot_scopes.items()}
        if isinstance(binder, dict):
            identity_slot = binder.get("identity_slot")
            if isinstance(identity_slot, int) and not isinstance(identity_slot, bool):
                nested.setdefault("Identity", set()).add(identity_slot)
            refinement = binder.get("clock_refinement")
            if isinstance(refinement, dict):
                clock_slot = refinement.get("clock_slot")
                if isinstance(clock_slot, int) and not isinstance(clock_slot, bool):
                    nested.setdefault("Clock", set()).add(clock_slot)
        validate_lexical_slot_scope(
            value.get("body"), slot_scopes=nested, _root=False,
        )
        return
    if tag == "ForAllOwnerTypeV2":
        nested = {key: set(slots) for key, slots in slot_scopes.items()}
        binder = value.get("binder")
        if isinstance(binder, dict):
            owner_slot = binder.get("owner_slot")
            if isinstance(owner_slot, int) and not isinstance(owner_slot, bool):
                nested.setdefault("Owner", set()).add(owner_slot)
        validate_lexical_slot_scope(
            value.get("body"), slot_scopes=nested, _root=False,
        )
        return
    if tag == "ExistsClockPackageTypeV2":
        binder = value.get("clock_binder")
        if isinstance(binder, dict):
            validate_lexical_slot_scope(
                binder.get("owner"), slot_scopes=slot_scopes, _root=False,
            )
        nested = {key: set(slots) for key, slots in slot_scopes.items()}
        if isinstance(binder, dict):
            identity_slot = binder.get("identity_slot")
            if isinstance(identity_slot, int) and not isinstance(identity_slot, bool):
                nested.setdefault("Identity", set()).add(identity_slot)
            refinement = binder.get("clock_refinement")
            if isinstance(refinement, dict):
                clock_slot = refinement.get("clock_slot")
                if isinstance(clock_slot, int) and not isinstance(clock_slot, bool):
                    nested.setdefault("Clock", set()).add(clock_slot)
        validate_lexical_slot_scope(
            value.get("summary_binder"), slot_scopes=nested, _root=False,
        )
        validate_lexical_slot_scope(
            value.get("body"), slot_scopes=nested, _root=False,
        )
        return
    if set(value) == {"namespace", "slot"}:
        namespace = value.get("namespace")
        if namespace in slot_scopes:
            reject(
                value.get("slot") not in slot_scopes[namespace],
                "contract-projection-escapes-scope",
            )
        return
    for member in value.values():
        validate_lexical_slot_scope(
            member, slot_scopes=slot_scopes, _root=False,
        )


def validate_transition(transition: dict[str, Any]) -> None:
    kind = transition.get("kind")
    if kind in {"BottomTransitionV1", "SameWorldV1"}:
        exact_fields(transition, {"kind"}, kind)
    elif kind == "NextWorldV1":
        exact_fields(transition, {"kind", "clock"}, kind)
        validate_slot_v1(transition["clock"], "Clock")
    elif kind == "SequenceTransitionV1":
        exact_fields(transition, {"kind", "steps"}, kind)
        reject(len(transition["steps"]) < 2, "contract-parameter-inconsistent-instantiation")
        for step in transition["steps"]:
            reject(step.get("kind") in {"SameWorldV1", "SequenceTransitionV1"}, "contract-parameter-inconsistent-instantiation")
            validate_transition(step)
    elif kind == "PathJoinTransitionV1":
        exact_fields(transition, {"kind", "paths"}, kind)
        reject(len(transition["paths"]) < 2, "contract-parameter-inconsistent-instantiation")
        for path in transition["paths"]:
            validate_transition(path)
    else:
        raise Diagnostic("contract-parameter-inconsistent-instantiation")


def validate_type_binder(binder: Any) -> None:
    binder = validate_contract_object(binder)
    exact_fields(binder, {"slot", "kind"}, "TypeBinderV1")
    validate_u32(binder["slot"], "TypeBinderV1 slot")
    reject(
        not isinstance(binder["kind"], str)
        or binder["kind"] not in {"Type", "Effect", "OwnerRegion"},
        "contract-component-kind-mismatch",
    )


def validate_type_constructor_v1(constructor: Any) -> None:
    constructor = validate_contract_object(constructor)
    kind = constructor.get("kind")
    if kind == "BuiltinConstructorV1":
        exact_fields(constructor, {"kind", "name"}, kind)
    elif kind == "NominalConstructorV1":
        exact_fields(constructor, {"kind", "module", "name"}, kind)
        reject(
            not isinstance(constructor["module"], list)
            or not all(isinstance(member, str) for member in constructor["module"]),
            "contract-component-kind-mismatch",
        )
    else:
        raise Diagnostic("contract-component-kind-mismatch")
    reject(not isinstance(constructor["name"], str), "contract-component-kind-mismatch")


def validate_type_v1(type_ref: Any) -> None:
    type_ref = validate_contract_object(type_ref)
    kind = type_ref.get("kind")
    schemas = {
        "BuiltinTypeV1": {"kind", "name"},
        "TypeParameterV1": {"kind", "slot"},
        "NominalTypeV1": {"kind", "module", "name", "arguments"},
        "ApplyTypeV1": {"kind", "constructor", "arguments"},
        "FunctionTypeV1": {"kind", "parameter", "result", "contract"},
        "CapabilityTypeV1": {"kind", "identity", "family"},
        "NextTypeV1": {"kind", "clock", "payload", "later_contract"},
        "OwnerTypeV1": {"kind", "owner"},
        "OwnerIndexedTypeV1": {"kind", "constructor", "owner", "payload"},
        "ResourceTypeV1": {"kind", "owner", "value", "cleanup_result"},
        "SignalTypeV1": {"kind", "clock", "payload"},
        "PlanTypeV1": {"kind", "payload"},
        "ResumeTypeV1": {
            "kind", "usage", "continuation", "argument", "answer",
            "live_provenance", "live_capture", "owner",
        },
        "HandlerTemplateTypeV1": {
            "kind", "family", "owner", "input", "answer", "residual_row",
            "contract", "policy",
        },
        "ForAllIdentityTypeV1": {"kind", "binder", "body"},
        "ForAllContractTypeV1": {"kind", "binder", "body"},
        "ExistsClockPackageTypeV1": {"kind", "clock_binder", "summary_binder", "body"},
        "ForAllOwnerTypeV1": {"kind", "binder", "body"},
    }
    reject(
        not isinstance(kind, str) or kind not in schemas,
        "contract-component-kind-mismatch",
    )
    exact_fields(type_ref, schemas[kind], kind)
    if kind == "BuiltinTypeV1":
        reject(type_ref["name"] not in {"Unit", "Never", "Bool", "Int", "String"}, "contract-component-kind-mismatch")
    elif kind == "TypeParameterV1":
        validate_u32(type_ref["slot"], "TypeParameterV1 slot")
    elif kind == "NominalTypeV1":
        reject(
            not isinstance(type_ref["module"], list)
            or not all(isinstance(member, str) for member in type_ref["module"])
            or not isinstance(type_ref["name"], str),
            "contract-component-kind-mismatch",
        )
        for argument in validate_contract_list(type_ref["arguments"]):
            validate_type_v1(argument)
    elif kind == "ApplyTypeV1":
        validate_type_constructor_v1(type_ref["constructor"])
        for argument in validate_contract_list(type_ref["arguments"]):
            validate_type_v1(argument)
    elif kind == "FunctionTypeV1":
        validate_type_v1(type_ref["parameter"])
        validate_type_v1(type_ref["result"])
        reject(not isinstance(type_ref["contract"], dict), "contract-component-kind-mismatch")
    elif kind == "CapabilityTypeV1":
        validate_slot_v1(type_ref["identity"], "Identity")
        validate_effect_family_ref(type_ref["family"])
    elif kind == "NextTypeV1":
        validate_slot_v1(type_ref["clock"], "Clock")
        validate_type_v1(type_ref["payload"])
        reject(not isinstance(type_ref["later_contract"], dict), "contract-component-kind-mismatch")
    elif kind in {"OwnerTypeV1", "OwnerIndexedTypeV1", "ResourceTypeV1"}:
        validate_slot_v1(type_ref["owner"], "Owner")
        for key in ("payload", "value", "cleanup_result"):
            if type_ref.get(key) is not None:
                validate_type_v1(type_ref[key])
    elif kind == "SignalTypeV1":
        validate_slot_v1(type_ref["clock"], "Clock")
        validate_type_v1(type_ref["payload"])
    elif kind == "PlanTypeV1":
        validate_type_v1(type_ref["payload"])
    elif kind == "ResumeTypeV1":
        reject(type_ref["usage"] not in {"Zero", "Once", "Many"}, "contract-component-kind-mismatch")
        reject(not isinstance(type_ref["continuation"], dict), "contract-component-kind-mismatch")
        validate_type_v1(type_ref["argument"])
        validate_type_v1(type_ref["answer"])
        validate_provenance_v1(type_ref["live_provenance"])
        validate_capture_v1(type_ref["live_capture"])
        validate_slot_v1(type_ref["owner"], "Owner")
    elif kind == "HandlerTemplateTypeV1":
        validate_effect_family_ref(type_ref["family"])
        for key in ("input", "answer"):
            validate_type_v1(type_ref[key])
        validate_slot_v1(type_ref["owner"], "Owner")
        validate_row_expr(type_ref["residual_row"])
        reject(not isinstance(type_ref["contract"], dict), "contract-component-kind-mismatch")
        validate_summary_normal_form(type_ref["policy"])
    elif kind in {"ForAllIdentityTypeV1", "ForAllContractTypeV1", "ForAllOwnerTypeV1"}:
        reject(not isinstance(type_ref["binder"], dict), "contract-component-kind-mismatch")
        validate_type_v1(type_ref["body"])
    elif kind == "ExistsClockPackageTypeV1":
        reject(
            not isinstance(type_ref["clock_binder"], dict)
            or not isinstance(type_ref["summary_binder"], dict),
            "contract-component-kind-mismatch",
        )
        validate_type_v1(type_ref["body"])


def validate_scoped_slot_v1(
    reference: Any,
    *,
    disposition_binder: dict[str, Any] | None = None,
    namespace: str | None = None,
) -> None:
    reference = validate_contract_object(reference)
    validate_slot_v1(reference, namespace)
    if reference["namespace"] == "SuffixLive":
        reject(
            disposition_binder is None or reference["slot"] != disposition_binder["slot"],
            "handler-disposition-escapes-scope",
        )


def validate_world_v1(world: Any) -> None:
    world = validate_contract_object(world)
    kind = world.get("kind")
    if kind == "EntryWorldV1":
        exact_fields(world, {"kind", "site_slot"}, kind)
        validate_u32(world["site_slot"], "EntryWorldV1 site_slot")
    elif kind == "WorldParameterV1":
        exact_fields(world, {"kind", "contract_slot"}, kind)
        validate_u32(world["contract_slot"], "WorldParameterV1 contract_slot")
    elif kind == "ApplyWorldTransitionV1":
        exact_fields(world, {"kind", "input", "transition"}, kind)
        validate_world_v1(world["input"])
        validate_transition(world["transition"])
    elif kind == "JoinWorldsV1":
        exact_fields(world, {"kind", "members"}, kind)
        for member in validate_contract_list(world["members"]):
            validate_world_v1(member)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_environment_binding_v1(
    binding: Any,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    binding = validate_contract_object(binding)
    exact_fields(binding, {"slot", "type", "provenance", "capture"}, "EnvironmentBindingV1")
    validate_scoped_slot_v1(binding["slot"], disposition_binder=disposition_binder)
    validate_type_v1(binding["type"])
    validate_provenance_v1(binding["provenance"], disposition_binder=disposition_binder)
    validate_capture_v1(binding["capture"], disposition_binder=disposition_binder)


def validate_provenance_v1(
    provenance: Any,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    provenance = validate_contract_object(provenance)
    kind = provenance.get("kind")
    if kind in {"BottomProvenanceV1", "StableV1"}:
        exact_fields(provenance, {"kind"}, kind)
    elif kind in {"ArgumentV1", "ArrayElementProvenanceV1"}:
        exact_fields(provenance, {"kind", "argument"}, kind)
        validate_scoped_slot_v1(provenance["argument"], disposition_binder=disposition_binder)
    elif kind in {"RegionV1", "OwnerV1", "GenerationBoundV1"}:
        exact_fields(provenance, {"kind", "owner"}, kind)
        validate_scoped_slot_v1(provenance["owner"], disposition_binder=disposition_binder, namespace="Owner")
    elif kind in {"CallbackV1", "OperationResultProvenanceV1"}:
        exact_fields(provenance, {"kind", "site_slot"}, kind)
        validate_u32(provenance["site_slot"], f"{kind} site_slot")
    elif kind == "EnvironmentV1":
        exact_fields(provenance, {"kind", "bindings"}, kind)
        for binding in validate_contract_list(provenance["bindings"]):
            validate_environment_binding_v1(binding, disposition_binder=disposition_binder)
    elif kind == "JoinProvenanceV1":
        exact_fields(provenance, {"kind", "members"}, kind)
        for member in validate_contract_list(provenance["members"]):
            validate_provenance_v1(member, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_capture_v1(
    capture: Any,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    capture = validate_contract_object(capture)
    kind = capture.get("kind")
    if kind in {"BottomCaptureV1", "NoCaptureV1"}:
        exact_fields(capture, {"kind"}, kind)
    elif kind == "CaptureSlotsV1":
        exact_fields(capture, {"kind", "slots"}, kind)
        for reference in validate_contract_list(capture["slots"]):
            validate_scoped_slot_v1(reference, disposition_binder=disposition_binder)
    elif kind in {"ArgumentCaptureV1", "ArrayElementCaptureV1"}:
        exact_fields(capture, {"kind", "argument"}, kind)
        validate_scoped_slot_v1(capture["argument"], disposition_binder=disposition_binder)
    elif kind == "OperationResultCaptureV1":
        exact_fields(capture, {"kind", "site_slot"}, kind)
        validate_u32(capture["site_slot"], "OperationResultCaptureV1 site_slot")
    elif kind == "UnionCaptureV1":
        exact_fields(capture, {"kind", "members"}, kind)
        for member in validate_contract_list(capture["members"]):
            validate_capture_v1(member, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_nominal_index_v1(index: Any) -> None:
    index = validate_contract_object(index)
    kind = index.get("kind")
    if kind == "NoNominalIndexV1":
        exact_fields(index, {"kind"}, kind)
    elif kind == "TypeParameterIndexV1":
        exact_fields(index, {"kind", "slot"}, kind)
        validate_u32(index["slot"], "TypeParameterIndexV1 slot")
    elif kind == "IdentityIndexV1":
        exact_fields(index, {"kind", "identity"}, kind)
        validate_slot_v1(index["identity"], "Identity")
    elif kind == "OwnerIndexV1":
        exact_fields(index, {"kind", "owner"}, kind)
        validate_slot_v1(index["owner"], "Owner")
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_result_transformer_v1(
    transformer: Any,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    transformer = validate_contract_object(transformer)
    kind = transformer.get("kind")
    if kind == "BottomResultV1":
        exact_fields(transformer, {"kind"}, kind)
    elif kind == "ParametricResultV1":
        exact_fields(transformer, {"kind", "provenance", "capture"}, kind)
        validate_provenance_v1(transformer["provenance"], disposition_binder=disposition_binder)
        validate_capture_v1(transformer["capture"], disposition_binder=disposition_binder)
    elif kind == "PathJoinResultV1":
        exact_fields(transformer, {"kind", "paths"}, kind)
        for path in validate_contract_list(transformer["paths"]):
            reject(not isinstance(path, dict) or path.get("kind") != "ParametricResultV1", "contract-component-kind-mismatch")
            validate_result_transformer_v1(path, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def compose_transition(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    steps: list[dict[str, Any]] = []
    for transition in (left, right):
        if transition.get("kind") == "SequenceTransitionV1":
            steps.extend(transition["steps"])
        elif transition.get("kind") != "SameWorldV1":
            steps.append(transition)
    if not steps:
        return {"kind": "SameWorldV1"}
    if len(steps) == 1:
        return copy.deepcopy(steps[0])
    return {"kind": "SequenceTransitionV1", "steps": copy.deepcopy(steps)}


def validate_return_ref(value: dict[str, Any], returns: ReturnScope) -> dict[str, Any]:
    exact_fields(value, {"kind", "return_slot"}, value.get("kind", "ReturnRefV2"))
    validate_u32(value["return_slot"], "return slot")
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


def validate_scoped_slot_v2(
    value: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    validate_slot_v2(value, returns)
    if value.get("kind") == "LegacySlotRefV2" and value["value"]["namespace"] == "SuffixLive":
        reject(
            disposition_binder is None
            or value["value"]["slot"] != disposition_binder["slot"],
            "handler-disposition-escapes-scope",
        )


def validate_contract_kind(
    kind: dict[str, Any],
    returns: ReturnScope,
    *,
    declaration_scope: DeclarationScope | None = None,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    kind = validate_contract_object(kind)
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
    for key in ("parameter_type", "result_type", "payload_type", "argument_type", "answer_type", "input_type"):
        if key in kind:
            validate_type_v2(
                kind[key], returns=returns,
                declaration_scope=declaration_scope,
                imports=imports,
                contract_binders=(
                    declaration_scope.contract_binders
                    if declaration_scope is not None
                    else None
                ),
                local_functions=local_functions,
            )
    if "family" in kind:
        family = validate_contract_object(kind["family"])
        if family.get("kind") == "LegacyTypeRefV2":
            family = family["value"]
        validate_effect_family_ref(
            family,
            declaration_scope.type_parameter_kinds
            if declaration_scope is not None
            else None,
        )
    if "clock" in kind:
        validate_slot_v1(kind["clock"], "Clock")
    if tag == "FunctionContractKindV2":
        validate_row_expr(kind["visible_row"])


def validate_contract_parameter(
    parameter: dict[str, Any],
    returns: ReturnScope,
    *,
    declaration_scope: DeclarationScope | None = None,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    exact_fields(parameter, {"slot", "kind"}, "ContractParameterV2")
    validate_u32(parameter["slot"], "ContractParameterV2 slot")
    validate_contract_kind(
        parameter["kind"], returns, declaration_scope=declaration_scope,
        imports=imports, local_functions=local_functions,
    )


def validate_contract_ref(
    reference: dict[str, Any],
    returns: ReturnScope,
    *,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    tag = reference.get("kind")
    if tag == "ImportedFunctionRefV2":
        exact_fields(reference, {"kind", "module", "name", "artifact_hash"}, tag)
        reject(
            not isinstance(reference["module"], list)
            or not reference["module"]
            or any(
                not isinstance(component, str) or not component
                for component in reference["module"]
            )
            or not isinstance(reference["name"], str)
            or not reference["name"],
            "contract-component-kind-mismatch",
        )
        reject(
            not isinstance(reference["artifact_hash"], str)
            or not reference["artifact_hash"],
            "contract-component-kind-mismatch",
        )
        reject(reference["artifact_hash"] not in imports, "contract-component-kind-mismatch")
        expected_export = imports.exports.get(reference["artifact_hash"])
        reject(
            expected_export != (tuple(reference["module"]), reference["name"]),
            "imported-function-export-mismatch",
        )
    elif tag == "LocalFunctionRefV2":
        exact_fields(reference, {"kind", "declaration_slot"}, tag)
        reject(
            not isinstance(reference["declaration_slot"], int)
            or isinstance(reference["declaration_slot"], bool)
            or reference["declaration_slot"] < 0
            or reference["declaration_slot"] > U32_MAX,
            "local-function-ref-unresolved",
        )
        reject(reference["declaration_slot"] not in local_functions, "local-function-ref-unresolved")
        target = local_functions[reference["declaration_slot"]]
        reject(
            target.get("artifact") != "FunctionContractV2"
            or target.get("declaration_kind", {}).get("kind") != "FunctionContractKindV2",
            "local-function-ref-unresolved",
        )
    elif tag == "ContractParameterRefV2":
        exact_fields(reference, {"kind", "parameter"}, tag)
        validate_contract_parameter(
            reference["parameter"], returns,
            declaration_scope=declaration_scope,
            imports=imports,
            local_functions=local_functions,
        )
        slot_number = reference["parameter"]["slot"]
        reject(slot_number not in contract_binders, "contract-projection-escapes-scope")
        reject(reference["parameter"]["kind"] != binder_kind(contract_binders[slot_number]), "contract-component-kind-mismatch")
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_later_contract(
    later: dict[str, Any],
    returns: ReturnScope,
    *,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    later = validate_contract_object(later)
    exact_fields(later, {"provenance", "capture", "semantic_summary", "required_phase"}, "LaterContractV2")
    validate_provenance(later["provenance"], returns)
    validate_capture(later["capture"], returns)
    validate_summary_normal_form(later["semantic_summary"])
    validate_phase_requirement(later["required_phase"])


def normalized_effect_family_v2(family: Any) -> dict[str, Any]:
    """Decode the V2 wrapper used around a concrete V1 Effect family."""

    family = validate_contract_object(family)
    if family.get("kind") == "LegacyTypeRefV2":
        exact_fields(family, {"kind", "value"}, "LegacyTypeRefV2")
        return validate_contract_object(family["value"])
    return family


def alpha_equal_v2(left: Any, right: Any) -> bool:
    """Compare V2 trees modulo every binder introduced inside a TypeRefV2."""

    counters: dict[str, int] = {}

    def extend(
        left_environment: dict[str, dict[int, int]],
        right_environment: dict[str, dict[int, int]],
        namespace: str,
        left_slot: int,
        right_slot: int,
    ) -> tuple[dict[str, dict[int, int]], dict[str, dict[int, int]]]:
        token = counters.get(namespace, 0)
        counters[namespace] = token + 1
        nested_left = {
            name: dict(bindings)
            for name, bindings in left_environment.items()
        }
        nested_right = {
            name: dict(bindings)
            for name, bindings in right_environment.items()
        }
        nested_left.setdefault(namespace, {})[left_slot] = token
        nested_right.setdefault(namespace, {})[right_slot] = token
        return nested_left, nested_right

    def resolved_slot(
        namespace: str,
        slot_number: Any,
        environment: dict[str, dict[int, int]],
    ) -> tuple[str, Any]:
        binding = environment.get(namespace, {}).get(slot_number)
        if binding is None:
            return "free", slot_number
        return "bound", binding

    def equivalent(
        left_value: Any,
        right_value: Any,
        left_environment: dict[str, dict[int, int]],
        right_environment: dict[str, dict[int, int]],
    ) -> bool:
        if type(left_value) is not type(right_value):
            return False
        if isinstance(left_value, list):
            return len(left_value) == len(right_value) and all(
                equivalent(
                    left_member,
                    right_member,
                    left_environment,
                    right_environment,
                )
                for left_member, right_member in zip(
                    left_value, right_value,
                )
            )
        if not isinstance(left_value, dict):
            return left_value == right_value
        if set(left_value) != set(right_value):
            return False

        if left_value.get("artifact") == "FunctionContractV2":
            binder_fields = {
                "parameter_binders", "type_binders", "row_binders",
                "contract_binders", "owner_binders", "clock_binders",
                "identity_binders", "prompt_binders",
            }
            left_binders = left_value.get("binders")
            right_binders = right_value.get("binders")
            if (
                not isinstance(left_binders, dict)
                or not isinstance(right_binders, dict)
                or set(left_binders) != binder_fields
                or set(right_binders) != binder_fields
            ):
                return False

            nested_left = left_environment
            nested_right = right_environment
            binder_specs = (
                ("parameter_binders", "slot", "Parameter"),
                ("type_binders", "slot", "Type"),
                ("row_binders", "slot", "Row"),
                ("contract_binders", "slot", "Contract"),
                ("owner_binders", "slot", "Owner"),
                ("clock_binders", "slot", "Clock"),
                ("identity_binders", "identity_slot", "Identity"),
                ("prompt_binders", "prompt_slot", "Prompt"),
            )
            for field, slot_field, namespace in binder_specs:
                left_entries = left_binders[field]
                right_entries = right_binders[field]
                if (
                    not isinstance(left_entries, list)
                    or not isinstance(right_entries, list)
                    or len(left_entries) != len(right_entries)
                ):
                    return False
                seen_left: set[int] = set()
                seen_right: set[int] = set()
                for left_entry, right_entry in zip(
                    left_entries, right_entries,
                ):
                    if (
                        not isinstance(left_entry, dict)
                        or not isinstance(right_entry, dict)
                        or set(left_entry) != set(right_entry)
                        or slot_field not in left_entry
                        or not isinstance(left_entry[slot_field], int)
                        or isinstance(left_entry[slot_field], bool)
                        or not isinstance(right_entry[slot_field], int)
                        or isinstance(right_entry[slot_field], bool)
                        or left_entry[slot_field] in seen_left
                        or right_entry[slot_field] in seen_right
                    ):
                        return False
                    seen_left.add(left_entry[slot_field])
                    seen_right.add(right_entry[slot_field])
                    nested_left, nested_right = extend(
                        nested_left,
                        nested_right,
                        namespace,
                        left_entry[slot_field],
                        right_entry[slot_field],
                    )

            left_closure = left_value.get("closure_environment")
            right_closure = right_value.get("closure_environment")
            if (
                not isinstance(left_closure, list)
                or not isinstance(right_closure, list)
                or len(left_closure) != len(right_closure)
            ):
                return False
            seen_left_closure: set[int] = set()
            seen_right_closure: set[int] = set()
            for left_binding, right_binding in zip(
                left_closure, right_closure,
            ):
                if (
                    not isinstance(left_binding, dict)
                    or not isinstance(right_binding, dict)
                    or set(left_binding) != set(right_binding)
                ):
                    return False
                left_slot = left_binding.get("slot")
                right_slot = right_binding.get("slot")
                if (
                    not isinstance(left_slot, dict)
                    or not isinstance(right_slot, dict)
                    or set(left_slot) != {"namespace", "slot"}
                    or set(right_slot) != {"namespace", "slot"}
                    or left_slot.get("namespace") != "ClosureCapture"
                    or right_slot.get("namespace") != "ClosureCapture"
                    or not isinstance(left_slot.get("slot"), int)
                    or isinstance(left_slot.get("slot"), bool)
                    or not isinstance(right_slot.get("slot"), int)
                    or isinstance(right_slot.get("slot"), bool)
                    or left_slot["slot"] in seen_left_closure
                    or right_slot["slot"] in seen_right_closure
                ):
                    return False
                seen_left_closure.add(left_slot["slot"])
                seen_right_closure.add(right_slot["slot"])
                nested_left, nested_right = extend(
                    nested_left,
                    nested_right,
                    "ClosureCapture",
                    left_slot["slot"],
                    right_slot["slot"],
                )

            for field, slot_field, _namespace in binder_specs:
                for left_entry, right_entry in zip(
                    left_binders[field], right_binders[field],
                ):
                    if not all(
                        equivalent(
                            left_entry[key],
                            right_entry[key],
                            nested_left,
                            nested_right,
                        )
                        for key in left_entry
                        if key != slot_field
                    ):
                        return False
            if not all(
                equivalent(
                    left_binding[key],
                    right_binding[key],
                    nested_left,
                    nested_right,
                )
                for left_binding, right_binding in zip(
                    left_closure, right_closure,
                )
                for key in left_binding
            ):
                return False
            return all(
                equivalent(
                    left_value[key],
                    right_value[key],
                    nested_left,
                    nested_right,
                )
                for key in left_value
                if key not in {"binders", "closure_environment"}
            )

        handler_contract_fields = {
            "handled_entry", "prompt_slot", "residual_row",
            "attributed_demand", "suspension", "semantic_summary",
            "required_phase", "handler_environment", "applications",
            "return_computation", "clause_computations",
        }
        if set(left_value) == handler_contract_fields:
            if resolved_slot(
                "Prompt", left_value["prompt_slot"], left_environment,
            ) != resolved_slot(
                "Prompt", right_value["prompt_slot"], right_environment,
            ):
                return False
            return all(
                equivalent(
                    left_value[key], right_value[key],
                    left_environment, right_environment,
                )
                for key in left_value
                if key != "prompt_slot"
            )

        park_contract_fields = {
            "owner_slot", "site_slot", "claim_cell_slot", "source",
            "completion_port", "claim", "disposition", "required_phase",
            "origin",
        }
        if set(left_value) == park_contract_fields:
            if resolved_slot(
                "Owner", left_value["owner_slot"], left_environment,
            ) != resolved_slot(
                "Owner", right_value["owner_slot"], right_environment,
            ):
                return False
            return all(
                equivalent(
                    left_value[key], right_value[key],
                    left_environment, right_environment,
                )
                for key in left_value
                if key != "owner_slot"
            )

        if set(left_value) == {"namespace", "slot"}:
            if left_value["namespace"] != right_value["namespace"]:
                return False
            namespace = left_value["namespace"]
            return resolved_slot(
                namespace, left_value["slot"], left_environment,
            ) == resolved_slot(
                namespace, right_value["slot"], right_environment,
            )

        tag = left_value.get("kind")
        if tag != right_value.get("kind"):
            return False
        if tag == "InstallationPromptV1" and set(left_value) == {
            "kind", "prompt_slot",
        }:
            return resolved_slot(
                "Prompt", left_value["prompt_slot"], left_environment,
            ) == resolved_slot(
                "Prompt", right_value["prompt_slot"], right_environment,
            )
        if isinstance(tag, str) and tag in {
            "TypeParameterV1", "TypeParameterV2",
        }:
            return resolved_slot(
                "Type", left_value.get("slot"), left_environment,
            ) == resolved_slot(
                "Type", right_value.get("slot"), right_environment,
            )
        if tag == "TypeParameterIndexV1" and set(left_value) == {
            "kind", "slot",
        }:
            return resolved_slot(
                "Type", left_value["slot"], left_environment,
            ) == resolved_slot(
                "Type", right_value["slot"], right_environment,
            )
        if tag == "WorldParameterV1" and set(left_value) == {
            "kind", "contract_slot",
        }:
            return resolved_slot(
                "Contract", left_value["contract_slot"], left_environment,
            ) == resolved_slot(
                "Contract", right_value["contract_slot"], right_environment,
            )
        if tag == "OwnerBoundV1" and set(left_value) == {
            "kind", "park_site_slot", "owner_slot", "grade", "origin",
        }:
            if resolved_slot(
                "Owner", left_value["owner_slot"], left_environment,
            ) != resolved_slot(
                "Owner", right_value["owner_slot"], right_environment,
            ):
                return False
            return all(
                equivalent(
                    left_value[key], right_value[key],
                    left_environment, right_environment,
                )
                for key in left_value
                if key != "owner_slot"
            )
        if tag == "HandlerEntryParameterV1":
            return resolved_slot(
                "Contract",
                left_value.get("contract_slot"),
                left_environment,
            ) == resolved_slot(
                "Contract",
                right_value.get("contract_slot"),
                right_environment,
            )
        if (
            set(left_value) == {"slot", "kind"}
            and isinstance(left_value.get("kind"), dict)
        ):
            return resolved_slot(
                "Contract", left_value["slot"], left_environment,
            ) == resolved_slot(
                "Contract", right_value["slot"], right_environment,
            ) and equivalent(
                left_value["kind"], right_value["kind"],
                left_environment, right_environment,
            )

        if tag == "ForAllOwnerTypeV2":
            left_binder = left_value.get("binder", {})
            right_binder = right_value.get("binder", {})
            if set(left_binder) != {"owner_slot"} or set(
                right_binder
            ) != {"owner_slot"}:
                return False
            nested_left, nested_right = extend(
                left_environment,
                right_environment,
                "Owner",
                left_binder["owner_slot"],
                right_binder["owner_slot"],
            )
            return equivalent(
                left_value["body"], right_value["body"],
                nested_left, nested_right,
            )

        if tag == "ForAllContractTypeV2":
            left_binder = left_value.get("binder", {})
            right_binder = right_value.get("binder", {})
            if set(left_binder) != {"contract_slot", "kind"} or set(
                right_binder
            ) != {"contract_slot", "kind"}:
                return False
            if not equivalent(
                left_binder["kind"], right_binder["kind"],
                left_environment, right_environment,
            ):
                return False
            nested_left, nested_right = extend(
                left_environment,
                right_environment,
                "Contract",
                left_binder["contract_slot"],
                right_binder["contract_slot"],
            )
            return equivalent(
                left_value["body"], right_value["body"],
                nested_left, nested_right,
            )

        if tag == "ForAllIdentityTypeV2":
            left_binder = left_value.get("binder", {})
            right_binder = right_value.get("binder", {})
            binder_fields = {
                "identity_slot", "clock_refinement", "family", "owner",
            }
            if set(left_binder) != binder_fields or set(
                right_binder
            ) != binder_fields:
                return False
            if not equivalent(
                left_binder["family"], right_binder["family"],
                left_environment, right_environment,
            ) or not equivalent(
                left_binder["owner"], right_binder["owner"],
                left_environment, right_environment,
            ):
                return False
            nested_left, nested_right = extend(
                left_environment,
                right_environment,
                "Identity",
                left_binder["identity_slot"],
                right_binder["identity_slot"],
            )
            left_refinement = left_binder["clock_refinement"]
            right_refinement = right_binder["clock_refinement"]
            if (left_refinement is None) != (right_refinement is None):
                return False
            if left_refinement is not None:
                if set(left_refinement) != {"clock_slot", "identity"} or set(
                    right_refinement
                ) != {"clock_slot", "identity"}:
                    return False
                nested_left, nested_right = extend(
                    nested_left,
                    nested_right,
                    "Clock",
                    left_refinement["clock_slot"],
                    right_refinement["clock_slot"],
                )
                if not equivalent(
                    left_refinement["identity"],
                    right_refinement["identity"],
                    nested_left,
                    nested_right,
                ):
                    return False
            return equivalent(
                left_value["body"], right_value["body"],
                nested_left, nested_right,
            )

        if tag == "ExistsClockPackageTypeV2":
            left_clock = left_value.get("clock_binder", {})
            right_clock = right_value.get("clock_binder", {})
            clock_fields = {
                "identity_slot", "clock_refinement", "family_witness",
                "owner",
            }
            if set(left_clock) != clock_fields or set(
                right_clock
            ) != clock_fields:
                return False
            if not equivalent(
                left_clock["family_witness"],
                right_clock["family_witness"],
                left_environment,
                right_environment,
            ) or not equivalent(
                left_clock["owner"], right_clock["owner"],
                left_environment, right_environment,
            ):
                return False
            nested_left, nested_right = extend(
                left_environment,
                right_environment,
                "Identity",
                left_clock["identity_slot"],
                right_clock["identity_slot"],
            )
            left_refinement = left_clock.get("clock_refinement", {})
            right_refinement = right_clock.get("clock_refinement", {})
            if set(left_refinement) != {"clock_slot", "identity"} or set(
                right_refinement
            ) != {"clock_slot", "identity"}:
                return False
            nested_left, nested_right = extend(
                nested_left,
                nested_right,
                "Clock",
                left_refinement["clock_slot"],
                right_refinement["clock_slot"],
            )
            if not equivalent(
                left_refinement["identity"],
                right_refinement["identity"],
                nested_left,
                nested_right,
            ):
                return False
            left_summary = left_value.get("summary_binder", {})
            right_summary = right_value.get("summary_binder", {})
            if set(left_summary) != {"contract_slot", "kind"} or set(
                right_summary
            ) != {"contract_slot", "kind"}:
                return False
            if not equivalent(
                left_summary["kind"], right_summary["kind"],
                nested_left, nested_right,
            ):
                return False
            nested_left, nested_right = extend(
                nested_left,
                nested_right,
                "Contract",
                left_summary["contract_slot"],
                right_summary["contract_slot"],
            )
            return equivalent(
                left_value["body"], right_value["body"],
                nested_left, nested_right,
            )

        signature_fields = {
            "type_binders", "parameters", "result", "mode", "transition",
            "suspension", "result_transformer", "required_phase",
            "obligation_ids", "secondary_sites",
        }
        if signature_fields <= set(left_value):
            left_binders = left_value["type_binders"]
            right_binders = right_value["type_binders"]
            if len(left_binders) != len(right_binders):
                return False
            nested_left = left_environment
            nested_right = right_environment
            for left_binder, right_binder in zip(
                left_binders, right_binders,
            ):
                if (
                    set(left_binder) != {"slot", "kind"}
                    or set(right_binder) != {"slot", "kind"}
                    or left_binder["kind"] != right_binder["kind"]
                ):
                    return False
                nested_left, nested_right = extend(
                    nested_left,
                    nested_right,
                    "Type",
                    left_binder["slot"],
                    right_binder["slot"],
                )
            return all(
                equivalent(
                    left_value[key], right_value[key],
                    nested_left, nested_right,
                )
                for key in left_value
                if key != "type_binders"
            )

        return all(
            equivalent(
                left_value[key], right_value[key],
                left_environment, right_environment,
            )
            for key in left_value
        )

    return equivalent(left, right, {}, {})


def validate_scoped_declaration_slot(
    reference: Any,
    namespace: str,
    bindings: dict[int, dict[str, Any]],
    *,
    enforce: bool = True,
) -> dict[str, Any]:
    """Decode an ordinary declaration reference and resolve its lexical slot."""

    reference = validate_contract_object(reference)
    validate_slot_v1(reference, namespace)
    if enforce:
        reject(
            reference["slot"] not in bindings,
            "contract-projection-escapes-scope",
        )
    return reference


def validate_quantified_contract_binder_v2(
    binder: Any,
    returns: ReturnScope,
    declaration_scope: DeclarationScope,
    *,
    imports: ImportScope,
    local_functions: LocalFunctionScope,
) -> dict[str, Any]:
    """Decode one V2 Contract binder in the scope preceding its body."""

    binder = validate_contract_object(binder)
    exact_fields(binder, {"contract_slot", "kind"}, "QuantifiedContractBinderV2")
    validate_u32(binder["contract_slot"], "QuantifiedContractBinderV2 contract_slot")
    kind = validate_contract_object(binder["kind"])
    reject(
        kind.get("kind")
        not in {
            "FunctionContractKindV2",
            "LaterContractKindV2",
            "ClockPackageSummaryKindV2",
        },
        "contract-component-kind-mismatch",
    )
    validate_contract_kind(
        kind, returns, declaration_scope=declaration_scope,
        imports=imports, local_functions=local_functions,
    )
    if "clock" in kind:
        validate_scoped_declaration_slot(
            kind["clock"], "Clock", declaration_scope.clock_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
    if "visible_row" in kind:
        validate_row_selector_scope(
            kind["visible_row"],
            type_parameter_kinds=declaration_scope.type_parameter_kinds,
            identity_binders=declaration_scope.identity_binders,
            handler_contract_binders=(
                declaration_scope.handler_contract_binders
            ),
        )
        validate_lexical_row_scope(
            kind["visible_row"], row_binders=declaration_scope.row_binders,
        )
    return binder


def validate_quantified_identity_binder_v2(
    binder: Any,
    declaration_scope: DeclarationScope,
) -> tuple[dict[str, Any], dict[int, dict[str, Any]]]:
    """Decode an Identity binder and its optional paired Clock view."""

    binder = validate_contract_object(binder)
    exact_fields(
        binder,
        {"identity_slot", "clock_refinement", "family", "owner"},
        "QuantifiedIdentityBinderV2",
    )
    validate_u32(binder["identity_slot"], "quantified Identity slot")
    validate_scoped_declaration_slot(
        binder["owner"], "Owner", declaration_scope.owner_binders,
        enforce=declaration_scope.enforce_ordinary_slots,
    )
    family = normalized_effect_family_v2(binder["family"])
    validate_effect_family_ref(
        family, declaration_scope.type_parameter_kinds,
    )
    is_frame_clock = family == {
        "arguments": [],
        "kind": "NominalTypeV1",
        "module": ["cire", "temporal"],
        "name": "FrameClock",
    }
    refinement = binder["clock_refinement"]
    reject(
        (refinement is None) == is_frame_clock,
        "clock-package-family-not-clock-indexing",
    )
    clocks = dict(declaration_scope.clock_binders)
    if refinement is not None:
        refinement = validate_contract_object(refinement)
        exact_fields(
            refinement,
            {"clock_slot", "identity"},
            "QuantifiedClockRefinementV1",
        )
        validate_u32(refinement["clock_slot"], "quantified Clock slot")
        reject(
            refinement["identity"]
            != slot("Identity", binder["identity_slot"]),
            "contract-component-kind-mismatch",
        )
        clocks[refinement["clock_slot"]] = {
            "identity": copy.deepcopy(refinement["identity"]),
            "owner": copy.deepcopy(binder["owner"]),
            "slot": refinement["clock_slot"],
        }
    return binder, clocks


def validate_type_v2(
    type_ref: Any,
    *,
    returns: ReturnScope | None = None,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    declaration_scope: DeclarationScope | None = None,
    defer_function_contract_shape: bool = False,
) -> None:
    returns = returns or {}
    applications = applications or {}
    imports = imports or ImportScope()
    if contract_binders is None:
        contract_binders = (
            declaration_scope.contract_binders
            if declaration_scope is not None
            else {}
        )
    local_functions = local_functions or {}
    declaration_scope = declaration_scope or DeclarationScope(
        type_parameter_kinds={},
        row_binders={},
        contract_binders=contract_binders,
        identity_binders={},
        handler_contract_binders=set(),
        owner_binders={},
        clock_binders={},
        parameter_binders=set(),
        closure_capture_binders=set(),
    )
    type_ref = validate_contract_object(type_ref)
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
    reject(
        not isinstance(kind, str) or kind not in schemas,
        "contract-component-kind-mismatch",
    )
    exact_fields(type_ref, schemas[kind], kind)
    if kind == "LegacyTypeRefV2":
        validate_type_v1(type_ref["value"])
        reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(type_ref["value"])), "unsupported-contract-schema-version")
    elif kind == "TypeParameterV2":
        validate_u32(type_ref["slot"], "TypeParameterV2 slot")
    elif kind in {"NominalTypeV2", "ApplyTypeV2"}:
        for argument in type_ref["arguments"]:
            validate_type_v2(argument, returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    elif kind == "FunctionTypeV2":
        validate_type_v2(type_ref["parameter"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        validate_type_v2(type_ref["result"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        contract = validate_contract_object(type_ref["contract"])
        if contract.get("artifact") == "FunctionContractV2":
            validate_function_contract(contract, imports=imports, local_functions=local_functions)
            resolved_kind = contract["declaration_kind"]
            check_shape = True
        elif isinstance(contract.get("kind"), dict) and isinstance(contract.get("slot"), int):
            validate_contract_parameter(
                contract, returns, declaration_scope=declaration_scope,
                imports=imports, local_functions=local_functions,
            )
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
                declaration_scope=declaration_scope,
            )
            resolved_kind, _ = resolve_contract_target(contract, imports, contract_binders, local_functions)
            # Only an AppliedContractV2 callee may defer this comparison until
            # its per-use substitution has been decoded. Standalone function
            # types must agree with the referenced declaration immediately.
            check_shape = not defer_function_contract_shape
        reject(resolved_kind is None or resolved_kind.get("kind") != "FunctionContractKindV2", "contract-component-kind-mismatch")
        reject(check_shape and (
            type_ref["parameter"] != resolved_kind["parameter_type"]
            or type_ref["result"] != resolved_kind["result_type"]),
            "contract-component-kind-mismatch",
        )
    elif kind == "CapabilityTypeV2":
        validate_slot_v1(type_ref["identity"], "Identity")
        family = normalized_effect_family_v2(type_ref["family"])
        validate_effect_family_ref(
            family, declaration_scope.type_parameter_kinds,
        )
        identity_slot = type_ref["identity"]["slot"]
        reject(
            identity_slot not in declaration_scope.identity_binders,
            "contract-projection-escapes-scope",
        )
        reject(
            normalized_effect_family_v2(
                declaration_scope.identity_binders[identity_slot]["family"]
            )
            != family,
            "contract-component-kind-mismatch",
        )
    elif kind == "NextTypeV2":
        validate_scoped_declaration_slot(
            type_ref["clock"], "Clock", declaration_scope.clock_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
        validate_type_v2(type_ref["payload"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        later = validate_contract_object(type_ref["later_contract"])
        if isinstance(later.get("kind"), dict):
            validate_contract_parameter(
                later, returns, declaration_scope=declaration_scope,
                imports=imports, local_functions=local_functions,
            )
            reject(later["slot"] not in contract_binders, "contract-projection-escapes-scope")
            reject(later["kind"] != binder_kind(contract_binders[later["slot"]]), "contract-component-kind-mismatch")
        else:
            validate_later_contract(
                later, returns, declaration_scope=declaration_scope,
            )
    elif kind in {"OwnerTypeV2", "OwnerIndexedTypeV2", "ResourceTypeV2", "PackedNextTypeV2"}:
        validate_scoped_declaration_slot(
            type_ref["owner"], "Owner", declaration_scope.owner_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
        for key in ("payload", "value", "cleanup_result"):
            if type_ref.get(key) is not None:
                validate_type_v2(type_ref[key], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        if kind == "OwnerIndexedTypeV2":
            no_payload = type_ref["constructor"] in {"CommitTicket", "CommitGate"}
            require((type_ref["payload"] is None) == no_payload, "OwnerIndexedTypeV2 payload")
    elif kind == "SignalTypeV2":
        validate_scoped_declaration_slot(
            type_ref["clock"], "Clock", declaration_scope.clock_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
        validate_type_v2(type_ref["payload"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    elif kind == "PlanTypeV2":
        validate_type_v2(type_ref["payload"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    elif kind == "ResumeTypeRefV2":
        validate_resume(type_ref["value"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    elif kind == "HandlerTemplateTypeV2":
        family = validate_contract_object(type_ref["family"])
        if family.get("kind") == "LegacyTypeRefV2":
            family = family["value"]
        validate_effect_family_ref(
            family, declaration_scope.type_parameter_kinds,
        )
        for key in ("input", "answer"):
            validate_type_v2(type_ref[key], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        validate_scoped_declaration_slot(
            type_ref["owner"], "Owner", declaration_scope.owner_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
        validate_row_expr(type_ref["residual_row"])
        validate_row_selector_scope(
            type_ref["residual_row"],
            type_parameter_kinds=declaration_scope.type_parameter_kinds,
            identity_binders=declaration_scope.identity_binders,
            handler_contract_binders=declaration_scope.handler_contract_binders,
        )
        validate_lexical_row_scope(
            type_ref["residual_row"],
            row_binders=declaration_scope.row_binders,
        )
        contract = type_ref["contract"]
        if isinstance(contract.get("kind"), dict):
            validate_contract_parameter(
                contract, returns, declaration_scope=declaration_scope,
                imports=imports, local_functions=local_functions,
            )
            contract_slot = contract["slot"]
            reject(
                contract_slot
                not in declaration_scope.handler_contract_binders,
                "contract-projection-escapes-scope",
            )
            resolved_handler_kind = handler_binder_kind(
                declaration_scope.contract_binders[contract_slot]
            )
            reject(
                contract["kind"] != resolved_handler_kind,
                "contract-component-kind-mismatch",
            )
        else:
            validate_handler_contract(
                contract,
                imports=imports,
                local_functions=local_functions,
                type_parameter_kinds=declaration_scope.type_parameter_kinds,
                row_binders=declaration_scope.row_binders,
                contract_binders=declaration_scope.contract_binders,
                identity_binders=declaration_scope.identity_binders,
                handler_contract_binders=declaration_scope.handler_contract_binders,
                owner_binders=declaration_scope.owner_binders,
                clock_binders=declaration_scope.clock_binders,
                prompt_binders=declaration_scope.prompt_binders,
                parameter_binders=declaration_scope.parameter_binders,
                closure_capture_binders=(
                    declaration_scope.closure_capture_binders
                ),
            )
    elif kind == "ForAllIdentityTypeV2":
        binder, clocks = validate_quantified_identity_binder_v2(
            type_ref["binder"], declaration_scope,
        )
        identities = dict(declaration_scope.identity_binders)
        identities[binder["identity_slot"]] = binder
        body_scope = declaration_scope.nested(
            identity_binders=identities, clock_binders=clocks,
        )
        validate_type_v2(
            type_ref["body"], returns=returns, applications=applications,
            imports=imports, contract_binders=contract_binders,
            local_functions=local_functions, declaration_scope=body_scope,
        )
    elif kind == "ForAllContractTypeV2":
        binder = validate_quantified_contract_binder_v2(
            type_ref["binder"], returns, declaration_scope,
            imports=imports, local_functions=local_functions,
        )
        nested_contracts = dict(declaration_scope.contract_binders)
        nested_contracts[binder["contract_slot"]] = binder
        body_scope = declaration_scope.nested(
            contract_binders=nested_contracts,
        )
        validate_type_v2(
            type_ref["body"], returns=returns, applications=applications,
            imports=imports, contract_binders=nested_contracts,
            local_functions=local_functions, declaration_scope=body_scope,
        )
    elif kind == "ForAllOwnerTypeV2":
        binder = validate_contract_object(type_ref["binder"])
        exact_fields(binder, {"owner_slot"}, "QuantifiedOwnerBinderV1")
        validate_u32(binder["owner_slot"], "quantified Owner slot")
        owners = dict(declaration_scope.owner_binders)
        owners[binder["owner_slot"]] = binder
        body_scope = declaration_scope.nested(owner_binders=owners)
        validate_type_v2(
            type_ref["body"], returns=returns, applications=applications,
            imports=imports, contract_binders=contract_binders,
            local_functions=local_functions, declaration_scope=body_scope,
        )
    elif kind == "ExistsClockPackageTypeV2":
        clock_binder = validate_contract_object(type_ref["clock_binder"])
        exact_fields(
            clock_binder,
            {"identity_slot", "clock_refinement", "family_witness", "owner"},
            "QuantifiedClockBinderV2",
        )
        validate_u32(clock_binder["identity_slot"], "quantified Identity slot")
        validate_scoped_declaration_slot(
            clock_binder["owner"], "Owner", declaration_scope.owner_binders,
            enforce=declaration_scope.enforce_ordinary_slots,
        )
        reject(
            clock_binder["family_witness"]
            != {
                "kind": "CanonicalFrameClockV2",
                "module": ["cire", "temporal"],
                "name": "FrameClock",
                "sealed_origin": "cire.temporal:FrameClock",
            },
            "clock-package-family-not-clock-indexing",
        )
        refinement = validate_contract_object(
            clock_binder["clock_refinement"]
        )
        exact_fields(
            refinement,
            {"clock_slot", "identity"},
            "QuantifiedClockRefinementV1",
        )
        validate_u32(refinement["clock_slot"], "quantified Clock slot")
        identity_ref = slot("Identity", clock_binder["identity_slot"])
        reject(
            refinement["identity"] != identity_ref,
            "contract-component-kind-mismatch",
        )
        identities = dict(declaration_scope.identity_binders)
        identities[clock_binder["identity_slot"]] = {
            "identity_slot": clock_binder["identity_slot"],
            "family": {
                "arguments": [],
                "kind": "NominalTypeV1",
                "module": ["cire", "temporal"],
                "name": "FrameClock",
            },
            "owner": copy.deepcopy(clock_binder["owner"]),
            "binder": "QuantifiedClockV2",
        }
        clocks = dict(declaration_scope.clock_binders)
        clocks[refinement["clock_slot"]] = {
            "identity": identity_ref,
            "owner": copy.deepcopy(clock_binder["owner"]),
            "slot": refinement["clock_slot"],
        }
        clock_scope = declaration_scope.nested(
            identity_binders=identities, clock_binders=clocks,
        )
        summary_binder = validate_quantified_contract_binder_v2(
            type_ref["summary_binder"], returns, clock_scope,
            imports=imports, local_functions=local_functions,
        )
        summary_kind = summary_binder["kind"]
        reject(
            summary_kind.get("kind") != "ClockPackageSummaryKindV2"
            or summary_kind.get("clock")
            != slot("Clock", refinement["clock_slot"]),
            "contract-component-kind-mismatch",
        )
        contracts = dict(clock_scope.contract_binders)
        contracts[summary_binder["contract_slot"]] = summary_binder
        body_scope = clock_scope.nested(contract_binders=contracts)
        validate_type_v2(
            type_ref["body"], returns=returns, applications=applications,
            imports=imports, contract_binders=contracts,
            local_functions=local_functions, declaration_scope=body_scope,
        )
        reject(
            not alpha_equal_v2(
                type_ref["body"], summary_kind["payload_type"],
            ),
            "contract-component-kind-mismatch",
        )


def validate_world(world: dict[str, Any], returns: ReturnScope) -> None:
    world = validate_contract_object(world)
    kind = world.get("kind")
    if kind == "LegacyWorldExprV2":
        exact_fields(world, {"kind", "value"}, kind)
        validate_world_v1(world["value"])
    elif kind == "ReturnWorldV2":
        validate_return_ref(world, returns)
    elif kind == "ApplicationEntryWorldV2":
        exact_fields(world, {"kind", "application_slot"}, kind)
        validate_u32(world["application_slot"], "ApplicationEntryWorldV2 application_slot")
    elif kind == "ApplyWorldTransitionV2":
        exact_fields(world, {"kind", "input", "transition"}, kind)
        validate_world(world["input"], returns)
        validate_transition(world["transition"])
    elif kind == "JoinWorldsV2":
        exact_fields(world, {"kind", "members"}, kind)
        for member in world["members"]:
            validate_world(member, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_nominal_index(index: dict[str, Any], returns: ReturnScope) -> None:
    index = validate_contract_object(index)
    if index.get("kind") == "LegacyNominalIndexExprV2":
        exact_fields(index, {"kind", "value"}, "LegacyNominalIndexExprV2")
        validate_nominal_index_v1(index["value"])
    elif index.get("kind") == "ReturnNominalIndexV2":
        validate_return_ref(index, returns)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_provenance(
    provenance: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    provenance = validate_contract_object(provenance)
    kind = provenance.get("kind")
    if kind == "LegacyProvenanceExprV2":
        exact_fields(provenance, {"kind", "value"}, kind)
        validate_provenance_v1(provenance["value"], disposition_binder=disposition_binder)
    elif kind == "ReturnProvenanceV2":
        validate_return_ref(provenance, returns)
    elif kind == "EnvironmentV2":
        exact_fields(provenance, {"kind", "bindings"}, kind)
        for binding in provenance["bindings"]:
            validate_environment_binding(
                binding, returns, disposition_binder=disposition_binder,
            )
    elif kind == "JoinProvenanceV2":
        exact_fields(provenance, {"kind", "members"}, kind)
        for member in provenance["members"]:
            validate_provenance(member, returns, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_capture(
    capture: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    capture = validate_contract_object(capture)
    kind = capture.get("kind")
    if kind == "LegacyCaptureExprV2":
        exact_fields(capture, {"kind", "value"}, kind)
        validate_capture_v1(capture["value"], disposition_binder=disposition_binder)
    elif kind == "ReturnCaptureV2":
        validate_return_ref(capture, returns)
    elif kind == "UnionCaptureV2":
        exact_fields(capture, {"kind", "members"}, kind)
        for member in capture["members"]:
            validate_capture(member, returns, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_usage(
    usage: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    usage = validate_contract_object(usage)
    kind = usage.get("kind")
    if kind == "LegacyUsageExprV2":
        exact_fields(usage, {"kind", "value"}, kind)
        value = validate_contract_object(usage["value"])
        exact_fields(value, {"slot", "kind"}, "UsageV1")
        validate_slot_v1(value["slot"])
        reject(value["kind"] not in {"Once", "Many"}, "contract-component-kind-mismatch")
        usage_slot = value["slot"]
        if usage_slot["namespace"] == "SuffixLive":
            reject(
                disposition_binder is None or usage_slot["slot"] != disposition_binder["slot"],
                "handler-disposition-escapes-scope",
            )
    elif kind == "ReturnUsageV2":
        binder = validate_return_ref(usage, returns)
        reject(
            binder["type"].get("kind") != "ResumeTypeRefV2"
            or binder.get("usage") is None,
            "contract-component-kind-mismatch",
        )
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def usage_map_key(usage: dict[str, Any]) -> tuple[str, int]:
    """Return the authority key of one already-validated nonzero usage entry."""

    if usage["kind"] == "LegacyUsageExprV2":
        reference = usage["value"]["slot"]
        return reference["namespace"], reference["slot"]
    return "Return", usage["return_slot"]


def suffix_projection_key(reference: dict[str, Any]) -> tuple[str, int]:
    """Normalize a V1/V2 live reference to its namespace-qualified key."""

    if reference.get("kind") == "LegacySlotRefV2":
        reference = reference.get("value", {})
    elif reference.get("kind") == "ReturnSlotRefV2":
        return "Return", reference["return_slot"]
    reject(
        set(reference) != {"namespace", "slot"},
        "contract-component-kind-mismatch",
    )
    return reference["namespace"], reference["slot"]


SUFFIX_FIELDS = {
    "answer_type", "applications", "computation", "cleanup", "live_bindings",
}
LIVE_TUPLE_FIELDS = ("type", "provenance", "capture", "usage")


def value_projection(
    *,
    type_ref: dict[str, Any],
    provenance: dict[str, Any],
    capture: dict[str, Any],
    usage: dict[str, Any] | None,
) -> dict[str, Any]:
    """Return the exact serialized part of one deterministic live tuple."""

    return {
        "type": copy.deepcopy(type_ref),
        "provenance": copy.deepcopy(provenance),
        "capture": copy.deepcopy(capture),
        "usage": copy.deepcopy(usage),
    }


def authority_projection(
    type_ref: dict[str, Any], reference: dict[str, Any],
) -> dict[str, Any] | None:
    """Materialize the canonical nonzero usage projection of an authority."""

    grade = authority_usage_grade(type_ref)
    if grade in {None, "Zero"}:
        return None
    return {
        "kind": "LegacyUsageExprV2",
        "value": {"slot": copy.deepcopy(reference), "kind": grade},
    }


def return_value_projection(binder: dict[str, Any]) -> dict[str, Any]:
    number = binder["slot"]
    return value_projection(
        type_ref=binder["type"],
        provenance={"kind": "ReturnProvenanceV2", "return_slot": number},
        capture={"kind": "ReturnCaptureV2", "return_slot": number},
        usage={"kind": "ReturnUsageV2", "return_slot": number},
    )


def suffix_live_projection(
    suffix: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    value_bindings: dict[tuple[str, int], dict[str, Any]] | None = None,
) -> tuple[dict[tuple[str, int], dict[str, Any] | None], set[tuple[str, int]]]:
    """Derive lexical free support and every resolvable full live tuple.

    A nested PathBind return is bound only in its continuation. Nested suffixes
    are deliberately skipped here and validated as independent projections by
    the root traversal. InvokeV2 adds the complete actual summaries from the
    referenced suffix application ledger.
    """

    outer_returns = returns or {}
    ambient = value_bindings or {}
    projected: dict[tuple[str, int], dict[str, Any] | None] = {}
    unresolved: set[tuple[str, int]] = set()
    invoked: set[int] = set()

    def resolved_projection(key: tuple[str, int]) -> dict[str, Any] | None:
        if key[0] == "Return" and key[1] in outer_returns:
            return return_value_projection(outer_returns[key[1]])
        return copy.deepcopy(ambient.get(key))

    def remember(
        key: tuple[str, int],
        *,
        summary: dict[str, Any] | None = None,
    ) -> None:
        expected = resolved_projection(key)
        from_summary = None
        if summary is not None:
            from_summary = value_projection(
                type_ref=summary["type"],
                provenance=summary["provenance"],
                capture=summary["capture"],
                usage=summary["usage"],
            )
            reject(
                expected is not None and from_summary != expected,
                "contract-component-kind-mismatch",
            )
        candidate = expected if expected is not None else from_summary
        if key in projected:
            reject(
                candidate is not None
                and projected[key] is not None
                and candidate != projected[key],
                "contract-component-kind-mismatch",
            )
            if projected[key] is None and candidate is not None:
                projected[key] = candidate
                unresolved.discard(key)
            return
        projected[key] = candidate
        if candidate is None:
            unresolved.add(key)

    def collect_expression(
        value: Any,
        bound_returns: set[int],
        *,
        summary: dict[str, Any] | None = None,
    ) -> None:
        if isinstance(value, list):
            for member in value:
                collect_expression(member, bound_returns, summary=summary)
            return
        if not isinstance(value, dict):
            return
        if value.get("kind") in RETURN_KINDS:
            number = value.get("return_slot")
            if number not in bound_returns:
                remember(("Return", number), summary=summary)
            return
        if set(value) == {"namespace", "slot"}:
            remember((value["namespace"], value["slot"]), summary=summary)
            return
        if set(value) == SUFFIX_FIELDS:
            return
        for member in value.values():
            collect_expression(member, bound_returns, summary=summary)

    def scan_summary(summary: dict[str, Any], bound_returns: set[int]) -> None:
        for key in ("provenance", "capture", "usage"):
            collect_expression(summary.get(key), bound_returns, summary=summary)

    def scan_computation(value: Any, bound_returns: set[int]) -> None:
        if isinstance(value, list):
            for member in value:
                scan_computation(member, bound_returns)
            return
        if not isinstance(value, dict) or set(value) == SUFFIX_FIELDS:
            return
        kind = value.get("kind")
        if kind == "InvokeV2":
            invoked.add(value["application_slot"])
            return
        if kind == "PathBindV2":
            scan_computation(value["prefix"], bound_returns)
            binder = value["return_binder"]
            for key in ("provenance", "capture", "usage"):
                collect_expression(binder.get(key), bound_returns)
            scan_computation(
                value["continuation"], bound_returns | {binder["slot"]},
            )
            return
        for key, member in value.items():
            if key in {"provenance", "capture", "usage"}:
                collect_expression(member, bound_returns)
            else:
                scan_computation(member, bound_returns)

    scan_computation(suffix["computation"], set())
    applications = {
        application["application_slot"]: application
        for application in suffix["applications"]
    }
    for application_slot in invoked:
        application = applications.get(application_slot)
        if application is None:
            continue
        for summary in application["actual_arguments"]:
            scan_summary(summary, set())
    return projected, unresolved


def suffix_live_projection_keys(suffix: dict[str, Any]) -> set[tuple[str, int]]:
    """Compatibility view used by ReplayableCleanup's empty-support check."""

    projected, _ = suffix_live_projection(suffix)
    return set(projected)


def validate_result_transformer(
    transformer: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    transformer = validate_contract_object(transformer)
    kind = transformer.get("kind")
    if kind == "LegacyResultTransformerV2":
        exact_fields(transformer, {"kind", "value"}, kind)
        validate_result_transformer_v1(transformer["value"], disposition_binder=disposition_binder)
    elif kind == "ParametricResultV2":
        exact_fields(transformer, {"kind", "provenance", "capture"}, kind)
        validate_provenance(transformer["provenance"], returns, disposition_binder=disposition_binder)
        validate_capture(transformer["capture"], returns, disposition_binder=disposition_binder)
    elif kind == "ReturnBoundResultV2":
        validate_return_ref(transformer, returns)
    elif kind == "PathJoinResultV2":
        exact_fields(transformer, {"kind", "paths"}, kind)
        for path in transformer["paths"]:
            validate_result_transformer(path, returns, disposition_binder=disposition_binder)
    else:
        raise Diagnostic("contract-component-kind-mismatch")


def validate_environment_binding(
    binding: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    binding = validate_contract_object(binding)
    exact_fields(binding, {"slot", "type", "provenance", "capture"}, "EnvironmentBindingV2")
    validate_slot_v1(binding["slot"])
    if (
        declaration_scope is not None
        and declaration_scope.enforce_ordinary_slots
    ):
        namespace = binding["slot"]["namespace"]
        bindings = {
            "Parameter": declaration_scope.parameter_binders,
            "ClosureCapture": declaration_scope.closure_capture_binders,
            "Owner": set(declaration_scope.owner_binders),
            "Identity": set(declaration_scope.identity_binders),
            "Clock": set(declaration_scope.clock_binders),
            "Row": set(declaration_scope.row_binders),
        }.get(namespace)
        if bindings is not None:
            reject(
                binding["slot"]["slot"] not in bindings,
                "contract-projection-escapes-scope",
            )
    validate_type_v2(
        binding["type"], returns=returns, applications=applications,
        imports=imports, contract_binders=contract_binders,
        local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
    validate_provenance(binding["provenance"], returns, disposition_binder=disposition_binder)
    validate_capture(binding["capture"], returns, disposition_binder=disposition_binder)


def validate_operation_argument_scope(value: Any, arity: int) -> None:
    """Resolve OperationArgument slots against the current site's actual list."""

    for node in walk(value):
        if (
            isinstance(node, dict)
            and set(node) == {"namespace", "slot"}
            and node.get("namespace") == "OperationArgument"
        ):
            reject(
                not isinstance(node.get("slot"), int)
                or isinstance(node.get("slot"), bool)
                or not 0 <= node["slot"] < arity,
                "contract-projection-escapes-scope",
            )


def validate_value_summary(
    summary: dict[str, Any],
    returns: ReturnScope | None = None,
    *,
    applications: ApplicationScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    declaration_scope: DeclarationScope | None = None,
    disposition_binder: dict[str, Any] | None = None,
    defer_function_contract_shape: bool = False,
) -> None:
    returns = returns or {}
    exact_fields(summary, {"source", "type", "nominal_index", "provenance", "capture", "usage", "origin"}, "ValueSummaryExprV2")
    if summary["source"] is not None:
        validate_slot_v2(summary["source"], returns)
    validate_type_v2(
        summary["type"], returns=returns, applications=applications,
        imports=imports, contract_binders=contract_binders,
        local_functions=local_functions,
        declaration_scope=declaration_scope,
        defer_function_contract_shape=defer_function_contract_shape,
    )
    validate_nominal_index(summary["nominal_index"], returns)
    validate_provenance(summary["provenance"], returns, disposition_binder=disposition_binder)
    validate_capture(summary["capture"], returns, disposition_binder=disposition_binder)
    if summary["usage"] is not None:
        validate_usage(summary["usage"], returns, disposition_binder=disposition_binder)


def contains_return_ref(value: Any, return_slot: int) -> bool:
    """Find a Return reference without crossing a fresh declaration boundary."""

    if isinstance(value, list):
        return any(contains_return_ref(member, return_slot) for member in value)
    if not isinstance(value, dict):
        return False
    if (
        value.get("artifact") == "FunctionContractV2"
        or set(value) == HANDLER_CONTRACT_FIELDS
    ):
        return False
    tag = value.get("kind")
    if (
        isinstance(tag, str)
        and tag in RETURN_KINDS
        and value.get("return_slot") == return_slot
    ):
        return True
    return any(
        contains_return_ref(member, return_slot)
        for member in value.values()
    )


def validate_return_binder(
    binder: dict[str, Any],
    returns: ReturnScope,
    *,
    applications: ApplicationScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    declaration_scope: DeclarationScope | None = None,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    exact_fields(binder, {"slot", "type", "world", "nominal_index", "provenance", "capture", "usage"}, "ReturnBinderV2")
    validate_u32(binder["slot"], "return binder slot")
    reject(binder["slot"] in returns, "contract-projection-escapes-scope")
    reject(contains_return_ref({key: value for key, value in binder.items() if key != "slot"}, binder["slot"]), "contract-projection-escapes-scope")
    validate_type_v2(binder["type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_world(binder["world"], returns)
    validate_nominal_index(binder["nominal_index"], returns)
    validate_provenance(binder["provenance"], returns, disposition_binder=disposition_binder)
    validate_capture(binder["capture"], returns, disposition_binder=disposition_binder)
    if binder["usage"] is not None:
        validate_usage(binder["usage"], returns, disposition_binder=disposition_binder)


def validate_cleanup(
    cleanup: dict[str, Any],
    *,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    exact_fields(cleanup, {"residual_row", "attributed_demand", "transition", "suspension", "semantic_summary"}, "CleanupContractV1")
    reject(
        any(
            isinstance(node, dict)
            and str(node.get("kind", "")).endswith("V2")
            for node in walk(cleanup)
        ),
        "unsupported-contract-schema-version",
    )
    validate_row_expr(cleanup["residual_row"])
    demand_keys = [
        validate_demand(
            demand, declaration_scope=declaration_scope,
        )
        for demand in validate_contract_list(cleanup["attributed_demand"])
    ]
    validate_transition(cleanup["transition"])
    request_keys = validate_suspension(
        cleanup["suspension"], declaration_scope=declaration_scope,
    )
    validate_attributed_request_keys(demand_keys, request_keys)
    validate_summary_normal_form(cleanup["semantic_summary"])


def validate_application_ledger(
    ledger: list[dict[str, Any]],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    row_binders: dict[int, dict[str, Any]] | None = None,
    type_parameter_kinds: dict[int, str] | None = None,
    identity_binders: dict[int, dict[str, Any]] | None = None,
    handler_contract_binders: set[int] | None = None,
    declaration_scope: DeclarationScope | None = None,
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
            row_binders=row_binders,
            type_parameter_kinds=type_parameter_kinds,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
            declaration_scope=declaration_scope,
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
    row_binders: dict[int, dict[str, Any]] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    exact_fields(suffix, {"answer_type", "applications", "computation", "cleanup", "live_bindings"}, "SuffixContractV2")
    applications = validate_application_ledger(
        suffix["applications"], returns=returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    validate_type_v2(suffix["answer_type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_cleanup(
        suffix["cleanup"], declaration_scope=declaration_scope,
    )
    declared_live_keys: set[tuple[str, int]] = set()
    for binding in suffix["live_bindings"]:
        exact_fields(binding, {"slot", "type", "provenance", "capture", "usage"}, "LiveAcrossSiteV2")
        validate_slot_v2(binding["slot"], returns)
        live_key = suffix_projection_key(binding["slot"])
        reject(live_key in declared_live_keys, "contract-component-kind-mismatch")
        declared_live_keys.add(live_key)
        binding_slot = binding["slot"]
        if binding_slot.get("kind") == "LegacySlotRefV2" and binding_slot["value"]["namespace"] == "SuffixLive":
            reject(
                disposition_binder is None
                or binding_slot["value"]["slot"] != disposition_binder["slot"],
                "handler-disposition-escapes-scope",
            )
        validate_type_v2(binding["type"], returns=returns, applications=applications, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        validate_provenance(binding["provenance"], returns, disposition_binder=disposition_binder)
        validate_capture(binding["capture"], returns, disposition_binder=disposition_binder)
        if binding["usage"] is not None:
            validate_usage(binding["usage"], returns, disposition_binder=disposition_binder)
    validate_computation(
        suffix["computation"], applications,
        returns=returns, context="suffix", imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        disposition_binder=disposition_binder,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
    )


def validate_resume(
    resumption: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    exact_fields(resumption, {"usage", "continuation", "argument", "answer", "live_provenance", "live_capture", "owner"}, "ResumeTypeV2")
    require(resumption["usage"] in {"Zero", "Once", "Many"}, "ResumeTypeV2 usage")
    validate_type_v2(resumption["argument"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_type_v2(resumption["answer"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_provenance(resumption["live_provenance"], returns)
    validate_capture(resumption["live_capture"], returns)
    validate_slot_v1(resumption["owner"], "Owner")
    validate_suffix(
        resumption["continuation"], returns=returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
    )


def validate_park(
    park: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_wire_u32_fields(park)
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    exact_fields(park, {"owner_slot", "site_slot", "claim_cell_slot", "source", "completion_port", "claim", "disposition", "required_phase", "origin"}, "ParkContractV2")
    for field in ("owner_slot", "site_slot", "claim_cell_slot"):
        validate_u32(park[field], f"ParkContractV2 {field}")
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
    for value, label in (
        (port["port_slot"], "CompletionPortV2 port_slot"),
        (port["claim_cell_slot"], "CompletionPortV2 claim_cell_slot"),
        (claim["claim_cell_slot"], "GenerationCASV1 claim_cell_slot"),
        (disposition["continuation_site_slot"], "OneShotDispositionV2 continuation_site_slot"),
        (disposition["claim_cell_slot"], "OneShotDispositionV2 claim_cell_slot"),
    ):
        validate_u32(value, label)
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
    validate_type_v2(source["value_type"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_type_v2(port["value_type"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    validate_resume(
        resumption, returns=returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    return owner, resumption["owner"]


def obligation_value(obligation: dict[str, Any]) -> dict[str, Any]:
    return obligation["value"] if obligation.get("kind") == "LegacyObligationV2" else obligation


OBLIGATION_FIELDS_V1 = {
    "BoundarySafeV1": {"kind", "id", "stage", "slots", "boundary", "origin"},
    "StableAcrossV1": {"kind", "id", "stage", "slots", "clock_slot", "worlds", "origin"},
    "OutlivesV1": {"kind", "id", "stage", "shorter", "longer", "origin"},
    "PhaseAllowsV1": {"kind", "id", "stage", "required_phase", "origin"},
    "DuplicableEnvV1": {"kind", "id", "stage", "slots", "site_slot", "origin"},
    "ReplayableCleanupV1": {"kind", "id", "stage", "site_slot", "cleanup", "origin"},
    "TickWitnessV1": {"kind", "id", "stage", "clock_slot", "site_slot", "origin"},
    "OwnerParkingV1": {"kind", "id", "stage", "owner_slot", "site_slot", "origin"},
    "RowLacksV1": {"kind", "id", "stage", "row_slot", "entry", "origin"},
}


def validate_obligation_stage(value: dict[str, Any]) -> None:
    reject(value.get("stage") not in {"Call", "HandlerInstall"}, "unknown-obligation-stage")


def validate_legacy_obligation(
    value: dict[str, Any],
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    value = validate_contract_object(value)
    kind = value.get("kind")
    reject(kind not in OBLIGATION_FIELDS_V1, "unknown-obligation-variant")
    exact_fields(value, OBLIGATION_FIELDS_V1[kind], kind)
    validate_u32(value["id"], "ObligationV1 id")
    validate_obligation_stage(value)
    if "slots" in value:
        reject(not isinstance(value["slots"], list), "contract-component-kind-mismatch")
    if "worlds" in value:
        reject(not isinstance(value["worlds"], list), "contract-component-kind-mismatch")
    for reference in value.get("slots", []):
        validate_scoped_slot_v1(reference, disposition_binder=disposition_binder)
    for key in ("shorter", "longer"):
        if key in value:
            validate_scoped_slot_v1(value[key], disposition_binder=disposition_binder)
    for key, namespace in (("clock_slot", "Clock"), ("owner_slot", "Owner"), ("row_slot", "Row")):
        if key in value:
            validate_scoped_slot_v1(value[key], namespace=namespace)
    for world in value.get("worlds", []):
        validate_world_v1(world)
    if "site_slot" in value:
        validate_u32(value["site_slot"], "ObligationV1 site_slot")
    if kind == "BoundarySafeV1":
        reject(
            value["boundary"] not in {
                "CallArgument", "Return", "Closure", "Aggregate", "OwnerStorage",
                "ContinuationCapture", "TemporalLock", "Suspension", "FFI",
            },
            "unknown-obligation-variant",
        )
    if kind == "PhaseAllowsV1":
        validate_phase_requirement(value["required_phase"])
    if kind == "ReplayableCleanupV1":
        validate_cleanup(value["cleanup"])
    if kind == "RowLacksV1":
        validate_effect_entry_selector(value["entry"])


def validate_obligation(
    obligation: dict[str, Any],
    returns: ReturnScope,
    *,
    disposition_binder: dict[str, Any] | None = None,
) -> None:
    kind = obligation.get("kind")
    if kind == "LegacyObligationV2":
        exact_fields(obligation, {"kind", "value"}, kind)
        require(isinstance(obligation["value"], dict), "LegacyObligationV2 value")
        validate_legacy_obligation(
            obligation["value"], disposition_binder=disposition_binder,
        )
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
    reject(kind not in fields, "unknown-obligation-variant")
    exact_fields(obligation, fields[kind], kind)
    validate_u32(obligation["id"], "ObligationV2 id")
    validate_obligation_stage(obligation)
    if "slots" in obligation:
        reject(not isinstance(obligation["slots"], list), "contract-component-kind-mismatch")
    if "worlds" in obligation:
        reject(not isinstance(obligation["worlds"], list), "contract-component-kind-mismatch")
    for reference in obligation.get("slots", []):
        validate_scoped_slot_v2(
            reference, returns, disposition_binder=disposition_binder,
        )
    for key in ("shorter", "longer"):
        if key in obligation:
            validate_scoped_slot_v2(
                obligation[key], returns, disposition_binder=disposition_binder,
            )
    for key, namespace in (("clock_slot", "Clock"), ("owner_slot", "Owner"), ("row_slot", "Row")):
        if key in obligation:
            validate_slot_v1(validate_contract_object(obligation[key]), namespace)
    for world in obligation.get("worlds", []):
        validate_world(world, returns)
    if "site_slot" in obligation:
        validate_u32(obligation["site_slot"], "ObligationV2 site_slot")
    if kind == "BoundarySafeV2":
        reject(
            obligation["boundary"] not in {
                "CallArgument", "Return", "Closure", "Aggregate", "OwnerStorage",
                "ContinuationCapture", "TemporalLock", "Suspension", "FFI",
            },
            "unknown-obligation-variant",
        )
    if kind == "PhaseAllowsV2":
        validate_phase_requirement(obligation["required_phase"])
    if kind == "ReplayableCleanupV2":
        validate_cleanup(obligation["cleanup"])
    if kind == "RowLacksV2":
        validate_effect_entry_selector(obligation["entry"])


def validate_secondary_site_set(
    secondary_sites: Any,
    *,
    declaration_scope: DeclarationScope | None = None,
) -> list[AttributionKey]:
    """Exact-decode one closed SecondarySiteSetV1 in lexical scope."""

    secondary_sites = validate_contract_object(secondary_sites)
    exact_fields(
        secondary_sites, {"kind", "sites"}, "SecondarySiteSetV1",
    )
    reject(
        secondary_sites["kind"] != "Closed",
        "contract-component-kind-mismatch",
    )
    site_keys: list[AttributionKey] = []
    for site in validate_contract_list(secondary_sites["sites"]):
        site = validate_contract_object(site)
        exact_fields(
            site,
            {
                "site_slot", "receiver", "operation", "route",
                "suspension", "semantic_summary", "origin",
            },
            "SecondarySiteV1",
        )
        validate_u32(site["site_slot"], "SecondarySiteV1 site_slot")
        validate_effect_entry_selector(
            site["receiver"],
            (
                declaration_scope.type_parameter_kinds
                if declaration_scope is not None
                else None
            ),
            identity_binders=(
                declaration_scope.identity_binders
                if declaration_scope is not None
                else None
            ),
            handler_contract_binders=(
                declaration_scope.handler_contract_binders
                if declaration_scope is not None
                else None
            ),
        )
        validate_operation_selector(
            site["operation"],
            (
                declaration_scope.type_parameter_kinds
                if declaration_scope is not None
                else None
            ),
        )
        route = validate_route_selector(
            site["route"], declaration_scope=declaration_scope,
        )
        validate_suspension(
            site["suspension"], declaration_scope=declaration_scope,
        )
        validate_summary_normal_form(site["semantic_summary"])
        validate_source_origins(site)
        site_keys.append(
            attribution_key(
                site_slot=site["site_slot"], route=route,
                entry=site["receiver"], operation=site["operation"],
                site_role={
                    "kind": "Secondary",
                    "secondary_slot": site["site_slot"],
                },
            )
        )
    return site_keys


def validate_operation_signature(
    signature: dict[str, Any],
    returns: ReturnScope,
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> list[AttributionKey]:
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    exact_fields(signature, {"type_binders", "parameters", "result", "mode", "transition", "suspension", "result_transformer", "required_phase", "obligation_ids", "secondary_sites"}, "OperationSignatureV2")
    type_binders = validate_contract_list(signature["type_binders"])
    for binder in type_binders:
        validate_type_binder(binder)
    reject(
        len({binder["slot"] for binder in type_binders}) != len(type_binders),
        "contract-component-kind-mismatch",
    )
    signature_scope = declaration_scope
    if declaration_scope is not None:
        local_type_parameter_kinds = dict(
            declaration_scope.type_parameter_kinds
        )
        local_type_parameter_kinds.update(
            {binder["slot"]: binder["kind"] for binder in type_binders}
        )
        signature_scope = DeclarationScope(
            type_parameter_kinds=local_type_parameter_kinds,
            row_binders=declaration_scope.row_binders,
            contract_binders=declaration_scope.contract_binders,
            identity_binders=declaration_scope.identity_binders,
            handler_contract_binders=(
                declaration_scope.handler_contract_binders
            ),
            owner_binders=declaration_scope.owner_binders,
            clock_binders=declaration_scope.clock_binders,
            prompt_binders=declaration_scope.prompt_binders,
            parameter_binders=declaration_scope.parameter_binders,
            closure_capture_binders=(
                declaration_scope.closure_capture_binders
            ),
            enforce_ordinary_slots=(
                declaration_scope.enforce_ordinary_slots
            ),
        )
    for parameter in validate_contract_list(signature["parameters"]):
        validate_type_v2(
            parameter, returns=returns, imports=imports,
            local_functions=local_functions,
            declaration_scope=signature_scope,
        )
    validate_type_v2(
        signature["result"], returns=returns, imports=imports,
        local_functions=local_functions,
        declaration_scope=signature_scope,
    )
    reject(
        not isinstance(signature["mode"], str)
        or signature["mode"] not in {"fun", "once", "ctl", "abort"},
        "contract-component-kind-mismatch",
    )
    validate_transition(signature["transition"])
    validate_suspension(
        signature["suspension"], declaration_scope=signature_scope,
    )
    validate_result_transformer_v1(signature["result_transformer"])
    validate_phase_requirement(signature["required_phase"])
    for local_id in validate_contract_list(signature["obligation_ids"]):
        validate_u32(local_id, "OperationSignatureV2 obligation id")
    return validate_secondary_site_set(
        signature["secondary_sites"], declaration_scope=signature_scope,
    )


def validate_latent_site(
    latent: dict[str, Any],
    *,
    returns: ReturnScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None = None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> list[AttributionKey]:
    exact_fields(latent, {"site_slot", "stage", "receiver", "operation", "route", "actual_arguments", "instantiated_signature", "suffix", "secondary_sites", "call_obligation_ids", "install_obligation_ids", "origin"}, "LatentSiteV2")
    validate_u32(latent["site_slot"], "LatentSiteV2 site_slot")
    reject(
        not isinstance(latent["stage"], str),
        "contract-component-kind-mismatch",
    )
    reject(
        latent["stage"] not in {"Call", "HandlerInstall"},
        "unknown-obligation-stage",
    )
    validate_effect_entry_selector(
        latent["receiver"],
        (
            declaration_scope.type_parameter_kinds
            if declaration_scope is not None
            else None
        ),
        identity_binders=(
            declaration_scope.identity_binders
            if declaration_scope is not None
            else None
        ),
        handler_contract_binders=(
            declaration_scope.handler_contract_binders
            if declaration_scope is not None
            else None
        ),
    )
    validate_operation_selector(
        latent["operation"],
        (
            declaration_scope.type_parameter_kinds
            if declaration_scope is not None
            else None
        ),
    )
    route = validate_route_selector(
        latent["route"], declaration_scope=declaration_scope,
    )
    route_kind = route.get("kind")
    reject(
        route_kind == "ResolveAtCallV1" and latent["stage"] != "Call"
        or route_kind == "ResolveAtInstallationV1"
        and latent["stage"] != "HandlerInstall",
        "contract-component-kind-mismatch",
    )
    actual_arguments = validate_contract_list(latent["actual_arguments"])
    call_obligation_ids = validate_contract_list(
        latent["call_obligation_ids"]
    )
    install_obligation_ids = validate_contract_list(
        latent["install_obligation_ids"]
    )
    for local_id in [*call_obligation_ids, *install_obligation_ids]:
        validate_u32(local_id, "LatentSiteV2 obligation id")
    for summary in actual_arguments:
        validate_value_summary(summary, returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope, disposition_binder=disposition_binder)
    validate_operation_argument_scope(
        actual_arguments, len(actual_arguments),
    )
    signature_site_keys = validate_operation_signature(
        latent["instantiated_signature"], returns,
        imports=imports, local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
    require(
        [summary["type"] for summary in actual_arguments]
        == latent["instantiated_signature"]["parameters"],
        "LatentSiteV2 actual/signature type mismatch",
    )
    secondary_site_keys = validate_secondary_site_set(
        latent["secondary_sites"], declaration_scope=declaration_scope,
    )
    validate_suffix(
        latent["suffix"], returns=returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        disposition_binder=disposition_binder, row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    return [
        attribution_key(
            site_slot=latent["site_slot"], route=route,
            entry=latent["receiver"], operation=latent["operation"],
            site_role="Primary",
        ),
        *(secondary_site_keys or signature_site_keys),
    ]


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
    nearest_outer_prompt_slot: int | None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    exact_fields(forward, {"site_slot", "route", "entry", "operation", "continuation", "entry_world", "actual_argument_summaries", "instantiated_signature", "call_obligation_ids", "install_obligation_ids", "secondary_sites", "origin"}, "ForwardContractV2")
    validate_u32(forward["site_slot"], "ForwardContractV2 site_slot")
    exact_fields(evidence, {"inner_disposition", "input_state", "output_state", "forward_site_slot", "continuation_transfer"}, "ForwardDispositionEvidenceV2")
    validate_u32(evidence["forward_site_slot"], "ForwardDispositionEvidenceV2 forward_site_slot")
    validate_slot_v1(evidence["inner_disposition"], "SuffixLive")
    require(evidence["inner_disposition"] == slot("SuffixLive", disposition_binder["slot"]), "Forward disposition binder mismatch")
    require(evidence["input_state"] == "Open" and evidence["output_state"] == "Forwarded", "Forward disposition states")
    require(evidence["forward_site_slot"] == forward["site_slot"], "Forward site mismatch")
    require(evidence["continuation_transfer"] == "ExclusiveToForwardContract", "Forward transfer must be exclusive")
    validate_operation_selector(forward["operation"])
    reject(forward["operation"] != clause_operation, "forward-operation-mismatch")
    reject(forward["entry"] != handled_entry, "forward-operation-mismatch")
    reject(forward["site_slot"] != disposition_binder["site_slot"], "forward-operation-mismatch")
    route = forward["route"]
    if isinstance(route, dict) and "prompt_slot" in route:
        validate_u32(route["prompt_slot"], "ForwardContractV2 prompt_slot")
    reject(
        route.get("kind") != "InstallationPromptV1"
        or set(route) != {"kind", "prompt_slot"}
        or route["prompt_slot"] == handler_prompt_slot
        or nearest_outer_prompt_slot is None
        or route["prompt_slot"] != nearest_outer_prompt_slot,
        "forward-route-mismatch",
    )
    validate_world(forward["entry_world"], returns)
    reject(
        forward["entry_world"]
        != {"kind": "LegacyWorldExprV2", "value": {"kind": "EntryWorldV1", "site_slot": forward["site_slot"]}},
        "forward-route-mismatch",
    )
    for summary in forward["actual_argument_summaries"]:
        validate_value_summary(summary, returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope, disposition_binder=disposition_binder)
    validate_operation_argument_scope(
        forward["actual_argument_summaries"],
        len(forward["actual_argument_summaries"]),
    )
    validate_operation_signature(
        forward["instantiated_signature"], returns,
        imports=imports, local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
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
    validate_suffix(
        forward["continuation"], returns=returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        disposition_binder=disposition_binder, row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    resume_type = disposition_binder["type"]
    require(resume_type.get("kind") == "ResumeTypeRefV2", "ClauseDispositionBinderV2 type")
    require(resume_type["value"]["continuation"] == forward["continuation"], "Forward continuation/disposition mismatch")
    reject(
        resume_type["value"]["argument"] != forward["instantiated_signature"]["result"]
        or resume_type["value"]["answer"] != forward["continuation"]["answer_type"],
        "forward-application-arity-type-mismatch",
    )
    quantities = {"fun": "Once", "once": "Once", "ctl": "Many", "abort": "Zero"}
    reject(
        resume_type["value"]["usage"] != quantities[forward["instantiated_signature"]["mode"]],
        "forward-disposition-quantity-mismatch",
    )


def validate_path(
    path: dict[str, Any],
    *,
    applications: ApplicationScope,
    returns: ReturnScope,
    context: str,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    row_binders: dict[int, dict[str, Any]] | None = None,
    disposition_binder: dict[str, Any] | None = None,
    clause_operation: dict[str, Any] | None = None,
    handled_entry: dict[str, Any] | None = None,
    handler_prompt_slot: int | None = None,
    nearest_outer_prompt_slot: int | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    exact_fields(path, {"outcome", "residual_row", "attributed_demand", "suspension", "semantic_summary", "usage", "required_phase", "ParametricObligations", "LatentSites"}, "PathContractV2")
    validate_row_expr(path["residual_row"])
    demand_keys = [
        validate_demand(
            demand, declaration_scope=declaration_scope,
        )
        for demand in validate_contract_list(path["attributed_demand"])
    ]
    request_keys = validate_suspension(
        path["suspension"], declaration_scope=declaration_scope,
    )
    validate_summary_normal_form(path["semantic_summary"])
    validate_phase_requirement(path["required_phase"])
    usage_keys: set[tuple[str, int]] = set()
    for usage in path["usage"]:
        validate_usage(usage, returns, disposition_binder=disposition_binder)
        usage_key = usage_map_key(usage)
        reject(usage_key in usage_keys, "contract-component-kind-mismatch")
        usage_keys.add(usage_key)
    for obligation in path["ParametricObligations"]:
        validate_obligation(
            obligation, returns, disposition_binder=disposition_binder,
        )
    q = [obligation_value(obligation) for obligation in path["ParametricObligations"]]
    q_keys = {(entry["stage"], entry["id"]) for entry in q}
    site_keys: list[AttributionKey] = []
    for latent in validate_contract_list(path["LatentSites"]):
        site_keys.extend(
            validate_latent_site(
                latent, returns=returns, imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                disposition_binder=disposition_binder,
                row_binders=row_binders,
                declaration_scope=declaration_scope,
            )
        )
        for local_id in latent["call_obligation_ids"]:
            reject(("Call", local_id) not in q_keys, "projected-obligation-stage-lost")
        for local_id in latent["install_obligation_ids"]:
            reject(("HandlerInstall", local_id) not in q_keys, "projected-obligation-stage-lost")
    validate_attributed_request_keys(
        demand_keys, request_keys, site_keys=site_keys,
    )
    outcome = path["outcome"]
    kind = outcome.get("kind")
    if kind == "ReturnsV2":
        exact_fields(outcome, {"kind", "transition", "result_transformer"}, kind)
        validate_transition(outcome["transition"])
        validate_result_transformer(
            outcome["result_transformer"], returns,
            disposition_binder=disposition_binder,
        )
    elif kind == "AbortsV2":
        exact_fields(outcome, {"kind", "origin"}, kind)
    elif kind == "TransfersV2":
        exact_fields(outcome, {"kind", "park_contract"}, kind)
        parked_owner, resumption_owner = validate_park(
            outcome["park_contract"], returns=returns, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            row_binders=row_binders,
            declaration_scope=declaration_scope,
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
        park = outcome["park_contract"]
        expected_atom = {
            "grade": "MaySuspend",
            "kind": "OwnerBoundV1",
            "origin": park["origin"],
            "owner_slot": park["owner_slot"],
            "park_site_slot": park["site_slot"],
        }
        expected_summary = packed_summary(
            park["origin"], replay_origin="Fresh", fork="Forbid", suspend="OwnerBound",
        )
        summary_members = (
            path["semantic_summary"]["members"]
            if path["semantic_summary"].get("kind") == "SequenceSummaryV1"
            else [path["semantic_summary"]]
        )
        reject(
            path["suspension"].get("grade") != "MaySuspend"
            or expected_atom not in path["suspension"].get("atoms", [])
            or expected_summary not in summary_members
            or path["required_phase"]["allowed_phases"] != ["Action"]
            or path["required_phase"]["current_owner"] != park["required_phase"]["current_owner"]
            or any(
                authority not in path["required_phase"]["required_authorities"]
                for authority in park["required_phase"]["required_authorities"]
            ),
            "park-path-observer-mismatch",
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
            nearest_outer_prompt_slot=nearest_outer_prompt_slot,
            row_binders=row_binders,
            declaration_scope=declaration_scope,
        )
        inner_disposition = outcome["disposition_evidence"]["inner_disposition"]
        reject(
            suffix_projection_key(inner_disposition) not in usage_keys
            or not any(
                usage.get("kind") == "LegacyUsageExprV2"
                and usage["value"]["slot"] == inner_disposition
                and usage["value"]["kind"] in {"Once", "Many"}
                for usage in path["usage"]
            ),
            "contract-component-kind-mismatch",
        )
    else:
        raise Diagnostic("unknown-path-outcome-v2")


def computation_return_types(
    computation: dict[str, Any],
    applications: ApplicationScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None = None,
    returns: ReturnScope | None = None,
) -> list[dict[str, Any]] | None:
    returns = returns or {}
    kind = computation.get("kind")
    if kind == "CurrentDispositionPathsV2":
        if disposition_binder is None:
            return None
        result_types = [
            copy.deepcopy(disposition_binder["type"])
            for path in computation["paths"]
            if path["outcome"].get("kind") == "ReturnsV2"
        ]
        return result_types
    if kind == "LiteralPathsV2":
        result_types: list[dict[str, Any]] = []
        for path in computation["paths"]:
            outcome = path["outcome"]
            if outcome.get("kind") != "ReturnsV2":
                continue
            transformer = outcome["result_transformer"]
            if transformer.get("kind") == "ReturnBoundResultV2":
                return_slot = transformer.get("return_slot")
                if return_slot not in returns:
                    return None
                result_types.append(copy.deepcopy(returns[return_slot]["type"]))
                continue
            if transformer.get("kind") == "ParametricResultV2":
                provenance = transformer.get("provenance", {})
                capture = transformer.get("capture", {})
                if (
                    provenance.get("kind") == "ReturnProvenanceV2"
                    and capture.get("kind") == "ReturnCaptureV2"
                    and provenance.get("return_slot") == capture.get("return_slot")
                    and provenance.get("return_slot") in returns
                ):
                    result_types.append(
                        copy.deepcopy(returns[provenance["return_slot"]]["type"])
                    )
                    continue
            provenance = (
                transformer.get("provenance")
                if transformer.get("kind") == "ParametricResultV2"
                else {"kind": "LegacyProvenanceExprV2", "value": transformer.get("value", {}).get("provenance")}
            )
            expression = provenance.get("value", {}) if provenance.get("kind") == "LegacyProvenanceExprV2" else {}
            if expression.get("kind") != "OperationResultProvenanceV1":
                return None
            matching_sites = [
                site for site in path["LatentSites"]
                if site["site_slot"] == expression.get("site_slot")
            ]
            if len(matching_sites) != 1:
                return None
            result_types.append(copy.deepcopy(matching_sites[0]["instantiated_signature"]["result"]))
        return result_types
    if kind == "InvokeV2":
        application = applications[computation["application_slot"]]
        target_kind, _ = resolve_contract_target(
            application["contract"], imports, contract_binders, local_functions,
        )
        return [substitute_contract_kind(target_kind, application["substitution"])["result_type"]]
    if kind == "PathBindV2":
        prefix_types = computation_return_types(
            computation["prefix"], applications, imports,
            contract_binders, local_functions, disposition_binder, returns,
        )
        if prefix_types is None or not prefix_types:
            return prefix_types
        continuation_returns = dict(returns)
        return_binder = computation["return_binder"]
        continuation_returns[return_binder["slot"]] = return_binder
        return computation_return_types(
            computation["continuation"], applications, imports,
            contract_binders, local_functions, disposition_binder,
            continuation_returns,
        )
    if kind == "JoinV2":
        member_types = [
            computation_return_types(
                member, applications, imports, contract_binders, local_functions,
                disposition_binder, returns,
            )
            for member in computation["members"]
        ]
        if any(result_types is None for result_types in member_types):
            return None
        return [result for result_types in member_types for result in result_types or []]
    return None


def validate_computation(
    computation: dict[str, Any],
    applications: ApplicationScope | set[int],
    *,
    returns: ReturnScope | None = None,
    context: str = "function",
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    disposition_binder: dict[str, Any] | None = None,
    clause_operation: dict[str, Any] | None = None,
    handled_entry: dict[str, Any] | None = None,
    handler_prompt_slot: int | None = None,
    nearest_outer_prompt_slot: int | None = None,
    allow_current_disposition_paths: bool = False,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    returns = returns or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    if isinstance(applications, set):
        applications = {number: {"application_slot": number} for number in applications}
    kind = computation.get("kind")
    if kind == "CurrentDispositionPathsV2":
        exact_fields(computation, {"kind", "paths"}, kind)
        reject(
            context != "handler_clause"
            or disposition_binder is None
            or not allow_current_disposition_paths,
            "path-bind-literal-prefix-forbidden",
        )
        require(bool(computation["paths"]), "CurrentDispositionPathsV2 must be nonempty")
        for path in computation["paths"]:
            validate_path(
                path, applications=applications, returns=returns, context=context,
                imports=imports, contract_binders=contract_binders,
                local_functions=local_functions, row_binders=row_binders,
                disposition_binder=disposition_binder,
                clause_operation=clause_operation, handled_entry=handled_entry,
                handler_prompt_slot=handler_prompt_slot,
                nearest_outer_prompt_slot=nearest_outer_prompt_slot,
                declaration_scope=declaration_scope,
            )
    elif kind == "LiteralPathsV2":
        exact_fields(computation, {"kind", "paths"}, kind)
        require(bool(computation["paths"]), "LiteralPathsV2 must be nonempty")
        for path in computation["paths"]:
            validate_path(
                path, applications=applications, returns=returns, context=context,
                imports=imports, contract_binders=contract_binders,
                local_functions=local_functions, row_binders=row_binders,
                disposition_binder=disposition_binder,
                clause_operation=clause_operation, handled_entry=handled_entry,
                handler_prompt_slot=handler_prompt_slot,
                nearest_outer_prompt_slot=nearest_outer_prompt_slot,
                declaration_scope=declaration_scope,
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
            row_binders=row_binders, disposition_binder=disposition_binder,
            clause_operation=clause_operation,
            handled_entry=handled_entry, handler_prompt_slot=handler_prompt_slot,
            nearest_outer_prompt_slot=nearest_outer_prompt_slot,
            allow_current_disposition_paths=context == "handler_clause",
            declaration_scope=declaration_scope,
        )
        binder = computation["return_binder"]
        validate_return_binder(
            binder, returns, applications=applications, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            declaration_scope=declaration_scope,
            disposition_binder=disposition_binder,
        )
        result_types = computation_return_types(
            computation["prefix"], applications, imports,
            contract_binders, local_functions, disposition_binder, returns,
        )
        reject(not result_types, "path-bind-literal-prefix-forbidden")
        for result_type in result_types:
            reject(binder["type"] != result_type, "path-bind-return-binder-mismatch")
        validate_computation_return_projection(
            computation["prefix"], binder,
            applications=applications, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            disposition_binder=disposition_binder, returns=returns,
        )
        continuation_returns = dict(returns)
        continuation_returns[binder["slot"]] = binder
        validate_computation(
            computation["continuation"], applications, returns=continuation_returns,
            context=context, imports=imports, contract_binders=contract_binders,
            local_functions=local_functions, row_binders=row_binders,
            disposition_binder=disposition_binder,
            clause_operation=clause_operation, handled_entry=handled_entry,
            handler_prompt_slot=handler_prompt_slot,
            nearest_outer_prompt_slot=nearest_outer_prompt_slot,
            declaration_scope=declaration_scope,
        )
    elif kind == "JoinV2":
        exact_fields(computation, {"kind", "members"}, kind)
        require(bool(computation["members"]), "JoinV2 must be nonempty")
        for member in computation["members"]:
            validate_computation(
                member, applications, returns=returns, context=context,
                imports=imports, contract_binders=contract_binders,
                local_functions=local_functions, row_binders=row_binders,
                disposition_binder=disposition_binder,
                clause_operation=clause_operation, handled_entry=handled_entry,
                handler_prompt_slot=handler_prompt_slot,
                nearest_outer_prompt_slot=nearest_outer_prompt_slot,
                declaration_scope=declaration_scope,
            )
    else:
        raise Diagnostic("unknown-contract-computation-variant")


def binder_kind(binder: dict[str, Any]) -> dict[str, Any]:
    if isinstance(binder.get("kind"), dict):
        kind = binder["kind"]
        reject(
            kind.get("kind")
            not in {
                "FunctionContractKindV2",
                "LaterContractKindV2",
                "ContinuationContractKindV2",
                "HandlerContractKindV2",
                "ClockPackageSummaryKindV2",
            },
            "contract-component-kind-mismatch",
        )
        return kind
    tag = binder.get("kind")
    if tag == "FunctionContractBinderV2":
        return {
            "kind": "FunctionContractKindV2",
            "parameter_type": binder["parameter_type"],
            "result_type": binder["result_type"],
            "visible_row": binder["visible_row"],
        }
    if tag == "LaterContractBinderV2":
        return {
            "kind": "LaterContractKindV2",
            "clock": binder["clock"],
            "payload_type": binder["payload_type"],
        }
    if tag == "ContinuationContractBinderV2":
        return {
            "kind": "ContinuationContractKindV2",
            "argument_type": binder["argument_type"],
            "answer_type": binder["answer_type"],
        }
    if tag == "HandlerContractBinderV2":
        return handler_binder_kind(binder)
    raise Diagnostic("contract-component-kind-mismatch")


def handler_binder_kind(binder: dict[str, Any]) -> dict[str, Any]:
    reject(
        binder.get("kind") != "HandlerContractBinderV2",
        "contract-component-kind-mismatch",
    )
    return {
        "kind": "HandlerContractKindV2",
        "family": binder["family"],
        "input_type": binder["input_type"],
        "answer_type": binder["answer_type"],
    }


def unique_slots(bindings: list[dict[str, Any]], key: str, label: str) -> set[int]:
    values: list[int] = []
    for binding in bindings:
        binding = validate_contract_object(binding)
        reject(key not in binding, "contract-component-kind-mismatch")
        validate_u32(binding[key], f"{label} binder slot")
        values.append(binding[key])
    reject(
        len(values) != len(set(values)),
        "contract-component-kind-mismatch",
    )
    return set(values)


def validate_declaration_binders(binders: dict[str, Any], closure_environment: list[dict[str, Any]]) -> None:
    exact_fields(
        binders,
        {"parameter_binders", "type_binders", "row_binders", "contract_binders", "owner_binders", "clock_binders", "identity_binders", "prompt_binders"},
        "DeclarationBindersV2",
    )
    binder_lists = {
        field: validate_contract_list(binders[field])
        for field in (
            "parameter_binders", "type_binders", "row_binders",
            "contract_binders", "owner_binders", "clock_binders",
            "identity_binders", "prompt_binders",
        )
    }
    for parameter in binder_lists["parameter_binders"]:
        parameter = validate_contract_object(parameter)
        exact_fields(parameter, {"slot", "type"}, "ParameterBinderV2")
    for binder in binder_lists["type_binders"]:
        validate_type_binder(binder)
    for row in binder_lists["row_binders"]:
        row = validate_contract_object(row)
        exact_fields(row, {"slot", "lacks"}, "RowBinderV1")
    for binder in binder_lists["contract_binders"]:
        binder = validate_contract_object(binder)
        binder_tag = binder.get("kind")
        if binder_tag == "FunctionContractBinderV2":
            exact_fields(
                binder,
                {"kind", "slot", "parameter_type", "result_type", "visible_row"},
                binder_tag,
            )
        elif binder_tag == "LaterContractBinderV2":
            exact_fields(
                binder,
                {"kind", "slot", "clock", "payload_type"},
                binder_tag,
            )
            validate_slot_v1(binder["clock"], "Clock")
        elif binder_tag == "ContinuationContractBinderV2":
            exact_fields(
                binder,
                {"kind", "slot", "argument_type", "answer_type"},
                binder_tag,
            )
        elif binder_tag == "HandlerContractBinderV2":
            exact_fields(
                binder,
                {"kind", "slot", "family", "input_type", "answer_type"},
                binder_tag,
            )
        else:
            raise Diagnostic("contract-component-kind-mismatch")
    for owner in binder_lists["owner_binders"]:
        owner = validate_contract_object(owner)
        exact_fields(owner, {"slot", "source"}, "OwnerSlotDeclV1")
        validate_slot_v1(owner["source"])
    for clock in binder_lists["clock_binders"]:
        clock = validate_contract_object(clock)
        exact_fields(
            clock, {"slot", "identity", "owner"}, "ClockSlotDeclV1",
        )
        validate_slot_v1(clock["identity"], "Identity")
        validate_slot_v1(clock["owner"], "Owner")
    for identity in binder_lists["identity_binders"]:
        identity = validate_contract_object(identity)
        exact_fields(
            identity,
            {"identity_slot", "family", "owner", "binder"},
            "IdentitySlotDeclV1",
        )
        validate_slot_v1(identity["owner"], "Owner")
    for prompt in binder_lists["prompt_binders"]:
        prompt = validate_contract_object(prompt)
        exact_fields(
            prompt,
            {"binder_site_slot", "prompt_slot", "scope"},
            "PromptSlotDeclV1",
        )
        validate_u32(prompt["binder_site_slot"], "Prompt binder site slot")
        validate_u32(prompt["prompt_slot"], "Prompt binder slot")
        reject(
            prompt["scope"] != "LexicalInstallation",
            "contract-component-kind-mismatch",
        )
    parameters = unique_slots(binders["parameter_binders"], "slot", "Parameter")
    types = unique_slots(binders["type_binders"], "slot", "Type")
    rows = unique_slots(binders["row_binders"], "slot", "Row")
    owners = unique_slots(binders["owner_binders"], "slot", "Owner")
    identities = unique_slots(binders["identity_binders"], "identity_slot", "Identity")
    clocks = unique_slots(binders["clock_binders"], "slot", "Clock")
    contracts = unique_slots(binders["contract_binders"], "slot", "Contract")
    prompts = unique_slots(binders["prompt_binders"], "prompt_slot", "Prompt")
    type_parameter_kinds = {
        binder["slot"]: binder["kind"] for binder in binders["type_binders"]
    }
    for number in [*parameters, *types, *rows, *contracts, *owners, *identities, *clocks, *prompts]:
        validate_u32(number, "declaration binder slot")
    closure_slots = {binding["slot"]["slot"] for binding in closure_environment if binding["slot"]["namespace"] == "ClosureCapture"}
    for owner in binders["owner_binders"]:
        source = owner["source"]
        require(
            (source["namespace"] == "Parameter" and source["slot"] in parameters)
            or (source["namespace"] == "ClosureCapture" and source["slot"] in closure_slots),
            "Owner binder source is out of scope",
        )
    for identity in binders["identity_binders"]:
        identity = validate_contract_object(identity)
        exact_fields(
            identity,
            {"identity_slot", "family", "owner", "binder"},
            "IdentitySlotDeclV1",
        )
        validate_effect_family_ref(identity["family"], type_parameter_kinds)
        reject(
            identity["binder"] not in {"FreshCap", "NamedHandler"},
            "contract-component-kind-mismatch",
        )
        require(identity["owner"] == slot("Owner", identity["owner"]["slot"]) and identity["owner"]["slot"] in owners, "Identity Owner is out of scope")
    identity_by_slot = {binding["identity_slot"]: binding for binding in binders["identity_binders"]}
    handler_contract_binders = {
        binding["slot"]
        for binding in binders["contract_binders"]
        if binding.get("kind") == "HandlerContractBinderV2"
    }
    for row in binders["row_binders"]:
        row = validate_contract_object(row)
        exact_fields(row, {"slot", "lacks"}, "RowBinderV1")
        for entry in validate_contract_list(row["lacks"]):
            validate_effect_entry_selector(
                entry,
                type_parameter_kinds,
                identity_binders=identity_by_slot,
                handler_contract_binders=handler_contract_binders,
            )
    for clock in binders["clock_binders"]:
        identity_ref = clock["identity"]
        require(identity_ref["namespace"] == "Identity" and identity_ref["slot"] in identities, "Clock identity is out of scope")
        require(clock["owner"] == identity_by_slot[identity_ref["slot"]]["owner"], "Clock/Identity Owner mismatch")


def validate_kinded_type_parameter_scope(
    value: Any,
    ambient_type_parameters: dict[int, str],
    *,
    expected_kind: str = "Type",
    imports: ImportScope | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    """Check Type/Effect positions against the innermost complete kind scope."""

    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}

    if isinstance(value, list):
        for member in value:
            validate_kinded_type_parameter_scope(
                member,
                ambient_type_parameters,
                expected_kind=expected_kind,
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2":
        # An inline nested declaration establishes its own binder context and is
        # validated recursively by validate_type_v2.
        return
    if value.get("kind") == "TypeParameterIndexV1":
        slot_number = value.get("slot")
        reject(
            expected_kind != "Type"
            or slot_number not in ambient_type_parameters
            or ambient_type_parameters[slot_number] != "Type",
            "contract-projection-escapes-scope",
        )
        return
    if isinstance(value.get("kind"), str) and value.get("kind") in {
        "TypeParameterV1", "TypeParameterV2",
    }:
        slot_number = value.get("slot")
        if expected_kind == "Effect":
            reject(
                slot_number not in ambient_type_parameters,
                "contract-projection-escapes-scope",
            )
            reject(
                ambient_type_parameters[slot_number] != "Effect",
                "contract-component-kind-mismatch",
            )
        else:
            # Preserve the established Type-position diagnostic: an Effect
            # binder is not in the Type projection namespace.
            reject(
                slot_number not in ambient_type_parameters
                or ambient_type_parameters[slot_number] != "Type",
                "contract-projection-escapes-scope",
            )
        return
    if expected_kind == "Effect":
        if value.get("kind") == "LegacyTypeRefV2":
            validate_kinded_type_parameter_scope(
                value.get("value"),
                ambient_type_parameters,
                expected_kind="Effect",
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
            )
            return
        if value.get("kind") == "NominalTypeV1":
            validate_effect_family_ref(value, ambient_type_parameters)
            for argument in value.get("arguments", []):
                validate_kinded_type_parameter_scope(
                    argument,
                    ambient_type_parameters,
                    expected_kind="Type",
                    imports=imports,
                    contract_binders=contract_binders,
                    local_functions=local_functions,
                )
            return
        raise Diagnostic("contract-component-kind-mismatch")
    signature_fields = {
        "type_binders", "parameters", "result", "mode", "transition",
        "suspension", "result_transformer", "required_phase",
        "obligation_ids", "secondary_sites",
    }
    if signature_fields <= set(value):
        local_type_parameters: dict[int, str] = {}
        for binder in validate_contract_list(value["type_binders"]):
            validate_type_binder(binder)
            local_type_parameters[binder["slot"]] = binder["kind"]
        signature_scope = dict(ambient_type_parameters)
        for slot_number in local_type_parameters:
            signature_scope.pop(slot_number, None)
        signature_scope.update(local_type_parameters)
        for key, member in value.items():
            if key != "type_binders":
                validate_kinded_type_parameter_scope(
                    member,
                    signature_scope,
                    imports=imports,
                    contract_binders=contract_binders,
                    local_functions=local_functions,
                )
        return
    application_fields = {
        "application_slot", "contract", "callee_summary", "actual_arguments",
        "substitution", "entry_world", "origin",
    }
    if application_fields == set(value):
        _, target = resolve_contract_target(
            value["contract"], imports, contract_binders, local_functions,
        )
        target_kinds = (
            {
                binder["slot"]: binder["kind"]
                for binder in target["binders"]["type_binders"]
            }
            if target is not None
            else {}
        )
        substitution = validate_contract_object(value["substitution"])
        type_arguments = validate_contract_list(
            substitution.get("type_arguments")
        )
        for argument in type_arguments:
            argument = validate_contract_object(argument)
            binder_slot = argument.get("binder_slot")
            if binder_slot not in target_kinds:
                # Domain equality is diagnosed by the application decoder.
                continue
            binder_kind_name = target_kinds[binder_slot]
            reject(
                binder_kind_name not in {"Type", "Effect"},
                "contract-component-kind-mismatch",
            )
            validate_kinded_type_parameter_scope(
                argument.get("value"),
                ambient_type_parameters,
                expected_kind=binder_kind_name,
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
            )
        for key, member in value.items():
            if key == "substitution":
                for field, entries in substitution.items():
                    if field == "type_arguments":
                        continue
                    validate_kinded_type_parameter_scope(
                        entries,
                        ambient_type_parameters,
                        imports=imports,
                        contract_binders=contract_binders,
                        local_functions=local_functions,
                    )
                continue
            validate_kinded_type_parameter_scope(
                member,
                ambient_type_parameters,
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
            )
        return
    for key, member in value.items():
        validate_kinded_type_parameter_scope(
            member,
            ambient_type_parameters,
            expected_kind="Effect" if key == "family" else "Type",
            imports=imports,
            contract_binders=contract_binders,
            local_functions=local_functions,
        )


def is_authority_bearing_type(type_ref: Any) -> bool:
    """AuthorityBearingSlot is exactly a Resume/disposition-typed binder."""

    if not isinstance(type_ref, dict):
        return False
    if type_ref.get("kind") == "ResumeTypeRefV2":
        return True
    return (
        type_ref.get("kind") == "LegacyTypeRefV2"
        and isinstance(type_ref.get("value"), dict)
        and type_ref["value"].get("kind") == "ResumeTypeV1"
    )


def authority_usage_grade(type_ref: Any) -> str | None:
    """Return the exact Resume/disposition grade carried by a binder type."""

    if not isinstance(type_ref, dict):
        return None
    if type_ref.get("kind") == "ResumeTypeRefV2":
        value = type_ref.get("value")
        return value.get("usage") if isinstance(value, dict) else None
    if type_ref.get("kind") == "LegacyTypeRefV2":
        value = type_ref.get("value")
        if isinstance(value, dict) and value.get("kind") == "ResumeTypeV1":
            return value.get("usage")
    return None


USAGE_GRADE_ORDER = {"Zero": 0, "Once": 1, "Many": 2}


def lexical_binding_projection(
    reference: dict[str, Any],
    type_ref: dict[str, Any],
    provenance: dict[str, Any],
    capture: dict[str, Any],
) -> dict[str, Any]:
    return value_projection(
        type_ref=type_ref,
        provenance=provenance,
        capture=capture,
        usage=authority_projection(type_ref, reference),
    )


def validate_suffix_projection_exact(
    suffix: dict[str, Any],
    *,
    returns: ReturnScope,
    value_bindings: dict[tuple[str, int], dict[str, Any]],
) -> None:
    expected, unresolved = suffix_live_projection(
        suffix, returns=returns, value_bindings=value_bindings,
    )
    declared: dict[tuple[str, int], dict[str, Any]] = {}
    for binding in suffix["live_bindings"]:
        key = suffix_projection_key(binding["slot"])
        declared[key] = {
            field: copy.deepcopy(binding[field]) for field in LIVE_TUPLE_FIELDS
        }
    reject(
        bool(unresolved) or set(declared) != set(expected),
        "contract-component-kind-mismatch",
    )
    for key in declared:
        fields = (
            ("provenance", "capture", "usage")
            if key[0] == "Return"
            else LIVE_TUPLE_FIELDS
        )
        reject(
            any(declared[key][field] != expected[key][field] for field in fields),
            "contract-component-kind-mismatch",
        )


HANDLER_CONTRACT_FIELDS = {
    "handled_entry", "prompt_slot", "residual_row", "attributed_demand",
    "suspension", "semantic_summary", "required_phase", "handler_environment",
    "applications", "return_computation", "clause_computations",
}


def validate_suffix_projection_tree(
    value: Any,
    *,
    returns: ReturnScope,
    value_bindings: dict[tuple[str, int], dict[str, Any]],
) -> None:
    """Validate every nested suffix with its exact lexical Return environment."""

    if isinstance(value, list):
        for member in value:
            validate_suffix_projection_tree(
                member, returns=returns, value_bindings=value_bindings,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2" or set(value) == HANDLER_CONTRACT_FIELDS:
        # Embedded contracts run their own root-scoped pass when decoded.
        return
    if set(value) == SUFFIX_FIELDS:
        validate_suffix_projection_exact(
            value, returns=returns, value_bindings=value_bindings,
        )
        for key in ("answer_type", "applications", "cleanup", "live_bindings"):
            validate_suffix_projection_tree(
                value[key], returns=returns, value_bindings=value_bindings,
            )
        validate_suffix_projection_tree(
            value["computation"], returns=returns,
            value_bindings=value_bindings,
        )
        return
    if value.get("kind") == "PathBindV2":
        validate_suffix_projection_tree(
            value["prefix"], returns=returns, value_bindings=value_bindings,
        )
        binder = value["return_binder"]
        validate_suffix_projection_tree(
            binder, returns=returns, value_bindings=value_bindings,
        )
        continuation_returns = dict(returns)
        continuation_returns[binder["slot"]] = binder
        validate_suffix_projection_tree(
            value["continuation"], returns=continuation_returns,
            value_bindings=value_bindings,
        )
        return
    for member in value.values():
        validate_suffix_projection_tree(
            member, returns=returns, value_bindings=value_bindings,
        )


def function_value_bindings(
    contract: dict[str, Any],
) -> dict[tuple[str, int], dict[str, Any]]:
    result: dict[tuple[str, int], dict[str, Any]] = {}
    for binder in contract["binders"]["parameter_binders"]:
        reference = slot("Parameter", binder["slot"])
        result[("Parameter", binder["slot"])] = lexical_binding_projection(
            reference,
            binder["type"],
            {
                "kind": "LegacyProvenanceExprV2",
                "value": {"kind": "ArgumentV1", "argument": reference},
            },
            {
                "kind": "LegacyCaptureExprV2",
                "value": {"kind": "ArgumentCaptureV1", "argument": reference},
            },
        )
    for binding in contract["closure_environment"]:
        reference = binding["slot"]
        result[(reference["namespace"], reference["slot"])] = lexical_binding_projection(
            reference, binding["type"], binding["provenance"], binding["capture"],
        )
    return result


def validate_function_suffix_projections(contract: dict[str, Any]) -> None:
    bindings = function_value_bindings(contract)
    for key in (
        "declaration_kind", "binders", "applications", "computation",
        "closure_environment",
    ):
        validate_suffix_projection_tree(
            contract[key], returns={}, value_bindings=bindings,
        )


def validate_handler_suffix_projections(contract: dict[str, Any]) -> None:
    bindings: dict[tuple[str, int], dict[str, Any]] = {}
    for binding in contract["handler_environment"]:
        reference = binding["slot"]
        bindings[(reference["namespace"], reference["slot"])] = lexical_binding_projection(
            reference, binding["type"], binding["provenance"], binding["capture"],
        )
    for key in ("applications", "return_computation"):
        validate_suffix_projection_tree(
            contract[key], returns={}, value_bindings=bindings,
        )
    for clause in contract["clause_computations"]:
        disposition = clause["disposition_binder"]
        reference = slot("SuffixLive", disposition["slot"])
        resume = disposition["type"]["value"]
        clause_bindings = dict(bindings)
        clause_bindings[("SuffixLive", disposition["slot"])] = lexical_binding_projection(
            reference,
            disposition["type"],
            resume["live_provenance"],
            resume["live_capture"],
        )
        validate_suffix_projection_tree(
            disposition["type"], returns={}, value_bindings=bindings,
        )
        validate_suffix_projection_tree(
            clause["computation"], returns={}, value_bindings=clause_bindings,
        )


def validate_authority_bearing_usages(
    value: Any,
    *,
    slot_types: dict[tuple[str, int], dict[str, Any]] | None = None,
    disposition: tuple[int, dict[str, Any]] | None = None,
    operation_argument_types: list[dict[str, Any]] | None = None,
) -> None:
    """Resolve every Legacy UsageV1 slot in its lexical binder context."""

    slot_types = slot_types or {}
    if isinstance(value, list):
        for member in value:
            validate_authority_bearing_usages(
                member,
                slot_types=slot_types,
                disposition=disposition,
                operation_argument_types=operation_argument_types,
            )
        return
    if not isinstance(value, dict):
        return

    if value.get("artifact") == "FunctionContractV2":
        binders = value["binders"]
        nested_slot_types = {
            ("Parameter", binder["slot"]): binder["type"]
            for binder in binders["parameter_binders"]
        }
        nested_slot_types.update(
            {
                ("ClosureCapture", binding["slot"]["slot"]): binding["type"]
                for binding in value["closure_environment"]
            }
        )
        for member in value.values():
            validate_authority_bearing_usages(
                member, slot_types=nested_slot_types,
            )
        return

    if value.get("kind") == "LegacyUsageExprV2":
        reference = value["value"]["slot"]
        namespace = reference["namespace"]
        number = reference["slot"]
        resolved_type = None
        if namespace == "SuffixLive" and disposition is not None:
            if number == disposition[0]:
                resolved_type = disposition[1]
        elif namespace == "OperationArgument" and operation_argument_types is not None:
            if 0 <= number < len(operation_argument_types):
                resolved_type = operation_argument_types[number]
        else:
            resolved_type = slot_types.get((namespace, number))
        occurrence_grade = value["value"]["kind"]
        capacity_grade = authority_usage_grade(resolved_type)
        reject(
            not is_authority_bearing_type(resolved_type)
            or occurrence_grade == "Zero"
            or occurrence_grade not in USAGE_GRADE_ORDER
            or capacity_grade not in USAGE_GRADE_ORDER
            or USAGE_GRADE_ORDER[occurrence_grade] > USAGE_GRADE_ORDER[capacity_grade],
            "contract-component-kind-mismatch",
        )
        return

    if {
        "answer_type", "applications", "computation", "cleanup", "live_bindings",
    } <= set(value):
        suffix_slot_types = dict(slot_types)
        for binding in value["live_bindings"]:
            reference = binding.get("slot", {})
            if reference.get("kind") == "LegacySlotRefV2":
                reference = reference.get("value", {})
            if (
                reference.get("namespace") == "SuffixLive"
                and isinstance(reference.get("slot"), int)
            ):
                suffix_slot_types[("SuffixLive", reference["slot"])] = binding["type"]
        for member in value.values():
            validate_authority_bearing_usages(
                member,
                slot_types=suffix_slot_types,
                disposition=disposition,
                operation_argument_types=operation_argument_types,
            )
        return

    if {
        "operation", "disposition_binder", "computation",
    } <= set(value):
        binder = value["disposition_binder"]
        for key, member in value.items():
            validate_authority_bearing_usages(
                member,
                slot_types=slot_types,
                disposition=(binder["slot"], binder["type"]),
                operation_argument_types=operation_argument_types,
            )
        return

    local_operation_types = operation_argument_types
    if isinstance(value.get("actual_arguments"), list):
        local_operation_types = [
            summary["type"]
            for summary in value["actual_arguments"]
            if isinstance(summary, dict) and isinstance(summary.get("type"), dict)
        ]
    for member in value.values():
        validate_authority_bearing_usages(
            member,
            slot_types=slot_types,
            disposition=disposition,
            operation_argument_types=local_operation_types,
        )


def substitute_contract_kind(kind: dict[str, Any], substitution: dict[str, Any]) -> dict[str, Any]:
    type_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["type_arguments"]}
    owner_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["owner_arguments"]}
    identity_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["identity_arguments"]}
    clock_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["clock_arguments"]}
    contract_arguments = {entry["binder_slot"]: entry["contract"] for entry in substitution["contract_arguments"]}
    row_arguments = {entry["binder_slot"]: entry["value"] for entry in substitution["row_arguments"]}

    namespaces = {"Type", "Row", "Contract", "Owner", "Identity", "Clock"}

    def collect_slots(
        value: Any,
        destination: dict[str, set[int]],
    ) -> None:
        if isinstance(value, list):
            for member in value:
                collect_slots(member, destination)
            return
        if not isinstance(value, dict):
            return
        if set(value) == {"namespace", "slot"}:
            namespace = value.get("namespace")
            slot_number = value.get("slot")
            if namespace in destination and isinstance(slot_number, int):
                destination[namespace].add(slot_number)
        tag = value.get("kind")
        if isinstance(tag, str) and tag in {
            "TypeParameterV1", "TypeParameterV2",
        } and isinstance(
            value.get("slot"), int,
        ):
            destination["Type"].add(value["slot"])
        if tag == "HandlerEntryParameterV1" and isinstance(
            value.get("contract_slot"), int,
        ):
            destination["Contract"].add(value["contract_slot"])
        if (
            set(value) == {"slot", "kind"}
            and isinstance(value.get("kind"), dict)
            and isinstance(value.get("slot"), int)
        ):
            destination["Contract"].add(value["slot"])
        if tag == "ForAllOwnerTypeV2":
            binder = value.get("binder", {})
            if isinstance(binder.get("owner_slot"), int):
                destination["Owner"].add(binder["owner_slot"])
        elif tag == "ForAllContractTypeV2":
            binder = value.get("binder", {})
            if isinstance(binder.get("contract_slot"), int):
                destination["Contract"].add(binder["contract_slot"])
        elif tag == "ForAllIdentityTypeV2":
            binder = value.get("binder", {})
            if isinstance(binder.get("identity_slot"), int):
                destination["Identity"].add(binder["identity_slot"])
            refinement = binder.get("clock_refinement")
            if isinstance(refinement, dict) and isinstance(
                refinement.get("clock_slot"), int,
            ):
                destination["Clock"].add(refinement["clock_slot"])
        elif tag == "ExistsClockPackageTypeV2":
            clock_binder = value.get("clock_binder", {})
            if isinstance(clock_binder.get("identity_slot"), int):
                destination["Identity"].add(clock_binder["identity_slot"])
            refinement = clock_binder.get("clock_refinement", {})
            if isinstance(refinement.get("clock_slot"), int):
                destination["Clock"].add(refinement["clock_slot"])
            summary = value.get("summary_binder", {})
            if isinstance(summary.get("contract_slot"), int):
                destination["Contract"].add(summary["contract_slot"])
        signature_fields = {
            "type_binders", "parameters", "result", "mode", "transition",
            "suspension", "result_transformer", "required_phase",
            "obligation_ids", "secondary_sites",
        }
        if signature_fields <= set(value):
            for binder in value["type_binders"]:
                if isinstance(binder.get("slot"), int):
                    destination["Type"].add(binder["slot"])
        for member in value.values():
            collect_slots(member, destination)

    used_slots = {namespace: set() for namespace in namespaces}
    collect_slots(kind, used_slots)
    collect_slots(substitution, used_slots)
    capture_slots = {namespace: set() for namespace in namespaces}
    for field in (
        "type_arguments", "owner_arguments", "identity_arguments",
        "clock_arguments", "contract_arguments", "row_arguments",
    ):
        for entry in substitution[field]:
            collect_slots(
                entry.get("value", entry.get("contract")), capture_slots,
            )

    def fresh_slot(namespace: str) -> int:
        candidate = 0
        while candidate in used_slots[namespace]:
            candidate += 1
        reject(candidate > U32_MAX, "contract-component-kind-mismatch")
        used_slots[namespace].add(candidate)
        return candidate

    def nested_renames(
        renames: dict[str, dict[int, int]],
        namespace: str,
        old_slot: int,
    ) -> tuple[dict[str, dict[int, int]], int]:
        new_slot = (
            fresh_slot(namespace)
            if old_slot in capture_slots[namespace]
            else old_slot
        )
        nested = {
            name: dict(bindings) for name, bindings in renames.items()
        }
        nested[namespace][old_slot] = new_slot
        return nested, new_slot

    def replace(
        value: Any,
        *,
        expected_kind: str = "Type",
        renames: dict[str, dict[int, int]] | None = None,
    ) -> Any:
        renames = renames or {namespace: {} for namespace in namespaces}
        if isinstance(value, list):
            return [
                replace(
                    member,
                    expected_kind=expected_kind,
                    renames=renames,
                )
                for member in value
            ]
        if not isinstance(value, dict):
            return value
        if value.get("artifact") == "FunctionContractV2":
            return copy.deepcopy(value)

        tag = value.get("kind")
        if tag == "ForAllOwnerTypeV2":
            binder = value["binder"]
            nested, owner_slot = nested_renames(
                renames, "Owner", binder["owner_slot"],
            )
            return {
                "kind": tag,
                "binder": {"owner_slot": owner_slot},
                "body": replace(value["body"], renames=nested),
            }
        if tag == "ForAllContractTypeV2":
            binder = value["binder"]
            binder_kind_value = replace(binder["kind"], renames=renames)
            nested, contract_slot = nested_renames(
                renames, "Contract", binder["contract_slot"],
            )
            return {
                "kind": tag,
                "binder": {
                    "contract_slot": contract_slot,
                    "kind": binder_kind_value,
                },
                "body": replace(value["body"], renames=nested),
            }
        if tag == "ForAllIdentityTypeV2":
            binder = value["binder"]
            nested, identity_slot = nested_renames(
                renames, "Identity", binder["identity_slot"],
            )
            refinement = binder["clock_refinement"]
            replaced_refinement = None
            if refinement is not None:
                nested, clock_slot = nested_renames(
                    nested, "Clock", refinement["clock_slot"],
                )
                replaced_refinement = {
                    "clock_slot": clock_slot,
                    "identity": replace(
                        refinement["identity"], renames=nested,
                    ),
                }
            return {
                "kind": tag,
                "binder": {
                    "identity_slot": identity_slot,
                    "clock_refinement": replaced_refinement,
                    "family": replace(
                        binder["family"],
                        expected_kind="Effect",
                        renames=renames,
                    ),
                    "owner": replace(binder["owner"], renames=renames),
                },
                "body": replace(value["body"], renames=nested),
            }
        if tag == "ExistsClockPackageTypeV2":
            clock_binder = value["clock_binder"]
            nested, identity_slot = nested_renames(
                renames, "Identity", clock_binder["identity_slot"],
            )
            refinement = clock_binder["clock_refinement"]
            nested, clock_slot = nested_renames(
                nested, "Clock", refinement["clock_slot"],
            )
            summary = value["summary_binder"]
            summary_kind = replace(summary["kind"], renames=nested)
            body_renames, contract_slot = nested_renames(
                nested, "Contract", summary["contract_slot"],
            )
            return {
                "kind": tag,
                "clock_binder": {
                    "identity_slot": identity_slot,
                    "clock_refinement": {
                        "clock_slot": clock_slot,
                        "identity": replace(
                            refinement["identity"], renames=nested,
                        ),
                    },
                    "family_witness": replace(
                        clock_binder["family_witness"], renames=renames,
                    ),
                    "owner": replace(
                        clock_binder["owner"], renames=renames,
                    ),
                },
                "summary_binder": {
                    "contract_slot": contract_slot,
                    "kind": summary_kind,
                },
                "body": replace(value["body"], renames=body_renames),
            }

        signature_fields = {
            "type_binders", "parameters", "result", "mode", "transition",
            "suspension", "result_transformer", "required_phase",
            "obligation_ids", "secondary_sites",
        }
        if signature_fields <= set(value):
            nested = renames
            replaced_binders = []
            for binder in value["type_binders"]:
                nested, type_slot = nested_renames(
                    nested, "Type", binder["slot"],
                )
                replaced_binders.append(
                    {"slot": type_slot, "kind": binder["kind"]}
                )
            return {
                key: (
                    replaced_binders
                    if key == "type_binders"
                    else replace(
                        member,
                        expected_kind=(
                            "Effect" if key == "family" else "Type"
                        ),
                        renames=nested,
                    )
                )
                for key, member in value.items()
            }

        if tag == "LegacyTypeRefV2" and isinstance(
            value.get("value"), dict,
        ) and value["value"].get("kind") == "TypeParameterV1":
            slot_number = value["value"].get("slot")
            if slot_number in renames["Type"]:
                return {
                    "kind": tag,
                    "value": {
                        "kind": "TypeParameterV1",
                        "slot": renames["Type"][slot_number],
                    },
                }
            if slot_number not in type_arguments:
                return copy.deepcopy(value)
            argument = copy.deepcopy(type_arguments[slot_number])
            if expected_kind == "Effect" and argument.get(
                "kind"
            ) == "LegacyTypeRefV2":
                return copy.deepcopy(argument["value"])
            return argument
        if isinstance(tag, str) and tag in {
            "TypeParameterV1", "TypeParameterV2",
        }:
            slot_number = value.get("slot")
            if slot_number in renames["Type"]:
                return {"kind": tag, "slot": renames["Type"][slot_number]}
            if slot_number not in type_arguments:
                return copy.deepcopy(value)
            argument = copy.deepcopy(type_arguments[value["slot"]])
            if tag == "TypeParameterV1":
                if argument.get("kind") == "LegacyTypeRefV2":
                    return copy.deepcopy(argument["value"])
                if argument.get("kind") == "TypeParameterV2":
                    return {
                        "kind": "TypeParameterV1",
                        "slot": argument["slot"],
                    }
            if expected_kind == "Effect" and argument.get("kind") == "LegacyTypeRefV2":
                return copy.deepcopy(argument["value"])
            return argument
        if tag == "TailV1":
            row_slot = value.get("row_slot", {})
            if row_slot.get("slot") in renames["Row"]:
                return {
                    "kind": tag,
                    "row_slot": {
                        "namespace": "Row",
                        "slot": renames["Row"][row_slot["slot"]],
                    },
                }
            if row_slot.get("namespace") == "Row" and row_slot.get("slot") in row_arguments:
                return copy.deepcopy(row_arguments[row_slot["slot"]])
        if set(value) == {"namespace", "slot"}:
            namespace = value["namespace"]
            if namespace in renames and value["slot"] in renames[namespace]:
                return {
                    "namespace": namespace,
                    "slot": renames[namespace][value["slot"]],
                }
            table = {"Owner": owner_arguments, "Identity": identity_arguments, "Clock": clock_arguments}.get(value["namespace"])
            if table is not None and value["slot"] in table:
                return copy.deepcopy(table[value["slot"]])
        if tag == "ContractParameterRefV2":
            parameter = value.get("parameter", {})
            slot_number = parameter.get("slot")
            if slot_number in renames["Contract"]:
                return {
                    "kind": tag,
                    "parameter": {
                        "slot": renames["Contract"][slot_number],
                        "kind": replace(
                            parameter["kind"], renames=renames,
                        ),
                    },
                }
            if slot_number in contract_arguments:
                return copy.deepcopy(contract_arguments[slot_number])
        if isinstance(value.get("kind"), dict) and isinstance(
            value.get("slot"), int,
        ):
            if value["slot"] in renames["Contract"]:
                return {
                    "slot": renames["Contract"][value["slot"]],
                    "kind": replace(value["kind"], renames=renames),
                }
            if value["slot"] in contract_arguments:
                return copy.deepcopy(contract_arguments[value["slot"]])
        if tag == "HandlerEntryParameterV1":
            contract_slot = value.get("contract_slot")
            if contract_slot in renames["Contract"]:
                return {
                    "kind": tag,
                    "contract_slot": renames["Contract"][contract_slot],
                }
        return {
            key: replace(
                member,
                expected_kind="Effect" if key == "family" else "Type",
                renames=renames,
            )
            for key, member in value.items()
        }

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


def validate_instantiated_selector_scope(
    application: dict[str, Any],
    *,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    type_parameter_kinds: dict[int, str],
    identity_binders: dict[int, dict[str, Any]],
    handler_contract_binders: set[int],
) -> None:
    """Resolve an application's substituted identity domain and visible row."""

    kind, target = resolve_contract_target(
        application["contract"], imports, contract_binders, local_functions,
    )
    substitution = application["substitution"]
    if target is not None:
        target_identities = {
            binder["identity_slot"]: binder
            for binder in target["binders"]["identity_binders"]
        }
        for argument in substitution["identity_arguments"]:
            actual = argument["value"]
            actual_slot = actual["slot"]
            reject(
                actual.get("namespace") != "Identity"
                or actual_slot not in identity_binders,
                "contract-projection-escapes-scope",
            )
            expected_family = substitute_contract_kind(
                {"family": target_identities[argument["binder_slot"]]["family"]},
                substitution,
            )["family"]
            validate_effect_family_ref(expected_family, type_parameter_kinds)
            reject(
                identity_binders[actual_slot]["family"] != expected_family,
                "contract-component-kind-mismatch",
            )
    instantiated = substitute_contract_kind(kind, substitution)
    validate_row_selector_scope(
        instantiated["visible_row"],
        type_parameter_kinds=type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )


def validate_lexical_application_instantiations(
    value: Any,
    *,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    type_parameter_kinds: dict[int, str],
    identity_binders: dict[int, dict[str, Any]],
    handler_contract_binders: set[int],
    _root: bool = True,
) -> None:
    """Check every nested application under the current declaration scope."""

    if isinstance(value, list):
        for member in value:
            validate_lexical_application_instantiations(
                member,
                imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                type_parameter_kinds=type_parameter_kinds,
                identity_binders=identity_binders,
                handler_contract_binders=handler_contract_binders,
                _root=False,
            )
        return
    if not isinstance(value, dict):
        return
    if value.get("artifact") == "FunctionContractV2" or (
        not _root and set(value) == HANDLER_CONTRACT_FIELDS
    ):
        return
    application_fields = {
        "application_slot", "contract", "callee_summary", "actual_arguments",
        "substitution", "entry_world", "origin",
    }
    if set(value) == application_fields:
        validate_instantiated_selector_scope(
            value,
            imports=imports,
            contract_binders=contract_binders,
            local_functions=local_functions,
            type_parameter_kinds=type_parameter_kinds,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
        )
        return
    for member in value.values():
        validate_lexical_application_instantiations(
            member,
            imports=imports,
            contract_binders=contract_binders,
            local_functions=local_functions,
            type_parameter_kinds=type_parameter_kinds,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
            _root=False,
        )


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
    row_binders: dict[int, dict[str, Any]] | None = None,
    type_parameter_kinds: dict[int, str] | None = None,
    identity_binders: dict[int, dict[str, Any]] | None = None,
    handler_contract_binders: set[int] | None = None,
    declaration_scope: DeclarationScope | None = None,
) -> None:
    returns = returns or {}
    applications = applications or {}
    imports = imports or ImportScope()
    contract_binders = contract_binders or {}
    local_functions = local_functions or {}
    row_binders = row_binders or {}
    type_parameter_kinds = type_parameter_kinds or {}
    declaration_scope = declaration_scope or DeclarationScope(
        type_parameter_kinds=type_parameter_kinds,
        row_binders=row_binders,
        contract_binders=contract_binders,
        identity_binders=identity_binders or {},
        handler_contract_binders=handler_contract_binders or set(),
    )
    exact_fields(application, {"application_slot", "contract", "callee_summary", "actual_arguments", "substitution", "entry_world", "origin"}, "AppliedContractV2")
    validate_u32(application["application_slot"], "AppliedContractV2 application_slot")
    validate_contract_ref(
        application["contract"], returns, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
    validate_value_summary(
        application["callee_summary"], returns, applications=applications,
        imports=imports, contract_binders=contract_binders,
        local_functions=local_functions, defer_function_contract_shape=True,
        declaration_scope=declaration_scope,
    )
    for summary in application["actual_arguments"]:
        validate_value_summary(
            summary, returns, applications=applications, imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            declaration_scope=declaration_scope,
        )
    validate_operation_argument_scope(
        application["actual_arguments"], len(application["actual_arguments"]),
    )
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
        validate_type_v2(entry["value"], returns=returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    for entry in substitution["row_arguments"]:
        validate_row_expr(entry["value"])
        validate_row_selector_scope(
            entry["value"],
            type_parameter_kinds=declaration_scope.type_parameter_kinds,
            identity_binders=declaration_scope.identity_binders,
            handler_contract_binders=(
                declaration_scope.handler_contract_binders
            ),
        )
        validate_lexical_row_scope(
            entry["value"], row_binders=declaration_scope.row_binders,
        )
    for entry in substitution["contract_arguments"]:
        validate_contract_ref(entry["contract"], returns, imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    for field, namespace in (("owner_arguments", "Owner"), ("identity_arguments", "Identity"), ("clock_arguments", "Clock")):
        for entry in substitution[field]:
            validate_slot_v1(entry["value"], namespace)
            active_slots = {
                "Owner": declaration_scope.owner_binders,
                "Identity": declaration_scope.identity_binders,
                "Clock": declaration_scope.clock_binders,
            }[namespace]
            if declaration_scope.enforce_ordinary_slots:
                reject(
                    entry["value"]["slot"] not in active_slots,
                    "contract-projection-escapes-scope",
                )

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
        if declaration_scope.enforce_ordinary_slots:
            owner_arguments = {
                entry["binder_slot"]: entry["value"]
                for entry in substitution["owner_arguments"]
            }
            identity_arguments = {
                entry["binder_slot"]: entry["value"]
                for entry in substitution["identity_arguments"]
            }
            caller_identities = declaration_scope.identity_binders
            caller_clocks = declaration_scope.clock_binders
            target_identities = {
                binder["identity_slot"]: binder
                for binder in binders["identity_binders"]
            }
            target_clocks = {
                binder["slot"]: binder
                for binder in binders["clock_binders"]
            }
            for formal_slot, actual in identity_arguments.items():
                expected_owner = owner_arguments[
                    target_identities[formal_slot]["owner"]["slot"]
                ]
                reject(
                    caller_identities[actual["slot"]]["owner"]
                    != expected_owner,
                    "contract-component-kind-mismatch",
                )
            for argument in substitution["clock_arguments"]:
                formal = target_clocks[argument["binder_slot"]]
                actual = caller_clocks[argument["value"]["slot"]]
                reject(
                    actual["identity"]
                    != identity_arguments[formal["identity"]["slot"]]
                    or actual["owner"]
                    != owner_arguments[formal["owner"]["slot"]],
                    "contract-component-kind-mismatch",
                )
    else:
        reject(
            any(substitution[field] for field in substitution),
            "contract-parameter-inconsistent-instantiation",
        )

    instantiated = substitute_contract_kind(kind, substitution)
    reject(
        instantiated.get("kind") != "FunctionContractKindV2"
        or set(instantiated)
        != {"kind", "parameter_type", "result_type", "visible_row"},
        "contract-component-kind-mismatch",
    )
    validate_type_v2(
        instantiated["parameter_type"],
        returns=returns,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
    validate_type_v2(
        instantiated["result_type"],
        returns=returns,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
        declaration_scope=declaration_scope,
    )
    validate_row_expr(instantiated["visible_row"])
    validate_instantiated_selector_scope(
        application,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
        type_parameter_kinds=declaration_scope.type_parameter_kinds,
        identity_binders=declaration_scope.identity_binders,
        handler_contract_binders=(
            declaration_scope.handler_contract_binders
        ),
    )
    validate_lexical_row_scope(
        instantiated["visible_row"],
        row_binders=declaration_scope.row_binders,
    )
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
    if target is not None:
        validate_concrete_application_call_obligations(
            application, target, caller_row_binders=row_binders,
        )


def validate_function_contract(
    contract: dict[str, Any],
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    validate_wire_u32_fields(contract)
    validate_source_origins(contract)
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    exact_fields(contract, {"artifact", "profile", "schema_version", "declaration_kind", "binders", "applications", "computation", "closure_environment"}, "FunctionContractV2")
    require(contract.get("artifact") == "FunctionContractV2", "not a FunctionContractV2")
    require(contract.get("profile") == PROFILE and contract.get("schema_version") == 2, "wrong FunctionContractV2 profile")
    require("declaration_kind" in contract, "FunctionContractV2 declaration_kind missing")
    closure_environment = validate_contract_list(contract["closure_environment"])
    for binding in closure_environment:
        binding = validate_contract_object(binding)
        reject(
            set(binding) != {"slot", "type", "provenance", "capture"},
            "contract-component-kind-mismatch",
        )
        validate_slot_v1(binding["slot"], "ClosureCapture")
    binders = contract["binders"]
    validate_declaration_binders(binders, closure_environment)
    contract_binders = {binder["slot"]: binder for binder in binders.get("contract_binders", [])}
    identity_binders = {
        binder["identity_slot"]: binder
        for binder in binders["identity_binders"]
    }
    handler_contract_binders = {
        binder["slot"]
        for binder in binders["contract_binders"]
        if binder.get("kind") == "HandlerContractBinderV2"
    }
    ambient_type_parameters = {
        binder["slot"]: binder["kind"]
        for binder in binders["type_binders"]
    }
    row_binders = {
        binder["slot"]: binder for binder in binders["row_binders"]
    }
    owner_binders = {
        binder["slot"]: binder for binder in binders["owner_binders"]
    }
    clock_binders = {
        binder["slot"]: binder for binder in binders["clock_binders"]
    }
    parameter_binders = {
        binder["slot"] for binder in binders["parameter_binders"]
    }
    closure_capture_binders = {
        binding["slot"]["slot"] for binding in closure_environment
    }
    declaration_scope = DeclarationScope(
        type_parameter_kinds=ambient_type_parameters,
        row_binders=row_binders,
        contract_binders=contract_binders,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
        owner_binders=owner_binders,
        clock_binders=clock_binders,
        prompt_binders={
            binder["prompt_slot"] for binder in binders["prompt_binders"]
        },
        parameter_binders=parameter_binders,
        closure_capture_binders=closure_capture_binders,
    )
    validate_kinded_type_parameter_scope(
        [
            contract["declaration_kind"], binders["parameter_binders"],
            binders["contract_binders"], closure_environment,
            contract["applications"], contract["computation"],
        ],
        ambient_type_parameters,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
    )
    declaration_kind = contract["declaration_kind"]
    if declaration_kind is not None:
        declaration_kind = validate_contract_object(declaration_kind)
        reject(
            declaration_kind.get("kind") != "FunctionContractKindV2",
            "contract-component-kind-mismatch",
        )
        reject(
            set(declaration_kind)
            != {"kind", "parameter_type", "result_type", "visible_row"},
            "contract-component-kind-mismatch",
        )
        validate_row_expr(declaration_kind["visible_row"])
        validate_row_selector_scope(
            declaration_kind["visible_row"],
            type_parameter_kinds=ambient_type_parameters,
            identity_binders=identity_binders,
            handler_contract_binders=handler_contract_binders,
        )
        validate_type_v2(declaration_kind["parameter_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        validate_type_v2(declaration_kind["result_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        reject(
            [parameter["type"] for parameter in binders["parameter_binders"]]
            != application_parameter_types(declaration_kind["parameter_type"]),
            "contract-component-kind-mismatch",
        )
    for binder in contract_binders.values():
        binder_tag = binder.get("kind")
        if binder_tag == "FunctionContractBinderV2":
            reject(
                set(binder)
                != {"kind", "slot", "parameter_type", "result_type", "visible_row"},
                "contract-component-kind-mismatch",
            )
            validate_row_expr(binder["visible_row"])
            validate_row_selector_scope(
                binder["visible_row"],
                type_parameter_kinds=ambient_type_parameters,
                identity_binders=identity_binders,
                handler_contract_binders=handler_contract_binders,
            )
            validate_type_v2(binder["parameter_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
            validate_type_v2(binder["result_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        elif binder_tag == "LaterContractBinderV2":
            reject(
                set(binder)
                != {"kind", "slot", "clock", "payload_type"},
                "contract-component-kind-mismatch",
            )
            validate_scoped_declaration_slot(
                binder["clock"], "Clock", clock_binders,
            )
            validate_type_v2(
                binder["payload_type"], imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                declaration_scope=declaration_scope,
            )
        elif binder_tag == "ContinuationContractBinderV2":
            reject(
                set(binder)
                != {"kind", "slot", "argument_type", "answer_type"},
                "contract-component-kind-mismatch",
            )
            validate_type_v2(
                binder["argument_type"], imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                declaration_scope=declaration_scope,
            )
            validate_type_v2(
                binder["answer_type"], imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                declaration_scope=declaration_scope,
            )
        elif binder_tag == "HandlerContractBinderV2":
            reject(
                set(binder)
                != {"kind", "slot", "family", "input_type", "answer_type"},
                "contract-component-kind-mismatch",
            )
            family = validate_contract_object(binder["family"])
            if family.get("kind") == "LegacyTypeRefV2":
                family = family["value"]
            validate_effect_family_ref(family, ambient_type_parameters)
            validate_type_v2(binder["input_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
            validate_type_v2(binder["answer_type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
        else:
            raise Diagnostic("contract-component-kind-mismatch")
    for parameter in binders.get("parameter_binders", []):
        validate_type_v2(parameter["type"], imports=imports, contract_binders=contract_binders, local_functions=local_functions, declaration_scope=declaration_scope)
    for binding in closure_environment:
        validate_environment_binding(
            binding, {}, imports=imports, contract_binders=contract_binders,
            local_functions=local_functions,
            declaration_scope=declaration_scope,
        )
    validate_operation_argument_scope(closure_environment, 0)
    parameter_scope = parameter_binders
    closure_scope = closure_capture_binders
    slot_scopes = {
        "Parameter": parameter_scope,
        "ClosureCapture": closure_scope,
        "Type": {binder["slot"] for binder in binders["type_binders"]},
        "Contract": {
            binder["slot"] for binder in binders["contract_binders"]
        },
        "Owner": {binder["slot"] for binder in binders["owner_binders"]},
        "Identity": {
            binder["identity_slot"] for binder in binders["identity_binders"]
        },
        "Clock": {binder["slot"] for binder in binders["clock_binders"]},
        "Row": {binder["slot"] for binder in binders["row_binders"]},
        "Prompt": {
            binder["prompt_slot"] for binder in binders["prompt_binders"]
        },
    }
    validate_lexical_effect_selector_scope(
        [
            contract["declaration_kind"], binders["parameter_binders"],
            binders["row_binders"], binders["contract_binders"],
            contract["closure_environment"], contract["applications"],
            contract["computation"],
        ],
        type_parameter_kinds=ambient_type_parameters,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    applications = validate_application_ledger(
        contract["applications"], returns={}, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
        type_parameter_kinds=ambient_type_parameters,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    validate_computation(
        contract["computation"], applications, context="function", imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    validate_lexical_application_instantiations(
        [
            contract["declaration_kind"], binders["parameter_binders"],
            binders["contract_binders"], contract["closure_environment"],
            contract["applications"], contract["computation"],
        ],
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
        type_parameter_kinds=ambient_type_parameters,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    validate_lexical_slot_scope(
        [
            contract["declaration_kind"], binders["parameter_binders"],
            binders["contract_binders"], contract["closure_environment"],
            contract["applications"], contract["computation"],
        ],
        slot_scopes=slot_scopes,
    )
    validate_authority_bearing_usages(contract)
    validate_function_suffix_projections(contract)


def validate_handler_contract(
    contract: dict[str, Any],
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
    nearest_outer_prompt_slot: int | None = None,
    type_parameter_kinds: dict[int, str] | None = None,
    row_binders: dict[int, dict[str, Any]] | None = None,
    contract_binders: dict[int, dict[str, Any]] | None = None,
    identity_binders: dict[int, dict[str, Any]] | None = None,
    handler_contract_binders: set[int] | None = None,
    owner_binders: dict[int, dict[str, Any]] | None = None,
    clock_binders: dict[int, dict[str, Any]] | None = None,
    prompt_binders: set[int] | None = None,
    parameter_binders: set[int] | None = None,
    closure_capture_binders: set[int] | None = None,
) -> None:
    validate_wire_u32_fields(contract)
    validate_source_origins(contract)
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    type_parameter_kinds = type_parameter_kinds or {}
    row_binders = row_binders or {}
    contract_binders = contract_binders or {}
    identity_binders = identity_binders or {}
    handler_contract_binders = handler_contract_binders or set()
    prompt_scope_provided = prompt_binders is not None
    ordinary_scope_provided = any(
        scope is not None
        for scope in (
            owner_binders,
            clock_binders,
            parameter_binders,
            closure_capture_binders,
        )
    )
    owner_binders = owner_binders or {}
    clock_binders = clock_binders or {}
    prompt_binders = prompt_binders or set()
    parameter_binders = parameter_binders or set()
    closure_capture_binders = closure_capture_binders or set()
    declaration_scope = DeclarationScope(
        type_parameter_kinds=type_parameter_kinds,
        row_binders=row_binders,
        contract_binders=contract_binders,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
        owner_binders=owner_binders,
        clock_binders=clock_binders,
        prompt_binders=prompt_binders,
        parameter_binders=parameter_binders,
        closure_capture_binders=closure_capture_binders,
        enforce_ordinary_slots=ordinary_scope_provided,
    )
    exact_fields(contract, {"handled_entry", "prompt_slot", "residual_row", "attributed_demand", "suspension", "semantic_summary", "required_phase", "handler_environment", "applications", "return_computation", "clause_computations"}, "HandlerContractV2")
    validate_kinded_type_parameter_scope(
        contract,
        type_parameter_kinds,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
    )
    validate_u32(contract["prompt_slot"], "HandlerContractV2 prompt_slot")
    if prompt_scope_provided:
        reject(
            contract["prompt_slot"] not in prompt_binders,
            "contract-projection-escapes-scope",
        )
    else:
        # A standalone HandlerContractV2 decoder receives the installation
        # prompt as its root scope.  Complete FunctionContractV2 roots still
        # have to resolve that prompt through DeclarationBindersV2.
        declaration_scope.prompt_binders = {contract["prompt_slot"]}
    validate_effect_entry_selector(
        contract["handled_entry"],
        type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    validate_row_expr(contract["residual_row"])
    validate_row_selector_scope(
        contract["residual_row"],
        type_parameter_kinds=type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    validate_lexical_effect_selector_scope(
        contract,
        type_parameter_kinds=type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    validate_lexical_row_scope(contract, row_binders=row_binders)
    if ordinary_scope_provided:
        validate_lexical_slot_scope(
            contract,
            slot_scopes={
                "Parameter": parameter_binders,
                "ClosureCapture": closure_capture_binders,
                "Type": set(type_parameter_kinds),
                "Contract": set(contract_binders),
                "Owner": set(owner_binders),
                "Identity": set(identity_binders),
                "Clock": set(clock_binders),
                "Row": set(row_binders),
                "Prompt": declaration_scope.prompt_binders,
            },
        )
    for binding in contract["handler_environment"]:
        validate_environment_binding(
            binding, {}, imports=imports, contract_binders=contract_binders,
            local_functions=local_functions,
            declaration_scope=declaration_scope,
        )
    validate_summary_normal_form(contract["semantic_summary"])
    validate_phase_requirement(contract["required_phase"])
    applications = validate_application_ledger(
        contract["applications"], returns={}, imports=imports,
        contract_binders=contract_binders, local_functions=local_functions,
        row_binders=row_binders,
        type_parameter_kinds=type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
        declaration_scope=declaration_scope,
    )
    validate_computation(
        contract["return_computation"], applications, context="handler_return",
        imports=imports, contract_binders=contract_binders,
        local_functions=local_functions, row_binders=row_binders,
        declaration_scope=declaration_scope,
    )
    seen_operations: set[str] = set()
    for clause in contract["clause_computations"]:
        exact_fields(clause, {"operation", "disposition_binder", "computation"}, "ClauseComputationV2")
        validate_operation_selector(clause["operation"])
        if clause["operation"]["kind"] == "ExactOperationV1" and "family" in contract["handled_entry"]:
            reject(
                clause["operation"]["family"] != contract["handled_entry"]["family"],
                "forward-operation-mismatch",
            )
        operation_key = jcs(clause["operation"])
        require(operation_key not in seen_operations, "duplicate HandlerContractV2 operation")
        seen_operations.add(operation_key)
        disposition = clause["disposition_binder"]
        exact_fields(disposition, {"slot", "site_slot", "type"}, "ClauseDispositionBinderV2")
        validate_u32(disposition["slot"], "ClauseDispositionBinderV2 slot")
        validate_u32(disposition["site_slot"], "ClauseDispositionBinderV2 site_slot")
        validate_type_v2(
            disposition["type"], imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            declaration_scope=declaration_scope,
        )
        require(disposition["type"].get("kind") == "ResumeTypeRefV2", "ClauseDispositionBinderV2 type")
        validate_computation(
            clause["computation"], applications, context="handler_clause", imports=imports,
            contract_binders=contract_binders, local_functions=local_functions,
            row_binders=row_binders, disposition_binder=disposition,
            clause_operation=clause["operation"], handled_entry=contract["handled_entry"],
            handler_prompt_slot=contract["prompt_slot"],
            nearest_outer_prompt_slot=nearest_outer_prompt_slot,
            declaration_scope=declaration_scope,
        )
    validate_lexical_application_instantiations(
        contract,
        imports=imports,
        contract_binders=contract_binders,
        local_functions=local_functions,
        type_parameter_kinds=type_parameter_kinds,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
    )
    handler_slot_types = {
        (binding["slot"]["namespace"], binding["slot"]["slot"]): binding["type"]
        for binding in contract["handler_environment"]
    }
    validate_authority_bearing_usages(
        contract, slot_types=handler_slot_types,
    )
    validate_handler_suffix_projections(contract)


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


def symbolic_return_paths(computation: dict[str, Any]) -> list[dict[str, Any]]:
    """Project reachable Returns without resolving abstract Invoke targets."""

    kind = computation["kind"]
    if kind in {"LiteralPathsV2", "CurrentDispositionPathsV2"}:
        return [
            copy.deepcopy(path)
            for path in computation["paths"]
            if path["outcome"]["kind"] == "ReturnsV2"
        ]
    if kind == "JoinV2":
        return [
            path
            for member in computation["members"]
            for path in symbolic_return_paths(member)
        ]
    if kind == "PathBindV2":
        binder = computation["return_binder"]
        world = binder["world"]
        prefix_transition = (
            world["transition"]
            if world.get("kind") == "ApplyWorldTransitionV2"
            else {"kind": "SameWorldV1"}
        )
        result = []
        for path in symbolic_return_paths(computation["continuation"]):
            path = substitute_return_binder(path, binder)
            path["outcome"]["transition"] = compose_transition(
                prefix_transition, path["outcome"]["transition"],
            )
            result.append(path)
        return result
    if kind == "InvokeV2":
        return []
    raise Diagnostic("unknown-contract-computation-variant")


def source_return_paths(
    source: dict[str, Any],
    *,
    imports: ImportScope,
    local_functions: LocalFunctionScope,
    contract_environment: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    contract_slots = {
        binder["slot"] for binder in source["binders"]["contract_binders"]
    }
    if not contract_slots <= set(contract_environment):
        return symbolic_return_paths(source["computation"])
    evaluated = evaluate_contract_computation(
        source, imports=imports, local_functions=local_functions,
        contract_environment=contract_environment,
    )
    return [
        item["path"]
        for item in evaluated
        if item["path"]["outcome"]["kind"] == "ReturnsV2"
    ]


def instantiate_source_result(
    source: dict[str, Any],
    application: dict[str, Any],
    path: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    outcome = path["outcome"]
    transformer = outcome["result_transformer"]
    if transformer["kind"] == "LegacyResultTransformerV2":
        value = transformer["value"]
        provenance = {"kind": "LegacyProvenanceExprV2", "value": value["provenance"]}
        capture = {"kind": "LegacyCaptureExprV2", "value": value["capture"]}
    else:
        provenance = copy.deepcopy(transformer["provenance"])
        capture = copy.deepcopy(transformer["capture"])
    provenance = substitute_term_actuals(provenance, source, application)
    capture = substitute_term_actuals(capture, source, application)
    result_type = copy.deepcopy(source["declaration_kind"]["result_type"])
    if result_type.get("kind") == "TypeParameterV2":
        argument = next(item for item in application["substitution"]["type_arguments"] if item["binder_slot"] == result_type["slot"])
        result_type = copy.deepcopy(argument["value"])
    return result_type, outcome["transition"], provenance, capture


def validate_application_return_binder(
    source: dict[str, Any],
    application: dict[str, Any],
    binder: dict[str, Any],
    *,
    imports: ImportScope | None = None,
    local_functions: LocalFunctionScope | None = None,
) -> None:
    imports = imports or ImportScope()
    local_functions = local_functions or {}
    contract_environment: dict[int, dict[str, Any]] = {}
    for entry in application["substitution"]["contract_arguments"]:
        actual = entry["contract"]
        if actual["kind"] == "ImportedFunctionRefV2":
            contract_environment[entry["binder_slot"]] = imports[actual["artifact_hash"]]
        elif actual["kind"] == "LocalFunctionRefV2":
            contract_environment[entry["binder_slot"]] = local_functions[actual["declaration_slot"]]
    paths = source_return_paths(
        source, imports=imports, local_functions=local_functions,
        contract_environment=contract_environment,
    )
    require(paths, "concrete application source has no ReturnsV2 path")
    for path in paths:
        result_type, transition, provenance, capture = instantiate_source_result(
            source, application, path,
        )
        reject(
            binder["type"] != result_type
            or binder["provenance"] != provenance
            or binder["capture"] != capture,
            "contract-parameter-inconsistent-instantiation",
        )
        expected_world = {
            "kind": "ApplyWorldTransitionV2",
            "input": {
                "application_slot": application["application_slot"],
                "kind": "ApplicationEntryWorldV2",
            },
            "transition": transition,
        }
        reject(
            binder["world"] != expected_world,
            "contract-parameter-inconsistent-instantiation",
        )


def validate_application_return_lineage(application: dict[str, Any], binder: dict[str, Any]) -> None:
    """Keep even abstract ContractParameter projections tied to their call entry."""
    expected_slot = application["application_slot"]
    entry_slots = {
        node["application_slot"]
        for node in walk(binder["world"])
        if isinstance(node, dict) and node.get("kind") == "ApplicationEntryWorldV2"
    }
    reject(entry_slots != {expected_slot}, "contract-parameter-inconsistent-instantiation")


def returning_path_projection(path: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    transformer = path["outcome"]["result_transformer"]
    if transformer["kind"] == "LegacyResultTransformerV2":
        value = transformer["value"]
        reject(value.get("kind") != "ParametricResultV1", "path-bind-literal-prefix-forbidden")
        return (
            {"kind": "LegacyProvenanceExprV2", "value": copy.deepcopy(value["provenance"])},
            {"kind": "LegacyCaptureExprV2", "value": copy.deepcopy(value["capture"])},
        )
    reject(transformer["kind"] != "ParametricResultV2", "path-bind-literal-prefix-forbidden")
    return copy.deepcopy(transformer["provenance"]), copy.deepcopy(transformer["capture"])


def passthrough_return_binders(
    computation: dict[str, Any],
    returns: ReturnScope,
) -> list[dict[str, Any]] | None:
    """Recognize same-world continuations whose result is an existing binder."""

    kind = computation.get("kind")
    if kind in {"LiteralPathsV2", "CurrentDispositionPathsV2"}:
        binders: list[dict[str, Any]] = []
        for path in computation["paths"]:
            outcome = path["outcome"]
            if outcome.get("kind") != "ReturnsV2":
                continue
            if outcome.get("transition") != {"kind": "SameWorldV1"}:
                return None
            transformer = outcome["result_transformer"]
            return_slot = None
            if transformer.get("kind") == "ReturnBoundResultV2":
                return_slot = transformer.get("return_slot")
            elif transformer.get("kind") == "ParametricResultV2":
                provenance = transformer.get("provenance", {})
                capture = transformer.get("capture", {})
                if (
                    provenance.get("kind") == "ReturnProvenanceV2"
                    and capture.get("kind") == "ReturnCaptureV2"
                    and provenance.get("return_slot") == capture.get("return_slot")
                ):
                    return_slot = provenance.get("return_slot")
            if return_slot not in returns:
                return None
            binders.append(returns[return_slot])
        return binders
    if kind == "PathBindV2":
        continuation_returns = dict(returns)
        return_binder = computation["return_binder"]
        continuation_returns[return_binder["slot"]] = return_binder
        return passthrough_return_binders(
            computation["continuation"], continuation_returns,
        )
    if kind == "JoinV2":
        member_results = [
            passthrough_return_binders(member, returns)
            for member in computation["members"]
        ]
        if any(result is None for result in member_results):
            return None
        return [
            binder
            for result in member_results
            for binder in result or []
        ]
    return None


def validate_computation_return_projection(
    computation: dict[str, Any],
    binder: dict[str, Any],
    *,
    applications: ApplicationScope,
    imports: ImportScope,
    contract_binders: dict[int, dict[str, Any]],
    local_functions: LocalFunctionScope,
    disposition_binder: dict[str, Any] | None,
    returns: ReturnScope,
) -> None:
    """Validate the one symbolic ReturnBinder against every returning prefix path."""

    kind = computation["kind"]
    if kind == "InvokeV2":
        application = applications[computation["application_slot"]]
        validate_application_return_lineage(application, binder)
        _, target = resolve_contract_target(
            application["contract"], imports, contract_binders, local_functions,
        )
        if target is not None:
            validate_application_return_binder(
                target, application, binder,
                imports=imports, local_functions=local_functions,
            )
        return
    if kind == "JoinV2":
        for member in computation["members"]:
            validate_computation_return_projection(
                member, binder, applications=applications, imports=imports,
                contract_binders=contract_binders,
                local_functions=local_functions,
                disposition_binder=disposition_binder,
                returns=returns,
            )
        return
    if kind == "PathBindV2":
        continuation_returns = dict(returns)
        return_binder = computation["return_binder"]
        continuation_returns[return_binder["slot"]] = return_binder
        projected_binders = passthrough_return_binders(
            computation["continuation"],
            continuation_returns,
        )
        if projected_binders:
            expected = {key: value for key, value in binder.items() if key != "slot"}
            reject(
                any(
                    {key: value for key, value in projected.items() if key != "slot"}
                    != expected
                    for projected in projected_binders
                ),
                "contract-parameter-inconsistent-instantiation",
            )
            return
        materialized_source = None
        if computation["prefix"]["kind"] == "CurrentDispositionPathsV2":
            reject(disposition_binder is None, "term-actual-source-unavailable")
            materialized_source = {
                "kind": "LegacySlotRefV2",
                "value": slot("SuffixLive", disposition_binder["slot"]),
            }
        continuation = substitute_return_binder(
            computation["continuation"], computation["return_binder"],
            materialized_source=materialized_source,
        )
        validate_computation_return_projection(
            continuation, binder,
            applications=applications, imports=imports,
            contract_binders=contract_binders,
            local_functions=local_functions,
            disposition_binder=disposition_binder,
            returns=returns,
        )
        return
    if kind == "CurrentDispositionPathsV2":
        reject(disposition_binder is None, "path-bind-literal-prefix-forbidden")
        expected_usage = {
            "kind": "LegacyUsageExprV2",
            "value": {
                "slot": slot("SuffixLive", disposition_binder["slot"]),
                "kind": disposition_binder["type"]["value"]["usage"],
            },
        }
        for path in computation["paths"]:
            if path["outcome"]["kind"] != "ReturnsV2":
                continue
            provenance, capture = returning_path_projection(path)
            expected_world = {
                "kind": "LegacyWorldExprV2",
                "value": {"kind": "EntryWorldV1", "site_slot": disposition_binder["site_slot"]},
            }
            reject(
                binder["type"] != disposition_binder["type"]
                or binder["world"] != expected_world
                or binder["provenance"] != provenance
                or binder["capture"] != capture
                or binder["usage"] != expected_usage,
                "contract-parameter-inconsistent-instantiation",
            )
        return
    if kind == "LiteralPathsV2":
        for path in computation["paths"]:
            if path["outcome"]["kind"] != "ReturnsV2":
                continue
            provenance, capture = returning_path_projection(path)
            legacy_provenance = (
                provenance["value"]
                if provenance.get("kind") == "LegacyProvenanceExprV2"
                else None
            )
            reject(
                not isinstance(legacy_provenance, dict)
                or legacy_provenance.get("kind") != "OperationResultProvenanceV1",
                "path-bind-literal-prefix-forbidden",
            )
            site_slot = legacy_provenance["site_slot"]
            matching_sites = [
                site for site in path["LatentSites"]
                if site["site_slot"] == site_slot
            ]
            reject(len(matching_sites) != 1, "path-bind-literal-prefix-forbidden")
            expected_world = {
                "kind": "ApplyWorldTransitionV2",
                "input": {
                    "kind": "LegacyWorldExprV2",
                    "value": {"kind": "EntryWorldV1", "site_slot": site_slot},
                },
                "transition": copy.deepcopy(path["outcome"]["transition"]),
            }
            reject(
                binder["type"] != matching_sites[0]["instantiated_signature"]["result"]
                or binder["world"] != expected_world
                or binder["provenance"] != provenance
                or binder["capture"] != capture,
                "contract-parameter-inconsistent-instantiation",
            )
        return
    raise Diagnostic("unknown-contract-computation-variant")


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
        validate_application_return_binder(source, app, binder, imports=imported)
    for app in apps:
        require(app["contract"]["artifact_hash"] in imported, "Q oracle application import not resolved")
    evaluated = evaluate_contract_computation(oracle["contract"], imports=imported)
    require(len(evaluated) == 1, "Q oracle twice-called Returns contract path count")
    path = evaluated[0]["path"]
    actual_sources = [site["actual_arguments"][0]["source"] for site in path["LatentSites"]]
    reject(
        actual_sources != oracle["expectation"]["evaluated_latent_actual_sources"]
        or [canonical_hash(path)] != oracle["expectation"]["evaluated_path_hashes"],
        "term-actual-substitution-mismatch",
    )


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


def compose_usage(left: list[dict[str, Any]], right: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grades = {"Zero": 0, "Once": 1, "Many": 2}
    legacy: dict[str, dict[str, Any]] = {}
    other: list[dict[str, Any]] = []
    for usage in [*left, *right]:
        if usage.get("kind") != "LegacyUsageExprV2":
            other.append(usage)
            continue
        key = jcs(usage["value"]["slot"])
        if key not in legacy:
            legacy[key] = copy.deepcopy(usage)
            continue
        current = legacy[key]["value"]["kind"]
        incoming = usage["value"]["kind"]
        if current == "Once" and incoming == "Once":
            combined = "Many"
        else:
            combined = max((current, incoming), key=grades.__getitem__)
        legacy[key]["value"]["kind"] = combined
    values = [value for value in legacy.values() if value["value"]["kind"] != "Zero"]
    return sorted(ordered_unique([*values, *other]), key=jcs)


def compose_path_contracts(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    require(left["outcome"]["kind"] == "ReturnsV2", "only ReturnsV2 enters a PathBind continuation")
    outcome = copy.deepcopy(right["outcome"])
    if outcome["kind"] == "ReturnsV2":
        outcome["transition"] = compose_transition(
            left["outcome"]["transition"], outcome["transition"],
        )
    return {
        "LatentSites": sorted(ordered_unique([*left["LatentSites"], *right["LatentSites"]]), key=lambda item: item["site_slot"]),
        "ParametricObligations": sorted(
            ordered_unique([*left["ParametricObligations"], *right["ParametricObligations"]]),
            key=lambda item: (obligation_value(item)["stage"], obligation_value(item)["id"]),
        ),
        "attributed_demand": sorted(ordered_unique([*left["attributed_demand"], *right["attributed_demand"]]), key=jcs),
        "outcome": outcome,
        "required_phase": compose_phase(left["required_phase"], right["required_phase"]),
        "residual_row": compose_row(left["residual_row"], right["residual_row"]),
        "semantic_summary": normalize_summary_sequence(left["semantic_summary"], right["semantic_summary"]),
        "suspension": compose_suspension(left["suspension"], right["suspension"]),
        "usage": compose_usage(left["usage"], right["usage"]),
    }


LOCAL_ID_FIELDS = {
    "site_slot", "park_site_slot", "continuation_site_slot",
    "forward_site_slot", "claim_cell_slot", "port_slot", "prompt_slot",
    "secondary_slot",
}


def collect_local_ids(value: Any) -> set[int]:
    result: set[int] = set()
    for node in walk(value):
        if not isinstance(node, dict):
            continue
        if node.get("stage") in {"Call", "HandlerInstall"} and isinstance(node.get("id"), int):
            result.add(node["id"])
        for key in LOCAL_ID_FIELDS:
            if isinstance(node.get(key), int):
                result.add(node[key])
        for key in ("call_obligation_ids", "install_obligation_ids", "obligation_ids"):
            if isinstance(node.get(key), list):
                result.update(number for number in node[key] if isinstance(number, int))
    return result


class FreshLocalQualifier:
    """Deterministically inject finite application-local ids into the u32 wire domain."""

    def __init__(self, reserved: Iterable[int] = ()) -> None:
        self.used: set[int] = set()
        for number in reserved:
            validate_u32(number, "reserved local id")
            self.used.add(number)
        self.mapping: dict[tuple[int, int], int] = {}
        self.next_candidate = 0

    def qualify(self, application_slot: int, local_id: int) -> int:
        validate_u32(application_slot, "qualification application_slot")
        validate_u32(local_id, "qualification local_id")
        key = application_slot, local_id
        if key not in self.mapping:
            while self.next_candidate in self.used and self.next_candidate <= U32_MAX:
                self.next_candidate += 1
            reject(self.next_candidate > U32_MAX, "qualified-local-id-space-exhausted")
            self.mapping[key] = self.next_candidate
            self.used.add(self.next_candidate)
            self.next_candidate += 1
        return self.mapping[key]


def reserve_application_locals(
    values: Iterable[Any],
    application_slot: int,
    qualifier: FreshLocalQualifier,
) -> None:
    """Allocate one application-wide sorted batch before rewriting any path."""

    local_ids: set[int] = set()
    for value in values:
        local_ids.update(collect_local_ids(value))
    for local_id in sorted(local_ids):
        qualifier.qualify(application_slot, local_id)


def qualify_application_locals(
    value: Any,
    application_slot: int,
    qualifier: FreshLocalQualifier | None = None,
) -> Any:
    qualifier = qualifier or FreshLocalQualifier()

    # Allocation is a semantic batch ordered by local id, never by JSON object
    # member order encountered during the subsequent structural rewrite.
    reserve_application_locals([value], application_slot, qualifier)

    def qualified(number: int) -> int:
        return qualifier.qualify(application_slot, number)

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
            elif key in LOCAL_ID_FIELDS and isinstance(member, int):
                result[key] = qualified(member)
            elif key in {"call_obligation_ids", "install_obligation_ids", "obligation_ids"} and isinstance(member, list):
                result[key] = [qualified(number) for number in member]
            else:
                result[key] = rewrite(member)
        return result

    return rewrite(value)


VALUE_SUMMARY_FIELDS = {"source", "type", "nominal_index", "provenance", "capture", "usage", "origin"}


def discharge_call_obligation(
    obligation: dict[str, Any],
    source_contract: dict[str, Any],
    application: dict[str, Any],
    *,
    returns: ReturnScope | None = None,
    source_path: dict[str, Any] | None = None,
    caller_row_binders: dict[int, dict[str, Any]] | None = None,
) -> None:
    """Resolve every formal and prove the Call predicate before discharge."""

    returns = returns or {}
    caller_row_binders = caller_row_binders or {}
    parameter_slots = [binder["slot"] for binder in source_contract["binders"]["parameter_binders"]]
    actual_by_slot = dict(zip(parameter_slots, application["actual_arguments"]))
    closure_by_slot = {
        binding["slot"]["slot"]: binding
        for binding in source_contract["closure_environment"]
        if binding["slot"]["namespace"] == "ClosureCapture"
    }
    owner_arguments = {
        entry["binder_slot"]: entry["value"]
        for entry in application["substitution"]["owner_arguments"]
    }
    row_arguments = {
        entry["binder_slot"]: entry["value"]
        for entry in application["substitution"]["row_arguments"]
    }

    def binding_summary(binding: dict[str, Any]) -> dict[str, Any]:
        return {
            "source": {
                "kind": "LegacySlotRefV2",
                "value": copy.deepcopy(binding["slot"]),
            },
            "type": copy.deepcopy(binding["type"]),
            "nominal_index": {
                "kind": "LegacyNominalIndexExprV2",
                "value": {"kind": "NoNominalIndexV1"},
            },
            "provenance": copy.deepcopy(binding["provenance"]),
            "capture": copy.deepcopy(binding["capture"]),
            "usage": None,
            "origin": "closure-environment",
        }

    def normalized_slot(formal: Any) -> dict[str, Any]:
        if isinstance(formal, dict) and formal.get("kind") == "LegacySlotRefV2":
            formal = formal["value"]
        reject(
            not isinstance(formal, dict)
            or set(formal) != {"namespace", "slot"},
            "contract-projection-escapes-scope",
        )
        return formal

    def return_binder(formal: Any) -> dict[str, Any] | None:
        if not isinstance(formal, dict) or formal.get("kind") != "ReturnSlotRefV2":
            return None
        exact_fields(formal, {"kind", "return_slot"}, "ReturnSlotRefV2")
        number = formal["return_slot"]
        reject(number not in returns, "contract-projection-escapes-scope")
        return returns[number]

    def resolve_summary(formal: Any) -> dict[str, Any]:
        binder = return_binder(formal)
        if binder is not None:
            actual = {
                "source": copy.deepcopy(formal),
                "type": copy.deepcopy(binder["type"]),
                "nominal_index": copy.deepcopy(binder["nominal_index"]),
                "provenance": copy.deepcopy(binder["provenance"]),
                "capture": copy.deepcopy(binder["capture"]),
                "usage": copy.deepcopy(binder["usage"]),
                "origin": "call-q:return-binder",
            }
            exact_fields(actual, VALUE_SUMMARY_FIELDS, "ValueSummaryExprV2")
            return actual
        formal = normalized_slot(formal)
        namespace = formal["namespace"]
        number = formal["slot"]
        if namespace == "Parameter":
            reject(number not in actual_by_slot, "application-arity-mismatch")
            actual = actual_by_slot[number]
        elif namespace == "ClosureCapture":
            reject(number not in closure_by_slot, "contract-projection-escapes-scope")
            actual = binding_summary(closure_by_slot[number])
        elif namespace == "OperationArgument":
            reject(
                not isinstance(number, int)
                or isinstance(number, bool)
                or not 0 <= number < len(application["actual_arguments"]),
                "contract-projection-escapes-scope",
            )
            actual = application["actual_arguments"][number]
        else:
            # Owner/Clock/Row/Identity are declaration resources, not value
            # summaries. They cannot disappear through an empty actual set.
            raise Diagnostic("call-obligation-unsatisfied")
        exact_fields(actual, VALUE_SUMMARY_FIELDS, "ValueSummaryExprV2")
        return copy.deepcopy(actual)

    def owner_from_provenance(provenance: Any) -> dict[str, Any] | None:
        if not isinstance(provenance, dict):
            return None
        if provenance.get("kind") != "LegacyProvenanceExprV2":
            return None
        legacy = provenance.get("value", {})
        if legacy.get("kind") not in {
            "OwnerV1", "RegionV1", "GenerationBoundV1",
        }:
            return None
        owner = legacy.get("owner")
        if not isinstance(owner, dict):
            return None
        if owner.get("namespace") == "Owner":
            return copy.deepcopy(owner_arguments.get(owner.get("slot"), owner))
        return copy.deepcopy(owner)

    def resolve_owner(formal: Any) -> dict[str, Any] | None:
        binder = return_binder(formal)
        if binder is not None:
            return owner_from_provenance(binder["provenance"])
        formal = normalized_slot(formal)
        if formal["namespace"] == "Owner":
            return copy.deepcopy(owner_arguments.get(formal["slot"]))
        try:
            summary = resolve_summary(formal)
        except Diagnostic:
            return None
        return owner_from_provenance(summary["provenance"])

    value = obligation_value(obligation)
    kind = value["kind"]
    instantiated: dict[str, Any] = {}
    if kind in {"OutlivesV1", "OutlivesV2"}:
        instantiated = {
            "shorter": resolve_owner(value["shorter"]),
            "longer": resolve_owner(value["longer"]),
        }
        actuals = []
    elif kind in {"RowLacksV1", "RowLacksV2"}:
        row_slot = normalized_slot(value["row_slot"])
        reject(
            row_slot["namespace"] != "Row",
            "contract-projection-escapes-scope",
        )
        source_row = next(
            (
                binder
                for binder in source_contract["binders"]["row_binders"]
                if binder["slot"] == row_slot["slot"]
            ),
            None,
        )
        reject(
            source_row is None or value["entry"] not in source_row["lacks"],
            "contract-parameter-inconsistent-instantiation",
        )
        instantiated = {
            "row": copy.deepcopy(row_arguments.get(row_slot["slot"])),
            "entry": copy.deepcopy(value["entry"]),
            "caller_row_binders": caller_row_binders,
        }
        actuals = []
    elif kind in {"ReplayableCleanupV1", "ReplayableCleanupV2"}:
        sites = [
            site
            for site in (source_path or {}).get("LatentSites", [])
            if site.get("site_slot") == value["site_slot"]
        ]
        instantiated = {
            "site": copy.deepcopy(sites[0]) if len(sites) == 1 else None,
        }
        actuals = []
    else:
        actuals = [resolve_summary(formal) for formal in value.get("slots", [])]

    solve_call_obligation(obligation, actuals, instantiated=instantiated)


def legacy_capture_is_boundary_safe(
    capture: dict[str, Any],
    boundary: str | None = None,
) -> bool:
    kind = capture["kind"]
    if kind == "BottomCaptureV1":
        return False
    if kind == "UnionCaptureV1":
        return all(
            legacy_capture_is_boundary_safe(member, boundary)
            for member in capture["members"]
        )
    if kind == "CaptureSlotsV1" and boundary in TEMPORAL_BOUNDARIES:
        return all(
            reference["namespace"] not in {
                "Owner", "SuffixLive", "OperationArgument",
            }
            for reference in capture["slots"]
        )
    if kind in {"ArgumentCaptureV1", "ArrayElementCaptureV1"}:
        return (
            boundary not in TEMPORAL_BOUNDARIES
            or capture["argument"]["namespace"]
            not in {"Owner", "SuffixLive", "OperationArgument"}
        )
    if kind == "OperationResultCaptureV1" and boundary in TEMPORAL_BOUNDARIES:
        return False
    return kind in {
        "NoCaptureV1", "CaptureSlotsV1", "ArgumentCaptureV1",
        "ArrayElementCaptureV1", "OperationResultCaptureV1",
    }


def capture_is_boundary_safe(
    capture: dict[str, Any],
    boundary: str | None = None,
) -> bool:
    kind = capture["kind"]
    if kind == "LegacyCaptureExprV2":
        return legacy_capture_is_boundary_safe(capture["value"], boundary)
    if kind == "UnionCaptureV2":
        return all(
            capture_is_boundary_safe(member, boundary)
            for member in capture["members"]
        )
    return kind == "ReturnCaptureV2"


def provenance_is_inhabited(provenance: dict[str, Any]) -> bool:
    kind = provenance["kind"]
    if kind == "LegacyProvenanceExprV2":
        value = provenance["value"]
        if value["kind"] == "BottomProvenanceV1":
            return False
        if value["kind"] == "JoinProvenanceV1":
            return all(
                provenance_is_inhabited({"kind": "LegacyProvenanceExprV2", "value": member})
                for member in value["members"]
            )
        return True
    if kind == "JoinProvenanceV2":
        return all(provenance_is_inhabited(member) for member in provenance["members"])
    if kind == "EnvironmentV2":
        return all(
            provenance_is_inhabited(binding["provenance"])
            and capture_is_boundary_safe(binding["capture"])
            for binding in provenance["bindings"]
        )
    return kind == "ReturnProvenanceV2"


TEMPORAL_BOUNDARIES = {
    "OwnerStorage", "ContinuationCapture", "TemporalLock", "Suspension", "FFI",
}


def legacy_provenance_valid_at_boundary(
    provenance: dict[str, Any],
    boundary: str,
) -> bool:
    kind = provenance["kind"]
    if kind == "BottomProvenanceV1":
        return False
    if kind == "CallbackV1":
        return boundary not in TEMPORAL_BOUNDARIES
    if kind in {"OwnerV1", "RegionV1", "GenerationBoundV1"}:
        return boundary not in TEMPORAL_BOUNDARIES
    if kind == "EnvironmentV1":
        return all(
            legacy_provenance_valid_at_boundary(binding["provenance"], boundary)
            and legacy_capture_is_boundary_safe(binding["capture"], boundary)
            for binding in provenance["bindings"]
        )
    if kind == "JoinProvenanceV1":
        return all(
            legacy_provenance_valid_at_boundary(member, boundary)
            for member in provenance["members"]
        )
    return True


def provenance_valid_at_boundary(
    provenance: dict[str, Any],
    boundary: str,
) -> bool:
    kind = provenance["kind"]
    if kind == "LegacyProvenanceExprV2":
        return legacy_provenance_valid_at_boundary(provenance["value"], boundary)
    if kind == "EnvironmentV2":
        return all(
            provenance_valid_at_boundary(binding["provenance"], boundary)
            and capture_is_boundary_safe(binding["capture"], boundary)
            for binding in provenance["bindings"]
        )
    if kind == "JoinProvenanceV2":
        return all(
            provenance_valid_at_boundary(member, boundary)
            for member in provenance["members"]
        )
    return kind == "ReturnProvenanceV2"


def legacy_capture_is_cross_world_safe(capture: dict[str, Any]) -> bool:
    kind = capture["kind"]
    if kind == "NoCaptureV1":
        return True
    if kind == "UnionCaptureV1":
        return all(
            legacy_capture_is_cross_world_safe(member)
            for member in capture["members"]
        )
    # A flat captured slot has no pointwise provenance/clock witness here.
    return False


def capture_is_cross_world_safe(capture: dict[str, Any]) -> bool:
    kind = capture["kind"]
    if kind == "LegacyCaptureExprV2":
        return legacy_capture_is_cross_world_safe(capture["value"])
    if kind == "UnionCaptureV2":
        return all(capture_is_cross_world_safe(member) for member in capture["members"])
    return False


def legacy_provenance_is_stable_across(provenance: dict[str, Any]) -> bool:
    kind = provenance["kind"]
    if kind == "StableV1":
        return True
    if kind == "EnvironmentV1":
        return all(
            legacy_provenance_is_stable_across(binding["provenance"])
            and legacy_capture_is_cross_world_safe(binding["capture"])
            for binding in provenance["bindings"]
        )
    if kind == "JoinProvenanceV1":
        return all(
            legacy_provenance_is_stable_across(member)
            for member in provenance["members"]
        )
    return False


def provenance_is_stable_across(provenance: dict[str, Any]) -> bool:
    kind = provenance["kind"]
    if kind == "LegacyProvenanceExprV2":
        return legacy_provenance_is_stable_across(provenance["value"])
    if kind == "EnvironmentV2":
        return all(
            provenance_is_stable_across(binding["provenance"])
            and capture_is_cross_world_safe(binding["capture"])
            for binding in provenance["bindings"]
        )
    if kind == "JoinProvenanceV2":
        return all(provenance_is_stable_across(member) for member in provenance["members"])
    return False


def legacy_capture_is_duplicable(capture: dict[str, Any]) -> bool:
    kind = capture["kind"]
    if kind == "NoCaptureV1":
        return True
    if kind in {"BottomCaptureV1", "OperationResultCaptureV1"}:
        return False
    if kind == "CaptureSlotsV1":
        return all(
            reference["namespace"] not in {"Owner", "SuffixLive"}
            for reference in capture["slots"]
        )
    if kind in {"ArgumentCaptureV1", "ArrayElementCaptureV1"}:
        return capture["argument"]["namespace"] not in {"Owner", "SuffixLive"}
    if kind == "UnionCaptureV1":
        return all(legacy_capture_is_duplicable(member) for member in capture["members"])
    return False


def capture_is_duplicable(capture: dict[str, Any]) -> bool:
    kind = capture["kind"]
    if kind == "LegacyCaptureExprV2":
        return legacy_capture_is_duplicable(capture["value"])
    if kind == "UnionCaptureV2":
        return all(capture_is_duplicable(member) for member in capture["members"])
    return False


def row_lacks_entry(
    row: Any,
    entry: dict[str, Any],
    row_binders: dict[int, dict[str, Any]] | None = None,
) -> bool:
    """Decide closed rows or a Tail backed by the caller's lexical Lacks proof."""

    row_binders = row_binders or {}
    if not isinstance(row, dict):
        return False
    kind = row.get("kind")
    if kind == "EmptyV1":
        return True
    if kind == "ClosedV1":
        return entry not in row.get("entries", [])
    if kind == "UnionV1":
        return all(
            row_lacks_entry(member, entry, row_binders)
            for member in row.get("members", [])
        )
    if kind == "TailV1":
        reference = row.get("row_slot", {})
        binder = row_binders.get(reference.get("slot"))
        return (
            reference.get("namespace") == "Row"
            and binder is not None
            and entry in binder.get("lacks", [])
        )
    return False


NEUTRAL_REPLAYABLE_CLEANUP = {
    "residual_row": {"kind": "EmptyV1"},
    "attributed_demand": [],
    "transition": {"kind": "SameWorldV1"},
    "suspension": {"atoms": [], "grade": "NoSuspend"},
    "semantic_summary": {"kind": "PureV1"},
}


def solve_call_obligation(
    obligation: dict[str, Any],
    actuals: list[dict[str, Any]],
    *,
    instantiated: dict[str, Any] | None = None,
) -> None:
    value = obligation_value(obligation)
    instantiated = instantiated or {}
    reject(value["stage"] != "Call", "unknown-obligation-stage")
    kind = value["kind"]
    if kind in {"BoundarySafeV1", "BoundarySafeV2"}:
        boundary = value["boundary"]
        reject(
            any(
                not provenance_valid_at_boundary(summary["provenance"], boundary)
                or not capture_is_boundary_safe(summary["capture"], boundary)
                for summary in actuals
            ),
            "call-obligation-unsatisfied",
        )
    elif kind in {"StableAcrossV1", "StableAcrossV2"}:
        reject(
            any(
                not provenance_is_stable_across(summary["provenance"])
                or not capture_is_cross_world_safe(summary["capture"])
                for summary in actuals
            ),
            "call-obligation-unsatisfied",
        )
    elif kind in {"DuplicableEnvV1", "DuplicableEnvV2"}:
        reject(
            any(
                not capture_is_duplicable(summary["capture"])
                or (
                    is_authority_bearing_type(summary["type"])
                    and authority_usage_grade(summary["type"]) != "Many"
                )
                or (
                    summary["usage"] is not None
                    and summary["usage"].get("kind") == "LegacyUsageExprV2"
                    and summary["usage"]["value"]["kind"] == "Once"
                )
                for summary in actuals
            ),
            "call-obligation-unsatisfied",
        )
    elif kind in {"PhaseAllowsV1", "PhaseAllowsV2"}:
        required_phase = value["required_phase"]
        reject(
            required_phase != {
                "allowed_phases": ["Pure", "Compute", "Action", "Commit"],
                "required_authorities": [],
                "current_owner": None,
            },
            "call-obligation-unsatisfied",
        )
    elif kind in {"OutlivesV1", "OutlivesV2"}:
        shorter = instantiated.get("shorter")
        longer = instantiated.get("longer")
        reject(
            shorter is None or longer is None or shorter != longer,
            "call-obligation-unsatisfied",
        )
    elif kind in {"RowLacksV1", "RowLacksV2"}:
        reject(
            not row_lacks_entry(
                instantiated.get("row"), instantiated.get("entry", {}),
                instantiated.get("caller_row_binders", {}),
            ),
            "call-obligation-unsatisfied",
        )
    elif kind in {"ReplayableCleanupV1", "ReplayableCleanupV2"}:
        site = instantiated.get("site")
        suffix = site.get("suffix", {}) if isinstance(site, dict) else {}
        reject(
            value["cleanup"] != NEUTRAL_REPLAYABLE_CLEANUP
            or suffix.get("cleanup") != value["cleanup"]
            or suffix.get("live_bindings") != []
            or (
                isinstance(suffix, dict)
                and suffix_live_projection_keys(suffix) != set()
            ),
            "call-obligation-unsatisfied",
        )
    elif kind in {
        "TickWitnessV1", "TickWitnessV2",
        "OwnerParkingV1", "OwnerParkingV2",
    }:
        # These legal variants require sealed site/install evidence. A bare
        # Call-stage obligation cannot manufacture that evidence.
        raise Diagnostic("call-obligation-unsatisfied")
    else:
        raise Diagnostic("call-obligation-unsatisfied")


def validate_concrete_application_call_obligations(
    application: dict[str, Any],
    source_contract: dict[str, Any],
    *,
    caller_row_binders: dict[int, dict[str, Any]] | None = None,
) -> None:
    """ContractWF discharges every concrete callee Call-Q, not only evaluator runs."""

    caller_row_binders = caller_row_binders or {}

    def scan_value(value: Any, returns: ReturnScope) -> None:
        if isinstance(value, list):
            for member in value:
                scan_value(member, returns)
            return
        if not isinstance(value, dict):
            return
        if value.get("kind") in {
            "LiteralPathsV2", "CurrentDispositionPathsV2", "InvokeV2",
            "PathBindV2", "JoinV2",
        }:
            scan_computation(value, returns)
            return
        for member in value.values():
            scan_value(member, returns)

    def scan_path(path: dict[str, Any], returns: ReturnScope) -> None:
        for obligation in path["ParametricObligations"]:
            if obligation_value(obligation)["stage"] == "Call":
                discharge_call_obligation(
                    obligation, source_contract, application,
                    returns=returns, source_path=path,
                    caller_row_binders=caller_row_binders,
                )
        for site in path["LatentSites"]:
            scan_value(site, returns)

    def scan_computation(
        computation: dict[str, Any], returns: ReturnScope,
    ) -> None:
        kind = computation["kind"]
        if kind in {"LiteralPathsV2", "CurrentDispositionPathsV2"}:
            for path in computation["paths"]:
                scan_path(path, returns)
            return
        if kind == "PathBindV2":
            scan_computation(computation["prefix"], returns)
            continuation_returns = dict(returns)
            binder = computation["return_binder"]
            continuation_returns[binder["slot"]] = binder
            scan_computation(computation["continuation"], continuation_returns)
            return
        if kind == "JoinV2":
            for member in computation["members"]:
                scan_computation(member, returns)
            return
        if kind == "InvokeV2":
            return
        raise Diagnostic("unknown-contract-computation-variant")

    scan_computation(source_contract["computation"], {})


def substitute_term_actuals(
    value: Any,
    source_contract: dict[str, Any],
    application: dict[str, Any],
) -> Any:
    parameter_slots = [binder["slot"] for binder in source_contract["binders"]["parameter_binders"]]
    actuals = application["actual_arguments"]
    require(len(parameter_slots) == len(actuals), "evaluator parameter-binder/actual arity mismatch")
    actual_by_slot = dict(zip(parameter_slots, actuals))

    def actual_for_slot_ref(reference: Any) -> dict[str, Any] | None:
        if not isinstance(reference, dict) or reference.get("namespace") != "Parameter":
            return None
        return actual_by_slot.get(reference.get("slot"))

    def rewrite(node: Any) -> Any:
        if isinstance(node, list):
            return [rewrite(member) for member in node]
        if not isinstance(node, dict):
            return node
        if set(node) == VALUE_SUMMARY_FIELDS:
            source = node.get("source")
            if isinstance(source, dict) and source.get("kind") == "LegacySlotRefV2":
                actual = actual_for_slot_ref(source.get("value"))
                if actual is not None:
                    return copy.deepcopy(actual)
        if node.get("kind") == "LegacySlotRefV2":
            actual = actual_for_slot_ref(node.get("value"))
            if actual is not None:
                reject(actual["source"] is None, "term-actual-source-unavailable")
                return copy.deepcopy(actual["source"])
        if node.get("kind") == "LegacyProvenanceExprV2":
            expression = node.get("value", {})
            if expression.get("kind") == "ArgumentV1":
                actual = actual_for_slot_ref(expression.get("argument"))
                if actual is not None:
                    return copy.deepcopy(actual["provenance"])
        if node.get("kind") == "LegacyCaptureExprV2":
            expression = node.get("value", {})
            if expression.get("kind") == "ArgumentCaptureV1":
                actual = actual_for_slot_ref(expression.get("argument"))
                if actual is not None:
                    return copy.deepcopy(actual["capture"])
        if set(node) == {"namespace", "slot"}:
            actual = actual_for_slot_ref(node)
            if actual is not None:
                reject(actual["source"] is None, "term-actual-source-unavailable")
                return copy.deepcopy(actual["source"]["value"])
        return {key: rewrite(member) for key, member in node.items()}

    return rewrite(value)


def instantiate_invoked_path(
    path: dict[str, Any],
    application: dict[str, Any],
    source_contract: dict[str, Any],
    qualifier: FreshLocalQualifier,
    *,
    caller_row_binders: dict[int, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    instantiated = qualify_application_locals(
        substitute_contract_kind(path, application["substitution"]),
        application["application_slot"], qualifier,
    )
    # Call-stage obligations are solved against the complete actual summary and
    # removed before any surviving bare SlotRef projection is materialized.
    # A source=null actual remains valid only where no later projection needs a
    # materialized slot; that later use emits term-actual-source-unavailable.
    for obligation in path["ParametricObligations"]:
        if obligation_value(obligation)["stage"] == "Call":
            discharge_call_obligation(
                obligation, source_contract, application,
                source_path=path, caller_row_binders=caller_row_binders,
            )
    instantiated["ParametricObligations"] = [
        obligation
        for obligation in instantiated["ParametricObligations"]
        if obligation_value(obligation)["stage"] != "Call"
    ]
    for latent in instantiated["LatentSites"]:
        latent["call_obligation_ids"] = []
    instantiated = substitute_term_actuals(instantiated, source_contract, application)
    return instantiated


def substitute_return_binder(
    value: Any,
    binder: dict[str, Any],
    *,
    materialized_source: dict[str, Any] | None = None,
) -> Any:
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
        if kind == "ReturnSlotRefV2":
            reject(materialized_source is None, "term-actual-source-unavailable")
            return copy.deepcopy(materialized_source)
        return {key: rewrite(member) for key, member in node.items()}

    return rewrite(value)


def evaluate_contract_computation(
    contract: dict[str, Any],
    *,
    imports: ImportScope,
    contract_environment: dict[int, dict[str, Any]] | None = None,
    local_functions: LocalFunctionScope | None = None,
    disposition_binder: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Evaluate V2 computation to complete normalized PathContractV2 values."""

    contract_environment = contract_environment or {}
    local_functions = local_functions or {}
    # Every declaration owns one qualifier. Its raw locals are reserved before
    # any nested application is evaluated; nested declarations get their own
    # allocator and are re-qualified only when projected into this declaration.
    qualifier = FreshLocalQualifier(collect_local_ids(contract["computation"]))
    applications = {application["application_slot"]: application for application in contract["applications"]}
    caller_row_binders = {
        binder["slot"]: binder
        for binder in contract.get("binders", {}).get("row_binders", [])
    }
    evaluator_slot_types = {
        ("Parameter", binder["slot"]): binder["type"]
        for binder in contract.get("binders", {}).get("parameter_binders", [])
    }
    evaluator_slot_types.update(
        {
            (binding["slot"]["namespace"], binding["slot"]["slot"]): binding["type"]
            for binding in contract.get("closure_environment", [])
        }
    )

    def materialize_path_usage(
        path: dict[str, Any], returns: ReturnScope,
    ) -> dict[str, Any]:
        result = copy.deepcopy(path)

        def materialize(
            usage: dict[str, Any], seen: set[int] | None = None,
        ) -> dict[str, Any]:
            if usage.get("kind") != "ReturnUsageV2":
                return copy.deepcopy(usage)
            number = usage["return_slot"]
            reject(number not in returns, "contract-projection-escapes-scope")
            seen = seen or set()
            reject(number in seen, "contract-component-kind-mismatch")
            projected = returns[number].get("usage")
            reject(projected is None, "contract-component-kind-mismatch")
            return materialize(projected, seen | {number})

        result["usage"] = [materialize(usage) for usage in result["usage"]]
        return result

    def evaluate(
        node: dict[str, Any], returns: ReturnScope | None = None,
    ) -> list[dict[str, Any]]:
        returns = returns or {}
        kind = node["kind"]
        if kind in {"LiteralPathsV2", "CurrentDispositionPathsV2"}:
            return [
                {
                    "path": materialize_path_usage(path, returns),
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
                    if actual["kind"] == "ImportedFunctionRefV2":
                        nested_environment[entry["binder_slot"]] = imports[actual["artifact_hash"]]
                    elif actual["kind"] == "LocalFunctionRefV2":
                        nested_environment[entry["binder_slot"]] = local_functions[actual["declaration_slot"]]
                    elif actual["kind"] == "ContractParameterRefV2":
                        outer_slot = actual["parameter"]["slot"]
                        require(
                            outer_slot in contract_environment,
                            "evaluator has no pass-through contract-parameter actual",
                        )
                        nested_environment[entry["binder_slot"]] = contract_environment[outer_slot]
                    else:
                        raise AssertionError("evaluator requires a resolved contract substitution")
            elif reference["kind"] == "LocalFunctionRefV2":
                source = local_functions[reference["declaration_slot"]]
                nested_environment = {}
            elif reference["kind"] == "ContractParameterRefV2":
                parameter_slot = reference["parameter"]["slot"]
                require(parameter_slot in contract_environment, "evaluator has no contract-parameter actual")
                source = contract_environment[parameter_slot]
                nested_environment = {}
            else:
                raise AssertionError("evaluator cannot resolve contract reference")
            paths = evaluate_contract_computation(
                source, imports=imports, contract_environment=nested_environment,
                local_functions=local_functions,
            )
            reserve_application_locals(
                [path["path"] for path in paths],
                application["application_slot"], qualifier,
            )
            return [
                {
                    "path": instantiate_invoked_path(
                        path["path"], application, source, qualifier,
                        caller_row_binders=caller_row_binders,
                    ),
                    "trace": [outcome_event(application["application_slot"], path["path"]["outcome"]), *path["trace"]],
                }
                for path in paths
            ]
        if kind == "PathBindV2":
            prefix = evaluate(node["prefix"], returns)
            terminal = [path for path in prefix if path["path"]["outcome"]["kind"] != "ReturnsV2"]
            continued: list[dict[str, Any]] = []
            continuation_returns = dict(returns)
            continuation_returns[node["return_binder"]["slot"]] = node["return_binder"]
            continuation = evaluate(node["continuation"], continuation_returns)
            materialized_source = None
            if node["prefix"]["kind"] == "CurrentDispositionPathsV2":
                reject(disposition_binder is None, "term-actual-source-unavailable")
                materialized_source = {
                    "kind": "LegacySlotRefV2",
                    "value": slot("SuffixLive", disposition_binder["slot"]),
                }
            for returning in (path for path in prefix if path["path"]["outcome"]["kind"] == "ReturnsV2"):
                for suffix in continuation:
                    substituted_suffix = substitute_return_binder(
                        suffix["path"], node["return_binder"],
                        materialized_source=materialized_source,
                    )
                    composed = compose_path_contracts(
                        returning["path"], substituted_suffix,
                    )
                    validate_authority_bearing_usages(
                        composed,
                        slot_types=evaluator_slot_types,
                        disposition=(
                            disposition_binder["slot"], disposition_binder["type"]
                        ) if disposition_binder is not None else None,
                    )
                    continued.append(
                        {
                            "path": composed,
                            "trace": [*returning["trace"], *suffix["trace"]],
                        }
                    )
            return [*terminal, *continued]
        if kind == "JoinV2":
            return [
                path
                for member in node["members"]
                for path in evaluate(member, returns)
            ]
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
        validate_application_return_binder(source, app, binder, imports=imported)
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
    observer_shapes = oracle["expectation"]["evaluated_observer_shapes"]
    require(len(observer_shapes) == len(evaluated), "HOF observer-shape golden cardinality")
    expected_phase = source["computation"]["prefix"]["paths"][0]["required_phase"]
    evaluated_scope = declaration_scope_from_binders(
        contract["binders"], contract["closure_environment"],
    )
    for item, observer_shape in zip(evaluated, observer_shapes):
        path = item["path"]
        exact_fields(
            path,
            {"outcome", "residual_row", "attributed_demand", "suspension", "semantic_summary", "usage", "required_phase", "ParametricObligations", "LatentSites"},
            "evaluated PathContractV2",
        )
        validate_path(
            path, applications={}, returns={}, context="function", imports=imported,
            contract_binders=evaluated_scope.contract_binders,
            local_functions={}, row_binders=evaluated_scope.row_binders,
            declaration_scope=evaluated_scope,
        )
        require(path["residual_row"] == source_kind["visible_row"], "HOF evaluated row observer lost")
        require(
            observer_shape
            == {
                "attributed_demand": len(path["attributed_demand"]),
                "latent_sites": len(path["LatentSites"]),
                "obligations": len(path["ParametricObligations"]),
                "semantic_summary": path["semantic_summary"],
                "suspension_atoms": len(path["suspension"]["atoms"]),
                "suspension_grade": path["suspension"]["grade"],
            },
            "HOF evaluated observer shape lost",
        )
        require(path["usage"] == [] and path["required_phase"] == expected_phase, "HOF evaluated usage/phase observer lost")
        require(
            all(obligation_value(obligation)["stage"] == "HandlerInstall" for obligation in path["ParametricObligations"]),
            "HOF evaluated Q observer lost",
        )
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


def validate_clock_package(
    package: dict[str, Any],
    *,
    storage_owner_scope: set[int] | None = None,
) -> None:
    validate_wire_u32_fields(package)
    exact_fields(package, {"artifact", "profile", "schema_version", "storage_owner", "child_owner_binder", "owner_relation", "clock_binder", "summary_binder", "body", "control_protocol", "sealed_origin"}, "PackedNextPackageV2")
    reject(
        package.get("artifact") != "PackedNextPackageV2"
        or package.get("profile") != PROFILE
        or package.get("schema_version") != 2,
        "packed-next-package-header-mismatch",
    )
    reject(package["sealed_origin"] != "cire.temporal:pack_next", "packed-next-sealed-origin-mismatch")
    storage_owner = package["storage_owner"]
    reject(
        not isinstance(storage_owner, dict)
        or set(storage_owner) != {"namespace", "slot"}
        or storage_owner.get("namespace") != "Owner"
        or isinstance(storage_owner.get("slot"), bool)
        or not isinstance(storage_owner.get("slot"), int)
        or not 0 <= storage_owner["slot"] <= U32_MAX
        or (storage_owner_scope is not None and storage_owner["slot"] not in storage_owner_scope),
        "packed-next-storage-owner-mismatch",
    )
    relation = validate_contract_object(package["owner_relation"])
    child_owner_binder = validate_contract_object(package["child_owner_binder"])
    exact_fields(child_owner_binder, {"owner_slot"}, "QuantifiedOwnerBinderV1")
    validate_u32(child_owner_binder["owner_slot"], "PackedNext child Owner binder")
    reject(
        child_owner_binder["owner_slot"] == storage_owner["slot"]
        or (
            storage_owner_scope is not None
            and child_owner_binder["owner_slot"] in storage_owner_scope
        ),
        "contract-component-kind-mismatch",
    )
    exact_fields(relation, {"child", "parent", "relation", "sealed_origin"}, "ChildOwnerWitnessV2")
    child = slot("Owner", child_owner_binder["owner_slot"])
    reject(
        relation
        != {
            "child": child,
            "parent": package["storage_owner"],
            "relation": "DirectChild",
            "sealed_origin": "cire.temporal:pack_next",
        },
        "contract-component-kind-mismatch",
    )
    clock = validate_contract_object(package["clock_binder"])
    exact_fields(clock, {"identity_slot", "clock_refinement", "family_witness", "owner"}, "QuantifiedClockBinderV2")
    clock_refinement = validate_contract_object(clock["clock_refinement"])
    exact_fields(clock_refinement, {"clock_slot", "identity"}, "QuantifiedClockRefinementV1")
    validate_u32(clock["identity_slot"], "PackedNext identity binder")
    validate_u32(clock_refinement["clock_slot"], "PackedNext clock binder")
    reject(clock["family_witness"] != {"kind": "CanonicalFrameClockV2", "module": ["cire", "temporal"], "name": "FrameClock", "sealed_origin": "cire.temporal:FrameClock"}, "clock-package-family-not-clock-indexing")
    reject(clock["owner"] != child, "contract-component-kind-mismatch")
    identity = slot("Identity", clock["identity_slot"])
    clock_ref = slot("Clock", clock_refinement["clock_slot"])
    reject(clock_refinement["identity"] != identity, "contract-component-kind-mismatch")
    summary_binder = validate_contract_object(package["summary_binder"])
    exact_fields(summary_binder, {"contract_slot", "kind"}, "QuantifiedContractBinderV2")
    validate_u32(summary_binder["contract_slot"], "PackedNext summary binder")
    summary = validate_contract_object(summary_binder["kind"])
    exact_fields(summary, {"kind", "clock", "payload_type"}, "ClockPackageSummaryKindV2")
    reject(
        summary["kind"] != "ClockPackageSummaryKindV2"
        or summary["clock"] != clock_ref,
        "contract-component-kind-mismatch",
    )
    body = validate_contract_object(package["body"])
    reject(
        body.get("kind") != "NextTypeV2"
        or body.get("clock") != clock_ref,
        "contract-component-kind-mismatch",
    )
    clock_scope = DeclarationScope(
        type_parameter_kinds={},
        row_binders={},
        contract_binders={},
        identity_binders={
            clock["identity_slot"]: {
                "family": {
                    "arguments": [],
                    "kind": "NominalTypeV1",
                    "module": ["cire", "temporal"],
                    "name": "FrameClock",
                },
                "identity_slot": clock["identity_slot"],
                "owner": child,
            }
        },
        handler_contract_binders=set(),
        owner_binders={
            storage_owner["slot"]: {"slot": storage_owner["slot"]},
            child["slot"]: {"owner_slot": child["slot"]},
        },
        clock_binders={
            clock_ref["slot"]: {
                "identity": identity,
                "owner": child,
                "slot": clock_ref["slot"],
            }
        },
    )
    validate_type_v2(
        summary["payload_type"],
        declaration_scope=clock_scope,
    )
    package_contracts = {
        summary_binder["contract_slot"]: summary_binder,
    }
    package_scope = clock_scope.nested(
        contract_binders=package_contracts,
    )
    validate_type_v2(
        body,
        contract_binders=package_contracts,
        declaration_scope=package_scope,
    )
    reject(
        not alpha_equal_v2(
            body["payload"], summary["payload_type"],
        ),
        "contract-component-kind-mismatch",
    )
    protocol = package["control_protocol"]
    exact_fields(protocol, {"states", "acquire", "dispose", "release"}, "PackedNextControlProtocolV2")
    reject(protocol != PACKED_CONTROL_PROTOCOL, "packed-next-control-protocol-mismatch")


def validate_clock_open(computation: dict[str, Any]) -> None:
    validate_wire_u32_fields(computation)
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
    exact_fields(
        oracle,
        {"artifact", "profile", "schema_version", "subject", "binders", "package", "lost_acquire_path", "open_computation", "body_observers", "pack_observers", "release_policy", "release_evidence"},
        "CireClockPackageOracleV2",
    )
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong clock oracle profile")
    owner_slots = {binder["slot"] for binder in oracle["binders"]["owner_binders"]}
    reject(
        oracle["package"]["storage_owner"].get("namespace") != "Owner"
        or oracle["package"]["storage_owner"].get("slot") not in owner_slots,
        "packed-next-owner-scope-mismatch",
    )
    validate_declaration_binders(oracle["binders"], [])
    validate_clock_package(oracle["package"], storage_owner_scope=owner_slots)
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
            expected_summary = normalize_summary_sequence(PACKED_ALLOCATE_SUMMARY, body["semantic_summary"])
            reject(
                packed["close_action"] is not None or packed["semantic_summary"] != expected_summary,
                "packed-next-observer-trust-mismatch",
            )
        else:
            require(packed["close_action"] == "CloseChildOnceBeforeExit", "T-Pack terminal close action missing")
            expected_summary = normalize_summary_sequence(
                PACKED_ALLOCATE_SUMMARY, body["semantic_summary"],
                PACKED_TERMINAL_CLOSE_SUMMARY,
            )
            reject(
                packed["semantic_summary"] != expected_summary,
                "packed-next-observer-trust-mismatch",
            )
    evidence = oracle["release_evidence"]
    require(len(evidence) == len(outcomes), "PackedNext release evidence cardinality")
    for index, item in enumerate(evidence):
        require(item["path_index"] == index and item["input_tag"] == outcomes[index] == item["output_tag"], "PackedNext tag preservation")
        require(item["lease_action"] == "ExactlyOnceRelease", "PackedNext release count")


def validate_flow_oracle(oracle: dict[str, Any]) -> None:
    exact_fields(
        oracle,
        {"artifact", "profile", "schema_version", "binders", "flow_summary", "park_obligations", "suspension", "semantic_summary", "required_phase", "route_examples", "expectation"},
        "CireSpecWireVariantOracleV2",
    )
    require(oracle.get("profile") == PROFILE and oracle.get("schema_version") == 2, "wrong flow oracle profile")
    validate_declaration_binders(oracle["binders"], [])
    outcomes = [path["kind"] for path in oracle["flow_summary"]]
    require(outcomes == ["AbortsV2", "TransfersV2"], "flow oracle variants")
    parked_owner, resumption_owner = validate_park(oracle["flow_summary"][1]["park_contract"])
    park = oracle["flow_summary"][1]["park_contract"]
    expected_atom = {
        "grade": "MaySuspend", "kind": "OwnerBoundV1",
        "origin": park["origin"], "owner_slot": park["owner_slot"],
        "park_site_slot": park["site_slot"],
    }
    reject(
        oracle["suspension"] != {"atoms": [expected_atom], "grade": "MaySuspend"}
        or oracle["semantic_summary"]
        != packed_summary(park["origin"], replay_origin="Fresh", fork="Forbid", suspend="OwnerBound")
        or oracle["required_phase"] != park["required_phase"],
        "park-path-observer-mismatch",
    )
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
    binders = oracle["binders"]
    validate_declaration_binders(binders, [])
    type_parameter_kinds = {
        binder["slot"]: binder["kind"] for binder in binders["type_binders"]
    }
    row_binders = {
        binder["slot"]: binder for binder in binders["row_binders"]
    }
    contract_binders = {
        binder["slot"]: binder for binder in binders["contract_binders"]
    }
    identity_binders = {
        binder["identity_slot"]: binder
        for binder in binders["identity_binders"]
    }
    owner_binders = {
        binder["slot"]: binder for binder in binders["owner_binders"]
    }
    clock_binders = {
        binder["slot"]: binder for binder in binders["clock_binders"]
    }
    parameter_binders = {
        binder["slot"] for binder in binders["parameter_binders"]
    }
    handler_contract_binders = {
        binder["slot"]
        for binder in binders["contract_binders"]
        if binder.get("kind") == "HandlerContractBinderV2"
    }
    prompt_slots = [
        binder["prompt_slot"] for binder in binders["prompt_binders"]
    ]
    declaration_scope = DeclarationScope(
        type_parameter_kinds=type_parameter_kinds,
        row_binders=row_binders,
        contract_binders=contract_binders,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
        owner_binders=owner_binders,
        clock_binders=clock_binders,
        prompt_binders=set(prompt_slots),
        parameter_binders=parameter_binders,
        closure_capture_binders=set(),
    )
    require(len(prompt_slots) == len(set(prompt_slots)) and {0, 1} <= set(prompt_slots), "handler oracle prompt scope")
    imported = resolve_imports(oracle, directory)
    current_prompt = oracle["handler_contract"]["prompt_slot"]
    current_index = prompt_slots.index(current_prompt)
    nearest_outer_prompt = prompt_slots[current_index + 1] if current_index + 1 < len(prompt_slots) else None
    validate_handler_contract(
        oracle["handler_contract"], imports=imported,
        nearest_outer_prompt_slot=nearest_outer_prompt,
        type_parameter_kinds=type_parameter_kinds,
        row_binders=row_binders,
        contract_binders=contract_binders,
        identity_binders=identity_binders,
        handler_contract_binders=handler_contract_binders,
        owner_binders=owner_binders,
        clock_binders=clock_binders,
        prompt_binders=set(prompt_slots),
        parameter_binders=parameter_binders,
        closure_capture_binders=set(),
    )
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
    validate_application_return_binder(
        source, applications[0], return_computation["return_binder"],
        imports=imported,
    )
    clause = oracle["handler_contract"]["clause_computations"][0]
    evaluated_clause = evaluate_contract_computation(
        {
            "applications": applications,
            "computation": clause["computation"],
        },
        imports=imported,
        disposition_binder=clause["disposition_binder"],
    )
    application_scope = {
        application["application_slot"]: application
        for application in applications
    }
    for item in evaluated_clause:
        validate_path(
            item["path"], applications=application_scope, returns={},
            context="handler_clause", imports=imported,
            contract_binders=contract_binders, local_functions={},
            disposition_binder=clause["disposition_binder"],
            clause_operation=clause["operation"],
            handled_entry=oracle["handler_contract"]["handled_entry"],
            handler_prompt_slot=current_prompt,
            nearest_outer_prompt_slot=nearest_outer_prompt,
            row_binders=row_binders,
            declaration_scope=declaration_scope,
        )
    require(
        [item["path"]["outcome"]["kind"] for item in evaluated_clause]
        == oracle["expectation"]["current_disposition_evaluated_outcomes"],
        "CurrentDispositionPathsV2 evaluator expectation",
    )
    continuation_path = clause["computation"]["continuation"]["paths"][0]
    require(continuation_path["outcome"]["kind"] == "DelegatesV2", "handler oracle positive DelegatesV2")
    forward = continuation_path["outcome"]["forward_contract"]
    require(
        forward["route"]["prompt_slot"] == nearest_outer_prompt,
        "handler oracle Forward outer route is unbound",
    )
    return_slot = oracle["expectation"]["return_bound_authority_slot"]
    surfaces = {
        "PathContractV2.usage": any(item.get("kind") == "ReturnUsageV2" and item.get("return_slot") == return_slot for item in continuation_path["usage"]),
        "BoundarySafeV2.slots": any(node.get("kind") == "ReturnSlotRefV2" and node.get("return_slot") == return_slot for node in walk(continuation_path["ParametricObligations"]) if isinstance(node, dict)),
        "LiveAcrossSiteV2.usage": any(node.get("kind") == "ReturnUsageV2" and node.get("return_slot") == return_slot for node in walk(continuation_path["LatentSites"]) if isinstance(node, dict)),
    }
    expected_surfaces = set(oracle["expectation"]["return_usage_surfaces"])
    require(
        {name for name, present in surfaces.items() if present} == expected_surfaces,
        "return-bound authority surfaces incomplete",
    )


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
    evaluated = evaluate_contract_computation(
        oracle["contract"], imports=ImportScope(), local_functions=local_functions,
    )
    reject(
        [item["path"]["outcome"]["kind"] for item in evaluated]
        != oracle["expectation"]["evaluated_outcomes"],
        "local-function-evaluation-mismatch",
    )
    reject(
        [
            [
                obligation_value(obligation)["id"]
                for obligation in item["path"]["ParametricObligations"]
            ]
            for item in evaluated
        ]
        != oracle["expectation"]["evaluated_q_ids"],
        "local-function-evaluation-mismatch",
    )
    next_transition = {"kind": "NextWorldV1", "clock": slot("Clock", 0)}
    composed_usage = compose_usage(
        [{"kind": "LegacyUsageExprV2", "value": {"slot": slot("Parameter", 0), "kind": "Once"}}],
        [{"kind": "LegacyUsageExprV2", "value": {"slot": slot("Parameter", 0), "kind": "Once"}}],
    )
    probe_qualifier = FreshLocalQualifier()
    qualified_prompts = [
        qualify_application_locals({"prompt_slot": 1000}, 0, probe_qualifier)["prompt_slot"],
        qualify_application_locals({"prompt_slot": 0}, 1, probe_qualifier)["prompt_slot"],
    ]
    large_qualifier = FreshLocalQualifier()
    large_pair_slots = [
        qualify_application_locals({"prompt_slot": 65536}, 65536, large_qualifier)["prompt_slot"],
        qualify_application_locals({"prompt_slot": 65536}, 65537, large_qualifier)["prompt_slot"],
    ]
    order_a = qualify_application_locals(
        {"site_slot": 5, "prompt_slot": 7}, 0, FreshLocalQualifier(),
    )
    order_b = qualify_application_locals(
        {"prompt_slot": 7, "site_slot": 5}, 0, FreshLocalQualifier(),
    )
    path_order_a = FreshLocalQualifier()
    reserve_application_locals(
        [{"site_slot": 5}, {"site_slot": 3}], 0, path_order_a,
    )
    path_order_b = FreshLocalQualifier()
    reserve_application_locals(
        [{"site_slot": 3}, {"site_slot": 5}], 0, path_order_b,
    )
    path_batch_order_invariant = [
        path_order_a.qualify(0, raw) for raw in (3, 5)
    ] == [
        path_order_b.qualify(0, raw) for raw in (3, 5)
    ]
    outer_qualifier = FreshLocalQualifier({0})
    nested_declaration_slots = [
        0,
        qualify_application_locals(
            {"site_slot": 0}, 0, outer_qualifier,
        )["site_slot"],
    ]
    exhaustion_probe = FreshLocalQualifier()
    # Compressed representation of the monotone search state after every u32
    # output has been allocated; retaining the full 2**32-member set is needless.
    exhaustion_probe.next_candidate = U32_MAX + 1
    try:
        exhaustion_probe.qualify(0, 0)
    except Diagnostic as error:
        exhaustion_diagnostic = error.diagnostic_id
    else:
        raise AssertionError("bounded qualifier accepted an exhausted output domain")
    reject(
        oracle["expectation"]["composition_probe"]
        != {
            "exhaustion_diagnostic": exhaustion_diagnostic,
            "next_then_same": compose_transition(next_transition, {"kind": "SameWorldV1"}),
            "once_then_once": composed_usage[0]["value"]["kind"],
            "large_pair_slots": large_pair_slots,
            "nested_declaration_slots": nested_declaration_slots,
            "qualified_prompt_slots": qualified_prompts,
            "object_order_invariant": order_a == order_b,
            "path_batch_order_invariant": path_batch_order_invariant,
        }
        or len(set(qualified_prompts)) != 2
        or len(set(large_pair_slots)) != 2
        or len(set(nested_declaration_slots)) != 2
        or any(number > U32_MAX for number in [*qualified_prompts, *large_pair_slots]),
        "path-bind-observer-composition-mismatch",
    )


def validate_document(document: dict[str, Any], directory: Path) -> None:
    validate_wire_u32_fields(document)
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
    elif artifact == "EffectFamilyDeclarationsV1":
        validate_effect_family_declarations(document)
    else:
        raise AssertionError(f"unknown interface artifact: {artifact}")


def validate_v1_decoder(target: dict[str, Any]) -> None:
    reject(any(isinstance(node, dict) and str(node.get("kind", "")).endswith("V2") for node in walk(target)), "unsupported-contract-schema-version")


def decode_named(decoder: str, target: dict[str, Any], document: dict[str, Any], directory: Path) -> None:
    validate_wire_u32_fields(target)
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
    elif decoder == "CireHandlerContractOracleV2":
        validate_handler_oracle(target, directory)
    elif decoder == "CireRuntimeModelOracleV2":
        validate_runtime_oracle(target)
    elif decoder == "ParkContractV2":
        validate_park(target)
    elif decoder == "PackedNextPackageV2":
        owner_scope = None
        if document.get("artifact") == "CireClockPackageOracleV2":
            owner_scope = {binder["slot"] for binder in document["binders"]["owner_binders"]}
        validate_clock_package(target, storage_owner_scope=owner_scope)
    elif decoder == "T-Clock-Unpack-Paths":
        validate_clock_open(target)
    elif decoder == "HandlerContractV2":
        imported = resolve_imports(document, directory) if document.get("artifact") == "CireHandlerContractOracleV2" else {}
        nearest_outer_prompt = None
        handler_scope: dict[str, Any] = {}
        if document.get("artifact") == "CireHandlerContractOracleV2":
            binders = document["binders"]
            prompt_slots = [binder["prompt_slot"] for binder in binders["prompt_binders"]]
            current_index = prompt_slots.index(target["prompt_slot"])
            if current_index + 1 < len(prompt_slots):
                nearest_outer_prompt = prompt_slots[current_index + 1]
            handler_scope = {
                "type_parameter_kinds": {
                    binder["slot"]: binder["kind"]
                    for binder in binders["type_binders"]
                },
                "row_binders": {
                    binder["slot"]: binder
                    for binder in binders["row_binders"]
                },
                "contract_binders": {
                    binder["slot"]: binder
                    for binder in binders["contract_binders"]
                },
                "identity_binders": {
                    binder["identity_slot"]: binder
                    for binder in binders["identity_binders"]
                },
                "handler_contract_binders": {
                    binder["slot"]
                    for binder in binders["contract_binders"]
                    if binder.get("kind") == "HandlerContractBinderV2"
                },
                "owner_binders": {
                    binder["slot"]: binder
                    for binder in binders["owner_binders"]
                },
                "clock_binders": {
                    binder["slot"]: binder
                    for binder in binders["clock_binders"]
                },
                "prompt_binders": set(prompt_slots),
                "parameter_binders": {
                    binder["slot"]
                    for binder in binders["parameter_binders"]
                },
                "closure_capture_binders": set(),
            }
        validate_handler_contract(
            target, imports=imported,
            nearest_outer_prompt_slot=nearest_outer_prompt,
            **handler_scope,
        )
    else:
        raise AssertionError(f"unknown mutation decoder: {decoder}")


def expect_diagnostic(
    label: str,
    expected: str,
    action: Callable[[], None],
) -> None:
    try:
        action()
    except Diagnostic as error:
        require(
            error.diagnostic_id == expected,
            f"{label}: expected {expected}, got {error.diagnostic_id}",
        )
    else:
        raise AssertionError(f"{label}: malformed full root was accepted")


def replace_imported_contract_reference(
    value: Any,
    artifact_hash: str,
    replacement: dict[str, Any],
) -> None:
    for node in walk(value):
        if (
            isinstance(node, dict)
            and node.get("kind") == "ImportedFunctionRefV2"
            and node.get("artifact_hash") == artifact_hash
        ):
            node.clear()
            node.update(copy.deepcopy(replacement))


def single_import_scope(
    artifact_hash: str,
    contract: dict[str, Any],
    module: tuple[str, ...],
    name: str,
) -> ImportScope:
    imports = ImportScope()
    imports[artifact_hash] = contract
    imports.exports[artifact_hash] = (module, name)
    return imports


def pure_return_continuation(
    path_template: dict[str, Any],
    return_slot: int,
) -> dict[str, Any]:
    path = copy.deepcopy(path_template)
    path.update(
        {
            "LatentSites": [],
            "ParametricObligations": [],
            "attributed_demand": [],
            "outcome": {
                "kind": "ReturnsV2",
                "transition": {"kind": "SameWorldV1"},
                "result_transformer": {
                    "kind": "ReturnBoundResultV2",
                    "return_slot": return_slot,
                },
            },
            "required_phase": {
                "allowed_phases": ["Pure", "Compute", "Action", "Commit"],
                "required_authorities": [],
                "current_owner": None,
            },
            "residual_row": {"kind": "EmptyV1"},
            "semantic_summary": {"kind": "PureV1"},
            "suspension": {"atoms": [], "grade": "NoSuspend"},
            "usage": [],
        }
    )
    return {"kind": "LiteralPathsV2", "paths": [path]}


def concrete_return_binder(
    source: dict[str, Any],
    application: dict[str, Any],
    return_slot: int,
    *,
    imports: ImportScope,
    local_functions: LocalFunctionScope,
) -> dict[str, Any]:
    contract_environment: dict[int, dict[str, Any]] = {}
    for entry in application["substitution"]["contract_arguments"]:
        reference = entry["contract"]
        if reference["kind"] == "ImportedFunctionRefV2":
            contract_environment[entry["binder_slot"]] = imports[reference["artifact_hash"]]
        elif reference["kind"] == "LocalFunctionRefV2":
            contract_environment[entry["binder_slot"]] = local_functions[reference["declaration_slot"]]
    paths = source_return_paths(
        source, imports=imports, local_functions=local_functions,
        contract_environment=contract_environment,
    )
    require(
        len(paths) == 1,
        "full-root return-binder probe requires one reachable ReturnsV2 path",
    )
    result_type, transition, provenance, capture = instantiate_source_result(
        source, application, paths[0],
    )
    return {
        "slot": return_slot,
        "type": result_type,
        "world": {
            "kind": "ApplyWorldTransitionV2",
            "input": {
                "kind": "ApplicationEntryWorldV2",
                "application_slot": application["application_slot"],
            },
            "transition": transition,
        },
        "nominal_index": {
            "kind": "LegacyNominalIndexExprV2",
            "value": {"kind": "NoNominalIndexV1"},
        },
        "provenance": provenance,
        "capture": capture,
        "usage": None,
    }


def validate_task28_path_and_qualification_regressions() -> int:
    """Exercise task #28 groups 1-2 through complete root contracts."""

    directory = INTERFACES
    choose = load_json(directory / "choose-once-function-contract.json")
    q_oracle = load_json(directory / "q-lambda-call-install.json")
    old_hash = q_oracle["imports"][0]["artifact_hash"]

    multi_return = copy.deepcopy(choose)
    second_return = copy.deepcopy(multi_return["computation"]["paths"][0])
    second_return["outcome"]["result_transformer"] = {
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
    multi_return["computation"]["paths"].append(second_return)
    validate_function_contract(multi_return)
    multi_hash = canonical_hash(multi_return)
    multi_reference = {
        "artifact_hash": multi_hash,
        "kind": "ImportedFunctionRefV2",
        "module": ["library"],
        "name": "choose_once",
    }
    mismatched_consumer = copy.deepcopy(q_oracle["contract"])
    replace_imported_contract_reference(
        mismatched_consumer, old_hash, multi_reference,
    )
    multi_imports = single_import_scope(
        multi_hash, multi_return, ("library",), "choose_once",
    )
    expect_diagnostic(
        "task28 concrete all-Returns projection",
        "contract-parameter-inconsistent-instantiation",
        lambda: validate_function_contract(
            mismatched_consumer, imports=multi_imports,
        ),
    )

    baseline_imports = resolve_imports(q_oracle, directory)
    mixed_join = copy.deepcopy(q_oracle["contract"])
    terminal_path = copy.deepcopy(
        mixed_join["computation"]["continuation"]["continuation"]["paths"][0]
    )
    terminal_path["outcome"] = {
        "kind": "AbortsV2",
        "origin": "task28:mixed-terminal-join",
    }
    mixed_join["computation"]["prefix"] = {
        "kind": "JoinV2",
        "members": [
            mixed_join["computation"]["prefix"],
            {"kind": "LiteralPathsV2", "paths": [terminal_path]},
        ],
    }
    validate_function_contract(mixed_join, imports=baseline_imports)
    mixed_outcomes = [
        item["path"]["outcome"]["kind"]
        for item in evaluate_contract_computation(
            mixed_join, imports=baseline_imports,
        )
    ]
    require(
        mixed_outcomes == ["AbortsV2", "ReturnsV2"],
        "task28 mixed terminal Join did not bypass the ReturnBinder",
    )

    hof_oracle = load_json(directory / "hof-mixed-later.json")
    hof_imports = resolve_imports(hof_oracle, directory)
    nested_consumer = copy.deepcopy(hof_oracle["consumer_contract"])
    nested_application = nested_consumer["applications"][0]
    nested_source = hof_imports[nested_application["contract"]["artifact_hash"]]
    nested_slot = 20
    nested_binder = concrete_return_binder(
        nested_source, nested_application, nested_slot,
        imports=hof_imports, local_functions={},
    )
    nested_template = q_oracle["contract"]["computation"]["continuation"]["continuation"]["paths"][0]
    nested_consumer["computation"] = {
        "kind": "PathBindV2",
        "prefix": nested_consumer["computation"],
        "return_binder": nested_binder,
        "continuation": pure_return_continuation(nested_template, nested_slot),
        "terminal_policy": "PreserveTerminalV2",
    }
    validate_function_contract(nested_consumer, imports=hof_imports)
    nested_outcomes = [
        item["path"]["outcome"]["kind"]
        for item in evaluate_contract_computation(
            nested_consumer, imports=hof_imports,
        )
    ]
    require(
        len(nested_outcomes) == 7
        and nested_outcomes.count("ReturnsV2") == 1
        and nested_outcomes.count("AbortsV2") == 2
        and nested_outcomes.count("TransfersV2") == 4,
        "task28 nested PathBind source lost its seven-path flow",
    )

    secondary_source = copy.deepcopy(choose)
    secondary_path = secondary_source["computation"]["paths"][0]
    secondary_latent = secondary_path["LatentSites"][0]
    secondary_path["ParametricObligations"] = []
    secondary_latent["call_obligation_ids"] = []
    secondary_latent["install_obligation_ids"] = []
    secondary_latent["site_slot"] = 5
    secondary_latent["instantiated_signature"]["secondary_sites"] = {
        "kind": "Closed",
        "sites": [
            {
                "site_slot": 7,
                "receiver": copy.deepcopy(secondary_latent["receiver"]),
                "operation": copy.deepcopy(secondary_latent["operation"]),
                "route": copy.deepcopy(secondary_latent["route"]),
                "suspension": {"atoms": [], "grade": "NoSuspend"},
                "semantic_summary": {"kind": "PureV1"},
                "origin": "task28:secondary-site",
            }
        ],
    }
    secondary_demand = copy.deepcopy(secondary_path["attributed_demand"][0])
    secondary_demand["site_slot"] = 7
    secondary_demand["site_role"] = {
        "kind": "Secondary",
        "secondary_slot": 7,
    }
    secondary_path["attributed_demand"] = [secondary_demand]
    secondary_request = next(
        atom
        for atom in secondary_path["suspension"]["atoms"]
        if atom.get("kind") == "RequestV1"
    )
    secondary_request["site_slot"] = 7
    secondary_request["site_role"] = {
        "kind": "Secondary",
        "secondary_slot": 7,
    }
    validate_function_contract(secondary_source)
    secondary_hash = canonical_hash(secondary_source)
    secondary_reference = {
        "artifact_hash": secondary_hash,
        "kind": "ImportedFunctionRefV2",
        "module": ["library"],
        "name": "choose_once",
    }
    secondary_consumer = copy.deepcopy(q_oracle["contract"])
    replace_imported_contract_reference(
        secondary_consumer, old_hash, secondary_reference,
    )
    secondary_imports = single_import_scope(
        secondary_hash, secondary_source, ("library",), "choose_once",
    )
    validate_function_contract(secondary_consumer, imports=secondary_imports)
    qualified_paths = evaluate_contract_computation(
        secondary_consumer, imports=secondary_imports,
    )
    require(len(qualified_paths) == 1, "task28 secondary qualification path count")
    qualified_path = qualified_paths[0]["path"]
    secondary_sites = sorted(
        site["site_slot"]
        for latent in qualified_path["LatentSites"]
        for site in latent["instantiated_signature"]["secondary_sites"]["sites"]
    )
    secondary_references = sorted({
        node["secondary_slot"]
        for node in walk(qualified_path)
        if isinstance(node, dict) and node.get("kind") == "Secondary"
    })
    require(
        len(secondary_sites) == 2
        and len(set(secondary_sites)) == 2
        and secondary_references == secondary_sites,
        "task28 Secondary.secondary_slot qualification broke target identity",
    )
    return 4


def validate_task28_call_and_exactness_regressions() -> int:
    """Exercise task #28 groups 3-6 through complete root contracts."""

    directory = INTERFACES
    local_oracle = load_json(directory / "local-function-call.json")

    def call_case(
        label: str,
        expected: str,
        mutate: Callable[[dict[str, Any]], None],
    ) -> None:
        document = copy.deepcopy(local_oracle)
        mutate(document)
        expect_diagnostic(
            label, expected,
            lambda: validate_local_contract_oracle(document),
        )

    call_case(
        "task28 actual Parameter scope",
        "contract-projection-escapes-scope",
        lambda document: document["contract"]["applications"][0]["actual_arguments"][0].__setitem__(
            "capture",
            {
                "kind": "LegacyCaptureExprV2",
                "value": {
                    "kind": "CaptureSlotsV1",
                    "slots": [slot("Parameter", 999)],
                },
            },
        ),
    )

    def mutate_closure_scope(document: dict[str, Any]) -> None:
        obligation = document["local_declarations"][0]["contract"]["computation"]["paths"][0]["ParametricObligations"][0]["value"]
        obligation["slots"][0] = slot("ClosureCapture", 999)

    call_case(
        "task28 Call-Q ClosureCapture scope",
        "contract-projection-escapes-scope",
        mutate_closure_scope,
    )

    def mutate_boundary_environment(document: dict[str, Any]) -> None:
        actual = document["contract"]["applications"][0]["actual_arguments"][0]
        actual["provenance"] = {
            "kind": "EnvironmentV2",
            "bindings": [
                {
                    "slot": slot("Parameter", 0),
                    "type": copy.deepcopy(actual["type"]),
                    "provenance": {
                        "kind": "LegacyProvenanceExprV2",
                        "value": {"kind": "BottomProvenanceV1"},
                    },
                    "capture": {
                        "kind": "LegacyCaptureExprV2",
                        "value": {"kind": "BottomCaptureV1"},
                    },
                }
            ],
        }

    call_case(
        "task28 BoundarySafe EnvironmentV2 bottom",
        "call-obligation-unsatisfied",
        mutate_boundary_environment,
    )

    def replace_call_obligation(
        document: dict[str, Any],
        value: dict[str, Any],
    ) -> None:
        document["local_declarations"][0]["contract"]["computation"]["paths"][0]["ParametricObligations"][0]["value"] = value

    def mutate_stable_bottom(document: dict[str, Any]) -> None:
        clocked_source = load_json(
            directory / "mixed-next-callback-function-contract.json"
        )
        local_binders = document["local_declarations"][0]["contract"]["binders"]
        for field in ("owner_binders", "identity_binders", "clock_binders"):
            local_binders[field] = copy.deepcopy(clocked_source["binders"][field])
        local_binders["owner_binders"][0]["source"] = slot("Parameter", 0)
        caller_binders = document["contract"]["binders"]
        for field in ("owner_binders", "identity_binders", "clock_binders"):
            caller_binders[field] = copy.deepcopy(local_binders[field])
        substitution = document["contract"]["applications"][0]["substitution"]
        substitution["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)}
        ]
        substitution["identity_arguments"] = [
            {"binder_slot": 0, "value": slot("Identity", 0)}
        ]
        substitution["clock_arguments"] = [
            {"binder_slot": 0, "value": slot("Clock", 0)}
        ]
        replace_call_obligation(
            document,
            {
                "kind": "StableAcrossV1",
                "id": 1,
                "stage": "Call",
                "slots": [slot("Parameter", 0)],
                "clock_slot": slot("Clock", 0),
                "worlds": [],
                "origin": "task28:stable-bottom",
            },
        )
        document["contract"]["applications"][0]["actual_arguments"][0]["capture"] = {
            "kind": "LegacyCaptureExprV2",
            "value": {"kind": "BottomCaptureV1"},
        }

    call_case(
        "task28 StableAcross BottomCapture",
        "call-obligation-unsatisfied",
        mutate_stable_bottom,
    )

    def mutate_duplicable_owner(document: dict[str, Any]) -> None:
        replace_call_obligation(
            document,
            {
                "kind": "DuplicableEnvV1",
                "id": 1,
                "stage": "Call",
                "slots": [slot("Parameter", 0)],
                "site_slot": 0,
                "origin": "task28:duplicable-owner",
            },
        )
        document["contract"]["applications"][0]["actual_arguments"][0]["capture"] = {
            "kind": "LegacyCaptureExprV2",
            "value": {
                "kind": "CaptureSlotsV1",
                "slots": [slot("Owner", 0)],
            },
        }

    call_case(
        "task28 DuplicableEnv Owner capture",
        "call-obligation-unsatisfied",
        mutate_duplicable_owner,
    )

    def mutate_unproved_phase(document: dict[str, Any]) -> None:
        replace_call_obligation(
            document,
            {
                "kind": "PhaseAllowsV1",
                "id": 1,
                "stage": "Call",
                "required_phase": {
                    "allowed_phases": ["Action"],
                    "required_authorities": [],
                    "current_owner": None,
                },
                "origin": "task28:unproved-phase",
            },
        )

    call_case(
        "task28 unproved Call-stage variant",
        "call-obligation-unsatisfied",
        mutate_unproved_phase,
    )

    source_null_oracle = copy.deepcopy(local_oracle)
    source_null_source = source_null_oracle["local_declarations"][0]["contract"]
    source_null_source["computation"]["paths"][0]["outcome"]["result_transformer"] = {
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
    source_null_contract = source_null_oracle["contract"]
    source_null_application = source_null_contract["applications"][0]
    source_null_locals = {0: source_null_source}
    source_null_slot = 20
    source_null_binder = concrete_return_binder(
        source_null_source, source_null_application, source_null_slot,
        imports=ImportScope(), local_functions=source_null_locals,
    )
    source_null_template = source_null_contract["computation"]["members"][0]["paths"][0]
    source_null_contract["computation"] = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": source_null_binder,
        "continuation": pure_return_continuation(
            source_null_template, source_null_slot,
        ),
        "terminal_policy": "PreserveTerminalV2",
    }
    validate_function_contract(
        source_null_source, local_functions=source_null_locals,
    )
    validate_function_contract(
        source_null_contract, local_functions=source_null_locals,
    )
    source_null_paths = evaluate_contract_computation(
        source_null_contract, imports=ImportScope(),
        local_functions=source_null_locals,
    )
    require(
        len(source_null_paths) == 1
        and source_null_paths[0]["path"]["outcome"]["kind"] == "ReturnsV2",
        "task28 source:null ParametricResultV2 did not evaluate to ReturnsV2",
    )

    def mutate_legacy_cleanup(document: dict[str, Any]) -> None:
        replace_call_obligation(
            document,
            {
                "kind": "ReplayableCleanupV1",
                "id": 1,
                "stage": "Call",
                "site_slot": 0,
                "cleanup": {
                    "residual_row": {"kind": "EmptyV1"},
                    "attributed_demand": [],
                    "transition": {"kind": "ReturnWorldV2", "return_slot": 0},
                    "suspension": {"atoms": [], "grade": "NoSuspend"},
                    "semantic_summary": {"kind": "PureV1"},
                },
                "origin": "task28:legacy-cleanup-v2-transition",
            },
        )

    call_case(
        "task28 Legacy cleanup hides V2 transition",
        "unsupported-contract-schema-version",
        mutate_legacy_cleanup,
    )

    choose = load_json(directory / "choose-once-function-contract.json")

    def validate_unbound_signature() -> None:
        contract = copy.deepcopy(choose)
        latent = contract["computation"]["paths"][0]["LatentSites"][0]
        unbound_type = {"kind": "TypeParameterV2", "slot": 999}
        latent["actual_arguments"][0]["type"] = copy.deepcopy(unbound_type)
        latent["instantiated_signature"]["parameters"][0] = unbound_type
        validate_function_contract(contract)

    expect_diagnostic(
        "task28 operation signature unbound TypeParameterV2",
        "contract-projection-escapes-scope",
        validate_unbound_signature,
    )

    def validate_extra_declaration_kind() -> None:
        contract = copy.deepcopy(choose)
        contract["declaration_kind"]["extra"] = True
        validate_function_contract(contract)

    expect_diagnostic(
        "task28 declaration kind extra field",
        "contract-component-kind-mismatch",
        validate_extra_declaration_kind,
    )

    def validate_forged_visible_row() -> None:
        contract = copy.deepcopy(choose)
        contract["declaration_kind"]["visible_row"] = {
            "kind": "ReturnSlotRefV2",
            "return_slot": 0,
        }
        validate_function_contract(contract)

    expect_diagnostic(
        "task28 declaration kind forged visible row",
        "contract-parameter-inconsistent-instantiation",
        validate_forged_visible_row,
    )

    hof_oracle = load_json(directory / "hof-mixed-later.json")
    hof_imports = resolve_imports(hof_oracle, directory)
    pass_through = copy.deepcopy(hof_oracle["consumer_contract"])
    callback_hash = next(
        entry["artifact_hash"]
        for entry in hof_oracle["imports"]
        if entry["function_name"] == "mixed_next_callback"
    )
    callback_source = hof_imports[callback_hash]
    pass_through_binder = copy.deepcopy(
        hof_oracle["contract"]["binders"]["contract_binders"][0]
    )
    pass_through["binders"]["contract_binders"] = [pass_through_binder]
    pass_through_reference = {
        "kind": "ContractParameterRefV2",
        "parameter": {
            "slot": pass_through_binder["slot"],
            "kind": binder_kind(pass_through_binder),
        },
    }
    replace_imported_contract_reference(
        pass_through, callback_hash, pass_through_reference,
    )
    validate_function_contract(pass_through, imports=hof_imports)
    pass_through_paths = evaluate_contract_computation(
        pass_through, imports=hof_imports,
        contract_environment={pass_through_binder["slot"]: callback_source},
    )
    require(
        len(pass_through_paths) == 7
        and sum(
            item["path"]["outcome"]["kind"] == "ReturnsV2"
            for item in pass_through_paths
        ) == 1,
        "task28 pass-through ContractParameter did not evaluate seven paths",
    )
    pass_through_application = pass_through["applications"][0]
    pass_through_source = hof_imports[
        pass_through_application["contract"]["artifact_hash"]
    ]
    pass_through_slot = 21
    pass_through_binder_result = concrete_return_binder(
        pass_through_source, pass_through_application, pass_through_slot,
        imports=hof_imports, local_functions={},
    )
    continuation_template = local_oracle["contract"]["computation"]["members"][0]["paths"][0]
    pass_through["computation"] = {
        "kind": "PathBindV2",
        "prefix": pass_through["computation"],
        "return_binder": pass_through_binder_result,
        "continuation": pure_return_continuation(
            continuation_template, pass_through_slot,
        ),
        "terminal_policy": "PreserveTerminalV2",
    }
    validate_function_contract(pass_through, imports=hof_imports)
    wrapped_pass_through_paths = evaluate_contract_computation(
        pass_through, imports=hof_imports,
        contract_environment={pass_through_binder["slot"]: callback_source},
    )
    require(
        len(wrapped_pass_through_paths) == 7
        and sum(
            item["path"]["outcome"]["kind"] == "ReturnsV2"
            for item in wrapped_pass_through_paths
        ) == 1,
        "task28 pass-through PathBind did not preserve seven paths",
    )
    return 13


def validate_task28_regressions() -> int:
    return (
        validate_task28_path_and_qualification_regressions()
        + validate_task28_call_and_exactness_regressions()
    )


def validate_task29_regressions() -> int:
    """Exercise the four adjacent task #29 groups through complete roots."""

    directory = INTERFACES
    local_oracle = load_json(directory / "local-function-call.json")

    def local_pair(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        return document["local_declarations"][0]["contract"], document["contract"]

    def call_case(
        label: str,
        expected: str,
        mutate: Callable[[dict[str, Any]], None],
    ) -> None:
        document = copy.deepcopy(local_oracle)
        mutate(document)
        expect_diagnostic(
            label, expected,
            lambda: validate_local_contract_oracle(document),
        )

    # A legal PathBind term remains a legal recursively typed prefix.
    nested_document = copy.deepcopy(local_oracle)
    nested_source, nested_consumer = local_pair(nested_document)
    nested_locals = {0: nested_source}
    nested_application = nested_consumer["applications"][0]
    nested_template = nested_consumer["computation"]["members"][0]["paths"][0]
    inner_binder = concrete_return_binder(
        nested_source, nested_application, 20,
        imports=ImportScope(), local_functions=nested_locals,
    )
    inner = {
        "kind": "PathBindV2",
        "prefix": {"kind": "InvokeV2", "application_slot": 0},
        "return_binder": inner_binder,
        "continuation": pure_return_continuation(nested_template, 20),
        "terminal_policy": "PreserveTerminalV2",
    }
    outer_binder = copy.deepcopy(inner_binder)
    outer_binder["slot"] = 21
    nested_consumer["computation"] = {
        "kind": "PathBindV2",
        "prefix": inner,
        "return_binder": outer_binder,
        "continuation": pure_return_continuation(nested_template, 21),
        "terminal_policy": "PreserveTerminalV2",
    }
    validate_function_contract(nested_consumer, local_functions=nested_locals)
    nested_paths = evaluate_contract_computation(
        nested_consumer, imports=ImportScope(), local_functions=nested_locals,
    )
    require(
        [item["path"]["outcome"]["kind"] for item in nested_paths]
        == ["ReturnsV2"],
        "task29 nested local PathBind prefix lost its ReturnsV2 path",
    )

    hof_oracle = load_json(directory / "hof-mixed-later.json")
    hof_imports = resolve_imports(hof_oracle, directory)
    nested_hof = copy.deepcopy(hof_oracle["contract"])
    nested_hof_binder = copy.deepcopy(
        nested_hof["computation"]["continuation"]["return_binder"]
    )
    nested_hof_binder["slot"] = 21
    nested_hof_template = nested_hof["computation"]["continuation"]["continuation"]["paths"][0]
    nested_hof["computation"] = {
        "kind": "PathBindV2",
        "prefix": nested_hof["computation"],
        "return_binder": nested_hof_binder,
        "continuation": pure_return_continuation(nested_hof_template, 21),
        "terminal_policy": "PreserveTerminalV2",
    }
    validate_function_contract(nested_hof, imports=hof_imports)
    nested_hof_callback_hash = next(
        entry["artifact_hash"]
        for entry in hof_oracle["imports"]
        if entry["function_name"] == "mixed_next_callback"
    )
    nested_hof_paths = evaluate_contract_computation(
        nested_hof, imports=hof_imports,
        contract_environment={0: hof_imports[nested_hof_callback_hash]},
    )
    nested_hof_outcomes = [
        item["path"]["outcome"]["kind"] for item in nested_hof_paths
    ]
    require(
        len(nested_hof_outcomes) == 7
        and nested_hof_outcomes.count("ReturnsV2") == 1
        and nested_hof_outcomes.count("AbortsV2") == 2
        and nested_hof_outcomes.count("TransfersV2") == 4,
        "task29 nested generic PathBind prefix lost its seven-path flow",
    )

    def mutate_boundary_callback(document: dict[str, Any]) -> None:
        source, caller = local_pair(document)
        obligation = source["computation"]["paths"][0]["ParametricObligations"][0]["value"]
        obligation["boundary"] = "Suspension"
        caller["applications"][0]["actual_arguments"][0]["provenance"] = {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "CallbackV1", "site_slot": 0},
        }

    call_case(
        "task29 BoundarySafe Suspension callback",
        "call-obligation-unsatisfied",
        mutate_boundary_callback,
    )

    def mutate_owner_formal(document: dict[str, Any]) -> None:
        source, caller = local_pair(document)
        for contract in (source, caller):
            contract["binders"]["owner_binders"] = [
                {"slot": 0, "source": slot("Parameter", 0)}
            ]
        caller["applications"][0]["substitution"]["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)}
        ]
        source["computation"]["paths"][0]["ParametricObligations"][0]["value"]["slots"] = [
            slot("Owner", 0)
        ]

    call_case(
        "task29 Call-Q Owner formal cannot discharge vacuously",
        "call-obligation-unsatisfied",
        mutate_owner_formal,
    )

    def operation_argument_capture() -> dict[str, Any]:
        return {
            "kind": "LegacyCaptureExprV2",
            "value": {
                "kind": "CaptureSlotsV1",
                "slots": [slot("OperationArgument", 999)],
            },
        }

    call_case(
        "task29 application OperationArgument scope",
        "contract-projection-escapes-scope",
        lambda document: document["contract"]["applications"][0]["actual_arguments"][0].__setitem__(
            "capture", operation_argument_capture(),
        ),
    )

    choose = load_json(directory / "choose-once-function-contract.json")

    def malformed_latent_operation_argument() -> None:
        contract = copy.deepcopy(choose)
        contract["computation"]["paths"][0]["LatentSites"][0]["actual_arguments"][0]["capture"] = operation_argument_capture()
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 latent OperationArgument scope",
        "contract-projection-escapes-scope",
        malformed_latent_operation_argument,
    )

    def mutate_duplicable_operation_argument(document: dict[str, Any]) -> None:
        source, caller = local_pair(document)
        source["computation"]["paths"][0]["ParametricObligations"][0]["value"] = {
            "kind": "DuplicableEnvV1",
            "id": 1,
            "stage": "Call",
            "slots": [slot("Parameter", 0)],
            "site_slot": 0,
            "origin": "task29:duplicable-operation-argument",
        }
        caller["applications"][0]["actual_arguments"][0]["capture"] = operation_argument_capture()

    call_case(
        "task29 DuplicableEnv malformed OperationArgument",
        "contract-projection-escapes-scope",
        mutate_duplicable_operation_argument,
    )

    def add_clock_binders(contract: dict[str, Any]) -> None:
        contract["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)}
        ]
        contract["binders"]["identity_binders"] = [
            {
                "binder": "FreshCap",
                "family": {
                    "arguments": [],
                    "kind": "NominalTypeV1",
                    "module": ["cire", "temporal"],
                    "name": "FrameClock",
                },
                "identity_slot": 0,
                "owner": slot("Owner", 0),
            }
        ]
        contract["binders"]["clock_binders"] = [
            {
                "identity": slot("Identity", 0),
                "owner": slot("Owner", 0),
                "slot": 0,
            }
        ]

    def install_stable_obligation(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        source, caller = local_pair(document)
        add_clock_binders(source)
        add_clock_binders(caller)
        source["computation"]["paths"][0]["ParametricObligations"][0]["value"] = {
            "kind": "StableAcrossV1",
            "id": 1,
            "stage": "Call",
            "slots": [slot("Parameter", 0)],
            "clock_slot": slot("Clock", 0),
            "worlds": [],
            "origin": "task29:stable-across",
        }
        substitution = caller["applications"][0]["substitution"]
        substitution["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)}
        ]
        substitution["identity_arguments"] = [
            {"binder_slot": 0, "value": slot("Identity", 0)}
        ]
        substitution["clock_arguments"] = [
            {"binder_slot": 0, "value": slot("Clock", 0)}
        ]
        return source, caller

    def mutate_stable_owner(document: dict[str, Any]) -> None:
        _, caller = install_stable_obligation(document)
        actual = caller["applications"][0]["actual_arguments"][0]
        actual["provenance"] = {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "StableV1"},
        }
        actual["capture"] = {
            "kind": "LegacyCaptureExprV2",
            "value": {
                "kind": "CaptureSlotsV1",
                "slots": [slot("Owner", 0)],
            },
        }

    call_case(
        "task29 StableAcross Owner capture lacks witness",
        "call-obligation-unsatisfied",
        mutate_stable_owner,
    )

    stable_environment = copy.deepcopy(local_oracle)
    _, stable_caller = install_stable_obligation(stable_environment)
    stable_actual = stable_caller["applications"][0]["actual_arguments"][0]
    stable_actual["provenance"] = {
        "kind": "EnvironmentV2",
        "bindings": [
            {
                "slot": slot("Parameter", 0),
                "type": copy.deepcopy(stable_actual["type"]),
                "provenance": {
                    "kind": "LegacyProvenanceExprV2",
                    "value": {"kind": "StableV1"},
                },
                "capture": {
                    "kind": "LegacyCaptureExprV2",
                    "value": {"kind": "NoCaptureV1"},
                },
            }
        ],
    }
    validate_local_contract_oracle(stable_environment)

    def declaration_cross_kind() -> None:
        contract = copy.deepcopy(choose)
        contract["binders"]["type_binders"][0]["kind"] = "Effect"
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 declaration TypeParameter resolved by Effect binder",
        "contract-projection-escapes-scope",
        declaration_cross_kind,
    )

    def operation_cross_kind() -> None:
        contract = copy.deepcopy(choose)
        latent = contract["computation"]["paths"][0]["LatentSites"][0]
        type_parameter = {"kind": "TypeParameterV2", "slot": 999}
        latent["instantiated_signature"]["type_binders"] = [
            {"slot": 999, "kind": "Effect"}
        ]
        latent["actual_arguments"][0]["type"] = copy.deepcopy(type_parameter)
        latent["instantiated_signature"]["parameters"][0] = type_parameter
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 operation TypeParameter resolved by Effect binder",
        "contract-projection-escapes-scope",
        operation_cross_kind,
    )

    def malformed_type_binder_kind() -> None:
        contract = copy.deepcopy(choose)
        signature = contract["computation"]["paths"][0]["LatentSites"][0]["instantiated_signature"]
        signature["type_binders"] = [
            {
                "slot": 0,
                "kind": {"kind": "ReturnSlotRefV2", "return_slot": 0},
            }
        ]
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 object-valued TypeBinder kind",
        "contract-component-kind-mismatch",
        malformed_type_binder_kind,
    )

    def malformed_legacy_origin() -> None:
        contract = load_json(directory / "mixed-next-callback-function-contract.json")
        obligation = contract["computation"]["prefix"]["paths"][0]["ParametricObligations"][0]["value"]
        obligation["origin"] = {"kind": "ReturnSlotRefV2", "return_slot": 0}
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 object-valued Legacy Q origin",
        "contract-component-kind-mismatch",
        malformed_legacy_origin,
    )

    def malformed_closure_capture() -> None:
        contract = load_json(directory / "mixed-next-callback-function-contract.json")
        contract["closure_environment"][0]["capture"] = {"kind": "UnknownCaptureV9"}
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 malformed root closure capture",
        "contract-component-kind-mismatch",
        malformed_closure_capture,
    )

    def unknown_declaration_kind() -> None:
        contract = copy.deepcopy(choose)
        contract["declaration_kind"]["kind"] = "UnknownContractKindV2"
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 unknown root declaration kind",
        "contract-component-kind-mismatch",
        unknown_declaration_kind,
    )

    def unknown_signature_mode() -> None:
        contract = copy.deepcopy(choose)
        contract["computation"]["paths"][0]["LatentSites"][0]["instantiated_signature"]["mode"] = "unknown"
        validate_function_contract(contract)

    expect_diagnostic(
        "task29 unknown operation signature mode",
        "contract-component-kind-mismatch",
        unknown_signature_mode,
    )

    return 16


def validate_task30_regressions() -> int:
    """Exercise task #30 boundary, shadowing, and exact-wire neighbors."""

    directory = INTERFACES
    local_oracle = load_json(directory / "local-function-call.json")

    def local_pair(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        return document["local_declarations"][0]["contract"], document["contract"]

    def owner_boundary_document(
        boundary: str,
        *,
        provenance_kind: str,
        owner_capture: bool,
    ) -> dict[str, Any]:
        document = copy.deepcopy(local_oracle)
        source, caller = local_pair(document)
        caller["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)}
        ]
        source["computation"]["paths"][0]["ParametricObligations"][0]["value"]["boundary"] = boundary
        actual = caller["applications"][0]["actual_arguments"][0]
        if provenance_kind == "StableV1":
            provenance_value = {"kind": "StableV1"}
        else:
            provenance_value = {
                "kind": provenance_kind,
                "owner": slot("Owner", 0),
            }
        actual["provenance"] = {
            "kind": "LegacyProvenanceExprV2",
            "value": provenance_value,
        }
        if owner_capture:
            actual["capture"] = {
                "kind": "LegacyCaptureExprV2",
                "value": {
                    "kind": "CaptureSlotsV1",
                    "slots": [slot("Owner", 0)],
                },
            }
        return document

    expect_diagnostic(
        "task30 BoundarySafe Suspension Owner provenance",
        "call-obligation-unsatisfied",
        lambda: validate_local_contract_oracle(
            owner_boundary_document(
                "Suspension", provenance_kind="OwnerV1", owner_capture=False,
            )
        ),
    )
    validate_local_contract_oracle(
        owner_boundary_document(
            "CallArgument", provenance_kind="OwnerV1", owner_capture=False,
        )
    )
    expect_diagnostic(
        "task30 BoundarySafe OwnerStorage Owner capture",
        "call-obligation-unsatisfied",
        lambda: validate_local_contract_oracle(
            owner_boundary_document(
                "OwnerStorage", provenance_kind="StableV1", owner_capture=True,
            )
        ),
    )
    validate_local_contract_oracle(
        owner_boundary_document(
            "CallArgument", provenance_kind="StableV1", owner_capture=True,
        )
    )
    for provenance_kind in ("RegionV1", "GenerationBoundV1"):
        expect_diagnostic(
            f"task30 BoundarySafe Suspension {provenance_kind}",
            "call-obligation-unsatisfied",
            lambda provenance_kind=provenance_kind: validate_local_contract_oracle(
                owner_boundary_document(
                    "Suspension",
                    provenance_kind=provenance_kind,
                    owner_capture=False,
                )
            ),
        )
        validate_local_contract_oracle(
            owner_boundary_document(
                "CallArgument",
                provenance_kind=provenance_kind,
                owner_capture=False,
            )
        )

    def phase_document(allowed_phases: list[str]) -> dict[str, Any]:
        document = copy.deepcopy(local_oracle)
        source, _ = local_pair(document)
        source["computation"]["paths"][0]["ParametricObligations"][0]["value"] = {
            "kind": "PhaseAllowsV1",
            "id": 1,
            "stage": "Call",
            "required_phase": {
                "allowed_phases": allowed_phases,
                "required_authorities": [],
                "current_owner": None,
            },
            "origin": "task30:phase-allows",
        }
        return document

    validate_local_contract_oracle(
        phase_document(["Pure", "Compute", "Action", "Commit"])
    )
    expect_diagnostic(
        "task30 nontrivial Call PhaseAllows lacks phase evidence",
        "call-obligation-unsatisfied",
        lambda: validate_local_contract_oracle(phase_document(["Action"])),
    )

    choose = load_json(directory / "choose-once-function-contract.json")

    def operation_shadow(kind: str) -> None:
        contract = copy.deepcopy(choose)
        signature = contract["computation"]["paths"][0]["LatentSites"][0]["instantiated_signature"]
        signature["type_binders"] = [{"slot": 0, "kind": kind}]
        validate_function_contract(contract)

    operation_shadow("Type")
    expect_diagnostic(
        "task30 local Effect binder shadows ambient Type binder",
        "contract-projection-escapes-scope",
        lambda: operation_shadow("Effect"),
    )

    def malformed_origin(origin: str) -> None:
        contract = copy.deepcopy(choose)
        contract["computation"]["paths"][0]["ParametricObligations"][0]["value"]["origin"] = origin
        validate_function_contract(contract)

    expect_diagnostic(
        "task30 SourceOrigin lacks file:subject separator",
        "contract-component-kind-mismatch",
        lambda: malformed_origin("not-a-canonical-origin"),
    )
    expect_diagnostic(
        "task30 SourceOrigin is empty",
        "contract-component-kind-mismatch",
        lambda: malformed_origin(""),
    )

    def wrong_closure_namespace() -> None:
        contract = load_json(
            directory / "mixed-next-callback-function-contract.json"
        )
        contract["closure_environment"][0]["slot"]["namespace"] = "Parameter"
        validate_function_contract(contract)

    expect_diagnostic(
        "task30 root closure slot namespace",
        "contract-component-kind-mismatch",
        wrong_closure_namespace,
    )
    return 15


def validate_task31_regressions() -> int:
    """Exercise task #31 Call-Q, authority, scope, and exact-wire roots."""

    directory = INTERFACES
    local_oracle = load_json(directory / "local-function-call.json")

    def local_document() -> dict[str, Any]:
        return copy.deepcopy(local_oracle)

    def local_pair(
        document: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        return document["local_declarations"][0]["contract"], document["contract"]

    def source_call_obligation(source: dict[str, Any]) -> dict[str, Any]:
        return source["computation"]["paths"][0]["ParametricObligations"][0]

    def collapsed_actual_outlives() -> None:
        document = local_document()
        source, caller = local_pair(document)
        application = caller["applications"][0]
        caller["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)}
        ]
        parameter_type = copy.deepcopy(
            source["binders"]["parameter_binders"][0]["type"]
        )
        argument_pack = {
            "kind": "ApplyTypeV2",
            "constructor": {
                "kind": "NominalConstructorV1",
                "module": ["fixtures"],
                "name": "Task31Arguments",
            },
            "arguments": [
                copy.deepcopy(parameter_type), copy.deepcopy(parameter_type),
            ],
        }
        source["declaration_kind"]["parameter_type"] = copy.deepcopy(
            argument_pack
        )
        source["binders"]["parameter_binders"].append(
            {"slot": 1, "type": copy.deepcopy(parameter_type)}
        )
        application["callee_summary"]["type"]["parameter"] = copy.deepcopy(
            argument_pack
        )
        first_actual = application["actual_arguments"][0]
        first_actual["provenance"] = {
            "kind": "LegacyProvenanceExprV2",
            "value": {"kind": "OwnerV1", "owner": slot("Owner", 0)},
        }
        application["actual_arguments"].append(copy.deepcopy(first_actual))
        source_call_obligation(source)["value"] = {
            "kind": "OutlivesV1",
            "id": 1,
            "stage": "Call",
            "shorter": slot("Parameter", 0),
            "longer": slot("Parameter", 1),
            "origin": "task31:reflexive-outlives",
        }
        validate_local_contract_oracle(document)

    def empty_row_lacks() -> None:
        document = local_document()
        source, caller = local_pair(document)
        entry = {
            "kind": "AnonV1",
            "family": {
                "kind": "NominalTypeV1",
                "module": ["library"],
                "name": "Choice",
                "arguments": [],
            },
        }
        source["binders"]["row_binders"] = [
            {"slot": 0, "lacks": [copy.deepcopy(entry)]}
        ]
        caller["applications"][0]["substitution"]["row_arguments"] = [
            {"binder_slot": 0, "value": {"kind": "EmptyV1"}}
        ]
        source_call_obligation(source)["value"] = {
            "kind": "RowLacksV1",
            "id": 1,
            "stage": "Call",
            "row_slot": slot("Row", 0),
            "entry": entry,
            "origin": "task31:empty-row-lacks",
        }
        validate_local_contract_oracle(document)

    def forged_non_authority_usage() -> None:
        document = local_document()
        source, caller = local_pair(document)
        source_call_obligation(source)["value"] = {
            "kind": "DuplicableEnvV1",
            "id": 1,
            "stage": "Call",
            "slots": [slot("Parameter", 0)],
            "site_slot": 0,
            "origin": "task31:non-authority-usage",
        }
        caller["applications"][0]["actual_arguments"][0]["usage"] = {
            "kind": "LegacyUsageExprV2",
            "value": {"slot": slot("Parameter", 0), "kind": "Many"},
        }
        validate_local_contract_oracle(document)

    validate_local_contract_oracle(local_document())
    collapsed_actual_outlives()
    empty_row_lacks()
    expect_diagnostic(
        "task31 ordinary Int cannot forge Many usage",
        "contract-component-kind-mismatch",
        forged_non_authority_usage,
    )

    choose = load_json(directory / "choose-once-function-contract.json")

    def legacy_parameter_shadow(kind: str) -> None:
        contract = copy.deepcopy(choose)
        latent = contract["computation"]["paths"][0]["LatentSites"][0]
        signature = latent["instantiated_signature"]
        signature["type_binders"] = [{"slot": 0, "kind": kind}]
        legacy_parameter = {
            "kind": "LegacyTypeRefV2",
            "value": {"kind": "TypeParameterV1", "slot": 0},
        }
        parameter = copy.deepcopy(signature["parameters"][0])
        parameter["arguments"][0] = copy.deepcopy(legacy_parameter)
        signature["parameters"] = [parameter]
        signature["result"] = copy.deepcopy(legacy_parameter)
        latent["actual_arguments"][0]["type"] = copy.deepcopy(parameter)
        validate_function_contract(contract)

    legacy_parameter_shadow("Type")
    expect_diagnostic(
        "task31 legacy TypeParameterV1 obeys Effect shadow",
        "contract-projection-escapes-scope",
        lambda: legacy_parameter_shadow("Effect"),
    )

    def malformed_closure_subnode(mode: str) -> None:
        contract = load_json(
            directory / "mixed-next-callback-function-contract.json"
        )
        binding = contract["closure_environment"][0]
        if mode == "slot-extra":
            binding["slot"]["extra"] = True
        else:
            binding["capture"]["extra"] = True
        validate_function_contract(contract)

    expect_diagnostic(
        "task31 closure SlotRefV1 exact fields",
        "contract-component-kind-mismatch",
        lambda: malformed_closure_subnode("slot-extra"),
    )
    expect_diagnostic(
        "task31 closure LegacyCaptureExprV2 exact fields",
        "contract-component-kind-mismatch",
        lambda: malformed_closure_subnode("capture-extra"),
    )

    def malformed_child_owner_origin() -> None:
        oracle = load_json(directory / "clock-package-paths.json")
        oracle["package"]["owner_relation"]["sealed_origin"] = ""
        validate_clock_oracle(oracle)

    expect_diagnostic(
        "task31 child Owner sealed origin",
        "contract-component-kind-mismatch",
        malformed_child_owner_origin,
    )

    def path_bind(
        prefix: dict[str, Any],
        binder: dict[str, Any],
        continuation: dict[str, Any],
    ) -> dict[str, Any]:
        return {
            "kind": "PathBindV2",
            "prefix": prefix,
            "return_binder": binder,
            "continuation": continuation,
            "terminal_policy": "PreserveTerminalV2",
        }

    def lexical_outer_return(*, evaluate: bool) -> list[str] | None:
        document = local_document()
        source, consumer = local_pair(document)
        local_functions = {0: source}
        template = copy.deepcopy(
            consumer["computation"]["members"][0]["paths"][0]
        )
        application0 = copy.deepcopy(consumer["applications"][0])
        application1 = copy.deepcopy(application0)
        application1["application_slot"] = 1
        application1["entry_world"]["application_slot"] = 1
        consumer["applications"] = [application0, application1]

        def return_binder(
            application: dict[str, Any], number: int,
        ) -> dict[str, Any]:
            return concrete_return_binder(
                source, application, number,
                imports=ImportScope(), local_functions=local_functions,
            )

        binder10 = return_binder(application0, 10)
        binder11 = return_binder(application1, 11)
        inner = path_bind(
            {"kind": "InvokeV2", "application_slot": 1},
            binder11,
            pure_return_continuation(template, 10),
        )
        binder12 = copy.deepcopy(binder10)
        binder12["slot"] = 12
        middle = path_bind(
            inner, binder12, pure_return_continuation(template, 12),
        )
        consumer["computation"] = path_bind(
            {"kind": "InvokeV2", "application_slot": 0}, binder10, middle,
        )
        if not evaluate:
            validate_function_contract(
                consumer, local_functions=local_functions,
            )
            return None
        return [
            item["path"]["outcome"]["kind"]
            for item in evaluate_contract_computation(
                consumer, imports=ImportScope(), local_functions=local_functions,
            )
        ]

    lexical_outer_return(evaluate=False)
    require(
        lexical_outer_return(evaluate=True) == ["ReturnsV2"],
        "task31 nested lexical ReturnBound evaluator control",
    )
    return 11


def validate_task33_regressions() -> int:
    """Exercise task #33 usage, Call-Q, replay, scope, and exact-wire roots."""

    directory = INTERFACES

    def handler_usage_grade(kind: str) -> None:
        document = load_json(directory / "handler-forward-contract.json")
        usage = document["handler_contract"]["clause_computations"][0][
            "computation"
        ]["continuation"]["paths"][0]["usage"][0]
        usage["value"]["kind"] = kind
        validate_handler_oracle(document, directory)

    handler_usage_grade("Once")
    expect_diagnostic(
        "task33 Resume Once authority cannot be recorded as Many",
        "contract-component-kind-mismatch",
        lambda: handler_usage_grade("Many"),
    )
    expect_diagnostic(
        "task33 explicit Zero UsageV1 is noncanonical",
        "contract-component-kind-mismatch",
        lambda: handler_usage_grade("Zero"),
    )

    local_oracle = load_json(directory / "local-function-call.json")

    def generic_row_tail(*, v2: bool, caller_has_evidence: bool) -> None:
        document = copy.deepcopy(local_oracle)
        source = document["local_declarations"][0]["contract"]
        caller = document["contract"]
        entry = {
            "kind": "AnonV1",
            "family": {
                "kind": "NominalTypeV1",
                "module": ["library"],
                "name": "Choice",
                "arguments": [],
            },
        }
        source["binders"]["row_binders"] = [
            {"slot": 0, "lacks": [copy.deepcopy(entry)]},
        ]
        caller["binders"]["row_binders"] = [
            {
                "slot": 1,
                "lacks": [copy.deepcopy(entry)] if caller_has_evidence else [],
            },
        ]
        caller["applications"][0]["substitution"]["row_arguments"] = [
            {
                "binder_slot": 0,
                "value": {"kind": "TailV1", "row_slot": slot("Row", 1)},
            },
        ]
        obligation = {
            "kind": "RowLacksV2" if v2 else "RowLacksV1",
            "id": 1,
            "stage": "Call",
            "row_slot": slot("Row", 0),
            "entry": copy.deepcopy(entry),
            "origin": "task33:generic-row-tail-lacks",
        }
        source_obligation = source["computation"]["paths"][0][
            "ParametricObligations"
        ][0]
        if v2:
            source["computation"]["paths"][0]["ParametricObligations"][0] = (
                obligation
            )
        else:
            source_obligation["value"] = obligation
        validate_local_contract_oracle(document)

    generic_row_tail(v2=False, caller_has_evidence=True)
    generic_row_tail(v2=True, caller_has_evidence=True)
    expect_diagnostic(
        "task33 generic TailV1 requires caller Lacks evidence",
        "call-obligation-unsatisfied",
        lambda: generic_row_tail(v2=False, caller_has_evidence=False),
    )

    def replayable_documents(
        mode: str,
    ) -> tuple[dict[str, Any], dict[str, Any], str]:
        handler = load_json(directory / "handler-forward-contract.json")
        source = load_json(directory / "choose-once-function-contract.json")
        source_path = source["computation"]["paths"][0]
        site = source_path["LatentSites"][0]
        neutral = copy.deepcopy(site["suffix"]["cleanup"])
        obligation_cleanup = copy.deepcopy(neutral)
        if mode in {"mismatched-cleanup", "nonneutral-cleanup"}:
            obligation_cleanup["suspension"] = {
                "atoms": [
                    {
                        "kind": "DirectV1",
                        "grade": "MaySuspend",
                        "origin": "task33:replayable-cleanup",
                    }
                ],
                "grade": "MaySuspend",
            }
        if mode == "nonneutral-cleanup":
            site["suffix"]["cleanup"] = copy.deepcopy(obligation_cleanup)
        source_path["ParametricObligations"][0] = {
            "kind": "LegacyObligationV2",
            "value": {
                "kind": "ReplayableCleanupV1",
                "id": 0,
                "stage": "Call",
                "site_slot": 999 if mode == "missing-site" else site["site_slot"],
                "cleanup": obligation_cleanup,
                "origin": "task33:replayable-cleanup",
            },
        }
        if mode == "nonempty-environment":
            source["binders"]["owner_binders"] = [
                {"slot": 0, "source": slot("Parameter", 0)},
            ]
            resume_type = copy.deepcopy(
                handler["handler_contract"]["clause_computations"][0][
                    "disposition_binder"
                ]["type"]
            )
            stable = {
                "kind": "LegacyProvenanceExprV2",
                "value": {"kind": "StableV1"},
            }
            empty_capture = {
                "kind": "LegacyCaptureExprV2",
                "value": {"kind": "NoCaptureV1"},
            }
            source["closure_environment"] = [
                {
                    "slot": slot("ClosureCapture", 0),
                    "type": copy.deepcopy(resume_type),
                    "provenance": copy.deepcopy(stable),
                    "capture": copy.deepcopy(empty_capture),
                },
            ]
            site["suffix"]["live_bindings"] = [
                {
                    "slot": {
                        "kind": "LegacySlotRefV2",
                        "value": slot("ClosureCapture", 0),
                    },
                    "type": copy.deepcopy(resume_type),
                    "provenance": stable,
                    "capture": empty_capture,
                    "usage": {
                        "kind": "LegacyUsageExprV2",
                        "value": {
                            "slot": slot("ClosureCapture", 0),
                            "kind": "Once",
                        },
                    },
                },
            ]
            transformer = site["suffix"]["computation"]["paths"][0][
                "outcome"
            ]["result_transformer"]["value"]
            transformer["provenance"] = {
                "kind": "ArgumentV1",
                "argument": slot("ClosureCapture", 0),
            }
            transformer["capture"] = {
                "kind": "CaptureSlotsV1",
                "slots": [slot("ClosureCapture", 0)],
            }

        old_hash = handler["imports"][0]["artifact_hash"]
        new_hash = canonical_hash(source)

        def replace_import_hash(value: Any) -> None:
            if isinstance(value, list):
                for member in value:
                    replace_import_hash(member)
            elif isinstance(value, dict):
                if value.get("artifact_hash") == old_hash:
                    value["artifact_hash"] = new_hash
                for member in value.values():
                    replace_import_hash(member)

        replace_import_hash(handler)
        if mode == "nonempty-environment":
            handler["handler_contract"]["applications"][0]["substitution"][
                "owner_arguments"
            ] = [{"binder_slot": 0, "value": slot("Owner", 0)}]
        return handler, source, new_hash

    def validate_replayable_source(mode: str) -> None:
        _, source, _ = replayable_documents(mode)
        validate_function_contract(source)

    def validate_replayable_handler(mode: str) -> None:
        handler, source, source_hash = replayable_documents(mode)
        validate_function_contract(source)
        imports = ImportScope()
        imports[source_hash] = source
        import_entry = handler["imports"][0]
        imports.exports[source_hash] = (
            tuple(import_entry["module"]), import_entry["function_name"],
        )
        scope = declaration_scope_from_binders(handler["binders"])
        validate_handler_contract(
            handler["handler_contract"], imports=imports,
            nearest_outer_prompt_slot=1,
            type_parameter_kinds=scope.type_parameter_kinds,
            row_binders=scope.row_binders,
            contract_binders=scope.contract_binders,
            identity_binders=scope.identity_binders,
            handler_contract_binders=scope.handler_contract_binders,
            owner_binders=scope.owner_binders,
            clock_binders=scope.clock_binders,
            parameter_binders=scope.parameter_binders,
            closure_capture_binders=scope.closure_capture_binders,
        )

    validate_replayable_source("neutral")
    validate_replayable_handler("neutral")
    expect_diagnostic(
        "task33 ReplayableCleanup must equal its site's cleanup",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler("mismatched-cleanup"),
    )
    expect_diagnostic(
        "task33 ReplayableCleanup exact nonneutral cleanup is not replayable",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler("nonneutral-cleanup"),
    )
    expect_diagnostic(
        "task33 ReplayableCleanup must resolve one local site",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler("missing-site"),
    )
    validate_replayable_source("nonempty-environment")
    expect_diagnostic(
        "task33 ReplayableCleanup requires empty Pi and chi",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler("nonempty-environment"),
    )

    def nested_return_call_outlives() -> None:
        document = copy.deepcopy(local_oracle)
        base_declaration = copy.deepcopy(document["local_declarations"][0])
        base_declaration["declaration_slot"] = 1
        base = base_declaration["contract"]
        base["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        base["computation"]["paths"][0]["outcome"]["result_transformer"][
            "value"
        ]["provenance"] = {"kind": "OwnerV1", "owner": slot("Owner", 0)}

        middle = copy.deepcopy(document["contract"])
        middle["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        application = middle["applications"][0]
        application["contract"]["declaration_slot"] = 1
        application["callee_summary"]["type"]["contract"][
            "declaration_slot"
        ] = 1
        application["substitution"]["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)},
        ]
        return_binder = concrete_return_binder(
            base, application, 10, imports=ImportScope(),
            local_functions={1: base},
        )
        template = copy.deepcopy(
            document["contract"]["computation"]["members"][0]["paths"][0]
        )
        continuation = pure_return_continuation(template, 10)
        continuation["paths"][0]["ParametricObligations"] = [
            {
                "kind": "OutlivesV2",
                "id": 2,
                "stage": "Call",
                "shorter": {"kind": "ReturnSlotRefV2", "return_slot": 10},
                "longer": {"kind": "ReturnSlotRefV2", "return_slot": 10},
                "origin": "task33:return-reflexive-outlives",
            },
        ]
        middle["computation"] = {
            "kind": "PathBindV2",
            "prefix": {"kind": "InvokeV2", "application_slot": 0},
            "return_binder": return_binder,
            "continuation": continuation,
            "terminal_policy": "PreserveTerminalV2",
        }

        outer = copy.deepcopy(document["contract"])
        outer["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        outer_application = outer["applications"][0]
        outer_application["contract"]["declaration_slot"] = 0
        outer_application["callee_summary"]["type"]["contract"][
            "declaration_slot"
        ] = 0
        outer_application["substitution"]["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)},
        ]
        local_functions = {0: middle, 1: base}
        validate_function_contract(base, local_functions=local_functions)
        validate_function_contract(middle, local_functions=local_functions)
        validate_function_contract(outer, local_functions=local_functions)

    def unscoped_return_call_outlives() -> None:
        document = copy.deepcopy(local_oracle)
        source = document["local_declarations"][0]["contract"]
        source["computation"]["paths"][0]["ParametricObligations"][0] = {
            "kind": "OutlivesV2",
            "id": 2,
            "stage": "Call",
            "shorter": {"kind": "ReturnSlotRefV2", "return_slot": 99},
            "longer": {"kind": "ReturnSlotRefV2", "return_slot": 99},
            "origin": "task33:unscoped-return-outlives",
        }
        validate_local_contract_oracle(document)

    nested_return_call_outlives()
    expect_diagnostic(
        "task33 Call-Q ReturnSlotRefV2 must be lexical",
        "contract-projection-escapes-scope",
        unscoped_return_call_outlives,
    )

    validate_clock_oracle(load_json(directory / "clock-package-paths.json"))

    def scalar_child_owner_relation() -> None:
        document = load_json(directory / "clock-package-paths.json")
        document["package"]["owner_relation"] = 0
        validate_clock_oracle(document)

    def child_clock_owner_mismatch() -> None:
        document = load_json(directory / "clock-package-paths.json")
        document["package"]["clock_binder"]["owner"] = copy.deepcopy(
            document["package"]["storage_owner"]
        )
        validate_clock_oracle(document)

    expect_diagnostic(
        "task33 ChildOwnerWitnessV2 scalar exact object",
        "contract-component-kind-mismatch",
        scalar_child_owner_relation,
    )
    expect_diagnostic(
        "task33 PackedNext clock must use the fresh child Owner",
        "contract-component-kind-mismatch",
        child_clock_owner_mismatch,
    )
    return 18


def validate_task34_regressions() -> int:
    """Exercise task #34 finite-map, suffix, Return, and PackedNext roots."""

    directory = INTERFACES

    def captured_resume_usage(declared: str, occurrence: str) -> None:
        document = load_json(
            directory / "mixed-next-callback-function-contract.json"
        )
        handler = load_json(directory / "handler-forward-contract.json")
        resume_type = copy.deepcopy(
            handler["handler_contract"]["clause_computations"][0][
                "disposition_binder"
            ]["type"]
        )
        resume_type["value"]["usage"] = declared
        document["closure_environment"].append(
            {
                "slot": slot("ClosureCapture", 1),
                "type": resume_type,
                "provenance": copy.deepcopy(
                    resume_type["value"]["live_provenance"]
                ),
                "capture": copy.deepcopy(
                    resume_type["value"]["live_capture"]
                ),
            }
        )
        document["computation"]["continuation"]["paths"][0]["usage"].append(
            {
                "kind": "LegacyUsageExprV2",
                "value": {
                    "slot": slot("ClosureCapture", 1),
                    "kind": occurrence,
                },
            }
        )
        validate_function_contract(document)

    captured_resume_usage("Many", "Many")
    captured_resume_usage("Many", "Once")

    def forwarded_usage(mode: str) -> None:
        document = load_json(directory / "handler-forward-contract.json")
        usages = document["handler_contract"]["clause_computations"][0][
            "computation"
        ]["continuation"]["paths"][0]["usage"]
        if mode == "omitted":
            del usages[0]
        else:
            usages.insert(1, copy.deepcopy(usages[0]))
        validate_handler_oracle(document, directory)

    expect_diagnostic(
        "task34 Forwarded disposition usage is complete",
        "contract-component-kind-mismatch",
        lambda: forwarded_usage("omitted"),
    )
    expect_diagnostic(
        "task34 path usage is a unique finite map",
        "contract-component-kind-mismatch",
        lambda: forwarded_usage("duplicated"),
    )

    def replayable_documents(
        *,
        variant: str,
        mode: str,
    ) -> tuple[dict[str, Any], dict[str, Any], str]:
        handler = load_json(directory / "handler-forward-contract.json")
        source = load_json(directory / "choose-once-function-contract.json")
        source_path = source["computation"]["paths"][0]
        site = source_path["LatentSites"][0]
        obligation_cleanup = copy.deepcopy(site["suffix"]["cleanup"])
        if mode in {"mismatched-cleanup", "nonneutral-cleanup"}:
            obligation_cleanup["suspension"] = {
                "atoms": [
                    {
                        "kind": "DirectV1",
                        "grade": "MaySuspend",
                        "origin": "task34:replayable-cleanup",
                    }
                ],
                "grade": "MaySuspend",
            }
        if mode == "nonneutral-cleanup":
            site["suffix"]["cleanup"] = copy.deepcopy(obligation_cleanup)
        obligation = {
            "kind": f"ReplayableCleanup{variant}",
            "id": 0,
            "stage": "Call",
            "site_slot": 999 if mode == "missing-site" else site["site_slot"],
            "cleanup": obligation_cleanup,
            "origin": "task34:replayable-cleanup",
        }
        source_path["ParametricObligations"][0] = (
            {"kind": "LegacyObligationV2", "value": obligation}
            if variant == "V1"
            else obligation
        )

        transformer = site["suffix"]["computation"]["paths"][0]["outcome"][
            "result_transformer"
        ]["value"]
        if mode == "hidden-environment":
            source["binders"]["owner_binders"] = [
                {"slot": 0, "source": slot("Parameter", 0)},
            ]
            transformer["provenance"] = {
                "kind": "OwnerV1",
                "owner": slot("Owner", 0),
            }
            transformer["capture"] = {
                "kind": "CaptureSlotsV1",
                "slots": [slot("Owner", 0)],
            }
            handler["handler_contract"]["applications"][0]["substitution"][
                "owner_arguments"
            ] = [{"binder_slot": 0, "value": slot("Owner", 0)}]
        elif mode == "nonempty-environment":
            source["binders"]["owner_binders"] = [
                {"slot": 0, "source": slot("Parameter", 0)},
            ]
            handler["handler_contract"]["applications"][0]["substitution"][
                "owner_arguments"
            ] = [{"binder_slot": 0, "value": slot("Owner", 0)}]
            resume_type = copy.deepcopy(
                handler["handler_contract"]["clause_computations"][0][
                    "disposition_binder"
                ]["type"]
            )
            stable = {
                "kind": "LegacyProvenanceExprV2",
                "value": {"kind": "StableV1"},
            }
            empty_capture = {
                "kind": "LegacyCaptureExprV2",
                "value": {"kind": "NoCaptureV1"},
            }
            source["closure_environment"] = [
                {
                    "slot": slot("ClosureCapture", 0),
                    "type": copy.deepcopy(resume_type),
                    "provenance": copy.deepcopy(stable),
                    "capture": copy.deepcopy(empty_capture),
                },
            ]
            site["suffix"]["live_bindings"] = [
                {
                    "slot": {
                        "kind": "LegacySlotRefV2",
                        "value": slot("ClosureCapture", 0),
                    },
                    "type": copy.deepcopy(resume_type),
                    "provenance": stable,
                    "capture": empty_capture,
                    "usage": {
                        "kind": "LegacyUsageExprV2",
                        "value": {
                            "slot": slot("ClosureCapture", 0),
                            "kind": "Once",
                        },
                    },
                },
            ]
            transformer["provenance"] = {
                "kind": "ArgumentV1",
                "argument": slot("ClosureCapture", 0),
            }
            transformer["capture"] = {
                "kind": "CaptureSlotsV1",
                "slots": [slot("ClosureCapture", 0)],
            }

        old_hash = handler["imports"][0]["artifact_hash"]
        new_hash = canonical_hash(source)

        def replace_import_hash(value: Any) -> None:
            if isinstance(value, list):
                for member in value:
                    replace_import_hash(member)
            elif isinstance(value, dict):
                if value.get("artifact_hash") == old_hash:
                    value["artifact_hash"] = new_hash
                for member in value.values():
                    replace_import_hash(member)

        replace_import_hash(handler)
        return handler, source, new_hash

    def validate_replayable_source(*, variant: str, mode: str) -> None:
        _, source, _ = replayable_documents(variant=variant, mode=mode)
        validate_function_contract(source)

    def validate_replayable_handler(*, variant: str, mode: str) -> None:
        handler, source, source_hash = replayable_documents(
            variant=variant, mode=mode,
        )
        validate_function_contract(source)
        imports = ImportScope()
        imports[source_hash] = source
        import_entry = handler["imports"][0]
        imports.exports[source_hash] = (
            tuple(import_entry["module"]), import_entry["function_name"],
        )
        scope = declaration_scope_from_binders(handler["binders"])
        validate_handler_contract(
            handler["handler_contract"], imports=imports,
            nearest_outer_prompt_slot=1,
            type_parameter_kinds=scope.type_parameter_kinds,
            row_binders=scope.row_binders,
            contract_binders=scope.contract_binders,
            identity_binders=scope.identity_binders,
            handler_contract_binders=scope.handler_contract_binders,
            owner_binders=scope.owner_binders,
            clock_binders=scope.clock_binders,
            parameter_binders=scope.parameter_binders,
            closure_capture_binders=scope.closure_capture_binders,
        )

    validate_replayable_handler(variant="V1", mode="neutral")
    expect_diagnostic(
        "task34 suffix projection cannot omit live Owner provenance/capture",
        "contract-component-kind-mismatch",
        lambda: validate_replayable_source(
            variant="V1", mode="hidden-environment",
        ),
    )
    expect_diagnostic(
        "task34 Replayable cannot treat omitted live Pi/chi as empty",
        "contract-component-kind-mismatch",
        lambda: validate_replayable_handler(
            variant="V1", mode="hidden-environment",
        ),
    )

    def nested_return_call_obligation(obligation: dict[str, Any]) -> None:
        document = load_json(directory / "local-function-call.json")
        base_declaration = copy.deepcopy(document["local_declarations"][0])
        base_declaration["declaration_slot"] = 1
        base = base_declaration["contract"]
        base["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        base["computation"]["paths"][0]["outcome"]["result_transformer"][
            "value"
        ]["provenance"] = {"kind": "OwnerV1", "owner": slot("Owner", 0)}

        middle = copy.deepcopy(document["contract"])
        middle["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        application = middle["applications"][0]
        application["contract"]["declaration_slot"] = 1
        application["callee_summary"]["type"]["contract"][
            "declaration_slot"
        ] = 1
        application["substitution"]["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)},
        ]
        return_binder = concrete_return_binder(
            base, application, 10, imports=ImportScope(),
            local_functions={1: base},
        )
        template = copy.deepcopy(
            document["contract"]["computation"]["members"][0]["paths"][0]
        )
        continuation = pure_return_continuation(template, 10)
        continuation["paths"][0]["ParametricObligations"] = [obligation]
        middle["computation"] = {
            "kind": "PathBindV2",
            "prefix": {"kind": "InvokeV2", "application_slot": 0},
            "return_binder": return_binder,
            "continuation": continuation,
            "terminal_policy": "PreserveTerminalV2",
        }

        outer = copy.deepcopy(document["contract"])
        outer["binders"]["owner_binders"] = [
            {"slot": 0, "source": slot("Parameter", 0)},
        ]
        outer_application = outer["applications"][0]
        outer_application["contract"]["declaration_slot"] = 0
        outer_application["callee_summary"]["type"]["contract"][
            "declaration_slot"
        ] = 0
        outer_application["substitution"]["owner_arguments"] = [
            {"binder_slot": 0, "value": slot("Owner", 0)},
        ]
        local_functions = {0: middle, 1: base}
        validate_function_contract(base, local_functions=local_functions)
        validate_function_contract(middle, local_functions=local_functions)
        validate_function_contract(outer, local_functions=local_functions)

    return_slot = {"kind": "ReturnSlotRefV2", "return_slot": 10}
    nested_return_call_obligation(
        {
            "kind": "OutlivesV2",
            "id": 2,
            "stage": "Call",
            "shorter": copy.deepcopy(return_slot),
            "longer": copy.deepcopy(return_slot),
            "origin": "task34:return-outlives-control",
        }
    )
    nested_return_call_obligation(
        {
            "kind": "BoundarySafeV2",
            "id": 2,
            "stage": "Call",
            "slots": [copy.deepcopy(return_slot)],
            "boundary": "CallArgument",
            "origin": "task34:return-boundary-safe",
        }
    )

    def packed_next_mutation(mode: str) -> None:
        document = load_json(directory / "clock-package-paths.json")
        package = document["package"]
        if mode == "identity":
            package["clock_binder"]["clock_refinement"]["identity"] = slot(
                "Identity", 999,
            )
        elif mode == "summary-clock":
            package["summary_binder"]["kind"]["clock"] = slot("Clock", 999)
        elif mode == "body-clock":
            package["body"]["clock"] = slot("Clock", 999)
        elif mode == "scalar-summary":
            package["summary_binder"] = 0
        else:
            package["body"] = 0
        validate_clock_oracle(document)

    for mode in (
        "identity", "summary-clock", "body-clock", "scalar-summary",
        "scalar-body",
    ):
        expect_diagnostic(
            f"task34 PackedNext {mode} uses stable recursive diagnostics",
            "contract-component-kind-mismatch",
            lambda mode=mode: packed_next_mutation(mode),
        )

    validate_replayable_source(variant="V2", mode="neutral")
    validate_replayable_handler(variant="V2", mode="neutral")
    expect_diagnostic(
        "task34 direct V2 Replayable cleanup linkage",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler(
            variant="V2", mode="mismatched-cleanup",
        ),
    )
    expect_diagnostic(
        "task34 direct V2 Replayable neutral truth",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler(
            variant="V2", mode="nonneutral-cleanup",
        ),
    )
    expect_diagnostic(
        "task34 direct V2 Replayable unique local site",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler(
            variant="V2", mode="missing-site",
        ),
    )
    validate_replayable_source(variant="V2", mode="nonempty-environment")
    expect_diagnostic(
        "task34 direct V2 Replayable requires empty projected Pi/chi",
        "call-obligation-unsatisfied",
        lambda: validate_replayable_handler(
            variant="V2", mode="nonempty-environment",
        ),
    )
    return 21


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
    reject(oracle.get("schema_version") != 2, "packed-next-runtime-protocol-mismatch")
    exact_fields(oracle["initial_state"], {"kind", "leases"}, "PackedNextRuntimeStateV2")
    reject(oracle["initial_state"] != {"kind": "Open", "leases": 0}, "packed-next-runtime-protocol-mismatch")
    package_oracle = load_json(INTERFACES / "clock-package-paths.json")
    owner_scope = {binder["slot"] for binder in package_oracle["binders"]["owner_binders"]}
    validate_clock_package(package_oracle["package"], storage_owner_scope=owner_scope)
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


def validate_normative_producer_alignment() -> None:
    text = FORMALIZATION.read_text(encoding="utf-8")
    declared_u32_fields = set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*): u32\b", text))
    require(
        declared_u32_fields == WIRE_U32_FIELDS,
        "wire u32 decoder field inventory differs from the frozen schema",
    )
    start = text.index("check_try_open_packed_next(ctx, packed_expr, body):")
    end = text.index("check_dispose_packed_next(ctx, packed_expr):", start)
    try_open = text[start:end]
    require("SequenceSummaryV1" not in try_open, "algorithmic T-Try emitted raw summary sequence")
    require(try_open.count("OrderedSummaryNF") >= 3, "algorithmic T-Try omitted canonical summary normalization")


def main() -> int:
    interface_paths = sorted(INTERFACES.glob("*.json"))
    for path in interface_paths:
        validate_document(load_json(path), path.parent)
    diagnostic_count = validate_diagnostics()
    mutation_cases, mutation_operations = validate_mutations()
    runtime_count = validate_runtime()
    task28_probe_count = validate_task28_regressions()
    task29_probe_count = validate_task29_regressions()
    task30_probe_count = validate_task30_regressions()
    task31_probe_count = validate_task31_regressions()
    task33_probe_count = validate_task33_regressions()
    task34_probe_count = validate_task34_regressions()
    task35_result = subprocess.run(
        [sys.executable, str(TASK35_REGRESSIONS), str(ROOT.parent.parent)],
        check=False,
        cwd=ROOT.parent.parent,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    require(
        task35_result.returncode == 0,
        "task-35 complete-root regressions failed:\n" + task35_result.stdout,
    )
    task35_probe_count = 13
    task45_result = subprocess.run(
        [sys.executable, str(TASK45_REGRESSIONS), str(ROOT.parent.parent)],
        check=False,
        cwd=ROOT.parent.parent,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    require(
        task45_result.returncode == 0,
        "task-45 complete-root regressions failed:\n" + task45_result.stdout,
    )
    task45_probe_count = 21
    task46_result = subprocess.run(
        [sys.executable, str(TASK46_REGRESSIONS), str(ROOT.parent.parent)],
        check=False,
        cwd=ROOT.parent.parent,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    require(
        task46_result.returncode == 0,
        "task-46 complete-root regressions failed:\n" + task46_result.stdout,
    )
    task46_probe_count = 142
    validate_normative_producer_alignment()
    print(
        f"PASS: {len(interface_paths)} interface artifacts, "
        f"{mutation_cases} decoder mutation cases/{mutation_operations} RFC 6902 operations, "
        f"{runtime_count} runtime traces, {diagnostic_count} diagnostic ids, "
        f"{task28_probe_count} task-28 full-root probes, "
        f"{task29_probe_count} task-29 full-root probes, "
        f"{task30_probe_count} task-30 full-root probes, "
        f"{task31_probe_count} task-31 full-root probes, "
        f"{task33_probe_count} task-33 full-root probes, "
        f"{task34_probe_count} task-34 full-root probes, "
        f"{task35_probe_count} task-35 full-root probes, "
        f"{task45_probe_count} task-45 full-root probes, "
        f"{task46_probe_count} task-46 full-root probes"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
