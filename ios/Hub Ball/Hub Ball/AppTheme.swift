import SwiftUI

enum AppColor {
    static let night = Color(hubHex: "#0B1B2B")
    static let nightRaised = Color(hubHex: "#14293D")
    static let rule = Color(hubHex: "#26415A")
    static let bone = Color(hubHex: "#F5F2EA")
    static let boneMuted = Color(hubHex: "#7C93A8")
    static let amber = Color(hubHex: "#E8A33D")
    static let steel = Color(hubHex: "#4FA3D1")

    // Legacy aliases keep existing view structure intact while routing every active
    // color through the Night Game palette above.
    static let paper = night
    static let paperRaised = nightRaised
    static let ink = bone
    static let inkMuted = boneMuted
    static let accent = amber
    static let positive = amber
    static let cream = night
    static let resultWin = nightRaised
    static let resultLoss = nightRaised
    static let resultWinText = amber
    static let resultLossText = steel
    static let teamAccent = bone
    static let accentSoft = nightRaised
    static let paleBlue = nightRaised
    static let paleRed = night
    static let navy = bone
    static let red = steel
    static let darkRed = steel
    static let green = amber
    static let hunterGreen = boneMuted
    static let border = rule
    static let separator = rule
    static let panelBorderWidth: CGFloat = 1
}

enum AppFont {
    static let displayLarge = Font.custom("BarlowCondensed-SemiBold", size: 30)
    static let displayMedium = Font.custom("BarlowCondensed-SemiBold", size: 22)
    static let displaySmall = Font.custom("BarlowCondensed-SemiBold", size: 17)
    static let body = Font.custom("Inter-Regular", size: 16)
    static let bodySmall = Font.custom("Inter-Regular", size: 14)
    static let label = Font.custom("Inter-Medium", size: 12)
    static let numberExtraLarge = Font.custom("Inter-Medium", size: 40)
    static let numberLarge = Font.custom("Inter-Medium", size: 24)
    static let number = Font.custom("Inter-Regular", size: 14)
}

private extension Color {
    init(hubHex: String) {
        let value = UInt64(hubHex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

extension View {
    func cardStyle(accent: Color? = nil, padding: CGFloat = 16) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.horizontal, padding)
            .padding(.bottom, padding)
            .overlay(alignment: .top) {
                Rectangle().fill(accent ?? AppColor.rule).frame(height: 1)
            }
            .clipShape(Rectangle())
    }

    func panelElevation() -> some View {
        self
    }
}

struct HubProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.label)
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? AppColor.nightRaised : AppColor.night)
            .contentShape(Rectangle())
    }
}

// Use the available content width, not the physical screen: iPad windows can resize.
private struct ContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 390
}

extension EnvironmentValues {
    var hubContentWidth: CGFloat {
        get { self[ContentWidthKey.self] }
        set { self[ContentWidthKey.self] = newValue }
    }
}

struct HubCardGrid<Content: View>: View {
    @Environment(\.hubContentWidth) private var width
    var minimumWidth: CGFloat = 340
    var compactSpacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        let columns = width - 32 >= minimumWidth * 2 + 16 ? 2 : 1
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns),
            alignment: .leading,
            spacing: width >= 650 ? 16 : compactSpacing,
            content: content
        )
    }
}
