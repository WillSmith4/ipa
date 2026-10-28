"""Build Foundation test harnesses from production code, without launching UIKit."""
from pathlib import Path
import sys
out = Path(sys.argv[1])

def method(source, signature):
    start = source.index(signature)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

source = Path('VoidLink/Database/DataManager.m').read_text(encoding='utf-8')
(out / 'SessionSettingsDataMethods.inc').write_text('\n'.join(method(source, name) for name in ['- (Settings*) retrieveSettings', '- (void) saveData']), encoding='utf-8')
header = Path('VoidLink/Input/CustomOSC/OSCProfile.h').read_text(encoding='utf-8').replace('#import "OnScreenButtonState.h"', '#import <AppKit/AppKit.h>')
(out / 'OSCProfile.h').write_text(header, encoding='utf-8')
source = Path('VoidLink/Input/CustomOSC/OSCProfile.m').read_text(encoding='utf-8').replace('#import "VoidLink-Swift.h"', '#define ControllerGyroSwitchDisabled 0\n#define ControllerElementNull 0\n#define NativeTouch 1\n#define NativeTouchOnly 4').replace('encodeCGPoint:', 'encodePoint:').replace('decodeCGPointForKey:', 'decodePointForKey:')
(out / 'OSCProfile.m').write_text(source, encoding='utf-8')
(out / 'ProfileBridge.h').write_text('#import "OSCProfile.h"\n#import "ApplicationProfileStore.h"\n', encoding='utf-8')
source = Path('VoidLink/Input/CustomOSC/OSCProfilesManager.swift').read_text(encoding='utf-8')
names = ['private func encodedProfiles(', 'private func persistProfiles(', 'func persistProfileOrder(', 'private func persistEncodedProfiles(', 'func deleteCurrentSelectedProfile(', 'func replaceSelectedProfile(', 'func replaceProfile(', 'func getEncodedProfiles(', 'func importEncodedProfiles(', 'func getAllProfiles(', 'private func decodeProfiles(', 'func getSelectedProfile(', 'func getIndexOfSelectedProfile(', 'func setProfileToSelected(', 'func activateAssignedProfile(', 'func duplicateSelectedProfile(', 'func profileNameAlreadyExist(']
harness = """import Foundation
import CoreGraphics
extension NSArray { subscript(safe index: Int) -> Any? { (0..<count).contains(index) ? self[index] : nil } }
enum GenericUtils { static let pencilProPurchaseProcessedWithImportingWidgetTemplates = false }
final class OSCProfilesManager: NSObject {
    private static let profilesDefaultsKey = "OSCProfiles"
    private static let widgetProfileUpdatedKey = "widgetProfileUpdated-20260801"
    private static let profileCodingClasses: [AnyClass] = [NSString.self, NSMutableData.self, NSMutableArray.self, OSCProfile.self]
    static let instance = OSCProfilesManager()
    static func sharedManager(_ bounds: CGRect) -> OSCProfilesManager { instance }
    var currentProfiles: NSMutableArray = []
    func importDefaultTemplates(selectedIndex: UInt32?) { fatalError("Tests seed profiles before activation") }
"""
harness += '\n'.join(method(source, name) for name in names) + '\n}\n'
(out / 'OSCProfilesManager.swift').write_text(harness, encoding='utf-8')
source = Path('VoidLink/ViewControllers/CustomOSCViewControl/Table/ProfileSelectorViewController.swift').read_text(encoding='utf-8')
container = source[source.index('private enum ProfilePayloadCompression'):source.index('@objc enum ProfileSelectorLoadingMode')]
(out / 'ProfileFileContainer.swift').write_text('import Foundation\nimport Compression\n' + container, encoding='utf-8')
source = Path('VoidLink/Input/CustomOSC/GameProfileTransfer.swift').read_text(encoding='utf-8').replace('import UIKit', '')
source = source[:source.index('#if !os(tvOS)')] + '}\n'
(out / 'GameProfileTransfer.swift').write_text(source + 'extension String { var localized: String { self } }\n', encoding='utf-8')
