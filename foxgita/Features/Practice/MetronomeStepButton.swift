//
//  MetronomeStepButton.swift
//  foxgita
//

import SwiftUI

struct MetronomeStepButton: View {
    enum Kind {
        case decrease
        case increase
    }

    let kind: Kind
    let diameter: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(kind == .increase ? "＋" : "−")
                .font(.system(size: diameter * 0.5, weight: .medium))
                .foregroundStyle(GitaTheme.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(GitaTheme.bgSurface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(GitaTheme.borderSubtle, lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
