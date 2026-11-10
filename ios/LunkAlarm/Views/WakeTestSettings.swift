import SwiftUI

enum WakeTest: String, Identifiable, CaseIterable {
    case typing, math, puzzle, mines, sudoku
    var id: String { rawValue }
    var name: String { switch self { case .typing: "Typing"; case .math: "Math"; case .puzzle: "Puzzle"; case .mines: "Minesweeper"; case .sudoku: "Sudoku" } }
    var title: String { name + " test" }
    func enabled(_ s: AlarmSettings) -> Bool {
        switch self { case .typing: s.typing; case .math: s.mathCount > 0; case .puzzle: s.wakeGames?.puzzle == true; case .mines: s.wakeGames?.mines == true; case .sudoku: s.wakeGames?.sudoku == true }
    }
    func practice(_ s: AlarmSettings) -> TimedWakeChallenge {
        var games = s.wakeGames ?? .init()
        games.puzzle = self == .puzzle; games.mines = self == .mines; games.sudoku = self == .sudoku
        return TimedWakeChallenge(typing: self == .typing, mathCount: self == .math ? max(1, s.mathCount) : 0,
            codeLength: s.typingCodeLength ?? 8, typingTimeLimit: s.typingTimeLimit ?? 30, mathTimeLimit: s.mathTimeLimit ?? 10, games: games)
    }
}

struct WakeTestSelector: View {
    @Binding var settings: AlarmSettings
    let theme: AlarmTheme
    var stopPreview: () -> Void
    @State private var selected: WakeTest?
    @State private var lastMathCount = 3
    var body: some View {
        HStack(spacing: 6) {
            ForEach(WakeTest.allCases) { test in
                let on = test.enabled(settings)
                Button { toggle(test, on: !on) } label: {
                    VStack(spacing: 10) {
                        WakeTestGlyph(test: test).frame(width: 36, height: 29)
                        Text(test.name).font(.system(size: test == .mines ? 9 : 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                            .foregroundStyle(theme.text)
                    }.foregroundStyle(on ? theme.accent2 : theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(on ? theme.accent2.opacity(0.1) : theme.field, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(on ? theme.accent2 : theme.border, lineWidth: on ? 1.5 : 1))
                        .overlay(alignment: .topTrailing) { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.accent2).padding(5) } }
                }.buttonStyle(.plain).accessibilityLabel(test.title).accessibilityValue(on ? "Enabled" : "Disabled")
                    .accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("test-tile-" + test.id)
            }
        }
        .sheet(item: $selected) { test in WakeTestSettingsView(test: test, settings: $settings, theme: theme, stopPreview: stopPreview) }
    }
    private func toggle(_ test: WakeTest, on: Bool) {
        var games = settings.wakeGames ?? .init()
        switch test {
        case .typing: settings.typing = on
        case .math:
            if !on { lastMathCount = settings.mathCount }
            settings.mathCount = on ? max(1, lastMathCount) : 0
        case .puzzle: games.puzzle = on
        case .mines: games.mines = on
        case .sudoku: games.sudoku = on
        }
        settings.wakeGames = games
        selected = on ? test : nil
    }
}

struct WakeTestGlyph: View {
    let test: WakeTest
    var body: some View {
        switch test {
        case .typing: Text("Aa").font(.system(size: 22, weight: .semibold)).fixedSize().accessibilityHidden(true)
        case .math: Text("+=").font(.system(size: 22, weight: .semibold)).fixedSize().accessibilityHidden(true)
        case .puzzle: Image(systemName: "puzzlepiece").font(.system(size: 24)).accessibilityHidden(true)
        case .mines:
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = min(size.width, size.height) * 0.27
                let color = GraphicsContext.Shading.foreground
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: color, lineWidth: 1.5)
                for i in 0..<8 {
                    let angle = Double(i) * .pi / 4
                    var line = Path()
                    line.move(to: CGPoint(x: center.x + cos(angle) * radius * 1.1, y: center.y + sin(angle) * radius * 1.1))
                    line.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 1.65, y: center.y + sin(angle) * radius * 1.65))
                    context.stroke(line, with: color, lineWidth: 1.5)
                }
            }.accessibilityHidden(true)
        case .sudoku:
            Canvas { context, size in
                let side = min(size.width, size.height) * 0.85, origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
                for i in 0...4 {
                    let offset = CGFloat(i) * side / 4
                    var p = Path(); p.move(to: CGPoint(x: origin.x + offset, y: origin.y)); p.addLine(to: CGPoint(x: origin.x + offset, y: origin.y + side))
                    p.move(to: CGPoint(x: origin.x, y: origin.y + offset)); p.addLine(to: CGPoint(x: origin.x + side, y: origin.y + offset))
                    context.stroke(p, with: .foreground, lineWidth: i % 2 == 0 ? 1.4 : 0.7)
                }
            }.accessibilityHidden(true)
        }
    }
}

