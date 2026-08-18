import AVKit
import SwiftUI

struct AlbumPreviewItem: Identifiable {
    let id: UUID
    let url: URL
    let displayName: String
    let durationSec: Int

    init(id: UUID = UUID(), url: URL, displayName: String, durationSec: Int) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.durationSec = durationSec
    }
}

struct AlbumPreviewView: View {
    let item: AlbumPreviewItem
    var onBack: () -> Void
    var onReselect: () -> Void
    var onConfirm: () -> Void

    @State private var player: AVPlayer?

    private var verdict: AlbumDurationVerdict {
        AlbumDurationGate.verdict(durationSec: item.durationSec)
    }

    private var canConfirm: Bool { verdict == .ok }

    private var durationLabel: String {
        let seconds = max(0, item.durationSec)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var gateMessage: String? {
        switch verdict {
        case .ok: return nil
        case .tooShort: return String(localized: "这段视频太短，证据不足，请选择至少 30 秒")
        case .tooLong: return String(localized: "这段视频超过 10 分钟，请换一段更短的")
        case .unknown: return String(localized: "无法读取时长")
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "返回"), action: onBack)
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(String(localized: "预览确认"))
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(durationLabel)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                        if let player {
                            VideoPlayer(player: player)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            Color.black
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        if let gateMessage {
                            Text(gateMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(GitaTheme.statusError)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 10) {
                    Button(String(localized: "重新选择"), action: onReselect)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Capsule().stroke(GitaTheme.borderSubtle, lineWidth: 1))
                    Button(String(localized: "开始分析"), action: onConfirm)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canConfirm ? GitaTheme.brand500 : GitaTheme.borderInactive)
                        .clipShape(Capsule())
                        .disabled(!canConfirm)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: item.url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
