import SwiftUI
import UIKit

struct AlarmNavigationSwipe: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let action: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        recognizer.direction = direction
    }
    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                // Never turn a wheel adjustment or control interaction into navigation.
                if current is UIPickerView || current is UIDatePicker || current is UIControl || current is UITextView { return false }
                if let scroll = current as? UIScrollView,
                   scroll.contentOffset.y + scroll.adjustedContentInset.top > 2 { return false }
                if current === gestureRecognizer.view { break }
                view = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
