# WebAssembly 与宿主互操作

> **ABI design:** [`Cire-TR₀/2026-07-31`](spec-status.md)。本文给未来 runtime
> 和 Wasm lowering 设约束；仓库当前没有 backend 或 adapter。

## 1. WebAssembly 是首要目标

**已决定**

Cire 不是“以后也许能输出 Wasm”的语言。WebAssembly 是首要编译目标，因此语言与标准库设计必须从一开始满足：

- 稳定、可版本化的 Wasm/host ABI；
- 第一方 JavaScript 与 DOM interop；
- 第一方 WASI 支持；
- 可与 C ABI 及既有 native library 互操作；
- effect、handler、continuation、Owner、异常、取消和 callback 都能可靠跨越 Wasm 边界；
- Wasm 实例销毁时可以确定地撤销宿主能力并清理资源。

具体 continuation lowering、GC 方案与 component model 版本仍是实现问题，当前文档只记录源语言与 ABI 必须维持的语义。

## 2. Wasm 不解决什么

WebAssembly 决定最终机器模型，但不会决定：

- 哪个 Source 变化；
- 运行时实际读取了哪些依赖；
- 哪个 continuation cut 支配另一个；
- 同一 batch 应恢复哪个 frontier；
- keyed item 是否延续；
- DOM node 应移动还是替换。

简写为：

```text
Wasm            决定“在哪种机器上运行”
effect/handler  决定“如何捕获和解释控制”
incremental     决定“输入变化后重算哪里”
UI renderer     决定“如何更新宿主界面”
```

因此选择 Wasm 不会让增量内核消失。

## 3. 宿主边界的主要对象

```text
Wasm program
    ↕ stable host ABI
JavaScript / DOM / WASI / native host
```

ABI 至少需要处理：

- Cire function 与宿主 callback 的相互转换；
- JS object、Promise、Error 与 DOM node 的 handle；
- 宿主 callback 调用一次或多次；
- Wasm 内存回收与宿主对象表关闭；
- 异常、取消与 trap 的映射；
- handler context 的受控保存和恢复；
- Owner/generation 失效后的 callback revocation；
- Wasm 实例 teardown；
- reentrant host call。

## 4. Host handle

DOM node 和普通 JS object 不应被伪装成 Wasm 线性内存中的裸地址。运行时需要不透明 handle：

```text
HostRef[T]
DomRef[Element]
```

概念上，handle table 记录：

```text
index
host object
owner/generation
capabilities
alive/revoked state
```

Capability capture checking 阻止明显的静态逃逸；运行时 generation 防止：

- handle 已被 release 后继续使用；
- 同一业务 key 重建后旧 handle 指向新对象；
- 浏览器队列里的旧 callback 重新进入；
- Wasm instance 销毁后宿主仍调用导出函数。

宿主对象何时被 JavaScript GC 不属于 Cire 语义；Cire 只保证何时撤销自己的使用权限和释放持有关系。

## 5. Callback modality

宿主 ABI 必须区分至少两种 callback：

```text
once callback
  Promise completion、一次性异步完成

many callback
  DOM event、stream、subscription
```

### 5.1 Once callback

Raw `once` continuation 不直接交给宿主。Sealed completion source建立
generation-bound completion port；宿主不受 Cire 数量规则约束，可能重复调用，
所以 port 内部使用 CAS slot：

```text
first completion  → claim 成功，以 Result/Outcome 恢复
later completion  → AlreadyUsed
owner revoked     → Revoked
```

无论 completion、cancel 还是 Owner close 获胜，都必须只处置 continuation 一次。

### 5.2 Many callback

DOM listener 可以被调用多次并同步重入，但 Owner 关闭后必须失效：

```text
HostCallback[many, Event]
```

Owner 关闭时：

- 先 revoke callback；
- 阻止新 action 注册到 dying Owner；
- 再调用宿主 `removeEventListener` 等 disposer；
- 已经排队的调用在入口 generation check 处被拒绝。

“many-shot”描述调用次数，不代表可以比 Owner 活得更久。

