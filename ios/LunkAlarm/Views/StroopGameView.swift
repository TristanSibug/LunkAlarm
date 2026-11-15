import SwiftUI

struct StroopGameView: View {
    let round: StroopRound
    let answered: Int
    let rounds: Int
    let theme: AlarmTheme
    var submit: (StroopColor) -> Void
    var body: some View {
        VStack(spacing: 18) {
            Text("\(answered) / \(rounds) rounds").font(.headline).accessibilityIdentifier("stroopProgress")
            Text("Choose the word’s ink color. Ignore the word and button colors.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(theme.muted)
            Text(round.word.name.uppercased())
                .font(.system(size: 56, weight: .bold)).tracking(2).lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(round.ink.inkColor)
                .frame(maxWidth: .infinity, minHeight: 140).padding(.horizontal, 16)
                .background(Color(hex: 0x10131b), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14)))
                .accessibilityLabel("\(round.word.name), written in \(round.ink.name.lowercased()) ink")
                .accessibilityIdentifier("stroopWord")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(Array(round.choices.enumerated()), id: \.element) { index, color in
                    let paint = round.buttonColors[index]
                    Button {
                        AlarmHaptics.keypress()
                        submit(color)
                    } label: {
                        Text(color.name).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .foregroundStyle(paint.buttonText)
                            .background(paint.buttonFill, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
                    }.buttonStyle(.plain).accessibilityLabel(color.name)
                        .accessibilityValue("\(paint.name) background")
                        .accessibilityIdentifier("stroop-choice-" + color.rawValue)
                }
            }
        }
    }
}

private extension StroopColor {
    var inkColor: Color {
        switch self { case .red: Color(hex: 0xff6778); case .blue: Color(hex: 0x6daaff); case .green: Color(hex: 0x55dba9); case .yellow: Color(hex: 0xffda6b) }
    }
    var buttonFill: Color {
        switch self { case .red: Color(hex: 0x9c2138); case .blue: Color(hex: 0x2154a0); case .green: Color(hex: 0x11734e); case .yellow: Color(hex: 0xf1c84f) }
    }
    var buttonText: Color { self == .yellow ? Color(hex: 0x17130a) : .white }
}
