import SwiftUI

/// Reusable picker for switching between visualizations of the same dataset.
/// The pattern is consistent across Dashboard, Reports, and the Trading Lab.
public struct ChartModeSwitcher<Mode: Hashable & CaseIterable & RawRepresentable>: View
where Mode.RawValue == String, Mode.AllCases: RandomAccessCollection
{
    @Binding public var selection: Mode
    public let label: (Mode) -> String

    public init(selection: Binding<Mode>, label: @escaping (Mode) -> String = { $0.rawValue }) {
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(Mode.allCases), id: \.self) { mode in
                Text(label(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
        .accessibilityLabel("Chart visualization mode")
    }
}
