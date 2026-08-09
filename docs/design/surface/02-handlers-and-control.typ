#import "../shared.typ": *

== Operation 调用 <surface-5>

*Profile baseline*

不增加 `perform` 关键字。调用沿用普通方法和限定名外观：

```moonbit
let choice = Choice::choose([false, true])
let value = app.read()
```

- `Choice::choose(...)` 由类型环境解析到当前匿名 `Choice` handler；
- `app.read()` 明确选择 named capability `app`，并给 row 贡献 `{app}`；
- parser 只建立普通的 qualified call 或 method call；resolver/typechecker 决定它是否是 effect operation。

这样 parser 不必提前知道某个名称是不是 operation，LSP 的未解析语法树也保持完整。

== Handler 与 clause <surface-6>

=== Handler expression <surface-6-1>

*Profile baseline*

Handler 是值。一个 handler expression 接受 handled computation 的 thunk：

```moonbit
let all_choices = handler Choice {
  ctl choose(_values) as k => {
    let left = k.resume(false)
    let right = k.resume(true)
    left + right
  }

  return(value) => value
}
```

`handler EffectType { ... }` 建立 handler value，而不是立即运行其后的代码。

=== Continuation binder <surface-6-2>

*已决定*

`once` 和 `ctl` clause 使用 `as k` 显式绑定 continuation：

```moonbit
once await(task) as k => {
  task.completion_source.park(k, under = task.owner)
}

ctl choose(values) as k => {
  values.map { value => k.resume(value) }
}
```

`abort` 与 `fun` clause 不允许 `as k`，因为它们不向用户暴露 continuation：

```moonbit
abort raise(error) => report(error)
fun ask() => current_environment
```

Continuation disposition 使用方法外观：

```moonbit
k.resume(value)
k.finalize()
```

这些不是可覆盖的普通方法。resolver 将它们识别为 `Resume` 与 `Finalize`，
因此不能通过定义同名 method 改变控制语义。`k.discontinue(error)` 不属于
`Cire-v1.0`：失败由显式 abort effect 表达，取消由 Owner/finalize 协议表达。

`source.park(k, under = owner)` 只在 operand 带 sealed completion-source
evidence 时降为 Core T-Park。它消耗当前 clause 的处置责任，产生
`Transfers(ParkContractV2)` 并终止当前 path；它不是返回 `Unit` 的普通容器
插入函数。source/port只传 operation result `A`，完整 resumption保存
`A -> B` answer transform；宿主 callback不能捕获 raw `Resume`。

=== Return 与 forwarding <surface-6-3>

*Profile baseline*

```moonbit
handler Reader[Int] {
  fun ask() => 42
  return(value) => value
}
```

- 省略 `return` 时，Surface elaboration 先合成
  `return(value) => value`；Core exactness checking 因而始终看到恰好一个
  return clause；
- 不属于当前 handled effect 的 operation 自动向外层 handler 转发；
- 当前 effect 中没有 clause 的 operation 默认产生穷尽性诊断；
- v1 没有显式 forwarding source clause；缺少当前-family clause是穷尽性错误，
  非当前-family operation按 validated `ForwardContract` 自动向外层转发；

v1 handler 是 lexical deep handler。Shallow handler 不进入 v1。

=== Inline handler derived form <surface-6-4>

#metadata("R06-inline-handler") <rule-r06-inline-handler>

v1 只有一个 inline derived form：

```cire
with Logger {
  fun log(message) => emit(message)
  return(value) => value
} as logger in body(logger)
```

它在 Normalize Surface 阶段唯一展开为：

```cire
with (handler Logger {
  fun log(message) => emit(message)
  return(value) => value
}) as logger in body(logger)
```

它复用 full handler 的 `HandlerMember`、mode、pattern、continuation、return、scope
与 omitted-return规则，不新增 Core/wire node。Clause mode绝不能省略；完整但缺 mode
的 clause head只产生 `handler-clause-mode-required`。`Type { field: value }`、空/
不完整 body 与普通 trailing lambda必须走 ordinary expression fallback，不能被 inline
recovery抢走。

