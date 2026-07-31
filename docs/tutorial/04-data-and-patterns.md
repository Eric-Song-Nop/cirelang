# 04　数据与模式匹配

> 本章示例属于 [`Cire-TR₀/2026-08-01`](../spec-status.md) 教程基线。

## 1. Struct：一组同时存在的字段

Struct 描述一个值由哪些字段组成：

```cire
struct User {
  id : Int
  name : String
  active : Bool
}
```

构造时字段名让含义清楚：

```cire
let user : User = {
  id: 1,
  name: "Lin",
  active: true,
}
```

读取字段：

```cire
let display_name = user.name
```

默认不可变数据鼓励创建新值，而不是在未知别名之间原地修改。精确的 struct
update 和 mutable field 语法仍需冻结。

## 2. Enum：多个可能形状中的一个

Enum 表示“这个值是这些情况之一”：

```cire
enum LoginState {
  LoggedOut
  Loading
  LoggedIn(User)
  Failed(String)
}
```

`LoggedOut` 和 `Loading` 没有 payload；`LoggedIn` 携带一个 `User`；
`Failed` 携带错误消息。

与用字符串或整数编码状态相比，enum 有两个重要优点：

- 非法组合无法构造；
- compiler 可以检查处理代码是否遗漏某种情况。

## 3. `match`

模式匹配同时完成“判断形状”和“取出数据”：

```cire
def status_text(state : LoginState) -> String {
  match state {
    LoggedOut => "Please sign in"
    Loading => "Loading..."
    LoggedIn(user) => "Hello, " + user.name
    Failed(message) => "Error: " + message
  }
}
```

`LoggedIn(user)` 匹配 constructor，并把内部 `User` 绑定为 `user`。

模式从上到下尝试。完整 enum match 应覆盖全部 constructor；遗漏分支时，
compiler 应给出缺失例子，而不只说“match 不完整”。

## 4. Wildcard、literal 与 guard

`_` 匹配任意值但不绑定：

```cire
def is_ready(state : LoginState) -> Bool {
  match state {
    LoggedIn(_) => true
    _ => false
  }
}
```

Literal pattern：

```cire
def word(value : Int) -> String {
  match value {
    0 => "zero"
    1 => "one"
    _ => "many"
  }
}
```

Guard 在 pattern 已经匹配后增加条件：

```cire
def describe(user : User) -> String {
  match user {
    { active: true, name, .. } if name != "" => name
    { active: false, .. } => "inactive"
    _ => "anonymous"
  }
}
```

Guard 不能替代穷尽性分析：两个看起来互补的运行时条件，也未必能由 compiler
证明覆盖全部值。

## 5. Generic enum

类型参数让同一种数据形状容纳不同 payload：

```cire
enum Option[A] {
  None
  Some(A)
}

enum Result[A, E] {
  Ok(A)
  Err(E)
}
```

`Option[User]` 表示可能有用户，也可能没有。`Result[User, LoadError]` 把成功与
失败作为普通数据返回。

`Result` 与 effect 不冲突：

- 需要保存、传递或组合一个失败结果时，用 `Result`；
- 当前计算要立即把错误请求交给周围上下文时，用 `Error[E]` effect。

## 6. 递归数据

Enum 可以引用自身：

```cire
enum Tree[A] {
  Empty
  Node(Tree[A], A, Tree[A])
}
```

递归函数与递归 pattern 自然配合：

```cire
def[A] size(tree : Tree[A]) -> Int {
  match tree {
    Empty => 0
    Node(left, _, right) => 1 + size(left) + size(right)
  }
}
```

## 7. Pattern 是 API 设计的一部分

如果 package 公开一个 enum 的全部 constructor，调用者可能穷尽匹配它们；
以后新增 constructor 就会影响下游。若希望保留演化空间，应公开观察函数或
保持表示抽象。

这也是可见性不只关乎“能不能访问”的原因：它还决定外部代码能对你的数据作出
哪些永久假设。

## 8. 还需要冻结的 pattern

Cire 的目标基线还包括 tuple、record、array、or-pattern、`as` pattern、
rest pattern 与 typed pattern。当前工作形状例如：

```cire
match value {
  Some(user) as whole => use(user, whole)
  [first, ..rest] => use(first, rest)
  Red | Blue => "cool"
  _ => "other"
}
```

这些形式已经与 precedence、binder 重复、两侧 binder 集合及恢复边界写入
完整 grammar；穷尽性和类型细化仍属于 checker/proof obligation。

## 当前状态

ADT、pattern、`match` 与 struct literal 属于 profile grammar；仓库没有
parser/checker。穷尽性、or-pattern type join 与诊断是未来实现义务。

上一章：[函数与控制流](03-functions-and-control-flow.md)　下一章：[泛型、trait 与包](05-generics-traits-and-packages.md)
