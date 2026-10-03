import Foundation

/// Host actions shared by the settings UI and the gesture runtime. Keyboard
/// chords use the same names as CommandManager (for example CTRL+Q).
enum GestureAction {
    static let defaults = ["SCROLL_DOWN", "SCROLL_UP", "Q", "E", "NONE"]
    static let presets = ["NONE", "SCROLL_DOWN", "SCROLL_UP"]

    enum Input: Equatable {
        case key(Int16)
        case mouse(Int32)
    }

    static func inputs(_ action: String, mappings: [String: Int16]) -> [Input]? {
        let mouse: [String: Int32] = ["MOUSE_LEFT": 1, "MOUSE_MIDDLE": 2, "MOUSE_RIGHT": 3]
        let names = action.uppercased().components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard names.allSatisfy({ mouse[$0] != nil || ($0 != "NULL" && mappings[$0] != nil) }) else { return nil }
        let keyNames = names.filter { mouse[$0] == nil }
        let keyboard = keyNames.isEmpty ? [] : keys(keyNames.joined(separator: "+"), mappings: mappings)!
        return keyboard.map(Input.key) + Array(Set(names.compactMap { mouse[$0] })).sorted().map(Input.mouse)
    }

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
        let inputs: [GestureAction.Input]
        var until: TimeInterval
    }
    private let mappings: [String: Int16]
    private let sendKey: (Int16, Bool) -> Void
    private let sendScroll: (Int16) -> Void
    private let sendMouse: (Int32, Bool) -> Void
    private var holds: [Int: Hold] = [:]
    private var pressed: [GestureAction.Input] = []
    private var scrollRemainder = 0.0

    var hasHolds: Bool { !holds.isEmpty }
    var hasTimedHolds: Bool { holds.values.contains { $0.until.isFinite } }

    init(mappings: [String: Int16], sendKey: @escaping (Int16, Bool) -> Void,
         sendScroll: @escaping (Int16) -> Void, sendMouse: @escaping (Int32, Bool) -> Void = { _, _ in }) {
        self.mappings = mappings
        self.sendKey = sendKey
        self.sendScroll = sendScroll
        self.sendMouse = sendMouse
    }

    /// Each axis owns a hold. Movement extends its deadline instead of sending
    /// repeated keydowns. Larger/faster movement buys more continuous hold time,
    /// capped at 450 ms of idle time; lifting fingers always releases immediately.
    func move(axis: Int, action: String, amount: Double, now: TimeInterval, controlScroll: Bool = false) {
        guard amount.isFinite, amount > 0, now.isFinite else { return }
        if action == "SCROLL_UP" || action == "SCROLL_DOWN" {
            let keys: [Int16] = controlScroll ? [0x11] : []
            holds[axis] = keys.isEmpty ? nil : Hold(inputs: keys.map(GestureAction.Input.key), until: now + 0.12)
            reconcile()
            let units = min(Double(Int16.max), amount * 7)
            scrollRemainder += (action == "SCROLL_UP" ? 1 : -1) * units
            // Preserve sub-unit motion and bound conversion for extreme samples.
            let whole = min(Double(Int16.max), max(Double(Int16.min), scrollRemainder.rounded(.towardZero)))
            if whole != 0 {
                sendScroll(Int16(whole))
                scrollRemainder -= whole
            }
        } else if let inputs = GestureAction.inputs(action, mappings: mappings) {
            let previous = holds[axis]
            let baseline = previous?.inputs == inputs ? max(now, previous!.until) : now
            // Mouse drags stay down through pauses until lift/reversal/cancellation.
            // Keep every component of a mixed chord down for the same lifetime.
            let isDrag = inputs.contains { if case .mouse = $0 { return true }; return false }
            let until = isDrag ? TimeInterval.infinity : min(now + 0.45, max(now + 0.07, baseline + amount * 0.012))
            holds[axis] = Hold(inputs: inputs, until: until)
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
        var desired: [GestureAction.Input] = []
        for axis in holds.keys.sorted() {
            for key in holds[axis]!.inputs where !desired.contains(key) { desired.append(key) }
        }
        // Reference counting by union: ending pinch must not release a key still
        // owned by rotation. Release old direction before pressing the new one.
        for key in pressed.reversed() where !desired.contains(key) { send(key, down: false) }
        for key in desired where !pressed.contains(key) { send(key, down: true) }
        pressed = desired
    }

    private func send(_ input: GestureAction.Input, down: Bool) {
        switch input {
        case .key(let key): sendKey(key, down)
        case .mouse(let button): sendMouse(button, down)
        }
    }
}

/// Tracks the centre of all fingers, matching translation of the whole hand.
/// Changing the touch set rebases without a cursor jump.
struct GesturePointerMotion {
    struct Point { let id: Int; let x: Double; let y: Double }
    private var previous: [Int: Point] = [:]
    private var remainderX = 0.0
    private var remainderY = 0.0

    mutating func sample(_ points: [Point]) -> (x: Double, y: Double) {
        let current = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        defer { previous = current }
        guard Set(current.keys) == Set(previous.keys), (1...2).contains(points.count) else { return (0, 0) }
        let count = Double(points.count)
        return points.reduce((x: 0.0, y: 0.0)) { result, p in
            (result.x + (p.x - previous[p.id]!.x) / count, result.y + (p.y - previous[p.id]!.y) / count)
        }
    }

    mutating func cursor(dx: Double, dy: Double, speed: Double) -> (Int16, Int16) {
        guard dx.isFinite, dy.isFinite, speed.isFinite, speed >= 0 else { return (0, 0) }
        func bounded(_ value: Double) -> Double { min(Double(Int16.max), max(Double(Int16.min), value)) }
        remainderX += bounded(dx * 1.35 * speed)
        remainderY += bounded(dy * 1.35 * speed)
        let x = bounded(remainderX.rounded(.towardZero)), y = bounded(remainderY.rounded(.towardZero))
        remainderX -= x
        remainderY -= y
        return (Int16(x), Int16(y))
    }

    mutating func reset() { self = GesturePointerMotion() }
}

/// Signed angle between consecutive two-finger vectors. As with the supplied
/// AlloyFinger current/previous-vector calculation, positive means clockwise
/// in screen coordinates (y down). atan2 avoids acos rounding away tiny angles.
struct GestureRotationMotion {
    private var ids: [Int] = []
    private var previous: (x: Double, y: Double)?

    mutating func sample(_ points: [GesturePointerMotion.Point]) -> Double? {
        guard points.count == 2 else { reset(); return nil }
        let pair = points.sorted { $0.id < $1.id }
        let pairIDs = pair.map { $0.id }
        let x = pair[1].x - pair[0].x, y = pair[1].y - pair[0].y
        let length = hypot(x, y)
        guard x.isFinite, y.isFinite, length.isFinite, length > 0 else { reset(); return nil }
        let vector = (x: x / length, y: y / length)
        let old = ids == pairIDs ? previous : nil
        ids = pairIDs
        previous = vector
        guard let old else { return nil }
        let cross = old.x * vector.y - old.y * vector.x
        let dot = old.x * vector.x + old.y * vector.y
        // Suppress floating-point roundoff for collinear vectors so pure pan or
        // pinch cannot become a rotation. This is at machine precision only.
        if dot > 0 && abs(cross) <= 8 * Double.ulpOfOne { return 0 }
        return atan2(cross, dot) * 180 / .pi
    }

    mutating func reset() { ids = []; previous = nil }
}
