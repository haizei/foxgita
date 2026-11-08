import SwiftUI

struct ScoreCanvasView: View {
    let score: ScoreDocument
    var tick: Int = 0
    var range: ScoreRange?
    var notation: ScoreNotation = .tablature
    var showChords = true
    private let timeline: ScoreTimeline

    init(score: ScoreDocument,tick: Int = 0,range: ScoreRange? = nil,notation: ScoreNotation = .tablature,showChords: Bool = true,timeline: ScoreTimeline? = nil) {
        self.score = score; self.tick = tick; self.range = range; self.notation = notation; self.showChords = showChords
        self.timeline = timeline ?? ScoreTimeline(score: score)
    }

    var body: some View {
        VStack(spacing: 6) {
            if notation != .tablature { canvas(staff: true) }
            if notation != .staff { canvas(staff: false) }
        }
        .padding(.vertical,8)
        .background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(GitaTheme.borderSubtle,lineWidth: 1) }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(notation.title)，第\(timeline.barIndex(atTick: tick)+1)小节")
        .accessibilityValue(currentNotes)
    }

    private var currentNotes: String {
        let i = timeline.barIndex(atTick: tick)
        guard score.bars.indices.contains(i) else { return "" }
        return score.bars[i].events.map { event in
            event.chord ?? event.tones.map { tone in
                if let string = tone.string, let fret = tone.fret { return "\(string)弦\(fret)品" }
                return "音高\(tone.midi)"
            }.joined(separator: "、")
        }.joined(separator: "；")
    }

    private func canvas(staff: Bool) -> some View {
        Canvas { context,size in
            let anchor = size.width*0.24
            let shortest = timeline.shortestDuration
            let scale = max(28/Double(max(1,shortest)),(size.width-60)/Double(score.ticksPerQuarter*12))
            func x(_ position: Int) -> Double { anchor+Double(position-tick)*scale }
            let index = timeline.barIndex(atTick: tick)
            let lower = max(0,index-1), upper = min(score.bars.count,index+5)
            if let range {
                let rect = CGRect(x: x(timeline.startTick(ofBar: range.firstBar)),y: 24,width: x(timeline.startTick(ofBar: range.lastBar+1))-x(timeline.startTick(ofBar: range.firstBar)),height: size.height-30)
                context.fill(Path(rect),with: .color(GitaTheme.brand50))
            }
            let top = staff ? 0.0 : size.height*0.19
            let step = (size.height-top-18)/5
            if !staff {
                for string in 0..<6 {
                    let y = top+Double(string)*step
                    var line = Path(); line.move(to: .init(x: 38,y: y)); line.addLine(to: .init(x: size.width-10,y: y))
                    context.stroke(line,with: .color(GitaTheme.borderInactive),lineWidth: string > 2 ? 1.4 : 0.8)
                    context.draw(Text(["1 e","2 B","3 G","4 D","5 A","6 E"][string]).font(.system(size: 10)).foregroundStyle(GitaTheme.textSecondary),at: .init(x: 20,y: y))
                }
            }
            let visibleTones = score.bars[lower..<upper].flatMap { $0.events.flatMap(\.tones) }
            let steps = visibleTones.map { staffStep($0.midi+12) }
            let maxStep = max(9,steps.max() ?? 9), minStep = min(-8,steps.min() ?? -8)
            let unit = max(2,(size.height-32)/Double(maxStep-minStep))
            let bottom = 16+Double(maxStep)*unit
            if staff {
                for i in 0..<5 {
                    var line = Path(); line.move(to: .init(x: 40,y: bottom-Double(i*2)*unit)); line.addLine(to: .init(x: size.width-10,y: bottom-Double(i*2)*unit))
                    context.stroke(line,with: .color(GitaTheme.textSecondary),lineWidth: 0.7)
                }
                context.draw(Text("𝄞").font(.system(size: 45)).foregroundStyle(GitaTheme.textPrimary),at: .init(x: 22,y: bottom-4*unit))
            }
            for i in lower..<upper {
                let bar = score.bars[i], start = timeline.startTick(ofBar: i), barX = x(start)
                var divider = Path(); divider.move(to: .init(x: barX,y: 26)); divider.addLine(to: .init(x: barX-10,y: size.height-10))
                context.stroke(divider,with: .color(GitaTheme.borderSubtle),lineWidth: 1)
                context.draw(Text("\(bar.number)").font(.system(size: 9)).foregroundStyle(GitaTheme.textSecondary),at: .init(x: barX+5,y: size.height-4),anchor: .bottomLeading)
                for event in bar.events {
                    let eventX = x(start+event.tick)
                    guard eventX > 36, eventX < size.width+40 else { continue }
                    if showChords,let chord = event.chord {
                        context.draw(Text(chord).font(.system(size: 16,weight: .bold)).foregroundStyle(start+event.tick <= tick ? GitaTheme.brand500 : GitaTheme.textPrimary),at: .init(x: eventX,y: 12),anchor: .center)
                    }
                    if event.isRest,staff {
                        context.draw(Text(event.duration < score.ticksPerQuarter ? "𝄾" : "𝄽").font(.system(size: 22)).foregroundStyle(GitaTheme.textPrimary),at: .init(x: eventX,y: bottom-4*unit))
                    }
                    for tone in event.tones {
                        if staff { drawStaff(tone,event: event,x: eventX,bottom: bottom,unit: unit,context: &context) }
                        else if let string = tone.string,let fret = tone.fret {
                            let y = top+Double(string-1)*step
                            let width = max(25,min(90,Double(event.duration)*scale-5))
                            let rect = CGRect(x: eventX-12,y: y-10,width: width,height: 20)
                            context.fill(Path(roundedRect: rect,cornerRadius: 10),with: .color(fingerColor(tone.finger)))
                            let textColor = (tone.finger ?? 0) > 0 ? Color.black.opacity(0.85) : GitaTheme.textPrimary
                            context.draw(Text("\(fret)").font(.system(size: 14,weight: .bold)).foregroundStyle(textColor),at: .init(x: eventX,y: y))
                        }
                    }
                    if staff { drawChordStem(event,x: eventX,bottom: bottom,unit: unit,context: &context) }
                }
            }
            var cursor = Path(); cursor.move(to: .init(x: anchor,y: 22)); cursor.addLine(to: .init(x: anchor,y: size.height-10))
            context.stroke(cursor,with: .color(GitaTheme.brand500),lineWidth: 1.5)
            context.fill(Path(ellipseIn: .init(x: anchor-4,y: 18,width: 8,height: 8)),with: .color(GitaTheme.brand500))
        }
    }
    private func fingerColor(_ finger: Int?) -> Color {
        switch finger { case 1: GitaTheme.categoryYellow; case 2: GitaTheme.categoryPurple; case 3: GitaTheme.categoryOrangeSoft; case 4: GitaTheme.categoryBlueSoft; default: GitaTheme.bgSubtle }
    }
    private func staffStep(_ midi: Int) -> Int {
        let classes = [0,0,1,1,2,3,3,4,4,5,5,6]
        return (midi/12-1)*7+classes[midi%12]-30
    }
    private func drawStaff(_ tone: ScoreTone,event: ScoreEvent,x: Double,bottom: Double,unit: Double,context: inout GraphicsContext) {
        let step = staffStep(tone.midi+12), y = bottom-Double(step)*unit
        let rect = CGRect(x: x-5,y: y-3.5,width: 10,height: 7)
        if event.duration >= score.ticksPerQuarter*2 { context.stroke(Path(ellipseIn: rect),with: .color(GitaTheme.textPrimary),lineWidth: 1.4) }
        else { context.fill(Path(ellipseIn: rect),with: .color(GitaTheme.textPrimary)) }
        if [score.ticksPerQuarter*3,score.ticksPerQuarter*3/2,score.ticksPerQuarter*3/4].contains(event.duration) {
            context.fill(Path(ellipseIn: .init(x: x+9,y: y-1.5,width: 3,height: 3)),with: .color(GitaTheme.textPrimary))
        }
        if [1,3,6,8,10].contains(tone.midi%12) {
            context.draw(Text("♯").font(.system(size: 14)).foregroundStyle(GitaTheme.textPrimary),at: .init(x: x-12,y: y))
        }
        if step < 0 {
            for value in stride(from: -2,through: step,by: -2) { ledger(x: x,y: bottom-Double(value)*unit,context: &context) }
        } else if step > 8 {
            for value in stride(from: 10,through: step,by: 2) { ledger(x: x,y: bottom-Double(value)*unit,context: &context) }
        }
        if tone.tiedFromPrevious {
            var tie = Path(); tie.move(to: .init(x: x-22,y: y+6)); tie.addQuadCurve(to: .init(x: x-3,y: y+6),control: .init(x: x-12,y: y+14))
            context.stroke(tie,with: .color(GitaTheme.textPrimary),lineWidth: 1)
        }
    }
    private func drawChordStem(_ event: ScoreEvent,x: Double,bottom: Double,unit: Double,context: inout GraphicsContext) {
        let steps = event.tones.map { staffStep($0.midi+12) }
        guard let low = steps.min(),let high = steps.max(),event.duration < score.ticksPerQuarter*4 else { return }
        let up = low+high < 8,stemX = x+(up ? 5 : -5)
        let start = bottom-Double(up ? low : high)*unit
        let end = bottom-Double(up ? high : low)*unit+(up ? -5*unit : 5*unit)
        var stem = Path(); stem.move(to: .init(x: stemX,y: start)); stem.addLine(to: .init(x: stemX,y: end))
        context.stroke(stem,with: .color(GitaTheme.textPrimary),lineWidth: 1.2)
        let flags = event.duration <= score.ticksPerQuarter/4 ? 2 : (event.duration <= score.ticksPerQuarter/2 ? 1 : 0)
        for index in 0..<flags {
            let tip = end+Double(index)*(up ? 6 : -6)
            var flag = Path(); flag.move(to: .init(x: stemX,y: tip)); flag.addQuadCurve(to: .init(x: stemX+7,y: tip+(up ? 14 : -14)),control: .init(x: stemX+13,y: tip+(up ? 5 : -5)))
            context.stroke(flag,with: .color(GitaTheme.textPrimary),lineWidth: 2)
        }
        if event.duration == score.ticksPerQuarter/3 || event.duration == score.ticksPerQuarter*2/3 {
            context.draw(Text("3").font(.system(size: 9)).foregroundStyle(GitaTheme.textSecondary),at: .init(x: x,y: end+(up ? -8 : 8)))
        }
    }
    private func ledger(x: Double,y: Double,context: inout GraphicsContext) {
        var path = Path(); path.move(to: .init(x: x-9,y: y)); path.addLine(to: .init(x: x+9,y: y))
        context.stroke(path,with: .color(GitaTheme.textPrimary),lineWidth: 1)
    }
}

