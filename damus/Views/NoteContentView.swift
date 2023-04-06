//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI
import LinkPresentation
import NaturalLanguage

struct Blur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct NoteContentView: View {
    
    let damus_state: DamusState
    let event: NostrEvent
    let show_images: Bool
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions
    let translatable: Bool

    @State var artifacts: NoteArtifacts
    @State var preview: LinkViewRepresentable?
    
    init(damus_state: DamusState, event: NostrEvent, show_images: Bool, size: EventViewKind, artifacts: NoteArtifacts, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.show_images = show_images
        self.size = size
        self.options = options
        self.translatable = damus_state.translations.shouldTranslate(event, state: damus_state)
        self._artifacts = State(initialValue: artifacts)
        self.preview_height = lookup_cached_preview_size(previews: damus_state.previews, evid: event.id)
        self._preview = State(initialValue: load_cached_preview(previews: damus_state.previews, evid: event.id))
        self._artifacts = State(initialValue: render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey))
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var with_padding: Bool {
        return options.contains(.pad_content)
    }
    
    var truncatedText: some View {
        TruncatedText(text: artifacts.content, maxChars: (truncate ? 280 : nil))
            .font(eventviewsize_to_font(size))
    }
    
    var invoicesView: some View {
        InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: artifacts.invoices)
    }

    var translateView: some View {
        TranslateView(damus_state: damus_state, event: event, size: self.size)
    }
    
    var previewView: some View {
        Group {
            if let preview = self.preview, show_images {
                if let preview_height {
                    preview
                        .frame(height: preview_height)
                } else {
                    preview
                }
            } else if let link = artifacts.links.first {
                LinkViewRepresentable(meta: .url(link))
                    .frame(height: 50)
            }
        }
    }
    
    var MainContent: some View {
        VStack(alignment: .leading) {
            if size == .selected {
                if with_padding {
                    SelectableText(attributedString: artifacts.content, size: self.size)
                        .padding(.horizontal)
                } else {
                    SelectableText(attributedString: artifacts.content, size: self.size)
                }
            } else {
                if with_padding {
                    truncatedText
                        .padding(.horizontal)
                } else {
                    truncatedText
                }
            }

            if translatable {
                if with_padding {
                    translateView
                        .padding(.horizontal)
                } else {
                    translateView
                }
            }

            if show_images && artifacts.images.count > 0 {
                ImageCarousel(previews: damus_state.previews, evid: event.id, urls: artifacts.images)
            } else if !show_images && artifacts.images.count > 0 {
                ZStack {
                    ImageCarousel(previews: damus_state.previews, evid: event.id, urls: artifacts.images)
                    Blur()
                        .disabled(true)
                }
                //.cornerRadius(10)
            }
            
            if artifacts.invoices.count > 0 {
                if with_padding {
                    invoicesView
                        .padding(.horizontal)
                } else {
                    invoicesView
                }
            }
            
            if with_padding {
                previewView.padding(.horizontal)
            } else {
                previewView
            }
            
        }
    }
    
    var body: some View {
        MainContent
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(damus_state.keypair.privkey)
                for block in blocks {
                    switch block {
                    case .mention(let m):
                        if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
                            self.artifacts = render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
                        }
                    case .text: return
                    case .hashtag: return
                    case .url: return
                    case .invoice: return
                    }
                }
            }
            .task {
                guard self.preview == nil else {
                    return
                }
                
                if show_images, artifacts.links.count == 1 {
                    let meta = await getMetaData(for: artifacts.links.first!)
                    
                    damus_state.previews.store(evid: self.event.id, preview: meta)
                    guard case .value(let cached) = damus_state.previews.lookup(self.event.id) else {
                        return
                    }
                    let view = LinkViewRepresentable(meta: .linkmeta(cached))
                    
                    self.preview = view
                }

            }
    }
    
    func getMetaData(for url: URL) async -> LPLinkMetadata? {
        // iOS 15 is crashing for some reason
        guard #available(iOS 16, *) else {
            return nil
        }
        
        let provider = LPMetadataProvider()
        
        do {
            return try await provider.startFetchingMetadata(for: url)
        } catch {
            return nil
        }
    }
}

func hashtag_str(_ htag: String) -> AttributedString {
     var attributedString = AttributedString(stringLiteral: "#\(htag)")
     attributedString.link = URL(string: "damus:t:\(htag)")
     attributedString.foregroundColor = DamusColors.purple
     return attributedString
 }

func url_str(_ url: URL) -> AttributedString {
    var attributedString = AttributedString(stringLiteral: url.absoluteString)
    attributedString.link = url
    attributedString.foregroundColor = DamusColors.purple
    return attributedString
 }

