#set page(
  paper: "a4",
  margin: (x: 22mm, y: 20mm),
  numbering: "1",
)
#set text(size: 10pt, lang: "zh")
#set par(justify: true, leading: 0.72em)
#set heading(numbering: "1.1")
#set table(
  stroke: 0.5pt + luma(190),
  inset: (x: 6pt, y: 4pt),
)

#import "design/shared.typ": status

#show raw.where(block: true): it => block(
  width: 100%,
  fill: luma(246),
  inset: 8pt,
  radius: 3pt,
  breakable: true,
  it,
)

#align(center)[
  #text(size: 22pt, weight: "bold")[
    Cire v1.0 Language Design
  ]

  #v(5pt)
  #text(size: 15pt)[语言设计、编译器阶段、wire/ABI、runtime 与验证]

  #v(14pt)
  #text(fill: luma(90))[Canonical successor profile · `Cire-v1.0` · 2026-08-09]
]

#v(18pt)

#status(
  [文档状态],
  [
    本文件是 `Cire-v1.0` 语言设计的唯一入口。`design/` 按维护目标分为 overview、
    language、frontend、static semantics、checker、interfaces、runtime、assurance 与
    reference；目录表示责任边界，不表示规范优先级。下方 `include` 顺序仍是唯一
    authority manifest，各章节不是互相竞争的第二规范。

    标成 legacy/retained TR0 的段落只供旧 artifact exact-decode 与 proof substrate，
    不属于 `Cire-v1.0` accepted producer language。Theorem 仍是陈述或证明义务，
    不代表已经完成机械化证明。未来 parser、checker、runtime 与 examples 必须服从
    本入口，不能反向定义语言。
  ],
)

#v(8pt)

#status(
  [本轮模型选择],
  [
    `Cire-v1.0` 采用纯 `Next`、Fitch-style clock lock、world-indexed resumption、
    独立 suspension summary、handler-instance law、Owner-bound one-shot disposition、
    sealed fixed-Epoch checkpoint runner，以及动态 single-claim commit gate。
    它不加入一般 affine value calculus，也不把 `Task`、`Live` 与 `Next` 合并；
    ordinary foundation、first-party contract 与 retained TR0 calculus 在 successor
    章节中统一，冲突处 successor 规则优先。
  ],
)

#v(16pt)
#outline(indent: auto)
#pagebreak()

#include "design/10-language/00-foundations.typ"
#include "design/10-language/10-effects-and-rows.typ"
#include "design/10-language/20-handlers-and-control.typ"
#include "design/20-frontend/10-first-party-overview.typ"
#include "design/20-frontend/11-first-party-bindings.typ"
#include "design/20-frontend/12-structural-registry.typ"
#include "design/20-frontend/20-profile-and-packages.typ"
#include "design/20-frontend/30-grammar-declarations.typ"
#include "design/20-frontend/31-grammar-types-and-functions.typ"
#include "design/20-frontend/32-grammar-expressions.typ"
#include "design/20-frontend/33-grammar-effects-and-temporal.typ"
#include "design/00-overview/00-scope-and-notation.typ"
#include "design/20-frontend/00-surface-authority.typ"
#include "design/00-overview/10-successor-profile.typ"
#include "design/50-interfaces/00-primitive-and-declaration-wire.typ"
#include "design/50-interfaces/10-const-component-and-abi.typ"
#include "design/50-interfaces/20-function-contract-v3.typ"
#include "design/20-frontend/40-elaboration-intrinsics-diagnostics.typ"
#include "design/30-static-semantics/00-ordinary-foundation-and-wasm.typ"
#include "design/60-runtime/00-cleanup-and-packed-next.typ"
#include "design/60-runtime/10-task-and-resource-protocols.typ"
#include "design/60-runtime/20-signal-and-ui-protocol.typ"
#include "design/70-assurance/00-conformance-closure.typ"
#include "design/30-static-semantics/10-retained-core-setup.typ"
#include "design/30-static-semantics/11-retained-core-types.typ"
#include "design/90-reference/00-legacy-wire-schema.typ"
#include "design/90-reference/01-legacy-wire-semantics.typ"
#include "design/90-reference/02-legacy-wire-import.typ"
#include "design/20-frontend/50-core-contract-elaboration.typ"
#include "design/30-static-semantics/20-core-expressions.typ"
#include "design/30-static-semantics/21-static-domains.typ"
#include "design/30-static-semantics/30-kinding.typ"
#include "design/30-static-semantics/31-packed-next.typ"
#include "design/30-static-semantics/32-identity-wf-safety.typ"
#include "design/30-static-semantics/40-algorithmic-typing.typ"
#include "design/30-static-semantics/41-temporal-typing.typ"
#include "design/30-static-semantics/50-operation-typing.typ"
#include "design/30-static-semantics/51-handler-site-checking.typ"
#include "design/30-static-semantics/52-resumptions-and-modes.typ"
#include "design/30-static-semantics/53-handler-forms.typ"
#include "design/30-static-semantics/60-capture-storage-owner.typ"
#include "design/30-static-semantics/61-async-and-phase.typ"
#include "design/30-static-semantics/62-reactive-contracts.typ"
#include "design/60-runtime/90-legacy-incremental-machine.typ"
#include "design/40-checker/00-type-checker-main.typ"
#include "design/40-checker/01-type-checker-handlers.typ"
#include "design/40-checker/02-type-checker-tail.typ"
#include "design/70-assurance/10-derivations.typ"
#include "design/70-assurance/20-metatheory.typ"
#include "design/90-reference/90-reserved-extensions.typ"
#include "design/40-checker/10-implementation-handoff.typ"
#include "design/00-overview/99-conclusion.typ"
