#let msg(a, b, label, dashed: false) = (t: "m", a: a, b: b, label: label, dashed: dashed)
#let ret(a, b, label) = msg(a, b, label, dashed: true)
#let self(a, label) = (t: "s", a: a, label: label)
#let group(kind, cond, a: none, b: none) = (t: "g", kind: kind, cond: cond, a: a, b: b)
#let otherwise(cond) = (t: "e", cond: cond)
#let end() = (t: "x")
#let note(a, b, body) = (t: "n", a: a, b: b, body: body)
#let divider(label) = (t: "d", label: label)

#let seq(parts, steps, size: 6.5pt) = layout(region => {
  let w = region.width
  let n = parts.len()
  let colw = w / n
  let lh = size * 1.3
  let head = 24pt
  let x(i) = colw * (i + 0.5)
  let txt(s) = text(size: size, s.split("\n").join(linebreak()))
  let lines(s) = s.split("\n").len()
  let els = ()
  let stack = ()
  let y = head + 12pt
  let k = 0

  let header(y0) = {
    let out = ()
    for (i, p) in parts.enumerate() {
      out.push(place(top + left, dx: x(i) - colw / 2 + 2pt, dy: y0, box(
        width: colw - 4pt, height: head, stroke: 0.6pt, radius: 2pt, fill: luma(248),
        align(center + horizon, text(size: size + 0.5pt, p.split("\n").join(linebreak()))),
      )))
    }
    out
  }

  for s in steps {
    if s.t == "m" {
      k += 1
      let label = str(k) + "  " + s.label
      y += lh * lines(label) + 3pt
      let x1 = x(s.a)
      let x2 = x(s.b)
      let lo = calc.min(x1, x2)
      let hi = calc.max(x1, x2)
      els.push(place(top + left, dx: lo + 3pt, dy: y - lh * lines(label) - 2pt,
        box(fill: white, inset: (x: 0.6pt), txt(label))))
      els.push(place(top + left, dx: lo, dy: y, line(length: hi - lo,
        stroke: (thickness: 0.6pt, dash: if s.dashed { "dashed" } else { none }))))
      if x2 > x1 {
        els.push(place(top + left, dx: x2 - 5pt, dy: y - 2.2pt,
          polygon(fill: black, (0pt, 0pt), (5pt, 2.2pt), (0pt, 4.4pt))))
      } else {
        els.push(place(top + left, dx: x2, dy: y - 2.2pt,
          polygon(fill: black, (5pt, 0pt), (0pt, 2.2pt), (5pt, 4.4pt))))
      }
      y += 5pt
    } else if s.t == "s" {
      k += 1
      let label = str(k) + "  " + s.label
      let x1 = x(s.a)
      y += 3pt
      els.push(place(top + left, dx: x1 + 3pt, dy: y,
        box(fill: white, inset: (x: 0.6pt), txt(label))))
      y += lh * lines(label) + 2pt
      els.push(place(top + left, dx: x1, dy: y, line(length: 14pt, stroke: 0.6pt)))
      els.push(place(top + left, dx: x1 + 14pt, dy: y, line(angle: 90deg, length: 8pt, stroke: 0.6pt)))
      els.push(place(top + left, dx: x1, dy: y + 8pt, line(length: 14pt, stroke: 0.6pt)))
      els.push(place(top + left, dx: x1, dy: y + 8pt - 2.2pt,
        polygon(fill: black, (5pt, 0pt), (0pt, 2.2pt), (5pt, 4.4pt))))
      y += 13pt
    } else if s.t == "g" {
      let d = stack.len()
      let x1 = if s.a == none { 3pt + d * 4pt } else { x(s.a) - colw * 0.45 + d * 4pt }
      let x2 = if s.b == none { w - 3pt - d * 4pt } else { x(s.b) + colw * 0.45 - d * 4pt }
      y += 4pt
      stack.push((kind: s.kind, cond: s.cond, x1: x1, x2: x2, y0: y))
      y += 14pt
    } else if s.t == "e" {
      let g = stack.last()
      y += 4pt
      els.push(place(top + left, dx: g.x1, dy: y, line(length: g.x2 - g.x1,
        stroke: (thickness: 0.5pt, dash: "dashed"))))
      els.push(place(top + left, dx: g.x1 + 4pt, dy: y + 2pt,
        box(fill: white, inset: (x: 0.6pt), txt("[" + s.cond + "]"))))
      y += 14pt
    } else if s.t == "x" {
      let g = stack.pop()
      y += 5pt
      els.push(place(top + left, dx: g.x1, dy: g.y0,
        rect(width: g.x2 - g.x1, height: y - g.y0, stroke: 0.6pt)))
      els.push(place(top + left, dx: g.x1, dy: g.y0, box(
        stroke: 0.6pt, fill: luma(235), inset: (x: 3pt, y: 2pt),
        text(size: size, weight: "bold", g.kind)) + h(3pt) + box(inset: (y: 2pt), txt("[" + g.cond + "]"))))
      y += 4pt
    } else if s.t == "n" {
      let x1 = x(s.a) - colw * 0.45
      let x2 = x(s.b) + colw * 0.45
      y += 5pt
      let hgt = lh * lines(s.body) + 6pt
      els.push(place(top + left, dx: x1, dy: y, rect(
        width: x2 - x1, height: hgt, stroke: 0.5pt, fill: rgb("#fbfbee"), inset: 3pt,
        txt(s.body))))
      y += hgt + 5pt
    } else if s.t == "d" {
      y += 8pt
      els.push(place(top + left, dx: 0pt, dy: y - 1.2pt, line(length: w, stroke: 0.6pt)))
      els.push(place(top + left, dx: 0pt, dy: y + 1.2pt, line(length: w, stroke: 0.6pt)))
      els.push(place(top + center, dy: y - lh / 2 - 2pt, box(
        fill: white, stroke: 0.6pt, inset: (x: 4pt, y: 2pt), txt(s.label))))
      y += 10pt
    }
  }
  y += 10pt
  let lifelines = ()
  for i in range(n) {
    lifelines.push(place(top + left, dx: x(i), dy: head, line(angle: 90deg, length: y - head,
      stroke: (thickness: 0.5pt, paint: luma(120), dash: "dashed"))))
  }
  block(width: w, height: y + head, {
    for e in lifelines { e }
    for e in els { e }
    for e in header(0pt) { e }
    for e in header(y) { e }
  })
})
