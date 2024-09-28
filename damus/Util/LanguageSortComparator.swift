//
//  LanguageSortComparator.swift
//  damus
//
//  Created by Terry Yiu on 9/22/24.
//

import Foundation

struct LanguageSortComparator: SortComparator {
    var order: SortOrder

    func compare(_ lhs: Locale.Language, _ rhs: Locale.Language) -> ComparisonResult {
        let comparisonResult = compareForward(lhs, rhs)
        switch order {
        case .forward:
            return comparisonResult
        case .reverse:
            switch comparisonResult {
            case .orderedAscending:
                return .orderedDescending
            case .orderedDescending:
                return .orderedAscending
            case .orderedSame:
                return .orderedSame
            }
        }
    }

    private func compareForward(_ lhs: Locale.Language, _ rhs: Locale.Language) -> ComparisonResult {
        let currentLocale = Locale.current
        let localizedLhs = currentLocale.localizedString(forLanguage: lhs)
        let localizedRhs = currentLocale.localizedString(forLanguage: rhs)

        return localizedLhs.localizedCompare(localizedRhs)
    }
}

extension Locale {
    func localizedString(forLanguage language: Locale.Language) -> String {
        guard let languageCode = language.languageCode, let localizedLanguageCode = localizedString(forLanguageCode: languageCode.identifier) else {
            return language.languageCode?.identifier ?? language.minimalIdentifier
        }

        if let region = language.region, let localizedRegion = localizedString(forRegionCode: region.identifier) {
            return "\(localizedLanguageCode) (\(localizedRegion))"
        } else {
            return localizedLanguageCode
        }
    }
}
