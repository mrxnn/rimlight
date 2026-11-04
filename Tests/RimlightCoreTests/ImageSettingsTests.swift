import Foundation
import Testing

@testable import RimlightCore

@Suite struct ImageSettingsTests {
    @Test func noFileMeansCodex() throws {
        try withTempDir { dir in
            let settings = try ImageSettings.load(environment: ["RIMLIGHT_CONFIG_DIR": dir.path])
            #expect(settings == ImageSettings())
            #expect(settings.provider == .codex)
        }
    }

    @Test func savesAndLoadsAndKeepsEachProvidersModel() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_CONFIG_DIR": dir.appending(path: "nested").path]
            var settings = ImageSettings(provider: .openai, quality: "medium")
            settings.setModel("gpt-image-2.5-flare", for: .openai)
            settings.setModel("vendor/model", for: .openrouter)
            try settings.save(environment: env)
            var read = try ImageSettings.load(environment: env)
            #expect(read == settings)
            read.provider = .openrouter
            #expect(read.model(for: read.provider) == "vendor/model")
            #expect(read.model(for: .codex) == nil)
        }
    }

    @Test func aBrokenFileIsAnErrorNotCodex() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_CONFIG_DIR": dir.path]
            try Data(#"{"provider":"nobody"}"#.utf8).write(to: ImageSettings.url(environment: env))
            #expect(throws: StoreError.self) { try ImageSettings.load(environment: env) }
        }
    }

    @Test func pathFollowsXDGThenHome() {
        #expect(ImageSettings.url(environment: ["XDG_CONFIG_HOME": "/x/config"]).path == "/x/config/rimlight/image.json")
        #expect(ImageSettings.url(environment: [:]).path.hasSuffix("/.config/rimlight/image.json"))
    }

    /// A flag's model belongs to the provider the flags end up on.
    @Test func overridesLandOnTheResolvedProvider() {
        var saved = ImageSettings(provider: .openai)
        saved.setModel("gpt-image-2.5-flare", for: .openai)
        let codex = ImageGenerators.resolve(saved, .init(provider: .codex, model: "default"))
        #expect(codex.provider == .codex && codex.model(for: .codex) == "default")
        #expect(codex.model(for: .openai) == "gpt-image-2.5-flare")
        let same = ImageGenerators.resolve(saved, .init(quality: "high"))
        #expect(same.provider == .openai && same.quality == "high")
    }

    @Test func keyVariablesAreRimlightsOwn() {
        #expect(ImageProvider.codex.keyVariable == nil)
        #expect(ImageProvider.openai.keyVariable == "RIMLIGHT_OPENAI_API_KEY")
        #expect(ImageProvider.openrouter.keyVariable == "RIMLIGHT_OPENROUTER_API_KEY")
    }
}
