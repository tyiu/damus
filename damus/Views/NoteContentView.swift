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
    let show_time: Bool

    @State var artifacts: NoteArtifacts
    @State var preview: LinkViewRepresentable? = nil
    
    func MainContent() -> some View {
        return VStack(alignment: .leading) {
            
            if size == .selected {
                SelectableText(attributedString: artifacts.content)
                TranslateView(damus_state: damus_state, event: event)
            } else {
                Text(artifacts.content)
                    .font(eventviewsize_to_font(size))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if show_images && artifacts.images.count > 0 {
                ImageCarousel(urls: artifacts.images)
            } else if !show_images && artifacts.images.count > 0 {
                ZStack {
                    ImageCarousel(urls: artifacts.images)
                    Blur()
                        .disabled(true)
                }
                .cornerRadius(10)
            }
            if artifacts.invoices.count > 0 {
                InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: artifacts.invoices)
            }
            
            if let preview = self.preview, show_images {
                preview
            } else {
                ForEach(artifacts.links, id:\.self) { link in
                    if let url = link {
                        LinkViewRepresentable(meta: .url(url))
                            .frame(height: 50)
                    }
                }
            }

            if show_time {
                Text(verbatim: Date.init(timeIntervalSince1970: Double(event.created_at)).formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .frame(alignment: .trailing)
                    .padding([.top], 2)
            }
        }
    }
    
    var body: some View {
        MainContent()
            .onAppear() {
                self.artifacts = render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
            }
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
                if let preview = damus_state.previews.lookup(self.event.id) {
                    switch preview {
                    case .value(let view):
                        self.preview = view
                    case .failed:
                        // don't try to refetch meta if we've failed
                        return
                    }
                }
                
                if show_images, artifacts.links.count == 1 {
                    let meta = await getMetaData(for: artifacts.links.first!)
                    
                    let view = meta.map { LinkViewRepresentable(meta: .linkmeta($0)) }
                    damus_state.previews.store(evid: self.event.id, preview: view)
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

func hashtag_str(_ htag: String, ev: NostrEvent) -> AttributedString {
    var attributedString = AttributedString(stringLiteral: "#\(htag)")
    attributedString.link = URL(string: "nostr:t:\(htag)")

    if ev.known_kind == .dm {
        attributedString.underlineStyle = .single
    } else {
        attributedString.foregroundColor = .purple
    }

    return attributedString
 }

func url_str(_ url: URL, ev: NostrEvent) -> AttributedString {
    var attributedString = AttributedString(stringLiteral: url.absoluteString)
    attributedString.link = url

    if ev.known_kind == .dm {
        attributedString.underlineStyle = .single
    } else {
        attributedString.foregroundColor = .purple
    }

    return attributedString
 }

func mention_str(_ m: Mention, profiles: Profiles, ev: NostrEvent) -> AttributedString {
    var attributedString: AttributedString
    switch m.type {
    case .pubkey:
        let pk = m.ref.ref_id
        let profile = profiles.lookup(id: pk)
        let disp = Profile.displayName(profile: profile, pubkey: pk)
        attributedString = AttributedString(stringLiteral: "@\(disp)")
        attributedString.link = URL(string: "nostr:\(encode_pubkey_uri(m.ref))")
    case .event:
        let bevid = bech32_note_id(m.ref.ref_id) ?? m.ref.ref_id
        attributedString = AttributedString(stringLiteral: "@\(abbrev_pubkey(bevid))")
        attributedString.link = URL(string: "nostr:\(encode_event_id_uri(m.ref))")
    }

    if ev.known_kind == .dm {
        attributedString.underlineStyle = .single
    } else {
        attributedString.foregroundColor = .purple
    }

    return attributedString
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let content = "hi there ¯\\_(ツ)_/¯ https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        let artifacts = NoteArtifacts(content: AttributedString(stringLiteral: content), images: [], invoices: [], links: [])
        NoteContentView(damus_state: state, event: NostrEvent(content: content, pubkey: "pk"), show_images: true, size: .normal, show_time: false, artifacts: artifacts)
    }
}

extension View {
    func translate_button_style() -> some View {
        return self
            .font(.footnote)
            .contentShape(Rectangle())
            .padding([.top, .bottom], 10)
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
    return render_blocks(blocks: blocks, profiles: profiles, privkey: privkey, ev: ev)
}

func render_blocks(blocks: [Block], profiles: Profiles, privkey: String?, ev: NostrEvent) -> NoteArtifacts {
    var invoices: [Invoice] = []
    var img_urls: [URL] = []
    var link_urls: [URL] = []
    let txt: AttributedString = blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            return str + mention_str(m, profiles: profiles, ev: ev)
        case .text(let txt):
            return str + AttributedString(stringLiteral: txt)
        case .hashtag(let htag):
            return str + hashtag_str(htag, ev: ev)
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
                return str + url_str(url, ev: ev)
            }
        }
    }

    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices, links: link_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent.lowercased()
    return str.hasSuffix("png") || str.hasSuffix("jpg") || str.hasSuffix("jpeg") || str.hasSuffix("gif")
}

