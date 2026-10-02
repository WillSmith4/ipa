import Foundation

/// Host actions shared by the settings UI and the gesture runtime. Keyboard
/// chords use the same names as CommandManager (for example CTRL+Q).
enum GestureAction {
    static let defaults = ["SCROLL_DOWN", "SCROLL_UP", "Q", "E"]
    static let presets = ["NONE", "SCROLL_DOWN", "SCROLL_UP"]

    static func keys(_ action: String, mappings: [String: Int16]) -> [Int16]? {
        let names = action.uppercased().components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !names.isEmpty, names.allSatisfy({ $0 != "NULL" && mappings[$0] != nil }) else { return nil }
        let codes = names.compactMap { mappings[$0] }
        // Modifiers precede ordinary keys, irrespective of the entered order.
        let modifiers: Set<Int16> = [0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]
        return Array(Set(codes)).sorted {
            if modifiers.contains($0) != modifiers.contains($1) { return modifiers.contains($0) }
            return $0 < $1
        }
    }
}

/// Independent of UIKit and the transport, so timing, overlapping chords and
/// scroll accumulation can be tested without a streaming host.
final class GestureActionEngine {
    private struct Hold {
        let keys: [Int16]
        var until: TimeInterval
    }
    private let mappings: [String: Int16]
    private let sendKey: (Int16, Bool) -> Void
    private let sendScroll: (Int16) -> Void
    private var holds: [Int: Hold] = [:]
    private var pressed: [Int16] = []
    private var scrollRemainder = 0.0

    var hasHolds: Bool { !holds.isEmpty }

    init(mappings: [String: Int16], sendKey: @escaping (Int16, Bool) -> Void,
         sendScroll: @escaping (Int16) -> Void) {
        self.mappings = mappings
        self.sendKey = sendKey
        self.sendScroll = sendScroll
    }

    /// Each axis owns a hold. Movement extends its deadline instead of sending
    /// repeated keydowns. Larger/faster movement buys more continuous hold time,
    /// capped at 450 ms of idle time; lifting fingers always releases immediately.
    func move(axis: Int, action: String, amount: Double, now: TimeInterval, controlScroll: Bool = false) {
        guard amount.isFinite, amount > 0, now.isFinite else { return }
        if action == "SCROLL_UP" || action == "SCROLL_DOWN" {
            let keys: [Int16] = controlScroll ? [0x11] : []
            holds[axis] = keys.isEmpty ? nil : Hold(keys: keys, until: now + 0.12)
            reconcile()
            let units = min(Double(Int16.max), amount * 7)
            scrollRemainder += (action == "SCROLL_UP" ? 1 : -1) * units
            // Preserve sub-unit motion and bound conversion for extreme samples.
            let whole = min(Double(Int16.max), max(Double(Int16.min), scrollRemainder.rounded(.towardZero)))
            if whole != 0 {
                sendScroll(Int16(whole))
                scrollRemainder -= whole
            }
        } else if let keys = GestureAction.keys(action, mappings: mappings) {
            let previous = holds[axis]
            let baseline = previous?.keys == keys ? max(now, previous!.until) : now
            let until = min(now + 0.45, max(now + 0.07, baseline + amount * 0.012))
            holds[axis] = Hold(keys: keys, until: until)
            reconcile()
        } else {
            end(axis: axis)
        }
    }

    func tick(now: TimeInterval) {
        holds = holds.filter { $0.value.until > now }
        reconcile()
    }

    func end(axis: Int) {
        holds.removeValue(forKey: axis)
        reconcile()
        if holds.isEmpty { scrollRemainder = 0 }
    }

    func cancel() {
        holds.removeAll()
        reconcile()
        scrollRemainder = 0
    }

    private func reconcile() {
        var desired: [Int16] = []
        for axis in holds.keys.sorted() {
            for key in holds[axis]!.keys where !desired.contains(key) { desired.append(key) }
        }
        // Reference counting by union: ending pinch must not release a key still
        // owned by rotation. Release old direction before pressing the new one.
        for key in pressed.reversed() where !desired.contains(key) { sendKey(key, false) }
        for key in desired where !pressed.contains(key) { sendKey(key, true) }
        pressed = desired
    }
}
