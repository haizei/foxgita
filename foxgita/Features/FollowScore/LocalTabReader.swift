import CoreGraphics
import Foundation
import ImageIO
import simd

/// Literal glyphs, ordered by stem. An arrow or cross alone supplies no sounding pitch.
nonisolated enum LocalTabReader {
  private struct Template {
    let char: String
    let aspect: Double
    let blocks: [SIMD16<UInt8>]
  }
  private static let bank = loadBank("tab-glyphs")
  private static let boldBank = loadBank("tab-bold-glyphs")
  private static func loadBank(_ name: String) -> [Template] {
    guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
      let data = try? Data(contentsOf: url), !data.isEmpty, data.count % 437 == 0
    else { return [] }
    return stride(from: 0, to: data.count, by: 437).map { i in
      let bits = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i + 1, as: UInt32.self) }
      return Template(
        char: String(UnicodeScalar(data[i])),
        aspect: Double(Float(bitPattern: UInt32(littleEndian: bits))),
        blocks: packed(Array(data[i + 5..<i + 437])))
    }
  }
  private static func packed(_ bytes: [UInt8]) -> [SIMD16<UInt8>] {
    bytes.withUnsafeBytes { raw in
      stride(from: 0, to: bytes.count, by: 16).map {
        raw.loadUnaligned(fromByteOffset: $0, as: SIMD16<UInt8>.self)
      }
    }
  }
  static func diagramPosition(glyph: [Int], size: Int) -> Int? {
    guard let value = Int(classify(glyph, size: size, large: true, threshold: 0.23)), (1...9).contains(value) else { return nil }
    return value
  }
  private static func groups(_ values: [Int]) -> [[Int]] {
    var out: [[Int]] = []
    for v in values {
      if out.last?.last == v - 1 { out[out.count - 1].append(v) } else { out.append([v]) }
    }
    return out
  }
  private static func classify(_ glyph: [Int], size: Int, bold: Bool = false, large: Bool = false,
    threshold: Double = 0.30)
    -> String
  {
    // Do not let a pale scan watermark expand the foreground bounding box.
    let floor = large ? 100 : 65
    let ink = glyph.indices.filter { glyph[$0] > floor }
    guard let l = ink.map({ $0 % size }).min(), let r = ink.map({ $0 % size }).max(),
      let t = ink.map({ $0 / size }).min(), let b = ink.map({ $0 / size }).max()
    else { return "?" }
    let w = r - l + 1
    let h = b - t + 1
    var norm: [UInt8] = []
    for y in 0..<24 {
      let sy = min(Double(b), max(Double(t), Double(t) + (Double(y) + 0.5) * Double(h) / 24 - 0.5))
      let j = Int(sy)
      let dy = sy - Double(j)
      for x in 0..<18 {
        let sx = min(
          Double(r), max(Double(l), Double(l) + (Double(x) + 0.5) * Double(w) / 18 - 0.5))
        let i = Int(sx)
        let dx = sx - Double(i)
        func row(_ k: Int) -> Double {
          Double(glyph[k * size + i]) * (1 - dx) + Double(glyph[k * size + min(i + 1, r)]) * dx
        }
        norm.append(UInt8((row(j) * (1 - dy) + row(min(j + 1, b)) * dy).rounded()))
      }
    }
    var best = threshold
    var mark = "?"
    let blocks = packed(norm)
    for tpl in (bold ? bank + boldBank : bank) {
      var lanes = SIMD16<UInt16>.zero
      for i in blocks.indices {
        let a = blocks[i]
        let b = tpl.blocks[i]
        lanes &+= SIMD16<UInt16>(
          truncatingIfNeeded: (a &- b).replacing(with: b &- a, where: b .> a))
      }
      let sum = (0..<16).reduce(0) { $0 + Int(lanes[$1]) }
      let d = Double(sum) / (255 * 432) + 0.045 * abs(log(Double(w) / Double(h) / tpl.aspect))
      if d < best {
        best = d
        mark = tpl.char
      }
    }
    return mark
  }
  static func read(_ slice: ScoreBarSlice) -> TabReading {
    let rejected = TabReading(problem: "未能清楚定位六根弦或小节线。请换清晰正面的原图，或手动补录。")
    guard slice.region.width < slice.cropRegion.width, !bank.isEmpty,
      let src = CGImageSourceCreateWithData(slice.image as CFData, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return rejected }
    let factor = Double(img.width) / slice.cropRegion.width
    let x0 = Int(((slice.region.x - slice.cropRegion.x) * factor).rounded())
    let w = Int((slice.region.width * factor).rounded())
    let h = img.height
    guard w >= 12, h >= 28, let crop = img.cropping(to: CGRect(x: x0, y: 0, width: w, height: h))
    else { return rejected }
    var pixels = [UInt8](repeating: 255, count: w * h)
    let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let c = CGContext(
          data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      c.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard ok else { return rejected }
    func p(_ x: Int, _ y: Int) -> Int {
      (0..<w).contains(x) && (0..<h).contains(y) ? Int(pixels[y * w + x]) : 255
    }
    let ruleRows = Set(
      (0..<h).filter { y in
        (0..<w).count(where: { p($0, y) < 185 }) * 100 > w * 65
      })
    /// Rule thickness varies across scans. Reconstruct the glyph through every
    /// dark rule row, using the nearest rows outside that complete rule stroke.
    func eraseRule(_ glyph: inout [Int], size: Int, left: Int, top: Int) {
      for j in 0..<size where ruleRows.contains(top + j) {
        var a = top + j - 1
        var b = top + j + 1
        while ruleRows.contains(a) { a -= 1 }
        while ruleRows.contains(b) { b += 1 }
        for k in 0..<size {
          let t = Double(top + j - a) / Double(b - a)
          glyph[j * size + k] =
            255 - Int((Double(p(left + k, a)) * (1 - t) + Double(p(left + k, b)) * t).rounded())
        }

      }
    }
    let rows = groups(ruleRows.sorted())
      .map { ($0.first! + $0.last!) / 2 }
    guard rows.count >= 6 else { return rejected }
    var lines: [Int] = []
    var best = 1.0
    for i in 0...rows.count - 6 {
      let six = Array(rows[i..<i + 6])
      let g = Double(six[5] - six[0]) / 5
      guard (5...32).contains(g) else { continue }
      let dev = zip(six, six.dropFirst()).map { abs(Double($1 - $0) / g - 1) }.max()!
      if dev < 0.24 && dev < best {
        best = dev
        lines = six
      }
    }
    guard lines.count == 6 else { return rejected }
    let g = zip(lines, lines.dropFirst()).map { $1 - $0 }.sorted()[2]
    let low = lines[5]
    let half = g / 2
    func u(_ scale: Double) -> Int { Int((Double(g) * scale).rounded(.toNearestOrEven)) }
    // Thin crisp rules have bright immediate neighbours; thick/defocused lines are not reliable glyph evidence.
    let edge = lines.flatMap { y in
      stride(from: 2, to: w - 2, by: 3).map { x in
        (p(x, y - 2) + p(x, y + 2)) / 2 - p(x, y)
      }
    }.sorted()
    guard !edge.isEmpty, edge[edge.count / 2] >= 98 else { return rejected }
    // In paired staff/TAB engraving the six lines often carry frets only. A
    // freestanding digit interrupts its own rule and has white space on both sides.
    // Keep the horizontal order and provenance; do not infer rhythm from spacing.
    func fretOnlyReading() -> TabReading {
      var columns: [(Int, Int, String)] = []
      for (s, cy) in lines.enumerated() {
        // Erase the long horizontal runs on the staff itself. Preserve short runs
        // (including the crossbar of a 4), then use the full connected glyph width.
        let radius = max(3, (g + 1) / 2)
        let n = radius * 2 + 1
        var ink = [Int](repeating: 0, count: n * w)
        for j in 0..<n {
          let y = cy - radius + j
          for x in 0..<w { ink[j * w + x] = 255 - p(x, y) }
          if abs(y - cy) <= max(2, g / 6) {
            for run in groups((0..<w).filter { ink[j * w + $0] > 57 }) where run.count > g {
              let l = max(0, run[0] - 1)
              let r = min(w - 1, run.last! + 1)
              for x in l...r { ink[j * w + x] = 0 }
            }
          }
        }
        let components = groups(
          (1..<w - 1).filter { x in (0..<n).contains(where: { ink[$0 * w + x] > 90 }) })
        var digits: [(ClosedRange<Int>, String)] = []
        for run in components {
          let a = run.first!
          let b = run.last!
          guard a >= 2, b < w - 2, b - a + 1 <= g, b - a + 1 >= 2 else { continue }
          let blank: (Int) -> Bool = { j in !(a...b).contains(where: { ink[j * w + $0] > 90 }) }
          let upper = (0..<max(0, radius - 1)).last(where: blank).map { $0 + 1 } ?? 0
          let lower = (min(n - 1, radius + 2)..<n).first(where: blank).map { $0 - 1 } ?? n - 1
          let ys = (upper...max(upper, lower)).filter { j in
            (a...b).contains(where: { ink[j * w + $0] > 90 })
          }
          guard let top = ys.first, let bottom = ys.last, top < radius, bottom > radius,
            bottom - top >= max(3, g / 3),
            top > 0
              || !(a...b).contains(where: {
                p($0, cy - radius - 1) < 150 && p($0, cy - radius) < 150
              }),
            bottom < n - 1
              || !(a...b).contains(where: {
                p($0, cy + radius + 1) < 150 && p($0, cy + radius) < 150
              })
          else { continue }
          var glyph = [Int](repeating: 0, count: n * n)
          for j in top...bottom { for x in a...b { glyph[j * n + x - a] = ink[j * w + x] } }
          // Some engravers print a thick digit directly on the string without a white
          // knockout. Reconnect its two halves only where ink exists on both sides.
          for x in a...b {
            for j in (radius - 1)...(radius + 1) {
              let index = j * n + x - a
              if glyph[index] == 0 {
                glyph[index] = min(
                  255 - p(x, cy - radius + j),
                  min(ink[(radius - 2) * w + x], ink[(radius + 2) * w + x]))
              }
            }
          }
          digits.append((a...b, classify(glyph, size: n, bold: true, large: g >= 11)))
        }
        var i = 0
        while i < digits.count {
          let a = digits[i].0.lowerBound
          var b = digits[i].0.upperBound
          var value = digits[i].1
          i += 1
          while i < digits.count, digits[i].0.lowerBound - b <= max(2, g / 3) {
            value += digits[i].1
            b = digits[i].0.upperBound
            i += 1
          }
          let pad = max(2, g / 3)
          guard a > pad, b + pad < w,
            (1...pad).contains(where: { p(a - $0, cy - 2) > 200 && p(a - $0, cy + 2) > 200 }),
            (1...pad).contains(where: { p(b + $0, cy - 2) > 200 && p(b + $0, cy + 2) > 200 }),
            let f = Int(value), (0...24).contains(f), String(f) == value
          else { continue }
          columns.append(((a + b) / 2, s + 1, "\(s+1):\(f)"))
        }
      }
      var attacks: [TabAttack] = []
      var left = 0
      for (x, _, mark) in columns.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
        if !attacks.isEmpty && x - left <= max(2, g / 4) {
          attacks[attacks.count - 1].marks.append(mark)
        } else {
          left = x
          let x0 = max(0, x - half)
          let x1 = min(w, x + half + 1)
          let y0 = max(0, lines[0] - half)
          let y1 = min(h, low + half + 1)
          let box = slice.region.originalBox([
            Double(x0) / Double(w), Double(y0) / Double(h), Double(x1 - x0) / Double(w),
            Double(y1 - y0) / Double(h),
          ])
          attacks.append(.init(start: 0, length: 0, marks: [mark], box: box))
        }
      }
      return attacks.isEmpty ? rejected : .init(attacks: attacks, problem: "已读到弦品，节奏待核对；请按原谱补录时值。")
    }
    func stemCenters(_ from: Int, _ to: Int) -> [Int] {
      let rows = (low + from)..<(low + to)
      return groups(
        (1..<w - 1).filter { x in rows.count(where: { p(x, $0) < 185 }) * 10 >= rows.count * 7 }
      )
      .filter { Double($0.count) <= max(2, Double(g) * 0.4) }.map {
        Int((Double($0.first! + $0.last!) / 2).rounded(.toNearestOrEven))
      }
    }
    func literalMarks(_ x: Int) -> [String] {
      var result: [String] = []
      let n = half * 2 + 1
      for (s, cy) in lines.enumerated() {
        var glyph = (0..<n * n).map { 255 - p(x - half + $0 % n, cy - half + $0 / n) }
        let thick = ruleRows.contains(cy - 1) || ruleRows.contains(cy + 1)
        if thick {
          eraseRule(&glyph, size: n, left: x - half, top: cy - half)
        } else {
          for k in 0..<n {
            glyph[half * n + k] = (glyph[(half - 1) * n + k] + glyph[(half + 1) * n + k]) / 2
          }
        }
        // Thick engraved rules often sit over a pale watermark. A real glyph
        // needs dark wings on both sides of the rule, not grey background ink.
        let sideThreshold = thick ? 130 : 75
        let side = glyph.indices.filter { abs($0 % n - half) >= 2 && glyph[$0] > sideThreshold }
        guard
          side.count(where: { $0 / n < half }) >= 2 && side.count(where: { $0 / n > half }) >= 2
        else { continue }
        var moment = 0
        var weight = 0
        for j in glyph.indices {
          let v = max(0, glyph[j] - 65)
          weight += v
          moment += (j % n - half) * v
        }
        let displacement = weight > 0 ? Double(moment) / Double(weight) : .infinity
        guard weight > 0, abs(displacement) <= Double(g) * (thick ? 0.34 : 0.24) else { continue }
        if thick && abs(displacement) > Double(g) * 0.24 {
          let center = x + Int(displacement.rounded())
          glyph = (0..<n * n).map { 255 - p(center - half + $0 % n, cy - half + $0 / n) }
          eraseRule(&glyph, size: n, left: center - half, top: cy - half)
        }
        // Chord stems legitimately cross printed frets. Narrow rails are
        // rejected below; broad, dark glyph wings remain eligible.
        if thick {
          let bodyRows = (0..<n).filter { j in
            (0..<n).count { k in abs(k - half) >= 2 && glyph[j * n + k] > 130 } >= 2
          }
          if let first = bodyRows.first, let last = bodyRows.last, first < half, last > half {
            for j in 0..<n where j < first || j > last {
              for k in 0..<n { glyph[j * n + k] = 0 }
            }
          }
        }
        // A fret must occupy its own string row. Disconnected technique text
        // above and a slur below must not be classified together as a digit.
        if g >= 11 && thick && (max(0,half-2)...half).allSatisfy({ row in
          !(0..<n).contains { glyph[row*n+$0] > sideThreshold }
        }) { continue }
        let small = classify(glyph, size: n, bold: true, large: g >= 11)
        let reach = max(half + 2, u(0.8))
        let rail = (-half...half).contains { dx in
          let band = (cy - reach...cy + reach)
          return band.count(where: { p(x + dx, $0) < 170 }) * 100 >= band.count * 90
        }
        let columns = (0..<n).filter { k in (0..<n).contains { j in glyph[j * n + k] > 90 } }
        let glyphWidth = (columns.last ?? 0) - (columns.first ?? 0) + 1
        if rail && small != "x" && glyphWidth <= 3 { continue }
        let ch = small
        result.append(ch == "x" ? "x\(s+1)" : "\(s+1):\(ch)")
      }
      return result
    }
    func lowResolutionArrow(_ x: Int) -> String? {
      var best = 0
      var mark: String?
      for i in 0..<4 {
        let a = lines[i]
        let b = lines[i + 2]
        let shaft = (a + 1..<b).filter { !lines.contains($0) }
        guard
          Double(shaft.count(where: { y in (-1...1).contains(where: { p(x + $0, y) < 185 }) }))
            / Double(shaft.count) >= 0.87
        else { continue }
        func flare(_ y: Int) -> Int { (-half...half).count { abs($0) >= 2 && p(x + $0, y) < 185 } }
        let up = (1..<u(0.72)).reduce(0) { $0 + flare(a + $1) }
        let down = (1..<u(0.72)).reduce(0) { $0 + flare(b - $1) }
        if max(up, down) >= 6 && min(up, down) <= 2 && max(up, down) > best {
          best = max(up, down)
          mark = up > down ? "↑" : "↓"
        }
      }
      return mark
    }
    func arrowObservation(_ x: Int) -> (mark: String, top: Int, bottom: Int)? {
      // Locate the actual shaft endpoints: short sweeps need not start on a
      // string rule. Rule intersections must not count as arrowhead wings.
      var runs: [(Int, Int)] = []
      var first: Int?, last = 0, white = 0
      for y in lines[0]...low where !ruleRows.contains(y) {
        if (-1...1).contains(where: { p(x+$0,y) < 185 }) {
          if first == nil { first = y }
          last = y; white = 0
        } else if first != nil {
          white += 1
          if white > 1 { runs.append((first!,last)); first = nil; white = 0 }
        }
      }
      if let first { runs.append((first,last)) }
      func flare(_ y: Int) -> Int {
        ruleRows.contains(y) ? 0 : (-half...half).count { abs($0) >= 2 && p(x+$0,y) < 185 }
      }
      var best = 0
      var observation: (mark: String, top: Int, bottom: Int)?
      for (a,b) in runs where b-a >= u(0.9) {
        let reach = min(u(0.72),(b-a)/2)
        guard reach > 1 else { continue }
        let up = (1..<reach).reduce(0) { $0 + flare(a + $1) }
        let down = (1..<reach).reduce(0) { $0 + flare(b - $1) }
        if max(up, down) >= 6 && min(up, down) <= 2 && max(up, down) > best {
          best = max(up, down)
          observation = (up > down ? "↑" : "↓",a,b)
        }
      }
      return observation
    }
    func arrow(_ x: Int) -> String? {
      g < 11 ? lowResolutionArrow(x) : arrowObservation(x)?.mark
    }
    func strumRange(_ x: Int) -> TabStrumRangeEvidence? {
      guard g >= 11, x-half >= 0, x+half < w,
            let observation = arrowObservation(x) else { return nil }
      func centerInk(_ y: Int) -> Bool { (-1...1).contains { p(x+$0,y) < 185 } }
      let ceiling = max(0,lines[0]-u(0.6)), floor = min(h-1,low+u(0.6))
      var top = observation.top, bottom = observation.bottom
      while top > ceiling && centerInk(top-1) { top -= 1 }
      while bottom < floor && centerInk(bottom+1) { bottom += 1 }
      let margin = max(2,u(0.3))
      guard top-margin >= 0, bottom+margin < h, top > ceiling, bottom < floor else { return nil }
      // Blank caps distinguish the arrow from a rhythm stem, slur or crop edge.
      let above = (top-margin..<top).filter { !ruleRows.contains($0) }
      let below = (bottom+1...bottom+margin).filter { !ruleRows.contains($0) }
      let clearEnds = above.count >= 2 && below.count >= 2
        && above.allSatisfy { !centerInk($0) } && below.allSatisfy { !centerInk($0) }
      let shaft = (top...bottom).filter { !ruleRows.contains($0) }
      guard !shaft.isEmpty else { return nil }
      func position(_ y: Int) -> Double {
        let index = min(4,max(0,(0..<5).last(where: { y >= lines[$0] }) ?? 0))
        return Double(index)+Double(y-lines[index])/Double(lines[index+1]-lines[index])
      }
      guard let box = slice.region.originalBox([
        Double(x-half)/Double(w),Double(top)/Double(h),
        Double(half*2+1)/Double(w),Double(bottom-top+1)/Double(h)
      ]) else { return nil }
      return .init(top: position(top),bottom: position(bottom),staffSpacing: g,
                   shaftCoverage: Double(shaft.count(where: centerInk))/Double(shaft.count),
                   clearEnds: clearEnds,box: box)
    }
    var stems = stemCenters(u(0.28), u(0.68))
    // A detached quarter stem starts lower. Require a real arrow above it and a clear gap
    // in between; a horizontal beam, barline, or stray ink cannot create an extra beat.
    var quarters = Set<Int>()
    for x in stemCenters(u(0.8), u(1.36)) where !stems.contains(where: { abs($0 - x) <= 2 }) {
      if (low + 1..<low + u(0.8)).contains(where: { p(x, $0) >= 210 }) {
        if arrow(x) != nil {
          quarters.insert(x)
          stems.append(x)
        } else if !literalMarks(x).isEmpty {
          stems.append(x)
        }
      }
    }
    stems.sort()
    // A faint neighbouring rail can split a single printed attack into two.
    // Keep the stronger below-staff stem when their glyph bands overlap.
    func stemStrength(_ x: Int) -> Int {
      (low + 1...low + u(1.7)).reduce(0) { $0 + max(0, 170 - p(x, $1)) }
    }
    var distinct: [Int] = []
    for x in stems {
      if let last = distinct.last, x - last < max(3, u(0.5)) {
        if stemStrength(x) > stemStrength(last) { distinct[distinct.count - 1] = x }
      } else {
        distinct.append(x)
      }
    }
    stems = distinct.filter { x in
      let edge = x <= u(0.5) || x >= w-u(0.5)
      let rail = (lines[0]...low).count { p(x,$0) < 185 }*100 >= (low-lines[0]+1)*90
      return !edge || !rail || arrow(x) != nil || !literalMarks(x).isEmpty
    }
    if stems.isEmpty { return fretOnlyReading() }
    guard stems.count <= 128 else { return rejected }
    var joins = [0]
    for (a, b) in zip(stems, stems.dropFirst()) {
      let inset = max(1, (b - a) / 3)
      let lo = a + inset
      let hi = b - inset
      guard hi >= lo else { return rejected }
      // Broad, pale watermark strokes can resemble a beam in larger scans.
      let beamInk = g >= 11 ? 130 : 185
      joins.append(
        groups(
          (low + u(0.5)..<low + u(2.4)).filter { y in
            (lo...hi).count(where: { p($0, y) < beamInk }) * 4 > (hi - lo + 1) * 3
          }
        ).count)
    }
    joins.append(0)
    var attacks: [TabAttack] = []
    var tick = 0
    var uncertain = false
    let literals = stems.map(literalMarks)
    let supported = literals.count { marks in
      marks.contains { !$0.contains("?") && !$0.hasSuffix(":1") }
    }
    let literalLayout = supported * 2 >= stems.count
    for (i, x) in stems.enumerated() {
      var marks: [String] = []
      let literal = literals[i]
      if literalLayout {
        // A numerically supported measure must not silently turn a rejected
        // glyph/rail into a sweep. Unresolved columns remain explicit.
        marks = literal.isEmpty ? ["?"] : literal
      } else if let dir = arrow(x) {
        marks = [dir]
      } else {
        marks = literal
      }
      let beams = max(joins[i], joins[i + 1])
      var quarterCandidate = false
      if beams == 0 && !quarters.contains(x) && !marks.isEmpty
        && !marks.contains(where: { $0.contains("?") })
      {
        let stemBand = (low + u(0.2))...(low + u(1.3))
        let single = stemBand.count(where: { p(x, $0) < 185 }) * 100 >= stemBand.count * 85
        let parallel = (2...max(2, u(0.6))).contains { offset in
          [-1, 1].contains { side in
            stemBand.count(where: { p(x + side * offset, $0) < 185 }) * 100 >= stemBand.count * 85
          }
        }
        quarterCandidate = single && !parallel
      }
      let length =
        beams == 1
        ? 2 : beams == 2 ? 1 : beams == 0 && quarters.contains(x) ? 4 : quarterCandidate ? 4 : 0
      if marks.isEmpty { marks = ["?"] }
      uncertain =
        uncertain || length == 0 || quarterCandidate || marks.contains(where: { $0.contains("?") })
      let left = max(0, x - half)
      let top = max(0, lines[0] - half)
      let right = min(w, x + half + 1)
      let bottom = min(h, low + u(1.8))
      let box = slice.region.originalBox([
        Double(left) / Double(w), Double(top) / Double(h),
        Double(right - left) / Double(w), Double(bottom - top) / Double(h),
      ])
      attacks.append(
        .init(
          start: tick, length: length, marks: marks, box: box,
          durationNeedsReview: quarterCandidate ? true : nil,
          strumRange: marks == ["↑"] || marks == ["↓"] ? strumRange(x) : nil))
      tick += length
    }
    for i in attacks.indices.dropLast() {
      for mark in attacks[i].marks {
        let pair = mark.split(separator: ":")
        guard pair.count == 2, let string = Int(pair[0]), let f = Int(pair[1]),
          attacks[i + 1].marks.contains(where: { other in
            let next = other.split(separator: ":")
            return next.count == 2 && next[0] == pair[0] && (Int(next[1]) ?? -1) > f
          })
        else { continue }
        let y = lines[string - 1]
        let a = stems[i]
        let b = stems[i + 1]
        let mid = (a + b) / 2
        let arc = [(a + 1, y - u(0.72)), (mid, y - u(0.89)), (b - 1, y - u(0.72))].allSatisfy {
          x, h in
          (-1...1).contains { dx in
            (-1...1).contains { dy in !lines.contains(h + dy) && p(x + dx, h + dy) < 185 }
          }
        }
        let ys = (y - u(2.2)..<y - u(1.2)).filter { !lines.contains($0) }
        let rails = [-1, 1].allSatisfy { side in
          (1...max(1, u(0.45))).contains { dx in
            ys.count(where: { p(mid + side * dx, $0) < 185 }) * 100 >= ys.count * 55
          }
        }
        if arc && rails && ys.contains(where: { p(mid, $0) < 185 })
          && ys.contains(where: { p(mid, $0) >= 185 })
        {
          attacks[i].hammerString = string
          // A printed H has two rails joined only in the middle. Requiring
          // blank counters above and below distinguishes it from adjacent
          // stems, digits and slur ink; the separate arc check is still needed.
          let labelTop = y-u(2.2), labelBottom = y-u(1.2)
          let labelHeight = labelBottom-labelTop
          let rails = [-1,1].map { side in
            (1...max(1,u(0.45))).filter { dx in
              ys.count(where: { p(mid+side*dx,$0) < 185 })*100 >= ys.count*75
            }.map { mid+side*$0 }
          }
          let clearH = rails[0].contains { left in
            rails[1].contains { right in
              guard right-left >= 3 else { return false }
              let middle = (labelTop+labelHeight/3...labelBottom-labelHeight/3)
              let bridge = middle.contains { row in
                (left...right).allSatisfy { p($0,row) < 185 }
              }
              let upper = labelTop..<labelTop+max(2,labelHeight/3)
              let lower = labelBottom-max(2,labelHeight/3)..<labelBottom
              return bridge && [upper,lower].allSatisfy { band in
                band.contains { row in p(mid,row) >= 210 && !ruleRows.contains(row) }
              }
            }
          }
          if g >= 11, clearH,
             let next = attacks[i+1].marks.first?.split(separator: ":"), next.count == 2,
             let toFret = Int(next[1]),
             let box = slice.region.originalBox([
               Double(max(0,a-half))/Double(w),Double(max(0,labelTop))/Double(h),
               Double(b-a+half*2+1)/Double(w),Double(y-labelTop+half)/Double(h)
             ]) {
            attacks[i].hammerEvidence = .init(string: string,fromFret: f,toFret: toFret,
                                              box: box,clearLabelAndArc: true)
          }
        }
      }
    }
    if g >= 11, ruleRows.contains(lines[0] + 1) || ruleRows.contains(lines[0] - 1),
      !attacks.flatMap(\.marks).contains(where: { $0.hasPrefix("x") || $0 == "↑" || $0 == "↓" })
    {
      let independent = fretOnlyReading()
      for candidate in independent.attacks {
        guard let cb = candidate.box else { continue }
        let cx = cb[0] + cb[2] / 2
        let nearest = attacks.indices.min { a, b in
          let ax = attacks[a].box.map { $0[0] + $0[2] / 2 } ?? -1
          let bx = attacks[b].box.map { $0[0] + $0[2] / 2 } ?? -1
          return abs(cx - ax) < abs(cx - bx)
        }
        guard let index = nearest, let ab = attacks[index].box,
          abs(cx - ab[0] - ab[2] / 2) * factor <= Double(g) * 0.5
        else { continue }
        for mark in candidate.marks {
          guard let string = mark.split(separator: ":").first else { continue }
          attacks[index].marks.removeAll { old in
            old == "?" || old.split(separator: ":").first == string
          }
          attacks[index].marks.append(mark)
        }
        attacks[index].marks.sort()
      }
    }
    let stemsThroughTop = (1..<w - 1).contains { x in
      p(x, lines[0] - 2) < 185 && p(x, lines[0] + 2) < 185
        && (lines[0] - 2...lines[0] + g).allSatisfy { y in
          lines.contains(y) || (-1...1).contains { p(x + $0, y) < 185 }
        }
    }
    if tick != 16 || uncertain,
      !attacks.flatMap(\.marks).contains(where: { $0.hasPrefix("x") }),
      stemsThroughTop || attacks.flatMap(\.marks).filter({ $0 == "↑" || $0 == "↓" }).count <= 2
    {
      let printedDigits = fretOnlyReading()
      if printedDigits.attacks.flatMap(\.marks).count
        > attacks.flatMap(\.marks).filter({ $0.contains(":") }).count
      {
        return printedDigits
      }
    }
    return .init(attacks: attacks, problem: tick == 16 && !uncertain ? nil : "符号或节拍不完整，请逐拍对照原谱。")
  }
}

