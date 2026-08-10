#import "../shared.typ": *

=== Closed intrinsic registry 与 first-party surface <surface-8-4>

Compiler、LSP 与 conformance只消费一个生成的 `IntrinsicRegistryRootV1`。它包含
两个 profile-disjoint child：

+ 下文定义的 exact `FirstPartyRegistryV1`，恰好 21 个
   temporal/Owner/reactive binding；
+ `StructuralIntrinsicRegistryV1`，恰好 `BuildStringV1` 与 `FinallyV1` 两个
   compiler-owned structural elaboration。

第二个 child不改变 21-entry registry的 bytes/cardinality。BuildString没有用户可调用
binding；`@control::finally`只有 #ref(<surface-2-6>) 的 exact runner signature。任何同 spelling用户
declaration、wrong package instance、missing evidence或 registry hash mismatch都走 ordinary
call或稳定拒绝，绝不按名字升级 privileged Kernel node。

21 个 binding ID按 NFC UTF-8严格排序如下；source signature中的 ordinary names均可
positional或同名 labelled传入，所有 slot nondefaultable：

#table(
  columns: (1.4fr, 1.8fr, 2.8fr),
  [*Stable binding ID*],
  [*Source*],
  [*Direct result / policy*],
  [`Cire-v1.0/intrinsic/async.await-receipt`],
  [`CloseReceipt::await(receipt)`],
  [`R`; Async/MaySuspend/current Owner],
  [`Cire-v1.0/intrinsic/async.await-task`],
  [`Async::await(task)`],
  [`R`; Async/MaySuspend/current Owner, `Shareable(R)`],
  [`Cire-v1.0/intrinsic/resource.dispose`],
  [`Resource::dispose(resource)`],
  [`CloseReceipt[DisposeReport]`],
  [`Cire-v1.0/intrinsic/resource.switch-latest`],
  [`Resource::switch_latest(under,keys){ owner,key => ... }`],
  [`Resource[rho,K,A,E]`],
  [`Cire-v1.0/intrinsic/resource.view`],
  [`Resource::view(resource)`],
  [`Live[rho,ResourceView[K,A,E]]`],
  [`Cire-v1.0/intrinsic/signal.map`],
  [`map_signal(input,transform)`],
  [`Signal[i,B]`; pure transform],
  [`Cire-v1.0/intrinsic/signal.track`],
  [`Signal::track(frame){ track => ... }`],
  [`Signal[i,A]`],
  [`Cire-v1.0/intrinsic/snapshot.read-live`],
  [`snapshot.read(live)`],
  [fixed-revision `A`],
  [`Cire-v1.0/intrinsic/snapshot.read-source`],
  [`snapshot.read(source)`],
  [fixed-revision `A`],
  [`Cire-v1.0/intrinsic/task.cancel-outcome`],
  [`Task::cancel(task,under)`],
  [`CancelResult`、NoSuspend],
  [`Cire-v1.0/intrinsic/temporal.pack-next`],
  [`@temporal::pack_next(under){ frame => ... }`],
  [`PackedNext[A]`],
  [`Cire-v1.0/intrinsic/temporal.packed-next-dispose`],
  [`@temporal::dispose(packed)`],
  [`CloseReceipt[DisposeReport]`],
  [`Cire-v1.0/intrinsic/temporal.try-with-packed-next`],
  [`@temporal::try_with_packed_next(packed){ frame,next => ... }`],
  [`Option[B]`],
  [`Cire-v1.0/intrinsic/track.read-live`],
  [`track.read(live)`],
  [invalidating `A`],
  [`Cire-v1.0/intrinsic/track.read-source`],
  [`track.read(source)`],
  [invalidating `A`],
  [`Cire-v1.0/intrinsic/ui.builder-owner`],
  [`ui.owner`],
  [exact `Owner[rho]` projection],
  [`Cire-v1.0/intrinsic/ui.candidate-action`],
  [`candidate.action { snapshot,event => ... }`],
  [`ActionPlan[gamma,E]`],
  [`Cire-v1.0/intrinsic/ui.coalesce-latest`],
  [`CoalesceLatest`],
  [closed `UiBackpressureV1` literal],
  [`Cire-v1.0/intrinsic/ui.mount-dispose`],
  [`UiMount::dispose(mount)`],
  [`CloseReceipt[DisposeReport]`],
  [`Cire-v1.0/intrinsic/ui.render`],
  [`ui.render(model){ candidate,current => ... }`],
  [Unit; generation-checked plan],
  [`Cire-v1.0/intrinsic/ui.run-signal`],
  [`@ui::run_signal(under,backpressure){ frame,ui => ... }`],
  [`UiMount[rho]`],
)

上表只是 human-readable index；它不定义简化 wire。下列 closed contract逐字段
唯一生成 registry bytes、callback scheme、evidence discharge与 Kernel lowering。
形式化只解释这些 evidence predicates与 Kernel/Core node的 WF/runtime意义，不能
维护第二张 registry或补写 Surface lowering。

#metadata("R06-first-party-registry") <rule-r06-first-party-registry>
