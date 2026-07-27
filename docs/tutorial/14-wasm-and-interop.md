# 14　WebAssembly 与宿主互操作

## 1. WebAssembly 是首要目标

Cire 从一开始就面向 WebAssembly，而不是先设计一门只适合某个 native runtime
的语言，再把 Wasm 当作次要输出格式。

目标平台包括：

- 浏览器中的 JavaScript 与 DOM；
- WASI；
- 通过明确 adapter 连接 C ABI 和既有 native library；
- 将来适用的 Wasm component 接口。

具体采用 core Wasm、Wasm GC 或 component model 的阶段安排仍是后端问题。

## 2. Wasm 不替语言做什么

```text
Wasm            决定程序在哪种机器模型上运行
effect/handler  决定请求与控制如何解释
incremental     决定输入变化后从哪里重算
UI renderer     决定如何修改宿主对象
```

选择 Wasm 不会自动获得 effect handler、结构化并发或响应式算法。

## 3. Host object 使用不透明 handle

JavaScript object、DOM node 和文件 descriptor 不能伪装成 Wasm 线性内存里的
裸地址。目标类型形状：

```cire
HostRef[T]
DomRef[Element]
```

运行时 handle table 概念上记录：

```text
index
host object
owner/generation
capabilities
alive/revoked state
```

静态 capture checking 阻止明显逃逸；运行时 generation 防止 release、
instance teardown 或宿主队列竞态后的陈旧访问。

## 4. 宿主权限仍然是 capability

第一方互操作层按权限分开：

```cire
clock     : cap HostClock
random    : cap HostRandom
network   : cap Network
dom_read  : cap DomRead
dom_write : cap DomWrite
storage   : cap Storage
wasi_fs   : cap WasiFs
```

例如 view 计算可以拥有 `dom_read`，但只有 commit scope 拥有 `dom_write`。
测试可以替换 clock、network 和 storage，而不必修改业务代码。

低层 escape hatch 可能不可避免，但必须明确标为 unsafe/unchecked，并形成
可审计边界，不能让任意代码直接访问整个 JavaScript global object。

## 5. Once callback

Promise completion 理论上只完成一次，但宿主 adapter 仍不能信任外部代码遵守
Cire 的数量规则。ABI 使用 one-shot slot：

```text
第一次 completion  → claim 成功，resume/discontinue
重复 completion     → AlreadyUsed
Owner 已关闭        → Revoked
```

Completion、cancel 和 Owner close 竞争同一个线性化点，确保 continuation
只被处置一次。

## 6. Many callback

DOM event、stream 和 subscription 可以被调用多次：

```text
HostCallback[many, Event]
```

Many-shot 表示 Owner 存活期间允许多次调用，不表示 callback 可以脱离 Owner
永久存在。关闭顺序：

```text
先 revoke callback
拒绝新 action 进入 dying Owner
再调用 removeEventListener/disposer
已排队调用在入口 generation check 被拒绝
```

同步 reentrant event 也必须经过同一套入口检查。

## 7. Portable context

宿主 callback 重新进入 Wasm 时：

1. 验证 Wasm instance；
2. 验证 Owner 和 generation；
3. 安装允许 portable 的 handler context；
4. 启动新的 action，或处置 parked continuation；
5. 退出时完整展开 cleanup；
6. 不保存 stack-only capability。

语言不会默认把整个 handler stack 序列化。Portable/reentrant 标记、嵌套顺序
和 ABI metadata 仍需设计。

## 8. 错误、取消与 trap

跨边界至少要区分：

```text
语言层 Error effect
结构化取消
宿主 exception/rejection
Wasm trap
```

可恢复宿主错误应映射到 typed error；取消应触发 continuation-aware unwind；
trap 是更强的运行失败，不能承诺所有语言 cleanup 都一定能继续执行。

把四者都压成一个字符串或 JavaScript rejection 会破坏静态 row、取消协议和
诊断信息。

## 9. Instance teardown

销毁 Wasm instance 也采用两阶段原则：

```text
阶段一
  标记 instance 不可进入
  revoke exported callback token
  revoke root Owner 与 child generation
  detach handle/callback registry

阶段二
  finalize parked resumption
  cancel task tree
  child-first/LIFO cleanup
  release host handle
  聚合 cleanup error
```

Teardown 后宿主再次调用旧入口，应得到稳定的 `RevokedInstance`，而不是进入已
释放的语言状态。

## 10. DOM 的特殊困难

DOM setter 可能同步运行 custom element code，event dispatch 可以嵌套重入，
node detach 也不等于 logical Owner dispose。因此：

- render 只产生 plan；
- commit capability 才能写 DOM；
- host ref 携带 Owner/generation；
- renderer 区分 move、detach、hide、retire 和 dispose；
- focus、selection、form value 等隐式宿主状态由 renderer 负责。

这些复杂度不能由一个通用 effect row 自动消失，但 capability 与 Owner 能把
权限和关闭边界说清楚。

## 当前状态

Wasm-first 是已决定方向；本章 ABI、handle、callback 和 teardown 是设计要求。
Compiler 还没有 Wasm backend、runtime、JS/DOM/WASI adapter 或 component
metadata。

上一章：[UI 与 trailing lambda](13-ui-and-trailing-lambdas.md)　下一章：[完整示例](15-complete-example.md)
