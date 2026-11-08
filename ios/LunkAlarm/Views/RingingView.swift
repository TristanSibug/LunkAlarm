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
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "alarm.waves.left.and.right.fill").font(.system(size: 36)).foregroundStyle(store.theme.gradient)
                    Text("Good morning.").font(.system(size: 34, weight: .light))
                    Text(store.ringing?.soundName ?? "LunkAlarm").font(.caption).foregroundStyle(store.theme.muted)
                    if let challenge = store.challenge {
                        if challenge.typingPending {
                            Text("Type this code to wake up").font(.headline)
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
                            Text("\(challenge.remaining) \(challenge.remaining == 1 ? "problem" : "problems") to go").font(.headline)
                            Text("\(challenge.left) + \(challenge.right)").font(.system(size: 48, weight: .light)).monospacedDigit()
                            Text(answer.isEmpty ? "Your answer" : answer).font(.system(size: 28, weight: .light)).monospacedDigit()
                                .foregroundStyle(answer.isEmpty ? store.theme.muted : store.theme.text)
                                .frame(maxWidth: .infinity).padding(16).background(store.theme.field, in: RoundedRectangle(cornerRadius: 14))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"], id: \.self) { key in
                                    Button { press(key) } label: {
                                        Text(key).font(.system(size: 24, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 16)
                                            .background(store.theme.card, in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain).accessibilityLabel(key == "⌫" ? "Delete digit" : key)
                                }
                            }
                        } else {
                            Button("Stop alarm") { store.finishCurrent() }.buttonStyle(AccentButtonStyle(theme: store.theme))
                        }
                    }
                    if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(store.theme.accent) }
                    Text("Wake-up tests run while LunkAlarm is open. iOS controls the Lock Screen alarm.")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(store.theme.muted)
                }.padding(28).padding(.top, 30).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(store.theme.text)
            .onChange(of: store.ringing?.id) { _, _ in code = ""; answer = ""; hint = "" }
            .alert("LunkAlarm", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private func press(_ key: String) {
        switch key {
        case "⌫": if !answer.isEmpty { answer.removeLast() }
        case "OK":
            if store.submitAnswer(answer) { hint = "" } else { hint = "Try that one again." }
            answer = ""
        default: if answer.count < 3 { answer += key }
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
