import SwiftUI

struct MetronomeSoundSheet: View {
    let metronome: MetronomeEngine
    var preferences: MetronomeVisualPreferencesStore = .shared
    var metronomeEnabled: Binding<Bool>?
    var onRecord: () -> Void = {}
    var onExpand: () -> Void = {}
    var showsPracticeActions = true
    var onDone: () -> Void
    @State private var previewError: String?
    @State private var showAdvanced = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var presets: [MetronomeSoundPreset] { Array(MetronomeSoundPreset.allCases) }
    private var presetIndex: Int { presets.firstIndex(of: metronome.soundPreset) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("完成", action: onDone).font(GitaFont.callout(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("metronome.sound.done")
            }.padding(.horizontal, 20)
            ScrollView {
                VStack(spacing: 24) {
                    header
                    MetronomeSettingsPanel(title: "音效", border: "MetronomeSoundBorder") { soundControls }
                    MetronomeSettingsPanel(title: "音色选择", border: "MetronomeSoundBorder") { presetGrid }
                    MetronomeVisualSettingsSection(preferences: preferences)
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .foregroundStyle(GitaTheme.textPrimary).background(Color.white).tint(GitaTheme.brand500)
        .environment(\.colorScheme, .light)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metronome.sound-settings")
        .onAppear { metronome.applyVisualPreferences(preferences.value) }
        .onChange(of: preferences.value) { _, value in metronome.applyVisualPreferences(value) }
        .onDisappear { if metronome.isPreviewing { metronome.stopPreview() } }
        .sheet(isPresented: $showAdvanced) {
            MetronomeAdvancedSoundSheet(metronome: metronome, preferences: preferences, metronomeEnabled: metronomeEnabled)
        }
        .alert("无法试听", isPresented: Binding(
            get: { previewError != nil }, set: { if !$0 { previewError = nil } }
        )) { Button("知道了", role: .cancel) { previewError = nil } }
        message: { Text(previewError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("MetronomeScrew").accessibilityHidden(true)
            if showsPracticeActions {
                roundButton("录音", image: "MetronomeSettingsMic", action: onRecord)
            }
            Spacer(minLength: 4)
            Text("设置").font(GitaFont.headline(.bold))
            Spacer(minLength: 4)
            if showsPracticeActions {
                roundButton("展开节拍器", image: "MetronomeSettingsExpand", action: onExpand)
            }
            Image("MetronomeScrew").accessibilityHidden(true)
        }.padding(.bottom, 8)
            .overlay(alignment: .bottom) { GitaTheme.borderSubtle.frame(height: 0.5) }
    }

    private var soundControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("音色：").font(GitaFont.body())
                Spacer(minLength: 0)
                roundButton("上一个音色", image: "MetronomeToneMinus", enabled: presetIndex > 0) {
                    select(presets[max(0, presetIndex - 1)])
                }
                Text("\(presetIndex + 1)").font(GitaFont.largeTitle(.medium)).monospacedDigit()
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(GitaTheme.borderSubtle))
                    .accessibilityLabel("音色编号")
                    .accessibilityValue("\(presetIndex + 1)，\(metronome.soundPreset.displayName)")
                roundButton("下一个音色", image: "MetronomeTonePlus", enabled: presetIndex < 6) {
                    select(presets[min(6, presetIndex + 1)])
                }
                Button(action: audition) { Image("MetronomeHeadphones").frame(width: 44, height: 44) }
                    .accessibilityLabel("试听当前音色")
            }
            HStack(spacing: 12) {
                Text("音量").font(GitaFont.body())
                Slider(value: Binding(get: { Double(metronome.volume) }, set: { metronome.setVolume(Int($0.rounded())) }), in: 0...100, step: 1)
                    .accessibilityLabel("音量").accessibilityValue("\(metronome.volume)%")
                Button { metronome.setTemporarilyMuted(!metronome.isTemporarilyMuted) } label: {
                    Image("MetronomeMute").renderingMode(.template)
                        .foregroundStyle(metronome.isTemporarilyMuted ? GitaTheme.brand500 : GitaTheme.textSecondary)
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(metronome.isTemporarilyMuted ? "取消静音" : "临时静音")
            }
            Button { showAdvanced = true } label: {
                HStack(spacing: 8) {
                    Image("MetronomeSliders")
                    Text("更多声音设置").font(GitaFont.body(.medium))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }.foregroundStyle(GitaTheme.brand500)
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前音色：\(metronome.soundPreset.displayName)").font(GitaFont.micro())
                .foregroundStyle(GitaTheme.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 8) {
                ForEach(presets) { preset in
                    let selected = metronome.soundPreset == preset
                    Button { select(preset) } label: {
                        Text(preset.displayName).font(GitaFont.footnote(selected ? .medium : .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selected ? GitaTheme.brand500 : GitaTheme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 4)
                            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? GitaTheme.brand500 : GitaTheme.borderSubtle.opacity(0.4)))
                            .overlay(alignment: .topTrailing) {
                                if selected { Image("MetronomeSelected").padding(3).accessibilityHidden(true) }
                            }
                    }.buttonStyle(.plain)
                        .accessibilityValue(selected ? "已选择" : "未选择")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func select(_ preset: MetronomeSoundPreset) {
        let shouldPreview = !metronome.isPlaying || metronome.isPreviewing
        metronome.setSoundPreset(preset)
        if shouldPreview { audition() }
    }

    private func audition() {
        guard !metronome.isPlaying || metronome.isPreviewing else { return }
        do { try metronome.preview(bars: 2) }
        catch { previewError = String(localized: "节拍声音加载失败，请重试。") }
    }

    private func roundButton(_ label: String, image: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image).frame(width: 44, height: 44)
                .background { Image("MetronomeRoundBase").resizable().frame(width: 56, height: 56) }
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4).accessibilityLabel(label)
    }
}

struct MetronomeSettingsPanel<Content: View>: View {
    let title: String
    let border: String
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(GitaFont.body(.medium)).fixedSize(horizontal: false, vertical: true)
                content
            }.padding(18).frame(maxWidth: .infinity)
                .overlay(Rectangle().stroke(GitaTheme.borderSubtle))
        } else {
          content.padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background {
                Image(border).resizable(capInsets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)).accessibilityHidden(true)
            }
            .overlay(alignment: .topLeading) {
                Text(title).font(GitaFont.body(.medium)).padding(.horizontal, 10)
                    .background(Color.white).offset(x: 12, y: -8)
            }
        }
    }
}
