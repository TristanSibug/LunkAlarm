import SwiftUI
import UIKit

struct WakeChallengeContent: View {
    let challenge: TimedWakeChallenge
    let theme: AlarmTheme
    let nativeMath: Bool
    var submitCode: (String) -> Bool
    var submitDigits: (String) -> WakeChallenge.DigitResult
    var place: (Int) -> Void
    var mine: (Int, Bool, Bool) -> Void
    var sudoku: (Int, Int) -> Void
    @State private var code = ""
    @State private var answer = ""
    @State private var hint = ""
    var body: some View {
        Group {
            switch challenge.phase {
            case .typing: typing
            case .math: math
            case .puzzle: JigsawGameView(challenge: challenge, theme: theme, place: place).id(challenge.puzzleSeed)
            case .mines: if let board = challenge.mineBoard { MineGameView(board: board, theme: theme, action: mine).id(challenge.resetCount) }
            case .sudoku: if let board = challenge.sudokuBoard { SudokuGameView(board: board, theme: theme, action: sudoku).id(challenge.resetCount) }
            case .complete: EmptyView()
            }
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(theme.accent) }
        }.onChange(of: challenge.resetCount) { _, _ in code = ""; answer = ""; hint = "Tests restarted." }
    }
    private var typing: some View {
        Group {
            Text("Type this code").font(.headline)
            Text(challenge.code).font(.system(size: 32, weight: .medium, design: .monospaced)).textSelection(.disabled).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("challengeCode")
            NativeCodeField(text: $code, maximumLength: challenge.codeLength, color: UIColor(theme.text)).frame(height: 54).padding(.horizontal, 14)
                .background(theme.field, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.text.opacity(0.22)))
            Button("Check code") {
                if submitCode(code) { hint = ""; code = "" }
                else { hint = "Match the code exactly, including capital letters." }
            }.buttonStyle(AccentButtonStyle(theme: theme)).accessibilityIdentifier("checkCode")
        }
    }
    private var math: some View {
        Group {
            Text("\(challenge.answered) / \(challenge.answered + challenge.remaining) answered").font(.headline).accessibilityIdentifier("mathProgress")
            Text("\(challenge.left) \(challenge.operation.symbol) \(challenge.right)").font(.system(size: 48, weight: .light)).monospacedDigit().accessibilityIdentifier("mathProblem")
            if nativeMath {
                TextField("Your answer", text: Binding(get: { answer }, set: { value in
                    let clean = String(value.filter { $0.isNumber }.prefix(3))
                    if clean.count < answer.count { answer = clean } else { enter(clean) }
                })).keyboardType(.numberPad).font(.system(size: 28, weight: .light)).multilineTextAlignment(.center)
                    .padding(16).background(theme.field, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
                    .accessibilityIdentifier("nativeMathAnswer")
            } else {
                Text(answer.isEmpty ? "Your answer" : answer).font(.system(size: 28, weight: .light)).monospacedDigit()
                    .foregroundStyle(answer.isEmpty ? theme.muted : theme.text).frame(maxWidth: .infinity).padding(16)
                    .background(theme.field, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("mathAnswer")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"], id: \.self) { key in
                        if key.isEmpty { Color.clear.frame(height: 60).accessibilityHidden(true) }
                        else { Button {
                            AlarmHaptics.keypress()
                            if key == "⌫" { answer = String(answer.dropLast()) } else { enter(answer + key) }
                        } label: {
                            Text(key).font(.system(size: 24, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 16).background(theme.card, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel(key == "⌫" ? "Delete digit" : key) }
                    }
                }
            }
        }
    }
    private func enter(_ value: String) {
        switch submitDigits(value) {
        case .incomplete: answer = value
        case .correct: answer = ""; hint = ""
        case .incorrect: answer = ""; hint = "Try that one again."; UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .timedOut: answer = ""; hint = "Time’s up. Tests restarted."
        }
    }
}
