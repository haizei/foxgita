//
//  GitaFont.swift
//  foxgita
//
//  Design-system point sizes that still scale with Dynamic Type. Built on
//  UIFontMetrics so a user who picks XXL accessibility text doesn't hit
//  clipped labels on the SE.
//

import SwiftUI
import UIKit

enum GitaFont {
    static func largeTitle(_ weight: Font.Weight = .bold) -> Font {
        scaled(size: 28, weight: weight, textStyle: .largeTitle)
    }

    static func title(_ weight: Font.Weight = .bold) -> Font {
        scaled(size: 20, weight: weight, textStyle: .title3)
    }

    static func headline(_ weight: Font.Weight = .bold) -> Font {
        scaled(size: 18, weight: weight, textStyle: .headline)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        scaled(size: 16, weight: weight, textStyle: .body)
    }

    static func callout(_ weight: Font.Weight = .regular) -> Font {
        scaled(size: 14, weight: weight, textStyle: .callout)
    }

    static func footnote(_ weight: Font.Weight = .regular) -> Font {
        scaled(size: 13, weight: weight, textStyle: .footnote)
    }

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        scaled(size: 12, weight: weight, textStyle: .caption1)
    }

    static func micro(_ weight: Font.Weight = .regular) -> Font {
        scaled(size: 11, weight: weight, textStyle: .caption2)
    }

    static func metric(_ weight: Font.Weight = .bold) -> Font {
        Font(uiFont(size: 22, weight: weight, textStyle: .title2)).monospacedDigit()
    }

    static func timer(_ weight: Font.Weight = .medium) -> Font {
        Font(uiFont(size: 24, weight: weight, textStyle: .title2)).monospacedDigit()
    }

    private static func scaled(size: CGFloat, weight: Font.Weight, textStyle: UIFont.TextStyle) -> Font {
        Font(uiFont(size: size, weight: weight, textStyle: textStyle))
    }

    private static func uiFont(size: CGFloat, weight: Font.Weight, textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