extension LocalTabReader {
  /// Repair only empty, unconfirmed local candidates that exactly match a positively
  /// detected header panel. Never rerun recognition over a user's corrected music.
  nonisolated static func removingHeaderPanels(from draft: RecognizedScoreDraft,pages: [Data]) -> RecognizedScoreDraft {
    guard !draft.isConfirmed, draft.localReadings != nil,
          draft.score.bars.contains(where: { $0.events.isEmpty }) else { return draft }
    var headers: [ScoreSourceLocation] = []
    for (page,image) in pages.enumerated() {
      for system in ScoreSystemImageSlicer.slices(page: image,number: page+1,tabOnly: true) {
        for slice in ScoreBarImageSlicer.slices(system: system,rejectExtendedStems: true,includeHeaders: true) where slice.isHeader {
          let r = slice.region
          headers.append(.init(page: page+1,box: [r.x,r.y,r.width,r.height]))
        }
      }
    }
    let removed = draft.score.bars.filter { bar in
      guard bar.events.isEmpty, let source = bar.source, let box = source.validBox else { return false }
      return headers.contains { header in
        guard header.page == source.page, let target = header.validBox else { return false }
        return zip(box,target).allSatisfy { abs($0-$1) < 0.002 }
      }
    }
    guard !removed.isEmpty, removed.count < draft.score.bars.count else { return draft }
    var result = draft
    let ids = Set(removed.map(\.id)), numbers = Set(removed.map(\.number))
    result.score.bars.removeAll { ids.contains($0.id) }
    var renumbered: [Int:Int] = [:]
    for i in result.score.bars.indices {
      let old = result.score.bars[i]
      renumbered[old.number] = i+1
      result.score.bars[i].number = i+1
      if result.reviewedBars?[old.id] == old { result.reviewedBars?[old.id] = result.score.bars[i] }
    }
    for id in ids { result.localReadings?.removeValue(forKey: id); result.reviewedBars?.removeValue(forKey: id) }
    result.issues = result.issues.compactMap { issue in
      guard let number = issue.bar else { return issue }
      guard !numbers.contains(number) else { return nil }
      var copy = issue; copy.bar = renumbered[number] ?? number; return copy
    }
    return result
  }

