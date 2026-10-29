import Foundation

/// How search reads a name or a query before matching (Georgs, 29 Oct: typo safe, and in English, Latvian, Ukrainian
/// and Russian alike): lower case, no accents (Latvian ā š ž, so "zinas" finds "Ziņas"), Cyrillic in Latin letters
/// (so "futbol" finds "Футбол" and the other way round), cut into words at anything that is not a letter or a digit.
nonisolated enum GFSearchText {
    /// `text` as search's words, in order (empty pieces left out).
    static func words(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// `text` lower case, without accents or apostrophes, with Cyrillic spelt in Latin letters.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        result.reserveCapacity(plain.utf8.count)
        for scalar in plain.unicodeScalars {
            if scalar.isASCII {
                if !apostrophes.contains(scalar) { result.unicodeScalars.append(scalar) }
            } else if apostrophes.contains(scalar) {
                continue
            } else if let latin = latin[scalar] {
                result += latin
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// The country or language code a channel or category name starts with, as IPTV lists write them ("FI | Yle TV1",
    /// "UK: BBC One", "[LV] LTV1", "|FI| Yle"): two or three letters followed by a separator. Nil for a name that only
    /// happens to start with a short word ("TV 1000", "AT&T SportsNet", "Sci Fi").
    static func leadingCode(_ name: String) -> String? {
        var rest = Substring(name).drop { opening.contains($0) || $0 == " " }
        let code = rest.prefix { $0.isLetter && $0.isASCII }
        guard (2 ... 3).contains(code.count) else { return nil }
        rest = rest.dropFirst(code.count)
        guard let next = rest.first else { return nil }
        if separators.contains(next) { return code.lowercased() }
        // "FI - Yle", "UK  BBC" (a dash or a second space after one space)
        guard next == " ", let after = rest.dropFirst().first, separators.contains(after) || after == " " else {
            return nil
        }
        return code.lowercased()
    }

    /// Words a channel name carries that say nothing about what it is (picture quality, a backup feed): left out when
    /// search weighs how much of a name a query covers ("bbc one" is all of "BBC One FHD").
    static let noiseWords: Set<String> = [
        "hd", "fhd", "uhd", "sd", "4k", "8k", "hevc", "h265", "h264", "raw", "hdr", "1080p", "720p", "50fps", "60fps",
        "backup", "multi", "vip"
    ]

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "\u{2018}", "\u{02BC}", "`"]
    private static let opening: Set<Character> = ["[", "(", "|", "{", "#", "▪", "•", "★", "☆"]
    private static let separators: Set<Character> = ["|", ":", "-", "–", "—", "]", ")", "}", "/", "•", "▪", "·", "_"]

    /// Cyrillic (Russian, Ukrainian, Belarusian) as people type it in Latin letters, and the few Latin letters that
    /// keep a mark when folded. Folding already turned й into и and ё into е, ї into і.
    private static let latin: [Unicode.Scalar: String] = {
        let pairs: [(Character, String)] = [
            ("а", "a"), ("б", "b"), ("в", "v"), ("г", "g"), ("ґ", "g"), ("д", "d"), ("е", "e"), ("є", "ye"),
            ("ж", "zh"), ("з", "z"), ("и", "i"), ("і", "i"), ("ї", "i"), ("й", "y"), ("к", "k"), ("л", "l"),
            ("м", "m"), ("н", "n"), ("о", "o"), ("п", "p"), ("р", "r"), ("с", "s"), ("т", "t"), ("у", "u"),
            ("ў", "u"), ("ф", "f"), ("х", "h"), ("ц", "ts"), ("ч", "ch"), ("ш", "sh"), ("щ", "shch"), ("ъ", ""),
            ("ы", "y"), ("ь", ""), ("э", "e"), ("ю", "yu"), ("я", "ya"), ("ё", "e"),
            ("ø", "o"), ("æ", "ae"), ("œ", "oe"), ("ß", "ss"), ("ł", "l"), ("đ", "d"), ("ı", "i"), ("þ", "th")
        ]
        var map: [Unicode.Scalar: String] = [:]
        for (letter, spelling) in pairs {
            for scalar in String(letter).unicodeScalars { map[scalar] = spelling }
        }
        return map
    }()
}
