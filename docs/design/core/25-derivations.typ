#import "../shared.typ": *

= 代表性推导与拒绝

== 纯 Next

程序：

```cire
def next_double(
  frame : FrameClock,
  value : Int,
) -> Next[frame, Int] ! {} {
  delay[frame] {
    value * 2
  }
}
```

假设：

$
  I(i) = ("FrameClock",rho)
$

$
  "StableAcross"(i,pi_"value",1)
  quad
  "Shareable"("Int")
$

Body derivation：

#irule(
  [T-Mul],
  (
    [$K;I;Phi@"pushLock"(Theta,i) ⊢_v "value" ⇒ "Int" @["Stable"] ▷ emptyset$],
    [$K;I;Phi@"pushLock"(Theta,i) ⊢_v 2 ⇒ "Int" @["Stable"] ▷ emptyset$],
  ),
  [$K;I;Phi;Omega@"pushLock"(Theta,i) ⊢ "value"*2 ⇒ "Int" @["Stable"] ! emptyset ▷ "direct"("NoSuspend");delta_"pure";emptyset @"pushLock"(Theta,i)⊣Omega$],
)

应用 T-Delay 得：

$
  L_"double"=⟨["Stable"],emptyset,delta_"pure",Phi⟩
$

$
  K;I;Phi;Omega@Theta
  ⊢ "delay"_i("value"*2)
  ⇒ "Next"[i,"Int",L_"double"] @["Stable"] ! emptyset
  ▷ "direct"("NoSuspend");delta_"alloc";emptyset
  @Theta⊣Omega
$

== 过早 Advance

```cire
def too_early(
  frame : FrameClock,
  value : Next[frame, Int],
) -> Int ! {} {
  advance(value)
}
```

当前 $Theta$ 中没有 `"lock"_i`，因此不存在：

$
  "splitRight"(Theta,i)
$

T-Advance 无法应用。建议诊断：

```text
cannot advance value for `frame` in the current temporal zone
required: one `frame` lock between value origin and this use
```

== 一次 Yield 后 Advance

```cire
let pending = delay[frame] { 42 }
frame.yield()
advance(pending)
```

顺序推导：

```text
delay:
  Θ → Θ
  pending : Next[ι, Int] is bound in the current zone

yield:
  Θ → pushLock(Θ, ι)

advance:
  splitRight(pushLock(Θ, ι), ι) succeeds
  pending is checked in the prefix Θ
```

因此得到 `Int`。

== Distinct clocks

若：

$
  v : "Next"[i_"network",A]
$

当前只有：

$
  "lock"_(i_"animation")
$

则 T-Advance 的 matching split失败。Clock family相同不意味着 identity相同。

== Handler 内外

内部 handler：

```cire
delay[frame] {
  with Error::result()
  in {
    parse(text)
  }
}
```

推导次序：

```text
T-Operation(parse)   produces {Error}
T-Handle             removes {Error}, attaches replay/temporal certificate
T-Delay              observes empty residual row and TemporalPure certificate
```

外部 handler：

```cire
with Error::result()
in {
  delay[frame] {
    parse(text)
  }
}
```

T-Delay 是 T-Handle 的 premise；它先看到 `{Error}`，因此失败。外层 rule
不能“事后”洗掉 latent effect。

== Empty row 但 HostObservable

```cire
delay[frame] {
  with Console::host()
  in {
    Console::print_line("surprise")
  }
}
```

T-Handle 可令 $epsilon=emptyset$，但：

$
  not "TemporalPure"(delta_"Console.host")
$

T-Delay 仍失败。这是 $epsilon$ 与 $delta$ 分轴的必要反例。

== Delay 内局部 Async handler

```cire
delay[frame] {
  with BrowserAsync::run(owner)
  in {
    Async::await(task)
  }
}
```

T-Operation先产生：

$
  "request"(
    "demandKey"("Demand"(kappa,p,"Anon"("Async"),
      "await","Primary")),
    "MaySuspend")
$

Browser handler的 `actualSusp=MaySuspend`，所以 elimination后
`grade(s)=MaySuspend`。T-Delay要求 `NoSuspend`，因此失败。

== 基本 Live

```cire
let total =
  live {
    read(price) * read(count)
  }
```

`live` elaborator创建 hidden $i_o$。两次 `read` 的 row union normalization
仍为：

$
  {"Named"(i_o,"Observe")}
$

若 body的 attributed suspension grade为 `NoSuspend`、result
`Shareable`、summary replay-safe，则 T-Live
成立。实际 dependency `{price,count}` 只进入 Trace。

== Live 中 Host write

```cire
live {
  let amount = read(total)
  charge_credit_card(amount)
}
```

Body residual row至少包含：

$
  {"Named"(i_o,"Observe"), "HostWrite"}
$

不满足 T-Live 要求的“只可含 Observe”row；若 Host handler在内部消除 row，
其 `HostObservable/Immediate` summary仍使 `ReplaySafe` 失败。

== Commit 跨 Await

```cire
Commit::run(ticket) { gate =>
  let result = Async::await(task)
  gate.try_publish(result)
}
```

Async.await signature要求 `Action` phase，T-Try-Publish要求 `Commit`
phase；不存在不显式
退出/revalidate 的 phase derivation。此外 await使 revision可能 stale。

== 判定矩阵

#table(
  columns: (2.7fr, 1fr, 2.5fr),
  [*程序形状*], [*判定*], [*决定 premise*],
  [`delay { pure immutable computation }`], [接受], [`ε=∅`、NoSuspend、TemporalPure、Shareable],
  [`advance` without matching lock], [拒绝], [`splitRight` undefined],
  [`delay { handled host IO }`], [拒绝], [handler summary is HostObservable],
  [`delay { handled Error -> Result }`], [接受], [sealed TemporalPure handler],
  [`delay { locally handled await }`], [拒绝], [MaySuspend survives row elimination],
  [`live { Observe.read }`], [接受], [row is subset of hidden Observe + ReplaySafe],
  [`live { read; await; read }`], [拒绝], [minimal Live requires NoSuspend],
  [`Choice before Observe cut`], [拒绝], [missing TraceCompatibleFork],
  [`Observe cut before pure local Choice`], [条件接受], [TraceNeutral concrete handler],
  [`sealed UI action captures one-shot authority`], [拒绝], [many-shot retained closure violates usage],
  [`private checkpoint/UI claim crosses await`], [拒绝], [phase/suspension + stale generation],
  [`owned snapshot across Wasm callback`], [条件接受], [boundary provenance + Owner root],
)
