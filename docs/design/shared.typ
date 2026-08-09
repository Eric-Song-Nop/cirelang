#let status(name, body) = block(
  width: 100%,
  fill: rgb("#f4f7fb"),
  stroke: (left: 3pt + rgb("#476a92")),
  inset: (left: 10pt, right: 8pt, y: 7pt),
  radius: 2pt,
  [
    *#name* \
    #body
  ],
)

#let warning(body) = block(
  width: 100%,
  fill: rgb("#fff8e8"),
  stroke: (left: 3pt + rgb("#b88016")),
  inset: (left: 10pt, right: 8pt, y: 7pt),
  radius: 2pt,
  body,
)

#let irule(name, premises, conclusion) = block(
  breakable: false,
  inset: (y: 0.45em),
  align(center, [
    $ frac(
      #stack(spacing: 0.3em, ..premises),
      #conclusion,
    ) #h(0.7em) #text(size: 8pt, fill: gray)[#name] $
  ]),
)