private struct WakeTestSettingsView: View {
    let test: WakeTest
    @Binding var settings: AlarmSettings
    let theme: AlarmTheme
    var stopPreview: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var practice: WakeTest?
    private var games: WakeGameOptions { settings.wakeGames ?? .init() }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(test.title).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, alignment: .leading)
                Button { stopPreview(); practice = test } label: {
                    HStack(spacing: 8) { Image(systemName: "play.fill").foregroundStyle(theme.accent2); Text("Try") }
                        .font(.system(size: 13, weight: .semibold)).frame(minWidth: 64, minHeight: 22).padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Capsule().stroke(theme.accent2, lineWidth: 1.2))
                }.buttonStyle(.plain).accessibilityIdentifier("try-" + test.id)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18)).frame(width: 32, height: 40) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("Close test settings").accessibilityIdentifier("closeTestSettings")
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { controls }
                    .padding(.horizontal, 20).padding(.bottom, 20)
            }.scrollBounceBehavior(.basedOnSize)
            Button("Done") { dismiss() }.buttonStyle(AccentButtonStyle(theme: theme)).padding(20).accessibilityIdentifier("testSettingsDone")
        }.foregroundStyle(theme.text).background(theme.card).preferredColorScheme(theme.isLight ? .light : .dark)
            .presentationDetents([.height(test == .sudoku ? 590 : test == .mines ? 470 : test == .math ? 430 : 360), .large])
            .presentationDragIndicator(.visible).presentationBackground(theme.card)
            .accessibilityIdentifier("test-settings-" + test.id)
            .fullScreenCover(item: $practice) { kind in WakePracticeView(test: kind, settings: settings, theme: theme) }
    }
    @ViewBuilder private var controls: some View {
        switch test {
        case .typing:
            HStack(alignment: .top, spacing: 12) {
                optionCard { WakeCountSetting(title: "Code length", value: option(\.typingCodeLength, 8), range: 4...10, footer: "4–10 characters", id: "typing-length", theme: theme) }.frame(maxWidth: .infinity)
                optionCard { WakeChoiceSetting(title: "Time limit", value: option(\.typingTimeLimit, 30), choices: WakeTestOptions.typingChoices, id: "typing-timer", theme: theme, suffix: "", footer: "seconds") }.frame(maxWidth: .infinity)
            }
        case .math:
            HStack(alignment: .top, spacing: 12) {
                optionCard { WakeCountSetting(title: "Problems", value: $settings.mathCount, range: 1...8, footer: "1–8 problems", id: "math-count", theme: theme) }.frame(maxWidth: .infinity)
                optionCard { WakeChoiceSetting(title: "Time per question", value: option(\.mathTimeLimit, 10), choices: WakeTestOptions.mathTimes, id: "math-timer", theme: theme) }.frame(maxWidth: .infinity)
            }
            Divider().overlay(theme.border)
            Toggle("Use native keyboard/keypad", isOn: Binding(get: { settings.nativeMathKeyboard == true }, set: { settings.nativeMathKeyboard = $0 }))
                .font(.system(size: 13)).tint(theme.accent2).accessibilityIdentifier("nativeMathKeyboard")
        case .puzzle:
            WakeChoiceSetting(title: "Pieces", value: game(\.puzzlePieces), choices: [6, 8, 10], id: "puzzle-pieces", theme: theme, suffix: "")
            WakeChoiceSetting(title: "Time limit", value: game(\.puzzleSeconds), choices: WakeGameOptions.gameTimes, id: "puzzle-timer", theme: theme)
        case .mines:
            settingTitle("Difficulty")
            HStack(spacing: 8) {
                ForEach(0..<3) { i in difficultyCard(title: ["Easy", "Medium", "Hard"][i], detail: "\([5, 7, 9][i]) × \([5, 7, 9][i])", value: i, selection: game(\.mineDifficulty), id: "mine-difficulty") }
            }
            WakeChoiceSetting(title: "Time limit", value: game(\.mineSeconds), choices: WakeGameOptions.gameTimes, id: "mine-timer", theme: theme)
        case .sudoku:
            settingTitle("Difficulty")
            VStack(spacing: 8) {
                ForEach(0..<2) { row in HStack(spacing: 8) {
                    ForEach((row * 2)..<(row * 2 + 2), id: \.self) { i in difficultyCard(title: ["Easy", "Medium", "Hard", "Difficult"][i], detail: "\(i < 2 ? "4 × 4" : "6 × 6") · \(i % 2 == 0 ? "Easy" : "Hard")", value: i, selection: game(\.sudokuDifficulty), id: "sudoku-difficulty") }
                } }
            }
            WakeChoiceSetting(title: "Time limit", value: game(\.sudokuSeconds), choices: WakeGameOptions.sudokuTimes, id: "sudoku-timer", theme: theme)
        }
    }
    private func option(_ key: WritableKeyPath<AlarmSettings, Int?>, _ fallback: Int) -> Binding<Int> { Binding(get: { settings[keyPath: key] ?? fallback }, set: { settings[keyPath: key] = $0 }) }
    private func game(_ key: WritableKeyPath<WakeGameOptions, Int>) -> Binding<Int> { Binding(get: { games[keyPath: key] }, set: { var g = games; g[keyPath: key] = $0; settings.wakeGames = g }) }
    private func optionCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        content().frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading).padding(10)
            .background(theme.field, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border))
    }
    private func settingTitle(_ title: String) -> some View { Text(title).font(.system(size: 14, weight: .semibold)) }
    private func difficultyCard(title: String, detail: String, value: Int, selection: Binding<Int>, id: String) -> some View {
        Button { selection.wrappedValue = value } label: {
            VStack(spacing: 8) {
                WakeTestGlyph(test: test).frame(width: 25, height: 25).foregroundStyle(selection.wrappedValue == value ? theme.accent2 : theme.muted)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(selection.wrappedValue == value ? theme.accent2.opacity(0.12) : theme.field, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(selection.wrappedValue == value ? theme.accent2 : theme.border, lineWidth: selection.wrappedValue == value ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : []).accessibilityIdentifier("\(id)-\(value)")
    }
}

private struct WakeCountSetting: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let footer: String
    let id: String
    let theme: AlarmTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                countButton("−", delta: -1)
                Text("\(value)").font(.system(size: 23, weight: .semibold)).monospacedDigit().frame(maxWidth: .infinity).accessibilityIdentifier(id + "-value")
                countButton("+", delta: 1)
            }
            Text(footer).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private func countButton(_ title: String, delta: Int) -> some View {
        Button { value += delta } label: { Text(title).font(.system(size: 23)).frame(width: 30, height: 44).background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border)) }
            .buttonStyle(.plain).disabled(!range.contains(value + delta)).opacity(range.contains(value + delta) ? 1 : 0.3)
            .accessibilityLabel((delta < 0 ? "Decrease " : "Increase ") + self.title).accessibilityIdentifier(id + (delta < 0 ? "-minus" : "-plus"))
    }
}

