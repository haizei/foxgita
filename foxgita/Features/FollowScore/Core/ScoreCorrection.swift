import Foundation

nonisolated enum ScoreCorrection {
    static func split(score: inout ScoreDocument,barIndex: Int,afterBeats: Int) throws {
        guard score.bars.indices.contains(barIndex),score.bars.count < 2_000 else { throw ScoreValidationError.invalidRange }
        let original = score.bars[barIndex]
        guard (1...32).contains(original.numerator),(0...1_000_000).contains(original.number),afterBeats > 0,afterBeats < original.numerator,[2,4,8,16].contains(original.denominator),
              (24...61_440).contains(score.ticksPerQuarter) else { throw ScoreValidationError.invalidBar(original.number) }
        guard hasValidSource(original,in: score) else { throw ScoreValidationError.invalidBar(original.number) }
        let cut = score.ticksPerQuarter*4/original.denominator*afterBeats
        var first = original
        first.numerator = afterBeats; first.events = []
        var second = ScoreBar(number: original.number+1,numerator: original.numerator-afterBeats,denominator: original.denominator,events: [])
        second.content = original.content
        second.source = original.source
        if let source = original.source,let box = source.validBox {
            let firstWidth = box[2]*Double(afterBeats)/Double(original.numerator)
            first.source = .init(page: source.page,box: [box[0],box[1],firstWidth,box[3]])
            second.source = .init(page: source.page,box: [box[0]+firstWidth,box[1],box[2]-firstWidth,box[3]])
            guard first.source?.validBox != nil,second.source?.validBox != nil else { throw ScoreValidationError.invalidBar(original.number) }
        }
        for event in original.events {
            guard event.tick >= 0,event.duration > 0,event.tick <= score.length(of: original),event.duration <= score.length(of: original)-event.tick else { throw ScoreValidationError.invalidEvent(original.number) }
            if event.tick >= cut { var shifted = event; shifted.tick -= cut; second.events.append(shifted) }
            else if event.tick+event.duration <= cut { first.events.append(event) }
            else {
                var left = event; left.duration = cut-event.tick; first.events.append(left)
                var right = event; right.id = UUID(); right.tick = 0; right.duration = event.tick+event.duration-cut
                right.tones = right.tones.map { var tone = $0; tone.tiedFromPrevious = true; return tone }
                right.chord = nil; right.lyric = nil; second.events.append(right)
            }
        }
        score.bars.replaceSubrange(barIndex...barIndex,with: [first,second])
    }

    static func mergeWithNext(score: inout ScoreDocument,barIndex: Int) throws {
        guard score.bars.indices.contains(barIndex),score.bars.indices.contains(barIndex+1) else { throw ScoreValidationError.invalidRange }
        var first = score.bars[barIndex]
        let second = score.bars[barIndex+1]
        guard (1...32).contains(first.numerator),(1...32).contains(second.numerator),first.numerator+second.numerator <= 32,
              first.denominator == second.denominator,second.tempo == nil,second.section == nil,
              first.isSourceOnly == second.isSourceOnly else { throw ScoreValidationError.invalidBar(first.number) }
        guard hasValidSource(first,in: score),hasValidSource(second,in: score) else { throw ScoreValidationError.invalidBar(first.number) }
        if first.source != nil || second.source != nil {
            guard let firstSource = first.source,let secondSource = second.source,
                  let firstBox = firstSource.validBox,let secondBox = secondSource.validBox,
                  firstSource.page == secondSource.page else { throw ScoreValidationError.invalidBar(first.number) }
            let overlap = min(firstBox[1]+firstBox[3],secondBox[1]+secondBox[3])-max(firstBox[1],secondBox[1])
            guard overlap >= min(firstBox[3],secondBox[3])*0.5 else { throw ScoreValidationError.invalidBar(first.number) }
            let x = min(firstBox[0],secondBox[0]),y = min(firstBox[1],secondBox[1])
            first.source = .init(page: firstSource.page,box: [x,y,
                max(firstBox[0]+firstBox[2],secondBox[0]+secondBox[2])-x,
                max(firstBox[1]+firstBox[3],secondBox[1]+secondBox[3])-y])
            guard first.source?.validBox != nil else { throw ScoreValidationError.invalidBar(first.number) }
        }
        let offset = score.length(of: first)
        guard second.events.allSatisfy({ $0.tick >= 0 && $0.tick <= score.length(of: second) && $0.duration > 0 && $0.duration <= score.length(of: second)-$0.tick }) else { throw ScoreValidationError.invalidEvent(second.number) }
        first.events += second.events.map { var event = $0; event.tick += offset; return event }
        first.numerator += second.numerator
        score.bars.replaceSubrange(barIndex...barIndex+1,with: [first])
    }

    static func remove(score: inout ScoreDocument,barIndex: Int) throws {
        guard score.bars.indices.contains(barIndex),score.bars.count > 1 else { throw ScoreValidationError.invalidRange }
        var bars = score.bars
        bars.remove(at: barIndex)
        for index in barIndex..<bars.count {
            guard bars[index].number > Int.min else { throw ScoreValidationError.invalidBar(bars[index].number) }
            bars[index].number -= 1
        }
        score.bars = bars
    }

    private static func hasValidSource(_ bar: ScoreBar,in score: ScoreDocument) -> Bool {
        if let source = bar.source {
            guard source.page >= 1,source.box == nil || source.validBox != nil else { return false }
        }
        if bar.isSourceOnly {
            guard bar.events.isEmpty,bar.source?.validBox != nil,score.sourceID != nil else { return false }
        }
        return true
    }
}