## 6. Portable handler context

**开放问题**

宿主稍后回调时，原来的 Wasm 动态栈已经不存在。语言不能默认把整个 handler stack 暗中序列化。

只有被标记为 portable/reentrant，且 capture checking 接受其全部依赖的
handler capability 才可以进入 `PortableContext`。

ABI adapter 恢复 callback 时需要：

1. 验证 Wasm instance；
2. 验证 Owner 与 generation；
3. 安装允许 portable 的 context；
4. 启动一次新的 action，或处置一个 parked continuation；
5. 在退出时完整展开 cleanup；
6. 不保留 stack-only capability。

Context 的具体表示、handler 嵌套次序和 reentrancy 规则尚未决定。

## 7. 异常、取消与 trap

跨边界至少要区分：

```text
语言层 Error effect
结构化取消
宿主 exception/rejection
Wasm trap
```

它们不能全部悄悄压成一个字符串或 JS rejection。

设计要求：

- 可恢复宿主错误映射到明确的 typed error；
- 取消能够触发 continuation-aware unwind；
- trap 被视为更强的运行失败，不能假设所有语言 cleanup 都仍可执行；
- host disposer 抛错时继续尝试 sibling cleanup，并聚合报告；
- instance teardown 即使遇到错误也要撤销全部 callback 入口。

## 8. Instance teardown

**设计方向**

销毁一个 Wasm 实例应遵循与 Owner 两阶段关闭相同的原则：

```text
阶段一：
  标记实例不可进入
  revoke 所有 exported callback token
  revoke root Owner 与 child generation
  detach handle/callback registries

阶段二：
  finalize parked resumptions
  cancel task tree
  child-first/LIFO cleanup
  release host handles
  聚合 cleanup 错误
```

这样宿主在 teardown 后再次调用旧 function index 时，只得到稳定的 `RevokedInstance` 结果，而不会进入已经释放的语言状态。

## 9. DOM 特殊约束

DOM 不在 Wasm 内部，并且具备同步重入与不可逆 mutation：

- property setter 可能触发 custom element code；
- event dispatch 可以嵌套进入 Wasm；
- node detach 不等于 logical Owner dispose；
- closed shadow root 可能无法检查；
- focus、selection、form value 具有隐式宿主状态。

因此：

- render 只产生 plan；
- commit capability 才能调用 DOM host ABI；
- host ref 带 Owner/generation；
- commit 不能被描述成可任意回滚；
- renderer 需要明确不可逆边界与失败策略。

具体规则见 [第一方响应式 UI 框架](reactive-ui.md)。

## 10. 第一方互操作层

**设计方向**

标准库应按 capability 分层，而不是把 JavaScript 全局对象无约束暴露给所有代码：

```text
clock     : cap HostClock
random    : cap HostRandom
network   : cap Network
dom_read  : cap DomRead
dom_write : cap DomWrite
storage   : cap Storage
wasi_fs   : cap WasiFs
```

这使：

- `live`/view 无法偷偷写 DOM；
- test handler 可以替换 clock、network 与 storage；
- capture set 能指出 closure 绑定了哪个宿主实例；
- FFI 权限不会因为 effect 被局部 handle 就凭空出现。

低层 escape hatch 仍可能需要，但应明确标记为 unsafe/unchecked，并形成可审计边界。

## 11. ABI 开放问题

- 目标采用 core Wasm、Wasm GC、component model，还是分阶段支持？
- continuation 使用 CPS、stack switching、显式 heap frame 还是混合 lowering？
- JS/DOM handle table 的 index、generation 与回收策略是什么？
- `once`/`many` callback modality 如何编码进 ABI metadata？
- portable handler Context 如何表示与版本化？
- Wasm exception handling 与语言 Error/取消如何映射？
- trap 后哪些 finalizer 仍有执行保证？
- 多线程 Wasm 下 Owner、one-shot slot 与 generation check 如何同步？
- C callback 违反有效性约定时，adapter 的失败策略是什么？
- Cire package/module identity 如何映射到 component imports/exports？
