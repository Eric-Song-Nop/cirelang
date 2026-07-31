# 09　具名 capability

> 本章示例属于 [`Cire-TR₀/2026-08-01`](../spec-status.md) 教程基线。

## 1. 先记住一句话

具名 capability 是：

> 一个显式传递的值，它指向当前 `with` 安装的某一个具体 handler。

```cire
app.read()
```

表示“向 `app` 指向的那个 handler 请求 `read`”，而不是“向当前最近的
`Read` handler 请求 `read`”。

对应的 effect row：

```cire
! {app}
```

表示这段计算精确依赖 `app`。如果现在只记住“显式 receiver + 精确 effect
依赖”，就已经抓住了 named capability 的主要用途。

## 2. 先看普通的匿名 effect

```cire
effect Counter {
  fun get() -> Int
  fun set(value : Int) -> Unit
}

def increment() -> Unit ! {Counter} {
  let value = Counter::get()
  Counter::set(value + 1)
}
```

安装一个 counter handler：

```cire
with make_counter(0)
in {
  increment()
}
```

`Counter::get()` 没有显式 receiver。它使用当前上下文中最近的 `Counter`
handler：

```text
increment()
  └── Counter::get()
        └── 当前最近的 Counter handler
```

这很像一个由词法上下文提供的隐式参数。一个作用域只需要一个 Counter 时，
匿名 effect 简单而清楚。

## 3. 两个相同 effect 实例的问题

现在同时打开两个账户：

```text
checking  余额 100
savings   余额 20
```

两者提供完全相同的操作：

```cire
ability Account {
  fun balance() -> Int
  fun withdraw(amount : Int) -> Unit
  fun deposit(amount : Int) -> Unit
}

effect BankAccount : Account {}
```

如果只使用匿名调用：

```cire
BankAccount::withdraw(10)
BankAccount::deposit(10)
```

两次调用都会寻找“当前最近的 `BankAccount` handler”。代码没有表达哪次操作
针对 checking，哪次针对 savings。即使嵌套安装两个 handler，也只能自然选择
最内层；业务含义依赖微妙的安装顺序。

为每个角色声明新 effect 也不好：

```text
CheckingAccount
SavingsAccount
SourceAccount
DestinationAccount
```

账户的角色是运行时数据，不应该迫使程序不断创造新的 effect family。

## 4. 用名字选择具体实例

给每次 handler application 绑定一个名字：

```cire
with make_account(100) as checking
with make_account(20) as savings
in {
  transfer(checking, savings, 10)
}
```

`checking` 与 `savings` 都是 `BankAccount` capability，但它们指向两个不同的
handler 实例。

`transfer` 显式选择 receiver：

```cire
def![F : Account] transfer(
  from : cap F,
  to : cap F,
  amount : Int,
) -> Unit ! {from, to} {
  from.withdraw(amount)
  to.deposit(amount)
}
```

逐行读：

```text
from.withdraw(amount)  只请求 from 指向的实例
to.deposit(amount)     只请求 to 指向的实例
! {from, to}           函数精确依赖这两个实例
```

执行后：

```text
checking  90
savings   30
```

Handler 的嵌套顺序不再决定账户角色；`from` 和 `to` 决定。

## 5. Ability、effect family、instance 是三层

这三个概念容易混淆：

| 层次 | 例子 | 回答的问题 |
|---|---|---|
| Ability | `Account` | 这类 effect 有哪些 operation？ |
| Effect family | `BankAccount` | 这是哪一种名义化 effect？ |
| Named capability | `checking` | 现在具体使用哪个 handler 实例？ |

类比普通类型：

```text
trait/interface  → ability Account
concrete class   → effect BankAccount
object/reference → capability checking
```

这个类比只帮助理解“接口、类别、实例”的层次。Capability operation 仍属于
effect system，受 effect row、handler、resumption 和 capture checking
约束，并不等同于普通对象调用。

## 6. `with ... as name` 到底做了什么

先创建 handler value：

```cire
let checking_handler = make_account(100)
```

再安装它，并在 action 中获得 capability：

