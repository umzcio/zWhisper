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
    /// Top-level components the loader can do without (e.g. the CTC repo's
    /// CtcHead.mlmodelc, which FluidAudio never fetches). Each is all or
    /// nothing; every other pinned file must be present.
    let optional: [String]?
}

enum ModelIntegrityError: LocalizedError, Equatable {
    case unpinned(String)
    case mismatch(file: String)
    case unexpected(file: String)
    case incomplete(file: String)

    var errorDescription: String? {
        switch self {
        case .unpinned(let id):
            "zWhisper has no verified copy of \(id) on record."
        case .incomplete(let file):
            "The model download is incomplete (\(file) is missing). Download it again to finish it."
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

    struct Expectation {
        let folder: URL
        let files: [String: String]
        let optional: Set<String>
    }

    /// Expected files per local folder for a catalog row.
    static func expectations(for id: String) throws -> [Expectation] {
        var byFolder: [String: [String: String]] = [:]
        var optional: [String: Set<String>] = [:]
        for pin in try pins(for: id) {
            byFolder[pin.folder, default: [:]].merge(pin.files) { $1 }
            optional[pin.folder, default: []].formUnion(pin.optional ?? [])
        }
        return try byFolder.keys.sorted().map { name in
            guard let url = folderURL(name, forVariant: id) else { throw ModelIntegrityError.unpinned(id) }
            return Expectation(folder: url, files: byFolder[name]!, optional: optional[name] ?? [])
        }
    }

    /// Some pinned file of the model is on disk (a started or older install).
    static func hasPartialInstall(_ id: String) -> Bool {
        guard let expectations = try? expectations(for: id) else { return false }
        return expectations.contains { expectation in
            expectation.files.keys.contains {
                FileManager.default.fileExists(atPath: expectation.folder.appendingPathComponent($0).path(percentEncoded: false))
            }
        }
    }

    /// Every file the loader needs is on disk (existence only, no hashing):
    /// a folder left half-written by a failed download isn't "installed".
    static func isComplete(_ id: String) -> Bool {
        guard let expectations = try? expectations(for: id) else { return false }
        return expectations.allSatisfy { expectation in
            let present = Set(expectation.files.keys.filter {
                FileManager.default.fileExists(atPath: expectation.folder.appendingPathComponent($0).path(percentEncoded: false))
            })
            return missingFile(expected: expectation.files, optional: expectation.optional, present: present) == nil
        }
    }

    /// Hashes every folder of a freshly downloaded model. A folder that fails
    /// is deleted (it is untrusted) and the error is rethrown.
    static func verifyDownload(_ id: String) throws {
        for expectation in try expectations(for: id) {
            do {
                try verify(folder: expectation.folder, expected: expectation.files, optional: expectation.optional)
            } catch {
                discardIfUntrusted(expectation.folder, after: error)
                throw error
            }
        }
    }

    /// A changed or unknown file makes the folder untrusted: it is deleted.
    /// A merely incomplete one holds only verified files, so it is kept for
    /// the next (pinned) download to finish, which then fetches just the gap.
    private static func discardIfUntrusted(_ folder: URL, after error: Error) {
        if case ModelIntegrityError.incomplete = error { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Before loading: a folder already verified against these pins is
    /// trusted; one from an older build (no marker) is hashed once now.
    static func verifyInstalled(_ id: String) throws {
        for expectation in try expectations(for: id) where !hasMarker(folder: expectation.folder, expected: expectation.files) {
            do {
                try verify(folder: expectation.folder, expected: expectation.files, optional: expectation.optional)
            } catch {
                discardIfUntrusted(expectation.folder, after: error)
                throw error
            }
        }
    }

    /// Every regular file in `folder` (hidden bookkeeping aside) must be pinned
    /// and match its hash, and every pinned file must be there, except whole
    /// optional components. A missing file would otherwise let a library
    /// fetch its own unpinned copy at load (WhisperKit's tokenizer fallback).
    static func verify(folder: URL, expected: [String: String], optional: Set<String> = []) throws {
        let files = try regularFiles(in: folder)
        for file in files {
            guard let hash = expected[file.relative] else { throw ModelIntegrityError.unexpected(file: file.relative) }
            guard try sha256(of: file.url) == hash.lowercased() else { throw ModelIntegrityError.mismatch(file: file.relative) }
        }
        if let missing = missingFile(expected: expected, optional: optional, present: Set(files.map(\.relative))) {
            throw ModelIntegrityError.incomplete(file: missing)
        }
        try Data(marker(expected: expected, files: files).utf8)
            .write(to: folder.appendingPathComponent(markerName), options: .atomic)
    }

    /// First pinned file that is absent: required files must all be present;
    /// an optional component is either entirely present or entirely absent.
    private static func missingFile(expected: [String: String], optional: Set<String>, present: Set<String>) -> String? {
        var partial: [String: [String]] = [:]
        for file in expected.keys.sorted() where !present.contains(file) {
            let component = String(file.split(separator: "/", maxSplits: 1).first ?? "")
            guard optional.contains(component) else { return file }
            partial[component, default: []].append(file)
        }
        for (component, missing) in partial.sorted(by: { $0.key < $1.key }) {
            let total = expected.keys.filter { $0.split(separator: "/", maxSplits: 1).first.map(String.init) == component }.count
            if missing.count < total { return missing[0] }
        }
        return nil
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
