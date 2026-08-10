#import "../shared.typ": *

= Retained TR0 theorem statements 与 Cire-v1.0 lifting obligations <metatheory>

这些是 retained theorem statement，不是本文已经完成的 proof。对 `Cire-v1.0`，
它们的 premise 必须先扩展为 @successor-rule-anchors-v1 的 package/M3/ordinary/registry/
runtime WF；旧 V1/V2 schema、generic Event、三参数 Resource、public Plan/Commit 或开放
checkpoint 的 theorem instance 只属 legacy decoder/proof profile。

== Canonical surface import obligations

#status(
  [Imported theorem P1 — surface determinism],
  [
    唯一 surface authority artifact必须证明对固定 profile/input的 accepted lossless CST与
    normalized Surface HIR唯一。本文只以 verified surface/profile/HIR hash为 premise，不重述 PEG。
  ],
)

#status(
  [Imported theorem P2 — surface pipeline progress],
  [
    Canonical surface producer必须终止或产生 deterministic frontend error；当且仅当 profile为该
    failure分配 stable diagnostic id时，该 id必须属于 `CireDiagnosticsV3`并遵守其 stage/origin metadata。
    Recovery CST不可进入 `CanonicalSurfaceV1`。这一义务由 surface authority及其 corpus验证，不由
    本文第二个 recognizer证明。
  ],
)

== Static semantics

Declarative relation
$K;I;Phi;Omega@Theta ⊢_"d" e:A @[pi] ! epsilon ▷ s;delta;chi
@Theta'⊣Omega'$ 由本节算法规则擦除 `⇒/⇐` 方向、normalization顺序与
evidence数据后归纳生成；function call、handler installation和 suffix site
仍保留其 existential contract premise。它不是另一套宽松规则，因此
soundness statement有明确目标。

#status(
  [Theorem T1 — algorithmic soundness],
  [
    若 algorithm返回的 path set含 `Returns(Θ′,π,χ)`，则擦除
    normalization evidence后存在对应的普通 declarative typing
    derivation；每个 `Aborts` entry存在对应
    $K;I;Phi;Omega@Theta ⊢_"abort" e ! epsilon ▷ s;delta⊣Omega'$
    derivation；每个 `Transfers(P)` entry存在唯一 T-Park derivation、
    sealed completion source 与匹配的 $P$。Terminal entries没有
    type/provenance/normal world output；同一 set可同时包含三类 outcome，
    但三类不互相 coercion。
  ],
)

#status(
  [Theorem T2 — synthesis uniqueness],
  [
    在 resolver binding、kind evidence和 handler certificate固定时，
    algorithm的 normalized flow set唯一。每个 `Returns` entry的
    type、provenance、world transformer、result capture与所有 entry共享的
    normalized row、attributed demand、attributed suspension、finite
    latent-site summary modulo alpha-renaming唯一；`Aborts` entry没有
    result字段；每个 `Transfers` entry具有唯一 sealed
    `ParkContractV2`/claim identity。Terminal entries不声称不存在的
    result/world唯一。这里声称的是 deterministic
    algorithm，不是任意 declarative derivation的 principal-type theorem。
  ],
)

#status(
  [Theorem T3 — decidability],
  [
    若 kind、row predicate、subtyping、ability resolution和 certificate
    lookup可判定，则 algorithmic type checking终止并可判定。
  ],
)

== Temporal safety

#status(
  [Theorem N1 — no early advance],
  [
    若 closed expression对 `advance(v)` 有 typing derivation，则 temporal
    context存在 matching clock lock，且 $v$ 可在该 lock之前的 prefix中
    typing。故 well-typed程序不能在对应 logical tick之前打开 `Next`。
  ],
)

#status(
  [Theorem N2 — clock separation],
  [
    $i != j$ 时，`lock_j` 不满足 `Next[i,A,L]` 的 elimination premise。
    Clock family相同不能替代 singleton identity相同。
  ],
)

#status(
  [Theorem N3 — no latent-effect laundering],
  [
    T-Delay要求 body在其 own future scope中 residual-effect-free、
    NoSuspend且TemporalPure。外层 handler不能在 T-Delay之后消除其 premise；
    handler消除 row也不能删除 semantic summary。
  ],
)

== Effect/control safety

#status(
  [Theorem E1 — handler contract preservation],
  [
    若 clause schema refine operation contract且每个实际 site通过
    `InstallOK`，则 resume不会获得更强 quantity、伪造不同 world target、
    绕过 Tick/parking obligation或隐藏 declared suspension上界。
  ],
)

#status(
  [Theorem E2 — one-shot disposition],
  [
    对每个 `once` resumption，任何运行路径至多一个 resume、finalize或
    park成功 claim；park后 completion、close/cancel再竞争同一个
    generation-bound atomic claim。证明结合路径敏感 usage algebra与
    runtime CAS。
  ],
)

#status(
  [Theorem E3 — no capability escape],
  [
    Fresh named handler scope的每一种 outward flow都不在 row、suspension、
    semantic summary或 usage evidence中自由出现 fresh identity；正常返回
    还要求 result type、provenance、capture与 temporal context满足同一
    条件。合法 existential container只通过将 identity绑定在 type内部，并
    同时拥有 runner/Owner/dispose responsibility而成立，并非 escape gate
    的例外。
  ],
)

#status(
  [Theorem E4 — multi-shot capture safety],
  [
    在 `declared-max` profile下，可能 multi-shot 的 operation suffix只捕获
    Duplicable authority和Replayable cleanup；因此不会复制 one-shot
    resumption或nonduplicable cleanup responsibility。
  ],
)

