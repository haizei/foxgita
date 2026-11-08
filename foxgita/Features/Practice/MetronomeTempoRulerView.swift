//
//  MetronomeTempoRulerView.swift
//  foxgita
//

import SwiftUI

struct MetronomeTempoRulerView: View {
    let bpm: Int
    var onBpmChange: (Int) -> Void

    private static let tickValues = [40, 80, 120, 160]
    private static let labeledValues = [40, 80, 120, 160]

    var body: some View {
        GeometryReader { geo in
            let trackLeading: CGFloat = 0
            let trackWidth = max(1, geo.size.width - trackLeading * 2)
            let thumbX = trackLeading + MetronomeTempoRuler.thumbFraction(for: bpm) * trackWidth

            ZStack(alignment: .topLeading) {
                ForEach(Self.tickValues, id: \.self) { tick in
                    let x = trackLeading + MetronomeTempoRuler.fraction(for: tick) * trackWidth
                    let isCurrent = tick == bpm
                        && bpm >= MetronomeTempoRuler.rangeMin
                        && bpm <= MetronomeTempoRuler.rangeMax
                    Rectangle()
                        .fill(isCurrent ? GitaTheme.brand500 : GitaTheme.textTertiary)
                        .frame(width: 1, height: 16)
                        .position(x: x, y: 34)
                }

                Capsule()
                    .fill(GitaTheme.bgSubtle)
                    .frame(width: trackWidth, height: 4)
                    .position(x: trackLeading + trackWidth / 2, y: 34)

                Capsule()
                    .fill(GitaTheme.brand500)
                    .frame(width: max(4, thumbX - trackLeading), height: 4)
                    .position(x: trackLeading + max(4, thumbX - trackLeading) / 2, y: 34)

                Circle()
                    .fill(GitaTheme.brand500)
                    .frame(width: 14, height: 14)
                    .position(x: thumbX, y: 34)

                ForEach(Self.labeledValues, id: \.self) { label in
                    Text("\(label)")
                        .font(GitaFont.micro())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .position(
                            x: trackLeading + MetronomeTempoRuler.fraction(for: label) * trackWidth,
                            y: 53
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
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("速度刻度")
        .accessibilityValue("\(bpm) BPM")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onBpmChange(min(200, bpm + 1))
            case .decrement: onBpmChange(max(40, bpm - 1))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("metronome.speed.ruler")
    }
}
