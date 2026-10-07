import Foundation

// Record only the transport boundary. The compiled action bridge and key map
// come directly from the production files, including Objective-C exposure.
enum CommandManager { static let keyboardButtonMappings = GestureTestKeyboard.keyboardButtonMappings }
let KEY_ACTION_DOWN: Int32 = 0x03
let KEY_ACTION_UP: Int32 = 0x04
let BUTTON_ACTION_PRESS: Int32 = 0x07
let BUTTON_ACTION_RELEASE: Int32 = 0x08
enum RecordedInput { static var events: [String] = [] }
func LiSendKeyboardEvent(_ key: Int16, _ action: CChar, _ modifiers: UInt8) -> Int32 {
    precondition(UInt16(bitPattern: key) & 0x8000 != 0 && modifiers == 0)
    RecordedInput.events.append("key\(UInt16(bitPattern: key) & 0x7FFF):\(action == CChar(KEY_ACTION_DOWN) ? "down" : "up")")
    return 0
}
func LiSendHighResScrollEvent(_ amount: Int16) -> Int32 {
    RecordedInput.events.append("scroll\(amount)")
    return 0
}
func LiSendMouseButtonEvent(_ action: CChar, _ button: Int32) -> Int32 {
    RecordedInput.events.append("mouse\(button):\(action == CChar(BUTTON_ACTION_PRESS) ? "down" : "up")")
    return 0
}

@main
struct LongPressActionTests {
    static func main() {
        for (binding, down, up) in [
            ("MOUSE_RIGHT", ["mouse3:down"], ["mouse3:up"]),
            ("MOUSE_LEFT", ["mouse1:down"], ["mouse1:up"]),
            ("MOUSE_MIDDLE", ["mouse2:down"], ["mouse2:up"]),
            ("CTRL++", ["key16:down", "key17:down", "key187:down"], ["key187:up", "key17:up", "key16:up"]),
            ("-", ["key189:down"], ["key189:up"]),
            ("CTRL+MOUSE_MIDDLE", ["key17:down", "mouse2:down"], ["mouse2:up", "key17:up"])
        ] {
            RecordedInput.events = []
            let action = GestureLongPressAction(action: binding)
            precondition(action.enabled)
            action.press()
            precondition(RecordedInput.events == down, "Long press must send the selected input: \(binding)")
            action.cancel()
            precondition(RecordedInput.events == down + up, "Pulse end/cancellation must release the entire chord")
            action.cancel()
            precondition(RecordedInput.events == down + up, "Repeated cleanup must not duplicate release events")
        }
        for binding in ["NONE", "NULL", "UNKNOWN"] {
            RecordedInput.events = []
            let action = GestureLongPressAction(action: binding)
            precondition(!action.enabled)
            action.press()
            action.cancel()
            precondition(RecordedInput.events.isEmpty, "Off/invalid input must not click or press a key")
        }
        for (binding, amount) in [("SCROLL_UP", 120), ("SCROLL_DOWN", -120)] {
            RecordedInput.events = []
            let action = GestureLongPressAction(action: binding)
            action.press()
            action.cancel()
            precondition(RecordedInput.events == ["scroll\(amount)"], "A wheel binding sends one notch")
        }
        RecordedInput.events = []
        var action: GestureLongPressAction? = GestureLongPressAction(action: "ALT+Q")
        action?.press()
        action = nil
        precondition(RecordedInput.events == ["key18:down", "key81:down", "key81:up", "key18:up"],
                     "Destroying the handler cannot leave a modifier or key held")
        print("Long press: configured keyboard/mouse pulses, Off and cleanup passed")
        testDoubleTapDrag()
        testSwipeDrag()
    }

    static func testSwipeDrag() {
        // Swipe enters the same drag owner directly, without generating a tap
        // first. Every selected key/button stays down while the finger pauses.
        for (binding, down, up) in [
            ("MOUSE_LEFT", ["mouse1:down"], ["mouse1:up"]),
            ("MOUSE_RIGHT", ["mouse3:down"], ["mouse3:up"]),
            ("MOUSE_MIDDLE", ["mouse2:down"], ["mouse2:up"]),
            ("W+D", ["key68:down", "key87:down"], ["key87:up", "key68:up"]),
            ("CTRL+MOUSE_LEFT", ["key17:down", "mouse1:down"], ["mouse1:up", "key17:up"])
        ] {
            RecordedInput.events = []
            let swipe = GestureDoubleTapDragAction(action: binding)
            swipe.begin()
            swipe.begin()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            precondition(swipe.dragging && RecordedInput.events == down,
                         "Swipe must hold \(binding) without a first tap, repeats or idle release")
            swipe.cancel()
            swipe.cancel()
            precondition(RecordedInput.events == down + up)
        }
        RecordedInput.events = []
        let off = GestureDoubleTapDragAction(action: "NONE")
        off.begin()
        off.cancel()
        precondition(RecordedInput.events.isEmpty, "Swipe Off must not acquire a default left hold")

        RecordedInput.events = []
        let swipe = GestureDoubleTapDragAction(action: "MOUSE_MIDDLE")
        let rotation = GestureLongPressAction(action: "MOUSE_MIDDLE")
        swipe.begin()
        swipe.cancel() // adding the second finger ends Swipe before Rotation
        rotation.press()
        swipe.cancel() // end-of-frame cleanup must not release Rotation's hold
        precondition(RecordedInput.events == ["mouse2:down", "mouse2:up", "mouse2:down"])
        rotation.cancel()
        precondition(RecordedInput.events.last == "mouse2:up")
        print("Swipe drag: shared double-tap holds, no synthetic tap, Off and two-finger handoff passed")
    }

