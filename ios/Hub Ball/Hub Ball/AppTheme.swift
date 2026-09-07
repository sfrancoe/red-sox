import SwiftUI

enum AppColor {
    private static var selectedTeam: HubTeam {
        let stored = UserDefaults.standard.string(forKey: HubPreferences.selectedTeamKey)
        return HubTeam(rawValue: stored ?? "") ?? .boston
    }

    static let cream = Color(red: 0.957, green: 0.969, blue: 0.980)
    static let paper = Color.white

    static var paleBlue: Color { Color(hubHex: selectedTeam.colors.background) }
    static var paleRed: Color { Color(hubHex: selectedTeam.colors.banner) }
    static var navy: Color { Color(hubHex: selectedTeam.colors.secondary) }
    static var red: Color { Color(hubHex: selectedTeam.colors.primary) }
    static var darkRed: Color { Color(hubHex: selectedTeam.colors.accentDark) }
    static var green: Color { Color(hubHex: selectedTeam.colors.positive) }
    static var hunterGreen: Color { Color(hubHex: selectedTeam.colors.navigation) }
    static var ink: Color { Color(hubHex: selectedTeam.colors.ink) }
    static var border: Color { Color(hubHex: selectedTeam.colors.border) }
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
            .padding(padding)
            .background(AppColor.paper)
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColor.border.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: AppColor.navy.opacity(0.08), radius: 12, y: 4)
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
