import SwiftUI

struct MetronomeFullscreenView: View {
    let controller: MetronomeTempoController
    let isPracticeRunning: Bool
    let metronomeEnabled: Binding<Bool>
    let onToggle: () -> Void
    let onRecord: () -> Void
    let onStartRamp: (TempoRampSettings) -> Void
    let onEndRamp: (Int?) -> Void
    let onDone: () -> Void
    @State private var anchor: MetronomeSheetAnchor?
    @State private var showSound = false
    private var metronome: MetronomeEngine { controller.engine }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text("\(metronome.bpm)")
                        .font(.system(size: 88, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(GitaTheme.brand500)
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityLabel("每分钟\(metronome.bpm)拍")
                    Text(metronome.timeSignatureText).font(GitaFont.largeTitle())
                    MetronomeDisplayCard(
                        metronome: metronome,
                        onEntryTap: { anchor = $0 },
                        onSoundTap: { showSound = true },
                        onAccentTap: { metronome.cycleAccent(at: $0) },
                        isAccentEditingLocked: controller.isRampActive
                    )
                    Button(isPracticeRunning ? "暂停练习" : "开始练习", action: onToggle)
                        .font(GitaFont.headline()).frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(GitaTheme.brandOn).background(GitaTheme.brand500, in: Capsule())
                    Button(action: onRecord) {
                        Label("练习录音", systemImage: "mic").frame(minHeight: 44)
                    }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(GitaTheme.bgDefault)
            .navigationTitle("大屏节拍器").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("收起", action: onDone) } }
            .sheet(item: $anchor) { selected in
                switch selected {
                case .speed:
                    MetronomeSpeedSheet(controller: controller, onDone: { anchor = nil }, onStartRamp: { settings in
                        anchor = nil
                        onStartRamp(settings)
                    }, onEndRamp: { onEndRamp($0) })
                case .meter, .subdivision:
                    MetronomeSettingsSheet(metronome: metronome, anchor: selected, isLocked: controller.isRampActive, onDone: { anchor = nil })
                }
            }
            .sheet(isPresented: $showSound) {
                MetronomeSoundSheet(metronome: metronome, metronomeEnabled: metronomeEnabled, onRecord: {
                    showSound = false
                    onRecord()
                }, onExpand: { showSound = false }, onDone: { showSound = false })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metronome.fullscreen")
    }
}
