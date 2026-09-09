import SwiftUI

enum AppColor {
    private static var selectedTeam: HubTeam {
        let stored = UserDefaults.standard.string(forKey: HubPreferences.selectedTeamKey)
        return HubTeam(rawValue: stored ?? "") ?? .boston
    }

    // A soft-white field lets the white panels read as gently raised surfaces.
    static let cream = Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 246.0 / 255.0)
    static let paper = Color.white
    static var ink: Color { Color(hubHex: selectedTeam.colors.ink) }
    static let resultWin = Color(red: 0.76, green: 0.88, blue: 0.78)
    static let resultLoss = Color(red: 0.94, green: 0.76, blue: 0.76)
    static let resultWinText = Color(red: 0.08, green: 0.42, blue: 0.20)
    static let resultLossText = Color(red: 0.72, green: 0.08, blue: 0.12)

    static var teamAccent: Color { Color(hubHex: selectedTeam.colors.primary) }
    static var accentSoft: Color { teamAccent.opacity(0.14) }
    static var paleBlue: Color { teamAccent.opacity(0.10) }
    static var paleRed: Color { cream }
    static var navy: Color { ink }
    static var red: Color { ink }
    static var darkRed: Color { ink }
    static var green: Color { ink }
    static var hunterGreen: Color { ink }
    static var border: Color { teamAccent.opacity(0.46) }
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
                        .frame(width: 4)
                }
            }
            .clipShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(AppColor.border, lineWidth: 1)
            }
            .panelElevation()
    }

    func panelElevation() -> some View {
        shadow(color: Color.black.opacity(0.11), radius: 7, x: 0, y: 3)
    }
}

struct HubProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? AppColor.teamAccent.opacity(0.22) : AppColor.accentSoft)
            .overlay {
                Rectangle().stroke(AppColor.border, lineWidth: 1)
            }
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
