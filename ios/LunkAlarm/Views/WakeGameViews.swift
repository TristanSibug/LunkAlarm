import SwiftUI

struct MineGameView: View {
    let board: MineBoard
    let theme: AlarmTheme
    var action: (Int, Bool, Bool) -> Void
    @State private var flagMode = false
    var body: some View {
        VStack(spacing: 14) {
            Text("Minesweeper").font(.system(size: 20, weight: .semibold))
            Text("Reveal safe squares and flag all mines.\nTap to reveal · Hold a hidden square to flag.\nHold a number to reveal adjacent squares.")
                .font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            HStack {
                Text("\(board.flags.count)/\(board.mines.count) flags").font(.system(size: 13)).foregroundStyle(theme.muted).accessibilityIdentifier("mineProgress")
                Spacer()
                Button(flagMode ? "⚑ Flag" : "Reveal") { flagMode.toggle() }.buttonStyle(ChipStyle(theme: theme)).accessibilityIdentifier("mineMode")
            }
            VStack(spacing: board.size == 9 ? 3 : 5) {
                ForEach(0..<board.size, id: \.self) { row in HStack(spacing: board.size == 9 ? 3 : 5) {
                    ForEach(0..<board.size, id: \.self) { column in mineCell(row * board.size + column) }
                } }
            }.accessibilityIdentifier("mineBoard")
        }.frame(maxWidth: 400)
    }
    private func mineCell(_ cell: Int) -> some View {
        let shown = board.revealed.contains(cell), flag = board.flags.contains(cell), number = board.number(cell)
        return Text(flag ? "⚑" : shown && number > 0 ? "\(number)" : "")
            .font(.system(size: board.size == 9 ? 16 : 21, weight: .semibold)).foregroundStyle(flag ? theme.accent2 : theme.text)
            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
            .background(shown ? theme.field : theme.accent2.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(shown ? theme.border : theme.accent2.opacity(0.65)))
            .contentShape(Rectangle())
            .onTapGesture { if !shown { AlarmHaptics.keypress(); action(cell, flagMode, false) } }
            .onLongPressGesture(minimumDuration: 0.45) { AlarmHaptics.keypress(); action(cell, !shown, shown) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Row \(cell / board.size + 1), column \(cell % board.size + 1)")
            .accessibilityValue(flag ? "Flagged" : shown ? "\(number) adjacent mines" : "Hidden")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(cell, flagMode, false) }
            .accessibilityAction(named: shown ? "Reveal adjacent squares" : "Toggle flag") { action(cell, !shown, shown) }
            .accessibilityIdentifier("mine-cell-\(cell)")
    }
}

