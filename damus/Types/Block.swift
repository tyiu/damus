//
//  Block.swift
//  damus
//
//  Created by Kyle Roucis on 2023-08-21.
//

import Foundation
import NaturalLanguage

fileprivate extension String {
    /// Failable initializer to build a Swift.String from a C-backed `str_block_t`.
    init?(_ s: str_block_t) {
        let len = s.end - s.start
        let bytes = Data(bytes: s.start, count: len)
        self.init(bytes: bytes, encoding: .utf8)
    }
}

/// Represents a block of data stored by the NOSTR protocol. This can be
/// simple text, a hashtag, a url, a relay reference, a mention ref and
/// potentially more in the future.
enum Block: Equatable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.mention(let a), .mention(let b)):
            return a == b
        case (.hashtag(let a), .hashtag(let b)):
            return a == b
        case (.url(let a), .url(let b)):
            return a == b
        case (.invoice(let a), .invoice(let b)):
            return a.string == b.string
        case (_, _):
            return false
        }
    }
    
    case text(String)
    case mention(Mention<MentionRef>)
    case hashtag(String)
    case url(URL)
    case invoice(Invoice)
    case relay(String)
}

struct Blocks: Equatable {
    let words: Int
    let blocks: [Block]
}

extension Block {
    /// Failable initializer for the C-backed type `block_t`. This initializer will inspect
    /// the underlying block type and build the appropriate enum value as needed.
    init?(_ block: block_t, tags: TagsSequence? = nil) {
        switch block.type {
        case BLOCK_HASHTAG:
            guard let str = String(block.block.str) else {
                return nil
            }
            self = .hashtag(str)
        case BLOCK_TEXT:
            guard let str = String(block.block.str) else {
                return nil
            }
            self = .text(str)
        case BLOCK_MENTION_INDEX:
            guard let b = Block(index: Int(block.block.mention_index), tags: tags) else {
                return nil
            }
            self = b
        case BLOCK_URL:
            guard let b = Block(block.block.str) else {
                return nil
            }
            self = b
        case BLOCK_INVOICE:
            guard let b = Block(invoice: block.block.invoice) else {
                return nil
            }
            self = b
        case BLOCK_MENTION_BECH32:
            guard let b = Block(bech32: block.block.mention_bech32) else {
                return nil
            }
            self = b
        default:
            return nil
        }
    }
}
fileprivate extension Block {
    /// Failable initializer for the C-backed type `str_block_t`.
    init?(_ b: str_block_t) {
        guard let str = String(b) else {
            return nil
        }
        
        if let url = URL(string: str) {
            self = .url(url)
        }
        else {
            self = .text(str)
        }
    }
}
fileprivate extension Block {
    /// Failable initializer for a block index and a tag sequence.
    init?(index: Int, tags: TagsSequence? = nil) {
        guard let tags,
              index >= 0,
              index + 1 <= tags.count
        else {
            self = .text("#[\(index)]")
            return
        }
        
        let tag = tags[index]
        
        if let mention = MentionRef.from_tag(tag: tag) {
            self = .mention(.any(mention, index: index))
        }
        else {
            self = .text("#[\(index)]")
        }
    }
}
fileprivate extension Block {
    /// Failable initializer for the C-backed type `invoice_block_t`.
    init?(invoice: invoice_block_t) {
        guard let invstr = String(invoice.invstr) else {
            return nil
        }
        
        guard var b11 = maybe_pointee(invoice.bolt11) else {
            return nil
        }
        
        guard let description = convert_invoice_description(b11: b11) else {
            return nil
        }
        
        let amount: Amount = maybe_pointee(b11.msat).map { .specific(Int64($0.millisatoshis)) } ?? .any
        let payment_hash = Data(bytes: &b11.payment_hash, count: 32)
        let created_at = b11.timestamp
        
        tal_free(invoice.bolt11)
        self = .invoice(Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, payment_hash: payment_hash, created_at: created_at))
    }
}
fileprivate extension Block {
    /// Failable initializer for the C-backed type `mention_bech32_block_t`. This initializer will inspect the
    /// bech32 type code and build the appropriate enum type.
    init?(bech32 b: mention_bech32_block_t) {
        switch b.bech32.type {
        case NOSTR_BECH32_NOTE:
            let note = b.bech32.data.note;
            let note_id = NoteId(Data(bytes: note.event_id, count: 32))
            self = .mention(.any(.note(note_id)))
        case NOSTR_BECH32_NEVENT:
            let nevent = b.bech32.data.nevent;
            let note_id = NoteId(Data(bytes: nevent.event_id, count: 32))
            self = .mention(.any(.note(note_id)))
        case NOSTR_BECH32_NPUB:
            let npub = b.bech32.data.npub
            let pubkey = Pubkey(Data(bytes: npub.pubkey, count: 32))
            self = .mention(.any(.pubkey(pubkey)))
        case NOSTR_BECH32_NSEC:
            let nsec = b.bech32.data.nsec
            let privkey = Privkey(Data(bytes: nsec.nsec, count: 32))
            guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
            self = .mention(.any(.pubkey(pubkey)))
        case NOSTR_BECH32_NPROFILE:
            let nprofile = b.bech32.data.nprofile
            let pubkey = Pubkey(Data(bytes: nprofile.pubkey, count: 32))
            self = .mention(.any(.pubkey(pubkey)))
        case NOSTR_BECH32_NRELAY:
            let nrelay = b.bech32.data.nrelay
            guard let relay_str = String(nrelay.relay) else {
                return nil
            }
            self = .relay(relay_str)
        case NOSTR_BECH32_NADDR:
            // TODO: wtf do I do with this
            guard let naddr = String(b.str) else {
                return nil
            }
            self = .text("nostr:" + naddr)
        default:
            return nil
        }
    }
}
extension Block {
    var asString: String {
        switch self {
        case .mention(let m):
            if let idx = m.index {
                return "#[\(idx)]"
            }
            
            switch m.ref {
            case .pubkey(let pk):    return "nostr:\(pk.npub)"
            case .note(let note_id): return "nostr:\(note_id.bech32)"
            }
        case .relay(let relay):
            return relay
        case .text(let txt):
            return txt
        case .hashtag(let htag):
            return "#" + htag
        case .url(let url):
            return url.absoluteString
        case .invoice(let inv):
            return inv.string
        }
    }
}

