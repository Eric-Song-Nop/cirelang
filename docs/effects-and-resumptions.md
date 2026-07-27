# 代数效应与恢复模式

## 1. 目标

**已决定**

效应系统不仅描述“程序可能执行什么 operation”，还要限制 handler 对 operation 后续控制流拥有多大权力。

例如：

```text
let answer = choose()
answer * 10
```

执行到 `choose()` 时，剩余计算可以概念化为：

```text
k(answer) = answer * 10
```

不同 operation 对这个 `k` 有完全不同的要求：

- 错误不会继续执行它；
- 环境读取会自动继续一次；
- `await` 会保存它，并在未来至多继续一次；
- 搜索可能用不同答案继续多次。

语言应直接表达这些差异。

## 2. Effect row 与具名 capability

### 2.1 Effect row

**已决定 effect-row 语义；双列表是尚未实现的工作语法**

```moonbit
fn[A, B]![..E] map_effectful(
  xs : Array[A],
  f : (A) -> B ! E,
) -> Array[B] ! E
```

Effect polymorphism 让效应能够穿过高阶函数、组合器与模块抽象，而无需在每一层手写转发代码。

Effect row 表达的是尚未被当前 handler 消除的操作集合：

```moonbit
fn load(url : Url) -> Data
  ! {Network, Async, Error[HttpError]}
```

普通参数和 effect 参数使用双列表，需要区分三个 kind、ability constraint
和一个 term identity：

```text
A                       : Type
F                       : Effect
E                       : EffectRow
Reader[A]               : Effect -> Constraint
app : cap F             : capability term
```

- `A` 是普通参数多态；
- `![F]` 代表一个完整的原子 effect；
- `![F : Reader[A]]` 进一步提供可调用 operation 的 ability evidence；
- `![..E]` 代表零个或多个 effect/capability row item；
- `app` 是一等 term，同时具有不可伪造的 singleton identity。

`! E` 表示结果恰好携带 `E`，`! {F, app, ..E}` 表示在 `E`
上增加一个原子 effect 和一个具名 capability。

`F` 在 row 中表示匿名 effect demand；`app : cap F` 允许同一个函数对
capability 所属 family 和具体 identity 同时多态：

```moonbit
fn[A]![F : Reader[A], ..E] relay(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E} {
  body()
}
```

`cap F` 明确表示 named capability value；它在 Core 中携带 family、
singleton identity、Region 和 origin。`Reader[A]` ability 让泛型代码既能
使用匿名 `F::read()`，也能使用具名 `app.read()`。

`effect Read[A]` 中的 `[A]` 只是普通类型参数，它建立
`Read : Type -> Effect`；operation 的 `[A]` 也只是普通参数多态。它们都
不能替代 `![F]`、`![F : Reader[A]]` 或 `![..E]`。

Polymorphic operation 的 handler clause 不重新声明同名 `[A]`。Typechecker
从 operation signature 打开 fresh type skolem，再检查 clause、结果和
continuation；这样 `abort[A] raise(...) -> A` 不会因为 handler 实现而偷偷
固定成某个普通类型。

### 2.2 具名 capability 与 identity polymorphism

**已决定 identity 语义与 `{app}` row 写法；`cap F` 仍是工作关键词**

种类相同的 effect 可以有多个具体实例：

```text
Read[app]       // 只用于诊断展开
Read[preview]   // 只用于诊断展开
```

源程序不写上面的诊断形式，而是直接绑定并使用 capability term：

```moonbit
fn[A]![F : Reader[A], ..E] use_reader(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E} {
  body()
}
```

这个函数既对普通类型 `A`、family `F` 和额外 row `E` 多态，也对参数
`app` 所代表的
具体 identity 多态。后者不是普通类型参数：每次调用可以传入不同实例，
但函数体中的 `{app}` 精确引用本次 value binder。

这与 named handler 的核心模型一致：name 是由普通 lambda 绑定的一等值；
fresh handler action 则由编译器按 rank-2 generativity 检查。源语言第一版
不引入 `[app : Read[A]]` 或显式 `forall app`。

`..E` 本身也能实例化为包含 named capability 的 row。例如调用
`map_effectful` 时，回调使用 `app.read()`，编译器可以推导
`E = {app}`。因此 row polymorphism 不会在遇到具名实例时退化成只能列举
固定 family 的系统。

Ability、associated effect/row、row predicate、higher-kinded effect 与
`fresh` quantifier 的完整工作设计见
[多态与 effect abstraction 工作设计](polymorphism-design.md)。

`app` 和 `preview` 不是可以伪造的字符串，而是 handler 创建或参数传入的
identity。一个函数即使能够执行某种 `Write` operation，也只有拿到对应
capability 后才能修改该实例。

这带来三个互补的静态信息：

