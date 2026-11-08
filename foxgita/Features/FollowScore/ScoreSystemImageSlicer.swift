import Foundation
import ImageIO
import CoreGraphics

nonisolated struct ScoreSystemSlice: Sendable {
    var page: Int
    var number: Int
    var region: ScoreSystemRegion
    var image: Data
    var header: Data?

    var images: [Data] { (header.map { [$0] } ?? []) + [image] }
}

nonisolated enum ScoreSystemImageSlicer {
    static func slices(page data: Data, number: Int, tabOnly: Bool = false) -> [ScoreSystemSlice] {
        let fallback = [ScoreSystemSlice(page: number, number: 1, region: .fullPage, image: data)]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width <= 2048, image.height <= 2048 else { return fallback }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return fallback }
        var lines = [Double](repeating: 0, count: height), ink = lines
        for row in 0..<height {
            var dark = 0, longest = 0, run = 0
            for column in 0..<width {
                if pixels[row * width + column] < 190 {
                    dark += 1; run += 1; longest = max(longest, run)
                } else { run = 0 }
            }
            lines[row] = Double(longest) / Double(width)
            ink[row] = Double(dark) / Double(width)
        }
        var regions = ScoreSystemLayout.regions(longLineCoverage: lines, inkCoverage: ink)
        if tabOnly {
            let wideBands = TabStaffBands.find(coverage: ink)
            let bands = TabStaffBands.find(coverage: ink,longLineCoverage:lines)
            guard !bands.isEmpty, bands.count <= 30 else { return fallback }
            func region(around band: [Int], index: Int, all: [[Int]], narrow: Bool) -> ScoreSystemRegion {
                let gap=max(1,(band[5]-band[0])/5)
                let top=max(index==0 ? 0 : (all[index-1][5]+band[0])/2,band[0]-gap*2)
                let end=min(index+1==all.count ? height : (all[index+1][0]+band[5])/2,band[5]+gap*3+1)
                guard narrow else {
                    return .init(y:Double(top)/Double(height),height:Double(end-top)/Double(height))
                }
                let runs=band.map { row -> (Int,Int) in
                    var first=0, best=(0,0), run=0
                    for x in 0..<width {
                        if pixels[row*width+x] < 190 {
                            if run==0 { first=x }; run += 1
                            if run > best.1-best.0 { best=(first,x+1) }
                        } else { run=0 }
                    }
                    return best
                }
                let left=max(0,(runs.map(\.0).min() ?? 0)-gap*2)
                let right=min(width,(runs.map(\.1).max() ?? width)+gap*2)
                return .init(x:Double(left)/Double(width),y:Double(top)/Double(height),
                    width:Double(right-left)/Double(width),height:Double(end-top)/Double(height))
            }
            // Establish the original wide crops first. A recovered short suffix
            // must not change JPEG context or rerun old measures with new crops.
            if wideBands.count != regions.count || !zip(wideBands,regions).allSatisfy({ band,region in
                Double(band[0]) >= region.y*Double(height) && Double(band[5]) < (region.y+region.height)*Double(height)
            }) {
                regions=wideBands.enumerated().map { i,band in
                    region(around:band,index:i,all:wideBands,narrow:false)
                }
            }
            for (i,band) in bands.enumerated() where !wideBands.contains(band) {
                regions.append(region(around:band,index:i,all:bands,narrow:true))
            }
        }
        guard (tabOnly || regions.count > 1), let first = regions.first else { return fallback }
        let headerHeight = Int((first.y * Double(height)).rounded())
        let header = headerHeight > 0
            ? image.cropping(to: CGRect(x: 0, y: 0, width: width, height: headerHeight)).flatMap(jpeg) : nil
        var slices: [ScoreSystemSlice] = []
        for (index, region) in regions.enumerated() {
            let top = Int((region.y * Double(height)).rounded())
            let bottom = Int(((region.y + region.height) * Double(height)).rounded())
            let left=Int((region.x*Double(width)).rounded())
            let right=Int(((region.x+region.width)*Double(width)).rounded())
            guard let crop = image.cropping(to: CGRect(x: left, y: top, width: right-left, height: bottom - top)),
                  let bytes = jpeg(crop) else { return fallback }
            slices.append(.init(page: number, number: index + 1, region: region, image: bytes, header: header))
        }
        return slices
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
