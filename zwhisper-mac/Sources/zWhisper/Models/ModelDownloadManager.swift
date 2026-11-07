import FluidAudio
import Foundation
import WhisperKit

/// One download progress sample: completion fraction plus bytes so far (for speed).
struct DownloadUpdate: Sendable {
    var fraction: Double
    var bytes: Int64
}

/// Where FluidAudio keeps the NVIDIA models: its own default cache under
/// Application Support/FluidAudio/Models. Vocabulary boosting reads the CTC
/// tokenizer from that default location, so a custom root would break it.
enum FluidModelStore {
    static let parakeetVersion: AsrModelVersion = .ultra
    static let nemotronSubdirectory = "multilingual/1120ms"

    static var parakeetFolder: URL { AsrModels.defaultCacheDirectory(for: parakeetVersion) }
    static var ctcFolder: URL { CtcModels.defaultCacheDirectory(for: .ctc110m) }
    static var nemotronRepoFolder: URL { MLModelConfigurationUtils.defaultModelsDirectory(for: .nemotronMultilingual) }
    static var nemotronFolder: URL { nemotronRepoFolder.appendingPathComponent(nemotronSubdirectory, isDirectory: true) }

    /// Approximate download sizes, for transfer speed (FluidAudio reports fractions).
    static let parakeetBytes: Int64 = 632_000_000
    static let ctcBytes: Int64 = 106_000_000
    static let nemotronBytes: Int64 = 664_000_000

    static var isParakeetInstalled: Bool {
        AsrModels.modelsExist(at: parakeetFolder, version: parakeetVersion) && CtcModels.modelsExist(at: ctcFolder)
    }

    static var isNemotronInstalled: Bool {
        let files = [
            "metadata.json", "tokenizer.json",
            "encoder.mlmodelc/weights/weight.bin", "decoder_joint.mlmodelc/weights/weight.bin",
        ]
        return files.allSatisfy {
            FileManager.default.fileExists(atPath: nemotronFolder.appendingPathComponent($0).path(percentEncoded: false))
        }
    }

    static func downloadParakeet(progress: @escaping @Sendable (DownloadUpdate) -> Void) async throws {
        ModelPins.installFluidRevisions
        let total = Double(parakeetBytes + ctcBytes)
        let share = Double(parakeetBytes) / total
        try await AsrModels.download(version: parakeetVersion) { update in
            let fraction = update.fractionCompleted * share
            progress(DownloadUpdate(fraction: fraction, bytes: Int64(fraction * total)))
        }
        try Task.checkCancellation()
        // The CTC model behind custom-vocabulary boosting (no progress reporting).
        try await CtcModels.download(variant: .ctc110m)
        progress(DownloadUpdate(fraction: 1, bytes: Int64(total)))
    }

    static func downloadNemotron(progress: @escaping @Sendable (DownloadUpdate) -> Void) async throws {
        ModelPins.installFluidRevisions
        let total = Double(nemotronBytes)
        try await ModelHub.download(
            .nemotronMultilingual,
            subdirectory: nemotronSubdirectory,
            to: nemotronRepoFolder,
            progressHandler: { update in
                progress(DownloadUpdate(fraction: update.fractionCompleted, bytes: Int64(update.fractionCompleted * total)))
            },
            shouldSkip: { $0.contains(".mlpackage") }
        )
    }

    /// Hugging Face tree listings whose files make up each download.
    static func repoTreeURLs(for family: LocalModelFamily) -> [URL] {
        switch family {
        case .whisper:
            return []
        case .parakeet:
            return [
                URL(string: "https://huggingface.co/api/models/\(Repo.parakeetUltra.remotePath)/tree/main?recursive=true")!,
                URL(string: "https://huggingface.co/api/models/\(Repo.parakeetCtc110m.remotePath)/tree/main?recursive=true")!,
            ]
        case .nemotron:
            return [URL(string: "https://huggingface.co/api/models/\(Repo.nemotronMultilingual.remotePath)/tree/main/\(nemotronSubdirectory)?recursive=true")!]
        }
    }
}

