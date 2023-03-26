//
//  UserAutocompletion.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import SwiftUI

struct SearchedUser: Identifiable {
    let petname: String?
    let profile: Profile?
    let pubkey: String
    
    var id: String {
        return pubkey
    }
}

struct UserSearch: View {
    let damus_state: DamusState
    let search: String

    @Binding var post: NSMutableAttributedString
    @Binding var cursor: Int
    
    var users: [SearchedUser] {
        guard let contacts = damus_state.contacts.event else {
            return search_profiles(profiles: damus_state.profiles, search: search)
        }
        
        return search_users_for_autocomplete(profiles: damus_state.profiles, tags: contacts.tags, search: search)
    }
    
    func on_user_tapped(user: SearchedUser) {
        guard let pk = bech32_pubkey(user.pubkey) else {
            return
        }

        // Remove all characters after the '@' and before the cursor
        let newCursor = removeCharactersAfterAtSymbol()

        // Create and append the user tag
        let tagAttributedString = createUserTag(for: user, with: pk)
        insertUserTag(tagAttributedString, cursor: newCursor)

        cursor = newCursor
    }
    
    private func removeCharactersAfterAtSymbol() -> Int {
        let newCursor = cursor

        guard newCursor > 0 else {
            return 0
        }

        var atSymbolOffset = newCursor
        while atSymbolOffset > 0 && post.string[post.string.index(post.string.startIndex, offsetBy: atSymbolOffset - 1)] != "@" {
            atSymbolOffset -= 1
        }

        var endOfWordOffset = newCursor
        while endOfWordOffset < post.string.count && !post.string[post.string.index(post.string.startIndex, offsetBy: endOfWordOffset)].isWhitespace {
            endOfWordOffset += 1
        }

        post.deleteCharacters(in: NSRange(location: atSymbolOffset - 1, length: endOfWordOffset - atSymbolOffset + 1))

        return atSymbolOffset - 1
    }

    private func createUserTag(for user: SearchedUser, with pk: String) -> NSMutableAttributedString {
        let name = Profile.displayName(profile: user.profile, pubkey: pk).username
        let tagString = "\u{200B}@\(name)\u{200B} "

        let tagAttributedString = NSMutableAttributedString(string: tagString,
                                   attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0),
                                                NSAttributedString.Key.link: "@\(pk)"])
        tagAttributedString.removeAttribute(.link, range: NSRange(location: 0, length: 1))
        tagAttributedString.removeAttribute(.link, range: NSRange(location: tagAttributedString.length - 2, length: 2))
        tagAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.label], range: NSRange(location: 0, length: 1))
        tagAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.label], range: NSRange(location: tagAttributedString.length - 2, length: 2))
        
        return tagAttributedString
    }

    private func insertUserTag(_ tagAttributedString: NSMutableAttributedString, cursor: Int) {
        let mutableString = NSMutableAttributedString()
        mutableString.append(post)
        mutableString.insert(tagAttributedString, at: cursor)
        post = mutableString
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(users) { user in
                    UserView(damus_state: damus_state, pubkey: user.pubkey)
                        .onTapGesture {
                            on_user_tapped(user: user)
                        }
                }
            }
        }
    }
}

struct UserSearch_Previews: PreviewProvider {
    static let search: String = "jb55"
    @State static var post: NSMutableAttributedString = NSMutableAttributedString(string: "some @jb55")
    @State static var cursor: Int = 0
    
    static var previews: some View {
        UserSearch(damus_state: test_damus_state(), search: search, post: $post, cursor: $cursor)
    }
}


func search_users_for_autocomplete(profiles: Profiles, tags: [[String]], search _search: String) -> [SearchedUser] {
    var seen_user = Set<String>()
    let search = _search.lowercased()
    
    var matches = tags.reduce(into: Array<SearchedUser>()) { arr, tag in
        guard tag.count >= 2 && tag[0] == "p" else {
            return
        }
        
        let pubkey = tag[1]
        guard !seen_user.contains(pubkey) else {
            return
        }
        seen_user.insert(pubkey)
        
        var petname: String? = nil
        if tag.count >= 4 {
            petname = tag[3]
        }
        
        let profile = profiles.lookup(id: pubkey)
        
        guard ((petname?.lowercased().hasPrefix(search) ?? false) ||
            (profile?.name?.lowercased().hasPrefix(search) ?? false) ||
            (profile?.display_name?.lowercased().hasPrefix(search) ?? false)) else {
            return
        }
        
        let searched_user = SearchedUser(petname: petname, profile: profile, pubkey: pubkey)
        arr.append(searched_user)
    }
    
    // search profile cache as well
    for tup in profiles.profiles.enumerated() {
        let pk = tup.element.key
        let prof = tup.element.value.profile
        
        guard !seen_user.contains(pk) else {
            continue
        }
        
        if let match = profile_search_matches(profiles: profiles, profile: prof, pubkey: pk, search: search) {
            matches.append(match)
        }
    }
    
    return matches
}
