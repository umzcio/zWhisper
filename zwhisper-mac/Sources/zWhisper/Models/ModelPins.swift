import CryptoKit
import FluidAudio
import Foundation

/// One upstream source of a local model: a repo at an exact commit, and the
/// SHA-256 of every file it puts in one local folder (scripts/pin-models.sh).
struct ModelPin: Decodable, Sendable, Equatable {
    /// Hugging Face repo, e.g. "argmaxinc/whisperkit-coreml".
    let repo: String
    /// Full commit SHA the app downloads from (never a branch).
    let revision: String
    /// Local folder the files land in: whisper, parakeet, ctc or nemotron.
    let folder: String
    /// Repo path that maps to that folder ("" for the repo root).
    let prefix: String
    /// Folder-relative path → lowercase hex SHA-256.
    let files: [String: String]
}

enum ModelIntegrityError: LocalizedError, Equatable {
    case unpinned(String)
    case mismatch(file: String)
    case unexpected(file: String)

    var errorDescription: String? {
        switch self {
        case .unpinned(let id):
            "zWhisper has no verified copy of \(id) on record."
        case .mismatch(let file), .unexpected(let file):
            "The downloaded model didn't match the version zWhisper verified (\(file)), so it was removed."
        }
    }
}

/// Supply-chain pin for every local catalog model: downloads come from the
/// pinned commits, and nothing is loaded until each file on disk matches the
/// hash shipped in the app. A changed or compromised upstream repo therefore
/// can't swap the model (or the tokenizer that maps its output to text).
enum ModelPins {
    /// Marker written after a folder verifies; holds a digest of its pins.
    static let markerName = ".zwhisper-verified"

    static let all: [String: [ModelPin]] = {
        struct Manifest: Decodable { let models: [String: [ModelPin]] }
        guard let url = Bundle.main.url(forResource: "model-pins", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [:] }
        return manifest.models
    }()

    static func pins(for id: String) throws -> [ModelPin] {
        guard let pins = all[id], !pins.isEmpty else { throw ModelIntegrityError.unpinned(id) }
        return pins
    }

    static func pin(for id: String, repo: String) throws -> ModelPin {
        guard let pin = try pins(for: id).first(where: { $0.repo == repo }) else {
            throw ModelIntegrityError.unpinned(id)
        }
        return pin
    }

    /// FluidAudio downloads read their revision from ModelRegistry; set once.
    static let installFluidRevisions: Void = {
        var overrides: [String: String] = [:]
        for pin in all.values.joined() where pin.repo.hasPrefix("FluidInference/") {
            overrides[pin.repo] = pin.revision
        }
        ModelRegistry.revisionOverrides = overrides
    }()

    static func folderURL(_ folder: String, forVariant id: String) -> URL? {
        switch folder {
        case "whisper": ModelDownloadManager.modelFolder(forVariant: id)
        case "parakeet": FluidModelStore.parakeetFolder
        case "ctc": FluidModelStore.ctcFolder
        case "nemotron": FluidModelStore.nemotronFolder
        default: nil
        }
    }

    /// Expected files per local folder for a catalog row.
    static func expectations(for id: String) throws -> [(folder: URL, files: [String: String])] {
        var byFolder: [String: [String: String]] = [:]
        for pin in try pins(for: id) {
            byFolder[pin.folder, default: [:]].merge(pin.files) { $1 }
        }
        return try byFolder.keys.sorted().map { name in
            guard let url = folderURL(name, forVariant: id) else { throw ModelIntegrityError.unpinned(id) }
            return (url, byFolder[name]!)
        }
    }

    /// Hashes every folder of a freshly downloaded model. A folder that fails
    /// is deleted (it is untrusted) and the error is rethrown.
    static func verifyDownload(_ id: String) throws {
        for (folder, files) in try expectations(for: id) {
            do {
                try verify(folder: folder, expected: files)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
    }

    /// Before loading: a folder already verified against these pins is
    /// trusted; one from an older build (no marker) is hashed once now.
    static func verifyInstalled(_ id: String) throws {
        for (folder, files) in try expectations(for: id) where !hasMarker(folder: folder, expected: files) {
            do {
                try verify(folder: folder, expected: files)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
    }

    /// Every regular file in `folder` (hidden bookkeeping aside) must be pinned
    /// and match its hash. Pinned files that weren't downloaded are fine — the
    /// loaders check for the ones they need; anything they read is verified.
    static func verify(folder: URL, expected: [String: String]) throws {
        let files = try regularFiles(in: folder)
        for file in files {
            guard let hash = expected[file.relative] else { throw ModelIntegrityError.unexpected(file: file.relative) }
            guard try sha256(of: file.url) == hash.lowercased() else { throw ModelIntegrityError.mismatch(file: file.relative) }
        }
        try Data(marker(expected: expected, files: files).utf8)
            .write(to: folder.appendingPathComponent(markerName), options: .atomic)
    }

    /// The marker stands only while the pins and every file's size, mtime and
    /// inode are unchanged: an added, replaced or edited file re-hashes the folder.
    static func hasMarker(folder: URL, expected: [String: String]) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
              let files = try? regularFiles(in: folder)
        else { return false }
        return String(decoding: data, as: UTF8.self) == marker(expected: expected, files: files)
    }

    private struct LocalFile {
        let relative: String
        let url: URL
        let stamp: String
    }

    /// Non-hidden regular files under `folder`; any symlink is refused (it
    /// could point anywhere, and models never ship one).
    private static func regularFiles(in folder: URL) throws -> [LocalFile] {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [
            .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey,
        ]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw ModelIntegrityError.unexpected(file: folder.lastPathComponent)
        }
        let rootPath = root.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var files: [LocalFile] = []
        for case let url as URL in walker {
            // The enumerator may report /private/var for /var: resolve the
            // parent (never the item, so a link is still seen as a link).
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path(percentEncoded: false)
            let path = (parent.hasSuffix("/") ? parent : parent + "/") + url.lastPathComponent
            guard path.hasPrefix(prefix) else { throw ModelIntegrityError.unexpected(file: url.lastPathComponent) }
            let relative = String(path.dropFirst(prefix.count))
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw ModelIntegrityError.unexpected(file: relative) }
            if values.isDirectory == true { continue }
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let inode = values.fileResourceIdentifier.map { String(describing: $0) } ?? ""
            files.append(LocalFile(relative: relative, url: url, stamp: "\(values.fileSize ?? -1):\(mtime):\(inode)"))
        }
        return files.sorted { $0.relative < $1.relative }
    }

    private static func marker(expected: [String: String], files: [LocalFile]) -> String {
        let listing = files.map { "\($0.relative)\t\($0.stamp)\n" }.joined()
        return markerDigest(expected) + "\n" + hex(SHA256.hash(data: Data(listing.utf8)))
    }

    /// Digest of the pins a folder was verified against: new pins re-verify.
    static func markerDigest(_ expected: [String: String]) -> String {
        let canonical = expected.keys.sorted().map { "\($0)\t\(expected[$0]!)\n" }.joined()
        return hex(SHA256.hash(data: Data(canonical.utf8)))
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
