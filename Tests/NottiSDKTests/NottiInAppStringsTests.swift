import XCTest
@testable import NottiSDK

/// IAM-38 (label), design D11: the close control's accessibility label comes from an in-code table keyed by
/// the primary subtag of the first preferred language (RN `NottiInAppViews.swift:546-560`). The preferred
/// languages are injected; the labels are asserted as literals.
final class NottiInAppStringsTests: XCTestCase {

    func test_englishGivesClose() {
        XCTAssertEqual(NottiInAppStrings.closeLabel(languages: ["en"]), "Close")
        XCTAssertEqual(NottiInAppStrings.closeLabel(languages: ["en-US"]), "Close")
    }

    func test_anyPortugueseGivesFechar() {
        for language in ["pt-BR", "pt-PT", "pt_BR", "pt", "PT-br"] {
            XCTAssertEqual(NottiInAppStrings.closeLabel(languages: [language]), "Fechar", language)
        }
    }

    func test_otherLanguagesAndAnEmptyListFallBackToClose() {
        for language in ["fr", "es", "es-419", "ptx", "pot", ""] {
            XCTAssertEqual(NottiInAppStrings.closeLabel(languages: [language]), "Close", language)
        }
        XCTAssertEqual(NottiInAppStrings.closeLabel(languages: []), "Close")
    }

    func test_onlyTheFirstPreferredLanguageCounts() {
        XCTAssertEqual(NottiInAppStrings.closeLabel(languages: ["fr", "pt-BR"]), "Close")
        XCTAssertEqual(NottiInAppStrings.closeLabel(languages: ["pt-BR", "en"]), "Fechar")
    }

    func test_theTableIsCodeWithNoResourceLookup() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent("Sources/NottiSDK/InApp/UI/NottiInAppStrings.swift"),
            encoding: .utf8
        )
        for banned in ["NSLocalizedString", "Bundle", "LocalizedStringKey", "String(localized", ".strings", "lproj"] {
            XCTAssertFalse(text.contains(banned), "the label table must not use \(banned)")
        }
        let sources = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent } ?? []
        XCTAssertFalse(files.isEmpty, "the sources were found")
        XCTAssertFalse(files.contains { $0.hasSuffix(".lproj") || $0.hasSuffix(".strings") || $0.hasSuffix(".xcstrings") },
                       "the SDK ships no localized resource")
    }
}
