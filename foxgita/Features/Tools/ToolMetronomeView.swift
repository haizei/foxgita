import SwiftUI

struct ToolMetronomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ToolMetronomeModel()
    @State private var anchor: MetronomeSheetAnchor?
    @State private var showSound = false
    private var preferences: MetronomeVisualPreferencesStore { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: GitaTheme.s24) {
                MetronomeDisplayCard(
                    metronome: model.engine,
                    onEntryTap: { anchor = $0 },
                    onSoundTap: { showSound = true },
                    onTapTempo: { anchor = .speed },
                    onAccentTap: { model.engine.cycleAccent(at: $0) },
                    isAccentEditingLocked: model.controller.isRampActive
                )
                Button(action: model.togglePlayback) {
                    Label(model.engine.isPlaying ? "暂停播放" : "开始播放",
                          systemImage: model.engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(GitaFont.headline())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(GitaTheme.brandOn)
                        .background(GitaTheme.brand500, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tools.metronome.toggle")
            }
            .padding(GitaTheme.s20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(GitaTheme.bgDefault)
        .navigationTitle("节拍器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $anchor) { selected in
            switch selected {
            case .speed:
                MetronomeSpeedSheet(
                    controller: model.controller,
                    onDone: { anchor = nil },
                    onStartRamp: { settings in
                        anchor = nil
                        model.startRamp(settings)
                    },
                    onEndRamp: { model.endRamp(applying: $0) }
                )
            case .meter, .subdivision:
                MetronomeSettingsSheet(
                    metronome: model.engine, anchor: selected,
                    isLocked: model.controller.isRampActive,
                    onDone: { anchor = nil }
                )
            }
        }
        .sheet(isPresented: $showSound) {
            MetronomeSoundSheet(
                metronome: model.engine,
                showsPracticeActions: false,
                onDone: { showSound = false }
            )
        }
        .alert("播放提示", isPresented: Binding(
            get: { model.playbackError != nil },
            set: { if !$0 { model.playbackError = nil } }
        )) {
            Button("知道了", role: .cancel) { model.playbackError = nil }
        } message: { Text(model.playbackError ?? "") }
        .onAppear {
            model.engine.applyVisualPreferences(preferences.value)
            model.engine.foregroundFeedbackEnabled = scenePhase == .active
            model.activate()
        }
        .onDisappear { model.deactivate() }
        .onChange(of: preferences.value) { _, value in model.engine.applyVisualPreferences(value) }
        .onChange(of: scenePhase) { _, phase in
            model.engine.foregroundFeedbackEnabled = phase == .active && router.selectedTab == .tools
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .tools { model.activate() }
            else { model.deactivate() }
        }
        .overlay {
            if anchor == .speed { MetronomeSpeedBackdrop { anchor = nil } }
        }
    }
}
