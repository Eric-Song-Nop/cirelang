# Cire 简明文档

> 基线：[`Cire-TR₀/2026-08-01`](../spec-status.md)。仓库当前没有实现；
> 本目录只解释规范和未来实现入口。

这组短文只回答三个问题：Cire 是什么、设计基线是什么、代码大概长什么样。

## 一句话介绍

Cire 是一门语法接近 MoonBit、面向 WebAssembly 的严格求值函数式语言。
它把代数效应和受控续体放进语言核心，同时希望让 UI DSL 仍然像普通函数调用。

## 先记住五件事

1. 普通声明、泛型、类型和调用尽量沿用 MoonBit 的外观。
2. `[A]` 放普通类型参数；`![F : Reader[A], ..E]` 放单 effect 和
   effect row 参数。
3. 具名 capability 的工作写法是 `app : cap F`，在 effect row 中写
   `{app}`；`Read[app]` 只会出现在诊断展开中。
4. Effect 有 `abort`、`fun`、`once`、`ctl` 四种恢复模式。
5. Cire 不做宏系统。UI DSL 使用 labelled argument 和 trailing lambda。

## 30 秒例子

```moonbit
pub(open) ability Reader[A] {
  fun read() -> A
}

pub(open) effect Read[A] : Reader[A] {}

def[A]![F : Reader[A]] read_app(
  app : cap F,
) -> A ! {app} {
  app.read()
}

def main() -> Int {
  with handler Read[Int] {
    fun read() => 42
  } as app
  in {
    read_app(app)
  }
}
```

这里：

- `Reader[Int]` 是 effect ability，`Read[Int]` 是具体 effect family；
- `app` 是本次安装 handler 时产生的具体 capability；
- `! {app}` 表示函数运行时可能向这个 capability 请求操作；
- `with ... as app in ...` 创建不可伪造的 identity；编译器从该 binder
  检查保留 `app` 的值没有逃出 handler action。

这段代码是 profile 级示例。仓库没有 parser、type checker、runtime 或 Wasm
backend；未来实现必须按规范接受或给出规范定义的诊断。

## 接下来读什么

- [语法和例子](examples.md)：看函数、effect、handler 和 UI DSL。
- [完整多态设计](../polymorphism-design.md)：看双列表、ability、row
  constraint 和 named capability。
- [规范状态与重启路线](progress.md)：看当前基线和未来实现入口。
- [完整设计文档](../README.md)：需要规则依据和开放问题时再读。
