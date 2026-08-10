#import "../shared.typ": *

==== Structural registry 与唯一 root <surface-8-4-2>

```text
StructuralIntrinsicRegistryV1 = {
  artifact: "StructuralIntrinsicRegistryV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  bindings: [StructuralIntrinsicV1; 2]
}

StructuralIntrinsicV1 =
    {
      kind: "StructuralIntrinsicV1",
      id: "Cire-v1.0/structural/build-string",
      source_form: "StringInterpolationV1",
      origin_kind: "SealedIntrinsicV1",
      kernel: "BuildStringV1",
      contract: "BuildStringContractV1"
    }
  | {
      kind: "StructuralIntrinsicV1",
      id: "Cire-v1.0/structural/control-finally",
      source_form: "@control::finally",
      origin_kind: "SealedIntrinsicV1",
      kernel: "ControlFinallyV1",
      contract: "FinalizerContractV1"
    }

IntrinsicRegistryRootV1 = {
  artifact: "IntrinsicRegistryRootV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  first_party: {
    artifact: "FirstPartyRegistryV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  },
  structural: {
    artifact: "StructuralIntrinsicRegistryV1",
    hash_algorithm: "sha256-jcs-nfc-v1",
    artifact_hash: Sha256V1
  }
}
```

Structural bindings按 ID NFC UTF-8 bytes严格递增且 exact两项。所有 object exact
fields，child hash是各 child递归 NFC后 RFC 8785/JCS UTF-8 bytes的 SHA-256；root
不内嵌或重解释 child。`BuildStringContractV1`把 literal byte segment与 hole按
source order各求值一次；hole解析 exact locked-core `Show`，保留自己的 effect/flow，
format step ProtocolPure。Functions、handlers、capability、Owner、resumption、
Task/Resource与 Bytes没有 implicit Show。

`FinalizerContractV1`建立 sealed suffix-ledger entry；cleanup NoSuspend、所有 path
Returns Unit、无 outward Abort/Transfer，并满足 phase/Owner/capture/usage；multi-shot
只在 cleanup Replayable时允许。Body的 Returns/Aborts/Transfers先执行或移交该
responsibility再保留原 tag。Derive虽用 `SealedIntrinsicV1` origin，但由 data
declaration与 `ImplEvidenceV1`闭合，不是第三个 structural binding。


`Task[rho,R]` 要求 `Shareable(R)` 与 `AsyncBoundarySafeV1(rho,R)`，
handle可复制且是 multi-waiter broadcast；只有
`Async::await`，不存在 `Task::await`。取消一个 waiter不取消 producer/其它 waiter。
Central cancel只适用于 `Task[rho,TaskOutcome[A,E]]`，且需要 exact task-owner authority；
`CancelReason` v1只有 sealed `ExplicitCancel`。`CloseReceipt[R]` 是 cleanup supervisor
完成的不可取消 latch，不是 Task；重复 close返回同一 receipt/report identity。

Resource唯一是 `SwitchLatest + LatestEpoch + keep-last-good`：

```cire
let resource = Resource::switch_latest(
  under = resource_owner,
  keys = selected_key,
) { child_owner, key =>
  load_key(key, under = child_owner)
}

let view = Resource::view(resource)
let receipt = Resource::dispose(resource)
```

Loader NoSuspend、无 Abort/Transfer并返回
`Task[rho_child,TaskOutcome[A,E]]`。严格更新 key revision stale当前 candidate，
只 retain最新 revision；last-good保持到 replacement success。Failure/cancel发布
`ResourceView.FailedLoad`并携带 previous，close/retire exactly-once。没有 merge/
concat/exhaust或 `Resource::next/snapshot`。
`K/A/E` 均必须 Shareable 并具有 exact Owner-storage boundary evidence；
loader产生的 Task 必须属于该 admission 的 direct child Owner。

唯一 Resource→Signal→UI root是：

```cire
@ui::run_signal(
  under = app_owner,
  backpressure = CoalesceLatest,
) { frame, ui =>
  let resource = Resource::switch_latest(
    under = ui.owner,
    keys = selected_key,
  ) { child_owner, key =>
    fetch(key, under = child_owner)
  }

  let model = Signal::track(frame) { track =>
    Model(
      remote = track.read(Resource::view(resource)),
    )
  }

  ui.render(model) { candidate, current =>
    let on_save = candidate.action { snapshot, event =>
      let draft = snapshot.read(draft_source)
      save_app.save(draft, event = event)
    }
    render_view(current, on_save = on_save)
  }
}
```

Surface equation固定为 `Signal[i,A] = Step(A, Next[i,Signal[i,A]])`，要求
`Shareable(A)`；sealed lowering才向 `Next` 的 evidence-indexed Kernel form插入
不可 source-spell 的第三个 `SignalTailContract[i,A]` argument。Hidden tail contract
固定 advance、capture nonescape、Owner cleanup与 full-flow release，不可由用户提供。
Signal是 pure clock-indexed value；`track.read`
唯一建立 invalidating
dependency，`snapshot.read`只读 fixed revision。`ui.render` callback必须直接返回
同 generation `ViewPlan[gamma]`; `candidate.action` callback固定
Action/NoSuspend/same-world/
Returns Unit。它可以调用已有 exact NoSuspend attributed operation，但不能 await、Abort、
Transfer、raw Resume或 generic spawn。

`map_signal` 的 transform必须 empty row、NoSuspend、Returns-only、
`TemporalStable(i,env)`、`CrossWorldSafe(i,capture)` 且 `Shareable(B)`；同名
ordinary function不能伪造该 sealed tail evidence。

每个 event type `E` 必须有 `ShareableV1(E)` 与 exact
`EventOccurrenceStorageV1(rho,gamma,E)` evidence。每个 occurrence在 generation
gate仍 Open时，立即将 exact typed payload存入
OwnerStorage并取得一个从 Queued贯穿 Running 的 linear lease。Mount-wide dispatcher按
monotone ordinal FIFO；Released传递并 release exact payload，Finalized在不调用用户代码时
release同一 payload。Close/stale先关 gate、finalize queued、等待唯一 running，再允许
listener/plan cleanup。没有 hidden host queue、late reread、shadow count、event coalescing
或 per-event CleanupLedger item。

`Event` nominal type保留给显式库协议，但 generic `on`/`on_async` 不属于 v1 reachable API；
UI event entry只由上述 typed action plan建立。Generic public `Plan`/`CommitTicket`/
`CommitGate`也不在 surface；它们若存在只能是 sealed runtime implementation detail。
