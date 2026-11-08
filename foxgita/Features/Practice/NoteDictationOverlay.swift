import SwiftUI

/// Both the gesture and the visible drop targets use the same screen coordinates.
enum NoteDictationTarget: Equatable {
    case listening
    case cancel
    case transcribe

    static func resolve(translation: CGSize, location: CGPoint, frame: CGRect) -> Self {
        guard translation.height < -60 else { return .listening }
        return location.x >= frame.midX ? .transcribe : .cancel
    }
}

struct NoteDictationOverlay: View {
    let service: NoteDictationService
    let target: NoteDictationTarget
    let onCancel: () -> Void
    let onTranscribe: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var status: String {
        if service.isPreparing { return "正在准备语音输入" }
        if service.isFinishing { return "正在转成文字…" }
        return target == .cancel ? "松手取消" : "松手转文字"
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack {
                Color.black.opacity(0.64)
                VStack(spacing: 16) {
                    Text(service.elapsedDisplay)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white.opacity(0.85))
                    VStack(spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(target == .cancel ? Color.gray : GitaTheme.brand500)
                            if service.isPreparing || service.isFinishing {
                                ProgressView().tint(.white).controlSize(.large)
                            } else {
                                HStack(spacing: 3) {
                                    ForEach(Array(service.inputLevels.enumerated()), id: \.offset) { _, level in
                                        Capsule().fill(.white.opacity(0.95))
                                            .frame(width: 3, height: max(4, CGFloat(level) * 42))
                                    }
                                }
                                .accessibilityHidden(true)
                            }
                        }.frame(width: 234, height: 84)
                        DictationBubbleTail()
                            .fill(target == .cancel ? Color.gray : GitaTheme.brand500)
                            .frame(width: 24, height: 10)
                    }
                    Text(status).font(GitaFont.headline(.semibold)).foregroundStyle(.white)
                    Text("上滑可取消").font(GitaFont.footnote()).foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .position(x: geometry.size.width / 2, y: height * 0.41)

                VStack(spacing: 24) {
                    HStack(spacing: 24) {
                        dropTarget("取消", symbol: "xmark", selected: target == .cancel, action: onCancel)
                        dropTarget("转文字", symbol: "text.bubble", selected: target == .transcribe, action: onTranscribe)
                    }
                    .padding(.horizontal, 28)
                    Image(systemName: "mic")
                        .font(.system(size: 30))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 92, height: 92)
                        .background(GitaTheme.brand50, in: Circle())
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background {
                            Ellipse().fill(Color(white: 0.97))
                                .frame(width: geometry.size.width * 1.8, height: 300)
                                .offset(y: 75)
                        }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.dictation.overlay")
        .accessibilityAddTraits(.isModal)
    }

    private func dropTarget(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 23, weight: .medium))
                Text(title).font(GitaFont.callout(.medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 100 : 70)
            .background(selected ? GitaTheme.brand500 : Color.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(service.isPreparing || service.isFinishing)
        .accessibilityLabel(title == "取消" ? "取消语音输入" : "结束并转成文字")
    }
}

private struct DictationBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .init(x: rect.minX, y: rect.minY))
            path.addLine(to: .init(x: rect.midX, y: rect.maxY))
            path.addLine(to: .init(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}
