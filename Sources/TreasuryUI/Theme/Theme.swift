import SwiftUI

/// Single place to tune look & feel. iPad-first sizing.
public enum Theme {
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
