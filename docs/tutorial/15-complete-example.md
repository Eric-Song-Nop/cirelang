# 15　完整示例：可测试的 Profile 加载器

这一章把普通数据、trait 式 effect abstraction、具名 capability、异步
operation、错误、handler 和 UI 外观放进同一个小例子。它展示目标设计，
不是当前可运行程序。

## 1. 数据模型

```cire
struct Settings {
  current_user : UserId
}

struct Profile {
  id : UserId
  name : String
}

enum LoadError {
  Offline
  NotFound(UserId)
  InvalidResponse(String)
}
```

Struct 表示字段同时存在；enum 表示失败只能是列出的情况之一。

## 2. 抽象“读取设置”

```cire
pub(open) ability Reader[A] {
  fun read() -> A
}

pub(open) effect SettingsState
  : Reader[Settings] {}
```

业务函数不必固定使用 `SettingsState`。它可以接受任意满足
`Reader[Settings]` 的具名 capability。

## 3. API、日志与错误

```cire
pub(open) effect ProfileApi {
  once load(id : UserId) -> Result[Profile, LoadError]
}

pub(open) effect Logger {
  fun log(level : Level, message : String) -> Unit
}

pub(open) effect Error[E] {
  abort[A] raise(error : E) -> A
}
```

为什么 mode 不同：

- `ProfileApi.load` 可能跨宿主等待，所以 handler 允许保存一个 one-shot
  continuation；
- `Logger.log` 只返回并自动继续一次；
- `Error.raise` 放弃后续计算。

## 4. 核心业务函数

```cire
fn![S : Reader[Settings]] load_current(
  settings : cap S,
) -> Profile
  ! {
    settings,
    ProfileApi,
    Logger,
    Error[LoadError],
  } {
  let current = settings.read()
  let user_id = current.current_user

  Logger::log(Info, "loading profile")

  match ProfileApi::load(user_id) {
    Ok(profile) => {
      Logger::log(Info, "profile loaded")
      profile
    }
    Err(error) => Error::raise(error)
  }
}
```

从签名就能读出：

```text
S                     任意 Reader[Settings] effect family
settings : cap S      一个具体 settings 实例
{settings}            精确请求这个实例
ProfileApi            匿名 API effect
Logger                匿名日志 effect
Error[LoadError]      可中止的 typed error
```

函数没有写网络、测试 fixture 或控制台实现。

## 5. 生产 handler 的概念形状

```cire
let browser_api = handler ProfileApi {
  once load(id) as k => {
    let request = js_fetch(profile_url(id))

    request.owner.adopt(k)
  }
}
```

实际 adapter 还要把 Promise completion 转成安全 one-shot slot：

```text
fulfilled → k.resume(Ok(profile))
rejected  → k.resume(Err(mapped_error))
cancelled → k.discontinue(cancelled)
close     → k.finalize()
```

示例省略了 adapter 细节，不能把裸 `k` 交给不受 Cire 规则约束的 JavaScript。

## 6. 测试 handler

设置：

```cire
let fixed_settings = handler SettingsState {
  fun read() => {
    current_user: UserId(7),
  }
}
```

API：

```cire
let fake_api = handler ProfileApi {
  fun load(id) => Ok({
    id,
    name: "Ada",
  })
}
```

虽然 operation 声明为 `once`，这个测试 handler 可以选择更严格的 `fun`
clause：它同步返回并自动继续一次。

日志：

```cire
let quiet_logger = handler Logger {
  fun log(_level, _message) => ()
}
```

错误转成普通 `Result`：

```cire
let catch_load_error = handler Error[LoadError] {
  abort raise(error) => Err(error)
  return(profile) => Ok(profile)
}
```

## 7. 组合测试

```cire
fn test_load_current() -> Result[Profile, LoadError] {
  with fixed_settings as settings
  with fake_api
  with quiet_logger
  with catch_load_error
  in {
    load_current(settings)
  }
}
```

逐层观察 row：

```text
load_current
  {settings, ProfileApi, Logger, Error[LoadError]}

with catch_load_error
  {settings, ProfileApi, Logger}

with quiet_logger
  {settings, ProfileApi}

with fake_api
  {settings}

with fixed_settings as settings
  {}
```

最终函数是纯的，并返回可断言的 `Result`。

## 8. Fresh identity 的价值

同一个测试可以同时安装两个设置实例：

```cire
with settings_for_user_7 as left
with settings_for_user_9 as right
in {
  let first = load_current(left)
  let second = load_current(right)
  (first, second)
}
```

两个 call 的 row 分别包含 `{left}` 和 `{right}`。即使 family 相同，
compiler 也不会把它们的读取路由到同一个 handler。

## 9. Effect-polymorphic helper

记录耗时的 helper 不应固定调用者剩余的 effect：

```cire
fn[A]![..E] measured(
  name : String,
  body : () -> A ! E,
) -> A ! {Clock, Logger, ..E} {
  let started = Clock::now()
  let value = body()
  let elapsed = Clock::now() - started
  Logger::log(Debug, name + ": " + elapsed.to_string())
  value
}
```

调用：

```cire
measured("profile") {
  load_current(settings)
}
```

`E` 会包含 `{settings, ProfileApi, Error[LoadError]}`。Helper 自己只增加
`Clock` 和 `Logger`。

## 10. 接到增量 UI

先把加载状态作为普通数据：

```cire
enum LoadState[A, E] {
  Idle
  Loading
  Ready(A)
  Failed(E)
}
```

概念 View：

```cire
fn![S : Reader[Settings]] profile_page(
  settings : cap S,
  state : Source[LoadState[Profile, LoadError]],
) -> View ! {settings, Observe} {
  Column(gap=8) {
    match read(state) {
      Idle => Text("Not loaded")
      Loading => Spinner()
      Ready(profile) => Text(profile.name)
      Failed(error) => ErrorView(error)
    }

    Button("Reload") {
      write(state, Loading)

      let profile = load_current(settings)
      write(state, Ready(profile))
    }
  }
}
```

Button body 是 latent event action。它的 `ProfileApi`、`Logger`、
`Error[LoadError]` 和 `Update` effect 由 Button/action API 的函数类型携带，
不会因为 callback 仅仅被构造就全部算进 view 本轮的 effect row。

真实框架还需要 error boundary、task Owner、candidate generation 和 commit
阶段；这里专注展示普通语法如何承载 DSL。

## 11. Capture error 示例

下面不能安全返回：

```cire
fn broken() -> () -> Settings {
  with fixed_settings as settings
  in {
    fn() {
      settings.read()
    }
  }
}
```

返回的 closure 保留 `{settings}`，但对应 handler 在 `with` action 结束后不再
安装。Compiler 应指出 `settings` 的 binding origin，并建议把工作留在 scope
内，或重新设计 API 让调用者传入 capability。

## 12. 这个例子展示了什么

- 普通 struct/enum 建模业务数据；
- ability 让具名 effect 和匿名 effect 共享抽象；
- effect row 让依赖出现在函数类型中；
- `once`、`fun`、`abort` 表达不同控制能力；
- handler 让生产、测试和错误收集实现分离；
- `with ... as settings` 创建 fresh identity；
- effect polymorphism 保留 helper 的可复用性；
- trailing lambda 让增量和 UI API 保持普通函数外观；
- Owner 与 host adapter 承担异步 continuation 的最终处置。

上一章：[Wasm 与互操作](14-wasm-and-interop.md)　下一章：[语法索引](16-syntax-index.md)
