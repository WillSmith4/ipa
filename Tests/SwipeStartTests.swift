import Foundation
import CoreGraphics

// UIKit delivery is replaced; the recognizer body is copied from production.
class UIView {}
class UIEvent {}
class UITouch: NSObject {
    var position: CGPoint
    var previous: CGPoint
    init(_ point: CGPoint) { position = point; previous = point }
    func location(in view: UIView?) -> CGPoint { position }
    func previousLocation(in view: UIView?) -> CGPoint { previous }
    func move(_ point: CGPoint) { previous = position; position = point }
}
class UIGestureRecognizer {
    enum State { case possible, began, changed, ended, cancelled, failed }
    var state = State.possible
    var isEnabled = true
    var view: UIView?
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {}
    func reset() { state = .possible }
}

@main struct SwipeStartTests {
    static func main() {
        let routing = GestureRoutingHarness()
        routing.singlePointMode = true
        routing.updateEnabled()
        precondition(!routing.swipe.isEnabled,
                     "Single Point MOUSE_LEFT must reach AbsoluteTouchHandler without swipe cancellation or extra anchoring")
        precondition(routing.pinch.isEnabled && routing.rotation.isEnabled && routing.motionObserver.isEnabled,
                     "Restore finger drag without disabling the two-finger gestures")
        routing.singlePointMode = false
        routing.updateEnabled()
        precondition(!routing.swipe.isEnabled && !routing.pinch.isEnabled && !routing.rotation.isEnabled && !routing.motionObserver.isEnabled && !routing.twoFingerTap.isEnabled,
                     "Touchpad must use only its original handlers, regardless of Single Point bindings")
        routing.singlePointMode = true
        for action in ["NONE", "MOUSE_RIGHT", "MOUSE_MIDDLE", "CTRL+MOUSE_LEFT", "W", "SCROLL_UP", "SCROLL_DOWN"] {
            routing.actions[3] = action
            routing.updateEnabled()
            precondition(routing.swipe.isEnabled, "Other Single Point bindings retain their existing path: \(action)")
        }
        precondition(routing.twoFingerTap.isEnabled, "Enable the configured Single Point tap")
        routing.twoFingerTapAction.enabled = false
        routing.updateEnabled()
        precondition(!routing.twoFingerTap.isEnabled, "Off must disable tap detection")
        routing.enabled = false
        routing.updateEnabled()
        precondition(!routing.swipe.isEnabled && !routing.pinch.isEnabled && !routing.rotation.isEnabled && !routing.motionObserver.isEnabled,
                     "Closing or disabling input must still disable all recognizers")
        print("Gesture routing: original Touchpad, original Single Point left drag, configurable two-finger tap")

        let recognizer = StreamSwipeRecognizer(), event = UIEvent()
        var starts: [CGPoint] = []
        recognizer.onTouchDown = { starts.append($0) }
        let finger = UITouch(CGPoint(x: 100, y: 200))
        recognizer.touchesBegan([finger], with: event)
        precondition(starts == [finger.position] && recognizer.state == .possible,
                     "Send the initial position on down, before recognizing a swipe or pressing any button")
        finger.move(CGPoint(x: 108, y: 200))
        recognizer.touchesMoved([finger], with: event)
        precondition(recognizer.state == .possible, "Keep the existing 6*sqrt(2) movement threshold")
        finger.move(CGPoint(x: 109, y: 200))
        recognizer.touchesMoved([finger], with: event)
        precondition(recognizer.state == .began && starts.count == 1,
                     "Recognition must not reposition the cursor again")
        recognizer.touchesEnded([finger], with: event)
        precondition(recognizer.state == .ended)
        recognizer.reset()
        let other = UITouch(CGPoint(x: 400, y: 500))
        recognizer.touchesBegan([other], with: event)
        precondition(starts.last == other.position && starts.count == 2)
        recognizer.touchesBegan([finger], with: event)
        precondition(starts.count == 2 && recognizer.state == .failed,
                     "A second finger must not start another one-finger anchor")
        print("Swipe start: immediate position, unchanged movement threshold, no synthetic tap, fresh anchor on next touch")
    }
}
