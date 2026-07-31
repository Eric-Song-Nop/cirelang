# Cire 语法和例子

> **Profile examples:** [`Cire-TR₀/2026-08-01`](../spec-status.md)。仓库当前
> 没有 parser；所有“状态”只表示规范状态。

这些例子展示当前 canonical surface。更系统的正负 case 在
[`examples/spec/`](../../examples/spec/)；仓库没有类型检查或运行时实现。

## 1. 普通函数

```moonbit
def[A] apply(
  value : A,
  transform : (A) -> A,
) -> A {
  transform(value)
}
```

泛型使用方括号，参数和返回类型的形状接近 MoonBit。纯函数不用写空 effect row。

状态：profile baseline；无实现。

## 2. 普通泛型和 effect 泛型分开写

Cire 保留 MoonBit 风格的普通泛型，并增加独立的 effect 泛型列表：

| 写法 | 表示什么 | 例子 |
|---|---|---|
| `[A]` | 普通类型参数 | `Int`、`String` |
| `![F]` | 单个 effect family | `Network`、`Read[Int]` |
| `![F : Reader[A]]` | 有 ability constraint 的 effect | `Read[Int]` |
| `![..E]` | 一整行 effect | `{}`、`{Network, app}` |
| `app : cap F` | 一个具体 capability 身份 | 调用者传入的 `F` 实例 |

先声明 ability 和具体 effect：

```moonbit
ability Reader[A] {
  fun read() -> A
}

effect Read[A] : Reader[A] {}
```

然后同时对普通类型、effect family、row 与 identity 多态：

```moonbit
def[A]![F : Reader[A], ..E] relay(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E} {
  body()
}
```

这里同时有四种抽象：

- `A` 对普通值类型多态；
- `F` 对满足 `Reader[A]` 的 effect family 多态；
- `E` 对剩余的整行 effect 多态；
- `app` 对一个具体但任意的 capability 身份多态。

`E` 可以实例化成包含匿名 effect 和具名 capability 的 row。例如高阶函数
收到一个使用 `{Network, app}` 的回调时，可以推导对应的 `E`。

如果只需要匿名 effect polymorphism，不传具体 capability：

```moonbit
def[A]![F : Reader[A], ..E] read_then(
  next : (A) -> Unit ! E,
) -> Unit ! {F, ..E} {
  next(F::read())
}
```

`effect Read[A]` 里的 `A` 仍然只是普通类型参数；它让
`Read : Type -> Effect`。同样，`abort[A] raise(...) -> A` 里的 `A`
是 operation 的普通返回类型多态，不是 effect row 多态。

状态：双形参列表、`ability`、`cap` 和 ability constraint 是 profile
baseline；无实现。

## 3. Effect 声明

```moonbit
pub(open) effect Choice {
  ctl[A] choose(value : A) -> A
}
```

四种 operation mode：

| mode | 简单含义 |
|---|---|
| `abort` | 后面的计算不再继续 |
| `fun` | 自动恢复一次，而且在尾部恢复 |
| `once` | handler 显式拿到 continuation，但最多使用一次 |
| `ctl` | handler 可以不恢复、恢复一次或恢复多次 |

状态：四种 mode 的声明与 clause lowering 是 profile baseline；无实现。

## 4. Effect row

匿名 effect family 直接写类型：

```moonbit
def fetch() -> Data ! {Network, Error[HttpError]} {
  Network::load()
}
```

具体 capability 直接写变量名：

```moonbit
def read_app(app : cap Read[Int]) -> Int ! {app} {
  app.read()
}
```

`{app}` 是源代码写法。下面的写法不合法：

```moonbit
def wrong(app : cap Read[Int]) -> Int ! {Read[app]} {
  app.read()
}
```

未来 parser 必须给出定向诊断，并建议把 `Read[app]` 改成 `app`。
`Read[app]` 只用于编译器解释
“这是 `Read` family 的具体实例”。

状态：closed row、open tail、family item、`{app}` 和 `RowExpr` 是 profile
baseline；无实现。

四种常见 effect annotation 要分清：

```moonbit
! E                     // 恰好是 row 变量 E
! {F}                   // 一个多态的匿名 effect
! {app}                 // 一个具体的具名 capability
! {F, app, ..E}         // 在 E 上增加 F 和 app
```

## 5. Handler 和 `with`

```moonbit
def run() -> Int {
  with handler Choice {
    ctl choose(value) as k => k.resume(value)
    return(value) => value
  }
  in {
    Choice::choose(1)
  }
}
```

- `handler Choice { ... }` 产生一个 handler value；
- `as k` 只用于需要显式 continuation 的 `once` 和 `ctl`；
- `with h in body` 把 `body` 作为 thunk 交给 scoped transformer。

从核心含义看：

```moonbit
with h
in {
  body()
}
```

若 `h` 是普通高阶 wrapper，近似于：

```moonbit
h(fn() {
  body()
})
```

若 `h` 解析为 effect handler，则不是普通 call：它降为
`freshprompt p in handle[p,h,...](body)`，并保存 fresh capability 与 source
origin。

连续 transformer 共用最后一个 `in`：

```moonbit
with retry(3)
with transaction(db)
in {
  save()
}
```

第一项最外层。`with` 常用于 effect handler，但普通接收 computation thunk
的 wrapper 也可以使用；`as app` 仍只建立 fresh named capability。

状态：只接受 canonical `with ... in ...` chain。Named binder、implicit
return synthesis 与 continuation binder 规则属于 profile baseline；无实现。

## 6. Trailing lambda 和 UI DSL

```moonbit
def view() -> View {
  Column(gap=8) {
    Text("Profile")
    users.for_each { user => UserRow(user) }
    Button("Save") { save() }
  }
}
```

它只使用普通调用、labelled argument 和 trailing lambda。Cire 不需要宏系统。

例如：

```moonbit
Button("Save") {
  save()
}
```

近似于：

```moonbit
Button("Save", fn() {
  save()
})
```

状态：调用、method、label、source-order 求值与 trailing-lambda 附着由
[完整表面语法](../surface-grammar.md)规定；`Column`、`Button` 是第一方 UI
契约示意，不是可运行框架。

## 7. Owner 和 capability capture

计划中的库式外观是：

```moonbit
Owner::scope { owner =>
  use(owner)
}

source.park(k, under = owner)
```

第二个 call 只在 sealed completion-source evidence下产生 terminal
`Transfers(ParkContractV2)`；它不会返回 `Unit`，也不会把 raw `Resume` 塞进
callback。Compiler必须理解 capability capture、escape、continuation
ownership、generation CAS 和 finalization。

状态：capture/escape/Owner boundary 是 profile baseline；仓库没有静态检查
实现。未来实现必须整组启用，不能只补少数特例。
