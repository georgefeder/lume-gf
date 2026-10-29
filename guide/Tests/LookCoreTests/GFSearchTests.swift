import Foundation
@testable import LookCore
import Testing

/// Lume GF's search (Georgs, 29 Oct: typo safe, in English, Latvian, Ukrainian and Russian, categories too, and an
/// "All" that understands what he is after).
struct GFSearchTextTests {
    @Test func `accents and case go, so Latvian is found without its marks`() {
        #expect(GFSearchText.words("LTV Ziņas HD") == ["ltv", "zinas", "hd"])
        #expect(GFSearchText.words("Šodien ĀRĀ") == ["sodien", "ara"])
    }

    @Test func `Cyrillic is spelt in Latin letters`() {
        #expect(GFSearchText.words("Футбол") == ["futbol"])
        #expect(GFSearchText.words("Новини") == ["novini"])
        #expect(GFSearchText.fold("Хокей") == "hokei")
        #expect(GFSearchText.words("Шахтар Донецьк") == ["shahtar", "donetsk"])
    }

    @Test func `apostrophes join a word, other marks split words`() {
        #expect(GFSearchText.words("Dragons' Den") == ["dragons", "den"])
        #expect(GFSearchText.words("Grey’s Anatomy") == ["greys", "anatomy"])
        #expect(GFSearchText.words("🔴 LIVE 20:30 · Arsenal v Chelsea")
            == ["live", "20", "30", "arsenal", "v", "chelsea"])
    }

    @Test func `a country code at the start of a name is read, a short first word is not`() {
        #expect(GFSearchText.leadingCode("FI | Yle TV1") == "fi")
        #expect(GFSearchText.leadingCode("UK: BBC One") == "uk")
        #expect(GFSearchText.leadingCode("[LV] LTV1") == "lv")
        #expect(GFSearchText.leadingCode("|FI| Yle") == "fi")
        #expect(GFSearchText.leadingCode("FI - Yle") == "fi")
        #expect(GFSearchText.leadingCode("GER | Sky") == "ger")
        for name in ["TV 1000", "AT&T SportsNet", "Sci Fi", "BBC One", "FINLAND", "TV3 Latvia", ""] {
            #expect(GFSearchText.leadingCode(name) == nil, "\(name)")
        }
    }
}

struct GFSearchFuzzyTests {
    @Test func `one mistake up to seven letters, two from eight, none in short words`() {
        #expect(GFSearchFuzzy.budget(forLength: 3) == 0)
        #expect(GFSearchFuzzy.budget(forLength: 4) == 1)
        #expect(GFSearchFuzzy.budget(forLength: 7) == 1)
        #expect(GFSearchFuzzy.budget(forLength: 8) == 2)
    }

    @Test func `a letter missing, extra, wrong or swapped is one mistake`() {
        #expect(GFSearchFuzzy.distance("warriors", "warrirs", limit: 2) == 1)
        #expect(GFSearchFuzzy.distance("finland", "finlnd", limit: 1) == 1)
        #expect(GFSearchFuzzy.distance("show", "sohw", limit: 1) == 1)
        #expect(GFSearchFuzzy.distance("lakers", "lakers", limit: 0) == 0)
        #expect(GFSearchFuzzy.distance("cnn", "cnbc", limit: 1) == nil)
        #expect(GFSearchFuzzy.distance("", "ab", limit: 2) == 2)
    }

    @Test func `the kept table gives the same answers for words of any length, in any order`() {
        var table = GFSearchFuzzy.Table()
        #expect(table.distance("championship", "champoinship", limit: 2) == 1)
        #expect(table.distance("dune", "june", limit: 1) == 1)
        #expect(table.distance("basketball", "baskteball", limit: 2) == 1)
        #expect(table.distance("nets", "news", limit: 1) == 1)
        #expect(table.distance("formula", "fromula", limit: 1) == 1)
    }
}

struct GFSearchLexiconTests {
    private let lexicon = GFSearchLexicon.standard

    @Test func `a country is the same in English, Latvian, Ukrainian and Russian`() {
        for name in ["Finland", "Somija", "Фінляндія", "Финляндия"] {
            #expect(lexicon.concepts(ofQueryWord: GFSearchText.fold(name)).contains("#fi"), "\(name)")
        }
        #expect(lexicon.concepts(ofQueryWord: "latvija").contains("#lv"))
        #expect(lexicon.concepts(ofQueryWord: "uk").contains("#gb"))
        #expect(lexicon.concepts(ofQueryWord: "england").contains("#gb"))
        #expect(lexicon.concepts(ofQueryWord: "finnish").contains("#fi"))
    }

    @Test func `TV words in any of the four languages, whatever their ending`() {
        #expect(lexicon.concepts(ofQueryWord: "hokejs").contains("#hockey"))
        #expect(lexicon.concepts(ofQueryWord: GFSearchText.fold("футбольний")).contains("#football"))
        #expect(lexicon.concepts(ofQueryWord: "zinas").contains("#news"))
        #expect(lexicon.concepts(ofQueryWord: GFSearchText.fold("новости")).contains("#news"))
    }

