import SwiftUI

/// Single place to tune look & feel. iPad-first sizing.
public enum Theme {
    /// Default fixed chart height. Prefer `responsiveChartHeight(width:)` from
    /// inside a GeometryReader so charts scale across iPhone, iPad portrait,
    /// and 13" iPad landscape.
    public static let chartHeight: CGFloat = 320
    public static let cardCorner: CGFloat = 18
    public static let cardPadding: CGFloat = 18

    public static let incomeColor   = Color.green
    public static let spendingColor = Color.pink
    public static let neutralColor  = Color.gray
    public static let strategyColor = Color.purple

    /// 8-step categorical palette for stacked / donut charts.
    public static let categoryPalette: [Color] = [
        .blue, .orange, .green, .pink, .purple, .teal, .yellow, .indigo,
    ]

    /// Aspect-aware chart height: ~42% of width, clamped to a readable range.
    /// Returns 220…420 pt.
    public static func responsiveChartHeight(width: CGFloat) -> CGFloat {
        min(420, max(220, width * 0.42))
    }
}

/// Preference key for letting chart wrappers read their container width
/// without forcing the outer layout to flex. Used by chart views to compute
/// `Theme.responsiveChartHeight(width:)` without nesting GeometryReader in
/// the main hierarchy.
public struct ChartWidthKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct Card<Content: View>: View {
    public let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        content()
            .padding(Theme.cardPadding)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}