struct ScoreRangeOverview: View {
    let score: ScoreDocument
    let tick: Int
    @Binding var range: ScoreRange
    var onSeek: (Int) -> Void
    var totalTicks: Int? = nil
    var body: some View {
        GeometryReader { geometry in
            let width = max(1,geometry.size.width-20), count = Double(max(1,score.bars.count))
            ZStack(alignment: .leading) {
                Capsule().fill(GitaTheme.bgSubtle).frame(height: 30)
                ScoreOverviewTrack(count: score.bars.count,range: range).equatable().padding(.horizontal,10)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        onSeek(max(0,min(score.bars.count-1,Int((point.x-10)/width*count))))
                    }
                ForEach([false,true],id: \.self) { isEnd in
                    let value = isEnd ? range.lastBar+1 : range.firstBar
                    Text(isEnd ? "B" : "A").font(.system(size: 10,weight: .bold)).foregroundStyle(GitaTheme.brand500)
                        .frame(width: 18,height: 25).background(GitaTheme.bgSurface,in: RoundedRectangle(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(GitaTheme.brand500) }
                        .offset(x: Double(value)/count*width)
                        .gesture(DragGesture(coordinateSpace: .named("scoreOverview")).onChanged { value in
                            let bar = max(0,min(score.bars.count-1,Int((value.location.x-10)/width*count)))
                            if isEnd { range.lastBar = max(range.firstBar,bar) }
                            else { range.firstBar = min(range.lastBar,bar) }
                        })
                        .accessibilityLabel(isEnd ? "B 结束小节" : "A 起始小节")
                        .accessibilityValue("第\((isEnd ? range.lastBar : range.firstBar)+1)小节")
                }
                Circle().fill(GitaTheme.brand500).frame(width: 10,height: 10)
                    .offset(x: 10+Double(tick)/Double(max(1,totalTicks ?? score.totalTicks))*width-5).allowsHitTesting(false)
            }.frame(maxHeight: .infinity)
        }.frame(height: 36).coordinateSpace(name: "scoreOverview")
    }
}

