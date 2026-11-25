import AVFoundation

/// Chooses the voice that speaks cues.
///
/// iOS's default voice for a language is usually the small, robotic "compact"
/// one. Enhanced and Premium voices sound far more natural, so unless the user
/// picked a voice we use the best one installed.
enum SpeechVoices {
    /// The user's preferred language, e.g. "en-GB". Voices in this exact
    /// language and region win ties against other accents.
    static var preferredLanguage: String { Locale.preferredLanguages.first ?? "en-US" }

    /// Installed voices that speak the user's language (any accent), best quality first.
    static func available(for language: String = preferredLanguage) -> [AVSpeechSynthesisVoice] {
        let code = languageCode(language)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                languageCode(voice.language) == code
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                let aLocal = a.language == language
                let bLocal = b.language == language
                if aLocal != bLocal { return aLocal }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// The chosen voice if it is still installed, otherwise the best installed voice.
    static func voice(identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return available().first ?? AVSpeechSynthesisVoice(language: preferredLanguage)
    }

    private static func languageCode(_ identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier
            ?? String(identifier.prefix(2))
    }
}
