import SwiftUI
import UIKit

struct RingingView: View {
    @Bindable var store: AlarmStore
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
                        if challenge.complete {
                            Button(store.finishing ? "Stopping…" : "Stop alarm") { store.finishCurrent() }.buttonStyle(AccentButtonStyle(theme: store.theme)).disabled(store.finishing)
                        } else {
                            WakeChallengeContent(challenge: challenge, theme: store.theme, nativeMath: store.ringing?.nativeMathKeyboard == true,
                                submitCode: store.submitCode, submitDigits: store.submitMathDigits, place: store.placePiece,
                                mine: { store.mineAction(cell: $0, flag: $1, chord: $2) }, sudoku: { store.sudokuAction(cell: $0, digit: $1) })
                        }
                    }
                    Text("Complete the tests to stop LunkAlarm. iOS also provides its own alarm controls.")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(store.theme.muted)
                }.padding(28).padding(.top, 30).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            }
        }.foregroundStyle(store.theme.text)
            .onChange(of: store.challenge?.resetCount) { _, count in
                guard let count, count > 0 else { return }
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
    let maximumLength: Int
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
        field.accessibilityLabel = "Wake-up code"; field.accessibilityIdentifier = "wakeCodeField"
        field.placeholder = "Type the code"
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.textColor = color
        field.attributedPlaceholder = NSAttributedString(string: "Type the code", attributes: [.foregroundColor: color.withAlphaComponent(0.5)])
        context.coordinator.parent = self
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeCodeField
        init(_ parent: NativeCodeField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); return true }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let accepted = string.count <= 1 && ((field.text ?? "") as NSString).replacingCharacters(in: range, with: string).count <= parent.maximumLength
            if accepted && (!string.isEmpty || range.length > 0) { AlarmHaptics.keypress() }
            return accepted
        }
    }
}