Full/derived pair在擦除 source-form/origin metadata并对 fresh prompt alpha-normalize
后，normalized Surface HIR、Kernel、row/flow/capture/usage/phase obligations必须相同；
origin golden则分别保留 direct form与 `InlineHandlerExpansionV1`。Formatter保留用户
原 form，不自动互转。

== 本质形式与语法糖 <surface-7>

唯一 frontend pipeline 是：

```text
UTF-8 source
  -> lossless token stream -> lossless CST -> syntax validation
  -> resolved Surface HIR -> normalized Surface HIR
  -> signature/kind-checked Surface HIR
  -> evidence-indexed Kernel HIR
  -> typed Core + Q/Λ/interface artifacts
```

Lex/Parse不读取 expected type或 symbol table；Syntax只处理 token-level shape；
Resolve选择 exact namespace/kind identity；Normalize只展开 inline handler、omitted
return、interpolation、derive、while/for 与 with right-fold；Signature/Kind选择唯一
callable/member/intrinsic signature、label/default table、direct capability binder与
sealed evidence；Kernel才生成 source-order temporaries、call-entry tuple、fresh prompt/
runtime capability与 privileged nodes。typed-Core stage只能增加 judgment evidence，
不得 reparse、重排求值或选择另一个 lowering。

CST 和 Surface HIR 保留用户原始写法。所有 synthesized Kernel node带
`ElaborationOriginMapV1` entry；interpolation/finally/derive使用
`SealedIntrinsicV1`，while/for/numeric/assignment evaluation nodes使用
`SourceOrderTemporaryV1`。同一 normalized node不得由不同 frontend获得不同
origin/binder/site allocation。

=== `with` 是 scoped computation application 的糖 <surface-7-1>

*已决定*

`with` 不表示一个额外的核心控制构造。它把一组有序的 scoped computation
transformer 应用到 `in` 后面的计算。Effect handler 是最重要的 transformer，
但不是唯一来源；普通高阶函数只要接收一个 computation thunk，也可以使用同一
外观。

```moonbit
with all_choices
in {
  Choice::choose([false, true])
}
```

降为：

```moonbit
all_choices(fn() {
  Choice::choose([false, true])
})
```

匿名 entry 的类型形状可以概括为：

```text
body       : () -> A ! Ein
transformer(body) : B ! Eout
```

它不要求 `A = B` 或 `Ein = Eout`。Handler 可以消除 effect、加入 effect，
或通过 `return` clause 改变结果类型。

`with` 语法本身不授予 wrapper 任意复制 action 的权限。Wrapper 能否零次、
一次或多次调用 thunk，仍由 action function 的 usage/capture 类型与普通调用
规则决定；具名 `ScopedApply` 经 Kernel handler lowering 后还要满足
generativity 和 capability escape 检查。

Evaluation order 以展开后的普通调用为准：先求值当前最外层 transformer
expression，再构造包含其余 chain 的 thunk，然后调用它。内层 operand 不会
预先求值；只有外层 transformer 调用 action thunk 时才求值。外层若调用
action 多次，内层 operand 也会随之重新求值多次。

连续的 `with` entry 共用链末尾的一个 `in`：

```moonbit
with retry(3)
with transaction(db)
with trace("save")
in {
  save_order(order)
}
```

第一项是最外层，最后一项最靠近 computation：

```moonbit
(retry(3))(fn() {
  (transaction(db))(fn() {
    (trace("save"))(fn() {
      save_order(order)
    })
  })
})
```

因此 entry 顺序具有语义。`with retry(3)` 放在 `with transaction(db)` 外面，
表示每次 retry 可以建立新的 transaction；调换顺序则表示同一个 transaction
包住全部 retry。

这里 `retry(3)`、`transaction(db)` 和 `trace("save")` 都求值得到
transformer value；`with` 再把 action thunk 传给该值。它不会偷偷把 action
追加成原调用的普通最后一个 argument。

换行不参与 chain 语义；下面两种 token sequence 等价：

```moonbit
with retry(3) with transaction(db) in save_order(order)
```

```moonbit
with retry(3)
with transaction(db)
in save_order(order)
```

Formatter 对多 entry chain 默认每行放一个 `with`。

