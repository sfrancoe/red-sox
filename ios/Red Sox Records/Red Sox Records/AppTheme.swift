import SwiftUI

enum AppColor {
    static let cream = Color(red: 0.957, green: 0.969, blue: 0.980)
    static let paper = Color.white
    static let paleBlue = Color(red: 0.918, green: 0.945, blue: 0.965)
    static let paleRed = Color(red: 0.720, green: 0.200, blue: 0.240)
    static let navy = Color(red: 0.082, green: 0.196, blue: 0.294)
    static let red = Color(red: 0.741, green: 0.188, blue: 0.224)
    static let green = Color(red: 0.157, green: 0.439, blue: 0.322)
    static let hunterGreen = Color(red: 0.075, green: 0.245, blue: 0.175)
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