extension Blocks {

    /// Returns a language hypothesis represented as an ``NLLanguage`` (determined by ``NLLanguageRecognizer``),
    /// which is the most likely language detected using the combination of blocks. If it cannot determine one, `nil` is returned.
    var languageHypothesis: NLLanguage? {
        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the blocks are in
        // and filter on only the text portions of the content as URLs, hashtags, and anything else confuse the language recognizer.
        let originalOnlyText = blocks.compactMap {
                if case .text(let txt) = $0 {
                    // Replacing right single quotation marks (’) with "typewriter or ASCII apostrophes" (')
                    // as a workaround to get Apple's language recognizer to predict language the correctly.
                    // It is important to add this workaround to get the language right because it wastes users' money to send translation requests.
                    // Until Apple fixes their language model, this workaround will be kept in place.
                    // See https://en.wikipedia.org/wiki/Apostrophe#Unicode for an explanation of the differences between the two characters.
                    //
                    // For example,
                    // "nevent1qqs0wsknetaju06xk39cv8sttd064amkykqalvfue7ydtg3p0lyfksqzyrhxagf6h8l9cjngatumrg60uq22v66qz979pm32v985ek54ndh8gj42wtp"
                    // has the note content "It’s a meme".
                    // Without the character replacement, it is 61% confident that the text is in Turkish (tr) and 8% confident that the text is in English (en),
                    // which is a wildly incorrect hypothesis.
                    // With the character replacement, it is 65% confident that the text is in English (en) and 24% confident that the text is in Turkish (tr), which is more accurate.
                    //
                    // Similarly,
                    // "nevent1qqspjqlln6wvxrqg6kzl2p7gk0rgr5stc7zz5sstl34cxlw55gvtylgpp4mhxue69uhkummn9ekx7mqpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qy28wumn8ghj7un9d3shjtnwdaehgu3wvfnsygpx6655ve67vqlcme9ld7ww73pqx7msclhwzu8lqmkhvuluxnyc7yhf3xut"
                    // has the note content "You’re funner".
                    // Without the character replacement, it is 52% confident that the text is in Norwegian Bokmål (nb) and 41% confident that the text is in English (en).
                    // With the character replacement, it is 93% confident that the text is in English (en) and 4% confident that the text is in Norwegian Bokmål (nb).
                    return txt.replacingOccurrences(of: "’", with: "'")
                }
                else {
                    return nil
                }
            }
            .joined(separator: " ")

        // If there is no text, there's nothing to use to detect language.
        guard !originalOnlyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        return languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key
    }
}
