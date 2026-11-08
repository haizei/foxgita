import SwiftUI

private enum SpeedSheetTab: String, CaseIterable, Identifiable {
    case adjust = "调速"
    case ramp = "变速"
    var id: Self { self }
}

struct MetronomeSpeedSheet: View {
    let controller: MetronomeTempoController
    var onDone: () -> Void
    var onStartRamp: (TempoRampSettings) -> Void
    var onEndRamp: (Int?) -> Void
    var practiceItemId: UUID?

    @State private var selectedTab: SpeedSheetTab = .adjust
    @State private var rampSettings: TempoRampSettings
    @State private var pendingManualTempo: Int?
    @State private var showRampHelp = false
    @State private var tapStartedAt: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("metronome.ramp-help-seen") private var hasSeenRampHelp = false

    init(
        controller: MetronomeTempoController,
        onDone: @escaping () -> Void,
        onStartRamp: @escaping (TempoRampSettings) -> Void = { _ in },
        onEndRamp: @escaping (Int?) -> Void = { _ in },
        practiceItemId: UUID? = nil
    ) {
        self.controller = controller
        self.onDone = onDone
        self.onStartRamp = onStartRamp
        self.onEndRamp = onEndRamp
        self.practiceItemId = practiceItemId
        _rampSettings = State(initialValue: controller.savedRampSettings ?? .suggested(currentBPM: controller.engine.bpm))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button(action: onDone) {
                    Capsule().fill(Color(.systemGray3))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12).padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.height > 40,
                           value.translation.height > abs(value.translation.width) {
                            onDone()
                        }
                    }
                )
                .accessibilityLabel("收起速度设置")
                .accessibilityIdentifier("metronome.speed.handle")
                segmentedControl
                if selectedTab == .ramp {
                    rampPanel.padding(.top, 16)
                } else {
                    adjustPanel.padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
        .background(GitaTheme.bgSurface)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(sheetHeight)])
        .presentationCornerRadius(24)
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metronome.speed-sheet")
        .onAppear {
            MetronomeAnalytics.emit(
                "metronome_speed_sheet_opened", itemId: practiceItemId?.uuidString ?? "",
                ["current_bpm": String(controller.engine.bpm), "playing": String(controller.engine.isPlaying)]
            )
        }
        .onDisappear { controller.resetTap() }
        .accessibilityAction(.escape, onDone)
        .onChange(of: selectedTab) { _, tab in
            guard tab == .ramp else { return }
            controller.resetTap()
            MetronomeAnalytics.emit(
                "metronome_ramp_settings_opened", itemId: practiceItemId?.uuidString ?? "",
                ["current_bpm": String(controller.engine.bpm), "last_plan": String(controller.savedRampSettings != nil)]
            )
            if !hasSeenRampHelp { showRampHelp = true }
        }
        .confirmationDialog(
            "变速训练进行中",
            isPresented: Binding(
                get: { pendingManualTempo != nil },
                set: { if !$0 { pendingManualTempo = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let value = pendingManualTempo {
                Button("调整当前档为 \(value) BPM") {
                    controller.handleManualChange(value, choice: .adjustCurrentStage)
                    pendingManualTempo = nil
                }
            }
            Button("结束变速训练", role: .destructive) {
                onEndRamp(pendingManualTempo)
                pendingManualTempo = nil
            }
            Button("取消", role: .cancel) { pendingManualTempo = nil }
        } message: {
            Text("手动改速会影响当前训练进度，请选择处理方式。")
        }
        .alert("变速训练", isPresented: $showRampHelp) {
            Button("知道了") { hasSeenRampHelp = true }
        } message: {
            Text("先按当前节拍播放预备小节，再按完整小节逐档升速。达到目标后会继续保持节拍和练习计时。")
        }
    }

    private var sheetHeight: CGFloat {
        if selectedTab == .ramp { return 418 }
        return 240 + (controller.tapAttempt.tapCount > 0 ? 44 : 0)
            + (controller.pendingTempo != nil ? 26 : 0)
    }

    private var adjustPanel: some View {
        VStack(spacing: 0) {
            tempoControls.frame(height: 78)
            if controller.tapAttempt.tapCount > 0 {
                tapFeedback.frame(minHeight: 44)
            }
            if let pendingTempo = controller.pendingTempo {
                Text("将在下一小节切换为 \(pendingTempo) BPM")
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minHeight: 26)
                    .accessibilityIdentifier("metronome.pendingTempo")
            }
            MetronomeTempoRulerView(bpm: controller.engine.bpm) { requestTempo($0) }
                .padding(.horizontal, 20)
            Text("调整即时生效 · 下滑或点遮罩收起")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }

    @ViewBuilder private var tapFeedback: some View {
        if let bpm = controller.tapAttempt.estimatedBPM {
            HStack {
                Text("测得 \(bpm) BPM")
                    .foregroundStyle(GitaTheme.textSecondary)
                    .accessibilityIdentifier("metronome.tap.estimate")
                Spacer()
                Button("采用 \(min(200, max(40, bpm))) BPM") { adoptMeasuredTempo(bpm) }
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minHeight: 44)
                    .disabled(!controller.tapReadyToApply)
                    .accessibilityIdentifier("metronome.tap.apply")
            }
            .font(GitaFont.caption())
        } else {
            Text("跟随节奏连续轻点（至少 4 次）")
                .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(SpeedSheetTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab.rawValue)
                        .font(GitaFont.callout(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? GitaTheme.brand500 : GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedTab == tab ? GitaTheme.brand50 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedTab == tab ? GitaTheme.brand500 : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier(tab == .adjust ? "metronome.speed.tab.adjust" : "metronome.speed.tab.ramp")
            }
        }
        .padding(4).background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12)).frame(height: 44)
    }

    private var tempoControls: some View {
        HStack(spacing: 14) {
            MetronomeStepButton(kind: .decrease, diameter: 44, enabled: controller.engine.bpm > 40) { requestTempo(controller.engine.bpm - 1) }
                .accessibilityLabel("降低速度")
                .accessibilityIdentifier("metronome.speed.decrease")
            VStack(spacing: 1) {
                Text("\(controller.engine.bpm)")
                    .font(.system(size: 46, weight: .medium)).monospacedDigit()
                    .foregroundStyle(GitaTheme.brand500)
                    .accessibilityIdentifier("metronome.speed.bpm")
                Text("BPM")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.frame(maxWidth: .infinity)
            MetronomeStepButton(kind: .increase, diameter: 44, enabled: controller.engine.bpm < 200) { requestTempo(controller.engine.bpm + 1) }
                .accessibilityLabel("提高速度")
                .accessibilityIdentifier("metronome.speed.increase")
            Button("TAP") { handleTap() }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(GitaTheme.brandOn)
                .frame(width: 74, height: 44).background(GitaTheme.brand500).clipShape(Capsule())
                .disabled(controller.isRampActive).accessibilityHint("连续轻点以测量速度")
                .accessibilityIdentifier("metronome.tap")
        }
        .padding(.horizontal, 4)
    }

    private var rampPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                numberField("起始速度", value: $rampSettings.startBPM, range: 40...199, suffix: "BPM")
                numberField("目标速度", value: $rampSettings.targetBPM, range: 41...200, suffix: "BPM")
            }
            HStack(spacing: 12) {
                Text("每").foregroundStyle(GitaTheme.textSecondary)
                rampMenu("\(rampSettings.barsPerStage) 小节", values: [1, 2, 4, 8, 16], selection: $rampSettings.barsPerStage)
                Text("增加").foregroundStyle(GitaTheme.textSecondary)
                rampMenu("+\(rampSettings.stepBPM) BPM", values: [1, 2, 5, 10], selection: $rampSettings.stepBPM)
                Spacer(minLength: 0)
                Text("调整").font(GitaFont.callout(.semibold)).foregroundStyle(GitaTheme.brand500)
            }
            .font(GitaFont.callout()).padding(.horizontal, 16).frame(height: 64)
            .background(GitaTheme.bgSubtle).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("预备小节"); Spacer()
                Menu {
                    ForEach(0...2, id: \.self) { value in
                        Button("\(value) 小节") { rampSettings.countInBars = value }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("\(rampSettings.countInBars) 小节").foregroundStyle(GitaTheme.textPrimary)
                        Image(systemName: "chevron.right").foregroundStyle(GitaTheme.textSecondary)
                    }
                }
            }
            .font(GitaFont.callout()).padding(.horizontal, 15).frame(height: 56)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GitaTheme.borderSubtle))
            if let error = rampSettings.validationError { Text(error).font(GitaFont.caption()).foregroundStyle(GitaTheme.statusError) }
            if rampSettings.validationError == nil {
                Text("约 \(estimatedMinutes) 分钟后达到 \(rampSettings.targetBPM) BPM")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }
            Button(controller.isRampActive ? "训练进行中" : "开始变速训练") { onStartRamp(rampSettings) }
                .font(GitaFont.body(.semibold)).foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(rampSettings.validationError == nil ? GitaTheme.brand500 : GitaTheme.borderInactive)
                .clipShape(Capsule()).disabled(rampSettings.validationError != nil || controller.isRampActive)
                .accessibilityIdentifier("metronome.ramp.start")
        }
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("", value: value, format: .number).keyboardType(.numberPad)
                    .font(.system(size: 26, weight: .medium)).monospacedDigit()
                    .foregroundStyle(GitaTheme.brand500)
                Text(suffix).font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 78)
        .background(GitaTheme.bgSubtle).clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: value.wrappedValue) { _, newValue in value.wrappedValue = min(range.upperBound, max(range.lowerBound, newValue)) }
    }

    private func handleTap() {
        let previousCount = controller.tapAttempt.tapCount
        let wasStable = controller.tapAttempt.isStable
        _ = controller.registerTap()
        if previousCount == 0, controller.tapAttempt.tapCount == 1 {
            tapStartedAt = Date()
            MetronomeAnalytics.emit(
                "metronome_tap_started", itemId: practiceItemId?.uuidString ?? "",
                ["current_bpm": String(controller.engine.bpm), "playing": String(controller.engine.isPlaying)]
            )
        }
        if !wasStable, controller.tapAttempt.isStable, let bpm = controller.tapAttempt.estimatedBPM {
            let duration = Int(Date().timeIntervalSince(tapStartedAt ?? Date()) * 1_000)
            MetronomeAnalytics.emit(
                "metronome_tap_stabilized", itemId: practiceItemId?.uuidString ?? "",
                ["tap_count": String(controller.tapAttempt.tapCount), "stable_bpm": String(bpm), "duration_ms": String(duration)]
            )
        }
        Haptics.tap()
    }

    private func adoptMeasuredTempo(_ bpm: Int) {
        let adopted = min(200, max(40, bpm))
        let from = controller.engine.bpm
        controller.applyMeasuredTempo(adopted)
        MetronomeAnalytics.emit(
            "metronome_tap_applied", itemId: practiceItemId?.uuidString ?? "",
            ["from_bpm": String(from), "to_bpm": String(adopted), "apply_context": controller.engine.isPlaying ? "next_bar" : "immediate"]
        )
        controller.resetTap()
        rampSettings.startBPM = adopted
    }

    private func requestTempo(_ value: Int) {
        if controller.isRampActive {
            pendingManualTempo = value
        } else {
            controller.resetTap()
            controller.setTempo(value)
        }
    }

    private var estimatedMinutes: String {
        var stageBPM = rampSettings.startBPM
        var seconds = 0.0
        while stageBPM < rampSettings.targetBPM {
            seconds += Double(rampSettings.barsPerStage * controller.engine.beatsPerBar) * 60 / Double(stageBPM)
            stageBPM = min(rampSettings.targetBPM, stageBPM + rampSettings.stepBPM)
        }
        return String(format: "%.1f", seconds / 60)
    }

    private func rampMenu(
        _ title: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button(value == selection.wrappedValue ? "✓ \(value)" : "\(value)") {
                    selection.wrappedValue = value
                }
            }
        } label: {
            Text(title)
                .foregroundStyle(GitaTheme.textPrimary)
                .frame(minWidth: 74, minHeight: 40)
                .overlay(Capsule().stroke(GitaTheme.borderSubtle))
        }
    }
}

#Preview { MetronomeSpeedSheet(controller: MetronomeTempoController(), onDone: {}) }

struct MetronomeSpeedBackdrop: View {
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Color.black.opacity(0.32).ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起速度设置")
        .accessibilityIdentifier("metronome.speed.dismiss")
    }
}
