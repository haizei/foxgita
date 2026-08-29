import SwiftUI

enum ProjectVersionKind: Equatable, Identifiable {
    case stage
    case final

    var id: Self { self }
}

struct ProjectVersionPickerView: View {
    let projectId: UUID
    let kind: ProjectVersionKind
    let selectedItemId: UUID?
    let candidates: [PracticeItemSnapshot]
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    private var calendar: Calendar { .current }

    private var title: String {
        kind == .stage ? "选择阶段版本" : "选择最终版本"
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text(title)
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                Button("关闭") { dismiss() }
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, GitaTheme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 16)

            if candidates.isEmpty {
                Text("先完成一次练习，再选成果")
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, item in
                            candidateRow(item)
                            if index < candidates.count - 1 {
                                Divider()
                                    .overlay(GitaTheme.borderSubtle)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(GitaTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                    .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(GitaTheme.bgDefault)
    }

    private func candidateRow(_ item: PracticeItemSnapshot) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RecordTimelineRules.dayTitle(dayKey: item.practiceDayKey, now: Date(), calendar: calendar))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Text(item.title)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(RecordMinutes.display(fromSeconds: item.durationSeconds)) 分钟")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                Spacer(minLength: 0)
                if item.recordingCount > 0 {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                if item.id == selectedItemId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
