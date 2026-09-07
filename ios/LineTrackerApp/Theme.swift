import SwiftUI

/// Ports the color palette straight from frontend/src/index.css's
/// :root variables, so the app matches the web version instead of
/// falling back to default system colors.
extension Color {
    static let ltBackground = Color(hex: 0x0B0E11)
    static let ltSurface = Color(hex: 0x161A1E)
    static let ltSurfaceRaised = Color(hex: 0x1D2227)
    static let ltBorder = Color(hex: 0x2A3038)
    static let ltBorderBright = Color(hex: 0x3A4250)

    static let ltTextPrimary = Color(hex: 0xE6E8EB)
    static let ltTextSecondary = Color(hex: 0x8B92A0)
    static let ltTextTertiary = Color(hex: 0x565D69)

    // index.css: --accent: blue; --accent-dim: white; --success: #3DDC97; --danger: #E0585C;
    static let ltAccent = Color.blue
    static let ltAccentDim = Color.white
    static let ltSuccess = Color(hex: 0x3DDC97)
    static let ltSuccessDim = Color(hex: 0x1A3B2E)
    static let ltDanger = Color(hex: 0xE0585C)
    static let ltDangerDim = Color(hex: 0x3D2226)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
