# Cire 简明文档

这组短文只回答三个问题：Cire 是什么、现在做到哪里、代码大概长什么样。

## 一句话介绍

Cire 是一门语法接近 MoonBit、面向 WebAssembly 的严格求值函数式语言。
它把代数效应和受控续体放进语言核心，同时希望让 UI DSL 仍然像普通函数调用。

## 先记住五件事

1. 普通声明、泛型、类型和调用尽量沿用 MoonBit 的外观。
2. `[A]` 是普通类型多态，`[Fx : Effect]` 是单个 effect 多态，
   `[Eff : EffectRow]` 是整行 effect 多态。
3. 具名 capability 用普通参数 `app : Read[A]` 绑定，在 effect row 中写成
   `{app}`；`Read[app]` 只会出现在诊断展开中。
4. Effect 有 `abort`、`fun`、`once`、`ctl` 四种恢复模式。
5. Cire 不做宏系统。UI DSL 使用 labelled argument 和 trailing lambda。

## 30 秒例子

```moonbit
pub(open) effect Read[A] {
  fun read() -> A
}

fn read_app(app : Read[Int]) -> Int ! {app} {
  app.read()
}

fn main() -> Int {
  with handler Read[Int] {
    fun read() => 42
  } as app {
    read_app(app)
  }
}
```

这里：

- `Read[Int]` 是一个 effect family；
- `app` 是本次安装 handler 时产生的具体 capability；
- `! {app}` 表示函数运行时可能向这个 capability 请求操作；
- `with ... as app { ... }` 在设计上会把 capability 限制在 action 的静态 Region 内。

当前 parser 已经能识别并保留这类语法，也能对坏输入继续恢复。类型、effect、
capture 和 Region 检查还没实现，所以这段代码目前不能一路编译到 Wasm。

## 接下来读什么

- [语法和例子](examples.md)：看函数、effect、handler 和 UI DSL。
- [实现设计与进度](progress.md)：看编译器已经完成什么、下一步做什么。
- [完整设计文档](../README.md)：需要规则依据和开放问题时再读。
