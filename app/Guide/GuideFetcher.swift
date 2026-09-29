import Foundation

/// Downloads a guide conditionally: sends the stored ETag / Last-Modified and treats 304 as "unchanged".
/// Local files (file:// sources) are always read in full.
nonisolated struct GuideFetcher {
    enum Result {
        case unchanged
        /// `isTemporary`: the file is a download the caller deletes after use (never the user's own local file).
        case file(URL, etag: String?, lastModified: String?, serverBuild: Date?, isTemporary: Bool)
    }

    let session: URLSession

    init(session: URLSession = M3UClient().session) {
        self.session = session
    }

    func fetch(urlString: String, etag: String?, lastModified: String?) async throws -> Result {
        guard let url = URL(string: urlString) else { throw M3UError.invalidURL }
        if url.isFileURL {
            let file = try await M3UClient(urlSession: session).downloadEPG(from: urlString)
            return .file(file, etag: nil, lastModified: nil, serverBuild: nil, isTemporary: file != url)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData // the validators are ours, not URLCache's
        for (name, value) in GuideFetchPolicy.requestHeaders(etag: etag, lastModified: lastModified) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw M3UError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw M3UError.invalidResponse }
        let answer = GuideFetchPolicy.interpret(status: http.statusCode,
                                                etag: http.value(forHTTPHeaderField: "ETag"),
                                                lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
        switch answer {
        case .unchanged:
            try? FileManager.default.removeItem(at: tempURL)
            return .unchanged
        case let .failed(status):
            try? FileManager.default.removeItem(at: tempURL)
            throw M3UError.serverError(status)
        case let .newGuide(newEtag, newLastModified, serverBuild):
            let stable = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".xmltv")
            try FileManager.default.moveItem(at: tempURL, to: stable)
            var file = stable
            if GzipFile.isGzip(stable) {
                file = try GzipFile.decompress(stable)
                try? FileManager.default.removeItem(at: stable)
            }
            return .file(file, etag: newEtag, lastModified: newLastModified, serverBuild: serverBuild,
                         isTemporary: true)
        }
    }
}
