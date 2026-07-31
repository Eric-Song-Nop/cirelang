# 第一方响应式 UI 框架

> **First-party contract:** [`Cire-TR₀/2026-08-01`](spec-status.md)。UI 由普通
> 调用、builder/effect protocol 与 renderer 提供，不增加 parser 特判。

## 1. 定位

**已决定**

响应式 UI 是 Cire 的旗舰第一方框架，而不是语言的基础求值语义。

语言核心不认识：

```text
Component / DOM / Signal / Suspense / useState / Virtual DOM / CSS
```

UI 框架组合：

```text
typed effects + resumptions
+ incremental kernel
+ named capability + Owner
+ structured tasks/resources
+ stable identity
+ renderer protocol
```

同一套通用机制也应能服务 IDE、构建系统、查询、流计算和长期运行的服务状态机。

## 2. 响应式读取的语义

UI 计算中的一次读取：

```text
let name = read(user_name)
text(name)
```

不是简单登记一个 callback，而是产生 continuation cut：

```text
read(user_name, |name| text(name))
```

Source 更新后，增量内核选择最早失效、且不被另一个失效 cut 支配的 frontier，然后恢复对应后缀。

UI 框架在此基础上增加：

- 每个动态 child/属性的独立 trace 边界；
- 跨重算保留的 logical owner；
- stable/keyed identity；
- staged view plan；
- DOM/Canvas/SSR 等 commit backend；
- task/resource、error 与 suspend policy。

## 3. 不能混为一棵树

系统中至少存在以下相互关联、但职责不同的结构：

```text
Source / Derived graph
  跨计算共享与变化传播

Continuation Trace
  单个计算内部从哪里恢复

Logical Owner tree
  状态、资源和子项跟谁一起死亡

Structured Task tree
  异步取消与错误传播

Host render tree
  DOM/Canvas/原生节点实际放在哪里
```

Portal、共享 Derived、异步任务和无 DOM 的 Provider 都证明这些结构不能合并为普通“组件树”。

## 4. 必须区分的有效条件

| 对象 | 身份来源 | 何时失效 |
|---|---|---|
| Continuation cut | 一次 trace 中的控制位置 | 祖先重放、trace replacement 或 Owner 关闭 |
| Candidate generation | 一次候选求值 | commit、abort、抢占或失败 |
| Logical UI item | parent name × lexical site × explicit key | 成功协调后确认该项不再存在 |
| Local state | logical Owner | Owner 被真正销毁 |
| Task/resource | Owner × declaration site × resource key/policy | Owner 销毁、key 改变或 policy 取消 |
| DOM node | renderer 的 host identity | renderer 决定 release |
| Event action | 一次 event occurrence | 返回、失败或取消 |

关键不变量是：

```text
continuation 属于 trace
trace/candidate 属于 logical Owner
Owner 拥有长期 state、task 与 resource
renderer 拥有实际 DOM 对象
```

不能让 continuation 的失效自动等价于组件状态销毁，也不能让 DOM 节点是否还 attached 决定 logical Owner 是否存在。

## 5. 稳定身份

**设计方向**

新旧两次执行中的逻辑项通过：

```text
Name =
  ParentName
  × LexicalSite
  × ExplicitKey
```

进行对应。

- `ParentName` 提供 namespace；
- `LexicalSite` 区分同一作用域中的声明位置；
- `ExplicitKey` 区分运行时集合项。

因此：

```text
continuation  决定“从哪里继续”
Owner         决定“什么跟谁一起活”
key/name      决定“新旧两轮是不是同一个对象”
```

列表重排：

```text
[Alice, Bob] → [Bob, Alice]
```

不能按执行序号交换两人的 state。keyed container 应移动 Bob 和 Alice 对应的现有 logical Owner，而不是重建或交换其状态。

Stable key 和 reconciliation 属于 UI/container 层。语言可以提供 typed
key、generative name、存在类型和受限的 compiler-defined stable
call-site identity，但不需要理解“组件”，也不因此引入宏系统。

## 6. Logical Owner 与 DOM identity

一个 logical item 可能：

