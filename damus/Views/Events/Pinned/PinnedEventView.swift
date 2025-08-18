//
//  PinnedEventView.swift
//  damus
//
//  Created by Terry Yiu on 7/21/25.
//

import SwiftUI

struct PinnedEventView: View {
    let damus: DamusState
    let event: NostrEvent
    let options: EventViewOptions

    var body: some View {
        VStack(alignment: .leading) {
            PinnedHeaderView(damus: damus, pubkey: event.pubkey)
                .padding(.horizontal)
                .buttonStyle(PlainButtonStyle())

            TextEvent(damus: damus, event: event, pubkey: event.pubkey, options: options)
        }
    }
}

#Preview {
    PinnedEventView(damus: test_damus_state, event: test_note, options: [])
}
