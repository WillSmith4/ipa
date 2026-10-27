import Foundation
import CoreGraphics

// Exercise the production handler with deterministic touch samples. Only UIKit
// events, the display timer and the transport boundary are substituted.
final class UIView: NSObject {}
final class UITouch: NSObject {
    enum TouchType { case direct, pencil }
    var type = TouchType.direct
    let old: CGPoint, current: CGPoint
    init(_ old: CGPoint, _ current: CGPoint) { self.old = old; self.current = current }
    func location(in view: UIView) -> CGPoint { current }
    func previousLocation(in view: UIView) -> CGPoint { old }
}
final class UIEvent: NSObject {
    let touches: Set<UITouch>
    init(_ touches: [UITouch]) { self.touches = Set(touches) }
}
enum UITouchUtil {
    static func touches(in view: UIView, from event: UIEvent) -> Set<UITouch> { event.touches }
    static func distance(between a: UITouch, and b: UITouch, in view: UIView) -> CGFloat {
        hypot(a.current.x - b.current.x, a.current.y - b.current.y)
    }
    static func previousDistance(between a: UITouch, and b: UITouch, in view: UIView) -> CGFloat {
        hypot(a.old.x - b.old.x, a.old.y - b.old.y)
    }
    static func midPointVector(between a: UITouch, and b: UITouch, in view: UIView) -> CGVector {
        CGVector(dx: (a.current.x + b.current.x - a.old.x - b.old.x) / 2,
                 dy: (a.current.y + b.current.y - a.old.y - b.old.y) / 2)
    }
}
final class FakeTimer { func pause() {}; func restart() {} }
final class InertialScroller {
    static var tick: (() -> Void)?
    var timer: FakeTimer? = FakeTimer()
    var vector = CGVector.zero
    init(decelerationRate: CGFloat, displayLinkRate: CGFloat, callback: @escaping () -> Void) {
        Self.tick = callback
    }
}
enum CommandManager { static let keyboardButtonMappings: [String: Int16] = ["CTRL": 17] }
let BUTTON_ACTION_RELEASE: Int32 = 8, BUTTON_LEFT: Int32 = 1, BUTTON_RIGHT: Int32 = 3
let KEY_ACTION_DOWN: Int32 = 3, KEY_ACTION_UP: Int32 = 4
enum Output { static var events: [String] = [] }
func LiSendMouseButtonEvent(_ action: CChar, _ button: Int32) { Output.events.append("mouse:\(button):\(action)") }
func LiSendKeyboardEvent(_ key: Int16, _ action: CChar, _ modifiers: UInt8) { Output.events.append("key:\(key):\(action)") }
func LiSendHighResScrollEvent(_ delta: Int16) { Output.events.append("vertical:\(delta)") }
func LiSendHighResHScrollEvent(_ delta: Int16) { Output.events.append("horizontal:\(delta)") }

@main
struct TouchpadGestureTests {
    static let view = UIView()
    static func event(dx: CGFloat = 0, dy: CGFloat = 0, spread: CGFloat = 0) -> UIEvent {
        UIEvent([
            UITouch(CGPoint(x: 0, y: 0), CGPoint(x: dx - spread, y: dy)),
            UITouch(CGPoint(x: 100, y: 0), CGPoint(x: 100 + dx + spread, y: dy))
        ])
    }
    static func reset() {
        TouchPadGestureHandler.cancel()
        TouchPadGestureHandler.enablePinch = true
        TouchPadGestureHandler.ctrlDownForPinch = false
        TouchPadGestureHandler.pinchSensitivity = 1
        TouchPadGestureHandler.scrollSensitivity = 1
        TouchPadGestureHandler.enableHorizontalScroll = true
        Output.events = []
    }
    static func main() {
        reset()
        TouchPadGestureHandler.scrollSensitivity = 2
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(dy: 5))
        precondition(Output.events == ["mouse:1:8", "mouse:3:8", "vertical:70"])
        Output.events = []
        InertialScroller.tick?()
        precondition(Output.events.contains("vertical:70"), "Original slide inertia must use scroll sensitivity")

        reset()
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(dx: 5, dy: 5))
        precondition(!Output.events.contains { $0.hasPrefix("horizontal:") }, "Retain original horizontal threshold")
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(dx: 7, dy: 5))
        precondition(Output.events.contains("horizontal:-49"))

        reset()
        TouchPadGestureHandler.pinchSensitivity = 2
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(spread: 5))
        precondition(Output.events.contains("vertical:140"), "Original pinch must use its own sensitivity")
        Output.events = []
        TouchPadGestureHandler.enablePinch = false
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(spread: 5))
        precondition(Output.events == ["mouse:1:8", "mouse:3:8", "vertical:0"], "Pinch Off must suppress pinch output")

        reset()
        TouchPadGestureHandler.ctrlDownForPinch = true
        TouchPadGestureHandler.handleTouchpadGesture(in: view, with: event(spread: 5))
        precondition(Output.events.contains("key:17:3") && TouchPadGestureHandler.ctrlDown)
        TouchPadGestureHandler.releaseControl()
        precondition(Output.events.last == "key:17:4", "Lifting fingers releases Control")
        Output.events = []
        InertialScroller.tick?()
        precondition(Output.events.isEmpty, "Pinch cannot produce residual wheel inertia")
        TouchPadGestureHandler.cancel()
        precondition(!TouchPadGestureHandler.ctrlDown)

        reset()
        TouchPadGestureHandler.handleGesture(in: view, with: event(spread: 5))
        precondition(!Output.events.contains { $0.hasPrefix("vertical:") || $0.hasPrefix("key:") },
                     "Single Point must not receive duplicate legacy pinch or Control output")
        print("Touchpad: original slide, pinch, sensitivities, Ctrl cleanup, inertia and Single Point isolation passed")
    }
}
