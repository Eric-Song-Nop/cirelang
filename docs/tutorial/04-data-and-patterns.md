# 04　数据与模式匹配

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
fn status_text(state : LoginState) -> String {
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
fn is_ready(state : LoginState) -> Bool {
  match state {
    LoggedIn(_) => true
    _ => false
  }
}
```

Literal pattern：

```cire
fn word(value : Int) -> String {
  match value {
    0 => "zero"
    1 => "one"
    _ => "many"
  }
}
```

Guard 在 pattern 已经匹配后增加条件：

```cire
fn describe(user : User) -> String {
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
fn[A] size(tree : Tree[A]) -> Int {
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

这些形式必须和 precedence、binder 重复、两侧 binder 集合、错误恢复一起
形成完整 PEG；在此之前不把细节当成稳定承诺。

## 当前状态

ADT、pattern、`match`、struct literal 与完整穷尽性检查尚未实现。本章使用
已经选择的 MoonBit 风格方向，并明确保留尚待冻结的细节。

上一章：[函数与控制流](03-functions-and-control-flow.md)　下一章：[泛型、trait 与包](05-generics-traits-and-packages.md)