struct SudokuGameView: View {
    let board: SudokuBoard
    let theme: AlarmTheme
    var action: (Int, Int) -> Void
    @State private var selected: Int
    init(board: SudokuBoard, theme: AlarmTheme, action: @escaping (Int, Int) -> Void) {
        self.board = board; self.theme = theme; self.action = action
        _selected = State(initialValue: board.givens.firstIndex(of: 0) ?? 0)
    }
    var body: some View {
        VStack(spacing: 14) {
            Text("Sudoku").font(.system(size: 20, weight: .semibold))
            Text("Use 1–\(board.size) once in each row, column and box.").font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            Text("\(board.filled)/\(board.blanks) filled").font(.system(size: 13)).foregroundStyle(theme.muted).accessibilityIdentifier("sudokuProgress")
            VStack(spacing: 0) {
                ForEach(0..<board.size, id: \.self) { row in HStack(spacing: 0) {
                    ForEach(0..<board.size, id: \.self) { column in sudokuCell(row * board.size + column) }
                } }
            }.overlay(Rectangle().stroke(theme.text.opacity(0.6), lineWidth: 1.5)).accessibilityIdentifier("sudokuBoard")
            HStack(spacing: 6) {
                ForEach(1...board.size, id: \.self) { digit in Button { AlarmHaptics.keypress(); action(selected, digit) } label: {
                    Text("\(digit)").font(.system(size: 22)).frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
                }.buttonStyle(.plain).accessibilityLabel("Enter \(digit)").accessibilityIdentifier("sudoku-digit-\(digit)") }
            }
            Button("Erase") { AlarmHaptics.keypress(); action(selected, 0) }.buttonStyle(ChipStyle(theme: theme)).accessibilityIdentifier("sudokuErase")
        }.frame(maxWidth: 400)
    }
    private func sudokuCell(_ cell: Int) -> some View {
        let given = board.givens[cell] != 0, row = cell / board.size, col = cell % board.size
        return Button { selected = cell; AlarmHaptics.keypress() } label: {
            Text(board.values[cell] == 0 ? "" : "\(board.values[cell])").font(.system(size: board.size == 6 ? 20 : 24, weight: given ? .semibold : .regular))
                .foregroundStyle(board.conflict(cell) ? theme.accent2 : given ? theme.text : theme.accent)
                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                .background(selected == cell ? theme.accent2.opacity(0.2) : given ? theme.text.opacity(0.05) : theme.field)
                .overlay(alignment: .top) { Rectangle().fill(theme.text.opacity(0.45)).frame(height: row % 2 == 0 ? 1.5 : 0.5) }
                .overlay(alignment: .leading) { Rectangle().fill(theme.text.opacity(0.45)).frame(width: col % (board.size / 2) == 0 ? 1.5 : 0.5) }
        }.buttonStyle(.plain).disabled(given).accessibilityLabel("Row \(row + 1), column \(col + 1)")
            .accessibilityValue((board.values[cell] == 0 ? "Empty" : "\(board.values[cell])") + (given ? ", fixed" : "") + (board.conflict(cell) ? ", conflict" : ""))
            .accessibilityAddTraits(selected == cell ? .isSelected : []).accessibilityIdentifier("sudoku-cell-\(cell)")
    }
}