    @Test func `a name's concepts: its words, its phrases and the code it starts with`() {
        let named = lexicon.concepts(inWords: GFSearchText.words("FI | Yle TV1"), leadingCode: "fi")
        #expect(named.contains("#fi"))
        #expect(!lexicon.concepts(inWords: GFSearchText.words("Sci Fi HD")).contains("#fi"))
        #expect(lexicon.concepts(inWords: GFSearchText.words("United Kingdom")).contains("#gb"))
        #expect(lexicon.concepts(inWords: ["premier", "league", "live"]).contains("#football"))
    }

    @Test func `a mistyped country is still found`() {
        #expect(lexicon.concepts(ofMistypedWord: "somja").contains("#fi"))
        #expect(lexicon.concepts(ofMistypedWord: "uk").isEmpty) // no mistakes in short words
    }
}

struct GFSearchQueryTests {
    @Test func `little words only help, time words ask for a time`() {
        let query = GFSearchQuery("Warriors game tonight")
        #expect(query.parts.map(\.words) == [["warriors"], ["game"], ["tonight"]])
        #expect(query.parts.map(\.isOptional) == [false, true, true])
        #expect(query.time == .tonight)
        #expect(GFSearchQuery("futbols šodien").time == .today)
        #expect(GFSearchQuery("хокей завтра").time == .tomorrow)
    }

    @Test func `a phrase the lexicon knows is one part`() {
        let query = GFSearchQuery("united kingdom")
        #expect(query.parts.count == 1)
        #expect(query.parts.first?.concepts.contains("#gb") == true)
        #expect(GFSearchQuery("Premier League").parts.first?.concepts.contains("#football") == true)
    }

    @Test func `a search of only little words is read as it is`() {
        let query = GFSearchQuery("tonight")
        #expect(query.parts.map(\.isOptional) == [false])
        #expect(query.time == nil)
    }

    @Test func `tonight runs from six in the evening to four in the morning`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Riga"))
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 15)))
        func at(_ hours: Double) -> Date {
            afternoon.addingTimeInterval(hours * 3600)
        }
        let tonight = GFSearchQuery.Time.tonight
        #expect(tonight.contains(start: at(5), end: at(6), now: afternoon, calendar: calendar)) // 20:00
        #expect(tonight.contains(start: at(11), end: at(12), now: afternoon, calendar: calendar)) // 02:00
        #expect(!tonight.contains(start: at(19), end: at(20), now: afternoon, calendar: calendar)) // tomorrow 10:00
        #expect(!tonight.contains(start: at(1), end: at(2), now: afternoon, calendar: calendar)) // 16:00
        #expect(GFSearchQuery.Time.now.contains(start: at(-1), end: at(1), now: afternoon, calendar: calendar))
        #expect(!GFSearchQuery.Time.now.contains(start: at(1), end: at(2), now: afternoon, calendar: calendar))
    }
}

struct GFSearchIndexTests {
    private let index: GFSearchIndex = {
        var builder = GFSearchIndex.Builder()
        builder.add(.category, key: "cat-fi", name: "FI | Finland")
        builder.add(.category, key: "cat-lv", name: "Latvia")
        builder.add(.category, key: "cat-sport", name: "UK | Sports")
        builder.add(.channel, key: "yle", name: "FI | Yle TV1 FHD")
        builder.add(.channel, key: "scifi", name: "Sci Fi HD")
        builder.add(.channel, key: "bbc1", name: "BBC One FHD")
        builder.add(.channel, key: "skysports", name: "Sky Sports Main Event FHD")
        builder.add(.channel, key: "skynews", name: "Sky News HD")
        builder.add(.channel, key: "cnbc", name: "CNBC HD")
        builder.add(.channel, key: "ltv", name: "LTV1 Ziņas")
        builder.add(.channel, key: "hockey", name: "Viaplay Hockey HD")
        builder.add(.programme, key: "nba", name: "NBA Basketball",
                    extra: "Golden State Warriors at Los Angeles Lakers")
        builder.add(.programme, key: "nets", name: "Brooklyn Nets Basketball")
        builder.add(.programme, key: "june", name: "June Brides")
        builder.add(.film, key: "dune", name: "Dune")
        builder.add(.film, key: "dune2", name: "Dune: Part Two")
        builder.add(.series, key: "warrior", name: "Warrior")
        return builder.build()
    }()

    private func keys(_ text: String) -> [String] {
        GFSearchIndex.merged([index.search(GFSearchQuery(text))]).map(\.key)
    }

    @Test func `a country finds its category first, and channels that start with its code`() {
        for text in ["finland", "Somija", "Фінляндія", "finlnd"] {
            let found = keys(text)
            #expect(found.first == "cat-fi", "\(text): \(found)")
            #expect(found.contains("yle"), "\(text): \(found)")
            #expect(!found.contains("scifi"), "\(text): \(found)")
        }
        #expect(keys("latvija").first == "cat-lv")
        #expect(keys("FI").first == "cat-fi") // "Sci Fi" has the word, so it is found as well
    }

