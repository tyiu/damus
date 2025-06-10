//
//  NIP59GiftWrap.swift
//  damus
//
//  Created by Terry Yiu on 6/6/25.
//

import Foundation

struct NIP59GiftWrap {
    /// Creates a ``NostrEvent`` gift wrap of kind 1059 that takes a rumor, an unsigned ``NostrEvent``, and seals it in a signed ``NostrEvent`` seal event of kind 13, and then wraps that seal encrypted in the content of the gift wrap.
    ///
    /// - Parameters:
    ///   - rumor: a ``NostrEvent`` that is not signed.
    ///   - recipient: the ``Pubkey`` of the receiver of the event. This pubkey will be used to encrypt the rumor. If `recipientAlias` is not provided, this pubkey will automatically be added as a tag to the ``NostrEvent`` gift wrap event.
    ///   - recipientAlias: optional ``Pubkey`` of the receiver's alias used to receive gift wraps without exposing the receiver's identity. It is not used to encrypt the rumor. If it is provided, this pubkey will automatically be added as a tag to the ``NostrEvent`` gift wrap event.
    ///   - tags: the list of tags to add to the ``NostrEvent`` gift wrap event in addition to the pubkey tag from `toRecipient`. This list should include any information needed to route the event to its intended recipient, such as [NIP-13 Proof of Work](https://github.com/nostr-protocol/nips/blob/master/13.md).
    ///   - createdAt: the creation timestamp of the seal. Note that this timestamp SHOULD be tweaked to thwart time-analysis attacks. Note that some relays don't serve events dated in the future, so all timestamps SHOULD be in the past. By default, if `createdAt` is not provided, a random timestamp within 2 days in the past will be chosen.
    ///   - keypair: The real ``FullKeypair`` to encrypt the rumor and sign the seal with. Note that a different random one-time use key is used to sign the gift wrap.
    static func giftWrap(
        withRumor rumor: NostrEvent,
        toRecipient recipient: Pubkey,
        recipientAlias: Pubkey? = nil,
        tags: [Tag] = [],
        createdAt: UInt32 = UInt32(max(0, Date.now.timeIntervalSince1970 - TimeInterval.random(in: 0...172800))),
        signedBy fullKeypair: FullKeypair
    ) throws -> NostrEvent? {
        guard let seal = try seal(withRumor: rumor, toRecipient: recipient, signedBy: fullKeypair) else {
            throw SealEventError.sealFailed
        }
        return try giftWrap(withSeal: seal, toRecipient: recipient, recipientAlias: recipientAlias, tags: tags, createdAt: createdAt)
    }

    /// Creates a ``NostrEvent`` gift wrap of kind 1059 that takes a signed ``NostrEvent`` of kind 13, and then wraps that seal encrypted in the content of the gift wrap.
    ///
    /// - Parameters:
    ///   - seal: a signed ``NostrEvent`` seal event of kind 13.
    ///   - recipient: the ``Pubkey`` of the receiver of the event. This pubkey will be used to encrypt the rumor. If `recipientAlias` is not provided, this pubkey will automatically be added as a tag to the ``GiftWrapEvent``.
    ///   - recipientAlias: optional ``Pubkey`` of the receiver's alias used to receive gift wraps without exposing the receiver's identity. It is not used to encrypt the rumor. If it is provided, this pubkey will automatically be added as a tag to the ``GiftWrapEvent``.
    ///   - tags: the list of tags.
    ///   - createdAt: the creation timestamp of the seal. Note that this timestamp SHOULD be tweaked to thwart time-analysis attacks. Note that some relays don't serve events dated in the future, so all timestamps SHOULD be in the past. By default, if `createdAt` is not provided, a random timestamp within 2 days in the past will be chosen.
    static func giftWrap(
        withSeal seal: NostrEvent,
        toRecipient recipient: Pubkey,
        recipientAlias: Pubkey? = nil,
        tags: [Tag] = [],
        createdAt: UInt32 = UInt32(max(0, Date.now.timeIntervalSince1970 - TimeInterval.random(in: 0...172800))),
    ) throws -> NostrEvent? {
        guard seal.known_kind == .seal else {
            throw GiftWrapError.sealInvalid
        }

        let jsonData = try JSONEncoder().encode(seal)
        guard let stringifiedJSON = String(data: jsonData, encoding: .utf8) else {
            throw GiftWrapError.utf8EncodingFailed
        }

        let randomFullKeypair = generate_new_keypair()

        let combinedTags = [["p", (recipientAlias ?? recipient).hex()]] + tags.map { $0.strings() }

        let encryptedSeal = try NIP44v2Encryption.encrypt(plaintext: stringifiedJSON, privateKeyA: randomFullKeypair.privkey, publicKeyB: recipient)
        return NostrEvent(content: encryptedSeal, keypair: randomFullKeypair.to_keypair(), kind: NostrKind.gift_wrap.rawValue, tags: combinedTags, createdAt: createdAt)
    }