```cire
with checking_handler as checking
in {
  checking.balance()
}
```

Surface HIR 保留为：

```text
ScopedApply(
  transformer = checking_handler,
  binder = checking,
  body = checking.balance(),
)
```

类型检查确认 handler 后，Kernel 才降为
`FreshPrompt + Handle + CapRef(checking)`；`checking` 不是普通 lambda 参数。
`as checking` 创建的 identity 对同一 chain 中后面的 entry 和最终
computation 可见：

```cire
with make_account(100) as checking
with audit_account(checking)
in {
  checking.balance()
}
```

它不在 `make_account(100)` 自身内部可见，因为 identity 要到该 handler
application 建立时才产生。

但 `checking` 不是一个可以不受限制地保存到任何地方的普通参数。每次
application 都创建新的、不可伪造的 identity，并且只在这次 action 中有效：

```cire
with make_account(0) as first
in {
  ...
}

with make_account(0) as second
in {
  ...
}
```

即使两个 handler 的初始值和实现完全相同，`first` 与 `second` 也不是同一个
capability。

`with` 本身也可以应用 transaction、timeout 等普通 computation wrapper，
但那些 entry 不能因此使用 `as` 绑定普通返回值。普通值继续用 `let` 或
trailing-lambda parameter；`with ... as app` 专门保留给 fresh named
capability。

## 7. 怎样读 `cap F`

再看一次泛型函数：

```cire
def[A]![F : Reader[A]] read_from(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

从外到内读：

```text
A
  普通返回类型

F : Reader[A]
  任意满足 Reader[A] 的 effect family

app : cap F
  family F 的一个具体 handler capability

app.read()
  向 app 指定的实例发出 read 请求

! {app}
  调用这个函数需要 app 仍然有效并已安装
```

`cap F` 是当前工作 type syntax。它不是“某个 F 值的数据内容”，而是选择
handler instance 的受检查引用。

## 8. 匿名 row 与具名 row 的区别

匿名：

```cire
def current_balance() -> Int ! {BankAccount} {
  BankAccount::balance()
}
```

含义：

```text
调用时需要上下文提供某个当前 BankAccount handler
```

具名：

```cire
def![F : Account] selected_balance(
  account : cap F,
) -> Int ! {account} {
  account.balance()
}
```

含义：

```text
调用时精确需要参数 account 指向的那个 handler
```

可以把它们记成：

```text
{F}        “给我一个当前的 F”
{account}  “我要这个 account”
```

两种形式都重要。只有一个自然实例时用匿名 effect；实例选择属于业务数据时用
named capability。

## 9. 源代码为什么写 `{app}`

具名 row 的源语法是：

```cire
! {app}
```

Compiler 为了帮助诊断，可以展开显示：

```text
Read[app]
```

它读作“`app` 是一个 Read family 的实例”，但不能写进源程序：

```cire
// 错误：Read[app] 不是源语法
def wrong(app : cap Read[Int]) -> Int ! {Read[app]} {
  app.read()
}
```

正确写法：

```cire
def right(app : cap Read[Int]) -> Int ! {app} {
  app.read()
}
```

原因是 row 需要记录 term identity `app`；`Read[A]` 中的方括号只用于普通
type argument，不能同时承担 instance syntax。

## 10. 为什么不直接传一个普通对象

如果一个服务只是普通数据，拥有普通 method，而且不需要 handler 控制，
直接传对象通常更简单：

```cire
def render(settings : Settings) -> View {
  Text(settings.theme)
}
```

Named capability 额外提供的是：

- operation 仍由词法安装的 handler 解释；
- effect row 能精确记录使用了哪个实例；
- 同一 ability 的多个实例可以显式选择；
- closure 或 continuation 保留实例时，compiler 能继续追踪；
- handler action 结束后，实例不能被偷偷带走继续调用；
- Owner、resumption 和 cleanup 规则可以使用同一个 identity。

所以 named capability 不是“所有依赖注入都要换一种写法”。判断标准是：

```text
普通值/普通服务对象
  只需要传数据或调用普通 method

