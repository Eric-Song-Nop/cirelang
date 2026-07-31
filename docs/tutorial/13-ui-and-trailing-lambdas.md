# 13　UI 与 trailing lambda

> 本章示例属于 [`Cire-TR₀/2026-08-01`](../spec-status.md) 第一方契约。

## 1. UI 是旗舰框架，不是语言语法

Cire 核心不认识：

```text
Component
DOM
Signal
Suspense
useState
Virtual DOM
CSS
```

第一方 UI 框架用普通函数、labelled argument、trailing lambda、增量计算、
Owner、task/resource 和 renderer protocol 组合这些概念。

## 2. Trailing lambda

零参数 block：

```cire
Button("Save") {
  save()
}
```

展开：

```cire
Button("Save", fn() {
  save()
})
```

带参数：

```cire
users.for_each { user =>
  UserRow(user)
}
```

展开：

```cire
users.for_each(fn(user) {
  UserRow(user)
})
```

它不是 AST macro。Block 不能读取调用点源码、创建卫生名称或改变 parser。

## 3. 完整附着规则

- 一个 trailing lambda 只能作为调用的最后一个实参；
- `callee(args) { ... }` 与 `callee { ... }` 都允许；
- `{ params => body }` 提供参数；
- `{ body }` 表示零参数 thunk；
- whitespace、newline 和 comment 不打断附着；
- 要把 call 与后续独立 block 分开，必须写显式 `;`。

例如：

```cire
Button("Save")
// comment
{
  save()
}
```

仍然是一个带 trailing lambda 的调用。

这条规则让 formatter 可以安全换行，也让 parser 不需要猜换行是否表示语句
结束。

## 4. Labelled argument 让 DSL 自解释

```cire
Column(gap=8, align=Center) {
  Text("Profile", style=Heading)
  Button("Save", enabled=can_save) {
    save()
  }
}
```

`gap`、`align`、`style`、`enabled` 是普通 labelled argument。`Column`、
`Text`、`Button` 是库函数。嵌套结构来自 lambda，不来自编译器识别的 tag。

## 5. 一个普通 View 函数

```cire
def user_card(user : User) -> View {
  Card {
    Text(user.name)

    if user.active {
      Badge("Active")
    } else {
      Badge("Inactive")
    }
  }
}
```

`if` 是表达式，`Card` 接收 child builder。整个例子可以用普通函数类型解释，
不需要 `component` 关键字。

## 6. 响应式 View

```cire
def counter_view(count : Source[Int]) -> View ! {Observe} {
  Column {
    Text(read(count).to_string())
    Button("Increment") {
      write(count, read_snapshot(count) + 1)
    }
  }
}
```

这里需要区分两个阶段：

- View 计算中的 `read(count)` 建立长期增量依赖；
- Event action 中的 `read_snapshot(count)` 只读取当前 Epoch，不建立 view
  continuation cut。

事件 callback 在 Owner 存活期间可以 many-shot 调用，但每次 click 启动一个
新的、结构化结束的 action。框架不会保存一条永久 event continuation 然后
反复恢复它。

## 7. State 跟随 logical Owner

概念上的 state API：

```cire
Owner::state(0)
```

它的身份来自：

```text
parent logical name
× declaration site
× optional explicit key
```

State 不跟随某一次 continuation，也不由某个 DOM node 是否 attached 决定。
重算替换了 trace，不应重置 state；真正销毁 logical Owner 才结束 state。

具体 `state` API 仍在设计中。它不会成为隐式 magic binding。

## 8. Keyed collection

```cire
Keyed::for_each(users, key=User::id) { user =>
  UserRow(user)
}
```

当 `[Alice, Bob]` 变成 `[Bob, Alice]` 时，框架根据 key 移动已有 logical
Owner，而不是交换两人的 state 或销毁重建。

Key、continuation 和 DOM identity 回答不同问题：

```text
continuation  从哪里继续计算
logical key   新旧两轮是否是同一个逻辑项
DOM identity  宿主节点实际是否复用或移动
```

## 9. Resource

概念 API：

```cire
let profile = Resource::load(
  key=user_id,
  policy=SwitchLatest,
) {
  Async::await(api.load_profile(user_id))
}
```

Key 改变时，policy 可以选择：

```text
SwitchLatest  取消旧任务
Merge         并行保留
Concat        顺序执行
Exhaust       当前任务期间忽略新请求
```

这些是 resource 协议，不是 `await` operation 的固有语义。

## 10. Render 与 commit 分开

View 计算先产生 plan，只有 commit capability 可以修改宿主：

```text
render/derive    可重算，产生候选 plan
coordinate       检查 candidate、Owner 与 generation
commit           使用 DomWrite 等 capability 修改宿主
retire           清理旧节点和资源
```

这防止失败或被抢占的候选计算提前写 DOM。DOM mutation 不是可随意回滚的
事务，renderer 必须明确不可逆边界。

## 11. Boundary、pending 与 transition

错误边界、pending UI 和 transition 是 scoped handler 与 candidate policy
的组合：

```cire
Boundary(
  pending=fn() { Spinner() },
  failed=fn(error) { ErrorView(error) },
) {
  ProfileView(profile.await())
}
```

它们是库 API，不是 parser 特判。Handler 负责控制请求，框架决定保留旧
committed view、显示 fallback，还是等待更小边界先提交。

## 12. 为什么明确不做宏

不做 token/AST/typed macro 带来：

- 单一 parser 与单一语义树；
- LSP 不需要执行用户宏才能理解文件；
- 诊断位置不在展开前后漂移；
- 增量编译 query 不需要缓存任意代码生成；
- UI 仍能通过 labelled argument 和 trailing lambda 获得嵌套外观。

需要 stable declaration site 时，由 compiler 提供受限、稳定的 site 机制，
而不是开放源码反射。

## 当前状态

Labelled argument、label punning、method call 和嵌套 trailing lambda 属于
profile grammar。仓库没有 parser；UI、incremental、Owner、renderer、
state/resource 与 stable site 都是尚未实现的第一方契约。

上一章：[增量计算](12-incremental-computation.md)　下一章：[Wasm 与互操作](14-wasm-and-interop.md)
