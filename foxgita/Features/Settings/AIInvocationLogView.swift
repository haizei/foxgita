import SwiftUI

struct AIInvocationLogView: View {
    @Environment(AIInvocationStore.self) private var store

    var body: some View {
        let logs = store.recent()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if logs.isEmpty {
                    Text("还没有 AI 调用记录")
                        .font(.system(size: 13))
                        .foregroundStyle(GitaTheme.textSecondary)
                } else {
                    ForEach(logs, id: \.id) { log in
                        row(log)
                    }
                }
            }
            .padding(16)
        }
        .background(PageBackground())
        .navigationTitle("AI 调用记录")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }

    @ViewBuilder
    private func row(_ log: AIInvocationLog) -> some View {
        let model = AIInvocationLogPresentation.row(log)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.skillTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text(model.statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        model.statusText == "失败" ? GitaTheme.statusError : GitaTheme.textSecondary
                    )
            }
            Text("\(model.outcomeText) · \(model.completedText)")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
            Text("\(model.durationText) · \(model.modelText)")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.statusError)
            }
            Text(log.startedAt, format: .dateTime.month().day().hour().minute())
                .font(.system(size: 11))
                .foregroundStyle(GitaTheme.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
