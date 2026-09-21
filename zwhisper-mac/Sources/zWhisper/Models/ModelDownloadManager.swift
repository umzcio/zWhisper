import Foundation
import WhisperKit

/// Minimal M3 slice of architecture §3.8: downloads the pinned default model on
/// first launch (idempotent — WhisperKit skips an existing download) with
/// progress. The full catalog (filters, starring, 2-concurrent queue) is M6.
struct ModelDownloadManager {
    /// §4 budget guidance: `large-v3-v20240930_626MB` on M2+/16GB, `small` on
    /// baseline M1/8GB.
    static var defaultModelName: String {
        if isBaselineM1 || physicalMemoryGB < 16 {
            return "small"
        }
        return "large-v3-v20240930_626MB"
    }

    func ensureDefaultModel(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await download(variant: Self.defaultModelName) { progress($0.fractionCompleted) }
    }

    /// Downloads any catalog variant (idempotent — WhisperKit skips an existing
    /// download). token "" forces anonymous access: the repo is public, and a
    /// stale user token in ~/.cache/huggingface/token otherwise fails with 401.
    func download(variant: String, progress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        Self.migrateLegacyModelFolderIfNeeded()
        let folder = try await WhisperKit.download(variant: variant, downloadBase: Self.downloadBase, from: "argmaxinc/whisperkit-coreml", token: "") { download in
            progress(download)
        }
        try await ensureTokenizer(inModelFolder: folder, forVariant: variant)
        return folder
    }

    /// WhisperKit's tokenizer download doesn't accept a token override (it
    /// reads ~/.cache/huggingface/token), so fetch the tokenizer files
    /// anonymously into the model folder — its local search finds them there
    /// and never touches the hub.
    private func ensureTokenizer(inModelFolder folder: URL, forVariant variant: String) async throws {
        let files = ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json"]
        let repo = Self.tokenizerRepoName(forVariant: variant)
        for file in files {
            let destination = folder.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            // tokenizer.json is required; the rest are best-effort config files.
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try data.write(to: destination)
            } else if file == "tokenizer.json" {
                throw TranscriptionError.modelNotLoaded
            }
        }
    }

    private static func tokenizerRepoName(forVariant variant: String) -> String {
        if variant.hasPrefix("tiny") { return "openai/whisper-tiny" }
        if variant.hasPrefix("small") { return "openai/whisper-small" }
        if variant.hasPrefix("medium") { return "openai/whisper-medium" }
        if variant.hasPrefix("base") { return "openai/whisper-base" }
        return "openai/whisper-large-v3"
    }

    /// Model storage root. Moved out of ~/Documents in 1.0.7: Documents is
    /// TCC-protected, so every model-folder check prompted "access your
    /// Documents folder". Application Support prompts for nothing.
    static var downloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zWhisper/huggingface", isDirectory: true)
    }

    /// One-time move of pre-1.0.7 models out of ~/Documents. Idempotent;
    /// same-volume rename, no re-download.
    static func migrateLegacyModelFolderIfNeeded() {
        let fm = FileManager.default
        let legacy = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models", isDirectory: true)
        let current = downloadBase.appendingPathComponent("models", isDirectory: true)
        guard !fm.fileExists(atPath: current.path(percentEncoded: false)),
              fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }
        try? fm.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        try? fm.moveItem(at: legacy, to: current)
    }

    /// Local model folder for a variant (under downloadBase/models/…).
    static func modelFolder(forVariant variant: String) -> URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)", isDirectory: true)
    }

    static func isDownloaded(variant: String) -> Bool {
        migrateLegacyModelFolderIfNeeded()
        return FileManager.default.fileExists(
            atPath: modelFolder(forVariant: variant)
                .appendingPathComponent("TextDecoder.mlmodelc").path(percentEncoded: false)
        )
    }

    static func delete(variant: String) throws {
        migrateLegacyModelFolderIfNeeded()
        try FileManager.default.removeItem(at: modelFolder(forVariant: variant))
    }

    private static var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    private static var isBaselineM1: Bool {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer).contains("M1")
    }
}
