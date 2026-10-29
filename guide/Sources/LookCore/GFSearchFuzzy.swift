/// How many typing mistakes search forgives in a word, and how many a pair of words is apart (Georgs, 29 Oct: "typo
/// safe"). A mistake is a letter missing, extra, wrong, or two letters swapped ("warrirs", "finlnd", "sohw").
nonisolated enum GFSearchFuzzy {
    /// None in words of three letters or fewer (else "cnn" would find "cnbc" and every other short name), one up to
    /// seven letters, two from eight. Counted in UTF-8 bytes, as `distance` compares them.
    static func budget(forLength length: Int) -> Int {
        switch length {
        case ..<4: 0
        case 4 ... 7: 1
        default: 2
        }
    }

    /// The mistakes between `lhs` and `rhs` (letters missing, extra, wrong or swapped), or nil when more than
    /// `limit`. Compares bytes: after `GFSearchText.fold` almost every word is plain ASCII.
    static func distance(_ lhs: String, _ rhs: String, limit: Int) -> Int? {
        var table = Table()
        return table.distance(lhs, rhs, limit: limit)
    }

    /// The rows `distance` works in, kept between calls: search compares a query word with thousands of words.
    struct Table {
        private var older: [Int] = []
        private var previous: [Int] = []
        private var current: [Int] = []

        init() {}

        mutating func distance(_ lhs: String, _ rhs: String, limit: Int) -> Int? {
            var lhs = lhs, rhs = rhs
            return lhs.withUTF8 { left in rhs.withUTF8 { right in distance(left, right, limit: limit) } }
        }

        /// The optimal string alignment distance, cut short once every path is past `limit`.
        mutating func distance(_ lhs: UnsafeBufferPointer<UInt8>, _ rhs: UnsafeBufferPointer<UInt8>,
                               limit: Int) -> Int? {
            let (n, m) = (lhs.count, rhs.count)
            guard abs(n - m) <= limit else { return nil }
            if n == 0 || m == 0 { return max(n, m) <= limit ? max(n, m) : nil }
            // the rows trade places as the table fills, so each is checked
            if older.count <= m { older = [Int](repeating: 0, count: m + 1) }
            if current.count <= m { current = [Int](repeating: 0, count: m + 1) }
            if previous.count <= m { previous = [Int](repeating: 0, count: m + 1) }
            for j in 0 ... m {
                previous[j] = j
            }
            for i in 1 ... n {
                current[0] = i
                var best = i
                for j in 1 ... m {
                    let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                    var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                    if i > 1, j > 1, lhs[i - 1] == rhs[j - 2], lhs[i - 2] == rhs[j - 1] {
                        value = min(value, older[j - 2] + 1)
                    }
                    current[j] = value
                    best = min(best, value)
                }
                guard best <= limit else { return nil }
                swap(&older, &previous)
                swap(&previous, &current)
            }
            return previous[m] <= limit ? previous[m] : nil
        }
    }
}
