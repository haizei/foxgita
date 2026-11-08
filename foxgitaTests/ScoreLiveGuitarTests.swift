import AVFoundation
import Foundation
import Testing
import UIKit
@testable import foxgita

/// Human-assisted physical acceptance. Saves numeric observations only, never PCM.
@MainActor struct ScoreLiveGuitarTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_LIVE_GUITAR_TEST"] == "1"))
    func phoneMicrophoneRecognizesRealChordsAndStrumTiming() async throws {
        #if targetEnvironment(simulator)
        Issue.record("A real guitar and the owner's physical iPhone are required.")
        #else
        let silent = ProcessInfo.processInfo.environment["GITA_LIVE_GUITAR_SILENT"] == "1"
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let panel = LiveGuitarPanel()
        panel.silent = silent
        let window = UIWindow(windowScene: scene)
        window.rootViewController = panel; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { window.isHidden = true; previous?.makeKey(); UIApplication.shared.isIdleTimerDisabled = idle }
        let setup = silent ? "纯收音：无示范音、无节拍器，跟屏幕提示。" : "连接耳机，跟屏幕与耳机节拍。"
        panel.set(title: "真实吉他听弹验证",detail: "\(setup)\n手机放在吉他旁。标准调弦，无变调夹。\n准备 C、G、Am 开放和弦。\n约64秒，先看提示准备4拍，再按大字提示弹。\n只保存音高与时间统计，不保存或上传录音。",beat: "准备好后点开始")
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while !panel.started && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard panel.started else { Issue.record("The user did not start the guitar probe."); return }
        let initialOutputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }
        let engine = ScoreAudioEngine()
        engine.demoVolume = 0; engine.clickVolume = silent ? 0 : 0.5
        let score = Self.clockScore
        var run = try ScoreRun(score: score,range: score.fullRange,speed: 1,loopLimit: 1)
        run.start(countIn: false)
        var observations: [LiveGuitarObservation] = []
        engine.onObservation = { observation,time in
            guard observations.count < 10_000 else { return }
            observations.append(.init(time: time,pitches: observation.pitches.keys.sorted(),rms: observation.rms,
                onset: observation.onset,quality: observation.quality.rawValue))
        }
        try await engine.start(run: run)
        defer { engine.stop() }
        let session = AVAudioSession.sharedInstance()
        var report = LiveGuitarReport(inputs: session.currentRoute.inputs.map { $0.portType.rawValue },
            outputs: session.currentRoute.outputs.map { $0.portType.rawValue },sampleRate: session.sampleRate,
            inputLatency: session.inputLatency,outputLatency: session.outputLatency,listening: engine.listening)
        report.initialOutputs = initialOutputs
        report.silentOutput = silent
        report.listeningUnavailableReason = engine.listeningUnavailableReason
        guard engine.listening else {
            panel.set(title: "收音未开启",detail: engine.listeningUnavailableReason ?? "检查耳机与麦克风权限",beat: "本轮未通过")
            try save(report); Issue.record("Live microphone input was unavailable.")
            try await Task.sleep(for: .seconds(5)); return
        }
        let timeout = ContinuousClock.now.advanced(by: .seconds(85))
        while engine.seconds < 64 && ContinuousClock.now < timeout && !panel.cancelled && scene.activationState == .foregroundActive {
            let time = engine.seconds
            let index = min(7,Int(time/8)),local = time-Double(index*8)
            let stage = Self.stages[index]
            let active = local >= 4
            let beat = Int(local.truncatingRemainder(dividingBy: 4))+1
            let strike: Bool = stage.kind == "late" ? local >= 4 && local.truncatingRemainder(dividingBy: 1) >= 0.5
                : local >= 4 && local.truncatingRemainder(dividingBy: 1) < 0.5
            let prompt = !active ? "准备 · \(4-Int(local))" : stage.kind == "silence" ? "保持安静"
                : stage.kind == "hold" ? (local < 4.6 ? "扫一次，保持" : "保持，不再弹")
                : strike ? "↓ 扫弦" : "等下一拍"
            let instruction = silent ? stage.instruction.replacingOccurrences(of: "跟耳机节拍",with: "跟屏幕节拍")
                .replacingOccurrences(of: "听到节拍后",with: "屏幕拍号变化后") : stage.instruction
            panel.set(title: "\(index+1)/8 · \(stage.title)",detail: instruction,beat: "\(prompt) · 第\(beat)拍",active: active)
            try await Task.sleep(for: .milliseconds(40))
        }
        let completed = engine.seconds >= 63.8 && !panel.cancelled && scene.activationState == .foregroundActive
        engine.stop()
        report.completed = completed
        report.observations = observations
        for (index,stage) in Self.stages.enumerated() {
            let start = Double(index*8+4)
            let samples = observations.filter { $0.time >= start && $0.time < start+4 }
            let reliable = samples.filter { $0.quality == ScoreInputQuality.reliable.rawValue }
            let expected = Set(stage.expected)
            let scores = reliable.map { sample -> Double in
                let played = Set(sample.pitches)
                return expected.isEmpty ? (played.isEmpty ? 1 : 0) : 2*Double(expected.intersection(played).count)/Double(expected.count+played.count)
            }
            var result = LiveGuitarStageResult(name: stage.title,samples: samples.count,reliableSamples: reliable.count,
                meanPitchF1: scores.isEmpty ? nil : scores.reduce(0,+)/Double(scores.count),
                strongPitchFraction: scores.isEmpty ? 0 : Double(scores.filter { $0 >= 0.75 }.count)/Double(scores.count),
                onsetTimes: samples.filter(\.onset).map { $0.time-start })
            if ["strum","wrong","late"].contains(stage.kind) {
                // Establish that the requested action was actually observed before
                // interpreting a low score as evidence for the negative control.
                let performed = Set(stage.kind == "wrong" ? [43,47,50,55,59,67] : stage.expected)
                let matching = reliable.filter { sample in
                    let played = Set(sample.pitches)
                    return 2*Double(performed.intersection(played).count)/Double(performed.count+played.count) >= 0.75
                }
                result.performedPitchFraction = reliable.isEmpty ? 0 : Double(matching.count)/Double(reliable.count)
                let offset = stage.kind == "late" ? 0.5 : 0.0
                let actualOnsets = matching.filter(\.onset).map { $0.time-start }
                result.matchedInstructionOnsets = (0..<4).filter { beat in
                    actualOnsets.contains { abs($0-Double(beat)-offset) < 0.24 }
                }.count
                let target = Self.stageScore(pitches: stage.expected)
                var grader = ScorePerformanceGrader(score: target,range: target.fullRange,speed: 1)
                for sample in samples {
                    grader.observe(.init(pitches: Dictionary(uniqueKeysWithValues: sample.pitches.map { ($0,1.0) }),rms: sample.rms,
                        onset: sample.onset,quality: ScoreInputQuality(rawValue: sample.quality) ?? .unreliable),at: sample.time-start)
                }
                grader.finish(at: 4)
                result.pitchAccuracy = grader.summary.pitchAccuracy
                result.rhythmAccuracy = grader.summary.rhythmAccuracy
                result.coverage = grader.summary.coverage
                result.totalScore = grader.summary.totalScore
            }
            report.stages.append(result)
        }
        try save(report)
        #expect(completed,"Capture must finish the whole human-assisted sequence.")
        #expect(report.stages[0].reliableSamples < max(3,report.stages[0].samples/10),"Silence should not look like reliable pitched guitar.")
        for i in 1...3 {
            #expect(report.stages[i].reliableSamples >= 10,"A held chord needs sufficient actual observations.")
            #expect(report.stages[i].strongPitchFraction >= 0.5,"Most reliable frames must match the complete expected chord.")
        }
        let correct = report.stages[4],wrong = report.stages[5],onTime = report.stages[6],late = report.stages[7]
        #expect((correct.pitchAccuracy ?? 0) >= (wrong.pitchAccuracy ?? 1)+0.2,"Wrong G against target C must score lower than correct C.")
        #expect((onTime.rhythmAccuracy ?? 0) >= (late.rhythmAccuracy ?? 1)+0.15,"Half-beat-late strums must score lower than on-time strums.")
        for i in 4...7 {
            #expect((report.stages[i].coverage ?? 0) >= 0.6,"Do not compare scores without sufficient observed coverage.")
            #expect((report.stages[i].performedPitchFraction ?? 0) >= 0.5,"Verify that the requested C or deliberately wrong G was actually played.")
            #expect(report.stages[i].matchedInstructionOnsets == 4,"All four requested on-time or half-beat-late attacks must be observed; silence/held notes cannot validate a negative control.")
        }
        panel.set(title: "采集已完成",detail: "本地音高与节奏统计已保存，正在核对。\n请先停止弹奏。",beat: "谢谢配合")
        print("[GitaGuitarProbe] completed=\(completed);frames=\(observations.count)")
        try await Task.sleep(for: .seconds(3))
        #endif
    }

    private func save(_ report: LiveGuitarReport) throws {
        let directory = URL.documentsDirectory.appendingPathComponent("ScoreDeviceValidation",isDirectory: true)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("guitar-report.json"),options: .atomic)
    }
    private static let stages: [LiveGuitarStage] = [
        .init(title: "安静基线",instruction: "双手轻按琴弦止音，全程不要弹。",kind: "silence",expected: []),
        .init(title: "C 和弦",instruction: "C：x32010。准备4拍，提示后扫一次，让和弦自然延音。",kind: "hold",expected: [48,52,55,60,64]),
        .init(title: "G 和弦",instruction: "G：320003。准备4拍，提示后扫一次，让和弦自然延音。",kind: "hold",expected: [43,47,50,55,59,67]),
        .init(title: "Am 和弦",instruction: "Am：x02210。准备4拍，提示后扫一次，让和弦自然延音。",kind: "hold",expected: [45,52,57,60,64]),
        .init(title: "正确 C 扫弦",instruction: "C：x32010。准备4拍，接着每拍向下扫一次，共4次。",kind: "strum",expected: [48,52,55,60,64]),
        .init(title: "故意弹错：G",instruction: "目标仍是 C，但请弹 G：320003。准备4拍，接着每拍向下扫，共4次。",kind: "wrong",expected: [48,52,55,60,64]),
        .init(title: "C 准时扫弦",instruction: "C：x32010。准备4拍，跟耳机节拍准时向下扫，共4次。",kind: "strum",expected: [48,52,55,60,64]),
        .init(title: "C 故意晚半拍",instruction: "C：x32010。准备4拍，每次听到节拍后等半秒再扫，跟随大字提示，共4次。",kind: "late",expected: [48,52,55,60,64])
    ]
    private static var clockScore: ScoreDocument {
        .init(title: "Local guitar validation clock",tempo: .init(bpm: 60),bars: (0..<16).map { .init(number: $0+1,events: []) })
    }
    private static func stageScore(pitches: [Int]) -> ScoreDocument {
        .init(title: "Local target",tempo: .init(bpm: 60),bars: [.init(number: 1,events: (0..<4).map {
            .init(tick: $0*960,duration: 960,tones: pitches.map { .init(midi: $0) })
        })])
    }
}

