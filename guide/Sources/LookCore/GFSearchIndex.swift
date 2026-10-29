import Foundation

/// Lume GF's search (Georgs, 29 Oct: typo safe, in his languages, categories too, and "All" that understands what he
/// is looking for): every category, channel, programme, film and series by its words, so a search finds names by
/// whole words, the start of a word ("warr"), words with a mistake ("warrirs"), joined words ("bbc1", channels and
/// categories) and concepts ("somija" is Finland, "hokejs" is hockey). Built off the main thread from a snapshot of
/// the library (GFSmartSearch); a search reads it without locks.
nonisolated final class GFSearchIndex: Sendable {
    enum Kind: UInt8, CaseIterable, Sendable {
        case category, channel, programme, film, series
    }

    /// One searchable thing. `key` is the app's own (an id, or a programme's title), `group` its playlist.
    struct Item: Sendable {
        let kind: Kind
        let group: UInt8
        /// The name's length, for putting the shorter of two equal matches first ("Dune" before "Dune: Part Two").
        let nameLength: UInt16
        let key: String
    }

    /// A match: what it is and how well it matched (higher is better, about 0 to 1.5).
    struct Hit: Equatable, Sendable {
        let kind: Kind
        let group: UInt8
        let key: String
        var score: Double
        /// The typing mistakes forgiven to match it.
        let typos: Int
        let nameLength: UInt16
    }

    let items: [Item]
    /// Every word and concept (concepts start with "#"), by its number.
    private let vocabulary: [String]
    private let numbers: [String: Int32]
    /// Per word: the items with it in their name, and those with it only in their extra words (a programme's
    /// episode line or genre), each ascending.
    private let inName: [[Int32]]
    private let inExtra: [[Int32]]
    /// Words (no concepts) in alphabetical order, for the start of a word, and by length in bytes, for mistakes.
    private let sorted: [Int32]
    private let byLength: [[Int32]]
    /// Each item's name words (by number, noise words and the leading code left out), flat: item `i`'s are
    /// `nameWords[nameStart[i] ..< nameStart[i + 1]]`.
    private let nameWords: [Int32]
    private let nameStart: [Int32]
    let lexicon: GFSearchLexicon

    var count: Int {
        items.count
    }

    fileprivate init(items: [Item], vocabulary: [String], numbers: [String: Int32], inName: [[Int32]],
                     inExtra: [[Int32]], nameWords: [Int32], nameStart: [Int32], lexicon: GFSearchLexicon) {
        self.items = items
        self.vocabulary = vocabulary
        self.numbers = numbers
        self.inName = inName
        self.inExtra = inExtra
        self.nameWords = nameWords
        self.nameStart = nameStart
        self.lexicon = lexicon
        let words = vocabulary.indices.filter { !vocabulary[$0].hasPrefix("#") }
        sorted = words.sorted { vocabulary[$0] < vocabulary[$1] }.map(Int32.init)
        var byLength: [[Int32]] = []
        for number in words {
            let length = vocabulary[number].utf8.count
            while byLength.count <= length {
                byLength.append([])
            }
            byLength[length].append(Int32(number))
        }
        self.byLength = byLength
    }

    // MARK: - Building

    struct Builder {
        private var items: [Item] = []
        private var vocabulary: [String] = []
        private var numbers: [String: Int32] = [:]
        private var inName: [[Int32]] = []
        private var inExtra: [[Int32]] = []
        private var nameWords: [Int32] = []
        private var nameStart: [Int32] = [0]
        private let lexicon: GFSearchLexicon

        init(lexicon: GFSearchLexicon = .standard) {
            self.lexicon = lexicon
        }

        /// Adds a thing by its `name` and, matched a little less strongly, its `extra` words.
        mutating func add(_ kind: Kind, key: String, group: UInt8 = 0, name: String, extra: String? = nil) {
            let item = Int32(items.count)
            let words = GFSearchText.words(name)
            let code = kind == .category || kind == .channel ? GFSearchText.leadingCode(name) : nil
            items.append(Item(kind: kind, group: group, nameLength: UInt16(clamping: name.count), key: key))
            var meaningful = words
            if let code, meaningful.first == code { meaningful.removeFirst() }
            meaningful.removeAll { GFSearchText.noiseWords.contains($0) }
            for word in Set(words) {
                post(word, item, extra: false)
            }
            // "bbc1" for "BBC 1", "skysports" for "Sky Sports": channels and categories, which people type joined
            if kind == .category || kind == .channel {
                for (first, second) in zip(words, words.dropFirst()) {
                    post(first + second, item, extra: false)
                }
            }
            let named = lexicon.concepts(inWords: words, leadingCode: code)
            for concept in named {
                post(concept, item, extra: false)
            }
            if let extra, !extra.isEmpty {
                let extraWords = GFSearchText.words(extra)
                for word in Set(extraWords).subtracting(words) {
                    post(word, item, extra: true)
                }
                for concept in lexicon.concepts(inWords: extraWords).subtracting(named) {
                    post(concept, item, extra: true)
                }
            }
            nameWords += meaningful.map { number(of: $0) }
            nameStart.append(Int32(nameWords.count))
        }

        func build() -> GFSearchIndex {
            GFSearchIndex(items: items, vocabulary: vocabulary, numbers: numbers, inName: inName, inExtra: inExtra,
                          nameWords: nameWords, nameStart: nameStart, lexicon: lexicon)
        }

        private mutating func number(of word: String) -> Int32 {
            if let number = numbers[word] { return number }
            let number = Int32(vocabulary.count)
            vocabulary.append(word)
            numbers[word] = number
            inName.append([])
            inExtra.append([])
            return number
        }

        private mutating func post(_ word: String, _ item: Int32, extra: Bool) {
            let index = Int(number(of: word))
            if extra {
                if inExtra[index].last != item { inExtra[index].append(item) }
            } else if inName[index].last != item {
                inName[index].append(item)
            }
        }
    }

    // MARK: - Searching

    /// How well a word of a name matches a query word.
    private struct WordMatch {
        var quality: Double
        var typos: Int
    }

    /// The matches for `query` among `kinds` (and `groups`, when given), at most `limit` of each kind: those that
    /// needed the fewest mistakes first, then the best. `merged` puts several indexes' matches together.
    func search(_ query: GFSearchQuery, kinds: Set<Kind> = Set(Kind.allCases), groups: Set<UInt8>? = nil,
                limit: Int = 50) -> [Hit] {
        let required = query.parts.filter { !$0.isOptional }
        guard !required.isEmpty, !items.isEmpty else { return [] }
        var table = GFSearchFuzzy.Table()
        // per required part: the items it matched (how well, with how many mistakes) and the words it matched
        let matches = required.map { part in itemMatches(part, table: &table) }
        let optional = query.parts.filter(\.isOptional).map { part in
            Set(itemMatches(part, table: &table, forgiving: false).items.keys)
        }
        // the items every required part matched; failing that (three parts or more), all but one
        var counts: [Int32: Int] = [:]
        for match in matches {
            for item in match.items.keys {
                counts[item, default: 0] += 1
            }
        }
        var wanted = required.count
        var survivors = counts.filter { $0.value == wanted }.map(\.key)
        if survivors.isEmpty, required.count >= 3 {
            wanted -= 1
            survivors = counts.filter { $0.value == wanted }.map(\.key)
        }
        let penalty = wanted < required.count ? 0.6 : 1.0
        let words = matches.map(\.words)
        var hits: [(item: Int32, score: Double, typos: Int)] = []
        for item in survivors where kinds.contains(items[Int(item)].kind)
            && (groups?.contains(items[Int(item)].group) ?? true) {
            var total = 0.0, typos = 0
            for match in matches {
                guard let found = match.items[item] else { continue }
                total += found.quality
                typos += found.typos
            }
            let base = total / Double(required.count)
            let name = nameWords[Int(nameStart[Int(item)]) ..< Int(nameStart[Int(item) + 1])]
            // how much of the name the search covers: "dune" is all of "Dune", a third of "Dune: Part Two"
            let covered = name.count(where: { word in words.contains { $0.contains(word) } })
            let coverage = name.isEmpty ? 1 : min(1, Double(covered) / Double(name.count))
            let first = name.first.map { word in words.first?.contains(word) ?? false } ?? false
            let helpers = optional.count(where: { $0.contains(item) })
            let score = (base * (0.75 + 0.25 * coverage) + (first ? 0.08 : 0) + 0.04 * Double(helpers))
                * penalty * Self.kindWeight(items[Int(item)].kind)
            hits.append((item, score, typos))
        }
        // the fewest mistakes first, then as `isBetter`, so the limit never cuts between equals at random
        hits.sort { lhs, rhs in
            if lhs.typos != rhs.typos { return lhs.typos < rhs.typos }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let left = items[Int(lhs.item)], right = items[Int(rhs.item)]
            if left.nameLength != right.nameLength { return left.nameLength < right.nameLength }
            return left.key < right.key
        }
        var taken: [Kind: Int] = [:]
        var result: [Hit] = []
        for hit in hits {
            let item = items[Int(hit.item)]
            guard taken[item.kind, default: 0] < limit else { continue }
            taken[item.kind, default: 0] += 1
            result.append(Hit(kind: item.kind, group: item.group, key: item.key, score: hit.score, typos: hit.typos,
                              nameLength: item.nameLength))
        }
        return result
    }

    /// Several searches' matches as one list, best first. Matches that needed mistakes are left out when others did
    /// not ("dune" never brings "June"): a mistake is forgiven only where it has to be.
    static func merged(_ lists: [[Hit]]) -> [Hit] {
        let all = lists.flatMap(\.self)
        let fewest = all.map(\.typos).min() ?? 0
        return all.filter { $0.typos == fewest }.sorted(by: isBetter)
    }

    /// Higher score first; between equals the shorter name ("Dune" before "Dune: Part Two"), then by key.
    static func isBetter(_ lhs: Hit, _ rhs: Hit) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.nameLength != rhs.nameLength { return lhs.nameLength < rhs.nameLength }
        return lhs.key < rhs.key
    }

    /// Ties go to what Georgs watches most: live TV first.
    private static func kindWeight(_ kind: Kind) -> Double {
        switch kind {
        case .category: 1.05
        case .channel: 1.03
        case .programme: 1.0
        case .film: 0.99
        case .series: 0.98
        }
    }

    /// An item's best match for one part: its quality and mistakes.
    private struct ItemMatch {
        var quality: Double
        var typos: Int
    }

    /// What one part matched: the items, and the words (for how much of a name it covers).
    private struct PartMatch {
        var items: [Int32: ItemMatch] = [:]
        var words: Set<Int32> = []

        /// Keeps an item's match with the fewest mistakes, then the best: a word still being typed ("spor") keeps its
        /// clean match, never one a guessed concept gave it.
        mutating func offer(_ item: Int32, _ match: ItemMatch) {
            if let old = items[item],
               old.typos < match.typos || (old.typos == match.typos && old.quality >= match.quality) { return }
            items[item] = match
        }
    }

    /// The items `part` matches. A phrase part matches by its concept, or by all its words.
    private func itemMatches(_ part: GFSearchQuery.Part, table: inout GFSearchFuzzy.Table,
                             forgiving: Bool = true) -> PartMatch {
        var result = PartMatch()
        var clean = false
        if part.words.count == 1 {
            let found = wordMatches(part.words[0], table: &table, forgiving: forgiving)
            clean = found.values.contains { $0.typos == 0 }
            for (number, match) in found {
                result.words.insert(number)
                for item in inName[Int(number)] {
                    result.offer(item, ItemMatch(quality: match.quality, typos: match.typos))
                }
                for item in inExtra[Int(number)] {
                    result.offer(item, ItemMatch(quality: match.quality * 0.85, typos: match.typos))
                }
            }
        } else {
            // every word of the phrase, each as a part of its own
            let each = part.words.map { word in
                itemMatches(GFSearchQuery.Part(words: [word], concepts: [], isOptional: false), table: &table,
                            forgiving: forgiving)
            }
            result.words = each.reduce(into: Set<Int32>()) { $0.formUnion($1.words) }
            if let first = each.first {
                for (item, match) in first.items {
                    let rest = each.dropFirst().compactMap { $0.items[item] }
                    guard rest.count == each.count - 1 else { continue }
                    let all = [match] + rest
                    result.offer(item, ItemMatch(quality: all.map(\.quality).reduce(0, +) / Double(all.count),
                                                 typos: all.map(\.typos).reduce(0, +)))
                }
            }
        }
        var concepts = part.concepts
        // a mistyped word no name has or starts may still be a concept ("somja"): never a word in a name ("nets"), nor
        // one still being typed ("spor")
        if forgiving, part.words.count == 1, !clean {
            concepts.formUnion(lexicon.concepts(ofMistypedWord: part.words[0]))
        }
        for concept in concepts {
            guard let number = numbers[concept] else { continue }
            let typos = part.concepts.contains(concept) ? 0 : 1
            for item in inName[Int(number)] {
                result.offer(item, ItemMatch(quality: 0.95, typos: typos))
            }
            for item in inExtra[Int(number)] {
                result.offer(item, ItemMatch(quality: 0.8, typos: typos))
            }
        }
        return result
    }

    /// The words `word` matches: itself, words it starts (the closest 300), and, `forgiving` and when neither
    /// matched, words within its mistakes budget, whole or (from five letters) by their start.
    private func wordMatches(_ word: String, table: inout GFSearchFuzzy.Table,
                             forgiving: Bool) -> [Int32: WordMatch] {
        var found: [Int32: WordMatch] = [:]
        if let exact = numbers[word], !word.hasPrefix("#") { found[exact] = WordMatch(quality: 1, typos: 0) }
        let length = word.utf8.count
        if length >= 2 {
            var starting: [Int32] = []
            var low = 0, high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if vocabulary[Int(sorted[middle])] < word { low = middle + 1 } else { high = middle }
            }
            var index = low
            while index < sorted.count, vocabulary[Int(sorted[index])].hasPrefix(word) {
                if vocabulary[Int(sorted[index])] != word { starting.append(sorted[index]) }
                index += 1
            }
            for number in starting.sorted(by: { vocabulary[Int($0)].utf8.count < vocabulary[Int($1)].utf8.count })
                .prefix(300) {
                let ratio = Double(length) / Double(vocabulary[Int(number)].utf8.count)
                found[number] = WordMatch(quality: 0.72 + 0.2 * ratio, typos: 0)
            }
        }
        // mistakes only for a word that matched nothing as it is: the clean matches would outrank them anyway
        let budget = GFSearchFuzzy.budget(forLength: length)
        guard forgiving, budget > 0, found.isEmpty else { return found }
        for candidateLength in max(1, length - budget) ... (length + budget) where candidateLength < byLength.count {
            guard !Task.isCancelled else { return found }
            for number in byLength[candidateLength] where found[number] == nil {
                guard let mistakes = table.distance(word, vocabulary[Int(number)], limit: budget), mistakes > 0
                else { continue }
                found[number] = WordMatch(quality: mistakes == 1 ? 0.7 : 0.55, typos: mistakes)
            }
        }
        // still typing, with a mistake: "fimlan" for Finland
        if length >= 5, found.isEmpty {
            var word = word
            word.withUTF8 { typed in
                for candidateLength in (length + budget + 1) ..< max(length + budget + 1, byLength.count) {
                    guard !Task.isCancelled else { return }
                    for number in byLength[candidateLength] {
                        var candidate = vocabulary[Int(number)]
                        let mistakes = candidate.withUTF8 { whole in
                            table.distance(typed, UnsafeBufferPointer(rebasing: whole.prefix(length)), limit: 1)
                        }
                        guard let mistakes, mistakes > 0 else { continue }
                        found[number] = WordMatch(quality: 0.5, typos: mistakes)
                    }
                }
            }
        }
        return found
    }
}
