//
//  ReviewGenerationSheet.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct ReviewGenerationSheet: View {
    let recordingIds: [String]
    let taskTitle: String
    var onReturn: () -> Void

    @Environment(ReviewJobRunner.self) private var runner
    @Query(filter: #Predicate<RecordingRef> { $0.deletedAt == nil })
    private var recordings: [RecordingRef]
    @State private var didReturn = false

    private var listedStatuses: [String] {
        recordingIds.map { id in
            recordings.first { $0.id == id }?.reviewStatus.rawValue ?? ""
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                Capsule()
                    .fill(GitaTheme.borderSubtle)
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "生成练习复盘"))
                        .font(GitaFont.title())
                    Text("\(taskTitle) · 本次练习")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(recordingIds, id: \.self) { id in
                            clipRow(id: id, recording: recordings.first { $0.id == id })
                        }
                    }
                    .padding(.horizontal, 16)
                }

                VStack(spacing: 10) {
                    Button(action: returnOnce) {
                        Text(String(localized: "后台生成并返回"))
                            .font(GitaFont.body(.semibold))
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GitaTheme.brand500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text(String(localized: "录制内容已安全保存"))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear { dismissIfFinished() }
        .onChange(of: listedStatuses) { _, _ in dismissIfFinished() }
        .onDisappear { returnOnce() }
    }

    private func clipRow(id: String, recording: RecordingRef?) -> some View {
        HStack {
            Text(rowTitle(recording))
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer()
            Text(statusLabel(id: id, recording: recording))
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(statusColor(id: id, recording: recording))
        }
        .padding(14)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rowTitle(_ recording: RecordingRef?) -> String {
        guard let recording else { return String(localized: "录音") }
        let isVideo = MediaReviewMedia.isVideo(fileName: recording.fileName)
        let kind = isVideo ? String(localized: "视频") : String(localized: "录音")
        return "\(kind) \(recording.durationLabel)"
    }

    private func statusLabel(id: String, recording: RecordingRef?) -> String {
        switch recording?.reviewStatus {
        case .ready:
            return String(localized: "完成")
        case .failed:
            return String(localized: "失败")
        case .pending where runner.activeRecordingId == id:
            return String(localized: "分析中")
        default:
            return String(localized: "等待中")
        }
    }

    private func statusColor(id: String, recording: RecordingRef?) -> Color {
        switch recording?.reviewStatus {
        case .ready:
            return GitaTheme.statusSuccess
        case .failed:
            return GitaTheme.statusError
        case .pending where runner.activeRecordingId == id:
            return GitaTheme.brand500
        default:
            return GitaTheme.textSecondary
        }
    }

    private func dismissIfFinished() {
        let statuses = recordingIds.compactMap { id in
            recordings.first { $0.id == id }?.reviewStatus
        }
        guard statuses.count == recordingIds.count, !statuses.isEmpty else { return }
        guard statuses.allSatisfy({ $0 == .ready || $0 == .failed }) else { return }
        returnOnce()
    }

    private func returnOnce() {
        guard !didReturn else { return }
        didReturn = true
        onReturn()
    }
}
