import SwiftUI

struct CandidateMemoryCard: View {
    let recordingID: String

    @Environment(PracticeStore.self) private var store
    @State private var screenID = UUID().uuidString
    @State private var notice: String?
    @State private var errorText: String?

    var body: some View {
        if let notice {
            Text(notice)
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(GitaTheme.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        } else if let draft = store.candidateMemoryDraft(recordingId: recordingID) {
            VStack(alignment: .leading, spacing: 10) {
                Text("建议记住")
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Text(draft.evidenceSummary)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(draft.semantic)
                    .font(GitaFont.callout(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let errorText {
                    Text(errorText)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.statusError)
                }
                HStack(spacing: 10) {
                    Button("忽略") {
                        store.ignoreCandidateMemory(draft)
                        notice = "已忽略，本条建议不再提示"
                    }
                    .buttonStyle(.bordered)

                    Button("记住") {
                        Task { await remember(draft) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(GitaFont.caption(.semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GitaTheme.brand50)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("候选记忆，证据：\(draft.evidenceSummary)，建议：\(draft.semantic)")
        }
    }

    private func remember(_ draft: CandidateMemoryDraft) async {
        errorText = nil
        let token = store.issueCandidateMemoryApproval(
            draft,
            userID: draft.profileID,
            sessionID: screenID
        )
        do {
            try await store.rememberCandidateMemory(
                draft,
                token: token,
                userID: draft.profileID,
                sessionID: screenID
            )
            notice = "已记住，将用于后续练习建议"
        } catch {
            errorText = "未能保存，请重试"
        }
    }
}