- 不产生 DOM；
- 产生多个 DOM 节点；
- 暂时不产生 DOM 但保留 state；
- 保留同一 DOM 节点，只更新属性；
- 移动节点；
- 通过 Portal 使用完全不同的 DOM parent；
- detach 或隐藏但暂不销毁；
- 在 transition 中让旧、新节点短暂并存。

因此 DOM 节点需要区分以下状态：

```text
Declared
Allocated
Attached
Visible
Detached
Disposed
Collected
```

框架最多可靠控制到 `Disposed`。浏览器何时 GC 属于宿主，不应进入 UI 语义。

DOM 还保存用户可观察的宿主状态：

- focus；
- selection；
- scroll position；
- 表单输入状态；
- 媒体播放位置；
- 第三方库或 custom element 附加的状态。

因此 DOM identity 不只是性能优化；错误替换会改变程序行为。

## 7. Candidate generation

**设计方向**

祖先 cut 失效时，不能立刻销毁当前已提交 UI。更稳健的流程是：

```text
Owner
├── committed generation γ0
└── candidate generation γ1
```

1. 保留 `γ0` 供用户继续观察和交互；
2. 在同一 Owner 下建立 `γ1`；
3. 在 `γ1` 中恢复 continuation、建立新 trace；
4. 产生新的 view/resource plan；
5. 成功稳定后再提交 `γ1`；
6. 提交后协调新旧 children，retire 不再匹配的旧资源；
7. 若失败、暂停、被抢占或再次失效，则放弃 `γ1`，不破坏 `γ0`。

这为 Suspense 与 transition 提供基础，但不要求最小增量内核一开始就实现并发 candidate。

## 8. Render 与 commit

### 8.1 推测计算不能直接写 DOM

如果 candidate 求值时直接执行：

```text
appendChild(...)
addEventListener(...)
startNetworkTask(...)
```

那么 candidate 被放弃时，cleanup 只能补偿，无法保证外部世界从未观察到这些行为。

因此 view/render 阶段只产生：

```text
ViewPlan
ResourcePlan
```

真正宿主修改需要 commit capability：

```text
def commit(
  plan : ViewPlan,
  authority : CommitAuthority,
) -> Unit ! {host_write} {
  ...
}
```

`CommitAuthority[γ]` 最多只能消费一次。它可以由续体专用数量系统扩展出的通用 affine capability 表达，也可以先由标准库安全封装。

### 8.2 阶段由 capability 表达

不需要把 `view/action/commit` 做成语言关键字。框架可以用具名 effect capability 约束：

```text
view : (Props) -> ViewPlan ! {observe, declare}
action : (Event) -> Unit ! {snapshot, state, tasks, command}
commit : (ViewPlan) -> Unit ! {host_write}
```

结果是：

- view 可重放、可放弃；
- view 拿不到 `HostWrite`；
- action 由每次外部事件重新启动；
- commit 才跨过宿主修改边界；
- layout read 需要节点已 mounted 的 capability。

## 9. DOM 不是可回滚事务

**已决定**

不能承诺任意 DOM 操作原子化：

- custom element callback 可能同步重入；
- setter、listener 或第三方补丁可能抛异常；
- closed shadow root 可能不可检查；
- focus、selection 和表单状态可能在 mutation 间被观察；
- retire/dispose 本身可能失败。

更诚实的 renderer 协议是：

```text
validate
  纯检查，可以失败

prepare
  构造宿主 draft，可能已部分可观察

irrevocable
  明确跨过不可逆边界

publish
  尽量设计成 total 的最终切换

retire
  可失败、可重试，并保证所有 sibling 都被尝试
```

Candidate plan 能减少不可逆工作泄漏，但不能把浏览器变成 ACID 数据库。

## 10. State、task 与 resource

### 10.1 State

持久 UI state 绑定 logical Owner 与声明 site。它使用普通 API：

```cire
let count = UiState::cell(owner, 0)
```

它不是普通局部 `var`：

- 同一 Owner 的后续 generation 再次遇到该声明时复用已有 cell；
- Owner 销毁时 state 才结束；
- continuation replacement 不会自动重置 state；
- DOM move 或 detach 不会自动重置 state。

### 10.2 Event

