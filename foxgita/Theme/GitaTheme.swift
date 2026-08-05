//
//  GitaTheme.swift
//  foxgita — Design tokens from DESIGN_SYSTEM_SPEC v2.0
//
//  Colours live in Assets.xcassets/Colors as light/dark pairs, so appearance
//  switching is handled by the system instead of by branching in views.
//

import SwiftUI

enum GitaTheme {
    // Action
    static let brand500 = Color(.brandPrimary)
    static let brand50 = Color(.brandSoft)
    static let brandOn = Color(.brandOn)

    // Background
    static let bgDefault = Color(.bgDefault)
    static let bgSurface = Color(.bgSurface)
    static let bgSubtle = Color(.bgSubtle)

    // Text
    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let textTertiary = Color(.textTertiary)
    static let textOnPrimary = Color(.brandOn)

    // Icon
    static let iconPrimary = Color(.iconPrimary)
    static let iconSecondary = Color(.iconSecondary)
    static let iconInactive = Color(.iconInactive)
    static let iconActive = Color(.brandPrimary)

    // Border / Status
    static let borderSubtle = Color(.borderSubtle)
    static let borderInactive = Color(.borderInactive)
    static let statusSuccess = Color(.statusSuccess)
    static let statusError = Color(.statusError)

    // Category
    static let categoryBlue = Color(.categoryBlue)
    static let categoryOrange = Color(.categoryOrange)
    static let categoryYellow = Color(.categoryYellow)
    static let categoryPurple = Color(.categoryPurple)
    static let categoryCyan = Color(.categoryCyan)

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

    static let shadowCard = Color(.shadowCard)
    static let shadowFab = Color(.shadowFab)
}

enum PracticeCategory: String, Codable, CaseIterable, Identifiable {
    case left, right, both, chord, scale, rhythm, song

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return String(localized: "左手")
        case .right: return String(localized: "右手")
        case .both: return String(localized: "双手")
        case .chord: return String(localized: "和弦")
        case .scale: return String(localized: "音阶")
        case .rhythm: return String(localized: "节奏")
        case .song: return String(localized: "歌曲")
        }
    }

    var shortTag: String {
        switch self {
        case .left, .right, .both: return String(localized: "技")
        case .chord: return String(localized: "弦")
        case .scale: return String(localized: "阶")
        case .rhythm: return String(localized: "节")
        case .song: return String(localized: "歌")
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
