//
//  GitaThemeAccentColorTests.swift
//  foxgitaTests
//

import Testing
import UIKit
@testable import foxgita

struct GitaThemeAccentColorTests {
    @Test func accentColorsResolveToFigmaHex() {
        expectColor("AccentMedium", hex: 0xF4A261)
        expectColor("AccentWeak", hex: 0xF9C89E)
        expectColor("AccentTrackBase", hex: 0xEEF0F3)
        expectColor("AccentCardStrongBg", hex: 0xFF591A)
        expectColor("AccentCardMediumBg", hex: 0xFFCCA8)
        expectColor("AccentCardMediumText", hex: 0x732E0D)
        expectColor("AccentCardWeakBg", hex: 0xEBEBE8)
        expectColor("AccentCardMuteBg", hex: 0x2E2E2E)
    }

    private func expectColor(_ name: String, hex: Int) {
        guard let color = UIColor(named: name) else {
            Issue.record("Missing color asset \(name)")
            return
        }
        let components = color.cgColor.components ?? []
        #expect(components.count >= 3)
        guard components.count >= 3 else { return }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        #expect(r == (hex >> 16) & 0xFF)
        #expect(g == (hex >> 8) & 0xFF)
        #expect(b == hex & 0xFF)
    }
}
