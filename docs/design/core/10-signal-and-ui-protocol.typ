#import "../shared.typ": *

== Signal、typed UI occurrence 与 dispatcher protocol <signal-ui-protocol-v1>

Surface lowering 后 `Signal[i,A]` 的唯一 evidence-indexed Kernel type equation是：

```text
Signal[i,A] = Step(A, Next[i, Signal[i,A], SignalTailContract[i,A]])
```

构造与每次 tail publication 都要求 `ShareableV1(A)`。`SignalTailContract[i,A]` 是
locked first-party hidden contract：它唯一固定 matching-clock `advance`、tail capture nonescape、
Owner/generation cleanup registration、以及 Returns/Aborts/Transfers 每个 full-flow terminal 的 exact release。
它没有 source constructor、public interface binder或 user evidence hook；用普通 `Next`、自定义 contract
或只覆盖 Returns path 都不能构造 `Signal`。

`Signal[i,A]` 是 clock-indexed pure incremental value。`map_signal`要求 Shareable A/B；transform恰是
empty row/demand、NoSuspend、Returns-only、duplicable environment、`TemporalStable(i,env)` 与
`CrossWorldSafe(i,capture)`。`Signal::track`只在 exact frame/context下建立
installed epoch与 complete dependency trace。UI唯一 runner是
`@ui::run_signal(under=owner,backpressure=CoalesceLatest){frame,ui=>...}`；没有 generic
Event subscription或 public Plan/Commit。

`ui.render(model){candidate,current=>...}` 的 transform 必须 NoSuspend、empty row、Returns-only并
直接产生 private `ViewPlan[gamma]`。`candidate.action{snapshot,event=>...}` 产生同 generation
`ActionPlan[gamma,E]`，其 latent callback恰为 Action phase、same world、NoSuspend且所有 path
`Returns(Unit)`；它可有已在 signature声明且 NoSuspend 的 attributed effect request，但不得
Abort、Transfer、await 或 generic spawn/enqueue。Suspending site稳定
`ui-action-suspend-policy-required`，非 Returns(Unit) terminal稳定 `ui-action-must-return`。Action
capture逐 slot 要求 UI child `OwnerStorage(rho)` provenance、BoundarySafe与 Outlives。

```text
TrackContext[rho,i,eta]
UiBuilder[rho,i]
UiCandidate[rho,gamma,nu]
SnapshotContext[rho,nu]
ViewPlan[gamma]                 // private sealed
ActionPlan[gamma,E]             // private sealed
UiBackpressureV1 = CoalesceLatest

FixedEpochRevision = { epoch: RuntimeNat, revision: RuntimeNat }

EntryGateStatus = Open | Closed
GenerationEntryCell = {
  generation: RuntimeNat,
  status: EntryGateStatus,
  live_occurrences: RuntimeNat
}
EntryGateRef = opaque identity of one GenerationEntryCell

UiOccurrenceLease = opaque linear QueuedHold { cell: EntryGateRef }
                  | opaque linear RunningEntry { cell: EntryGateRef }
HostMountHandle = opaque linear host mount responsibility
HostMountHandleRef = opaque non-owning identity reference

UiListenerBindingId = opaque fresh identity, never reused
UiEventTypeWitness[E] = sealed exact type-equality witness
UiActionPlanToken[E] = sealed immutable non-cleanup retained form of exact ActionPlanContractV1
UiEventStorageWitness[E] = sealed exact (storage_owner,generation,E) witness

UiActionEntry[E] = {
  generation: RuntimeNat,
  revision: FixedEpochRevision,
  event_type: UiEventTypeWitness[E],
  action_plan: UiActionPlanToken[E],
  occurrence_storage: UiEventStorageWitness[E]
}

UiListenerBindingBody[E] = {
  declaration_slot: u32,
  cleanup_ordinal: RuntimeNat,
  binding_id: UiListenerBindingId,
  action_entry: UiActionEntry[E],
  listener_token: UiListenerCleanupToken[E],
  generation_entry_gate: EntryGateRef
}

UiListenerBinding = seal exists E: Type. UiListenerBindingBody[E]
UiListenerRef[E] = opaque non-owning typed identity of exact UiListenerBindingBody[E]
UiListenerCleanupToken[E] = opaque linear staged/installed listener responsibility

UiStoredEvent[E] = opaque linear OwnerStorage value of one frozen exact E

UiEventOccurrence = seal exists E: Type. {
  listener_ref: UiListenerRef[E],
  payload: UiStoredEvent[E],
  occurrence_lease: UiOccurrenceLease
}

ActionClaim = Queued {
                event_ordinal: RuntimeNat,
                occurrence: UiEventOccurrence
              }
            | Running {
                event_ordinal: RuntimeNat,
                occurrence: UiEventOccurrence
              }
            | Released { event_ordinal: RuntimeNat }
            | Finalized { event_ordinal: RuntimeNat }

ActionDispatcher = {
  next_event_ordinal: RuntimeNat,
  queue: [ActionClaim],
  active_claim: Option[ActionClaim]
}
```

