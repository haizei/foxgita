import SwiftUI

struct MemoryConsentSheet: View {
    var onEnable: () -> Void
    var onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(MemoryConsentCopy.lines, id: \.self) { line in
                    Text(line).font(.system(size: 15))
                }
                Spacer()
                Button(action: onEnable) {
                    Text(MemoryConsentCopy.enable)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(GitaTheme.brand500)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button(MemoryConsentCopy.decline, action: onDecline)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(20)
            .navigationTitle(MemoryConsentCopy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(false)
    }
}
