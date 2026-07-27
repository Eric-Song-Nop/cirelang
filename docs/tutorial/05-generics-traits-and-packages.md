# 05　泛型、trait 与包

## 1. 参数多态

一个函数不关心元素的具体类型时，用普通类型参数：

```cire
fn[A] first_or(
  values : Array[A],
  fallback : A,
) -> A {
  if values.is_empty() {
    fallback
  } else {
    values[0]
  }
}
```

`A` 表示调用者选择的任意普通类型：

```cire
first_or([1, 2], 0)
first_or(["a", "b"], "")
```

大多数时候 compiler 从参数推导 `A`。需要消除歧义时可以显式写：

```cire
first_or[String]([], "unknown")
```

方括号始终用于普通 type parameter 和 type argument。

## 2. 高阶泛型函数

`map` 同时抽象输入类型、输出类型和转换函数：

```cire
fn[A, B] map(
  values : Array[A],
  transform : (A) -> B,
) -> Array[B] {
  ...
}
```

这段签名没有承诺 `A` 或 `B` 支持比较、打印或算术，因此实现也不能偷偷使用
这些操作。泛型参数越自由，函数能做的事越少，但能被复用的地方越多。

## 3. Trait constraint

函数确实需要某种行为时，用 trait 约束：

```cire
fn[A : Eq] contains(
  values : Array[A],
  expected : A,
) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}
```

`A : Eq` 表示 `A` 必须有一致的相等比较实现。多个 constraint 使用 `+`：

```cire
fn[A : Eq + Show] explain_equal(left : A, right : A) -> String {
  if left == right {
    left.to_string() + " equals " + right.to_string()
  } else {
    "different"
  }
}
```

## 4. 声明与实现 trait

普通 trait 采用 MoonBit 风格基线：

```cire
pub(open) trait Show {
  to_string(Self) -> String
}
```

`Self` 表示实现 trait 的类型。为 `User` 实现：

```cire
pub impl Show for User with to_string(self) {
  "User(" + self.name + ")"
}
```

调用者可以写：

```cire
user.to_string()
```

Trait visibility：

```text
trait             只在当前 package 可见
pub trait         外部可使用，只有定义 package 可新增实现
pub(open) trait   外部也可新增实现
```

Coherence 要保证同一个 `Type : Trait` 组合不会在程序里同时出现互相冲突的
实现。Orphan 和 overlap 的精确规则仍需冻结。

## 5. Trait、method 与函数的区别

三种写法表面相似，但抽象程度不同：

```cire
fn parse(text : String) -> User
fn User::display_name(self : User) -> String
fn[A : Show] render(value : A) -> View
```

- 普通函数由 package 名称选择；
- method 是与一个已知类型关联的顶层函数；
- trait method 通过 constraint 对许多类型抽象。

不要为了获得点调用就创建 trait。一个操作只有在需要跨多个类型统一抽象时，
才值得成为 trait。

## 6. Package 与限定名

Package 是主要代码组织边界。导入的 package 用 `@alias.name` 访问：

```cire
let value = @math.clamp(input, min=0, max=100)
let request = @http.Request::get(url)
```

这让来源在大型代码库中仍然清楚，也给 compiler 和 LSP 一个稳定的
package-qualified identity。

源文件中的 `pub` 控制 API 可见性；依赖、alias 和构建选项属于 package
配置。Cire 尚未冻结配置文件格式，因此教程不伪造一套 `cire.pkg` 语法。

## 7. 抽象边界

Package 应能只公开类型名称而隐藏表示：

```cire
// package 内部
struct UserId {
  raw : Int
}

pub fn UserId::parse(text : String) -> Option[UserId] {
  ...
}
```

外部代码只能通过公开函数构造和观察 `UserId`，就不会依赖 `raw` 字段。
数据表示、trait implementation 和 effect handler 的开放程度都应该由
package 作者明确选择。

## 8. 两套泛型列表的预告

到目前为止，`[A]` 只量化普通类型。Effect 系统还需要量化：

- 一个 effect family；
- 一个 effect constructor；
- 一整行 effect。

Cire 不把它们混进同一个列表，而是使用相邻的第二个列表：

```cire
fn[A]![F, ..E] example(...) -> A ! {F, ..E} {
  ...
}
```

```text
[A]       普通类型参数
![F, ..E] effect family 与 effect row 参数
```

第 7 章会完整解释这种“双列表”设计。

## 当前状态

普通泛型已有 parser baseline；完整 trait、`impl`、package、visibility、
name resolution 和 type checking 尚未实现。本章的普通 trait 写法以
MoonBit 风格为教学基线；effect ability 的独立工作设计见第 7 章。

上一章：[数据与模式匹配](04-data-and-patterns.md)　下一章：[第一个 effect](06-effects.md)
