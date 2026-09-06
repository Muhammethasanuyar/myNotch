import SwiftUI

extension EnvironmentValues {
    /// How large the content of a compact wing (artwork, meter, mark) may be, in points. The engine
    /// sets it per state: `NotchLayout.compactWingContentSize` beside the housing, and the larger
    /// `popupWingContentSize` while a popup widens the surface, so the wings keep up with the title
    /// strip beneath them instead of shrinking into its corners.
    @Entry var wingContentSize: CGFloat = NotchLayout.compactWingContentSize
}
