//
//  MetronomeTempoRulerView.swift
//  foxgita
//

import SwiftUI

struct MetronomeTempoRulerView: View {
    let bpm: Int
    var onBpmChange: (Int) -> Void

    private static let tickValues = Array(stride(from: MetronomeTempoRuler.rangeMin, through: MetronomeTempoRuler.rangeMax, by: 10))
    private static let labeledValues = [40, 80, 120, 160]

    var body: some View {
        GeometryReader { geo in
            let trackLeading: CGFloat = 11
            let trackWidth = max(1, geo.size.width - trackLeading * 2)
            let thumbX = trackLeading + MetronomeTempoRuler.thumbFraction(for: bpm) * trackWidth

            ZStack(alignment: .topLeading) {
                ForEach(Self.tickValues, id: \.self) { tick in
                    let x = trackLeading + MetronomeTempoRuler.fraction(for: tick) * trackWidth
                    let isMajor = tick % 40 == 0
                    let isCurrent = tick == bpm
                        && bpm >= MetronomeTempoRuler.rangeMin
                        && bpm <= MetronomeTempoRuler.rangeMax
                    Rectangle()
                        .fill(isCurrent ? GitaTheme.brand500 : GitaTheme.textTertiary)
                        .frame(width: isCurrent ? 3 : (isMajor ? 2 : 1), height: isCurrent ? 26 : (isMajor ? 20 : 12))
                        .position(x: x, y: 44)
                }

                Capsule()
                    .fill(GitaTheme.bgSubtle)
                    .frame(width: trackWidth, height: 4)
                    .position(x: trackLeading + trackWidth / 2, y: 44)

                Capsule()
                    .fill(GitaTheme.brand500)
                    .frame(width: max(4, thumbX - trackLeading), height: 4)
                    .position(x: trackLeading + max(4, thumbX - trackLeading) / 2, y: 44)

                Circle()
                    .fill(GitaTheme.brand500)
                    .frame(width: 16, height: 16)
                    .position(x: thumbX, y: 44)

                ForEach(Self.labeledValues, id: \.self) { label in
                    Text("\(label)")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .position(
                            x: trackLeading + MetronomeTempoRuler.fraction(for: label) * trackWidth,
                            y: 81
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x - trackLeading) / trackWidth
                        onBpmChange(MetronomeTempoRuler.bpm(forFraction: fraction))
                    }
            )
        }
        .frame(height: 112)
    }
}
