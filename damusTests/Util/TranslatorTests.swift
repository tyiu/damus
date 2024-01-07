//
//  TranslatorTests.swift
//  damusTests
//
//  Created by Terry Yiu on 1/8/24.
//

import XCTest
@testable import damus

final class TranslatorTests: XCTestCase {

    func testShouldTranslateWhenLanguagesAreDifferent() throws {
        let userSettingsStore = UserSettingsStore()
        userSettingsStore.translation_service = .purple
        let translator = Translator(userSettingsStore, purple: DamusPurple(environment: .local_test, keypair: test_keypair))

        XCTAssertTrue(translator.shouldTranslate(from: "en", to: "es"))
        XCTAssertTrue(translator.shouldTranslate(from: "es", to: "fr"))
    }

    func testShouldNotTranslateWhenLanguagesAreTheSame() throws {
        let userSettingsStore = UserSettingsStore()
        userSettingsStore.translation_service = .purple
        let translator = Translator(userSettingsStore, purple: DamusPurple(environment: .local_test, keypair: test_keypair))

        XCTAssertFalse(translator.shouldTranslate(from: "en", to: "en"))
        XCTAssertFalse(translator.shouldTranslate(from: "es", to: "es"))
    }

    func testShouldNotTranslateWhenNoTranslationServiceSelected() throws {
        let userSettingsStore = UserSettingsStore()
        userSettingsStore.translation_service = .none
        let translator = Translator(userSettingsStore, purple: DamusPurple(environment: .local_test, keypair: test_keypair))

        XCTAssertFalse(translator.shouldTranslate(from: "en", to: "es"))
        XCTAssertFalse(translator.shouldTranslate(from: "es", to: "fr"))
    }

}
