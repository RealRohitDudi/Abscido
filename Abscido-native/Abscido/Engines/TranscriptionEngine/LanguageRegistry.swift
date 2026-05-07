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

    /// Normalizes various language inputs to Whisper/MLX style ISO-639-1 codes.
    /// Examples:
    /// - "hi-IN" / "hi_IN" -> "hi"
    /// - "Hindi" -> "hi"
    /// - "AUTO" / "" -> nil
    static func normalizedLanguageCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lower = trimmed.lowercased()
        if lower == "auto" { return nil }

        // "hi-IN" / "hi_IN" / "en_US" → "hi" / "en"
        let base = lower
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? lower

        // Common human-readable names (defensive; picker uses codes already).
        let aliases: [String: String] = [
            "hindi": "hi",
            "english": "en",
            "spanish": "es",
            "french": "fr",
            "german": "de",
            "japanese": "ja",
            "portuguese": "pt",
            "arabic": "ar",
            "chinese": "zh",
            "korean": "ko",
            "italian": "it",
            "dutch": "nl",
            "russian": "ru",
            "polish": "pl",
            "turkish": "tr",
            "swedish": "sv",
            "danish": "da",
            "norwegian": "no",
            "finnish": "fi",
            "ukrainian": "uk",
        ]

        let normalized = aliases[base] ?? base
        // If it's in our registry, great; otherwise still return the base
        // (WhisperKit supports more languages than our UI list).
        return normalized
    }

    /// Minimal in-language seed text to bias decoding toward the chosen script.
    /// This helps prevent Whisper-like models from emitting English translations when
    /// the user explicitly chose a source language.
    static func promptSeedText(forNormalizedCode code: String) -> String? {
        switch code {
        case "hi":
            return "हिंदी"
        case "ja":
            return "日本語"
        case "zh":
            return "中文"
        case "ko":
            return "한국어"
        case "ru":
            return "русский"
        case "ar":
            return "العربية"
        default:
            return nil
        }
    }
}
