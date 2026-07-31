# Cire 设计基线与状态矩阵

> **Canonical profile:** `Cire-TR₀/2026-07-31`
>
> 本 profile 是仓库中语言设计、教程、例子和未来实现的共同基线。它是设计规范，
> 不是发布版兼容性承诺；其中明确标为参数或开放问题的部分仍可演化。仓库当前
> 不包含编译器、运行时或标准库实现。

## 1. 权威层级

同一问题出现冲突时，按以下顺序解释：

1. 本文确定 profile、文档职责和状态；
2. [完整表面语法](surface-grammar.md)确定 token、grammar、优先级和
   surface-to-Core elaboration；[语法设计说明](surface-syntax.md)解释动机，
   不得覆盖完整 grammar；
3. [多态设计](polymorphism-design.md)、[effect 与恢复模式](effects-and-resumptions.md)
   和 [capability/Owner](capabilities-and-finalization.md)确定各自领域的静态契约；
4. [Cire-TR₀ 形式化](temporal-reactivity-formalization.typ)确定 Core judgment、
   handler/temporal/Owner/incremental machine 和算法化检查；
5. 教程、简明文档、案例研究和架构文档解释上述规则，不得反向改变它们。

Parser、测试 fixture 或历史实现从不裁决语言设计。未来实现必须服从 profile；
发现冲突时应修改实现或提出 profile 变更，而不是把实现偶然行为写回规范。

## 2. 状态词

| 状态 | 含义 |
|---|---|
| **Profile baseline** | `Cire-TR₀/2026-07-31` 中下游可以依赖的当前设计 |
| **工作语法** | 已有唯一 grammar/elaboration，但拼写仍可在发布承诺前调整 |
| **参数化** | 语义边界已写清，profile 显式保留有限候选值 |
| **开放问题** | 尚无唯一规则，不得由实现自行选择并冒充规范 |
| **第一方契约** | 由普通语言构造和 sealed protocol 提供，不是新关键字 |
| **证明义务** | 已陈述待证明性质，不表示已经完成证明 |

“已进入 parser”“测试通过”不是设计状态。仓库当前实现状态只有一种：
**尚无实现**。

## 3. 语法与语义矩阵

| 构造 | 设计状态 | `TR₀` 规则 | 实现状态 |
|---|---|---|---|
| `def` / `fn` / `fun` | Profile baseline | 具名声明 / 匿名函数值 / effect mode 三分 | 无实现 |
| 普通类型形参 `[...]` | Profile baseline | 表面形参绑定；不等同于 Core 量化 | 无实现 |
| Effect/row 形参 `![...]` | Profile baseline | 与普通类型形参分域、分 kind | 无实现 |
| `ability → effect → cap F` | Profile baseline | 契约、名义 family、生成式实例分离 | 无实现 |
| `{F}` / `{app}` | Profile baseline | `Anonymous(F)` / `Named(app,F)` 不相等 | 无实现 |
| `RowExpr`、`|`、projection | 工作语法 | kinded normalization；literal 最多一个 tail | 无实现 |
| `abort/fun/once/ctl` | Profile baseline | 最大恢复权为 `0/1/1/ω`，允许向下收紧 | 无实现 |
| Handler 省略 `return` | Profile baseline | 先合成 identity，再做 exactly-one 检查 | 无实现 |
| `k.resume` / `k.finalize` | Profile baseline | disposition、world、cleanup 都进入判断 | 无实现 |
| `k.discontinue` | 不在本 profile | 等 error payload/world/cleanup contract 完整后再提案 | 无实现 |
| `with h as app in e` | Profile baseline | 生成式 scoped handler application；每次 installation fresh prompt；按 route 精确 row removal | 无实现 |
| 普通 `with h in e` | 工作语法 | `ScopedApply`；仅有 handler evidence 才降为 `handle` | 无实现 |
| Labelled argument | Profile baseline | positional 在前、label 唯一、按源码顺序求值 | 无实现 |
| Trailing lambda | Profile baseline | 附着到紧邻 call 的最后一个实参；换行不脱附 | 无实现 |
| Block item/result | Profile baseline | maximal-expression item；最后一个未加 `;` 的表达式为结果 | 无实现 |
| `defer` | 工作语法 + 证明义务 | LIFO intent 已定；capture/abort/park/close reduction calculus 尚未冻结 | 无实现 |
| `Next/delay/advance` | Profile baseline | generative clock + Fitch lock；`Next` 纯且可共享 | 无实现 |
| `FrameClock.yield` suspension | Profile baseline | 默认 `MaySuspend` + parking；只有 sealed runner refinement 可证明 `NoSuspend` | 无实现 |
| Task / Live / Signal / Event | 第一方契约 | 四种不同协议，无隐式 coercion | 无实现 |
| Owner transfer | Profile baseline + sealed source | `Transfers(ParkContract)`；generation-bound completion port + CAS + close-time finalize | 无实现 |
| Flow | Profile baseline | reachable path set 同时保留 `Returns` / `Aborts` / `Transfers`；sequence 只推进 return path | 无实现 |
| Operation secondary effects | Profile baseline | `SecondaryRow` 在 TR₀ 必须 closed；call row = argument row ∪ dispatch entry ∪ secondary sites；`Δ`/suspension 保留 site/route attribution | 无实现 |
| Interface `Q/Λ` | Profile baseline | versioned tagged V1 variants、alpha-normalized slots、独立 route；`Call` / `HandlerInstall` 两阶段 | 无实现 |
| General affine user values | 不在本 profile | 只追踪 resumption/authority 的受限 usage | 无实现 |
| 宏系统 | 不采用 | UI 使用普通调用、label 和 trailing lambda | 无实现 |

