#import "../shared.typ": *

== Successor conformance closure <successor-conformance-v1>

一个 artifact/tree只有同时满足以下 finite boundary才可称 `Cire-v1.0`：

1. 唯一 surface authority能生成 complete normalized HIR；本文无 active PEG；所有 removed spelling
   (`~` parameter marker、`cap` parameter marker、`defer`、prefix pattern alias、source `extern`、generic
   Event subscribe、public Plan/Commit)均有 stable reject root。
2. Package graph exact-decode `CireLanguageInterfaceV1`，验证 package digest、package-qualified module、
   declaration/evidence/callable/component closure；每 callable只走 Interface→V3 edge；V3 M3 recursion、
   local slots、defaults、DAG/hash与 every named-def explicit row全部 positive/mutation green。
3. Primitive catalog 16-entry exact；legacy五项 byte-equal，sealed十一项 locked-core nominal；
   String/Bytes/Char const payload byte/scalar differential证明 NFC/JCS不改 semantic value。
4. Data/trait/impl/const/component exact schema与 ordinary judgments覆盖 positive/reject、alpha/order/
   visibility/coherence/exhaustiveness/value-restriction/MayTrap/ConstSafe/Component boundary。
5. Intrinsic root恰两个 children；FirstParty registry exact 21、Structural exact 2；13-kind origin arena、
   prescribed derive/interpolation/finally/temporary mapping与 diagnostic precedence全部 exact。
6. PackedNextProtocolV1、Task broadcast、Receipt/CleanupLedger、Resource switch-latest、Signal/UI typed FIFO
   occurrence与 sealed checkpoint各通过 exhaustive state/claim/lease mutation；V2 Packed artifact只能在
   legacy profile decoder成功，两个 profile cross-feed必须拒绝。
7. 未来 conformance tree 中，full type/effect/flow/world/capture/usage/phase/Owner/checker gates、
   runtime trace gates、Typst build与 exact-checked artifacts必须同时 green；任何 memo、side table
   或 host queue都不是证据。当前纯规范仓库只执行 Typst 与结构性验证，不声称其余 gates 已实现。

最小 coherent migration order正是：package identity/module → primitive catalog → package declaration/
evidence schemas → callable V3/DAG → origin/diagnostics/registries → ordinary inference/data/traits →
mutation/control/const → Component boundary → cleanup/receipt → PackedNext/Task → Resource → Signal/UI →
checkpoint → future exact-checked artifacts。不得发布中间 mixed profile或让
later runtime stage反向定义 earlier type。