    /// Unwraps the content of the gift wrap event and decrypts it into a ``NostrEvent`` seal event.
    /// - Parameters:
    ///   - giftWrapEvent: The ``NostrEvent`` gift wrap kind 1059 to unwrap.
    ///   - privateKey: The ``Privkey`` to decrypt the content.
    /// - Returns: The ``SealEvent``.
    static func unwrappedSeal(giftWrapEvent: NostrEvent, using privateKey: Privkey) throws -> NostrEvent? {
        guard giftWrapEvent.known_kind == .gift_wrap else {
            throw GiftWrapError.giftWrapInvalid
        }

        guard let unwrappedSeal = try? NIP44v2Encryption.decrypt(payload: giftWrapEvent.content, privateKeyA: privateKey, publicKeyB: giftWrapEvent.pubkey) else {
            throw GiftWrapError.decryptionFailed
        }

        guard let sealJSONData = unwrappedSeal.data(using: .utf8) else {
            throw GiftWrapError.utf8EncodingFailed
        }

        guard let sealEvent = try? JSONDecoder().decode(NostrEvent.self, from: sealJSONData) else {
            throw GiftWrapError.jsonDecodingFailed
        }

        return sealEvent
    }

    /// Creates a ``NostrEvent`` seal event of kind 13  that encrypts a rumor with the sender's private key and receiver's public key.
    /// There is no p tag pointing to the receiver. There is no way to know who the rumor is for without the receiver's or the sender's private key.
    /// The only public information in this event is who is signing it.
    ///
    /// - Parameters:
    ///   - withRumor: a ``NostrEvent`` that is not signed.
    ///   - toRecipient: the ``PublicKey`` of the receiver of the event.
    ///   - createdAt: the creation timestamp of the seal. Note that this timestamp SHOULD be tweaked to thwart time-analysis attacks. Note that some relays don't serve events dated in the future, so all timestamps SHOULD be in the past. By default, if `createdAt` is not provided, a random timestamp within 2 days in the past will be chosen.
    ///   - keypair: The ``FullKeypair`` to sign with.
    static func seal(
        withRumor rumor: NostrEvent,
        toRecipient recipient: Pubkey,
        createdAt: UInt32 = UInt32(max(0, Date.now.timeIntervalSince1970 - TimeInterval.random(in: 0...172800))),
        signedBy fullKeypair: FullKeypair
    ) throws -> NostrEvent? {
        guard rumor.isRumor else {
            throw SealEventError.sealSignedEvent
        }

        let jsonData = try JSONEncoder().encode(rumor)
        guard let stringifiedJSON = String(data: jsonData, encoding: .utf8) else {
            throw SealEventError.utf8EncodingFailed
        }

        let encryptedRumor = try NIP44v2Encryption.encrypt(plaintext: stringifiedJSON, privateKeyA: fullKeypair.privkey, publicKeyB: recipient)
        return NostrEvent(content: encryptedRumor, keypair: fullKeypair.to_keypair(), kind: NostrKind.seal.rawValue, createdAt: createdAt)
    }

    /// Unseals the content of this seal event into a decrypted rumor.
    /// - Parameters:
    ///   - giftWrapEvent: The ``NostrEvent`` gift wrap kind 1059 to unwrap into a seal, and then unseal to reveal the decrypted rumor.
    ///   - privateKey: The `PrivateKey` to decrypt the rumor.
    /// - Returns: The decrypted ``NostrEvent`` rumor, where its `signature` is absent.
    static func unsealedRumor(giftWrapEvent: NostrEvent, using privateKey: Privkey) throws -> NostrEvent? {
        guard let sealEvent = try unwrappedSeal(giftWrapEvent: giftWrapEvent, using: privateKey) else {
            return nil
        }
        return try unsealedRumor(sealEvent: sealEvent, using: privateKey)
    }

    static func unsealedRumor(
        sealEvent: NostrEvent,
        using privateKey: Privkey
    ) throws -> NostrEvent? {
        guard let unsealedRumor = try? NIP44v2Encryption.decrypt(payload: sealEvent.content, privateKeyA: privateKey, publicKeyB: sealEvent.pubkey) else {
            throw SealEventError.decryptionFailed
        }

        guard let data = unsealedRumor.data(using: .utf8) else {
            throw SealEventError.rumorInvalid
        }

        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = dict["content"] as? String,
              let pubkey = dict["pubkey"] as? String,
              let author = Pubkey(hex: pubkey),
              let kind = dict["kind"] as? UInt32,
              let tags = dict["tags"] as? [[String]],
              let createdAt = dict["created_at"] as? UInt32,
              let id = dict["id"] as? String,
              let noteId = NoteId(hex: id) else {
            return nil
        }

//        guard let ev = NostrEvent(content: content, author: author, kind: kind, tags: tags, createdAt: createdAt, id: noteId, sig: Signature(Data())) else {
//            return nil
//        }
        guard let ev = NostrEvent(content: content, keypair: .just_pubkey(author), kind: kind, tags: tags, createdAt: createdAt) else {
            return nil
        }

        return ev
    }
}

extension NostrEvent {
    var isRumor: Bool {
        return sig.data == Data(repeating: 0, count: 128)
    }
}

enum GiftWrapError: Error {
    case decryptionFailed
    case jsonDecodingFailed
    case keypairGenerationFailed
    case pubkeyInvalid
    case utf8EncodingFailed
    case sealInvalid
    case giftWrapInvalid
}

enum SealEventError: Error {
    case decryptionFailed
    case jsonDecodingFailed
    case pubkeyInvalid
    case sealSignedEvent
    case utf8EncodingFailed
    case sealFailed
    case rumorInvalid
}
