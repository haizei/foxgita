import SwiftUI
import UIKit

struct OriginalScorePageView: View {
    let image: UIImage
    let rows: [OriginalScoreRow]
    var numbers: [UUID: Int] = [:]
    var activeID: UUID?
    var fraction: Double = 0

    var body: some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            let box = row.box
                            Rectangle().fill(Color.orange.opacity(row.id == activeID ? 0.12 : 0.025))
                                .overlay(Rectangle().stroke(Color.orange, lineWidth: row.id == activeID ? 2 : 1))
                                .frame(width: geometry.size.width * box.width, height: geometry.size.height * box.height)
                                .position(x: geometry.size.width * (box.x + box.width / 2),
                                          y: geometry.size.height * (box.y + box.height / 2))
                                .id(row.id)
                            Text("\(numbers[row.id] ?? (index + 1))").font(.caption2.bold()).padding(3).background(.orange, in: Capsule())
                                .offset(x: geometry.size.width * box.x, y: geometry.size.height * box.y)
                            if row.id == activeID {
                                Rectangle().fill(.orange)
                                    .frame(width: 3, height: geometry.size.height * box.height)
                                    .position(x: geometry.size.width * (box.x + box.width * fraction),
                                              y: geometry.size.height * (box.y + box.height / 2))
                                    .accessibilityIdentifier("original.cursor")
                            }
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor enum OriginalScoreUITestPage {
    static var data: Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 900), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 900))
            ("原谱跟弹 · 测试谱页 4/4" as NSString).draw(at: CGPoint(x: 30, y: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
            UIColor.black.setStroke()
            for row in 0..<4 {
                for line in 0..<6 {
                    let y = CGFloat(130 + row * 160 + line * 12)
                    let path = UIBezierPath(); path.move(to: CGPoint(x: 40, y: y)); path.addLine(to: CGPoint(x: 600, y: y)); path.stroke()
                }
                for x in stride(from: 40, through: 600, by: 140) {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x, y: 130 + row * 160))
                    path.addLine(to: CGPoint(x: x, y: 190 + row * 160))
                    path.stroke()
                }
                ("0       2       3       2       0       2" as NSString).draw(at: CGPoint(x: 60, y: 145 + row * 160), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
#endif
