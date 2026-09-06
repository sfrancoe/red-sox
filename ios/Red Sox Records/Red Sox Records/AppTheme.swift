import SwiftUI

enum AppColor {
    private static var usesYankeesPalette: Bool {
        UserDefaults.standard.string(forKey: HubPreferences.selectedTeamKey) == HubTeam.newYork.id
    }

    static let cream = Color(red: 0.957, green: 0.969, blue: 0.980)
    static let paper = Color.white

    static var paleBlue: Color {
        usesYankeesPalette
            ? Color(red: 0.910, green: 0.933, blue: 0.957)
            : Color(red: 0.918, green: 0.945, blue: 0.965)
    }

    static var paleRed: Color {
        usesYankeesPalette
            ? Color(red: 0.047, green: 0.137, blue: 0.251)
            : Color(red: 0.720, green: 0.200, blue: 0.240)
    }

    static var navy: Color {
        usesYankeesPalette
            ? Color(red: 0.047, green: 0.137, blue: 0.251)
            : Color(red: 0.082, green: 0.196, blue: 0.294)
    }

    static var red: Color {
        usesYankeesPalette
            ? Color(red: 0.047, green: 0.137, blue: 0.251)
            : Color(red: 0.741, green: 0.188, blue: 0.224)
    }

    static var darkRed: Color {
        usesYankeesPalette
            ? Color(red: 0.025, green: 0.082, blue: 0.153)
            : Color(red: 0.545, green: 0.047, blue: 0.075)
    }

    static var green: Color {
        usesYankeesPalette
            ? Color(red: 0.106, green: 0.247, blue: 0.396)
            : Color(red: 0.157, green: 0.439, blue: 0.322)
    }

    static var hunterGreen: Color {
        usesYankeesPalette
            ? Color(red: 0.047, green: 0.137, blue: 0.251)
            : Color(red: 0.075, green: 0.245, blue: 0.175)
    }

    static var ink: Color {
        usesYankeesPalette
            ? Color(red: 0.025, green: 0.082, blue: 0.153)
            : Color(red: 0.090, green: 0.129, blue: 0.169)
    }

    static var border: Color {
        usesYankeesPalette
            ? Color(red: 0.776, green: 0.824, blue: 0.871)
            : Color(red: 0.847, green: 0.882, blue: 0.910)
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
