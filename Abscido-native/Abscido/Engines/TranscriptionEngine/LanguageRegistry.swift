import Foundation

/// Supported languages for MLX-Whisper transcription.
enum LanguageRegistry {
    struct Language: Identifiable, Sendable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let languages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "zh", name: "Chinese (Simplified)"),
        Language(code: "ko", name: "Korean"),
        Language(code: "it", name: "Italian"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "ru", name: "Russian"),
        Language(code: "pl", name: "Polish"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "da", name: "Danish"),
        Language(code: "no", name: "Norwegian"),
        Language(code: "fi", name: "Finnish"),
        Language(code: "uk", name: "Ukrainian"),
    ]

    static let defaultLanguage = languages[0]

    static func language(forCode code: String) -> Language? {
        languages.first { $0.code == code }
    }
}
