import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated struct ScoreBarSlice: Sendable {
  var page: Int
  var system: Int
  var number: Int
  /// The measure's target bounds in the original page, without crop overlap.
  var region: ScoreSystemRegion
  /// The actual image bounds in the original page, including horizontal padding.
  var cropRegion: ScoreSystemRegion
  var image: Data
  var context: Data?
  var isHeader = false

  var id: String { "p\(page)-s\(system)-b\(number)" }
  var images: [Data] { (context.map { [$0] } ?? []) + [image] }
}

nonisolated enum ScoreBarImageSlicer {
  static func slices(system: ScoreSystemSlice, rejectExtendedStems: Bool = false, includeHeaders: Bool = false) -> [ScoreBarSlice]
  {
    let fallback = [
      ScoreBarSlice(
        page: system.page, system: system.number, number: 1,
        region: system.region, cropRegion: system.region, image: system.image,
        context: system.header)
    ]
    guard let source = CGImageSourceCreateWithData(system.image as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width <= 2048, image.height <= 2048
    else { return fallback }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 255, count: width * height)
    let rendered = pixels.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered,
      let staff = rejectExtendedStems
        ? sixStringStaff(pixels, width, height)
        : staff(pixels: pixels, width: width, height: height)
    else { return fallback }
    let boundaries = barlines(
      pixels: pixels, width: width, staff: staff, rejectExtendedStems: rejectExtendedStems)
    guard boundaries.count >= 2 else { return fallback }
    let padding = max(3, Int((Double(staff.spacing) * 1.4).rounded()))
    var result: [ScoreBarSlice] = []
    for (index, pair) in zip(boundaries, boundaries.dropFirst()).enumerated() {
      let isHeader = index == 0 && tabHeaderOnly(image: image,pixels: pixels,width: width,staff: staff,left: pair.0,right: pair.1)
      if isHeader && !includeHeaders { continue }
      let left = max(0, pair.0 - padding)
      let right = min(width, pair.1 + padding + 1)
      guard
        let crop = image.cropping(to: CGRect(x: left, y: 0, width: right - left, height: height)),
        let data = jpeg(crop)
      else { return fallback }
      func region(left: Int, right: Int) -> ScoreSystemRegion {
        .init(
          x: system.region.x + system.region.width * Double(left) / Double(width),
          y: system.region.y, width: system.region.width * Double(right - left) / Double(width),
          height: system.region.height)
      }
      result.append(
        .init(
          page: system.page, system: system.number, number: result.count + 1,
          region: region(left: pair.0, right: pair.1), cropRegion: region(left: left, right: right),
          image: data, context: system.header,isHeader: isHeader))
    }
    return result
  }

  private struct Staff {
    var top: Int
    var bottom: Int
    var left: Int
    var right: Int
    var spacing: Int
  }

  /// A separate leading TAB/time-signature panel carries setup, not musical time.
  /// Require positive TAB evidence; narrow or empty measures alone are never discarded.
  private static func tabHeaderOnly(image: CGImage,pixels: [UInt8],width: Int,staff: Staff,left: Int,right: Int) -> Bool {
    let gap = staff.spacing
    guard right-left >= gap*3, right-left <= gap*9 else { return false }
    let innerLeft = left + max(2,gap/3), innerRight = right - max(2,gap/3)
    guard innerLeft < innerRight else { return false }
    // Real attacks normally extend into the rhythm lane. Keep them even alongside TAB.
    let belowStart = staff.bottom+max(2,gap/2), belowEnd = min(image.height,staff.bottom+gap*2)
    if belowStart < belowEnd,
       (belowStart..<belowEnd).contains(where: { y in (innerLeft..<innerRight).contains { pixels[y*width+$0] < 170 } }) { return false }
    let lines = (0..<6).map { staff.top+$0*gap }
    let rows = (staff.top...staff.bottom).filter { y in !lines.contains(where: { abs($0-y) <= max(2,gap/5) }) }
    let columns = (innerLeft..<innerRight).filter { x in rows.contains { pixels[$0*width+x] < 170 } }
    var groups: [[Int]] = []
    for x in columns {
      if let last = groups.last?.last, x-last <= max(2,gap/4) {
        groups[groups.count-1].append(x)
      } else { groups.append([x]) }
    }
    guard !groups.isEmpty, groups.count <= 2, let group = groups.first,
          let first = group.first, let last = group.last,
          last-first >= gap/2, last-first <= gap*2 else { return false }
    guard let canvas = CGContext(data: nil,width: 360,height: 180,bitsPerComponent: 8,bytesPerRow: 360,
                                 space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
    canvas.setFillColor(gray: 1,alpha: 1)
    canvas.fill(CGRect(x: 0,y: 0,width: 360,height: 180))
    // OCR expects horizontal words. Reorder the three vertical letters without
    // changing the source page or its coordinate system.
    let cuts = [max(0,staff.top-2),staff.top+gap*8/5,staff.top+gap*33/10,min(image.height,staff.bottom+3)]
    for i in 0..<3 {
      guard cuts[i+1] > cuts[i], let glyph = image.cropping(to: CGRect(
        x: max(0,first-2),y: cuts[i],width: min(image.width,last+3)-max(0,first-2),height: cuts[i+1]-cuts[i])) else { return false }
      canvas.draw(glyph,in: CGRect(x: 30+i*100,y: 30,width: 80,height: 110))
    }
    guard let montage = canvas.makeImage() else { return false }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    do { try VNImageRequestHandler(cgImage: montage).perform([request]) }
    catch { return false }
    return request.results?.contains { observation in
      guard let candidate = observation.topCandidates(1).first else { return false }
      return candidate.confidence >= 0.5 && candidate.string.replacingOccurrences(of: " ",with: "").uppercased() == "TAB"
    } == true
  }

  private static func sixStringStaff(_ pixels: [UInt8], _ width: Int, _ height: Int) -> Staff? {
    let coverage = (0..<height).map { y in
      Double(pixels[y * width..<(y + 1) * width].count(where: { $0 < 190 })) / Double(width)
    }
    let bands = TabStaffBands.find(coverage: coverage)
    guard bands.count == 1, let lines = bands.first else { return nil }
    let gap = (lines[5] - lines[0]) / 5
    // A brace is also vertical ink on six lines, but is detached from their long common span.
    var spans: [ClosedRange<Int>] = []
    var start: Int?
    var last = 0
    for x in 0..<width where lines.count(where: { pixels[$0 * width + x] < 190 }) >= 4 {
      if let first = start, x - last > 2 * gap {
        spans.append(first...last)
        start = nil
      }
      if start == nil { start = x }
      last = x
    }
    if let start { spans.append(start...last) }
    guard let span = spans.max(by: { $0.count < $1.count }), span.count * 2 >= width else {
      return nil
    }
    return Staff(
      top: lines[0], bottom: lines[5], left: span.lowerBound, right: span.upperBound, spacing: gap)
  }

  private static func staff(pixels: [UInt8], width: Int, height: Int) -> Staff? {
    var rows: [(y: Int, left: Int, right: Int)] = []
    var previousLineRow: Int?
    for y in 0..<height {
      var run = 0
      var longest = 0
      var right = 0
      for x in 0..<width {
        if pixels[y * width + x] < 190 {
          run += 1
          if run > longest {
            longest = run
            right = x
          }
        } else {
          run = 0
        }
      }
      guard Double(longest) / Double(width) >= 0.45 else { continue }
      defer { previousLineRow = y }
      if let previousLineRow, y - previousLineRow <= 1 { continue }
      rows.append((y, right - longest + 1, right))
    }
    var best: Staff?
    var bestSpan = 0
    for start in rows.indices where start + 4 < rows.count {
      let spacing = rows[start + 1].y - rows[start].y
      guard (3...40).contains(spacing) else { continue }
      var end = start + 1
      while end + 1 < rows.count, end - start < 5,
        abs(Double(rows[end + 1].y - rows[end].y - spacing)) <= max(1.5, Double(spacing) * 0.25)
      {
        end += 1
      }
      guard end - start >= 4 else { continue }
      let group = rows[start...end]
      let left = group.map(\.left).sorted()[group.count / 2]
      let right = group.map(\.right).sorted()[group.count / 2]
      if right - left > bestSpan {
        best = Staff(
          top: rows[start].y, bottom: rows[end].y, left: left, right: right, spacing: spacing)
        bestSpan = right - left
      }
    }
    return best
  }

  private static func barlines(pixels: [UInt8], width: Int, staff: Staff, rejectExtendedStems: Bool)
    -> [Int]
  {
    let tolerance = max(1, staff.spacing / 8)
    var candidates: [Int] = []
    for x in staff.left...staff.right {
      if rejectExtendedStems && x > staff.left + staff.spacing && x < staff.right - staff.spacing {
        let from = staff.bottom + max(2, staff.spacing / 3)
        let to = min(pixels.count / width, staff.bottom + staff.spacing)
        if to > from
          && (from..<to).allSatisfy({ y in
            (max(0, x - tolerance)...min(width - 1, x + tolerance)).contains {
              pixels[y * width + $0] < 190
            }
          })
        {
          continue
        }
      }
      var covered = 0
      var gap = 0
      var longestGap = 0
      for y in staff.top...staff.bottom {
        let dark =
          rejectExtendedStems
          ? pixels[y * width + x] < 190
          : (max(0, x - tolerance)...min(width - 1, x + tolerance)).contains {
            pixels[y * width + $0] < 190
          }
        if dark {
          covered += 1
          gap = 0
        } else {
          gap += 1
          longestGap = max(longestGap, gap)
        }
      }
      // Note stems usually begin within the staff; a barline must connect every string.
      if Double(covered) / Double(staff.bottom - staff.top + 1) >= 0.9,
        longestGap <= max(2, staff.spacing / 3)
      {
        if rejectExtendedStems && x > staff.left + staff.spacing && x < staff.right - staff.spacing
        {
          // Full-height sweep arrows can have a detached lower rhythm stem.
          // Their flared tips are not plain measure rules.
          let headRows =
            Array((staff.top + 2)...(staff.top + max(2, staff.spacing / 2)))
            + Array((staff.bottom - max(2, staff.spacing / 2))...(staff.bottom - 2))
          let fullStroke = Set(
            (-max(3, staff.spacing / 2)...max(3, staff.spacing / 2)).filter { dx in
              guard (0..<width).contains(x + dx) else { return false }
              let covered = (staff.top...staff.bottom).count { y in pixels[y * width + x + dx] < 190
              }
              return covered * 100 >= (staff.bottom - staff.top + 1) * 90
            })
          let wings = headRows.reduce(0) { sum, y in
            sum
              + (-max(3, staff.spacing / 2)...max(3, staff.spacing / 2)).count {
                abs($0) >= 2 && !fullStroke.contains($0) && (0..<width).contains(x + $0)
                  && pixels[y * width + x + $0] < 170
              }
          }
          let wingRows = headRows.count { y in
            (-max(3, staff.spacing / 2)...max(3, staff.spacing / 2)).count { dx in
              abs(dx) >= 2 && !fullStroke.contains(dx) && (0..<width).contains(x + dx)
                && pixels[y * width + x + dx] < 170
            } >= 2
          }
          // One rasterized row at a staff intersection is not an arrowhead.
          if wings >= 4 && wingRows >= 2 { continue }
        }
        candidates.append(x)
      }
    }
    var groups: [[Int]] = []
    for x in candidates {
      if let last = groups.last?.last, x - last <= tolerance * 2 + 1 {
        groups[groups.count - 1].append(x)
      } else {
        groups.append([x])
      }
    }
    let strokeCenters = groups.map { ($0[0] + $0[$0.count - 1]) / 2 }
    // Double and repeat barlines use several full-height strokes for one boundary.
    // Measure their separation after collapsing each stroke's pixel tolerance.
    var boundaryGroups: [[Int]] = []
    for center in strokeCenters {
      if let last = boundaryGroups.last?.last, center - last <= staff.spacing {
        boundaryGroups[boundaryGroups.count - 1].append(center)
      } else {
        boundaryGroups.append([center])
      }
    }
    let centers = boundaryGroups.map { ($0[0] + $0[$0.count - 1]) / 2 }
    // An incomplete staff edge must not turn a partial measure into a confident crop.
    guard let first = centers.first, let last = centers.last,
      first - staff.left <= staff.spacing, staff.right - last <= staff.spacing
    else { return [] }
    return centers
  }

  private static func jpeg(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
