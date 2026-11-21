import CryptoKit
import FluidAudio
import Foundation
import Testing
@testable import zWhisper

@Suite("Model integrity pins")
struct ModelPinsTests {
    private func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A temp model folder: weights.bin + nested/config.json, and their pins.
    private func makeFolder() throws -> (URL, [String: String]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let weights = Data((0..<10_000).map { UInt8($0 % 251) })
        let config = Data(#"{"a":1}"#.utf8)
        try weights.write(to: folder.appendingPathComponent("weights.bin"))
        try config.write(to: folder.appendingPathComponent("nested/config.json"))
        return (folder, ["weights.bin": hex(weights), "nested/config.json": hex(config)])
    }

    @Test("every local catalog model is pinned to full commits and SHA-256 hashes")
    func manifestCoversCatalog() throws {
        for entry in ModelCatalogEntry.locals {
            let pins = try ModelPins.pins(for: entry.id)
            for pin in pins {
                #expect(pin.revision.count == 40 && pin.revision.allSatisfy(\.isHexDigit), "\(entry.id) \(pin.repo)")
                #expect(!pin.files.isEmpty)
                #expect(pin.files.values.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
                #expect(ModelPins.folderURL(pin.folder, forVariant: entry.id) != nil)
            }
        }
        // Whisper rows pin the tokenizer too: it decides the text that's typed.
        let small = try ModelPins.pins(for: "small")
        #expect(small.contains { $0.repo == ModelDownloadManager.whisperRepo })
        #expect(small.contains { $0.repo == ModelDownloadManager.tokenizerRepoName(forVariant: "small") && $0.files["tokenizer.json"] != nil })
    }

    @Test("unknown models are refused, not trusted")
    func unpinned() {
        #expect(throws: ModelIntegrityError.unpinned("nope")) { try ModelPins.pins(for: "nope") }
    }

    @Test("a folder matching its pins verifies and gets a marker")
    func verifies() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ModelPins.verify(folder: folder, expected: files)
        #expect(ModelPins.hasMarker(folder: folder, expected: files))
        // New pins (an upstream update) invalidate the marker.
        var changed = files
        changed["weights.bin"] = String(repeating: "0", count: 64)
        #expect(!ModelPins.hasMarker(folder: folder, expected: changed))
    }

    @Test("a file changed or added after verification voids the marker")
    func markerTracksFiles() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ModelPins.verify(folder: folder, expected: files)
        #expect(ModelPins.hasMarker(folder: folder, expected: files))
        try Data("x".utf8).write(to: folder.appendingPathComponent("added.bin"))
        #expect(!ModelPins.hasMarker(folder: folder, expected: files))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("added.bin"))
        try ModelPins.verify(folder: folder, expected: files)
        // Same size, new bytes: the replacement gets a new inode/mtime.
        try Data(#"{"b":1}"#.utf8).write(to: folder.appendingPathComponent("nested/config.json"), options: .atomic)
        #expect(!ModelPins.hasMarker(folder: folder, expected: files))
    }

    @Test("one altered byte is refused")
    func alteredByte() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("nested/config.json")
        try Data(#"{"a":2}"#.utf8).write(to: url)
        #expect(throws: ModelIntegrityError.mismatch(file: "nested/config.json")) {
            try ModelPins.verify(folder: folder, expected: files)
        }
        #expect(!ModelPins.hasMarker(folder: folder, expected: files))
    }

    @Test("a file that isn't pinned is refused")
    func unexpectedFile() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x".utf8).write(to: folder.appendingPathComponent("extra.json"))
        #expect(throws: ModelIntegrityError.unexpected(file: "extra.json")) {
            try ModelPins.verify(folder: folder, expected: files)
        }
    }

    @Test("a symlink is refused, even to a matching file")
    func symlink() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("pins-target-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: folder.appendingPathComponent("weights.bin"), to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("weights.bin"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("weights.bin"), withDestinationURL: elsewhere)
        #expect(throws: ModelIntegrityError.unexpected(file: "weights.bin")) {
            try ModelPins.verify(folder: folder, expected: files)
        }
    }

    @Test("a pinned file that's missing fails the check, so no loader can fetch its own copy")
    func incompleteFails() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var more = files
        more["tokenizer.json"] = String(repeating: "a", count: 64)
        #expect(throws: ModelIntegrityError.incomplete(file: "tokenizer.json")) {
            try ModelPins.verify(folder: folder, expected: more)
        }
        // Each file removed in turn from an otherwise valid folder fails too.
        for name in files.keys {
            let (other, pins) = try makeFolder()
            defer { try? FileManager.default.removeItem(at: other) }
            try FileManager.default.removeItem(at: other.appendingPathComponent(name))
            #expect(throws: ModelIntegrityError.incomplete(file: name)) {
                try ModelPins.verify(folder: other, expected: pins)
            }
        }
    }

    @Test("an optional component may be absent, but only as a whole")
    func optionalComponent() throws {
        let (folder, files) = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var more = files
        more["Head.mlmodelc/model.mil"] = String(repeating: "a", count: 64)
        more["Head.mlmodelc/weights.bin"] = String(repeating: "b", count: 64)
        try ModelPins.verify(folder: folder, expected: more, optional: ["Head.mlmodelc"])
        // Half of it present: incomplete.
        let half = Data("mil".utf8)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Head.mlmodelc"), withIntermediateDirectories: true)
        try half.write(to: folder.appendingPathComponent("Head.mlmodelc/model.mil"))
        more["Head.mlmodelc/model.mil"] = hex(half)
        #expect(throws: ModelIntegrityError.incomplete(file: "Head.mlmodelc/weights.bin")) {
            try ModelPins.verify(folder: folder, expected: more, optional: ["Head.mlmodelc"])
        }
        // Optional only names whole components: a required file stays required.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Head.mlmodelc"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("weights.bin"))
        #expect(throws: ModelIntegrityError.incomplete(file: "weights.bin")) {
            try ModelPins.verify(folder: folder, expected: files, optional: ["Head.mlmodelc"])
        }
    }

    @Test("only the CTC head is optional in the shipped pins")
    func shippedOptionals() throws {
        let optional = ModelCatalogEntry.locals.flatMap { (try? ModelPins.pins(for: $0.id)) ?? [] }.compactMap(\.optional).flatMap { $0 }
        #expect(optional == ["CtcHead.mlmodelc"])
    }

    @Test("FluidAudio downloads use the pinned commits")
    func fluidRevisions() throws {
        ModelPins.installFluidRevisions
        let parakeet = try ModelPins.pins(for: LocalModelFamily.parakeetID)
        let nemotron = try ModelPins.pins(for: LocalModelFamily.nemotronID)
        for pin in parakeet + nemotron {
            #expect(ModelRegistry.revisionOverrides[pin.repo] == pin.revision)
        }
    }
}
