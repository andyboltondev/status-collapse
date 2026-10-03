import Foundation
import Testing
@testable import StatusCollapse

@Suite struct UpdateCheckTests {
    @Test(arguments: [
        ("1.3.1", "1.3.0", true), ("1.10.0", "1.9.0", true), ("2", "1.9.9", true),
        ("v1.4.0", "1.3.0", true), ("1.3.0", "1.3.0", false), ("1.2.9", "1.3.0", false),
        ("1.3", "1.3.0", false), ("1.3.0.1", "1.3.0", true), ("beta", "1.3.0", false), ("", "1.3.0", false),
    ])
    func comparesVersions(remote: String, local: String, newer: Bool) {
        #expect(UpdateCheck.isNewer(remote, than: local) == newer)
    }

    private func json(tag: String = "v1.4.0", url: String = "https://github.com/a/b/releases/tag/v1.4.0",
                      extra: String = "") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)"\#(extra)}"#.utf8)
    }

    @Test func parsesARelease() {
        let release = UpdateCheck.parse(json())
        #expect(release?.version == "1.4.0")
        #expect(release?.url.host == "github.com")
    }

    @Test func ignoresDraftsAndPreReleases() {
        #expect(UpdateCheck.parse(json(extra: #","draft":true"#)) == nil)
        #expect(UpdateCheck.parse(json(extra: #","prerelease":true"#)) == nil)
    }

    @Test func refusesLinksOffGitHub() {
        #expect(UpdateCheck.parse(json(url: "https://evil.example/x")) == nil)
        #expect(UpdateCheck.parse(json(url: "http://github.com/a/b")) == nil)
        #expect(UpdateCheck.parse(json(url: "file:///etc/passwd")) == nil)
    }

    @Test func rejectsMalformedPayloads() {
        #expect(UpdateCheck.parse(Data("{}".utf8)) == nil)
        #expect(UpdateCheck.parse(Data("not json".utf8)) == nil)
        #expect(UpdateCheck.parse(json(tag: "nightly")) == nil)
    }
}

@Suite struct LanguageTests {
    @Test(arguments: [
        (["en-GB"], "en-GB"), (["en-US"], "en-US"), (["en-AU"], "en-GB"), (["fr-FR"], "fr"),
        (["pt-BR"], "pt-BR"), (["pt-PT"], "pt-PT"), (["zh-Hant-TW"], "zh-Hant"),
        (["zh-Hans-CN"], "zh-Hans"), (["no"], "nb"), (["xx", "de"], "de"), (["xx"], "en-GB"),
    ])
    func resolvesLanguages(preferred: [String], expected: String) {
        #expect(AppLanguage.resolve(preferred: preferred) == expected)
    }

    @Test func everyLanguageHasATranslationFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Localization")
        for language in AppLanguage.all where language.code != AppLanguage.fallback {
            let file = root.appending(path: "\(language.code).lproj/Localizable.strings")
            #expect(FileManager.default.fileExists(atPath: file.path), "missing \(language.code)")
        }
    }

    /// Every string shown through `L(...)` must be translated in every language, so a new string
    /// can't ship in English only.
    @Test func everyStringIsTranslatedEverywhere() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = try ["Views", "Controller"].map {
            try String(contentsOf: project.appending(path: "Sources/StatusCollapse/\($0).swift"), encoding: .utf8)
        }.joined()
        let used = Set(sources.matches(of: /\bL\("((?:[^"\\]|\\.)*)"/).map { String($0.1) })
        #expect(used.count > 50)
        for language in AppLanguage.all {
            let file = project.appending(path: "Resources/Localization/\(language.code).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: file) as? [String: String], "\(language.code) unreadable")
            for key in used where table[key.replacingOccurrences(of: "\\\"", with: "\"")] == nil {
                Issue.record("\(language.code) lacks \"\(key)\"")
            }
        }
    }
}
