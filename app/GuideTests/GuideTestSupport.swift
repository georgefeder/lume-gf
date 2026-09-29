import Foundation

struct GuideTestProgramme {
    var channel: String
    var start: Date
    var end: Date
    var title: String
}

/// Writes a small XMLTV file; `cut` drops the end of the file like an interrupted download.
func writeGuideFile(_ programmes: [GuideTestProgramme], cut: Bool = false) throws -> URL {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(identifier: "UTC")
    format.dateFormat = "yyyyMMddHHmmss"
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tv>\n"
    for p in programmes {
        xml += "<programme start=\"\(format.string(from: p.start)) +0000\" stop=\"\(format.string(from: p.end)) +0000\""
        xml += " channel=\"\(p.channel)\"><title>\(p.title)</title></programme>\n"
    }
    xml += "</tv>\n"
    if cut { xml = String(xml.dropLast(60)) }
    let url = FileManager.default.temporaryDirectory.appending(path: "guide-\(UUID().uuidString).xml")
    try xml.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// `count` hourly programmes on `channel` starting at `from`.
func hourly(_ channel: String, from: Date, count: Int, title: String = "Show") -> [GuideTestProgramme] {
    (0 ..< count).map {
        GuideTestProgramme(channel: channel, start: from.addingTimeInterval(Double($0) * 3600),
                           end: from.addingTimeInterval(Double($0 + 1) * 3600), title: "\(title) \($0)")
    }
}
