import Foundation

/// A search as typed, read into the parts that must match and the parts that only help (Georgs, 29 Oct: search
/// should understand what he means). "warriors game tonight": "warriors" must match, "game" helps if it does, and
/// "tonight" puts tonight's programmes first. A country or a TV word named in several words ("united kingdom",
/// "premier league") is one part, matched by its concept as well as by its words.
nonisolated struct GFSearchQuery: Equatable, Sendable {
    struct Part: Equatable, Sendable {
        /// The folded words this part is made of (one, or a phrase's).
        var words: [String]
        /// The concepts it names (`GFSearchLexicon`).
        var concepts: Set<String>
        /// Only helps: a little word ("the", "game", "kanāls") or a time word.
        var isOptional: Bool
    }

    /// When a time word asks for programmes ("now", "tonight", "šodien", "завтра").
    enum Time: Equatable, Sendable {
        case now, today, tonight, tomorrow

        /// Whether a programme from `start` to `end` is in this time, seen at `now`. Tonight runs from six in the
        /// evening to four in the morning; until four in the morning, "today" and "tonight" are still the evening
        /// before.
        func contains(start: Date, end: Date, now: Date, calendar: Calendar) -> Bool {
            guard end > now else { return false }
            let midnight = calendar.startOfDay(for: now)
            let today = calendar.component(.hour, from: now) < 4
                ? calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight : midnight
            func hours(_ hours: Int, from day: Date) -> Date {
                calendar.date(byAdding: .hour, value: hours, to: day) ?? day
            }
            switch self {
            case .now:
                return start <= now
            case .today:
                return start < hours(24, from: today)
            case .tonight:
                return end > hours(18, from: today) && start < hours(28, from: today)
            case .tomorrow:
                return start >= hours(24, from: today) && start < hours(48, from: today)
            }
        }
    }

    var parts: [Part]
    var time: Time?

    /// The parts that must match.
    var required: [Part] {
        parts.filter { !$0.isOptional }
    }

    init(parts: [Part], time: Time?) {
        self.parts = parts
        self.time = time
    }

    init(_ text: String, lexicon: GFSearchLexicon = .standard) {
        let words = GFSearchText.words(text)
        var parts: [Part] = []
        var time: Time?
        var index = 0
        while index < words.count {
            // the longest phrase the lexicon knows, from here
            var phrase: (length: Int, concepts: Set<String>)?
            if lexicon.longestPhrase > 1 {
                for length in stride(from: min(lexicon.longestPhrase, words.count - index), through: 2, by: -1) {
                    let joined = words[index ..< index + length].joined(separator: " ")
                    if let concepts = lexicon.phrases[joined] {
                        phrase = (length, concepts)
                        break
                    }
                }
            }
            if let phrase {
                parts.append(Part(words: Array(words[index ..< index + phrase.length]), concepts: phrase.concepts,
                                  isOptional: false))
                index += phrase.length
                continue
            }
            let word = words[index]
            if let named = Self.timeWords[word] {
                time = time ?? named
                parts.append(Part(words: [word], concepts: [], isOptional: true))
            } else if Self.littleWords.contains(word) {
                parts.append(Part(words: [word], concepts: [], isOptional: true))
            } else {
                parts.append(Part(words: [word], concepts: lexicon.concepts(ofQueryWord: word), isOptional: false))
            }
            index += 1
        }
        // only little words ("the", "now"): they are the search, read as they are
        if !parts.isEmpty, parts.allSatisfy(\.isOptional) {
            parts = parts.map { Part(words: $0.words, concepts: lexicon.concepts(ofQueryWord: $0.words[0]),
                                     isOptional: false) }
            time = nil
        }
        self.parts = parts
        self.time = time
    }

    // MARK: - Word lists (folded, as `GFSearchText.words` gives them)

    /// Words that name a time: English, Latvian, Ukrainian and Russian.
    static let timeWords: [String: Time] = {
        let lists: [(Time, [String])] = [
            (.now, ["now", "live", "tagad", "tiešraide", "tiešraidē", "зараз", "сейчас", "наживо"]),
            (.today, ["today", "šodien", "сьогодні", "сегодня"]),
            (.tonight, ["tonight", "šovakar", "ввечері", "вечером", "вечір", "вечер"]),
            (.tomorrow, ["tomorrow", "rīt", "rītdien", "завтра"])
        ]
        var map: [String: Time] = [:]
        for (time, words) in lists {
            for word in words {
                map[GFSearchText.fold(word)] = time
            }
        }
        return map
    }()

    /// Words that only help: they count when a name has them, and never keep a name out.
    static let littleWords: Set<String> = Set([
        "the", "a", "an", "on", "at", "in", "of", "and", "or", "for", "to", "with", "vs", "v", "versus", "tv",
        "channel", "channels", "game", "games", "match", "matches", "watch", "show", "play", "playing", "what", "whats",
        "when", "where", "is", "are", "un", "uz", "ar", "pret", "kas", "kad", "kur", "kanāls", "kanāli", "kanālā",
        "spēle", "spēles", "pārraide", "translācija", "канал", "канали", "каналы", "матч", "гра", "игра", "і", "и",
        "та", "на", "по", "в", "у", "що", "что", "коли", "когда", "де", "где", "дивитися", "смотреть"
    ].map(GFSearchText.fold))
}
