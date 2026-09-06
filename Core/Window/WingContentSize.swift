import SwiftUI

extension EnvironmentValues {
    /// How large the content of a compact wing (artwork, meter, mark) may be, in points. The engine
    /// sets it from the surface's current height (`NotchLayout.wingContentSize`): about the
    /// housing's height in the compact strip, most of the surface while a popup is open, so the
    /// wings grow and shrink with the notch instead of staying small inside a large surface.
    @Entry var wingContentSize: CGFloat = NotchLayout.defaultWingContentSize
}
