@testable import LookCore
import Testing

/// The player's moments of a live play, as sent to the server (Georgs through the Oracle Admin, 18 Nov: more analysis).
struct GFPlayEventTests {
    func event(_ kind: GFPlayEvent.Kind, stream: String = "12345.ts") -> GFPlayEvent {
        GFPlayEvent(kind: kind, stream: stream, at: 1_763_480_000_123, session: "k3x9")
    }

    @Test func `each kind names itself first, then the channel, time, session, device and build`() {
        #expect(event(.open).query(device: "iphone", build: "412")
            == "ev=open&ch=12345&t=1763480000123&id=k3x9&d=iphone&b=412")
        #expect(event(.stall(ms: 2350)).query(device: "atv", build: "412")
            == "ev=stall&ms=2350&ch=12345&t=1763480000123&id=k3x9&d=atv&b=412")
        #expect(event(.reopen(.stallWatchdog)).query(device: "atv", build: "412")
            .hasPrefix("ev=reopen&why=stall-watchdog&ch=12345&"))
        #expect(event(.buffer(seconds: 7.46)).query(device: "atv", build: "412").hasPrefix("ev=buf&s=7.5&"))
        #expect(event(.picture(ms: 830)).query(device: "atv", build: "412").hasPrefix("ev=pic&ms=830&"))
        #expect(event(.failed).query(device: "atv", build: "412").hasPrefix("ev=fail&ch="))
        #expect(event(.close).query(device: "atv", build: "412").hasPrefix("ev=close&ch="))
    }

    @Test func `the player's settings go last when known`() {
        var open = event(.open)
        open.lowLatency = false
        open.liveBuffer = 8
        #expect(open.query(device: "iphone", build: "412").hasSuffix("&b=412&ll=0&lb=8"))
    }

    @Test func `nothing but words and numbers: no channel number when the stream has none`() {
        let query = event(.open, stream: "index.m3u8").query(device: "iphone", build: "4.1 (412)")
        #expect(!query.contains("ch="))
        #expect(query.hasSuffix("&b=4.1412"))
        #expect(!query.contains("index"))
    }
}