== Async/Owner safety

#status(
  [Theorem A1 — suspension ownership],
  [
    对通过 `OwnerBoundParking` installation 的 may-suspend handler，每个
    parked once continuation由一个 live Owner拥有；completion、cancel与
    close竞争同一 disposition claim。Owner/generation无效后不能恢复。
  ],
)

#status(
  [Theorem A2 — no borrowed boundary escape],
  [
    若 value跨 temporal lock、suspension、checkpoint或FFI storage boundary，
    则其 provenance和captures满足对应 boundary predicate；callback-local
    borrow与未rooted Wasm memory view不能通过。
  ],
)

== Incremental safety

#status(
  [Theorem I1 — fixed-Epoch reads],
  [
    一次 candidate replay中所有 invalidating Source read来自 Begin时 pin住的
    同一 $Sigma(e)$；replay期间的新 write只能进入 pending/batch journal并
    形成下一 Epoch。
  ],
)

#status(
  [Theorem I2 — replacement generation safety],
  [
    对同一 cut至多一个 active candidate slot；Begin不覆盖 committed
    generation。只有 current、owner-valid candidate能原子替换
    value/trace/wakes。被祖先替换或 generation失效的后代不能恢复或 publish。
  ],
)

#status(
  [Legacy theorem I3 — generic commit at-most-once],
  [
    对固定 publication slot/revision $(ell,r)$，Commit claim状态只能从
    OpenClaim原子转为CommittedClaim一次，且抽象 accepted-publication log
    至多追加一次；其他调用返回Stale/AlreadyCommitted并且不修改 $J/L$。
    这是动态 claim theorem，不是静态 affine或外部网络 exactly-once theorem。
  ],
)

`Cire-v1.0` 不暴露上述 generic Commit claim。其 canonical replacement义务是：
@checkpoint-runner-v1 的 `PrivateCheckpointClaim`、@signal-ui-protocol-v1 的 `UiCommitClaim`
与 @resource-protocol-v1 的 publication gate 分别在自己的 sealed state machine 中至多一次成功，
且不存在可用户构造或跨协议搬运的共享 Commit authority。

== From-scratch consistency

令 $sigma_p$ 是显式允许的 persistent state。定义从头执行：

$
  "evalFS"(e,Sigma(e_n),sigma_p) = (v_"fs",T_"fs",sigma_"fs"')
$

Representation relation：

$
  "Rep"_A(M,c_0,e,Sigma(e_o),v_o,T_o)
$

其中 $c_0$ 是该 Live computation的 designated root cut；relation表示 $M$
的 committed value/trace确实来自此前对 $e$ 的合法执行。
Successful quiescence要求：

```text
B = []
P = ∅
N = ∅
Q has no dirty or error marker
C has no active candidate
all required frontier candidates published successfully
```

从 committed $T(c_0)="Committed"(g,v,T_c,W_c)$ 读取增量结果：

$
  "evalInc"(M,c_0,e,Sigma(e_n),sigma_p)
  = (M',v_"inc",T_"inc",sigma_"inc"')
$

#status(
  [Theorem FSC — conditional from-scratch consistency],
  [
    若：

    - `e` 通过 T-Live；
    - $"WF"(M)$ 且
      $"Rep"_A(M,c_0,e,Sigma(e_o),v_o,T_o)$；
    - 本轮 Freeze产生目标 snapshot $Sigma(e_n)$；
    - runner具有 `ImplementsLive` witness；
    - handler certificates的 replay laws真实；
    - typed candidate evaluation与 source semantics互相 simulation；
    - dependency recorder对本轮控制流 sound且complete；
    - speculative trace、wake、cleanup与effect全部 candidate-buffered；
    - primitive computation deterministic于 fixed snapshot；
    - persistent state两边使用同一初态；若 handler有持久化优化，其
      certificate给出同时保持 result与control/dependency observation的
      bisimulation
      $"PersistentTraceEq"(sigma_"fs"',sigma_"inc"')$；
    - 每个 dirty frontier均成功 publish，scheduler到达 successful quiescence；

    则 $v_"inc" ≈_A v_"fs"$，且 $T_"inc"$ 与 $T_"fs"$ 的有效 dependency
    在 cut identity/generation alpha-renaming下等价。
  ],
)

Abort/error留下 dirty/error marker，因此“旧值但 Q 已清空”的状态不满足 theorem
前提。FSC 不推出 scheduler fairness、Task最终完成、retire queue liveness或
浏览器最终产生 frame。

== Proof 分层

建议 mechanization不要试图一次证明“大一统 soundness”，而按依赖分层：

```text
Surface grammar + elaboration preservation
        ↓
CBV Core operational semantics + evaluation-context determinism
        ↓
kinding + row normalization
        ↓
algorithmic typing soundness
        ↓
temporal preservation
        ↓
effect/summary/capture preservation
        ↓
one-shot + Owner runtime safety
        ↓
incremental machine invariants
        ↓
conditional FSC + Commit safety
```

Surface 层先证明 n-ary `def`/labelled call、block final expression、隐式
`return` 与 `fun` hidden tail-resume 的 elaboration preservation；随后在
CBV Core中给出 sealed `@control::finally`、handler delimiter、resume/finalize/park、Owner
close与 generation CAS 的小步语义。没有这两层，后续 preservation
只能算规则草图。