private struct PuzzleShape: Shape {
    let piece: PuzzlePiece
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ p: PuzzlePoint) -> CGPoint { CGPoint(x: CGFloat(p.x - piece.x) * rect.width + rect.minX, y: CGFloat(p.y - piece.y) * rect.height + rect.minY) }
        path.move(to: point(piece.edges[0].from))
        for edge in piece.edges {
            let a = point(edge.from), b = point(edge.to), dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
            let normal = CGVector(dx: dy / length * min(rect.width, rect.height) * edge.tab, dy: -dx / length * min(rect.width, rect.height) * edge.tab)
            func p(_ t: CGFloat, _ bump: CGFloat = 0) -> CGPoint { CGPoint(x: a.x + dx * t + normal.dx * bump, y: a.y + dy * t + normal.dy * bump) }
            if edge.tab != 0 {
                let c = edge.center
                path.addLine(to: p(c - 0.12))
                path.addCurve(to: p(c, 1), control1: p(c - 0.04), control2: p(c - 0.19, 1))
                path.addCurve(to: p(c + 0.12), control1: p(c + 0.19, 1), control2: p(c + 0.04))
            }
            path.addLine(to: b)
        }
        path.closeSubpath(); return path
    }
}
private struct PuzzleTrayFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct JigsawGameView: View {
    let challenge: TimedWakeChallenge
    let theme: AlarmTheme
    var place: (Int) -> Void
    @State private var selected: Int?
    @State private var dragged: Int?
    @State private var location = CGPoint.zero
    @State private var grab = CGPoint.zero
    @State private var frames: [Int: CGRect] = [:]
    @State private var stageWidth: CGFloat = 320
    private var puzzle: Jigsaw { Jigsaw.create(count: challenge.games.puzzlePieces, seed: challenge.puzzleSeed) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(challenge.placedPieces.count)/\(challenge.games.puzzlePieces) placed").font(.system(size: 20)).accessibilityIdentifier("puzzleProgress")
            Text("Drag pieces onto the board, or tap a piece then its position.").font(.system(size: 12)).foregroundStyle(theme.muted)
            GeometryReader { geometry in stage(width: geometry.size.width) }
                .frame(height: stageWidth * 0.58 + 196)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        }.frame(maxWidth: 400)
    }
    private func stage(width: CGFloat) -> some View {
        let puzzle = self.puzzle, cellW = width / CGFloat(puzzle.columns), cellH = width * 0.58 / 2, scale = 0.43
        return VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(theme.field)
                ForEach(puzzle.pieces) { piece in
                    if challenge.placedPieces.contains(piece.id) {
                        PuzzleShape(piece: piece).fill(theme.accent).frame(width: cellW, height: cellH).offset(x: CGFloat(piece.x) * cellW, y: CGFloat(piece.y) * cellH).accessibilityHidden(true)
                    }
                }
                VStack(spacing: 0) { ForEach(0..<2) { row in HStack(spacing: 0) {
                    ForEach(0..<puzzle.columns, id: \.self) { column in
                        let id = row * puzzle.columns + column
                        Button { if selected == id { place(id); selected = nil; AlarmHaptics.keypress() } } label: {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Puzzle position \(id + 1)").accessibilityIdentifier("puzzle-slot-\(id)")
                    }
                } } }
            }.frame(height: width * 0.58).accessibilityIdentifier("jigsawBoard")
            VStack(spacing: 8) {
                ForEach(0..<2) { row in HStack(spacing: 6) {
                    ForEach(0..<5) { column in
                        let index = row * 5 + column
                        if index < puzzle.order.count { trayPiece(puzzle.pieces[puzzle.order[index]], cellW: cellW, cellH: cellH, scale: scale) }
                        else { Color.clear.frame(maxWidth: .infinity).frame(height: 78).accessibilityHidden(true) }
                    }
                } }
            }.padding(8).background(theme.card, in: RoundedRectangle(cornerRadius: 14))
        }.coordinateSpace(name: "jigsawStage").onPreferenceChange(PuzzleTrayFrames.self) { frames = $0 }
            .overlay(alignment: .topLeading) {
                if let id = dragged {
                    PuzzleShape(piece: puzzle.pieces[id]).fill(theme.accent).overlay(PuzzleShape(piece: puzzle.pieces[id]).stroke(theme.text.opacity(0.7), lineWidth: 1))
                        .frame(width: cellW, height: cellH).offset(x: location.x - grab.x, y: location.y - grab.y).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
    private func trayPiece(_ piece: PuzzlePiece, cellW: CGFloat, cellH: CGFloat, scale: CGFloat) -> some View {
        let placed = challenge.placedPieces.contains(piece.id)
        return ZStack {
            if !placed && dragged != piece.id { PuzzleShape(piece: piece).fill(theme.accent).overlay(PuzzleShape(piece: piece).stroke(theme.text.opacity(0.75), lineWidth: 0.8)).frame(width: cellW * scale, height: cellH * scale) }
        }.frame(maxWidth: .infinity).frame(height: 78).contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == piece.id ? theme.accent : .clear, lineWidth: 1.5))
            .background(GeometryReader { proxy in Color.clear.preference(key: PuzzleTrayFrames.self, value: [piece.id: proxy.frame(in: .named("jigsawStage"))]) })
            .onTapGesture { if !placed { selected = piece.id; AlarmHaptics.keypress() } }
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("jigsawStage")).onChanged { value in
                guard !placed, let frame = frames[piece.id] else { return }
                if dragged == nil {
                    dragged = piece.id; selected = piece.id
                    grab = CGPoint(x: (value.startLocation.x - frame.midX + cellW * scale / 2) / scale, y: (value.startLocation.y - frame.midY + cellH * scale / 2) / scale)
                    AlarmHaptics.keypress()
                }
                location = value.location
            }.onEnded { value in
                guard dragged == piece.id else { return }
                let dropped = CGPoint(x: value.location.x - grab.x, y: value.location.y - grab.y), tolerance = min(cellW, cellH) * 0.4
                if abs(dropped.x - CGFloat(piece.x) * cellW) < tolerance && abs(dropped.y - CGFloat(piece.y) * cellH) < tolerance { place(piece.id); selected = nil; AlarmHaptics.keypress() }
                dragged = nil
            })
            .accessibilityElement(children: .ignore).accessibilityLabel(placed ? "Placed piece" : "Puzzle piece \(piece.id + 1)")
            .accessibilityAddTraits(.isButton).accessibilityAction { if !placed { selected = piece.id } }.accessibilityIdentifier("puzzle-piece-\(piece.id)")
    }
}
