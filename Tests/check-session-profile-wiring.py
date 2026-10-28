from pathlib import Path

def read(path): return Path(path).read_text(encoding="utf-8")
main = read("VoidLink/ViewControllers/MainFrameViewController.m")
sidebar = read("VoidLink/ViewControllers/SWRevealViewController.m")
swift = read("VoidLink/ViewControllers/SettingsSwiftUI.swift")
uikit = read("VoidLink/ViewControllers/SettingsViewController.m")
assert "restoreSessionDefaults" not in sidebar
assert "reconnectAfterSettingsChange" not in main
assert "ApplicationSettingsStore" not in main + swift + uikit
assert "[self revealToggleAnimated:YES];" in sidebar.split("- (void)foldRearView{")[1].split("}")[0]
assert "[self.settingsViewController saveSettings];" in main.split("didMoveToPosition:(FrontViewPosition)position {")[1].split("// #endif")[0]
assert "request(forBitrate:" in swift and "requestForBitrate:" in uikit
catalog = swift[swift.index("distribution: .proportionalToContent,", swift.index("options: { $0.resolutionOptions }")):]
assert "isVisible: { !$0.isStreaming }" in catalog[:100]
for name in ["usesCustomResolution", "frameRate"]:
    start = catalog.index("\\." + name + ",")
    assert "isVisible: { !$0.isStreaming }" in catalog[start:start+700], name
launch = main[main.index("- (void) prepareToStreamApp:"):main.index("- (void) reloadStreamConfig")]
assert launch.index("activateAssignedProfileForHostUUID:") < launch.index("[self reloadStreamConfig]")
selector = read("VoidLink/ViewControllers/CustomOSCViewControl/Table/ProfileSelectorViewController.swift")
assert "session.localContext = self" in selector and "window.passesThroughTouches = true" in selector
assert "profileCollectionView.dragDelegate = self" in selector and "profileCollectionView.dropDelegate = self" in selector
assert "nativeDragActive" in selector.split("shouldRecognizeSimultaneouslyWith")[1].split("@objc func presentInKeyWindow")[0]
assert "GameProfileTransfer.importFile" in read("VoidLink/UIAppView.swift")
assert "item.dragItem.localObject as? GameProfileDragReference" in selector
print("Session/profile wiring: shared save, hidden connection settings, no reconnect/defaults, early profile selection and native drag/drop passed")
