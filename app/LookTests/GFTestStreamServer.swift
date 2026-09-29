import Foundation
import Network

/// A tiny HTTP server on 127.0.0.1 for the zapping test. Every GET gets an endless MPEG-TS stream (see `GFTestTS`), and
/// the server records when each path's connection opened and closed, and how many were open at once.
nonisolated final class GFTestStreamServer: @unchecked Sendable {
    struct Event: Sendable {
        enum Kind: Sendable { case opened, closed }
        let kind: Kind
        let path: String
        let time: Date
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "lume-gf.test-stream-server")
    // all on `queue`
    private var log: [Event] = []
    private var open = Set<ObjectIdentifier>()
    private var peak = 0
    private(set) var port: UInt16 = 0

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
        self.port = port
    }

    var events: [Event] {
        queue.sync { log }
    }

    /// "opened /a.ts +0.00 s, closed /a.ts +1.23 s, ..." for failure messages.
    var eventsDescription: String {
        let events = events
        guard let first = events.first?.time else { return "no connections" }
        return events.map { "\($0.kind) \($0.path) +\(String(format: "%.2f", $0.time.timeIntervalSince(first))) s" }
            .joined(separator: ", ")
    }

    var peakConnections: Int {
        queue.sync { peak }
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    func stop() {
        listener.cancel()
    }

    /// Waits until `path` has an event of `kind`.
    func wait(for kind: Event.Kind, path: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if events.contains(where: { $0.kind == kind && $0.path == path }) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
            open.insert(id)
            peak = max(peak, open.count)
            log.append(Event(kind: .opened, path: path, time: Date()))
            let header = "HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
            pump(connection, id: id, path: path, counter: 0)
            watch(connection, id: id, path: path)
        }
    }

    /// Reads until the player closes its side of the connection.
    private func watch(_ connection: NWConnection, id: ObjectIdentifier, path: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                closed(connection, id: id, path: path)
            } else {
                watch(connection, id: id, path: path)
            }
        }
    }

    /// About 580 KB/s of stream, like a live channel, until the player goes.
    private func pump(_ connection: NWConnection, id: ObjectIdentifier, path: String, counter: Int) {
        guard open.contains(id) else { return }
        connection.send(content: GFTestTS.chunk(counter: counter), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                closed(connection, id: id, path: path)
                return
            }
            queue.asyncAfter(deadline: .now() + 0.02) {
                self.pump(connection, id: id, path: path, counter: counter + 1)
            }
        })
    }

    private func closed(_ connection: NWConnection, id: ObjectIdentifier, path: String) {
        guard open.remove(id) != nil else { return }
        log.append(Event(kind: .closed, path: path, time: Date()))
        connection.cancel()
    }
}

/// A minimal MPEG-TS stream: a programme association table, a programme map with one H.264 stream, and filler for
/// that stream. There is no decodable picture, so FFmpeg keeps analysing (up to its 5 MB default) and the channel stays
/// connected and read, like a channel a viewer zaps away from.
nonisolated enum GFTestTS {
    static let pmtPID: UInt16 = 0x1000
    static let videoPID: UInt16 = 0x0100

    static func chunk(counter: Int) -> Data {
        var data = Data()
        let pat = section(tableID: 0x00, id: 1, body: [0x00, 0x01, 0xE0 | UInt8(pmtPID >> 8), UInt8(pmtPID & 0xFF)])
        data.append(packet(pid: 0, payloadStart: true, continuity: counter, payload: [0] + pat))
        let pmt = section(tableID: 0x02, id: 1, body: [
            0xE0 | UInt8(videoPID >> 8), UInt8(videoPID & 0xFF), 0xF0, 0x00, // PCR PID, no programme info
            0x1B, 0xE0 | UInt8(videoPID >> 8), UInt8(videoPID & 0xFF), 0xF0, 0x00 // H.264 on the video PID
        ])
        data.append(packet(pid: pmtPID, payloadStart: true, continuity: counter, payload: [0] + pmt))
        for index in 0 ..< 60 {
            let pes: [UInt8] = index == 0 ? [0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0x80, 0x00, 0x00] : []
            data.append(packet(pid: videoPID, payloadStart: index == 0, continuity: counter * 60 + index,
                               payload: pes + [UInt8](repeating: 0xAA, count: 184 - pes.count)))
        }
        return data
    }

    static func packet(pid: UInt16, payloadStart: Bool, continuity: Int, payload: [UInt8]) -> Data {
        var bytes: [UInt8] = [0x47, (payloadStart ? 0x40 : 0x00) | UInt8(pid >> 8), UInt8(pid & 0xFF),
                              0x10 | UInt8(continuity & 0x0F)]
        bytes += payload.prefix(184)
        bytes += [UInt8](repeating: 0xFF, count: 184 - min(payload.count, 184))
        return Data(bytes)
    }

    static func section(tableID: UInt8, id: UInt16, body: [UInt8]) -> [UInt8] {
        let length = 5 + body.count + 4
        var bytes: [UInt8] = [tableID, 0xB0 | UInt8(length >> 8), UInt8(length & 0xFF), UInt8(id >> 8), UInt8(id & 0xFF),
                              0xC1, 0x00, 0x00] + body
        let crc = crc32(bytes)
        bytes += [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        return bytes
    }

    /// CRC-32/MPEG-2, as MPEG-TS tables carry it.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte) << 24
            for _ in 0 ..< 8 {
                crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1
            }
        }
        return crc
    }
}
