import UIKit

@MainActor enum AlarmHaptics {
    private static let key = UIImpactFeedbackGenerator(style: .light)
    private static let threshold = UIImpactFeedbackGenerator(style: .medium)
    private static let result = UINotificationFeedbackGenerator()
    static func keypress() { key.impactOccurred(intensity: 0.55); key.prepare() }
    static func deleteThreshold() { threshold.impactOccurred(); threshold.prepare() }
    static func deleted() { result.notificationOccurred(.success) }
}
