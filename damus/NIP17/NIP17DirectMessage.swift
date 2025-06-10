//
//  NIP17.swift
//  damus
//
//  Created by Terry Yiu on 6/6/25.
//

import Foundation

/// Functions and utilities for the NIP-04 spec
struct NIP17 {}

extension NIP17 {
    /// Creates a sealed and gift wrapped kind 14 direct message event. The kind 14 direct message will not be signed because the message might leak to relays and become fully public.
    static func giftWrappedDirectMessage(message: String, senderKeypair: FullKeypair, receiverPubkey: Pubkey) -> NostrEvent? {
        let tags = [
            ["p", receiverPubkey.hex()] // TODO add receiver relay URL
        ]

        guard let unsignedDM = NostrEvent(content: message, keypair: .just_pubkey(senderKeypair.pubkey), kind: NostrKind.dm.rawValue, tags: tags)
        else {
            return nil;
        }

        return try? NIP59GiftWrap.giftWrap(withRumor: unsignedDM, toRecipient: receiverPubkey, signedBy: senderKeypair)
    }
}
