//
//  TranslateButton.swift
//  damus
//
//  Created by William Casarin on 2023-02-02.
//

import SwiftUI
import NaturalLanguage

struct TranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind
    
    @State var checkingTranslationStatus: Bool = false
    @State var translatable: Bool = true

    @State var noteLanguage: String?
    @State var show_translated_note: Bool
    @State var translated_artifacts: NoteArtifacts?

    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })

    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self._noteLanguage = State(initialValue: damus_state.translations.detectLanguage(event, state: damus_state))

        if let translationWithLanguage = damus_state.translations.cachedTranslation(event) {
            self._noteLanguage = State(initialValue: translationWithLanguage.language)

            let translatedBlocks = event.get_blocks(content: translationWithLanguage.translation)
            self._translated_artifacts = State.init(initialValue: render_blocks(blocks: translatedBlocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey))
        } else {
            self._translated_artifacts = State(initialValue: nil)
        }

        self._show_translated_note = State(initialValue: damus_state.settings.auto_translate)
    }
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            show_translated_note = true
            processTranslation()
        }
        .translate_button_style()
    }

    func processTranslation() {
        guard noteLanguage != nil && !checkingTranslationStatus && translatable else {
            return
        }

        checkingTranslationStatus = true
        show_translated_note = true

        Task {
            let translationWithLanguage = await damus_state.translations.translate(event, state: damus_state)
            DispatchQueue.main.async {
                guard translationWithLanguage != nil else {
                    noteLanguage = damus_state.translations.targetLanguage
                    checkingTranslationStatus = false
                    show_translated_note = false
                    translatable = false
                    return
                }

                noteLanguage = translationWithLanguage!.language

                // Render translated note.
                let translatedBlocks = event.get_blocks(content: translationWithLanguage!.translation)
                translated_artifacts = render_blocks(blocks: translatedBlocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)

                translatable = true

                checkingTranslationStatus = false
            }
        }
    }
    
    func Translated(lang: String, artifacts: NoteArtifacts) -> some View {
        return Group {
            Button(String(format: NSLocalizedString("Translated from %@", comment: "Button to indicate that the note has been translated from a different language."), lang)) {
                show_translated_note = false
            }
            .translate_button_style()
            
            SelectableText(attributedString: artifacts.content, size: self.size)
        }
    }
    
    func MainContent(note_lang: String) -> some View {
        return Group {
            if translatable {
                let languageName = Locale.current.localizedString(forLanguageCode: note_lang)
                if let languageName, let translated_artifacts, show_translated_note {
                    Translated(lang: languageName, artifacts: translated_artifacts)
                } else if !damus_state.settings.auto_translate {
                    TranslateButton
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        Group {
            if let note_lang = noteLanguage, note_lang != damus_state.translations.targetLanguage {
                MainContent(note_lang: note_lang)
                    .task {
                        if show_translated_note {
                            processTranslation()
                        }
                    }
            } else {
                Text("")
            }
        }
    }
}

extension View {
    func translate_button_style() -> some View {
        return self
            .font(.footnote)
            .contentShape(Rectangle())
            .padding([.top, .bottom], 10)
    }
}

struct TranslateView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        TranslateView(damus_state: ds, event: test_event, size: .normal)
    }
}