```text
ε  effect row
   运行时仍会向上下文请求什么

χ  capture set
   值已经固定携带了哪些具体 capability

φ  authority/phase
   当前作用域实际授予了哪些操作权限
```

局部 handler 可以消除 `ε` 中的 effect，却不能凭空制造另一个实例的 authority。这是具名 capability 相较于只有 effect row 的关键价值。

普通 let-polymorphism 不能抹掉这一 identity。闭包若捕获 `app`，其 capture
信息仍包含 `app`；把匿名 effect 在 handler 中消除，也不会把固定 capability
伪装成与任意实例都兼容的普通泛型值。具体 generalization rule 仍要和
`ctl`、mutation、capture 与 Region 一起形式化。

## 3. 四种表面恢复模式

**已决定**

```text
effect Error<E> {
  abort raise<A>(error: E) -> A
}

effect Async {
  once await<A>(task: Task<A>) -> A
}

effect Reader<R> {
  fun ask() -> R
}

effect Choice {
  ctl choose<A>(values: List<A>) -> A
}
```

| 关键词 | 是否显式得到 `k` | 恢复规则 | 典型用途 |
|---|---:|---|---|
| `abort` | 否 | 零次 | 错误、不可恢复的取消 |
| `once` | 是 | 至多一次；可以保存到未来 | `await`、yield、一次性宿主完成 |
| `fun` | 否 | 恰好一次，且自动尾恢复 | Reader、动态绑定、普通函数式 operation |
| `ctl` | 是 | 零次、一次或多次 | 搜索、回溯、协程、通用控制 |

### 3.1 `fun`

`fun` 与 Koka 的 tail-resumptive operation 保持同一核心语义：

```text
fun ask() => body
```

概念上相当于：

```text
ctl ask(k) =>
  let value = body
  resume k value
```

但前者不向 handler 暴露 `k`，并保证恢复恰好一次且处于尾部。因此编译器通常可以把它实现得接近普通函数调用，而不真正捕获续体。

### 3.2 `ctl`

`ctl` 也与 Koka 的一般控制语义一致：

```text
ctl choose(k) =>
  resume k False ++ resume k True
```

但 `ctl` 不等于 multi-shot。它表示 handler 拥有一般控制权，因此下面三种实现都可能：

```text
// 零次：放弃后续
return fallback

// 一次
resume k value

// 多次
resume k left ++ resume k right
```

### 3.3 `abort`

`abort` 是 zero-shot 的静态模式。handler 不得到恢复权，因此调用点之后的计算不会继续。

它不是把返回类型强制写成 `Never`：operation 可以是多态返回，因为调用者无论期待什么类型，后续都不会被恢复。

### 3.4 `once`

`once` 填补 Koka `fun` 与一般 `ctl` 之间的重要空档：

- handler 显式得到恢复权；
- 可以把它保存到异步 callback；
- 可以在非尾位置决定如何处置；
- 但所有运行路径上至多处置一次。

概念示例：

```text
once await(task; k) =>
  park k under task.owner
```

将来只能发生一种结局：

```text
resume k value
discontinue k error
finalize k
```

三者都消耗同一项恢复权。

## 4. 模式之间的关系

四个模式不是四个互不相关的标签，而是按 handler 控制能力形成偏序：

```text
             ctl
              │
            once
           /    \
         fun    abort
```

含义是：

- `abort` 是 `once` 中使用零次恢复权的特例；
- `fun` 是 `once` 中恰好一次且尾恢复的特例；
- `once` 是一般控制中至多恢复一次的子集；
- `ctl` 允许全部控制行为。

operation 声明给出 handler 被允许拥有的**最大控制能力**；具体 handler 可以采用更严格的 clause：

```text
effect Choice {
  ctl choose() -> Bool
}

handler RandomChoice {
  fun choose() =>
    random_bool()
}

handler AllChoices {
  ctl choose(k) =>
    resume k False ++ resume k True
}
```

因此，概念上的兼容关系是：

| operation 声明 | handler 可采用 |
|---|---|
| `abort` | `abort` |
| `fun` | `fun` |
| `once` | `abort`、`fun`、`once` |
| `ctl` | `abort`、`fun`、`once`、`ctl` |

`fun` 与 `abort` 彼此不可替代：一个保证继续，另一个保证不继续。

## 5. 内部数量系统

**已决定**

复杂数量记号只属于核心演算和高级泛型 API：

```text
abort = Mode(usage = 0,    position = arbitrary)
once  = Mode(usage = 0..1, position = arbitrary)
fun   = Mode(usage = 1,    position = tail)
ctl   = Mode(usage = 0..ω, position = arbitrary)
```

普通 effect 声明只使用四个关键词。只有实现通用 handler 组合器时，才可能看到类似：

