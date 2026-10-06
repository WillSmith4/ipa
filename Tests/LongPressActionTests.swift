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
    }
}
