import UIKit

@MainActor
enum AppIcon {
    private static let namePrefix = "AppIcon-"
    private static let defaultID = "sunrise"

    static var selectedID: String {
        guard let name = UIApplication.shared.alternateIconName, name.hasPrefix(namePrefix) else {
            return defaultID
        }
        return AlarmTheme.find(String(name.dropFirst(namePrefix.count))).id
    }

    static func previewName(for id: String) -> String {
        (alternateName(for: id) ?? "AppIcon") + "-Preview"
    }

    static func select(_ id: String) async throws {
        let app = UIApplication.shared
        let name = alternateName(for: id)
        if app.alternateIconName != name { try await app.setAlternateIconName(name) }
    }

    private static func alternateName(for id: String) -> String? {
        id == defaultID ? nil : namePrefix + id
    }
}
