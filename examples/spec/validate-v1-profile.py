#!/usr/bin/env python3
"""Finite Cire-v1.0 specification-model conformance validator.

This lane validates closed JSON models, their hash graph, mutation corpus, and
symbolic protocol traces.  It deliberately does not parse Cire source and is
not evidence for a compiler, backend, runtime implementation, or LSP.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
import sys
import unicodedata
from collections import deque
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence


PROFILE = "Cire-v1.0"
HASH_ALGORITHM = "sha256-jcs-nfc-v1"
ROOT = Path(__file__).resolve().parent
V1 = ROOT / "v1"
REPO_ROOT = ROOT.parents[1]
ZERO_HASH = "sha256:" + "0" * 64
SHA256_RE = re.compile(r"sha256:[0-9a-f]{64}\Z")

PACKAGE_DIGEST = "f2bbc193c4c2b87315b2376b171ec3b600f3fe743bd87135940ed4c0f95c31eb"
PACKAGE_ID = {"kind": "PackageInstanceIdV1", "digest": PACKAGE_DIGEST}
PACKAGE_MODULE = "pkg-" + PACKAGE_DIGEST

ARTIFACT_FILES = {
    "authority-rule-coverage.json": ("CireV1AuthorityRuleCoverageV1", 1),
    "diagnostics-v3.json": ("CireDiagnosticsV3", 3),
    "interfaces/callable-interface.json": ("CallableInterfaceV1", 1),
    "interfaces/canonicalization-cases.json": (
        "CireCanonicalizationOracleV1",
        1,
    ),
    "interfaces/callable-contract-fact.json": (
        "CallableContractFactEvidenceV1",
        1,
    ),
    "interfaces/ability-declaration.json": ("AbilityDeclarationV1", 1),
    "interfaces/call-assembly.json": ("CallAssemblyOracleV1", 1),
    "interfaces/component-interface.json": ("CireComponentInterfaceV1", 1),
    "interfaces/component-manifest.json": ("ComponentManifestV1", 1),
    "interfaces/const-values.json": ("ConstValueOracleV1", 1),
    "interfaces/const-declaration.json": ("ConstDeclarationV1", 1),
    "interfaces/control-mutation.json": ("ControlMutationOracleV1", 1),
    "interfaces/elaboration-origin-map.json": ("ElaborationOriginMapV1", 1),
    "interfaces/data-declaration.json": ("DataDeclarationV1", 1),
    "interfaces/effect-declaration.json": ("EffectDeclarationV1", 1),
    "interfaces/function-contract-v3.json": ("FunctionContractV3", 3),
    "interfaces/function-contract-v3-suite.json": (
        "CireFunctionContractV3SuiteV1",
        1,
    ),
    "interfaces/first-party-registry.json": ("FirstPartyRegistryV1", 1),
    "interfaces/intrinsic-registry.json": ("IntrinsicRegistryRootV1", 1),
    "interfaces/impl-evidence.json": ("ImplEvidenceV1", 1),
    "interfaces/language-interface.json": ("CireLanguageInterfaceV1", 1),
    "interfaces/link-abi.json": ("CireLinkAbiV1", 1),
    "interfaces/local-inference.json": ("LocalInferenceOracleV1", 1),
    "interfaces/nominal-data.json": ("NominalDataOracleV1", 1),
    "interfaces/numeric-semantics.json": ("NumericSemanticsOracleV1", 1),
    "interfaces/primitive-catalog.json": ("PrimitiveCatalogV1", 1),
    "interfaces/structural-intrinsic-registry.json": (
        "StructuralIntrinsicRegistryV1",
        1,
    ),
    "interfaces/trait-impl-extension.json": ("TraitImplExtensionOracleV1", 1),
    "interfaces/trait-declaration.json": ("TraitDeclarationV1", 1),
    "mutations/profile-mutations.json": ("CireV1MutationCorpusV1", 1),
    "runtime/protocol-models.json": ("CireRuntimeProtocolModelsV1", 1),
}

PRIMITIVES = [
    "Unit",
    "Never",
    "Bool",
    "Int8",
    "Int16",
    "Int",
    "Int64",
    "UInt8",
    "UInt16",
    "UInt",
    "UInt64",
    "Float32",
    "Float",
    "Char",
    "String",
    "Bytes",
]
LEGACY_PRIMITIVES = {"Bool", "Int", "Never", "String", "Unit"}

FIRST_PARTY_IDS = [
    "Cire-v1.0/intrinsic/" + suffix
    for suffix in [
        "async.await-receipt",
        "async.await-task",
        "resource.dispose",
        "resource.switch-latest",
        "resource.view",
        "signal.map",
        "signal.track",
        "snapshot.read-live",
        "snapshot.read-source",
        "task.cancel-outcome",
        "temporal.pack-next",
        "temporal.packed-next-dispose",
        "temporal.try-with-packed-next",
        "track.read-live",
        "track.read-source",
        "ui.builder-owner",
        "ui.candidate-action",
        "ui.coalesce-latest",
        "ui.mount-dispose",
        "ui.render",
        "ui.run-signal",
    ]
]

FIRST_PARTY_KERNELS = [
    {"kind": "OperationCallV1", "family": "AsyncV1", "operation": "await_receiptV1"},
    {"kind": "OperationCallV1", "family": "AsyncV1", "operation": "awaitV1"},
    {"kind": "ResourceDisposeV1"},
    {"kind": "ResourceSwitchLatestV1"},
    {"kind": "ResourceViewV1"},
    {"kind": "SignalMapV1"},
    {"kind": "SignalTrackV1"},
    {"kind": "SnapshotReadLiveV1"},
    {"kind": "SnapshotReadSourceV1"},
    {"kind": "TaskCancelV1"},
    {"kind": "PackedNextPackV1"},
    {"kind": "PackedNextDisposeV1"},
    {"kind": "PackedNextOpenV1"},
    {"kind": "TrackReadLiveV1"},
    {"kind": "TrackReadSourceV1"},
    {"kind": "UiBuilderOwnerV1"},
    {"kind": "UiCandidateActionV1"},
    {"kind": "UiBackpressureCoalesceLatestV1"},
    {"kind": "UiMountDisposeV1"},
    {"kind": "UiRenderV1"},
    {"kind": "UiRunSignalV1"},
]

STRUCTURAL_IDS = [
    "Cire-v1.0/structural/build-string",
    "Cire-v1.0/structural/control-finally",
]

ORIGIN_KINDS = [
    "TrailingLambdaArgumentV1",
    "InlineHandlerExpansionV1",
    "ImplicitHandlerReturnV1",
    "SourceOrderTemporaryV1",
    "CallEntryTupleV1",
    "DefaultPrologueV1",
    "ParameterTupleV1",
    "WithRightFoldV1",
    "FreshPromptV1",
    "FreshCapabilityV1",
    "HiddenTailResumeV1",
    "HiddenFinalizeV1",
    "SealedIntrinsicV1",
]

RULE_IDS = sorted([
    "FND-component-sync-v1",
    "FND-const-evaluation",
    "FND-control-structural",
    "FND-explicit-named-rows",
    "FND-local-inference-boundary",
    "FND-method-resolution",
    "FND-mutation-place-replay",
    "FND-nominal-data",
    "FND-numeric-semantics",
    "FND-package-instance-identity",
    "FND-pattern-matrix",
    "FND-postfix-derive",
    "FND-primitive-wire-forms",
    "FND-semantic-string-const-bytes",
    "FND-trait-coherence",
    "FND-maytrap-defect-transition",
    "R06-associated-ability-profile-boundary",
    "R06-call-assembly",
    "R06-callable-hash-dag",
    "R06-capability-identity",
    "R06-cleanup-receipt-report",
    "R06-diagnostic-origin-stability",
    "R06-first-party-registry",
    "R06-inline-handler",
    "R06-no-generic-event-on",
    "R06-origin-arena",
    "R06-packed-next",
    "R06-public-plan-commit-excluded",
    "R06-resource-latest-retained",
    "R06-runtime-symbolic-replay",
    "R06-sealed-checkpoint",
    "R06-signal-tracking",
    "R06-task-multiwaiter-shareable",
    "R06-ui-action-flow",
    "R06-ui-exact-occurrence",
    "R06-ui-generation-cleanup",
])

RUNTIME_TRACE_IDS = [
    "checkpoint-commit-close",
    "checkpoint-stale-retained",
    "component-resource-borrow-close",
    "packed-building-parent-close",
    "packed-multi-lease-close",
    "receipt-multiwaiter-late",
    "resource-last-good-on-failure",
    "resource-latest-retained",
    "sealed-finally-terminal-preserved",
    "signal-dependency-rerun",
    "task-central-cancel",
    "task-independent-cancel",
    "ui-close-running-queued",
    "ui-fifo-exact-payload",
    "ui-heterogeneous-exact-payload",
]

RUNTIME_INVARIANTS = sorted([
    "checkpoint-claim-lease-exactly-once",
    "checkpoint-fixed-epoch-prepare-before-commit",
    "checkpoint-retained-latest-coalescing",
    "checkpoint-runtime-nat-nonnegative",
    "checkpoint-single-publish-claim",
    "checkpoint-stale-settlement-released",
    "close-receipt-multiwaiter-late-registration",
    "component-resource-borrow-nonescape",
    "component-resource-child-owner-fresh",
    "component-resource-destroy-report-exactly-once",
    "component-resource-owner-derived-from-parent",
    "packed-next-builder-exactly-once",
    "packed-next-child-owner-fresh",
    "packed-next-close-after-all-leases",
    "packed-next-parent-close-terminal-report",
    "resource-latest-retained-revision",
    "resource-stale-settlement-ignored",
    "resource-no-live-dispose",
    "resource-runtime-nat-generation",
    "resource-closed-view",
    "resource-view-retains-last-good-value",
    "sealed-finally-finalizer-exactly-once",
    "sealed-finally-preserve-terminal-tag",
    "signal-complete-dependency-trace",
    "signal-dispose-cleanup-exactly-once",
    "signal-owner-storage",
    "signal-invalidation-token-gating",
    "task-central-cancel-authority",
    "task-generation-and-result-type",
    "task-independent-waiter-cancellation",
    "task-multiwaiter-late-registration",
    "ui-cleanup-after-generation-count-zero",
    "ui-exact-typed-payload-per-occurrence",
    "ui-fifo-occurrence-order",
    "ui-one-linear-lease-queued-to-running",
    "ui-release-exactly-once",
    "ui-generation-gate-terminal",
])


class ValidationFailure(Exception):
    """A stable diagnostic emitted by a closed model decoder."""

    def __init__(self, diagnostic: str, detail: str) -> None:
        super().__init__(detail)
        self.diagnostic = diagnostic
        self.detail = detail


def fail(diagnostic: str, detail: str) -> None:
    raise ValidationFailure(diagnostic, detail)


def duplicate_safe_object(pairs: Sequence[tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise ValueError("non-finite JSON number: " + value)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(
            handle,
            object_pairs_hook=duplicate_safe_object,
            parse_constant=reject_constant,
        )


def exact_keys(
    value: Any, fields: Iterable[str], diagnostic: str, context: str
) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        fail(diagnostic, context + " must be an object")
    expected = set(fields)
    observed = set(value)
    if observed != expected:
        fail(
            diagnostic,
            context
            + " fields differ; missing="
            + repr(sorted(expected - observed))
            + " extra="
            + repr(sorted(observed - expected)),
        )
    return value


def require_list(value: Any, diagnostic: str, context: str) -> List[Any]:
    if not isinstance(value, list):
        fail(diagnostic, context + " must be an array")
    return value


def require_int(value: Any, diagnostic: str, context: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        fail(diagnostic, context + " must be an integer")
    return value


def walk_json(value: Any, context: str = "$") -> None:
    if isinstance(value, str):
        if unicodedata.normalize("NFC", value) != value:
            fail("manifest-noncanonical", context + " is not NFC")
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            fail("Decode/unicode-scalar-mismatch", context + " contains a lone surrogate")
        return
    if value is None or isinstance(value, bool) or isinstance(value, int):
        return
    if isinstance(value, float):
        fail("manifest-noncanonical", context + " contains a float")
    if isinstance(value, list):
        for index, item in enumerate(value):
            walk_json(item, context + "/" + str(index))
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                fail("manifest-noncanonical", context + " has a non-string key")
            walk_json(key, context + "/<key>")
            walk_json(item, context + "/" + key)
        return
    fail("manifest-noncanonical", context + " has an unsupported JSON value")


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
        fail("manifest-noncanonical", "JCS domain forbids floating-point JSON numbers")
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(jcs(member) for member in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=utf16_key)
        return "{" + ",".join(jcs(key) + ":" + jcs(value[key]) for key in keys) + "}"
    fail("manifest-noncanonical", "unsupported JCS value " + type(value).__name__)
    raise AssertionError("unreachable")


def canonical_bytes(value: Any) -> bytes:
    walk_json(value)
    return jcs(value).encode("utf-8")


def object_hash(value: Any) -> str:
    return "sha256:" + hashlib.sha256(canonical_bytes(value)).hexdigest()


def validate_profile_header(
    value: Mapping[str, Any], artifact: str, schema: int, diagnostic: str
) -> None:
    if value.get("artifact") != artifact:
        fail(diagnostic, "expected artifact " + artifact)
    if value.get("profile") != PROFILE:
        fail(diagnostic, artifact + " has the wrong profile")
    if value.get("schema_version") != schema:
        fail(diagnostic, artifact + " has the wrong schema version")


def package_identity_input() -> Dict[str, Any]:
    return {
        "kind": "PackageIdentityInputV1",
        "dependencies": [],
        "exact_version": "1.0.0",
        "features": ["component-sync-v1", "sealed-checkpoint-v1"],
        "profile": PROFILE,
        "source_checksum": (
            "sha256:6fbe07bca576af65d7bcbbe9894a0784"
            "9d3fdbd85c8c7477c94040d29cf96cf1"
        ),
        "source_identity": "cire:core",
    }


def validate_package_id() -> None:
    observed = hashlib.sha256(canonical_bytes(package_identity_input())).hexdigest()
    if observed != PACKAGE_DIGEST:
        fail("package-instance-hash-mismatch", "validator package digest drift")


def validate_function_contract(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "root_declaration_slot",
            "declaration_kind",
            "binders",
            "callable_dependencies",
            "local_declarations",
            "default_prologues",
            "applications",
            "computation",
            "closure_environment",
        ],
        "callable-interface-contract-mismatch",
        "FunctionContractV3",
    )
    validate_profile_header(root, "FunctionContractV3", 3, "callable-interface-contract-mismatch")
    if root["root_declaration_slot"] != 0:
        fail("callable-interface-contract-mismatch", "root slot must be zero")
    kind = exact_keys(
        root["declaration_kind"],
        ["kind", "parameter_type", "result_type", "visible_row"],
        "callable-interface-contract-mismatch",
        "declaration kind",
    )
    if kind["kind"] != "FunctionContractKindV2":
        fail("callable-interface-contract-mismatch", "wrong function kind")
    if kind["visible_row"] != {"kind": "EmptyV1"}:
        fail("named-function-effect-row-required", "identity must expose ! {}")
    binders = exact_keys(
        root["binders"],
        [
            "type_binders",
            "row_binders",
            "contract_binders",
            "identity_binders",
            "owner_binders",
            "clock_binders",
            "prompt_binders",
            "parameter_binders",
        ],
        "callable-interface-contract-mismatch",
        "binders",
    )
    if binders["type_binders"] != [{"kind": "Type", "slot": 0}]:
        fail("callable-interface-contract-mismatch", "type binder drift")
    if len(binders["parameter_binders"]) != 1:
        fail("callable-interface-contract-mismatch", "parameter binder drift")
    for field in (
        "callable_dependencies",
        "local_declarations",
        "default_prologues",
        "applications",
        "closure_environment",
    ):
        require_list(root[field], "callable-interface-contract-mismatch", field)


def validate_hash_ref(value: Any, artifact: str, diagnostic: str) -> None:
    ref = exact_keys(
        value,
        ["artifact", "artifact_hash", "hash_algorithm"],
        diagnostic,
        artifact + " hash reference",
    )
    if ref["artifact"] != artifact or ref["hash_algorithm"] != HASH_ALGORITHM:
        fail(diagnostic, artifact + " hash reference metadata differs")
    if not isinstance(ref["artifact_hash"], str) or not SHA256_RE.fullmatch(
        ref["artifact_hash"]
    ):
        fail(diagnostic, artifact + " hash is malformed")
    if ref["artifact_hash"] == ZERO_HASH:
        fail(diagnostic, artifact + " hash is the zero placeholder")


def validate_callable(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "module",
            "export_path",
            "core_contract",
            "surface_signature",
        ],
        "callable-interface-contract-mismatch",
        "CallableInterfaceV1",
    )
    validate_profile_header(root, "CallableInterfaceV1", 1, "callable-interface-contract-mismatch")
    validate_hash_ref(
        root["core_contract"], "FunctionContractV3", "callable-interface-contract-mismatch"
    )
    if root["module"] != [PACKAGE_MODULE, "foundation"]:
        fail("package-instance-hash-mismatch", "callable module is not package-qualified")
    if root["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", "export path drift")
    signature = exact_keys(
        root["surface_signature"],
        ["kind", "effect_row", "slots"],
        "callable-interface-contract-mismatch",
        "surface signature",
    )
    if signature["kind"] != "CallableSurfaceSignatureV1":
        fail("callable-interface-contract-mismatch", "wrong surface signature kind")
    if signature["effect_row"] != "! {}":
        fail("named-function-effect-row-required", "callable row must be explicit")
    slots = require_list(
        signature["slots"], "callable-interface-contract-mismatch", "surface slots"
    )
    if len(slots) != 1:
        fail("callable-interface-contract-mismatch", "identity needs one slot")
    exact_keys(
        slots[0],
        ["slot", "passing", "public_label", "defaultable"],
        "callable-interface-contract-mismatch",
        "surface slot",
    )


def validate_language(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "package_identity",
            "package_instance_id",
            "imports",
            "declarations",
            "evidence",
            "callables",
            "components",
            "primitive_catalog",
            "intrinsic_registry",
        ],
        "callable-interface-contract-mismatch",
        "CireLanguageInterfaceV1",
    )
    validate_profile_header(root, "CireLanguageInterfaceV1", 1, "callable-interface-contract-mismatch")
    identity = exact_keys(
        root["package_identity"],
        [
            "dependencies",
            "features",
            "instance",
            "kind",
            "profile",
            "source_checksum",
            "source_identity",
            "version",
        ],
        "package-instance-hash-mismatch",
        "package identity",
    )
    if identity["kind"] != "PackageIdentityV1":
        fail("package-instance-hash-mismatch", "wrong package identity kind")
    expected_input = package_identity_input()
    observed_input = {key: identity[key] for key in expected_input}
    if observed_input != expected_input:
        fail("package-instance-hash-mismatch", "package identity input differs")
    if identity["instance"] != PACKAGE_ID or root["package_instance_id"] != PACKAGE_ID:
        fail("package-instance-hash-mismatch", "package instance differs")
    if root["imports"] != []:
        fail("package-import-not-locked", "foundation fixture has unexpected imports")
    declarations = require_list(
        root["declarations"], "callable-interface-contract-mismatch", "declarations"
    )
    expected_declarations = [
        "ConstValueOracleV1",
        "NominalDataOracleV1",
        "TraitImplExtensionOracleV1",
    ]
    if [item.get("artifact") for item in declarations] != expected_declarations:
        fail("callable-interface-contract-mismatch", "declaration edge order differs")
    for item, artifact in zip(declarations, expected_declarations):
        validate_hash_ref(item, artifact, "callable-interface-contract-mismatch")
    evidence = require_list(
        root["evidence"], "callable-interface-contract-mismatch", "evidence"
    )
    if len(evidence) != 1:
        fail("callable-interface-contract-mismatch", "expected one evidence root")
    validate_hash_ref(
        evidence[0], "ElaborationOriginMapV1", "callable-interface-contract-mismatch"
    )
    callables = require_list(
        root["callables"], "callable-interface-contract-mismatch", "callables"
    )
    if len(callables) != 1:
        fail("callable-interface-contract-mismatch", "expected one callable")
    callable_edge = exact_keys(
        callables[0],
        ["callable_interface", "export_path", "module"],
        "callable-interface-contract-mismatch",
        "callable edge",
    )
    if callable_edge["module"] != [PACKAGE_MODULE, "foundation"]:
        fail("package-instance-hash-mismatch", "root callable module differs")
    if callable_edge["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", "root export path differs")
    validate_hash_ref(
        callable_edge["callable_interface"],
        "CallableInterfaceV1",
        "callable-interface-contract-mismatch",
    )
    components = require_list(
        root["components"], "callable-interface-contract-mismatch", "components"
    )
    if len(components) != 1:
        fail("callable-interface-contract-mismatch", "expected one component edge")
    component_edge = exact_keys(
        components[0],
        ["component_interface", "manifest_selection"],
        "callable-interface-contract-mismatch",
        "component edge",
    )
    if component_edge["manifest_selection"] != "component-sync-v1":
        fail("component-native-async-not-in-v1", "wrong component selection")
    validate_hash_ref(
        component_edge["component_interface"],
        "CireComponentInterfaceV1",
        "callable-interface-contract-mismatch",
    )
    validate_hash_ref(
        root["primitive_catalog"], "PrimitiveCatalogV1", "callable-interface-contract-mismatch"
    )
    validate_hash_ref(
        root["intrinsic_registry"],
        "IntrinsicRegistryRootV1",
        "callable-interface-contract-mismatch",
    )


def validate_primitive_catalog(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "wasm_target",
            "legacy_wire_names",
            "builtins",
            "numeric_policy",
            "text_policy",
        ],
        "package-instance-hash-mismatch",
        "PrimitiveCatalogV1",
    )
    validate_profile_header(root, "PrimitiveCatalogV1", 1, "package-instance-hash-mismatch")
    if root["legacy_wire_names"] != sorted(LEGACY_PRIMITIVES):
        fail("package-instance-hash-mismatch", "legacy primitive vector differs")
    builtins = require_list(root["builtins"], "package-instance-hash-mismatch", "builtins")
    if [item.get("name") for item in builtins] != PRIMITIVES:
        fail("package-instance-hash-mismatch", "primitive universe/order differs")
    numeric = root["numeric_policy"]
    if numeric.get("may_trap_representation") != "OrdinaryFactV1+DefectTransitionV1":
        fail("maytrap-not-an-effect", "MayTrap must not enter an effect row")
    for item in builtins:
        exact_keys(
            item,
            [
                "name",
                "category",
                "bits",
                "wasm_carrier",
                "literal_suffixes",
                "default_literal_kind",
                "wire_form",
            ],
            "package-instance-hash-mismatch",
            "primitive " + str(item.get("name")),
        )
        wire = item["wire_form"]
        name = item["name"]
        if name in LEGACY_PRIMITIVES:
            if wire != {"kind": "BuiltinTypeV1", "name": name}:
                fail("package-instance-hash-mismatch", "legacy wire form differs")
        else:
            exact_keys(
                wire,
                ["kind", "module", "name"],
                "package-instance-hash-mismatch",
                "sealed primitive wire",
            )
            if wire["kind"] != "SealedPrimitiveNominalV1":
                fail("package-instance-hash-mismatch", "wrong sealed primitive kind")
            if wire["module"] != [PACKAGE_MODULE, "core", "primitive"]:
                fail("package-instance-hash-mismatch", "sealed module is not locked")
            if wire["name"] != name:
                fail("package-instance-hash-mismatch", "sealed primitive name differs")
    wasm = root["wasm_target"]
    if wasm.get("version") != "3.0" or wasm.get("memory") != "memory32":
        fail("component-public-type-not-safe", "Wasm target drift")


def validate_nominal_data(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "package_instance_id",
            "declarations",
            "construction_cases",
            "pattern_cases",
            "layout_cases",
        ],
        "record-construction-missing-field",
        "NominalDataOracleV1",
    )
    validate_profile_header(root, "NominalDataOracleV1", 1, "record-construction-missing-field")
    if root["package_instance_id"] != PACKAGE_ID:
        fail("package-instance-hash-mismatch", "nominal data package differs")
    declarations = require_list(
        root["declarations"], "record-construction-missing-field", "declarations"
    )
    if [item.get("identity") for item in declarations] != [
        "Meters",
        "Point",
        "Secret",
        "Status",
        "UserId",
    ]:
        fail("record-construction-missing-field", "nominal declaration order differs")
    for item in declarations:
        if item.get("derives"):
            spelling = item.get("source_spelling")
            if not isinstance(spelling, str) or "} derive(" not in spelling:
                fail("postfix-derive-required", "derive must be postfix")


def validate_trait_impl_extension(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "traits",
            "impls",
            "extensions",
            "resolution_cases",
            "coherence_cases",
        ],
        "trait-impl-overlap",
        "TraitImplExtensionOracleV1",
    )
    validate_profile_header(root, "TraitImplExtensionOracleV1", 1, "trait-impl-overlap")
    traits = require_list(root["traits"], "trait-impl-overlap", "traits")
    if [item.get("identity") for item in traits] != [
        "DisplayName",
        "IntoIterator",
        "Iterator",
    ]:
        fail("trait-impl-overlap", "trait order differs")
    for trait in traits:
        for method in require_list(trait.get("methods"), "trait-impl-overlap", "methods"):
            if method.get("effect_row") != "! {}":
                fail("named-function-effect-row-required", "trait method row missing")
    heads = []
    for impl in require_list(root["impls"], "trait-impl-overlap", "impls"):
        head = (impl.get("trait"), impl.get("target"))
        if head in heads:
            fail("trait-impl-overlap", "duplicate unifiable impl head")
        heads.append(head)
        for method in require_list(impl.get("methods"), "trait-impl-overlap", "impl methods"):
            if method.get("effect_row") != "! {}":
                fail("named-function-effect-row-required", "impl method row missing")
    for extension in require_list(
        root["extensions"], "extension-resolution-ambiguous", "extensions"
    ):
        if extension.get("effect_row") != "! {}":
            fail("named-function-effect-row-required", "extension row missing")
        activation = extension.get("activation")
        if not isinstance(activation, str) or not activation.startswith("use @"):
            fail("extension-resolution-ambiguous", "extension activation differs")


def validate_const_values(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "definitions",
            "evaluation_cases",
            "initialization_policy",
        ],
        "const-operation-not-safe",
        "ConstValueOracleV1",
    )
    validate_profile_header(root, "ConstValueOracleV1", 1, "const-operation-not-safe")
    definitions = require_list(root["definitions"], "const-operation-not-safe", "definitions")
    if [item.get("name") for item in definitions] != [
        "decomposed",
        "greeting",
        "magic",
        "packet",
    ]:
        fail("const-operation-not-safe", "const definition order differs")
    for item in definitions:
        if item.get("effect_row") != "! {}":
            fail("named-function-effect-row-required", "const definition row missing")
        payload = item.get("value")
        if not isinstance(payload, dict):
            fail("const-operation-not-safe", "const payload must be an object")
        if payload.get("kind") == "StringConstV1":
            octets = require_list(
                payload.get("utf8_bytes"),
                "semantic-string-payload-mismatch",
                "String UTF-8 bytes",
            )
            scalars = require_list(
                payload.get("unicode_scalars"),
                "semantic-string-payload-mismatch",
                "String scalars",
            )
            if any(require_int(x, "semantic-string-payload-mismatch", "byte") not in range(256) for x in octets):
                fail("semantic-string-payload-mismatch", "String byte out of range")
            try:
                text = bytes(octets).decode("utf-8")
            except (UnicodeDecodeError, ValueError):
                fail("semantic-string-payload-mismatch", "String bytes are not UTF-8")
            if [ord(char) for char in text] != scalars:
                fail("semantic-string-payload-mismatch", "String byte/scalar views differ")
        if payload.get("kind") == "BytesConstV1":
            octets = require_list(payload.get("bytes"), "byte-literal-out-of-range", "Bytes")
            for octet in octets:
                if require_int(octet, "byte-literal-out-of-range", "byte") not in range(256):
                    fail("byte-literal-out-of-range", "Bytes element out of range")


def contains_forbidden_component_type(value: Any) -> bool:
    if isinstance(value, str):
        return value in {"ActionPlan", "Plan", "UiCommit", "ViewPlan"}
    if isinstance(value, list):
        return any(contains_forbidden_component_type(item) for item in value)
    if isinstance(value, dict):
        return any(contains_forbidden_component_type(item) for item in value.values())
    return False


def validate_component(value: Any) -> None:
    root = exact_keys(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "package_instance_id",
            "manifest_selection",
            "exports",
            "imports",
            "resources",
            "component_safe_types",
            "forbidden_direct_types",
            "borrow_policy",
            "trap_policy",
        ],
        "component-public-type-not-safe",
        "CireComponentInterfaceV1",
    )
    validate_profile_header(root, "CireComponentInterfaceV1", 1, "component-public-type-not-safe")
    if root["package_instance_id"] != PACKAGE_ID:
        fail("package-instance-hash-mismatch", "component package differs")
    manifest = exact_keys(
        root["manifest_selection"],
        ["surface", "string_encoding", "memory", "native_async"],
        "component-native-async-not-in-v1",
        "component manifest selection",
    )
    if manifest["surface"] != "component-sync-v1" or manifest["native_async"] is not False:
        fail("component-native-async-not-in-v1", "component must be sync-first")
    if manifest["string_encoding"] != "utf8" or manifest["memory"] != "memory32":
        fail("component-public-type-not-safe", "component ABI selection differs")
    exports = require_list(root["exports"], "component-public-type-not-safe", "exports")
    for export in exports:
        if export.get("effect_row") != "! {}":
            fail("named-function-effect-row-required", "component export row missing")
        if contains_forbidden_component_type(
            {"parameters": export.get("parameters"), "result": export.get("result")}
        ):
            fail("component-public-type-not-safe", "public Plan/Commit form exposed")
    if sorted(root["component_safe_types"]) != root["component_safe_types"]:
        fail("component-public-type-not-safe", "component-safe types are not ordered")
    if sorted(root["forbidden_direct_types"]) != root["forbidden_direct_types"]:
        fail("component-public-type-not-safe", "forbidden types are not ordered")


def validate_registry(value: Any) -> None:
    root = exact_keys(
        value,
        ["artifact", "profile", "schema_version", "first_party", "structural"],
        "intrinsic-registry-root-mismatch",
        "IntrinsicRegistryRootV1",
    )
    validate_profile_header(root, "IntrinsicRegistryRootV1", 1, "intrinsic-registry-root-mismatch")
    first = exact_keys(
        root["first_party"],
        ["artifact", "bindings", "profile", "schema_version"],
        "intrinsic-registry-root-mismatch",
        "FirstPartyRegistryV1",
    )
    structural = exact_keys(
        root["structural"],
        ["artifact", "bindings", "profile", "schema_version"],
        "intrinsic-registry-root-mismatch",
        "StructuralIntrinsicRegistryV1",
    )
    if first["artifact"] != "FirstPartyRegistryV1" or first["profile"] != PROFILE:
        fail("intrinsic-registry-root-mismatch", "first-party registry metadata differs")
    if structural["artifact"] != "StructuralIntrinsicRegistryV1" or structural["profile"] != PROFILE:
        fail("intrinsic-registry-root-mismatch", "structural registry metadata differs")
    structural_bindings = require_list(
        structural["bindings"], "intrinsic-registry-root-mismatch", "structural bindings"
    )
    if len(structural_bindings) != 2:
        fail("intrinsic-registry-root-mismatch", "structural registry must contain two bindings")
    if [item.get("id") for item in structural_bindings] != STRUCTURAL_IDS:
        fail("intrinsic-registry-root-mismatch", "structural binding order differs")
    for binding in structural_bindings:
        exact_keys(
            binding,
            ["id", "kernel", "row", "source", "visibility"],
            "intrinsic-registry-root-mismatch",
            "structural binding",
        )
        if binding["visibility"] != "CompilerOwned":
            fail("intrinsic-registry-root-mismatch", "structural intrinsic became public")
        validate_row(binding["row"], "intrinsic-registry-root-mismatch", "structural row")
    bindings = require_list(first["bindings"], "intrinsic-registry-root-mismatch", "bindings")
    ids = [item.get("id") if isinstance(item, dict) else None for item in bindings]
    if ids != FIRST_PARTY_IDS:
        fail("first-party-registry-noncanonical-order", "first-party id vector differs")
    callback_count = 0
    for binding in bindings:
        binding_id = binding["id"]
        exact_keys(
            binding,
            [
                "callbacks",
                "direct",
                "evidence",
                "fresh",
                "id",
                "kind",
                "kernel",
                "slots",
                "source",
                "types",
            ],
            "first-party-registry-contract-nonunique",
            "first-party binding " + binding_id,
        )
        if binding["kind"] != "FirstPartyBindingV1":
            fail("first-party-registry-contract-nonunique", "wrong binding kind")
        if binding.get("kernel") != {"kind": FIRST_PARTY_KERNELS[binding_id]}:
            fail("first-party-registry-contract-nonunique", "kernel mapping differs")
        source = exact_keys(
            binding["source"],
            ["kind", "spelling"],
            "first-party-registry-contract-nonunique",
            "source",
        )
        if source["kind"] != "CanonicalSourceV1":
            fail("first-party-registry-contract-nonunique", "wrong source kind")
        if source["spelling"] in {"Event.on", "Event.on_async", "on", "on_async"}:
            fail("first-party-static-scope-escape", "generic Event registration is excluded")
        slots = require_list(
            binding["slots"], "first-party-registry-contract-nonunique", "slots"
        )
        if [item.get("slot") for item in slots] != list(range(len(slots))):
            fail("first-party-registry-contract-nonunique", "slot namespace is not contiguous")
        for slot in slots:
            exact_keys(
                slot,
                ["defaultable", "passing", "public_label", "slot", "type"],
                "first-party-registry-contract-nonunique",
                "slot",
            )
            if slot["defaultable"] is not False:
                fail("first-party-registry-contract-nonunique", "first-party slot defaulted")
        direct = exact_keys(
            binding["direct"],
            ["flow", "kind", "phase", "row", "suspension", "temporal", "world"],
            "first-party-registry-contract-nonunique",
            "direct contract",
        )
        if direct["kind"] != "FirstPartyContractTemplateV1":
            fail("first-party-registry-contract-nonunique", "wrong direct contract kind")
        validate_row(direct["row"], "first-party-registry-contract-nonunique", "direct row")
        callbacks = require_list(
            binding["callbacks"], "first-party-callback-scheme-mismatch", "callbacks"
        )
        callback_count += len(callbacks)
        callback_slots = []
        for callback in callbacks:
            exact_keys(
                callback,
                ["acquisition", "contract", "name", "parameter_slot", "type"],
                "first-party-callback-scheme-mismatch",
                "callback",
            )
            callback_slot = require_int(
                callback["parameter_slot"],
                "first-party-callback-scheme-mismatch",
                "callback parameter slot",
            )
            if callback_slot not in range(len(slots)) or callback_slot in callback_slots:
                fail("first-party-callback-scheme-mismatch", "callback slot linkage differs")
            callback_slots.append(callback_slot)
            contract = exact_keys(
                callback["contract"],
                ["flow", "phase", "row", "suspension", "temporal", "world"],
                "first-party-callback-scheme-mismatch",
                "callback contract",
            )
            validate_row(
                contract["row"], "first-party-callback-scheme-mismatch", "callback row"
            )
        evidence = require_list(
            binding["evidence"], "first-party-registry-contract-nonunique", "evidence"
        )
        if binding_id == "async.await-task" and "ShareableV1(R)" not in evidence:
            fail("first-party-registry-contract-nonunique", "Task result is not Shareable")
        if binding_id == "ui.candidate-action":
            required = {"ShareableV1(E)", "EventOccurrenceStorageV1(E)"}
            if not required.issubset(set(evidence)):
                fail(
                    "first-party-action-occurrence-contract-mismatch",
                    "UI occurrence storage/shareability evidence is incomplete",
                )
    if callback_count != 8:
        fail("first-party-callback-scheme-mismatch", "expected exactly eight callback schemes")


def validate_row(value: Any, diagnostic: str, context: str) -> None:
    row = exact_keys(value, ["entries", "tail"], diagnostic, context)
    require_list(row["entries"], diagnostic, context + " entries")
    if row["tail"] is not None:
        fail(diagnostic, context + " must be an explicit closed row")


def validate_origin_map(value: Any) -> None:
    root = exact_keys(
        value,
        ["artifact", "profile", "schema_version", "nodes", "sites"],
        "origin-map-noncanonical",
        "ElaborationOriginMapV1",
    )
    validate_profile_header(root, "ElaborationOriginMapV1", 1, "origin-map-noncanonical")
    nodes = require_list(root["nodes"], "origin-map-noncanonical", "origin nodes")
    sites = require_list(root["sites"], "origin-map-noncanonical", "origin sites")
    if len(nodes) != 14 or len(sites) != 13:
        fail("origin-map-noncanonical", "origin arena cardinality differs")
    direct = exact_keys(
        nodes[0],
        [
            "node_kind",
            "file_id",
            "subject",
            "source_digest",
            "utf8_range",
            "utf16_range",
        ],
        "origin-map-noncanonical",
        "Direct origin",
    )
    if direct["node_kind"] != "DirectV1":
        fail("origin-map-noncanonical", "origin zero must be DirectV1")
    if direct["source_digest"] != (
        "sha256:9f3e3ed1c6b6cc45c25337bccd22b7cb7931d724c0d6d46d92325fc5452ec578"
    ):
        fail("origin-map-noncanonical", "source digest differs")
    if direct["utf8_range"] != {"start": 0, "end": 31}:
        fail("origin-map-noncanonical", "UTF-8 range differs")
    if direct["utf16_range"] != {"start": 0, "end": 31}:
        fail("origin-map-noncanonical", "UTF-16 range differs")
    if [item.get("derivation_kind") for item in nodes[1:]] != ORIGIN_KINDS:
        fail("origin-map-noncanonical", "derived-kind vector differs")
    for index, node in enumerate(nodes[1:], 1):
        exact_keys(
            node,
            ["node_kind", "derivation_kind", "anchor", "parents", "ordinal"],
            "origin-map-noncanonical",
            "Derived origin",
        )
        if node["node_kind"] != "DerivedV1" or node["anchor"] != 0:
            fail("origin-map-noncanonical", "derived anchor differs")
        if node["ordinal"] != 0:
            fail("origin-map-noncanonical", "group ordinal differs")
        if node["parents"] != [{"role": "PrincipalV1", "target": 0}]:
            fail("origin-map-noncanonical", "derived parent vector differs")
        if index <= node["anchor"]:
            fail("origin-map-noncanonical", "derived node allocation is cyclic")
    origin_ids = []
    for index, site in enumerate(sites):
        exact_keys(
            site,
            ["site_id", "origin_id"],
            "origin-map-noncanonical",
            "origin site",
        )
        site_id = exact_keys(
            site["site_id"],
            ["root_binding_slot", "kernel_node_preorder", "role", "field_path"],
            "origin-map-noncanonical",
            "site id",
        )
        if site_id != {
            "root_binding_slot": 0,
            "kernel_node_preorder": index,
            "role": "PrincipalV1",
            "field_path": [],
        }:
            fail("origin-map-noncanonical", "site order/id differs")
        origin_ids.append(v1_u32(site["origin_id"], "site origin id"))
    if origin_ids != list(range(1, 14)):
        fail("origin-map-noncanonical", "site-to-origin mapping is not one-to-one")


def validate_diagnostics(value: Any) -> None:
    root = exact_keys(
        value,
        ["artifact", "diagnostics", "profile", "schema_version"],
        "manifest-noncanonical",
        "CireDiagnosticsV3",
    )
    validate_profile_header(root, "CireDiagnosticsV3", 3, "manifest-noncanonical")
    diagnostics = require_list(root["diagnostics"], "manifest-noncanonical", "diagnostics")
    ids = []
    allowed_stages = {
        "Coherence",
        "Component",
        "Const",
        "ContractWF",
        "Effect",
        "Elaboration",
        "Interface",
        "Kind",
        "Runtime",
        "Syntax",
        "Type",
    }
    for item in diagnostics:
        exact_keys(
            item,
            [
                "causal_cluster",
                "fix_safety",
                "id",
                "primary_origin_role",
                "required_notes",
                "stage",
            ],
            "manifest-noncanonical",
            "diagnostic",
        )
        ids.append(item["id"])
        if item["stage"] not in allowed_stages:
            fail("manifest-noncanonical", "unknown diagnostic stage")
        if item["primary_origin_role"] not in {"Direct", "Principal"}:
            fail("manifest-noncanonical", "unknown primary origin role")
        if item["fix_safety"] not in {
            "MachineApplicable",
            "MaybeIncorrect",
            "Manual",
            "None",
        }:
            fail("manifest-noncanonical", "unknown fix safety")
        require_list(item["required_notes"], "manifest-noncanonical", "required notes")
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        fail("manifest-noncanonical", "diagnostic ids are not unique and sorted")
    required_stages = {
        "surface-tilde-label-removed": "Syntax",
        "surface-cap-marker-removed": "Syntax",
        "named-function-effect-row-required": "Syntax",
        "named-call-requires-static-signature": "Kind",
        "trailing-lambda-target-not-callable": "Kind",
        "capability-binder-default-not-in-v1": "Kind",
        "capability-identity-required": "Kind",
        "defer-not-in-cire-v1": "Syntax",
        "handler-clause-mode-required": "Syntax",
        "open-visibility-not-applicable": "Kind",
        "non-exhaustive-match": "Type",
        "unreachable-pattern": "Type",
        "float-pattern-not-in-cire-v1": "Syntax",
        "row-predicate-not-in-profile": "Kind",
        "independent-ability-impl-not-in-profile": "Kind",
        "callable-interface-contract-mismatch": "Interface",
        "recursive-public-callable-scc-not-in-v1": "Interface",
        "callable-source-import-collision": "Interface",
    }
    stage_by_id = {item["id"]: item["stage"] for item in diagnostics}
    for diagnostic, stage in required_stages.items():
        if stage_by_id.get(diagnostic) != stage:
            fail("manifest-noncanonical", diagnostic + " has the wrong stage")


RUNTIME_MODEL_ORDER = [
    "CheckpointRunnerV1",
    "CloseReceiptV1",
    "ComponentResourceV1",
    "PackedNextV1",
    "ResourceV1",
    "SealedFinallyV1",
    "SignalV1",
    "TaskV1",
    "UiDispatcherV1",
]

RUNTIME_TRACE_MODELS = {
    "checkpoint-commit-close": "CheckpointRunnerV1",
    "checkpoint-stale-retained": "CheckpointRunnerV1",
    "component-resource-borrow-close": "ComponentResourceV1",
    "packed-building-parent-close": "PackedNextV1",
    "packed-multi-lease-close": "PackedNextV1",
    "receipt-multiwaiter-late": "CloseReceiptV1",
    "resource-last-good-on-failure": "ResourceV1",
    "resource-latest-retained": "ResourceV1",
    "sealed-finally-terminal-preserved": "SealedFinallyV1",
    "signal-dependency-rerun": "SignalV1",
    "task-central-cancel": "TaskV1",
    "task-independent-cancel": "TaskV1",
    "ui-close-running-queued": "UiDispatcherV1",
    "ui-fifo-exact-payload": "UiDispatcherV1",
    "ui-heterogeneous-exact-payload": "UiDispatcherV1",
}

CLEANUP_ROLES = {
    "PackedRunnerV1",
    "ResourceCandidateV1",
    "ResourceCommittedV1",
    "ResourceInputV1",
    "ResourceRetiredV1",
    "SignalTailV1",
    "UiCandidateV1",
    "UiCommittedPlanV1",
    "UiListenerV1",
}


def runtime_nat(value: Any, context: str) -> int:
    if not isinstance(value, str) or re.fullmatch(r"0|[1-9][0-9]*", value) is None:
        fail("runtime-protocol-trace-mismatch", context + " is not CanonicalNatV1")
    return int(value)


def runtime_child_owner(parent: str, family: str, ordinal: str) -> str:
    return parent + "/" + family + "/" + ordinal


def runtime_initial_state(model: str) -> Dict[str, Any]:
    if model == "CloseReceiptV1":
        return {
            "phase": "PendingV1",
            "next_registration": 0,
            "value": None,
            "waiters": {},
            "deliveries": [],
            "closed_waiters": [],
        }
    if model == "TaskV1":
        return {
            "phase": "UncreatedV1",
            "generation": None,
            "result_type": None,
            "cancel_authority": None,
            "next_registration": 0,
            "value": None,
            "waiters": {},
            "deliveries": [],
            "cancelled_waiters": [],
        }
    if model == "PackedNextV1":
        return {
            "phase": "InitialV1",
            "parent_owner": None,
            "child_owner": None,
            "receipt": None,
            "builder_calls": 0,
            "builder_terminal": None,
            "next_lease": 0,
            "leases": {},
            "close_reason": None,
            "report_count": 0,
        }
    if model == "ResourceV1":
        return {
            "phase": "InitialV1",
            "generation_cursor": 0,
            "input_cursor": None,
            "latest": None,
            "busy": None,
            "retained": None,
            "committed": None,
            "view": {"kind": "PendingV1"},
            "admitted": [],
            "admitted_epochs": [],
            "ignored": [],
            "report_count": 0,
        }
    if model == "SignalV1":
        return {
            "phase": "InitialV1",
            "parent_owner": None,
            "child_owner": None,
            "generation": 0,
            "active_token": None,
            "current_dependencies": [],
            "dependency_sets": [],
            "completed_generations": [],
            "invalidations": [],
            "cleanup_count": 0,
        }
    if model == "SealedFinallyV1":
        return {
            "phase": "InitialV1",
            "reserved": [],
            "retired": [],
            "terminal": None,
            "finalizer_count": 0,
            "report_count": 0,
        }
    if model == "ComponentResourceV1":
        return {
            "phase": "InitialV1",
            "parent_owner": None,
            "child_owner": None,
            "handle": None,
            "borrow": None,
            "destroy_count": 0,
            "report_count": 0,
        }
    if model == "UiDispatcherV1":
        return {
            "phase": "InitialV1",
            "generation": None,
            "gate": None,
            "next_event": 0,
            "queue": [],
            "running": None,
            "lease_states": {},
            "callbacks": [],
            "released": [],
            "cleanup_count": 0,
        }
    if model == "CheckpointRunnerV1":
        return {
            "phase": "OpenV1",
            "latest_epoch": None,
            "latest_value": None,
            "active": None,
            "retained": None,
            "committed": [],
            "aborted": [],
            "stale": [],
            "released": [],
            "settled_claims": [],
        }
    fail("runtime-protocol-trace-mismatch", "unknown runtime model")
    raise AssertionError("unreachable")


def runtime_step_receipt(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "register":
        exact_keys(event, ["observer_generation", "op", "waiter"], "runtime-protocol-trace-mismatch", "receipt register")
        waiter = event["waiter"]
        observer_generation = runtime_nat(event["observer_generation"], "receipt observer generation")
        if not isinstance(waiter, str) or not waiter or waiter in result["waiters"]:
            fail("runtime-protocol-trace-mismatch", "invalid receipt waiter")
        result["waiters"][waiter] = {
            "ordinal": result["next_registration"],
            "observer_generation": observer_generation,
            "status": "ArmedV1",
        }
        result["next_registration"] += 1
    elif op == "resolve":
        exact_keys(event, ["op", "value"], "runtime-protocol-trace-mismatch", "receipt resolve")
        if result["phase"] != "PendingV1":
            fail("runtime-protocol-trace-mismatch", "receipt resolved more than once")
        result["phase"] = "ResolvedV1"
        result["value"] = copy.deepcopy(event["value"])
    elif op in {"deliver", "close_waiter"}:
        exact_keys(event, ["op", "waiter"], "runtime-protocol-trace-mismatch", "receipt waiter terminal")
        waiter = result["waiters"].get(event["waiter"])
        if waiter is None or waiter["status"] != "ArmedV1":
            fail("runtime-protocol-trace-mismatch", "receipt waiter claim is not armed")
        if op == "deliver":
            if result["phase"] != "ResolvedV1":
                fail("runtime-protocol-trace-mismatch", "receipt delivered before resolution")
            waiter["status"] = "DeliveredV1"
            result["deliveries"].append(
                {"waiter": event["waiter"], "value": copy.deepcopy(result["value"])}
            )
        else:
            waiter["status"] = "FinalizedV1"
            result["closed_waiters"].append(event["waiter"])
    else:
        fail("runtime-protocol-trace-mismatch", "unknown CloseReceipt transition")
    return result


def runtime_step_task(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "create":
        exact_keys(event, ["cancel_authority", "generation", "op", "result_type"], "runtime-protocol-trace-mismatch", "task create")
        if result["phase"] != "UncreatedV1" or event["cancel_authority"] != "TaskProducerOwnerV1":
            fail("runtime-protocol-trace-mismatch", "task creation/cancel authority differs")
        result["phase"] = "PendingV1"
        result["generation"] = runtime_nat(event["generation"], "task generation")
        if event["result_type"] != "IntV1":
            fail("runtime-protocol-trace-mismatch", "task result type differs")
        result["result_type"] = event["result_type"]
        result["cancel_authority"] = event["cancel_authority"]
    elif op == "register":
        exact_keys(event, ["generation", "observer_generation", "op", "waiter"], "runtime-protocol-trace-mismatch", "task register")
        generation = runtime_nat(event["generation"], "task waiter generation")
        observer_generation = runtime_nat(event["observer_generation"], "task observer generation")
        waiter = event["waiter"]
        if result["phase"] not in {"PendingV1", "ResolvedV1"} or generation != result["generation"]:
            fail("runtime-protocol-trace-mismatch", "task waiter generation differs")
        if not isinstance(waiter, str) or not waiter or waiter in result["waiters"]:
            fail("runtime-protocol-trace-mismatch", "invalid task waiter")
        result["waiters"][waiter] = {
            "ordinal": result["next_registration"],
            "observer_generation": observer_generation,
            "status": "ArmedV1",
        }
        result["next_registration"] += 1
    elif op == "resolve":
        exact_keys(event, ["generation", "op", "value"], "runtime-protocol-trace-mismatch", "task resolve")
        if result["phase"] != "PendingV1" or runtime_nat(event["generation"], "task result generation") != result["generation"]:
            fail("runtime-protocol-trace-mismatch", "task result generation differs")
        value = exact_keys(event["value"], ["kind", "value"], "runtime-protocol-trace-mismatch", "typed task result")
        if value["kind"] != result["result_type"] or isinstance(value["value"], bool) or not isinstance(value["value"], int):
            fail("runtime-protocol-trace-mismatch", "task result is not exact typed payload")
        result["phase"] = "ResolvedV1"
        result["value"] = copy.deepcopy(value)
    elif op == "central_cancel":
        exact_keys(event, ["authority", "generation", "op"], "runtime-protocol-trace-mismatch", "task central cancel")
        if (
            result["phase"] != "PendingV1"
            or event["authority"] != result["cancel_authority"]
            or runtime_nat(event["generation"], "task cancel generation") != result["generation"]
        ):
            fail("runtime-protocol-trace-mismatch", "task central cancel is unauthorized")
        result["phase"] = "OwnerClosedV1"
        for waiter in result["waiters"].values():
            if waiter["status"] == "ArmedV1":
                waiter["status"] = "FinalizedV1"
    elif op in {"deliver", "cancel_waiter"}:
        exact_keys(event, ["op", "waiter"], "runtime-protocol-trace-mismatch", "task waiter terminal")
        waiter = result["waiters"].get(event["waiter"])
        if waiter is None or waiter["status"] != "ArmedV1":
            fail("runtime-protocol-trace-mismatch", "task waiter claim is not armed")
        if op == "deliver":
            if result["phase"] != "ResolvedV1":
                fail("runtime-protocol-trace-mismatch", "task delivered before resolution")
            waiter["status"] = "DeliveredV1"
            result["deliveries"].append(
                {"waiter": event["waiter"], "value": copy.deepcopy(result["value"])}
            )
        else:
            waiter["status"] = "FinalizedV1"
            result["cancelled_waiters"].append(event["waiter"])
    else:
        fail("runtime-protocol-trace-mismatch", "unknown Task transition")
    return result


def runtime_step_packed(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "admit_builder":
        exact_keys(event, ["child_owner", "op", "parent_owner", "receipt"], "runtime-protocol-trace-mismatch", "PackedNext admission")
        if result["phase"] != "InitialV1" or not isinstance(event["parent_owner"], str):
            fail("runtime-protocol-trace-mismatch", "PackedNext builder admitted twice")
        if event["child_owner"] != runtime_child_owner(event["parent_owner"], "packed", "0"):
            fail("runtime-protocol-trace-mismatch", "PackedNext child Owner is not exact fresh derivation")
        if event["receipt"] != event["child_owner"] + "/receipt":
            fail("runtime-protocol-trace-mismatch", "PackedNext receipt identity differs")
        result.update(
            phase="BuildingV1",
            parent_owner=event["parent_owner"],
            child_owner=event["child_owner"],
            receipt=event["receipt"],
            builder_calls=1,
            next_lease=1,
        )
        result["leases"] = {"0": "ConstructionV1"}
    elif op in {"parent_close", "dispose"}:
        exact_keys(event, ["op", "reason", "receipt"], "runtime-protocol-trace-mismatch", "PackedNext close")
        if result["phase"] not in {"BuildingV1", "OpenV1", "ClosingV1"} or event["receipt"] != result["receipt"]:
            fail("runtime-protocol-trace-mismatch", "PackedNext close receipt differs")
        expected_reason = "ParentOwnerCloseV1" if op == "parent_close" else "ExplicitDisposeV1"
        if event["reason"] != expected_reason:
            fail("runtime-protocol-trace-mismatch", "PackedNext close reason differs")
        if result["close_reason"] is None:
            result["close_reason"] = event["reason"]
        if result["phase"] == "OpenV1":
            result["phase"] = "ClosingV1"
    elif op == "builder_terminal":
        exact_keys(event, ["op", "tag"], "runtime-protocol-trace-mismatch", "PackedNext builder terminal")
        if result["phase"] != "BuildingV1" or result["builder_terminal"] is not None:
            fail("runtime-protocol-trace-mismatch", "PackedNext builder terminal duplicated")
        if event["tag"] not in {"ReturnsV2", "AbortsV2", "TransfersV2"}:
            fail("runtime-protocol-trace-mismatch", "PackedNext builder terminal tag differs")
        result["builder_terminal"] = event["tag"]
        result["leases"]["0"] = "ReleasedV1"
        if event["tag"] == "ReturnsV2" and result["close_reason"] is None:
            result["phase"] = "OpenV1"
        else:
            result["phase"] = "ClosingV1"
            if result["close_reason"] is None:
                result["close_reason"] = "StorageOwnerCloseV1"
    elif op == "acquire":
        exact_keys(event, ["lease", "op"], "runtime-protocol-trace-mismatch", "PackedNext acquire")
        ordinal = runtime_nat(event["lease"], "PackedNext lease")
        if result["phase"] != "OpenV1" or ordinal != result["next_lease"]:
            fail("runtime-protocol-trace-mismatch", "PackedNext lease ordinal differs")
        result["leases"][event["lease"]] = "ArmedV1"
        result["next_lease"] += 1
    elif op == "release":
        exact_keys(event, ["lease", "op"], "runtime-protocol-trace-mismatch", "PackedNext release")
        if result["leases"].get(event["lease"]) != "ArmedV1":
            fail("runtime-protocol-trace-mismatch", "PackedNext lease was not armed")
        result["leases"][event["lease"]] = "ReleasedV1"
    elif op == "finalize":
        exact_keys(event, ["op", "receipt"], "runtime-protocol-trace-mismatch", "PackedNext finalize")
        if (
            result["phase"] != "ClosingV1"
            or event["receipt"] != result["receipt"]
            or any(status in {"ArmedV1", "ConstructionV1"} for status in result["leases"].values())
            or result["builder_terminal"] is None
            or result["report_count"] != 0
        ):
            fail("runtime-protocol-trace-mismatch", "PackedNext finalized before terminal/lease drain")
        result["phase"] = "ClosedV1"
        result["report_count"] = 1
    else:
        fail("runtime-protocol-trace-mismatch", "unknown PackedNext transition")
    return result


def runtime_step_resource(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "open":
        exact_keys(event, ["generation", "op"], "runtime-protocol-trace-mismatch", "Resource open")
        if result["phase"] != "InitialV1" or runtime_nat(event["generation"], "Resource initial generation") != 0:
            fail("runtime-protocol-trace-mismatch", "Resource initial generation differs")
        result["phase"] = "OpenV1"
    elif op == "publish":
        exact_keys(event, ["epoch", "key", "op"], "runtime-protocol-trace-mismatch", "Resource publish")
        if result["phase"] != "OpenV1" or not isinstance(event["key"], str):
            fail("runtime-protocol-trace-mismatch", "Resource publication outside Open")
        epoch = runtime_nat(event["epoch"], "Resource revision epoch")
        if result["input_cursor"] is not None and epoch <= result["input_cursor"]:
            fail("runtime-protocol-trace-mismatch", "Resource revision did not increase")
        if result["input_cursor"] is None and epoch != 0:
            fail("runtime-protocol-trace-mismatch", "Resource first epoch is not zero")
        result["input_cursor"] = epoch
        result["latest"] = {"epoch": epoch, "key": event["key"]}
        if result["busy"] is not None:
            result["retained"] = copy.deepcopy(result["latest"])
    elif op == "start":
        exact_keys(event, ["generation", "key", "op"], "runtime-protocol-trace-mismatch", "Resource start")
        generation = runtime_nat(event["generation"], "Resource candidate generation")
        if (
            result["phase"] != "OpenV1"
            or result["busy"] is not None
            or result["latest"] is None
            or event["key"] != result["latest"]["key"]
            or generation != result["generation_cursor"] + 1
        ):
            fail("runtime-protocol-trace-mismatch", "Resource candidate admission differs")
        result["generation_cursor"] = generation
        result["busy"] = {
            "generation": generation,
            "epoch": result["latest"]["epoch"],
            "key": event["key"],
        }
        result["admitted"].append(event["key"])
        result["admitted_epochs"].append(result["latest"]["epoch"])
    elif op in {"succeed", "fail"}:
        fields = ["generation", "op", "value"] if op == "succeed" else ["error", "generation", "op"]
        exact_keys(event, fields, "runtime-protocol-trace-mismatch", "Resource settlement")
        generation = runtime_nat(event["generation"], "Resource settlement generation")
        busy = result["busy"]
        if result["phase"] != "OpenV1" or busy is None or generation != busy["generation"]:
            fail("runtime-protocol-trace-mismatch", "Resource settlement identity differs")
        if result["latest"] is None:
            fail("runtime-protocol-trace-mismatch", "Resource lost latest revision")
        if busy["epoch"] != result["latest"]["epoch"]:
            result["ignored"].append(generation)
        elif op == "succeed":
            result["committed"] = {
                "generation": generation,
                "key": busy["key"],
                "value": copy.deepcopy(event["value"]),
            }
            result["view"] = {"kind": "ReadyV1", "value": copy.deepcopy(event["value"])}
        elif result["committed"] is None:
            result["view"] = {"error": event["error"], "kind": "FailedV1"}
        else:
            result["view"] = {
                "error": event["error"],
                "kind": "DegradedV1",
                "value": copy.deepcopy(result["committed"]["value"]),
            }
        result["busy"] = None
    elif op == "admit_retained":
        exact_keys(event, ["generation", "op"], "runtime-protocol-trace-mismatch", "Resource retained admission")
        generation = runtime_nat(event["generation"], "Resource retained generation")
        if (
            result["phase"] != "OpenV1"
            or result["busy"] is not None
            or result["retained"] is None
            or generation != result["generation_cursor"] + 1
        ):
            fail("runtime-protocol-trace-mismatch", "Resource retained admission differs")
        result["generation_cursor"] = generation
        result["busy"] = {
            "generation": generation,
            "epoch": result["retained"]["epoch"],
            "key": result["retained"]["key"],
        }
        result["admitted"].append(result["retained"]["key"])
        result["admitted_epochs"].append(result["retained"]["epoch"])
        result["retained"] = None
    elif op == "dispose":
        exact_keys(event, ["op", "reason"], "runtime-protocol-trace-mismatch", "Resource dispose")
        if result["phase"] != "OpenV1" or result["busy"] is not None or result["retained"] is not None:
            fail("runtime-protocol-trace-mismatch", "Resource disposed with live candidate")
        if event["reason"] not in {"ExplicitDisposeV1", "ParentOwnerCloseV1", "StorageOwnerCloseV1"}:
            fail("runtime-protocol-trace-mismatch", "Resource close reason differs")
        result["phase"] = "ClosedV1"
        result["view"] = {
            "kind": "ClosedV1",
            "last_good": None
            if result["committed"] is None
            else copy.deepcopy(result["committed"]["value"]),
        }
        result["report_count"] = 1
    else:
        fail("runtime-protocol-trace-mismatch", "unknown Resource transition")
    return result


def runtime_step_signal(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "install":
        exact_keys(event, ["child_owner", "op", "parent_owner"], "runtime-protocol-trace-mismatch", "Signal install")
        if result["phase"] != "InitialV1" or not isinstance(event["parent_owner"], str):
            fail("runtime-protocol-trace-mismatch", "Signal installed twice")
        if event["child_owner"] != runtime_child_owner(event["parent_owner"], "signal", "0"):
            fail("runtime-protocol-trace-mismatch", "Signal child Owner is not exact fresh derivation")
        result["phase"] = "OpenV1"
        result["parent_owner"] = event["parent_owner"]
        result["child_owner"] = event["child_owner"]
    elif op == "begin_run":
        exact_keys(event, ["generation", "op", "token"], "runtime-protocol-trace-mismatch", "Signal begin run")
        generation = runtime_nat(event["generation"], "Signal generation")
        expected_token = result["child_owner"] + "/generation/" + event["generation"]
        if result["phase"] != "OpenV1" or generation != result["generation"] or event["token"] != expected_token:
            fail("runtime-protocol-trace-mismatch", "Signal generation token differs")
        result["phase"] = "RunningV1"
        result["active_token"] = event["token"]
        result["current_dependencies"] = []
    elif op == "track_read":
        exact_keys(event, ["dependency", "op", "token"], "runtime-protocol-trace-mismatch", "Signal track read")
        dependency = event["dependency"]
        if (
            result["phase"] != "RunningV1"
            or event["token"] != result["active_token"]
            or not isinstance(dependency, str)
            or dependency in result["current_dependencies"]
        ):
            fail("runtime-protocol-trace-mismatch", "Signal dependency trace differs")
        result["current_dependencies"].append(dependency)
    elif op == "finish_run":
        exact_keys(event, ["op", "token"], "runtime-protocol-trace-mismatch", "Signal finish run")
        if (
            result["phase"] != "RunningV1"
            or event["token"] != result["active_token"]
            or not result["current_dependencies"]
            or result["current_dependencies"] != sorted(result["current_dependencies"])
        ):
            fail("runtime-protocol-trace-mismatch", "Signal incomplete/noncanonical dependency trace")
        result["dependency_sets"].append(copy.deepcopy(result["current_dependencies"]))
        result["completed_generations"].append(result["generation"])
        result["phase"] = "OpenV1"
        result["active_token"] = None
    elif op == "invalidate":
        exact_keys(event, ["dependency", "op", "token"], "runtime-protocol-trace-mismatch", "Signal invalidate")
        expected_token = result["child_owner"] + "/generation/" + str(result["generation"])
        if (
            result["phase"] != "OpenV1"
            or event["token"] != expected_token
            or not result["dependency_sets"]
            or event["dependency"] not in result["dependency_sets"][-1]
        ):
            fail("runtime-protocol-trace-mismatch", "Signal invalidation token/dependency differs")
        result["invalidations"].append(event["dependency"])
        result["generation"] += 1
    elif op == "dispose":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "Signal dispose")
        if result["phase"] != "OpenV1" or result["cleanup_count"] != 0:
            fail("runtime-protocol-trace-mismatch", "Signal disposed while a run is live")
        result["phase"] = "ClosedV1"
        result["cleanup_count"] = 1
    else:
        fail("runtime-protocol-trace-mismatch", "unknown Signal transition")
    return result


def runtime_step_finally(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "open":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "finally open")
        if result["phase"] != "InitialV1":
            fail("runtime-protocol-trace-mismatch", "finally opened twice")
        result["phase"] = "BodyV1"
    elif op == "reserve":
        exact_keys(event, ["op", "ordinal", "role"], "runtime-protocol-trace-mismatch", "finally reserve")
        ordinal = runtime_nat(event["ordinal"], "cleanup ordinal")
        if (
            result["phase"] != "BodyV1"
            or ordinal != len(result["reserved"])
            or event["role"] not in CLEANUP_ROLES
        ):
            fail("runtime-protocol-trace-mismatch", "cleanup reservation differs")
        result["reserved"].append(event["role"])
    elif op == "body_terminal":
        exact_keys(event, ["op", "tag"], "runtime-protocol-trace-mismatch", "finally terminal")
        if result["phase"] != "BodyV1" or event["tag"] not in {"ReturnsV2", "AbortsV2", "TransfersV2"}:
            fail("runtime-protocol-trace-mismatch", "finally terminal differs")
        result["phase"] = "RetiringV1"
        result["terminal"] = event["tag"]
    elif op == "retire":
        exact_keys(event, ["op", "role"], "runtime-protocol-trace-mismatch", "finally retire")
        index = len(result["reserved"]) - len(result["retired"]) - 1
        if result["phase"] != "RetiringV1" or index < 0 or event["role"] != result["reserved"][index]:
            fail("runtime-protocol-trace-mismatch", "cleanup retirement is not reverse exact")
        result["retired"].append(event["role"])
    elif op == "run_finalizer":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "finally finalizer")
        if result["phase"] != "RetiringV1" or len(result["retired"]) != len(result["reserved"]) or result["finalizer_count"]:
            fail("runtime-protocol-trace-mismatch", "finally finalizer eligibility differs")
        result["finalizer_count"] = 1
    elif op == "emit_report":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "finally report")
        if result["phase"] != "RetiringV1" or result["finalizer_count"] != 1 or result["report_count"]:
            fail("runtime-protocol-trace-mismatch", "finally report eligibility differs")
        result["report_count"] = 1
    elif op == "close":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "finally close")
        if result["phase"] != "RetiringV1" or result["report_count"] != 1:
            fail("runtime-protocol-trace-mismatch", "finally closed before cleanup")
        result["phase"] = "ClosedV1"
    else:
        fail("runtime-protocol-trace-mismatch", "unknown sealed-finally transition")
    return result


def runtime_step_component(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "export_handle":
        exact_keys(event, ["child_owner", "handle", "op", "parent_owner"], "runtime-protocol-trace-mismatch", "component handle export")
        if result["phase"] != "InitialV1" or not isinstance(event["parent_owner"], str):
            fail("runtime-protocol-trace-mismatch", "component handle exported twice")
        expected_owner = runtime_child_owner(event["parent_owner"], "component", "0")
        if event["child_owner"] != expected_owner or event["handle"] != expected_owner + "/handle/0":
            fail("runtime-protocol-trace-mismatch", "component child Owner/handle derivation differs")
        result.update(
            phase="OpenV1",
            parent_owner=event["parent_owner"],
            child_owner=event["child_owner"],
            handle=event["handle"],
        )
    elif op == "borrow_enter":
        exact_keys(event, ["borrow", "handle", "op"], "runtime-protocol-trace-mismatch", "component borrow enter")
        if result["phase"] != "OpenV1" or result["borrow"] is not None or event["handle"] != result["handle"]:
            fail("runtime-protocol-trace-mismatch", "component borrow admission differs")
        if not isinstance(event["borrow"], str) or not event["borrow"]:
            fail("runtime-protocol-trace-mismatch", "component borrow identity differs")
        result["borrow"] = event["borrow"]
    elif op == "borrow_return":
        exact_keys(event, ["borrow", "op"], "runtime-protocol-trace-mismatch", "component borrow return")
        if result["phase"] != "OpenV1" or event["borrow"] != result["borrow"]:
            fail("runtime-protocol-trace-mismatch", "component borrow escaped/mismatched")
        result["borrow"] = None
    elif op == "destroy":
        exact_keys(event, ["handle", "op"], "runtime-protocol-trace-mismatch", "component destroy")
        if result["phase"] != "OpenV1" or result["borrow"] is not None or event["handle"] != result["handle"] or result["destroy_count"]:
            fail("runtime-protocol-trace-mismatch", "component destroy eligibility differs")
        result["phase"] = "ClosingV1"
        result["destroy_count"] = 1
    elif op == "emit_report":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "component report")
        if result["phase"] != "ClosingV1" or result["report_count"]:
            fail("runtime-protocol-trace-mismatch", "component report emitted out of order")
        result["phase"] = "ClosedV1"
        result["report_count"] = 1
    else:
        fail("runtime-protocol-trace-mismatch", "unknown Component-resource transition")
    return result


def runtime_ui_payload(event_tag: Any, payload: Any) -> Dict[str, Any]:
    if event_tag == "SaveEventV1":
        value = exact_keys(payload, ["draft"], "runtime-protocol-trace-mismatch", "SaveEventV1 payload")
        if not isinstance(value["draft"], str):
            fail("runtime-protocol-trace-mismatch", "SaveEventV1 draft is not String")
        return copy.deepcopy(dict(value))
    if event_tag == "ToggleEventV1":
        value = exact_keys(payload, ["checked", "key"], "runtime-protocol-trace-mismatch", "ToggleEventV1 payload")
        if not isinstance(value["checked"], bool) or isinstance(value["key"], bool) or not isinstance(value["key"], int):
            fail("runtime-protocol-trace-mismatch", "ToggleEventV1 payload types differ")
        return copy.deepcopy(dict(value))
    fail("runtime-protocol-trace-mismatch", "unknown UI event type witness")
    raise AssertionError("unreachable")


def runtime_step_ui(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "open_generation":
        exact_keys(event, ["gate", "generation", "op"], "runtime-protocol-trace-mismatch", "UI generation open")
        if result["phase"] != "InitialV1" or runtime_nat(event["generation"], "UI generation") != 0:
            fail("runtime-protocol-trace-mismatch", "UI generation opening differs")
        if event["gate"] != "ui-generation/0":
            fail("runtime-protocol-trace-mismatch", "UI generation gate identity differs")
        result.update(phase="OpenV1", generation=0, gate=event["gate"])
    elif op == "enqueue":
        exact_keys(event, ["event_ordinal", "event_type", "gate", "generation", "lease", "op", "payload"], "runtime-protocol-trace-mismatch", "UI enqueue")
        generation = runtime_nat(event["generation"], "UI occurrence generation")
        ordinal = runtime_nat(event["event_ordinal"], "UI event ordinal")
        expected_lease = result["gate"] + "/event/" + event["event_ordinal"]
        if (
            result["phase"] != "OpenV1"
            or generation != result["generation"]
            or event["gate"] != result["gate"]
            or ordinal != result["next_event"]
            or event["lease"] != expected_lease
            or event["lease"] in result["lease_states"]
        ):
            fail("runtime-protocol-trace-mismatch", "UI occurrence identity/gate differs")
        occurrence = {
            "event_ordinal": ordinal,
            "event_type": event["event_type"],
            "generation": generation,
            "gate": event["gate"],
            "lease": event["lease"],
            "payload": runtime_ui_payload(event["event_type"], event["payload"]),
        }
        result["queue"].append(occurrence)
        result["lease_states"][event["lease"]] = "QueuedV1"
        result["next_event"] += 1
    elif op == "dequeue":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "UI dequeue")
        if result["phase"] not in {"OpenV1", "ClosingV1"} or result["running"] is not None or not result["queue"]:
            fail("runtime-protocol-trace-mismatch", "UI dequeue eligibility differs")
        occurrence = result["queue"].pop(0)
        if result["lease_states"].get(occurrence["lease"]) != "QueuedV1":
            fail("runtime-protocol-trace-mismatch", "UI queued lease was reacquired/lost")
        result["lease_states"][occurrence["lease"]] = "RunningV1"
        result["running"] = occurrence
    elif op == "return_running":
        exact_keys(event, ["event_type", "gate", "generation", "op", "returns"], "runtime-protocol-trace-mismatch", "UI action return")
        running = result["running"]
        if running is None:
            fail("runtime-protocol-trace-mismatch", "UI action returned without running occurrence")
        if (
            event["event_type"] != running["event_type"]
            or runtime_nat(event["generation"], "UI action generation") != running["generation"]
            or event["gate"] != running["gate"]
            or event["returns"] != "UnitV1"
            or result["lease_states"].get(running["lease"]) != "RunningV1"
        ):
            fail("runtime-protocol-trace-mismatch", "UI action/generation/gate terminal differs")
        result["callbacks"].append(
            {
                "event_ordinal": running["event_ordinal"],
                "event_type": running["event_type"],
                "payload": copy.deepcopy(running["payload"]),
            }
        )
        result["lease_states"][running["lease"]] = "ReleasedV1"
        result["released"].append(running["lease"])
        result["running"] = None
    elif op == "close_gate":
        exact_keys(event, ["gate", "generation", "op"], "runtime-protocol-trace-mismatch", "UI close gate")
        if (
            result["phase"] != "OpenV1"
            or runtime_nat(event["generation"], "UI closed generation") != result["generation"]
            or event["gate"] != result["gate"]
        ):
            fail("runtime-protocol-trace-mismatch", "UI closed foreign generation gate")
        result["phase"] = "ClosingV1"
    elif op == "finalize_queued":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "UI finalize queued")
        if result["phase"] != "ClosingV1":
            fail("runtime-protocol-trace-mismatch", "UI finalized queued while gate open")
        for occurrence in result["queue"]:
            if result["lease_states"].get(occurrence["lease"]) != "QueuedV1":
                fail("runtime-protocol-trace-mismatch", "UI queued lease finalized twice")
            result["lease_states"][occurrence["lease"]] = "FinalizedV1"
            result["released"].append(occurrence["lease"])
        result["queue"] = []
    elif op == "cleanup_generation":
        exact_keys(event, ["gate", "generation", "op"], "runtime-protocol-trace-mismatch", "UI cleanup generation")
        live = sum(status in {"QueuedV1", "RunningV1"} for status in result["lease_states"].values())
        if (
            result["phase"] != "ClosingV1"
            or result["running"] is not None
            or result["queue"]
            or live != 0
            or result["cleanup_count"]
            or runtime_nat(event["generation"], "UI cleanup generation") != result["generation"]
            or event["gate"] != result["gate"]
        ):
            fail("runtime-protocol-trace-mismatch", "UI cleanup before generation drain")
        result["phase"] = "ClosedV1"
        result["cleanup_count"] = 1
    else:
        fail("runtime-protocol-trace-mismatch", "unknown UI transition")
    return result


def runtime_step_checkpoint(state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(dict(state))
    op = event.get("op")
    if op == "publish":
        exact_keys(event, ["epoch", "op", "value"], "runtime-protocol-trace-mismatch", "checkpoint publish")
        epoch = runtime_nat(event["epoch"], "checkpoint epoch")
        if result["phase"] == "ClosedV1" or (result["latest_epoch"] is None and epoch != 0) or (
            result["latest_epoch"] is not None and epoch <= result["latest_epoch"]
        ):
            fail("runtime-protocol-trace-mismatch", "checkpoint epoch is not canonical successor")
        result["latest_epoch"] = epoch
        result["latest_value"] = copy.deepcopy(event["value"])
        if result["active"] is not None:
            result["retained"] = {"epoch": epoch, "value": copy.deepcopy(event["value"])}
    elif op == "compute":
        exact_keys(event, ["claim", "epoch", "lease", "op"], "runtime-protocol-trace-mismatch", "checkpoint compute")
        epoch = runtime_nat(event["epoch"], "checkpoint compute epoch")
        expected_claim = "checkpoint/" + event["epoch"] + "/claim"
        expected_lease = "checkpoint/" + event["epoch"] + "/lease"
        if (
            result["phase"] != "OpenV1"
            or result["latest_epoch"] is None
            or result["active"] is not None
            or epoch != result["latest_epoch"]
            or event["claim"] != expected_claim
            or event["lease"] != expected_lease
            or event["claim"] in result["settled_claims"]
            or event["lease"] in result["released"]
        ):
            fail("runtime-protocol-trace-mismatch", "checkpoint claim/lease/fixed epoch differs")
        result["phase"] = "ComputeV1"
        result["active"] = {
            "claim": event["claim"],
            "epoch": epoch,
            "lease": event["lease"],
            "value": copy.deepcopy(result["latest_value"]),
            "dependencies": [],
        }
    elif op == "track_read":
        exact_keys(event, ["claim", "dependency", "op"], "runtime-protocol-trace-mismatch", "checkpoint dependency")
        active = result["active"]
        if result["phase"] != "ComputeV1" or active is None or event["claim"] != active["claim"]:
            fail("runtime-protocol-trace-mismatch", "checkpoint dependency has foreign claim")
        dependency = event["dependency"]
        if not isinstance(dependency, str) or dependency in active["dependencies"]:
            fail("runtime-protocol-trace-mismatch", "checkpoint dependency is duplicate/invalid")
        active["dependencies"].append(dependency)
    elif op == "prepare":
        exact_keys(event, ["claim", "epoch", "op"], "runtime-protocol-trace-mismatch", "checkpoint prepare")
        active = result["active"]
        if (
            result["phase"] != "ComputeV1"
            or active is None
            or event["claim"] != active["claim"]
            or runtime_nat(event["epoch"], "checkpoint prepared epoch") != active["epoch"]
            or not active["dependencies"]
            or active["dependencies"] != sorted(active["dependencies"])
        ):
            fail("runtime-protocol-trace-mismatch", "checkpoint prepared before complete dependency trace")
        result["phase"] = "PreparedV1"
    elif op in {"commit", "abort", "stale"}:
        exact_keys(event, ["claim", "epoch", "lease", "op"], "runtime-protocol-trace-mismatch", "checkpoint settlement")
        active = result["active"]
        if (
            result["phase"] != "PreparedV1"
            or active is None
            or event["claim"] != active["claim"]
            or event["lease"] != active["lease"]
            or runtime_nat(event["epoch"], "checkpoint settled epoch") != active["epoch"]
            or active["claim"] in result["settled_claims"]
        ):
            fail("runtime-protocol-trace-mismatch", "checkpoint settlement identity differs")
        is_current = active["epoch"] == result["latest_epoch"]
        if op == "commit":
            if not is_current:
                fail("runtime-protocol-trace-mismatch", "stale checkpoint committed")
            result["committed"].append({"epoch": active["epoch"], "value": copy.deepcopy(active["value"])})
        elif op == "stale":
            if is_current:
                fail("runtime-protocol-trace-mismatch", "current checkpoint marked stale")
            result["stale"].append(active["epoch"])
        else:
            result["aborted"].append(active["epoch"])
        result["settled_claims"].append(active["claim"])
        result["released"].append(active["lease"])
        result["active"] = None
        result["phase"] = "OpenV1"
        if result["retained"] is not None:
            result["latest_epoch"] = result["retained"]["epoch"]
            result["latest_value"] = copy.deepcopy(result["retained"]["value"])
            result["retained"] = None
    elif op == "close":
        exact_keys(event, ["op"], "runtime-protocol-trace-mismatch", "checkpoint close")
        if result["phase"] != "OpenV1" or result["active"] is not None or result["retained"] is not None:
            fail("runtime-protocol-trace-mismatch", "checkpoint closed with live work")
        result["phase"] = "ClosedV1"
    else:
        fail("runtime-protocol-trace-mismatch", "unknown checkpoint transition")
    return result


def runtime_step(model: str, state: Mapping[str, Any], event: Mapping[str, Any]) -> Dict[str, Any]:
    if not isinstance(event, dict):
        fail("runtime-protocol-trace-mismatch", "runtime event must be an object")
    dispatch = {
        "CheckpointRunnerV1": runtime_step_checkpoint,
        "CloseReceiptV1": runtime_step_receipt,
        "ComponentResourceV1": runtime_step_component,
        "PackedNextV1": runtime_step_packed,
        "ResourceV1": runtime_step_resource,
        "SealedFinallyV1": runtime_step_finally,
        "SignalV1": runtime_step_signal,
        "TaskV1": runtime_step_task,
        "UiDispatcherV1": runtime_step_ui,
    }
    step = dispatch.get(model)
    if step is None:
        fail("runtime-protocol-trace-mismatch", "unknown runtime model")
    return step(state, event)


def runtime_public_output(model: str, state: Mapping[str, Any]) -> Dict[str, Any]:
    if model == "CloseReceiptV1":
        return {
            "closed_waiters": state["closed_waiters"],
            "deliveries": state["deliveries"],
            "next_registration_ordinal": str(state["next_registration"]),
            "state": state["phase"],
        }
    if model == "TaskV1":
        return {
            "cancelled_waiters": state["cancelled_waiters"],
            "deliveries": state["deliveries"],
            "generation": None if state["generation"] is None else str(state["generation"]),
            "next_registration_ordinal": str(state["next_registration"]),
            "result_type": state["result_type"],
            "state": state["phase"],
        }
    if model == "PackedNextV1":
        return {
            "builder_calls": state["builder_calls"],
            "builder_terminal": state["builder_terminal"],
            "child_owner": state["child_owner"],
            "close_reason": state["close_reason"],
            "live_leases": sorted(key for key, value in state["leases"].items() if value in {"ArmedV1", "ConstructionV1"}),
            "next_lease_ordinal": str(state["next_lease"]),
            "receipt": state["receipt"],
            "report_count": state["report_count"],
            "state": state["phase"],
        }
    if model == "ResourceV1":
        return {
            "admitted_keys": state["admitted"],
            "committed": state["committed"],
            "generation_cursor": str(state["generation_cursor"]),
            "ignored_settlements": [str(value) for value in state["ignored"]],
            "retained": state["retained"],
            "report_count": state["report_count"],
            "state": state["phase"],
            "view": state["view"],
        }
    if model == "SignalV1":
        return {
            "child_owner": state["child_owner"],
            "cleanup_count": state["cleanup_count"],
            "dependency_sets": state["dependency_sets"],
            "generation": str(state["generation"]),
            "invalidations": state["invalidations"],
            "state": state["phase"],
        }
    if model == "SealedFinallyV1":
        return {
            "finalizer_count": state["finalizer_count"],
            "report_count": state["report_count"],
            "retired_roles": state["retired"],
            "state": state["phase"],
            "terminal_tag": state["terminal"],
        }
    if model == "ComponentResourceV1":
        return {
            "active_borrow": state["borrow"],
            "child_owner": state["child_owner"],
            "destroy_count": state["destroy_count"],
            "handle": state["handle"],
            "report_count": state["report_count"],
            "state": state["phase"],
        }
    if model == "UiDispatcherV1":
        live = sum(value in {"QueuedV1", "RunningV1"} for value in state["lease_states"].values())
        return {
            "callbacks": state["callbacks"],
            "cleanup_count": state["cleanup_count"],
            "generation": None if state["generation"] is None else str(state["generation"]),
            "gate": state["gate"],
            "live_generation_count": str(live),
            "released_leases": state["released"],
            "state": state["phase"],
        }
    if model == "CheckpointRunnerV1":
        return {
            "aborted_epochs": [str(value) for value in state["aborted"]],
            "committed": [
                {"epoch": str(item["epoch"]), "value": item["value"]}
                for item in state["committed"]
            ],
            "latest_epoch": None if state["latest_epoch"] is None else str(state["latest_epoch"]),
            "released_leases": state["released"],
            "retained": state["retained"],
            "stale_epochs": [str(value) for value in state["stale"]],
            "state": state["phase"],
        }
    fail("runtime-protocol-trace-mismatch", "unknown runtime model")
    raise AssertionError("unreachable")


def runtime_replay(model: str, events: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    state = runtime_initial_state(model)
    for event in events:
        state = runtime_step(model, state, event)
    return runtime_public_output(model, state)


def build_runtime_protocol_models() -> Dict[str, Any]:
    packed_parent = "owner-app"
    packed_child = runtime_child_owner(packed_parent, "packed", "0")
    packed_receipt = packed_child + "/receipt"
    ui_gate = "ui-generation/0"
    signal_parent = "owner-signal-root"
    signal_child = runtime_child_owner(signal_parent, "signal", "0")
    traces = [
        {
            "events": [
                {"epoch": "0", "op": "publish", "value": "A"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "lease": "checkpoint/0/lease", "op": "compute"},
                {"claim": "checkpoint/0/claim", "dependency": "source-a", "op": "track_read"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "op": "prepare"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "lease": "checkpoint/0/lease", "op": "commit"},
                {"op": "close"},
            ],
            "id": "checkpoint-commit-close",
            "model": "CheckpointRunnerV1",
        },
        {
            "events": [
                {"epoch": "0", "op": "publish", "value": "A"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "lease": "checkpoint/0/lease", "op": "compute"},
                {"claim": "checkpoint/0/claim", "dependency": "source-a", "op": "track_read"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "op": "prepare"},
                {"epoch": "1", "op": "publish", "value": "B"},
                {"epoch": "2", "op": "publish", "value": "C"},
                {"claim": "checkpoint/0/claim", "epoch": "0", "lease": "checkpoint/0/lease", "op": "stale"},
                {"claim": "checkpoint/2/claim", "epoch": "2", "lease": "checkpoint/2/lease", "op": "compute"},
                {"claim": "checkpoint/2/claim", "dependency": "source-c", "op": "track_read"},
                {"claim": "checkpoint/2/claim", "epoch": "2", "op": "prepare"},
                {"claim": "checkpoint/2/claim", "epoch": "2", "lease": "checkpoint/2/lease", "op": "abort"},
                {"op": "close"},
            ],
            "id": "checkpoint-stale-retained",
            "model": "CheckpointRunnerV1",
        },
        {
            "events": [
                {"child_owner": "owner-ui/component/0", "handle": "owner-ui/component/0/handle/0", "op": "export_handle", "parent_owner": "owner-ui"},
                {"borrow": "borrow-0", "handle": "owner-ui/component/0/handle/0", "op": "borrow_enter"},
                {"borrow": "borrow-0", "op": "borrow_return"},
                {"handle": "owner-ui/component/0/handle/0", "op": "destroy"},
                {"op": "emit_report"},
            ],
            "id": "component-resource-borrow-close",
            "model": "ComponentResourceV1",
        },
        {
            "events": [
                {"child_owner": packed_child, "op": "admit_builder", "parent_owner": packed_parent, "receipt": packed_receipt},
                {"op": "parent_close", "reason": "ParentOwnerCloseV1", "receipt": packed_receipt},
                {"op": "builder_terminal", "tag": "ReturnsV2"},
                {"op": "finalize", "receipt": packed_receipt},
            ],
            "id": "packed-building-parent-close",
            "model": "PackedNextV1",
        },
        {
            "events": [
                {"child_owner": packed_child, "op": "admit_builder", "parent_owner": packed_parent, "receipt": packed_receipt},
                {"op": "builder_terminal", "tag": "ReturnsV2"},
                {"lease": "1", "op": "acquire"},
                {"lease": "2", "op": "acquire"},
                {"op": "dispose", "reason": "ExplicitDisposeV1", "receipt": packed_receipt},
                {"lease": "1", "op": "release"},
                {"lease": "2", "op": "release"},
                {"op": "finalize", "receipt": packed_receipt},
            ],
            "id": "packed-multi-lease-close",
            "model": "PackedNextV1",
        },
        {
            "events": [
                {"observer_generation": "0", "op": "register", "waiter": "w0"},
                {"observer_generation": "0", "op": "register", "waiter": "w1"},
                {"op": "resolve", "value": {"disposed": True, "roles": ["PackedRunnerV1"]}},
                {"op": "deliver", "waiter": "w0"},
                {"op": "close_waiter", "waiter": "w1"},
                {"observer_generation": "1", "op": "register", "waiter": "w2"},
                {"op": "deliver", "waiter": "w2"},
            ],
            "id": "receipt-multiwaiter-late",
            "model": "CloseReceiptV1",
        },
        {
            "events": [
                {"generation": "0", "op": "open"},
                {"epoch": "0", "key": "A", "op": "publish"},
                {"generation": "1", "key": "A", "op": "start"},
                {"generation": "1", "op": "succeed", "value": "good-A"},
                {"epoch": "1", "key": "B", "op": "publish"},
                {"generation": "2", "key": "B", "op": "start"},
                {"error": "network", "generation": "2", "op": "fail"},
            ],
            "id": "resource-last-good-on-failure",
            "model": "ResourceV1",
        },
        {
            "events": [
                {"generation": "0", "op": "open"},
                {"epoch": "0", "key": "A", "op": "publish"},
                {"generation": "1", "key": "A", "op": "start"},
                {"epoch": "1", "key": "B", "op": "publish"},
                {"epoch": "2", "key": "C", "op": "publish"},
                {"generation": "1", "op": "succeed", "value": "stale-A"},
                {"generation": "2", "op": "admit_retained"},
                {"generation": "2", "op": "succeed", "value": "current-C"},
                {"op": "dispose", "reason": "ExplicitDisposeV1"},
            ],
            "id": "resource-latest-retained",
            "model": "ResourceV1",
        },
        {
            "events": [
                {"op": "open"},
                {"op": "reserve", "ordinal": "0", "role": "ResourceCandidateV1"},
                {"op": "reserve", "ordinal": "1", "role": "UiListenerV1"},
                {"op": "body_terminal", "tag": "AbortsV2"},
                {"op": "retire", "role": "UiListenerV1"},
                {"op": "retire", "role": "ResourceCandidateV1"},
                {"op": "run_finalizer"},
                {"op": "emit_report"},
                {"op": "close"},
            ],
            "id": "sealed-finally-terminal-preserved",
            "model": "SealedFinallyV1",
        },
        {
            "events": [
                {"child_owner": signal_child, "op": "install", "parent_owner": signal_parent},
                {"generation": "0", "op": "begin_run", "token": signal_child + "/generation/0"},
                {"dependency": "source-a", "op": "track_read", "token": signal_child + "/generation/0"},
                {"op": "finish_run", "token": signal_child + "/generation/0"},
                {"dependency": "source-a", "op": "invalidate", "token": signal_child + "/generation/0"},
                {"generation": "1", "op": "begin_run", "token": signal_child + "/generation/1"},
                {"dependency": "source-b", "op": "track_read", "token": signal_child + "/generation/1"},
                {"op": "finish_run", "token": signal_child + "/generation/1"},
                {"op": "dispose"},
            ],
            "id": "signal-dependency-rerun",
            "model": "SignalV1",
        },
        {
            "events": [
                {"cancel_authority": "TaskProducerOwnerV1", "generation": "0", "op": "create", "result_type": "IntV1"},
                {"generation": "0", "observer_generation": "0", "op": "register", "waiter": "w0"},
                {"authority": "TaskProducerOwnerV1", "generation": "0", "op": "central_cancel"},
            ],
            "id": "task-central-cancel",
            "model": "TaskV1",
        },
        {
            "events": [
                {"cancel_authority": "TaskProducerOwnerV1", "generation": "0", "op": "create", "result_type": "IntV1"},
                {"generation": "0", "observer_generation": "0", "op": "register", "waiter": "w0"},
                {"generation": "0", "observer_generation": "0", "op": "register", "waiter": "w1"},
                {"op": "cancel_waiter", "waiter": "w0"},
                {"generation": "0", "op": "resolve", "value": {"kind": "IntV1", "value": 7}},
                {"op": "deliver", "waiter": "w1"},
                {"generation": "0", "observer_generation": "1", "op": "register", "waiter": "w2"},
                {"op": "deliver", "waiter": "w2"},
            ],
            "id": "task-independent-cancel",
            "model": "TaskV1",
        },
        {
            "events": [
                {"gate": ui_gate, "generation": "0", "op": "open_generation"},
                {"event_ordinal": "0", "event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/0", "op": "enqueue", "payload": {"draft": "alpha"}},
                {"event_ordinal": "1", "event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/1", "op": "enqueue", "payload": {"draft": "beta"}},
                {"op": "dequeue"},
                {"gate": ui_gate, "generation": "0", "op": "close_gate"},
                {"op": "finalize_queued"},
                {"event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "op": "return_running", "returns": "UnitV1"},
                {"gate": ui_gate, "generation": "0", "op": "cleanup_generation"},
            ],
            "id": "ui-close-running-queued",
            "model": "UiDispatcherV1",
        },
        {
            "events": [
                {"gate": ui_gate, "generation": "0", "op": "open_generation"},
                {"event_ordinal": "0", "event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/0", "op": "enqueue", "payload": {"draft": "alpha"}},
                {"event_ordinal": "1", "event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/1", "op": "enqueue", "payload": {"draft": "beta"}},
                {"op": "dequeue"},
                {"event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "op": "return_running", "returns": "UnitV1"},
                {"op": "dequeue"},
                {"event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "op": "return_running", "returns": "UnitV1"},
            ],
            "id": "ui-fifo-exact-payload",
            "model": "UiDispatcherV1",
        },
        {
            "events": [
                {"gate": ui_gate, "generation": "0", "op": "open_generation"},
                {"event_ordinal": "0", "event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/0", "op": "enqueue", "payload": {"draft": "one"}},
                {"event_ordinal": "1", "event_type": "ToggleEventV1", "gate": ui_gate, "generation": "0", "lease": ui_gate + "/event/1", "op": "enqueue", "payload": {"checked": True, "key": 42}},
                {"op": "dequeue"},
                {"event_type": "SaveEventV1", "gate": ui_gate, "generation": "0", "op": "return_running", "returns": "UnitV1"},
                {"op": "dequeue"},
                {"event_type": "ToggleEventV1", "gate": ui_gate, "generation": "0", "op": "return_running", "returns": "UnitV1"},
            ],
            "id": "ui-heterogeneous-exact-payload",
            "model": "UiDispatcherV1",
        },
    ]
    return {
        "artifact": "CireRuntimeProtocolModelsV1",
        "invariants": RUNTIME_INVARIANTS,
        "models": RUNTIME_MODEL_ORDER,
        "profile": PROFILE,
        "schema_version": 1,
        "traces": traces,
    }


RUNTIME_GOLDENS: Dict[str, Dict[str, Any]] = {
    "checkpoint-commit-close": {
        "aborted_epochs": [],
        "committed": [{"epoch": "0", "value": "A"}],
        "latest_epoch": "0",
        "released_leases": ["checkpoint/0/lease"],
        "retained": None,
        "stale_epochs": [],
        "state": "ClosedV1",
    },
    "checkpoint-stale-retained": {
        "aborted_epochs": ["2"],
        "committed": [],
        "latest_epoch": "2",
        "released_leases": ["checkpoint/0/lease", "checkpoint/2/lease"],
        "retained": None,
        "stale_epochs": ["0"],
        "state": "ClosedV1",
    },
    "component-resource-borrow-close": {
        "active_borrow": None,
        "child_owner": "owner-ui/component/0",
        "destroy_count": 1,
        "handle": "owner-ui/component/0/handle/0",
        "report_count": 1,
        "state": "ClosedV1",
    },
    "packed-building-parent-close": {
        "builder_calls": 1,
        "builder_terminal": "ReturnsV2",
        "child_owner": "owner-app/packed/0",
        "close_reason": "ParentOwnerCloseV1",
        "live_leases": [],
        "next_lease_ordinal": "1",
        "receipt": "owner-app/packed/0/receipt",
        "report_count": 1,
        "state": "ClosedV1",
    },
    "packed-multi-lease-close": {
        "builder_calls": 1,
        "builder_terminal": "ReturnsV2",
        "child_owner": "owner-app/packed/0",
        "close_reason": "ExplicitDisposeV1",
        "live_leases": [],
        "next_lease_ordinal": "3",
        "receipt": "owner-app/packed/0/receipt",
        "report_count": 1,
        "state": "ClosedV1",
    },
    "receipt-multiwaiter-late": {
        "closed_waiters": ["w1"],
        "deliveries": [
            {"value": {"disposed": True, "roles": ["PackedRunnerV1"]}, "waiter": "w0"},
            {"value": {"disposed": True, "roles": ["PackedRunnerV1"]}, "waiter": "w2"},
        ],
        "next_registration_ordinal": "3",
        "state": "ResolvedV1",
    },
    "resource-last-good-on-failure": {
        "admitted_keys": ["A", "B"],
        "committed": {"generation": 1, "key": "A", "value": "good-A"},
        "generation_cursor": "2",
        "ignored_settlements": [],
        "report_count": 0,
        "retained": None,
        "state": "OpenV1",
        "view": {"error": "network", "kind": "DegradedV1", "value": "good-A"},
    },
    "resource-latest-retained": {
        "admitted_keys": ["A", "C"],
        "committed": {"generation": 2, "key": "C", "value": "current-C"},
        "generation_cursor": "2",
        "ignored_settlements": ["1"],
        "report_count": 1,
        "retained": None,
        "state": "ClosedV1",
        "view": {"kind": "ClosedV1", "last_good": "current-C"},
    },
    "sealed-finally-terminal-preserved": {
        "finalizer_count": 1,
        "report_count": 1,
        "retired_roles": ["UiListenerV1", "ResourceCandidateV1"],
        "state": "ClosedV1",
        "terminal_tag": "AbortsV2",
    },
    "signal-dependency-rerun": {
        "child_owner": "owner-signal-root/signal/0",
        "cleanup_count": 1,
        "dependency_sets": [["source-a"], ["source-b"]],
        "generation": "1",
        "invalidations": ["source-a"],
        "state": "ClosedV1",
    },
    "task-central-cancel": {
        "cancelled_waiters": [],
        "deliveries": [],
        "generation": "0",
        "next_registration_ordinal": "1",
        "result_type": "IntV1",
        "state": "OwnerClosedV1",
    },
    "task-independent-cancel": {
        "cancelled_waiters": ["w0"],
        "deliveries": [
            {"value": {"kind": "IntV1", "value": 7}, "waiter": "w1"},
            {"value": {"kind": "IntV1", "value": 7}, "waiter": "w2"},
        ],
        "generation": "0",
        "next_registration_ordinal": "3",
        "result_type": "IntV1",
        "state": "ResolvedV1",
    },
    "ui-close-running-queued": {
        "callbacks": [{"event_ordinal": 0, "event_type": "SaveEventV1", "payload": {"draft": "alpha"}}],
        "cleanup_count": 1,
        "gate": "ui-generation/0",
        "generation": "0",
        "live_generation_count": "0",
        "released_leases": ["ui-generation/0/event/1", "ui-generation/0/event/0"],
        "state": "ClosedV1",
    },
    "ui-fifo-exact-payload": {
        "callbacks": [
            {"event_ordinal": 0, "event_type": "SaveEventV1", "payload": {"draft": "alpha"}},
            {"event_ordinal": 1, "event_type": "SaveEventV1", "payload": {"draft": "beta"}},
        ],
        "cleanup_count": 0,
        "gate": "ui-generation/0",
        "generation": "0",
        "live_generation_count": "0",
        "released_leases": ["ui-generation/0/event/0", "ui-generation/0/event/1"],
        "state": "OpenV1",
    },
    "ui-heterogeneous-exact-payload": {
        "callbacks": [
            {"event_ordinal": 0, "event_type": "SaveEventV1", "payload": {"draft": "one"}},
            {"event_ordinal": 1, "event_type": "ToggleEventV1", "payload": {"checked": True, "key": 42}},
        ],
        "cleanup_count": 0,
        "gate": "ui-generation/0",
        "generation": "0",
        "live_generation_count": "0",
        "released_leases": ["ui-generation/0/event/0", "ui-generation/0/event/1"],
        "state": "OpenV1",
    },
}


def validate_runtime(value: Any) -> None:
    root = exact_keys(
        value,
        ["artifact", "invariants", "models", "profile", "schema_version", "traces"],
        "runtime-protocol-trace-mismatch",
        "CireRuntimeProtocolModelsV1",
    )
    validate_profile_header(root, "CireRuntimeProtocolModelsV1", 1, "runtime-protocol-trace-mismatch")
    if root["invariants"] != RUNTIME_INVARIANTS:
        fail("runtime-protocol-trace-mismatch", "runtime invariant vector differs")
    if root["models"] != RUNTIME_MODEL_ORDER:
        fail("runtime-protocol-trace-mismatch", "runtime model vector differs")
    traces = require_list(root["traces"], "runtime-protocol-trace-mismatch", "traces")
    if [item.get("id") for item in traces] != RUNTIME_TRACE_IDS:
        fail("runtime-protocol-trace-mismatch", "runtime trace order differs")
    for trace in traces:
        exact_keys(
            trace,
            ["events", "id", "model"],
            "runtime-protocol-trace-mismatch",
            "runtime trace",
        )
        require_list(trace["events"], "runtime-protocol-trace-mismatch", "events")
        if RUNTIME_TRACE_MODELS.get(trace["id"]) != trace["model"]:
            fail("runtime-protocol-trace-mismatch", trace["id"] + " model binding differs")
        replayed = runtime_replay(trace["model"], trace["events"])
        if replayed != RUNTIME_GOLDENS.get(trace["id"]):
            fail(
                "runtime-protocol-trace-mismatch",
                trace["id"] + " replay differs from validator-owned golden: " + repr(replayed),
            )
    expected_root = build_runtime_protocol_models()
    if root != expected_root:
        fail("runtime-protocol-trace-mismatch", "runtime trace model differs from deterministic builder")


def runtime_candidate_events(model: str, state: Mapping[str, Any]) -> List[Dict[str, Any]]:
    events: List[Dict[str, Any]] = []
    phase = state["phase"]
    if model == "CloseReceiptV1":
        for waiter in ("w0", "w1"):
            if waiter not in state["waiters"]:
                events.append({"observer_generation": "0", "op": "register", "waiter": waiter})
        if phase == "PendingV1":
            events.append({"op": "resolve", "value": {"disposed": True, "roles": ["PackedRunnerV1"]}})
        for waiter, claim in sorted(state["waiters"].items()):
            if claim["status"] == "ArmedV1":
                if phase == "ResolvedV1":
                    events.append({"op": "deliver", "waiter": waiter})
                events.append({"op": "close_waiter", "waiter": waiter})
    elif model == "TaskV1":
        if phase == "UncreatedV1":
            events.append({"cancel_authority": "TaskProducerOwnerV1", "generation": "0", "op": "create", "result_type": "IntV1"})
        if phase in {"PendingV1", "ResolvedV1"}:
            for waiter in ("w0", "w1"):
                if waiter not in state["waiters"]:
                    events.append({"generation": "0", "observer_generation": "0", "op": "register", "waiter": waiter})
        if phase == "PendingV1":
            events.extend([
                {"generation": "0", "op": "resolve", "value": {"kind": "IntV1", "value": 7}},
                {"authority": "TaskProducerOwnerV1", "generation": "0", "op": "central_cancel"},
            ])
        for waiter, claim in sorted(state["waiters"].items()):
            if claim["status"] == "ArmedV1":
                if phase == "ResolvedV1":
                    events.append({"op": "deliver", "waiter": waiter})
                if phase in {"PendingV1", "ResolvedV1"}:
                    events.append({"op": "cancel_waiter", "waiter": waiter})
    elif model == "PackedNextV1":
        parent = "owner-app"
        child = runtime_child_owner(parent, "packed", "0")
        receipt = child + "/receipt"
        if phase == "InitialV1":
            events.append({"child_owner": child, "op": "admit_builder", "parent_owner": parent, "receipt": receipt})
        elif phase == "BuildingV1":
            events.extend([
                {"op": "parent_close", "reason": "ParentOwnerCloseV1", "receipt": receipt},
                {"op": "builder_terminal", "tag": "ReturnsV2"},
                {"op": "builder_terminal", "tag": "AbortsV2"},
                {"op": "builder_terminal", "tag": "TransfersV2"},
            ])
        elif phase == "OpenV1":
            if state["next_lease"] < 3:
                events.append({"lease": str(state["next_lease"]), "op": "acquire"})
            events.append({"op": "dispose", "reason": "ExplicitDisposeV1", "receipt": receipt})
        if phase in {"OpenV1", "ClosingV1"}:
            for lease, status in sorted(state["leases"].items()):
                if status == "ArmedV1":
                    events.append({"lease": lease, "op": "release"})
        if phase == "ClosingV1" and state["builder_terminal"] is not None and not any(
            status in {"ArmedV1", "ConstructionV1"} for status in state["leases"].values()
        ):
            events.append({"op": "finalize", "receipt": receipt})
    elif model == "ResourceV1":
        if phase == "InitialV1":
            events.append({"generation": "0", "op": "open"})
        elif phase == "OpenV1":
            if state["input_cursor"] is None:
                events.append({"epoch": "0", "key": "A", "op": "publish"})
            elif state["input_cursor"] < 2:
                next_epoch = state["input_cursor"] + 1
                events.append({"epoch": str(next_epoch), "key": chr(ord("A") + next_epoch), "op": "publish"})
            if (
                state["busy"] is None
                and state["latest"] is not None
                and state["retained"] is None
                and state["latest"]["epoch"] not in state["admitted_epochs"]
            ):
                events.append({"generation": str(state["generation_cursor"] + 1), "key": state["latest"]["key"], "op": "start"})
            if state["busy"] is not None:
                generation = str(state["busy"]["generation"])
                events.extend([
                    {"generation": generation, "op": "succeed", "value": "value-" + state["busy"]["key"]},
                    {"error": "failed-" + state["busy"]["key"], "generation": generation, "op": "fail"},
                ])
            if state["busy"] is None and state["retained"] is not None:
                events.append({"generation": str(state["generation_cursor"] + 1), "op": "admit_retained"})
            if state["busy"] is None and state["retained"] is None:
                events.append({"op": "dispose", "reason": "ExplicitDisposeV1"})
    elif model == "SignalV1":
        parent = "owner-signal-root"
        child = runtime_child_owner(parent, "signal", "0")
        if phase == "InitialV1":
            events.append({"child_owner": child, "op": "install", "parent_owner": parent})
        elif phase == "OpenV1":
            token = child + "/generation/" + str(state["generation"])
            if state["generation"] not in state["completed_generations"]:
                events.append({"generation": str(state["generation"]), "op": "begin_run", "token": token})
            if state["dependency_sets"] and state["generation"] < 1:
                events.append({"dependency": state["dependency_sets"][-1][0], "op": "invalidate", "token": token})
            events.append({"op": "dispose"})
        elif phase == "RunningV1":
            for dependency in ("source-a", "source-b"):
                if dependency not in state["current_dependencies"]:
                    events.append({"dependency": dependency, "op": "track_read", "token": state["active_token"]})
            if state["current_dependencies"] and state["current_dependencies"] == sorted(state["current_dependencies"]):
                events.append({"op": "finish_run", "token": state["active_token"]})
    elif model == "SealedFinallyV1":
        if phase == "InitialV1":
            events.append({"op": "open"})
        elif phase == "BodyV1":
            roles = ["ResourceCandidateV1", "UiListenerV1"]
            if len(state["reserved"]) < len(roles):
                events.append({"op": "reserve", "ordinal": str(len(state["reserved"])), "role": roles[len(state["reserved"])]})
            for terminal in ("ReturnsV2", "AbortsV2", "TransfersV2"):
                events.append({"op": "body_terminal", "tag": terminal})
        elif phase == "RetiringV1":
            if len(state["retired"]) < len(state["reserved"]):
                events.append({"op": "retire", "role": state["reserved"][len(state["reserved"]) - len(state["retired"]) - 1]})
            elif state["finalizer_count"] == 0:
                events.append({"op": "run_finalizer"})
            elif state["report_count"] == 0:
                events.append({"op": "emit_report"})
            else:
                events.append({"op": "close"})
    elif model == "ComponentResourceV1":
        if phase == "InitialV1":
            events.append({"child_owner": "owner-ui/component/0", "handle": "owner-ui/component/0/handle/0", "op": "export_handle", "parent_owner": "owner-ui"})
        elif phase == "OpenV1":
            if state["borrow"] is None:
                events.extend([
                    {"borrow": "borrow-0", "handle": state["handle"], "op": "borrow_enter"},
                    {"handle": state["handle"], "op": "destroy"},
                ])
            else:
                events.append({"borrow": state["borrow"], "op": "borrow_return"})
        elif phase == "ClosingV1":
            events.append({"op": "emit_report"})
    elif model == "UiDispatcherV1":
        gate = "ui-generation/0"
        if phase == "InitialV1":
            events.append({"gate": gate, "generation": "0", "op": "open_generation"})
        elif phase in {"OpenV1", "ClosingV1"}:
            if phase == "OpenV1" and state["next_event"] < 2:
                ordinal = str(state["next_event"])
                event_type = "SaveEventV1" if ordinal == "0" else "ToggleEventV1"
                payload = {"draft": "alpha"} if ordinal == "0" else {"checked": True, "key": 42}
                events.append({"event_ordinal": ordinal, "event_type": event_type, "gate": gate, "generation": "0", "lease": gate + "/event/" + ordinal, "op": "enqueue", "payload": payload})
            if state["running"] is None and state["queue"]:
                events.append({"op": "dequeue"})
            if state["running"] is not None:
                events.append({"event_type": state["running"]["event_type"], "gate": gate, "generation": "0", "op": "return_running", "returns": "UnitV1"})
            if phase == "OpenV1":
                events.append({"gate": gate, "generation": "0", "op": "close_gate"})
            else:
                if state["queue"]:
                    events.append({"op": "finalize_queued"})
                live = sum(value in {"QueuedV1", "RunningV1"} for value in state["lease_states"].values())
                if not state["queue"] and state["running"] is None and live == 0:
                    events.append({"gate": gate, "generation": "0", "op": "cleanup_generation"})
    elif model == "CheckpointRunnerV1":
        if phase != "ClosedV1" and (state["latest_epoch"] is None or state["latest_epoch"] < 2):
            epoch = 0 if state["latest_epoch"] is None else state["latest_epoch"] + 1
            events.append({"epoch": str(epoch), "op": "publish", "value": chr(ord("A") + epoch)})
        if phase == "OpenV1":
            if state["latest_epoch"] is not None:
                epoch = str(state["latest_epoch"])
                claim = "checkpoint/" + epoch + "/claim"
                lease = "checkpoint/" + epoch + "/lease"
                if claim not in state["settled_claims"] and lease not in state["released"]:
                    events.append({"claim": claim, "epoch": epoch, "lease": lease, "op": "compute"})
            if state["latest_epoch"] is not None and state["retained"] is None:
                events.append({"op": "close"})
        elif phase == "ComputeV1":
            active = state["active"]
            for dependency in ("source-a", "source-b"):
                if dependency not in active["dependencies"]:
                    events.append({"claim": active["claim"], "dependency": dependency, "op": "track_read"})
            if active["dependencies"] and active["dependencies"] == sorted(active["dependencies"]):
                events.append({"claim": active["claim"], "epoch": str(active["epoch"]), "op": "prepare"})
        elif phase == "PreparedV1":
            active = state["active"]
            if active["epoch"] == state["latest_epoch"]:
                events.extend([
                    {"claim": active["claim"], "epoch": str(active["epoch"]), "lease": active["lease"], "op": "commit"},
                    {"claim": active["claim"], "epoch": str(active["epoch"]), "lease": active["lease"], "op": "abort"},
                ])
            else:
                events.append({"claim": active["claim"], "epoch": str(active["epoch"]), "lease": active["lease"], "op": "stale"})
    return events


def bounded_protocol_exploration() -> Dict[str, Any]:
    """Explore fixed finite domains through the exact trace transition functions."""

    model_counts: Dict[str, Dict[str, int]] = {}
    for model in RUNTIME_MODEL_ORDER:
        initial = runtime_initial_state(model)
        pending = deque([initial])
        seen = {canonical_bytes(initial)}
        transitions = 0
        while pending:
            state = pending.popleft()
            for event in runtime_candidate_events(model, state):
                successor = runtime_step(model, state, event)
                transitions += 1
                key = canonical_bytes(successor)
                if key not in seen:
                    seen.add(key)
                    pending.append(successor)
        if len(seen) < 2 or transitions < 1:
            fail("runtime-protocol-trace-mismatch", model + " bounded domain is vacuous")
        model_counts[model] = {
            "state_count": len(seen),
            "transition_count": transitions,
        }
    return {
        "explored_state_count": sum(item["state_count"] for item in model_counts.values()),
        "explored_transition_count": sum(item["transition_count"] for item in model_counts.values()),
        "model_counts": [
            {"model": model, **model_counts[model]} for model in RUNTIME_MODEL_ORDER
        ],
    }


EXPECTED_SCHEMA_POINTER_COUNT = 0
EXPECTED_SCHEMA_POINTER_SET_HASH = ""
EXPECTED_CLOSED_KIND_VOCABULARY: tuple[str, ...] = ('AbortsV2',
 'AcceptedV1',
 'AcquireOptionReturnMapV1',
 'ActionPlanContractV1',
 'AdmittedUiGenerationV1',
 'AlphaRenameStabilityV1',
 'AnonV1',
 'AnonymousAsyncRowV1',
 'ApplicationEntryWorldV2',
 'ApplyTypeV2',
 'ApplyWorldTransitionV2',
 'ArgumentCaptureV1',
 'ArgumentV1',
 'ArrayElementCaptureV1',
 'ArrayElementProvenanceV1',
 'AssociatedFunctionV1',
 'AssociatedProjectionV1',
 'AsyncMaySuspendV1',
 'AwaitOrParkV1',
 'BinderTypeTemplateV1',
 'BindingCallbackRefV1',
 'BoundarySafeV1',
 'BuiltinConstructorV1',
 'BuiltinTypeTemplateV1',
 'BuiltinTypeV1',
 'BytesConstV1',
 'CacheEquivalenceCollisionV1',
 'CallableCallbackRefV1',
 'CallableComponentItemV1',
 'CallableSurfaceSignatureV1',
 'CallbackFlowV1',
 'CallbackOnlyV1',
 'CallbackRowV1',
 'CallbackSuspensionV1',
 'CallbackWorldV1',
 'CanonicalFirstPartyLiteralPathsV1',
 'CapabilityTypeTemplateV1',
 'CapabilityTypeV2',
 'CertificateV1',
 'ChildOwnerRegionV1',
 'ClockPackageSummaryV1',
 'Closed',
 'ClosedLiteralV1',
 'ClosedV1',
 'ConstIntV1',
 'ContextualCallbackRefV1',
 'ContractParameterRefV2',
 'DecodeFailureV1',
 'DefaultChangeCascadeV1',
 'DefaultPrologueV1',
 'Degraded',
 'DerivedCurrentOwnerBinderV1',
 'DerivedV1',
 'DiagnosticV1',
 'DirectAndCallbackPrivateV1',
 'DirectCapabilityDriftRejectionV1',
 'DirectOnlyV1',
 'DirectV1',
 'DuplicableEnvV1',
 'EmptyRowV1',
 'EmptyV1',
 'EntryWorldV1',
 'EnumV1',
 'EvidenceTypeRefV1',
 'ExactCallbackEntryOwnerV1',
 'ExactOperationV1',
 'FirstPartyBindingV1',
 'FirstPartyCallbackSchemeV1',
 'FirstPartyCallbackV1',
 'FirstPartyContractTemplateV1',
 'FloatV1',
 'FrameClockIdentityV1',
 'FreshBinderRefV1',
 'FunctionContractBinderV2',
 'FunctionContractKindV2',
 'FunctionTypeTemplateV1',
 'FunctionTypeV2',
 'GenerativeFreshBinderV1',
 'GenericBinderRefV1',
 'GenericEffectRowV1',
 'HandleV1',
 'HandlerContractV3',
 'HandlerTemplateTypeV2',
 'HostObservableV1',
 'ImplicitReceiverSlotV1',
 'ImportedCallableSlotRefV3',
 'InstalledTrackEpochV1',
 'InstalledTrackInvocationV1',
 'IntegerConstV1',
 'IntegerV1',
 'IntrinsicModuleFunctionV1',
 'InvokeV2',
 'JoinV2',
 'KindBinderV1',
 'LegacyCaptureExprV2',
 'LegacyNominalIndexExprV2',
 'LegacyObligationV2',
 'LegacyProvenanceExprV2',
 'LegacyResultTransformerV2',
 'LegacySlotRefV2',
 'LegacyTypeRefV2',
 'LegacyWorldExprV2',
 'ListV1',
 'LiteralPathsV2',
 'LocalFunctionRefV2',
 'LocalInferenceV1',
 'MapCallbackFlowV1',
 'NamedOrPositionalSlotV1',
 'NamedV1',
 'NewtypeV1',
 'NextTypeV2',
 'NoCallbackEntryOwnerV1',
 'NoCaptureV1',
 'NoNominalIndexV1',
 'NoSuspendV1',
 'NominalConstructorV1',
 'NominalEffectFamilyTemplateV1',
 'NominalTypeTemplateV1',
 'NominalTypeV1',
 'NominalTypeV2',
 'OpaqueTypeV1',
 'OpenedPackedNextBinderV1',
 'OperationCallV1',
 'OperationResultCaptureV1',
 'OperationResultProvenanceV1',
 'OwnerAuthorityV1',
 'OwnerBoundV1',
 'OwnerIndexV1',
 'OwnerTypeV2',
 'OwnerV1',
 'PackNextReturnMapV1',
 'PackageIdentityEvidenceV1',
 'PackageIdentityInputV1',
 'PackageInstanceIdV1',
 'PackedNextDisposeV1',
 'PackedNextOpenV1',
 'PackedNextPackV1',
 'ParameterSlotRefV1',
 'ParametricResultV1',
 'ParametricResultV2',
 'PathBindV2',
 'PhaseAllowsV1',
 'ProjectPrivateWorldV1',
 'ProofRuleEvidenceV1',
 'ProtocolEvidenceV1',
 'PublicCallableCycleRejectionV1',
 'PublicLabelCascadeV1',
 'PureV1',
 'Ready',
 'RecordVariantV1',
 'RequestV1',
 'ResolveAtInstallationV1',
 'ResourceDisposeV1',
 'ResourceLoaderContractV1',
 'ResourceSwitchLatestV1',
 'ResourceViewV1',
 'RetainedCallbackContractV1',
 'ReturnCaptureV2',
 'ReturnProvenanceV2',
 'ReturnsOnlyV1',
 'ReturnsV2',
 'ReverseOrderDeterminismV1',
 'SameWorldV1',
 'ScalarV1',
 'ScopedApplyV1',
 'Sealed',
 'SignalMapV1',
 'SignalTailContractEvidenceV1',
 'SignalTrackV1',
 'SnapshotReadLiveV1',
 'SnapshotReadSourceV1',
 'StableV1',
 'StoredFieldV1',
 'StringConstV1',
 'StringV1',
 'StructV1',
 'StructuralIntrinsicV1',
 'TaskCancelV1',
 'TrackReadLiveV1',
 'TrackReadSourceV1',
 'TransfersV2',
 'TransparentAliasV1',
 'TupleVariantV1',
 'Type',
 'TypeParameterV2',
 'TypeRefV1',
 'UiAdmissionInvocationV1',
 'UiBackpressureCoalesceLatestV1',
 'UiBuilderOwnerV1',
 'UiCandidateActionV1',
 'UiMountDisposeV1',
 'UiRenderV1',
 'UiRevisionOfV1',
 'UiRevisionScopeBinderV1',
 'UiRunSignalV1',
 'UnitVariantV1',
 'UnqualifiedFunctionV1',
 'WholeProgramImportedEqualityV1',
 'accept',
 'reject')
EXPECTED_CLOSED_ENUM_DOMAINS: tuple[
    tuple[str, tuple[str | bool, ...]], ...
] = (('diagnostics-v3.json|anonymous|fix_safety',
  ('MachineApplicable', 'MaybeIncorrect', 'Manual', 'None')),
 ('diagnostics-v3.json|anonymous|primary_origin_role',
  ('PrincipalV1', 'ArgumentV1', 'DeclarationV1', 'SynthesisBasisV1')),
 ('diagnostics-v3.json|anonymous|stage',
  ('Decode',
   'Lex',
   'Parse',
   'Syntax',
   'Resolve',
   'Kind',
   'Type',
   'Row',
   'HandlerWF',
   'Flow',
   'Capture',
   'Usage',
   'World',
   'Phase',
   'Owner',
   'ContractWF')),
 ('interfaces/call-assembly.json|anonymous|call_form', ('ExplicitArgListV1',)),
 ('interfaces/call-assembly.json|anonymous|outcome',
  ('DuplicateLabelRejectedV1',
   'FinalSlotAlreadyFilledV1',
   'LaterDefaultSlotOutOfScopeV1',
   'PositionalAfterLabelRejectedV1',
   'UnknownLabelRejectedV1')),
 ('interfaces/callable-contract-fact.json|CallableContractFactEvidenceV1|trap',
  ('NoTrapV1',)),
 ('interfaces/callable-interface.json|anonymous|passing', ('NamedOrPositionalV1',)),
 ('interfaces/component-interface.json|CireComponentInterfaceV1|memory',
  ('Memory32V1',)),
 ('interfaces/component-interface.json|CireComponentInterfaceV1|native_async',
  (False,)),
 ('interfaces/component-interface.json|CireComponentInterfaceV1|string_encoding',
  ('Utf8V1',)),
 ('interfaces/component-interface.json|ScalarV1|scalar', ('S32V1', 'U8V1')),
 ('interfaces/component-interface.json|StringV1|encoding', ('Utf8V1',)),
 ('interfaces/component-interface.json|anonymous|cire_defect',
  ('DefectTransitionV1AfterSuffixRetirementV1',)),
 ('interfaces/component-interface.json|anonymous|host_or_engine_trap',
  ('CatastrophicInstanceFailureV1',)),
 ('interfaces/component-interface.json|anonymous|owner_policy',
  ('PerCallChildOwnerV1',)),
 ('interfaces/component-interface.json|anonymous|provenance', ('CallbackOrFfiV1',)),
 ('interfaces/component-interface.json|anonymous|suspend', (False,)),
 ('interfaces/component-interface.json|anonymous|terminal_close_policy',
  ('EveryCireReturnsOrAbortsV1',)),
 ('interfaces/control-mutation.json|DerivedV1|derivation_kind',
  ('InlineHandlerExpansionV1',)),
 ('interfaces/control-mutation.json|HandlerContractV3|capture', ('NoCaptureV1',)),
 ('interfaces/control-mutation.json|HandlerContractV3|flow', ('ReturnsV2',)),
 ('interfaces/control-mutation.json|HandlerContractV3|phase', ('Compute',)),
 ('interfaces/control-mutation.json|HandlerContractV3|usage', ('ManyV1',)),
 ('interfaces/control-mutation.json|anonymous|evaluation',
  ('ConditionOncePerIterationV1',
   'ConditionThenSelectedBranchV1',
   'FreshLoopTargetV1',
   'InnermostLoopTargetV1',
   'IteratorExpressionExactlyOnceV1',
   'OperandBeforeTransferV1',
   'ScrutineeExactlyOnceV1',
   'TargetResolvedBeforeOperandV1')),
 ('interfaces/control-mutation.json|anonymous|lowering',
  ('CoreIfV1',
   'CoreLoopV1',
   'FreshLexicalBreakTargetV1',
   'FreshLexicalContinueTargetV1',
   'FreshLexicalReturnTargetV1',
   'SourceOrderTemporaryV1+CoreLoopV1',
   'SourceOrderTemporaryV1+CoreMatchV1',
   'SourceOrderTemporaryV1+StateThreadedIteratorV1+CoreLoopV1')),
 ('interfaces/control-mutation.json|anonymous|mode',
  ('ctl', 'fun', 'once', 'return', 'structural')),
 ('interfaces/control-mutation.json|anonymous|outcome',
  ('BreakTransferContributesNeverV1',
   'ContinueTransferContributesNeverV1',
   'MultiShotMutableCaptureRejectedV1',
   'MutablePlaceCaptureRejectedV1',
   'MutablePlaceEscapeRejectedV1',
   'OneShotUniqueNoAliasAcceptedV1',
   'OrderedExactlyOnceAcceptedV1',
   'ReturnTransferContributesNeverV1',
   'SuspendWithLivePlaceRejectedV1')),
 ('interfaces/control-mutation.json|anonymous|source_form',
  ('FullHandlerV1', 'InlineHandlerV1')),
 ('interfaces/control-mutation.json|anonymous|stage', ('Syntax',)),
 ('interfaces/elaboration-origin-map.json|anonymous|derivation_kind',
  ('CallEntryTupleV1',
   'DefaultPrologueV1',
   'FreshCapabilityV1',
   'FreshPromptV1',
   'HiddenFinalizeV1',
   'HiddenTailResumeV1',
   'ImplicitHandlerReturnV1',
   'InlineHandlerExpansionV1',
   'ParameterTupleV1',
   'SealedIntrinsicV1',
   'SourceOrderTemporaryV1',
   'TrailingLambdaArgumentV1',
   'WithRightFoldV1')),
 ('interfaces/elaboration-origin-map.json|anonymous|node_kind',
  ('DirectV1', 'DerivedV1')),
 ('interfaces/elaboration-origin-map.json|anonymous|role', ('PrincipalV1',)),
 ('interfaces/first-party-registry.json|ActionPlanContractV1|occurrence_policy',
  ('OwnerStoredExactQueuedOccurrenceV1',)),
 ('interfaces/first-party-registry.json|AwaitOrParkV1|park', ('ParkContractV2',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|capture_policy',
  ('ActualArgumentsAndCallbacksV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|demand_policy',
  ('NormalizedRowAndKernelV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|obligation_policy',
  ('EvidenceArrayOrderV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|origin_policy',
  ('ElaborationOriginProjectionV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|result_policy',
  ('TypeAndFlowDirectedV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|site_policy',
  ('AllReferencedDirectAndProjectedCallbackSitesV1',)),
 ('interfaces/first-party-registry.json|CanonicalFirstPartyLiteralPathsV1|usage_policy',
  ('AuthoritySlotsExactV1',)),
 ('interfaces/first-party-registry.json|ChildOwnerRegionV1|relation',
  ('DirectChildV1',)),
 ('interfaces/first-party-registry.json|ClosedLiteralV1|variant', ('CoalesceLatest',)),
 ('interfaces/first-party-registry.json|DerivedCurrentOwnerBinderV1|binder_kind',
  ('OwnerRegionV1',)),
 ('interfaces/first-party-registry.json|DerivedCurrentOwnerBinderV1|derivation',
  ('CurrentOwnerOfEntryPhaseV1',)),
 ('interfaces/first-party-registry.json|FirstPartyCallbackSchemeV1|trigger',
  ('CallableInvocationV1',
   'DirectInvocationV1',
   'PerAdmittedGenerationV1',
   'PerEventDispatchV1',
   'PerInstalledSubscriptionV1')),
 ('interfaces/first-party-registry.json|FirstPartyCallbackV1|acquisition',
  ('CallableValueV1', 'ContextualV1')),
 ('interfaces/first-party-registry.json|FirstPartyContractTemplateV1|phase',
  ('PureV1', 'ComputeV1', 'ActionV1')),
 ('interfaces/first-party-registry.json|GenerativeFreshBinderV1|binder_kind',
  ('ClockIdentityV1',
   'ClockPackageSummaryV1',
   'OwnerRegionV1',
   'TrackEpochScopeV1',
   'UiGenerationScopeV1',
   'UiRevisionScopeV1')),
 ('interfaces/first-party-registry.json|GenerativeFreshBinderV1|cardinality',
  ('PerAdmittedGenerationV1', 'PerDirectCallV1', 'PerInstalledSubscriptionV1')),
 ('interfaces/first-party-registry.json|ImplicitReceiverSlotV1|passing',
  ('ImplicitReceiverV1',)),
 ('interfaces/first-party-registry.json|KindBinderV1|binder_kind',
  ('ClockIdentityV1',
   'EffectRowV1',
   'OwnerRegionV1',
   'TrackEpochScopeV1',
   'TypeV1',
   'UiGenerationScopeV1')),
 ('interfaces/first-party-registry.json|NamedOrPositionalSlotV1|passing',
  ('NamedOrPositionalV1',)),
 ('interfaces/first-party-registry.json|OpenedPackedNextBinderV1|binder_kind',
  ('ClockIdentityV1', 'ClockPackageSummaryV1', 'OwnerRegionV1')),
 ('interfaces/first-party-registry.json|RetainedCallbackContractV1|capture_policy',
  ('OwnerStorageBoundarySafeOutlivesV1',)),
 ('interfaces/function-contract-v3-suite.json|BoundarySafeV1|boundary',
  ('CallArgument',)),
 ('interfaces/function-contract-v3-suite.json|BoundarySafeV1|stage', ('Call',)),
 ('interfaces/function-contract-v3-suite.json|CertificateV1|publish', ('None',)),
 ('interfaces/function-contract-v3-suite.json|CertificateV1|replay_origin', ('Fresh',)),
 ('interfaces/function-contract-v3-suite.json|CertificateV1|suspend', ('OwnerBound',)),
 ('interfaces/function-contract-v3-suite.json|CertificateV1|temporal',
  ('HostObservable',)),
 ('interfaces/function-contract-v3-suite.json|DuplicableEnvV1|stage',
  ('HandlerInstall',)),
 ('interfaces/function-contract-v3-suite.json|HandlerTemplateTypeV2|policy',
  ('PersistentTemplateV1',)),
 ('interfaces/function-contract-v3-suite.json|OwnerBoundV1|grade', ('MaySuspend',)),
 ('interfaces/function-contract-v3-suite.json|PathBindV2|terminal_policy',
  ('PreserveTerminalV2',)),
 ('interfaces/function-contract-v3-suite.json|PhaseAllowsV1|stage',
  ('HandlerInstall',)),
 ('interfaces/function-contract-v3-suite.json|RequestV1|grade', ('NoSuspend',)),
 ('interfaces/function-contract-v3-suite.json|RequestV1|site_role', ('Primary',)),
 ('interfaces/function-contract-v3-suite.json|ResolveAtInstallationV1|on_missing',
  ('RootOfEntryV1',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|completion_generation_gate',
  ('EqualCurrentGeneration',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|completion_transition',
  ('UnclaimedToCompleted',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|failure_transition',
  ('NoStateChange',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|finalization_generation_gate',
  ('EqualCurrentGenerationOrOwnerRetireAuthority',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|finalization_transition',
  ('UnclaimedToFinalized',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|generation_model',
  ('Unsigned64NoWrap',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|generation_transition',
  ('PreserveGeneration',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|grade',
  ('MaySuspend', 'NoSuspend')),
 ('interfaces/function-contract-v3-suite.json|anonymous|mode', ('ctl',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|namespace',
  ('Clock', 'ClosureCapture', 'Identity', 'Owner', 'Parameter')),
 ('interfaces/function-contract-v3-suite.json|anonymous|passing',
  ('NamedOrPositionalV1',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|role', ('DirectV1',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|scope',
  ('LexicalInstallation',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|site_role', ('Primary',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|source_generation',
  ('ClaimTicketGeneration',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|stage', ('HandlerInstall',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|usage', ('Once',)),
 ('interfaces/function-contract-v3-suite.json|anonymous|write_authority',
  ('OwnerExecutorOnly',)),
 ('interfaces/function-contract-v3.json|anonymous|grade', ('NoSuspend',)),
 ('interfaces/function-contract-v3.json|anonymous|namespace', ('Parameter',)),
 ('interfaces/link-abi.json|CireLinkAbiV1|calling_convention',
  ('CirePrivateWasmCallV1',)),
 ('interfaces/link-abi.json|anonymous|memory', ('Memory32V1',)),
 ('interfaces/link-abi.json|anonymous|memory_sharing', ('NonSharedV1',)),
 ('interfaces/link-abi.json|anonymous|validation', ('Wasm3.0V1',)),
 ('interfaces/local-inference.json|anonymous|atomic_hidden_contract',
  ('WholeFnContractOnlyV1',)),
 ('interfaces/local-inference.json|anonymous|binding', ('ImmutableLocalLetV1',)),
 ('interfaces/local-inference.json|anonymous|boundary_kind',
  ('LocalLambdaV1', 'NamedDefV1')),
 ('interfaces/local-inference.json|anonymous|decision',
  ('GeneralizeV1', 'WeakMonomorphicV1')),
 ('interfaces/local-inference.json|anonymous|environment_stability',
  ('StableDuplicableV1', 'UnstableOrLinearV1')),
 ('interfaces/local-inference.json|anonymous|fallback', ('WeakMonomorphicV1',)),
 ('interfaces/local-inference.json|anonymous|initializer',
  ('ComputationV1', 'LambdaConstructionV1', 'ValueV1')),
 ('interfaces/local-inference.json|anonymous|meta',
  ('FloatLiteralV1', 'IntegerLiteralV1')),
 ('interfaces/local-inference.json|anonymous|named_boundary',
  ('EveryNamedDefExplicitV1',)),
 ('interfaces/local-inference.json|anonymous|rank', ('QualifiedRank1V1',)),
 ('interfaces/local-inference.json|anonymous|reason',
  ('AuthorityCaptureV1',
   'ClockQuantificationV1',
   'EffectfulInitializerV1',
   'EligibleV1',
   'ExpansiveInitializerV1',
   'ForbiddenBinderKindV1',
   'GenerativeIdentityV1',
   'NonReplayableCleanupV1',
   'NotManyCallSafeV1',
   'OpenConstraintsV1',
   'OwnerQuantificationV1',
   'ReachableBorrowV1',
   'ReachableClaimV1',
   'ReachableMutableCellV1',
   'ReachableResumptionV1',
   'UnstableEnvironmentV1')),
 ('interfaces/local-inference.json|anonymous|visibility', ('PrivateV1', 'PublicV1')),
 ('interfaces/nominal-data.json|EnumV1|visibility', ('PublicV1',)),
 ('interfaces/nominal-data.json|NewtypeV1|visibility', ('PublicV1',)),
 ('interfaces/nominal-data.json|OpaqueTypeV1|visibility', ('PublicV1',)),
 ('interfaces/nominal-data.json|StoredFieldV1|visibility', ('PackageV1', 'PublicV1')),
 ('interfaces/nominal-data.json|StructV1|visibility', ('PublicV1',)),
 ('interfaces/nominal-data.json|TransparentAliasV1|visibility', ('PackageV1',)),
 ('interfaces/nominal-data.json|anonymous|visibility', ('PackageV1', 'PublicV1')),
 ('interfaces/numeric-semantics.json|FloatV1|carrier', ('F32V1', 'F64V1')),
 ('interfaces/numeric-semantics.json|FloatV1|signed', (True,)),
 ('interfaces/numeric-semantics.json|IntegerV1|carrier', ('I32V1', 'I64V1')),
 ('interfaces/numeric-semantics.json|IntegerV1|signed', (False, True)),
 ('interfaces/numeric-semantics.json|anonymous|canonical_nan',
  ('positive-quiet-zero-payload',)),
 ('interfaces/numeric-semantics.json|anonymous|default_operations',
  ('MayTrapV1+DefectTransitionV1',)),
 ('interfaces/numeric-semantics.json|anonymous|float_to_int',
  ('checked-truncate-toward-zero',)),
 ('interfaces/numeric-semantics.json|anonymous|int_to_float',
  ('round-nearest-ties-to-even',)),
 ('interfaces/numeric-semantics.json|anonymous|to_bits_from_bits',
  ('exact-bit-preserving',)),
 ('interfaces/numeric-semantics.json|anonymous|trap_fact', ('MayTrapV1', 'NoTrapV1')),
 ('interfaces/primitive-catalog.json|anonymous|carrier',
  ('F32V1', 'F64V1', 'I32V1', 'I64V1', 'NoneV1', 'PrivateManagedV1')),
 ('interfaces/structural-intrinsic-registry.json|StructuralIntrinsicV1|contract',
  ('BuildStringContractV1', 'FinalizerContractV1')),
 ('interfaces/structural-intrinsic-registry.json|StructuralIntrinsicV1|kernel',
  ('BuildStringV1', 'ControlFinallyV1')),
 ('interfaces/structural-intrinsic-registry.json|StructuralIntrinsicV1|origin_kind',
  ('SealedIntrinsicV1',)),
 ('interfaces/structural-intrinsic-registry.json|StructuralIntrinsicV1|source_form',
  ('@control::finally', 'StringInterpolationV1')),
 ('interfaces/trait-impl-extension.json|anonymous|visibility', ('PublicOpenV1',)),
 ('runtime/protocol-models.json|anonymous|close_reason',
  ('ExplicitDisposeV1', 'ParentOwnerCloseV1')),
 ('runtime/protocol-models.json|anonymous|reason',
  ('ExplicitDisposeV1', 'ParentOwnerCloseV1')),
 ('runtime/protocol-models.json|anonymous|role', ('ResourceRunner', 'UiRunner')),
 ('runtime/protocol-models.json|anonymous|state', ('Open', 'Resolved', 'Closed')),
 ('runtime/protocol-models.json|anonymous|terminal_tag', ('AbortsV2',)))
SYNTHETIC_CLOSED_KIND_POSITIVES: tuple[str, ...] = ()
SYNTHETIC_CLOSED_ENUM_POSITIVES: tuple[
    tuple[str, tuple[str | bool, ...]], ...
] = (('diagnostics-v3.json|anonymous|stage', ('Lex', 'HandlerWF')),)
CANONICAL_ARRAY_POINTERS: tuple[str, ...] = (
    "diagnostics-v3.json:/diagnostics",
    "interfaces/call-assembly.json:/cases",
    "interfaces/component-interface.json:/exports",
    "interfaces/component-interface.json:/type_mappings",
    "interfaces/component-manifest.json:/exports",
    "interfaces/const-values.json:/definitions",
    "interfaces/const-values.json:/evaluation_cases",
    "interfaces/control-mutation.json:/control_cases",
    "interfaces/control-mutation.json:/place_cases",
    "interfaces/control-mutation.json:/structural_forms",
    "interfaces/elaboration-origin-map.json:/nodes",
    "interfaces/elaboration-origin-map.json:/sites",
    "interfaces/first-party-registry.json:/bindings",
    "interfaces/function-contract-v3-suite.json:/cases",
    "interfaces/function-contract-v3-suite.json:/differentials",
    "interfaces/function-contract-v3-suite.json:/differentials/0/inputs/parameter_slot_renaming",
    "interfaces/function-contract-v3-suite.json:/differentials/5/inputs/edges",
    "interfaces/function-contract-v3-suite.json:/differentials/6/inputs/dependency_cases",
    "interfaces/function-contract-v3-suite.json:/differentials/7/inputs/dependency_cases",
    "interfaces/function-contract-v3-suite.json:/expectations/callee_before_caller",
    "interfaces/ability-declaration.json:/associated_items",
    "interfaces/ability-declaration.json:/binders/type_binders",
    "interfaces/ability-declaration.json:/operations",
    "interfaces/callable-contract-fact.json:/trait_method_uses",
    "interfaces/data-declaration.json:/binders/type_binders",
    "interfaces/data-declaration.json:/body/variants",
    "interfaces/data-declaration.json:/body/variants/0/payload/fields",
    "interfaces/data-declaration.json:/derives",
    "interfaces/effect-declaration.json:/binders/type_binders",
    "interfaces/effect-declaration.json:/conformances",
    "interfaces/effect-declaration.json:/conformances/0/associated_arguments",
    "interfaces/effect-declaration.json:/declared_operations",
    "interfaces/impl-evidence.json:/associated_types",
    "interfaces/impl-evidence.json:/methods",
    "interfaces/language-interface.json:/callables",
    "interfaces/language-interface.json:/components",
    "interfaces/language-interface.json:/declarations",
    "interfaces/language-interface.json:/evidence",
    "interfaces/link-abi.json:/callable_layouts",
    "interfaces/local-inference.json:/generalization_cases",
    "interfaces/local-inference.json:/named_boundary_cases",
    "interfaces/nominal-data.json:/construction_cases",
    "interfaces/nominal-data.json:/declarations",
    "interfaces/nominal-data.json:/layout_cases",
    "interfaces/nominal-data.json:/pattern_cases",
    "interfaces/numeric-semantics.json:/carrier_cases",
    "interfaces/numeric-semantics.json:/conversion_cases",
    "interfaces/numeric-semantics.json:/differential_cases",
    "interfaces/numeric-semantics.json:/integer_boundary_cases",
    "interfaces/numeric-semantics.json:/literal_types",
    "interfaces/numeric-semantics.json:/operation_cases",
    "interfaces/primitive-catalog.json:/entries",
    "interfaces/structural-intrinsic-registry.json:/bindings",
    "interfaces/trait-impl-extension.json:/coherence_cases",
    "interfaces/trait-impl-extension.json:/extensions",
    "interfaces/trait-impl-extension.json:/impls",
    "interfaces/trait-impl-extension.json:/resolution_cases",
    "interfaces/trait-impl-extension.json:/traits",
    "interfaces/trait-declaration.json:/associated_types",
    "interfaces/trait-declaration.json:/binders/type_binders",
    "interfaces/trait-declaration.json:/methods",
    "runtime/protocol-models.json:/invariants",
    "runtime/protocol-models.json:/models",
    "runtime/protocol-models.json:/traces",
)
HASH_GRAPH_POLICIES: tuple[tuple[str, str, str], ...] = (
    (
        "interfaces/callable-interface.json:/core_contract/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/callable-contract-fact.json:/callable/callable_interface/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/intrinsic-registry.json:/first_party/artifact_hash",
        "intrinsic-registry-root-mismatch",
        "intrinsic-registry-root-mismatch",
    ),
    (
        "interfaces/intrinsic-registry.json:/structural/artifact_hash",
        "intrinsic-registry-root-mismatch",
        "intrinsic-registry-root-mismatch",
    ),
    (
        "interfaces/language-interface.json:/evidence/0/evidence/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/evidence/1/evidence/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/declarations/0/declaration/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/declarations/1/declaration/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/declarations/2/declaration/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/declarations/3/declaration/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/declarations/4/declaration/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/callables/0/callable_interface/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/language-interface.json:/components/0/manifest/artifact_hash",
        "component-public-type-not-safe",
        "component-public-type-not-safe",
    ),
    (
        "interfaces/language-interface.json:/primitive_catalog/artifact_hash",
        "package-instance-hash-mismatch",
        "package-instance-hash-mismatch",
    ),
    (
        "interfaces/language-interface.json:/intrinsic_registry/artifact_hash",
        "intrinsic-registry-root-mismatch",
        "intrinsic-registry-root-mismatch",
    ),
    (
        "interfaces/component-manifest.json:/exports/0/item/callable/callable_interface/artifact_hash",
        "component-public-type-not-safe",
        "component-public-type-not-safe",
    ),
    (
        "interfaces/link-abi.json:/language_interface/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/link-abi.json:/callable_layouts/0/callable_interface_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
    (
        "interfaces/component-interface.json:/manifest/artifact_hash",
        "component-public-type-not-safe",
        "component-public-type-not-safe",
    ),
    (
        "interfaces/component-interface.json:/link_abi/artifact_hash",
        "component-public-type-not-safe",
        "component-public-type-not-safe",
    ),
    (
        "interfaces/component-interface.json:/exports/0/callable/callable_interface/artifact_hash",
        "callable-interface-contract-mismatch",
        "callable-interface-contract-mismatch",
    ),
)

CLOSED_ENUM_FIELDS = {
    "acquisition",
    "atomic_hidden_contract",
    "binder_kind",
    "binding",
    "boundary",
    "boundary_kind",
    "call_form",
    "calling_convention",
    "canonical_nan",
    "capture",
    "capture_policy",
    "cardinality",
    "carrier",
    "cire_defect",
    "close_reason",
    "completion_generation_gate",
    "completion_transition",
    "contract",
    "decision",
    "default_operations",
    "demand_policy",
    "derivation",
    "derivation_kind",
    "encoding",
    "environment_stability",
    "evaluation",
    "fallback",
    "failure_transition",
    "finalization_generation_gate",
    "finalization_transition",
    "fix_safety",
    "float_to_int",
    "flow",
    "generation_model",
    "generation_transition",
    "grade",
    "host_or_engine_trap",
    "initializer",
    "int_to_float",
    "kernel",
    "lowering",
    "memory",
    "memory_sharing",
    "meta",
    "mode",
    "named_boundary",
    "native_async",
    "namespace",
    "node_kind",
    "obligation_policy",
    "occurrence_policy",
    "on_missing",
    "origin_kind",
    "origin_policy",
    "outcome",
    "owner_policy",
    "park",
    "passing",
    "phase",
    "policy",
    "primary_origin_role",
    "provenance",
    "publish",
    "rank",
    "reason",
    "relation",
    "replay_origin",
    "result_policy",
    "role",
    "scalar",
    "scope",
    "signed",
    "site_policy",
    "site_role",
    "source_form",
    "source_generation",
    "stage",
    "state",
    "string_encoding",
    "suspend",
    "suspension",
    "temporal",
    "terminal_close_policy",
    "terminal_policy",
    "terminal_tag",
    "to_bits_from_bits",
    "trap",
    "trap_fact",
    "trigger",
    "usage",
    "usage_policy",
    "validation",
    "variant",
    "visibility",
    "world",
    "write_authority",
}
CLOSED_U32_FIELDS = {
    "anchor",
    "binder_slot",
    "code_point",
    "end",
    "epoch",
    "event_parameter_index",
    "fresh_slot",
    "generation",
    "kernel_node_preorder",
    "occurrence",
    "ordinal",
    "origin_id",
    "parameter_slot",
    "revision",
    "root_binding_slot",
    "scalar_probe",
    "slot",
    "start",
    "width",
    "application_slot",
    "binder_site_slot",
    "builder_calls",
    "callback_runs",
    "claim_cell_slot",
    "cleanup_count",
    "continuation_site_slot",
    "declaration_slot",
    "destroy_count",
    "finalizer_calls",
    "from",
    "id",
    "identity_drift_slot",
    "identity_slot",
    "import_slot",
    "latest_epoch",
    "live_generation_count",
    "next_registration_ordinal",
    "owner_slot",
    "packed_parameter_slot",
    "park_site_slot",
    "port_slot",
    "prompt_slot",
    "report_calls",
    "report_count",
    "return_slot",
    "rhs_evaluations",
    "root_declaration_slot",
    "selector_evaluations",
    "site_slot",
    "source_parameter_slot",
    "to",
    "writes",
}


def json_pointer_child(pointer: str, key: str | int) -> str:
    escaped = str(key).replace("~", "~0").replace("/", "~1")
    return pointer + "/" + escaped


def schema_value_shape(value: Any) -> str:
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, str):
        return "string"
    return type(value).__name__


def closed_field_spec(field: str, value: Any) -> str:
    if isinstance(value, str):
        if field == "kind":
            return "tag:" + value
        if field in CLOSED_ENUM_FIELDS:
            return "enum-string:" + value
        if field in {"artifact", "profile"}:
            return "literal:" + value
        if SHA256_RE.fullmatch(value):
            return "sha256"
        return "string"
    if isinstance(value, bool):
        if field in CLOSED_ENUM_FIELDS:
            return "enum-bool:" + ("true" if value else "false")
        return "bool"
    if isinstance(value, int):
        if field == "schema_version":
            return "literal-int:" + str(value)
        if field in CLOSED_U32_FIELDS:
            return "u32"
        return "int"
    if value is None:
        return "null"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    raise AssertionError("non-JSON value in closed schema")


def closed_object_schema(value: Mapping[str, Any]) -> Dict[str, str]:
    return {key: closed_field_spec(key, child) for key, child in value.items()}


def closed_check_field(value: Any, spec: str, context: str) -> None:
    if spec == "object":
        if not isinstance(value, dict):
            fail("Decode/type-mismatch", context + " must be an object")
        return
    if spec == "array":
        if not isinstance(value, list):
            fail("Decode/type-mismatch", context + " must be an array")
        return
    if spec == "null":
        if value is not None:
            fail("Decode/type-mismatch", context + " must be null")
        return
    if spec == "bool":
        if not isinstance(value, bool):
            fail("Decode/type-mismatch", context + " must be a boolean")
        return
    if spec == "int":
        if isinstance(value, bool) or not isinstance(value, int):
            fail("Decode/type-mismatch", context + " must be an integer")
        return
    if spec == "u32":
        if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 1 << 32:
            fail("Decode/u32-mismatch", context + " must be a wire u32")
        return
    if spec == "string":
        if not isinstance(value, str):
            fail("Decode/type-mismatch", context + " must be a string")
        walk_json(value, context)
        return
    if spec == "sha256":
        if not isinstance(value, str) or not SHA256_RE.fullmatch(value) or value == ZERO_HASH:
            fail("Decode/hash-mismatch", context + " must be a nonzero SHA-256")
        return
    if spec.startswith("tag:"):
        if not isinstance(value, str):
            fail("Decode/type-mismatch", context + " tag must be a string")
        if value != spec.removeprefix("tag:"):
            fail("Decode/tag-mismatch", context + " has an unknown union tag")
        return
    if spec.startswith("enum-string:"):
        if not isinstance(value, str):
            fail("Decode/type-mismatch", context + " enum must be a string")
        if value != spec.removeprefix("enum-string:"):
            fail("Decode/enum-mismatch", context + " has an unknown enum literal")
        return
    if spec.startswith("enum-bool:"):
        if not isinstance(value, bool):
            fail("Decode/type-mismatch", context + " enum must be a boolean")
        expected = spec.removeprefix("enum-bool:") == "true"
        if value != expected:
            fail("Decode/enum-mismatch", context + " has an unknown enum literal")
        return
    if spec.startswith("literal:"):
        if not isinstance(value, str):
            fail("Decode/type-mismatch", context + " literal must be a string")
        if value != spec.removeprefix("literal:"):
            fail("Decode/literal-mismatch", context + " literal differs")
        return
    if spec.startswith("literal-int:"):
        expected = int(spec.removeprefix("literal-int:"))
        if isinstance(value, bool) or not isinstance(value, int):
            fail("Decode/type-mismatch", context + " literal must be an integer")
        if value != expected:
            fail("Decode/literal-mismatch", context + " integer literal differs")
        return
    raise AssertionError("unknown closed field spec " + spec)


def closed_check_object(
    value: Any, schema: Mapping[str, str], context: str
) -> None:
    if not isinstance(value, dict):
        fail("Decode/object-mismatch", context + " must be an object")
    if set(value) != set(schema):
        fail("Decode/closed-field-mismatch", context + " fields differ")
    for field, spec in schema.items():
        closed_check_field(value[field], spec, context + "/" + field)


def incompatible_schema_value(spec: str) -> Any:
    if spec in {"object", "array"}:
        return "__wrong_container__"
    if spec == "null":
        return "__not_null__"
    if spec in {"bool", "int", "u32"} or spec.startswith("literal-int:"):
        return "__wrong_scalar__"
    return {"__wrong_scalar__": True}


def closed_schema_inventory(documents: Mapping[str, Any]) -> Dict[str, Any]:
    objects: List[Dict[str, Any]] = []
    tags: List[tuple[str, str, str]] = []
    enums: List[tuple[str, str, str, str, str | bool]] = []
    u32s: List[tuple[str, str]] = []
    hashes: List[tuple[str, str]] = []
    arrays: Dict[str, List[Any]] = {}

    def visit(path: str, value: Any, pointer: str, field: str = "$") -> None:
        if isinstance(value, dict):
            schema = closed_object_schema(value)
            objects.append(
                {"path": path, "pointer": pointer, "value": value, "schema": schema}
            )
            parent_tag = value.get("kind", value.get("artifact", "anonymous"))
            parent_context = (
                parent_tag if isinstance(parent_tag, str) else "anonymous"
            )
            for key, child in value.items():
                child_pointer = json_pointer_child(pointer, key)
                spec = schema[key]
                if spec.startswith("tag:"):
                    tags.append((path, child_pointer, spec.removeprefix("tag:")))
                if spec.startswith("enum-string:"):
                    enums.append(
                        (
                            path,
                            child_pointer,
                            parent_context,
                            key,
                            spec.removeprefix("enum-string:"),
                        )
                    )
                if spec.startswith("enum-bool:"):
                    enums.append(
                        (
                            path,
                            child_pointer,
                            parent_context,
                            key,
                            spec.removeprefix("enum-bool:") == "true",
                        )
                    )
                if spec == "u32":
                    u32s.append((path, child_pointer))
                if spec == "sha256":
                    hashes.append((path, child_pointer))
                visit(path, child, child_pointer, key)
        elif isinstance(value, list):
            arrays[path + ":" + (pointer or "/")] = value
            for index, child in enumerate(value):
                visit(path, child, json_pointer_child(pointer, index), field)
        elif isinstance(value, str):
            walk_json(value, path + ":" + (pointer or "/"))

    excluded = {"authority-rule-coverage.json", "mutations/profile-mutations.json"}
    for path in sorted(set(ARTIFACT_FILES) - excluded):
        visit(path, documents[path], "")
    tag_vocabulary = sorted({tag for _path, _pointer, tag in tags})
    enum_domains: Dict[str, set[str | bool]] = {}
    for path, _pointer, parent, field, value in enums:
        domain = path + "|" + parent + "|" + field
        enum_domains.setdefault(domain, set()).add(value)
    return {
        "objects": objects,
        "tags": tags,
        "enums": enums,
        "u32s": u32s,
        "hashes": hashes,
        "arrays": arrays,
        "tag_vocabulary": tag_vocabulary,
        "enum_domains": enum_domains,
    }


def schema_pointer_descriptors(inventory: Mapping[str, Any]) -> List[str]:
    descriptors: List[str] = []
    for item in inventory["objects"]:
        prefix = item["path"] + ":" + (item["pointer"] or "/")
        descriptors.append("object-container:" + prefix)
        descriptors.append("object-extra:" + prefix)
        for field, spec in sorted(item["schema"].items()):
            descriptors.append("field-missing:" + prefix + ":" + field)
            descriptors.append("field-type:" + prefix + ":" + field + ":" + spec)
    descriptors.extend(
        "tag-unknown:" + path + ":" + pointer + ":" + tag
        for path, pointer, tag in inventory["tags"]
    )
    descriptors.extend(
        "enum-unknown:"
        + path
        + ":"
        + pointer
        + ":"
        + parent
        + ":"
        + field
        + ":"
        + json.dumps(value, ensure_ascii=False)
        for path, pointer, parent, field, value in inventory["enums"]
    )
    for path, pointer in inventory["u32s"]:
        for boundary in ("bool", "negative", "overflow"):
            descriptors.append("u32:" + path + ":" + pointer + ":" + boundary)
    for path, pointer in inventory["hashes"]:
        descriptors.append("hash-zero:" + path + ":" + pointer)
        descriptors.append("hash-malformed:" + path + ":" + pointer)
    canonical_arrays = set(CANONICAL_ARRAY_POINTERS)
    for pointer, value in sorted(inventory["arrays"].items()):
        mode = "canonical-vector" if pointer in canonical_arrays else "semantic-sequence"
        suffix = ":" + object_hash(value) if mode == "canonical-vector" else ""
        descriptors.append("array-policy:" + mode + ":" + pointer + suffix)
    for pointer in CANONICAL_ARRAY_POINTERS:
        descriptors.append("array-remove:" + pointer)
        descriptors.append("array-duplicate:" + pointer)
        descriptors.append("array-order:" + pointer)
    for pointer, zero_diagnostic, malformed_diagnostic in HASH_GRAPH_POLICIES:
        descriptors.append("hash-edge-zero:" + pointer)
        descriptors.append("hash-edge-malformed:" + pointer)
        descriptors.append("hash-edge-zero-diagnostic:" + zero_diagnostic)
        descriptors.append("hash-edge-malformed-diagnostic:" + malformed_diagnostic)
    descriptors.extend(["unicode:non-nfc", "unicode:lone-surrogate"])
    return sorted(descriptors)


def schema_pointer_audit(documents: Mapping[str, Any]) -> Dict[str, int]:
    """Exhaust the pinned closed-schema matrix without semantic-hash fallback."""

    inventory = closed_schema_inventory(documents)
    descriptors = schema_pointer_descriptors(inventory)
    pointer_hash = object_hash(descriptors)
    if EXPECTED_SCHEMA_POINTER_COUNT and (
        len(descriptors) != EXPECTED_SCHEMA_POINTER_COUNT
        or pointer_hash != EXPECTED_SCHEMA_POINTER_SET_HASH
    ):
        fail("Decode/schema-pointer-set-mismatch", "closed-schema pointer set differs")
    observed_kinds = set(inventory["tag_vocabulary"])
    positive_kinds = observed_kinds | set(SYNTHETIC_CLOSED_KIND_POSITIVES)
    if len(EXPECTED_CLOSED_KIND_VOCABULARY) != len(
        set(EXPECTED_CLOSED_KIND_VOCABULARY)
    ):
        fail(
            "Decode/schema-tag-vocabulary-mismatch",
            "closed union tag vocabulary has duplicates",
        )
    if EXPECTED_CLOSED_KIND_VOCABULARY and positive_kinds != set(
        EXPECTED_CLOSED_KIND_VOCABULARY
    ):
        fail("Decode/schema-tag-vocabulary-mismatch", "closed union tag coverage differs")
    for tag in SYNTHETIC_CLOSED_KIND_POSITIVES:
        closed_check_object(
            {"kind": tag}, {"kind": "tag:" + tag}, "synthetic kind " + tag
        )
    expected_enum_domains = dict(EXPECTED_CLOSED_ENUM_DOMAINS)
    synthetic_enum_domains = dict(SYNTHETIC_CLOSED_ENUM_POSITIVES)
    if expected_enum_domains:
        if len(expected_enum_domains) != len(EXPECTED_CLOSED_ENUM_DOMAINS):
            fail(
                "Decode/schema-enum-vocabulary-mismatch",
                "closed enum domain inventory has duplicates",
            )
        if set(inventory["enum_domains"]) != set(expected_enum_domains):
            fail(
                "Decode/schema-enum-vocabulary-mismatch",
                "closed enum domain inventory differs",
            )
        for domain, expected_values in expected_enum_domains.items():
            if len(expected_values) != len(set(expected_values)):
                fail(
                    "Decode/schema-enum-vocabulary-mismatch",
                    domain + " has duplicate allowed enum literals",
                )
            positive_values = set(inventory["enum_domains"][domain]) | set(
                synthetic_enum_domains.get(domain, ())
            )
            if positive_values != set(expected_values):
                fail(
                    "Decode/schema-enum-vocabulary-mismatch",
                    domain + " positive enum coverage differs",
                )
            for value in synthetic_enum_domains.get(domain, ()):
                spec = (
                    "enum-bool:" + ("true" if value else "false")
                    if isinstance(value, bool)
                    else "enum-string:" + value
                )
                closed_check_field(value, spec, "synthetic enum " + domain)

    mutation_count = 0

    def expect_failure(action: Any, diagnostic: str, label: str) -> None:
        nonlocal mutation_count
        mutation_count += 1
        try:
            action()
        except ValidationFailure as error:
            if error.diagnostic != diagnostic:
                fail(
                    "Decode/schema-pointer-wrong-failure",
                    label + " expected " + diagnostic + " but observed " + error.diagnostic,
                )
            return
        except Exception as error:  # noqa: BLE001 - totality is normative
            fail(
                "Decode/schema-pointer-host-exception",
                label + " leaked host " + type(error).__name__ + ": " + str(error),
            )
        fail("Decode/schema-pointer-accepted", label + " unexpectedly accepted")

    for item in inventory["objects"]:
        path = item["path"]
        pointer = item["pointer"] or "/"
        value = item["value"]
        schema = item["schema"]
        closed_check_object(value, schema, path + ":" + pointer)
        expect_failure(
            lambda schema=schema, path=path, pointer=pointer: closed_check_object(
                [], schema, path + ":" + pointer
            ),
            "Decode/object-mismatch",
            "object-container:" + path + ":" + pointer,
        )
        extra = dict(value)
        extra["__unknown_field__"] = None
        expect_failure(
            lambda extra=extra, schema=schema, path=path, pointer=pointer: closed_check_object(
                extra, schema, path + ":" + pointer
            ),
            "Decode/closed-field-mismatch",
            "object-extra:" + path + ":" + pointer,
        )
        for field, spec in schema.items():
            missing = dict(value)
            del missing[field]
            expect_failure(
                lambda missing=missing, schema=schema, path=path, pointer=pointer: closed_check_object(
                    missing, schema, path + ":" + pointer
                ),
                "Decode/closed-field-mismatch",
                "field-missing:" + path + ":" + pointer + ":" + field,
            )
            wrong = dict(value)
            wrong[field] = incompatible_schema_value(spec)
            expect_failure(
                lambda wrong=wrong, schema=schema, path=path, pointer=pointer: closed_check_object(
                    wrong, schema, path + ":" + pointer
                ),
                "Decode/hash-mismatch"
                if spec == "sha256"
                else "Decode/u32-mismatch"
                if spec == "u32"
                else "Decode/type-mismatch",
                "field-type:" + path + ":" + pointer + ":" + field,
            )

    for path, pointer, _tag in inventory["tags"]:
        parent_pointer, field = pointer.rsplit("/", 1)
        parent = resolve_pointer(documents[path], parent_pointer)
        schema = closed_object_schema(parent)
        wrong = dict(parent)
        wrong[field] = "UnknownUnionTagV1"
        expect_failure(
            lambda wrong=wrong, schema=schema, path=path, pointer=parent_pointer: closed_check_object(
                wrong, schema, path + ":" + (pointer or "/")
            ),
            "Decode/tag-mismatch",
            "tag-unknown:" + path + ":" + pointer,
        )
    for path, pointer, parent_context, field, enum_value in inventory["enums"]:
        parent_pointer, _field = pointer.rsplit("/", 1)
        occurrence = next(
            item
            for item in inventory["objects"]
            if item["path"] == path and item["pointer"] == parent_pointer
        )
        wrong = dict(occurrence["value"])
        wrong[field] = not enum_value if isinstance(enum_value, bool) else "UnknownEnumV1"
        expect_failure(
            lambda wrong=wrong, occurrence=occurrence: closed_check_object(
                wrong,
                occurrence["schema"],
                occurrence["path"] + ":" + (occurrence["pointer"] or "/"),
            ),
            "Decode/enum-mismatch",
            "enum-unknown:"
            + path
            + ":"
            + pointer
            + ":"
            + parent_context
            + ":"
            + field,
        )
    for path, pointer in inventory["u32s"]:
        parent_pointer, field = pointer.rsplit("/", 1)
        parent = resolve_pointer(documents[path], parent_pointer)
        schema = closed_object_schema(parent)
        for boundary in (True, -1, 1 << 32):
            wrong = dict(parent)
            wrong[field] = boundary
            expect_failure(
                lambda wrong=wrong, schema=schema, path=path, pointer=parent_pointer: closed_check_object(
                    wrong, schema, path + ":" + (pointer or "/")
                ),
                "Decode/u32-mismatch",
                "u32:" + path + ":" + pointer + ":" + repr(boundary),
            )
    for path, pointer in inventory["hashes"]:
        parent_pointer, field = pointer.rsplit("/", 1)
        parent = resolve_pointer(documents[path], parent_pointer)
        schema = closed_object_schema(parent)
        for replacement in (ZERO_HASH, "sha256:not-a-digest"):
            wrong = dict(parent)
            wrong[field] = replacement
            expect_failure(
                lambda wrong=wrong, schema=schema, path=path, pointer=parent_pointer: closed_check_object(
                    wrong, schema, path + ":" + (pointer or "/")
                ),
                "Decode/hash-mismatch",
                "hash:" + path + ":" + pointer,
            )

    for array_pointer in CANONICAL_ARRAY_POINTERS:
        path, pointer = array_pointer.split(":", 1)
        canonical = resolve_pointer(documents[path], "" if pointer == "/" else pointer)
        if not isinstance(canonical, list):
            fail("Decode/schema-array-policy-mismatch", array_pointer + " is not an array")
        canonical_keys = [canonical_bytes(item) for item in canonical]

        def check_array(candidate: Any) -> None:
            if not isinstance(candidate, list):
                fail("Decode/array-mismatch", array_pointer + " must be an array")
            if [canonical_bytes(item) for item in candidate] != canonical_keys:
                fail("Decode/array-canonicality-mismatch", array_pointer + " differs")

        check_array(canonical)
        # Empty total vectors still have a finite negative: injecting one
        # element.  Calling the policy class "remove" preserves the stable
        # descriptor vocabulary while ensuring the candidate differs.
        removed = canonical[:-1] if canonical else [None]
        duplicated = canonical + ([copy.deepcopy(canonical[0])] if canonical else [None])
        swapped = copy.deepcopy(canonical)
        if len(swapped) >= 2:
            swapped[0], swapped[1] = swapped[1], swapped[0]
        else:
            swapped.append(None)
        for label, candidate in (
            ("remove", removed),
            ("duplicate", duplicated),
            ("order", swapped),
        ):
            expect_failure(
                lambda candidate=candidate: check_array(candidate),
                "Decode/array-canonicality-mismatch",
                "array-" + label + ":" + array_pointer,
            )

    for edge_pointer, zero_diagnostic, malformed_diagnostic in HASH_GRAPH_POLICIES:
        path, pointer = edge_pointer.split(":", 1)
        for replacement, expected_diagnostic in (
            (ZERO_HASH, zero_diagnostic),
            ("sha256:not-a-digest", malformed_diagnostic),
        ):
            mutated_documents = dict(documents)
            mutated_documents[path] = apply_patch(
                documents[path],
                [{"op": "replace", "path": pointer, "value": replacement}],
            )
            expect_failure(
                lambda mutated_documents=mutated_documents: v1_validate_hash_graph(
                    mutated_documents
                ),
                expected_diagnostic,
                "hash-edge:" + edge_pointer,
            )

    for label, probe, expected in [
        ("non-nfc", "e\u0301", "manifest-noncanonical"),
        ("lone-surrogate", "\ud800", "Decode/unicode-scalar-mismatch"),
    ]:
        expect_failure(
            lambda probe=probe, label=label: walk_json({"probe": probe}, label),
            expected,
            "unicode:" + label,
        )
    return {
        "schema_pointer_count": len(descriptors),
        "schema_pointer_mutation_count": mutation_count,
        "schema_closed_object_count": len(inventory["objects"]),
        "schema_required_field_count": sum(
            len(item["schema"]) for item in inventory["objects"]
        ),
        "schema_array_policy_count": len(inventory["arrays"]),
        "schema_tag_occurrence_count": len(inventory["tags"]),
        "schema_enum_occurrence_count": len(inventory["enums"]),
        "schema_u32_pointer_count": len(inventory["u32s"]),
        "schema_hash_syntax_pointer_count": len(inventory["hashes"]),
        "schema_tag_variant_count": len(EXPECTED_CLOSED_KIND_VOCABULARY),
        "schema_enum_variant_count": sum(
            len(values) for _domain, values in EXPECTED_CLOSED_ENUM_DOMAINS
        ),
        "canonical_array_policy_count": len(CANONICAL_ARRAY_POINTERS),
        "hash_graph_edge_count": len(HASH_GRAPH_POLICIES),
    }


def schema_pointer_inventory(documents: Mapping[str, Any]) -> Dict[str, Any]:
    inventory = closed_schema_inventory(documents)
    descriptors = schema_pointer_descriptors(inventory)
    mutation_count = (
        sum(2 + 2 * len(item["schema"]) for item in inventory["objects"])
        + len(inventory["tags"])
        + len(inventory["enums"])
        + 3 * len(inventory["u32s"])
        + 2 * len(inventory["hashes"])
        + 3 * len(CANONICAL_ARRAY_POINTERS)
        + 2 * len(HASH_GRAPH_POLICIES)
        + 2
    )
    return {
        "pointer_count": len(descriptors),
        "pointer_set_hash": object_hash(descriptors),
        "mutation_count": mutation_count,
        "closed_object_count": len(inventory["objects"]),
        "required_field_count": sum(
            len(item["schema"]) for item in inventory["objects"]
        ),
        "array_policy_count": len(inventory["arrays"]),
        "tag_occurrence_count": len(inventory["tags"]),
        "enum_occurrence_count": len(inventory["enums"]),
        "u32_pointer_count": len(inventory["u32s"]),
        "hash_syntax_pointer_count": len(inventory["hashes"]),
        "tag_variant_count": len(EXPECTED_CLOSED_KIND_VOCABULARY),
        "enum_variant_count": sum(
            len(values) for _domain, values in EXPECTED_CLOSED_ENUM_DOMAINS
        ),
        "canonical_array_policy_count": len(CANONICAL_ARRAY_POINTERS),
        "hash_graph_edge_count": len(HASH_GRAPH_POLICIES),
    }

def pointer_parts(pointer: str) -> List[str]:
    if pointer == "":
        return []
    if not isinstance(pointer, str) or not pointer.startswith("/"):
        fail("mutation-corpus-invalid", "invalid JSON Pointer")
    return [part.replace("~1", "/").replace("~0", "~") for part in pointer[1:].split("/")]


def resolve_pointer(document: Any, pointer: str) -> Any:
    current = document
    for part in pointer_parts(pointer):
        if isinstance(current, list):
            if part == "-":
                fail("mutation-corpus-invalid", "'-' is not readable")
            index = int(part)
            current = current[index]
        elif isinstance(current, dict):
            current = current[part]
        else:
            fail("mutation-corpus-invalid", "pointer traverses a scalar")
    return current


def apply_patch(document: Any, operations: Sequence[Mapping[str, Any]]) -> Any:
    result = copy.deepcopy(document)
    for operation in operations:
        op = operation.get("op")
        path = operation.get("path")
        parts = pointer_parts(path)
        if not parts:
            fail("mutation-corpus-invalid", "root replacement is excluded")
        parent_pointer = "/" + "/".join(
            part.replace("~", "~0").replace("/", "~1") for part in parts[:-1]
        ) if len(parts) > 1 else ""
        parent = resolve_pointer(result, parent_pointer)
        leaf = parts[-1]
        try:
            if isinstance(parent, list):
                if op == "add" and leaf == "-":
                    parent.append(copy.deepcopy(operation["value"]))
                else:
                    index = int(leaf)
                    if op == "remove":
                        parent.pop(index)
                    elif op == "replace":
                        parent[index] = copy.deepcopy(operation["value"])
                    elif op == "add":
                        parent.insert(index, copy.deepcopy(operation["value"]))
                    else:
                        fail("mutation-corpus-invalid", "unsupported patch operation")
            elif isinstance(parent, dict):
                if op == "remove":
                    del parent[leaf]
                elif op in {"add", "replace"}:
                    if op == "replace" and leaf not in parent:
                        fail("mutation-corpus-invalid", "replace target is absent")
                    parent[leaf] = copy.deepcopy(operation["value"])
                else:
                    fail("mutation-corpus-invalid", "unsupported patch operation")
            else:
                fail("mutation-corpus-invalid", "patch parent is scalar")
        except (IndexError, KeyError, TypeError, ValueError) as error:
            fail("mutation-corpus-invalid", "patch failed: " + str(error))
    return result


def validate_preimage(document: Any, preimage: Mapping[str, Any]) -> None:
    target = resolve_pointer(document, preimage["path"])
    if "value" in preimage:
        if target != preimage["value"]:
            fail("mutation-corpus-invalid", "mutation preimage value differs")
        return
    kind = preimage.get("value_kind")
    if kind == "nonzero-sha256":
        if not isinstance(target, str) or not SHA256_RE.fullmatch(target) or target == ZERO_HASH:
            fail("mutation-corpus-invalid", "expected a nonzero hash preimage")
    elif kind == "explicit-row":
        validate_row(target, "mutation-corpus-invalid", "row preimage")
    elif kind == "two-structural-bindings":
        if not isinstance(target, list) or len(target) != 2:
            fail("mutation-corpus-invalid", "expected two structural bindings")
    elif kind == "postfix-derive-spelling":
        if not isinstance(target, str) or "} derive(" not in target:
            fail("mutation-corpus-invalid", "expected postfix derive")
    elif kind == "one-impl":
        if not isinstance(target, list) or len(target) != 1:
            fail("mutation-corpus-invalid", "expected one impl")
    else:
        fail("mutation-corpus-invalid", "unknown preimage kind")


def validate_mutated_artifact(path: str, value: Any) -> None:
    dispatch = {
        "interfaces/ability-declaration.json": (
            v1_validate_ability_declaration,
            "callable-interface-contract-mismatch",
        ),
        "interfaces/callable-interface.json": validate_callable,
        "interfaces/component-interface.json": validate_component,
        "interfaces/const-values.json": validate_const_values,
        "interfaces/elaboration-origin-map.json": validate_origin_map,
        "interfaces/intrinsic-registry.json": validate_registry,
        "interfaces/language-interface.json": validate_language,
        "interfaces/nominal-data.json": validate_nominal_data,
        "interfaces/primitive-catalog.json": validate_primitive_catalog,
        "interfaces/trait-impl-extension.json": validate_trait_impl_extension,
        "runtime/protocol-models.json": validate_runtime,
    }
    validator = dispatch.get(path)
    if validator is None:
        fail("mutation-corpus-invalid", "mutation target has no decoder")
    validator(value)


def validate_mutations(value: Any, documents: Mapping[str, Any]) -> Dict[str, int]:
    root = exact_keys(
        value,
        ["artifact", "cases", "positive_controls", "profile", "schema_version"],
        "mutation-corpus-invalid",
        "CireV1MutationCorpusV1",
    )
    validate_profile_header(root, "CireV1MutationCorpusV1", 1, "mutation-corpus-invalid")
    cases = require_list(root["cases"], "mutation-corpus-invalid", "mutation cases")
    controls = require_list(
        root["positive_controls"], "mutation-corpus-invalid", "positive controls"
    )
    case_ids = [item.get("id") for item in cases]
    control_ids = [item.get("id") for item in controls]
    if case_ids != sorted(case_ids) or len(case_ids) != len(set(case_ids)):
        fail("mutation-corpus-invalid", "mutation cases are not unique and sorted")
    if control_ids != sorted(control_ids) or len(control_ids) != len(set(control_ids)):
        fail("mutation-corpus-invalid", "positive controls are not unique and sorted")
    allowed_assertions = {
        "callable-module-is-package-qualified-and-contract-hash-is-nonzero",
        "manifest-selects-component-sync-v1-with-no-public-plan-or-commit",
        "semantic-string-and-bytes-payloads-are-exact",
        "all-derived-declarations-use-postfix-derive",
        "sealed-checkpoint-is-enabled-but-not-public-or-generic",
        "registry-has-exactly-21-first-party-and-2-structural-bindings",
        "all-protocol-expected-states-are-independently-replayed",
    }
    for control in controls:
        exact_keys(
            control,
            ["artifact_path", "assertion", "id", "rule_id"],
            "mutation-corpus-invalid",
            "positive control",
        )
        if control["artifact_path"] not in documents:
            fail("mutation-corpus-invalid", "positive control artifact is absent")
        if control["assertion"] not in allowed_assertions:
            fail("mutation-corpus-invalid", "unknown positive assertion")
    for case in cases:
        exact_keys(
            case,
            [
                "artifact_path",
                "expected_diagnostic",
                "id",
                "operations",
                "preimage",
                "rule_id",
            ],
            "mutation-corpus-invalid",
            "mutation case",
        )
        artifact_path = case["artifact_path"]
        if artifact_path not in documents:
            fail("mutation-corpus-invalid", "mutation target is absent")
        validate_preimage(documents[artifact_path], case["preimage"])
        operations = require_list(
            case["operations"], "mutation-corpus-invalid", "patch operations"
        )
        for operation in operations:
            fields = ["op", "path"]
            if operation.get("op") in {"add", "replace"}:
                fields.append("value")
            exact_keys(operation, fields, "mutation-corpus-invalid", "patch operation")
        mutated = apply_patch(documents[artifact_path], operations)
        if canonical_bytes(mutated) == canonical_bytes(documents[artifact_path]):
            fail("mutation-corpus-invalid", "mutation did not change the artifact")
        try:
            validate_mutated_artifact(artifact_path, mutated)
        except ValidationFailure as error:
            if error.diagnostic != case["expected_diagnostic"]:
                fail(
                    "mutation-corpus-invalid",
                    case["id"]
                    + " expected "
                    + case["expected_diagnostic"]
                    + " but observed "
                    + error.diagnostic,
                )
        except Exception as error:  # noqa: BLE001 - host exceptions are conformance failures
            fail(
                "mutation-corpus-invalid",
                case["id"] + " leaked host " + type(error).__name__ + ": " + str(error),
            )
        else:
            fail("mutation-corpus-invalid", case["id"] + " unexpectedly accepted")
    return {"positive_controls": len(controls), "reject_mutations": len(cases)}


def collect_diagnostic_references(value: Any) -> set[str]:
    result: set[str] = set()

    def visit(item: Any, key: str | None = None) -> None:
        if isinstance(item, dict):
            for child_key, child in item.items():
                if child_key in {"diagnostic", "expected_diagnostic"} and isinstance(child, str):
                    result.add(child)
                elif child_key == "diagnostics" and isinstance(child, list):
                    if all(isinstance(entry, str) for entry in child):
                        result.update(child)
                visit(child, child_key)
        elif isinstance(item, list):
            for child in item:
                visit(child, key)

    visit(value)
    return result




def load_documents() -> Dict[str, Any]:
    observed = {
        path.relative_to(V1).as_posix()
        for path in V1.rglob("*.json")
        if path.name != "manifest.json"
    }
    expected = set(ARTIFACT_FILES)
    if observed != expected:
        fail(
            "manifest-noncanonical",
            "v1 artifact set differs; missing="
            + repr(sorted(expected - observed))
            + " extra="
            + repr(sorted(observed - expected)),
        )
    documents = {path: load_json(V1 / path) for path in sorted(ARTIFACT_FILES)}
    for path, (artifact, schema) in ARTIFACT_FILES.items():
        document = documents[path]
        if not isinstance(document, dict):
            fail("manifest-noncanonical", path + " root must be an object")
        validate_profile_header(document, artifact, schema, "manifest-noncanonical")
        walk_json(document)
    return documents


# Successor-profile exact decoders.  The historical functions above remain the
# frozen TR0 implementation; these functions deliberately use distinct names
# so the two lanes cannot silently redefine one another.

EXPECTED_MODEL_HASHES: Dict[str, str] = {'diagnostics-v3.json': 'sha256:c78cf885086d9a2f53232133fba5a3345ba2479ee48be7262f267f64a14c13a0',
 'interfaces/call-assembly.json': 'sha256:b3140bb80ba8b0af4535bf51932bad0f331a5b8d05abfc0277e13d88c4774ce7',
 'interfaces/callable-contract-fact.json': 'sha256:61baaa570ab09eeb00b48046af92f4d4193b8c09d69996530b2c23d7afeceb4c',
 'interfaces/callable-interface.json': 'sha256:10120be19605708096660b3932b1da3807ed174c036b10dd3780490a04e8d180',
 'interfaces/canonicalization-cases.json': 'sha256:7c1065715c227b1628d614a110deb67e6c312ab99cb74fee3d334ed7c657b658',
 'interfaces/component-interface.json': 'sha256:29ff9fa0a65cdef23641cbb25ed473fe94b366e695ef518d9f27645c740e16f2',
 'interfaces/component-manifest.json': 'sha256:50f0b8e1990e3ece1a25b841955e50049aebeac6f8f7cdbd19c9163d80963dc4',
 'interfaces/const-values.json': 'sha256:fe75bf2dbeaf0016134621a63a9b80dad33f826b19e7b60d7faf5b064ad6acc6',
 'interfaces/control-mutation.json': 'sha256:51b5c6d238b3a1368fa0260ad97274ccc3554a8ec9bfd6bcc27a786a46dfc1a1',
 'interfaces/elaboration-origin-map.json': 'sha256:ac02a7fcf8a38a53eb4a145c21427143ff3787ed960082795602dceec01b41d7',
 'interfaces/first-party-registry.json': 'sha256:53ef84a795e822bf75e3d75a8d9ab7ae6d34e341a7d2c9e66f4f7b5b49e13b11',
 'interfaces/function-contract-v3-suite.json': 'sha256:a5bc1326c170b43729cfd219607033e8f85ae1881be4ba1e86e3484a761efc4b',
 'interfaces/function-contract-v3.json': 'sha256:d1196fc0099cbd4b60fe178571c46cb06d9ea7549a4771d4ffba0bc074d27cd5',
 'interfaces/intrinsic-registry.json': 'sha256:0517bc97b9964b475c7c2d2df2b8ec78c9e9d7ad1dc94c145267797418b694f1',
 'interfaces/language-interface.json': 'sha256:aaaf25bd4aa7e4e4134941d54a8751973d854a85811c2cb5a50463f8039bcdc6',
 'interfaces/link-abi.json': 'sha256:1e6b07cc87276e119894f4acf11949c74933beb415599157131aea8c0365f9ed',
 'interfaces/local-inference.json': 'sha256:4c06bcdf91939323cbedd697d84079b601938ce019fb966fb357f4c7617f9cc8',
 'interfaces/nominal-data.json': 'sha256:7fdabd2f9a4eb82ace21189e72fb2d119fb38ee0fc4a62a3b654bf54d400ac32',
 'interfaces/numeric-semantics.json': 'sha256:74e613ddfa5bb61ebfd2fbb8f6b47fc364d69dc90c463f1e31f9bf1e50585f1f',
 'interfaces/primitive-catalog.json': 'sha256:3148fee559f220f7de6fa74f98a15d26202dbab7104ee1c6811a0e04184b5935',
 'interfaces/structural-intrinsic-registry.json': 'sha256:67f0d93f2478a32964a0b48bd2a26571e530d31ad6f8afa2cd6ecec667fb44df',
 'interfaces/trait-impl-extension.json': 'sha256:2cceb002b290d92b26925b23804ea90ba0d7b97ca53d1f1fc2caa6aa37cb4ab9',
 'runtime/protocol-models.json': 'sha256:33b7741848b00c62b0cf27e9cb910ac69a99f1bec9f69125f990068f6f640376'}

FIRST_PARTY_TAG_FIELDS = {'ActionPlanContractV1': ('callback',
                          'event_parameter_index',
                          'event_type',
                          'generation',
                          'kind',
                          'occurrence_policy',
                          'revision',
                          'storage_owner'),
 'AdmittedUiGenerationV1': ('kind', 'owner'),
 'AnonymousAsyncRowV1': ('kind',),
 'AssociatedFunctionV1': ('kind', 'member', 'receiver'),
 'AssociatedProjectionV1': ('kind', 'member', 'receiver', 'surface_member'),
 'AsyncMaySuspendV1': ('kind',),
 'BinderTypeTemplateV1': ('binder', 'kind'),
 'BindingCallbackRefV1': ('callback_name', 'kind'),
 'BuiltinTypeTemplateV1': ('kind', 'name'),
 'CallableCallbackRefV1': ('callback_name', 'kind'),
 'CallbackOnlyV1': ('callback_name', 'kind'),
 'CanonicalFirstPartyLiteralPathsV1': ('capture_policy',
                                       'demand_policy',
                                       'kind',
                                       'obligation_policy',
                                       'origin_policy',
                                       'result_policy',
                                       'site_policy',
                                       'usage_policy'),
 'ChildOwnerRegionV1': ('kind', 'parent', 'relation'),
 'ClockPackageSummaryV1': ('identity', 'kind', 'payload'),
 'ClosedLiteralV1': ('kind', 'nominal', 'variant'),
 'ContextualCallbackRefV1': ('callback_name', 'kind'),
 'DerivedCurrentOwnerBinderV1': ('binder_kind', 'derivation', 'fresh_slot', 'kind', 'visibility'),
 'DirectAndCallbackPrivateV1': ('callback_name', 'kind'),
 'EmptyRowV1': ('kind',),
 'EvidenceTypeRefV1': ('kind', 'type'),
 'ExactCallbackEntryOwnerV1': ('kind', 'owner'),
 'FirstPartyBindingV1': ('callbacks',
                         'direct',
                         'evidence',
                         'fresh',
                         'id',
                         'kernel',
                         'kind',
                         'slots',
                         'source',
                         'types'),
 'FirstPartyCallbackSchemeV1': ('captured_fresh_slots',
                                'entry_owner',
                                'generated_fresh_slots',
                                'kind',
                                'trigger'),
 'FirstPartyCallbackV1': ('acquisition',
                          'contract',
                          'kind',
                          'name',
                          'parameter_slot',
                          'scheme',
                          'type'),
 'FirstPartyContractTemplateV1': ('construction',
                                  'flow',
                                  'kind',
                                  'phase',
                                  'row',
                                  'suspension',
                                  'temporal',
                                  'world'),
 'FrameClockIdentityV1': ('kind', 'owner'),
 'FreshBinderRefV1': ('fresh_slot', 'kind'),
 'FunctionTypeTemplateV1': ('kind', 'parameters', 'result'),
 'GenerativeFreshBinderV1': ('binder_kind',
                             'cardinality',
                             'fresh_slot',
                             'kind',
                             'origin',
                             'visibility'),
 'GenericBinderRefV1': ('binder_slot', 'kind'),
 'HostObservableV1': ('kind',),
 'ImplicitReceiverSlotV1': ('kind', 'passing', 'slot', 'type'),
 'InstalledTrackEpochV1': ('kind',),
 'IntrinsicModuleFunctionV1': ('kind', 'member', 'module'),
 'KindBinderV1': ('binder_kind', 'binder_slot', 'kind'),
 'NamedOrPositionalSlotV1': ('defaultable', 'kind', 'passing', 'public_label', 'slot', 'type'),
 'NoCallbackEntryOwnerV1': ('kind',),
 'NoSuspendV1': ('kind',),
 'NominalTypeTemplateV1': ('arguments', 'kind', 'module', 'name'),
 'OpenedPackedNextBinderV1': ('binder_kind',
                              'component',
                              'fresh_slot',
                              'kind',
                              'packed_parameter_slot',
                              'visibility'),
 'OperationCallV1': ('family', 'kind', 'operation'),
 'PackedNextDisposeV1': ('kind',),
 'PackedNextOpenV1': ('kind',),
 'PackedNextPackV1': ('kind',),
 'ParameterSlotRefV1': ('kind', 'slot'),
 'ProofRuleEvidenceV1': ('arguments', 'kind', 'rule'),
 'PureV1': ('kind',),
 'ResourceDisposeV1': ('kind',),
 'ResourceLoaderContractV1': ('callback',
                              'error_type',
                              'generation_owner',
                              'key_type',
                              'kind',
                              'storage_owner',
                              'value_type'),
 'ResourceSwitchLatestV1': ('kind',),
 'ResourceViewV1': ('kind',),
 'ReturnsOnlyV1': ('kind', 'result'),
 'SameWorldV1': ('kind',),
 'SignalMapV1': ('kind',),
 'SignalTailContractEvidenceV1': ('callback', 'clock', 'input_type', 'kind', 'output_type'),
 'SignalTrackV1': ('kind',),
 'SnapshotReadLiveV1': ('kind',),
 'SnapshotReadSourceV1': ('kind',),
 'TaskCancelV1': ('kind',),
 'TrackReadLiveV1': ('kind',),
 'TrackReadSourceV1': ('kind',),
 'TypeRefV1': ('kind', 'type'),
 'UiBackpressureCoalesceLatestV1': ('kind',),
 'UiBuilderOwnerV1': ('kind',),
 'UiCandidateActionV1': ('kind',),
 'UiMountDisposeV1': ('kind',),
 'UiRenderV1': ('kind',),
 'UiRevisionOfV1': ('generation', 'kind'),
 'UiRevisionScopeBinderV1': ('binder_slot', 'generation', 'kind'),
 'UiRunSignalV1': ('kind',),
 'UnqualifiedFunctionV1': ('kind', 'name')}

FIRST_PARTY_SOURCES = [{'kind': 'AssociatedFunctionV1', 'member': 'await', 'receiver': 'CloseReceipt'},
 {'kind': 'AssociatedFunctionV1', 'member': 'await', 'receiver': 'Async'},
 {'kind': 'AssociatedFunctionV1', 'member': 'dispose', 'receiver': 'Resource'},
 {'kind': 'AssociatedFunctionV1', 'member': 'switch_latest', 'receiver': 'Resource'},
 {'kind': 'AssociatedFunctionV1', 'member': 'view', 'receiver': 'Resource'},
 {'kind': 'UnqualifiedFunctionV1', 'name': 'map_signal'},
 {'kind': 'AssociatedFunctionV1', 'member': 'track', 'receiver': 'Signal'},
 {'kind': 'AssociatedFunctionV1', 'member': 'read', 'receiver': 'SnapshotContext'},
 {'kind': 'AssociatedFunctionV1', 'member': 'read', 'receiver': 'SnapshotContext'},
 {'kind': 'AssociatedFunctionV1', 'member': 'cancel', 'receiver': 'Task'},
 {'kind': 'IntrinsicModuleFunctionV1', 'member': 'pack_next', 'module': 'temporal'},
 {'kind': 'IntrinsicModuleFunctionV1', 'member': 'dispose', 'module': 'temporal'},
 {'kind': 'IntrinsicModuleFunctionV1', 'member': 'try_with_packed_next', 'module': 'temporal'},
 {'kind': 'AssociatedFunctionV1', 'member': 'read', 'receiver': 'TrackContext'},
 {'kind': 'AssociatedFunctionV1', 'member': 'read', 'receiver': 'TrackContext'},
 {'kind': 'AssociatedProjectionV1', 'member': 'owner', 'receiver': 'UiBuilder', 'surface_member': 'owner'},
 {'kind': 'AssociatedFunctionV1', 'member': 'action', 'receiver': 'UiCandidate'},
 {'kind': 'ClosedLiteralV1', 'nominal': 'UiBackpressureV1', 'variant': 'CoalesceLatest'},
 {'kind': 'AssociatedFunctionV1', 'member': 'dispose', 'receiver': 'UiMount'},
 {'kind': 'AssociatedFunctionV1', 'member': 'render', 'receiver': 'UiBuilder'},
 {'kind': 'IntrinsicModuleFunctionV1', 'member': 'run_signal', 'module': 'ui'}]



def v1_closed(value: Any, fields: Iterable[str], context: str) -> Mapping[str, Any]:
    return exact_keys(value, fields, "Decode/closed-field-mismatch", context)


def v1_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value or unicodedata.normalize("NFC", value) != value:
        fail("Decode/string-mismatch", context + " must be a nonempty NFC string")
    return value


def v1_u32(value: Any, context: str) -> int:
    result = require_int(value, "Decode/integer-mismatch", context)
    if result < 0 or result > 0xFFFFFFFF:
        fail("Decode/integer-mismatch", context + " is outside u32")
    return result


def v1_package_instance(value: Any, context: str) -> None:
    item = v1_closed(value, ["kind", "digest"], context)
    if item["kind"] != "PackageInstanceIdV1" or item["digest"] != PACKAGE_DIGEST:
        fail("package-instance-hash-mismatch", context + " differs")


def v1_module(value: Any, context: str) -> None:
    parts = require_list(value, "Decode/array-mismatch", context)
    if len(parts) < 2 or parts[0] != PACKAGE_MODULE:
        fail("package-instance-hash-mismatch", context + " is not package-qualified")
    for index, part in enumerate(parts):
        v1_string(part, context + "/" + str(index))


def v1_hash_ref(value: Any, artifact: str, diagnostic: str) -> None:
    item = v1_closed(value, ["artifact", "hash_algorithm", "artifact_hash"], artifact + " ref")
    if item["artifact"] != artifact or item["hash_algorithm"] != HASH_ALGORITHM:
        fail(diagnostic, artifact + " reference metadata differs")
    if not isinstance(item["artifact_hash"], str) or not SHA256_RE.fullmatch(item["artifact_hash"]):
        fail("Decode/hash-mismatch", artifact + " hash is malformed")
    if item["artifact_hash"] == ZERO_HASH:
        fail(diagnostic, artifact + " hash is the zero placeholder")


def v1_declaration_identity(value: Any, context: str) -> tuple[str, str, str]:
    item = v1_closed(value, ["package", "namespace", "module", "path"], context)
    v1_package_instance(item["package"], context + ".package")
    if item["namespace"] not in {
        "TypeV1", "ValueV1", "TraitV1", "EffectV1", "AbilityV1"
    }:
        fail("Decode/enum-mismatch", context + " has an unknown namespace")
    v1_module(item["module"], context + ".module")
    path = require_list(item["path"], "Decode/array-mismatch", context + ".path")
    if not path:
        fail("Decode/array-mismatch", context + " path is empty")
    for segment in path:
        v1_string(segment, context + ".path")
    return item["namespace"], "/".join(item["module"]), "/".join(path)


def v1_declaration_identity_value(
    namespace: str, path: str
) -> Dict[str, Any]:
    return {
        "package": copy.deepcopy(PACKAGE_ID),
        "namespace": namespace,
        # Surface has no module declaration or file-to-module convention.
        # Every ordinary source declaration therefore lives in the one
        # canonical source module for this package.
        "module": [PACKAGE_MODULE, "root"],
        "path": [path],
    }


TRAIT_IDENTITY = v1_declaration_identity_value("TraitV1", "Comparable")
DATA_IDENTITY = v1_declaration_identity_value("TypeV1", "Status")
ABILITY_IDENTITY = v1_declaration_identity_value("AbilityV1", "Reactive")
EFFECT_IDENTITY = v1_declaration_identity_value("EffectV1", "FrameClock")
CONST_IDENTITY = v1_declaration_identity_value("ValueV1", "Answer")
CALLABLE_SOURCE_IDENTITY = v1_declaration_identity_value("ValueV1", "identity")


def v1_evidence_identity_value(kind: str, ordinal: int) -> Dict[str, Any]:
    return {
        "package": copy.deepcopy(PACKAGE_ID),
        "kind": kind,
        "ordinal": ordinal,
    }


def v1_legacy_builtin(name: str) -> Dict[str, Any]:
    return {
        "kind": "LegacyTypeRefV2",
        "value": {"kind": "BuiltinTypeV1", "name": name},
    }


def v1_type_parameter(slot: int) -> Dict[str, Any]:
    return {"kind": "TypeParameterV2", "slot": slot}


def v1_empty_row() -> Dict[str, str]:
    return {"kind": "EmptyV1"}


def v1_empty_binders(
    *,
    parameter_binders: Sequence[Mapping[str, Any]] = (),
    type_binders: Sequence[Mapping[str, Any]] = (),
    row_binders: Sequence[Mapping[str, Any]] = (),
    contract_binders: Sequence[Mapping[str, Any]] = (),
) -> Dict[str, Any]:
    return {
        "parameter_binders": copy.deepcopy(list(parameter_binders)),
        "type_binders": copy.deepcopy(list(type_binders)),
        "row_binders": copy.deepcopy(list(row_binders)),
        "contract_binders": copy.deepcopy(list(contract_binders)),
        "owner_binders": [],
        "clock_binders": [],
        "identity_binders": [],
        "prompt_binders": [],
    }


def v1_empty_requirements() -> Dict[str, List[Any]]:
    return {"ordinary_traits": [], "effect_parameters": []}


def v1_comparable_requirement(
    *, binder_slot: int, associated_slot: int
) -> Dict[str, Any]:
    return {
        "requirement_ordinal": 0,
        "origin": {"kind": "SourceTraitRequirementV1"},
        "binder_slot": binder_slot,
        "trait": copy.deepcopy(TRAIT_IDENTITY),
        "arguments": [],
        "associated_types": [
            {
                "item_ordinal": 0,
                "declaration_name": "Output",
                "binder_slot": associated_slot,
                "equality": None,
            }
        ],
    }


def v1_generic_requirements(
    *, binder_slot: int, associated_slot: int
) -> Dict[str, Any]:
    return {
        "ordinary_traits": [
            v1_comparable_requirement(
                binder_slot=binder_slot,
                associated_slot=associated_slot,
            )
        ],
        "effect_parameters": [],
    }


def v1_surface_signature(parameter_count: int) -> Dict[str, Any]:
    return {
        "kind": "CallableSurfaceSignatureV1",
        "slots": [
            {
                "slot": slot,
                "passing": "NamedOrPositionalV1",
                "public_label": "value" if slot == 0 else "value" + str(slot),
                "defaultable": False,
            }
            for slot in range(parameter_count)
        ],
    }


def v1_operation_signature(
    *, type_binders: Sequence[Mapping[str, Any]], parameter: Any, result: Any
) -> Dict[str, Any]:
    return {
        "type_binders": copy.deepcopy(list(type_binders)),
        "parameters": [copy.deepcopy(parameter)],
        "result": copy.deepcopy(result),
        "mode": "fun",
        "transition": {"kind": "SameWorldV1"},
        "suspension": {"atoms": [], "grade": "NoSuspend"},
        "result_transformer": {
            "kind": "ParametricResultV1",
            "provenance": {"kind": "StableV1"},
            "capture": {"kind": "NoCaptureV1"},
        },
        "required_phase": {
            "allowed_phases": ["Pure", "Compute", "Action", "Commit"],
            "required_authorities": [],
            "current_owner": None,
        },
        "obligation_ids": [],
        "secondary_sites": {"kind": "Closed", "sites": []},
    }


def v1_artifact_ref(artifact: str, artifact_hash: str) -> Dict[str, str]:
    return {
        "artifact": artifact,
        "hash_algorithm": HASH_ALGORITHM,
        "artifact_hash": artifact_hash,
    }


def v1_nominal_type(
    identity: Mapping[str, Any], arguments: Sequence[Mapping[str, Any]] = ()
) -> Dict[str, Any]:
    return {
        "kind": "NominalTypeV2",
        "module": copy.deepcopy(identity["module"]),
        "name": identity["path"][-1],
        "arguments": copy.deepcopy(list(arguments)),
    }


def v1_signed_int_const(width: int, value: int) -> Dict[str, Any]:
    byte_width = width // 8
    encoded = value.to_bytes(byte_width, "big", signed=True)
    return {
        "kind": "ScalarConstV1",
        "scalar": {
            "kind": "SignedIntConstV1",
            "width": width,
            "twos_complement_be": list(encoded),
        },
    }


def v1_type_builtin_name(value: Any) -> str | None:
    if not isinstance(value, dict):
        return None
    if value.get("kind") == "LegacyTypeRefV2":
        legacy = value.get("value")
        if isinstance(legacy, dict) and legacy.get("kind") == "BuiltinTypeV1":
            return legacy.get("name") if isinstance(legacy.get("name"), str) else None
    if value.get("kind") == "NominalTypeV2":
        name = value.get("name")
        return name if isinstance(name, str) else None
    return None


def v1_type_application(value: Any) -> tuple[str, List[Any]] | None:
    if not isinstance(value, dict) or value.get("kind") != "ApplyTypeV2":
        return None
    constructor = value.get("constructor")
    arguments = value.get("arguments")
    if (
        not isinstance(constructor, dict)
        or constructor.get("kind") != "BuiltinConstructorV1"
        or not isinstance(constructor.get("name"), str)
        or not isinstance(arguments, list)
    ):
        return None
    return constructor["name"], arguments


def v1_const_octets(value: Any, length: int | None, context: str) -> List[int]:
    octets = require_list(value, "Decode/array-mismatch", context)
    if length is not None and len(octets) != length:
        fail("const-operation-not-safe", context + " has the wrong byte width")
    result: List[int] = []
    for index, octet in enumerate(octets):
        parsed = require_int(octet, "const-operation-not-safe", context)
        if parsed not in range(256):
            fail("const-operation-not-safe", context + " contains a non-u8 value")
        result.append(parsed)
    return result


def v1_validate_const_value(
    value: Any, expected_type: Any, binder_table: Mapping[int, Mapping[str, Any]], context: str
) -> None:
    """Exact, expected-type-directed ConstValueV1 judgment for this package model."""

    if not isinstance(value, dict):
        fail("Decode/object-mismatch", context + " const value is not an object")
    kind = value.get("kind")
    builtin = v1_type_builtin_name(expected_type)
    if kind == "ScalarConstV1":
        item = v1_closed(value, ["kind", "scalar"], "ScalarConstV1")
        scalar_value = item["scalar"]
        if not isinstance(scalar_value, dict):
            fail("Decode/object-mismatch", context + " scalar is not an object")
        scalar_kind = scalar_value.get("kind")
        if scalar_kind == "UnitConstV1":
            v1_closed(scalar_value, ["kind"], "UnitConstV1")
            if builtin != "Unit":
                fail("const-operation-not-safe", context + " Unit payload type differs")
        elif scalar_kind == "BoolConstV1":
            scalar = v1_closed(scalar_value, ["kind", "value"], "BoolConstV1")
            if not isinstance(scalar["value"], bool) or builtin != "Bool":
                fail("const-operation-not-safe", context + " Bool payload type differs")
        elif scalar_kind == "SignedIntConstV1":
            scalar = v1_closed(
                scalar_value,
                ["kind", "width", "twos_complement_be"],
                "SignedIntConstV1",
            )
            width = require_int(scalar["width"], "const-operation-not-safe", context)
            expected_width = {"Int8": 8, "Int16": 16, "Int": 32, "Int64": 64}.get(builtin)
            if width not in {8, 16, 32, 64} or expected_width != width:
                fail("const-operation-not-safe", context + " signed integer width/type differs")
            v1_const_octets(scalar["twos_complement_be"], width // 8, context)
        elif scalar_kind == "UnsignedIntConstV1":
            scalar = v1_closed(
                scalar_value,
                ["kind", "width", "magnitude_be"],
                "UnsignedIntConstV1",
            )
            width = require_int(scalar["width"], "const-operation-not-safe", context)
            expected_width = {"UInt8": 8, "UInt16": 16, "UInt": 32, "UInt64": 64}.get(builtin)
            if width not in {8, 16, 32, 64} or expected_width != width:
                fail("const-operation-not-safe", context + " unsigned integer width/type differs")
            v1_const_octets(scalar["magnitude_be"], width // 8, context)
        elif scalar_kind == "FloatBitsConstV1":
            scalar = v1_closed(
                scalar_value,
                ["kind", "width", "ieee_be"],
                "FloatBitsConstV1",
            )
            width = require_int(scalar["width"], "const-operation-not-safe", context)
            expected_width = {"Float32": 32, "Float": 64}.get(builtin)
            if width not in {32, 64} or expected_width != width:
                fail("const-operation-not-safe", context + " float width/type differs")
            octets = v1_const_octets(scalar["ieee_be"], width // 8, context)
            bits = int.from_bytes(bytes(octets), "big")
            exponent_bits = 8 if width == 32 else 11
            fraction_bits = 23 if width == 32 else 52
            exponent = (bits >> fraction_bits) & ((1 << exponent_bits) - 1)
            fraction = bits & ((1 << fraction_bits) - 1)
            if exponent == (1 << exponent_bits) - 1 and fraction:
                canonical_nan = 0x7FC00000 if width == 32 else 0x7FF8000000000000
                if bits != canonical_nan:
                    fail("const-operation-not-safe", context + " NaN is not canonical")
        elif scalar_kind == "CharConstV1":
            scalar = v1_closed(
                scalar_value, ["kind", "unicode_scalar"], "CharConstV1"
            )
            codepoint = v1_u32(scalar["unicode_scalar"], context + " Char scalar")
            if builtin != "Char" or codepoint > 0x10FFFF or 0xD800 <= codepoint <= 0xDFFF:
                fail("const-operation-not-safe", context + " Char payload is not a Unicode scalar")
        elif scalar_kind == "StringConstV1":
            scalar = v1_closed(scalar_value, ["kind", "utf8"], "StringConstV1")
            octets = v1_const_octets(scalar["utf8"], None, context)
            if builtin != "String":
                fail("const-operation-not-safe", context + " String payload type differs")
            try:
                bytes(octets).decode("utf-8")
            except UnicodeDecodeError:
                fail("const-operation-not-safe", context + " String bytes are not canonical UTF-8")
        elif scalar_kind == "BytesConstV1":
            scalar = v1_closed(scalar_value, ["kind", "octets"], "BytesConstV1")
            v1_const_octets(scalar["octets"], None, context)
            if builtin != "Bytes":
                fail("const-operation-not-safe", context + " Bytes payload type differs")
        else:
            fail("Decode/tag-mismatch", context + " has an unknown ConstScalarV1 tag")
        return
    if kind in {"TupleConstV1", "ArrayConstV1"}:
        item = v1_closed(value, ["kind", "elements"], kind)
        application = v1_type_application(expected_type)
        expected_constructor = "Tuple" if kind == "TupleConstV1" else "Array"
        if application is None or application[0] != expected_constructor:
            fail("const-operation-not-safe", context + " aggregate expected type differs")
        elements = require_list(item["elements"], "Decode/array-mismatch", context)
        child_types = application[1]
        if kind == "ArrayConstV1":
            child_types = [child_types[0]] * len(elements) if len(child_types) == 1 else []
        if len(elements) != len(child_types):
            fail("const-operation-not-safe", context + " aggregate arity differs")
        for index, (element, child_type) in enumerate(zip(elements, child_types)):
            v1_validate_const_value(element, child_type, binder_table, context + "/" + str(index))
        return
    if kind == "BuiltinVariantConstV1":
        item = v1_closed(
            value,
            ["kind", "constructor", "variant", "fields"],
            "BuiltinVariantConstV1",
        )
        application = v1_type_application(expected_type)
        fields = require_list(item["fields"], "Decode/array-mismatch", context + " fields")
        variants = {
            ("OptionV1", "NoneV1"): [],
            ("OptionV1", "SomeV1"): [0],
            ("ResultV1", "OkV1"): [0],
            ("ResultV1", "ErrV1"): [1],
        }
        indexes = variants.get((item["constructor"], item["variant"]))
        expected_constructor = {
            "OptionV1": "Option",
            "ResultV1": "Result",
        }.get(item["constructor"])
        if (
            application is None
            or application[0] != expected_constructor
            or indexes is None
            or len(fields) != len(indexes)
        ):
            fail("const-operation-not-safe", context + " builtin variant shape/type differs")
        for field_value, argument_index in zip(fields, indexes):
            v1_validate_const_value(
                field_value,
                application[1][argument_index],
                binder_table,
                context + " builtin field",
            )
        return
    if kind == "NominalConstV1":
        item = v1_closed(
            value,
            ["kind", "declaration", "variant_ordinal", "fields"],
            "NominalConstV1",
        )
        if expected_type.get("kind") != "NominalTypeV2" or item["declaration"] != DATA_IDENTITY:
            fail("const-operation-not-safe", context + " nominal declaration/type differs")
        if expected_type.get("name") != DATA_IDENTITY["path"][-1]:
            fail("const-operation-not-safe", context + " nominal expected identity differs")
        ordinal = item["variant_ordinal"]
        if ordinal is not None:
            v1_u32(ordinal, context + " variant ordinal")
        fields = require_list(item["fields"], "Decode/array-mismatch", context + " nominal fields")
        previous = -1
        for field_value in fields:
            field = v1_closed(field_value, ["ordinal", "value"], "ConstFieldValueV1")
            field_ordinal = v1_u32(field["ordinal"], context + " field ordinal")
            if field_ordinal <= previous:
                fail("const-operation-not-safe", context + " nominal fields are not canonical")
            previous = field_ordinal
        return
    fail("Decode/tag-mismatch", context + " has an unknown ConstValueV1 tag")


def build_const_declaration() -> Dict[str, Any]:
    return {
        "artifact": "ConstDeclarationV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": copy.deepcopy(CONST_IDENTITY),
        "visibility": "PublicV1",
        "type": v1_legacy_builtin("Int"),
        "value": v1_signed_int_const(32, 42),
        "evaluator": "CireConstEvaluatorV1",
    }


def build_trait_declaration() -> Dict[str, Any]:
    """Build the package trait root.

    The method vector is intentionally empty until the authority's generic
    trait-method scheme delta lands.  The associated type is nevertheless a
    real hidden-binder witness, so ordinary requirement lowering cannot be
    reconstructed from source spelling.
    """

    return {
        "artifact": "TraitDeclarationV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": copy.deepcopy(TRAIT_IDENTITY),
        "visibility": "PublicOpenV1",
        "binders": v1_empty_binders(
            type_binders=[
                {"kind": "Type", "slot": 0},
                {"kind": "Type", "slot": 1},
            ]
        ),
        "self_binder_slot": 0,
        "requirements": v1_empty_requirements(),
        "associated_types": [
            {
                "ordinal": 0,
                "name": "Output",
                "binder_slot": 1,
                "constraints": [],
                "default_type": v1_legacy_builtin("Int"),
            }
        ],
        "methods": [],
    }


def build_data_declaration() -> Dict[str, Any]:
    return {
        "artifact": "DataDeclarationV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": copy.deepcopy(DATA_IDENTITY),
        "visibility": "PublicV1",
        "binders": v1_empty_binders(),
        "requirements": v1_empty_requirements(),
        "body": {
            "kind": "EnumV1",
            "variants": [
                {
                    "ordinal": 0,
                    "name": "Present",
                    "payload": {
                        "kind": "RecordVariantV1",
                        "fields": [
                            {
                                "ordinal": 0,
                                "name": "value",
                                "visibility": "PublicV1",
                                "type": v1_legacy_builtin("Int"),
                                "default_value": None,
                            },
                            {
                                "ordinal": 1,
                                "name": "fallback",
                                "visibility": "PublicV1",
                                "type": v1_legacy_builtin("Int"),
                                # Stored defaults carry the already-evaluated
                                # semantic value inline.  They are not edges to
                                # an otherwise unrelated const declaration.
                                "default_value": v1_signed_int_const(32, 42),
                            },
                            {
                                "ordinal": 2,
                                "name": "optional",
                                "visibility": "PublicV1",
                                "type": v1_builtin_application(
                                    "Option", [v1_legacy_builtin("Int")]
                                ),
                                "default_value": {
                                    "kind": "BuiltinVariantConstV1",
                                    "constructor": "OptionV1",
                                    "variant": "NoneV1",
                                    "fields": [],
                                },
                            },
                        ],
                    },
                },
                {
                    "ordinal": 1,
                    "name": "Absent",
                    "payload": {"kind": "UnitVariantV1"},
                },
            ],
        },
        "derives": [],
    }


def build_ability_declaration() -> Dict[str, Any]:
    type_binders = [
        {"kind": "Type", "slot": 0},
        {"kind": "Type", "slot": 1},
        {"kind": "Type", "slot": 2},
    ]
    return {
        "artifact": "AbilityDeclarationV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": copy.deepcopy(ABILITY_IDENTITY),
        "visibility": "PublicOpenV1",
        "binders": v1_empty_binders(type_binders=type_binders),
        "requirements": v1_generic_requirements(
            binder_slot=0, associated_slot=2
        ),
        "associated_items": [
            {
                "kind": "AbilityAssociatedTypeV1",
                "ordinal": 0,
                "name": "Response",
                "binder_slot": 1,
                "default_type": v1_legacy_builtin("Int"),
            }
        ],
        "operations": [
            {
                "ordinal": 0,
                "name": "observe",
                "binders": v1_empty_binders(type_binders=type_binders),
                "requirements": v1_empty_requirements(),
                "surface_signature": v1_surface_signature(1),
                "signature": v1_operation_signature(
                    type_binders=type_binders,
                    parameter=v1_type_parameter(0),
                    result=v1_type_parameter(1),
                ),
            }
        ],
    }


def v1_effect_parameter_requirement() -> Dict[str, Any]:
    return {
        "binder_slot": 0,
        "constructor_arity": 1,
        # Higher-kinded F[_] retains its constructor arity in TypeBinderV3;
        # ability constraints are deliberately excluded from this profile.
        "abilities": [],
    }


def v1_effect_parameter_application(argument: Mapping[str, Any]) -> Dict[str, Any]:
    return {
        "kind": "ApplyTypeV2",
        "constructor": {
            "kind": "EffectParameterConstructorV3",
            "binder_slot": 0,
            "constructor_arity": 1,
        },
        "arguments": [copy.deepcopy(argument)],
    }


def v1_builtin_application(
    name: str, arguments: Sequence[Mapping[str, Any]]
) -> Dict[str, Any]:
    return {
        "kind": "ApplyTypeV2",
        "constructor": {"kind": "BuiltinConstructorV1", "name": name},
        "arguments": copy.deepcopy(list(arguments)),
    }


def build_effect_declaration() -> Dict[str, Any]:
    type_binders = [
        {
            "kind": "EffectConstructorV3",
            "slot": 0,
            "constructor_arity": 1,
        },
    ]
    requirements = {
        "ordinary_traits": [],
        "effect_parameters": [v1_effect_parameter_requirement()],
    }
    return {
        "artifact": "EffectDeclarationV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": copy.deepcopy(EFFECT_IDENTITY),
        "visibility": "PublicOpenV1",
        "binders": v1_empty_binders(type_binders=type_binders),
        "requirements": requirements,
        "conformances": [
            {
                "ability": copy.deepcopy(ABILITY_IDENTITY),
                "arguments": [v1_legacy_builtin("Int")],
                "associated_arguments": [
                    {
                        "item_ordinal": 0,
                        "declaration_name": "Response",
                        "value": {
                            "kind": "TypeAssociatedArgumentV1",
                            "value": v1_legacy_builtin("Int"),
                        },
                    }
                ],
            }
        ],
        "declared_operations": [
            {
                "ordinal": 0,
                "name": "observe",
                "binders": v1_empty_binders(type_binders=type_binders),
                "requirements": v1_empty_requirements(),
                "surface_signature": v1_surface_signature(1),
                "signature": v1_operation_signature(
                    type_binders=type_binders,
                    parameter=v1_legacy_builtin("Int"),
                    result=v1_legacy_builtin("Int"),
                ),
            },
            {
                "ordinal": 1,
                "name": "wrap",
                "binders": v1_empty_binders(type_binders=type_binders),
                "requirements": v1_empty_requirements(),
                "surface_signature": v1_surface_signature(1),
                "signature": v1_operation_signature(
                    type_binders=type_binders,
                    parameter=v1_effect_parameter_application(
                        v1_legacy_builtin("Int")
                    ),
                    result=v1_legacy_builtin("Unit"),
                ),
            },
        ],
    }


def v1_package_callable_edge() -> Dict[str, Any]:
    callable_interface = load_json(V1 / "interfaces/callable-interface.json")
    return {
        "module": [PACKAGE_MODULE, "root"],
        "export_path": ["identity"],
        "callable_interface": v1_artifact_ref(
            "CallableInterfaceV1", object_hash(callable_interface)
        ),
    }


def build_component_manifest() -> Dict[str, Any]:
    exports = [
        {
            "wit_path": ["foundation", "identity-int"],
            "item": {
                "kind": "CallableComponentItemV1",
                "callable": v1_package_callable_edge(),
            },
        },
        {
            "wit_path": ["foundation", "status"],
            "item": {
                "kind": "DataComponentItemV1",
                "declaration": copy.deepcopy(DATA_IDENTITY),
            },
        },
    ]
    exports.sort(key=lambda item: canonical_bytes(item["wit_path"]))
    return {
        "artifact": "ComponentManifestV1",
        "profile": PROFILE,
        "schema_version": 1,
        "package": copy.deepcopy(PACKAGE_ID),
        "name": "foundation",
        "imports": [],
        "exports": exports,
    }


def v1_core_wasm_signature_hash() -> str:
    return object_hash(
        {
            "artifact": "CireCoreWasmSignatureV1",
            "calling_convention": "CirePrivateWasmCallV1",
            "parameters": ["i32"],
            "results": ["i32"],
        }
    )


def build_link_abi() -> Dict[str, Any]:
    callable_interface = load_json(V1 / "interfaces/callable-interface.json")
    data = build_data_declaration()
    return {
        "artifact": "CireLinkAbiV1",
        "profile": PROFILE,
        "schema_version": 1,
        "package_instance_id": copy.deepcopy(PACKAGE_ID),
        "language_interface": v1_artifact_ref(
            "CireLanguageInterfaceV1", object_hash(build_language_interface())
        ),
        "compiler_abi_epoch": "cirec-abi-v1",
        "runtime_abi_epoch": "cire-runtime-v1",
        "target": {
            "validation": "Wasm3.0V1",
            "memory": "Memory32V1",
            "memory_sharing": "NonSharedV1",
            "multi_value": True,
            "bulk_memory": True,
            "indirect_calls": "OrdinaryV1",
            "memory64": False,
            "gc_identity": False,
            "exception_handling": False,
            "native_continuations": False,
            "stack_switching": False,
            "tail_call_semantics": False,
            "simd": False,
            "relaxed_simd": False,
            "threads": False,
            "atomics": False,
        },
        "calling_convention": "CirePrivateWasmCallV1",
        "callable_layouts": [
            {
                "module": [PACKAGE_MODULE, "root"],
                "export_path": ["identity"],
                "callable_interface_hash": object_hash(callable_interface),
                "core_wasm_signature_hash": v1_core_wasm_signature_hash(),
            }
        ],
        "data_layouts": [
            {
                "declaration": copy.deepcopy(DATA_IDENTITY),
                "private_layout_hash": object_hash(
                    {
                        "artifact": "CirePrivateDataLayoutV1",
                        "declaration": DATA_IDENTITY,
                        "body": data["body"],
                    }
                ),
            }
        ],
    }


def build_impl_evidence() -> Dict[str, Any]:
    status_type = v1_nominal_type(DATA_IDENTITY)
    return {
        "artifact": "ImplEvidenceV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": v1_evidence_identity_value("ImplEvidenceV1", 0),
        "binders": v1_empty_binders(),
        "requirements": v1_empty_requirements(),
        "trait": copy.deepcopy(TRAIT_IDENTITY),
        "target": copy.deepcopy(status_type),
        "header": {
            "trait": copy.deepcopy(TRAIT_IDENTITY),
            "arguments": [],
            "associated_types": [
                {
                    "item_ordinal": 0,
                    "declaration_name": "Output",
                    "value": v1_legacy_builtin("Int"),
                }
            ],
            "target": copy.deepcopy(status_type),
        },
        "associated_types": [
            {
                "ordinal": 0,
                "declaration_name": "Output",
                "value": v1_legacy_builtin("Int"),
                "source": "TraitDefaultBindingV1",
            }
        ],
        "methods": [],
        "origin": {
            "kind": "HandwrittenImplV1",
            "origin": "foundation/declarations.cire:impl-comparable-box-int",
        },
    }


def build_callable_contract_fact() -> Dict[str, Any]:
    return {
        "artifact": "CallableContractFactEvidenceV1",
        "profile": PROFILE,
        "schema_version": 1,
        "identity": v1_evidence_identity_value("ProtocolEvidenceV1", 0),
        "package": copy.deepcopy(PACKAGE_ID),
        "callable": v1_package_callable_edge(),
        "source_identity": {
            "kind": "FreeSourceV1",
            "declaration": copy.deepcopy(CALLABLE_SOURCE_IDENTITY),
        },
        "declaration_kind": {"kind": "FreeCallableV1"},
        "visibility": "PublicV1",
        "requirement_scopes": [
            {
                "declaration_slot": 0,
                "requirements": v1_empty_requirements(),
            }
        ],
        "trait_method_uses": [],
        "const_safety": "RuntimeCallableV1",
        "protocol_purity": "OrdinaryCallableV1",
        "trap": "NoTrapV1",
    }


DECLARATION_BUILDERS: Dict[str, Any] = {
    "AbilityDeclarationV1": build_ability_declaration,
    "ConstDeclarationV1": build_const_declaration,
    "DataDeclarationV1": build_data_declaration,
    "EffectDeclarationV1": build_effect_declaration,
    "TraitDeclarationV1": build_trait_declaration,
}


def v1_expected_declaration_documents() -> Dict[str, Dict[str, Any]]:
    return {
        artifact: builder() for artifact, builder in DECLARATION_BUILDERS.items()
    }


def v1_declaration_edge(document: Mapping[str, Any]) -> Dict[str, Any]:
    artifact = document["artifact"]
    return {
        "identity": copy.deepcopy(document["identity"]),
        "declaration": v1_artifact_ref(artifact, object_hash(document)),
    }


def v1_evidence_edge(document: Mapping[str, Any]) -> Dict[str, Any]:
    return {
        "identity": copy.deepcopy(document["identity"]),
        "evidence": v1_artifact_ref(document["artifact"], object_hash(document)),
    }


def build_language_interface() -> Dict[str, Any]:
    declarations = [
        v1_declaration_edge(document)
        for document in v1_expected_declaration_documents().values()
    ]
    declarations.sort(key=lambda edge: canonical_bytes(edge["identity"]))
    evidence_documents = [build_impl_evidence(), build_callable_contract_fact()]
    evidence = [v1_evidence_edge(document) for document in evidence_documents]
    evidence.sort(key=lambda edge: canonical_bytes(edge["identity"]))
    return {
        "artifact": "CireLanguageInterfaceV1",
        "profile": PROFILE,
        "schema_version": 1,
        "package_identity": {
            "kind": "PackageIdentityEvidenceV1",
            "instance": copy.deepcopy(PACKAGE_ID),
            "input": package_identity_input(),
            "hash_algorithm": HASH_ALGORITHM,
        },
        "package_instance_id": copy.deepcopy(PACKAGE_ID),
        "imports": [],
        "declarations": declarations,
        "evidence": evidence,
        "callables": [v1_package_callable_edge()],
        "components": [
            {
                "name": "foundation",
                "manifest": v1_artifact_ref(
                    "ComponentManifestV1",
                    object_hash(build_component_manifest()),
                ),
            }
        ],
        "primitive_catalog": v1_artifact_ref(
            "PrimitiveCatalogV1",
            object_hash(load_json(V1 / "interfaces/primitive-catalog.json")),
        ),
        "intrinsic_registry": v1_artifact_ref(
            "IntrinsicRegistryRootV1",
            object_hash(load_json(V1 / "interfaces/intrinsic-registry.json")),
        ),
    }


def v1_component_option_int_type() -> Dict[str, Any]:
    return v1_builtin_application("Option", [v1_legacy_builtin("Int")])


def v1_component_status_type() -> Dict[str, Any]:
    return v1_nominal_type(DATA_IDENTITY)


def v1_core_primitive_type(name: str) -> Dict[str, Any]:
    return {
        "kind": "NominalTypeV2",
        "module": [PACKAGE_MODULE, "core", "primitive"],
        "name": name,
        "arguments": [],
    }


def v1_component_status_abi() -> Dict[str, Any]:
    int_abi = {"kind": "ScalarV1", "scalar": "S32V1"}
    return {
        "kind": "VariantV1",
        "source": v1_component_status_type(),
        "declaration": copy.deepcopy(DATA_IDENTITY),
        "cases": [
            {
                "ordinal": 0,
                "name": "Present",
                "payload": {
                    "kind": "RecordPayloadV1",
                    "fields": [
                        {"ordinal": 0, "name": "value", "type": copy.deepcopy(int_abi)},
                        {"ordinal": 1, "name": "fallback", "type": copy.deepcopy(int_abi)},
                        {
                            "ordinal": 2,
                            "name": "optional",
                            "type": {
                                "kind": "OptionV1",
                                "value": copy.deepcopy(int_abi),
                            },
                        },
                    ],
                },
            },
            {"ordinal": 1, "name": "Absent", "payload": None},
        ],
    }


def build_component_interface() -> Dict[str, Any]:
    sources = [
        (v1_legacy_builtin("Int"), {"kind": "ScalarV1", "scalar": "S32V1"}),
        (
            v1_component_option_int_type(),
            {
                "kind": "OptionV1",
                "value": {"kind": "ScalarV1", "scalar": "S32V1"},
            },
        ),
        (v1_component_status_type(), v1_component_status_abi()),
    ]
    sources.sort(key=lambda item: canonical_bytes(item[0]))
    return {
        "artifact": "CireComponentInterfaceV1",
        "profile": PROFILE,
        "schema_version": 1,
        "package_instance_id": copy.deepcopy(PACKAGE_ID),
        "manifest": v1_artifact_ref(
            "ComponentManifestV1", object_hash(build_component_manifest())
        ),
        "link_abi": v1_artifact_ref("CireLinkAbiV1", object_hash(build_link_abi())),
        "component_abi_epoch": "cire-component-memory32-utf8-sync-v1",
        "memory": "Memory32V1",
        "string_encoding": "Utf8V1",
        "native_async": False,
        "type_mappings": [
            {"source": source, "canonical_abi": target}
            for source, target in sources
        ],
        "imports": [],
        "exports": [
            {
                "wit_path": ["foundation", "identity-int"],
                "callable": v1_package_callable_edge(),
                "parameters": [
                    {
                        "ordinal": 0,
                        "name": "value",
                        "type": {"kind": "ScalarV1", "scalar": "S32V1"},
                    }
                ],
                "result": {"kind": "ScalarV1", "scalar": "S32V1"},
                "owner_policy": "PerCallChildOwnerV1",
                "terminal_close_policy": "EveryCireReturnsOrAbortsV1",
            }
        ],
        "resources": [],
        "borrow_policy": {
            "provenance": "CallbackOrFfiV1",
            "escape": False,
            "suspend": False,
            "store_without_owned_copy": False,
        },
        "trap_policy": {
            "cire_defect": "DefectTransitionV1AfterSuffixRetirementV1",
            "host_or_engine_trap": "CatastrophicInstanceFailureV1",
            "catchable_as_raise": False,
            "convert_to_result": False,
        },
    }


def v1_validate_exact_declaration(
    value: Any,
    *,
    artifact: str,
    root_fields: Sequence[str],
    identity: Mapping[str, Any],
    builder: Any,
) -> None:
    root = v1_closed(value, root_fields, artifact)
    validate_profile_header(
        root, artifact, 1, "callable-interface-contract-mismatch"
    )
    v1_declaration_identity(root["identity"], artifact + ".identity")
    if root["identity"] != identity:
        fail(
            "package-instance-hash-mismatch",
            artifact + " identity differs from the package declaration edge",
        )
    if root != builder():
        fail(
            "callable-interface-contract-mismatch",
            artifact + " differs from the deterministic successor model",
        )


def v1_type_binder_table(value: Any, context: str) -> Dict[int, Dict[str, Any]]:
    binders = v1_closed(
        value,
        [
            "parameter_binders",
            "type_binders",
            "row_binders",
            "contract_binders",
            "owner_binders",
            "clock_binders",
            "identity_binders",
            "prompt_binders",
        ],
        context,
    )
    for field in binders:
        require_list(
            binders[field], "Decode/array-mismatch", context + "." + field
        )
    result: Dict[int, Dict[str, Any]] = {}
    slots: List[int] = []
    for value_binder in binders["type_binders"]:
        if not isinstance(value_binder, dict):
            fail("Decode/object-mismatch", context + " type binder is not an object")
        kind = value_binder.get("kind")
        if kind == "EffectConstructorV3":
            binder = v1_closed(
                value_binder,
                ["slot", "kind", "constructor_arity"],
                "EffectConstructorBinderV3",
            )
            arity = v1_u32(
                binder["constructor_arity"], "effect constructor arity"
            )
            if arity == 0:
                fail(
                    "contract-component-kind-mismatch",
                    "EffectConstructorBinderV3 arity must be positive",
                )
        else:
            binder = v1_closed(
                value_binder, ["slot", "kind"], "TypeBinderV3"
            )
            if kind not in {"Type", "Effect", "OwnerRegion"}:
                fail("Decode/tag-mismatch", "unknown TypeBinderV3 variant")
        slot = v1_u32(binder["slot"], "type binder slot")
        if slot in result:
            fail(
                "contract-component-kind-mismatch",
                "type binder slot is duplicated",
            )
        slots.append(slot)
        result[slot] = binder
    if slots != sorted(slots):
        fail(
            "contract-component-kind-mismatch",
            "type binder table is not slot ordered",
        )
    return result


def v1_validate_m3_type(
    value: Any, binder_table: Mapping[int, Mapping[str, Any]], context: str
) -> None:
    if not isinstance(value, dict):
        fail("Decode/object-mismatch", context + " type is not an object")
    kind = value.get("kind")
    if kind == "LegacyTypeRefV2":
        legacy = v1_closed(value, ["kind", "value"], "LegacyTypeRefV2")
        builtin = v1_closed(
            legacy["value"], ["kind", "name"], "BuiltinTypeV1"
        )
        if builtin["kind"] != "BuiltinTypeV1" or builtin["name"] not in {
            "Unit",
            "Never",
            "Bool",
            "Int",
            "String",
        }:
            fail(
                "contract-component-kind-mismatch",
                context + " legacy builtin differs",
            )
        return
    if kind == "TypeParameterV2":
        parameter = v1_closed(value, ["kind", "slot"], "TypeParameterV2")
        slot = v1_u32(parameter["slot"], context + " type parameter slot")
        binder = binder_table.get(slot)
        if binder is None or binder["kind"] not in {"Type", "Effect"}:
            fail(
                "contract-component-kind-mismatch",
                context + " type parameter does not resolve to an atomic binder",
            )
        return
    if kind == "NominalTypeV2":
        nominal = v1_closed(
            value,
            ["kind", "module", "name", "arguments"],
            "NominalTypeV2",
        )
        v1_module(nominal["module"], context + " nominal module")
        v1_string(nominal["name"], context + " nominal name")
        for index, argument in enumerate(
            require_list(
                nominal["arguments"],
                "Decode/array-mismatch",
                context + " nominal arguments",
            )
        ):
            v1_validate_m3_type(
                argument, binder_table, context + ".argument" + str(index)
            )
        return
    if kind == "ApplyTypeV2":
        applied = v1_closed(
            value, ["kind", "constructor", "arguments"], "ApplyTypeV2"
        )
        arguments = require_list(
            applied["arguments"],
            "Decode/array-mismatch",
            context + " arguments",
        )
        constructor_value = applied["constructor"]
        if not isinstance(constructor_value, dict):
            fail("Decode/object-mismatch", context + " constructor is not an object")
        constructor_kind = constructor_value.get("kind")
        if constructor_kind == "EffectParameterConstructorV3":
            constructor = v1_closed(
                constructor_value,
                ["kind", "binder_slot", "constructor_arity"],
                "EffectParameterConstructorV3",
            )
            slot = v1_u32(constructor["binder_slot"], context + " binder slot")
            arity = v1_u32(
                constructor["constructor_arity"], context + " constructor arity"
            )
            binder = binder_table.get(slot)
            if (
                binder is None
                or binder["kind"] != "EffectConstructorV3"
                or binder["constructor_arity"] != arity
                or len(arguments) != arity
            ):
                fail(
                    "contract-component-kind-mismatch",
                    context + " effect constructor application differs from its binder",
                )
        elif constructor_kind == "BuiltinConstructorV1":
            constructor = v1_closed(
                constructor_value,
                ["kind", "name"],
                "BuiltinConstructorV1",
            )
            arities = {"Array": 1, "Option": 1, "Result": 2}
            if constructor["name"] not in arities or len(arguments) != arities[
                constructor["name"]
            ]:
                fail(
                    "contract-component-kind-mismatch",
                    context + " builtin constructor arity differs",
                )
        elif constructor_kind == "NominalConstructorV1":
            constructor = v1_closed(
                constructor_value,
                ["kind", "module", "name"],
                "NominalConstructorV1",
            )
            v1_module(constructor["module"], context + " constructor module")
            v1_string(constructor["name"], context + " constructor name")
        else:
            fail(
                "contract-component-kind-mismatch",
                context + " has an unsupported retained M3 constructor",
            )
        for index, argument in enumerate(arguments):
            v1_validate_m3_type(
                argument, binder_table, context + ".argument" + str(index)
            )
        return
    fail("contract-component-kind-mismatch", context + " has an unsupported M3 type")


def v1_validate_declaration_requirements(
    value: Any,
    binder_table: Mapping[int, Mapping[str, Any]],
    context: str,
) -> None:
    requirements = v1_closed(
        value,
        ["ordinary_traits", "effect_parameters"],
        "DeclarationRequirementsV1",
    )
    ordinary_traits = require_list(
        requirements["ordinary_traits"],
        "Decode/array-mismatch",
        context + ".ordinary_traits",
    )
    effect_parameters = require_list(
        requirements["effect_parameters"],
        "Decode/array-mismatch",
        context + ".effect_parameters",
    )
    ordinary_keys: List[bytes] = []
    for requirement_value in ordinary_traits:
        requirement = v1_closed(
            requirement_value,
            [
                "requirement_ordinal",
                "origin",
                "binder_slot",
                "trait",
                "arguments",
                "associated_types",
            ],
            "GenericTraitRequirementV1",
        )
        ordinal = v1_u32(
            requirement["requirement_ordinal"],
            context + " trait requirement ordinal",
        )
        if ordinal != len(ordinary_keys):
            fail(
                "associated-contract-mismatch",
                context + " trait requirement ordinal is not canonical",
            )
        origin_value = requirement["origin"]
        if not isinstance(origin_value, dict):
            fail(
                "Decode/object-mismatch",
                context + " trait requirement origin must be an object",
            )
        origin_kind = origin_value.get("kind")
        if origin_kind == "SourceTraitRequirementV1":
            v1_closed(
                origin_value,
                ["kind"],
                "SourceTraitRequirementV1",
            )
        elif origin_kind == "AssociatedConstraintEntailmentV1":
            origin = v1_closed(
                origin_value,
                [
                    "kind",
                    "parent_requirement_ordinal",
                    "associated_item_ordinal",
                    "constraint_ordinal",
                ],
                "AssociatedConstraintEntailmentV1",
            )
            parent = v1_u32(
                origin["parent_requirement_ordinal"],
                context + " derived requirement parent",
            )
            item_ordinal = v1_u32(
                origin["associated_item_ordinal"],
                context + " derived requirement associated item",
            )
            v1_u32(
                origin["constraint_ordinal"],
                context + " derived requirement constraint",
            )
            if parent >= ordinal or item_ordinal != 0:
                fail(
                    "associated-contract-mismatch",
                    context + " derived requirement origin is not a prior valid associated item",
                )
        else:
            fail(
                "Decode/tag-mismatch",
                context + " trait requirement has an unknown origin tag",
            )
        slot = v1_u32(
            requirement["binder_slot"], context + " trait binder slot"
        )
        if binder_table.get(slot, {}).get("kind") != "Type":
            fail(
                "associated-contract-mismatch",
                context + " trait requirement does not target a Type binder",
            )
        if requirement["trait"] != TRAIT_IDENTITY:
            fail(
                "associated-contract-mismatch",
                context + " trait identity is not package-resolved",
            )
        arguments = require_list(
            requirement["arguments"],
            "Decode/array-mismatch",
            context + " trait arguments",
        )
        for argument in arguments:
            v1_validate_m3_type(argument, binder_table, context + " trait argument")
        associated = require_list(
            requirement["associated_types"],
            "Decode/array-mismatch",
            context + " associated types",
        )
        if len(associated) != 1:
            fail(
                "associated-contract-mismatch",
                context + " associated type vector is not total",
            )
        item = v1_closed(
            associated[0],
            ["item_ordinal", "declaration_name", "binder_slot", "equality"],
            "GenericTraitAssociatedTypeV1",
        )
        hidden_slot = v1_u32(
            item["binder_slot"], context + " associated hidden binder"
        )
        if (
            item["item_ordinal"] != 0
            or item["declaration_name"] != "Output"
            or binder_table.get(hidden_slot, {}).get("kind") != "Type"
        ):
            fail(
                "associated-contract-mismatch",
                context + " associated type hidden binder differs",
            )
        if origin_kind == "AssociatedConstraintEntailmentV1":
            parent_requirement = ordinary_traits[
                origin_value["parent_requirement_ordinal"]
            ]
            parent_associated = parent_requirement["associated_types"][
                origin_value["associated_item_ordinal"]
            ]
            if slot != parent_associated["binder_slot"]:
                fail(
                    "associated-contract-mismatch",
                    context + " derived requirement does not target the parent associated hidden binder",
                )
        if item["equality"] is not None:
            v1_validate_m3_type(
                item["equality"], binder_table, context + " associated equality"
            )
        ordinary_keys.append(
            canonical_bytes(
                {
                    "binder_slot": slot,
                    "requirement": requirement,
                }
            )
        )
    if ordinary_keys != sorted(ordinary_keys) or len(ordinary_keys) != len(
        set(ordinary_keys)
    ):
        fail(
            "associated-contract-mismatch",
            context + " trait requirements are not canonical unique",
        )
    effect_keys: List[bytes] = []
    for parameter_value in effect_parameters:
        parameter = v1_closed(
            parameter_value,
            ["binder_slot", "constructor_arity", "abilities"],
            "GenericEffectParameterV1",
        )
        slot = v1_u32(
            parameter["binder_slot"], context + " effect binder slot"
        )
        arity = v1_u32(
            parameter["constructor_arity"], context + " effect arity"
        )
        binder = binder_table.get(slot)
        if arity == 0:
            if binder is None or binder["kind"] != "Effect":
                fail(
                    "contract-component-kind-mismatch",
                    context + " atomic Effect requirement binder differs",
                )
        elif (
            binder is None
            or binder["kind"] != "EffectConstructorV3"
            or binder["constructor_arity"] != arity
        ):
            fail(
                "contract-component-kind-mismatch",
                context + " effect constructor requirement binder differs",
            )
        abilities = require_list(
            parameter["abilities"],
            "Decode/array-mismatch",
            context + " ability constraints",
        )
        if arity > 0 and abilities:
            fail(
                "associated-contract-mismatch",
                context + " F[_] ability constraints are not in Cire-v1.0",
            )
        effect_keys.append(
            canonical_bytes(
                {"binder_slot": slot, "requirement": parameter}
            )
        )
    if effect_keys != sorted(effect_keys) or len(effect_keys) != len(
        set(effect_keys)
    ):
        fail(
            "associated-contract-mismatch",
            context + " effect requirements are not canonical unique",
        )


def v1_validate_const_declaration(value: Any) -> None:
    v1_validate_exact_declaration(
        value,
        artifact="ConstDeclarationV1",
        root_fields=[
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "visibility",
            "type",
            "value",
            "evaluator",
        ],
        identity=CONST_IDENTITY,
        builder=build_const_declaration,
    )
    v1_validate_m3_type(value["type"], {}, "ConstDeclarationV1.type")
    v1_validate_const_value(
        value["value"], value["type"], {}, "ConstDeclarationV1.value"
    )


def v1_validate_trait_declaration(value: Any) -> None:
    v1_validate_exact_declaration(
        value,
        artifact="TraitDeclarationV1",
        root_fields=[
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "visibility",
            "binders",
            "self_binder_slot",
            "requirements",
            "associated_types",
            "methods",
        ],
        identity=TRAIT_IDENTITY,
        builder=build_trait_declaration,
    )
    binder_table = v1_type_binder_table(
        value["binders"], "TraitDeclarationV1.binders"
    )
    v1_validate_declaration_requirements(
        value["requirements"], binder_table, "TraitDeclarationV1.requirements"
    )
    if value["self_binder_slot"] not in binder_table:
        fail("associated-contract-mismatch", "trait Self binder is absent")
    for associated in value["associated_types"]:
        if associated["binder_slot"] not in binder_table:
            fail(
                "associated-contract-mismatch",
                "trait associated type binder is absent",
            )
        if associated["default_type"] is not None:
            v1_validate_m3_type(
                associated["default_type"],
                binder_table,
                "TraitDeclarationV1 associated default",
            )


def v1_validate_data_declaration(value: Any) -> None:
    v1_validate_exact_declaration(
        value,
        artifact="DataDeclarationV1",
        root_fields=[
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "visibility",
            "binders",
            "requirements",
            "body",
            "derives",
        ],
        identity=DATA_IDENTITY,
        builder=build_data_declaration,
    )
    binder_table = v1_type_binder_table(
        value["binders"], "DataDeclarationV1.binders"
    )
    v1_validate_declaration_requirements(
        value["requirements"], binder_table, "DataDeclarationV1.requirements"
    )
    for variant in value["body"]["variants"]:
        payload = variant["payload"]
        for field in payload.get("fields", []):
            v1_validate_m3_type(
                field["type"], binder_table, "DataDeclarationV1 stored field"
            )
            if field["default_value"] is not None:
                v1_validate_const_value(
                    field["default_value"],
                    field["type"],
                    binder_table,
                    "DataDeclarationV1 stored default",
                )


def v1_validate_ability_declaration(value: Any) -> None:
    v1_validate_exact_declaration(
        value,
        artifact="AbilityDeclarationV1",
        root_fields=[
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "visibility",
            "binders",
            "requirements",
            "associated_items",
            "operations",
        ],
        identity=ABILITY_IDENTITY,
        builder=build_ability_declaration,
    )
    binder_table = v1_type_binder_table(
        value["binders"], "AbilityDeclarationV1.binders"
    )
    v1_validate_declaration_requirements(
        value["requirements"],
        binder_table,
        "AbilityDeclarationV1.requirements",
    )
    for operation in value["operations"]:
        operation_binders = v1_type_binder_table(
            operation["binders"], "Ability operation binders"
        )
        v1_validate_declaration_requirements(
            operation["requirements"],
            operation_binders,
            "Ability operation requirements",
        )
        for type_value in [
            *operation["signature"]["parameters"],
            operation["signature"]["result"],
        ]:
            v1_validate_m3_type(
                type_value, operation_binders, "Ability operation type"
            )


def v1_validate_effect_declaration(value: Any) -> None:
    v1_validate_exact_declaration(
        value,
        artifact="EffectDeclarationV1",
        root_fields=[
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "visibility",
            "binders",
            "requirements",
            "conformances",
            "declared_operations",
        ],
        identity=EFFECT_IDENTITY,
        builder=build_effect_declaration,
    )
    binder_table = v1_type_binder_table(
        value["binders"], "EffectDeclarationV1.binders"
    )
    v1_validate_declaration_requirements(
        value["requirements"], binder_table, "EffectDeclarationV1.requirements"
    )
    for operation in value["declared_operations"]:
        operation_binders = v1_type_binder_table(
            operation["binders"], "Effect operation binders"
        )
        v1_validate_declaration_requirements(
            operation["requirements"],
            operation_binders,
            "Effect operation requirements",
        )
        for type_value in [
            *operation["signature"]["parameters"],
            operation["signature"]["result"],
        ]:
            v1_validate_m3_type(
                type_value, operation_binders, "Effect operation type"
            )


def v1_validate_impl_evidence(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "binders",
            "requirements",
            "trait",
            "target",
            "header",
            "associated_types",
            "methods",
            "origin",
        ],
        "ImplEvidenceV1",
    )
    validate_profile_header(
        root,
        "ImplEvidenceV1",
        1,
        "callable-interface-contract-mismatch",
    )
    identity = v1_closed(
        root["identity"],
        ["package", "kind", "ordinal"],
        "EvidenceIdentityV1",
    )
    v1_package_instance(identity["package"], "impl evidence package")
    if identity["kind"] != "ImplEvidenceV1" or v1_u32(
        identity["ordinal"], "impl evidence ordinal"
    ) != 0:
        fail(
            "callable-interface-contract-mismatch",
            "impl evidence identity differs",
        )
    if root != build_impl_evidence():
        fail(
            "callable-interface-contract-mismatch",
            "ImplEvidenceV1 differs from the deterministic successor model",
        )
    binder_table = v1_type_binder_table(
        root["binders"], "ImplEvidenceV1.binders"
    )
    v1_validate_declaration_requirements(
        root["requirements"], binder_table, "ImplEvidenceV1.requirements"
    )
    v1_validate_m3_type(root["target"], binder_table, "ImplEvidenceV1.target")


_HISTORICAL_VALIDATOR: Any = None


def v1_historical_validator() -> Any:
    global _HISTORICAL_VALIDATOR
    if _HISTORICAL_VALIDATOR is None:
        path = ROOT / "validate-oracles.py"
        spec = importlib.util.spec_from_file_location("cire_tr0_validator", path)
        if spec is None or spec.loader is None:
            fail("callable-interface-contract-mismatch", "cannot load the frozen V2 decoder")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _HISTORICAL_VALIDATOR = module
    return _HISTORICAL_VALIDATOR


def v1_provided_or_omitted(output_type: Any) -> Dict[str, Any]:
    return {
        "kind": "ApplyTypeV2",
        "constructor": {
            "kind": "NominalConstructorV1",
            "module": [PACKAGE_MODULE, "core"],
            "name": "ProvidedOrOmitted",
        },
        "arguments": [copy.deepcopy(output_type)],
    }


def v1_call_entry_types(parameter_type: Any) -> List[Any]:
    if not isinstance(parameter_type, dict):
        fail(
            "callable-interface-contract-mismatch",
            "function parameter type is not an object",
        )
    constructor = parameter_type.get("constructor")
    if (
        parameter_type.get("kind") == "ApplyTypeV2"
        and isinstance(constructor, dict)
        and constructor.get("kind") == "NominalConstructorV1"
        and isinstance(constructor.get("name"), str)
        and constructor["name"].endswith("Arguments")
    ):
        return require_list(
            parameter_type.get("arguments"),
            "Decode/array-mismatch",
            "function call-entry tuple",
        )
    return [parameter_type]


def v1_validate_surface_slots(
    value: Any,
    binders: Mapping[str, Any],
    default_slots: set[int],
) -> None:
    signature = v1_closed(
        value, ["kind", "slots"], "CallableSurfaceSignatureV1"
    )
    if signature["kind"] != "CallableSurfaceSignatureV1":
        fail("Decode/tag-mismatch", "wrong callable surface signature tag")
    slots = require_list(
        signature["slots"], "Decode/array-mismatch", "surface slots"
    )
    parameter_binders = require_list(
        binders.get("parameter_binders"),
        "Decode/array-mismatch",
        "parameter binders",
    )
    binder_slots = [binder.get("slot") for binder in parameter_binders]
    if binder_slots != list(range(len(binder_slots))):
        fail(
            "callable-interface-contract-mismatch",
            "call-entry parameter slots are not contiguous",
        )
    if [slot.get("slot") for slot in slots if isinstance(slot, dict)] != binder_slots:
        fail(
            "callable-interface-contract-mismatch",
            "surface/Core call-entry slots differ",
        )
    observed_default_slots: set[int] = set()
    public_labels: List[str] = []
    for expected_slot, value_slot in enumerate(slots):
        if not isinstance(value_slot, dict):
            fail("Decode/object-mismatch", "surface slot is not an object")
        passing = value_slot.get("passing")
        if passing in {"ImplicitReceiverV1", "PositionalOnlyV1"}:
            slot = v1_closed(
                value_slot, ["slot", "passing"], "ParameterSurfaceSlotV1"
            )
            if expected_slot in default_slots:
                fail(
                    "callable-interface-contract-mismatch",
                    "receiver/destructuring slot cannot be defaultable",
                )
        elif passing == "NamedOrPositionalV1":
            slot = v1_closed(
                value_slot,
                ["slot", "passing", "public_label", "defaultable"],
                "ParameterSurfaceSlotV1",
            )
            v1_string(slot["public_label"], "public parameter label")
            public_labels.append(slot["public_label"])
            if not isinstance(slot["defaultable"], bool):
                fail("Decode/bool-mismatch", "defaultable is not a Bool")
            if slot["defaultable"]:
                observed_default_slots.add(expected_slot)
        else:
            fail("Decode/enum-mismatch", "unknown parameter passing mode")
        if v1_u32(slot["slot"], "surface parameter slot") != expected_slot:
            fail(
                "callable-interface-contract-mismatch",
                "surface parameter slots are not contiguous",
            )
    if observed_default_slots != default_slots:
        fail(
            "callable-interface-contract-mismatch",
            "surface defaultable slots and Core prologues differ",
        )
    if len(public_labels) != len(set(public_labels)):
        fail(
            "callable-interface-contract-mismatch",
            "named-or-positional public labels are not pairwise distinct",
        )


def v1_validate_callable_dependencies(value: Any) -> List[Dict[str, Any]]:
    dependencies = require_list(
        value, "Decode/array-mismatch", "callable dependencies"
    )
    keys: List[bytes] = []
    result: List[Dict[str, Any]] = []
    for expected_slot, dependency_value in enumerate(dependencies):
        dependency = v1_closed(
            dependency_value,
            ["import_slot", "module", "export_path", "interface_hash"],
            "ImportedCallableRefV3",
        )
        if v1_u32(dependency["import_slot"], "import slot") != expected_slot:
            fail(
                "callable-interface-contract-mismatch",
                "dependency import slots are not contiguous",
            )
        v1_module(dependency["module"], "dependency module")
        export_path = require_list(
            dependency["export_path"],
            "Decode/array-mismatch",
            "dependency export path",
        )
        if not export_path:
            fail(
                "callable-interface-contract-mismatch",
                "dependency export path is empty",
            )
        for segment in export_path:
            v1_string(segment, "dependency export path segment")
        interface_hash = dependency["interface_hash"]
        if (
            not isinstance(interface_hash, str)
            or not SHA256_RE.fullmatch(interface_hash)
            or interface_hash == ZERO_HASH
        ):
            fail(
                "callable-interface-contract-mismatch",
                "dependency interface hash is malformed",
            )
        key = {
            "module": dependency["module"],
            "export_path": dependency["export_path"],
            "interface_hash": interface_hash,
        }
        keys.append(canonical_bytes(key))
        result.append(dependency)
    if keys != sorted(keys) or len(keys) != len(set(keys)):
        fail(
            "callable-interface-contract-mismatch",
            "dependency table is not canonical sorted unique",
        )
    return result


def v1_scan_m3_payload(
    value: Any,
    *,
    import_count: int,
    local_slots: set[int],
    imported_uses: set[int],
    local_uses: set[int],
) -> None:
    if isinstance(value, dict):
        if value.get("artifact") == "FunctionContractV2":
            fail(
                "callable-interface-contract-mismatch",
                "nested raw FunctionContractV2 remains",
            )
        kind = value.get("kind")
        if isinstance(kind, str) and kind in {
            "ImportedFunctionRefV2",
            "ImportedCallableRefV2",
        }:
            fail(
                "callable-interface-contract-mismatch",
                "raw V2 imported callable reference remains",
            )
        if kind == "ImportedCallableSlotRefV3":
            reference = v1_closed(
                value,
                ["kind", "import_slot"],
                "ImportedCallableSlotRefV3",
            )
            slot = v1_u32(reference["import_slot"], "imported callable slot")
            if slot >= import_count:
                fail(
                    "callable-interface-contract-mismatch",
                    "imported callable slot is out of range",
                )
            imported_uses.add(slot)
            return
        if kind == "LocalFunctionRefV2":
            reference = v1_closed(
                value,
                ["kind", "declaration_slot"],
                "LocalFunctionRefV2",
            )
            slot = v1_u32(reference["declaration_slot"], "local declaration slot")
            if slot not in local_slots:
                fail(
                    "callable-interface-contract-mismatch",
                    "local function reference is unresolved",
                )
            local_uses.add(slot)
            return
        for child in value.values():
            v1_scan_m3_payload(
                child,
                import_count=import_count,
                local_slots=local_slots,
                imported_uses=imported_uses,
                local_uses=local_uses,
            )
    elif isinstance(value, list):
        for child in value:
            v1_scan_m3_payload(
                child,
                import_count=import_count,
                local_slots=local_slots,
                imported_uses=imported_uses,
                local_uses=local_uses,
            )


def v1_validate_effect_constructor_references(
    value: Any,
    binder_table: Mapping[int, Mapping[str, Any]],
    context: str,
) -> None:
    if isinstance(value, dict):
        kind = value.get("kind")
        if kind == "EffectConstructorV3":
            binder = v1_closed(
                value,
                ["slot", "kind", "constructor_arity"],
                "EffectConstructorBinderV3",
            )
            slot = v1_u32(binder["slot"], context + " binder slot")
            arity = v1_u32(
                binder["constructor_arity"], context + " binder arity"
            )
            if arity == 0 or binder_table.get(slot) != binder:
                fail(
                    "contract-component-kind-mismatch",
                    context + " EffectConstructorBinderV3 is out of scope",
                )
            return
        if kind == "EffectParameterConstructorV3":
            fail(
                "contract-component-kind-mismatch",
                context + " effect constructor ref is outside ApplyTypeV2",
            )
        if kind == "ApplyTypeV2" and isinstance(
            value.get("constructor"), dict
        ) and value["constructor"].get("kind") == "EffectParameterConstructorV3":
            applied = v1_closed(
                value, ["kind", "constructor", "arguments"], "ApplyTypeV2"
            )
            constructor = v1_closed(
                applied["constructor"],
                ["kind", "binder_slot", "constructor_arity"],
                "EffectParameterConstructorV3",
            )
            slot = v1_u32(
                constructor["binder_slot"], context + " constructor slot"
            )
            arity = v1_u32(
                constructor["constructor_arity"],
                context + " constructor arity",
            )
            arguments = require_list(
                applied["arguments"],
                "Decode/array-mismatch",
                context + " constructor arguments",
            )
            binder = binder_table.get(slot)
            if (
                binder is None
                or binder.get("kind") != "EffectConstructorV3"
                or binder.get("constructor_arity") != arity
                or len(arguments) != arity
            ):
                fail(
                    "contract-component-kind-mismatch",
                    context + " effect constructor application differs",
                )
            for index, argument in enumerate(arguments):
                v1_validate_effect_constructor_references(
                    argument,
                    binder_table,
                    context + ".argument" + str(index),
                )
            return
        for key, child in value.items():
            v1_validate_effect_constructor_references(
                child, binder_table, context + "." + key
            )
    elif isinstance(value, list):
        for index, child in enumerate(value):
            v1_validate_effect_constructor_references(
                child, binder_table, context + "." + str(index)
            )


def v1_demigrate_payload(
    value: Any, legacy_references: Mapping[int, Mapping[str, Any]]
) -> Any:
    if isinstance(value, dict):
        if value.get("kind") == "ImportedCallableSlotRefV3":
            slot = value["import_slot"]
            if slot not in legacy_references:
                fail(
                    "callable-interface-contract-mismatch",
                    "cannot resolve imported callable slot for V2 compatibility",
                )
            return copy.deepcopy(legacy_references[slot])
        if value.get("kind") == "EffectConstructorV3":
            binder = v1_closed(
                value,
                ["slot", "kind", "constructor_arity"],
                "EffectConstructorBinderV3",
            )
            return {"slot": binder["slot"], "kind": "Effect"}
        if value.get("kind") == "EffectParameterConstructorV3":
            constructor = v1_closed(
                value,
                ["kind", "binder_slot", "constructor_arity"],
                "EffectParameterConstructorV3",
            )
            return {
                "kind": "NominalConstructorV1",
                "module": [PACKAGE_MODULE, "m3-effect-parameter"],
                "name": "F" + str(constructor["binder_slot"]),
            }
        return {
            key: v1_demigrate_payload(child, legacy_references)
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [v1_demigrate_payload(child, legacy_references) for child in value]
    return copy.deepcopy(value)


def v1_local_contract_to_v2(
    declaration: Mapping[str, Any], legacy_references: Mapping[int, Mapping[str, Any]]
) -> Dict[str, Any]:
    historical = v1_historical_validator()
    return {
        "artifact": "FunctionContractV2",
        "profile": historical.PROFILE,
        "schema_version": 2,
        "declaration_kind": v1_demigrate_payload(
            declaration["declaration_kind"], legacy_references
        ),
        "binders": v1_demigrate_payload(declaration["binders"], legacy_references),
        "applications": v1_demigrate_payload(
            declaration["applications"], legacy_references
        ),
        "computation": v1_demigrate_payload(
            declaration["computation"], legacy_references
        ),
        "closure_environment": v1_demigrate_payload(
            declaration["closure_environment"], legacy_references
        ),
    }


def v1_validate_default_prologues(
    prologues_value: Any,
    *,
    declaration_kind: Mapping[str, Any],
    binders: Mapping[str, Any],
    applications: Sequence[Any],
    closure_environment: Sequence[Any],
    legacy_references: Mapping[int, Mapping[str, Any]],
    imports: Any,
    local_functions: Mapping[int, Dict[str, Any]],
) -> set[int]:
    prologues = require_list(
        prologues_value, "Decode/array-mismatch", "default prologues"
    )
    if not prologues:
        return set()
    slots: List[int] = []
    parameter_binders = require_list(
        binders.get("parameter_binders"),
        "Decode/array-mismatch",
        "parameter binders",
    )
    binder_by_slot = {
        binder.get("slot"): binder
        for binder in parameter_binders
        if isinstance(binder, dict)
    }
    call_entry_types = v1_call_entry_types(declaration_kind["parameter_type"])
    historical = v1_historical_validator()
    for prologue_value in prologues:
        prologue = v1_closed(
            prologue_value,
            [
                "kind",
                "parameter_slot",
                "input_type",
                "output_type",
                "computation",
                "origin",
            ],
            "DefaultPrologueV1",
        )
        if prologue["kind"] != "DefaultPrologueV1":
            fail("Decode/tag-mismatch", "wrong default prologue tag")
        slot = v1_u32(prologue["parameter_slot"], "default parameter slot")
        slots.append(slot)
        if slot not in binder_by_slot or slot >= len(call_entry_types):
            fail(
                "callable-interface-contract-mismatch",
                "default prologue parameter slot is unresolved",
            )
        expected_input = v1_provided_or_omitted(prologue["output_type"])
        if (
            prologue["input_type"] != expected_input
            or binder_by_slot[slot].get("type") != expected_input
            or call_entry_types[slot] != expected_input
        ):
            fail(
                "callable-interface-contract-mismatch",
                "default prologue is not an exact ProvidedOrOmitted wrapper",
            )
        v1_string(prologue["origin"], "default prologue origin")
        retained = {
            "artifact": "FunctionContractV2",
            "profile": historical.PROFILE,
            "schema_version": 2,
            "declaration_kind": v1_demigrate_payload(
                {
                    **copy.deepcopy(declaration_kind),
                    "result_type": copy.deepcopy(prologue["output_type"]),
                },
                legacy_references,
            ),
            "binders": v1_demigrate_payload(binders, legacy_references),
            "applications": v1_demigrate_payload(applications, legacy_references),
            "computation": v1_demigrate_payload(
                prologue["computation"], legacy_references
            ),
            "closure_environment": v1_demigrate_payload(
                closure_environment, legacy_references
            ),
        }
        try:
            historical.validate_function_contract(
                retained, imports=imports, local_functions=local_functions
            )
        except Exception as error:  # noqa: BLE001 - host failures are conformance failures
            fail(
                "callable-interface-contract-mismatch",
                "default prologue V2 nonterminal rejection: "
                + type(error).__name__
                + ": "
                + str(error),
            )
    if slots != sorted(slots) or len(slots) != len(set(slots)):
        fail(
            "callable-interface-contract-mismatch",
            "default prologues are not parameter-slot sorted unique",
        )
    return set(slots)


def v1_validate_function_contract(
    value: Any,
    *,
    dependency_legacy: Mapping[str, Dict[str, Any]] | None = None,
    surface_signature: Any | None = None,
) -> Dict[str, Any]:
    root = v1_closed(
        value,
        [
            "artifact", "profile", "schema_version", "root_declaration_slot",
            "declaration_kind", "binders", "callable_dependencies",
            "local_declarations", "default_prologues", "applications",
            "computation", "closure_environment",
        ],
        "FunctionContractV3",
    )
    validate_profile_header(
        root,
        "FunctionContractV3",
        3,
        "callable-interface-contract-mismatch",
    )
    if v1_u32(root["root_declaration_slot"], "root_declaration_slot") != 0:
        fail(
            "callable-interface-contract-mismatch",
            "root declaration slot must be zero",
        )
    dependencies = v1_validate_callable_dependencies(root["callable_dependencies"])
    local_values = require_list(
        root["local_declarations"],
        "Decode/array-mismatch",
        "local declarations",
    )
    applications = require_list(
        root["applications"], "Decode/array-mismatch", "applications"
    )
    closure_environment = require_list(
        root["closure_environment"],
        "Decode/array-mismatch",
        "closure environment",
    )
    root_type_binders = v1_type_binder_table(
        root["binders"], "FunctionContractV3.binders"
    )
    for field in (
        "declaration_kind",
        "binders",
        "applications",
        "computation",
        "closure_environment",
        "default_prologues",
    ):
        v1_validate_effect_constructor_references(
            root[field], root_type_binders, "FunctionContractV3." + field
        )
    local_slots = set(range(1, len(local_values) + 1))
    local_declarations: Dict[int, Dict[str, Any]] = {}
    for expected_slot, local_value in enumerate(local_values, 1):
        declaration = v1_closed(
            local_value,
            [
                "declaration_slot",
                "declaration_kind",
                "binders",
                "default_prologues",
                "applications",
                "computation",
                "closure_environment",
            ],
            "LocalFunctionDeclarationV3",
        )
        if (
            v1_u32(declaration["declaration_slot"], "local declaration slot")
            != expected_slot
        ):
            fail(
                "callable-interface-contract-mismatch",
                "local declarations are not lexical slots 1..n",
            )
        for field in (
            "default_prologues",
            "applications",
            "closure_environment",
        ):
            require_list(
                declaration[field],
                "Decode/array-mismatch",
                "local declaration " + field,
            )
        local_type_binders = v1_type_binder_table(
            declaration["binders"],
            "LocalFunctionDeclarationV3.binders",
        )
        for field in (
            "declaration_kind",
            "binders",
            "default_prologues",
            "applications",
            "computation",
            "closure_environment",
        ):
            v1_validate_effect_constructor_references(
                declaration[field],
                local_type_binders,
                "LocalFunctionDeclarationV3." + field,
            )
        local_declarations[expected_slot] = declaration

    imported_uses: set[int] = set()
    root_local_uses: set[int] = set()
    for field in (
        "declaration_kind",
        "binders",
        "applications",
        "computation",
        "closure_environment",
        "default_prologues",
    ):
        v1_scan_m3_payload(
            root[field],
            import_count=len(dependencies),
            local_slots=local_slots,
            imported_uses=imported_uses,
            local_uses=root_local_uses,
        )
    local_edges: Dict[int, set[int]] = {}
    for slot, declaration in local_declarations.items():
        uses: set[int] = set()
        v1_scan_m3_payload(
            declaration,
            import_count=len(dependencies),
            local_slots=local_slots,
            imported_uses=imported_uses,
            local_uses=uses,
        )
        local_edges[slot] = uses
    if imported_uses != set(range(len(dependencies))):
        fail(
            "callable-interface-contract-mismatch",
            "dependency table is not exact-used",
        )
    reachable: set[int] = set()
    worklist = list(root_local_uses)
    while worklist:
        slot = worklist.pop()
        if slot in reachable:
            continue
        reachable.add(slot)
        worklist.extend(local_edges[slot] - reachable)
    if reachable != local_slots:
        fail(
            "callable-interface-contract-mismatch",
            "local declaration table is not exact-reachable",
        )

    dependency_legacy = dependency_legacy or {}
    historical = v1_historical_validator()
    imports = historical.ImportScope()
    legacy_references: Dict[int, Dict[str, Any]] = {}
    for dependency in dependencies:
        interface_hash = dependency["interface_hash"]
        target = dependency_legacy.get(interface_hash)
        if target is None:
            fail(
                "callable-interface-contract-mismatch",
                "dependency interface hash is absent or not callee-before-caller",
            )
        legacy_hash = historical.canonical_hash(target)
        legacy_module = [
            *dependency["module"],
            *dependency["export_path"][:-1],
        ]
        legacy_name = dependency["export_path"][-1]
        imports[legacy_hash] = target
        imports.exports[legacy_hash] = (tuple(legacy_module), legacy_name)
        legacy_references[dependency["import_slot"]] = {
            "kind": "ImportedFunctionRefV2",
            "module": legacy_module,
            "name": legacy_name,
            "artifact_hash": legacy_hash,
        }

    local_functions = {
        slot: v1_local_contract_to_v2(declaration, legacy_references)
        for slot, declaration in local_declarations.items()
    }
    retained = {
        "artifact": "FunctionContractV2",
        "profile": historical.PROFILE,
        "schema_version": 2,
        "declaration_kind": v1_demigrate_payload(
            root["declaration_kind"], legacy_references
        ),
        "binders": v1_demigrate_payload(root["binders"], legacy_references),
        "applications": v1_demigrate_payload(applications, legacy_references),
        "computation": v1_demigrate_payload(root["computation"], legacy_references),
        "closure_environment": v1_demigrate_payload(
            closure_environment, legacy_references
        ),
    }
    try:
        for local_contract in local_functions.values():
            historical.validate_function_contract(
                local_contract, imports=imports, local_functions=local_functions
            )
        historical.validate_function_contract(
            retained, imports=imports, local_functions=local_functions
        )
    except Exception as error:  # noqa: BLE001 - host failures are conformance failures
        fail(
            "callable-interface-contract-mismatch",
            "retained V2 nonterminal decoder rejected M3: "
            + type(error).__name__
            + ": "
            + str(error),
        )

    default_slots = v1_validate_default_prologues(
        root["default_prologues"],
        declaration_kind=root["declaration_kind"],
        binders=root["binders"],
        applications=applications,
        closure_environment=closure_environment,
        legacy_references=legacy_references,
        imports=imports,
        local_functions=local_functions,
    )
    for declaration in local_declarations.values():
        v1_validate_default_prologues(
            declaration["default_prologues"],
            declaration_kind=declaration["declaration_kind"],
            binders=declaration["binders"],
            applications=declaration["applications"],
            closure_environment=declaration["closure_environment"],
            legacy_references=legacy_references,
            imports=imports,
            local_functions=local_functions,
        )
    if surface_signature is not None:
        v1_validate_surface_slots(surface_signature, root["binders"], default_slots)
    return retained


def v1_contains_tag(value: Any, tag: str) -> bool:
    if isinstance(value, dict):
        return value.get("kind") == tag or any(
            v1_contains_tag(child, tag) for child in value.values()
        )
    if isinstance(value, list):
        return any(v1_contains_tag(child, tag) for child in value)
    return False


def v1_contains_field(value: Any, field: str) -> bool:
    if isinstance(value, dict):
        return field in value or any(
            v1_contains_field(child, field) for child in value.values()
        )
    if isinstance(value, list):
        return any(v1_contains_field(child, field) for child in value)
    return False


def v1_contract_features(contract: Mapping[str, Any]) -> List[str]:
    features: set[str] = set()
    declaration_kind = contract.get("declaration_kind")
    visible_row = (
        declaration_kind.get("visible_row")
        if isinstance(declaration_kind, dict)
        else None
    )
    if isinstance(visible_row, dict) and visible_row.get("kind") != "EmptyV1":
        features.add("explicit-row")
    if v1_contains_tag(contract, "NamedV1"):
        features.add("explicit-named-row")
    if (
        v1_contains_tag(contract, "CapabilityTypeV2")
        and v1_contains_tag(contract, "NamedV1")
        and any(
            isinstance(binder, dict) and binder.get("binder") == "FreshCap"
            for binder in contract.get("binders", {}).get(
                "identity_binders", []
            )
        )
    ):
        features.add("direct-capability-identity")
    if v1_contains_tag(contract, "ParkContractV2") or v1_contains_field(
        contract, "park_contract"
    ):
        features.add("park")
    if v1_contains_tag(contract, "TransfersV2"):
        features.add("transfers")
    if (
        v1_contains_tag(contract, "HandlerContractV2")
        or v1_contains_tag(contract, "HandlerTemplateTypeV2")
        or v1_contains_field(contract, "handler_contract")
    ):
        features.add("handler")
    if v1_contains_tag(contract, "ContractParameterRefV2"):
        features.add("higher-order-contract-parameter")
    if v1_contains_tag(contract, "ImportedCallableSlotRefV3"):
        features.add("imported-callable-slot")
    if v1_contains_tag(contract, "LocalFunctionRefV2"):
        features.add("local-call")
    if v1_contains_tag(contract, "FunctionTypeV2") and len(
        contract.get("callable_dependencies", [])
    ) >= 2:
        features.add("higher-order-import")
    if contract.get("local_declarations"):
        features.add("deterministic-local-slots")
    if contract.get("default_prologues"):
        features.add("default-prologue")
    if v1_contains_tag(contract, "ApplyTypeV2") and any(
        isinstance(node, dict)
        and node.get("kind") == "NominalConstructorV1"
        and node.get("name") == "ProvidedOrOmitted"
        for node in _walk_values(contract)
    ):
        features.add("provided-or-omitted")
    return sorted(features)


def _walk_values(value: Any) -> Iterable[Any]:
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_values(child)


V3_SUITE_CASE_ORDER = [
    "apply-later-hof-callee",
    "choose-once-import-leaf",
    "default-prologue",
    "direct-capability-identity",
    "mixed-next-park",
    "named-row",
    "local-declaration",
    "handler-forward",
    "hof-import-caller",
]

V3_DIFFERENTIAL_ORDER = [
    "alpha-rename-stability",
    "cache-equivalence-collision",
    "default-change-cascade",
    "direct-capability-drift-rejection",
    "public-label-cascade",
    "public-cycle-rejection",
    "reversed-order-determinism",
    "whole-program-imported-equality",
]


def v1_suite_interface(
    case: Mapping[str, Any],
    *,
    contract: Any | None = None,
    surface_signature: Any | None = None,
) -> Dict[str, Any]:
    contract = case["contract"] if contract is None else contract
    surface_signature = (
        case["surface_signature"]
        if surface_signature is None
        else surface_signature
    )
    return {
        "artifact": "CallableInterfaceV1",
        "profile": PROFILE,
        "schema_version": 1,
        "module": copy.deepcopy(case["module"]),
        "export_path": copy.deepcopy(case["export_path"]),
        "core_contract": {
            "artifact": "FunctionContractV3",
            "hash_algorithm": HASH_ALGORITHM,
            "artifact_hash": object_hash(contract),
        },
        "surface_signature": copy.deepcopy(surface_signature),
    }


def v1_rewrite_import_slots(value: Any, mapping: Mapping[int, int]) -> Any:
    if isinstance(value, dict):
        if value.get("kind") == "ImportedCallableSlotRefV3":
            return {
                "kind": "ImportedCallableSlotRefV3",
                "import_slot": mapping[value["import_slot"]],
            }
        return {
            key: v1_rewrite_import_slots(child, mapping)
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [v1_rewrite_import_slots(child, mapping) for child in value]
    return copy.deepcopy(value)


def v1_rebuild_dependency_table(
    contract: Mapping[str, Any],
    dependency_cases: Sequence[Mapping[str, Any]],
) -> Dict[str, Any]:
    rebuilt = copy.deepcopy(contract)
    old_dependencies = v1_validate_callable_dependencies(
        rebuilt["callable_dependencies"]
    )
    old_by_hash = {
        dependency["interface_hash"]: dependency["import_slot"]
        for dependency in old_dependencies
    }
    candidates = [
        {
            "module": copy.deepcopy(case["module"]),
            "export_path": copy.deepcopy(case["export_path"]),
            "interface_hash": case["callable_interface_hash"],
        }
        for case in dependency_cases
    ]
    candidates.sort(key=canonical_bytes)
    if {item["interface_hash"] for item in candidates} != set(old_by_hash):
        fail(
            "callable-interface-contract-mismatch",
            "dependency rebuild candidates differ from the caller graph",
        )
    new_dependencies = [
        {"import_slot": slot, **copy.deepcopy(candidate)}
        for slot, candidate in enumerate(candidates)
    ]
    new_by_hash = {
        dependency["interface_hash"]: dependency["import_slot"]
        for dependency in new_dependencies
    }
    slot_mapping = {
        old_slot: new_by_hash[interface_hash]
        for interface_hash, old_slot in old_by_hash.items()
    }
    rebuilt = v1_rewrite_import_slots(rebuilt, slot_mapping)
    rebuilt["callable_dependencies"] = new_dependencies
    return rebuilt


def v1_alpha_rename_parameters(
    contract: Mapping[str, Any], renaming: Mapping[int, int]
) -> Dict[str, Any]:
    def rewrite(value: Any, mapping: Mapping[int, int]) -> Any:
        if isinstance(value, dict):
            if value.get("namespace") == "Parameter" and set(value) == {
                "namespace",
                "slot",
            }:
                slot = value["slot"]
                return {
                    "namespace": "Parameter",
                    "slot": mapping.get(slot, slot),
                }
            return {key: rewrite(child, mapping) for key, child in value.items()}
        if isinstance(value, list):
            return [rewrite(child, mapping) for child in value]
        return copy.deepcopy(value)

    result = rewrite(contract, renaming)
    binders = result["binders"]["parameter_binders"]
    for binder in binders:
        binder["slot"] = renaming.get(binder["slot"], binder["slot"])
    return result


def v1_canonicalize_parameter_slots(contract: Mapping[str, Any]) -> Dict[str, Any]:
    slots = [
        binder["slot"] for binder in contract["binders"]["parameter_binders"]
    ]
    if len(slots) != len(set(slots)):
        fail(
            "callable-interface-contract-mismatch",
            "alpha-renamed parameter slots collide",
        )
    return v1_alpha_rename_parameters(
        contract, {slot: canonical for canonical, slot in enumerate(slots)}
    )


def v1_replace_dependency_hash(
    contract: Mapping[str, Any], old_hash: str, new_hash: str
) -> Dict[str, Any]:
    result = copy.deepcopy(contract)
    matches = 0
    for dependency in result["callable_dependencies"]:
        if dependency["interface_hash"] == old_hash:
            dependency["interface_hash"] = new_hash
            matches += 1
    if matches != 1:
        fail(
            "callable-interface-contract-mismatch",
            "caller does not have exactly one requested cascade edge",
        )
    return result


def v1_retarget_imported_callee(
    contract: Mapping[str, Any],
    import_slot: int,
    parameter_slot: int,
    input_type: Mapping[str, Any],
) -> Dict[str, Any]:
    result = copy.deepcopy(contract)

    def rewrite(value: Any) -> None:
        if isinstance(value, dict):
            reference = value.get("contract")
            matches = (
                isinstance(reference, dict)
                and reference.get("kind") == "ImportedCallableSlotRefV3"
                and reference.get("import_slot") == import_slot
            )
            if value.get("kind") == "FunctionTypeV2" and matches:
                entry_types = v1_call_entry_types(value["parameter"])
                if parameter_slot >= len(entry_types):
                    fail(
                        "callable-interface-contract-mismatch",
                        "retargeted callee slot is absent",
                    )
                entry_types[parameter_slot] = copy.deepcopy(input_type)
                value["parameter"]["arguments"] = entry_types
            if "application_slot" in value and matches and "actual_arguments" in value:
                actuals = value["actual_arguments"]
                if parameter_slot >= len(actuals):
                    fail(
                        "callable-interface-contract-mismatch",
                        "default cascade application slot is absent",
                    )
                actual = actuals[parameter_slot]
                actual["type"] = copy.deepcopy(input_type)
                actual["source"] = None
                actual["nominal_index"] = {
                    "kind": "LegacyNominalIndexExprV2",
                    "value": {"kind": "NoNominalIndexV1"},
                }
                actual["provenance"] = {
                    "kind": "LegacyProvenanceExprV2",
                    "value": {"kind": "StableV1"},
                }
                actual["capture"] = {
                    "kind": "LegacyCaptureExprV2",
                    "value": {"kind": "NoCaptureV1"},
                }
                actual["usage"] = None
            for child in value.values():
                rewrite(child)
        elif isinstance(value, list):
            for child in value:
                rewrite(child)

    rewrite(result)
    return result


def v1_constant_default_computation() -> Dict[str, Any]:
    return {
        "kind": "LiteralPathsV2",
        "paths": [
            {
                "LatentSites": [],
                "ParametricObligations": [],
                "attributed_demand": [],
                "outcome": {
                    "kind": "ReturnsV2",
                    "result_transformer": {
                        "kind": "LegacyResultTransformerV2",
                        "value": {
                            "capture": {"kind": "NoCaptureV1"},
                            "kind": "ParametricResultV1",
                            "provenance": {"kind": "StableV1"},
                        },
                    },
                    "transition": {"kind": "SameWorldV1"},
                },
                "required_phase": {
                    "allowed_phases": ["Pure", "Compute", "Action", "Commit"],
                    "current_owner": None,
                    "required_authorities": [],
                },
                "residual_row": {"kind": "EmptyV1"},
                "semantic_summary": {"kind": "PureV1"},
                "suspension": {"atoms": [], "grade": "NoSuspend"},
                "usage": [],
            }
        ],
    }


def v1_add_default(
    case: Mapping[str, Any], parameter_slot: int, origin: str
) -> tuple[Dict[str, Any], Dict[str, Any]]:
    contract = copy.deepcopy(case["contract"])
    surface = copy.deepcopy(case["surface_signature"])
    parameter_binders = contract["binders"]["parameter_binders"]
    if parameter_slot >= len(parameter_binders):
        fail(
            "callable-interface-contract-mismatch",
            "default differential parameter slot is absent",
        )
    output_type = copy.deepcopy(parameter_binders[parameter_slot]["type"])
    if isinstance(output_type, dict) and output_type.get("kind") == "CapabilityTypeV2":
        fail(
            "callable-interface-contract-mismatch",
            "direct capability binder cannot receive a default",
        )
    input_type = v1_provided_or_omitted(output_type)
    entry_types = v1_call_entry_types(
        contract["declaration_kind"]["parameter_type"]
    )
    entry_types[parameter_slot] = copy.deepcopy(input_type)
    contract["declaration_kind"]["parameter_type"]["arguments"] = entry_types
    parameter_binders[parameter_slot]["type"] = copy.deepcopy(input_type)
    contract["default_prologues"].append(
        {
            "kind": "DefaultPrologueV1",
            "parameter_slot": parameter_slot,
            "input_type": copy.deepcopy(input_type),
            "output_type": output_type,
            "computation": v1_constant_default_computation(),
            "origin": origin,
        }
    )
    contract["default_prologues"].sort(key=lambda item: item["parameter_slot"])
    surface["slots"][parameter_slot]["defaultable"] = True
    return contract, surface


def v1_reverse_mapping_order(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: v1_reverse_mapping_order(value[key])
            for key in reversed(list(value))
        }
    if isinstance(value, list):
        return [v1_reverse_mapping_order(child) for child in value]
    return copy.deepcopy(value)


def v1_public_graph_has_cycle(edges: Sequence[Sequence[str]]) -> bool:
    graph: Dict[str, set[str]] = {}
    for edge in edges:
        if not isinstance(edge, list) or len(edge) != 2:
            fail("Decode/array-mismatch", "public graph edge is not a pair")
        source = v1_string(edge[0], "public graph source")
        target = v1_string(edge[1], "public graph target")
        graph.setdefault(source, set()).add(target)
        graph.setdefault(target, set())
    indegree = {node: 0 for node in graph}
    for targets in graph.values():
        for target in targets:
            indegree[target] += 1
    ready = deque(sorted(node for node, degree in indegree.items() if degree == 0))
    visited = 0
    while ready:
        node = ready.popleft()
        visited += 1
        for target in sorted(graph[node]):
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
    return visited != len(graph)


def v1_validate_direct_capability_case(
    value: Any,
    *,
    cases_by_id: Mapping[str, Mapping[str, Any]],
) -> None:
    binding = v1_closed(
        value,
        ["case", "source_parameter_slot", "role", "identity_slot"],
        "DirectCapabilityBindingV1",
    )
    case_id = v1_string(binding["case"], "direct capability case")
    if case_id not in cases_by_id:
        fail(
            "capability-identity-required",
            "direct capability case is absent",
        )
    if binding["role"] != "DirectV1":
        fail(
            "capability-identity-required",
            "capability parameter role is not DirectV1",
        )
    parameter_slot = v1_u32(
        binding["source_parameter_slot"],
        "direct capability source parameter slot",
    )
    identity_slot = v1_u32(
        binding["identity_slot"], "direct capability identity slot"
    )
    case = cases_by_id[case_id]
    signature = v1_closed(
        case["surface_signature"],
        ["kind", "slots"],
        "direct capability surface signature",
    )
    surface_slots = require_list(
        signature["slots"],
        "Decode/array-mismatch",
        "direct capability surface slots",
    )
    matching_surface = [
        slot
        for slot in surface_slots
        if isinstance(slot, dict) and slot.get("slot") == parameter_slot
    ]
    if len(matching_surface) != 1:
        fail(
            "capability-identity-required",
            "direct capability source slot is not unique",
        )
    surface_slot = v1_closed(
        matching_surface[0],
        ["slot", "passing", "public_label", "defaultable"],
        "direct capability surface slot",
    )
    if surface_slot["defaultable"] is not False:
        fail(
            "capability-binder-default-not-in-v1",
            "direct capability parameter is defaultable",
        )
    if surface_slot["passing"] != "NamedOrPositionalV1":
        fail(
            "capability-identity-required",
            "direct capability parameter has the wrong passing role",
        )
    contract = case["contract"]
    parameter_binders = require_list(
        contract["binders"]["parameter_binders"],
        "Decode/array-mismatch",
        "direct capability parameter binders",
    )
    matching_parameters = [
        binder
        for binder in parameter_binders
        if isinstance(binder, dict) and binder.get("slot") == parameter_slot
    ]
    if len(matching_parameters) != 1:
        fail(
            "capability-identity-required",
            "direct capability parameter binder is absent or duplicated",
        )
    parameter = v1_closed(
        matching_parameters[0],
        ["slot", "type"],
        "direct capability parameter binder",
    )
    capability_type = v1_closed(
        parameter["type"],
        ["kind", "identity", "family"],
        "direct capability parameter type",
    )
    identity_ref = v1_closed(
        capability_type["identity"],
        ["namespace", "slot"],
        "direct capability parameter identity",
    )
    if capability_type["kind"] != "CapabilityTypeV2" or identity_ref != {
        "namespace": "Identity",
        "slot": identity_slot,
    }:
        fail(
            "capability-identity-required",
            "direct capability parameter is not Cap[i,F]",
        )
    declaration_parameters = v1_call_entry_types(
        contract["declaration_kind"]["parameter_type"]
    )
    if (
        parameter_slot >= len(declaration_parameters)
        or declaration_parameters[parameter_slot] != capability_type
    ):
        fail(
            "capability-identity-required",
            "surface slot and declaration Cap[i,F] slot differ",
        )
    identity_binders = require_list(
        contract["binders"]["identity_binders"],
        "Decode/array-mismatch",
        "direct capability identity binders",
    )
    matching_identities = [
        binder
        for binder in identity_binders
        if isinstance(binder, dict)
        and binder.get("identity_slot") == identity_slot
    ]
    if len(matching_identities) != 1:
        fail(
            "capability-identity-required",
            "direct capability identity binder is absent or duplicated",
        )
    identity_binder = v1_closed(
        matching_identities[0],
        ["identity_slot", "family", "owner", "binder"],
        "direct capability identity binder",
    )
    if (
        identity_binder["binder"] != "FreshCap"
        or identity_binder["family"] != capability_type["family"]
    ):
        fail(
            "capability-identity-required",
            "direct capability does not use the same FreshCap family",
        )
    expected_projection = {
        "kind": "NamedV1",
        "identity": {"namespace": "Identity", "slot": identity_slot},
        "family": copy.deepcopy(capability_type["family"]),
    }
    projections: List[Mapping[str, Any]] = []

    def collect_named(item: Any) -> None:
        if isinstance(item, dict):
            if item.get("kind") == "NamedV1":
                projections.append(
                    v1_closed(
                        item,
                        ["kind", "identity", "family"],
                        "direct capability Named-row projection",
                    )
                )
            for child in item.values():
                collect_named(child)
        elif isinstance(item, list):
            for child in item:
                collect_named(child)

    collect_named(contract["declaration_kind"]["visible_row"])
    collect_named(contract["computation"])
    if len(projections) != 2 or any(
        projection != expected_projection for projection in projections
    ):
        fail(
            "capability-identity-required",
            "direct capability Named-row projection differs",
        )
    if any(
        prologue.get("parameter_slot") == parameter_slot
        for prologue in require_list(
            contract["default_prologues"],
            "Decode/array-mismatch",
            "direct capability default prologues",
        )
        if isinstance(prologue, dict)
    ):
        fail(
            "capability-binder-default-not-in-v1",
            "direct capability has a default prologue",
        )


def v1_validate_v3_differentials(
    value: Any,
    *,
    cases_by_id: Mapping[str, Mapping[str, Any]],
    legacy_by_interface: Mapping[str, Dict[str, Any]],
    direct_capability_binding: Mapping[str, Any],
) -> None:
    differentials = require_list(
        value, "Decode/array-mismatch", "V3 differentials"
    )
    if [
        item.get("id") for item in differentials if isinstance(item, dict)
    ] != V3_DIFFERENTIAL_ORDER:
        fail(
            "callable-interface-contract-mismatch",
            "V3 differential IDs/order differ",
        )
    for differential_value in differentials:
        differential = v1_closed(
            differential_value,
            ["id", "kind", "inputs", "expected"],
            "FunctionContractV3DifferentialV1",
        )
        kind = differential["kind"]
        inputs = differential["inputs"]
        expected = differential["expected"]
        if kind == "AlphaRenameStabilityV1":
            item = v1_closed(
                inputs,
                ["case", "parameter_slot_renaming"],
                "AlphaRenameStabilityV1.inputs",
            )
            result = v1_closed(
                expected,
                ["contract_hash", "callable_interface_hash"],
                "AlphaRenameStabilityV1.expected",
            )
            case = cases_by_id[item["case"]]
            pairs = require_list(
                item["parameter_slot_renaming"],
                "Decode/array-mismatch",
                "alpha parameter renaming",
            )
            if pairs != [{"from": 0, "to": 17}, {"from": 1, "to": 3}]:
                fail(
                    "callable-interface-contract-mismatch",
                    "alpha parameter renaming vector is not canonical",
                )
            renaming: Dict[int, int] = {}
            for pair_value in pairs:
                pair = v1_closed(
                    pair_value, ["from", "to"], "AlphaParameterSlotRenameV1"
                )
                source = v1_u32(pair["from"], "alpha source slot")
                target = v1_u32(pair["to"], "alpha target slot")
                if source in renaming or target in renaming.values():
                    fail(
                        "callable-interface-contract-mismatch",
                        "alpha parameter renaming is not injective",
                    )
                renaming[source] = target
            alpha = v1_alpha_rename_parameters(case["contract"], renaming)
            canonical = v1_canonicalize_parameter_slots(alpha)
            if canonical != case["contract"]:
                fail(
                    "callable-interface-contract-mismatch",
                    "alpha-renamed contract did not canonicalize to identical bytes",
                )
            observed = {
                "contract_hash": object_hash(canonical),
                "callable_interface_hash": object_hash(
                    v1_suite_interface(case, contract=canonical)
                ),
            }
            if result != observed:
                fail(
                    "callable-interface-contract-mismatch",
                    "alpha-renaming differential golden differs",
                )
        elif kind == "PublicLabelCascadeV1":
            item = v1_closed(
                inputs,
                [
                    "callee_case",
                    "caller_case",
                    "parameter_slot",
                    "new_public_label",
                ],
                "PublicLabelCascadeV1.inputs",
            )
            result = v1_closed(
                expected,
                [
                    "callee_contract_hash",
                    "callee_interface_hash",
                    "caller_contract_hash",
                    "caller_interface_hash",
                ],
                "PublicLabelCascadeV1.expected",
            )
            callee = cases_by_id[item["callee_case"]]
            caller = cases_by_id[item["caller_case"]]
            slot = v1_u32(item["parameter_slot"], "renamed public-label slot")
            label = v1_string(item["new_public_label"], "renamed public label")
            surface = copy.deepcopy(callee["surface_signature"])
            if slot >= len(surface["slots"]):
                fail(
                    "callable-interface-contract-mismatch",
                    "renamed public-label slot is absent",
                )
            surface["slots"][slot]["public_label"] = label
            callee_contract_hash = object_hash(callee["contract"])
            callee_interface_hash = object_hash(
                v1_suite_interface(callee, surface_signature=surface)
            )
            caller_contract = v1_replace_dependency_hash(
                caller["contract"],
                callee["callable_interface_hash"],
                callee_interface_hash,
            )
            caller_contract_hash = object_hash(caller_contract)
            caller_interface_hash = object_hash(
                v1_suite_interface(caller, contract=caller_contract)
            )
            if (
                callee_contract_hash != callee["contract_hash"]
                or callee_interface_hash == callee["callable_interface_hash"]
                or caller_contract_hash == caller["contract_hash"]
                or caller_interface_hash == caller["callable_interface_hash"]
            ):
                fail(
                    "callable-interface-contract-mismatch",
                    "public-label hash cascade did not propagate exactly",
                )
            extended = dict(legacy_by_interface)
            extended[callee_interface_hash] = legacy_by_interface[
                callee["callable_interface_hash"]
            ]
            v1_validate_function_contract(
                caller_contract,
                dependency_legacy=extended,
                surface_signature=caller["surface_signature"],
            )
            if result != {
                "callee_contract_hash": callee_contract_hash,
                "callee_interface_hash": callee_interface_hash,
                "caller_contract_hash": caller_contract_hash,
                "caller_interface_hash": caller_interface_hash,
            }:
                fail(
                    "callable-interface-contract-mismatch",
                    "public-label cascade golden differs",
                )
        elif kind == "DefaultChangeCascadeV1":
            item = v1_closed(
                inputs,
                ["callee_case", "caller_case", "parameter_slot", "origin"],
                "DefaultChangeCascadeV1.inputs",
            )
            result = v1_closed(
                expected,
                [
                    "callee_contract_hash",
                    "callee_interface_hash",
                    "caller_contract_hash",
                    "caller_interface_hash",
                ],
                "DefaultChangeCascadeV1.expected",
            )
            callee = cases_by_id[item["callee_case"]]
            caller = cases_by_id[item["caller_case"]]
            slot = v1_u32(item["parameter_slot"], "default cascade slot")
            origin = v1_string(item["origin"], "default cascade origin")
            callee_contract, callee_surface = v1_add_default(
                callee, slot, origin
            )
            retained = v1_validate_function_contract(
                callee_contract,
                dependency_legacy=legacy_by_interface,
                surface_signature=callee_surface,
            )
            callee_contract_hash = object_hash(callee_contract)
            callee_interface_hash = object_hash(
                v1_suite_interface(
                    callee,
                    contract=callee_contract,
                    surface_signature=callee_surface,
                )
            )
            caller_dependency = next(
                dependency
                for dependency in caller["contract"]["callable_dependencies"]
                if dependency["interface_hash"]
                == callee["callable_interface_hash"]
            )
            retargeted_caller = v1_retarget_imported_callee(
                caller["contract"],
                caller_dependency["import_slot"],
                slot,
                callee_contract["binders"]["parameter_binders"][slot]["type"],
            )
            caller_contract = v1_replace_dependency_hash(
                retargeted_caller,
                callee["callable_interface_hash"],
                callee_interface_hash,
            )
            extended = dict(legacy_by_interface)
            extended[callee_interface_hash] = retained
            v1_validate_function_contract(
                caller_contract,
                dependency_legacy=extended,
                surface_signature=caller["surface_signature"],
            )
            observed = {
                "callee_contract_hash": callee_contract_hash,
                "callee_interface_hash": callee_interface_hash,
                "caller_contract_hash": object_hash(caller_contract),
                "caller_interface_hash": object_hash(
                    v1_suite_interface(caller, contract=caller_contract)
                ),
            }
            if (
                observed["callee_contract_hash"] == callee["contract_hash"]
                or observed["callee_interface_hash"]
                == callee["callable_interface_hash"]
                or observed["caller_contract_hash"] == caller["contract_hash"]
                or observed["caller_interface_hash"]
                == caller["callable_interface_hash"]
                or result != observed
            ):
                fail(
                    "callable-interface-contract-mismatch",
                    "default-change hash cascade differs",
                )
        elif kind == "DirectCapabilityDriftRejectionV1":
            item = v1_closed(
                inputs,
                ["case", "defaultability_value", "identity_drift_slot"],
                "DirectCapabilityDriftRejectionV1.inputs",
            )
            result = v1_closed(
                expected,
                ["defaultability_failure", "identity_failure"],
                "DirectCapabilityDriftRejectionV1.expected",
            )
            for field in ("defaultability_failure", "identity_failure"):
                v1_closed(
                    result[field],
                    ["kind", "id"],
                    "DirectCapabilityDriftRejectionV1." + field,
                )
            if item["case"] != direct_capability_binding["case"]:
                fail(
                    "capability-identity-required",
                    "direct capability differential selects another case",
                )
            if item["defaultability_value"] is not True:
                fail(
                    "Decode/boolean-mismatch",
                    "direct capability defaultability mutation is not true",
                )
            identity_drift_slot = v1_u32(
                item["identity_drift_slot"],
                "direct capability drift identity slot",
            )
            if identity_drift_slot == direct_capability_binding["identity_slot"]:
                fail(
                    "capability-identity-required",
                    "direct capability identity mutation does not drift",
                )

            def observed_failure(mutated_case: Mapping[str, Any]) -> Dict[str, str]:
                mutated_cases = dict(cases_by_id)
                mutated_cases[item["case"]] = mutated_case
                try:
                    v1_validate_direct_capability_case(
                        direct_capability_binding,
                        cases_by_id=mutated_cases,
                    )
                except ValidationFailure as error:
                    return {"kind": "DiagnosticV1", "id": error.diagnostic}
                fail(
                    "callable-interface-contract-mismatch",
                    "direct capability drift unexpectedly validated",
                )

            defaultable_case = copy.deepcopy(cases_by_id[item["case"]])
            parameter_slot = direct_capability_binding[
                "source_parameter_slot"
            ]
            next(
                slot
                for slot in defaultable_case["surface_signature"]["slots"]
                if slot["slot"] == parameter_slot
            )["defaultable"] = item["defaultability_value"]
            identity_case = copy.deepcopy(cases_by_id[item["case"]])
            next(
                binder
                for binder in identity_case["contract"]["binders"][
                    "parameter_binders"
                ]
                if binder["slot"] == parameter_slot
            )["type"]["identity"]["slot"] = identity_drift_slot
            declaration_parameters = v1_call_entry_types(
                identity_case["contract"]["declaration_kind"][
                    "parameter_type"
                ]
            )
            declaration_parameters[parameter_slot]["identity"][
                "slot"
            ] = identity_drift_slot
            observed = {
                "defaultability_failure": observed_failure(defaultable_case),
                "identity_failure": observed_failure(identity_case),
            }
            if result != observed:
                fail(
                    "callable-interface-contract-mismatch",
                    "direct capability drift diagnostics differ",
                )
        elif kind in {
            "ReverseOrderDeterminismV1",
            "WholeProgramImportedEqualityV1",
        }:
            item = v1_closed(
                inputs,
                ["caller_case", "dependency_cases"],
                kind + ".inputs",
            )
            result = v1_closed(
                expected,
                ["contract_hash", "byte_equal"],
                kind + ".expected",
            )
            caller = cases_by_id[item["caller_case"]]
            dependency_ids = require_list(
                item["dependency_cases"],
                "Decode/array-mismatch",
                "differential dependency cases",
            )
            expected_dependency_ids = (
                ["mixed-next-park", "apply-later-hof-callee"]
                if kind == "ReverseOrderDeterminismV1"
                else ["apply-later-hof-callee", "mixed-next-park"]
            )
            if dependency_ids != expected_dependency_ids:
                fail(
                    "callable-interface-contract-mismatch",
                    kind + " dependency vector is not canonical",
                )
            dependencies = [cases_by_id[case_id] for case_id in dependency_ids]
            rebuilt = v1_rebuild_dependency_table(caller["contract"], dependencies)
            byte_equal = canonical_bytes(rebuilt) == canonical_bytes(
                caller["contract"]
            )
            if kind == "WholeProgramImportedEqualityV1":
                for dependency in rebuilt["callable_dependencies"]:
                    resolved = next(
                        (
                            case
                            for case in dependencies
                            if case["callable_interface_hash"]
                            == dependency["interface_hash"]
                        ),
                        None,
                    )
                    if resolved is None or object_hash(
                        v1_suite_interface(resolved)
                    ) != dependency["interface_hash"]:
                        fail(
                            "callable-interface-contract-mismatch",
                            "imported interface does not equal whole-program envelope",
                        )
            observed = {
                "contract_hash": object_hash(rebuilt),
                "byte_equal": byte_equal,
            }
            if not byte_equal or result != observed:
                fail(
                    "callable-interface-contract-mismatch",
                    kind + " differs",
                )
        elif kind == "CacheEquivalenceCollisionV1":
            item = v1_closed(
                inputs,
                ["equivalent_case", "collision_case", "forced_cache_key"],
                "CacheEquivalenceCollisionV1.inputs",
            )
            result = v1_closed(
                expected,
                ["equivalent_hash", "collision_failure"],
                "CacheEquivalenceCollisionV1.expected",
            )
            equivalent = cases_by_id[item["equivalent_case"]]["contract"]
            collision = cases_by_id[item["collision_case"]]["contract"]
            reordered = v1_reverse_mapping_order(equivalent)
            equivalent_hash = object_hash(reordered)
            if (
                canonical_bytes(reordered) != canonical_bytes(equivalent)
                or equivalent_hash != object_hash(equivalent)
            ):
                fail(
                    "callable-interface-contract-mismatch",
                    "canonical cache equivalence differs under map insertion order",
                )
            forced_key = item["forced_cache_key"]
            if forced_key != object_hash(equivalent):
                fail(
                    "callable-interface-contract-mismatch",
                    "cache differential key is not the semantic hash",
                )
            cache = {forced_key: canonical_bytes(equivalent)}
            collision_rejected = cache[forced_key] != canonical_bytes(collision)
            failure = {
                "kind": "DiagnosticV1",
                "id": "callable-interface-contract-mismatch",
            }
            if (
                not collision_rejected
                or result
                != {
                    "equivalent_hash": equivalent_hash,
                    "collision_failure": failure,
                }
            ):
                fail(
                    "callable-interface-contract-mismatch",
                    "semantic cache collision was not rejected",
                )
        elif kind == "PublicCallableCycleRejectionV1":
            item = v1_closed(
                inputs, ["edges"], "PublicCallableCycleRejectionV1.inputs"
            )
            result = v1_closed(
                expected,
                ["failure"],
                "PublicCallableCycleRejectionV1.expected",
            )
            failure = {
                "kind": "DiagnosticV1",
                "id": "recursive-public-callable-scc-not-in-v1",
            }
            edges = require_list(
                item["edges"], "Decode/array-mismatch", "public graph edges"
            )
            if edges != [["cycle-a", "cycle-b"], ["cycle-b", "cycle-a"]]:
                fail(
                    "callable-interface-contract-mismatch",
                    "public callable graph vector is not canonical",
                )
            if not v1_public_graph_has_cycle(edges) or result != {
                "failure": failure
            }:
                fail(
                    "callable-interface-contract-mismatch",
                    "public callable cycle was not rejected",
                )
        else:
            fail(
                "Decode/tag-mismatch",
                "unknown FunctionContractV3 differential kind",
            )


def build_effect_constructor_controls() -> Dict[str, Any]:
    return {
        "applications": [
            {
                "kind": "ApplyTypeV2",
                "constructor": {
                    "kind": "EffectParameterConstructorV3",
                    "binder_slot": 0,
                    "constructor_arity": 1,
                },
                "arguments": [v1_legacy_builtin("Int")],
            },
            {
                "kind": "ApplyTypeV2",
                "constructor": {
                    "kind": "EffectParameterConstructorV3",
                    "binder_slot": 1,
                    "constructor_arity": 1,
                },
                "arguments": [v1_legacy_builtin("String")],
            },
        ],
        "binders": [
            {"constructor_arity": 1, "kind": "EffectConstructorV3", "slot": 0},
            {"constructor_arity": 1, "kind": "EffectConstructorV3", "slot": 1},
        ],
        "substitutions": [
            {
                "binder_slot": 0,
                "constructor": {
                    "constructor_arity": 1,
                    "effect": copy.deepcopy(EFFECT_IDENTITY),
                    "kind": "NominalEffectConstructorActualV1",
                },
                "kind": "EffectConstructorSubstitutionV3",
            },
            {
                "binder_slot": 1,
                "constructor": {
                    "binder_slot": 0,
                    "constructor_arity": 1,
                    "kind": "EffectConstructorParameterActualV1",
                },
                "kind": "EffectConstructorSubstitutionV3",
            },
        ],
    }


def v1_validate_effect_constructor_controls(value: Any) -> None:
    controls = v1_closed(
        value,
        ["applications", "binders", "substitutions"],
        "EffectConstructorControlsV1",
    )
    binders = require_list(
        controls["binders"],
        "Decode/array-mismatch",
        "effect constructor control binders",
    )
    binder_table: Dict[int, Dict[str, Any]] = {}
    for expected_slot, binder_value in enumerate(binders):
        binder = v1_closed(
            binder_value,
            ["constructor_arity", "kind", "slot"],
            "EffectConstructorBinderV3",
        )
        slot = v1_u32(binder["slot"], "effect constructor binder slot")
        arity = v1_u32(
            binder["constructor_arity"], "effect constructor binder arity"
        )
        if binder["kind"] != "EffectConstructorV3" or slot != expected_slot or arity != 1:
            fail(
                "contract-component-kind-mismatch",
                "effect constructor control binder differs",
            )
        binder_table[slot] = dict(binder)
    if len(binder_table) != 2:
        fail(
            "contract-component-kind-mismatch",
            "effect constructor control binder coverage differs",
        )
    applications = require_list(
        controls["applications"],
        "Decode/array-mismatch",
        "effect constructor control applications",
    )
    if len(applications) != 2:
        fail(
            "contract-component-kind-mismatch",
            "effect constructor application coverage differs",
        )
    for index, application in enumerate(applications):
        v1_validate_effect_constructor_references(
            application,
            binder_table,
            "effect constructor control application " + str(index),
        )
    substitutions = require_list(
        controls["substitutions"],
        "Decode/array-mismatch",
        "effect constructor substitutions",
    )
    if len(substitutions) != 2:
        fail(
            "contract-component-kind-mismatch",
            "effect constructor substitution branch coverage differs",
        )
    seen_slots: List[int] = []
    seen_actual_kinds: List[str] = []
    for substitution_value in substitutions:
        substitution = v1_closed(
            substitution_value,
            ["binder_slot", "constructor", "kind"],
            "EffectConstructorSubstitutionV3",
        )
        if substitution["kind"] != "EffectConstructorSubstitutionV3":
            fail("Decode/tag-mismatch", "wrong effect constructor substitution tag")
        slot = v1_u32(
            substitution["binder_slot"],
            "effect constructor substitution binder slot",
        )
        target = binder_table.get(slot)
        if target is None:
            fail(
                "contract-component-kind-mismatch",
                "effect constructor substitution target is absent",
            )
        constructor = substitution["constructor"]
        if not isinstance(constructor, dict):
            fail(
                "Decode/object-mismatch",
                "effect constructor substitution actual is not an object",
            )
        actual_kind = constructor.get("kind")
        if actual_kind == "NominalEffectConstructorActualV1":
            actual = v1_closed(
                constructor,
                ["constructor_arity", "effect", "kind"],
                actual_kind,
            )
            if actual["effect"] != EFFECT_IDENTITY:
                fail(
                    "contract-component-kind-mismatch",
                    "nominal effect constructor does not resolve to the package Effect declaration",
                )
        elif actual_kind == "EffectConstructorParameterActualV1":
            actual = v1_closed(
                constructor,
                ["binder_slot", "constructor_arity", "kind"],
                actual_kind,
            )
            actual_slot = v1_u32(
                actual["binder_slot"],
                "effect constructor parameter actual slot",
            )
            if actual_slot == slot or actual_slot not in binder_table:
                fail(
                    "contract-component-kind-mismatch",
                    "effect constructor parameter actual is not another in-scope binder",
                )
        else:
            fail("Decode/tag-mismatch", "unknown effect constructor actual tag")
        if v1_u32(actual["constructor_arity"], "effect constructor actual arity") != target["constructor_arity"]:
            fail(
                "contract-component-kind-mismatch",
                "effect constructor substitution arity differs",
            )
        seen_slots.append(slot)
        seen_actual_kinds.append(actual_kind)
    if seen_slots != [0, 1] or seen_actual_kinds != [
        "NominalEffectConstructorActualV1",
        "EffectConstructorParameterActualV1",
    ]:
        fail(
            "contract-component-kind-mismatch",
            "effect constructor substitution order/variant coverage differs",
        )
    if controls != build_effect_constructor_controls():
        fail(
            "contract-component-kind-mismatch",
            "effect constructor controls differ from deterministic generation",
        )


def build_lambda_lifting_controls() -> Dict[str, Any]:
    sources = [
        {
            "source_ordinal": 0,
            "source_kind": "OrdinaryLambdaExprV1",
            "generic": False,
        },
        {
            "source_ordinal": 1,
            "source_kind": "GenericLambdaExprV1",
            "generic": True,
        },
    ]
    return {
        "root_declaration_slot": 0,
        "source_nodes": sources,
        "lifted_declarations": [
            {
                "source_ordinal": source["source_ordinal"],
                "declaration_slot": source["source_ordinal"] + 1,
                "scheme": "Rank1ImmutableSimpleNameV1"
                if source["generic"]
                else "MonomorphicLambdaV1",
                "reference": {
                    "kind": "LocalFunctionRefV2",
                    "declaration_slot": source["source_ordinal"] + 1,
                },
                "nested_function_contract_v3_roots": 0,
            }
            for source in sources
        ],
    }


def v1_validate_lambda_lifting_controls(value: Any) -> None:
    root = v1_closed(
        value,
        ["root_declaration_slot", "source_nodes", "lifted_declarations"],
        "LambdaLiftingControlsV1",
    )
    if v1_u32(root["root_declaration_slot"], "lambda root slot") != 0:
        fail("callable-interface-contract-mismatch", "lambda root slot is not zero")
    sources = require_list(root["source_nodes"], "Decode/array-mismatch", "lambda sources")
    lifted = require_list(
        root["lifted_declarations"], "Decode/array-mismatch", "lifted lambdas"
    )
    if len(sources) != len(lifted) or not sources:
        fail("callable-interface-contract-mismatch", "lambda lifting is not total")
    seen_sources: set[int] = set()
    seen_slots: set[int] = set()
    for index, (source_value, lifted_value) in enumerate(zip(sources, lifted)):
        source = v1_closed(
            source_value,
            ["source_ordinal", "source_kind", "generic"],
            "LambdaSourceNodeV1",
        )
        source_ordinal = v1_u32(source["source_ordinal"], "lambda source ordinal")
        if source_ordinal != index or source["source_kind"] not in {
            "OrdinaryLambdaExprV1",
            "GenericLambdaExprV1",
        } or not isinstance(source["generic"], bool):
            fail("callable-interface-contract-mismatch", "lambda source order/kind differs")
        if source["generic"] != (source["source_kind"] == "GenericLambdaExprV1"):
            fail("callable-interface-contract-mismatch", "lambda generic classification differs")
        item = v1_closed(
            lifted_value,
            [
                "source_ordinal",
                "declaration_slot",
                "scheme",
                "reference",
                "nested_function_contract_v3_roots",
            ],
            "LiftedLambdaDeclarationV1",
        )
        declaration_slot = v1_u32(item["declaration_slot"], "lifted declaration slot")
        if item["source_ordinal"] != source_ordinal or declaration_slot != index + 1:
            fail("callable-interface-contract-mismatch", "lambda lexical slot allocation differs")
        expected_scheme = (
            "Rank1ImmutableSimpleNameV1" if source["generic"] else "MonomorphicLambdaV1"
        )
        if item["scheme"] != expected_scheme:
            fail("callable-interface-contract-mismatch", "lambda scheme boundary differs")
        reference = v1_closed(
            item["reference"], ["kind", "declaration_slot"], "LocalFunctionRefV2"
        )
        if reference != {"kind": "LocalFunctionRefV2", "declaration_slot": declaration_slot}:
            fail("local-function-ref-unresolved", "lifted lambda reference differs")
        if v1_u32(
            item["nested_function_contract_v3_roots"],
            "nested FunctionContractV3 root count",
        ) != 0:
            fail(
                "callable-interface-contract-mismatch",
                "lambda reset lexical slot 0 in a nested V3 root",
            )
        seen_sources.add(source_ordinal)
        seen_slots.add(declaration_slot)
    if seen_sources != set(range(len(sources))) or seen_slots != set(
        range(1, len(sources) + 1)
    ):
        fail("callable-interface-contract-mismatch", "lambda lifting coverage differs")
    if root != build_lambda_lifting_controls():
        fail("callable-interface-contract-mismatch", "lambda lifting model differs")


def build_trait_default_program_controls() -> Dict[str, Any]:
    program = {
        "kind": "TraitDefaultPrologueProgramV1",
        "root_declaration_slot": 0,
        "callable_dependencies": [],
        "local_declarations": [],
        "default_prologues": [],
        "applications": [],
        "closure_environment": [],
        "requirement_scopes": [
            {"declaration_slot": 0, "requirements": v1_empty_requirements()}
        ],
        "trait_method_uses": [],
    }
    return {
        "signature": {
            "binders": v1_empty_binders(),
            "requirements": v1_empty_requirements(),
            "surface_signature": v1_surface_signature(0),
            "declaration_kind": {
                "kind": "FunctionContractKindV2",
                "parameter_type": v1_legacy_builtin("Unit"),
                "result_type": v1_legacy_builtin("Unit"),
                "visible_row": v1_empty_row(),
            },
            "default_program": copy.deepcopy(program),
        },
        "projected_default_program": copy.deepcopy(program),
    }


def v1_validate_trait_default_program_controls(value: Any) -> None:
    controls = v1_closed(
        value,
        ["signature", "projected_default_program"],
        "TraitDefaultProgramControlsV1",
    )
    signature = v1_closed(
        controls["signature"],
        [
            "binders",
            "requirements",
            "surface_signature",
            "declaration_kind",
            "default_program",
        ],
        "TraitMethodSignatureV1",
    )
    binder_table = v1_type_binder_table(signature["binders"], "trait method binders")
    v1_validate_declaration_requirements(
        signature["requirements"], binder_table, "trait method requirements"
    )
    v1_validate_surface_slots(signature["surface_signature"], signature["binders"], set())
    declaration_kind = v1_closed(
        signature["declaration_kind"],
        ["kind", "parameter_type", "result_type", "visible_row"],
        "FunctionContractKindV2",
    )
    if declaration_kind["kind"] != "FunctionContractKindV2" or declaration_kind["visible_row"] != v1_empty_row():
        fail("callable-interface-contract-mismatch", "trait method kind/row differs")
    for field in ("parameter_type", "result_type"):
        v1_validate_m3_type(declaration_kind[field], binder_table, "trait method " + field)
    program = v1_closed(
        signature["default_program"],
        [
            "kind",
            "root_declaration_slot",
            "callable_dependencies",
            "local_declarations",
            "default_prologues",
            "applications",
            "closure_environment",
            "requirement_scopes",
            "trait_method_uses",
        ],
        "TraitDefaultPrologueProgramV1",
    )
    if program["kind"] != "TraitDefaultPrologueProgramV1" or v1_u32(
        program["root_declaration_slot"], "trait default root slot"
    ) != 0:
        fail("callable-interface-contract-mismatch", "trait default root differs")
    for field in (
        "callable_dependencies",
        "local_declarations",
        "default_prologues",
        "applications",
        "closure_environment",
        "trait_method_uses",
    ):
        if require_list(program[field], "Decode/array-mismatch", field):
            fail("callable-interface-contract-mismatch", "empty trait default control has executable drift")
    scopes = require_list(program["requirement_scopes"], "Decode/array-mismatch", "trait default scopes")
    if len(scopes) != 1:
        fail("callable-interface-contract-mismatch", "trait default scope closure differs")
    scope = v1_closed(scopes[0], ["declaration_slot", "requirements"], "CallableRequirementScopeV1")
    if v1_u32(scope["declaration_slot"], "trait default scope slot") != 0:
        fail("callable-interface-contract-mismatch", "trait default scope slot differs")
    v1_validate_declaration_requirements(scope["requirements"], binder_table, "trait default complete scope")
    if controls["projected_default_program"] != program:
        fail("callable-interface-contract-mismatch", "trait default projection differs")
    if controls != build_trait_default_program_controls():
        fail("callable-interface-contract-mismatch", "trait default program model differs")


def v1_validate_function_contract_suite(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "hash_algorithm",
            "cases",
            "differentials",
            "effect_constructor_controls",
            "lambda_lifting_controls",
            "trait_default_program_controls",
            "expectations",
        ],
        "CireFunctionContractV3SuiteV1",
    )
    validate_profile_header(
        root,
        "CireFunctionContractV3SuiteV1",
        1,
        "callable-interface-contract-mismatch",
    )
    if root["hash_algorithm"] != HASH_ALGORITHM:
        fail(
            "callable-interface-contract-mismatch",
            "V3 suite hash algorithm differs",
        )
    expectations = v1_closed(
        root["expectations"],
        [
            "callee_before_caller",
            "default_case",
            "direct_capability_binding",
            "handler_case",
            "higher_order_case",
            "local_case",
            "named_row_case",
            "park_case",
        ],
        "FunctionContractV3SuiteExpectationsV1",
    )
    if expectations != {
        "callee_before_caller": V3_SUITE_CASE_ORDER,
        "default_case": "default-prologue",
        "direct_capability_binding": {
            "case": "direct-capability-identity",
            "source_parameter_slot": 1,
            "role": "DirectV1",
            "identity_slot": 0,
        },
        "handler_case": "handler-forward",
        "higher_order_case": "hof-import-caller",
        "local_case": "local-declaration",
        "named_row_case": "named-row",
        "park_case": "mixed-next-park",
    }:
        fail(
            "callable-interface-contract-mismatch",
            "V3 suite expectation vector differs",
        )
    cases = require_list(root["cases"], "Decode/array-mismatch", "V3 cases")
    if [case.get("id") for case in cases if isinstance(case, dict)] != V3_SUITE_CASE_ORDER:
        fail(
            "callable-interface-contract-mismatch",
            "V3 cases are not in frozen callee-before-caller order",
        )
    legacy_by_interface: Dict[str, Dict[str, Any]] = {}
    cases_by_id: Dict[str, Mapping[str, Any]] = {}
    observed_features: set[str] = set()
    for case_value in cases:
        case = v1_closed(
            case_value,
            [
                "id",
                "module",
                "export_path",
                "surface_signature",
                "contract",
                "contract_hash",
                "callable_interface_hash",
                "features",
            ],
            "FunctionContractV3SuiteCaseV1",
        )
        v1_string(case["id"], "V3 case ID")
        v1_module(case["module"], "V3 case module")
        export_path = require_list(
            case["export_path"], "Decode/array-mismatch", "V3 case export path"
        )
        if not export_path:
            fail(
                "callable-interface-contract-mismatch",
                "V3 case export path is empty",
            )
        for segment in export_path:
            v1_string(segment, "V3 case export segment")
        if case["id"] == expectations["direct_capability_binding"]["case"]:
            v1_validate_direct_capability_case(
                expectations["direct_capability_binding"],
                cases_by_id={case["id"]: case},
            )
        contract_hash = object_hash(case["contract"])
        if case["contract_hash"] != contract_hash:
            fail(
                "callable-interface-contract-mismatch",
                case["id"] + " contract hash differs",
            )
        interface = {
            "artifact": "CallableInterfaceV1",
            "profile": PROFILE,
            "schema_version": 1,
            "module": copy.deepcopy(case["module"]),
            "export_path": copy.deepcopy(case["export_path"]),
            "core_contract": {
                "artifact": "FunctionContractV3",
                "hash_algorithm": HASH_ALGORITHM,
                "artifact_hash": contract_hash,
            },
            "surface_signature": copy.deepcopy(case["surface_signature"]),
        }
        interface_hash = object_hash(interface)
        if case["callable_interface_hash"] != interface_hash:
            fail(
                "callable-interface-contract-mismatch",
                case["id"] + " callable interface hash differs",
            )
        if interface_hash in legacy_by_interface:
            fail(
                "callable-interface-contract-mismatch",
                "duplicate callable interface hash in V3 suite",
            )
        retained = v1_validate_function_contract(
            case["contract"],
            dependency_legacy=legacy_by_interface,
            surface_signature=case["surface_signature"],
        )
        features = require_list(
            case["features"], "Decode/array-mismatch", "V3 case features"
        )
        expected_features = v1_contract_features(case["contract"])
        if features != expected_features:
            fail(
                "callable-interface-contract-mismatch",
                case["id"] + " feature witness vector differs",
            )
        observed_features.update(features)
        legacy_by_interface[interface_hash] = retained
        cases_by_id[case["id"]] = case
    v1_validate_direct_capability_case(
        expectations["direct_capability_binding"],
        cases_by_id=cases_by_id,
    )
    required_features = {
        "default-prologue",
        "deterministic-local-slots",
        "direct-capability-identity",
        "explicit-named-row",
        "handler",
        "higher-order-contract-parameter",
        "higher-order-import",
        "imported-callable-slot",
        "local-call",
        "park",
        "provided-or-omitted",
        "transfers",
    }
    if not required_features <= observed_features:
        fail(
            "callable-interface-contract-mismatch",
            "V3 suite misses required executable feature witnesses",
        )
    v1_validate_v3_differentials(
        root["differentials"],
        cases_by_id=cases_by_id,
        legacy_by_interface=legacy_by_interface,
        direct_capability_binding=expectations["direct_capability_binding"],
    )
    v1_validate_effect_constructor_controls(root["effect_constructor_controls"])
    v1_validate_lambda_lifting_controls(root["lambda_lifting_controls"])
    v1_validate_trait_default_program_controls(
        root["trait_default_program_controls"]
    )


def v1_validate_callable(value: Any) -> None:
    root = v1_closed(
        value,
        ["artifact", "profile", "schema_version", "module", "export_path", "core_contract", "surface_signature"],
        "CallableInterfaceV1",
    )
    validate_profile_header(root, "CallableInterfaceV1", 1, "callable-interface-contract-mismatch")
    v1_module(root["module"], "callable.module")
    if root["module"] != [PACKAGE_MODULE, "root"] or root["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", "callable semantic identity differs")
    v1_hash_ref(root["core_contract"], "FunctionContractV3", "callable-interface-contract-mismatch")
    signature = v1_closed(root["surface_signature"], ["kind", "slots"], "CallableSurfaceSignatureV1")
    if signature["kind"] != "CallableSurfaceSignatureV1":
        fail("Decode/tag-mismatch", "wrong callable surface signature tag")
    slots = require_list(signature["slots"], "Decode/array-mismatch", "surface slots")
    if len(slots) != 1:
        fail("callable-interface-contract-mismatch", "identity callable needs one slot")
    slot = v1_closed(slots[0], ["slot", "passing", "public_label", "defaultable"], "ParameterSurfaceSlotV1")
    if slot != {"slot": 0, "passing": "NamedOrPositionalV1", "public_label": "value", "defaultable": False}:
        fail("callable-interface-contract-mismatch", "identity surface slot differs")


def v1_validate_canonicalization(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "utf16_order_probe",
            "expected_jcs",
            "expected_hash",
            "scalar_probe",
            "scalar_rejection",
        ],
        "CireCanonicalizationOracleV1",
    )
    validate_profile_header(
        root,
        "CireCanonicalizationOracleV1",
        1,
        "Decode/canonicalization-mismatch",
    )
    expected_jcs = '{"😀":2,"":1}'
    if root["utf16_order_probe"] != {"\ue000": 1, "😀": 2}:
        fail("Decode/canonicalization-mismatch", "UTF-16 ordering probe differs")
    if jcs(root["utf16_order_probe"]) != expected_jcs or root["expected_jcs"] != expected_jcs:
        fail("Decode/canonicalization-mismatch", "RFC 8785 UTF-16 ordering differs")
    expected_hash = "sha256:28c95d1bbb2209223307e62f489020e8f9e0cfa16adf2daf6d88127a1e8dd22a"
    if root["expected_hash"] != expected_hash or object_hash(root["utf16_order_probe"]) != expected_hash:
        fail("Decode/canonicalization-mismatch", "UTF-16 ordering hash differs")
    scalar = v1_u32(root["scalar_probe"], "scalar probe")
    if scalar > 0x10FFFF or 0xD800 <= scalar <= 0xDFFF:
        fail("Decode/unicode-scalar-mismatch", "scalar probe is not a Unicode scalar")
    rejection = v1_closed(
        root["scalar_rejection"],
        ["code_point", "expected_failure"],
        "scalar rejection",
    )
    if rejection != {
        "code_point": 0xD800,
        "expected_failure": {
            "kind": "DecodeFailureV1",
            "code": "unicode-scalar-mismatch",
        },
    }:
        fail("Decode/canonicalization-mismatch", "surrogate rejection vector differs")
    try:
        walk_json(chr(rejection["code_point"]), "surrogate-probe")
    except ValidationFailure as error:
        if v1_failure_shape(error) != rejection["expected_failure"]:
            fail("Decode/canonicalization-mismatch", "surrogate failure shape differs")
    else:
        fail("Decode/canonicalization-mismatch", "lone surrogate unexpectedly accepted")


def v1_validate_callable_fact(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "identity",
            "package",
            "callable",
            "source_identity",
            "declaration_kind",
            "visibility",
            "requirement_scopes",
            "trait_method_uses",
            "const_safety",
            "protocol_purity",
            "trap",
        ],
        "CallableContractFactEvidenceV1",
    )
    validate_profile_header(
        root,
        "CallableContractFactEvidenceV1",
        1,
        "callable-interface-contract-mismatch",
    )
    identity = v1_closed(
        root["identity"],
        ["package", "kind", "ordinal"],
        "EvidenceIdentityV1",
    )
    v1_package_instance(identity["package"], "callable fact identity package")
    if identity["kind"] != "ProtocolEvidenceV1" or v1_u32(
        identity["ordinal"], "callable fact ordinal"
    ) != 0:
        fail(
            "callable-interface-contract-mismatch",
            "callable fact identity differs",
        )
    v1_package_instance(root["package"], "callable fact package")
    callable_edge = v1_closed(
        root["callable"],
        ["module", "export_path", "callable_interface"],
        "PackageCallableEdgeV1",
    )
    v1_module(callable_edge["module"], "callable fact module")
    v1_hash_ref(
        callable_edge["callable_interface"],
        "CallableInterfaceV1",
        "callable-interface-contract-mismatch",
    )
    source_identity = v1_closed(
        root["source_identity"],
        ["kind", "declaration"],
        "FreeSourceV1",
    )
    if source_identity["kind"] != "FreeSourceV1":
        fail("Decode/tag-mismatch", "callable source identity is not FreeSourceV1")
    namespace, _module, _path = v1_declaration_identity(
        source_identity["declaration"], "free callable source identity"
    )
    if namespace != "ValueV1" or source_identity["declaration"] != CALLABLE_SOURCE_IDENTITY:
        fail(
            "callable-interface-contract-mismatch",
            "free callable source identity differs",
        )
    declaration_kind = v1_closed(
        root["declaration_kind"], ["kind"], "FreeCallableV1"
    )
    if declaration_kind["kind"] != "FreeCallableV1":
        fail("Decode/tag-mismatch", "callable declaration kind is not FreeCallableV1")
    if root["visibility"] != "PublicV1":
        fail(
            "callable-interface-contract-mismatch",
            "free callable visibility differs",
        )
    scopes = require_list(
        root["requirement_scopes"],
        "Decode/array-mismatch",
        "callable requirement scopes",
    )
    if len(scopes) != 1:
        fail(
            "callable-interface-contract-mismatch",
            "root callable requirement scope coverage differs",
        )
    scope = v1_closed(
        scopes[0],
        ["declaration_slot", "requirements"],
        "CallableRequirementScopeV1",
    )
    if v1_u32(scope["declaration_slot"], "callable requirement declaration slot") != 0:
        fail(
            "callable-interface-contract-mismatch",
            "root callable requirement scope is not slot zero",
        )
    v1_validate_declaration_requirements(
        scope["requirements"], {}, "callable root requirements"
    )
    if root["trait_method_uses"] != []:
        fail(
            "callable-interface-contract-mismatch",
            "free identity callable unexpectedly carries trait method uses",
        )
    if root != build_callable_contract_fact():
        fail(
            "callable-interface-contract-mismatch",
            "callable contract fact differs from the deterministic package fact",
        )


def v1_validate_language(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact", "profile", "schema_version", "package_identity",
            "package_instance_id", "imports", "declarations", "evidence",
            "callables", "components", "primitive_catalog", "intrinsic_registry",
        ],
        "CireLanguageInterfaceV1",
    )
    validate_profile_header(root, "CireLanguageInterfaceV1", 1, "package-instance-hash-mismatch")
    evidence = v1_closed(root["package_identity"], ["kind", "instance", "input", "hash_algorithm"], "PackageIdentityEvidenceV1")
    if evidence["kind"] != "PackageIdentityEvidenceV1" or evidence["hash_algorithm"] != HASH_ALGORITHM:
        fail("package-instance-hash-mismatch", "package evidence metadata differs")
    v1_package_instance(evidence["instance"], "package_identity.instance")
    v1_package_instance(root["package_instance_id"], "package_instance_id")
    if evidence["instance"] != root["package_instance_id"]:
        fail("package-instance-hash-mismatch", "package evidence/root identity differs")
    if evidence["input"] != package_identity_input():
        fail("package-instance-hash-mismatch", "package identity input differs")
    observed_digest = hashlib.sha256(canonical_bytes(evidence["input"])).hexdigest()
    if observed_digest != PACKAGE_DIGEST:
        fail("package-instance-hash-mismatch", "package digest recomputation differs")
    if root["imports"] != []:
        fail("package-import-not-locked", "foundation package unexpectedly imports another package")
    declarations = require_list(
        root["declarations"], "Decode/array-mismatch", "declarations"
    )
    if len(declarations) != 5:
        fail(
            "callable-interface-contract-mismatch",
            "package declaration dispatcher is not the exact five-arm closure",
        )
    declaration_dispatch = {
        "AbilityV1": "AbilityDeclarationV1",
        "EffectV1": "EffectDeclarationV1",
        "TraitV1": "TraitDeclarationV1",
        "TypeV1": "DataDeclarationV1",
        "ValueV1": "ConstDeclarationV1",
    }
    declaration_identities: List[Mapping[str, Any]] = []
    for edge in declarations:
        item = v1_closed(
            edge,
            ["identity", "declaration"],
            "PackageDeclarationEdgeV1",
        )
        namespace, _module, _path = v1_declaration_identity(
            item["identity"], "package declaration identity"
        )
        artifact = declaration_dispatch.get(namespace)
        if artifact is None:
            fail(
                "Decode/tag-mismatch",
                "package declaration namespace has no closed dispatcher arm",
            )
        v1_hash_ref(
            item["declaration"],
            artifact,
            "callable-interface-contract-mismatch",
        )
        declaration_identities.append(item["identity"])
    if [canonical_bytes(item) for item in declaration_identities] != sorted(
        canonical_bytes(item) for item in declaration_identities
    ):
        fail(
            "callable-interface-contract-mismatch",
            "package declaration identities are not canonical",
        )
    evidence_edges = require_list(root["evidence"], "Decode/array-mismatch", "evidence")
    if len(evidence_edges) != 2:
        fail("callable-interface-contract-mismatch", "evidence closure differs")
    evidence_dispatch = {
        "ImplEvidenceV1": "ImplEvidenceV1",
        "ProtocolEvidenceV1": "CallableContractFactEvidenceV1",
    }
    ordinal_by_kind: Dict[str, List[int]] = {}
    evidence_identities: List[Mapping[str, Any]] = []
    for edge in evidence_edges:
        item = v1_closed(edge, ["identity", "evidence"], "PackageEvidenceEdgeV1")
        identity = v1_closed(item["identity"], ["package", "kind", "ordinal"], "EvidenceIdentityV1")
        v1_package_instance(identity["package"], "evidence package")
        kind = identity["kind"]
        artifact = evidence_dispatch.get(kind)
        if artifact is None:
            fail("Decode/tag-mismatch", "unknown evidence dispatcher arm")
        ordinal_by_kind.setdefault(kind, []).append(
            v1_u32(identity["ordinal"], "evidence ordinal")
        )
        v1_hash_ref(
            item["evidence"],
            artifact,
            "callable-interface-contract-mismatch",
        )
        evidence_identities.append(item["identity"])
    if any(
        sorted(ordinals) != list(range(len(ordinals)))
        for ordinals in ordinal_by_kind.values()
    ):
        fail(
            "callable-interface-contract-mismatch",
            "evidence ordinals are not contiguous within each evidence kind",
        )
    if [canonical_bytes(item) for item in evidence_identities] != sorted(
        canonical_bytes(item) for item in evidence_identities
    ):
        fail(
            "callable-interface-contract-mismatch",
            "package evidence identities are not canonical",
        )
    callables = require_list(root["callables"], "Decode/array-mismatch", "callables")
    if len(callables) != 1:
        fail("callable-interface-contract-mismatch", "callable closure differs")
    callable_edge = v1_closed(callables[0], ["module", "export_path", "callable_interface"], "PackageCallableEdgeV1")
    v1_module(callable_edge["module"], "package callable module")
    if callable_edge["module"] != [PACKAGE_MODULE, "root"] or callable_edge["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", "package callable identity differs")
    v1_hash_ref(callable_edge["callable_interface"], "CallableInterfaceV1", "callable-interface-contract-mismatch")
    components = require_list(root["components"], "Decode/array-mismatch", "components")
    if len(components) != 1:
        fail("component-public-type-not-safe", "component manifest closure differs")
    component = v1_closed(components[0], ["name", "manifest"], "PackageComponentEdgeV1")
    if component["name"] != "foundation":
        fail("component-public-type-not-safe", "component name differs")
    v1_hash_ref(component["manifest"], "ComponentManifestV1", "component-public-type-not-safe")
    v1_hash_ref(root["primitive_catalog"], "PrimitiveCatalogV1", "package-instance-hash-mismatch")
    v1_hash_ref(root["intrinsic_registry"], "IntrinsicRegistryRootV1", "intrinsic-registry-root-mismatch")
    if root != build_language_interface():
        fail(
            "callable-interface-contract-mismatch",
            "package root differs from the exact declaration/evidence closure",
        )


def v1_validate_primitive_catalog(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "core_package", "entries"], "PrimitiveCatalogV1")
    validate_profile_header(root, "PrimitiveCatalogV1", 1, "package-instance-hash-mismatch")
    v1_package_instance(root["core_package"], "primitive core package")
    entries = require_list(root["entries"], "Decode/array-mismatch", "primitive entries")
    if [entry.get("source_name") for entry in entries if isinstance(entry, dict)] != PRIMITIVES:
        fail("package-instance-hash-mismatch", "primitive universe/order differs")
    carriers = ["NoneV1", "NoneV1", "I32V1", "I32V1", "I32V1", "I32V1", "I64V1", "I32V1", "I32V1", "I32V1", "I64V1", "F32V1", "F64V1", "I32V1", "PrivateManagedV1", "PrivateManagedV1"]
    for entry, carrier in zip(entries, carriers):
        item = v1_closed(entry, ["source_name", "type", "carrier"], "PrimitiveEntryV1")
        name = item["source_name"]
        if item["carrier"] != carrier:
            fail("package-instance-hash-mismatch", name + " carrier differs")
        type_ref = item["type"]
        if name in LEGACY_PRIMITIVES:
            legacy = v1_closed(type_ref, ["kind", "value"], "LegacyTypeRefV2")
            builtin = v1_closed(legacy["value"], ["kind", "name"], "BuiltinTypeV1")
            if legacy["kind"] != "LegacyTypeRefV2" or builtin != {"kind": "BuiltinTypeV1", "name": name}:
                fail("package-instance-hash-mismatch", name + " legacy wire form differs")
        else:
            nominal = v1_closed(type_ref, ["kind", "module", "name", "arguments"], "NominalTypeV2")
            if nominal["kind"] != "NominalTypeV2" or nominal["name"] != name or nominal["arguments"] != []:
                fail("package-instance-hash-mismatch", name + " sealed nominal form differs")
            if nominal["module"] != [PACKAGE_MODULE, "core", "primitive"]:
                fail("package-instance-hash-mismatch", name + " sealed module differs")


def build_numeric_oracle() -> Dict[str, Any]:
    integer_types = [
        ("Int8", 8, True, "i8", False, "I32V1"),
        ("Int16", 16, True, "i16", False, "I32V1"),
        ("Int", 32, True, "i32", True, "I32V1"),
        ("Int64", 64, True, "i64", False, "I64V1"),
        ("UInt8", 8, False, "u8", False, "I32V1"),
        ("UInt16", 16, False, "u16", False, "I32V1"),
        ("UInt", 32, False, "u32", False, "I32V1"),
        ("UInt64", 64, False, "u64", False, "I64V1"),
    ]
    literal_types = [
        {
            "name": name,
            "kind": "IntegerV1",
            "width": width,
            "signed": signed,
            "suffix": suffix,
            "default_for_unsuffixed": default,
            "carrier": carrier,
        }
        for name, width, signed, suffix, default, carrier in integer_types
    ] + [
        {
            "name": "Float32",
            "kind": "FloatV1",
            "width": 32,
            "signed": True,
            "suffix": "f32",
            "default_for_unsuffixed": False,
            "carrier": "F32V1",
        },
        {
            "name": "Float",
            "kind": "FloatV1",
            "width": 64,
            "signed": True,
            "suffix": "f64",
            "default_for_unsuffixed": True,
            "carrier": "F64V1",
        },
    ]
    boundary_cases: List[Dict[str, Any]] = []
    for name, width, signed, _suffix, _default, _carrier in integer_types:
        minimum = -(1 << (width - 1)) if signed else 0
        maximum = (1 << (width - (1 if signed else 0))) - 1
        prefix = name.lower()
        for label, number, expected in [
            ("below-min", minimum - 1, "OutOfRangeV1"),
            ("max", maximum, "AcceptedV1"),
            ("min", minimum, "AcceptedV1"),
            ("one-past-max", maximum + 1, "OutOfRangeV1"),
        ]:
            boundary_cases.append(
                {
                    "id": prefix + "-" + label,
                    "type": name,
                    "value_decimal": str(number),
                    "expected": expected,
                }
            )
    boundary_cases.sort(key=lambda item: item["id"])
    carrier_cases = [
        {"id": "bool-one", "kind": "accept", "source": "Bool", "wasm_i32": 1, "decoded": True},
        {"id": "bool-two", "kind": "reject", "source": "Bool", "wasm_i32": 2, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "bool-zero", "kind": "accept", "source": "Bool", "wasm_i32": 0, "decoded": False},
        {"id": "char-max-scalar", "kind": "accept", "source": "Char", "wasm_i32": 0x10FFFF, "decoded": 0x10FFFF},
        {"id": "char-negative", "kind": "reject", "source": "Char", "wasm_i32": -1, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "char-surrogate", "kind": "reject", "source": "Char", "wasm_i32": 0xD800, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "char-too-large", "kind": "reject", "source": "Char", "wasm_i32": 0x110000, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "int16-negative-one-sign-extends", "kind": "accept", "source": "Int16", "wasm_i32": -1, "canonical_bits": 0xFFFF},
        {"id": "int16-noncanonical-upper-bits", "kind": "reject", "source": "Int16", "wasm_i32": 0x1FFFF, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "int8-negative-one-sign-extends", "kind": "accept", "source": "Int8", "wasm_i32": -1, "canonical_bits": 0xFF},
        {"id": "int8-noncanonical-upper-bits", "kind": "reject", "source": "Int8", "wasm_i32": 0x1FF, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "uint16-max-zero-extends", "kind": "accept", "source": "UInt16", "wasm_i32": 0xFFFF, "canonical_bits": 0xFFFF},
        {"id": "uint16-noncanonical-upper-bits", "kind": "reject", "source": "UInt16", "wasm_i32": 0x10000, "diagnostic": "integer-conversion-out-of-range"},
        {"id": "uint8-max-zero-extends", "kind": "accept", "source": "UInt8", "wasm_i32": 0xFF, "canonical_bits": 0xFF},
        {"id": "uint8-noncanonical-upper-bits", "kind": "reject", "source": "UInt8", "wasm_i32": 0x100, "diagnostic": "integer-conversion-out-of-range"},
    ]
    operation_cases = [
        {"id": "checked-add-overflow", "operation": "checked_add", "type": "Int8", "operands": ["127", "1"], "expected": "NoneV1", "trap_fact": "NoTrapV1"},
        {"id": "checked-div-zero", "operation": "checked_div", "type": "Int", "operands": ["1", "0"], "expected": "NoneV1", "trap_fact": "NoTrapV1"},
        {"id": "checked-neg-min", "operation": "checked_neg", "type": "Int8", "operands": ["-128"], "expected": "NoneV1", "trap_fact": "NoTrapV1"},
        {"id": "checked-shift-range", "operation": "checked_shl", "type": "UInt8", "operands": ["1", "8"], "expected": "NoneV1", "trap_fact": "NoTrapV1"},
        {"id": "ordinary-abs-min", "operation": "abs", "type": "Int8", "operands": ["-128"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "ordinary-add-overflow", "operation": "+", "type": "Int8", "operands": ["127", "1"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "ordinary-div-zero", "operation": "/", "type": "Int", "operands": ["1", "0"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "ordinary-neg-min", "operation": "neg", "type": "Int64", "operands": ["-9223372036854775808"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "ordinary-rem-zero", "operation": "%", "type": "UInt", "operands": ["1", "0"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "ordinary-shift-range", "operation": "<<", "type": "UInt16", "operands": ["1", "16"], "expected": "DefectTransitionV1", "trap_fact": "MayTrapV1"},
        {"id": "saturating-add-max", "operation": "saturating_add", "type": "Int8", "operands": ["127", "1"], "expected": "127", "trap_fact": "NoTrapV1"},
        {"id": "saturating-mul-max", "operation": "saturating_mul", "type": "UInt8", "operands": ["200", "2"], "expected": "255", "trap_fact": "NoTrapV1"},
        {"id": "saturating-sub-min", "operation": "saturating_sub", "type": "Int8", "operands": ["-128", "1"], "expected": "-128", "trap_fact": "NoTrapV1"},
        {"id": "wrapping-add-max", "operation": "wrapping_add", "type": "UInt8", "operands": ["255", "1"], "expected": "0", "trap_fact": "NoTrapV1"},
        {"id": "wrapping-neg-min", "operation": "wrapping_neg", "type": "Int8", "operands": ["-128"], "expected": "-128", "trap_fact": "NoTrapV1"},
        {"id": "wrapping-shift-mask", "operation": "wrapping_shl", "type": "UInt8", "operands": ["1", "8"], "expected": "1", "trap_fact": "NoTrapV1"},
    ]
    conversion_cases = [
        {"id": "exact-widen", "operation": "Int64::from", "input": "127_i8", "expected": "127_i64"},
        {"id": "float-from-bits-canonical-nan", "operation": "Float::from_bits", "input": "0x7ff0000000000001", "expected": "0x7ff8000000000000"},
        {"id": "float-to-bits-signed-zero", "operation": "to_bits", "input": "-0.0_f64", "expected": "0x8000000000000000"},
        {"id": "round-int-ties-even", "operation": "Float32::round_from_int", "input": "16777217_i32", "expected": "0x4b800000"},
        {"id": "try-from-narrow-fail", "operation": "Int8::try_from", "input": "128_i32", "expected": "NoneV1"},
        {"id": "try-from-narrow-success", "operation": "Int8::try_from", "input": "127_i32", "expected": "Some(127_i8)"},
        {"id": "try-truncate-infinity", "operation": "Int::try_truncate", "input": "+inf_f64", "expected": "NoneV1"},
        {"id": "try-truncate-nan", "operation": "Int::try_truncate", "input": "nan_f64", "expected": "NoneV1"},
        {"id": "try-truncate-out-of-range", "operation": "Int::try_truncate", "input": "2147483648.0_f64", "expected": "NoneV1"},
        {"id": "try-truncate-toward-zero", "operation": "Int::try_truncate", "input": "-3.9_f64", "expected": "Some(-3_i32)"},
        {"id": "wrapping-from", "operation": "UInt8::wrapping_from", "input": "256_u32", "expected": "0_u8"},
    ]
    differential_cases = [
        {"id": "canonical-nan-f32", "source": "0.0_f32/0.0_f32", "result_bits": "0x7fc00000"},
        {"id": "canonical-nan-f64", "source": "0.0_f64/0.0_f64", "result_bits": "0x7ff8000000000000"},
        {"id": "float-to-int-truncate", "source_bits": "0xc06ccccccccccccd", "target": "Int", "result": "-3_i32"},
        {"id": "int-to-float-tie-even", "source": "16777217_i32", "target": "Float32", "result_bits": "0x4b800000"},
        {"id": "signed-zero-ordinary-eq", "left_bits": "0x0000000000000000", "right_bits": "0x8000000000000000", "result": True},
        {"id": "signed-zero-to-bits", "left_bits": "0x0000000000000000", "right_bits": "0x8000000000000000", "result": False},
        {"id": "total-float-nan-hash", "left_bits": "0x7ff0000000000001", "right_bits": "0x7fffffffffffffff", "result": "canonical-equal"},
        {"id": "total-float-signed-zero-distinct", "left_bits": "0x0000000000000000", "right_bits": "0x8000000000000000", "result": "distinct-eq-ord-hash"},
    ]
    return {
        "artifact": "NumericSemanticsOracleV1",
        "profile": PROFILE,
        "schema_version": 1,
        "literal_types": literal_types,
        "integer_policy": {
            "checked_named_operations": ["checked_abs", "checked_add", "checked_div", "checked_mul", "checked_neg", "checked_rem", "checked_shl", "checked_shr", "checked_sub"],
            "default_operations": "MayTrapV1+DefectTransitionV1",
            "implicit_typed_conversion": False,
            "saturating_named_operations": ["saturating_add", "saturating_mul", "saturating_sub"],
            "wrapping_named_operations": ["wrapping_abs", "wrapping_add", "wrapping_mul", "wrapping_neg", "wrapping_shl", "wrapping_shr", "wrapping_sub"],
        },
        "conversion_policy": {
            "float_to_int": "checked-truncate-toward-zero",
            "general_cast_operator": False,
            "int_to_float": "round-nearest-ties-to-even",
            "to_bits_from_bits": "exact-bit-preserving",
        },
        "float_policy": {
            "canonical_nan": "positive-quiet-zero-payload",
            "ordinary_protocols": ["PartialEq", "PartialOrd", "Show"],
            "ordinary_signed_zero_equal": True,
            "total_signed_zero_equal": False,
            "total_wrappers": ["TotalFloat32", "TotalFloat"],
            "total_wrapper_protocols": ["Eq", "Ord", "Hash"],
            "total_hash_includes_width_and_canonical_bits": True,
        },
        "carrier_cases": carrier_cases,
        "integer_boundary_cases": boundary_cases,
        "operation_cases": operation_cases,
        "conversion_cases": conversion_cases,
        "differential_cases": differential_cases,
    }


def v1_validate_numeric(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "literal_types",
            "integer_policy",
            "conversion_policy",
            "float_policy",
            "carrier_cases",
            "integer_boundary_cases",
            "operation_cases",
            "conversion_cases",
            "differential_cases",
        ],
        "NumericSemanticsOracleV1",
    )
    validate_profile_header(
        root, "NumericSemanticsOracleV1", 1, "maytrap-not-an-effect"
    )
    integer = v1_closed(
        root["integer_policy"],
        [
            "checked_named_operations",
            "default_operations",
            "implicit_typed_conversion",
            "saturating_named_operations",
            "wrapping_named_operations",
        ],
        "integer policy",
    )
    if integer["default_operations"] != "MayTrapV1+DefectTransitionV1":
        fail(
            "maytrap-not-an-effect",
            "default arithmetic must carry an ordinary MayTrap fact",
        )
    if integer["implicit_typed_conversion"] is not False:
        fail(
            "integer-conversion-out-of-range",
            "implicit typed conversion is not in v1",
        )
    conversion = v1_closed(
        root["conversion_policy"],
        [
            "float_to_int",
            "general_cast_operator",
            "int_to_float",
            "to_bits_from_bits",
        ],
        "conversion policy",
    )
    if conversion["general_cast_operator"] is not False:
        fail(
            "integer-conversion-out-of-range",
            "a general cast operator is not in Cire-v1.0",
        )
    v1_closed(
        root["float_policy"],
        [
            "canonical_nan",
            "ordinary_protocols",
            "ordinary_signed_zero_equal",
            "total_signed_zero_equal",
            "total_wrappers",
            "total_wrapper_protocols",
            "total_hash_includes_width_and_canonical_bits",
        ],
        "float policy",
    )
    literal_types = require_list(
        root["literal_types"], "Decode/array-mismatch", "literal types"
    )
    for literal in literal_types:
        v1_closed(
            literal,
            [
                "name",
                "kind",
                "width",
                "signed",
                "suffix",
                "default_for_unsuffixed",
                "carrier",
            ],
            "NumericLiteralTypeV1",
        )
    for field in [
        "carrier_cases",
        "integer_boundary_cases",
        "operation_cases",
        "conversion_cases",
        "differential_cases",
    ]:
        cases = require_list(root[field], "Decode/array-mismatch", field)
        identifiers = [
            v1_string(case.get("id"), field + " id")
            if isinstance(case, dict)
            else fail("Decode/object-mismatch", field + " case is not an object")
            for case in cases
        ]
        if identifiers != sorted(set(identifiers)):
            fail(
                "integer-conversion-out-of-range",
                field + " identifiers are not canonical",
            )
    if root != build_numeric_oracle():
        fail(
            "integer-conversion-out-of-range",
            "numeric semantics matrix differs from the frozen oracle",
        )


def v1_validate_nominal(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "package_instance_id", "declarations", "construction_cases", "pattern_cases", "layout_cases"], "NominalDataOracleV1")
    validate_profile_header(root, "NominalDataOracleV1", 1, "record-construction-missing-field")
    v1_package_instance(root["package_instance_id"], "nominal package")
    declarations = require_list(root["declarations"], "Decode/array-mismatch", "nominal declarations")
    if [item.get("identity") for item in declarations] != [
        "Meters",
        "Point",
        "Secret",
        "Status",
        "UserId",
        "WireMessage",
    ]:
        fail("record-construction-missing-field", "nominal declaration order differs")
    for declaration_value in declarations:
        declaration = v1_closed(
            declaration_value,
            [
                "identity",
                "kind",
                "visibility",
                "representation",
                "fields",
                "variants",
                "derives",
                "source_spelling",
            ],
            "NominalDeclarationV1",
        )
        if declaration["kind"] not in {
            "TransparentAliasV1",
            "StructV1",
            "OpaqueTypeV1",
            "EnumV1",
            "NewtypeV1",
        } or declaration["visibility"] not in {"PackageV1", "PublicV1"}:
            fail("Decode/enum-mismatch", "nominal declaration kind/visibility differs")
        representation = declaration["representation"]
        if representation is not None:
            representation = v1_closed(
                representation, ["kind", "name"], "BuiltinTypeV1"
            )
            if representation["kind"] != "BuiltinTypeV1":
                fail("Decode/tag-mismatch", "nominal representation tag differs")
        fields = require_list(
            declaration["fields"], "Decode/array-mismatch", "nominal fields"
        )
        for field_value in fields:
            field = v1_closed(
                field_value,
                ["name", "type", "visibility", "default"],
                "NominalFieldV1",
            )
            if field["visibility"] not in {"PackageV1", "PublicV1"}:
                fail("Decode/enum-mismatch", "nominal field visibility differs")
            if field["default"] is not None:
                default = v1_closed(
                    field["default"], ["kind", "value"], "ConstIntV1"
                )
                if default["kind"] != "ConstIntV1":
                    fail("Decode/tag-mismatch", "nominal field default tag differs")
        variants = require_list(
            declaration["variants"], "Decode/array-mismatch", "nominal variants"
        )
        for variant in variants:
            if not isinstance(variant, dict):
                fail("Decode/object-mismatch", "enum variant must be an object")
            variant_kind = variant.get("kind")
            if variant_kind in {"UnitVariantV1", "TupleVariantV1"}:
                item = v1_closed(
                    variant, ["kind", "name", "payload"], variant_kind
                )
                payloads = require_list(
                    item["payload"], "Decode/array-mismatch", "variant payload"
                )
                if variant_kind == "UnitVariantV1" and payloads:
                    fail("Decode/array-mismatch", "unit variant payload is not empty")
                for payload in payloads:
                    v1_string(payload, "variant payload type")
            elif variant_kind == "RecordVariantV1":
                item = v1_closed(
                    variant, ["kind", "name", "fields"], "RecordVariantV1"
                )
                stored_fields = require_list(
                    item["fields"],
                    "Decode/array-mismatch",
                    "record variant stored fields",
                )
                for stored_value in stored_fields:
                    stored = v1_closed(
                        stored_value,
                        ["kind", "name", "type", "visibility", "default"],
                        "StoredFieldV1",
                    )
                    if stored["kind"] != "StoredFieldV1" or stored[
                        "visibility"
                    ] not in {"PackageV1", "PublicV1"}:
                        fail(
                            "Decode/enum-mismatch",
                            "record variant stored field differs",
                        )
                    if stored["default"] is not None:
                        default = v1_closed(
                            stored["default"], ["kind", "value"], "ConstIntV1"
                        )
                        if default["kind"] != "ConstIntV1":
                            fail(
                                "Decode/tag-mismatch",
                                "record variant default is not pure const data",
                            )
            else:
                fail("Decode/tag-mismatch", "unknown enum variant form")
        derives = require_list(declaration["derives"], "Decode/array-mismatch", "derives")
        for derive in derives:
            v1_string(derive, "derive identity")
        source = v1_string(declaration["source_spelling"], "source_spelling")
        if derives and "} derive(" not in source:
            fail("postfix-derive-required", "derive must follow the declaration")
    construction_cases = require_list(
        root["construction_cases"], "Decode/array-mismatch", "construction cases"
    )
    if [item.get("id") for item in construction_cases] != [
        "point-default-y",
        "point-functional-update",
        "external-hidden-field-construction",
        "wire-message-record-default-code",
        "external-record-variant-hidden-field",
    ]:
        fail("record-construction-missing-field", "construction case matrix differs")
    for index, case in enumerate(construction_cases):
        fields = (
            ["id", "result", "evaluation_order", "published_after"]
            if index == 0
            else ["id", "result", "evaluation_order", "defaults_reapplied"]
            if index == 1
            else ["id", "result", "diagnostic"]
            if index == 2
            else ["id", "result", "evaluation_order", "published_after"]
            if index == 3
            else ["id", "result", "diagnostic"]
        )
        v1_closed(case, fields, "ConstructionCaseV1")
    pattern_cases = require_list(
        root["pattern_cases"], "Decode/array-mismatch", "pattern cases"
    )
    if [item.get("id") for item in pattern_cases] != ["status-exhaustive", "status-missing-failed", "guard-does-not-cover", "useless-ready-after-wildcard"]:
        fail("non-exhaustive-match", "pattern case matrix differs")
    for index, case in enumerate(pattern_cases):
        fields = (
            ["id", "result", "constructors", "guards_contribute_coverage", "witness"]
            if index == 0
            else [
                "id",
                "result",
                "diagnostic",
                "constructors",
                "guards_contribute_coverage",
                "witness",
            ]
            if index < 3
            else ["id", "result", "diagnostic", "witness"]
        )
        v1_closed(case, fields, "PatternCaseV1")
    layout_cases = require_list(
        root["layout_cases"], "Decode/array-mismatch", "layout cases"
    )
    if [item.get("id") for item in layout_cases] != [
        "transparent-alias-cycle",
        "unbroken-newtype-cycle",
        "enum-recursion-private-indirection",
    ]:
        fail("newtype-representation-cycle", "layout case matrix differs")
    for case in layout_cases:
        v1_closed(case, ["id", "result", "diagnostic"], "LayoutCaseV1")
    if object_hash(root) != (
        "sha256:7fdabd2f9a4eb82ace21189e72fb2d119fb38ee0fc4a62a3b654bf54d400ac32"
    ):
        fail("record-construction-missing-field", "nominal data model differs")


def v1_validate_traits(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "traits", "impls", "extensions", "resolution_cases", "coherence_cases"], "TraitImplExtensionOracleV1")
    validate_profile_header(root, "TraitImplExtensionOracleV1", 1, "trait-impl-overlap")
    traits = require_list(root["traits"], "Decode/array-mismatch", "traits")
    if [item.get("identity") for item in traits] != ["DisplayName", "IntoIterator", "Iterator"]:
        fail("trait-impl-overlap", "trait declaration order differs")
    for trait_value in traits:
        trait = v1_closed(
            trait_value,
            ["identity", "visibility", "associated_types", "methods"],
            "TraitDeclarationV1",
        )
        if trait["visibility"] != "PublicOpenV1":
            fail("open-visibility-not-applicable", "trait visibility differs")
        for associated in require_list(
            trait["associated_types"], "Decode/array-mismatch", "associated types"
        ):
            v1_string(associated, "associated type")
        for method_value in require_list(
            trait["methods"], "Decode/array-mismatch", "trait methods"
        ):
            method = v1_closed(
                method_value,
                ["name", "parameters", "result", "effect_row", "receiver"],
                "TraitMethodV1",
            )
            if method.get("effect_row") != "! {}":
                fail("named-function-effect-row-required", "trait method lacks explicit row")
            if not str(method.get("receiver", "")).startswith("self :"):
                fail("extension-self-parameter-required", "method receiver differs")
            for parameter in require_list(
                method["parameters"], "Decode/array-mismatch", "trait parameters"
            ):
                v1_string(parameter, "trait parameter")
    heads: set[tuple[Any, Any]] = set()
    for impl_value in require_list(root["impls"], "Decode/array-mismatch", "impls"):
        impl = v1_closed(
            impl_value,
            ["identity", "trait", "target", "owner", "constraints", "methods"],
            "ImplEvidenceV1",
        )
        head = (impl.get("trait"), impl.get("target"))
        if head in heads:
            fail("trait-impl-overlap", "duplicate unifiable impl head")
        heads.add(head)
        for constraint in require_list(
            impl["constraints"], "Decode/array-mismatch", "impl constraints"
        ):
            v1_string(constraint, "impl constraint")
        for method_value in require_list(
            impl["methods"], "Decode/array-mismatch", "impl methods"
        ):
            method = v1_closed(
                method_value, ["name", "effect_row"], "ImplMethodV1"
            )
            if method.get("effect_row") != "! {}":
                fail("named-function-effect-row-required", "impl method lacks explicit row")
    extensions = require_list(root["extensions"], "Decode/array-mismatch", "extensions")
    for extension_value in extensions:
        extension = v1_closed(
            extension_value,
            [
                "identity",
                "qualified_name",
                "receiver",
                "parameters",
                "result",
                "effect_row",
                "activation",
            ],
            "ExtensionDeclarationV1",
        )
        if extension.get("effect_row") != "! {}":
            fail("named-function-effect-row-required", "extension lacks explicit row")
        parameters = require_list(extension.get("parameters"), "Decode/array-mismatch", "extension parameters")
        if not parameters or not isinstance(parameters[0], str) or not parameters[0].startswith("self :"):
            fail("extension-self-parameter-required", "extension must begin with self")
        if not str(extension.get("activation", "")).startswith("use @"):
            fail("extension-resolution-ambiguous", "extension activation differs")
    resolution_cases = require_list(
        root["resolution_cases"], "Decode/array-mismatch", "resolution cases"
    )
    if [case.get("id") for case in resolution_cases] != [
        "inherent-wins",
        "trait-extension-ambiguous",
        "trait-ufcs",
        "explicit-extension-import",
    ]:
        fail("method-candidate-ambiguous", "resolution case order differs")
    for case in resolution_cases:
        fields = ["id", "candidates", "selected", "result"] + (
            ["diagnostic"] if case.get("result") == "reject" else []
        )
        item = v1_closed(case, fields, "MethodResolutionCaseV1")
        for candidate in require_list(
            item["candidates"], "Decode/array-mismatch", "method candidates"
        ):
            v1_string(candidate, "method candidate")
    coherence_cases = require_list(
        root["coherence_cases"], "Decode/array-mismatch", "coherence cases"
    )
    if [case.get("id") for case in coherence_cases] != [
        "foreign-trait-foreign-head",
        "unifiable-overlap",
        "constraints-do-not-disambiguate",
        "local-newtype-head",
    ]:
        fail("trait-impl-overlap", "coherence case order differs")
    for case in coherence_cases:
        v1_closed(case, ["id", "result", "diagnostic"], "CoherenceCaseV1")
    if object_hash(root) != (
        "sha256:2cceb002b290d92b26925b23804ea90ba0d7b97ca53d1f1fc2caa6aa37cb4ab9"
    ):
        fail("trait-impl-overlap", "trait/impl/extension model differs")


def build_call_assembly_oracle() -> Dict[str, Any]:
    cases = [
        {
            "id": "default-declaration-order",
            "kind": "accept",
            "source": "def f(first : Int = 1, second : Int = first + 1) -> Int ! {} { second }",
            "expected": {
                "prologue_order": ["first", "second"],
                "visible_to_second": ["first"],
            },
        },
        {
            "id": "default-sees-later-slot",
            "kind": "reject",
            "source": "def f(first : Int = second, second : Int = 2) -> Int ! {} { first }",
            "expected": {"outcome": "LaterDefaultSlotOutOfScopeV1"},
        },
        {
            "id": "duplicate-final-trailing-slot",
            "kind": "reject",
            "source": "visit(body = explicit) { item => item }",
            "expected": {"outcome": "FinalSlotAlreadyFilledV1"},
        },
        {
            "id": "duplicate-labelled-argument",
            "kind": "reject",
            "source": "f(value = first(), value = second())",
            "expected": {"outcome": "DuplicateLabelRejectedV1"},
        },
        {
            "id": "explicit-empty-arg-list",
            "kind": "accept",
            "source": "f()",
            "expected": {"call_form": "ExplicitArgListV1"},
        },
        {
            "id": "label-before-positional",
            "kind": "reject",
            "source": "connect(\"host\", secure = true, 443)",
            "expected": {"outcome": "PositionalAfterLabelRejectedV1"},
        },
        {
            "id": "positional-before-label-evaluation",
            "kind": "accept",
            "source": "panel(make_title(), enabled = is_enabled(), gap = measure_gap())",
            "expected": {
                "evaluation_order": [
                    "panel",
                    "make_title",
                    "is_enabled",
                    "measure_gap",
                ],
                "tuple_order": ["title", "enabled", "gap"],
            },
        },
        {
            "id": "trailing-lambda-final-slot",
            "kind": "accept",
            "source": "visit(items()) { item => render(item) }",
            "expected": {
                "evaluation_order": ["visit", "items", "lambda"],
                "filled_slot": "body",
            },
        },
        {
            "id": "unknown-labelled-argument",
            "kind": "reject",
            "source": "f(unknown = 1)",
            "expected": {"outcome": "UnknownLabelRejectedV1"},
        },
    ]
    return {
        "artifact": "CallAssemblyOracleV1",
        "profile": PROFILE,
        "schema_version": 1,
        "cases": cases,
    }


def v1_validate_call_assembly(value: Any) -> None:
    root = v1_closed(
        value,
        ["artifact", "profile", "schema_version", "cases"],
        "CallAssemblyOracleV1",
    )
    validate_profile_header(
        root, "CallAssemblyOracleV1", 1, "callable-interface-contract-mismatch"
    )
    cases = require_list(root["cases"], "Decode/array-mismatch", "call cases")
    identifiers = []
    for case in cases:
        item = v1_closed(
            case, ["id", "kind", "source", "expected"], "CallAssemblyCaseV1"
        )
        identifiers.append(v1_string(item["id"], "call case id"))
        if item["kind"] not in {"accept", "reject"}:
            fail("Decode/enum-mismatch", "call case kind differs")
        v1_string(item["source"], "call case source")
        if not isinstance(item["expected"], dict):
            fail("Decode/object-mismatch", "call case expectation is not an object")
    if identifiers != sorted(identifiers) or len(identifiers) != len(set(identifiers)):
        fail("callable-interface-contract-mismatch", "call case order differs")
    if root != build_call_assembly_oracle():
        fail(
            "callable-interface-contract-mismatch",
            "call assembly matrix differs from the frozen exact model",
        )


def erase_handler_alpha_origin(value: Any) -> Any:
    """Erase only the two non-semantic differences allowed by Surface."""

    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            if key == "origin":
                continue
            if key in {"fresh_prompt", "prompt_ref"}:
                result[key] = "$alpha-prompt-0"
            else:
                result[key] = erase_handler_alpha_origin(child)
        return result
    if isinstance(value, list):
        return [erase_handler_alpha_origin(child) for child in value]
    return copy.deepcopy(value)


def handler_elaboration_variant(
    source_form: str, source: str, prompt: str, origin: Dict[str, Any]
) -> Dict[str, Any]:
    projection = {
        "normalized_hir": {
            "kind": "ScopedApplyV1",
            "fresh_prompt": prompt,
            "effect": "Logger",
            "clauses": [
                {"mode": "fun", "operation": "log", "parameter": "message"},
                {"mode": "return", "parameter": "value"},
            ],
            "origin": copy.deepcopy(origin),
        },
        "kernel": {
            "kind": "HandleV1",
            "prompt_ref": prompt,
            "effect": "Logger",
            "clause_modes": ["fun", "return"],
            "origin": copy.deepcopy(origin),
        },
        "contract": {
            "kind": "HandlerContractV3",
            "prompt_ref": prompt,
            "row": {"entries": [], "tail": None},
            "flow": "ReturnsV2",
            "capture": "NoCaptureV1",
            "usage": "ManyV1",
            "phase": "Compute",
            "origin": copy.deepcopy(origin),
        },
    }
    return {
        "source_form": source_form,
        "source": source,
        "projection": projection,
    }


def build_handler_elaboration_differential() -> Dict[str, Any]:
    full = handler_elaboration_variant(
        "FullHandlerV1",
        "with (handler Logger { fun log(message) => emit(message) return(value) => value }) as logger in body(logger)",
        "$full-prompt",
        {"kind": "DirectV1", "origin_id": 0},
    )
    inline = handler_elaboration_variant(
        "InlineHandlerV1",
        "with Logger { fun log(message) => emit(message) return(value) => value } as logger in body(logger)",
        "$inline-prompt",
        {
            "kind": "DerivedV1",
            "derivation_kind": "InlineHandlerExpansionV1",
            "origin_id": 1,
        },
    )
    return {
        "alpha_origin_erasure": ["fresh_prompt", "origin", "prompt_ref"],
        "full": full,
        "inline": inline,
        "diagnostic_equivalence": {
            "full_source": "with (handler Logger { log(message) => emit(message) }) in body()",
            "inline_source": "with Logger { log(message) => emit(message) } in body()",
            "id": "handler-clause-mode-required",
            "stage": "Syntax",
        },
    }


def build_control_mutation_oracle() -> Dict[str, Any]:
    return {
        "artifact": "ControlMutationOracleV1",
        "profile": PROFILE,
        "schema_version": 1,
        "handler_elaboration_differential": build_handler_elaboration_differential(),
        "structural_forms": [
            {
                "source": "break",
                "lowering": "FreshLexicalBreakTargetV1",
                "evaluation": "TargetResolvedBeforeOperandV1",
            },
            {
                "source": "continue",
                "lowering": "FreshLexicalContinueTargetV1",
                "evaluation": "InnermostLoopTargetV1",
            },
            {
                "source": "for",
                "lowering": "SourceOrderTemporaryV1+StateThreadedIteratorV1+CoreLoopV1",
                "evaluation": "IteratorExpressionExactlyOnceV1",
            },
            {
                "source": "if",
                "lowering": "CoreIfV1",
                "evaluation": "ConditionThenSelectedBranchV1",
            },
            {
                "source": "loop",
                "lowering": "CoreLoopV1",
                "evaluation": "FreshLoopTargetV1",
            },
            {
                "source": "match",
                "lowering": "SourceOrderTemporaryV1+CoreMatchV1",
                "evaluation": "ScrutineeExactlyOnceV1",
            },
            {
                "source": "return",
                "lowering": "FreshLexicalReturnTargetV1",
                "evaluation": "OperandBeforeTransferV1",
            },
            {
                "source": "while",
                "lowering": "SourceOrderTemporaryV1+CoreLoopV1",
                "evaluation": "ConditionOncePerIterationV1",
            },
        ],
        "place_trace": {
            "events": [
                {"ordinal": 0, "op": "evaluate-base", "subject": "items()"},
                {"ordinal": 1, "op": "evaluate-selector", "subject": "index()"},
                {"ordinal": 2, "op": "acquire-unique-place", "subject": "place-0"},
                {"ordinal": 3, "op": "evaluate-rhs", "subject": "value()"},
                {"ordinal": 4, "op": "write", "subject": "place-0"},
                {"ordinal": 5, "op": "release-unique-place", "subject": "place-0"},
            ],
            "expected": {
                "base_evaluations": 1,
                "selector_evaluations": 1,
                "rhs_evaluations": 1,
                "writes": 1,
                "unique_borrow_released": True,
                "order": [
                    "evaluate-base",
                    "evaluate-selector",
                    "acquire-unique-place",
                    "evaluate-rhs",
                    "write",
                    "release-unique-place",
                ],
            },
        },
        "control_cases": [
            {
                "id": "break-never-join",
                "mode": "structural",
                "outcome": "BreakTransferContributesNeverV1",
            },
            {
                "id": "continue-never-join",
                "mode": "structural",
                "outcome": "ContinueTransferContributesNeverV1",
            },
            {
                "id": "ctl-multi-shot-mutable-capture",
                "mode": "ctl",
                "outcome": "MultiShotMutableCaptureRejectedV1",
            },
            {
                "id": "once-unique-place-no-alias",
                "mode": "once",
                "outcome": "OneShotUniqueNoAliasAcceptedV1",
            },
            {
                "id": "return-never-join",
                "mode": "structural",
                "outcome": "ReturnTransferContributesNeverV1",
            },
            {
                "id": "suspend-with-live-place",
                "mode": "once",
                "outcome": "SuspendWithLivePlaceRejectedV1",
            },
        ],
        "structural_judgment_cases": [
            {
                "id": "for-body-not-many-reject",
                "construct": "ForV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": True,
                "body_many_safe": False,
                "expected": "ForBodyNotManySafeRejectedV1",
            },
            {
                "id": "for-irrefutable-many-unit",
                "construct": "ForV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": True,
                "body_many_safe": True,
                "expected": "UnitV1",
            },
            {
                "id": "for-refutable-binder-reject",
                "construct": "ForV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": False,
                "body_many_safe": True,
                "expected": "ForBinderRefutableRejectedV1",
            },
            {
                "id": "loop-bare-break-unit",
                "construct": "LoopV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 1,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "UnitV1",
            },
            {
                "id": "loop-break-value-join-int",
                "construct": "LoopV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": ["Int", "Int"],
                "bare_break_count": 0,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "IntV1",
            },
            {
                "id": "loop-no-break-never",
                "construct": "LoopV1",
                "condition_type": None,
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "NeverV1",
            },
            {
                "id": "while-body-not-unit-reject",
                "construct": "WhileV1",
                "condition_type": "Bool",
                "body_type": "Int",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "WhileBodyNotUnitRejectedV1",
            },
            {
                "id": "while-bool-unit",
                "construct": "WhileV1",
                "condition_type": "Bool",
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "UnitV1",
            },
            {
                "id": "while-condition-not-bool-reject",
                "construct": "WhileV1",
                "condition_type": "Int",
                "body_type": "Unit",
                "break_value_types": [],
                "bare_break_count": 0,
                "binder_irrefutable": None,
                "body_many_safe": None,
                "expected": "WhileConditionNotBoolRejectedV1",
            },
        ],
        "place_cases": [
            {
                "id": "captured-by-resumption",
                "outcome": "MutablePlaceCaptureRejectedV1",
            },
            {
                "id": "escape-through-return",
                "outcome": "MutablePlaceEscapeRejectedV1",
            },
            {
                "id": "selector-rhs-write-once",
                "outcome": "OrderedExactlyOnceAcceptedV1",
            },
        ],
        "place_judgment_cases": [
            {
                "id": "array-sealed-update",
                "target_kind": "ArrayElementV1",
                "base_evaluations": 1,
                "selector_evaluations": 1,
                "field_visibility": "AccessibleV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": False,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "AcceptedUniquePlaceV1",
            },
            {
                "id": "field-base-visibility",
                "target_kind": "MutableFieldV1",
                "base_evaluations": 1,
                "selector_evaluations": 0,
                "field_visibility": "AccessibleV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": False,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "AcceptedUniquePlaceV1",
            },
            {
                "id": "hidden-field-reject",
                "target_kind": "MutableFieldV1",
                "base_evaluations": 1,
                "selector_evaluations": 0,
                "field_visibility": "HiddenV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": False,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "FieldVisibilityRejectedV1",
            },
            {
                "id": "nonescaping-borrow",
                "target_kind": "MutableFieldV1",
                "base_evaluations": 1,
                "selector_evaluations": 0,
                "field_visibility": "AccessibleV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": False,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "AcceptedUniquePlaceV1",
            },
            {
                "id": "owner-stored-closure-reject",
                "target_kind": "MutableFieldV1",
                "base_evaluations": 1,
                "selector_evaluations": 0,
                "field_visibility": "AccessibleV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": True,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "OwnerStoredClosureCaptureRejectedV1",
            },
            {
                "id": "user-mutable-index-reject",
                "target_kind": "UserMutableIndexV1",
                "base_evaluations": 1,
                "selector_evaluations": 1,
                "field_visibility": "AccessibleV1",
                "borrow_escapes": False,
                "suspends": False,
                "owner_stored": False,
                "multi_shot_capture": False,
                "unique_alias_count": 1,
                "expected": "UserMutableIndexRejectedV1",
            },
        ],
    }


def v1_structural_judgment(case: Mapping[str, Any]) -> str:
    construct = case["construct"]
    if construct == "LoopV1":
        values = list(case["break_value_types"])
        values.extend(["Unit"] * case["bare_break_count"])
        if not values:
            return "NeverV1"
        if len(set(values)) == 1:
            return values[0] + "V1"
        return "IncompatibleBreakValueTypesRejectedV1"
    if construct == "WhileV1":
        if case["condition_type"] != "Bool":
            return "WhileConditionNotBoolRejectedV1"
        if case["body_type"] != "Unit":
            return "WhileBodyNotUnitRejectedV1"
        return "UnitV1"
    if construct == "ForV1":
        if case["binder_irrefutable"] is not True:
            return "ForBinderRefutableRejectedV1"
        if case["body_many_safe"] is not True:
            return "ForBodyNotManySafeRejectedV1"
        if case["body_type"] != "Unit":
            return "ForBodyNotUnitRejectedV1"
        return "UnitV1"
    fail("Decode/enum-mismatch", "unknown structural judgment construct")


def v1_place_judgment(case: Mapping[str, Any]) -> str:
    target = case["target_kind"]
    if target == "UserMutableIndexV1":
        return "UserMutableIndexRejectedV1"
    if target not in {"MutableFieldV1", "ArrayElementV1"}:
        fail("Decode/enum-mismatch", "unknown mutable place target kind")
    expected_selectors = 1 if target == "ArrayElementV1" else 0
    if case["base_evaluations"] != 1 or case["selector_evaluations"] != expected_selectors:
        return "EvaluationMultiplicityRejectedV1"
    if case["field_visibility"] != "AccessibleV1":
        return "FieldVisibilityRejectedV1"
    if case["borrow_escapes"]:
        return "MutablePlaceEscapeRejectedV1"
    if case["suspends"]:
        return "SuspendWithLivePlaceRejectedV1"
    if case["owner_stored"]:
        return "OwnerStoredClosureCaptureRejectedV1"
    if case["multi_shot_capture"]:
        return "MultiShotMutableCaptureRejectedV1"
    if case["unique_alias_count"] != 1:
        return "UniqueAliasViolationRejectedV1"
    return "AcceptedUniquePlaceV1"


def v1_validate_control_mutation(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "handler_elaboration_differential",
            "structural_forms",
            "place_trace",
            "control_cases",
            "place_cases",
            "structural_judgment_cases",
            "place_judgment_cases",
        ],
        "ControlMutationOracleV1",
    )
    validate_profile_header(
        root,
        "ControlMutationOracleV1",
        1,
        "runtime-protocol-trace-mismatch",
    )
    handler_pair = v1_closed(
        root["handler_elaboration_differential"],
        ["alpha_origin_erasure", "full", "inline", "diagnostic_equivalence"],
        "HandlerElaborationDifferentialV1",
    )
    if handler_pair["alpha_origin_erasure"] != [
        "fresh_prompt",
        "origin",
        "prompt_ref",
    ]:
        fail(
            "callable-interface-contract-mismatch",
            "handler alpha/origin erasure field vector differs",
        )
    variants = []
    for name in ("full", "inline"):
        variant = v1_closed(
            handler_pair[name],
            ["source_form", "source", "projection"],
            name + " handler elaboration",
        )
        v1_string(variant["source_form"], name + " handler source form")
        v1_string(variant["source"], name + " handler source")
        if not isinstance(variant["projection"], dict):
            fail("Decode/object-mismatch", name + " handler projection is not an object")
        variants.append(variant)
    full_projection, inline_projection = (
        variants[0]["projection"],
        variants[1]["projection"],
    )
    if full_projection == inline_projection:
        fail(
            "callable-interface-contract-mismatch",
            "full and inline handler origins/prompts were not preserved",
        )
    if erase_handler_alpha_origin(full_projection) != erase_handler_alpha_origin(
        inline_projection
    ):
        fail(
            "callable-interface-contract-mismatch",
            "full and inline handlers differ after alpha/origin erasure",
        )
    diagnostic = v1_closed(
        handler_pair["diagnostic_equivalence"],
        ["full_source", "inline_source", "id", "stage"],
        "HandlerDiagnosticEquivalenceV1",
    )
    if diagnostic["id"] != "handler-clause-mode-required" or diagnostic[
        "stage"
    ] != "Syntax":
        fail(
            "handler-clause-mode-required",
            "full/inline missing-mode diagnostic code or stage differs",
        )
    forms = require_list(
        root["structural_forms"], "Decode/array-mismatch", "structural forms"
    )
    for form in forms:
        v1_closed(
            form,
            ["source", "lowering", "evaluation"],
            "StructuralControlFormV1",
        )
    trace = v1_closed(root["place_trace"], ["events", "expected"], "PlaceTraceV1")
    events = require_list(trace["events"], "Decode/array-mismatch", "place events")
    operations = []
    for ordinal, event in enumerate(events):
        item = v1_closed(
            event, ["ordinal", "op", "subject"], "PlaceTraceEventV1"
        )
        if v1_u32(item["ordinal"], "place event ordinal") != ordinal:
            fail("runtime-protocol-trace-mismatch", "place event order differs")
        operations.append(v1_string(item["op"], "place operation"))
    expected = v1_closed(
        trace["expected"],
        [
            "base_evaluations",
            "selector_evaluations",
            "rhs_evaluations",
            "writes",
            "unique_borrow_released",
            "order",
        ],
        "PlaceTraceExpectedV1",
    )
    replayed = {
        "base_evaluations": operations.count("evaluate-base"),
        "selector_evaluations": operations.count("evaluate-selector"),
        "rhs_evaluations": operations.count("evaluate-rhs"),
        "writes": operations.count("write"),
        "unique_borrow_released": bool(operations)
        and operations[-1] == "release-unique-place",
        "order": operations,
    }
    if replayed != expected:
        fail(
            "runtime-protocol-trace-mismatch",
            "mutable place selector/RHS/write replay differs",
        )
    for field in ("control_cases", "place_cases"):
        cases = require_list(root[field], "Decode/array-mismatch", field)
        identifiers = []
        for case in cases:
            required = ["id", "outcome"] + (["mode"] if field == "control_cases" else [])
            item = v1_closed(case, required, field + " case")
            identifiers.append(v1_string(item["id"], field + " id"))
        if identifiers != sorted(identifiers) or len(identifiers) != len(set(identifiers)):
            fail("runtime-protocol-trace-mismatch", field + " order differs")
    structural_cases = require_list(
        root["structural_judgment_cases"],
        "Decode/array-mismatch",
        "structural judgment cases",
    )
    structural_ids = []
    for case in structural_cases:
        item = v1_closed(
            case,
            [
                "id",
                "construct",
                "condition_type",
                "body_type",
                "break_value_types",
                "bare_break_count",
                "binder_irrefutable",
                "body_many_safe",
                "expected",
            ],
            "StructuralJudgmentCaseV1",
        )
        structural_ids.append(v1_string(item["id"], "structural judgment id"))
        construct = v1_string(item["construct"], "structural judgment construct")
        if construct not in {"LoopV1", "WhileV1", "ForV1"}:
            fail("Decode/enum-mismatch", "unknown structural judgment construct")
        condition_type = item["condition_type"]
        if condition_type is not None:
            v1_string(condition_type, "structural condition type")
        v1_string(item["body_type"], "structural body type")
        for break_type in require_list(
            item["break_value_types"],
            "Decode/array-mismatch",
            "structural break value types",
        ):
            v1_string(break_type, "structural break value type")
        v1_u32(item["bare_break_count"], "structural bare break count")
        for field in ("binder_irrefutable", "body_many_safe"):
            member = item[field]
            if member is not None and not isinstance(member, bool):
                fail("Decode/bool-mismatch", field + " is not bool or null")
        v1_string(item["expected"], "structural expected result")
        if construct == "LoopV1":
            if (
                condition_type is not None
                or item["binder_irrefutable"] is not None
                or item["body_many_safe"] is not None
            ):
                fail(
                    "runtime-protocol-trace-mismatch",
                    "loop judgment carries inapplicable fields",
                )
        elif construct == "WhileV1":
            if (
                item["break_value_types"]
                or item["bare_break_count"] != 0
                or item["binder_irrefutable"] is not None
                or item["body_many_safe"] is not None
            ):
                fail(
                    "runtime-protocol-trace-mismatch",
                    "while judgment carries inapplicable fields",
                )
        elif (
            condition_type is not None
            or item["break_value_types"]
            or item["bare_break_count"] != 0
            or not isinstance(item["binder_irrefutable"], bool)
            or not isinstance(item["body_many_safe"], bool)
        ):
            fail(
                "runtime-protocol-trace-mismatch",
                "for judgment fields are not canonical",
            )
        if item["expected"] != v1_structural_judgment(item):
            fail(
                "runtime-protocol-trace-mismatch",
                "structural judgment result differs",
            )
    if structural_ids != sorted(structural_ids) or len(structural_ids) != len(
        set(structural_ids)
    ):
        fail(
            "runtime-protocol-trace-mismatch",
            "structural judgment case order differs",
        )
    place_judgments = require_list(
        root["place_judgment_cases"],
        "Decode/array-mismatch",
        "place judgment cases",
    )
    place_ids = []
    for case in place_judgments:
        item = v1_closed(
            case,
            [
                "id",
                "target_kind",
                "base_evaluations",
                "selector_evaluations",
                "field_visibility",
                "borrow_escapes",
                "suspends",
                "owner_stored",
                "multi_shot_capture",
                "unique_alias_count",
                "expected",
            ],
            "PlaceJudgmentCaseV1",
        )
        place_ids.append(v1_string(item["id"], "place judgment id"))
        target_kind = v1_string(item["target_kind"], "place target kind")
        if target_kind not in {
            "ArrayElementV1",
            "MutableFieldV1",
            "UserMutableIndexV1",
        }:
            fail("Decode/enum-mismatch", "unknown mutable place target kind")
        for field in (
            "base_evaluations",
            "selector_evaluations",
            "unique_alias_count",
        ):
            v1_u32(item[field], "place " + field)
        if item["field_visibility"] not in {"AccessibleV1", "HiddenV1"}:
            fail("Decode/enum-mismatch", "unknown mutable field visibility")
        for field in (
            "borrow_escapes",
            "suspends",
            "owner_stored",
            "multi_shot_capture",
        ):
            if not isinstance(item[field], bool):
                fail("Decode/bool-mismatch", field + " is not bool")
        v1_string(item["expected"], "place expected result")
        if item["expected"] != v1_place_judgment(item):
            fail(
                "runtime-protocol-trace-mismatch",
                "mutable place judgment result differs",
            )
    if place_ids != sorted(place_ids) or len(place_ids) != len(set(place_ids)):
        fail(
            "runtime-protocol-trace-mismatch",
            "place judgment case order differs",
        )
    if root != build_control_mutation_oracle():
        fail(
            "runtime-protocol-trace-mismatch",
            "control/mutable-place oracle differs from the frozen model",
        )


def v1_validate_const(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "definitions", "evaluation_cases", "initialization_policy"], "ConstValueOracleV1")
    validate_profile_header(root, "ConstValueOracleV1", 1, "const-operation-not-safe")
    definitions = require_list(root["definitions"], "Decode/array-mismatch", "const definitions")
    if [item.get("name") for item in definitions] != [
        "decomposed",
        "greeting",
        "magic",
        "packet",
    ]:
        fail("const-operation-not-safe", "const definition order differs")
    for definition_value in definitions:
        definition = v1_closed(
            definition_value,
            ["name", "type", "effect_row", "const_safe", "value"],
            "ConstDefinitionV1",
        )
        v1_string(definition["name"], "const definition name")
        v1_string(definition["type"], "const definition type")
        if definition["const_safe"] is not True:
            fail("const-safe-requirement-failed", "const definition is not ConstSafe")
        if "effect_row" not in definition or definition["effect_row"] != "! {}":
            fail("named-function-effect-row-required", "const definition lacks explicit row")
        payload = definition.get("value")
        if not isinstance(payload, dict):
            fail("Decode/object-mismatch", "const payload is not an object")
        if payload.get("kind") == "StringConstV1":
            item = v1_closed(payload, ["kind", "utf8_bytes", "unicode_scalars"], "StringConstV1")
            octets = require_list(item["utf8_bytes"], "Decode/array-mismatch", "String bytes")
            scalars = require_list(item["unicode_scalars"], "Decode/array-mismatch", "String scalars")
            for octet in octets:
                if require_int(octet, "semantic-string-payload-mismatch", "UTF-8 byte") not in range(256):
                    fail("semantic-string-payload-mismatch", "String byte is outside u8")
            try:
                text = bytes(octets).decode("utf-8")
            except (UnicodeDecodeError, ValueError):
                fail("semantic-string-payload-mismatch", "String bytes are not canonical UTF-8")
            if [ord(character) for character in text] != scalars:
                fail("semantic-string-payload-mismatch", "String bytes and scalars differ")
            if definition["name"] == "decomposed" and (
                octets != [101, 204, 129] or scalars != [101, 769]
            ):
                fail(
                    "semantic-string-payload-mismatch",
                    "decomposed semantic String was normalized or rewritten",
                )
        elif payload.get("kind") == "BytesConstV1":
            item = v1_closed(payload, ["kind", "bytes"], "BytesConstV1")
            for octet in require_list(item["bytes"], "Decode/array-mismatch", "Bytes octets"):
                if require_int(octet, "byte-literal-out-of-range", "Bytes octet") not in range(256):
                    fail("byte-literal-out-of-range", "Bytes octet is outside u8")
        elif payload.get("kind") == "IntegerConstV1":
            v1_closed(payload, ["kind", "decimal"], "IntegerConstV1")
        else:
            fail("Decode/tag-mismatch", "unknown const payload")
    expected_evaluation_cases = [
        {
            "id": "literal-adt-and-match",
            "result": "accept",
            "value": {"kind": "IntegerConstV1", "decimal": "7"},
        },
        {
            "id": "direct-structural-recursion",
            "result": "accept",
            "value": {"kind": "IntegerConstV1", "decimal": "3"},
        },
        {
            "id": "definite-overflow",
            "result": "reject",
            "diagnostic": "const-definite-trap",
        },
        {
            "id": "mutual-recursion",
            "result": "reject",
            "diagnostic": "const-termination-not-proven",
        },
        {
            "id": "effectful-const",
            "result": "reject",
            "diagnostic": "const-safe-requirement-failed",
        },
        {
            "id": "mutable-const",
            "result": "reject",
            "diagnostic": "const-safe-requirement-failed",
        },
    ]
    evaluation_cases = require_list(
        root["evaluation_cases"], "Decode/array-mismatch", "const evaluation cases"
    )
    for case in evaluation_cases:
        if isinstance(case, dict) and case.get("result") == "accept":
            item = v1_closed(
                case, ["id", "result", "value"], "ConstAcceptCaseV1"
            )
            value = v1_closed(
                item["value"], ["kind", "decimal"], "IntegerConstV1"
            )
            if value["kind"] != "IntegerConstV1":
                fail("Decode/tag-mismatch", "const accept result has wrong value tag")
        else:
            v1_closed(
                case, ["id", "result", "diagnostic"], "ConstRejectCaseV1"
            )
    if evaluation_cases != expected_evaluation_cases:
        fail("const-operation-not-safe", "const evaluation case matrix differs")
    initialization = v1_closed(root["initialization_policy"], ["top_level_dynamic_bindings", "cross_file_initializer_order", "user_wasm_start_hook", "package_singleton_mutation"], "initialization policy")
    if any(initialization.values()):
        fail("const-operation-not-safe", "implicit initialization mechanism enabled")


LOCAL_INFERENCE_POLICY = {
    "rank": "QualifiedRank1V1",
    "binding": "ImmutableLocalLetV1",
    "generalizable_binder_order": [
        "TypeV1",
        "EffectRowV1",
        "TraitConstraintV1",
        "FnContractV1",
    ],
    "atomic_hidden_contract": "WholeFnContractOnlyV1",
    "forbidden_generalization": [
        "RowProjectionV1",
        "IdentityV1",
        "OwnerV1",
        "ClockV1",
    ],
    "numeric_default_order": [
        {"meta": "IntegerLiteralV1", "type": "Int"},
        {"meta": "FloatLiteralV1", "type": "Float"},
    ],
    "fallback": "WeakMonomorphicV1",
    "named_boundary": "EveryNamedDefExplicitV1",
}
LOCAL_INFERENCE_CASE_IDS = [
    "authority-capture-weak",
    "borrow-reachable-weak",
    "claim-reachable-weak",
    "clock-quantification-weak",
    "effectful-initializer-weak",
    "effectful-lambda-construction-generalizes",
    "generative-identity-weak",
    "mutable-cell-weak",
    "nonreplayable-cleanup-weak",
    "not-many-call-safe-weak",
    "numeric-default-before-generalization",
    "open-constraints-weak",
    "owner-quantification-weak",
    "resumption-weak",
    "row-projection-weak",
    "safe-value-generalizes",
    "unstable-environment-weak",
    "weak-monomorphism-expansive",
]
LOCAL_BOUNDARY_CASE_IDS = [
    "local-lambda-inferred",
    "named-def-explicit-effectful",
    "named-def-explicit-pure",
    "named-def-missing-effect-row",
    "named-def-missing-generic-boundary",
    "named-def-missing-parameter-type",
    "named-def-missing-result-type",
    "named-def-unsolved-meta",
]
LOCAL_REACHABLE_BLOCKERS = {
    "MutableCellV1": "ReachableMutableCellV1",
    "BorrowV1": "ReachableBorrowV1",
    "ResumptionV1": "ReachableResumptionV1",
    "ClaimV1": "ReachableClaimV1",
    "NonReplayableCleanupV1": "NonReplayableCleanupV1",
}
LOCAL_GENERATIVE_BLOCKERS = {
    "IdentityV1": "GenerativeIdentityV1",
    "OwnerV1": "OwnerQuantificationV1",
    "ClockV1": "ClockQuantificationV1",
}


def v1_local_bool(value: Any, context: str) -> bool:
    if not isinstance(value, bool):
        fail("Decode/boolean-mismatch", context + " must be a boolean")
    return value


def v1_local_ordered_strings(
    value: Any,
    *,
    context: str,
    order: Sequence[str] | None = None,
) -> List[str]:
    items = require_list(value, "Decode/array-mismatch", context)
    strings = [v1_string(item, context + " entry") for item in items]
    if len(strings) != len(set(strings)):
        fail(
            "callable-interface-contract-mismatch",
            context + " contains a duplicate",
        )
    if order is None:
        canonical = sorted(strings)
    else:
        allowed = {item: index for index, item in enumerate(order)}
        if any(item not in allowed for item in strings):
            fail("Decode/enum-mismatch", context + " has an unknown entry")
        canonical = sorted(strings, key=allowed.__getitem__)
    if strings != canonical:
        fail(
            "callable-interface-contract-mismatch",
            context + " is not in canonical order",
        )
    return strings


def v1_validate_local_inference(value: Any) -> None:
    root = v1_closed(
        value,
        [
            "artifact",
            "profile",
            "schema_version",
            "policy",
            "generalization_cases",
            "named_boundary_cases",
        ],
        "LocalInferenceOracleV1",
    )
    validate_profile_header(
        root,
        "LocalInferenceOracleV1",
        1,
        "callable-interface-contract-mismatch",
    )
    policy = v1_closed(
        root["policy"],
        [
            "rank",
            "binding",
            "generalizable_binder_order",
            "atomic_hidden_contract",
            "forbidden_generalization",
            "numeric_default_order",
            "fallback",
            "named_boundary",
        ],
        "LocalInferencePolicyV1",
    )
    if policy != LOCAL_INFERENCE_POLICY:
        fail(
            "callable-interface-contract-mismatch",
            "local inference policy differs",
        )
    all_binders = (
        LOCAL_INFERENCE_POLICY["generalizable_binder_order"]
        + LOCAL_INFERENCE_POLICY["forbidden_generalization"]
    )
    numeric_order = [
        entry["meta"]
        for entry in LOCAL_INFERENCE_POLICY["numeric_default_order"]
    ]
    numeric_by_meta = {
        entry["meta"]: entry
        for entry in LOCAL_INFERENCE_POLICY["numeric_default_order"]
    }
    cases = require_list(
        root["generalization_cases"],
        "Decode/array-mismatch",
        "local inference cases",
    )
    if [case.get("id") for case in cases if isinstance(case, dict)] != (
        LOCAL_INFERENCE_CASE_IDS
    ):
        fail(
            "callable-interface-contract-mismatch",
            "local inference case IDs/order differ",
        )
    for case_value in cases:
        case = v1_closed(
            case_value,
            ["id", "facts", "expected"],
            "LocalInferenceCaseV1",
        )
        identifier = v1_string(case["id"], "local inference case id")
        facts = v1_closed(
            case["facts"],
            [
                "binding",
                "initializer",
                "non_expansive",
                "construction_effects",
                "body_effects",
                "authority_captures",
                "environment_stability",
                "many_call_safe",
                "reachable_state",
                "generative_quantification",
                "constraints_closed",
                "candidate_binders",
                "numeric_metas",
            ],
            identifier + ".facts",
        )
        if facts["binding"] != LOCAL_INFERENCE_POLICY["binding"]:
            fail(
                "callable-interface-contract-mismatch",
                identifier + " is not an immutable local let",
            )
        if facts["initializer"] not in {
            "ValueV1",
            "LambdaConstructionV1",
            "ComputationV1",
        }:
            fail(
                "Decode/enum-mismatch",
                identifier + " has an unknown initializer class",
            )
        non_expansive = v1_local_bool(
            facts["non_expansive"], identifier + ".non_expansive"
        )
        construction_effects = v1_local_ordered_strings(
            facts["construction_effects"],
            context=identifier + ".construction_effects",
        )
        body_effects = v1_local_ordered_strings(
            facts["body_effects"],
            context=identifier + ".body_effects",
        )
        authority_captures = v1_local_ordered_strings(
            facts["authority_captures"],
            context=identifier + ".authority_captures",
        )
        if facts["environment_stability"] not in {
            "StableDuplicableV1",
            "UnstableOrLinearV1",
        }:
            fail(
                "Decode/enum-mismatch",
                identifier + " has an unknown environment stability",
            )
        many_call_safe = v1_local_bool(
            facts["many_call_safe"], identifier + ".many_call_safe"
        )
        reachable = v1_local_ordered_strings(
            facts["reachable_state"],
            context=identifier + ".reachable_state",
            order=list(LOCAL_REACHABLE_BLOCKERS),
        )
        generative = v1_local_ordered_strings(
            facts["generative_quantification"],
            context=identifier + ".generative_quantification",
            order=list(LOCAL_GENERATIVE_BLOCKERS),
        )
        constraints_closed = v1_local_bool(
            facts["constraints_closed"], identifier + ".constraints_closed"
        )
        candidates = v1_local_ordered_strings(
            facts["candidate_binders"],
            context=identifier + ".candidate_binders",
            order=all_binders,
        )
        numeric_metas = v1_local_ordered_strings(
            facts["numeric_metas"],
            context=identifier + ".numeric_metas",
            order=numeric_order,
        )
        numeric_defaults = [
            copy.deepcopy(numeric_by_meta[meta]) for meta in numeric_metas
        ]
        if construction_effects:
            reason = "EffectfulInitializerV1"
        elif facts["initializer"] == "ComputationV1" or not non_expansive:
            reason = "ExpansiveInitializerV1"
        elif authority_captures:
            reason = "AuthorityCaptureV1"
        elif facts["environment_stability"] != "StableDuplicableV1":
            reason = "UnstableEnvironmentV1"
        elif not many_call_safe:
            reason = "NotManyCallSafeV1"
        elif reachable:
            reason = LOCAL_REACHABLE_BLOCKERS[reachable[0]]
        elif generative:
            reason = LOCAL_GENERATIVE_BLOCKERS[generative[0]]
        elif not constraints_closed:
            reason = "OpenConstraintsV1"
        elif any(
            binder in LOCAL_INFERENCE_POLICY["forbidden_generalization"]
            for binder in candidates
        ):
            reason = "ForbiddenBinderKindV1"
        else:
            reason = "EligibleV1"
        generalizes = reason == "EligibleV1"
        observed = {
            "decision": "GeneralizeV1" if generalizes else "WeakMonomorphicV1",
            "reason": reason,
            "generalized_binders": candidates if generalizes else [],
            "weak_binders": [] if generalizes else candidates,
            "numeric_defaults": numeric_defaults,
            "phase_trace": [
                "SolveExpectedTypesV1",
                "DefaultNumericMetasV1",
                "GeneralizeV1" if generalizes else "KeepWeakMonomorphicV1",
            ],
            "body_effects": body_effects,
        }
        expected = v1_closed(
            case["expected"],
            [
                "decision",
                "reason",
                "generalized_binders",
                "weak_binders",
                "numeric_defaults",
                "phase_trace",
                "body_effects",
            ],
            identifier + ".expected",
        )
        for default_value in require_list(
            expected["numeric_defaults"],
            "Decode/array-mismatch",
            identifier + ".expected.numeric_defaults",
        ):
            v1_closed(
                default_value,
                ["meta", "type"],
                identifier + ".expected.numeric_default",
            )
        if expected != observed:
            fail(
                "callable-interface-contract-mismatch",
                identifier + " local generalization result differs",
            )
    boundary_cases = require_list(
        root["named_boundary_cases"],
        "Decode/array-mismatch",
        "named boundary cases",
    )
    if [
        case.get("id") for case in boundary_cases if isinstance(case, dict)
    ] != LOCAL_BOUNDARY_CASE_IDS:
        fail(
            "callable-interface-contract-mismatch",
            "named boundary case IDs/order differ",
        )
    for case_value in boundary_cases:
        case = v1_closed(
            case_value,
            [
                "id",
                "boundary_kind",
                "visibility",
                "generic_boundary_explicit",
                "parameter_types_explicit",
                "result_type_explicit",
                "effect_row",
                "unsolved_meta_count",
                "expected",
            ],
            "NamedBoundaryCaseV1",
        )
        identifier = v1_string(case["id"], "named boundary case id")
        explicit = [
            v1_local_bool(
                case["generic_boundary_explicit"],
                identifier + ".generic_boundary_explicit",
            ),
            v1_local_bool(
                case["parameter_types_explicit"],
                identifier + ".parameter_types_explicit",
            ),
            v1_local_bool(
                case["result_type_explicit"],
                identifier + ".result_type_explicit",
            ),
        ]
        unsolved = v1_u32(
            case["unsolved_meta_count"], identifier + ".unsolved_meta_count"
        )
        if case["boundary_kind"] == "LocalLambdaV1":
            if (
                case["visibility"] is not None
                or any(explicit)
                or case["effect_row"] is not None
            ):
                fail(
                    "callable-interface-contract-mismatch",
                    identifier + " is not a local inference boundary",
                )
            observed_boundary = {"kind": "LocalInferenceV1"}
        elif case["boundary_kind"] == "NamedDefV1":
            if case["visibility"] not in {"PrivateV1", "PublicV1"}:
                fail(
                    "Decode/enum-mismatch",
                    identifier + " has an unknown named visibility",
                )
            effect_row = case["effect_row"]
            if effect_row is not None:
                effect_row = v1_string(effect_row, identifier + ".effect_row")
                if not effect_row.startswith("! {") or not effect_row.endswith("}"):
                    fail(
                        "named-function-effect-row-required",
                        identifier + " does not spell a complete effect row",
                    )
            if effect_row is None:
                observed_boundary = {
                    "kind": "DiagnosticV1",
                    "id": "named-function-effect-row-required",
                }
            elif not all(explicit) or unsolved != 0:
                observed_boundary = {
                    "kind": "DiagnosticV1",
                    "id": "callable-interface-contract-mismatch",
                }
            else:
                observed_boundary = {"kind": "AcceptedV1"}
        else:
            fail(
                "Decode/enum-mismatch",
                identifier + " has an unknown boundary kind",
            )
        expected_boundary_value = case["expected"]
        if not isinstance(expected_boundary_value, dict):
            fail(
                "Decode/object-mismatch",
                identifier + ".expected must be an object",
            )
        expected_fields = (
            ["kind", "id"]
            if expected_boundary_value.get("kind") == "DiagnosticV1"
            else ["kind"]
        )
        expected_boundary = v1_closed(
            expected_boundary_value,
            expected_fields,
            identifier + ".expected",
        )
        if expected_boundary != observed_boundary:
            fail(
                "callable-interface-contract-mismatch",
                identifier + " named-boundary result differs",
            )


def v1_callable_edge(value: Any, context: str) -> None:
    edge = v1_closed(value, ["module", "export_path", "callable_interface"], context)
    v1_module(edge["module"], context + ".module")
    if edge["module"] != [PACKAGE_MODULE, "root"] or edge["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", context + " identity differs")
    v1_hash_ref(edge["callable_interface"], "CallableInterfaceV1", "callable-interface-contract-mismatch")


def v1_validate_component_manifest(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "package", "name", "imports", "exports"], "ComponentManifestV1")
    validate_profile_header(root, "ComponentManifestV1", 1, "component-public-type-not-safe")
    v1_package_instance(root["package"], "component manifest package")
    if root["name"] != "foundation" or root["imports"] != []:
        fail("component-public-type-not-safe", "component manifest selection differs")
    exports = require_list(root["exports"], "Decode/array-mismatch", "component manifest exports")
    paths: List[bytes] = []
    for export_value in exports:
        export = v1_closed(export_value, ["wit_path", "item"], "ComponentExportV1")
        path = require_list(export["wit_path"], "Decode/array-mismatch", "component WIT path")
        if not path:
            fail("component-public-type-not-safe", "component WIT path is empty")
        for segment in path:
            v1_string(segment, "component WIT segment")
        paths.append(canonical_bytes(path))
        item_value = export["item"]
        if not isinstance(item_value, dict):
            fail("Decode/object-mismatch", "component manifest item is not an object")
        item_kind = item_value.get("kind")
        if item_kind == "CallableComponentItemV1":
            item = v1_closed(item_value, ["kind", "callable"], item_kind)
            v1_callable_edge(item["callable"], "manifest callable")
        elif item_kind in {"DataComponentItemV1", "ResourceComponentItemV1"}:
            item = v1_closed(item_value, ["kind", "declaration"], item_kind)
            v1_declaration_identity(item["declaration"], "manifest declaration")
        else:
            fail("Decode/tag-mismatch", "component manifest item tag differs")
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        fail("component-public-type-not-safe", "component manifest paths are not canonical")
    if root != build_component_manifest():
        fail("component-public-type-not-safe", "component manifest selection differs")


def v1_validate_link(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "package_instance_id", "language_interface", "compiler_abi_epoch", "runtime_abi_epoch", "target", "calling_convention", "callable_layouts", "data_layouts"], "CireLinkAbiV1")
    validate_profile_header(root, "CireLinkAbiV1", 1, "component-public-type-not-safe")
    v1_package_instance(root["package_instance_id"], "link package")
    v1_hash_ref(root["language_interface"], "CireLanguageInterfaceV1", "callable-interface-contract-mismatch")
    if root["compiler_abi_epoch"] != "cirec-abi-v1" or root["runtime_abi_epoch"] != "cire-runtime-v1" or root["calling_convention"] != "CirePrivateWasmCallV1":
        fail("component-public-type-not-safe", "link ABI epoch/convention differs")
    target = v1_closed(root["target"], ["validation", "memory", "memory_sharing", "multi_value", "bulk_memory", "indirect_calls", "memory64", "gc_identity", "exception_handling", "native_continuations", "stack_switching", "tail_call_semantics", "simd", "relaxed_simd", "threads", "atomics"], "CireWasmTargetV1")
    expected_target = {"validation": "Wasm3.0V1", "memory": "Memory32V1", "memory_sharing": "NonSharedV1", "multi_value": True, "bulk_memory": True, "indirect_calls": "OrdinaryV1", "memory64": False, "gc_identity": False, "exception_handling": False, "native_continuations": False, "stack_switching": False, "tail_call_semantics": False, "simd": False, "relaxed_simd": False, "threads": False, "atomics": False}
    if target != expected_target:
        fail("component-public-type-not-safe", "Wasm target differs")
    callables = require_list(root["callable_layouts"], "Decode/array-mismatch", "callable layouts")
    if len(callables) != 1:
        fail("callable-interface-contract-mismatch", "link callable closure differs")
    layout = v1_closed(callables[0], ["module", "export_path", "callable_interface_hash", "core_wasm_signature_hash"], "CireCallableLinkEntryV1")
    v1_module(layout["module"], "link callable module")
    if layout["export_path"] != ["identity"]:
        fail("callable-interface-contract-mismatch", "link callable export differs")
    for field in ("callable_interface_hash", "core_wasm_signature_hash"):
        if not isinstance(layout[field], str) or not SHA256_RE.fullmatch(layout[field]) or layout[field] == ZERO_HASH:
            fail("callable-interface-contract-mismatch", "link callable hash differs")
    data = require_list(root["data_layouts"], "Decode/array-mismatch", "data layouts")
    data_keys: List[bytes] = []
    for layout_value in data:
        data_layout = v1_closed(
            layout_value,
            ["declaration", "private_layout_hash"],
            "CireDataLayoutEntryV1",
        )
        v1_declaration_identity(data_layout["declaration"], "link data declaration")
        if (
            not isinstance(data_layout["private_layout_hash"], str)
            or not SHA256_RE.fullmatch(data_layout["private_layout_hash"])
            or data_layout["private_layout_hash"] == ZERO_HASH
        ):
            fail("component-public-type-not-safe", "private layout hash differs")
        data_keys.append(canonical_bytes(data_layout["declaration"]))
    if data_keys != sorted(data_keys) or len(data_keys) != len(set(data_keys)):
        fail("component-public-type-not-safe", "link data layouts are not canonical")
    if root != build_link_abi():
        fail("component-public-type-not-safe", "link ABI differs from deterministic generation")


def v1_component_nominal_pair(source: Any, declaration: Any, context: str) -> None:
    v1_validate_m3_type(source, {}, context + ".source")
    v1_declaration_identity(declaration, context + ".declaration")
    if not isinstance(source, dict) or source.get("kind") != "NominalTypeV2":
        fail("component-public-type-not-safe", context + " source is not nominal")
    if (
        source.get("module")
        != declaration["module"] + declaration["path"][:-1]
        or source.get("name") != declaration["path"][-1]
    ):
        fail(
            "component-public-type-not-safe",
            context + " source/declaration identity split differs",
        )


def v1_component_fields(value: Any, context: str) -> None:
    fields = require_list(value, "Decode/array-mismatch", context)
    names: List[str] = []
    for ordinal, field_value in enumerate(fields):
        field = v1_closed(
            field_value,
            ["ordinal", "name", "type"],
            "ComponentRecordFieldV1",
        )
        if v1_u32(field["ordinal"], context + " ordinal") != ordinal:
            fail("component-public-type-not-safe", context + " ordinals differ")
        names.append(v1_string(field["name"], context + " name"))
        v1_component_type(field["type"], context + "/" + str(ordinal))
    if len(names) != len(set(names)):
        fail("component-public-type-not-safe", context + " names are duplicated")


def v1_component_type(value: Any, context: str) -> None:
    if not isinstance(value, dict):
        fail("Decode/object-mismatch", context + " must be an object")
    kind = value.get("kind")
    if kind == "ScalarV1":
        item = v1_closed(value, ["kind", "scalar"], context)
        if item["scalar"] not in {"BoolV1", "S8V1", "S16V1", "S32V1", "S64V1", "U8V1", "U16V1", "U32V1", "U64V1", "F32V1", "F64V1", "CharV1"}:
            fail("Decode/enum-mismatch", context + " scalar differs")
    elif kind == "StringV1":
        item = v1_closed(value, ["kind", "encoding"], context)
        if item["encoding"] != "Utf8V1":
            fail("component-public-type-not-safe", "String mapping is not UTF-8")
    elif kind == "ListV1":
        item = v1_closed(value, ["kind", "element"], context)
        v1_component_type(item["element"], context + ".element")
    elif kind == "TupleV1":
        item = v1_closed(value, ["kind", "elements"], context)
        for index, element in enumerate(
            require_list(item["elements"], "Decode/array-mismatch", context)
        ):
            v1_component_type(element, context + "/" + str(index))
    elif kind == "RecordV1":
        item = v1_closed(
            value,
            ["kind", "source", "declaration", "fields"],
            "RecordV1",
        )
        v1_component_nominal_pair(item["source"], item["declaration"], context)
        v1_component_fields(item["fields"], context + ".fields")
    elif kind == "RecordPayloadV1":
        item = v1_closed(value, ["kind", "fields"], "RecordPayloadV1")
        v1_component_fields(item["fields"], context + ".fields")
    elif kind == "VariantV1":
        item = v1_closed(
            value,
            ["kind", "source", "declaration", "cases"],
            "VariantV1",
        )
        v1_component_nominal_pair(item["source"], item["declaration"], context)
        cases = require_list(item["cases"], "Decode/array-mismatch", context)
        names: List[str] = []
        for ordinal, case_value in enumerate(cases):
            case = v1_closed(
                case_value,
                ["ordinal", "name", "payload"],
                "ComponentVariantCaseV1",
            )
            if v1_u32(case["ordinal"], context + " case ordinal") != ordinal:
                fail("component-public-type-not-safe", context + " case ordinals differ")
            names.append(v1_string(case["name"], context + " case name"))
            if case["payload"] is not None:
                v1_component_type(case["payload"], context + ".payload")
        if len(names) != len(set(names)):
            fail("component-public-type-not-safe", context + " case names are duplicated")
    elif kind == "OptionV1":
        item = v1_closed(value, ["kind", "value"], "OptionV1")
        v1_component_type(item["value"], context + ".value")
    elif kind == "ResultV1":
        item = v1_closed(value, ["kind", "ok", "error"], "ResultV1")
        for field in ("ok", "error"):
            if item[field] is not None:
                v1_component_type(item[field], context + "." + field)
    elif kind == "ResourceV1":
        item = v1_closed(
            value,
            ["kind", "source", "declaration"],
            "ResourceV1",
        )
        v1_component_nominal_pair(item["source"], item["declaration"], context)
    else:
        fail("Decode/tag-mismatch", context + " uses an unknown ComponentAbiTypeV1 tag")


def v1_canonical_component_type(source: Any) -> Dict[str, Any]:
    v1_validate_m3_type(source, {}, "component source type")
    builtin = v1_type_builtin_name(source)
    scalar = {
        "Bool": "BoolV1",
        "Int8": "S8V1",
        "Int16": "S16V1",
        "Int": "S32V1",
        "Int64": "S64V1",
        "UInt8": "U8V1",
        "UInt16": "U16V1",
        "UInt": "U32V1",
        "UInt64": "U64V1",
        "Float32": "F32V1",
        "Float": "F64V1",
        "Char": "CharV1",
    }.get(builtin)
    if scalar is not None:
        return {"kind": "ScalarV1", "scalar": scalar}
    if builtin == "Unit":
        return {"kind": "TupleV1", "elements": []}
    if builtin == "String":
        return {"kind": "StringV1", "encoding": "Utf8V1"}
    if builtin == "Bytes":
        return {
            "kind": "ListV1",
            "element": {"kind": "ScalarV1", "scalar": "U8V1"},
        }
    if builtin == "Never":
        fail("component-public-type-not-safe", "Never is not ComponentSafe")
    application = v1_type_application(source)
    if application is not None:
        constructor, arguments = application
        if constructor == "Array" and len(arguments) == 1:
            return {
                "kind": "ListV1",
                "element": v1_canonical_component_type(arguments[0]),
            }
        if constructor == "Option" and len(arguments) == 1:
            return {
                "kind": "OptionV1",
                "value": v1_canonical_component_type(arguments[0]),
            }
        if constructor == "Result" and len(arguments) == 2:
            return {
                "kind": "ResultV1",
                "ok": None
                if v1_type_builtin_name(arguments[0]) == "Unit"
                else v1_canonical_component_type(arguments[0]),
                "error": None
                if v1_type_builtin_name(arguments[1]) == "Unit"
                else v1_canonical_component_type(arguments[1]),
            }
    if source == v1_component_status_type():
        return v1_component_status_abi()
    fail(
        "component-public-type-not-safe",
        "source type has no canonical Cire-v1.0 Component mapping",
    )


def v1_validate_component_type_controls() -> None:
    """Exercise every recursive mapping branch used by the closed profile."""

    scalar_names = [
        ("Bool", "BoolV1"),
        ("Int8", "S8V1"),
        ("Int16", "S16V1"),
        ("Int", "S32V1"),
        ("Int64", "S64V1"),
        ("UInt8", "U8V1"),
        ("UInt16", "U16V1"),
        ("UInt", "U32V1"),
        ("UInt64", "U64V1"),
        ("Float32", "F32V1"),
        ("Float", "F64V1"),
        ("Char", "CharV1"),
    ]
    controls: List[tuple[Any, Any]] = []
    for source_name, scalar_name in scalar_names:
        source = (
            v1_legacy_builtin(source_name)
            if source_name in LEGACY_PRIMITIVES
            else v1_core_primitive_type(source_name)
        )
        controls.append((source, {"kind": "ScalarV1", "scalar": scalar_name}))
    controls.extend(
        [
            (v1_legacy_builtin("Unit"), {"kind": "TupleV1", "elements": []}),
            (
                v1_legacy_builtin("String"),
                {"kind": "StringV1", "encoding": "Utf8V1"},
            ),
            (
                v1_core_primitive_type("Bytes"),
                {
                    "kind": "ListV1",
                    "element": {"kind": "ScalarV1", "scalar": "U8V1"},
                },
            ),
            (
                v1_builtin_application("Array", [v1_legacy_builtin("Int")]),
                {
                    "kind": "ListV1",
                    "element": {"kind": "ScalarV1", "scalar": "S32V1"},
                },
            ),
            (
                v1_component_option_int_type(),
                {
                    "kind": "OptionV1",
                    "value": {"kind": "ScalarV1", "scalar": "S32V1"},
                },
            ),
            (
                v1_builtin_application(
                    "Result", [v1_legacy_builtin("Unit"), v1_legacy_builtin("String")]
                ),
                {
                    "kind": "ResultV1",
                    "ok": None,
                    "error": {"kind": "StringV1", "encoding": "Utf8V1"},
                },
            ),
            (v1_component_status_type(), v1_component_status_abi()),
        ]
    )
    for index, (source, expected) in enumerate(controls):
        observed = v1_canonical_component_type(source)
        v1_component_type(observed, "component mapping control " + str(index))
        if observed != expected:
            fail(
                "component-public-type-not-safe",
                "component mapping control differs",
            )

    record_identity = v1_declaration_identity_value("TypeV1", "RecordFixture")
    resource_identity = v1_declaration_identity_value("TypeV1", "ResourceFixture")
    for structural in (
        {
            "kind": "RecordV1",
            "source": v1_nominal_type(record_identity),
            "declaration": record_identity,
            "fields": [],
        },
        {
            "kind": "ResourceV1",
            "source": v1_nominal_type(resource_identity),
            "declaration": resource_identity,
        },
    ):
        v1_component_type(structural, "component structural schema control")


def v1_validate_component(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "package_instance_id", "manifest", "link_abi", "component_abi_epoch", "memory", "string_encoding", "native_async", "type_mappings", "imports", "exports", "resources", "borrow_policy", "trap_policy"], "CireComponentInterfaceV1")
    validate_profile_header(root, "CireComponentInterfaceV1", 1, "component-public-type-not-safe")
    v1_package_instance(root["package_instance_id"], "component package")
    v1_hash_ref(root["manifest"], "ComponentManifestV1", "component-public-type-not-safe")
    v1_hash_ref(root["link_abi"], "CireLinkAbiV1", "component-public-type-not-safe")
    if root["component_abi_epoch"] != "cire-component-memory32-utf8-sync-v1" or root["memory"] != "Memory32V1" or root["string_encoding"] != "Utf8V1":
        fail("component-public-type-not-safe", "component ABI selection differs")
    if root["native_async"] is not False:
        fail("component-native-async-not-in-v1", "native async is excluded")
    imports = require_list(root["imports"], "Decode/array-mismatch", "component imports")
    for import_value in imports:
        item = v1_closed(
            import_value,
            [
                "wit_path",
                "manifest_item",
                "parameters",
                "result",
                "generated_capability",
                "semantic_summary",
            ],
            "ComponentImportAbiV1",
        )
        if item["semantic_summary"] != "HostObservableV1":
            fail("component-public-type-not-safe", "component import is not HostObservable")
        v1_declaration_identity(item["generated_capability"], "component import capability")
        if not isinstance(item["manifest_item"], dict) or item["manifest_item"].get("kind") != "CallableComponentItemV1":
            fail("component-public-type-not-safe", "component import item is not callable")
        v1_closed(item["manifest_item"], ["kind", "callable"], "CallableComponentItemV1")
        v1_callable_edge(item["manifest_item"]["callable"], "component import callable")
        for parameter in require_list(item["parameters"], "Decode/array-mismatch", "component import parameters"):
            parameter_item = v1_closed(parameter, ["ordinal", "name", "type"], "ComponentParameterAbiV1")
            v1_u32(parameter_item["ordinal"], "component import parameter ordinal")
            v1_string(parameter_item["name"], "component import parameter name")
            v1_component_type(parameter_item["type"], "component import parameter type")
        if item["result"] is not None:
            v1_component_type(item["result"], "component import result")
    mappings = require_list(root["type_mappings"], "Decode/array-mismatch", "type mappings")
    mapping_keys: List[bytes] = []
    for mapping in mappings:
        item = v1_closed(mapping, ["source", "canonical_abi"], "ComponentTypeMappingV1")
        source = item["source"]
        v1_validate_m3_type(source, {}, "component mapping source")
        v1_component_type(item["canonical_abi"], "canonical ABI")
        if item["canonical_abi"] != v1_canonical_component_type(source):
            fail("component-public-type-not-safe", "canonical component type differs")
        mapping_keys.append(canonical_bytes(source))
    if mapping_keys != sorted(mapping_keys) or len(mapping_keys) != len(set(mapping_keys)):
        fail("component-public-type-not-safe", "type mappings are not canonical unique")
    expected_sources = sorted(
        [
            v1_legacy_builtin("Int"),
            v1_component_option_int_type(),
            v1_component_status_type(),
        ],
        key=canonical_bytes,
    )
    if [mapping["source"] for mapping in mappings] != expected_sources:
        fail("component-public-type-not-safe", "reachable type mapping closure differs")
    exports = require_list(root["exports"], "Decode/array-mismatch", "component exports")
    if len(exports) != 1:
        fail("component-public-type-not-safe", "component export closure differs")
    export = v1_closed(exports[0], ["wit_path", "callable", "parameters", "result", "owner_policy", "terminal_close_policy"], "ComponentExportAbiV1")
    if export["wit_path"] != ["foundation", "identity-int"] or export["owner_policy"] != "PerCallChildOwnerV1" or export["terminal_close_policy"] != "EveryCireReturnsOrAbortsV1":
        fail("component-public-type-not-safe", "component export policy differs")
    v1_callable_edge(export["callable"], "component callable")
    parameters = require_list(export["parameters"], "Decode/array-mismatch", "component parameters")
    if len(parameters) != 1:
        fail("component-public-type-not-safe", "component parameter closure differs")
    for ordinal, parameter in enumerate(parameters):
        item = v1_closed(parameter, ["ordinal", "name", "type"], "ComponentParameterAbiV1")
        if v1_u32(item["ordinal"], "component parameter ordinal") != ordinal:
            fail("component-public-type-not-safe", "component parameter order differs")
        v1_string(item["name"], "component parameter label")
        v1_component_type(item["type"], "component parameter type")
    if export["result"] is not None:
        v1_component_type(export["result"], "component result")
    callable_interface = load_json(V1 / "interfaces/callable-interface.json")
    contract = load_json(V1 / "interfaces/function-contract-v3.json")
    surface_slots = callable_interface["surface_signature"]["slots"]
    parameter_binders = contract["binders"]["parameter_binders"]
    if len(surface_slots) != len(parameters) or len(parameter_binders) != len(parameters):
        fail("component-public-type-not-safe", "component callable parameter closure differs")
    for parameter, surface, binder in zip(parameters, surface_slots, parameter_binders):
        if (
            surface["passing"] != "NamedOrPositionalV1"
            or parameter["ordinal"] != surface["slot"]
            or parameter["name"] != surface["public_label"]
            or parameter["type"] != v1_canonical_component_type(binder["type"])
        ):
            fail("component-public-type-not-safe", "component parameter projection differs")
    declaration_kind = contract["declaration_kind"]
    if declaration_kind["visible_row"] != {"kind": "EmptyV1"}:
        fail("component-public-type-not-safe", "component export row is not closed empty")
    if export["result"] != v1_canonical_component_type(declaration_kind["result_type"]):
        fail("component-public-type-not-safe", "component result projection differs")
    paths = contract["computation"]["paths"]
    if any(path["suspension"]["grade"] != "NoSuspend" for path in paths):
        fail("component-native-async-not-in-v1", "component export may suspend")
    resources = require_list(root["resources"], "Decode/array-mismatch", "component resources")
    for resource_value in resources:
        resource = v1_closed(
            resource_value,
            ["wit_path", "declaration", "ownership", "runtime_identity", "destruction"],
            "ComponentResourceAbiV1",
        )
        v1_declaration_identity(resource["declaration"], "component resource declaration")
        if (
            resource["ownership"] != "OwnOrBorrowV1"
            or resource["runtime_identity"] != "InstanceHandleTableAndOwnerGenerationV1"
            or resource["destruction"] != "SealedOwnerCloseV1"
        ):
            fail("component-public-type-not-safe", "component resource policy differs")
    if contains_forbidden_component_type(root["exports"]):
        fail("component-public-type-not-safe", "public Plan/Commit form exposed")
    borrow = v1_closed(root["borrow_policy"], ["provenance", "escape", "suspend", "store_without_owned_copy"], "ComponentBorrowPolicyV1")
    if borrow != {"provenance": "CallbackOrFfiV1", "escape": False, "suspend": False, "store_without_owned_copy": False}:
        fail("component-public-type-not-safe", "borrow policy differs")
    trap = v1_closed(root["trap_policy"], ["cire_defect", "host_or_engine_trap", "catchable_as_raise", "convert_to_result"], "ComponentTrapPolicyV1")
    if trap != {"cire_defect": "DefectTransitionV1AfterSuffixRetirementV1", "host_or_engine_trap": "CatastrophicInstanceFailureV1", "catchable_as_raise": False, "convert_to_result": False}:
        fail("component-public-type-not-safe", "trap policy differs")
    v1_validate_component_type_controls()
    if root != build_component_interface():
        fail("component-public-type-not-safe", "component interface differs from deterministic generation")


def _fp_g(slot: int) -> Dict[str, Any]:
    return {"kind": "GenericBinderRefV1", "binder_slot": slot}


def _fp_f(slot: int) -> Dict[str, Any]:
    return {"kind": "FreshBinderRefV1", "fresh_slot": slot}


def _fp_builtin(name: str) -> Dict[str, Any]:
    return {"kind": "BuiltinTypeTemplateV1", "name": name}


def _fp_nominal(module: str, name: str, *arguments: Any) -> Dict[str, Any]:
    return {"kind": "NominalTypeTemplateV1", "module": ["cire", module], "name": name, "arguments": list(arguments)}


def _fp_binder_type(ref: Mapping[str, Any]) -> Dict[str, Any]:
    return {"kind": "BinderTypeTemplateV1", "binder": copy.deepcopy(ref)}


def _fp_capability(identity: Mapping[str, Any]) -> Dict[str, Any]:
    return {
        "kind": "CapabilityTypeTemplateV1",
        "identity": copy.deepcopy(identity),
        "family": {"kind": "NominalEffectFamilyTemplateV1", "module": ["cire", "temporal"], "name": "FrameClock", "arguments": []},
    }


def _fp_function(parameters: Sequence[Any], result: Any) -> Dict[str, Any]:
    return {"kind": "FunctionTypeTemplateV1", "parameters": copy.deepcopy(list(parameters)), "result": copy.deepcopy(result)}


def _fp_owner(ref: Mapping[str, Any]) -> Dict[str, Any]:
    return _fp_nominal("owner", "Owner", _fp_binder_type(ref))


def _fp_next(identity: Mapping[str, Any], payload: Any, summary: Mapping[str, Any]) -> Dict[str, Any]:
    return _fp_nominal("temporal", "Next", _fp_binder_type(identity), copy.deepcopy(payload), _fp_binder_type(summary))


def _fp_packed(owner: Mapping[str, Any], payload: Any) -> Dict[str, Any]:
    return _fp_nominal("temporal", "PackedNext", _fp_binder_type(owner), copy.deepcopy(payload))


def _fp_task(owner: Mapping[str, Any], payload: Any) -> Dict[str, Any]:
    return _fp_nominal("async", "Task", _fp_binder_type(owner), copy.deepcopy(payload))


def _fp_live(owner: Mapping[str, Any], payload: Any) -> Dict[str, Any]:
    return _fp_nominal("reactive", "Live", _fp_binder_type(owner), copy.deepcopy(payload))


def _fp_source_type(owner: Mapping[str, Any], payload: Any) -> Dict[str, Any]:
    return _fp_nominal("reactive", "Source", _fp_binder_type(owner), copy.deepcopy(payload))


def _fp_signal(identity: Mapping[str, Any], payload: Any) -> Dict[str, Any]:
    return _fp_nominal("signal", "Signal", _fp_binder_type(identity), copy.deepcopy(payload))


def _fp_type_ref(value: Any) -> Dict[str, Any]:
    return {"kind": "TypeRefV1", "type": copy.deepcopy(value)}


def _fp_named(slot: int, label: str, value: Any) -> Dict[str, Any]:
    pattern = copy.deepcopy(value) if isinstance(value, dict) and value.get("kind") in {"ContextualCallbackRefV1", "CallableCallbackRefV1"} else _fp_type_ref(value)
    return {"kind": "NamedOrPositionalSlotV1", "slot": slot, "passing": "NamedOrPositionalV1", "public_label": label, "defaultable": False, "type": pattern}


def _fp_implicit(slot: int, value: Any) -> Dict[str, Any]:
    return {"kind": "ImplicitReceiverSlotV1", "slot": slot, "passing": "ImplicitReceiverV1", "type": _fp_type_ref(value)}


def _fp_callback_slot(name: str, contextual: bool = True) -> Dict[str, Any]:
    return {"kind": "ContextualCallbackRefV1" if contextual else "CallableCallbackRefV1", "callback_name": name}


def _fp_types(*kinds: str) -> List[Dict[str, Any]]:
    return [{"kind": "KindBinderV1", "binder_slot": index, "binder_kind": kind} for index, kind in enumerate(kinds)]


def _fp_direct_only() -> Dict[str, Any]:
    return {"kind": "DirectOnlyV1"}


def _fp_both(callback: str) -> Dict[str, Any]:
    return {"kind": "DirectAndCallbackPrivateV1", "callback_name": callback}


def _fp_callback_only(callback: str) -> Dict[str, Any]:
    return {"kind": "CallbackOnlyV1", "callback_name": callback}


def _fp_current(slot: int, visibility: Any) -> Dict[str, Any]:
    return {"kind": "DerivedCurrentOwnerBinderV1", "fresh_slot": slot, "binder_kind": "OwnerRegionV1", "derivation": "CurrentOwnerOfEntryPhaseV1", "visibility": copy.deepcopy(visibility)}


def _fp_generative(slot: int, kind: str, cardinality: str, visibility: Any, origin: Any) -> Dict[str, Any]:
    return {"kind": "GenerativeFreshBinderV1", "fresh_slot": slot, "binder_kind": kind, "cardinality": cardinality, "visibility": copy.deepcopy(visibility), "origin": copy.deepcopy(origin)}


def _fp_child(slot: int, parent: Any, cardinality: str, visibility: Any) -> Dict[str, Any]:
    return _fp_generative(slot, "OwnerRegionV1", cardinality, visibility, {"kind": "ChildOwnerRegionV1", "parent": copy.deepcopy(parent), "relation": "DirectChildV1"})


def _fp_frame(slot: int, owner: Any, cardinality: str, visibility: Any) -> Dict[str, Any]:
    return _fp_generative(slot, "ClockIdentityV1", cardinality, visibility, {"kind": "FrameClockIdentityV1", "owner": copy.deepcopy(owner)})


def _fp_summary(slot: int, identity: Any, payload: Any, cardinality: str, visibility: Any) -> Dict[str, Any]:
    return _fp_generative(slot, "ClockPackageSummaryV1", cardinality, visibility, {"kind": "ClockPackageSummaryV1", "identity": copy.deepcopy(identity), "payload": copy.deepcopy(payload)})


def _fp_opened(slot: int, binder_kind: str, component: str, callback: str) -> Dict[str, Any]:
    return {"kind": "OpenedPackedNextBinderV1", "fresh_slot": slot, "binder_kind": binder_kind, "packed_parameter_slot": 0, "component": component, "visibility": _fp_both(callback)}


def _fp_contract(phase: str, row: Any, suspension: Any, world: Any, flow: Any, temporal: str) -> Dict[str, Any]:
    return {
        "kind": "FirstPartyContractTemplateV1", "phase": phase + "V1", "row": copy.deepcopy(row),
        "suspension": copy.deepcopy(suspension), "world": copy.deepcopy(world), "flow": copy.deepcopy(flow),
        "temporal": {"kind": temporal + "V1"},
        "construction": {"kind": "CanonicalFirstPartyLiteralPathsV1", "demand_policy": "NormalizedRowAndKernelV1", "obligation_policy": "EvidenceArrayOrderV1", "site_policy": "AllReferencedDirectAndProjectedCallbackSitesV1", "result_policy": "TypeAndFlowDirectedV1", "capture_policy": "ActualArgumentsAndCallbacksV1", "usage_policy": "AuthoritySlotsExactV1", "origin_policy": "ElaborationOriginProjectionV1"},
    }


def _fp_r0() -> Dict[str, Any]: return {"kind": "EmptyRowV1"}
def _fp_ra() -> Dict[str, Any]: return {"kind": "AnonymousAsyncRowV1"}
def _fp_rg(ref: Any) -> Dict[str, Any]: return {"kind": "GenericEffectRowV1", "binder": copy.deepcopy(ref)}
def _fp_rcb(name: str) -> Dict[str, Any]: return {"kind": "CallbackRowV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}}
def _fp_s0() -> Dict[str, Any]: return {"kind": "NoSuspendV1"}
def _fp_sa() -> Dict[str, Any]: return {"kind": "AsyncMaySuspendV1"}
def _fp_scb(name: str) -> Dict[str, Any]: return {"kind": "CallbackSuspensionV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}}
def _fp_w0() -> Dict[str, Any]: return {"kind": "SameWorldV1"}
def _fp_wcb(name: str) -> Dict[str, Any]: return {"kind": "CallbackWorldV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}}
def _fp_wprivate(name: str, refs: Sequence[Any]) -> Dict[str, Any]: return {"kind": "ProjectPrivateWorldV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}, "private_binders": copy.deepcopy(list(refs))}
def _fp_return(value: Any) -> Dict[str, Any]: return {"kind": "ReturnsOnlyV1", "result": copy.deepcopy(value)}
def _fp_await(value: Any) -> Dict[str, Any]: return {"kind": "AwaitOrParkV1", "result": copy.deepcopy(value), "park": "ParkContractV2"}
def _fp_callback_flow(name: str) -> Dict[str, Any]: return {"kind": "CallbackFlowV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}}


def _fp_map_flow(name: str, returns: Any) -> Dict[str, Any]:
    return {"kind": "MapCallbackFlowV1", "callback": {"kind": "BindingCallbackRefV1", "callback_name": name}, "returns": copy.deepcopy(returns), "preserve_terminal_tags": ["AbortsV2", "TransfersV2"]}


def _fp_scheme(trigger: str, owner: Any, captured: Sequence[int], generated: Sequence[int]) -> Dict[str, Any]:
    return {"kind": "FirstPartyCallbackSchemeV1", "trigger": trigger, "entry_owner": copy.deepcopy(owner), "captured_fresh_slots": list(captured), "generated_fresh_slots": list(generated)}


def _fp_callback(name: str, slot: int, acquisition: str, type_value: Any, contract: Any, scheme: Any) -> Dict[str, Any]:
    return {"kind": "FirstPartyCallbackV1", "name": name, "parameter_slot": slot, "acquisition": acquisition, "type": copy.deepcopy(type_value), "contract": copy.deepcopy(contract), "scheme": copy.deepcopy(scheme)}


def _fp_evidence(rule: str, *arguments: Any) -> Dict[str, Any]:
    return {"kind": "ProofRuleEvidenceV1", "rule": rule, "arguments": copy.deepcopy(list(arguments))}


def _fp_p(slot: int) -> Dict[str, Any]: return {"kind": "ParameterSlotRefV1", "slot": slot}
def _fp_cb(name: str) -> Dict[str, Any]: return {"kind": "BindingCallbackRefV1", "callback_name": name}
def _fp_et(value: Any) -> Dict[str, Any]: return {"kind": "EvidenceTypeRefV1", "type": copy.deepcopy(value)}
def _fp_entry_owner(ref: Any) -> Dict[str, Any]: return {"kind": "ExactCallbackEntryOwnerV1", "owner": copy.deepcopy(ref)}
def _fp_no_owner() -> Dict[str, Any]: return {"kind": "NoCallbackEntryOwnerV1"}


def _fp_binding(identifier: str, source: Any, slots: Any, types: Any, fresh: Any, direct: Any, callbacks: Any, evidence: Any, kernel: Any) -> Dict[str, Any]:
    return {"kind": "FirstPartyBindingV1", "id": identifier, "source": source, "slots": slots, "types": types, "fresh": fresh, "direct": direct, "callbacks": callbacks, "evidence": evidence, "kernel": kernel}


def build_first_party_registry() -> Dict[str, Any]:
    unit = _fp_builtin("Unit")
    dispose_report = _fp_nominal("owner", "DisposeReport")
    cancel_result = _fp_nominal("async", "CancelResult")
    backpressure = _fp_nominal("ui", "UiBackpressureV1")
    close_dispose = _fp_nominal("async", "CloseReceipt", dispose_report)
    entries: Dict[str, Dict[str, Any]] = {}
    def add(suffix: str, *args: Any) -> None:
        identifier = "Cire-v1.0/intrinsic/" + suffix
        entries[identifier] = _fp_binding(identifier, *args)

    # async await receipt/task
    r = _fp_g(0)
    observer = _fp_f(0)
    add("async.await-receipt", {"kind": "AssociatedFunctionV1", "receiver": "CloseReceipt", "member": "await"},
        [_fp_named(0, "receipt", _fp_nominal("async", "CloseReceipt", _fp_binder_type(r)))], _fp_types("TypeV1"),
        [_fp_current(0, _fp_direct_only())], _fp_contract("Action", _fp_ra(), _fp_sa(), _fp_w0(), _fp_await(_fp_binder_type(r)), "HostObservable"), [],
        [_fp_evidence("OwnerAuthorityV1", observer), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(r))), _fp_evidence("AsyncBoundarySafeV1", observer, _fp_et(_fp_binder_type(r))), _fp_evidence("SuspensionStableV1", _fp_p(0)), _fp_evidence("OwnerBoundParkingV1", observer)],
        {"kind": "OperationCallV1", "family": "AsyncV1", "operation": "await_receiptV1"})
    rho, result, observer = _fp_g(0), _fp_g(1), _fp_f(0)
    add("async.await-task", {"kind": "AssociatedFunctionV1", "receiver": "Async", "member": "await"},
        [_fp_named(0, "task", _fp_task(rho, _fp_binder_type(result)))], _fp_types("OwnerRegionV1", "TypeV1"), [_fp_current(0, _fp_direct_only())],
        _fp_contract("Action", _fp_ra(), _fp_sa(), _fp_w0(), _fp_await(_fp_binder_type(result)), "HostObservable"), [],
        [_fp_evidence("OwnerAuthorityV1", observer), _fp_evidence("OutlivesV1", observer, rho), _fp_evidence("AsyncBoundarySafeV1", observer, _fp_et(_fp_binder_type(result))), _fp_evidence("SuspensionStableV1", _fp_p(0)), _fp_evidence("OwnerBoundParkingV1", observer), _fp_evidence("ExactTaskRegionGenerationV1", _fp_p(0), rho), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(result)))],
        {"kind": "OperationCallV1", "family": "AsyncV1", "operation": "awaitV1"})

    # resources
    rho, key, value, error = _fp_g(0), _fp_g(1), _fp_g(2), _fp_g(3)
    resource = _fp_nominal("resource", "Resource", _fp_binder_type(rho), _fp_binder_type(key), _fp_binder_type(value), _fp_binder_type(error))
    add("resource.dispose", {"kind": "AssociatedFunctionV1", "receiver": "Resource", "member": "dispose"}, [_fp_named(0, "resource", resource)], _fp_types("OwnerRegionV1", "TypeV1", "TypeV1", "TypeV1"), [], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(close_dispose), "HostObservable"), [], [_fp_evidence("ExactResourceRootV1", _fp_p(0), rho), _fp_evidence("ExactCloseCellIdentityV1", _fp_p(0))], {"kind": "ResourceDisposeV1"})
    child = _fp_f(0)
    outcome = _fp_nominal("async", "TaskOutcome", _fp_binder_type(value), _fp_binder_type(error))
    load_type = _fp_function([_fp_owner(child), _fp_binder_type(key)], _fp_task(child, outcome))
    load_contract = _fp_contract("Action", _fp_rcb("load"), _fp_s0(), _fp_w0(), _fp_return(_fp_task(child, outcome)), "HostObservable")
    loader_special = {"kind": "ResourceLoaderContractV1", "callback": _fp_cb("load"), "storage_owner": rho, "generation_owner": child, "key_type": _fp_binder_type(key), "value_type": _fp_binder_type(value), "error_type": _fp_binder_type(error)}
    add("resource.switch-latest", {"kind": "AssociatedFunctionV1", "receiver": "Resource", "member": "switch_latest"},
        [_fp_named(0, "under", _fp_owner(rho)), _fp_named(1, "keys", _fp_live(rho, _fp_binder_type(key))), _fp_named(2, "load", _fp_callback_slot("load"))],
        _fp_types("OwnerRegionV1", "TypeV1", "TypeV1", "TypeV1"), [_fp_child(0, rho, "PerAdmittedGenerationV1", _fp_callback_only("load"))],
        _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(resource), "HostObservable"),
        [_fp_callback("load", 2, "ContextualV1", load_type, load_contract, _fp_scheme("PerAdmittedGenerationV1", _fp_entry_owner(child), [], [0]))],
        [_fp_evidence("ShareableV1", _fp_et(_fp_binder_type(key))), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(value))), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(error))), _fp_evidence("ChildOwnerV1", rho, child), _fp_evidence("DuplicableEnvironmentV1", _fp_cb("load")), _fp_evidence("OwnerStorageProvenanceV1", _fp_cb("load"), rho), _fp_evidence("BoundarySafeCaptureV1", _fp_cb("load")), _fp_evidence("OutlivesV1", _fp_cb("load"), rho), loader_special], {"kind": "ResourceSwitchLatestV1"})
    view = _fp_nominal("resource", "ResourceView", _fp_binder_type(key), _fp_binder_type(value), _fp_binder_type(error))
    add("resource.view", {"kind": "AssociatedFunctionV1", "receiver": "Resource", "member": "view"}, [_fp_named(0, "resource", resource)], _fp_types("OwnerRegionV1", "TypeV1", "TypeV1", "TypeV1"), [], _fp_contract("Pure", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_live(rho, view)), "Pure"), [], [_fp_evidence("ShareableV1", _fp_et(view))], {"kind": "ResourceViewV1"})

    # signals
    identity, a, b = _fp_g(0), _fp_g(1), _fp_g(2)
    transform_type = _fp_function([_fp_binder_type(a)], _fp_binder_type(b))
    transform_contract = _fp_contract("Pure", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_binder_type(b)), "Pure")
    tail = {"kind": "SignalTailContractEvidenceV1", "callback": _fp_cb("transform"), "clock": identity, "input_type": _fp_binder_type(a), "output_type": _fp_binder_type(b)}
    add("signal.map", {"kind": "UnqualifiedFunctionV1", "name": "map_signal"}, [_fp_named(0, "input", _fp_signal(identity, _fp_binder_type(a))), _fp_named(1, "transform", _fp_callback_slot("transform", contextual=False))], _fp_types("ClockIdentityV1", "TypeV1", "TypeV1"), [], _fp_contract("Pure", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_signal(identity, _fp_binder_type(b))), "Pure"), [_fp_callback("transform", 1, "CallableValueV1", transform_type, transform_contract, _fp_scheme("CallableInvocationV1", _fp_no_owner(), [], []))], [_fp_evidence("ShareableV1", _fp_et(_fp_binder_type(a))), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(b))), _fp_evidence("DuplicableEnvironmentV1", _fp_cb("transform")), _fp_evidence("TemporalStableCaptureV1", _fp_cb("transform"), identity), _fp_evidence("CrossWorldSafeCaptureV1", _fp_cb("transform"), identity), tail], {"kind": "SignalMapV1"})
    identity, a, owner, epoch = _fp_g(0), _fp_g(1), _fp_f(0), _fp_f(1)
    track_context = _fp_nominal("signal", "TrackContext", _fp_binder_type(owner), _fp_binder_type(identity), _fp_binder_type(epoch))
    body_type = _fp_function([track_context], _fp_binder_type(a))
    body_contract = _fp_contract("Compute", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_binder_type(a)), "HostObservable")
    retain_track = {"kind": "RetainedCallbackContractV1", "callback": _fp_cb("body"), "storage_owner": owner, "invocation_scope": {"kind": "InstalledTrackInvocationV1", "epoch": epoch}, "capture_policy": "OwnerStorageBoundarySafeOutlivesV1"}
    add("signal.track", {"kind": "AssociatedFunctionV1", "receiver": "Signal", "member": "track"}, [_fp_named(0, "frame", _fp_capability(identity)), _fp_named(1, "body", _fp_callback_slot("body"))], _fp_types("ClockIdentityV1", "TypeV1"), [_fp_current(0, _fp_both("body")), _fp_generative(1, "TrackEpochScopeV1", "PerInstalledSubscriptionV1", _fp_callback_only("body"), {"kind": "InstalledTrackEpochV1"})], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_signal(identity, _fp_binder_type(a))), "HostObservable"), [_fp_callback("body", 1, "ContextualV1", body_type, body_contract, _fp_scheme("PerInstalledSubscriptionV1", _fp_entry_owner(owner), [0], [1]))], [_fp_evidence("CurrentOwnerV1", owner), _fp_evidence("OwnerAuthorityV1", owner), _fp_evidence("ExactBuilderRootV1", _fp_p(0), owner, identity), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(a))), _fp_evidence("DuplicableEnvironmentV1", _fp_cb("body")), _fp_evidence("CompleteDependencyTraceV1", _fp_cb("body"), epoch), _fp_evidence("ContextualNonescapeV1", _fp_cb("body")), _fp_evidence("OwnerStorageProvenanceV1", _fp_cb("body"), owner), _fp_evidence("BoundarySafeCaptureV1", _fp_cb("body")), _fp_evidence("OutlivesV1", _fp_cb("body"), owner), retain_track], {"kind": "SignalTrackV1"})

    # snapshot/track reads
    def add_read(suffix: str, receiver: str, input_name: str, source: Any, types: Any, direct_phase: str, temporal: str, evidence: Any, kernel: str) -> None:
        add(suffix, {"kind": "AssociatedFunctionV1", "receiver": receiver, "member": "read"}, [_fp_implicit(0, source[0]), _fp_named(1, "input", source[1])], types, [], _fp_contract(direct_phase, _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(source[2]), temporal), [], evidence, {"kind": kernel})
    rho, identity, epoch, a = _fp_g(0), _fp_g(1), _fp_g(2), _fp_g(3)
    track = _fp_nominal("signal", "TrackContext", _fp_binder_type(rho), _fp_binder_type(identity), _fp_binder_type(epoch))
    add_read("track.read-live", "TrackContext", "input", (track, _fp_live(rho, _fp_binder_type(a)), _fp_binder_type(a)), _fp_types("OwnerRegionV1", "ClockIdentityV1", "TrackEpochScopeV1", "TypeV1"), "Compute", "HostObservable", [_fp_evidence("InvalidatingDependencyV1", epoch, _fp_p(1)), _fp_evidence("ExactOwnerV1", rho)], "TrackReadLiveV1")
    add_read("track.read-source", "TrackContext", "input", (track, _fp_source_type(rho, _fp_binder_type(a)), _fp_binder_type(a)), _fp_types("OwnerRegionV1", "ClockIdentityV1", "TrackEpochScopeV1", "TypeV1"), "Compute", "HostObservable", [_fp_evidence("InvalidatingDependencyV1", epoch, _fp_p(1)), _fp_evidence("ExactOwnerV1", rho)], "TrackReadSourceV1")
    rho, generation, revision, a = _fp_g(0), _fp_g(1), _fp_g(2), _fp_g(3)
    revision_types = _fp_types("OwnerRegionV1", "UiGenerationScopeV1") + [{"kind": "UiRevisionScopeBinderV1", "binder_slot": 2, "generation": generation}] + [{"kind": "KindBinderV1", "binder_slot": 3, "binder_kind": "TypeV1"}]
    snapshot = _fp_nominal("ui", "SnapshotContext", _fp_binder_type(rho), _fp_binder_type(revision))
    add_read("snapshot.read-live", "SnapshotContext", "input", (snapshot, _fp_live(rho, _fp_binder_type(a)), _fp_binder_type(a)), copy.deepcopy(revision_types), "Action", "Pure", [_fp_evidence("FixedSnapshotV1", revision), _fp_evidence("NoDependencyRegistrationV1", _fp_p(1))], "SnapshotReadLiveV1")
    add_read("snapshot.read-source", "SnapshotContext", "input", (snapshot, _fp_source_type(rho, _fp_binder_type(a)), _fp_binder_type(a)), copy.deepcopy(revision_types), "Action", "Pure", [_fp_evidence("FixedSnapshotV1", revision), _fp_evidence("NoDependencyRegistrationV1", _fp_p(1))], "SnapshotReadSourceV1")

    # task cancel
    rho, a, error = _fp_g(0), _fp_g(1), _fp_g(2)
    outcome = _fp_nominal("async", "TaskOutcome", _fp_binder_type(a), _fp_binder_type(error))
    add("task.cancel-outcome", {"kind": "AssociatedFunctionV1", "receiver": "Task", "member": "cancel"}, [_fp_named(0, "task", _fp_task(rho, outcome)), _fp_named(1, "under", _fp_owner(rho))], _fp_types("OwnerRegionV1", "TypeV1", "TypeV1"), [], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(cancel_result), "HostObservable"), [], [_fp_evidence("OwnerAuthorityV1", rho), _fp_evidence("ExactOutcomeTaskV1", _fp_p(0), rho, _fp_et(_fp_binder_type(a)), _fp_et(_fp_binder_type(error)))], {"kind": "TaskCancelV1"})

    # packed next pack/open/dispose
    rho, a = _fp_g(0), _fp_g(1)
    child, identity, summary = _fp_f(0), _fp_f(1), _fp_f(2)
    builder_type = _fp_function([_fp_capability(identity)], _fp_next(identity, _fp_binder_type(a), summary))
    builder_contract = _fp_contract("Action", _fp_rcb("builder"), _fp_scb("builder"), _fp_wcb("builder"), _fp_callback_flow("builder"), "HostObservable")
    pack_returns = {"kind": "PackNextReturnMapV1", "input": _fp_next(identity, _fp_binder_type(a), summary), "output": _fp_packed(rho, _fp_binder_type(a))}
    add("temporal.pack-next", {"kind": "IntrinsicModuleFunctionV1", "module": "temporal", "member": "pack_next"}, [_fp_named(0, "under", _fp_owner(rho)), _fp_named(1, "builder", _fp_callback_slot("builder"))], _fp_types("OwnerRegionV1", "TypeV1"), [_fp_child(0, rho, "PerDirectCallV1", _fp_both("builder")), _fp_frame(1, child, "PerDirectCallV1", _fp_both("builder")), _fp_summary(2, identity, _fp_binder_type(a), "PerDirectCallV1", _fp_both("builder"))], _fp_contract("Action", _fp_rcb("builder"), _fp_scb("builder"), _fp_wprivate("builder", [child, identity, summary]), _fp_map_flow("builder", pack_returns), "HostObservable"), [_fp_callback("builder", 1, "ContextualV1", builder_type, builder_contract, _fp_scheme("DirectInvocationV1", _fp_entry_owner(child), [], [0, 1, 2]))], [_fp_evidence("CurrentOwnerV1", rho), _fp_evidence("OwnerAuthorityV1", rho), _fp_evidence("ChildOwnerV1", rho, child), _fp_evidence("FrameClockNextSummaryCoherenceV1", child, identity, summary, _fp_et(_fp_binder_type(a))), _fp_evidence("PrivateIdentityOutwardGateV1", child, identity, summary, _fp_cb("builder"))], {"kind": "PackedNextPackV1"})
    add("temporal.packed-next-dispose", {"kind": "IntrinsicModuleFunctionV1", "module": "temporal", "member": "dispose"}, [_fp_named(0, "packed", _fp_packed(rho, _fp_binder_type(a)))], _fp_types("OwnerRegionV1", "TypeV1"), [], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(close_dispose), "HostObservable"), [], [_fp_evidence("ExactPackedNextOverloadV1", _fp_p(0)), _fp_evidence("ExactCloseCellIdentityV1", _fp_p(0))], {"kind": "PackedNextDisposeV1"})
    rho, a, b = _fp_g(0), _fp_g(1), _fp_g(2)
    child, identity, summary = _fp_f(0), _fp_f(1), _fp_f(2)
    body_type = _fp_function([_fp_capability(identity), _fp_next(identity, _fp_binder_type(a), summary)], _fp_binder_type(b))
    body_contract = _fp_contract("Action", _fp_rcb("body"), _fp_scb("body"), _fp_wcb("body"), _fp_callback_flow("body"), "HostObservable")
    option_b = _fp_nominal("core", "Option", _fp_binder_type(b))
    open_returns = {"kind": "AcquireOptionReturnMapV1", "lost": option_b, "input": _fp_binder_type(b), "output": option_b}
    add("temporal.try-with-packed-next", {"kind": "IntrinsicModuleFunctionV1", "module": "temporal", "member": "try_with_packed_next"}, [_fp_named(0, "packed", _fp_packed(rho, _fp_binder_type(a))), _fp_named(1, "body", _fp_callback_slot("body"))], _fp_types("OwnerRegionV1", "TypeV1", "TypeV1"), [_fp_opened(0, "OwnerRegionV1", "OwnerRegionV1", "body"), _fp_opened(1, "ClockIdentityV1", "ClockIdentityV1", "body"), _fp_opened(2, "ClockPackageSummaryV1", "ClockPackageSummaryV1", "body")], _fp_contract("Action", _fp_rcb("body"), _fp_scb("body"), _fp_wprivate("body", [child, identity, summary]), _fp_map_flow("body", open_returns), "HostObservable"), [_fp_callback("body", 1, "ContextualV1", body_type, body_contract, _fp_scheme("DirectInvocationV1", _fp_entry_owner(child), [0, 1, 2], []))], [_fp_evidence("PackedNextPackageLeaseV1", _fp_p(0), _fp_cb("body")), _fp_evidence("ExactPackagePrivateScopeV1", child, identity, summary, _fp_cb("body")), _fp_evidence("PrivateIdentityOutwardGateV1", child, identity, summary, _fp_cb("body"))], {"kind": "PackedNextOpenV1"})

    # UI
    add("ui.coalesce-latest", {"kind": "ClosedLiteralV1", "nominal": "UiBackpressureV1", "variant": "CoalesceLatest"}, [], [], [], _fp_contract("Pure", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(backpressure), "Pure"), [], [_fp_evidence("ExactCoalesceLatestV1")], {"kind": "UiBackpressureCoalesceLatestV1"})
    rho = _fp_g(0)
    identity = _fp_f(0)
    ui_builder = _fp_nominal("ui", "UiBuilder", _fp_binder_type(rho), _fp_binder_type(identity))
    run_body_type = _fp_function([_fp_capability(identity), ui_builder], unit)
    run_body_contract = _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(unit), "HostObservable")
    add("ui.run-signal", {"kind": "IntrinsicModuleFunctionV1", "module": "ui", "member": "run_signal"}, [_fp_named(0, "under", _fp_owner(rho)), _fp_named(1, "backpressure", backpressure), _fp_named(2, "body", _fp_callback_slot("body"))], _fp_types("OwnerRegionV1"), [_fp_frame(0, rho, "PerDirectCallV1", _fp_both("body"))], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_nominal("ui", "UiMount", _fp_binder_type(rho))), "HostObservable"), [_fp_callback("body", 2, "ContextualV1", run_body_type, run_body_contract, _fp_scheme("DirectInvocationV1", _fp_entry_owner(rho), [], [0]))], [_fp_evidence("OwnerAuthorityV1", rho), _fp_evidence("ExactBackpressureArgumentV1", _fp_p(1)), _fp_evidence("ContextualNonescapeV1", _fp_cb("body")), _fp_evidence("PrivateFrameBuilderNonescapeV1", identity, _fp_cb("body"))], {"kind": "UiRunSignalV1"})
    rho, identity = _fp_g(0), _fp_g(1)
    builder = _fp_nominal("ui", "UiBuilder", _fp_binder_type(rho), _fp_binder_type(identity))
    add("ui.builder-owner", {"kind": "AssociatedProjectionV1", "receiver": "UiBuilder", "member": "owner", "surface_member": "owner"}, [_fp_implicit(0, builder)], _fp_types("OwnerRegionV1", "ClockIdentityV1"), [], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(_fp_owner(rho)), "Pure"), [], [_fp_evidence("ExactBuilderRootV1", _fp_p(0), rho, identity), _fp_evidence("ProjectionNonescapeV1", _fp_p(0))], {"kind": "UiBuilderOwnerV1"})
    rho, identity, a = _fp_g(0), _fp_g(1), _fp_g(2)
    generation, revision = _fp_f(0), _fp_f(1)
    candidate = _fp_nominal("ui", "UiCandidate", _fp_binder_type(rho), _fp_binder_type(generation), _fp_binder_type(revision))
    view_plan = _fp_nominal("ui", "ViewPlan", _fp_binder_type(generation))
    transform_type = _fp_function([candidate, _fp_binder_type(a)], view_plan)
    transform_contract = _fp_contract("Compute", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(view_plan), "Pure")
    retain_ui = {"kind": "RetainedCallbackContractV1", "callback": _fp_cb("transform"), "storage_owner": rho, "invocation_scope": {"kind": "UiAdmissionInvocationV1", "generation": generation, "revision": revision}, "capture_policy": "OwnerStorageBoundarySafeOutlivesV1"}
    add("ui.render", {"kind": "AssociatedFunctionV1", "receiver": "UiBuilder", "member": "render"}, [_fp_implicit(0, builder), _fp_named(1, "model", _fp_signal(identity, _fp_binder_type(a))), _fp_named(2, "transform", _fp_callback_slot("transform"))], _fp_types("OwnerRegionV1", "ClockIdentityV1", "TypeV1"), [_fp_generative(0, "UiGenerationScopeV1", "PerAdmittedGenerationV1", _fp_both("transform"), {"kind": "AdmittedUiGenerationV1", "owner": rho}), _fp_generative(1, "UiRevisionScopeV1", "PerAdmittedGenerationV1", _fp_both("transform"), {"kind": "UiRevisionOfV1", "generation": generation})], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(unit), "HostObservable"), [_fp_callback("transform", 2, "ContextualV1", transform_type, transform_contract, _fp_scheme("PerAdmittedGenerationV1", _fp_entry_owner(rho), [], [0, 1]))], [_fp_evidence("DuplicableEnvironmentV1", _fp_cb("transform")), _fp_evidence("ExactBuilderRootV1", _fp_p(0), rho, identity), _fp_evidence("ExactGenerationRevisionBindingV1", _fp_cb("transform"), generation, revision), _fp_evidence("OwnerStorageProvenanceV1", _fp_cb("transform"), rho), _fp_evidence("BoundarySafeCaptureV1", _fp_cb("transform")), _fp_evidence("OutlivesV1", _fp_cb("transform"), rho), _fp_evidence("CandidatePlanCaptureNonescapeV1", _fp_cb("transform"), generation, revision), retain_ui], {"kind": "UiRenderV1"})
    rho, generation, revision, event_type, effect_row = _fp_g(0), _fp_g(1), _fp_g(2), _fp_g(3), _fp_g(4)
    candidate = _fp_nominal("ui", "UiCandidate", _fp_binder_type(rho), _fp_binder_type(generation), _fp_binder_type(revision))
    snapshot = _fp_nominal("ui", "SnapshotContext", _fp_binder_type(rho), _fp_binder_type(revision))
    action_type = _fp_function([snapshot, _fp_binder_type(event_type)], unit)
    action_contract = _fp_contract("Action", _fp_rg(effect_row), _fp_s0(), _fp_w0(), _fp_return(unit), "HostObservable")
    action_plan = _fp_nominal("ui", "ActionPlan", _fp_binder_type(generation), _fp_binder_type(event_type))
    action_special = {"kind": "ActionPlanContractV1", "callback": _fp_cb("body"), "storage_owner": rho, "generation": generation, "revision": revision, "event_type": _fp_binder_type(event_type), "event_parameter_index": 1, "occurrence_policy": "OwnerStoredExactQueuedOccurrenceV1"}
    add("ui.candidate-action", {"kind": "AssociatedFunctionV1", "receiver": "UiCandidate", "member": "action"}, [_fp_implicit(0, candidate), _fp_named(1, "body", _fp_callback_slot("body"))], _fp_types("OwnerRegionV1", "UiGenerationScopeV1") + [{"kind": "UiRevisionScopeBinderV1", "binder_slot": 2, "generation": generation}, {"kind": "KindBinderV1", "binder_slot": 3, "binder_kind": "TypeV1"}, {"kind": "KindBinderV1", "binder_slot": 4, "binder_kind": "EffectRowV1"}], [], _fp_contract("Compute", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(action_plan), "Pure"), [_fp_callback("body", 1, "ContextualV1", action_type, action_contract, _fp_scheme("PerEventDispatchV1", _fp_entry_owner(rho), [], []))], [_fp_evidence("ActionSafeRowV1", rho, generation, effect_row), _fp_evidence("DuplicableEnvironmentV1", _fp_cb("body")), _fp_evidence("OwnerStorageProvenanceV1", _fp_cb("body"), rho), _fp_evidence("BoundarySafeCaptureV1", _fp_cb("body")), _fp_evidence("OutlivesV1", _fp_cb("body"), rho), action_special, _fp_evidence("EventEntryDischargeOnlyV1", _fp_cb("body")), _fp_evidence("ShareableV1", _fp_et(_fp_binder_type(event_type))), _fp_evidence("EventOccurrenceStorageV1", rho, generation, _fp_et(_fp_binder_type(event_type)))], {"kind": "UiCandidateActionV1"})
    rho = _fp_g(0)
    add("ui.mount-dispose", {"kind": "AssociatedFunctionV1", "receiver": "UiMount", "member": "dispose"}, [_fp_named(0, "mount", _fp_nominal("ui", "UiMount", _fp_binder_type(rho)))], _fp_types("OwnerRegionV1"), [], _fp_contract("Action", _fp_r0(), _fp_s0(), _fp_w0(), _fp_return(close_dispose), "HostObservable"), [], [_fp_evidence("ExactMountRootV1", _fp_p(0), rho), _fp_evidence("ExactCloseCellIdentityV1", _fp_p(0))], {"kind": "UiMountDisposeV1"})

    bindings = [entries[identifier] for identifier in sorted(entries)]
    if [binding["id"] for binding in bindings] != FIRST_PARTY_IDS:
        raise AssertionError("first-party generator ID set drift")
    return {"artifact": "FirstPartyRegistryV1", "profile": PROFILE, "schema_version": 1, "bindings": bindings}


def _fp_schema_fields(value: Any) -> Dict[str, tuple[str, ...]]:
    result: Dict[str, tuple[str, ...]] = {}
    def visit(item: Any) -> None:
        if isinstance(item, dict):
            kind = item.get("kind")
            if isinstance(kind, str):
                fields = tuple(sorted(item))
                if kind in result and result[kind] != fields:
                    raise AssertionError("non-unique first-party schema for " + kind)
                result[kind] = fields
            for child in item.values():
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)
    visit(value)
    return result


FIRST_PARTY_GOLDEN = build_first_party_registry()
FIRST_PARTY_TAG_FIELDS = _fp_schema_fields(FIRST_PARTY_GOLDEN)
FIRST_PARTY_SOURCES = [binding["source"] for binding in FIRST_PARTY_GOLDEN["bindings"]]
FIRST_PARTY_KERNELS = [binding["kernel"] for binding in FIRST_PARTY_GOLDEN["bindings"]]


def v1_validate_tagged_registry(value: Any, context: str) -> None:
    if isinstance(value, dict):
        kind = value.get("kind")
        if not isinstance(kind, str) or kind not in FIRST_PARTY_TAG_FIELDS:
            fail("Decode/tag-mismatch", context + " has an unknown/missing registry tag")
        v1_closed(value, FIRST_PARTY_TAG_FIELDS[kind], context + "/" + kind)
        for key, child in value.items():
            if key != "kind" and isinstance(child, (dict, list)):
                v1_validate_tagged_registry(child, context + "/" + key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            if isinstance(child, (dict, list)):
                v1_validate_tagged_registry(child, context + "/" + str(index))


def v1_registry_refs(value: Any, type_count: int, fresh_count: int, slot_count: int, callbacks: set[str]) -> None:
    if isinstance(value, dict):
        kind = value.get("kind")
        if kind == "GenericBinderRefV1" and v1_u32(value.get("binder_slot"), "generic binder ref") >= type_count:
            fail("first-party-type-template-kind-mismatch", "generic binder ref is out of range")
        if kind == "FreshBinderRefV1" and v1_u32(value.get("fresh_slot"), "fresh binder ref") >= fresh_count:
            fail("first-party-projection-namespace-mismatch", "fresh binder ref is out of range")
        if kind == "ParameterSlotRefV1" and v1_u32(value.get("slot"), "parameter slot ref") >= slot_count:
            fail("first-party-static-scope-escape", "parameter slot ref is out of range")
        if kind in {"BindingCallbackRefV1", "CallableCallbackRefV1", "ContextualCallbackRefV1"} and value.get("callback_name") not in callbacks:
            fail("first-party-callback-scheme-mismatch", "callback ref is unresolved")
        for child in value.values():
            v1_registry_refs(child, type_count, fresh_count, slot_count, callbacks)
    elif isinstance(value, list):
        for child in value:
            v1_registry_refs(child, type_count, fresh_count, slot_count, callbacks)


def v1_validate_contract_template(value: Any, diagnostic: str) -> None:
    item = v1_closed(value, ["kind", "phase", "row", "suspension", "world", "flow", "temporal", "construction"], "FirstPartyContractTemplateV1")
    if item["kind"] != "FirstPartyContractTemplateV1":
        fail("Decode/tag-mismatch", "wrong first-party contract tag")
    if item["phase"] not in {"PureV1", "ComputeV1", "ActionV1", "CommitV1"}:
        fail(diagnostic, "first-party phase is not closed")
    if item["row"].get("kind") not in {
        "EmptyRowV1",
        "AnonymousAsyncRowV1",
        "GenericEffectRowV1",
        "CallbackRowV1",
    }:
        fail(diagnostic, "first-party row is not explicit")
    if item["suspension"].get("kind") not in {
        "NoSuspendV1",
        "AsyncMaySuspendV1",
        "CallbackSuspensionV1",
    }:
        fail(diagnostic, "first-party suspension is not closed")
    if item["world"].get("kind") not in {
        "SameWorldV1",
        "CallbackWorldV1",
        "ProjectPrivateWorldV1",
    } or item["flow"].get("kind") not in {
        "ReturnsOnlyV1",
        "AwaitOrParkV1",
        "CallbackFlowV1",
        "MapCallbackFlowV1",
    } or item["temporal"].get("kind") not in {"PureV1", "HostObservableV1"}:
        fail(diagnostic, "first-party world/flow/temporal contract differs")
    construction = item["construction"]
    if construction != {
        "kind": "CanonicalFirstPartyLiteralPathsV1",
        "demand_policy": "NormalizedRowAndKernelV1",
        "obligation_policy": "EvidenceArrayOrderV1",
        "site_policy": "AllReferencedDirectAndProjectedCallbackSitesV1",
        "result_policy": "TypeAndFlowDirectedV1",
        "capture_policy": "ActualArgumentsAndCallbacksV1",
        "usage_policy": "AuthoritySlotsExactV1",
        "origin_policy": "ElaborationOriginProjectionV1",
    }:
        fail(diagnostic, "literal-path construction policy differs")


def v1_validate_first_party(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "bindings"], "FirstPartyRegistryV1")
    validate_profile_header(root, "FirstPartyRegistryV1", 1, "first-party-registry-contract-nonunique")
    bindings = require_list(root["bindings"], "Decode/array-mismatch", "first-party bindings")
    ids = [binding.get("id") if isinstance(binding, dict) else None for binding in bindings]
    if ids != FIRST_PARTY_IDS or ids != sorted(ids) or len(set(ids)) != 21:
        fail("first-party-registry-noncanonical-order", "first-party ID vector differs")
    callback_count = 0
    for index, binding in enumerate(bindings):
        item = v1_closed(binding, ["kind", "id", "source", "slots", "types", "fresh", "direct", "callbacks", "evidence", "kernel"], "FirstPartyBindingV1")
        v1_validate_tagged_registry(item, item["id"])
        if item["kind"] != "FirstPartyBindingV1":
            fail("Decode/tag-mismatch", "wrong first-party binding tag")
        if item["source"] != FIRST_PARTY_SOURCES[index]:
            source_text = canonical_bytes(item["source"]).decode("utf-8")
            if "Event" in source_text or "on_async" in source_text or '"on"' in source_text:
                fail("first-party-static-scope-escape", "generic Event on/on_async is excluded")
            fail("first-party-registry-contract-nonunique", "source identity mapping differs")
        if item["kernel"] != FIRST_PARTY_KERNELS[index]:
            fail("first-party-registry-contract-nonunique", "kernel mapping differs")
        slots = require_list(item["slots"], "Decode/array-mismatch", "first-party slots")
        types = require_list(item["types"], "Decode/array-mismatch", "first-party type binders")
        fresh = require_list(item["fresh"], "Decode/array-mismatch", "first-party fresh binders")
        callbacks = require_list(item["callbacks"], "Decode/array-mismatch", "first-party callbacks")
        evidence = require_list(item["evidence"], "Decode/array-mismatch", "first-party evidence")
        if [slot.get("slot") for slot in slots] != list(range(len(slots))):
            fail("first-party-registry-contract-nonunique", "parameter slots are not contiguous")
        if [binder.get("binder_slot") for binder in types] != list(range(len(types))):
            fail("first-party-projection-namespace-mismatch", "generic binder namespace differs")
        if [binder.get("fresh_slot") for binder in fresh] != list(range(len(fresh))):
            fail("first-party-projection-namespace-mismatch", "fresh binder namespace differs")
        for slot in slots:
            if slot["kind"] == "ImplicitReceiverSlotV1":
                if slot["passing"] != "ImplicitReceiverV1":
                    fail("first-party-registry-contract-nonunique", "receiver passing differs")
            elif slot["kind"] == "NamedOrPositionalSlotV1":
                if slot["passing"] != "NamedOrPositionalV1" or slot["defaultable"] is not False:
                    fail("first-party-registry-contract-nonunique", "named slot passing/default differs")
            else:
                fail("Decode/tag-mismatch", "unknown first-party slot tag")
        callback_names = [callback.get("name") for callback in callbacks]
        if len(callback_names) != len(set(callback_names)):
            fail("first-party-callback-scheme-mismatch", "callback names are not unique")
        callback_set = set(callback_names)
        callback_count += len(callbacks)
        for callback in callbacks:
            callback_item = v1_closed(callback, ["kind", "name", "parameter_slot", "acquisition", "type", "contract", "scheme"], "FirstPartyCallbackV1")
            slot_index = v1_u32(callback_item["parameter_slot"], "callback parameter slot")
            expected_slot_type = {
                "kind": (
                    "ContextualCallbackRefV1"
                    if callback_item["acquisition"] == "ContextualV1"
                    else "CallableCallbackRefV1"
                ),
                "callback_name": callback_item["name"],
            }
            if slot_index >= len(slots) or slots[slot_index].get("type") != expected_slot_type:
                fail("first-party-callback-scheme-mismatch", "callback declaration/slot linkage differs")
            if callback_item["acquisition"] not in {"ContextualV1", "CallableValueV1"}:
                fail("first-party-callback-scheme-mismatch", "callback acquisition differs")
            v1_validate_contract_template(callback_item["contract"], "first-party-callback-scheme-mismatch")
            scheme = callback_item["scheme"]
            if scheme.get("kind") != "FirstPartyCallbackSchemeV1":
                fail("Decode/tag-mismatch", "wrong callback scheme tag")
            for field in ("captured_fresh_slots", "generated_fresh_slots"):
                refs = require_list(scheme[field], "Decode/array-mismatch", field)
                if refs != sorted(refs) or len(refs) != len(set(refs)) or any(v1_u32(ref, field) >= len(fresh) for ref in refs):
                    fail("first-party-callback-scheme-mismatch", field + " differs")
        v1_validate_contract_template(item["direct"], "first-party-registry-contract-nonunique")
        v1_registry_refs(item, len(types), len(fresh), len(slots), callback_set)
        rules = [entry.get("rule") for entry in evidence if isinstance(entry, dict) and entry.get("kind") == "ProofRuleEvidenceV1"]
        if item["id"].endswith("async.await-task") and "ShareableV1" not in rules:
            fail("first-party-registry-contract-nonunique", "await-task lacks ShareableV1(R)")
        if item["id"].endswith("ui.candidate-action"):
            body_callbacks = [
                callback
                for callback in callbacks
                if callback.get("name") == "body"
            ]
            if len(body_callbacks) != 1:
                fail("ui-action-must-return", "UI action body callback differs")
            action_contract = body_callbacks[0]["contract"]
            if action_contract.get("suspension") != {"kind": "NoSuspendV1"}:
                fail(
                    "ui-action-suspend-policy-required",
                    "UI action body must be explicitly non-suspending",
                )
            if action_contract.get("flow") != {
                "kind": "ReturnsOnlyV1",
                "result": {"kind": "BuiltinTypeTemplateV1", "name": "Unit"},
            }:
                fail("ui-action-must-return", "UI action body must return Unit")
            if "ActionSafeRowV1" not in rules:
                fail(
                    "ui-action-must-return",
                    "UI action row lacks the exact ActionSafeRowV1 evidence",
                )
            if "ShareableV1" not in rules or "EventOccurrenceStorageV1" not in rules:
                fail("first-party-action-occurrence-contract-mismatch", "UI action occurrence evidence differs")
            plans = [entry for entry in evidence if isinstance(entry, dict) and entry.get("kind") == "ActionPlanContractV1"]
            if len(plans) != 1 or plans[0].get("occurrence_policy") != "OwnerStoredExactQueuedOccurrenceV1":
                fail("first-party-action-occurrence-contract-mismatch", "UI action occurrence policy differs")
            v1_u32(
                plans[0].get("event_parameter_index"),
                "UI action event parameter index",
            )
    if callback_count != 8:
        fail("first-party-callback-scheme-mismatch", "first-party registry needs eight callbacks")
    if root != FIRST_PARTY_GOLDEN:
        fail(
            "first-party-registry-contract-nonunique",
            "registry does not deep-equal the authoritative 21-entry constructor expansion",
        )


def v1_validate_structural(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "bindings"], "StructuralIntrinsicRegistryV1")
    validate_profile_header(root, "StructuralIntrinsicRegistryV1", 1, "intrinsic-registry-root-mismatch")
    bindings = require_list(root["bindings"], "Decode/array-mismatch", "structural bindings")
    expected = [
        {"kind": "StructuralIntrinsicV1", "id": "Cire-v1.0/structural/build-string", "source_form": "StringInterpolationV1", "origin_kind": "SealedIntrinsicV1", "kernel": "BuildStringV1", "contract": "BuildStringContractV1"},
        {"kind": "StructuralIntrinsicV1", "id": "Cire-v1.0/structural/control-finally", "source_form": "@control::finally", "origin_kind": "SealedIntrinsicV1", "kernel": "ControlFinallyV1", "contract": "FinalizerContractV1"},
    ]
    for binding in bindings:
        v1_closed(binding, ["kind", "id", "source_form", "origin_kind", "kernel", "contract"], "StructuralIntrinsicV1")
    if bindings != expected:
        fail("intrinsic-registry-root-mismatch", "structural registry is not the exact two-entry vector")


def v1_validate_registry_root(value: Any) -> None:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "first_party", "structural"], "IntrinsicRegistryRootV1")
    validate_profile_header(root, "IntrinsicRegistryRootV1", 1, "intrinsic-registry-root-mismatch")
    v1_hash_ref(root["first_party"], "FirstPartyRegistryV1", "intrinsic-registry-root-mismatch")
    v1_hash_ref(root["structural"], "StructuralIntrinsicRegistryV1", "intrinsic-registry-root-mismatch")


TR0_DIAGNOSTIC_REGISTRY_HASH = (
    "sha256:d5768bc6de0deea92c8678bd41ecb0c999820b6fc52e16e30096d00924a3c7e0"
)
RETAINED_DIAGNOSTIC_LEDGER_TSV = """abort-has-no-resume-transition\tContractWF\tAbortTransition\tDeclarationV1\tabort-operation,forbidden-resume-transition\tNone\tR06-inline-handler
application-argument-type-mismatch\tContractWF\tCallableApplication\tArgumentV1\tactual-argument-type,expected-parameter-type,parameter-index\tManual\tR06-callable-hash-dag
application-arity-mismatch\tContractWF\tCallableApplication\tArgumentV1\tactual-arity,expected-arity\tManual\tR06-callable-hash-dag
call-obligation-unsatisfied\tContractWF\tCallObligation\tPrincipalV1\tobligation-id,obligation-stage,unsatisfied-predicate\tManual\tR06-callable-hash-dag
clock-package-family-not-clock-indexing\tKind\tClockFamily\tSynthesisBasisV1\tactual-family,expected-clock-indexing-family\tNone\tR06-packed-next
clock-package-path-observer-mismatch\tContractWF\tClockPathObserver\tSynthesisBasisV1\texpected-path-observer,observed-path-observer,path-index\tNone\tR06-packed-next
clock-package-private-identity-escape\tCapture\tClockIdentityEscape\tSynthesisBasisV1\tclock-slot,escaping-obligation-id\tNone\tR06-packed-next
clock-package-transfer-captures-private-identity\tCapture\tClockTransferCapture\tSynthesisBasisV1\tclock-slot,transfer-site\tNone\tR06-packed-next
contract-component-kind-mismatch\tContractWF\tContractComponentKind\tPrincipalV1\tcomponent-path,expected-kind,observed-kind\tNone\tR06-callable-hash-dag
contract-parameter-inconsistent-instantiation\tContractWF\tContractInstantiation\tArgumentV1\tcontract-parameter-slot,expected-instantiation,observed-instantiation\tNone\tR06-callable-hash-dag
contract-projection-escapes-scope\tCapture\tContractProjectionScope\tPrincipalV1\tbinder-slot,escaping-projection\tNone\tR06-callable-hash-dag
contract-term-cycle\tContractWF\tContractDependencyCycle\tDeclarationV1\tcontract-parameter-slot,cycle-path\tNone\tR06-callable-hash-dag
delegates-outside-handler-clause\tContractWF\tHandlerProjectionContext\tSynthesisBasisV1\tdelegates-site,expected-handler-clause\tNone\tR06-inline-handler
forward-application-arity-type-mismatch\tContractWF\tForwardApplication\tArgumentV1\tactual-argument-types,expected-parameter-types,forward-site\tNone\tR06-inline-handler
forward-disposition-quantity-mismatch\tUsage\tForwardDisposition\tSynthesisBasisV1\tavailable-quantity,forward-site,required-quantity\tNone\tR06-inline-handler
forward-obligation-projection-mismatch\tContractWF\tForwardObligationProjection\tSynthesisBasisV1\tforward-site,obligation-id,projection-stage\tNone\tR06-inline-handler
forward-operation-mismatch\tResolve\tForwardOperation\tSynthesisBasisV1\tactual-operation,expected-operation,forward-site\tNone\tR06-inline-handler
forward-route-mismatch\tResolve\tForwardRoute\tSynthesisBasisV1\tactual-route,expected-route,forward-site\tNone\tR06-inline-handler
handler-disposition-escapes-scope\tCapture\tHandlerDispositionScope\tDeclarationV1\tdisposition-binder,escaping-site\tNone\tR06-inline-handler
hof-complete-path-observer-mismatch\tContractWF\tHigherOrderPathObserver\tSynthesisBasisV1\texpected-path-observers,observed-path-observers,path-index\tNone\tR06-callable-hash-dag
imported-function-export-mismatch\tResolve\tImportedCallableResolution\tDeclarationV1\tactual-export-path,artifact-hash,expected-export-path\tNone\tR06-callable-hash-dag
local-function-evaluation-mismatch\tContractWF\tLocalCallableEvaluation\tDeclarationV1\texpected-path-contracts,local-declaration-slot,observed-path-contracts\tNone\tR06-callable-hash-dag
local-function-ref-unresolved\tResolve\tLocalCallableResolution\tPrincipalV1\tdeclaration-slot,reference-site\tNone\tR06-callable-hash-dag
multi-shot-captures-one-shot-resumption\tUsage\tResumptionUsage\tPrincipalV1\tcaptured-resumption-slot,closure-site,resumption-quantity\tManual\tR06-inline-handler
named-capability-escapes\tCapture\tCapabilityIdentityEscape\tPrincipalV1\tcapability-binder,escaping-site\tManual\tR06-capability-identity
no-matching-clock-lock\tWorld\tClockLock\tPrincipalV1\tavailable-clock-locks,required-clock\tManual\tR06-packed-next
packed-next-builder-result-mismatch\tContractWF\tPackedNextBuilder\tSynthesisBasisV1\tactual-builder-result,expected-packed-next-type\tNone\tR06-packed-next
packed-next-control-protocol-mismatch\tContractWF\tPackedNextControlProtocol\tSynthesisBasisV1\tactual-control-protocol,expected-control-protocol\tNone\tR06-packed-next
packed-next-observer-trust-mismatch\tContractWF\tPackedNextObserver\tSynthesisBasisV1\texpected-observer-summary,observed-observer-summary,path-index\tNone\tR06-packed-next
packed-next-owner-scope-mismatch\tOwner\tPackedNextOwnerScope\tSynthesisBasisV1\towner-slot,package-site\tNone\tR06-packed-next
packed-next-pack-phase-mismatch\tPhase\tPackedNextPhase\tSynthesisBasisV1\tactual-phase-requirement,expected-pack-phase,path-index\tNone\tR06-packed-next
packed-next-package-header-mismatch\tDecode\tPackedNextPackageHeader\tPrincipalV1\texpected-artifact-profile-version,observed-artifact-profile-version\tNone\tR06-packed-next
packed-next-runtime-protocol-mismatch\tContractWF\tPackedNextRuntimeProtocol\tSynthesisBasisV1\texpected-transition-table,first-invalid-transition,runtime-trace\tNone\tR06-packed-next
packed-next-sealed-origin-mismatch\tContractWF\tPackedNextSealedOrigin\tSynthesisBasisV1\texpected-sealed-origin,observed-sealed-origin\tNone\tR06-packed-next
packed-next-storage-owner-mismatch\tOwner\tPackedNextStorageOwner\tSynthesisBasisV1\towner-scope,storage-owner\tNone\tR06-packed-next
park-disposition-protocol-mismatch\tContractWF\tParkDisposition\tSynthesisBasisV1\tactual-disposition,expected-one-shot-disposition,park-site\tNone\tR06-task-multiwaiter-shareable
park-generation-protocol-mismatch\tContractWF\tParkGeneration\tSynthesisBasisV1\tactual-generation,expected-generation,park-site\tNone\tR06-task-multiwaiter-shareable
park-owner-outlives-missing\tOwner\tParkOwnerScope\tSynthesisBasisV1\tpark-owner,required-outlives-edge,resumption-owner\tNone\tR06-task-multiwaiter-shareable
park-path-observer-mismatch\tContractWF\tParkPathObserver\tSynthesisBasisV1\texpected-path-observer,observed-path-observer,park-site\tNone\tR06-task-multiwaiter-shareable
park-required-phase-mismatch\tPhase\tParkPhase\tPrincipalV1\tactual-phase-requirement,park-site,required-phase\tNone\tR06-task-multiwaiter-shareable
park-resumption-type-mismatch\tContractWF\tParkResumptionType\tSynthesisBasisV1\tcontinuation-answer-type,park-site,resumption-answer-type\tNone\tR06-task-multiwaiter-shareable
park-source-payload-mismatch\tContractWF\tParkPayloadType\tArgumentV1\tcompletion-port-type,park-source-type,resumption-argument-type\tNone\tR06-task-multiwaiter-shareable
path-bind-literal-prefix-forbidden\tContractWF\tPathBindPrefix\tSynthesisBasisV1\tpath-bind-site,prefix-outcome\tNone\tR06-callable-hash-dag
path-bind-observer-composition-mismatch\tContractWF\tPathBindObserver\tSynthesisBasisV1\tcomposed-observer,expected-observer,path-bind-site\tNone\tR06-callable-hash-dag
path-bind-return-binder-mismatch\tContractWF\tPathBindReturnBinder\tSynthesisBasisV1\tbinder-type,path-bind-site,returned-type\tNone\tR06-callable-hash-dag
path-bind-terminal-not-preserved\tContractWF\tPathBindTerminal\tSynthesisBasisV1\tobserved-terminal-policy,path-bind-site,required-terminal-policy\tNone\tR06-callable-hash-dag
positional-after-labelled\tParse\tCallAssembly\tArgumentV1\targument-index,first-labelled-index\tManual\tR06-call-assembly
projected-latent-site-key-mismatch\tContractWF\tLatentSiteProjection\tSynthesisBasisV1\tapplication-slot,latent-site-key,projected-source-site\tNone\tR06-inline-handler
projected-obligation-stage-lost\tContractWF\tObligationProjection\tSynthesisBasisV1\tobligation-id,projected-stage,source-stage\tNone\tR06-inline-handler
qualified-local-id-space-exhausted\tContractWF\tQualifiedLocalId\tSynthesisBasisV1\tapplication-slot,exhausted-u32-domain,local-id\tNone\tR06-callable-hash-dag
return-projection-does-not-match-flow\tContractWF\tReturnFlowProjection\tSynthesisBasisV1\texpected-flow-projection,observed-return-projection\tNone\tR06-callable-hash-dag
semantic-summary-not-normalized\tContractWF\tSemanticSummaryNormalization\tPrincipalV1\texpected-normal-form,observed-summary\tNone\tR06-callable-hash-dag
term-actual-source-unavailable\tContractWF\tTermActualSource\tArgumentV1\tformal-parameter-slot,surviving-projection\tNone\tR06-callable-hash-dag
term-actual-substitution-mismatch\tContractWF\tTermActualSubstitution\tArgumentV1\tactual-summary,formal-parameter-slot,projected-observer\tNone\tR06-callable-hash-dag
terminal-transfer-has-no-value\tFlow\tTerminalFlow\tPrincipalV1\tterminal-outcome,value-context\tNone\tR06-callable-hash-dag
unknown-contract-computation-variant\tDecode\tContractComputationVariant\tPrincipalV1\tcomputation-tag,contract-path\tNone\tR06-callable-hash-dag
unknown-obligation-stage\tDecode\tObligationStage\tPrincipalV1\tobligation-id,observed-stage\tNone\tR06-callable-hash-dag
unknown-obligation-variant\tDecode\tObligationVariant\tPrincipalV1\tobligation-id,obligation-tag\tNone\tR06-callable-hash-dag
unknown-path-outcome-v2\tDecode\tPathOutcomeVariant\tPrincipalV1\toutcome-tag,path-index\tNone\tR06-callable-hash-dag
unknown-resumption-primitive\tResolve\tResumptionPrimitive\tPrincipalV1\tallowed-primitives,observed-primitive\tManual\tR06-inline-handler
unsupported-contract-schema-version\tDecode\tContractSchemaVersion\tPrincipalV1\tobserved-schema-version,supported-schema-version\tNone\tR06-callable-hash-dag
wire-u32-out-of-range\tDecode\tWireU32\tPrincipalV1\tfield-path,observed-value,valid-range\tNone\tR06-callable-hash-dag"""


def build_retained_diagnostic_ledger() -> Dict[str, Dict[str, Any]]:
    result: Dict[str, Dict[str, Any]] = {}
    for line in RETAINED_DIAGNOSTIC_LEDGER_TSV.splitlines():
        identifier, stage, cluster, role, notes, fix_safety, owner = line.split("\t")
        if identifier in result:
            raise AssertionError("duplicate retained diagnostic " + identifier)
        result[identifier] = {
            "entry": {
                "id": identifier,
                "stage": stage,
                "causal_cluster": cluster,
                "primary_origin_role": role,
                "required_notes": notes.split(","),
                "fix_safety": fix_safety,
            },
            "owner": owner,
        }
    if len(result) != 62:
        raise AssertionError("retained diagnostic ledger must contain 62 rows")
    return result


RETAINED_DIAGNOSTIC_LEDGER = build_retained_diagnostic_ledger()


def v1_retained_diagnostic_entry(identifier: str, old_stage: str) -> Dict[str, Any]:
    del old_stage
    row = RETAINED_DIAGNOSTIC_LEDGER.get(identifier)
    if row is None:
        fail(
            "Decode/diagnostic-registry-mismatch",
            identifier + " has no reviewed retained-diagnostic tuple",
        )
    return copy.deepcopy(row["entry"])


def v1_validate_diagnostics(value: Any) -> set[str]:
    root = v1_closed(value, ["artifact", "diagnostics", "profile", "schema_version"], "CireDiagnosticsV3")
    validate_profile_header(root, "CireDiagnosticsV3", 3, "Decode/diagnostic-registry-mismatch")
    entries = require_list(root["diagnostics"], "Decode/array-mismatch", "diagnostics")
    ids: List[str] = []
    stage_by_id: Dict[str, str] = {}
    allowed_stages = ["Decode", "Lex", "Parse", "Syntax", "Resolve", "Kind", "Type", "Row", "HandlerWF", "Flow", "Capture", "Usage", "World", "Phase", "Owner", "ContractWF"]
    allowed_roles = {"PrincipalV1", "ArgumentV1", "DeclarationV1", "SynthesisBasisV1"}
    for entry in entries:
        item = v1_closed(entry, ["id", "stage", "causal_cluster", "primary_origin_role", "required_notes", "fix_safety"], "DiagnosticEntryV3")
        diagnostic_id = v1_string(item["id"], "diagnostic id")
        ids.append(diagnostic_id)
        stage_by_id[diagnostic_id] = item["stage"]
        if item["stage"] not in allowed_stages:
            fail("Decode/enum-mismatch", diagnostic_id + " has an unknown stage")
        if item["primary_origin_role"] not in allowed_roles:
            fail("Decode/enum-mismatch", diagnostic_id + " has an unknown OriginRoleV1")
        if item["fix_safety"] not in {"None", "Manual", "MachineApplicable", "MaybeIncorrect"}:
            fail("Decode/enum-mismatch", diagnostic_id + " has unknown fix safety")
        notes = require_list(item["required_notes"], "Decode/array-mismatch", diagnostic_id + " notes")
        if notes != sorted(notes) or len(notes) != len(set(notes)):
            fail("Decode/diagnostic-registry-mismatch", diagnostic_id + " notes are not canonical")
        for note in notes:
            v1_string(note, diagnostic_id + " note")
    if len(ids) != 133 or ids != sorted(ids) or len(set(ids)) != len(ids):
        fail("Decode/diagnostic-registry-mismatch", "diagnostic registry is not the exact 133-entry order")
    retained = load_json(ROOT / "diagnostics-v2.json")
    if object_hash(retained) != TR0_DIAGNOSTIC_REGISTRY_HASH:
        fail(
            "Decode/diagnostic-registry-mismatch",
            "frozen TR0 diagnostic source differs",
        )
    retained_entries = require_list(
        retained.get("diagnostics"),
        "Decode/diagnostic-registry-mismatch",
        "retained diagnostics",
    )
    entry_by_id = {entry["id"]: entry for entry in entries}
    retained_ids = {entry["id"] for entry in retained_entries}
    if not retained_ids.issubset(entry_by_id):
        fail(
            "Decode/diagnostic-registry-mismatch",
            "successor registry dropped a retained TR0 diagnostic",
        )
    for old_entry in retained_entries:
        identifier = old_entry["id"]
        if identifier not in {
            "associated-contract-mismatch",
            "associated-declaration-constraint-not-in-profile",
            "associated-parameterization-not-in-profile",
            "effect-header-conformance-mismatch",
            "independent-ability-impl-not-in-profile",
            "operation-secondary-row-must-be-closed",
            "row-literal-has-multiple-tails",
            "row-predicate-not-in-profile",
        } and entry_by_id[identifier] != v1_retained_diagnostic_entry(
            identifier, old_entry["stage"]
        ):
            fail(
                "Decode/diagnostic-registry-mismatch",
                identifier + " retained V2-to-V3 tuple differs",
            )
    required = {
        "associated-contract-mismatch": "Kind",
        "associated-declaration-constraint-not-in-profile": "Kind",
        "associated-parameterization-not-in-profile": "Kind",
        "effect-header-conformance-mismatch": "Resolve",
        "extension-self-parameter-required": "Syntax",
        "impl-visibility-not-allowed": "Syntax",
        "operation-secondary-row-must-be-closed": "ContractWF",
        "row-literal-has-multiple-tails": "Row",
        "named-function-effect-row-required": "Syntax",
        "callable-source-import-collision": "Resolve",
        "callable-interface-contract-mismatch": "ContractWF",
        "ui-action-must-return": "Flow",
        "ui-action-suspend-policy-required": "Phase",
        "maytrap-not-an-effect": "Row",
    }
    for diagnostic_id, stage in required.items():
        if stage_by_id.get(diagnostic_id) != stage:
            fail("Decode/diagnostic-registry-mismatch", diagnostic_id + " has the wrong stage")
    return set(ids)


def v1_check_frozen(path: str, value: Any, diagnostic: str) -> None:
    expected = EXPECTED_MODEL_HASHES.get(path)
    if expected is None:
        fail(
            "Decode/frozen-model-set-mismatch",
            path + " is absent from the exact semantic-model hash table",
        )
    if object_hash(value) != expected:
        fail(diagnostic, path + " differs from its frozen exact semantic model")


def v1_validate_frozen_model_set(documents: Mapping[str, Any]) -> None:
    expected_paths = set(ARTIFACT_FILES) - {
        "authority-rule-coverage.json",
        "mutations/profile-mutations.json",
    }
    if set(EXPECTED_MODEL_HASHES) != expected_paths:
        fail(
            "Decode/frozen-model-set-mismatch",
            "semantic-model hash table does not cover the exact non-meta artifact set",
        )
    for path in sorted(expected_paths):
        v1_check_frozen(
            path,
            documents[path],
            "Decode/frozen-model-hash-mismatch",
        )


def v1_validate_artifact(path: str, value: Any, frozen: bool = True) -> None:
    dispatch = {
        "interfaces/ability-declaration.json": (
            v1_validate_ability_declaration,
            "callable-interface-contract-mismatch",
        ),
        "diagnostics-v3.json": (v1_validate_diagnostics, "Decode/diagnostic-registry-mismatch"),
        "interfaces/canonicalization-cases.json": (v1_validate_canonicalization, "Decode/canonicalization-mismatch"),
        "interfaces/call-assembly.json": (
            v1_validate_call_assembly,
            "callable-interface-contract-mismatch",
        ),
        "interfaces/callable-contract-fact.json": (v1_validate_callable_fact, "callable-interface-contract-mismatch"),
        "interfaces/callable-interface.json": (v1_validate_callable, "callable-interface-contract-mismatch"),
        "interfaces/component-interface.json": (v1_validate_component, "component-public-type-not-safe"),
        "interfaces/component-manifest.json": (v1_validate_component_manifest, "component-public-type-not-safe"),
        "interfaces/const-values.json": (v1_validate_const, "const-operation-not-safe"),
        "interfaces/const-declaration.json": (
            v1_validate_const_declaration,
            "const-operation-not-safe",
        ),
        "interfaces/control-mutation.json": (
            v1_validate_control_mutation,
            "runtime-protocol-trace-mismatch",
        ),
        "interfaces/elaboration-origin-map.json": (validate_origin_map, "origin-map-noncanonical"),
        "interfaces/data-declaration.json": (
            v1_validate_data_declaration,
            "record-construction-missing-field",
        ),
        "interfaces/effect-declaration.json": (
            v1_validate_effect_declaration,
            "effect-header-conformance-mismatch",
        ),
        "interfaces/first-party-registry.json": (v1_validate_first_party, "first-party-registry-contract-nonunique"),
        "interfaces/function-contract-v3.json": (v1_validate_function_contract, "callable-interface-contract-mismatch"),
        "interfaces/function-contract-v3-suite.json": (v1_validate_function_contract_suite, "callable-interface-contract-mismatch"),
        "interfaces/intrinsic-registry.json": (v1_validate_registry_root, "intrinsic-registry-root-mismatch"),
        "interfaces/impl-evidence.json": (
            v1_validate_impl_evidence,
            "trait-impl-overlap",
        ),
        "interfaces/language-interface.json": (v1_validate_language, "callable-interface-contract-mismatch"),
        "interfaces/link-abi.json": (v1_validate_link, "component-public-type-not-safe"),
        "interfaces/local-inference.json": (
            v1_validate_local_inference,
            "callable-interface-contract-mismatch",
        ),
        "interfaces/nominal-data.json": (v1_validate_nominal, "record-construction-missing-field"),
        "interfaces/numeric-semantics.json": (v1_validate_numeric, "integer-conversion-out-of-range"),
        "interfaces/primitive-catalog.json": (v1_validate_primitive_catalog, "package-instance-hash-mismatch"),
        "interfaces/structural-intrinsic-registry.json": (v1_validate_structural, "intrinsic-registry-root-mismatch"),
        "interfaces/trait-impl-extension.json": (v1_validate_traits, "trait-impl-overlap"),
        "interfaces/trait-declaration.json": (
            v1_validate_trait_declaration,
            "trait-impl-overlap",
        ),
        "runtime/protocol-models.json": (validate_runtime, "runtime-protocol-trace-mismatch"),
    }
    pair = dispatch.get(path)
    if pair is None:
        fail("Decode/unsupported-artifact", path + " has no exact decoder")
    validator, diagnostic = pair
    try:
        validator(value)
    except ValidationFailure:
        raise
    except (AttributeError, IndexError, KeyError, TypeError, ValueError) as error:
        fail(
            "Decode/container-mismatch",
            path
            + " decoder rejected malformed structure without leaking host "
            + type(error).__name__,
        )
    if frozen:
        v1_check_frozen(path, value, diagnostic)


def v1_validate_preimage(document: Any, preimage: Any) -> None:
    if not isinstance(preimage, dict):
        fail("Decode/mutation-corpus", "preimage must be an object")
    if set(preimage) == {"path", "value"}:
        if resolve_pointer(document, preimage["path"]) != preimage["value"]:
            fail("Decode/mutation-corpus", "preimage value differs")
        return
    item = v1_closed(preimage, ["path", "value_kind"], "mutation preimage")
    target = resolve_pointer(document, item["path"])
    kind = item["value_kind"]
    if kind == "nonzero-sha256":
        if not isinstance(target, str) or not SHA256_RE.fullmatch(target) or target == ZERO_HASH:
            fail("Decode/mutation-corpus", "expected nonzero sha256 preimage")
    elif kind == "postfix-derive-spelling":
        if not isinstance(target, str) or "} derive(" not in target:
            fail("Decode/mutation-corpus", "expected postfix derive spelling")
    elif kind == "one-impl":
        if not isinstance(target, list) or len(target) != 1:
            fail("Decode/mutation-corpus", "expected one impl")
    elif kind == "two-structural-bindings":
        if not isinstance(target, list) or len(target) != 2:
            fail("Decode/mutation-corpus", "expected two structural bindings")
    elif kind == "explicit-first-party-row":
        if not isinstance(target, dict) or target.get("kind") not in {"EmptyRowV1", "AnonymousAsyncRowV1"}:
            fail("Decode/mutation-corpus", "expected explicit first-party row")
    elif kind == "nonempty-array":
        if not isinstance(target, list) or not target:
            fail("Decode/mutation-corpus", "expected nonempty array")
    else:
        fail("Decode/mutation-corpus", "unknown preimage value kind")


def v1_failure_shape(error: ValidationFailure) -> Dict[str, str]:
    if error.diagnostic.startswith("Decode/"):
        return {"kind": "DecodeFailureV1", "code": error.diagnostic.split("/", 1)[1]}
    return {"kind": "DiagnosticV1", "id": error.diagnostic}


def v1_build_mutation_corpus(documents: Mapping[str, Any]) -> Dict[str, Any]:
    """Build the finite, hash-bound successor rejection/metadata corpus."""

    cases: List[Dict[str, Any]] = []

    def diagnostic(identifier: str) -> Dict[str, str]:
        return {"kind": "DiagnosticV1", "id": identifier}

    def decode(code: str) -> Dict[str, str]:
        return {"kind": "DecodeFailureV1", "code": code}

    def add_case(
        identifier: str,
        path: str,
        rule_id: str,
        expected_failure: Mapping[str, str],
        operations: Sequence[Mapping[str, Any]],
        preimage_path: str,
        *,
        preimage_kind: str | None = None,
    ) -> None:
        if preimage_kind is None:
            preimage = {
                "path": preimage_path,
                "value": copy.deepcopy(resolve_pointer(documents[path], preimage_path)),
            }
        else:
            preimage = {"path": preimage_path, "value_kind": preimage_kind}
        cases.append(
            {
                "artifact_path": path,
                "base_hash": object_hash(documents[path]),
                "expected_failure": dict(expected_failure),
                "id": identifier,
                "operations": copy.deepcopy(list(operations)),
                "preimage": preimage,
                "rule_id": rule_id,
            }
        )

    add_case(
        "callable-contract-hash-zero",
        "interfaces/callable-interface.json",
        "R06-callable-hash-dag",
        diagnostic("callable-interface-contract-mismatch"),
        [{"op": "replace", "path": "/core_contract/artifact_hash", "value": ZERO_HASH}],
        "/core_contract/artifact_hash",
        preimage_kind="nonzero-sha256",
    )
    add_case(
        "callable-extra-root-field",
        "interfaces/callable-interface.json",
        "R06-callable-hash-dag",
        decode("closed-field-mismatch"),
        [{"op": "add", "path": "/shadow_contract", "value": {}}],
        "/artifact",
    )
    add_case(
        "callable-module-prefix-drift",
        "interfaces/callable-interface.json",
        "FND-package-instance-identity",
        diagnostic("package-instance-hash-mismatch"),
        [{"op": "replace", "path": "/module/0", "value": "cire"}],
        "/module/0",
    )
    add_case(
        "callable-slot-container-wrong",
        "interfaces/callable-interface.json",
        "R06-call-assembly",
        decode("array-mismatch"),
        [{"op": "replace", "path": "/surface_signature/slots", "value": {}}],
        "/surface_signature/slots",
    )
    add_case(
        "canonical-root-extra-field",
        "interfaces/canonicalization-cases.json",
        "R06-callable-hash-dag",
        decode("closed-field-mismatch"),
        [{"op": "add", "path": "/normalization", "value": "forbidden"}],
        "/artifact",
    )
    add_case(
        "canonical-scalar-surrogate",
        "interfaces/canonicalization-cases.json",
        "FND-semantic-string-const-bytes",
        decode("unicode-scalar-mismatch"),
        [{"op": "replace", "path": "/scalar_probe", "value": 0xD800}],
        "/scalar_probe",
    )
    add_case(
        "call-assembly-evaluation-order-drift",
        "interfaces/call-assembly.json",
        "R06-call-assembly",
        diagnostic("callable-interface-contract-mismatch"),
        [
            {
                "op": "replace",
                "path": "/cases/6/expected/evaluation_order/1",
                "value": "measure_gap",
            }
        ],
        "/cases/6/expected/evaluation_order/1",
    )
    add_case(
        "component-bytes-not-u8",
        "interfaces/component-interface.json",
        "FND-component-sync-v1",
        diagnostic("component-public-type-not-safe"),
        [{"op": "replace", "path": "/type_mappings/0/canonical_abi/element/scalar", "value": "S8V1"}],
        "/type_mappings/0/canonical_abi/element/scalar",
    )
    add_case(
        "component-native-async",
        "interfaces/component-interface.json",
        "FND-component-sync-v1",
        diagnostic("component-native-async-not-in-v1"),
        [{"op": "replace", "path": "/native_async", "value": True}],
        "/native_async",
    )
    add_case(
        "component-public-plan",
        "interfaces/component-interface.json",
        "R06-public-plan-commit-excluded",
        diagnostic("component-public-type-not-safe"),
        [{"op": "replace", "path": "/exports/0/wit_path/1", "value": "Plan"}],
        "/exports/0/wit_path/1",
    )
    add_case(
        "control-place-write-before-rhs",
        "interfaces/control-mutation.json",
        "FND-mutation-place-replay",
        diagnostic("runtime-protocol-trace-mismatch"),
        [
            {
                "op": "replace",
                "path": "/place_trace/events/3/op",
                "value": "write",
            }
        ],
        "/place_trace/events/3/op",
    )
    add_case(
        "inline-handler-kernel-drift",
        "interfaces/control-mutation.json",
        "R06-inline-handler",
        diagnostic("callable-interface-contract-mismatch"),
        [
            {
                "op": "replace",
                "path": "/handler_elaboration_differential/inline/projection/kernel/clause_modes/0",
                "value": "once",
            }
        ],
        "/handler_elaboration_differential/inline/projection/kernel/clause_modes/0",
    )
    add_case(
        "const-byte-out-of-range",
        "interfaces/const-values.json",
        "FND-primitive-wire-forms",
        diagnostic("byte-literal-out-of-range"),
        [{"op": "replace", "path": "/definitions/3/value/bytes/3", "value": 256}],
        "/definitions/3/value/bytes/3",
    )
    add_case(
        "const-definition-row-removed",
        "interfaces/const-values.json",
        "FND-explicit-named-rows",
        decode("closed-field-mismatch"),
        [{"op": "remove", "path": "/definitions/2/effect_row"}],
        "/definitions/2/effect_row",
    )
    add_case(
        "const-semantic-string-scalar-drift",
        "interfaces/const-values.json",
        "FND-semantic-string-const-bytes",
        diagnostic("semantic-string-payload-mismatch"),
        [{"op": "replace", "path": "/definitions/0/value/unicode_scalars/1", "value": 233}],
        "/definitions/0/value/unicode_scalars/1",
    )
    add_case(
        "diagnostic-origin-role-unknown",
        "diagnostics-v3.json",
        "R06-diagnostic-origin-stability",
        decode("enum-mismatch"),
        [{"op": "replace", "path": "/diagnostics/0/primary_origin_role", "value": "Direct"}],
        "/diagnostics/0/primary_origin_role",
    )
    add_case(
        "diagnostic-stage-unknown",
        "diagnostics-v3.json",
        "R06-diagnostic-origin-stability",
        decode("enum-mismatch"),
        [{"op": "replace", "path": "/diagnostics/0/stage", "value": "RowWF"}],
        "/diagnostics/0/stage",
    )
    add_case(
        "first-party-await-task-shareability-removed",
        "interfaces/first-party-registry.json",
        "R06-task-multiwaiter-shareable",
        diagnostic("first-party-registry-contract-nonunique"),
        [{"op": "remove", "path": "/bindings/1/evidence/6"}],
        "/bindings/1/evidence",
        preimage_kind="nonempty-array",
    )
    add_case(
        "first-party-callback-slot-out-of-range",
        "interfaces/first-party-registry.json",
        "R06-first-party-registry",
        diagnostic("first-party-callback-scheme-mismatch"),
        [{"op": "replace", "path": "/bindings/3/callbacks/0/parameter_slot", "value": 99}],
        "/bindings/3/callbacks/0/parameter_slot",
    )
    add_case(
        "first-party-generic-event-on-async",
        "interfaces/first-party-registry.json",
        "R06-no-generic-event-on",
        diagnostic("first-party-static-scope-escape"),
        [{"op": "replace", "path": "/bindings/5/source/name", "value": "Event.on_async"}],
        "/bindings/5/source/name",
    )
    add_case(
        "first-party-id-order-drift",
        "interfaces/first-party-registry.json",
        "R06-first-party-registry",
        diagnostic("first-party-registry-noncanonical-order"),
        [{"op": "replace", "path": "/bindings/0/id", "value": "z.invalid"}],
        "/bindings/0/id",
    )
    add_case(
        "first-party-ui-occurrence-policy-drift",
        "interfaces/first-party-registry.json",
        "R06-ui-exact-occurrence",
        diagnostic("first-party-action-occurrence-contract-mismatch"),
        [{"op": "replace", "path": "/bindings/16/evidence/5/occurrence_policy", "value": "LateRereadV1"}],
        "/bindings/16/evidence/5/occurrence_policy",
    )
    add_case(
        "first-party-ui-action-row-evidence-removed",
        "interfaces/first-party-registry.json",
        "R06-ui-action-flow",
        diagnostic("ui-action-must-return"),
        [
            {
                "op": "replace",
                "path": "/bindings/16/evidence/0/rule",
                "value": "NotActionSafeV1",
            }
        ],
        "/bindings/16/evidence/0/rule",
    )
    add_case(
        "first-party-ui-action-suspends",
        "interfaces/first-party-registry.json",
        "R06-ui-action-flow",
        diagnostic("ui-action-suspend-policy-required"),
        [
            {
                "op": "replace",
                "path": "/bindings/16/callbacks/0/contract/suspension/kind",
                "value": "AsyncMaySuspendV1",
            }
        ],
        "/bindings/16/callbacks/0/contract/suspension/kind",
    )
    add_case(
        "first-party-ui-action-wrong-result",
        "interfaces/first-party-registry.json",
        "R06-ui-action-flow",
        diagnostic("ui-action-must-return"),
        [
            {
                "op": "replace",
                "path": "/bindings/16/callbacks/0/contract/flow/result/name",
                "value": "Int",
            }
        ],
        "/bindings/16/callbacks/0/contract/flow/result/name",
    )
    add_case(
        "v3-direct-capability-defaultability-drift",
        "interfaces/function-contract-v3-suite.json",
        "R06-capability-identity",
        diagnostic("capability-binder-default-not-in-v1"),
        [
            {
                "op": "replace",
                "path": "/cases/3/surface_signature/slots/1/defaultable",
                "value": True,
            }
        ],
        "/cases/3/surface_signature/slots/1/defaultable",
    )
    add_case(
        "v3-direct-capability-identity-drift",
        "interfaces/function-contract-v3-suite.json",
        "R06-capability-identity",
        diagnostic("capability-identity-required"),
        [
            {
                "op": "replace",
                "path": "/cases/3/contract/binders/identity_binders/0/identity_slot",
                "value": 7,
            }
        ],
        "/cases/3/contract/binders/identity_binders/0/identity_slot",
    )
    add_case(
        "language-evidence-hash-zero",
        "interfaces/language-interface.json",
        "R06-callable-hash-dag",
        diagnostic("callable-interface-contract-mismatch"),
        [{"op": "replace", "path": "/evidence/0/evidence/artifact_hash", "value": ZERO_HASH}],
        "/evidence/0/evidence/artifact_hash",
        preimage_kind="nonzero-sha256",
    )
    add_case(
        "language-package-digest-drift",
        "interfaces/language-interface.json",
        "FND-package-instance-identity",
        diagnostic("package-instance-hash-mismatch"),
        [{"op": "replace", "path": "/package_instance_id/digest", "value": "f" * 64}],
        "/package_instance_id/digest",
    )
    add_case(
        "link-language-hash-zero",
        "interfaces/link-abi.json",
        "R06-callable-hash-dag",
        diagnostic("callable-interface-contract-mismatch"),
        [{"op": "replace", "path": "/language_interface/artifact_hash", "value": ZERO_HASH}],
        "/language_interface/artifact_hash",
        preimage_kind="nonzero-sha256",
    )
    add_case(
        "local-inference-safe-value-decision-drift",
        "interfaces/local-inference.json",
        "FND-local-inference-boundary",
        diagnostic("callable-interface-contract-mismatch"),
        [
            {
                "op": "replace",
                "path": "/generalization_cases/15/expected/decision",
                "value": "WeakMonomorphicV1",
            }
        ],
        "/generalization_cases/15/expected/decision",
    )
    add_case(
        "manifest-public-plan",
        "interfaces/component-manifest.json",
        "R06-public-plan-commit-excluded",
        diagnostic("component-public-type-not-safe"),
        [{"op": "replace", "path": "/exports/0/wit_path/1", "value": "Plan"}],
        "/exports/0/wit_path/1",
    )
    add_case(
        "nominal-prefix-derive",
        "interfaces/nominal-data.json",
        "FND-postfix-derive",
        diagnostic("postfix-derive-required"),
        [{"op": "replace", "path": "/declarations/1/source_spelling", "value": "derive(Eq, Show) pub struct Point { pub x : Int, pub y : Int = 0 }"}],
        "/declarations/1/source_spelling",
        preimage_kind="postfix-derive-spelling",
    )
    add_case(
        "nominal-record-variant-default-removed",
        "interfaces/nominal-data.json",
        "FND-nominal-data",
        diagnostic("record-construction-missing-field"),
        [
            {
                "op": "replace",
                "path": "/declarations/5/variants/0/fields/0/default",
                "value": None,
            }
        ],
        "/declarations/5/variants/0/fields/0/default",
    )
    add_case(
        "numeric-boundary-accepted-out-of-range",
        "interfaces/numeric-semantics.json",
        "FND-numeric-semantics",
        diagnostic("integer-conversion-out-of-range"),
        [{"op": "replace", "path": "/integer_boundary_cases/0/expected", "value": "AcceptedV1"}],
        "/integer_boundary_cases/0/expected",
    )
    add_case(
        "numeric-maytrap-laundered-as-row",
        "interfaces/numeric-semantics.json",
        "FND-maytrap-defect-transition",
        diagnostic("maytrap-not-an-effect"),
        [{"op": "replace", "path": "/integer_policy/default_operations", "value": "EffectRowEntryV1"}],
        "/integer_policy/default_operations",
    )
    add_case(
        "origin-site-allocation-drift",
        "interfaces/elaboration-origin-map.json",
        "R06-origin-arena",
        diagnostic("origin-map-noncanonical"),
        [{"op": "replace", "path": "/sites/0/origin_id", "value": 2}],
        "/sites/0/origin_id",
    )
    add_case(
        "primitive-name-duplicate",
        "interfaces/primitive-catalog.json",
        "FND-primitive-wire-forms",
        diagnostic("package-instance-hash-mismatch"),
        [{"op": "replace", "path": "/entries/3/source_name", "value": "Bool"}],
        "/entries/3/source_name",
    )
    add_case(
        "primitive-sealed-module-drift",
        "interfaces/primitive-catalog.json",
        "FND-primitive-wire-forms",
        diagnostic("package-instance-hash-mismatch"),
        [{"op": "replace", "path": "/entries/3/type/module/0", "value": "cire"}],
        "/entries/3/type/module/0",
    )
    add_case(
        "registry-root-first-party-zero",
        "interfaces/intrinsic-registry.json",
        "R06-first-party-registry",
        diagnostic("intrinsic-registry-root-mismatch"),
        [{"op": "replace", "path": "/first_party/artifact_hash", "value": ZERO_HASH}],
        "/first_party/artifact_hash",
        preimage_kind="nonzero-sha256",
    )
    checkpoint = {
        "kind": "StructuralIntrinsicV1",
        "id": "Cire-v1.0/structural/checkpoint",
        "source_form": "CheckpointV1",
        "origin_kind": "SealedIntrinsicV1",
        "kernel": "CheckpointV1",
        "contract": "CheckpointContractV1",
    }
    add_case(
        "structural-generic-checkpoint-added",
        "interfaces/structural-intrinsic-registry.json",
        "R06-sealed-checkpoint",
        diagnostic("intrinsic-registry-root-mismatch"),
        [{"op": "add", "path": "/bindings/-", "value": checkpoint}],
        "/bindings",
        preimage_kind="two-structural-bindings",
    )
    duplicate_impl = copy.deepcopy(documents["interfaces/trait-impl-extension.json"]["impls"][0])
    duplicate_impl["identity"] = "impl-display-name-for-point-duplicate"
    add_case(
        "trait-overlapping-impl-added",
        "interfaces/trait-impl-extension.json",
        "FND-trait-coherence",
        diagnostic("trait-impl-overlap"),
        [{"op": "add", "path": "/impls/-", "value": duplicate_impl}],
        "/impls",
        preimage_kind="one-impl",
    )
    add_case(
        "trait-extension-self-renamed",
        "interfaces/trait-impl-extension.json",
        "FND-method-resolution",
        diagnostic("extension-self-parameter-required"),
        [{"op": "replace", "path": "/extensions/0/parameters/0", "value": "items : Array[String]"}],
        "/extensions/0/parameters/0",
    )
    add_case(
        "runtime-checkpoint-commit-before-prepare",
        "runtime/protocol-models.json",
        "R06-sealed-checkpoint",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/0/events/2/op", "value": "commit"}],
        "/traces/0/events/2/op",
    )
    add_case(
        "runtime-resource-stale-settlement-committed",
        "runtime/protocol-models.json",
        "R06-resource-latest-retained",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/7/events/5/generation", "value": "2"}],
        "/traces/7/events/5/generation",
    )
    add_case(
        "runtime-sealed-finally-terminal-drift",
        "runtime/protocol-models.json",
        "R06-cleanup-receipt-report",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/8/events/3/tag", "value": "ReturnsV2"}],
        "/traces/8/events/3/tag",
    )
    add_case(
        "runtime-signal-untracked-invalidation",
        "runtime/protocol-models.json",
        "R06-signal-tracking",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/9/events/4/dependency", "value": "source-z"}],
        "/traces/9/events/4/dependency",
    )
    add_case(
        "runtime-ui-occurrence-late-reread",
        "runtime/protocol-models.json",
        "R06-ui-exact-occurrence",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/12/events/1/payload/draft", "value": "changed-after-enqueue"}],
        "/traces/12/events/1/payload/draft",
    )
    add_case(
        "runtime-trace-model-binding-drift",
        "runtime/protocol-models.json",
        "R06-runtime-symbolic-replay",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/0/model", "value": "ResourceV1"}],
        "/traces/0/model",
    )
    add_case(
        "runtime-caller-authored-expected-added",
        "runtime/protocol-models.json",
        "R06-runtime-symbolic-replay",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "add", "path": "/traces/0/expected", "value": {}}],
        "/traces/0/id",
    )
    add_case(
        "runtime-checkpoint-noncanonical-nat",
        "runtime/protocol-models.json",
        "R06-sealed-checkpoint",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/0/events/0/epoch", "value": "00"}],
        "/traces/0/events/0/epoch",
    )
    add_case(
        "runtime-checkpoint-prepare-without-dependencies",
        "runtime/protocol-models.json",
        "R06-sealed-checkpoint",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "remove", "path": "/traces/0/events/2"}],
        "/traces/0/events/2/op",
    )
    add_case(
        "runtime-component-child-owner-not-fresh",
        "runtime/protocol-models.json",
        "R06-cleanup-receipt-report",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/2/events/0/child_owner", "value": "owner-ui"}],
        "/traces/2/events/0/child_owner",
    )
    add_case(
        "runtime-packed-close-receipt-drift",
        "runtime/protocol-models.json",
        "R06-packed-next",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/3/events/1/receipt", "value": "foreign-receipt"}],
        "/traces/3/events/1/receipt",
    )
    add_case(
        "runtime-packed-terminal-lost",
        "runtime/protocol-models.json",
        "R06-packed-next",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "remove", "path": "/traces/3/events/2"}],
        "/traces/3/events/2/op",
    )
    add_case(
        "runtime-resource-dispose-with-live-candidate",
        "runtime/protocol-models.json",
        "R06-resource-latest-retained",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/7/events/5", "value": {"op": "dispose", "reason": "ExplicitDisposeV1"}}],
        "/traces/7/events/5/op",
    )
    add_case(
        "runtime-resource-closed-view-lost",
        "runtime/protocol-models.json",
        "R06-resource-latest-retained",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "remove", "path": "/traces/7/events/8"}],
        "/traces/7/events/8/op",
    )
    add_case(
        "runtime-finally-role-open-world",
        "runtime/protocol-models.json",
        "R06-cleanup-receipt-report",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/8/events/1/role", "value": "UserRoleV1"}],
        "/traces/8/events/1/role",
    )
    add_case(
        "runtime-signal-invalidation-token-drift",
        "runtime/protocol-models.json",
        "R06-signal-tracking",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/9/events/4/token", "value": "foreign-token"}],
        "/traces/9/events/4/token",
    )
    add_case(
        "runtime-task-central-cancel-authority-drift",
        "runtime/protocol-models.json",
        "R06-task-multiwaiter-shareable",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/10/events/2/authority", "value": "WaiterOwnerV1"}],
        "/traces/10/events/2/authority",
    )
    add_case(
        "runtime-task-result-type-drift",
        "runtime/protocol-models.json",
        "R06-task-multiwaiter-shareable",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/11/events/4/value/kind", "value": "StringV1"}],
        "/traces/11/events/4/value/kind",
    )
    add_case(
        "runtime-ui-event-type-payload-drift",
        "runtime/protocol-models.json",
        "R06-ui-exact-occurrence",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/14/events/2/event_type", "value": "SaveEventV1"}],
        "/traces/14/events/2/event_type",
    )
    add_case(
        "runtime-ui-gate-terminal-drift",
        "runtime/protocol-models.json",
        "R06-ui-generation-cleanup",
        diagnostic("runtime-protocol-trace-mismatch"),
        [{"op": "replace", "path": "/traces/12/events/6/returns", "value": "IntV1"}],
        "/traces/12/events/6/returns",
    )

    controls = [
        ("call-assembly-control", "interfaces/call-assembly.json", "labels, defaults, trailing lambda, and source-order evaluation are exact", "R06-call-assembly"),
        ("callable-hash-edge-control", "interfaces/callable-interface.json", "callable/module/contract hashes are exact", "R06-callable-hash-dag"),
        ("canonicalization-utf16-control", "interfaces/canonicalization-cases.json", "RFC8785 UTF-16 key ordering differential is exact", "R06-callable-hash-dag"),
        ("component-sync-control", "interfaces/component-interface.json", "manifest/link/component hashes are distinct and sync-only", "FND-component-sync-v1"),
        ("const-decomposed-string-control", "interfaces/const-values.json", "semantic decomposed String bytes/scalars are not NFC-rewritten", "FND-semantic-string-const-bytes"),
        ("control-structural-lowering-control", "interfaces/control-mutation.json", "if/match/loop/while/for and lexical return/break/continue lower uniquely", "FND-control-structural"),
        ("derive-placement-control", "interfaces/nominal-data.json", "derive syntax is postfix only", "FND-postfix-derive"),
        ("inline-handler-equivalence-control", "interfaces/control-mutation.json", "full and inline handlers have identical alpha/origin-erased HIR, Kernel, contract, and diagnostic projections", "R06-inline-handler"),
        ("local-inference-full-boundary-control", "interfaces/local-inference.json", "value restriction, weak monomorphism, numeric defaulting, forbidden binders, and explicit named boundaries are exact", "FND-local-inference-boundary"),
        ("numeric-full-matrix-control", "interfaces/numeric-semantics.json", "fixed scalar, conversion, operation, NaN, zero, and TotalFloat matrix is exact", "FND-numeric-semantics"),
        ("place-replay-control", "interfaces/control-mutation.json", "selector then RHS then unique write executes exactly once", "FND-mutation-place-replay"),
        ("primitive-catalog-control", "interfaces/primitive-catalog.json", "five legacy plus eleven sealed primitive forms are exact", "FND-primitive-wire-forms"),
        ("record-variant-stored-field-control", "interfaces/nominal-data.json", "record-shaped enum stored fields preserve visibility, pure const defaults, construction, and hidden-field rejection", "FND-nominal-data"),
        ("registry-cardinality-control", "interfaces/first-party-registry.json", "all 21 Surface-regenerated first-party bindings are exact", "R06-first-party-registry"),
        ("runtime-bounded-exploration-control", "runtime/protocol-models.json", "all traces replay and bounded state exploration is exhaustive", "R06-runtime-symbolic-replay"),
        ("sealed-checkpoint-control", "interfaces/structural-intrinsic-registry.json", "checkpoint remains sealed and outside the public structural registry", "R06-sealed-checkpoint"),
        ("ui-action-contract-control", "interfaces/first-party-registry.json", "candidate action returns Unit, is non-suspending, and carries ActionSafeRow evidence", "R06-ui-action-flow"),
        ("v3-direct-capability-control", "interfaces/function-contract-v3-suite.json", "direct source slot, FreshCap identity, Cap[i,F], named row, and nondefaultability are exact", "R06-capability-identity"),
        ("v3-differential-suite-control", "interfaces/function-contract-v3-suite.json", "alpha stability, hash cascades, deterministic order, cache collision, public-cycle rejection, and import byte equality are executable", "R06-callable-hash-dag"),
    ]
    positive_controls = [
        {"artifact_path": path, "assertion": assertion, "id": identifier, "rule_id": rule}
        for identifier, path, assertion, rule in controls
    ]

    source_rows = [
        ("accept-byte-pattern", "accept", r'match byte { b"\xff" => 1, _ => 0 }', None, "FND-pattern-matrix"),
        ("accept-direct-capability-binder", "accept", "def![F : Reader[Int]] f(app : F) -> Int ! {app} { app.read() }", None, "R06-capability-identity"),
        ("accept-explicit-arg-list", "accept", "f()", None, "R06-call-assembly"),
        ("accept-ordinary-trait-associated-constraint", "accept", "trait T { type Item : Eq }", None, "R06-associated-ability-profile-boundary"),
        ("accept-signed-min-pattern", "accept", "match x { -128i8 => 0, _ => 1 }", None, "FND-pattern-matrix"),
        ("reject-ability-associated-constraint", "reject", "ability A { type Item : Eq }", "associated-declaration-constraint-not-in-profile", "R06-associated-ability-profile-boundary"),
        ("reject-ability-associated-parameter", "reject", "ability A { type Item[T] }", "associated-parameterization-not-in-profile", "R06-associated-ability-profile-boundary"),
        ("reject-associated-contract-mismatch", "reject", "impl T for S { type Item = Bad }", "associated-contract-mismatch", "FND-trait-coherence"),
        ("reject-cap-binder-default", "reject", "def![F : Reader[Int]] f(source : F, app : F = source) -> Unit ! {} { () }", "capability-binder-default-not-in-v1", "R06-capability-identity"),
        ("reject-cap-marker", "reject", "def![F : Reader[Int]] f(app : cap F) -> Unit ! {} { () }", "surface-cap-marker-removed", "R06-capability-identity"),
        ("reject-defer", "reject", "defer cleanup()", "defer-not-in-cire-v1", "FND-control-structural"),
        ("reject-double-trailing-block-bare", "reject", "f { } { }", "trailing-lambda-target-not-callable", "R06-call-assembly"),
        ("reject-double-trailing-block-call", "reject", "f() { } { }", "trailing-lambda-target-not-callable", "R06-call-assembly"),
        ("reject-effect-header-mismatch", "reject", "ability A { abort fail() -> Int } effect E : A { abort fail() -> Bool }", "effect-header-conformance-mismatch", "FND-explicit-named-rows"),
        ("reject-extension-missing-self", "reject", "extend def f(value : T) -> T ! {} { value }", "extension-self-parameter-required", "FND-method-resolution"),
        ("reject-float-pattern-negative", "reject", "match x { -1.0 => 0, _ => 1 }", "float-pattern-not-in-cire-v1", "FND-pattern-matrix"),
        ("reject-float-pattern-positive", "reject", "match x { 1.0 => 0, _ => 1 }", "float-pattern-not-in-cire-v1", "FND-pattern-matrix"),
        ("reject-handler-clause-without-mode", "reject", "with E { op(x) => x } in body", "handler-clause-mode-required", "R06-inline-handler"),
        ("reject-impl-visibility", "reject", "pub impl T for S { }", "impl-visibility-not-allowed", "FND-trait-coherence"),
        ("reject-independent-ability-impl", "reject", "impl A for S { }", "independent-ability-impl-not-in-profile", "R06-associated-ability-profile-boundary"),
        ("reject-missing-capability-identity", "reject", "def![F : Reader[Int]] f(value : Array[F]) -> Unit ! {} { () }", "capability-identity-required", "R06-capability-identity"),
        ("reject-missing-named-row", "reject", "def f(x : Int) -> Int { x }", "named-function-effect-row-required", "FND-explicit-named-rows"),
        ("reject-multiple-row-tails", "reject", "def![..E, ..F] f() -> Unit ! {..E, ..F} { () }", "row-literal-has-multiple-tails", "FND-explicit-named-rows"),
        ("reject-named-dynamic-call", "reject", "{ let f = choose(); f(value = 1) }", "named-call-requires-static-signature", "R06-call-assembly"),
        ("reject-non-exhaustive-match", "reject", "match b { true => 1 }", "non-exhaustive-match", "FND-pattern-matrix"),
        ("reject-open-private-definition", "reject", "pub(open) def f() -> Unit ! {} { () }", "open-visibility-not-applicable", "FND-trait-coherence"),
        ("reject-operation-open-secondary-row", "reject", "effect E { abort fail() -> Int ! {X, ..R} }", "operation-secondary-row-must-be-closed", "FND-explicit-named-rows"),
        ("reject-recursive-public-callable-scc", "reject", "pub def f() -> Unit ! {} { g() } pub def g() -> Unit ! {} { f() }", "recursive-public-callable-scc-not-in-v1", "R06-callable-hash-dag"),
        ("reject-row-predicate", "reject", "def![..E : Closed[E]] f() -> Unit ! E { () }", "row-predicate-not-in-profile", "FND-local-inference-boundary"),
        ("reject-source-import-collision", "reject", "use @a::f; use @b::f", "callable-source-import-collision", "R06-callable-hash-dag"),
        ("reject-tilde-label", "reject", "f(value~)", "surface-tilde-label-removed", "R06-call-assembly"),
        ("reject-trailing-block-target", "reject", "1 { x => x }", "trailing-lambda-target-not-callable", "R06-call-assembly"),
        ("reject-unreachable-pattern", "reject", "match x { _ => 0, 1 => 1 }", "unreachable-pattern", "FND-pattern-matrix"),
    ]
    source_cases = [
        {
            "expected_diagnostic": expected,
            "id": identifier,
            "kind": kind,
            "parser_status": "metadata-only-not-parsed",
            "rule_id": rule,
            "source": source,
        }
        for identifier, kind, source, expected, rule in source_rows
    ]
    return {
        "artifact": "CireV1MutationCorpusV1",
        "profile": PROFILE,
        "schema_version": 1,
        "cases": sorted(cases, key=lambda item: item["id"]),
        "positive_controls": sorted(positive_controls, key=lambda item: item["id"]),
        "source_cases": sorted(source_cases, key=lambda item: item["id"]),
    }


def v1_validate_mutations(value: Any, documents: Mapping[str, Any], diagnostics: set[str]) -> Dict[str, int]:
    root = v1_closed(value, ["artifact", "profile", "schema_version", "cases", "positive_controls", "source_cases"], "CireV1MutationCorpusV1")
    validate_profile_header(root, "CireV1MutationCorpusV1", 1, "Decode/mutation-corpus")
    cases = require_list(root["cases"], "Decode/mutation-corpus", "mutation cases")
    controls = require_list(root["positive_controls"], "Decode/mutation-corpus", "positive controls")
    source_cases = require_list(root["source_cases"], "Decode/mutation-corpus", "source cases")
    for collection, label in ((cases, "mutation"), (controls, "control"), (source_cases, "source")):
        ids = [entry.get("id") for entry in collection if isinstance(entry, dict)]
        if ids != sorted(ids) or len(ids) != len(set(ids)) or len(ids) != len(collection):
            fail("Decode/mutation-corpus", label + " IDs are not sorted and unique")
    for control in controls:
        item = v1_closed(control, ["artifact_path", "assertion", "id", "rule_id"], "positive control")
        if item["artifact_path"] not in documents:
            fail("Decode/mutation-corpus", "positive control artifact is absent")
        v1_string(item["assertion"], "positive assertion")
        v1_string(item["rule_id"], "positive rule")
    for source_case in source_cases:
        item = v1_closed(source_case, ["expected_diagnostic", "id", "kind", "parser_status", "rule_id", "source"], "source metadata case")
        if item["kind"] not in {"accept", "reject"} or item["parser_status"] != "metadata-only-not-parsed":
            fail("Decode/mutation-corpus", "source case overstates parser execution")
        v1_string(item["source"], "source metadata")
        if item["kind"] == "accept":
            if item["expected_diagnostic"] is not None:
                fail("Decode/mutation-corpus", "accept source case has a diagnostic")
        elif item["expected_diagnostic"] not in diagnostics:
            fail("Decode/mutation-corpus", "reject source case names unknown diagnostic")
    patch_count = 0
    for case in cases:
        item = v1_closed(case, ["artifact_path", "base_hash", "expected_failure", "id", "operations", "preimage", "rule_id"], "mutation case")
        path = item["artifact_path"]
        if path not in documents or path in {"mutations/profile-mutations.json", "authority-rule-coverage.json"}:
            fail("Decode/mutation-corpus", "mutation target is absent or recursive")
        if item["base_hash"] != object_hash(documents[path]):
            fail("Decode/mutation-corpus", item["id"] + " base hash differs")
        expected = item["expected_failure"]
        if not isinstance(expected, dict) or expected.get("kind") not in {"DiagnosticV1", "DecodeFailureV1"}:
            fail("Decode/mutation-corpus", "expected failure is not closed")
        if expected["kind"] == "DiagnosticV1":
            v1_closed(expected, ["kind", "id"], "DiagnosticV1")
            if expected["id"] not in diagnostics:
                fail("Decode/mutation-corpus", "mutation names unknown diagnostic")
        else:
            v1_closed(expected, ["kind", "code"], "DecodeFailureV1")
        v1_validate_preimage(documents[path], item["preimage"])
        operations = require_list(item["operations"], "Decode/mutation-corpus", "patch operations")
        for operation in operations:
            fields = ["op", "path"] + (["value"] if operation.get("op") in {"add", "replace"} else [])
            v1_closed(operation, fields, "RFC6902 operation")
            if operation.get("op") not in {"add", "remove", "replace"}:
                fail("Decode/mutation-corpus", "unsupported RFC6902 operation")
        mutated = apply_patch(documents[path], operations)
        patch_count += len(operations)
        if canonical_bytes(mutated) == canonical_bytes(documents[path]):
            fail("Decode/mutation-corpus", item["id"] + " did not change semantic bytes")
        try:
            v1_validate_artifact(path, mutated, frozen=False)
            mutated_documents = dict(documents)
            mutated_documents[path] = mutated
            v1_validate_hash_graph(mutated_documents)
            v1_validate_artifact(path, mutated, frozen=True)
        except ValidationFailure as error:
            observed = v1_failure_shape(error)
            if observed != expected:
                fail("Decode/mutation-corpus", item["id"] + " expected " + repr(expected) + " but observed " + repr(observed))
        except Exception as error:  # noqa: BLE001 - host exceptions are conformance failure
            fail("Decode/mutation-corpus", item["id"] + " leaked host " + type(error).__name__ + ": " + str(error))
        else:
            fail("Decode/mutation-corpus", item["id"] + " unexpectedly accepted")
    if root != v1_build_mutation_corpus(documents):
        fail(
            "Decode/mutation-corpus",
            "mutation/source corpus differs from deterministic generation",
        )
    return {"positive_controls": len(controls), "reject_mutations": len(cases), "patch_operations": patch_count, "source_cases": len(source_cases)}


AUTHORITY_SOURCE_SPECS = [
    ("docs/spec-status.md", "profile-and-release-authority"),
    ("docs/surface-syntax.md", "surface-and-elaboration-authority"),
    ("docs/temporal-reactivity-formalization.typ", "formal-and-wire-authority"),
]


def v1_authority_sources() -> List[Dict[str, str]]:
    result = []
    for path, role in AUTHORITY_SOURCE_SPECS:
        raw = (REPO_ROOT / path).read_bytes()
        result.append(
            {
                "path": path,
                "raw_sha256": "sha256:" + hashlib.sha256(raw).hexdigest(),
                "role": role,
            }
        )
    return result

SURFACE_RULES = {
    "FND-control-structural", "FND-explicit-named-rows", "FND-local-inference-boundary",
    "FND-method-resolution", "FND-nominal-data", "FND-pattern-matrix", "FND-postfix-derive",
    "FND-trait-coherence", "R06-associated-ability-profile-boundary", "R06-call-assembly",
    "R06-capability-identity", "R06-first-party-registry", "R06-inline-handler",
    "R06-no-generic-event-on", "R06-origin-arena",
}


def v1_rule_authority(rule_id: str) -> Dict[str, str]:
    return {
        "path": "docs/surface-syntax.md" if rule_id in SURFACE_RULES else "docs/temporal-reactivity-formalization.typ",
        "anchor": "rule-" + rule_id.lower(),
    }


DIAGNOSTIC_RULE_GROUPS = {
    "FND-component-sync-v1": [
        "component-native-async-not-in-v1",
        "component-public-type-not-safe",
    ],
    "FND-const-evaluation": [
        "const-definite-trap",
        "const-evaluation-did-not-terminate",
        "const-operation-not-safe",
        "const-safe-requirement-failed",
        "const-termination-not-proven",
    ],
    "FND-control-structural": ["defer-not-in-cire-v1"],
    "FND-explicit-named-rows": [
        "effect-header-conformance-mismatch",
        "named-function-effect-row-required",
        "operation-secondary-row-must-be-closed",
        "row-literal-has-multiple-tails",
    ],
    "FND-local-inference-boundary": ["row-predicate-not-in-profile"],
    "FND-method-resolution": [
        "extension-resolution-ambiguous",
        "extension-self-parameter-required",
        "interpolation-evidence-not-unique",
        "method-candidate-ambiguous",
    ],
    "FND-mutation-place-replay": ["record-update-base-not-final"],
    "FND-nominal-data": [
        "data-field-not-public",
        "newtype-representation-cycle",
        "record-construction-missing-field",
        "type-alias-cycle",
    ],
    "FND-numeric-semantics": ["integer-conversion-out-of-range"],
    "FND-package-instance-identity": [
        "duplicate-package-instance",
        "package-import-not-locked",
        "package-instance-hash-mismatch",
    ],
    "FND-pattern-matrix": [
        "float-pattern-not-in-cire-v1",
        "non-exhaustive-match",
        "unreachable-pattern",
    ],
    "FND-postfix-derive": ["postfix-derive-required"],
    "FND-primitive-wire-forms": ["byte-literal-out-of-range"],
    "FND-semantic-string-const-bytes": ["semantic-string-payload-mismatch"],
    "FND-trait-coherence": [
        "associated-contract-mismatch",
        "associated-type-normalization-cycle",
        "impl-visibility-not-allowed",
        "open-visibility-not-applicable",
        "trait-impl-orphan-violation",
        "trait-impl-overlap",
        "trait-orphan-impl",
    ],
    "FND-maytrap-defect-transition": ["maytrap-not-an-effect"],
    "R06-associated-ability-profile-boundary": [
        "associated-declaration-constraint-not-in-profile",
        "associated-parameterization-not-in-profile",
        "independent-ability-impl-not-in-profile",
    ],
    "R06-call-assembly": [
        "named-call-requires-static-signature",
        "surface-tilde-label-removed",
        "trailing-lambda-target-not-callable",
    ],
    "R06-callable-hash-dag": [
        "callable-interface-contract-mismatch",
        "callable-source-import-collision",
        "public-overload-requires-distinct-export-path",
        "recursive-public-callable-scc-not-in-v1",
    ],
    "R06-capability-identity": [
        "capability-binder-default-not-in-v1",
        "capability-identity-required",
        "surface-cap-marker-removed",
    ],
    "R06-cleanup-receipt-report": ["dispose-report-schema-mismatch"],
    "R06-diagnostic-origin-stability": ["origin-map-noncanonical"],
    "R06-first-party-registry": [
        "first-party-callback-scheme-mismatch",
        "first-party-projection-namespace-mismatch",
        "first-party-registry-contract-nonunique",
        "first-party-registry-noncanonical-order",
        "first-party-type-template-kind-mismatch",
        "intrinsic-registry-root-mismatch",
    ],
    "R06-inline-handler": ["handler-clause-mode-required"],
    "R06-no-generic-event-on": ["first-party-static-scope-escape"],
    "R06-resource-latest-retained": [
        "first-party-retained-callback-contract-mismatch"
    ],
    "R06-runtime-symbolic-replay": ["runtime-protocol-trace-mismatch"],
    "R06-sealed-checkpoint": ["sealed-checkpoint-contract-mismatch"],
    "R06-signal-tracking": ["signal-track-builder-root-mismatch"],
    "R06-ui-action-flow": [
        "ui-action-must-return",
        "ui-action-suspend-policy-required",
    ],
    "R06-ui-exact-occurrence": [
        "first-party-action-occurrence-contract-mismatch"
    ],
    "R06-ui-generation-cleanup": [
        "first-party-callback-entry-owner-mismatch"
    ],
}


ARTIFACT_RULE_GROUPS = {
    "FND-control-structural": ["interfaces/control-mutation.json"],
    "FND-component-sync-v1": [
        "interfaces/component-interface.json",
        "interfaces/component-manifest.json",
        "interfaces/link-abi.json",
    ],
    "FND-const-evaluation": [
        "interfaces/const-declaration.json",
        "interfaces/const-values.json",
    ],
    "FND-local-inference-boundary": ["interfaces/local-inference.json"],
    "FND-method-resolution": ["interfaces/trait-impl-extension.json"],
    "FND-mutation-place-replay": ["interfaces/control-mutation.json"],
    "FND-nominal-data": [
        "interfaces/data-declaration.json",
        "interfaces/nominal-data.json",
    ],
    "FND-numeric-semantics": ["interfaces/numeric-semantics.json"],
    "FND-package-instance-identity": ["interfaces/language-interface.json"],
    "FND-pattern-matrix": ["interfaces/nominal-data.json"],
    "FND-postfix-derive": ["interfaces/nominal-data.json"],
    "FND-primitive-wire-forms": ["interfaces/primitive-catalog.json"],
    "FND-semantic-string-const-bytes": [
        "interfaces/canonicalization-cases.json",
        "interfaces/const-values.json",
    ],
    "FND-trait-coherence": [
        "interfaces/impl-evidence.json",
        "interfaces/trait-declaration.json",
        "interfaces/trait-impl-extension.json",
    ],
    "FND-maytrap-defect-transition": [
        "interfaces/numeric-semantics.json",
        "runtime/protocol-models.json",
    ],
    "R06-callable-hash-dag": [
        "interfaces/callable-contract-fact.json",
        "interfaces/callable-interface.json",
        "interfaces/function-contract-v3.json",
        "interfaces/function-contract-v3-suite.json",
    ],
    "R06-call-assembly": ["interfaces/call-assembly.json"],
    "R06-associated-ability-profile-boundary": [
        "interfaces/ability-declaration.json",
        "interfaces/effect-declaration.json",
    ],
    "R06-capability-identity": [
        "interfaces/first-party-registry.json",
        "interfaces/function-contract-v3-suite.json",
    ],
    "R06-first-party-registry": [
        "interfaces/first-party-registry.json",
        "interfaces/intrinsic-registry.json",
    ],
    "R06-inline-handler": ["interfaces/control-mutation.json"],
    "R06-origin-arena": ["interfaces/elaboration-origin-map.json"],
    "R06-runtime-symbolic-replay": ["runtime/protocol-models.json"],
    "R06-sealed-checkpoint": [
        "interfaces/structural-intrinsic-registry.json"
    ],
    "R06-ui-action-flow": ["interfaces/first-party-registry.json"],
}


TRACE_RULES = {
    "checkpoint-commit-close": "R06-sealed-checkpoint",
    "checkpoint-stale-retained": "R06-sealed-checkpoint",
    "component-resource-borrow-close": "FND-component-sync-v1",
    "packed-building-parent-close": "R06-packed-next",
    "packed-multi-lease-close": "R06-packed-next",
    "receipt-multiwaiter-late": "R06-cleanup-receipt-report",
    "resource-last-good-on-failure": "R06-resource-latest-retained",
    "resource-latest-retained": "R06-resource-latest-retained",
    "sealed-finally-terminal-preserved": "R06-cleanup-receipt-report",
    "signal-dependency-rerun": "R06-signal-tracking",
    "task-independent-cancel": "R06-task-multiwaiter-shareable",
    "ui-close-running-queued": "R06-ui-generation-cleanup",
    "ui-fifo-exact-payload": "R06-ui-exact-occurrence",
    "ui-heterogeneous-exact-payload": "R06-ui-exact-occurrence",
}


def v1_retained_diagnostic_rule(identifier: str) -> str:
    row = RETAINED_DIAGNOSTIC_LEDGER.get(identifier)
    if row is None:
        fail(
            "Decode/diagnostic-registry-mismatch",
            identifier + " has no reviewed rule owner",
        )
    return row["owner"]


def v1_build_coverage(
    documents: Mapping[str, Any], diagnostics: set[str]
) -> Dict[str, Any]:
    diagnostic_groups = copy.deepcopy(DIAGNOSTIC_RULE_GROUPS)
    grouped_diagnostics = {
        diagnostic
        for group in diagnostic_groups.values()
        for diagnostic in group
    }
    for diagnostic in sorted(diagnostics - grouped_diagnostics):
        diagnostic_groups.setdefault(
            v1_retained_diagnostic_rule(diagnostic), []
        ).append(diagnostic)
    grouped_diagnostics = {
        diagnostic
        for group in diagnostic_groups.values()
        for diagnostic in group
    }
    if grouped_diagnostics != diagnostics:
        raise AssertionError(
            "diagnostic owner map differs: missing="
            + repr(sorted(diagnostics - grouped_diagnostics))
            + " extra="
            + repr(sorted(grouped_diagnostics - diagnostics))
        )
    mutation_root = documents["mutations/profile-mutations.json"]
    rules: Dict[str, Dict[str, Any]] = {
        rule_id: {
            "artifacts": [],
            "authority": v1_rule_authority(rule_id),
            "diagnostics": sorted(diagnostic_groups.get(rule_id, [])),
            "id": rule_id,
            "mutation_cases": [],
            "positive_controls": [],
            "runtime_traces": [],
            "source_cases": [],
        }
        for rule_id in RULE_IDS
    }
    for rule_id, paths in ARTIFACT_RULE_GROUPS.items():
        rules[rule_id]["artifacts"].extend(
            path for path in paths if path in ARTIFACT_FILES
        )
    for field, output_field in [
        ("cases", "mutation_cases"),
        ("positive_controls", "positive_controls"),
        ("source_cases", "source_cases"),
    ]:
        for item in mutation_root[field]:
            rules[item["rule_id"]][output_field].append(item["id"])
    for trace_id, rule_id in TRACE_RULES.items():
        rules[rule_id]["runtime_traces"].append(trace_id)
    for rule in rules.values():
        for field in (
            "artifacts",
            "diagnostics",
            "mutation_cases",
            "positive_controls",
            "runtime_traces",
            "source_cases",
        ):
            rule[field] = sorted(set(rule[field]))
    return {
        "artifact": "CireV1AuthorityRuleCoverageV1",
        "authority_sources": v1_authority_sources(),
        "profile": PROFILE,
        "rules": [rules[rule_id] for rule_id in RULE_IDS],
        "schema_version": 1,
    }


def v1_collect_diagnostic_references(value: Any) -> set[str]:
    result: set[str] = set()
    def visit(item: Any, key: str = "") -> None:
        if isinstance(item, dict):
            if item.get("kind") == "DiagnosticV1" and isinstance(item.get("id"), str):
                result.add(item["id"])
            for child_key, child in item.items():
                if child_key in {"diagnostic", "expected_diagnostic"} and isinstance(child, str):
                    result.add(child)
                visit(child, child_key)
        elif isinstance(item, list):
            for child in item:
                visit(child, key)
    visit(value)
    return result


def v1_validate_coverage(value: Any, documents: Mapping[str, Any], diagnostics: set[str]) -> None:
    root = v1_closed(value, ["artifact", "authority_sources", "profile", "rules", "schema_version"], "CireV1AuthorityRuleCoverageV1")
    validate_profile_header(root, "CireV1AuthorityRuleCoverageV1", 1, "Decode/coverage-mismatch")
    authority_sources = require_list(
        root["authority_sources"], "Decode/coverage-mismatch", "authority sources"
    )
    for source in authority_sources:
        v1_closed(
            source,
            ["path", "raw_sha256", "role"],
            "CanonicalAuthoritySourceV1",
        )
    if authority_sources != v1_authority_sources():
        fail("Decode/coverage-mismatch", "coverage treats evidence memo or another file as authority")
    rules = require_list(root["rules"], "Decode/coverage-mismatch", "coverage rules")
    if [rule.get("id") for rule in rules] != RULE_IDS:
        fail("Decode/coverage-mismatch", "coverage is not the exact 36-rule vector")
    mutation_root = documents["mutations/profile-mutations.json"]
    mutation_ids = {case["id"] for case in mutation_root["cases"]}
    control_ids = {case["id"] for case in mutation_root["positive_controls"]}
    source_ids = {case["id"] for case in mutation_root["source_cases"]}
    trace_ids = {trace["id"] for trace in documents["runtime/protocol-models.json"]["traces"]}
    used_mutations: set[str] = set()
    used_controls: set[str] = set()
    used_sources: set[str] = set()
    used_traces: set[str] = set()
    used_diagnostics: set[str] = set()
    used_artifacts: set[str] = set()
    for rule in rules:
        item = v1_closed(rule, ["artifacts", "authority", "diagnostics", "id", "mutation_cases", "positive_controls", "runtime_traces", "source_cases"], "coverage rule")
        if item["authority"] != v1_rule_authority(item["id"]):
            fail("Decode/coverage-mismatch", item["id"] + " authority owner/anchor differs")
        authority_path = item["authority"]["path"]
        anchor = item["authority"]["anchor"]
        authority_text = (REPO_ROOT / authority_path).read_text(encoding="utf-8")
        exact_anchor = (
            '<a id="' + anchor + '"></a>'
            if authority_path.endswith("surface-syntax.md")
            else "<" + anchor + ">"
        )
        if authority_text.count(exact_anchor) != 1:
            fail(
                "Decode/coverage-mismatch",
                item["id"] + " owner anchor is absent or duplicated",
            )
        for field in ("artifacts", "diagnostics", "mutation_cases", "positive_controls", "runtime_traces", "source_cases"):
            values = require_list(item[field], "Decode/coverage-mismatch", item["id"] + "." + field)
            if values != sorted(values) or len(values) != len(set(values)):
                fail("Decode/coverage-mismatch", item["id"] + "." + field + " is not sorted unique")
        for path in item["artifacts"]:
            if path not in ARTIFACT_FILES:
                fail("Decode/coverage-mismatch", "coverage names absent artifact " + str(path))
            used_artifacts.add(path)
        for diagnostic in item["diagnostics"]:
            if diagnostic not in diagnostics:
                fail("Decode/coverage-mismatch", "coverage names unknown diagnostic")
            used_diagnostics.add(diagnostic)
        for case_id in item["mutation_cases"]:
            if case_id not in mutation_ids:
                fail("Decode/coverage-mismatch", "coverage names unknown mutation")
            used_mutations.add(case_id)
        for control_id in item["positive_controls"]:
            if control_id not in control_ids:
                fail("Decode/coverage-mismatch", "coverage names unknown control")
            used_controls.add(control_id)
        for source_id in item["source_cases"]:
            if source_id not in source_ids:
                fail("Decode/coverage-mismatch", "coverage names unknown source case")
            used_sources.add(source_id)
        for trace_id in item["runtime_traces"]:
            if trace_id not in trace_ids:
                fail("Decode/coverage-mismatch", "coverage names unknown trace")
            used_traces.add(trace_id)
    if used_mutations != mutation_ids or used_controls != control_ids or used_sources != source_ids or used_traces != trace_ids:
        fail("Decode/coverage-mismatch", "coverage is not bidirectionally complete over executable cases")
    if used_diagnostics != diagnostics:
        fail("Decode/coverage-mismatch", "coverage diagnostic union is not exact")
    executable_artifacts = set(ARTIFACT_FILES) - {"authority-rule-coverage.json", "diagnostics-v3.json", "mutations/profile-mutations.json"}
    if used_artifacts != executable_artifacts:
        fail("Decode/coverage-mismatch", "coverage artifact union is not exact")
    referenced: set[str] = set()
    for path, document in documents.items():
        if path != "diagnostics-v3.json":
            referenced.update(v1_collect_diagnostic_references(document))
    if referenced - diagnostics:
        fail("Decode/coverage-mismatch", "artifact names unregistered diagnostics: " + repr(sorted(referenced - diagnostics)))
    for case in mutation_root["cases"]:
        if case["rule_id"] not in RULE_IDS:
            fail("Decode/coverage-mismatch", "mutation has unknown rule owner")
    for collection in (mutation_root["positive_controls"], mutation_root["source_cases"]):
        if any(case["rule_id"] not in RULE_IDS for case in collection):
            fail("Decode/coverage-mismatch", "control/source case has unknown rule owner")
    if root != v1_build_coverage(documents, diagnostics):
        fail("Decode/coverage-mismatch", "coverage differs from deterministic generation")


def v1_assert_hash_edge(ref: Mapping[str, Any], documents: Mapping[str, Any], diagnostic: str) -> None:
    artifact = ref["artifact"]
    candidates = [document for document in documents.values() if document.get("artifact") == artifact]
    if len(candidates) != 1 or ref["artifact_hash"] != object_hash(candidates[0]):
        fail(diagnostic, artifact + " hash edge is stale or ambiguous")


def v1_validate_hash_graph(documents: Mapping[str, Any]) -> None:
    callable_doc = documents["interfaces/callable-interface.json"]
    v1_assert_hash_edge(callable_doc["core_contract"], documents, "callable-interface-contract-mismatch")
    callable_fact = documents["interfaces/callable-contract-fact.json"]
    v1_assert_hash_edge(
        callable_fact["callable"]["callable_interface"],
        documents,
        "callable-interface-contract-mismatch",
    )
    registry = documents["interfaces/intrinsic-registry.json"]
    v1_assert_hash_edge(registry["first_party"], documents, "intrinsic-registry-root-mismatch")
    v1_assert_hash_edge(registry["structural"], documents, "intrinsic-registry-root-mismatch")
    language = documents["interfaces/language-interface.json"]
    for edge in language["declarations"]:
        v1_assert_hash_edge(edge["declaration"], documents, "callable-interface-contract-mismatch")
        child = next(
            document
            for document in documents.values()
            if document.get("artifact") == edge["declaration"]["artifact"]
        )
        if child.get("identity") != edge["identity"]:
            fail(
                "callable-interface-contract-mismatch",
                "package declaration edge identity does not equal its child root",
            )
    for edge in language["evidence"]:
        v1_assert_hash_edge(edge["evidence"], documents, "callable-interface-contract-mismatch")
        child = next(
            document
            for document in documents.values()
            if document.get("artifact") == edge["evidence"]["artifact"]
        )
        if child.get("identity") != edge["identity"]:
            fail(
                "callable-interface-contract-mismatch",
                "package evidence edge identity does not equal its child root",
            )
    v1_assert_hash_edge(language["callables"][0]["callable_interface"], documents, "callable-interface-contract-mismatch")
    if callable_fact["callable"] != language["callables"][0]:
        fail(
            "callable-interface-contract-mismatch",
            "protocol evidence does not authenticate the exact package callable edge",
        )
    canonical_callables = sorted(language["callables"], key=canonical_bytes)
    if callable_fact["identity"]["ordinal"] != canonical_callables.index(
        callable_fact["callable"]
    ):
        fail(
            "callable-interface-contract-mismatch",
            "ProtocolEvidenceV1 ordinal is not the canonical callable index",
        )
    impl_documents = [documents["interfaces/impl-evidence.json"]]
    impl_preidentities = []
    for document in impl_documents:
        preidentity = copy.deepcopy(document)
        del preidentity["identity"]
        impl_preidentities.append((canonical_bytes(preidentity), document))
    if len({key for key, _document in impl_preidentities}) != len(
        impl_preidentities
    ):
        fail(
            "trait-impl-overlap",
            "duplicate impl preidentity exists before ordinal allocation",
        )
    for ordinal, (_key, document) in enumerate(sorted(impl_preidentities)):
        if document["identity"]["ordinal"] != ordinal:
            fail(
                "callable-interface-contract-mismatch",
                "ImplEvidenceV1 ordinal is not the canonical preidentity index",
            )
    v1_assert_hash_edge(language["components"][0]["manifest"], documents, "component-public-type-not-safe")
    v1_assert_hash_edge(language["primitive_catalog"], documents, "package-instance-hash-mismatch")
    v1_assert_hash_edge(language["intrinsic_registry"], documents, "intrinsic-registry-root-mismatch")
    manifest = documents["interfaces/component-manifest.json"]
    v1_assert_hash_edge(manifest["exports"][0]["item"]["callable"]["callable_interface"], documents, "callable-interface-contract-mismatch")
    link = documents["interfaces/link-abi.json"]
    v1_assert_hash_edge(link["language_interface"], documents, "callable-interface-contract-mismatch")
    if link["callable_layouts"][0]["callable_interface_hash"] != object_hash(callable_doc):
        fail("callable-interface-contract-mismatch", "link callable hash is stale")
    component = documents["interfaces/component-interface.json"]
    v1_assert_hash_edge(component["manifest"], documents, "component-public-type-not-safe")
    v1_assert_hash_edge(component["link_abi"], documents, "component-public-type-not-safe")
    v1_assert_hash_edge(component["exports"][0]["callable"]["callable_interface"], documents, "callable-interface-contract-mismatch")
    def scan_zero(item: Any) -> None:
        if item == ZERO_HASH:
            fail("Decode/hash-mismatch", "zero hash placeholder remains")
        if isinstance(item, dict):
            for child in item.values():
                scan_zero(child)
        elif isinstance(item, list):
            for child in item:
                scan_zero(child)
    for path, document in documents.items():
        if path != "mutations/profile-mutations.json":
            scan_zero(document)


def v1_generated_manifest(documents: Mapping[str, Any]) -> Dict[str, Any]:
    coverage = documents["authority-rule-coverage.json"]
    diagnostics = documents["diagnostics-v3.json"]
    mutations = documents["mutations/profile-mutations.json"]
    runtime = documents["runtime/protocol-models.json"]
    first_party = documents["interfaces/first-party-registry.json"]
    structural = documents["interfaces/structural-intrinsic-registry.json"]
    origins = documents["interfaces/elaboration-origin-map.json"]
    exploration = bounded_protocol_exploration()
    schema_inventory = schema_pointer_inventory(documents)
    artifacts = [
        {"artifact": ARTIFACT_FILES[path][0], "path": path, "schema_version": ARTIFACT_FILES[path][1], "sha256": object_hash(documents[path])}
        for path in sorted(ARTIFACT_FILES)
    ]
    return {
        "artifact": "CireV1ProfileManifestV1",
        "profile": PROFILE,
        "schema_version": 1,
        "hash_algorithm": HASH_ALGORITHM,
        "package_instance_id": copy.deepcopy(PACKAGE_ID),
        "authority_sources": copy.deepcopy(coverage["authority_sources"]),
        "artifacts": artifacts,
        "counts": {
            "artifact_count": len(artifacts),
            "diagnostic_count": len(diagnostics["diagnostics"]),
            "explored_state_count": exploration["explored_state_count"],
            "explored_transition_count": exploration["explored_transition_count"],
            "first_party_binding_count": len(first_party["bindings"]),
            "origin_kind_count": len(origins["nodes"]) - 1,
            "patch_operation_count": sum(len(case["operations"]) for case in mutations["cases"]),
            "positive_control_count": len(mutations["positive_controls"]),
            "reject_mutation_count": len(mutations["cases"]),
            "rule_count": len(coverage["rules"]),
            "runtime_trace_count": len(runtime["traces"]),
            "semantic_model_hash_count": len(EXPECTED_MODEL_HASHES),
            "schema_pointer_count": schema_inventory["pointer_count"],
            "schema_pointer_mutation_count": schema_inventory["mutation_count"],
            "schema_closed_object_count": schema_inventory["closed_object_count"],
            "schema_required_field_count": schema_inventory["required_field_count"],
            "schema_array_policy_count": schema_inventory["array_policy_count"],
            "schema_tag_occurrence_count": schema_inventory["tag_occurrence_count"],
            "schema_tag_variant_count": schema_inventory["tag_variant_count"],
            "schema_enum_occurrence_count": schema_inventory["enum_occurrence_count"],
            "schema_enum_variant_count": schema_inventory["enum_variant_count"],
            "schema_u32_pointer_count": schema_inventory["u32_pointer_count"],
            "schema_hash_syntax_pointer_count": schema_inventory[
                "hash_syntax_pointer_count"
            ],
            "canonical_array_policy_count": schema_inventory[
                "canonical_array_policy_count"
            ],
            "hash_graph_edge_count": schema_inventory["hash_graph_edge_count"],
            "source_metadata_case_count": len(mutations["source_cases"]),
            "structural_intrinsic_count": len(structural["bindings"]),
        },
        "historical_lane": {
            "diagnostic_registry_sha256": TR0_DIAGNOSTIC_REGISTRY_HASH,
            "profile": "Cire-TR₀/2026-08-01",
            "status": "frozen-separate",
            "validator": "../validate-oracles.py",
        },
        "lane_scope": "specification-model-only-no-parser-compiler-backend",
        "runtime_exploration": exploration["model_counts"],
        "schema_pointer_set": {
            "count": schema_inventory["pointer_count"],
            "hash": schema_inventory["pointer_set_hash"],
            "accepted_kind_vocabulary": {
                "count": len(EXPECTED_CLOSED_KIND_VOCABULARY),
                "hash": object_hash(list(EXPECTED_CLOSED_KIND_VOCABULARY)),
            },
            "closed_enum_domains": {
                "count": len(EXPECTED_CLOSED_ENUM_DOMAINS),
                "literal_count": schema_inventory["enum_variant_count"],
                "hash": object_hash(
                    [
                        [domain, list(values)]
                        for domain, values in EXPECTED_CLOSED_ENUM_DOMAINS
                    ]
                ),
            },
            "array_policies": {
                "canonical_vector_count": len(CANONICAL_ARRAY_POINTERS),
                "total_count": schema_inventory["array_policy_count"],
                "hash": object_hash(
                    [
                        "canonical-vector:" + pointer
                        for pointer in CANONICAL_ARRAY_POINTERS
                    ]
                ),
            },
            "hash_graph_policies": {
                "count": len(HASH_GRAPH_POLICIES),
                "hash": object_hash(
                    [list(policy) for policy in HASH_GRAPH_POLICIES]
                ),
            },
        },
    }


def validate_all(documents: Mapping[str, Any]) -> Dict[str, int]:
    validate_package_id()
    v1_validate_frozen_model_set(documents)
    diagnostic_ids = v1_validate_diagnostics(documents["diagnostics-v3.json"])
    meta_paths = {
        "authority-rule-coverage.json",
        "diagnostics-v3.json",
        "mutations/profile-mutations.json",
    }
    for path in sorted(set(ARTIFACT_FILES) - meta_paths):
        v1_validate_artifact(path, documents[path], frozen=True)
    mutation_counts = v1_validate_mutations(
        documents["mutations/profile-mutations.json"], documents, diagnostic_ids
    )
    v1_validate_coverage(
        documents["authority-rule-coverage.json"], documents, diagnostic_ids
    )
    v1_validate_hash_graph(documents)
    mutation_counts.update(bounded_protocol_exploration())
    mutation_counts.update(schema_pointer_audit(documents))
    return mutation_counts


def validate_manifest(documents: Mapping[str, Any]) -> Dict[str, Any]:
    path = V1 / "manifest.json"
    if not path.is_file() or path.is_symlink():
        fail("manifest-noncanonical", "manifest.json is absent or a symlink")
    manifest = load_json(path)
    expected = v1_generated_manifest(documents)
    if manifest != expected:
        fail("manifest-noncanonical", "manifest differs from deterministic generation")
    for entry in manifest["artifacts"]:
        artifact_path = V1 / entry["path"]
        if artifact_path.is_symlink() or not artifact_path.is_file():
            fail("manifest-noncanonical", "manifest path is absent or a symlink")
        resolved = artifact_path.resolve()
        if V1.resolve() not in resolved.parents:
            fail("manifest-noncanonical", "manifest path escapes v1")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--print-manifest",
        action="store_true",
        help="print deterministic manifest JSON after validating all non-manifest artifacts",
    )
    parser.add_argument(
        "--print-first-party-registry",
        action="store_true",
        help="print the deterministic exact Surface registry expansion",
    )
    parser.add_argument(
        "--print-schema-descriptors",
        action="store_true",
        help="print the deterministic closed-schema descriptor inventory",
    )
    args = parser.parse_args()
    try:
        if args.print_first_party_registry:
            print(json.dumps(FIRST_PARTY_GOLDEN, ensure_ascii=False, indent=2))
            return 0
        documents = load_documents()
        if args.print_schema_descriptors:
            inventory = closed_schema_inventory(documents)
            print(
                json.dumps(
                    schema_pointer_descriptors(inventory),
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0
        mutation_counts = validate_all(documents)
        expected_manifest = v1_generated_manifest(documents)
        if args.print_manifest:
            print(json.dumps(expected_manifest, ensure_ascii=False, indent=2))
            return 0
        manifest = validate_manifest(documents)
    except (OSError, ValueError, ValidationFailure) as error:
        if isinstance(error, ValidationFailure):
            print("FAIL " + error.diagnostic + ": " + error.detail, file=sys.stderr)
        else:
            print("FAIL malformed-artifact: " + str(error), file=sys.stderr)
        return 1
    counts = manifest["counts"]
    print("PASS Cire-v1.0 specification-model conformance")
    print(
        "  artifacts: {artifact_count}; authority rules: {rule_count}; "
        "diagnostics: {diagnostic_count}".format(**counts)
    )
    print(
        "  positive controls: {positive_controls}; reject mutations: "
        "{reject_mutations}".format(**mutation_counts)
    )
    print(
        "  patch operations: {patch_operations}; source metadata cases: "
        "{source_cases}".format(**mutation_counts)
    )
    print(
        "  runtime traces: {runtime_trace_count}; origins: {origin_kind_count}; "
        "registry: {first_party_binding_count}+{structural_intrinsic_count}".format(
            **counts
        )
    )
    print(
        "  bounded protocol exploration: {explored_state_count} states / "
        "{explored_transition_count} transitions".format(**counts)
    )
    print(
        "  closed-schema audit: {schema_pointer_count} pinned descriptors / "
        "{schema_pointer_mutation_count} mutations".format(**counts)
    )
    print(
        "  schema inventory: {schema_closed_object_count} objects / "
        "{schema_required_field_count} required fields / "
        "{schema_array_policy_count} array policies / "
        "{schema_tag_variant_count} tags / {schema_enum_variant_count} enum literals / "
        "{hash_graph_edge_count} hash edges".format(**counts)
    )
    print(
        "  per-model exploration: "
        + ", ".join(
            "{model}={state_count}/{transition_count}".format(**entry)
            for entry in manifest["runtime_exploration"]
        )
    )
    print("  scope: specification models only; no source parser/compiler/backend claim")
    print("  historical TR0 lane: frozen and separately validated by validate-oracles.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
