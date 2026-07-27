# 相关语言与设计先例

## 1. 结论

Cire 的单个零件大多有明确先例。研究空间不在于声称 capture set、effect row 或 one-shot continuation 从未出现，而在于把这些部分连成一个可用系统：

```text
typed algebraic effects
+ abort / once / fun / ctl
+ named capabilities
+ inferred capture checking
+ revocable dynamic Owner/Region
+ continuation-aware finalization
+ stable Wasm host callbacks
+ first-party incremental computation
```

没有任何一门下表中的语言可以被简单“照抄”为 Cire；每门语言都提供一个需要理解的局部答案。

## 2. 对应关系

| Cire 关注的机制 | 可参考的语言/系统 | 已有贡献 | Cire 仍需解决 |
|---|---|---|---|
| Effect row 与 effect polymorphism | Koka | 实用的 row-polymorphic effect typing | 与具名 capability、capture lifetime 连接 |
| `fun` / `ctl` | Koka | tail-resumptive 与 general control | 加入静态 `abort`、`once` |
| Named effect instance | Eff、Effekt | 具体 effect/capability identity | 统一生成式 instance、Owner 与 capture |
| One-shot continuation | OCaml 5 | 高效 one-shot runtime 与 `discontinue` | 把 at-most-once 放进静态类型，并自动 finalization |
| Multi-shot handler | Effekt、Scheme/Racket、Koka `ctl` | 多次恢复与一般控制 | 捕获不可重放 capability 的静态规则 |
| Capture set 与 region | Effekt、Scala 3、Haskell `ST` | 防止局部 capability/reference 逃逸 | 动态可撤销 Owner、generation 与 host race |
| QTT/multiplicity | Idris 2、Linear Haskell、Granule | 0/1/ω 或 graded usage | 专门用于 resumption，并额外检查 tail position |
| Continuation-aware dynamic extent | Scheme/Racket | `dynamic-wind` 的进入/离开语义 | 与 Owner 收养、one-shot disposition、cleanup failure 结合 |
| Affine resource ownership | Rust 等 | move-only ownership 与 deterministic drop | 不是 Cire 默认变量模型；只作为可选通用资源能力 |

## 3. Koka

Koka 是 Cire effect surface 的最直接先例。

### 3.1 `val`

Koka 的 value operation 是无参数的动态绑定值，概念上等价于无参数 `fun`：

```koka
effect val width : int
```

Cire 可以把 `val` 作为无参数 `fun` 的语法糖，但是否保留尚未冻结。

### 3.2 `fun`

Koka `fun` operation 是 tail-resumptive：

- handler 不获得显式 continuation；
- handler body 产生 operation 的返回值；
- 调用点自动恢复恰好一次；
- 恢复位于 handler clause 尾部。

Cire 若使用同名 `fun`，就保持这一语义，不重新定义它。

### 3.3 `ctl`

Koka `ctl` 给予 handler 一般控制：

- 可以不恢复；
- 可以恢复一次；
- 可以恢复多次；
- 可以围绕恢复执行额外逻辑。

因此 `ctl` 不是“multi-shot”的同义词，multi-shot 只是 `ctl` 的一种具体用法。

Cire 在 Koka 的控制包络中增加：

```text
abort  静态 zero-shot
once   静态 at-most-once，可保存
```

Koka 还提供 `raw ctl`、`rcontext`、resume/finalize 等面向长寿 continuation 的低层机制。Cire 更倾向于让保存的 one-shot continuation 被某个 Owner 明确收养，而不是裸逃逸。

### 3.4 Effect kind 与 named handler

Koka 的内部 kind system 区分原子 effect 与 effect row；它的 named handler
设计进一步把 handler name 作为由普通 lambda 绑定的一等值，并使用 rank-2
polymorphism 防止 fresh name 逃逸。

Cire 采用相同的分层动机，但使用 MoonBit 风格的表面写法：

```moonbit
fn[A]![F : Reader[A], ..E] relay(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E}
```

- `A` 是普通类型参数；
- `F` 是受 `Reader[A]` ability 约束的原子 effect 参数；
- `E` 是 row 参数；
- `app` 是普通 term binder，同时携带具体 handler identity。

