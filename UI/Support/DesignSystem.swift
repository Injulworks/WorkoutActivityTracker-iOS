import SwiftUI

/// Pure-black, high-contrast, single-accent theme — "Nokia simplicity meets
/// Apple HIG," per the design spec. Centralized so no view hardcodes a color.
enum Theme {
    static let background = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.98) // single subtle accent
    static let cardBackground = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.12)
    static let destructive = Color(red: 1.0, green: 0.35, blue: 0.35)

    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 14
        static let input: CGFloat = 12
        static let dialog: CGFloat = 20
        static let sheet: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Font {
        static let clock = SwiftUI.Font.system(size: 68, weight: .semibold, design: .rounded)
        static let sectionTitle = SwiftUI.Font.system(size: 28, weight: .bold)
        static let screenTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 18, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 16, weight: .regular)
        static let secondary = SwiftUI.Font.system(size: 14, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
    }

    enum Animation {
        static let button = SwiftUI.Animation.easeOut(duration: 0.12)
        static let screenTransition = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let cardExpansion = SwiftUI.Animation.easeInOut(duration: 0.2)
    }
}

/// `.symbolEffect(.pulse, isActive:)` only exists on iOS 17+, but this app's
/// deployment target is iOS 16 (to stay installable on older
/// devices). This modifier gives the same "pulsing while active" look on
/// both: the real symbol effect on 17+, a manual opacity/scale animation
/// otherwise. Used anywhere the app wants a pulsing SF Symbol (Voice Mission
/// listening indicator, etc.) without gating deployment target on iOS 17.
struct PulsingModifier: ViewModifier {
    let isActive: Bool
    @State private var animate = false

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.pulse, isActive: isActive)
        } else {
            content
                .opacity(isActive && animate ? 0.4 : 1.0)
                .scaleEffect(isActive && animate ? 0.92 : 1.0)
                .onAppear {
                    guard isActive else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        animate = true
                    }
                }
                .onChange(of: isActive) { newValue in
                    if newValue {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            animate = true
                        }
                    } else {
                        animate = false
                    }
                }
        }
    }
}

extension View {
    func pulsing(isActive: Bool) -> some View {
        modifier(PulsingModifier(isActive: isActive))
    }
}

/// Reusable frosted card used for AlarmCard / AudioCard / RecordingCard /
/// PlaylistCard / StatisticsCard / BluetoothCard per the component spec.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

struct PrimaryButton: View {
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.cardTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .foregroundStyle(isDestructive ? Theme.destructive : Color.black)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(isDestructive ? Color.clear : Theme.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .stroke(isDestructive ? Theme.destructive : Color.clear, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Animation.button, value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(minWidth: 44, minHeight: 44) // HIG minimum touch target
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Simple bar-style waveform, reusable for recorder live-level and playback preview.
struct WaveformView: View {
    let levels: [Float]
    var barColor: Color = Theme.primaryText

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(levels.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor.opacity(0.8))
                        .frame(width: max(2, geo.size.width / CGFloat(max(levels.count, 1)) - 2),
                               height: max(2, CGFloat(levels[i]) * geo.size.height))
                }
            }
            .frame(height: geo.size.height, alignment: .center)
        }
    }
}

