import CoreGraphics
import Foundation
import ImageIO

/// Reads printed fretboard geometry, not a dictionary of chord names.
/// -2 is unread, -1 is explicitly muted; values >= 0 are frets. Treble string first.
nonisolated struct TabPrintedDiagram: Codable, Sendable {
  var frets: [Int]
  var box: [Double]
  var staffTop: Double
  var staffGap: Double

  func resolved(_ marks: [String], range: TabStrumRangeEvidence? = nil) -> [String]? {
    guard frets.count == 6 else { return nil }
    let strings: [Int]
    if marks == ["↑"] || marks == ["↓"] {
      let crossed = range?.crossedStrings ?? Array(1...6)
      guard crossed.allSatisfy({ frets[$0-1] >= -1 }) else { return nil }
      strings = crossed.filter { frets[$0 - 1] >= 0 }
    } else {
      strings = marks.compactMap { $0.hasPrefix("x") ? Int($0.dropFirst()) : nil }
      guard strings.count == marks.count else { return nil }
    }
    guard !strings.isEmpty, strings.allSatisfy({ (1...6).contains($0) && frets[$0 - 1] >= 0 })
    else { return nil }
    return strings.map { "\($0):\(frets[$0 - 1])" }
  }
}

nonisolated enum TabDiagramReader {
  struct Change {
    var x: Double
    var diagram: TabPrintedDiagram?
  }
  static func changes(diagrams: [TabPrintedDiagram], columns: [Double]) -> [Change] {
    let changes = diagrams.map { d -> Change in
      guard let x = columns.min(by: { abs($0-d.box[0]) < abs($1-d.box[0]) }),
        abs(x-d.box[0]) <= d.staffGap*1.5 else {
        return Change(x:d.box[0],diagram:nil)
      }
      return Change(x:x,diagram:d)
    }.sorted { $0.x < $1.x }
    return changes.map { change in
      changes.count(where: { abs($0.x-change.x) < 0.000001 }) > 1
        ? Change(x:change.x,diagram:nil) : change
    }
  }
  static func diagrams(page: Data) -> [TabPrintedDiagram] {
    guard let src = CGImageSourceCreateWithData(page as CFData, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
      img.width <= 2048, img.height <= 2048 else { return [] }
    let w = img.width, h = img.height
    var pixels = [UInt8](repeating: 255, count: w * h)
    let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let c = CGContext(data: raw.baseAddress, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
      c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard ok else { return [] }
    func dark(_ x: Int, _ y: Int) -> Bool {
      (0..<w).contains(x) && (0..<h).contains(y) && pixels[y * w + x] < 140
    }
    func rail(_ x: Int, _ y: Int, small: Bool) -> Bool {
      (0..<w).contains(x) && (0..<h).contains(y) && pixels[y*w+x] < (small ? 185 : 140)
    }
    func near(_ x: Int, _ y: Int, small: Bool) -> Bool {
      (-1...1).contains { rail(x + $0,y,small:small) }
    }
    func marker(cx: Int, top: Int, gap: Double, step: Int, gridLeft: Int, gridRight: Int,includeClosingRow: Bool = false) -> Int {
      let small = gap < 8
      func ink(_ x: Int, _ y: Int) -> Bool { rail(x,y,small:small) }
      let first = Int((Double(top) - Double(step) * (small ? 0.7 : 0.53)).rounded())
      // The closing stroke of an open-string circle can sit immediately above
      // the nut. Excluding that row opens the counter and loses a clear O.
      let end = top - (small || includeClosingRow ? 0 : 1)
      let left = Int((Double(cx) - gap * 0.45).rounded())
      let right = Int((Double(cx) + gap * 0.45).rounded())
      var gridRows: [Int] = []
      var points = (first..<end).flatMap { yy in
        if small && (gridLeft...gridRight).count(where: { rail($0,yy,small:true) })*100
          > (gridRight-gridLeft+1)*85 { gridRows.append(yy); return [(x:Int,y:Int)]() }
        return (left...right).filter { ink($0, yy) }.map { (x: $0, y: yy) }
      }
      // A tiny open circle can meet the antialiased top rule. Keep that
      // observed closing stroke within the glyph's own bounds; do not let
      // the full horizontal rule expand the marker's bounding box.
      if small, let glyphLeft=points.map(\.x).min(), let glyphRight=points.map(\.x).max(),
        let glyphBottom=points.map(\.y).max() {
        for yy in gridRows where yy == glyphBottom+1 {
          points += (glyphLeft...glyphRight).filter { ink($0,yy) }.map { (x:$0,y:yy) }
        }
      }
      guard points.count >= (small ? 4 : 8),
        let l = points.map(\.x).min(), let r = points.map(\.x).max(),
        let t = points.map(\.y).min(), let b = points.map(\.y).max(),
        r-l >= (small ? 2 : 3), b-t >= (small ? 2 : 3)
      else { return -2 }
      if small && (l <= left || r >= right || t <= first) { return -2 }
      // Open circles have an enclosed white counter. Averaging a 3x3 centre
      // incorrectly calls a thin X an O, adding an unwanted open string.
      let width = r-l+1, height = b-t+1
      var outside = Set<Int>(), queue: [Int] = []
      for yy in 0..<height {
        for xx in 0..<width where xx == 0 || yy == 0 || xx == width-1 || yy == height-1 {
          let k = yy*width+xx
          if !ink(l+xx,t+yy), outside.insert(k).inserted { queue.append(k) }
        }
      }
      var i = 0
      while i < queue.count {
        let k = queue[i]; i += 1
        let x = k%width, y = k/width
        for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1),
          (x-1,y-1),(x-1,y+1),(x+1,y-1),(x+1,y+1)] {
          guard (0..<width).contains(nx), (0..<height).contains(ny) else { continue }
          let next = ny*width+nx
          if !ink(l+nx,t+ny), outside.insert(next).inserted { queue.append(next) }
        }
      }
      let hasCounter = (0..<height).contains(where: { yy in
        (0..<width).contains { xx in !ink(l+xx,t+yy) && !outside.contains(yy*width+xx) }
      })
      let cx0 = (l+r)/2, cx1 = (l+r+1)/2, cy0 = (t+b)/2, cy1 = (t+b+1)/2
      let centre = [ink(cx0,cy0),ink(cx0,cy1),ink(cx1,cy0),ink(cx1,cy1)]
      if hasCounter {
        let centred = [(cx0,cy0),(cx0,cy1),(cx1,cy0),(cx1,cy1)].contains { xx,yy in
          !ink(xx,yy) && !outside.contains((yy-t)*width+xx-l)
        }
        return centred && centre.count(where: { !$0 }) >= (small ? 2 : 3)
          && (0.7...1.5).contains(Double(width)/Double(height)) ? 0 : -2
      }
      return centre.count(where: { $0 }) >= 3 ? -1 : -2
    }
    let coverage = (0..<h).map { y in
      Double(pixels[y * w..<(y + 1) * w].count(where: { $0 < 190 })) / Double(w)
    }
    let longest = (0..<h).map { y -> Double in
      var run=0, best=0
      for x in 0..<w {
        if pixels[y*w+x] < 190 { run += 1; best=max(best,run) }
        else { run=0 }
      }
      return Double(best)/Double(w)
    }
    let bands = TabStaffBands.find(coverage: coverage,longLineCoverage:longest)
    var result: [TabPrintedDiagram] = []
    for (index, band) in bands.enumerated() {
      let staffGap = Double(band[5] - band[0]) / 5
      let begin = max(index == 0 ? 0 : bands[index - 1][5] + 1,
        band[0] - Int(staffGap * 13))
      let end = band[0] - 2
      guard begin < end else { continue }
      var grids: [(left: Int, top: Int, bottom: Int)] = []
      for y in begin..<end {
        // The second pass locates faint small-grid rules only. Finger ink and
        // position numerals still use the separate, stricter foreground mask.
        for softGrid in [false,true] {
        var x = 0
        while x < w {
          guard rail(x,y,small:softGrid) else { x += 1; continue }
          let l = x
          while x < w && rail(x,y,small:softGrid) { x += 1 }
          let r = x - 1, width = r - l
          guard (25...90).contains(width), (!softGrid || width < 40),
            !grids.contains(where: { abs($0.left - l) < 6 && y >= $0.top-2 && y <= $0.bottom+2 })
          else { continue }
          let gap = Double(width) / 5
          let small = gap < 8
          for step in Int((gap * 1.1).rounded())...Int((gap * 1.7).rounded()) {
            var bottom = y + step * 3
            guard bottom < end,
              (0..<6).allSatisfy({ i in
                (y...bottom).count(where: { near(Int((Double(l) + Double(i) * gap).rounded()), $0,small:small) })
                  >= Int(Double(step * 3) * 0.85)
              }),
              (1...3).allSatisfy({ row in
                (l...r).count(where: { xx in
                  (-1...1).contains { rail(xx,y + row * step + $0,small:softGrid) }
                }) > Int(Double(width) * 0.9)
              }) else { continue }
            // A faint antialiased rule can start one raster row before its
            // darkest centre. Reading cells from that edge includes the next
            // horizontal rule and falsely calls every string fretted.
            let gridTop: Int
            if small {
              func strength(_ top: Int) -> Int {
                (0...3).reduce(0) { sum,row in
                  sum + (l...r).count(where: { dark($0,top+row*step) })
                }
              }
              gridTop = (max(0,y-1)...min(end-3*step-1,y+1)).max { a,b in
                let av=strength(a), bv=strength(b)
                return av == bv ? abs(a-y) > abs(b-y) : av < bv
              }!
            } else { gridTop = y }
            bottom = gridTop+3*step
            var fretCount = 3
            while fretCount < 6 && bottom + step < end && (l...r).count(where: { xx in
              (-1...1).contains { dark(xx, bottom + step + $0) }
            }) > Int(Double(width) * 0.9)
              && (0..<6).allSatisfy({ i in
                (bottom...bottom+step).count(where: {
                  near(Int((Double(l)+Double(i)*gap).rounded()),$0,small:small)
                }) >= Int(Double(step)*0.85)
              }) {
              bottom += step; fretCount += 1
            }
            // A fingering applies immediately above its TAB system. Underlined
            // lyric digits much higher in the gap can mimic a tiny grid.
            guard Double(band[0]-bottom) <= staffGap*3 else { continue }
            grids.append((l, gridTop, bottom))
            // Keep unknown geometry as a chord change, never carry the previous
            // chord through a diagram whose position cannot be decoded.
            let positionInk = (max(0, l - Int(gap))..<max(0, l - 2)).reduce(0) { sum, xx in
              sum + (gridTop..<gridTop + step).count(where: { dark(xx, $0) })
            }
            var position: Int? = positionInk < 2 ? 1 : nil
            if positionInk >= 6 {
              let size = step + 4
              var glyph = [Int](repeating: 0, count: size*size)
              let left = l - Int(gap*1.5)
              var points: [(x:Int,y:Int)] = []
              for yy in 0..<size {
                for xx in 0..<size {
                  let px = left+xx, py = gridTop-2+yy
                  if px < l-2, py >= gridTop, py < gridTop+step, (0..<w).contains(px), (0..<h).contains(py) {
                    if dark(px,py) {
                      glyph[yy*size+xx] = 255-Int(pixels[py*w+px])
                      points.append((px,py))
                    }
                  }
                }
              }
              if let minX=points.map(\.x).min(), let maxX=points.map(\.x).max(),
                let minY=points.map(\.y).min(), let maxY=points.map(\.y).max(),
                minX > left, maxX < l-3, minY > gridTop, maxY < gridTop+step-1,
                Double(maxY-minY+1) >= Double(step)*0.4,
                (0.18...1.15).contains(Double(maxX-minX+1)/Double(maxY-minY+1)) {
                position = LocalTabReader.diagramPosition(glyph: glyph, size: size)
              }
            }
            var frets = [Int](repeating: -2, count: 6)
            if fretCount <= 4, let position {
              var barres = [[ClosedRange<Int>]](repeating: [],count:fretCount)
              for row in 0..<fretCount {
                let top = gridTop+row*step+(small ? 1 : 3), endY = gridTop+(row+1)*step-(small ? 1 : 2)
                guard top < endY else { continue }
                for yy in top..<endY {
                  var xx = l
                  while xx <= r {
                    guard dark(xx,yy) else { xx += 1; continue }
                    let start = xx
                    while xx <= r && dark(xx,yy) { xx += 1 }
                    if Double(xx-start) >= gap*3 { barres[row].append(start...xx-1) }
                  }
                }
              }
              for i in 0..<6 {
                let ideal = Double(l) + Double(i) * gap
                // Locate each actual vertical rule independently; interpolation alone
                // leaves thick/uneven rules looking like finger numerals.
                let cx = (Int(ideal.rounded()) - 2...Int(ideal.rounded()) + 2).max { a, b in
                  let ac = (gridTop...bottom).count(where: { rail(a,$0,small:small) })
                  let bc = (gridTop...bottom).count(where: { rail(b,$0,small:small) })
                  if small && ac == bc {
                    func shade(_ x: Int) -> Int {
                      guard (0..<w).contains(x) else { return 255*(bottom-gridTop+1) }
                      return (gridTop...bottom).reduce(0) { $0+Int(pixels[$1*w+x]) }
                    }
                    let av=shade(a), bv=shade(b)
                    if av != bv { return av > bv }
                  }
                  return ac == bc ? abs(Double(a) - ideal) > abs(Double(b) - ideal) : ac < bc
                }!
                let railColumns = Set((cx-2...cx+2).filter { xx in
                  small ? (gridTop...bottom).count(where: { rail(xx,$0,small:true) })*100 >= (bottom-gridTop+1)*80
                    : abs(xx-cx) <= 1
                })
                var fret = -2
                var faintCell = false
                for row in 0..<fretCount {
                  let top = gridTop + row * step + (small ? 1 : 3), endY = gridTop + (row + 1) * step - (small ? 1 : 2)
                  guard top < endY else { continue }
                  let left = Int((Double(cx) - gap * 0.35).rounded())
                  let right = Int((Double(cx) + gap * 0.35).rounded())
                  let ink = (left...right).filter { !railColumns.contains($0) }.reduce(0) { sum, xx in
                    sum + (top..<endY).count(where: { dark(xx, $0) })
                  }
                  let barre = barres[row].contains(where: { $0.contains(cx) })
                  if ink >= max(small ? 2 : 4, Int((gap * Double(step) * 0.03).rounded(.up))) || barre {
                    let clearCore = (left...right).filter { !railColumns.contains($0) }.contains { xx in
                      (top..<endY).contains { yy in
                        (0..<w).contains(xx) && pixels[yy*w+xx] < 120
                      }
                    }
                    if small && !barre && !clearCore { faintCell = true }
                    else { fret = row+1 }
                  }
                }
                // Faint extra ink could be either a higher finger or a watermark.
                // Do not silently choose the lower, clearer fret in that case.
                if faintCell { frets[5-i] = -2; continue }
                var topMark = marker(cx: cx, top: gridTop, gap: gap, step: step,gridLeft:l,gridRight:r)
                if topMark == -2 && !small {
                  topMark = marker(cx: cx,top: gridTop,gap: gap,step: step,gridLeft: l,gridRight: r,includeClosingRow: true)
                }
                if fret == -2 { fret = topMark }
                else if topMark == 0 || topMark == -1 { fret = -2 } // Contradictory overlay, not a finger.
                frets[5 - i] = fret > 0 ? fret + position - 1 : fret
              }
            }
            let boxTop = max(0,gridTop-step)
            result.append(.init(frets: frets,
              box: [Double(l) / Double(w), Double(boxTop) / Double(h),
                Double(width) / Double(w), Double(bottom+1-boxTop) / Double(h)],
              staffTop: Double(band[0]) / Double(h), staffGap: staffGap / Double(w)))
            break
          }
        }
        }
      }
    }
    return result
  }
}
