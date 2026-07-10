import SwiftUI

/// Design tokens lifted from docs/design/null-run-prototype.html.
enum Theme {
    // Light surfaces
    static let bg = Color(hex: 0xF7F4EE)
    static let card = Color.white
    static let ink = Color(hex: 0x26221C)
    static let muted = Color(hex: 0x8A8072)
    static let faint = Color(hex: 0xA29A8B)
    static let hairline = Color(hex: 0xECE6DA)
    static let track = Color(hex: 0xE9E3D7)
    static let divider = Color(hex: 0xF0EAE0)
    static let dimBg = Color(hex: 0xF0EDE6)
    static let mapBg = Color(hex: 0xE8E4DA)
    static let mapRoad = Color(hex: 0xD8D2C4)
    static let mapBlock = Color(hex: 0xDED8CA)

    // Dark surfaces (run / locked / scan cam)
    static let darkBg = Color(hex: 0x171512)
    static let darkCard = Color(hex: 0x211E1A)
    static let darkLine = Color(hex: 0x322E28)
    static let darkInk = Color(hex: 0xF2EDE4)
    static let darkDim = Color(hex: 0x6B655B)

    // Greens
    static let green = Color(hex: 0x1E8A5B)
    static let greenDeep = Color(hex: 0x14663F)
    static let greenBright = Color(hex: 0x34B37D)
    static let greenPale = Color(hex: 0x8FD9B4)
    static let greenBgSoft = Color(hex: 0xE4F2EA)
    static let greenDarkPill = Color(hex: 0x243B30)

    // Oranges
    static let orange = Color(hex: 0xE8834A)
    static let orangeSoft = Color(hex: 0xF0975F)
    static let orangeDeep = Color(hex: 0xB85E23)
    static let orangeBg = Color(hex: 0xFBEADD)
    static let orangePale = Color(hex: 0xF0B48A)
    static let orangeInk = Color(hex: 0x7A4A1E)
    static let streakDarkPill = Color(hex: 0x3A2C1E)
    static let guardian = Color(hex: 0xF26522)

    // Purples (mascot / wheel / league)
    static let purple = Color(hex: 0x7A55C6)
    static let purpleMid = Color(hex: 0x8A63D2)
    static let purpleSoft = Color(hex: 0xC2ABEC)
    static let purpleDeep = Color(hex: 0x5E44A0)
    static let purpleBg = Color(hex: 0xEFE9FB)
    static let purpleInk = Color(hex: 0x33244F)
    static let purpleDark = Color(hex: 0x4A3178)

    // Blues (privacy / scan)
    static let blue = Color(hex: 0x3D5C9E)
    static let blueBg = Color(hex: 0xEBF0FA)
    static let bluePale = Color(hex: 0x8FA7D9)

    static let danger = Color(hex: 0xB3403A)
    static let sheetBg = Color(hex: 0xFDFCF9)

    static let cardShadow = Color(hex: 0x5A4B32).opacity(0.06)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Be Vietnam Pro for text, IBM Plex Mono for numbers — per the design.
extension Font {
    static func viet(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "BeVietnamPro-Medium"
        case .semibold: name = "BeVietnamPro-SemiBold"
        case .bold: name = "BeVietnamPro-Bold"
        case .heavy, .black: name = "BeVietnamPro-ExtraBold"
        default: name = "BeVietnamPro-Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .regular: name = "IBMPlexMono-Regular"
        case .medium: name = "IBMPlexMono-Medium"
        case .bold, .heavy: name = "IBMPlexMono-Bold"
        default: name = "IBMPlexMono-SemiBold"
        }
        return .custom(name, size: size)
    }
}

enum Fmt {
    /// 1250 → "1.250" (vi-VN grouping)
    static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 2.37 → "2,37" (km with comma decimals, 2 digits)
    static func dist(_ km: Double) -> String {
        String(format: "%.2f", km).replacingOccurrences(of: ".", with: ",")
    }

    static func time(_ seconds: Int) -> String {
        // h:mm:ss once past an hour, else mm:ss — a 75-minute run must not
        // render as "75:12".
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Pace seconds/km → 7'51"
    static func pace(_ secPerKm: Double?) -> String {
        guard let p = secPerKm, p.isFinite, p > 0 else { return "—" }
        return "\(Int(p) / 60)'\(String(format: "%02d", Int(p) % 60))\""
    }
}
