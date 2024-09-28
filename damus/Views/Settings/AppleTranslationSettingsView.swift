//
//  AppleTranslationSettingsView.swift
//  damus
//
//  Created by Terry Yiu on 9/22/24.
//

import SwiftUI
import Translation

@available(iOS 18.0, macOS 15.0, *)
@available(macCatalyst, unavailable)
struct AppleTranslationSettingsView: View {
    @ObservedObject var settings: UserSettingsStore

    @State private var supportedLanguages: [Locale.Language] = []
    @State private var installedLanguages = Set<Locale.Language>()
    @State private var installingLanguages = Set<Locale.Language>()
    @State private var languageTranslationConfigurations = [Locale.Language: TranslationSession.Configuration]()

    var body: some View {
        if settings.translation_service == .none {
            if !installedLanguages.isEmpty {
                Section(NSLocalizedString("Available Offline", comment: "Section for downloaded languages for Apple offline translations.")) {
                    ForEach(installedLanguages.sorted(using: LanguageSortComparator(order: .forward)), id: \.self) { language in
                        Text(Locale.current.localizedString(forLanguage: language))
                    }
                }
            }

            Section(NSLocalizedString("Languages Available for Download", comment: "Section for downloadable languages for Apple offline translations.")) {
                ForEach(supportedLanguages.filter { !installedLanguages.contains($0) }, id: \.self) { language in
                    HStack {
                        Text(Locale.current.localizedString(forLanguage: language))
                        Button(
                            action: {
                                installingLanguages.insert(language)
                                languageTranslationConfigurations[language]?.invalidate()
                            },
                            label: {
                                Image(systemName: "arrow.down.circle")
                            }
                        )
                    }
                    .translationTask(languageTranslationConfigurations[language]) { session in
                        if installingLanguages.contains(language) {
                            do {
                                // Display a sheet asking the user's permission
                                // to start downloading the language pairing by
                                // translating a dummy string.
                                //
                                // We do not use `session.prepareTranslation()` because
                                // it does not throw errors as loudly as `session.translate` does,
                                // which helps us indicate when language download is complete.
                                _ = try await session.translate("A")
                                installedLanguages.insert(language)
                                installingLanguages.remove(language)
                            } catch {
                                // Handle any errors.
                                print("Error downloading language \(language): \(error)")
                                installingLanguages.remove(language)
                            }
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    let languageAvailability = LanguageAvailability()
                    supportedLanguages = await languageAvailability.supportedLanguages
                    supportedLanguages.sort(using: LanguageSortComparator(order: .forward))
                    installedLanguages.removeAll()

                    for supportedLanguage in supportedLanguages {
                        let status = await languageAvailability.status(from: supportedLanguage, to: nil)
                        switch status {
                        case .installed:
                            installedLanguages.insert(supportedLanguage)
                        case .supported:
                            languageTranslationConfigurations[supportedLanguage] = TranslationSession.Configuration(
                                source: supportedLanguage
                            )
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
}
