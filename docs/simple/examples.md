# Cire 语法和例子

这些例子展示当前表面语法。标为“parser 已支持”的部分已经有语法测试，
但还没有类型检查和运行时语义。

## 1. 普通函数

```moonbit
fn[A] apply(
  value : A,
  transform : (A) -> A,
) -> A {
  transform(value)
}
```

泛型使用方括号，参数和返回类型的形状接近 MoonBit。纯函数不用写空 effect row。

状态：parser 已支持函数、类型参数、函数类型、调用和 block。

## 2. Effect 声明

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

状态：四种 mode 的声明和 handler clause 都已进入 parser。

## 3. Effect row

匿名 effect family 直接写类型：

```moonbit
fn fetch() -> Data ! {Network, Error[HttpError]} {
  Network::load()
}
```

具体 capability 直接写变量名：

```moonbit
fn read_app(app : Read[Int]) -> Int ! {app} {
  app.read()
}
```

`{app}` 是源代码写法。下面的写法不合法：

```moonbit
fn wrong(app : Read[Int]) -> Int ! {Read[app]} {
  app.read()
}
```

Parser 会给出定向诊断，并建议把 `Read[app]` 改成 `app`。`Read[app]`
只用于编译器解释“这是 `Read` family 的具体实例”。

状态：closed row、`..Eff` open tail、family item 和 `{app}` 都已支持。

## 4. Handler 和 `with`

```moonbit
fn run() -> Int {
  with handler Choice {
    ctl choose(value) as k => k.resume(value)
    return(value) => value
  } {
    Choice::choose(1)
  }
}
```

- `handler Choice { ... }` 产生一个 handler value；
- `as k` 只用于需要显式 continuation 的 `once` 和 `ctl`；
- `with h { body }` 把 `body` 作为 thunk 交给 handler。

从核心含义看：

```moonbit
with h {
  body()
}
```

近似于：

```moonbit
h(fn() {
  body()
})
```

这只是帮助理解的展开。编译器后续仍会在 HIR 中保存 handler、fresh
capability 和 source origin，不能把它们当成完全普通的库调用。

状态：handler、`with`、named capability binder、`return` clause 和
continuation binder 的定向错误已经进入 parser。

## 5. Trailing lambda 和 UI DSL

```moonbit
fn view() -> View {
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

状态：调用、method call、labelled argument、label punning、嵌套 trailing
lambda，以及跨换行和注释的附着都已进入 parser。这里的 `Column`、`Button`
只是未来 UI 库的示意，还没有可运行的 UI 框架。

## 6. Owner、Region 和 capture

计划中的库式外观是：

```moonbit
Owner::scope { owner =>
  use(owner)
}
```

但它不会只是一个普通库函数。编译器必须理解 Region、capture、escape、
continuation ownership 和 finalization。

状态：核心设计方向已确定，静态规则尚未实现。我们会等整套规则一致后再启用，
不会先做几个不完整的“安全检查”。
