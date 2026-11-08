import SwiftUI
import UIKit

struct RingingView: View {
    @Bindable var store: AlarmStore
    @State private var code = ""
    @State private var answer = ""
    @State private var hint = ""
    var body: some View {
        ZStack {
            AlarmBackground(theme: store.theme)
            VStack(spacing: 0) {
            if store.ringing?.hasTests == true { challengeControls }
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "alarm.waves.left.and.right.fill").font(.system(size: 36)).foregroundStyle(store.theme.gradient)
                    Text("Good morning.").font(.system(size: 34, weight: .light))
                    Text(store.ringing?.soundName ?? "LunkAlarm").font(.caption).foregroundStyle(store.theme.muted)
                    if let challenge = store.challenge {
                        if challenge.typingPending {
                            Text("Type this code in 30 seconds").font(.headline)
                            Text(challenge.code).font(.system(size: 32, weight: .medium, design: .monospaced)).textSelection(.disabled)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            NativeCodeField(text: $code, color: UIColor(store.theme.text))
                                .frame(height: 54).padding(.horizontal, 14)
                                .background(store.theme.field, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityLabel("Wake-up code")
                            Button("Check code") {
                                if store.submitCode(code) { hint = ""; code = "" }
                                else { hint = "Match the code exactly, including capital letters." }
                            }.buttonStyle(AccentButtonStyle(theme: store.theme))
                        } else if challenge.remaining > 0 {
                            Text("\(challenge.answered) / \(challenge.answered + challenge.remaining) answered").font(.headline).accessibilityIdentifier("mathProgress")
                            Text("\(challenge.left) + \(challenge.right)").font(.system(size: 48, weight: .light)).monospacedDigit().accessibilityIdentifier("mathProblem")
                            Text(answer.isEmpty ? "Your answer" : answer).font(.system(size: 28, weight: .light)).monospacedDigit()
                                .foregroundStyle(answer.isEmpty ? store.theme.muted : store.theme.text)
                                .frame(maxWidth: .infinity).padding(16).background(store.theme.field, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("mathAnswer")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"], id: \.self) { key in
                                    if key.isEmpty { Color.clear.frame(height: 60).accessibilityHidden(true) }
                                    else { Button { press(key) } label: {
                                        Text(key).font(.system(size: 24, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 16)
                                            .background(store.theme.card, in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain).accessibilityLabel(key == "⌫" ? "Delete digit" : key)
                                    }
                                }
                            }
                        } else {
                            Button(store.finishing ? "Stopping…" : "Stop alarm") { store.finishCurrent() }.buttonStyle(AccentButtonStyle(theme: store.theme)).disabled(store.finishing)
                        }
                    }
                    if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(store.theme.accent) }
                    Text("Complete the tests to stop LunkAlarm. iOS also provides its own alarm controls.")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(store.theme.muted)
                }.padding(28).padding(.top, 30).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            }
        }.foregroundStyle(store.theme.text)
            .onChange(of: store.ringing?.id) { _, _ in code = ""; answer = ""; hint = "" }
            .onChange(of: store.challenge?.resetCount) { _, count in
                guard let count, count > 0 else { return }
                code = ""; answer = ""; hint = "Time’s up. Tests restarted and sound is back on."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            .alert("LunkAlarm", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private var challengeControls: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let challenge = store.challenge, !challenge.complete {
                    let seconds = challenge.secondsRemaining(now: context.date)
                    Label("\(seconds)s", systemImage: "timer")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(seconds <= 3 ? store.theme.accent2 : store.theme.muted)
                        .accessibilityIdentifier("challengeTimeRemaining")
                }
            }
            Spacer()
            Toggle("Sound", isOn: Binding(get: { store.challengeSoundEnabled }, set: { store.setChallengeSound($0) }))
                .font(.system(size: 13, weight: .medium)).fixedSize().tint(store.theme.accent2)
                .accessibilityLabel("Alarm sound while answering").accessibilityIdentifier("challengeSoundToggle")
                .disabled(store.finishing)
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }
    private func press(_ key: String) {
        switch key {
        case "⌫": if !answer.isEmpty { answer.removeLast() }
        default:
            answer += key
            switch store.submitMathDigits(answer) {
            case .incomplete: break
            case .correct: answer = ""; hint = ""
            case .incorrect:
                answer = ""; hint = "Try that one again."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .timedOut:
                answer = ""; hint = "Time’s up. Tests restarted and sound is back on."
            }
        }
    }
}

private final class NoPasteTextField: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }
    override func paste(_ sender: Any?) {}
    override func buildMenu(with builder: any UIMenuBuilder) { builder.remove(menu: .standardEdit) }
}

struct NativeCodeField: UIViewRepresentable {
    @Binding var text: String
    let color: UIColor
    func makeUIView(context: Context) -> UITextField {
        let field = NoPasteTextField()
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 24, weight: .regular)
        field.textAlignment = .center
        field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.spellCheckingType = .no; field.smartQuotesType = .no
        field.smartDashesType = .no; field.smartInsertDeleteType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.accessibilityLabel = "Wake-up code"
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.textColor = color
        context.coordinator.parent = self
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeCodeField
        init(_ parent: NativeCodeField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            string.count <= 1 && ((field.text ?? "") as NSString).replacingCharacters(in: range, with: string).count <= 8
        }
    }
}
