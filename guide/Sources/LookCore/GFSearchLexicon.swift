import Foundation

/// What search knows about words beyond their letters (Georgs, 29 Oct: searching "finland" should show the Finland
/// category, in English, Latvian, Ukrainian and Russian alike): every country by its name in those languages and its
/// code ("Somija", "Фінляндія", "FI"), the main languages ("Finnish", "somu"), and the words TV is sorted by (sport,
/// football, news, kids…). A name and a query that name the same thing share a concept, whatever their language.
nonisolated struct GFSearchLexicon: Sendable {
    /// A word or a phrase (folded words joined by one space) → the concepts it names.
    let phrases: [String: Set<String>]
    /// Stems: a word starting with one names its concepts ("futbol" in "futbols", "футбольний"), by their first four
    /// letters.
    let stems: [String: [(stem: String, concepts: Set<String>)]]
    /// A code a name starts with ("FI | Yle", "UK: BBC One", "GER | Sky") → its country's concept.
    let codes: [String: String]
    /// The most words in a phrase.
    let longestPhrase: Int

    /// The languages country and language names are read in: English, Latvian, Ukrainian, Russian and the device's own.
    static let languages = ["en", "lv", "uk", "ru"]

    static let standard = GFSearchLexicon(languages: languages + [Locale.current.language.languageCode?.identifier]
        .compactMap(\.self))

    init(languages: [String]) {
        var phrases: [String: Set<String>] = [:]
        var stems: [String: [(stem: String, concepts: Set<String>)]] = [:]
        func add(_ name: String, _ concept: String) {
            let words = GFSearchText.words(name)
            guard !words.isEmpty else { return }
            phrases[words.joined(separator: " "), default: []].insert(concept)
        }
        let locales = Set(languages).sorted().map(Locale.init(identifier:))
        for code in Self.countryCodes {
            for locale in locales {
                if let name = locale.localizedString(forRegionCode: code) { add(name, "#" + code.lowercased()) }
            }
        }
        for (code, region) in Self.languageRegions {
            for locale in locales {
                if let name = locale.localizedString(forLanguageCode: code) { add(name, "#" + region) }
            }
        }
        for (name, region) in Self.countryAliases {
            add(name, "#" + region)
        }
        for (concept, words) in Self.tvWords {
            for word in words {
                if word.hasSuffix("*") {
                    let stem = GFSearchText.fold(String(word.dropLast()))
                    stems[String(stem.prefix(4)), default: []].append((stem, ["#" + concept]))
                } else {
                    add(word, "#" + concept)
                }
            }
        }
        var codes: [String: String] = [:]
        for code in Self.countryCodes {
            codes[code.lowercased()] = "#" + code.lowercased()
        }
        for (code, region) in Self.codeAliases {
            codes[code] = "#" + region
        }
        self.phrases = phrases
        self.stems = stems
        self.codes = codes
        longestPhrase = phrases.keys.map { $0.split(separator: " ").count }.max() ?? 1
    }

    /// The concepts one folded word names by itself: as a whole word, or by a stem it starts with.
    func concepts(ofWord word: String) -> Set<String> {
        var found = phrases[word] ?? []
        if word.utf8.count >= 4 {
            for entry in stems[String(word.prefix(4))] ?? [] where word.hasPrefix(entry.stem) {
                found.formUnion(entry.concepts)
            }
        }
        return found
    }

    /// Every concept a name's folded `words` name, phrases included ("united kingdom"), and the country of the code
    /// it starts with (`leadingCode`, from `GFSearchText.leadingCode`).
    func concepts(inWords words: [String], leadingCode: String? = nil) -> Set<String> {
        var found: Set<String> = []
        if let leadingCode, let concept = codes[leadingCode] { found.insert(concept) }
        for start in words.indices {
            found.formUnion(concepts(ofWord: words[start]))
            var phrase = words[start]
            for end in words.indices.dropFirst(start + 1).prefix(longestPhrase - 1) {
                phrase += " " + words[end]
                if let concepts = phrases[phrase] { found.formUnion(concepts) }
            }
        }
        return found
    }

    /// The concepts a query word means: as a word, by a stem, or as a country code ("fi", "uk").
    func concepts(ofQueryWord word: String) -> Set<String> {
        var found = concepts(ofWord: word)
        if (2 ... 3).contains(word.utf8.count), let concept = codes[word] { found.insert(concept) }
        return found
    }

    /// The concepts a mistyped query word may mean (`GFSearchFuzzy.budget`): "somja" is still Finland. Search asks only
    /// for a word no name has, so "nets" (the Brooklyn Nets) never turns into "news".
    func concepts(ofMistypedWord word: String) -> Set<String> {
        let budget = GFSearchFuzzy.budget(forLength: word.utf8.count)
        guard budget > 0 else { return [] }
        var found: Set<String> = []
        var table = GFSearchFuzzy.Table()
        for (phrase, concepts) in phrases where !phrase.contains(" ") {
            if table.distance(word, phrase, limit: budget) != nil { found.formUnion(concepts) }
        }
        return found
    }

    // MARK: - Word lists

    /// Every country's two-letter code (Locale's list also holds continents and other areas by number).
    static let countryCodes: [String] = Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }

    /// Languages whose name points at one country ("Finnish" → Finland; English → the United Kingdom, where Georgs
    /// lives). Languages spoken across many countries (Spanish, Arabic…) are left out.
    static let languageRegions: [(String, String)] = [
        ("fi", "fi"), ("lv", "lv"), ("lt", "lt"), ("et", "ee"), ("uk", "ua"), ("ru", "ru"), ("be", "by"),
        ("pl", "pl"), ("de", "de"), ("it", "it"), ("nl", "nl"), ("sv", "se"), ("nb", "no"), ("no", "no"),
        ("da", "dk"), ("is", "is"), ("en", "gb"), ("tr", "tr"), ("el", "gr"), ("hu", "hu"), ("cs", "cz"),
        ("sk", "sk"), ("ro", "ro"), ("bg", "bg"), ("hr", "hr"), ("sr", "rs"), ("sl", "si"), ("he", "il"),
        ("hi", "in"), ("ja", "jp"), ("ko", "kr"), ("ka", "ge"), ("hy", "am"), ("az", "az"), ("kk", "kz")
    ]

    /// Other names IPTV lists and people use for a country.
    static let countryAliases: [(String, String)] = [
        ("UK", "gb"), ("Great Britain", "gb"), ("Britain", "gb"), ("England", "gb"), ("Scotland", "gb"),
        ("Wales", "gb"), ("Northern Ireland", "gb"), ("Anglija", "gb"), ("Skotija", "gb"), ("Англія", "gb"),
        ("Англия", "gb"), ("Шотландія", "gb"), ("Шотландия", "gb"), ("USA", "us"), ("America", "us"),
        ("Amerika", "us"), ("Америка", "us"), ("Holland", "nl"), ("Turkey", "tr"), ("Czech Republic", "cz"),
        ("Korea", "kr"), ("Baltkrievija", "by"), ("Ex Yu", "rs")
    ]

    /// Codes in names that are not ISO country codes, or not the country they read as.
    static let codeAliases: [(String, String)] = [
        ("uk", "gb"), ("en", "gb"), ("eng", "gb"), ("gbr", "gb"), ("sco", "gb"), ("usa", "us"), ("fin", "fi"),
        ("ger", "de"), ("deu", "de"), ("ita", "it"), ("swe", "se"), ("nor", "no"), ("den", "dk"), ("dnk", "dk"),
        ("pol", "pl"), ("rus", "ru"), ("ukr", "ua"), ("can", "ca"), ("esp", "es"), ("spa", "es"), ("fra", "fr"),
        ("por", "pt"), ("ned", "nl"), ("nld", "nl"), ("tur", "tr"), ("lat", "lv"), ("lva", "lv"), ("ltu", "lt"),
        ("est", "ee"), ("aut", "at"), ("sui", "ch"), ("che", "ch"), ("cze", "cz"), ("svk", "sk"), ("hun", "hu"),
        ("rom", "ro"), ("rou", "ro"), ("bul", "bg"), ("cro", "hr"), ("hrv", "hr"), ("srb", "rs"), ("gre", "gr"),
        ("grc", "gr"), ("isr", "il"), ("ind", "in"), ("chn", "cn"), ("jpn", "jp"), ("kor", "kr"), ("bra", "br"),
        ("arg", "ar"), ("mex", "mx"), ("aus", "au"), ("irl", "ie"), ("bel", "be"), ("ua", "ua")
    ]

    /// The words TV is sorted by, in English, Latvian, Ukrainian and Russian. A trailing `*` makes a stem (it matches
    /// every word starting with it: Latvian, Ukrainian and Russian change a word's ending).
    static let tvWords: [(String, [String])] = [
        ("sport", ["sport", "sports", "sporta", "sportam", "sportiv*", "спорт", "спортив*", "sportu"]),
        ("football", ["football", "soccer", "futbol*", "футбол*", "fussball", "jalkapallo", "voetbal", "calcio",
                      "premier league", "champions league", "la liga", "bundesliga", "serie a"]),
        ("hockey", ["hockey", "hokej*", "хокей", "хокею", "хоккей*", "nhl", "khl", "jääkiekko"]),
        ("basketball", ["basketball", "basketbol*", "баскетбол*", "nba", "euroleague", "basket"]),
        ("tennis", ["tennis", "tenis*", "теніс*", "теннис*", "atp", "wta", "wimbledon"]),
        ("motorsport", ["motorsport", "motorsports", "formula 1", "formula1", "f1", "motogp", "nascar", "rally",
                        "autosport*", "автоспорт*", "rallijs"]),
        ("boxing", ["boxing", "bokss", "boksa", "бокс", "ufc", "mma", "fight", "fights", "wrestling", "wwe"]),
        ("golf", ["golf", "golfs", "гольф"]),
        ("news", ["news", "ziņas", "ziņu", "jaunumi", "новини", "новости", "nyheter", "uutiset", "nachrichten"]),
        ("kids", ["kids", "kid", "children", "childrens", "cartoon", "cartoons", "bērnu", "bērniem", "bērni",
                  "multfilm*", "мультфільм*", "мультфильм*", "дитяч*", "детск*", "lapsille"]),
        ("films", ["film", "films", "movie", "movies", "cinema", "kino", "filma", "filmas", "фільм*", "фильм*",
                   "кіно", "кино", "elokuvat"]),
        ("series", ["series", "seriāli", "seriāls", "serial*", "серіал*", "сериал*", "sarjat"]),
        ("music", ["music", "mūzika", "mūzikas", "музика", "музыка", "музик*", "музык*", "musiikki", "mtv"]),
        ("documentary", ["documentary", "documentaries", "docs", "dokument*", "документал*", "dokumentti*"]),
        ("entertainment", ["entertainment", "izklaide", "izklaides", "розважальн*", "развлекательн*", "viihde"]),
        ("nature", ["nature", "wildlife", "daba", "dabas", "природ*", "animal planet", "nat geo wild"])
    ]
}