## 4. 不可混合的六个维度

每个 Core judgment 必须分别保存：

1. effect row：计算可能请求什么；
2. capture/provenance：结果或后缀保留了什么；
3. usage：one-shot authority 还可处置几次；
4. world/clock：计算跨越了哪个 logical world；
5. phase authority：Compute、Action、Commit 中允许做什么；
6. Owner/generation：运行时谁负责关闭，哪一代 callback 仍有效。

“row 已被 handler 消除”不能推出计算可 replay、可跨时钟、可复制或可发布。

## 5. Surface 到 Core 的固定边界

- Surface handler 没写 `return` 时，elaboration 合成
  `return(value) => value`；Core handler 始终恰好有一个 return clause。
- `fun` 产生隐藏的唯一尾 `resume`；`abort` 产生隐藏的 suffix finalization；
  `once` 的每条路径必须 `resume`、`finalize` 或转交一次；`ctl` 还要满足
  duplicability、cleanup replay 和 world-fork 义务。
- `with` 先保留有序 `ScopedApply`。只有 resolver/type checker 证明 operand
  是 handler 后，才生成
  `freshprompt p in handle[p,h,ι](let cap=capref(ι); body)`（匿名形式不含
  `cap` binder）、fresh identity 和按 prompt精确的 row/suspension removal。
- `k.discontinue(error)` 不属于 `TR₀`。失败由显式 abort effect 表达；取消由
  Owner/finalize 协议表达。
- Owner 转交只能通过 sealed completion source 产生
  `Transfers(ParkContract)`。它不是 `Unit`，会终止当前 path；source 保存
  `(owner,generation,claim)` 并只向宿主暴露 completion port。completion、
  cancel 与 close 竞争同一个 CAS；普通 callback、many-call closure 或容器
  不能捕获 raw `Resume`。
- Public effect row 是 attributed demand `Δ` 的擦除。Handler 只移除路由到
  自己 prompt 的 site；同 family forwarding、named identity 和 secondary row
  都不能用 raw set subtraction 近似。

## 6. 证明状态

形式化文档中的 determinism、soundness、preservation、no-early-advance、
one-shot disposition、identity nonescape、Owner safety、incremental
replacement 与 from-scratch consistency 都是**定理陈述或证明义务**。
除 PEG 的局部结构论证外，本 profile 不宣称已有机械化证明。

机械化顺序为：

1. surface grammar 与 n-ary-to-unary Core elaboration preservation；
2. CBV Core operational semantics；
3. row + attributed demand + handler + one-shot；
4. world/clock；
5. phase + Owner/park CAS；
6. incremental replacement。

## 7. 未来实现的入口条件

重新开始实现前必须具备：

- [完整表面语法](surface-grammar.md)及其 elaboration；
- `examples/spec/` 的正负 conformance corpus；
- 每个 case 的 type、row、world、capture、usage、Owner obligation 或 rule id；
- 能以 versioned `ParametricObligations` / `LatentSites` 序列化 `Q/Λ`、
  handler certificate 和 cleanup contract 的 interface schema；
- 不把旧 parser fixture 当作规范的评审流程。