`revision_cursor` 初始恰为 `{epoch=0,revision=0}`。安装一个新 track subscription 时，
同一 CAS 用 RuntimeNat successor推进 epoch并把 revision重置 0；该 subscription 每次
invalidation只在同 epoch把 revision推进一次。Pair按 `(epoch,revision)` 数值 lexicographic
order，只接受严格更大 pair；duplicate/older不改 state，`retained_latest` 只保留最大
pair。`FixedEpochRevision` 与 Resource 的 `FixedEpochKeyRevision[K]` 是 distinct closed objects，
不可 coercion、共享 equality 或互用 cursor。

`UiActionEntry[E]` 只由同一个 exact action contract的
`ShareableV1(E)+EventOccurrenceStorageV1(rho,gamma,E)`铸造；event type、owner、generation、revision
与 callback contract双向相等。Host callback ABI是 typed `(UiListenerRef[E],E)`。它的第一个不可分割
动作验证 binding/generation gate Open、递增唯一 `live_occurrences`并取得一个 Queued lease、把 exact
E复制/移动进 `UiStoredEvent[E]`、分配递增 enqueue ordinal，然后 FIFO publish。任一步失败都 release
本地未发布责任；绝不保存 raw host bytes、getter、late reread或 shadow count。

Dispatcher只按 event ordinal取得队首，原子 `QueuedHold -> RunningEntry`，从同一个 existential
package解出 exact listener/action/storage witness，并用存储的 immutable generation/revision创建
SnapshotContext；不得读取 then-current revision。Action terminal无论 Returns、sealed finalization或
defect cleanup都恰一次销毁 stored event、consume `RunningEntry`、把 ActionClaim标 Released并把 gate唯一
count减一。Close/stale把 gate status改 Closed禁止新 enqueue，但 queued/running继续持同一 lease；
count为0后 listener
cleanup eligible。没有 per-event DisposeReport item；occurrence storage与 lease只在 enqueue-local、Queued、
Running之一线性存在。

```text
UiCommittedPayload = {
  generation: RuntimeNat,
  plan_token,
  listener_bindings: [UiListenerBinding],
  signal_tail_token,
  host_mount_handle: HostMountHandle,
  entry_gate: EntryGateRef
}

UiCandidatePayload = {
  generation: RuntimeNat,
  revision: FixedEpochRevision,
  state: CandidateState,
  candidate_token,
  signal_tail_token,
  start_claim: CallbackStart,
  publication_gate: CandidateGate
}

UiSharedFields = {
  generation_cursor: RuntimeNat,
  revision_cursor: FixedEpochRevision,
  committed: Option[UiCommittedPayload],
  retained_latest: Option[FixedEpochRevision],
  action_dispatcher: ActionDispatcher,
  retiring: [UiRetiring],
  ledger: CleanupLedger,
  close_cell
}

UiRetiring = {
  generation: RuntimeNat,
  host_mount_handle: HostMountHandle,
  closed_entry_gate: EntryGateRef(status=Closed),
  cleanup_ordinals: [RuntimeNat]
}

ListenerIntentBody[E] = {
  declaration_slot: u32,
  cleanup_ordinal: RuntimeNat,
  binding_id: UiListenerBindingId,
  action_entry: UiActionEntry[E],
  listener_token: UiListenerCleanupToken[E],
  generation_entry_gate: EntryGateRef
}
ListenerIntent = seal exists E: Type. ListenerIntentBody[E]

UiPreparation = {
  generation: RuntimeNat,
  revision: FixedEpochRevision,
  plan,
  candidate_token,
  signal_tail_token,
  listener_intents: [ListenerIntent],
  new_entry_gate: EntryGateRef(status=Closed),
  prepare_claim: CallbackStart,
  commit_claim: UiCommitClaim
}

UiPreparedCommit = {
  generation: RuntimeNat,
  revision: FixedEpochRevision,
  plan,
  candidate_token,
  signal_tail_token,
  listener_intents: [ListenerIntent],
  new_entry_gate: EntryGateRef(status=Closed),
  prepared_txn: PreparedUiTxn,
  commit_claim: UiCommitClaim,
  abort_claim: UiAbortClaim
}

PreparedUiTxn = {
  generation: RuntimeNat,
  host_txn_handle,
  listener_slots: [u32 strictly increasing],
  visible: false
}

HostSwapRecord = {
  generation: RuntimeNat,
  previous_generation: Option[RuntimeNat],
  previous_host_mount_handle_ref: Option[HostMountHandleRef],
  new_host_mount_handle: HostMountHandle,
  old_entry_gate: Option[EntryGateRef],
  new_entry_gate: EntryGateRef
}

UiCell =
    Running { fields: UiSharedFields, candidate: Option[UiCandidatePayload] }
  | Preparing { fields: UiSharedFields, work: UiPreparation }
  | Committing { fields: UiSharedFields, work: UiPreparedCommit }
  | Closing { close_reason: CloseReason,
              generation_cursor: RuntimeNat,
              committed: Option[UiCommittedPayload],
              work: Option[UiCloseWork],
              action_dispatcher: ActionDispatcher,
              retiring: [UiRetiring],
              ledger: CleanupLedger,
              close_cell }
  | Closed { report: DisposeReport, close_cell }

UiCommitClaim = Pending | Committed(HostSwapRecord) | Aborted
UiAbortClaim = Dormant | Startable | Running(entry_lease) | Released
UiCloseWork = CandidateWork(UiCandidatePayload)
            | PreparingWork(UiPreparation)
            | PreparedWork(UiPreparedCommit)
CandidateState = Active | Ready(ViewPlan)
```