/// Architecture §3.8: downloads, locates and deletes every local catalog row
/// (WhisperKit variants and the FluidAudio NVIDIA models), with progress.
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
        try await download(variant: Self.defaultModelName) { progress($0.fraction) }
    }

    static let whisperRepo = "argmaxinc/whisperkit-coreml"

    /// Downloads any local catalog row from its pinned commit, then checks
    /// every file against the hashes in model-pins.json (ModelPins); a model
    /// that doesn't match is deleted and never loaded. Idempotent: WhisperKit's
    /// hub client and FluidAudio both skip files already on disk. For Whisper,
    /// token "" forces anonymous access: the repo is public, and a stale user
    /// token in ~/.cache/huggingface/token otherwise fails with 401.
    func download(variant: String, progress: @escaping @Sendable (DownloadUpdate) -> Void) async throws -> URL {
        switch LocalModelFamily(id: variant) {
        case .parakeet:
            try await FluidModelStore.downloadParakeet(progress: progress)
        case .nemotron:
            try await FluidModelStore.downloadNemotron(progress: progress)
        case .whisper:
            Self.migrateLegacyModelFolderIfNeeded()
            let pin = try ModelPins.pin(for: variant, repo: Self.whisperRepo)
            let hub = HubApiWrapper(downloadBase: Self.downloadBase, hfToken: "", endpoint: Constants.defaultRemoteEndpoint)
            _ = try await hub.snapshot(from: HubApiWrapper.Repo(id: Self.whisperRepo), revision: pin.revision, matching: ["\(pin.prefix)*"]) { download in
                progress(DownloadUpdate(fraction: download.fractionCompleted, bytes: download.completedUnitCount))
            }
            try await ensureTokenizer(inModelFolder: Self.modelFolder(forVariant: variant), forVariant: variant)
        }
        try Task.checkCancellation()
        try ModelPins.verifyDownload(variant)
        return Self.modelFolder(forVariant: variant)
    }

    /// WhisperKit's tokenizer download doesn't accept a token override (it
    /// reads ~/.cache/huggingface/token), so fetch the tokenizer files
    /// anonymously into the model folder — its local search finds them there
    /// and never touches the hub. Fetched from the pinned commit only.
    private func ensureTokenizer(inModelFolder folder: URL, forVariant variant: String) async throws {
        let files = ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json"]
        let repo = Self.tokenizerRepoName(forVariant: variant)
        let revision = try ModelPins.pin(for: variant, repo: repo).revision
        for file in files {
            let destination = folder.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            // tokenizer.json is required; the rest are best-effort config files.
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try data.write(to: destination)
            } else if file == "tokenizer.json" {
                throw TranscriptionError.modelNotLoaded
            }
        }
    }

    static func tokenizerRepoName(forVariant variant: String) -> String {
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

    /// The variant's real download size from the model repo; nil on any failure,
    /// which leaves the catalog's fallback label in place.
    static func fetchSizeLabel(forVariant variant: String) async -> String? {
        let family = LocalModelFamily(id: variant)
        let urls = family == .whisper
            ? [URL(string: "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-\(variant)?recursive=true")!]
            : FluidModelStore.repoTreeURLs(for: family)
        var total: Int64 = 0
        for url in urls {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let bytes = byteCount(fromRepoTree: data)
            else { return nil }
            total += bytes
        }
        return sizeLabel(bytes: total)
    }

    static func sizeLabel(fromRepoTree data: Data) -> String? {
        byteCount(fromRepoTree: data).flatMap(sizeLabel(bytes:))
    }

    /// Compiled CoreML only: FluidAudio skips the repos' .mlpackage sources.
    private static func byteCount(fromRepoTree data: Data) -> Int64? {
        struct Node: Decodable {
            let type: String
            let path: String?
            let size: Int64?
        }
        guard let nodes = try? JSONDecoder().decode([Node].self, from: data) else { return nil }
        let bytes = nodes
            .filter { $0.type == "file" && !($0.path ?? "").contains(".mlpackage") }
            .reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        return bytes > 0 ? bytes : nil
    }

    private static func sizeLabel(bytes: Int64) -> String? {
        guard bytes > 0 else { return nil }
        let mb = Double(bytes) / 1_000_000
        return mb >= 1000 ? String(format: "%.1f GB", mb / 1000) : "\(Int(mb.rounded())) MB"
    }

    /// Local model folder for a catalog row (Whisper: under downloadBase/models/…).
    static func modelFolder(forVariant variant: String) -> URL {
        switch LocalModelFamily(id: variant) {
        case .parakeet: FluidModelStore.parakeetFolder
        case .nemotron: FluidModelStore.nemotronFolder
        case .whisper:
            downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)", isDirectory: true)
        }
    }

    static func isDownloaded(variant: String) -> Bool {
        switch LocalModelFamily(id: variant) {
        case .parakeet: return FluidModelStore.isParakeetInstalled
        case .nemotron: return FluidModelStore.isNemotronInstalled
        case .whisper:
            migrateLegacyModelFolderIfNeeded()
            return FileManager.default.fileExists(
                atPath: modelFolder(forVariant: variant)
                    .appendingPathComponent("TextDecoder.mlmodelc").path(percentEncoded: false)
            )
        }
    }

    static func delete(variant: String) throws {
        let fm = FileManager.default
        switch LocalModelFamily(id: variant) {
        case .parakeet:
            try fm.removeItem(at: FluidModelStore.parakeetFolder)
            try? fm.removeItem(at: FluidModelStore.ctcFolder)
        case .nemotron:
            try fm.removeItem(at: FluidModelStore.nemotronFolder)
        case .whisper:
            migrateLegacyModelFolderIfNeeded()
            try fm.removeItem(at: modelFolder(forVariant: variant))
        }
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
