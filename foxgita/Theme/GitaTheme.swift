//
//  GitaTheme.swift
//  foxgita — Design tokens from DESIGN_SYSTEM_SPEC v2.0
//

import SwiftUI

enum GitaTheme {
    // Action
    static let brand500 = Color(hex: 0xFF7925)
    static let brand50 = Color(hex: 0xFFF0E6)
    static let brandOn = Color.white

    // Background
    static let bgDefault = Color(hex: 0xFAFAFA)
    static let bgSurface = Color.white
    static let bgSubtle = Color(hex: 0xF6F6F6)

    // Text
    static let textPrimary = Color(hex: 0x292929)
    static let textSecondary = Color(hex: 0x999999)
    static let textTertiary = Color(hex: 0xC6C8CC)
    static let textOnPrimary = Color.white

    // Icon
    static let iconPrimary = Color(hex: 0x333333)
    static let iconSecondary = Color(hex: 0x999999)
    static let iconInactive = Color(hex: 0xD6D9DE)
    static let iconActive = Color(hex: 0xFF7925)

    // Border / Status
    static let borderSubtle = Color(hex: 0xEEEEEE)
    static let borderInactive = Color(hex: 0xD6D9DE)
    static let statusSuccess = Color(hex: 0x78E39D)

    // Category
    static let categoryBlue = Color(hex: 0x6682ED)
    static let categoryOrange = Color(hex: 0xF4A16F)
    static let categoryYellow = Color(hex: 0xFFE58D)
    static let categoryPurple = Color(hex: 0xA986D2)
    static let categoryCyan = Color(hex: 0x27B3D3)

    // Radius
    static let radius8: CGFloat = 8
    static let radius12: CGFloat = 12
    static let radius16: CGFloat = 16
    static let radius20: CGFloat = 20
    static let radius24: CGFloat = 24

    // Spacing
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24

    static let pagePadding: CGFloat = 16
    static let tabBarHeight: CGFloat = 56

    static let shadowCard = Color.black.opacity(0.06)
    static let shadowFab = Color(hex: 0xFF7925).opacity(0.18)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum PracticeCategory: String, Codable, CaseIterable, Identifiable {
    case left, right, both, chord, scale, rhythm, song

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "左手"
        case .right: return "右手"
        case .both: return "双手"
        case .chord: return "和弦"
        case .scale: return "音阶"
        case .rhythm: return "节奏"
        case .song: return "歌曲"
        }
    }

    var shortTag: String {
        switch self {
        case .left, .right, .both: return "技"
        case .chord: return "弦"
        case .scale: return "阶"
        case .rhythm: return "节"
        case .song: return "歌"
        }
    }

    var accent: Color {
        switch self {
        case .left: return GitaTheme.categoryYellow
        case .right: return GitaTheme.categoryOrange
        case .both: return GitaTheme.categoryCyan
        case .chord: return GitaTheme.categoryBlue
        case .scale: return GitaTheme.categoryPurple
        case .rhythm: return GitaTheme.categoryOrange
        case .song: return GitaTheme.categoryPurple
        }
    }
}

enum TaskStatus: String, Codable {
    case active, done
}

enum UserRole: String, CaseIterable {
    case guest, novice, vip

    var label: String {
        switch self {
        case .guest: return "游客"
        case .novice: return "新手"
        case .vip: return "高光"
        }
    }
}