每个 admitted UI generation同一 CAS递增 generation/revision，建立一个 shared entry gate，按固定
`UiCandidate,SignalTail` reservation顺序登记，安装 Startable；transform/plan construction在 CAS后
且 NoSuspend。Normalized plan listener按 declaration slot递增、无重复；prepare为每个 exact E建立
typed intent与 listener cleanup reservation，但不开放 callback admission。Prepared transaction只有一个
`UiCommitClaim`；commit、stale与 close竞争该 claim。Committed(record)的 helper必须逐字段无损
materialize listeners、把 candidate reservation改 UiCommittedPlan、安装 record exact new gate/host mount，
再把 old committed移入 UiRetiring；Aborted helper必须 attempt-all释放整个 prepared transaction与所有
listener/candidate/tail责任。任何 state只有一个 `Option[UiCloseWork]`，不能同时藏 candidate和commit work。

Close/stale先 revoke candidate/commit与所有 generation gates，再等待 transform/abort/event entry leases；
listener token保留完整 existential binding/action entry直到其唯一 gate count 0。UI dispose最后按 ledger
ordinal生成 report；同 target repeated dispose返回同一 receipt。

== Sealed fixed-Epoch checkpoint runner <checkpoint-runner-v1>

Incremental checkpoint在 successor中固定为 first-party sealed runner，不再是 open
`trusted-ctl/sealed-checkpoint` choice。Source没有 generic checkpoint constructor，也没有 public
`Plan[A]`、CommitGate/Ticket或 Commit operation。Runner建立 private fixed Epoch snapshot；一个 run内
所有 candidate read必须证明相同 `FixedEpochRevision(epoch,revision)`，dependency trace complete且
source order固定。

```text
CheckpointRunnerProtocolV1 = {
  artifact: "CheckpointRunnerProtocolV1",
  profile: "Cire-v1.0",
  schema_version: 1,
  epoch_policy: "FixedEpochV1",
  candidate_policy: "CoalesceLatestV1",
  claim_policy: "PrivateSingleClaimV1",
  public_plan_commit_api: false
}

CheckpointCell[A] =
    Idle { committed: Option[CommittedSnapshot[A]], latest: Option[Revision] }
  | Computing { fixed_epoch: Revision, dependency_trace,
                latest: Option[Revision], private_claim: Pending }
  | Prepared { fixed_epoch: Revision, candidate: PrivateCandidate[A],
               latest: Option[Revision], private_claim: Pending }
  | Closing { committed: Option[CommittedSnapshot[A]], private_work,
              close_cell }
  | Closed

PrivateCheckpointClaim = Pending | Committed | Aborted
```

只有 runner可产生/消费 private candidate/claim。Compute在 fixed epoch捕获 complete dependencies；
prepare后 commit/stale/close竞争一个 claim。Commit仅在 source heads仍等于 fixed epoch且 Owner/generation
gate Open时一次 publish；否则 Abort并 cleanup。期间到达 revision只覆盖 latest，当前 terminal后最多
admit一次 retained latest。用户 code不能观察 claim、candidate或提交中间态。下文旧泛化
`Plan/CommitGate` rule仅属 legacy calculus，不能用于构造 successor source/API。
