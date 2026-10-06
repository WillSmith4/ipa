import Foundation
import ImageIO
import CoreGraphics

@main
struct ApplicationShortcutTests {
    @MainActor static func main() async throws {
        let host = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let link = ApplicationLaunchLink.make(hostUUID: host, appID: "42")!
        precondition(link.absoluteString == "voidlink://launch?host=\(host)&app=42")
        let parsed = ApplicationLaunchLink.parse(link)!
        precondition(parsed.hostUUID == host && parsed.appID == "42")
        precondition(ApplicationLaunchLink.parse(URL(string: "VOIDLINK://LAUNCH?app=42&host=\(host)")!) != nil)
        for invalid in [
            "https://launch?host=\(host)&app=42", "voidlink://other?host=\(host)&app=42",
            "voidlink://launch/path?host=\(host)&app=42", "voidlink://user@launch?host=\(host)&app=42",
            "voidlink://launch:12?host=\(host)&app=42", "voidlink://launch?host=\(host)&app=42#fragment",
            "voidlink://launch?host=\(host)", "voidlink://launch?host=\(host)&app=42&app=43",
            "voidlink://launch?host=\(host)&host=\(host)&app=42", "voidlink://launch?host=unknown&app=42",
            "voidlink://launch?host=\(host)&app=0", "voidlink://launch?host=\(host)&app=-1",
            "voidlink://launch?host=\(host)&app=042", "voidlink://launch?host=\(host)&app=4294967296",
            "voidlink://launch?host=\(host)&app=42&address=evil.example"
        ] { precondition(ApplicationLaunchLink.parse(URL(string: invalid)!) == nil, invalid) }
        precondition(ApplicationLaunchLink.make(hostUUID: "invalid", appID: "42") == nil)
        precondition(ApplicationLaunchLink.make(hostUUID: host, appID: "42&app=43") == nil)

        for (name, bucket) in [("The Sims 3", "th"), ("7 Days", "7"), ("!Abc", "a"), ("中文", "@"), ("😀X", "@"), ("", "@")] {
            precondition(GameCoverSearch.bucket(for: name) == bucket)
        }
        let bucket = Data(#"{"1":{"name":"The Sims 3: Pets"},"2":{"name":"THE SIMS 3"},"3":{"name":"The Sims 4"},"4":{"name":"The  Sims 3: Seasons"},"../5":{"name":"The Sims 3"}}"#.utf8)
        let matches = try GameCoverSearch.candidates(in: bucket, named: "The Sims 3")
        precondition(matches.map(\.id) == ["2", "1", "4"])
        let none = try GameCoverSearch.candidates(in: bucket, named: "Unknown")
        precondition(none.isEmpty)
        let game = Data(#"{"id":2,"name":"The Sims 3","cover":{"url":"//images.igdb.com/igdb/image/upload/t_thumb/co1234.jpg"}}"#.utf8)
        let iconURL = try GameCoverSearch.iconURL(in: game)
        precondition(iconURL.absoluteString == "https://images.igdb.com/igdb/image/upload/t_thumb_2x/co1234.png")
        for invalid in [#"{}"#, #"{"cover":null}"#, #"{"cover":{"url":"https://evil.example/icon.png"}}"#, #"{"cover":{"url":"//images.igdb.com/path/a%20b.jpg"}}"#] {
            do { _ = try GameCoverSearch.iconURL(in: Data(invalid.utf8)); preconditionFailure("Invalid cover accepted") }
            catch {}
        }
        let icon = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])
        var requested: [String] = []
        let service = GameCoverService { url in
            requested.append(url.absoluteString)
            if url.path.hasSuffix("/buckets/th.json") { return bucket }
            if url.path.hasSuffix("/games/2.json") { return game }
            if url == iconURL { return icon }
            preconditionFailure("Unexpected download: \(url)")
        }
        let found = try await service.search("The Sims 3")
        let downloaded = try await service.icon(for: found[0])
        precondition(downloaded == icon && requested.count == 3, "Only the selected game and t_thumb_2x image should download")
        requested = []
        let automatic = try await service.automaticIcon(named: "The Sims 3")
        precondition(automatic == icon && requested.count == 3, "An exact name selects its cover without a picker")
        let numeric = try GameCoverSearch.candidates(in: Data(#"{"1020":{"name":"Grand Theft Auto V"},"100":{"name":"Grand Theft Auto IV"},"7":{"name":"Grand Theft Auto"}}"#.utf8), named: "Grand Theft")
        precondition(numeric.map(\.id) == ["7", "100", "1020"], "Prefix-only matches follow numeric GameDB IDs")
        var skipped: [String] = []
        let skipMissing = GameCoverService { url in
            skipped.append(url.lastPathComponent)
            if url.path.contains("/buckets/") { return bucket }
            if url.path.hasSuffix("/games/2.json") { return Data(#"{"cover":null}"#.utf8) }
            if url.path.hasSuffix("/games/1.json") { return game }
            return icon
        }
        let fallback = try await skipMissing.automaticIcon(named: "The Sims 3")
        precondition(fallback == icon && skipped == ["th.json", "2.json", "1.json", "co1234.png"])
        let unavailable = GameCoverService { _ in throw ApplicationShortcutError.download }
        do { _ = try await unavailable.search("The Sims 3"); preconditionFailure("Download failure was hidden") }
        catch { precondition(error is ApplicationShortcutError) }
        let noMatch = GameCoverService { _ in return Data("{}".utf8) }
        do { _ = try await noMatch.automaticIcon(named: "Custom desktop"); preconditionFailure("Missing cover must request a Files image") }
        catch { precondition(error as? ApplicationShortcutError == .noCover) }

        let context = CGContext(data: nil, width: 1024, height: 2048, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 2048))
        let imageBytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(imageBytes, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let normalized = try ApplicationIcon.png(from: imageBytes as Data)
        let source = CGImageSourceCreateWithData(normalized as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        precondition(CGImageSourceGetType(source)! as String == "public.png")
        precondition(properties[kCGImagePropertyPixelWidth] as? Int == 512 && properties[kCGImagePropertyPixelHeight] as? Int == 256,
                     "Files images must honor orientation and downsample for Home Screen icons")
        do { _ = try ApplicationIcon.png(from: Data("invalid".utf8)); preconditionFailure("Invalid Files image accepted") }
        catch { precondition(error as? ApplicationShortcutError == .invalidImage) }

        let name = "Sims & <Custom> \"Edition\""
        let profile = try ApplicationWebClip.profile(name: name, launchURL: link, icon: icon)
        let plist = try PropertyListSerialization.propertyList(from: profile, format: nil) as! [String: Any]
        let clips = plist["PayloadContent"] as! [[String: Any]]
        precondition(clips.count == 1 && clips[0]["PayloadType"] as? String == "com.apple.webClip.managed")
        precondition(clips[0]["Label"] as? String == name && clips[0]["Icon"] as? Data == icon)
        precondition(clips[0]["URL"] as? String == link.absoluteString)
        precondition(clips[0]["IsRemovable"] as? Bool == true && plist["PayloadRemovalDisallowed"] as? Bool == false)
        precondition(plist["PayloadType"] as? String == "Configuration")
        let second = try PropertyListSerialization.propertyList(from: ApplicationWebClip.profile(name: name, launchURL: link, icon: icon), format: nil) as! [String: Any]
        precondition(second["PayloadIdentifier"] as? String == plist["PayloadIdentifier"] as? String)
        precondition(second["PayloadUUID"] as? String != plist["PayloadUUID"] as? String)

        let server = WebClipProfileServer(profile: profile)
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            server.start { continuation.resume(with: $0) }
        }
        precondition(url.host == "127.0.0.1")
        let (served, response) = try await URLSession.shared.data(from: url)
        precondition(served == profile && (response as! HTTPURLResponse).statusCode == 200)
        precondition(response.mimeType == "application/x-apple-aspen-config")
        var head = URLRequest(url: url); head.httpMethod = "HEAD"
        let (empty, headResponse) = try await URLSession.shared.data(for: head)
        precondition(empty.isEmpty && (headResponse as! HTTPURLResponse).statusCode == 200)
        let wrongPath = url.deletingLastPathComponent().appendingPathComponent("other.mobileconfig")
        let (missing, missingResponse) = try await URLSession.shared.data(from: wrongPath)
        precondition(missing.isEmpty && (missingResponse as! HTTPURLResponse).statusCode == 404)
        var post = URLRequest(url: url); post.httpMethod = "POST"
        let (_, postResponse) = try await URLSession.shared.data(for: post)
        precondition((postResponse as! HTTPURLResponse).statusCode == 404)
        server.stop()
        print("Application shortcuts: launch URLs, GameDB lookup, t_thumb_2x, Web Clip profiles and loopback download passed")
    }
}
