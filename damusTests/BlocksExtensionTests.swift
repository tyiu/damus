//
//  BlocksExtensionTests.swift
//  damusTests
//
//  Created by Terry Yiu on 1/8/24.
//

import XCTest
import NaturalLanguage
@testable import damus

final class BlocksExtensionTests: XCTestCase {

    func testLanguageHypothesisIsCorrectWithRightSingleQuotationMark() throws {
        let note = try XCTUnwrap(NdbNote.owned_from_json(json: test_english_text_note_with_right_single_quotation_mark))
        let blocks = note.blocks(test_keypair)
        XCTAssertEqual(blocks.languageHypothesis, NLLanguage.english)
    }

    func testLanguageHypothesisIsCorrectWithNonEnglishLocale() throws {
        let note = try XCTUnwrap(NdbNote.owned_from_json(json: test_japanese_text_note))
        let blocks = note.blocks(test_keypair)
        XCTAssertEqual(blocks.languageHypothesis, NLLanguage.japanese)
    }

}
