import SwiftUI

/// A horizontal gesture alongside the vertical list scroll. A partial swipe
/// reveals Delete; a long swipe crosses a tactile threshold and commits on lift.
struct SwipeDeleteAlarmRow<Content: View>: View {
    var enabled: Bool
    var name: String
    var delete: () -> Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 320
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var armed = false
    @State private var deleting = false
    private let reveal: CGFloat = 82
    private var threshold: CGFloat { width * 0.65 }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button { performDelete() } label: {
                    Image(systemName: "trash.fill").font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white).frame(width: 52, height: 52)
                        .background(.red, in: Circle()).scaleEffect(armed ? 1.12 : 1)
                        .frame(width: min(-offset, width), alignment: .center)
                }.buttonStyle(.plain).accessibilityLabel("Delete \(name)")
                    .accessibilityIdentifier("swipeDeleteAlarm")
            }
            content.offset(x: offset)
                .allowsHitTesting(!deleting && offset == 0)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard enabled, !deleting else { return }
                if dragStart == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                    dragStart = offset
                }
                offset = min(0, max(-width, (dragStart ?? 0) + value.translation.width))
                let next = -offset >= threshold
                if next && !armed { AlarmHaptics.deleteThreshold() }
                armed = next
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                // A fast, deliberate swipe also commits; a short flick only reveals.
                let fastFullSwipe = -offset > width * 0.35 && value.predictedEndTranslation.width < -width * 0.85
                if armed || fastFullSwipe { performDelete() }
                else { withAnimation(animation) { offset = -offset > reveal * 0.5 ? -reveal : 0; armed = false } }
            })
        .accessibilityAction(named: "Delete") { if enabled { performDelete() } }
        .onChange(of: enabled) { _, value in if !value && !deleting { withAnimation(animation) { offset = 0; armed = false } } }
    }
    private func performDelete() {
        guard enabled, !deleting else { return }
        deleting = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = -width - 24 }
        completion: {
            if delete() { AlarmHaptics.deleted() }
            else { withAnimation(animation) { offset = 0 } }
            armed = false; deleting = false
        }
    }
}
