import Foundation

enum ModeProcessingError: Error, Equatable {
    /// Apple Intelligence off and no cloud key configured (§8 actionable card).
    case intelligenceUnavailable
}

/// Architecture §6: exactly two implementations. Streams yield cumulative text
/// (the teleprompter replaces, never appends).
protocol ModeBackend: Sendable {
    func stream(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error>
}

/// Architecture §3.4 contract. Voice Note short-circuits before either backend
/// (§7 identity transform, zero latency).
protocol ModeProcessorProtocol: Sendable {
    func process(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error>
}

/// Backend choice (architecture §6): Foundation Models when
/// `SystemLanguageModel.default.availability` is available, otherwise a
/// configured cloud provider, otherwise an actionable failure — never a spinner.
struct ModeProcessor: ModeProcessorProtocol {
    let foundationBackend: (any ModeBackend)?
    let cloudBackend: (any ModeBackend)?

    init(foundationBackend: (any ModeBackend)?, cloudBackend: (any ModeBackend)?) {
        self.foundationBackend = foundationBackend
        self.cloudBackend = cloudBackend
    }

    func process(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error> {
        if mode.isIdentity {
            return AsyncThrowingStream { continuation in
                continuation.yield(raw)
                continuation.finish()
            }
        }
        guard let backend = foundationBackend ?? cloudBackend else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ModeProcessingError.intelligenceUnavailable)
            }
        }
        return backend.stream(raw: raw, mode: mode, context: context)
    }
}
