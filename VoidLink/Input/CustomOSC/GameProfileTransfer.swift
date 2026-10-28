import Foundation
import UIKit

// Uses the same archive and VLPR container as the existing Import/Export buttons.
enum GameProfileTransfer {
    static let maximumFileSize = 64 * 1024 * 1024

    static func decodedArchive(_ data: Data) throws -> NSMutableArray {
        guard !data.isEmpty, data.count <= maximumFileSize else { throw invalidFile() }
        if data.starts(with: Array("VLPR".utf8)) {
            guard data.count >= 14 else { throw invalidFile() }
            let length = data[6..<14].enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * $1.offset)) }
            guard length > 0, length <= maximumFileSize else { throw invalidFile() }
        }
        let payload = try ProfileFileContainer.unpackedData(from: data)
        guard let entries = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSData.self], from: payload) as? NSArray,
              entries.count > 0 else { throw invalidFile() }
        // Validate the entire file before the manager changes the user's collection.
        for entry in entries {
            guard let encoded = entry as? Data,
                  let profile = try NSKeyedUnarchiver.unarchivedObject(ofClass: OSCProfile.self, from: encoded),
                  !profile.name.isEmpty else { throw invalidFile() }
        }
        return entries.mutableCopy() as! NSMutableArray
    }

    static func importFile(_ data: Data) throws -> String {
        let archive = try decodedArchive(data)
        guard let identifier = OSCProfilesManager.sharedManager(.zero).importEncodedProfiles(archive) else { throw invalidFile() }
        return identifier
    }

    static func invalidFile() -> NSError {
        NSError(domain: "GameProfileTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to import profiles".localized])
    }

#if !os(tvOS)
    static func accepts(_ session: UIDropSession) -> Bool {
        session.items.count == 1 && (session.items.first?.localObject is GameProfileDragReference || session.hasItemsConforming(toTypeIdentifiers: ["public.data"]))
    }

    static func loadFile(from provider: NSItemProvider, completion: @escaping (Result<Data, Error>) -> Void) {
        // Files supplies the file's bytes through public.data, including files stored in iCloud.
        provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, error in
            DispatchQueue.main.async {
                if let data, data.count <= maximumFileSize { completion(.success(data)) }
                else { completion(.failure(error ?? invalidFile())) }
            }
        }
    }

    static func showImportResult(_ success: Bool, on controller: UIViewController?) {
        let alert = UIAlertController(title: nil, message: (success ? "Pofiles imported" : "Failed to import profiles").localized, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK".localized, style: .default))
        controller?.present(alert, animated: true)
    }
#endif
}

#if !os(tvOS)
final class GameProfileDragReference: NSObject {
    let identifier: String
    init(identifier: String) { self.identifier = identifier }
}
#endif
