#import "../shared.typ": *

== RuntimeNat、receipt 与 cleanup ledger <cleanup-ledger-v1>

所有 runtime-only generation、cleanup/lease/waiter/event ordinal、Signal revision与 Live epoch使用
数学非负整数 `RuntimeNat` 和 infallible successor。它们不是 u32、不会 wrap/exhaust/reuse，也不与
Core slot、origin ID或 source integer alias。

```text
CanonicalNatV1 = JSON String matching 0 | [1-9][0-9]*

DisposeReportV1 = {
  artifact: "DisposeReportV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  reason: "ExplicitDisposeV1" | "ParentOwnerCloseV1" | "StorageOwnerCloseV1",
  items: [DisposeItemV1]
}

DisposeItemV1 = {
  kind: "DisposeItemV1",
  ordinal: CanonicalNatV1,
  generation: CanonicalNatV1,
  role: "PackedRunnerV1" | "ResourceCandidateV1" | "ResourceCommittedV1"
      | "ResourceRetiredV1" | "ResourceInputV1" | "UiCandidateV1"
      | "UiCommittedPlanV1" | "UiListenerV1" | "SignalTailV1",
  outcome: { kind: "ClosedV1" }
         | { kind: "CleanupFailedV1", error: CleanupErrorV1 }
}

CleanupErrorV1 = {
  kind: "CleanupErrorV1",
  code: "UserFinalizerAbortedV1" | "ChildOwnerCloseFailedV1"
      | "HostAdapterCloseFailedV1" | "ProtocolInvariantFailedV1",
  origin: SourceOriginV1 | null
}

CleanupLedger = {
  next_cleanup_ordinal: RuntimeNat,
  live: Map[RuntimeNat, ReservedCleanup { generation, role, token }],
  pending: [PendingCleanup { ordinal, generation, role, token }],
  dispose_items: Map[RuntimeNat, DisposeItem]
}
```

接受 responsibility的同一 atomic registration取 ordinal、推进 counter、加入 live。Candidate到
committed/retired只转移同一 reservation并更新 role，不重编号。Retire做 live→pending，不分配；
attempt-all cleanup无论成功失败都写 immutable item。第一次 close CAS固定 reason；重复 request返回
同一 receipt/report identity且不改 reason。全部已赢 lease drain且 live/pending为空时，items按 numeric
ordinal严格为 `0..next_cleanup_ordinal-1`生成 report并 resolve。Report禁止 host message、backtrace、
absolute path、exception class/object address；这些只能 noncanonical note。

```text
ReceiptCell[R] =
    Pending { next_registration_ordinal: RuntimeNat, waiter_map }
  | Resolved { next_registration_ordinal: RuntimeNat, value: R }

ReceiptWaiter =
    Armed(registration_ordinal, observer_owner_generation, completion_port)
  | DeliveryWon(observer_entry_lease)
  | Delivered(observer_entry_lease)
  | Finalized
```

Target cleanup supervisor唯一 `Pending -> Resolved`，late observer读 immutable R。Register必须在同一
linearization验证 observer generation gate Open并登记 Owner claim；resolve/register无 lost wakeup。
Delivery用一个 gate+claim CAS取得 entry lease并 Armed→DeliveryWon；observer close先赢则 Finalized，
delivery先赢则 close等待 lease drain。Cleanup supervisor禁止 await自己的 receipt。

== PackedNextProtocolV1 <packed-next-protocol-v1>

`PackedNextPackageV2` 与 `PackedNextControlProtocolV2` 的 bytes/profile继续可按
`Cire-TR₀/2026-08-01` legacy decoder读取，但 successor producer、registry与 conformance不能输出或
引用它们。`PackedNextProtocolV1` 是 profile-disjoint new artifact；V2 hash绝不能冒充 V1。

```text
PackedNextProtocolV1 = {
  artifact: "PackedNextProtocolV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  handle: "SharedOpaquePackedNextV1",
  private_package: "FreshClockOwnerNextPackageV1",
  states: ["BuildingV1", "OpenV1", "ClosingV1", "ClosedV1"],
  lease: "OneShotPackedLeaseV1",
  cleanup: "CleanupLedgerV1"
}

PackedCell[A] =
    Building {
      builder_entry_lease,
      runner_ordinal: RuntimeNat,
      next_lease_ordinal: RuntimeNat,
      close_reason: Option[CloseReason],
      close_cell,
      ledger
    }
  | Open {
      package: PrivatePackedPackage[A],
      active_lease_count: RuntimeNat,
      runner_ordinal: RuntimeNat,
      next_lease_ordinal: RuntimeNat,
      close_cell,
      ledger
    }
  | Closing {
      package: PrivatePackedPackage[A],
      active_lease_count: RuntimeNat,
      runner_ordinal: RuntimeNat,
      next_lease_ordinal: RuntimeNat,
      close_reason: CloseReason,
      close_cell,
      ledger
    }
  | Closed {
      report: DisposeReport,
      next_lease_ordinal: RuntimeNat,
      close_cell
    }

PackedLeaseClaim = Armed(lease_ordinal: RuntimeNat) | Released
```

`pack_next` 的第一 linearization是 parent-root admission：建立 cell/ledger，ordinal 0、generation 0
登记唯一 PackedRunner，construction lease ordinal 0，安装 Building(next=1)，然后才调用 builder。
Parent close在 admission前赢则 builder不运行；admission后赢必须看到 provisional root并等待 lease。
Builder Returns exact sealed package：无 close则 Building→Open(count=0,next=1)；已有 close则安装 package
到 Closing、release construction lease并由 cleanup继续。Builder Abort/Transfer固定 first
StorageOwnerClose（除非 earlier reason已赢），runner live→pending恰一次，release lease，完整生成 report后
再重发原 terminal tag。

Acquire仅 `Open(P,n,k) -> Open(P,n+1,k+1) + Armed(k)`；Closing/Closed返回 None。Release先
`Armed(k)->Released`，再只把 matching Open/Closing count `n+1 -> n`且保存 next ordinal；duplicate
release无作用。Request close用同一 CAS固定 first reason、把 runner live→pending、Open→Closing或只在
Building记 reason；重复返回同一 close cell。Closing最后 count 1→0的 release唯一 close runner/child、
写 report并 resolve。已赢 lease的 body不被 dispose中断；Returns/Aborts/Transfers每条 path先做
rho-child/identity/summary outward gate，再恰好 release一次并保留 flow tag。Parent registry只登记
Packed root，不能绕过 root先关 child。

对应唯一 surface/registry API是 `@temporal::pack_next`、
`@temporal::try_with_packed_next`、`@temporal::dispose`；用户不能构造/命名 private existential、
rank-2 identity、lease或 package component。
