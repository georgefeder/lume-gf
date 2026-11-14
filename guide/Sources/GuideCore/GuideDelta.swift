import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// The guide server's hourly change file (Georgs, 14 Nov 2026: the server's push woke the iPhone every hour, but each
/// wake ran out of time importing the whole guide, about 121k programmes, to find the 9 % that changed). Asked with
/// `gf_since=<the build the device has>`, the server answers with what changed since then, or with the full guide
/// when it has no change file for that build (selfhost-aio host-scripts/lume-gf-push/guide_delta.py):
///
///     <tv gf-delta-since="1794676320" gf-build="1794680850">
///       <gf-removed channel="42161" start="20261114183000 +0000"/>
///       <programme ...>...</programme>
///
/// Its programmes are new or changed; each `gf-removed` is a programme gone from the guide before it ended. Programmes
/// that simply ended are not listed: the device drops those by itself.
nonisolated enum GuideDelta {
    struct Header: Equatable {
        var since: Int
        var build: Int
        var removed: [Removed]
    }

    struct Removed: Equatable {
        var channel: String
        var start: String
    }

    /// The guide's address with `gf_since` appended as text: the rest (the login in its query) stays byte for byte.
    static func url(_ urlString: String, since: Int) -> String {
        guard !urlString.contains("gf_since=") else { return urlString }
        return urlString + (urlString.contains("?") ? "&" : "?") + "gf_since=\(since)"
    }

    /// The change file's header and removals, or nil for a full guide. Reads up to the first programme only (the
    /// server writes the removals first).
    static func header(ofFileAt url: URL) -> Header? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let reader = HeaderReader()
        parser.delegate = reader
        parser.parse()
        return reader.header
    }

    private final class HeaderReader: NSObject, XMLParserDelegate {
        var header: Header?

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI _: String?,
                    qualifiedName _: String?, attributes: [String: String] = [:]) {
            switch element {
            case "tv":
                if let since = attributes["gf-delta-since"].flatMap(Int.init),
                   let build = attributes["gf-build"].flatMap(Int.init) {
                    header = Header(since: since, build: build, removed: [])
                } else {
                    parser.abortParsing() // a full guide
                }
            case "gf-removed":
                if let channel = attributes["channel"], let start = attributes["start"] {
                    header?.removed.append(Removed(channel: channel, start: start))
                }
            case "programme":
                parser.abortParsing() // the removals come first
            default:
                break
            }
        }
    }
}