每层都写 `in` 仍然是合法的显式嵌套：

```moonbit
with retry(3) in
  with transaction(db) in
    save_order(order)
```

它由两个单 entry `WithChain` 构成，不是一个双 entry chain。规范写法对连续
组合只在末尾写一次 `in`；formatter 保留用户明确写出的嵌套边界和其上的
comment，不擅自把两棵 CST 合并。

Named capability binder 把生成式 action 参数写得更自然：

```moonbit
with read_42 as app
in {
  read_app(app)
}
```

降为：

```text
ScopedApply(
  transformer = read_42,
  binder = app,
  body = read_app(app),
)
```

若 transformer 类型证明它是 handler application，Kernel 再降为
`freshprompt p` + `handle[p,...]`，并用 `capref(ι)` 绑定 `app`。普通
transformer 降为高阶调用且没有 named capability binder。Handler 的类型为
`app` 创建 fresh generative identity；这里不能把 `app` 当作普通未受约束的
函数参数。

在同一个 chain 中，entry 创建的 identity 对后续 entry operand 和最终
computation 可见，但不在创建它的 operand 内可见：

```moonbit
with open_database(config) as db
with traced_database(db)
in {
  db.query("select * from users")
}
```

Inline handler：

```moonbit
with handler Read[Int] {
  fun read() => 42
} as app
in {
  read_app(app)
}
```

先保留为 scoped application：

```text
let generated_handler = handler Read[Int] {
  fun read() => 42
}
ScopedApply(generated_handler, binder = app, body = read_app(app))
```

临时绑定只用于说明求值顺序，编译器不必实际生成可观察的名称。

`with` operand 不要求是 `handler E { ... }` 产生的值。下面这些库式
computation wrapper 都可以使用同一语法：

```moonbit
with timeout(200.ms)
with trace("render")
with ui_scheduler
in render_page()
```

它们可以由 effect handler 实现，也可以只是普通高阶函数。类型检查只要求
每个 entry 能接收当前内层 computation，并产生下一层 computation；不同 entry
可以消除 effect、加入 effect 或改变结果类型。

`as name` 不随之泛化成普通 binding。它只允许用于能建立 fresh named
capability 的 handler application。普通运行时值继续使用普通 API 和 trailing
lambda：

```moonbit
Owner::scope { owner =>
  consume(owner)
}
```

`with` 也不复用于 record update、trait/effect constraint、普通对象 receiver
scope、import 或 match clause。它始终只表示“用 scoped transformer 包住一段
computation”。

=== Trailing lambda <surface-7-2>

#metadata("R06-call-assembly") <rule-r06-call-assembly>

*已决定*

Cire 不做宏系统。UI DSL 依靠普通函数、labelled argument 和 Kotlin/Koka 风格 trailing lambda：

```moonbit
Column(gap=8) {
  Text("Profile")
  Button("Save") {
    save()
  }
}
```

降为：

```moonbit
Column(
  gap = 8,
  body = fn() {
    Text("Profile")
    Button("Save", body = fn() {
      save()
    })
  },
)
```

带参数的 trailing lambda：

```moonbit
users.for_each { user =>
  UserRow(user)
}
```

降为：

```moonbit
users.for_each(fn(user) {
  UserRow(user)
})
```

规则是：

- 一个 trailing lambda 只能作为调用的最后一个实参；
- `callee(args) { ... }` 与 `callee { ... }` 都允许；
- `{ params => body }` 提供参数，`{ body }` 表示零参数 thunk；
- call 与 trailing block 之间的 whitespace、newline 或 comment 不打断附着，
  因而 formatter 可以安全换行；若要把 call 与后续独立 block 分开，必须写
  显式 `;`；
- 它不获得 AST、调用点源码或卫生名称访问权；
- 需要 lexical site 的第一方 API 必须使用编译器定义的稳定 site 机制，而不是偷偷实现宏展开。
- signature resolution 后它只填排除 implicit receiver 后 slot 最大的 final formal，
  绝不搜索“最后一个未填槽”；该 slot已提供时报 duplicate（先于 callable/type error），
  有 default时 trailing覆盖 default，非 callable时报
  `trailing-lambda-target-not-callable`；
