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
    var view: UIView?
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {}
    func reset() { state = .possible }
}

@main struct SwipeStartTests {
    static func main() {
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
