import Foundation

/// JSON file persistence per architecture §7: plain JSON in
/// `~/Library/Application Support/zWhisper/`, atomic writes, 500ms-debounced
/// saves for high-churn stores, all behind a single actor.
actor PersistenceStore {
    nonisolated let directory: URL
    private let debounceInterval: Duration
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingWrites: [URL: Task<Void, Never>] = [:]

    init(directory: URL? = nil, debounceInterval: Duration = .milliseconds(500)) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zWhisper", isDirectory: true)
        self.debounceInterval = debounceInterval
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Returns nil when the file does not exist (first launch).
    func load<T: Decodable>(_ type: T.Type, from file: String) throws -> T? {
        let url = directory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func save<T: Encodable>(_ value: T, to file: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
    }

    /// Debounced save for high-churn stores (§7): coalesces bursts within the
    /// debounce interval into a single write of the latest value.
    func saveDebounced<T: Encodable & Sendable>(_ value: T, to file: String) {
        let url = directory.appendingPathComponent(file)
        pendingWrites[url]?.cancel()
        pendingWrites[url] = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            try? save(value, to: file)
        }
    }

    /// Awaits all pending debounced writes (used at app termination and in tests).
    func flush() async {
        let tasks = pendingWrites
        pendingWrites.removeAll()
        for task in tasks.values {
            await task.value
        }
    }

    func deleteFile(_ relativePath: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath))
    }
}