    static func testDoubleTapDrag() {
        precondition(GestureDoubleTapDetection.isQuickTap(from: .zero, to: CGPoint(x: 180, y: 240), elapsed: 0.19))
        precondition(!GestureDoubleTapDetection.isQuickTap(from: .zero, to: .zero, elapsed: GestureDoubleTapDetection.interval))
        precondition(!GestureDoubleTapDetection.isQuickTap(from: .zero, to: CGPoint(x: 301, y: 0), elapsed: 0.1))
        precondition(GestureDoubleTapDetection.isQuickTap(from: CGPoint(x: 320, y: 200), to: CGPoint(x: 20, y: 200), elapsed: 0.1))

        // A normal tap still presses immediately, then releases at the original
        // handler's deadline. It is never postponed to wait for a second tap.
        for binding in ["MOUSE_LEFT", "NONE", "CTRL++", "MOUSE_RIGHT"] {
            RecordedInput.events = []
            let action = GestureDoubleTapDragAction(action: binding)
            action.firstTap()
            precondition(RecordedInput.events == ["mouse1:down"])
            action.expireFirstTap()
            precondition(RecordedInput.events == ["mouse1:down", "mouse1:up"])
            precondition(!action.dragging)
        }

        RecordedInput.events = []
        let left = GestureDoubleTapDragAction(action: "MOUSE_LEFT")
        left.firstTap()
        left.begin()
        left.expireFirstTap()
        left.begin()
        precondition(left.dragging && left.usesLeftButton)
        precondition(RecordedInput.events == ["mouse1:down"],
                     "The default drag continues the first click with no release/repress")
        left.cancel()
        left.cancel()
        precondition(RecordedInput.events == ["mouse1:down", "mouse1:up"])

        for (binding, down, up) in [
            ("MOUSE_RIGHT", ["mouse3:down"], ["mouse3:up"]),
            ("MOUSE_MIDDLE", ["mouse2:down"], ["mouse2:up"]),
            ("CTRL+MOUSE_LEFT", ["key17:down", "mouse1:down"], ["mouse1:up", "key17:up"]),
            ("CTRL++", ["key16:down", "key17:down", "key187:down"], ["key187:up", "key17:up", "key16:up"]),
            ("-", ["key189:down"], ["key189:up"])
        ] {
            RecordedInput.events = []
            let action = GestureDoubleTapDragAction(action: binding)
            action.firstTap()
            action.begin()
            let pressed = ["mouse1:down", "mouse1:up"] + down
            precondition(RecordedInput.events == pressed,
                         "Second touch must replace the first tap's left hold with \(binding)")
            action.expireFirstTap()
            action.firstTap() // delayed first-tap callback must not interrupt the drag
            action.begin()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            precondition(action.dragging && RecordedInput.events == pressed,
                         "Even keyboard-only drag bindings remain held during a stationary second touch")
            action.cancel()
            action.cancel()
            action.expireFirstTap()
            precondition(!action.dragging && RecordedInput.events == pressed + up,
                         "Lift/cancel/profile change releases the whole drag input exactly once")
        }

        for binding in ["NONE", "UNKNOWN"] {
            RecordedInput.events = []
            let action = GestureDoubleTapDragAction(action: binding)
            action.firstTap()
            action.begin()
            precondition(!action.enabled && !action.dragging)
            precondition(RecordedInput.events == ["mouse1:down", "mouse1:up"],
                         "Off ends the ordinary first click instead of turning it into a drag")
            action.expireFirstTap()
            action.cancel()
            precondition(RecordedInput.events.count == 2)
        }

        for binding in ["MOUSE_LEFT", "CTRL+MOUSE_LEFT"] {
            RecordedInput.events = []
            var action: GestureDoubleTapDragAction? = GestureDoubleTapDragAction(action: binding)
            action?.firstTap()
            action?.begin()
            action = nil
            let expected = binding == "MOUSE_LEFT" ? ["mouse1:down", "mouse1:up"] :
                ["mouse1:down", "mouse1:up", "key17:down", "mouse1:down", "mouse1:up", "key17:up"]
            precondition(RecordedInput.events == expected, "Destroying the touchpad releases drag inputs")
        }
        print("Double-tap drag: immediate clicks, uninterrupted left drag, custom holds, Off and cleanup passed")
    }
}
