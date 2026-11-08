import Foundation

public struct StateRepository: Sendable {
    public let url: URL
    public var backupURL: URL { url.appendingPathExtension("bak") }
    public init(url: URL) { self.url = url }
    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url)).validated()
    }
    public func save(_ state: SavedState) throws {
        _ = try state.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            // Never replace a corrupt/unsupported file, including during an attempted save.
            _ = try load()
            try Data(contentsOf: url).write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