匿名 effect
  需要上下文解释 operation，并且作用域内只有一个自然实例

named capability
  需要上下文解释 operation，而且同一协议有多个实例或必须追踪具体权限
```

## 11. 匿名与具名调用共享同一个 ability

```cire
ability Reader[A] {
  fun read() -> A
}
```

匿名调用：

```cire
def[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}
```

具名调用：

```cire
def[A]![F : Reader[A]] read_named(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

两者共享同一份 `Reader[A]` contract。区别只在 operation 路由：

```text
F::read()   → 当前匿名 F handler
app.read()  → app 指定的 handler
```

Compiler 内部必须保留这个区别：

```text
{F}    Anonymous(F)
{app}  Named(app, F)
```

## 12. Capability 参数本身就是 identity polymorphism

```cire
def[A]![F : Reader[A], ..E] relay(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E} {
  body()
}
```

这个函数不固定某个全局 `app`。每次调用都可以传不同 capability：

```cire
relay(checking, body_for_checking)
relay(savings, body_for_savings)
```

因此它同时对：

```text
A     普通类型
F     effect family
E     额外 effect row
app   本次调用传入的具体 identity
```

抽象。`app` 不需要写进 generic list；普通 term parameter 已经绑定了本次
identity。

## 13. Closure 为什么不能把 capability 带出 `with`

在 action 内创建并使用 closure 没问题：

```cire
with make_account(100) as checking
in {
  let show_later = fn() {
    checking.balance()
  }

  use_inside(show_later)
}
```

`show_later` 保留了 `checking`。只要它仍在安装 checking handler 的 action
内被调用，路由目标就存在。

把 closure 返回出去则不安全：

```cire
with make_account(100) as checking
in {
  fn() {
    checking.balance()
  }
}
```

离开 `with` 后，checking handler 已经不再安装。Compiler 应拒绝并指出：

```text
cannot return this closure

it retains `checking`, installed by this `with`
the handler is no longer installed after the action returns
```

用户不需要手写 capture annotation。Compiler 从 closure、struct、调用结果和
其他聚合值中推导这种依赖。

## 14. Capability 不能防止所有业务错误

Named capability 可以保证：

- `from.withdraw` 一定路由到 `from`；
- `{from}` 不会被误当成 `{to}`；
- capability 不能被伪造或越过安装范围；
- 抽象边界不能静默擦掉具体依赖。

它不能保证程序员没有把实参顺序写反：

```cire
transfer(savings, checking, 10)
```

这仍是业务逻辑问题。可以通过更明确的 labelled parameter、新类型或更高层
API 解决。类型系统的目标是消除环境路由和权限边界的歧义，不是假装理解所有
业务意图。

## 15. 什么时候应该使用

适合匿名 effect：

```text
当前测试环境唯一的 Clock
当前请求唯一的 Logger
当前控制范围唯一的 Error handler
```

适合 named capability：

```text
两个数据库连接
两个状态 cell
source account 与 destination account
两个 DOM root
读权限和写权限指向不同宿主实例
```

适合普通值：

```text
不可变 Settings
普通配置记录
不需要 effect/handler 语义的 service object
```

不要仅仅因为 `cap` 看起来“更安全”就给所有参数加上它。

## 16. 最后再看完整心智模型

```text
effect family
  定义一类 operation

handler value
  定义这些 operation 的一种解释

with handler
  在 action 中安装解释

with handler as app
  安装解释，并给这个具体实例一个可传递的 capability

app.operation()
  向这个具体实例发出请求

! {app}
  在类型中记录对这个具体实例的依赖
```

Named capability 的核心不是多一层复杂类型，而是把原本隐式的“到底调用哪个
handler”在确实需要时变成显式、可检查的 receiver。

## 当前状态

`{app}` 是 profile 源语法，`Read[app]` 只用于诊断。`with ... in ...`、
`cap`、ability constraint 与 fresh `CapId` 已形式化；仓库没有 parser、
capture inference 或 escape checker。

上一章：[Handler 与 with](08-handlers-and-with.md)　下一章：[四种恢复模式](10-resumptions.md)