```text
Resume<q, A, R>
```

其中：

- `q` 是恢复能力的数量 grade；
- `A` 是 operation 调用点期待的返回值；
- `R` 是整段 handled computation 的最终结果。

仅靠 QTT 的 `0 / 1 / ω` 不足以表达 `fun`，因为“恰好一次”与“必须在尾位置”是两个独立约束。

## 6. `once` 的静态检查

### 6.1 顺序组合

下面不合法：

```text
once op(k) =>
  resume k 1
  resume k 2
```

因为顺序路径的使用量相加，结果超过 `0..1`。

### 6.2 互斥分支

下面合法：

```text
once op(k) =>
  match result {
    Ok(value)  => resume k value
    Err(error) => discontinue k error
  }
```

代码中出现两次 `k`，但任意一次执行只进入一个分支。

### 6.3 闭包捕获

如果闭包捕获 `once k`，闭包自身就不能成为可任意调用的值：

```text
let callback = fn(result) {
  resume k result
}
```

编译器需要把 `k` 的使用预算传递到闭包调用能力中。一个 many-call callback 不能捕获 `once k`。

具体闭包表面语法尚未决定；这里描述的是类型规则，不代表要公开 `fn[0..1]` 之类语法。

### 6.4 转交与 clause 退出

如果 clause 同步离开时 `k` 既未处置也未转交，语言自动 finalize：

```text
once op(k) =>
  return fallback

// 等价地承担：
// finalize k
// return fallback
```

如果要跨越 clause 生命周期保存 `k`，必须把处置责任交给受管理的 Owner：

```text
park k under owner
```

此后由 Owner 保证：

- 正常完成时恢复；
- 失败时 discontinue；
- Owner 关闭时 finalize。

`park/adopt` 的最终表面语法仍是开放问题，但“裸 one-shot 续体不能无主逃逸”是设计约束。

## 7. Multi-shot 与捕获环境

`ctl` 允许同一后缀执行多次，因此续体捕获的内容必须支持这种行为：

```text
let file = open_file("log")
let choice = choose([1, 2])
write(file, choice)
```

如果 `choose` 的 handler 恢复两次，后缀会两次使用同一个独占文件能力。语言不能假装这自然安全。

可接受的处理方式包括：

- 拒绝捕获不可复制、不可重放的能力；
- 每条恢复分支重新获取独立资源；
- 捕获显式可共享、并发语义明确的 capability；
- 对已知采用更弱 clause 的 handler 做安全的词法专门化。

最后一项涉及“按 operation 声明的最大模式检查，还是按词法已知 handler 的实际模式检查”，目前仍是开放的类型系统问题。

## 8. 多次恢复与局部可变状态

**开放问题**

multi-shot continuation 与普通局部 `var` 的语义必须明确，不能留给实现偶然决定。候选选择包括：

- 各次恢复共享同一个 cell；
- 捕获时复制 store，每个分支得到自己的版本；
- 只允许 generation-local mutation，重放从捕获快照重新开始；
- 包含不可复制 mutation capability 时禁止 multi-shot。

响应式计算更倾向于：

- 普通值默认不可变；
- 局部 mutation 受控且不能逃出 generation；
- 跨重算持久状态必须显式属于 Owner；
- 外部 mutation 通过具名 capability 和 effect row 约束。

需要用原型验证其可用性与编译成本。

## 9. Handler、续体与清理

恢复模式不能脱离 finalization 语义：

| 动作 | 控制结果 | 清理结果 |
|---|---|---|
| `resume k v` | 在操作点返回 `v` 并继续 | 重新进入续体携带的动态清理段 |
| `discontinue k e` | 在操作点抛出/注入 `e` | 正常展开该控制分支 |
| `finalize k` | 永不继续该分支 | 展开该分支的 cleanup |
| `park/adopt k owner` | 当前 clause 放弃直接处置权 | 清理责任转移给 Owner |

对于 multi-shot，每次恢复造成的动态进入/退出必须与捕获环境的可重放性一致；含一次性 cleanup 的续体不能被无条件复制。

完整生命周期规则见 [Owner、Region、capture set 与结构化清理](lifetimes-and-finalization.md)。

## 10. 尚未冻结的表面语法

以下均未决定：

- operation declaration 与 handler clause 的最终参数分隔形式；
- `resume k value`、`resume(k, value)` 或其他调用形式；
- `discontinue`、`finalize` 的正式名称；
- `park/adopt` 的名称与所有权转交语法；
- one-call/many-call closure 是否需要显式标记；
- 高级 `Resume<q, A, R>` 是否向普通用户公开；
- `val` 是否作为正式 operation 形式保留。

已经冻结的是四种日常恢复模式的名字与核心含义，而不是整套具体语法。