双列表把普通 type 与 effect binder 分开；`cap F` 再显式区分 family 与
具体 identity，因此 named capability polymorphism 不需要把 capability name
降成字符串 label。

参考：

- [Koka language guide](https://koka-lang.github.io/koka/doc/book.html)
- [First-class Named Effect Handlers](https://www.microsoft.com/en-us/research/publication/first-class-named-effect-handlers/)
- [Tail-resumptive operations](https://koka-lang.github.io/koka/doc/book.html#sec-tail-resumptive)
- [Resuming more than once](https://koka-lang.github.io/koka/doc/book.html#sec-resume-multiple)

## 4. Eff

Eff 展示了一等 effect instance。一个 effect kind 可以产生不同实例：

```text
left#lookup()
right#lookup()
```

这不是仅仅说“程序使用 State”，而是明确调用 `left` 或 `right` 的 operation。它是 Cire 具名 effect capability 的重要先例。

Cire 还要进一步追踪：

- closure/continuation 固定捕获了哪个 instance；
- instance 属于哪个 Region/Owner；
- 保存到未来时该 capability 是否仍有效；
- generation 被撤销后宿主 callback 是否能再次使用它。

参考：[Programming with algebraic effects and handlers](https://math.andrej.com/wp-content/uploads/2012/03/eff.pdf)。

## 5. Effekt

Effekt 是当前最接近 Cire 研究方向的语言之一，因为它同时提供：

- capability 风格的 effect；
- effect handler；
- multi-shot resume；
- capture set；
- region。

Capture checking 区分：

```text
effect
  调用时仍向上下文请求的能力

capture
  closure 已经固定携带的具体能力
```

Region 示例能阻止闭包把局部 cell 带出作用域。

Cire 与 Effekt 的主要差异目标是把该静态模型继续连接到：

- `abort / once / fun / ctl` 的静态恢复模式；
- 可长期保存的异步 continuation；
- 动态 keyed Owner；
- runtime generation/revocation；
- continuation-aware Owner finalization；
- Wasm/DOM callback ABI；
- 第一方增量 trace。

参考：

- [Effekt captures](https://effekt-lang.org/tour/captures)
- [Effekt regions](https://effekt-lang.org/tour/regions)
- [Effekt effect handlers](https://effekt-lang.org/docs/concepts/effect-handlers)

## 6. OCaml 5

OCaml 5 的 effect continuation 是 one-shot：

```ocaml
let n = perform Ask in
n * 10
```

handler 取得 `k` 后可以：

```ocaml
continue k 7
```

第二次继续同一 `k` 会在运行时失败。OCaml 还提供 `discontinue`，相当于在暂停点注入异常，使捕获栈上的 `finally` 正常展开。

Cire 希望加强为：

- `once` 在类型层保证至多处置一次；
- 分支敏感检查 `resume/discontinue/finalize`；
- 未处置时自动 finalize；
- 保存到未来必须转交 Owner；
- host duplicate completion 由 one-shot runtime slot 防御。

参考：

- [OCaml effect handlers](https://ocaml.org/manual/5.4/effects.html)
- [Effect.Deep API](https://ocaml.org/manual/5.0/api/Effect.Deep.html)

## 7. Haskell `ST`

`ST` 使用 rank-2 polymorphism 创建外部无法命名的生成式 region：

```haskell
runST :: (forall s. ST s a) -> a
```

`STRef s A` 不能逃出 `runST`，但普通结果可以。

这说明生成式身份可以在不依赖全局 affine 变量的情况下阻止局部引用逃逸。

Cire 的动态 Owner 更复杂：

- Owner 可以跨越很多次函数调用；
- 可以因取消或宿主卸载提前死亡；
- keyed container 可以重新打开同一 existential Owner；
- generation 需要处理运行时 ABA 和旧 callback。

参考：[Control.Monad.ST](https://hackage.haskell.org/package/base/docs/Control-Monad-ST.html)。

## 8. Scala 3 capture checking

Scala 3 实验性的 capture checking 使用类似：

```text
T^{x, y}
```

表示一个值捕获 capability `x`、`y`，并依靠 capability 的词法嵌套限制值可以逃逸到哪里。

它证明 capture set 可以主要由编译器推导，并只在高级签名与诊断中显式出现。

Cire 不能只依靠 capture set，因为浏览器已排队 callback、动态 key、candidate 抢占与 FFI 竞态仍需要 generation/revocation。

参考：[Scala 3 capture checking](https://docs.scala-lang.org/scala3/reference/experimental/capture-checking/cc.html)。

## 9. Idris 2、Linear Haskell 与 Granule

这些语言说明 quantity/modal information 可以放在类型内部，而不必为每个常见控制行为暴露复杂区间语法。

### 9.1 Idris 2 QTT

Idris 2 使用：

```idris
(0 x : A) -> B
(1 x : A) -> B
A -> B
```

分别表达 erased、恰好一次与 unrestricted。`1` 是 linear，不是 affine 的 `0..1`。

参考：[Idris 2 multiplicities](https://idris2.readthedocs.io/en/latest/tutorial/multiplicities.html)。

### 9.2 Linear Haskell

Linear Haskell 把 multiplicity 放在箭头上：

```haskell
A %1 -> B
A %m -> B
```

参考：[GHC Linear Types](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/linear_types.html)。

### 9.3 Granule

Granule 使用 graded modalities，可表达类似：

```text
A [2]
A [0..1]
```

这接近 Cire 内部对 affine 恢复权的形式化表示。但 Granule 面向一般 grade，复杂记号有充分价值；Cire 的普通 effect surface 只有四个常见控制模式，没必要把区间暴露给所有用户。

参考：

- [Granule](https://granule-project.github.io/granule.html)
- [Deriving graded modal types](https://granule-project.github.io/papers/deriving-graded-dist.pdf)

## 10. Scheme/Racket `dynamic-wind`

`dynamic-wind` 规定：

- 控制进入动态作用域时执行 `before`；
- 离开时执行 `after`；
- continuation jump 造成的离开与重新进入也遵守同一规则。

它是“动态清理语义跟随 continuation”的直接先例。

但它不等于 Cire 需要的完整资源语义：

- multi-shot 重新进入时，before/after 可能重复运行；
- 没有 Owner 收养 parked continuation；
- 没有静态 once disposition；
- 没有 generation revocation；
- 没有 cleanup failure aggregation。

参考：[R7RS `dynamic-wind`](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-8.html#TAG:__tex2page_sec_6.10)。

## 11. Rust 的位置

**不作为设计中心**

Rust 的非 `Copy` 值是理解 affine ownership 的一个现实例子，但用户提到 Rust 并不意味着 Cire 应照搬：

- 默认 move-only 变量；
- borrow checker 表面语法；
- `self` receiver 对象模型；
- RAII 作为所有 continuation 的解释。

Cire 第一版约束的是 handler 中的**恢复权使用量**，不是所有普通变量：

```text
k : Resume<A, R> with usage 0..1
```

它是 QTT/graded context 中的能力预算。以后若要给文件、socket 和锁提供通用 affine user type，可以复用部分数量系统；那是独立的资源安全扩展。

Rust 仅帮助说明：

```text
affine = 可以不用，但不能复制后使用两次
```

它不是 Cire one-shot continuation API 的模板。

## 12. 真正的差异化目标

各先例覆盖的是局部轴：

```text
Koka        effects + fun/ctl
OCaml       one-shot continuation + discontinue
Eff/Effekt  named capability + handlers
Effekt      capture set + region + multi-shot
ST          generative region
Scala 3     inferred capture checking
Idris/GHC/
Granule     quantitative/modal typing
Scheme      continuation-aware dynamic extent
```

Cire 的研究命题是：

> 能否在不产生全局所有权噪声的前提下，把 operation 的恢复权、continuation capture、动态 Owner/generation 与确定性 finalization 统一起来，并让普通库安全实现增量计算、结构化异步和 Wasm 宿主 callback？

这比“又一门 Koka 风格语言”更具体，也比宣称所有零件全新更准确。
