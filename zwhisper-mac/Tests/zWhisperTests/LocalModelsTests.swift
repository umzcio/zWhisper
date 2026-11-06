import Foundation
import Testing
@testable import zWhisper

@Suite("On-device model families")
struct LocalModelsTests {
    @Test("catalog ids map to the engine that runs them")
    func familyMapping() {
        #expect(LocalModelFamily(id: LocalModelFamily.parakeetID) == .parakeet)
        #expect(LocalModelFamily(id: LocalModelFamily.nemotronID) == .nemotron)
        for id in ["tiny", "small", "medium", "large-v3-v20240930_626MB", ModelDownloadManager.defaultModelName] {
            #expect(LocalModelFamily(id: id) == .whisper)
        }
        let ids = ModelCatalogEntry.locals.map(\.id)
        #expect(ids.contains(LocalModelFamily.parakeetID))
        #expect(ids.contains(LocalModelFamily.nemotronID))
        #expect(ModelCatalogEntry.locals.allSatisfy { !$0.isCloud })
    }

    @Test("only Whisper can translate")
    func translation() {
        #expect(LocalModelFamily.whisper.canTranslate)
        #expect(!LocalModelFamily.parakeet.canTranslate)
        #expect(!LocalModelFamily.nemotron.canTranslate)
    }

    @Test("NVIDIA models live in FluidAudio's cache, Whisper in zWhisper's")
    func folders() {
        let parakeet = ModelDownloadManager.modelFolder(forVariant: LocalModelFamily.parakeetID).path
        let nemotron = ModelDownloadManager.modelFolder(forVariant: LocalModelFamily.nemotronID).path
        let whisper = ModelDownloadManager.modelFolder(forVariant: "small").path
        #expect(parakeet.hasSuffix("FluidAudio/Models/parakeet-ultra"))
        #expect(nemotron.hasSuffix("/multilingual/1120ms"))
        #expect(nemotron.contains("FluidAudio/Models/"))
        #expect(whisper.hasSuffix("whisperkit-coreml/openai_whisper-small"))
    }

    @Test("Nemotron prompt languages")
    func nemotronLanguages() {
        #expect(NemotronEngine.promptLanguage(for: nil) == "auto")
        #expect(NemotronEngine.promptLanguage(for: "auto") == "auto")
        #expect(NemotronEngine.promptLanguage(for: "en") == "en")
        #expect(NemotronEngine.promptLanguage(for: "ja") == "ja-JP")
        #expect(NemotronEngine.promptLanguage(for: "zh") == "zh-CN")
        #expect(NemotronEngine.promptLanguage(for: "ko") == "ko")
    }

    @Test("Nemotron closes the final sentence")
    func closingSentence() {
        #expect(NemotronEngine.closingSentence("transcribed it", language: "en-US") == "transcribed it.")
        #expect(NemotronEngine.closingSentence("Is it done?", language: nil) == "Is it done?")
        #expect(NemotronEngine.closingSentence("done.", language: nil) == "done.")
        #expect(NemotronEngine.closingSentence("出来た", language: "ja-JP") == "出来た。")
        #expect(NemotronEngine.closingSentence("", language: nil) == "")
    }

    @Test("download sizes count compiled models only")
    func sizesSkipPackages() {
        let tree = Data("""
        [{"type":"file","path":"Encoder.mlmodelc/weights/weight.bin","size":600000000},
         {"type":"file","path":"mlpackages/Encoder.mlpackage/Data/weight.bin","size":445000000},
         {"type":"file","path":"vocab.json","size":27000000}]
        """.utf8)
        #expect(ModelDownloadManager.sizeLabel(fromRepoTree: tree) == "627 MB")
    }
}
