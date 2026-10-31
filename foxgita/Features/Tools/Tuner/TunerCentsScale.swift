import SwiftUI

struct TunerCentsScale: View {
    let cents: Double?
    let inTune: Bool
    var isHeld = false

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2).fill(GitaTheme.statusSuccess.opacity(0.08))
                        .frame(width: width * 0.12, height: 44).offset(x: width * 0.44)
                    ForEach(-10...10, id: \.self) { index in
                        Rectangle().fill(index.isMultiple(of: 5) ? GitaTheme.textSecondary : GitaTheme.borderInactive)
                            .frame(width: index.isMultiple(of: 5) ? 1.5 : 1, height: index.isMultiple(of: 5) ? 39 : 31)
                            .offset(x: CGFloat(index + 10) / 20 * width, y: index.isMultiple(of: 5) ? 1 : 5)
                    }
                    if let cents {
                        RoundedRectangle(cornerRadius: 2).fill(inTune ? GitaTheme.statusSuccess : GitaTheme.brand500)
                            .frame(width: 4, height: 45)
                            .offset(x: CGFloat(max(-50, min(50, cents)) + 50) / 100 * (width - 4))
                    }
                }
            }.frame(height: 44)
            HStack {
                Text("−50"); Spacer(); Text("−25"); Spacer(); Text("0"); Spacer(); Text("+25"); Spacer(); Text("+50")
            }.font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音准刻度")
        .accessibilityValue(cents.map {
            (isHeld ? String(localized: "上一读数") + " " : "") + String(format: "%+.0f cent", $0)
        } ?? String(localized: "等待声音"))
    }
}
