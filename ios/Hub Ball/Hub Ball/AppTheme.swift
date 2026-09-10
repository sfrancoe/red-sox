import SwiftUI

enum AppColor {
    private static var selectedTeam: HubTeam {
        let stored = UserDefaults.standard.string(forKey: HubPreferences.selectedTeamKey)
        return HubTeam(rawValue: stored ?? "") ?? .boston
    }

    // Hub Ball's neutral field: every screen and panel sits on the same warm paper.
    static let cream = Color(red: 239.0 / 255.0, green: 231.0 / 255.0, blue: 213.0 / 255.0)
    static let paper = cream
    static let ink = Color.black
    static let resultWin = Color(red: 0.76, green: 0.88, blue: 0.78)
    static let resultLoss = Color(red: 0.94, green: 0.76, blue: 0.76)

    static var paleBlue: Color {
        switch selectedTeam {
        case .boston: Color(red: 0.918, green: 0.945, blue: 0.965)
        case .newYork: Color(red: 0.910, green: 0.933, blue: 0.957)
        case .newYorkMets: Color(red: 0.918, green: 0.945, blue: 0.980)
        case .tampaBay: Color(red: 0.906, green: 0.953, blue: 0.980)
        }
    }

    static var paleRed: Color {
        cream
    }

    static var navy: Color {
        ink
    }

    static var red: Color {
        ink
    }

    static var darkRed: Color {
        ink
    }

    static var green: Color {
        ink
    }

    static var hunterGreen: Color {
        ink
    }

    static var teamAccent: Color {
        switch selectedTeam {
        case .boston: Color(red: 0.741, green: 0.188, blue: 0.224)
        case .newYork: Color(red: 0.047, green: 0.137, blue: 0.251)
        case .newYorkMets: Color(red: 1.000, green: 0.349, blue: 0.063)
        case .tampaBay: Color(red: 0.000, green: 0.478, blue: 0.698)
        }
    }

    static var accentSoft: Color {
        teamAccent.opacity(0.14)
    }

    static var border: Color {
        teamAccent.opacity(0.46)
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
            .shadow(color: AppColor.teamAccent.opacity(0.17), radius: 10)
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
            .shadow(color: AppColor.teamAccent.opacity(configuration.isPressed ? 0.08 : 0.14), radius: 7)
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