private struct LiveGuitarStage { var title: String; var instruction: String; var kind: String; var expected: [Int] }
private struct LiveGuitarObservation: Codable { var time: Double; var pitches: [Int]; var rms: Double; var onset: Bool; var quality: String }
private struct LiveGuitarStageResult: Codable {
    var name: String; var samples: Int; var reliableSamples: Int; var meanPitchF1: Double?; var strongPitchFraction: Double; var onsetTimes: [Double]
    var pitchAccuracy: Double?; var rhythmAccuracy: Double?; var coverage: Double?; var totalScore: Int?
    var performedPitchFraction: Double?; var matchedInstructionOnsets: Int?
}
private struct LiveGuitarReport: Codable {
    var inputs: [String]; var outputs: [String]; var sampleRate: Double; var inputLatency: Double; var outputLatency: Double; var listening: Bool
    var completed = false
    var silentOutput = false
    var initialOutputs: [String] = []
    var listeningUnavailableReason: String?
    var observations: [LiveGuitarObservation] = []
    var stages: [LiveGuitarStageResult] = []
}

@MainActor private final class LiveGuitarPanel: UIViewController {
    private let heading = UILabel(),detail = UILabel(),beat = UILabel(),button = UIButton(type: .system)
    var silent = false
    private(set) var started = false
    private(set) var cancelled = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let stack = UIStackView(arrangedSubviews: [heading,detail,beat,button]); stack.axis = .vertical; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,constant: -24),stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        heading.font = .systemFont(ofSize: 26,weight: .bold); detail.font = .systemFont(ofSize: 18)
        beat.font = .systemFont(ofSize: 30,weight: .bold)
        for label in [heading,detail,beat] { label.numberOfLines = 0; label.textAlignment = .center; label.adjustsFontForContentSizeCategory = true }
        button.setTitle(silent ? "开始纯收音验证" : "耳机已连接，开始验证",for: .normal); button.titleLabel?.font = .systemFont(ofSize: 21,weight: .bold)
        button.addTarget(self,action: #selector(start),for: .touchUpInside)
    }
    @objc private func start() {
        if started { cancelled = true; button.isEnabled = false }
        else { started = true; button.setTitle("停止验证",for: .normal) }
    }
    func set(title: String,detail text: String,beat value: String,active: Bool = false) {
        loadViewIfNeeded(); heading.text = title; detail.text = text; beat.text = value
        beat.textColor = active ? .systemGreen : .secondaryLabel
    }
}
