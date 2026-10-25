import Foundation

/// The only text the SDK owns in an In-App message: the close control's accessibility label (IAM-38,
/// design D11). An in-code table, no resource lookup, so CocoaPods and SPM ship the same thing. Port of RN
/// `NottiInAppAccessibility.closeLabel` (`NottiInAppViews.swift:546-560`).
enum NottiInAppStrings {

    private static let closeEnglish = "Close"
    private static let closeLabels = ["pt": "Fechar"]

    /// The label for the first preferred language: `Fechar` when its primary subtag (split on `-` or `_`,
    /// lowercased) is `pt`, so `pt-BR` and `pt-PT` alike; `Close` for any other language or an empty list.
    static func closeLabel(languages: [String] = Locale.preferredLanguages) -> String {
        guard let first = languages.first else { return closeEnglish }
        let primary = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        return closeLabels[primary] ?? closeEnglish
    }
}
