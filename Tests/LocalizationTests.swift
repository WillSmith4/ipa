import Foundation

@main
struct LocalizationTests {
    static func main() throws {
        let bundle = Bundle.main
        let language = bundle.preferredLocalizations.first ?? "en"
        func table(_ language: String) throws -> [String: String] {
            let url = bundle.bundleURL.appendingPathComponent("Contents/Resources/\(language).lproj/Localizable.strings")
            return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
        }
        let english = try table("en")
        let selected = try table(language)
        var fallbacks = 0
        for (key, englishValue) in english {
            let local = selected[key]
            let expected = (local?.isEmpty == false && local != key) ? local! : englishValue
            let actual = LocalizationHelper.localizedTemplate(forKey: key)
            precondition(actual == expected, "Incorrect \(language) fallback for \(key): \(actual)")
            if local == nil { fallbacks += 1 }
        }
        if language == "pl" {
            precondition(fallbacks > 100, "Exercise the real partial-translation case")
            precondition(LocalizationHelper.localizedString(forKey: "Pairing") == "Parowanie")
        }
        for message in [LocalizationHelper.localizedString(forKey: "Enter_PIN_Msg", "0123"), TestObjectiveCPINMessage()!] {
            precondition(message.contains("0123"), "PIN must survive localization and retain its leading zero")
            precondition(!message.contains("%@") && message != "Enter_PIN_Msg", "Unresolved pairing message")
        }
        // Unknown readable source strings and literal percent signs remain intact.
        precondition(LocalizationHelper.localizedString(forKey: "Battery 100%") == "Battery 100%")
        precondition(LocalizationHelper.localizedString(forKey: "A new readable label") == "A new readable label")
        for key in ["enterSqueezePressShort", "relativeTouchSlideThresholdStackTip", "SensitivityX", "SensitivityY", "PencilProPackDescription"] {
            precondition(LocalizationHelper.localizedString(forKey: key) != key, "Untranslated internal key: \(key)")
        }
        print("Localization: \(language), \(english.count) keys checked, \(fallbacks) missing translations resolved; Swift and Objective-C PIN formatting passed")
    }
}