struct WakeChoiceSetting: View {
    let title: String
    @Binding var value: Int
    let choices: [Int]
    let id: String
    let theme: AlarmTheme
    var suffix = " s"
    var footer: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 3) {
                ForEach(choices, id: \.self) { n in Button { value = n } label: {
                    Text("\(n)\(suffix)").font(.system(size: choices.count > 4 ? 10 : 12)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44).background(n == value ? theme.accent2 : theme.field, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(n == value ? theme.onAccent : theme.text)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(n == value ? theme.accent2 : theme.border))
                }.buttonStyle(.plain).accessibilityAddTraits(n == value ? .isSelected : []).accessibilityIdentifier("\(id)-\(n)") }
            }
            if let footer { Text(footer).font(.system(size: 11)).foregroundStyle(theme.muted) }
        }
    }
}

private struct WakePracticeView: View {
    let test: WakeTest
    let settings: AlarmSettings
    let theme: AlarmTheme
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: TimedWakeChallenge
    init(test: WakeTest, settings: AlarmSettings, theme: AlarmTheme) {
        self.test = test; self.settings = settings; self.theme = theme
        _challenge = State(initialValue: test.practice(settings))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(test.name + " practice").font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Exit practice").accessibilityIdentifier("exitPractice")
            }.padding(.horizontal, 20).padding(.top, 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(challenge.complete ? "Practice complete" : "\(challenge.secondsRemaining(now: context.date))s").font(.system(size: 15)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).accessibilityIdentifier("practiceCountdown")
            }
            ScrollView {
                VStack(spacing: 18) {
                    if challenge.complete {
                        Text("Well done!").font(.system(size: 28, weight: .light)).padding(.top, 30)
                        Button("Try again") { challenge = test.practice(settings) }.buttonStyle(AccentButtonStyle(theme: theme)).accessibilityIdentifier("retryPractice")
                    } else {
                        WakeChallengeContent(challenge: challenge, theme: theme, nativeMath: settings.nativeMathKeyboard == true,
                            submitCode: { challenge.submit(code: $0) }, submitDigits: { challenge.submit(digits: $0) },
                            place: { _ = challenge.placePiece($0) }, mine: { _ = challenge.mineAction(cell: $0, flag: $1, chord: $2) },
                            sudoku: { _ = challenge.sudokuAction(cell: $0, digit: $1) })
                    }
                }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(theme.text).background(theme.background).preferredColorScheme(theme.isLight ? .light : .dark)
            .interactiveDismissDisabled().accessibilityIdentifier("practiceTest")
            .task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)); if Task.isCancelled { return }; if let deadline = challenge.deadline, Date() >= deadline { _ = challenge.expireIfNeeded() } } }
    }
}
