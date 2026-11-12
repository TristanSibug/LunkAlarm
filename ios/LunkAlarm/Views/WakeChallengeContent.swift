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
                NativeMathAnswerField(text: answer, color: UIColor(theme.text), placeholderColor: UIColor(theme.muted)) { value in
                    let clean = String(value.filter { $0.isASCII && $0.isNumber }.prefix(3))
                    if clean.count < answer.count { answer = clean } else { enter(clean) }
                    return answer
                }.frame(height: 36).padding(16)
                    .background(theme.field, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
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

// UIKit must receive the accepted value synchronously. A completed one-digit
// answer can leave SwiftUI's state unchanged (empty -> empty), so a Binding alone
// does not reliably clear the text displayed by the native field.
private struct NativeMathAnswerField: UIViewRepresentable {
    let text: String
    let color: UIColor
    let placeholderColor: UIColor
    var edit: (String) -> String
    func makeCoordinator() -> Coordinator { Coordinator(edit: edit) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.font = .systemFont(ofSize: 28, weight: .light)
        field.textAlignment = .center
        field.autocorrectionType = .no
        field.accessibilityIdentifier = "nativeMathAnswer"
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.edit = edit
        field.textColor = color
        field.tintColor = color
        field.attributedPlaceholder = NSAttributedString(string: "Your answer", attributes: [.foregroundColor: placeholderColor])
        if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject {
        var edit: (String) -> String
        init(edit: @escaping (String) -> String) { self.edit = edit }
        @objc func changed(_ field: UITextField) {
            let accepted = edit(field.text ?? "")
            if field.text != accepted { field.text = accepted }
        }
    }
}
