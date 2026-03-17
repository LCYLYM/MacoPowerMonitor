import Foundation
import OSLog

struct PowerHistoryStore {
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "history-store")
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppPaths.historyFileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [PowerSnapshot] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([PowerSnapshot].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ history: [PowerSnapshot]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
