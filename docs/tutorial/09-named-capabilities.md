# 09　具名 capability

## 1. Effect family 有时还不够精确

假设界面同时显示主文档和预览文档：

```text
两个状态都满足 Reader[Document]
但读取主文档与读取预览不能混为同一件事
```

匿名 row 只能说：

```cire
! {Read[Document]}
```

它没有指出使用哪一个具体 handler。Cire 因此允许 handler application
创建不可伪造的具名 capability。

## 2. 创建具名 capability

```cire
with read_main as app {
  app.read()
}
```

`app` 是一个普通 term binder，但它也有由 compiler 创建的 singleton
identity。每次 application 都是 fresh：

```cire
with read_main as left {
  with read_main as right {
    // left 和 right 的 family 相同，identity 不同
  }
}
```

名字相同不代表 identity 相同；identity 也不是字符串、整数或用户可以伪造的
全局 token。

## 3. Capability type 与 named row

函数接收一个具体 capability：

```cire
fn[A]![F : Reader[A]] read_from(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

逐部分读：

```text
A                 普通结果类型
F : Reader[A]     任意满足 Reader[A] 的 effect family
app : cap F       family F 的一个具体 capability value
{app}             调用精确依赖这个 identity
```

`cap F` 是 capability type 的当前工作写法。

## 4. 源代码只写 `{app}`

具名 row 的最终源语法是：

```cire
! {app}
```

Compiler 在诊断或高级类型展开中可以显示：

```text
Read[app]
```

`Read[app]` 只用于解释 `app` 属于哪个 family，不能写进源程序：

```cire
// 错误
fn wrong(app : cap Read[Int]) -> Int ! {Read[app]} {
  app.read()
}
```

定向诊断应建议改成：

```cire
fn right(app : cap Read[Int]) -> Int ! {app} {
  app.read()
}
```

这条区别很重要：`Read[A]` 是普通类型参数化的 effect family，
`Read[app]` 不是泛型应用。

## 5. 匿名与具名调用共享 ability

```cire
ability Reader[A] {
  fun read() -> A
}
```

匿名调用：

```cire
fn[A]![F : Reader[A]] read_any() -> A ! {F} {
  F::read()
}
```

具名调用：

```cire
fn[A]![F : Reader[A]] read_named(
  app : cap F,
) -> A ! {app} {
  app.read()
}
```

二者共享同一份 `Reader[A]` evidence，但 Core row entry 不同：

```text
{F}    Anonymous(F)
{app}  Named(app, F)
```

这样具名 effect 不会退化成一套与普通 effect 多态互不相干的系统。

## 6. Identity polymorphism

```cire
fn[A]![F : Reader[A], ..E] relay(
  app : cap F,
  body : () -> A ! {app, ..E},
) -> A ! {app, ..E} {
  body()
}
```

这个函数同时对四件事抽象：

```text
A     普通类型
F     effect family
E     额外 effect row
app   本次调用传入的具体 identity
```

`app` 不写进 generic list。它由普通参数绑定，函数体中的 `{app}` 精确引用
本次传入的 capability。

`E` 也可以实例化为包含其他 named capability 的 row，因此 row polymorphism
与 identity polymorphism 可以自然组合。

## 7. 捕获与逃逸

Lambda 可以保留 capability：

```cire
with read_main as app {
  let later = fn() {
    app.read()
  }

  use_inside(later)
}
```

`later` 的函数类型带 `! {app}`，compiler 也在内部记录它保留了 `app`。
如果它被带出 handler action：

```cire
with read_main as app {
  fn() {
    app.read()
  }
}
```

应拒绝并指出：

```text
cannot return this closure

it retains `app`, whose handler is installed by this `with`
the handler is no longer installed after the action returns
```

捕获信息由 compiler 从 term binder、闭包、aggregate 和调用结果推导。
源码不增加另一套 capture 标注。

## 8. 为什么局部 handle 不会“洗掉权限”

局部 handler 可以消除 computation 的 effect demand，但不能凭空获得另一个
实例：

```text
effect row   调用值时还会请求什么
capture      值已经固定保留了什么具体 capability
authority    当前作用域实际授予哪些操作
```

三者相互关联但不能互相替代。一个闭包即使把内部匿名 effect 处理完，仍不能把
捕获的 `app` 伪装成“适用于任意 Reader 实例”的普通纯值。

## 9. Package 抽象也必须保留 identity

Capability 被放进 struct、trait object 或抽象 package 返回值时，接口摘要
必须保留必要的 capture 约束。否则模块化会把静态安全信息擦掉。

这也是 compiler 从一开始就需要可序列化 HIR/interface 的原因：CLI、增量
编译和 LSP 应共享同一份 identity 与 capture 分析，而不是各自猜测。

## 当前状态

`{app}` 是已决定源语法，`Read[app]` 只用于诊断。Named binder 已有 parser
基线；`cap`、ability constraint、fresh generativity、capture inference 和
escape checking 尚未实现。

上一章：[Handler 与 with](08-handlers-and-with.md)　下一章：[四种恢复模式](10-resumptions.md)
