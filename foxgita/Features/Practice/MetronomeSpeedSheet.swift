import SwiftUI

private enum SpeedSheetTab: String, CaseIterable, Identifiable {
    case adjust = "调速"
    case tap = "测速"
    case ramp = "变速"
    var id: Self { self }
}

struct MetronomeSpeedSheet: View {
    let controller: MetronomeTempoController
    var onDone: () -> Void
    var onStartRamp: (TempoRampSettings) -> Void
    var onEndRamp: () -> Void

    @State private var expanded = false
    @State private var selectedTab: SpeedSheetTab = .adjust
    @State private var rampSettings: TempoRampSettings
    @State private var pendingManualTempo: Int?
    @State private var showRampHelp = false
    @AppStorage("metronome.ramp-help-seen") private var hasSeenRampHelp = false

    init(
        controller: MetronomeTempoController,
        onDone: @escaping () -> Void,
        onStartRamp: @escaping (TempoRampSettings) -> Void = { _ in },
        onEndRamp: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onDone = onDone
        self.onStartRamp = onStartRamp
        self.onEndRamp = onEndRamp
        _rampSettings = State(initialValue: controller.savedRampSettings ?? .suggested(currentBPM: controller.engine.bpm))
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.systemGray3)).frame(width: 40, height: 4).padding(.top, 12)
            header.padding(.top, 12)
            if expanded {
                segmentedControl.padding(.top, 10)
                expandedContent.padding(.top, 16)
            } else {
                compactContent.padding(.top, 16)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GitaTheme.bgSurface)
        .presentationDetents([.height(expanded ? 498 : 382)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(controller.isRampActive)
        .accessibilityIdentifier("metronome.speed-sheet")
        .onDisappear { controller.resetTap() }
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
                onEndRamp()
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

    private var header: some View {
        HStack {
            Text(expanded ? "速度设置" : "调整速度")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer()
            Button("完成", action: onDone)
                .font(.system(size: 14))
                .foregroundStyle(GitaTheme.brand500)
                .frame(minWidth: 48, minHeight: 44, alignment: .trailing)
        }.frame(height: 34)
    }

    private var compactContent: some View {
        VStack(spacing: 18) {
            tempoControls(showTap: true)
            if let pendingTempo = controller.pendingTempo {
                Text("将在下一小节切换为 \(pendingTempo) BPM")
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .accessibilityIdentifier("metronome.pendingTempo")
            }
            MetronomeTempoRulerView(bpm: controller.engine.bpm) { requestTempo($0) }
                .padding(.horizontal, 20)
            Divider()
            Button {
                expanded = true
                selectedTab = .ramp
                if !hasSeenRampHelp { showRampHelp = true }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("变速训练").font(GitaFont.body(.semibold)).foregroundStyle(GitaTheme.textPrimary)
                        Text("\(compactRampSettings.startBPM) → \(compactRampSettings.targetBPM) BPM")
                            .font(.system(size: 18, weight: .medium)).foregroundStyle(GitaTheme.brand500)
                        Text("每 \(compactRampSettings.barsPerStage) 小节增加 \(compactRampSettings.stepBPM) BPM")
                            .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: "chevron.right").font(.system(size: 20)).foregroundStyle(GitaTheme.brand500)
                        Text("进入设置").font(GitaFont.caption(.semibold)).foregroundStyle(GitaTheme.brand500)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("metronome.ramp-entry")
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
                        .background(selectedTab == tab ? GitaTheme.bgSurface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: selectedTab == tab ? GitaTheme.shadowCard : .clear, radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4).background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12)).frame(height: 44)
    }

    @ViewBuilder private var expandedContent: some View {
        switch selectedTab {
        case .adjust:
            VStack(spacing: 24) {
                tempoControls(showTap: false)
                MetronomeTempoRulerView(bpm: controller.engine.bpm) { requestTempo($0) }
                    .padding(.horizontal, 20)
            }
        case .tap: tapPanel
        case .ramp: rampPanel
        }
    }

    private func tempoControls(showTap: Bool) -> some View {
        HStack(spacing: 12) {
            MetronomeStepButton(kind: .decrease, diameter: 44, enabled: controller.engine.bpm > 40) { requestTempo(controller.engine.bpm - 1) }
            VStack(spacing: 1) {
                Text("\(controller.engine.bpm)")
                    .font(.system(size: 46, weight: .medium)).monospacedDigit()
                    .foregroundStyle(GitaTheme.brand500)
                Text("BPM")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.frame(maxWidth: .infinity)
            MetronomeStepButton(kind: .increase, diameter: 44, enabled: controller.engine.bpm < 200) { requestTempo(controller.engine.bpm + 1) }
            if showTap {
                Button("TAP") { handleTap() }
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(GitaTheme.brandOn)
                    .frame(width: 74, height: 44).background(GitaTheme.brand500).clipShape(Capsule())
                    .disabled(controller.isRampActive).accessibilityHint("连续轻点以测量速度")
            }
        }
    }

    private var tapPanel: some View {
        VStack(spacing: 18) {
            Text(controller.tapAttempt.estimatedBPM.map(String.init) ?? "—")
                .font(.system(size: 58, weight: .medium)).monospacedDigit().foregroundStyle(GitaTheme.brand500)
            Text(controller.tapReadyToApply ? "可以采用测得速度" : (controller.tapAttempt.isStable ? "速度已稳定" : "跟随节奏连续轻点（至少 4 次）"))
                .font(GitaFont.callout()).foregroundStyle(GitaTheme.textSecondary)
            Button("TAP") { handleTap() }
                .font(.system(size: 20, weight: .bold)).foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity, minHeight: 56).background(GitaTheme.brand500).clipShape(Capsule())
                .disabled(controller.isRampActive)
            if let bpm = controller.tapAttempt.estimatedBPM, controller.tapReadyToApply {
                Button("采用 \(min(200, max(40, bpm))) BPM") { adoptMeasuredTempo(bpm) }
                    .font(GitaFont.body(.semibold)).foregroundStyle(GitaTheme.brand500).frame(minHeight: 44)
            }
            if let bpm = controller.tapAttempt.estimatedBPM, bpm > 200 {
                Text("采用时将使用上限 200 BPM")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }
        }
    }

    private var rampPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                numberField("起始速度", value: $rampSettings.startBPM, range: 40...199, suffix: "BPM")
                numberField("目标速度", value: $rampSettings.targetBPM, range: 41...200, suffix: "BPM")
            }
            HStack(spacing: 12) {
                Text("每").foregroundStyle(GitaTheme.textSecondary)
                rampMenu("\(rampSettings.barsPerStage) 小节", values: [1, 2, 4, 8, 16, 32], selection: $rampSettings.barsPerStage)
                Text("增加").foregroundStyle(GitaTheme.textSecondary)
                rampMenu("+\(rampSettings.stepBPM) BPM", values: [1, 2, 5, 10, 15, 20], selection: $rampSettings.stepBPM)
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
                .accessibilityIdentifier("metronome.ramp-start")
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
        _ = controller.registerTap()
        Haptics.tap()
    }

    private func adoptMeasuredTempo(_ bpm: Int) {
        let adopted = min(200, max(40, bpm))
        controller.applyMeasuredTempo(adopted)
        rampSettings.startBPM = adopted
    }

    private func requestTempo(_ value: Int) {
        if controller.isRampActive {
            pendingManualTempo = value
        } else {
            controller.setTempo(value)
        }
    }

    private var estimatedMinutes: String {
        let distance = max(0, rampSettings.targetBPM - rampSettings.startBPM)
        let stages = Int(ceil(Double(distance) / Double(max(1, rampSettings.stepBPM)))) + 1
        let bars = rampSettings.countInBars + stages * rampSettings.barsPerStage
        let seconds = Double(bars * controller.engine.beatsPerBar) * 60 / Double(max(1, rampSettings.startBPM))
        return String(format: "%.1f", seconds / 60)
    }

    private var compactRampSettings: TempoRampSettings {
        controller.savedRampSettings ?? .suggested(currentBPM: controller.engine.bpm)
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