    @Test func `the closest name comes first, and a mistake is forgiven only where needed`() {
        #expect(keys("dune") == ["dune", "dune2"]) // no "June Brides"
        #expect(keys("warriors") == ["nba"]) // the exact word in the game's line, not the series "Warrior"
        #expect(keys("warrirs") == ["nba"])
        #expect(Set(keys("warr")) == ["nba", "warrior"])
        #expect(keys("nets") == ["nets"]) // never "news"
    }

    @Test func `short words are never guessed`() {
        #expect(keys("cnn").isEmpty)
        #expect(keys("cnbc") == ["cnbc"])
    }

    @Test func `joined words, accents and TV words`() {
        #expect(keys("skysports").first == "skysports")
        #expect(keys("zinas") == ["ltv", "skynews"]) // the word itself first, then news in other words
        #expect(keys("ziņas") == ["ltv", "skynews"])
        #expect(keys("hokejs") == ["hockey"])
        #expect(keys("sky sprts").first == "skysports")
    }

    @Test func `a category beats a channel that only has the word`() {
        #expect(keys("sports").first == "cat-sport")
    }

    @Test func `little words help, and with three words or more one may be missing`() {
        #expect(keys("warriors game") == ["nba"])
        #expect(keys("golden lakers xyzzy") == ["nba"])
        #expect(keys("golden xyzzy").isEmpty)
    }

    @Test func `only the kinds asked for, at most the limit of each`() {
        let films = index.search(GFSearchQuery("dune"), kinds: [.film], limit: 1)
        #expect(films.map(\.key) == ["dune"])
        #expect(index.search(GFSearchQuery("dune"), kinds: [.channel]).isEmpty)
    }

    @Test func `matches from several indexes keep only the fewest mistakes`() {
        var builder = GFSearchIndex.Builder()
        builder.add(.programme, key: "tune", name: "Tune In")
        let other = builder.build()
        let merged = GFSearchIndex.merged([index.search(GFSearchQuery("dune")), other.search(GFSearchQuery("dune"))])
        #expect(merged.map(\.key) == ["dune", "dune2"])
    }
}

struct GFSearchLayoutTests {
    private typealias Row = GFSearchLayout.Row<String>

    @Test func `All leads with the best few of any kind, then each kind, the best kind first`() {
        let rows = [Row(kind: .film, id: "dune", score: 1.2), Row(kind: .category, id: "fi", score: 0.9),
                    Row(kind: .channel, id: "yle", score: 1.1), Row(kind: .channel, id: "mtv", score: 0.5),
                    Row(kind: .film, id: "dune2", score: 0.8), Row(kind: .series, id: "x", score: 0.3)]
        let sections = GFSearchLayout.sections(rows, allKinds: true)
        #expect(sections.map(\.kind) == [nil, .film, .channel, .series])
        #expect(sections.map(\.ids) == [["dune", "yle", "fi"], ["dune2"], ["mtv"], ["x"]])
    }

    @Test func `no Top Results for one kind, a filter or a handful`() {
        let channels = [Row(kind: .channel, id: "a", score: 1), Row(kind: .channel, id: "b", score: 0.9),
                        Row(kind: .channel, id: "c", score: 0.8), Row(kind: .channel, id: "d", score: 0.7),
                        Row(kind: .channel, id: "e", score: 0.6)]
        #expect(GFSearchLayout.sections(channels, allKinds: true).map(\.kind) == [.channel])
        let mixed = channels + [Row(kind: .film, id: "f", score: 2)]
        #expect(GFSearchLayout.sections(mixed, allKinds: false).map(\.kind) == [.film, .channel])
        let few = [Row(kind: .film, id: "f", score: 2), Row(kind: .channel, id: "a", score: 1)]
        #expect(GFSearchLayout.sections(few, allKinds: true).map(\.kind) == [.film, .channel])
    }

    @Test func `favourites, programmes on now and the time asked for count more`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(GFSearchLayout.channelScore(1, isFavorite: true, lastWatched: nil, now: now) > 1)
        #expect(GFSearchLayout.channelScore(1, isFavorite: false, lastWatched: now.addingTimeInterval(-3600),
                                            now: now) > 1)
        #expect(GFSearchLayout.channelScore(1, isFavorite: false, lastWatched: now.addingTimeInterval(-30 * 86400),
                                            now: now) == 1)
        let calendar = Calendar(identifier: .gregorian)
        let live = GFSearchLayout.programmeScore(1, start: now.addingTimeInterval(-600),
                                                 end: now.addingTimeInterval(600), now: now, time: nil,
                                                 calendar: calendar)
        let later = GFSearchLayout.programmeScore(1, start: now.addingTimeInterval(86400),
                                                  end: now.addingTimeInterval(90000), now: now, time: nil,
                                                  calendar: calendar)
        #expect(live > later)
        let asked = GFSearchLayout.programmeScore(1, start: now.addingTimeInterval(-600),
                                                  end: now.addingTimeInterval(600), now: now, time: .now,
                                                  calendar: calendar)
        #expect(asked > live)
    }
}
