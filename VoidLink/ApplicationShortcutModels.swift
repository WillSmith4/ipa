import Foundation
import ImageIO

/// A launch link contains stable IDs only. Addresses, pairing keys and commands
/// always come from the client's saved host, never from an external URL.
@objc final class ApplicationLaunchLink: NSObject {
    @objc let hostUUID: String
    @objc let appID: String

    private init(hostUUID: String, appID: String) {
        self.hostUUID = hostUUID
        self.appID = appID
    }

    @objc static func make(hostUUID: String, appID: String) -> URL? {
        guard UUID(uuidString: hostUUID) != nil, validAppID(appID) else { return nil }
        var parts = URLComponents()
        parts.scheme = "voidlink"
        parts.host = "launch"
        parts.queryItems = [URLQueryItem(name: "host", value: hostUUID), URLQueryItem(name: "app", value: appID)]
        return parts.url
    }

    @objc static func parse(_ url: URL) -> ApplicationLaunchLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "voidlink", parts.host?.lowercased() == "launch",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "host" }).count == 1,
              items.filter({ $0.name == "app" }).count == 1,
              let host = items.first(where: { $0.name == "host" })?.value,
              let app = items.first(where: { $0.name == "app" })?.value,
              UUID(uuidString: host) != nil, validAppID(app) else { return nil }
        return ApplicationLaunchLink(hostUUID: host, appID: app)
    }

    private static func validAppID(_ value: String) -> Bool {
        guard let number = UInt32(value), number > 0 else { return false }
        return String(number) == value
    }
}

enum ApplicationShortcutError: String, LocalizedError {
    case invalidLink = "Invalid VoidLink launch URL. Copy the URL from the application's menu."
    case download = "Unable to download the app icon. Check your connection and try again."
    case noCover = "No matching cover was found in GameDB. Choose an image from Files to use as the app icon."
    case invalidImage = "The downloaded app icon is not a valid image."
    case profileServer = "Unable to open the Web Clip profile. Please try again."
    var errorDescription: String? { NSLocalizedString(rawValue, comment: "Application shortcuts") }
}

enum GameCoverSearch {
    struct Candidate: Equatable { let id: String; let name: String }

    static func bucket(for name: String) -> String {
        // Match Sunshine's JS substring(0, 2), then lowercase and strip non-ASCII.
        let name = name as NSString
        let prefix = name.substring(to: min(2, name.length)).lowercased()
        let bucket = prefix.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return bucket.isEmpty ? "@" : bucket
    }

    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "\\s+", with: ".", options: .regularExpression).lowercased()
    }

    static func candidates(in data: Data, named name: String) throws -> [Candidate] {
        struct Entry: Decodable { let name: String }
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        let query = normalized(name)
        guard !query.isEmpty else { return [] }
        return entries.compactMap { id, entry -> Candidate? in
            guard UInt64(id) != nil, id.allSatisfy({ $0.isASCII && $0.isNumber }),
                  normalized(entry.name).hasPrefix(query) else { return nil }
            return Candidate(id: id, name: entry.name)
        }.sorted {
            let a = normalized($0.name), b = normalized($1.name)
            if (a == query) != (b == query) { return a == query }
            // JS Object.keys enumerates the bucket's numeric game IDs in order.
            return UInt64($0.id)! < UInt64($1.id)!
        }
    }

    static func iconURL(in data: Data) throws -> URL {
        struct Game: Decodable {
            struct Cover: Decodable { let url: String }
            let cover: Cover?
        }
        guard let cover = try JSONDecoder().decode(Game.self, from: data).cover,
              let source = URL(string: cover.url.hasPrefix("//") ? "https:" + cover.url : cover.url),
              source.host?.lowercased() == "images.igdb.com" else { throw ApplicationShortcutError.noCover }
        let slug = source.deletingPathExtension().lastPathComponent
        guard !slug.isEmpty, slug.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let url = URL(string: "https://images.igdb.com/igdb/image/upload/t_thumb_2x/\(slug).png")
        else { throw ApplicationShortcutError.noCover }
        return url
    }
}

/// Fetch only the selected game's JSON/image, rather than downloading every
/// cover in a broad search. The injectable transport is also used by CI tests.
final class GameCoverService {
    typealias Fetch = (URL) async throws -> Data
    private let fetch: Fetch
    private static let database = "https://raw.githubusercontent.com/LizardByte/GameDB/gh-pages"

    init(fetch: @escaping Fetch = GameCoverService.download) { self.fetch = fetch }

    func search(_ name: String) async throws -> [GameCoverSearch.Candidate] {
        let bucket = GameCoverSearch.bucket(for: name)
        let url = URL(string: "\(Self.database)/buckets/\(bucket).json")!
        return try GameCoverSearch.candidates(in: await fetch(url), named: name)
    }

    func icon(for candidate: GameCoverSearch.Candidate) async throws -> Data {
        guard UInt64(candidate.id) != nil, candidate.id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ApplicationShortcutError.noCover
        }
        let game = try await fetch(URL(string: "\(Self.database)/games/\(candidate.id).json")!)
        return try await fetch(GameCoverSearch.iconURL(in: game))
    }

    func automaticIcon(named name: String) async throws -> Data {
        let matches = try await search(name)
        for candidate in matches {
            try Task.checkCancellation()
            do { return try await icon(for: candidate) }
            catch ApplicationShortcutError.noCover { continue }
        }
        throw ApplicationShortcutError.noCover
    }

    static func download(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("VoidLink", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error); return }
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    continuation.resume(throwing: ApplicationShortcutError.noCover); return
                }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, !data.isEmpty, data.count <= 8 * 1024 * 1024 else {
                    continuation.resume(throwing: ApplicationShortcutError.download); return
                }
                continuation.resume(returning: data)
            }.resume()
        }
    }
}

enum ApplicationIcon {
    /// Decode the first frame, honor orientation and bound memory/profile size.
    /// Small t_thumb_2x covers keep their size; large Files images are downsampled.
    static func png(from data: Data) throws -> Data {
        guard data.count <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { throw ApplicationShortcutError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw ApplicationShortcutError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ApplicationShortcutError.invalidImage }
        return output as Data
    }
}

enum ApplicationWebClip {
    static func profile(name: String, launchURL: URL, icon: Data) throws -> Data {
        guard let target = ApplicationLaunchLink.parse(launchURL) else { throw ApplicationShortcutError.invalidLink }
        let identifier = "com.voidlink.webclip.\(target.hostUUID.lowercased()).\(target.appID)"
        let description = String(format: NSLocalizedString("Launch %@ in VoidLink.", comment: "Web Clip profile"), name)
        let clip: [String: Any] = [
            "PayloadType": "com.apple.webClip.managed", "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".clip", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": name, "Label": name, "URL": launchURL.absoluteString,
            "Icon": icon, "FullScreen": true, "IgnoreManifestScope": true,
            "IsRemovable": true, "Precomposed": true
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": identifier, "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": name, "PayloadDescription": description,
            "PayloadOrganization": "VoidLink", "PayloadRemovalDisallowed": false,
            "ConsentText": ["default": description], "PayloadContent": [clip]
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
