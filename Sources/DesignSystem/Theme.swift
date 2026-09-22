import SwiftUI
import UIKit

// MARK: - Farben
//
// Farben werden ausschließlich über Tokens angesprochen, nie als Hex-Wert im View.
// Grund: Hell- und Dunkelmodus müssen dieselbe Bedeutung transportieren
// ("Anna ist grün"), nicht denselben Farbwert.

public enum Palette {

    /// Reihenfolge ist stabil: Mitglied 1 bekommt person1, Mitglied 2 person2 und so weiter.
    public static let personTokens = ["person1", "person2", "person3", "person4", "person5", "person6"]

    private static let definitions: [String: (light: UInt32, dark: UInt32)] = [
        // Personenfarben: in beiden Modi gleich gesättigt wahrnehmbar
        "person1":    (0x2F6FED, 0x6E9BFF),   // Blau
        "person2":    (0x1E9E6A, 0x4FD3A0),   // Grün
        "person3":    (0xD1495B, 0xFF8797),   // Rot
        "person4":    (0x9B5DE5, 0xC49BFF),   // Violett
        "person5":    (0xE07A00, 0xFFB454),   // Orange
        "person6":    (0x0E7C86, 0x4FC5CF),   // Petrol

        // Kategorien: gedämpfter als Personenfarben, damit sie nicht konkurrieren
        "tagSchool":  (0x5B6B8C, 0x93A3C4),
        "tagSport":   (0x3E8E5A, 0x77C295),
        "tagHealth":  (0xB05070, 0xE193AC),
        "tagWork":    (0x6A6A73, 0xA8A8B2),
        "tagPrivate": (0x8A6D3B, 0xC4A470),
        "tagNeutral": (0x78788C, 0xAEAEBE),

        // Flächen und Linien
        "surface":      (0xFFFFFF, 0x1C1C1E),
        "surfaceSunken":(0xF2F3F7, 0x121214),
        "hairline":     (0xD9DDE5, 0x3A3A3E),
        "busy":         (0x9AA0AE, 0x6C7280)
    ]

    public static func color(_ token: String) -> Color {
        guard let pair = definitions[token] else { return .gray }
        return Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    public static var surface: Color { color("surface") }
    public static var surfaceSunken: Color { color("surfaceSunken") }
    public static var hairline: Color { color("hairline") }
    public static var busy: Color { color("busy") }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Abstände

public enum Spacing {
    public static let hair: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

// MARK: - Typografie

public enum TypeScale {
    public static let laneHeader = Font.system(size: 13, weight: .semibold, design: .rounded)
    public static let eventTitle = Font.system(size: 13, weight: .medium)
    public static let eventMeta  = Font.system(size: 11, weight: .regular)
    public static let hourLabel  = Font.system(size: 11, weight: .regular, design: .rounded)
    public static let sectionTitle = Font.system(size: 17, weight: .semibold)
}

// MARK: - Zoomstufen der Tagesansicht
//
// Die Ansicht wird nicht zwischen Tag, Woche und Monat umgeschaltet, sondern
// verdichtet. Jede Stufe legt fest, wie viele Punkte eine Stunde hoch ist.

public enum DayZoom: CaseIterable {
    case compact, normal, detailed

    public var pointsPerHour: CGFloat {
        switch self {
        case .compact: return 28
        case .normal: return 52
        case .detailed: return 92
        }
    }

    /// Unterhalb dieser Dauer wird ein Termin nur noch als Balken ohne Text gezeigt.
    public var minimumLabelDuration: TimeInterval {
        switch self {
        case .compact: return 60 * 60
        case .normal: return 30 * 60
        case .detailed: return 15 * 60
        }
    }

    public func zoomedIn() -> DayZoom {
        switch self {
        case .compact: return .normal
        case .normal: return .detailed
        case .detailed: return .detailed
        }
    }

    public func zoomedOut() -> DayZoom {
        switch self {
        case .compact: return .compact
        case .normal: return .compact
        case .detailed: return .normal
        }
    }
}
