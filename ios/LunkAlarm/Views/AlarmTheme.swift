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
    var field: Color { isLight ? Color.black.opacity(0.045) : Color.black.opacity(0.25) }
    var border: Color { text.opacity(0.1) }
    var onAccent: Color { isLight ? .white : Color(hex: 0x160f12) }
    var gradient: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing) }
    static func find(_ id: String) -> AlarmTheme { all.first { $0.id == id } ?? all[0] }
    static let all: [AlarmTheme] = [
        AlarmTheme(id: "sunrise", name: "Sunrise", background: Color(hex: 0x0a0c16), card: Color(hex: 0x171923), text: Color(hex: 0xf4f2ff), muted: Color(hex: 0x9a9bb8), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a), glow: true),
        AlarmTheme(id: "oled", name: "OLED Black", background: .black, card: Color(hex: 0x0c0c0e), text: Color(hex: 0xf2f2f5), muted: Color(hex: 0x9a9aa3), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a)),
        AlarmTheme(id: "dark", name: "Dark", background: Color(hex: 0x17181c), card: Color(hex: 0x212329), text: Color(hex: 0xececf1), muted: Color(hex: 0x9a9ba6), accent: Color(hex: 0xffa94d), accent2: Color(hex: 0xff6b7a)),
        AlarmTheme(id: "light", name: "Light", background: Color(hex: 0xf3f2fa), card: .white, text: Color(hex: 0x1c1b2e), muted: Color(hex: 0x5b5c76), accent: Color(hex: 0xc4520a), accent2: Color(hex: 0xd6336c), isLight: true, glow: true),
        AlarmTheme(id: "tokyo-night", name: "Tokyo Night", background: Color(hex: 0x1a1b26), card: Color(hex: 0x24283b), text: Color(hex: 0xc0caf5), muted: Color(hex: 0x8c93bf), accent: Color(hex: 0x7aa2f7), accent2: Color(hex: 0xbb9af7)),
        AlarmTheme(id: "vscode-blue", name: "VS Code Blue", background: Color(hex: 0x002451), card: Color(hex: 0x082e59), text: Color(hex: 0xe8f0ff), muted: Color(hex: 0xa2bcdb), accent: Color(hex: 0x5db0ff), accent2: Color(hex: 0x3a86ff)),
        AlarmTheme(id: "dracula", name: "Dracula", background: Color(hex: 0x282a36), card: Color(hex: 0x303241), text: Color(hex: 0xf8f8f2), muted: Color(hex: 0xa7a5bd), accent: Color(hex: 0xbd93f9), accent2: Color(hex: 0xff79c6)),
        AlarmTheme(id: "nord", name: "Nord", background: Color(hex: 0x2e3440), card: Color(hex: 0x3b4252), text: Color(hex: 0xeceff4), muted: Color(hex: 0xa4b1c4), accent: Color(hex: 0x88c0d0), accent2: Color(hex: 0x81a1c1))
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
                    if theme.glow {
                        RadialGradient(colors: [Color(hex: 0x7c5cff).opacity(0.24), .clear], center: .topLeading,
                                       startRadius: 0, endRadius: max(300, geometry.size.width))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if theme.glow {
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
