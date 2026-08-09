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
  #text(size: 15pt)[语法、typed Core、算法化检查、wire schema 与 runtime protocol]

  #v(14pt)
  #text(fill: luma(90))[Canonical successor profile · `Cire-v1.0` · 2026-08-09]
]

#v(18pt)

#status(
  [文档状态],
  [
    本文件是 `Cire-v1.0` 语言设计的唯一入口。`design/surface/` 固定 token、PEG、
    precedence、lossless CST、surface scope 与 elaboration；`design/core/` 固定
    typed Core、静态 judgment、wire meaning 与 runtime protocol。两组章节按下方
    `include` 顺序组成一份 authority，不是互相竞争的第二规范。

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

#include "design/surface/00-foundations.typ"
#include "design/surface/01-effects-and-rows.typ"
#include "design/surface/02-handlers-and-control.typ"
#include "design/surface/03-01-first-party-overview.typ"
#include "design/surface/03-02-first-party-bindings.typ"
#include "design/surface/03-03-structural-registry.typ"
#include "design/surface/04-profile-and-packages.typ"
#include "design/surface/05-grammar-declarations.typ"
#include "design/surface/06-grammar-types-and-functions.typ"
#include "design/surface/07-grammar-expressions.typ"
#include "design/surface/08-grammar-effects-and-temporal.typ"
#include "design/core/00-foundations.typ"
#include "design/core/01-surface-authority.typ"
#include "design/core/02-successor-profile.typ"
#include "design/core/03-primitive-and-declaration-wire.typ"
#include "design/core/04-const-component-and-abi.typ"
#include "design/core/05-function-contract-v3.typ"
#include "design/core/06-elaboration-intrinsics-diagnostics.typ"
#include "design/core/07-ordinary-foundation-and-wasm.typ"
#include "design/core/08-cleanup-and-packed-next.typ"
#include "design/core/09-task-and-resource-protocols.typ"
#include "design/core/10-signal-and-ui-protocol.typ"
#include "design/core/11-conformance-closure.typ"
#include "design/core/12-retained-core-setup.typ"
#include "design/core/13-01-retained-core-types.typ"
#include "design/core/13-02-legacy-wire-schema.typ"
#include "design/core/13-03-legacy-wire-semantics.typ"
#include "design/core/13-04-legacy-wire-import.typ"
#include "design/core/13-05-core-contract-elaboration.typ"
#include "design/core/14-core-expressions.typ"
#include "design/core/15-static-domains.typ"
#include "design/core/16-01-kinding.typ"
#include "design/core/16-02-packed-next.typ"
#include "design/core/16-03-identity-wf-safety.typ"
#include "design/core/17-algorithmic-typing.typ"
#include "design/core/18-temporal-typing.typ"
#include "design/core/19-01-operation-typing.typ"
#include "design/core/19-02-handler-site-checking.typ"
#include "design/core/19-03-resumptions-and-modes.typ"
#include "design/core/19-04-handler-forms.typ"
#include "design/core/20-capture-storage-owner.typ"
#include "design/core/21-async-and-phase.typ"
#include "design/core/22-reactive-contracts.typ"
#include "design/core/23-incremental-machine.typ"
#include "design/core/24-01-type-checker-main.typ"
#include "design/core/24-02-type-checker-handlers.typ"
#include "design/core/24-03-type-checker-tail.typ"
#include "design/core/25-derivations.typ"
#include "design/core/26-metatheory.typ"
#include "design/core/27-reserved-extensions.typ"
#include "design/core/28-implementation-handoff.typ"
#include "design/core/29-conclusion.typ"
