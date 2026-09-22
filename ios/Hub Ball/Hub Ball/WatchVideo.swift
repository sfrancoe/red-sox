import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct WatchVideo: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let channel: String
    let channelID: String
    let published: Date

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
    var shareText: String { "\(title)\nFound on Hub Ball ⚾\n\(url.absoluteString)" }

    static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}

// Parse only YouTube's public Atom feed. Ignore descriptions, HTML, and remote
// image/link URLs: all playable URLs are constructed from validated video IDs.
final class WatchFeedParser: NSObject, XMLParserDelegate {
    private var videos: [WatchVideo] = []
    private var entry: [String: String]?
    private var element = ""
    private var text = ""
    private let expectedChannelID: String

    init(channelID: String) { expectedChannelID = channelID }

    func parse(_ data: Data) throws -> [WatchVideo] {
        videos = []
        entry = nil
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw WatchFeedError.invalidFeed }
        // An HTML block page or a malformed feed must not replace cached videos.
        guard !videos.isEmpty else { throw WatchFeedError.emptyFeed }
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }.sorted { $0.published > $1.published }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "entry" { entry = [:] }
        element = elementName
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard entry != nil else { return }
        if element == elementName { entry?[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard elementName == "entry" else { return }
        defer { entry = nil }
        guard let values = entry, let id = values["yt:videoId"], WatchVideo.validID(id),
              values["yt:channelId"] == expectedChannelID,
              let title = values["title"], !title.isEmpty,
              let channel = values["name"], !channel.isEmpty,
              let published = values["published"],
              let date = ISO8601DateFormatter().date(from: published) else { return }
        videos.append(WatchVideo(id: id, title: title, channel: channel,
                                 channelID: expectedChannelID, published: date))
    }
}

enum WatchFeedError: Error { case invalidFeed, emptyFeed, badResponse }
