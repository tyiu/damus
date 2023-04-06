//
//  Translations.swift
//  damus
//
//  Created by Terry Yiu on 3/29/23.
//

import Foundation
import NaturalLanguage

class Translations: ObservableObject {
    private static let languageDetectionMinConfidence = 0.5

    @Published var translations: [NostrEvent: String] = [:]
    @Published var languages: [NostrEvent: String] = [:]

    let settings: UserSettingsStore

    let translator: Translator

    let targetLanguage = currentLanguage()
    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })

    init(_ settings: UserSettingsStore) {
        self.settings = settings
        self.translator = Translator(settings)
    }

    /**
     Attempts to detect the language of the content of a given nostr event using Apple's offline NaturalLanguage API.
     The detected language will be returned only if it has a 50% or more confidence.
     This is a best effort guess and could be incorrect.
     */
    func detectLanguage(_ event: NostrEvent, state: DamusState) -> String? {
        if let cachedLanguage = languages[event] {
            return cachedLanguage
        }

        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = event.blocks(state.keypair.privkey)
        let originalOnlyText = originalBlocks.compactMap { $0.is_text }.joined(separator: " ")

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= Translations.languageDetectionMinConfidence })?.key.rawValue else {
            return nil
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        let language = localeToLanguage(locale)
        languages[event] = language
        return language
    }

    /**
     Returns true if the given translation is effectively the same as the original note, ignoring whitespaces and new lines.
     */
    private func translationSameAsOriginal(_ translation: String, event: NostrEvent, state: DamusState) -> Bool {
        return translation.trimmingCharacters(in: .whitespacesAndNewlines) == event.get_content(state.keypair.privkey).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasCachedTranslation(_ event: NostrEvent) -> Bool {
        return languages[event] != nil
    }

    func cachedTranslation(_ event: NostrEvent) -> TranslationWithLanguage? {
        if let cachedLanguage = languages[event] {
            if let cachedTranslation = translations[event] {
                return TranslationWithLanguage(translation: cachedTranslation, language: cachedLanguage)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    func translate(_ event: NostrEvent, state: DamusState) async -> TranslationWithLanguage? {
        guard shouldTranslate(event, state: state) else {
            return nil
        }

        guard let noteLanguage = detectLanguage(event, state: state) else {
            return nil
        }

        if languages[event] != nil {
            return cachedTranslation(event)
        }

        do {
            guard let translationWithLanguage = try await translator.translate(event.get_content(state.keypair.privkey), from: noteLanguage, to: targetLanguage) else {
                return nil
            }

            // If the translated content is identical to the original content, don't return the translation.
            if translationSameAsOriginal(translationWithLanguage.translation, event: event, state: state) {
                // Nil out the translation as it's the same as the original.
                translations[event] = nil
                // Leave an entry so that we don't attempt to translate it again in the future.
                languages[event] = targetLanguage
                return nil
            } else {
                translations[event] = translationWithLanguage.translation
                languages[event] = translationWithLanguage.language
                return translationWithLanguage
            }
        } catch {
            return nil
        }
    }

    func shouldTranslate(_ event: NostrEvent, state: DamusState) -> Bool {
        // Do not translate self-authored content because if the language recognizer guesses the wrong language for your own note,
        // it's annoying and unexpected for the translation to show up.
        if event.pubkey == state.pubkey && state.is_privkey_user {
            return false
        }

        // Avoid translating if no translation service is configured.
        switch settings.translation_service {
        case .none:
            return false
        case .libretranslate:
            if URLComponents(string: settings.libretranslate_url) == nil {
                return false
            }
        case .deepl:
            if settings.deepl_api_key == "" {
                return false
            }
        }

        // If translation was attempted before, use the results of the cached translation to determine if it should be shown.
        if languages[event] != nil {
            return translations[event] != nil
        }

        // Avoid translating notes if language cannot be detected or if it is in one of the user's preferred languages.
        guard let noteLanguage = detectLanguage(event, state: state), !preferredLanguages.contains(noteLanguage) else {
            return false
        }

        return true
    }
}
