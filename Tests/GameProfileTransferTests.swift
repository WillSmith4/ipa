import Foundation

@main enum GameProfileTransferTests {
    static func profile(_ name: String, selected: Bool = false) -> OSCProfile {
        let result: OSCProfile = OSCProfile(name: name, buttonStates: NSMutableArray(), isSelected: selected)
        result.pressureCurvePoints = [0, 0, 1, 1]
        result.brushShortcut = "B"
        result.eraserShortcut = "E"
        result.squeezeStartShortcut = ""
        result.squeezeEndShortcut = ""
        result.touchMode = 2
        result.gyroSensitivityYaw = 1.75
        return result
    }
    static func file(_ profiles: [OSCProfile], compressed: Bool = true) throws -> Data {
        let entries = NSMutableArray()
        for profile in profiles { entries.add(try NSKeyedArchiver.archivedData(withRootObject: profile, requiringSecureCoding: true)) }
        let data = try NSKeyedArchiver.archivedData(withRootObject: entries, requiringSecureCoding: true)
        return compressed ? ProfileFileContainer.packedData(from: data) : data
    }
    static func main() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "OSCProfiles")
        let templateKey = "widgetProfileUpdated-20260801"
        let oldTemplateFlag = defaults.object(forKey: templateKey)
        defer {
            defaults.set(previous, forKey: "OSCProfiles")
            defaults.set(oldTemplateFlag, forKey: templateKey)
            ApplicationProfileStore.shared.setProfileIdentifier(nil, forHostUUID: "profile-test", appID: "42")
        }
        defaults.set(true, forKey: templateKey)
        let manager = OSCProfilesManager.sharedManager(.zero)
        let original = profile("Legacy", selected: true)
        original.profileIdentifier = nil
        manager.persistProfileOrder(NSMutableArray(array: [profile("Default"), original]))
        let migrated = manager.getSelectedProfile()
        let identifier = migrated.profileIdentifier!
        precondition(manager.getSelectedProfile().profileIdentifier == identifier, "Legacy identity must be persisted once")
        ApplicationProfileStore.shared.setProfileIdentifier(identifier, forHostUUID: "profile-test", appID: "42")
        let edited = migrated.mutableCopy() as! OSCProfile
        edited.name = "Renamed"
        edited.gyroSensitivityYaw = 2.25
        manager.replaceProfile(migrated, withProfile: edited)
        precondition(manager.getSelectedProfile().profileIdentifier == identifier, "Rename/edit must retain identity")
        manager.duplicateSelectedProfile(withName: "Duplicate")
        let duplicateID = manager.getSelectedProfile().profileIdentifier!
        precondition(duplicateID != identifier, "Duplicate must have a fresh identity")
        manager.activateAssignedProfile(hostUUID: "profile-test", appID: "42")
        precondition(manager.getSelectedProfile().name == "Renamed" && manager.getSelectedProfile().gyroSensitivityYaw == 2.25, "Activate the live existing profile, including later edits")
        let reordered = manager.getAllProfiles()
        reordered.exchangeObject(at: 1, withObjectAt: 2)
        manager.persistProfileOrder(reordered)
        manager.setProfileToSelected(0)
        manager.activateAssignedProfile(hostUUID: "profile-test", appID: "42")
        precondition(manager.getSelectedProfile().profileIdentifier == identifier, "Reordering must not change app assignments")
        for compressed in [false, true] {
            let importedID = try GameProfileTransfer.importFile(file([edited], compressed: compressed))
            precondition(importedID != identifier && manager.getSelectedProfile().profileIdentifier == importedID, "Raw/VLPR import has a fresh identity")
            precondition(manager.getSelectedProfile().touchMode == 2 && manager.getSelectedProfile().gyroSensitivityYaw == 2.25, "Existing profile fields must survive import")
        }
        let selected = profile("Bundle selection", selected: true)
        let bundleID = try GameProfileTransfer.importFile(file([profile("Bundle first"), selected]))
        precondition(manager.getAllProfiles().contains { ($0 as? OSCProfile)?.name == selected.name && ($0 as? OSCProfile)?.profileIdentifier == bundleID }, "Multi-profile export assigns the exported selection")
        let before = defaults.data(forKey: "OSCProfiles")!
        for invalid in [Data(), Data("garbage".utf8), Data("VLPR".utf8), Data([86,76,80,82,1,2] + Array(repeating: 255, count: 8))] {
            do { _ = try GameProfileTransfer.importFile(invalid); preconditionFailure("Reject malformed files") }
            catch { precondition(defaults.data(forKey: "OSCProfiles") == before, "A failed import cannot modify profiles") }
        }
        manager.activateAssignedProfile(hostUUID: "profile-test", appID: "42")
        manager.deleteCurrentSelectedProfile()
        let fallback = manager.getSelectedProfile().profileIdentifier
        manager.activateAssignedProfile(hostUUID: "profile-test", appID: "42")
        precondition(manager.getSelectedProfile().profileIdentifier == fallback, "Deleted profile falls back to current selection")
        precondition(ApplicationProfileStore.shared.profileIdentifier(forHostUUID: "profile-test", appID: "42") == nil, "Remove stale assignment")
        if CommandLine.arguments.count > 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let entries = try GameProfileTransfer.decodedArchive(Data(contentsOf: url))
            precondition(entries.count > 0, "Bundled legacy profile files must remain importable")
        }
        print("Game profiles: legacy migration, rename/edit/reorder, duplicate, app activation, raw/VLPR import, invalid files and deleted-profile fallback passed")
    }
}
