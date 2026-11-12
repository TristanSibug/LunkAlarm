import SwiftUI

struct AlarmTheme: Identifiable, Sendable {
    let id: String
    let name: String
    let background: Color
    let card: Color
    let text: Color
    let muted: Color
    let accent: Color
    let accent2: Color
    var isLight = false
    var glow = false
    var dayAccent: Color { id == "cobalt-coral" ? accent2 : accent }
    var alarmCardTheme: AlarmTheme {
        guard id == "midnight-cherry" else { return self }
        return AlarmTheme(id: id, name: name, background: background, card: Color(hex: 0xfff8fa), text: Color(hex: 0x351624), muted: Color(hex: 0x735567), accent: Color(hex: 0x91445e), accent2: Color(hex: 0xb23d61), isLight: true)
    }
    var field: Color { isLight ? Color.black.opacity(0.045) : Color.black.opacity(0.25) }
    var border: Color { text.opacity(0.1) }
    var onAccent: Color { isLight ? .white : Color(hex: 0x160f12) }
    var gradient: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing) }
    static func find(_ id: String) -> AlarmTheme { all.first { $0.id == id } ?? all[0] }
    // Light palettes, neutral darks, warm palettes, then green/blue/purple families.
    static var arranged: [AlarmTheme] {
        ["light", "eggshell-white", "linen", "sea-glass", "heritage", "oled", "dark", "sunrise", "ember", "midnight-cherry", "forest", "nord", "deep-ocean", "cobalt-coral", "signal-blue", "tokyo-night", "amethyst", "dracula"].map(find)
    }
    static let all: [AlarmTheme] = [
        AlarmTheme(id: "sunrise", name: "Sunrise", background: Color(hex: 0x0a0c16), card: Color(hex: 0x171923), text: Color(hex: 0xf4f2ff), muted: Color(hex: 0x9a9bb8), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a), glow: true),
        AlarmTheme(id: "oled", name: "OLED Black", background: .black, card: Color(hex: 0x0c0c0e), text: Color(hex: 0xf2f2f5), muted: Color(hex: 0x9a9aa3), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a)),
        AlarmTheme(id: "dark", name: "Dark", background: Color(hex: 0x17181c), card: Color(hex: 0x212329), text: Color(hex: 0xececf1), muted: Color(hex: 0x9a9ba6), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a)),
        AlarmTheme(id: "light", name: "Light", background: Color(hex: 0xf3f2fa), card: .white, text: Color(hex: 0x1c1b2e), muted: Color(hex: 0x5b5c76), accent: Color(hex: 0xc4520a), accent2: Color(hex: 0xd6336c), isLight: true, glow: true),
        AlarmTheme(id: "tokyo-night", name: "Tokyo Night", background: Color(hex: 0x1a1b26), card: Color(hex: 0x24283b), text: Color(hex: 0xc0caf5), muted: Color(hex: 0x8c93bf), accent: Color(hex: 0x7aa2f7), accent2: Color(hex: 0xbb9af7)),
        AlarmTheme(id: "dracula", name: "Dracula", background: Color(hex: 0x282a36), card: Color(hex: 0x303241), text: Color(hex: 0xf8f8f2), muted: Color(hex: 0xa7a5bd), accent: Color(hex: 0xbd93f9), accent2: Color(hex: 0xff79c6)),
        AlarmTheme(id: "nord", name: "Nord", background: Color(hex: 0x2e3440), card: Color(hex: 0x3b4252), text: Color(hex: 0xeceff4), muted: Color(hex: 0xa4b1c4), accent: Color(hex: 0x88c0d0), accent2: Color(hex: 0x81a1c1)),
        AlarmTheme(id: "linen", name: "Linen", background: Color(hex: 0xf5efe5), card: Color(hex: 0xfffcf6), text: Color(hex: 0x302921), muted: Color(hex: 0x766858), accent: Color(hex: 0x986020), accent2: Color(hex: 0xb34938), isLight: true),
        AlarmTheme(id: "sea-glass", name: "Sea Glass", background: Color(hex: 0xeaf3ef), card: Color(hex: 0xf9fffc), text: Color(hex: 0x173c37), muted: Color(hex: 0x526d67), accent: Color(hex: 0x237268), accent2: Color(hex: 0x346d8e), isLight: true),
        AlarmTheme(id: "forest", name: "Forest", background: Color(hex: 0x0b1714), card: Color(hex: 0x142720), text: Color(hex: 0xe4f2e9), muted: Color(hex: 0x9bb5a4), accent: Color(hex: 0x9dcc88), accent2: Color(hex: 0x59c7a5)),
        AlarmTheme(id: "ember", name: "Ember", background: Color(hex: 0x1b1110), card: Color(hex: 0x2b1d1a), text: Color(hex: 0xffeee3), muted: Color(hex: 0xc3a49a), accent: Color(hex: 0xffbb74), accent2: Color(hex: 0xef876d)),
        AlarmTheme(id: "amethyst", name: "Amethyst", background: Color(hex: 0x171123), card: Color(hex: 0x251d36), text: Color(hex: 0xf1eaff), muted: Color(hex: 0xb3a3cb), accent: Color(hex: 0xc5a2ff), accent2: Color(hex: 0xf0a4ce)),
        AlarmTheme(id: "deep-ocean", name: "Deep Ocean", background: Color(hex: 0x081a24), card: Color(hex: 0x102b38), text: Color(hex: 0xe1f5fb), muted: Color(hex: 0x99b9c6), accent: Color(hex: 0x79d2de), accent2: Color(hex: 0x82b0f7)),
        AlarmTheme(id: "eggshell-white", name: "Eggshell White", background: Color(hex: 0xf7f3e8), card: Color(hex: 0xfffefa), text: Color(hex: 0x28343c), muted: Color(hex: 0x636b70), accent: Color(hex: 0x566a78), accent2: Color(hex: 0x6d6252), isLight: true),
        // Reference stripes 1 / 3 / 4: oxblood, ivory and navy.
        AlarmTheme(id: "heritage", name: "Heritage", background: Color(hex: 0xf9efd4), card: Color(hex: 0xfffdf5), text: Color(hex: 0x032d3f), muted: Color(hex: 0x52626b), accent: Color(hex: 0x7d0500), accent2: Color(hex: 0x032d3f), isLight: true),
        // Reference stripes 2 / 4 / 5: crimson cards, navy background, steel-blue accents.
        // Pale blue/rose text keeps the saturated red surfaces readable.
        AlarmTheme(id: "signal-blue", name: "Signal Blue", background: Color(hex: 0x032d3f), card: Color(hex: 0xbe0d1f), text: Color(hex: 0xf1f7fa), muted: Color(hex: 0xe8d7e1), accent: Color(hex: 0xd2e7f2), accent2: Color(hex: 0x699db8)),
        AlarmTheme(id: "cobalt-coral", name: "Cobalt & Coral", background: Color(hex: 0x101c3d), card: Color(hex: 0x1d3057), text: Color(hex: 0xf2f6ff), muted: Color(hex: 0xa8b8d6), accent: Color(hex: 0x92bdff), accent2: Color(hex: 0xff8a85)),
        AlarmTheme(id: "midnight-cherry", name: "Midnight Cherry", background: Color(hex: 0x260f19), card: Color(hex: 0x3d1c2a), text: Color(hex: 0xfff2f6), muted: Color(hex: 0xcaa6b5), accent: Color(hex: 0x9ecbf5), accent2: Color(hex: 0xff8d87))
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct AlarmBackground: View {
    let theme: AlarmTheme
    var body: some View {
        GeometryReader { geometry in
            theme.background
                .overlay(alignment: .topLeading) {
                    if theme.id != "oled" && theme.id != "dark" {
                        RadialGradient(colors: [theme.accent.opacity(theme.isLight ? 0.12 : 0.22), .clear], center: .topLeading,
                                       startRadius: 0, endRadius: max(300, geometry.size.width))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if theme.id != "oled" && theme.id != "dark" {
                        RadialGradient(colors: [theme.accent2.opacity(0.17), .clear], center: .bottomTrailing,
                                       startRadius: 0, endRadius: max(280, geometry.size.width))
                    }
                }
        }.ignoresSafeArea()
    }
}

struct AlarmCard<Content: View>: View {
    let theme: AlarmTheme
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 24) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.border))
    }
}

struct AccentButtonStyle: ButtonStyle {
    let theme: AlarmTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.onAccent).padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(theme.gradient, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: theme.accent2.opacity(0.2), radius: 14, y: 6)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ChipStyle: ButtonStyle {
    let theme: AlarmTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(theme.text)
            .background(theme.text.opacity(configuration.isPressed ? 0.15 : 0.065), in: Capsule())
            .overlay(Capsule().stroke(theme.border))
            .contentShape(Capsule())
    }
}