- labelled/default call只允许 exact static callable metadata；只剩 structural function
  type的 value不能使用 label并报 `named-call-requires-static-signature`。

`in` 已经明确分开 operand 区和 computation，因此 `with` operand 可以正常
包含 trailing lambda：

```moonbit
with make_handler(1) {
  configure()
}
in {
  run()
}
```

这里第一个 block 属于 `make_handler(1)`；`in` 后面的 block 才是被包裹的
computation。若 operand 自身是一个顶层 `with` expression，仍需用括号明确其
边界：

```moonbit
with (
  with configure_runtime
  in make_handler()
)
in {
  run()
}
```

=== 不属于语法糖的构造 <surface-7-3>

以下语义不能降为不受编译器理解的普通库调用：

- handler expression 与 operation dispatch；
- `k.resume`、`k.finalize`；
- fresh named capability identity；
- continuation usage/capture checking；
- sealed source park 的 terminal responsibility transfer；
- sealed `BuildString` 与 `@control::finally`；
- nominal derive、state-threaded `for` 与 numeric defect checks。

它们可以有普通调用的表面外观，但 HIR 必须保留专用节点和 source origin。

== Named capability capture 与 Owner <surface-8>

=== Handler binding scope <surface-8-1>

*已决定*

Named capability 的有效范围由 handler application 的 binder 决定。第一方
Owner API 可以保持库式外观：

```moonbit
Owner::scope { owner =>
  let cell = owner.cell(0)
  ...
}
```

Surface HIR 先保留中立的 scoped application：

```text
ScopedApply {
  transformer
  optional_binder
  body
}
```

只有类型检查确认 transformer 是 handler 后，Kernel HIR 才产生
`FreshPrompt + Handle + CapRef`；普通 transformer继续使用 closure call。
编译器负责：

- 为 capability binder 生成 fresh、不可伪造的 identity；
- 推导闭包、handler 与 continuation 的 capture；
- 检查 return、closure、aggregate 与 storage boundary 上的 escape；
- 检查 continuation 被 sealed source park 后的唯一处置责任；
- 把静态 capability identity 与运行时 Owner/generation 区分开。

源码只使用 `{app}`。Capture 结果保存在 HIR、接口摘要和诊断中。

=== Capture safety gate <surface-8-2>

*Profile baseline*

Capture inference 与传递 closure、capability escape、`once` usage、multi-shot
replayability、mutable-place capture、handler-mode weakening、Owner park/CAS 与
finalization responsibility 全部属于 accepted-program WF。Checker不得 feature-gate
其中子集或在缺少 evidence 时接受。ordinary mutable place的 exact boundary见 #ref(<surface-2-6>)；
一般 affine value calculus仍不进入 v1。

=== PackedNext 的 sealed scope <surface-8-3>

*已决定*

Cire-v1.0 不增加一般 existential 或 rank-2 类型语法。跨越 generative FrameClock
lifetime 使用 shared `PackedNext[A]` 与三个 sealed first-party origin：

```cire
let packed = @temporal::pack_next(under = owner) { frame =>
  delay[frame] { 42 }
}

let opened = @temporal::try_with_packed_next(packed) { frame, pending =>
  frame.yield()
  advance(pending)
}

let receipt : CloseReceipt[DisposeReport] = @temporal::dispose(packed)
```

`try_with_packed_next` 的 result是 `Option[B]`：Closing/Closed acquisition返回
`None`；成功 body的 Returns映射为 `Some`；Aborts/Transfers保持 terminal tag，
但必须先证明 private frame/Next/Later/lease没有通过任何 outward evidence逃逸，
再 exactly-once release。Handle可复制，alias共享当前形式化的
`Building|Open|Closing|Closed` cell、construction lease、monotone lease ordinal、
唯一 cleanup reservation与 close cell；dispose 是幂等 NoSuspend request，重复调用
返回同一 `CloseReceipt[DisposeReport]`。最后一个 construction/open lease release
后才 physical close并 resolve receipt；任何 terminal path保留原 flow tag并归档 report。
三段 block是 contextual HIR，不是用户可声明的普通 callback
contract；同名用户函数无 privileged lowering。
