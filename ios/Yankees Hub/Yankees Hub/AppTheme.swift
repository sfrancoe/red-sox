import SwiftUI

enum AppColor {
    static let cream = Color(red: 0.957, green: 0.969, blue: 0.980)
    static let paper = Color.white
    static let paleBlue = Color(red: 0.918, green: 0.945, blue: 0.965)
    static let paleRed = Color(red: 0.040, green: 0.110, blue: 0.205)
    static let navy = Color(red: 0.027, green: 0.086, blue: 0.160)
    static let red = Color(red: 0.710, green: 0.090, blue: 0.145)
    static let green = Color(red: 0.180, green: 0.330, blue: 0.490)
    static let hunterGreen = Color(red: 0.055, green: 0.150, blue: 0.270)
    static let ink = Color(red: 0.090, green: 0.129, blue: 0.169)
    static let border = Color(red: 0.847, green: 0.882, blue: 0.910)
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