DOM listener 在 Owner 存活期间可以被调用很多次，但每次 event occurrence 启动一个新的 action：

```cire
Button(
  "Update",
  on_click = Event::handler(owner) {
    update_state()
  },
)
```

不应把一次永久事件 continuation 反复恢复。需要区分：

```text
listener callback  在 Owner 关闭前 many-shot
event action        每个 occurrence 独立、结构化结束
```

宿主 callback 仍需要 generation token，因为事件可能已在浏览器队列中。

Action 内读取 state 通常是一次当前 Epoch 的 snapshot read，不建立长期响应依赖。`Observe.read` 属于 view/live；`SnapshotRead` 属于一次 event action。

状态事务不能跨越 `await`：

```cire
Action::run {
  Atomic::run {
    saving = true
  }

  let result = Async::await(save())

  Atomic::run {
    saving = false
    status = result
  }
}
```

`await` 之后的第二段写入属于新的 Epoch。这样不会让一个事务在任意长的宿主等待期间锁住或观察移动中的世界。

### 10.3 Resource

Resource 的身份通常是：

```text
(owner, declaration_site, key, generation)
```

概念 API 使用普通 labelled call 与 trailing lambda：

```cire
let profile = Resource::switch_latest(
  owner,
  key = user.id,
) { key =>
  Async::await(api.load_profile(key))
}
```

key 改变后，policy 决定：

- `switch_latest`：取消旧任务；
- `merge`：并行保留；
- `concat`：顺序执行；
- `exhaust`：当前任务期间忽略新请求。

这些是第一方资源协议，不是 `await` operation 的固有语义。

## 11. `Observe` 与 `Await` 的顺序

代数效应组合使两种常见情况自然不同。

本节是 UI 层 `resource`/candidate runner 的**概念展开**，不是说最小
`live : (() -> A ! {Observe}) -> Live[A]` 可以直接包含 `await`。普通
`live` 排除 Async；第一方 UI runner 必须显式选择 task replacement、snapshot、
取消和 stale-completion policy。语言层 accept/reject 例见
[Temporal modality、代数效应与增量计算](temporal-reactivity-design-experiment.md)。
对应的候选 typing 与 candidate-buffer machine 见
[Cire-TR₀ Typst 形式化](temporal-reactivity-formalization.typ)。

### 11.1 Observe 在 Await 前

```text
let key = read(user_id)
let profile = await(load(key))
render(profile)
```

`user_id` 变化会恢复外层 read cut。旧 await 属于被替换的 candidate/task scope：

- resource key 不变时可以按 policy 复用任务；
- key 改变时可以取消或替换任务；
- 旧 completion 受 generation 检查，不能提交到新 candidate。

### 11.2 Await 在 Observe 前

```text
let config = await(load_config())
let theme = read(theme_source)
render(config, theme)
```

任务只等待一次。完成后才建立 `theme` cut；未来 `theme` 变化只恢复读取之后的后缀，无需重新 await。

这说明 continuation cut 的控制位置本身有价值，不需要把所有异步和响应式行为压成同一种 Observable。

## 12. Error boundary、Suspense 与 transition

这些是 scoped handler 与 candidate policy 的组合：

```cire
Boundary(
  pending = fn() { Spinner() },
  failed = fn(error) { ErrorView(error) },
) {
  child_computation()
}
```

暂停时可以选择：

- 立即提交 fallback；
- 保留旧 committed generation；
- 显示旧数据并标记 stale；
- 等待子任务全部准备好；
- 允许较小子边界先提交。

错误时可以选择：

- 保留旧 committed UI；
- 提交 error view；
- 将本轮读取保留为 retry dependency；
- 在手动 event 或下一次依赖变化时重试。

失败 candidate 的 task、continuation 和 resource 必须完整清理；旧 committed generation 的 Owner 不应因候选失败被误销毁。

## 13. Keyed collection

普通：

```text
read(List[Item])
```

列表变化后重放整个循环是正确但粗粒度的。

第一方 keyed sequence 可以传播：

```text
Insert(key, position, value)
Remove(key)
Move(key, position)
Update(key, delta)
```

框架为每个 key 建立 sibling Owner：

```text
friends.for_each_keyed(key = fn(item) { item.id }) { item =>
  FriendRow(item)
}
```

