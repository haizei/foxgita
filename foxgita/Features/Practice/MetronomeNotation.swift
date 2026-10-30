import SwiftUI

/// Notation is relative to the configured beat unit; subdivision timing stays unchanged.
struct MetronomeNotation {
    let noteValue: Int
    let rests: [Bool]
    let isTriplet: Bool

    init(beatUnit: Int, kind: MetronomeBeatKind) {
        let beat = Self(subdivision: .quarter, beatUnit: beatUnit)
        noteValue = beat.noteValue
        rests = [kind == .mute]
        isTriplet = false
    }

    init(subdivision: MetronomeSubdivision, beatUnit: Int) {
        let unit = MetronomeMeter.supportedDenominators.contains(beatUnit) ? beatUnit : 4
        switch subdivision {
        case .quarter: noteValue = unit
        case .fourSixteenths: noteValue = unit * 4
        default: noteValue = unit * 2
        }
        rests = subdivision.steps.map { $0.role == .rest }
        isTriplet = [.triplet, .tripletRestFirst, .tripletRestLast].contains(subdivision)
    }

    var beamCount: Int {
        switch noteValue {
        case 8: 1
        case 16: 2
        case 32: 3
        case 64: 4
        default: 0
        }
    }

    var hasHollowHead: Bool { noteValue == 2 }

}

/// Vector notes allow the same rhythm to be shown at every supported beat unit.
struct MetronomeNotationView: View {
    let notation: MetronomeNotation
    var color: Color = GitaTheme.textPrimary

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 72)
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 72 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let count = notation.rests.count
            let spacing: CGFloat = count == 1 ? 0 : 72 / CGFloat(count - 1)
            let startX: CGFloat = count == 1 ? 45 : 12
            let noteIndexes = notation.rests.indices.filter { !notation.rests[$0] }
            let beamed = notation.beamCount > 0 && noteIndexes.count > 1
            for index in notation.rests.indices {
                let x = startX + CGFloat(index) * spacing
                if notation.rests[index] {
                    drawRest(in: &context, x: x)
                    continue
                }
                let head = Path(ellipseIn: CGRect(x: x - 9, y: 51, width: 18, height: 12))
                if notation.hasHollowHead {
                    context.stroke(head, with: .color(color), lineWidth: 2.5)
                } else {
                    context.fill(head, with: .color(color))
                }
                var stem = Path()
                stem.move(to: CGPoint(x: x + 8, y: 56))
                stem.addLine(to: CGPoint(x: x + 8, y: 15))
                context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                if !beamed {
                    for flag in 0..<notation.beamCount {
                        let y = 15 + CGFloat(flag) * 7
                        var path = Path()
                        path.move(to: CGPoint(x: x + 8, y: y))
                        path.addCurve(to: CGPoint(x: x + 18, y: y + 23), control1: CGPoint(x: x + 8, y: y + 9), control2: CGPoint(x: x + 28, y: y + 9))
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
            }
            if beamed, let first = noteIndexes.first, let last = noteIndexes.last {
                for beam in 0..<notation.beamCount {
                    let rect = CGRect(x: startX + CGFloat(first) * spacing + 6.5, y: 14 + CGFloat(beam) * 7, width: CGFloat(last - first) * spacing + 3, height: 4)
                    context.fill(Path(rect), with: .color(color))
                }
            }
            if notation.isTriplet {
                var bracket = Path()
                bracket.move(to: CGPoint(x: 5, y: 10))
                bracket.addLine(to: CGPoint(x: 5, y: 3))
                bracket.addLine(to: CGPoint(x: 39, y: 3))
                bracket.move(to: CGPoint(x: 61, y: 3))
                bracket.addLine(to: CGPoint(x: 95, y: 3))
                bracket.addLine(to: CGPoint(x: 95, y: 10))
                context.stroke(bracket, with: .color(color), lineWidth: 1.5)
                context.draw(Text("3").font(.system(size: 13, weight: .medium)).foregroundStyle(color), at: CGPoint(x: 50, y: 4))
            }
        }
        .accessibilityHidden(true)
    }

    private func drawRest(in context: inout GraphicsContext, x: CGFloat) {
        if notation.noteValue == 2 {
            context.fill(Path(CGRect(x: x - 9, y: 35, width: 18, height: 6)), with: .color(color))
            var line = Path()
            line.move(to: CGPoint(x: x - 13, y: 42))
            line.addLine(to: CGPoint(x: x + 13, y: 42))
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        } else if notation.noteValue == 4 {
            var rest = Path()
            rest.move(to: CGPoint(x: x - 4, y: 18))
            rest.addLine(to: CGPoint(x: x + 4, y: 28))
            rest.addLine(to: CGPoint(x: x - 4, y: 37))
            rest.addLine(to: CGPoint(x: x + 5, y: 44))
            rest.addCurve(to: CGPoint(x: x - 3, y: 57), control1: CGPoint(x: x - 11, y: 39), control2: CGPoint(x: x - 10, y: 53))
            context.stroke(rest, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        } else {
            var stem = Path()
            stem.move(to: CGPoint(x: x - 4, y: 61))
            stem.addLine(to: CGPoint(x: x + 8, y: 23))
            context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            for flag in 0..<notation.beamCount {
                let y = 26 + CGFloat(flag) * 7
                context.fill(Path(ellipseIn: CGRect(x: x - 9, y: y - 4, width: 9, height: 8)), with: .color(color))
                var hook = Path()
                hook.move(to: CGPoint(x: x - 5, y: y + 3))
                hook.addQuadCurve(to: CGPoint(x: x + 8 - CGFloat(flag) * 2, y: y - 2), control: CGPoint(x: x + 2, y: y + 6))
                context.stroke(hook, with: .color(color), lineWidth: 2)
            }
        }
    }
}