private struct ScoreOverviewTrack: View,Equatable {
    let count: Int
    let range: ScoreRange
    var body: some View {
        Canvas { context,size in
            let columns = max(1,min(count,Int(size.width/3)))
            let width = size.width/Double(columns)
            for column in 0..<columns {
                let first = column*count/columns,last = max(first,(column+1)*count/columns-1)
                let selected = first <= range.lastBar && last >= range.firstBar
                let rect = CGRect(x: Double(column)*width,y: (size.height-8)/2,width: max(1,width-2),height: 8)
                context.fill(Path(roundedRect: rect,cornerRadius: 2),with: .color(selected ? GitaTheme.brand500.opacity(0.6) : GitaTheme.borderInactive))
            }
        }
    }
}

struct ScoreMovingCanvas: View {
    let score: ScoreDocument
    let timeline: ScoreTimeline
    let clock: ScoreVisualClock
    let range: ScoreRange
    let notation: ScoreNotation
    let showChords: Bool
    var body: some View {
        let _ = clock.revision
        TimelineView(.animation(minimumInterval: 1.0/60,paused: !clock.isAnimating)) { _ in
            ScoreCanvasView(score: score,tick: clock.tick,range: range,notation: notation,showChords: showChords,timeline: timeline)
        }
    }
}

struct ScoreMovingOverview: View {
    let score: ScoreDocument
    let timeline: ScoreTimeline
    let clock: ScoreVisualClock
    @Binding var range: ScoreRange
    var onSeek: (Int) -> Void
    var body: some View {
        let _ = clock.revision
        TimelineView(.animation(minimumInterval: 1.0/60,paused: !clock.isAnimating)) { _ in
            ScoreRangeOverview(score: score,tick: clock.tick,range: $range,onSeek: onSeek,totalTicks: timeline.totalTicks)
        }
    }
}
