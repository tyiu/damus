//
//  PinnedHeaderView.swift
//  damus
//
//  Created by Terry Yiu on 7/21/25.
//

import SwiftUI

struct PinnedHeaderView: View {
    let damus: DamusState
    let pubkey: Pubkey

    init(damus: DamusState, pubkey: Pubkey) {
        self.damus = damus
        self.pubkey = pubkey
    }

    var body: some View {
        HStack(alignment: .center) {
            Image("pin")
                .foregroundColor(Color.gray)

            Text("Pinned", comment: "FIXME")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    PinnedHeaderView(damus: test_damus_state, pubkey: test_pubkey)
}
