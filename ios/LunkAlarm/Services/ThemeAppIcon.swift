import OSLog
import UIKit

@MainActor
final class ThemeAppIcon {
    private let logger = Logger(subsystem: "online.reeeserve.LunkAlarm", category: "AppIcon")
    private var pendingTheme: String?
    private var updating = false

    func sync(with themeID: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }

        pendingTheme = themeID
        guard app.applicationState == .active, !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            while app.applicationState == .active, let theme = pendingTheme {
                pendingTheme = nil
                let name = theme == "sunrise" ? nil : "AppIcon-\(theme)"
                guard app.alternateIconName != name else { continue }
                do {
                    try await app.setAlternateIconName(name)
                } catch {
                    logger.error("Could not change the app icon: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