于是：

- Insert 只创建一个 Owner；
- Move 只改变宿主顺序；
- Update 只更新对应输入；
- Remove 在成功 commit 后关闭对应 Owner；
- 其他项的 state、task 与 trace 不变。

重复 key、易变 key 或用 index 标识携带 state 的动态项应产生诊断。

## 14. 独立的增量边界

严格求值会使早期读取的 continuation 包含整个后缀：

```text
Text(name())
Chart(data())
```

如果 `name()` 先执行，名字变化可能连 Chart 一起重算。UI block 应把动态 child、属性、条件和 keyed item 自动变成独立 effectful thunk：

```text
Column {
  child { Text(read(name)) }
  child { Chart(read(data)) }
}
```

这使它们成为兄弟 trace root：

```text
Column Owner
├── Text trace  → name
└── Chart trace → data
```

它是 UI 框架的边界策略，不改变普通函数的求值语义。

## 15. Demand 与 activation

逻辑 Owner 的存在不等于当前必须求值：

```text
active
dormant
retained
disposed
```

- mounted UI 通常是 active demand root；
- 没有消费者的 Derived 可以只标记 dirty；
- retained/keep-alive Owner 可以保留 state 但暂停求值；
- disposed Owner 永远不能恢复；
- hidden、detached 和 disposed 不能混为一谈。

Demand tracking 是后续优化，不是最小增量内核的要求。

## 16. 用 canonical syntax 组合第一方 API

语言不增加 `component/state/resource/view/action` 关键字。下面使用普通 `def`、
labelled argument 与 trailing lambda；具体库名仍可演化：

```cire
def user_pane(user : Source[User]) -> View
  ! {Observe, UiState, Resource, Event} {
  Owner::scope { owner =>
    let expanded = UiState::cell(owner, false)
    let profile = Resource::switch_latest(
      owner,
      key = Observe::read(user).id,
    ) { key =>
      api.load_profile(key)
    }

    Column {
      Button(
        "Toggle",
        on_click = Event::handler(owner) {
          expanded.update(fn(value) { !value })
        },
      )

      if expanded.read() {
        Boundary(
          pending = fn() { Spinner() },
          failed = fn(error) { ErrorView(error) },
        ) {
          Profile(profile.await())
        }
      }
    }
  }
}
```

其中：

- Source read 建立 continuation cut；
- state 绑定 logical Owner；
- resource 绑定 Owner、site 与 key；
- `await` 使用 `once`；
- boundary 是 scoped handler；
- event 每次启动新 action；
- view 只产生 plan；
- renderer 在 commit capability 下修改宿主。

表单双向访问应优先使用有定律的 `Binding[A]`/lens，而不是隐式深层 Proxy。它是 UI 库设计方向，不是语言内建特性。

## 17. 必须坚持的不变量

**已决定作为框架正确性目标**

1. 同一轮 view/derive 的读取来自同一逻辑 Epoch。
2. 增量结果与同一快照上的从头执行等价。
3. 被放弃的 candidate 不得发布未声明的外部效果。
4. State 跟随 logical identity，而不是 continuation 或 DOM node。
5. Continuation 失效不等于 logical Owner 销毁。
6. DOM attach、detach、hide、move、dispose 是不同操作。
7. Host mutation 权限只存在于明确的 commit/layout 作用域。
8. Owner 销毁后，旧 continuation、callback 与异步结果不得再次影响 UI。
9. Candidate 成功协调以前，不销毁当前 committed Owner。
10. 一个 cleanup 失败不能阻止其余 child/resource 被清理。

## 18. 明确留在框架或 backend 的复杂度

- Source-local continuation index；
- frontier scheduler；
- equality/version/invalidation；
- shared Derived DAG 与 cycle detection；
- keyed diff、key map 与 move 策略；
- DOM marker/range；
- focus、selection、scroll 与表单状态保存；
- hydration；
- event delegation；
- custom element、shadow root 与跨 realm 防御；
- DOM retirement retry policy；
- Suspense/transition 的产品策略。

语言特性应减少这些系统中的续体和结构化关闭样板，但不应假装消除领域算法。
