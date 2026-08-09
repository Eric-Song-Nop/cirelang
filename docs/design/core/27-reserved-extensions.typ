#import "../shared.typ": *

= Reserved future extensions 与 successor exclusions

== `defer` 保留但不 reachable

`defer` 是 reserved keyword并稳定 `defer-not-in-cire-v1`；它不产生 accepted HIR/Core，
也没有待实现的 v1 reduction calculus。唯一 scoped general finalization是
@intrinsic-registry-root-v1 的 sealed `with @control::finally(cleanup) in body`，其 cleanup
进入既有 suffix ledger。

== Clock representation

`Cire-v1.0` 固定 singleton capability identity。Fresh phantom type是未来新 profile研究，
若采用将改变：

- kinding与substitution；
- public API clock quantification；
- existential packaging；
- capability identity与clock identity是否共用一套基础设施。

任何实验都不能改变当前 profile artifact meaning。

== Fitch availability 的表达能力

本模型把函数参数绑定在调用时的当前 zone，因此保守拒绝某些“调用者已经知道
该 Next成熟、但 helper签名未携带 world evidence”的程序。未来可研究：

```text
world-polymorphic function contract
availability witness parameter
clock quantification
```

不能靠普通 effect row猜测成熟关系。

== Effectful Later

若以后加入：

$
  "Later"[i]{A ! epsilon} ▷ chi
$

必须同时定义：

- 执行次数；
- future handler instance；
- Owner；
- cleanup；
- suspension；
- result quantity；
- 丢弃语义。

它不应通过放宽 T-Delay 的 empty-row premise偶然出现。

== Handler specialization

Successor固定按 operation声明的最大 mode检查 capture；不存在 lexical specialization。若未来
新 profile希望词法已知：

```cire
with Choice::first()
in { ... }
```

享受 `fun/once` 的较弱 capture限制，需要证明：

- handler不能被 abstraction替换；
- operation dispatch确实绑定该 instance；
- specialization evidence跨module保存；
- optimizer不改变 handler ordering。

== Local mutable State under multi-shot/replay

`Cire-v1.0` 固定：multi-shot/replay boundary 捕获任何 live ordinary mutable place均拒绝；one-shot
boundary只在 continuation独占 place且无 handler/environment alias时允许。Shared cell必须是显式
Owner-managed nominal capability。Copy-on-capture与 candidate-local implicit snapshot不在本 profile；
family级 `Replayable(State)`不能放宽这条 gate。

== Checkpoint profile 已关闭

`Cire-v1.0` 唯一选择是 @checkpoint-runner-v1 的 sealed fixed-Epoch first-party runner。
`trusted-ctl` generic implementation与 public Plan/Commit不属于本 profile。普通 effect仍有四种
resumption mode，但它们不授予 checkpoint private claim。

== General affine values

本文只对 resumption disposition做 quantity analysis。若未来引入一般 affine：

```text
once cap Commit
unique Socket
affine Event payload
```

需要把 quantity传播到：

- closure call grade；
- ADT field；
- generic container；
- existential；
- trait object；
- interface artifact。

在此之前 successor只对 sealed runtime-private claim声称 dynamic at-most-once；没有 user Commit value。

== Portable handlers 与 async finalizer excluded

Retained rule固定 continuation cleanup不是隐式 pure；其
$F_k=⟨epsilon^"fin",Delta^"fin",zeta^"fin",s^"fin",delta^"fin"⟩$ 必须进入
T-Finalize与 clause aggregation。`Cire-v1.0` 不提供 portable/reentrant handler value、async cleanup
executor或 finalizer trap aggregation API；cleanup必须满足其现有 phase/row/NoSuspend contract，
Wasm context representation保持 compiler-private。任何上述能力都需要新 profile/schema，不能由 host
stack重装顺序或 ABI实现细节补出。
