#import "../shared.typ": *

== Task broadcast protocol <task-protocol-v1>

`Task[rho,R]` formation要求 `ShareableV1(R)` 与 `AsyncBoundarySafeV1(rho,R)`；handle可复制且
multi-waiter。只有 exact `Task[rho,TaskOutcome[A,E]]`有 central cancel API；generic Task不会凭空
产生 failure/cancel value。

```text
TaskCell[R] =
    Pending {
      task_generation: RuntimeNat,
      next_registration_ordinal: RuntimeNat,
      waiter_map
    }
  | Resolved {
      task_generation: RuntimeNat,
      next_registration_ordinal: RuntimeNat,
      value: R
    }
  | OwnerClosed {
      task_generation: RuntimeNat,
      next_registration_ordinal: RuntimeNat
    }

TaskWaiter =
    Armed(registration_ordinal, task_generation,
          observer_owner_generation, completion_port)
  | DeliveryWon(observer_entry_lease)
  | Delivered(observer_entry_lease)
  | Finalized
```

Ready await同步 Returns immutable R，但 static contract仍 MaySuspend。Pending await按 receipt同一
observer gate protocol登记独立 waiter，再由 sealed park产生唯一 Transfers(ParkContractV2)。Producer
complete CAS一次保存 exact R，并按 registration ordinal竞争每个独立 claim；Shareable允许 fan-out。
Waiter cancel只 finalize自己，不取消 producer/其它 waiter。Outcome normal/failure/explicit cancel只在
task Owner Open时竞争 Pending→Resolved(TaskOutcome)。Owner close若先赢 Pending→OwnerClosed，禁止新
register/cancel、finalize waiter并 child-first close producer，不伪装成 TaskOutcome；Resolved先赢则 close
不改写 R。所有 counter保留最终值，ordinal不由 map size反推或回收。

`Async::await` 的 current observer Owner从 phase推出，不能由 `under=other`重定向；要求
OwnerAuthority、Outlives(observer,task region)、Shareable(R)、AsyncBoundarySafe、SuspensionStable与
OwnerBoundParking。`CloseReceipt::await` 是独立 operation，不改写成 Task await。

== Resource switch-latest protocol <resource-protocol-v1>

唯一 public family为 `Resource[rho,K,A,E]`；K/A/E都需 Shareable与 owner-storage boundary evidence。
唯一 behavior是 SwitchLatest + keep-last-good：新 key supersede active candidate；成功 atomic replace
last-good，失败时有旧值则 Degraded、无旧值则 Failed；stale completion只 cleanup，绝不 publish。

```text
FixedEpochKeyRevision[K] = { epoch: RuntimeNat, key: K }

CandidateGate = Active | Stale | Closed
CallbackStart = Startable | Running(entry_lease) | Released | Finalized

CandidateRegistration =
    Starting { cleanup_ordinal: RuntimeNat, candidate_token,
               start_claim: CallbackStart }
  | Awaiting { cleanup_ordinal: RuntimeNat, candidate_token,
               completion_claim_ref }
  | Retiring { cleanup_ordinal: RuntimeNat, task_link: TaskLink }

TaskLink = NoTask | TaskClaim { completion_claim_ref }

CommittedPayload[K,A] = {
  generation: RuntimeNat,
  key: K,
  token,
  value: A
}

CandidatePayload[K] = {
  generation: RuntimeNat,
  revision: FixedEpochKeyRevision[K],
  gate: CandidateGate,
  registration: CandidateRegistration
}

ResourceRetiring = {
  generation: RuntimeNat,
  registration: Retiring {
    cleanup_ordinal: RuntimeNat,
    task_link: TaskLink
  }
}

InputSubscription =
    InputLive { cleanup_ordinal: RuntimeNat, input_token,
                gate: InputGate, dispatch_claim: InputDispatchClaim }
  | InputRetiring { cleanup_ordinal: RuntimeNat, input_token }
  | InputFinalized { cleanup_ordinal: RuntimeNat }

InputGate = Open | Closed
InputDispatchClaim = Idle | Running(entry_lease)

ResourceCommon = {
  input_subscription: InputSubscription,
  input_revision_cursor: Option[RuntimeNat],
  retiring: [ResourceRetiring],
  close_cell,
  ledger: CleanupLedger
}

ResourceCell[K,A,E] =
    Vacant { generation_cursor: RuntimeNat, common: ResourceCommon }
  | Acquiring { generation_cursor: RuntimeNat, candidate: CandidatePayload[K],
                retained_latest: Option[FixedEpochKeyRevision[K]],
                common: ResourceCommon }
  | Ready { generation_cursor: RuntimeNat, committed: CommittedPayload[K,A],
            common: ResourceCommon }
  | Replacing { generation_cursor: RuntimeNat, committed: CommittedPayload[K,A],
                candidate: CandidatePayload[K],
                retained_latest: Option[FixedEpochKeyRevision[K]],
                common: ResourceCommon }
  | Degraded { generation_cursor: RuntimeNat, committed: CommittedPayload[K,A],
               failed_key: K, error: LoadFailure[E], common: ResourceCommon }
  | Failed { generation_cursor: RuntimeNat, failed_key: K, error: LoadFailure[E],
             common: ResourceCommon }
  | Closing { close_reason: CloseReason, generation_cursor: RuntimeNat,
              committed: Option[CommittedPayload[K,A]],
              candidate: Option[CandidatePayload[K]], common: ResourceCommon }
  | Closed { report: DisposeReport, close_cell }
```

Construction在新 ledger ordinal 0/generation 0登记 ResourceInput，安装 closed input gate与
`input_revision_cursor=None`，再同一 linearization Open gate并 publish Vacant。Input callback先原子
验证 gate并取得 entry lease；cursor None只接受 epoch 0，此后只接受严格更大 RuntimeNat。同/旧 epoch
在读取 key前丢弃，不改 state。接受新 revision的单一 CAS同时推进 cursor并恰一执行：无 active
candidate则 admit；Active candidate变 Stale并 retain latest；已 Stale则覆盖 retained latest。

每次真实 admission同一 CAS递增 generation、建立 direct child、登记唯一 ResourceCandidate reservation
并安装 `Starting(...,Startable)`；CAS内不调用 user code。Winner再 Startable→Running(entry lease)后
调用 loader；stale/close先赢则 Finalized且调用次数 0，running先赢则 revoke publication并等待 release。
Loader必须返回 exact child-owned `Task[rho_child,TaskOutcome[A,E]]`，handoff到 Awaiting后才可 release
callback entry lease；task completion claim、candidate gate与 outer state共同决定唯一 publication。

Success publish必须在一个 transaction中验证 outer Acquiring/Replacing、matching candidate identity/
generation与 gate Active；把 new value/token reservation role改 ResourceCommitted，把旧 committed
移入 retiring并 role改 ResourceRetired，再发布 Ready。Failure同一 transaction移 candidate到 retiring，
有 old committed发布 Degraded，否则 Failed。任何 path都不先 publish view再转 token。Candidate terminal
后若 retained_latest存在，按其 exact revision立即 admit next generation；只保留 latest。

Close先关 input gate、进入 Closing、把 candidate gate Closed、丢 retained value，线性把 input/
candidate/committed/retiring reservations移入 pending并等待所有 entry/completion claims。Closing schema
不含 retained_latest；Failed/Degraded不含 hidden candidate。全部 cleanup后生成同一 receipt/report。
