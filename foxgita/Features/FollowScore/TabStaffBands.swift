import Foundation

/// TAB digits interrupt individual horizontal rules. Count all dark pixels across a row,
/// not just its longest unbroken run; require *six* regularly spaced rules.
nonisolated enum TabStaffBands {
  static func find(coverage: [Double], longLineCoverage: [Double]? = nil) -> [[Int]] {
    let wide = regular(coverage:coverage,minimum:0.55)
    guard let longest=longLineCoverage, longest.count==coverage.count,
      let last=wide.last else { return wide }
    let gap=Double(last[5]-last[0])/5
    // Only recover an unambiguous final short system. Long contiguous rules,
    // unlike total ink, exclude dense lyric and QR regions in the footer.
    let suffix=regular(coverage:longest,minimum:0.25).filter { band in
      Double(band[0]-last[5]) > gap*3 && Double(band[0]-last[5]) <= gap*30
        && abs(Double(band[5]-band[0])/5-gap) <= max(1.5,gap*0.2)
    }
    return suffix.count == 1 ? wide+suffix : wide
  }

  private static func regular(coverage: [Double], minimum: Double) -> [[Int]] {
    var rows: [Int] = []
    var y = 0
    while y < coverage.count {
      guard coverage[y] >= minimum else {
        y += 1
        continue
      }
      let first = y
      while y < coverage.count && coverage[y] >= minimum { y += 1 }
      if y - first <= 6 { rows.append((first + y - 1) / 2) }
    }
    var lines: [[Int]] = []
    var i = 0
    while i + 5 < rows.count {
      let six = Array(rows[i..<i + 6])
      let gap = Double(six[5] - six[0]) / 5
      if (4...40).contains(gap)
        && zip(six, six.dropFirst()).allSatisfy({
          abs(Double($1 - $0) - gap) <= max(1.5, gap * 0.20)
        })
      {
        lines.append(six)
        i += 6
      } else {
        i += 1
      }
    }
    return lines
  }
}
