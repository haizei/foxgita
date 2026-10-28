import SwiftUI

struct MetronomeVisualSettingsSection: View {
    let preferences: MetronomeVisualPreferencesStore
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        MetronomeSettingsPanel(title: "视觉模块", border: "MetronomeVisualBorder") {
            VStack(spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack { modules }
                    VStack(alignment: .leading) { modules }
                }
                Text("高亮节拍").font(GitaFont.micro()).foregroundStyle(GitaTheme.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3)) {
                    checkbox("重音", key: \.highlightStrong, id: "strong", color: GitaTheme.brand500, check: "MetronomeCheckStrong")
                    checkbox("次重音", key: \.highlightMedium, id: "medium", color: GitaTheme.accentMedium, check: "MetronomeCheckMedium")
                    checkbox("普通", key: \.highlightNormal, id: "normal", color: GitaTheme.accentWeak, check: "MetronomeCheckNormal")
                }.padding(.horizontal, 8).background(GitaTheme.bgSubtle)
                HStack {
                    Text("小节计数").font(GitaFont.body())
                    Spacer()
                    Button {
                        var value = preferences.value
                        value.barCounterVisible.toggle()
                        preferences.update(value)
                    } label: {
                        ZStack(alignment: preferences.value.barCounterVisible ? .trailing : .leading) {
                            if preferences.value.barCounterVisible {
                                Capsule().fill(GitaTheme.brand500)
                                Image("MetronomeRoundBase").resizable().frame(width: 58, height: 58)
                                    .overlay(Circle().fill(GitaTheme.brand500).frame(width: 7, height: 7))
                            } else {
                                Image("MetronomeBarCounterOff").resizable().frame(width: 110, height: 110)
                                    .frame(width: 92, height: 48).clipped()
                            }
                        }.frame(width: 92, height: 48)
                    }.buttonStyle(.plain).accessibilityLabel("小节计数")
                        .accessibilityValue(preferences.value.barCounterVisible ? "开启" : "关闭")
                        .accessibilityIdentifier("metronome.visual.bar-counter")
                }
            }
        }
    }

    @ViewBuilder private var modules: some View {
        checkbox("节拍模块", key: \.beatModuleEnabled, id: "beat-module", color: GitaTheme.brand500)
        Spacer(minLength: 8)
        checkbox("钟摆模式", key: \.pendulumEnabled, id: "pendulum", color: GitaTheme.brand500)
    }

    private func checkbox(_ title: String, key: WritableKeyPath<MetronomeVisualPreferences, Bool>, id: String, color: Color, check: String = "MetronomeCheckStrong") -> some View {
        let selected = preferences.value[keyPath: key]
        return Button {
            var value = preferences.value
            value[keyPath: key].toggle()
            preferences.update(value)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(selected ? color : GitaTheme.borderSubtle)
                    .frame(width: 18, height: 18)
                    .overlay { if selected { Image(check).accessibilityHidden(true) } }
                Text(title).font(GitaFont.body()).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(selected ? "已选择" : "未选择")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("metronome.visual.\(id)")
    }
}
