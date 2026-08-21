//
//  VideoAnalysisView.swift
//  foxgita
//

import Combine
import SwiftData
import SwiftUI

struct VideoAnalysisView: View {
    let recordingId: String
    let taskTitle: String
    let durationSec: Int
    var onDismiss: () -> Void
    var onReady: () -> Void

    @Environment(PracticeStore.self) private var store
    @Environment(ReviewJobRunner.self) private var runner
    @Environment(MemoryConsentCoordinator.self) private var consent
    @Query(filter: #Predicate<RecordingRef> { $0.deletedAt == nil })
    private var recordings: [RecordingRef]
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""

    @State private var displayPercent = 0
    @State private var didReportReady = false

    /// The percentage is a stage indicator, not real byte progress — a single
    /// completions call backs all three rows.
    private let tick = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    private enum StageState {
        case done, running, waiting

        var label: String {
            switch self {
            case .done: return String(localized: "分析完成")
            case .running: return String(localized: "分析中")
            case .waiting: return String(localized: "等待中")
            }
        }

        var tint: Color {
            switch self {
            case .done: return GitaTheme.statusSuccess
            case .running: return GitaTheme.brand500
            case .waiting: return GitaTheme.textTertiary
            }
        }
    }

    private var status: ReviewStatus {
        recordings.first { $0.id == recordingId }?.reviewStatus ?? .pending
    }

    private var mmss: String {
        let seconds = max(0, durationSec)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var stageStates: [StageState] {
        switch displayPercent {
        case ..<30: return [.running, .waiting, .waiting]
        case ..<90: return [.done, .running, .waiting]
        case ..<100: return [.done, .done, .running]
        default: return [.done, .done, .done]
        }
    }

    private var statusLine: String {
        switch displayPercent {
        case ..<30: return String(localized: "正在提取声音与关键帧")
        case ..<90: return String(localized: "正在按片段分析声音与手型")
        default: return String(localized: "正在建立前奏 / 主歌 / 副歌问题地图")
        }
    }

    private var failureBody: String {
        switch runner.lastFailureKind {
        case .prepare: return String(localized: "抽帧失败，没有生成分段诊断")
        case .parse: return String(localized: "结果无法解析，没有生成分段诊断")
        default: return String(localized: "网络中断，没有生成分段诊断")
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(taskTitle) · 本次练习 \(mmss)")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)

                        if status == .failed {
                            failureCard
                        } else {
                            progressCard
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                footer
            }
        }
        .onReceive(tick) { _ in advance() }
        .onAppear { syncReady() }
        .onChange(of: status) { _, _ in syncReady() }
        .memoryConsentGate()
    }

    private var header: some View {
        HStack {
            Button("返回") { onDismiss() }
                .font(.system(size: 14))
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(minWidth: 40, alignment: .leading)
            Text("AI 分段分析")
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 40, height: 1)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("正在按片段分析声音与手型")
                .font(GitaFont.headline())

            waveform

            VStack(spacing: 4) {
                Text("\(displayPercent)%")
                    .font(GitaFont.largeTitle())
                    .foregroundStyle(GitaTheme.brand500)
                Text(statusLine)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("已完成 \(displayPercent)% · \(statusLine)"))

            VStack(spacing: 0) {
                stageRow(String(localized: "前奏 · 节奏与拍点"), stageStates[0])
                stageRow(String(localized: "主歌 · 和弦切换"), stageStates[1])
                stageRow(String(localized: "副歌 · 动作与指法"), stageStates[2])
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.waveBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isBarFilled(index) ? GitaTheme.brand500 : GitaTheme.borderInactive)
                    .frame(width: 3, height: Self.waveHeights[index % Self.waveHeights.count])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    private func stageRow(_ title: String, _ state: StageState) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(GitaFont.callout())
            Spacer()
            Circle()
                .fill(state.tint)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(state.tint)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这次分析未完成")
                .font(GitaFont.headline())
            Text(failureBody)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if status == .failed {
                Button(action: retry) {
                    Text("重新分析")
                        .font(GitaFont.body(.semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(GitaTheme.brand500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button { onDismiss() } label: {
                    Text("后台生成并返回")
                        .font(GitaFont.body(.semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .contentShape(Capsule())
                        .overlay(Capsule().stroke(GitaTheme.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Text("录制内容已安全保存")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private func advance() {
        guard status == .pending, runner.isRunning(recordingId) else { return }
        displayPercent = min(90, displayPercent + 3)
    }

    private func syncReady() {
        guard status == .ready, !didReportReady else { return }
        didReportReady = true
        displayPercent = 100
        onReady()
    }

    private func retry() {
        Task { @MainActor in
            guard await consent.ensureDecided() == .proceed else { return }
            displayPercent = 0
            store.markReviewsPending(recordingIds: [recordingId])
            runner.enqueue([recordingId], baseURL: llmBaseURL, model: llmModel)
        }
    }

    private func isBarFilled(_ index: Int) -> Bool {
        index * 100 < displayPercent * Self.waveBarCount
    }

    private static let waveBarCount = 32
    private static let waveHeights: [CGFloat] = [10, 18, 26, 14, 30, 12, 22, 16]
}
