import SwiftUI

struct MetronomeAdvancedSoundSheet: View {
    let metronome: MetronomeEngine
    let preferences: MetronomeVisualPreferencesStore
    var metronomeEnabled: Binding<Bool>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let metronomeEnabled {
                    Toggle("启用节拍器", isOn: metronomeEnabled)
                        .accessibilityIdentifier("practice.metronome-enabled")
                }
                Toggle("强拍增强", isOn: Binding(get: { metronome.strongBeatBoost }, set: metronome.setStrongBeatBoost))
                Toggle("振动提示", isOn: binding(\.hapticsEnabled))
                Toggle("闪拍提示", isOn: binding(\.flashEnabled))
                Text("辅助提示由你单独控制，切换音色不会自动开启。")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.navigationTitle("更多声音设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(GitaTheme.brand500).environment(\.colorScheme, .light)
    }

    private func binding(_ key: WritableKeyPath<MetronomeVisualPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { preferences.value[keyPath: key] }, set: { enabled in
            var value = preferences.value
            value[keyPath: key] = enabled
            preferences.update(value)
            metronome.applyVisualPreferences(value)
        })
    }
}
