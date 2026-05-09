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

    /// Multi-sentence in-language seed text that primes the Whisper decoder's prior toward the
    /// chosen script. The `<|hi|>` language token alone is only a *soft* bias — for languages
    /// where two scripts share an audio space (Hindi/Urdu, traditional/simplified Chinese, etc.)
    /// a one-word seed is not enough to keep small Whisper models on the right script. A longer
    /// natural-language prefix fed via `promptTokens` shifts the decoder's distribution decisively
    /// toward the target script for every subsequent window.
    static func promptSeedText(forNormalizedCode code: String) -> String? {
        switch code {
        case "hi":
            // Devanagari prior. Without this Whisper-base routinely emits Urdu/Arabic-script
            // tokens for Hindi audio because Hindi-Urdu share phonemes in the model's audio space.
            return "नमस्ते। यह वीडियो हिंदी भाषा में है। मैं हिंदी में बात कर रहा हूँ। कृपया देवनागरी लिपि में लिखें।"
        case "ur":
            return "السلام علیکم۔ یہ ویڈیو اردو زبان میں ہے۔ میں اردو میں بات کر رہا ہوں۔"
        case "bn":
            return "নমস্কার। এই ভিডিওটি বাংলা ভাষায়। আমি বাংলায় কথা বলছি।"
        case "mr":
            return "नमस्कार. हा व्हिडिओ मराठी भाषेत आहे. मी मराठीत बोलत आहे."
        case "ta":
            return "வணக்கம். இந்த வீடியோ தமிழ் மொழியில் உள்ளது. நான் தமிழில் பேசுகிறேன்."
        case "te":
            return "నమస్కారం. ఈ వీడియో తెలుగు భాషలో ఉంది. నేను తెలుగులో మాట్లాడుతున్నాను."
        case "ja":
            return "こんにちは。このビデオは日本語です。私は日本語で話しています。日本語で書き起こしてください。"
        case "zh":
            return "你好。这段视频是普通话。我正在用中文说话。请用简体中文转写。"
        case "ko":
            return "안녕하세요. 이 영상은 한국어입니다. 저는 한국어로 말하고 있습니다."
        case "ru":
            return "Здравствуйте. Это видео на русском языке. Я говорю по-русски. Пожалуйста, расшифруйте кириллицей."
        case "ar":
            return "مرحبا. هذا الفيديو باللغة العربية. أنا أتحدث بالعربية. الرجاء الكتابة بالحروف العربية."
        case "fa":
            return "سلام. این ویدیو به زبان فارسی است. من به فارسی صحبت می‌کنم."
        case "he":
            return "שלום. הסרטון הזה בעברית. אני מדבר בעברית. אנא תמללו באותיות עבריות."
        case "th":
            return "สวัสดีครับ วิดีโอนี้เป็นภาษาไทย ผมกำลังพูดภาษาไทย"
        case "el":
            return "Γειά σας. Αυτό το βίντεο είναι στα ελληνικά. Μιλώ ελληνικά."
        case "uk":
            return "Привіт. Це відео українською мовою. Я розмовляю українською."
        default:
            return nil
        }
    }
}
