//
//  GitaThemeAccentColorTests.swift
//  foxgitaTests
//

import Testing
import UIKit
@testable import foxgita

struct GitaThemeAccentColorTests {
    @Test func accentColorsResolveToFigmaHex() {
        expectColor("AccentStrong", hex: 0xFF6B1A)
        expectColor("AccentMedium", hex: 0xFF9961)
        expectColor("AccentWeak", hex: 0xFFCCA6)
        expectColor("AccentMute", hex: 0xBDC2C9)
        expectColor("AccentSlotEmpty", hex: 0xEDF2F7)
        expectColor("AccentTrackBase", hex: 0xEEF0F3)
        expectColor("AccentTrackDivider", hex: 0xD0D3D9)
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

    @Test func accentImageAssetsLoad() {
        for kind in MetronomeBeatKind.allCases {
            let image = UIImage(named: kind.assetName)
            #expect(image != nil, "Missing accent image for \(kind.assetName)")
        }
    }
}
