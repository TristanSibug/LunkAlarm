import SwiftUI
import UIKit

/// A horizontal gesture alongside the vertical list scroll. A partial swipe
/// reveals Delete; a long swipe crosses a tactile threshold and commits on lift.
struct SwipeDeleteAlarmRow<Content: View>: View {
    var enabled: Bool
    var name: String
    var delete: () -> Bool
    var onSwipe: () -> Void = {}
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
        .gesture(AlarmRowPan(enabled: enabled && !deleting, changed: { translation in
            onSwipe()
            if dragStart == nil { dragStart = offset }
            offset = min(0, max(-width, (dragStart ?? 0) + translation))
            let next = -offset >= threshold
            if next && !armed { AlarmHaptics.deleteThreshold() }
            armed = next
        }, ended: { translation, velocity, cancelled in
            guard dragStart != nil else { return }
            onSwipe()
            dragStart = nil
            let fastFullSwipe = -offset > width * 0.35 && translation + velocity * 0.16 < -width * 0.85
            if !cancelled && (armed || fastFullSwipe) { performDelete() }
            else { withAnimation(animation) { offset = -offset > reveal * 0.5 ? -reveal : 0; armed = false } }
        }))
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

// A horizontal-only native pan cancels the card's tap/control tracking before
// release. Vertical drags stay with the list's scrolling/navigation recognizers.
private struct AlarmRowPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat, Bool) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        pan.isEnabled = enabled
        return pan
    }
    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) { pan.isEnabled = enabled }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed: changed(translation)
        case .ended: ended(translation, pan.velocity(in: pan.view).x, false)
        case .cancelled, .failed: ended(translation, 0, true)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.3
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
