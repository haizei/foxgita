import Foundation
import Testing
import UIKit

@testable import foxgita

@Suite @MainActor struct LocalTabReaderTests {
  @Test func shortSystemRequiresLongRulesRatherThanFooterInk() {
    var ink=[Double](repeating:0,count:330), longest=ink
    for y in stride(from:20,through:70,by:10) { ink[y]=0.8; longest[y]=0.8 }
    for y in stride(from:200,through:250,by:10) { ink[y]=0.35; longest[y]=0.03 }
    #expect(TabStaffBands.find(coverage:ink,longLineCoverage:longest).count == 1)
    for y in stride(from:200,through:250,by:10) { longest[y]=0.31 }
    #expect(TabStaffBands.find(coverage:ink,longLineCoverage:longest).count == 2)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func shortFinalSystemKeepsBothMeasuresAndOriginalCoordinates() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath:dir).appendingPathComponent("晴天-谱子3.jpg"))
    let page = try #require(ScoreImportSelection.images([data]).pages.first)
    let systems = ScoreSystemImageSlicer.slices(page:page,number:1,tabOnly:true)
    #expect(systems.count == 6)
    let last = try #require(systems.last)
    #expect(last.region.width < 0.5)
    let bars = ScoreBarImageSlicer.slices(system:last,rejectExtendedStems:true)
    #expect(bars.count == 2)
    let first = try #require(bars.first), final = try #require(bars.last)
    #expect(abs(first.region.x-80.0/950) < 0.004)
    #expect(abs(first.region.x+first.region.width-267.0/950) < 0.004)
    #expect(abs(final.region.x+final.region.width-373.0/950) < 0.004)
    #expect(try LocalTabReader.draft(pages:[page]).score.bars.count == 23)
    let diagrams=TabDiagramReader.diagrams(page:page)
    #expect(diagrams.count == 29)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func lyricDigitsDoNotAddFingeringDiagrams() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    for (page,count) in [(1,49),(2,68)] {
      let data = try Data(contentsOf: URL(fileURLWithPath:dir).appendingPathComponent("知足-知足\(page).jpg"))
      let image = try #require(ScoreImportSelection.images([data]).pages.first)
      #expect(TabDiagramReader.diagrams(page:image).count == count)
    }
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func smallDiagramWatermarksRemainUnresolved() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    for (page,x,y,strings) in [(1,814.0,1103.0,[3]),(2,322,518,[2,5]),(2,410,945,[2])] {
      let data = try Data(contentsOf: URL(fileURLWithPath:dir).appendingPathComponent("晴天-谱子\(page).jpg"))
      let image = try #require(ScoreImportSelection.images([data]).pages.first)
      let diagrams = TabDiagramReader.diagrams(page:image)
      let d = try #require(diagrams.min { a,b in
        abs(a.box[0]-x/950)+abs(a.box[1]-y/1343)
          < abs(b.box[0]-x/950)+abs(b.box[1]-y/1343)
      })
      #expect(abs(d.box[0]-x/950) < 0.005)
      #expect(abs(d.box[1]-y/1343) < 0.005)
      for string in strings { #expect(d.frets[string-1] == -2) }
    }
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func faintSmallGridBottomRuleDoesNotDropAWholeSystem() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("晴天-谱子3.jpg"))
    let page = try #require(ScoreImportSelection.images([data]).pages.first)
    let diagrams = TabDiagramReader.diagrams(page: page)
    let d = try #require(diagrams.min { a,b in
      abs(a.box[0]-137.0/950)+abs(a.box[1]-52.0/1343)
        < abs(b.box[0]-137.0/950)+abs(b.box[1]-52.0/1343)
    })
    #expect(abs(d.box[0]-137.0/950) < 0.005)
    #expect(abs(d.box[1]-52.0/1343) < 0.005)
    #expect(d.frets == [3,1,0,2,0,-1])
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func smallPrintedFingerboardsRetainDigitsAndOpenMarkers() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("晴天-谱子1.jpg"))
    let page = try #require(ScoreImportSelection.images([data]).pages.first)
    let diagrams = TabDiagramReader.diagrams(page: page)
    // Read from the supplied image, not common chord-name dictionary voicings.
    for (x,y,frets) in [(150.0,293.0,[3,1,2,0,0,-1]),(212,293,[3,1,0,3,-1,-1]),
      (295,293,[3,1,0,2,3,-1]),(134,463,[3,1,0,2,3,-1])] {
      let d = try #require(diagrams.min { a,b in
        abs(a.box[0]-x/950)+abs(a.box[1]-y/1343)
          < abs(b.box[0]-x/950)+abs(b.box[1]-y/1343)
      })
      #expect(abs(d.box[0]-x/950) < 0.005)
      #expect(abs(d.box[1]-y/1343) < 0.005)
      #expect(d.frets == frets)
    }
  }
  @Test func fourthFretIsNotRereadAsThirdFret() throws {
    let image = UIGraphicsImageRenderer(size: .init(width: 600, height: 300), format: {
      let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
    }()).image { context in
      UIColor.white.setFill(); context.fill(.init(x: 0, y: 0, width: 600, height: 300))
      let c = context.cgContext
      c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(1)
      for y in stride(from: 180, through: 230, by: 10) {
        c.move(to: .init(x: 20, y: y)); c.addLine(to: .init(x: 580, y: y))
      }
      for x in stride(from: 80, through: 130, by: 10) {
        c.move(to: .init(x: x, y: 100)); c.addLine(to: .init(x: x, y: 156))
      }
      for y in stride(from: 100, through: 156, by: 14) {
        c.move(to: .init(x: 80, y: y)); c.addLine(to: .init(x: 130, y: y))
      }
      c.strokePath()
      c.setFillColor(UIColor.black.cgColor)
      c.fillEllipse(in: .init(x: 127, y: 146, width: 6, height: 6))
    }
    let diagrams = TabDiagramReader.diagrams(page: try #require(image.pngData()))
    #expect(diagrams.count == 1)
    #expect(diagrams.first?.frets.first == 4)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func secondPositionBarreUsesPrintedPosition() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("知足-知足2.jpg"))
    let page = try #require(ScoreImportSelection.images([data]).pages.first)
    let diagrams = TabDiagramReader.diagrams(page: page)
    let bm = try #require(diagrams.min { a,b in
      abs(a.box[0] - 672.0/1280) + abs(a.box[1] - 918.0/1708)
        < abs(b.box[0] - 672.0/1280) + abs(b.box[1] - 918.0/1708)
    })
    #expect(bm.frets == [2,3,4,4,2,-1])
  }

  @Test func incompleteAndMutedShapesNeverBecomeOpenStrings() {
    let d = TabPrintedDiagram(frets:[0,1,0,2,3,-1],box:[0,0,0.1,0.1],staffTop:0.2,staffGap:0.01)
    #expect(d.resolved(["x6"]) == nil)
    #expect(d.resolved(["x5"]) == ["5:3"])
    #expect(d.resolved(["↓"]) == ["1:0","2:1","3:0","4:2","5:3"])
    var unread = d; unread.frets[0] = -2
    #expect(unread.resolved(["↓"]) == nil)
    #expect(unread.resolved(["x1"]) == nil)
    #expect(unread.resolved(["x0"]) == nil)
  }

  @Test func measuredSweepUsesOnlyCrossedStringsAndDoesNotGuessUnreadFrets() {
    var diagram = TabPrintedDiagram(frets: [-2,-2,0,2,-1,0],box: [0.1,0.1,0.1,0.1],staffTop: 0.3,staffGap: 0.01)
    let range = TabStrumRangeEvidence(top: 2,bottom: 5.4,staffSpacing: 15,shaftCoverage: 1,clearEnds: true,box: [0.2,0.3,0.02,0.1])
    #expect(diagram.resolved(["↑"],range: range) == ["3:0","4:2","6:0"])
    #expect(diagram.resolved(["↑"]) == nil)
    diagram.frets[3] = -2
    #expect(diagram.resolved(["↑"],range: range) == nil)
    diagram.frets = [0,0,0,2,2,0]
    var blurred = range; blurred.clearEnds = false
    #expect(blurred.crossedStrings == nil)
    // An unproven range keeps the legacy tentative voicing and its review flag.
    #expect(diagram.resolved(["↑"],range: blurred)?.count == 6)
  }

  @Test func missedOnsetDoesNotCarryPreviousChordAcrossAChange() {
    let c = TabPrintedDiagram(frets:[0,1,0,2,3,-1],box:[0.1,0.1,0.05,0.05],staffTop:0.2,staffGap:0.01)
    var g = c; g.box[0] = 0.3; g.frets = [3,0,0,0,2,3]
    let changes = TabDiagramReader.changes(diagrams:[c,g],columns:[0.1,0.5])
    #expect(changes.last(where: { $0.x <= 0.5 })?.diagram == nil)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func contaminatedPositionMustStayUnknown() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("知足-知足2.jpg"))
    let page = try #require(ScoreImportSelection.images([data]).pages.first)
    let diagrams = TabDiagramReader.diagrams(page: page)
    for (x,y) in [(1096.0,406.0),(852,670),(183,1196)] {
      let d = try #require(diagrams.min { a,b in
        abs(a.box[0]-x/1280)+abs(a.box[1]-(y-15)/1708)
          < abs(b.box[0]-x/1280)+abs(b.box[1]-(y-15)/1708)
      })
      #expect(d.frets.allSatisfy { $0 == -2 })
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SONG_DIR"] != nil))
  func printedChordChangesBindOnlyTheirOwnStrings() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["GITA_SONG_DIR"])
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("知足-知足1.jpg"))
    let pages = try ScoreImportSelection.images([data]).pages
    let draft = try LocalTabReader.draft(pages: pages)
    let bar = draft.score.bars[8] // Printed C changes to G at tick 8/16.
    #expect(bar.events.count == 8)
    #expect(bar.events.first?.tones.map(\.midi) == [48]) // C: fifth string, third fret.
    #expect(bar.events.first(where: { $0.tick == 8 * 240 })?.tones.map(\.midi) == [43])
    #expect(bar.events.first(where: { $0.tick == 4 * 240 })?.tones.map(\.midi) == [64, 60])
    #expect(draft.hasReviewedCoverage(bar))
    let fBar = draft.score.bars[10]
    #expect(fBar.events.first(where: { $0.tick == 0 })?.tones.map(\.midi) == [41])
    #expect(draft.hasReviewedCoverage(fBar))
    #expect(!draft.isConfirmed)
  }
  @Test func confirmedChordRespectsPrintedStringsAndCapo() {
    let shape: [Int?] = [0, 1, 0, 2, nil, nil]
    let tuning = [40, 45, 50, 55, 59, 64]
    #expect(
      TabChordResolution.tones(marks: ["x3", "x5"], frets: shape, tuning: tuning, capo: 6) == nil)
    #expect(
      TabChordResolution.tones(marks: ["x2"], frets: shape, tuning: tuning, capo: 6)?.map(\.midi)
        == [66])
    #expect(
      TabChordResolution.tones(marks: ["↓"], frets: shape, tuning: tuning, capo: 6)?.map(\.midi)
        == [70, 66, 61, 58])
  }

  @Test func missingTimeIsNotARest() {
    let bar = ScoreBar(
      number: 1, events: [.init(tick: 960, duration: 2880, tones: [.init(midi: 60)])])
    let draft = RecognizedScoreDraft(score: .init(title: "Test", bars: [bar]), issues: [])
    #expect(!draft.hasReviewedCoverage(bar))
    var corrected = bar
    corrected.events.append(.init(tick: 0, duration: 960, tones: []))
    #expect(draft.hasReviewedCoverage(corrected))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_TAB_QA_DIR"] != nil))
  func importedPagesOnSimulator() throws {
    let dir = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GITA_TAB_QA_DIR"]))
    for name in ["clean", "blur", "tilt", "synthetic", "independent"] {
      let data = try Data(contentsOf: dir.appendingPathComponent(name + ".png"))
      let begin = Date()
      let selection = try ScoreImportSelection.images([data])
      let draft = try LocalTabReader.draft(pages: selection.pages)
      let rows = try #require(draft.localReadings)
      let ordered = try draft.score.bars.map { try #require(rows[$0.id]) }
      let json = try JSONEncoder().encode(ordered)
      print(
        "GitaLocalTab \(name) \(Date().timeIntervalSince(begin)) \(String(decoding:json,as:UTF8.self))"
      )
      #expect(!draft.isConfirmed)
      if name == "clean" {
        #expect(draft.score.bars.count == 18)
        #expect(!draft.score.bars.allSatisfy(draft.hasReviewedCoverage))
      } else if name == "blur" || name == "tilt" {
        #expect(ordered.allSatisfy { $0.problem != nil })
        #expect(draft.score.soundingEvents.isEmpty)
      } else if name == "synthetic" {
        #expect(ordered.count == 2)
        #expect(
          ordered.allSatisfy {
            $0.problem == nil && $0.attacks.map(\.marks) == [["↑"], ["↑"], ["↑"], ["↑"]]
              && $0.attacks.map(\.length) == [4, 4, 4, 4]
          })
      }
    }
  }
}
