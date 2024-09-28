//
//  OfflineTranslateView.swift
//  damus
//
//  Created by Terry Yiu on 9/29/24.
//

import SwiftUI

import SwiftUI
import NaturalLanguage
import Translation

fileprivate let MIN_UNIQUE_CHARS = 2

@available(iOS 18.0, macOS 15.0, *)
@available(macCatalyst, unavailable)
struct OfflineTranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind

    @ObservedObject var translations_model: TranslationModel

    @State private var translationConfiguration: TranslationSession.Configuration?

//    @State private var languageStatus: LanguageAvailability.Status?

    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self._translations_model = ObservedObject(wrappedValue: damus_state.events.get_cache_data(event.id).translations_model)
    }

    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            translate()
        }
        .translate_button_style()
    }

    func TranslatedView(lang: String?, artifacts: NoteArtifactsSeparated, font_size: Double) -> some View {
        return VStack(alignment: .leading) {
            let translatedFromLanguageString = String(format: NSLocalizedString("Translated from %@", comment: "Button to indicate that the note has been translated from a different language."), lang ?? "ja")
            Text(translatedFromLanguageString)
                .foregroundColor(.gray)
                .font(.footnote)
                .padding([.top, .bottom], 10)

            if self.size == .selected {
                SelectableText(damus_state: damus_state, event: event, attributedString: artifacts.content.attributed, size: self.size)
            } else {
                artifacts.content.text
                    .font(eventviewsize_to_font(self.size, font_size: font_size))
            }
        }
    }

    func translate() {
        guard /*let languageStatus, */translations_model.state == .havent_tried && damus_state.settings.translation_service == .none && damus_state.settings.translate_offline/* && languageStatus != .unsupported*/, let note_language = translations_model.note_language else {
            return
        }

        guard translationConfiguration == nil else {
            translationConfiguration?.invalidate()
            return
        }

        translationConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: note_language))
    }

//    func setLanguageStatus() async {
//        guard languageStatus == nil else {
//            return
//        }
//
//        guard let note_language = translations_model.note_language else {
//            languageStatus = .unsupported
//            return
//        }
//
//        let languageAvailability = LanguageAvailability()
//        let language = Locale.Language(identifier: note_language)
//        languageStatus = await languageAvailability.status(from: language, to: nil)
//    }

    var body: some View {
        if let note_lang = translations_model.note_language, damus_state.settings.translation_service == .none && damus_state.settings.translate_offline && should_translate(event: event, our_keypair: damus_state.keypair, note_lang: note_lang) {
            Group {
                switch self.translations_model.state {
                case .havent_tried:
                    if damus_state.settings.auto_translate/* && languageStatus == .installed*/ {
                        Text("")
                    } else {
                        TranslateButton
                    }
                case .translating:
                    Text("")
                case .translated(let translated):
                    let languageName = Locale.current.localizedString(forLanguageCode: translated.language)
                    TranslatedView(lang: languageName, artifacts: translated.artifacts, font_size: damus_state.settings.font_size)
                case .not_needed:
                    Text("")
                }
            }
            .onAppear {
//                Task { @MainActor in
//                    await setLanguageStatus()
//                }
                translate()
            }
            .translationTask(translationConfiguration) { translationSession in
                Task { @MainActor in
                    do {
                        guard let note_language = translations_model.note_language, translations_model.state == .havent_tried/*, languageStatus != .unsupported*/ else {
                            return
                        }

                        translations_model.state = .translating

                        let originalContent = event.get_content(damus_state.keypair)
                        let response = try await translationSession.translate(originalContent)
                        let translated_note = response.targetText

                        guard originalContent != translated_note else {
                            // if its the same, give up and don't retry
                            translations_model.state = .not_needed
                            return
                        }

                        guard translationMeetsStringDistanceRequirements(original: originalContent, translated: translated_note) else {
                            translations_model.state = .not_needed
                            return
                        }

                        // Render translated note
                        let translated_blocks = parse_note_content(content: .content(translated_note, event.tags))
                        let artifacts = render_blocks(blocks: translated_blocks, profiles: damus_state.profiles)

                        // and cache it
                        translations_model.state = .translated(Translated(artifacts: artifacts, language: note_language))
                    } catch {
                        // code to handle error
                        print("Error translating note: \(error.localizedDescription)")
                        translations_model.state = .not_needed
                    }
                }
            }
        } else {
            Text("")
        }
    }

    func translationMeetsStringDistanceRequirements(original: String, translated: String) -> Bool {
        return levenshteinDistanceIsGreaterThanOrEqualTo(from: original, to: translated, threshold: MIN_UNIQUE_CHARS)
    }
}

@available(iOS 18.0, macOS 15.0, *)
@available(macCatalyst, unavailable)
struct OfflineTranslateView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        OfflineTranslateView(damus_state: ds, event: test_note, size: .normal)
    }
}
