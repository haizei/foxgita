import SwiftUI

struct TunerSettingsView: View {
    let model: TunerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("标准音校准") {
                    HStack {
                        Button { model.setCalibration(model.calibrationA4 - 1) } label: {
                            Image(systemName: "minus").frame(width: 44, height: 44)
                        }.accessibilityLabel("降低标准音频率").accessibilityIdentifier("tuner.calibration.decrease")
                        Spacer()
                        Text("\(model.calibrationA4, specifier: "%.0f") Hz")
                            .font(GitaFont.metric()).accessibilityIdentifier("tuner.calibration.value")
                        Spacer()
                        Button { model.setCalibration(model.calibrationA4 + 1) } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }.accessibilityLabel("提高标准音频率").accessibilityIdentifier("tuner.calibration.increase")
                    }.buttonStyle(.borderless)
                    Button("恢复 A4 = 440 Hz") { model.setCalibration(440) }
                        .accessibilityIdentifier("tuner.calibration.reset")
                    Text("可在 430–450 Hz 之间调整。所有琴弦的目标频率会一起更新。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
                Section("标准音") {
                    Button(model.status == .referenceTone ? "停止标准音" : "播放当前琴弦标准音") {
                        model.toggleReferenceTone()
                    }
                    .disabled(model.status == .preparing)
                    .accessibilityIdentifier("tuner.settings.reference")
                    Text("\(model.target.noteLabel) · \(model.targetFrequency, specifier: "%.1f") Hz")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                    Text("播放时暂停调音判断，余音消退后再聆听琴弦。")
                        .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                }
                Section("调音提示") {
                    Text("音准在 ±5 cent 内持续稳定约 0.4 秒后确认调准；超过 ±8 cent 或声音失效后撤销确认。自动识弦适用于空弦，手动点选后固定目标。")
                    Text("麦克风声音只在设备上实时分析，不会保存或上传。")
                }.font(GitaFont.callout())
            }
            .navigationTitle("调音设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("tuner.settings.done")
                }
            }
        }
        .tint(GitaTheme.brand500)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