  nonisolated static func draft(
    pages: [Data], checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }
  ) throws -> RecognizedScoreDraft {
    var score = ScoreDocument(title: "导入的六线谱", bars: [])
    var evidence: [UUID: TabReading] = [:]
    for (page, image) in pages.enumerated() {
      try checkCancellation()
      let diagrams = TabDiagramReader.diagrams(page: image)
      try checkCancellation()
      for system in ScoreSystemImageSlicer.slices(page: image, number: page + 1, tabOnly: true) {
        try checkCancellation()
        let slices = ScoreBarImageSlicer.slices(system: system, rejectExtendedStems: true)
        let readings = try slices.map { slice in
          try checkCancellation()
          return read(slice)
        }
        let columns = readings.flatMap(\.attacks).compactMap { a in
          a.box.map { $0[0] + $0[2] / 2 }
        }
        let systemDiagrams = diagrams.filter {
          $0.staffTop >= system.region.y && $0.staffTop < system.region.y + system.region.height
        }
        let changes = TabDiagramReader.changes(diagrams:systemDiagrams,columns:columns)
        for (slice, originalReading) in zip(slices, readings) {
          try checkCancellation()
          var reading = originalReading
          for i in reading.attacks.indices {
            guard let box = reading.attacks[i].box else { continue }
            let x = box[0] + box[2] / 2
            guard let change = changes.last(where: { $0.x <= x + 0.000001 }),
              let diagram = change.diagram,
              let binding = diagram.resolved(reading.attacks[i].marks,range: reading.attacks[i].strumRange) else { continue }
            reading.attacks[i].diagramBinding = binding
            reading.attacks[i].diagramBox = diagram.box
            if let crossed = reading.attacks[i].strumRange?.crossedStrings {
              reading.attacks[i].strumRange?.mutedStrings = crossed.filter { diagram.frets[$0-1] == -1 }
            }
          }
          let r = slice.region
          let source = ScoreSourceLocation(page: page + 1, box: [r.x, r.y, r.width, r.height])
          var bar = ScoreBar(number: score.bars.count + 1, events: [], source: source)
          guard bar.number <= 2_000 else { throw ScoreRecognitionError.tooLarge }
          evidence[bar.id] = reading
          // Incomplete timing stays as visual evidence only, never inferred silence.
          bar.events = reading.recognizedEvents(tuning: score.tuning,capo: score.capo,page: page+1)
          score.bars.append(bar)
        }
      }
    }
    try checkCancellation()
    guard !score.bars.isEmpty else { throw ScoreRecognitionError.invalidFile }
    return .init(
      score: score,
      issues: [.init(field: "setup", message: RecognizedScoreDraft.localSetupMessage)],
      localReadings: evidence,localRecognitionVersion: RecognizedScoreDraft.currentLocalRecognitionVersion)
  }
}