func mention_str(_ m: Mention, profiles: Profiles) -> AttributedString {
    switch m.type {
    case .pubkey:
        let pk = m.ref.ref_id
        let profile = profiles.lookup(id: pk)
        let disp = Profile.displayName(profile: profile, pubkey: pk).username
        var attributedString = AttributedString(stringLiteral: "@\(disp)")
        attributedString.link = URL(string: "damus:\(encode_pubkey_uri(m.ref))")
        attributedString.foregroundColor = DamusColors.purple
        return attributedString
    case .event:
        let bevid = bech32_note_id(m.ref.ref_id) ?? m.ref.ref_id
        var attributedString = AttributedString(stringLiteral: "@\(abbrev_pubkey(bevid))")
        attributedString.link = URL(string: "damus:\(encode_event_id_uri(m.ref))")
        attributedString.foregroundColor = DamusColors.purple
        return attributedString
    }
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let content = "hi there ¯\\_(ツ)_/¯ https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        let artifacts = NoteArtifacts(content: AttributedString(stringLiteral: content), images: [], invoices: [], links: [])
        NoteContentView(damus_state: state, event: NostrEvent(content: content, pubkey: "pk"), show_images: true, size: .normal, artifacts: artifacts, options: [])
    }
}

struct NoteArtifacts {
    let content: AttributedString
    let images: [URL]
    let invoices: [Invoice]
    let links: [URL]
    
    static func just_content(_ content: String) -> NoteArtifacts {
        NoteArtifacts(content: AttributedString(stringLiteral: content), images: [], invoices: [], links: [])
    }
}

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    
    return render_blocks(blocks: blocks, profiles: profiles, privkey: privkey)
}

func render_blocks(blocks: [Block], profiles: Profiles, privkey: String?) -> NoteArtifacts {
    var invoices: [Invoice] = []
    var img_urls: [URL] = []
    var link_urls: [URL] = []
    
    let one_note_ref = blocks
        .filter({ $0.is_note_mention })
        .count == 1
    
    var ind: Int = -1
    let txt: AttributedString = blocks.reduce("") { str, block in
        ind = ind + 1
        
        switch block {
        case .mention(let m):
            if m.type == .event && one_note_ref {
                return str
            }
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            var trimmed = txt
            if let prev = blocks[safe: ind-1], case .url(let u) = prev, is_image_url(u) {
                trimmed = " " + trim_prefix(trimmed)
            }
            if let next = blocks[safe: ind+1], case .url(let u) = next, is_image_url(u) {
                trimmed = trim_suffix(trimmed)
            }
            return str + AttributedString(stringLiteral: trimmed)
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            invoices.append(invoice)
            return str
        case .url(let url):
            // Handle Image URLs
            if is_image_url(url) {
                // Append Image
                img_urls.append(url)
                return str
            } else {
                link_urls.append(url)
                return str + url_str(url)
            }
        }
    }

    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices, links: link_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent.lowercased()
    let isUrl = str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif")
    return isUrl
}

func lookup_cached_preview_size(previews: PreviewCache, evid: String) -> CGFloat? {
    guard case .value(let cached) = previews.lookup(evid) else {
        return nil
    }
    
    guard let height = cached.intrinsic_height else {
        return nil
    }
    
    return height
}
    

func load_cached_preview(previews: PreviewCache, evid: String) -> LinkViewRepresentable? {
    guard case .value(let meta) = previews.lookup(evid) else {
        return nil
    }
    
    return LinkViewRepresentable(meta: .linkmeta(meta))
}

struct TruncatedText: View {
    
    let text: AttributedString
    let maxChars: Int?
    
    var body: some View {
        let truncatedAttributedString: AttributedString? = getTruncatedString()
        
        Text(truncatedAttributedString ?? text)
            .fixedSize(horizontal: false, vertical: true)
        
        if truncatedAttributedString != nil {
            Spacer()
            Button(NSLocalizedString("Show more", comment: "Button to show entire note.")) { }
                .allowsHitTesting(false)
        }
    }
    
    func getTruncatedString() -> AttributedString? {
        guard let maxChars = maxChars else { return nil }
        let nsAttributedString = NSAttributedString(text)
        if nsAttributedString.length < maxChars { return nil }
        
        let range = NSRange(location: 0, length: maxChars)
        let truncatedAttributedString = nsAttributedString.attributedSubstring(from: range)
        
        return AttributedString(truncatedAttributedString) + "..."
    }
}


// trim suffix whitespace and newlines
func trim_suffix(_ str: String) -> String {
    return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

// trim prefix whitespace and newlines
func trim_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
}
