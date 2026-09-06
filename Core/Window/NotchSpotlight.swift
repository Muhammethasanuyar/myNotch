import SwiftUI

/// The card-side hover language every module shares: an indicator under the cursor lifts towards
/// it and tells the card what is being looked at, elements slide in a beat after one another when
/// the card opens, and a short sentence explains the focused indicator inside the card — the
/// notch panel never shows `.help()` tooltips, so this is the only way to explain a glyph.
struct Spotlight<Element: Hashable>: ViewModifier {
    let element: Element
    @Binding var focus: Element?
    /// Colour of the glow around the lifted indicator; a module's accent.
    let accent: Color

    func body(content: Content) -> some View {
        let active = focus == element
        content
            .scaleEffect(active ? 1.08 : 1)
            .shadow(color: accent.opacity(active ? 0.45 : 0), radius: active ? 8 : 0)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    focus = element
                } else if focus == element {
                    focus = nil
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: active)
    }
}

/// Fades and slides an element in when the card opens, each a beat after the last.
struct Reveal: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
    }
}

/// The sentence that explains the focused indicator, drawn as a pill the card floats over its
/// content. It never takes hits, so the indicator under the cursor stays hovered while it is up.
struct NotchExplanationBubble: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(accent.opacity(0.55), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

extension View {
    /// Marks an indicator the cursor can rest on; `focus` says which one it is resting on.
    func spotlight<Element: Hashable>(_ element: Element, focus: Binding<Element?>, accent: Color) -> some View {
        modifier(Spotlight(element: element, focus: focus, accent: accent))
    }

    /// Staggered entrance: `index` is the element's place in the sequence.
    func reveal(_ appeared: Bool, index: Int) -> some View {
        modifier(Reveal(appeared: appeared, index: index))
    }
}
