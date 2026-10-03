import Foundation

@main
struct GestureActionEngineTests {
    static func main() {
        let mappings: [String: Int16] = ["Q": 0x51, "E": 0x45, "W": 0x57, "D": 0x44, "CTRL": 0x11, "SHIFT": 0x10, "NULL": 0xFF]
        var events: [String] = []
        var scroll: [Int16] = []
        let engine = GestureActionEngine(mappings: mappings,
            sendKey: { events.append("\($0):\($1 ? "down" : "up")") },
            sendScroll: { scroll.append($0) },
            sendMouse: { events.append("mouse\($0):\($1 ? "down" : "up")") })
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }

        // Sustained motion sends exactly one down, and one up on finger lift.
        for i in 0..<120 {
            let time = Double(i) / 120
            engine.move(axis: 1, action: "Q", amount: 1, now: time)
            engine.tick(now: time)
        }
        check(events == ["81:down"], "Keydown must not repeat during a hold")
        engine.end(axis: 1)
        check(events == ["81:down", "81:up"], "Finger lift must release immediately")

        events.removeAll()
        engine.move(axis: 1, action: "Q", amount: 10, now: 2)
        engine.move(axis: 1, action: "E", amount: 10, now: 2.01)
        check(events == ["81:down", "81:up", "69:down"], "Reversal must release Q before E")
        engine.cancel()
        check(events.last == "69:up", "Cancellation must release the current direction")

        events.removeAll()
        engine.move(axis: 0, action: "CTRL+Q", amount: 5, now: 3)
        engine.move(axis: 1, action: "CTRL+Q", amount: 5, now: 3)
        engine.end(axis: 0)
        check(events == ["17:down", "81:down"], "An overlapping gesture still owns both keys")
        engine.end(axis: 1)
        check(events == ["17:down", "81:down", "81:up", "17:up"], "Release main key before modifier")

        events.removeAll()
        engine.move(axis: 1, action: "Q", amount: 1, now: 4)
        engine.tick(now: 4.1)
        check(!engine.hasHolds, "Small motion gets a short hold")
        engine.move(axis: 1, action: "Q", amount: 20, now: 5)
        engine.tick(now: 5.1)
        check(engine.hasHolds, "Stronger motion gets a longer hold")
        engine.tick(now: 5.5)
        check(!engine.hasHolds, "Idle timeout prevents stuck keys")

        events.removeAll()
        engine.move(axis: 1, action: "Q", amount: 1_000_000, now: 6)
        engine.tick(now: 6.451)
        check(!engine.hasHolds, "Even extreme motion has bounded idle time")
        engine.move(axis: 1, action: "Q", amount: .nan, now: 7)
        check(!engine.hasHolds, "Ignore nonfinite motion")
        engine.move(axis: 1, action: "Q", amount: 1, now: 8)
        engine.move(axis: 1, action: "NONE", amount: 1, now: 8.01)
        check(!engine.hasHolds, "Disabled action releases previous direction")

        for _ in 0..<10 { engine.move(axis: 0, action: "SCROLL_DOWN", amount: 0.1, now: 9) }
        check(scroll.reduce(0, { $0 + Int($1) }) == -7, "Preserve fractional downward scrolling")
        scroll.removeAll()
        engine.cancel()
        engine.move(axis: 0, action: "SCROLL_UP", amount: 10, now: 10, controlScroll: true)
        check(scroll == [70], "Pinch out scrolls upward")
        check(events.last == "17:down", "Ctrl is pressed before modified scroll")
        engine.end(axis: 0)
        check(events.last == "17:up", "Ctrl is released after pinch")

        scroll.removeAll()
        engine.move(axis: 0, action: "SCROLL_UP", amount: Double.greatestFiniteMagnitude, now: 11)
        engine.move(axis: 0, action: "SCROLL_DOWN", amount: 1, now: 11.1)
        check(scroll == [Int16.max, -7], "Extreme samples must not leave a backlog of scroll events")

        check(GestureAction.keys("q + ctrl + Q", mappings: mappings) == [0x11, 0x51], "Normalize and deduplicate chords")
        check(GestureAction.keys("Q+", mappings: mappings) == nil, "Reject empty chord components")
        check(GestureAction.keys("NULL", mappings: mappings) == nil, "Do not send the NULL sentinel")
        check(GestureAction.keys("UNKNOWN", mappings: mappings) == nil, "Reject unsupported keys")
        engine.cancel()
        events.removeAll()
        engine.move(axis: 2, action: "W+D", amount: 10, now: 20)
        check(events == ["68:down", "87:down"], "Both ordinary keys must be held together")
        engine.cancel()
        events.removeAll()
        for i in 0..<120 {
            engine.move(axis: 2, action: "MOUSE_MIDDLE", amount: 2, now: 21 + Double(i) / 120)
        }
        engine.tick(now: 60)
        check(events == ["mouse2:down"] && engine.hasHolds && !engine.hasTimedHolds, "Camera drag remains continuous through movement and pauses")
        engine.end(axis: 2)
        check(events == ["mouse2:down", "mouse2:up"], "Finger lift ends the drag")
        events.removeAll()
        engine.move(axis: 0, action: "CTRL+MOUSE_RIGHT", amount: 5, now: 70)
        engine.move(axis: 1, action: "CTRL+MOUSE_RIGHT", amount: 5, now: 70)
        engine.end(axis: 0)
        engine.tick(now: 90)
        check(events == ["17:down", "mouse3:down"], "Overlapping mouse chords share ownership and retain their modifier")
        engine.move(axis: 1, action: "MOUSE_LEFT", amount: 1, now: 91)
        check(events.suffix(3) == ["mouse3:up", "17:up", "mouse1:down"], "Reversal releases the old drag before pressing the new one")
        engine.cancel()
        check(events.last == "mouse1:up", "Cancellation must release mouse buttons")
        check(GestureAction.inputs("ctrl + MOUSE_MIDDLE + CTRL", mappings: mappings) == [.key(0x11), .mouse(2)], "Mixed chords normalize and deduplicate")
        for invalid in ["", "MOUSE_MIDDLE+", "MOUSE_UNKNOWN", "MOUSE_LEFT+UNKNOWN", "WHEELUP", "NULL+MOUSE_LEFT"] {
            check(GestureAction.inputs(invalid, mappings: mappings) == nil, "Reject invalid or non-stateful mouse actions: \(invalid)")
        }

        var pointer = GesturePointerMotion()
        typealias Point = GesturePointerMotion.Point
        func sample(_ points: [Point]) -> (Double, Double) { pointer.sample(points) }
        check(sample([.init(id: 0, x: 50, y: 50)]) == (0, 0), "Touch down must not warp the cursor")
        check(sample([.init(id: 0, x: 55, y: 40)]) == (5, -10), "Swipe follows both axes")
        check(sample([.init(id: 0, x: 55, y: 40), .init(id: 1, x: 155, y: 40)]) == (0, 0), "Adding a finger rebases without a jump")
        check(sample([.init(id: 0, x: 45, y: 30), .init(id: 1, x: 165, y: 30)]) == (0, -10), "Pinch plus upward hand motion moves the cursor upward")
        check(sample([.init(id: 1, x: 165, y: 40), .init(id: 0, x: 45, y: 20)]) == (0, 0), "Symmetric rotation has no translation; touch order is irrelevant")
        check(sample([.init(id: 0, x: 45, y: 20)]) == (0, 0), "Lifting one finger cannot jump the cursor")
        var totalX = 0
        for _ in 0..<10 { totalX += Int(pointer.cursor(dx: 0.2, dy: 0, speed: 1).0) }
        check(totalX == 2, "Slow subpixel cursor motion is accumulated")
        pointer.reset()
        check(pointer.cursor(dx: -10, dy: 10, speed: 2) == (-27, 27), "Cursor uses existing touchpad speed and preserves direction")
        check(pointer.cursor(dx: .nan, dy: 10, speed: 1) == (0, 0), "Ignore invalid cursor samples")
        check(pointer.cursor(dx: Double.greatestFiniteMagnitude, dy: 0, speed: 3).0 == Int16.max, "Bound transport values without overflow")
        check(pointer.cursor(dx: -1, dy: 0, speed: 1).0 == -1, "Extreme movement leaves no cursor backlog")

        var rotation = GestureRotationMotion()
        func fingers(angle: Double, radius: Double = 100, x: Double = 0, y: Double = 0) -> [Point] {
            [.init(id: 10, x: x, y: y),
             .init(id: 20, x: x + cos(angle * .pi / 180) * radius, y: y + sin(angle * .pi / 180) * radius)]
        }
        func near(_ actual: Double?, _ expected: Double, _ message: String) {
            check(actual != nil && abs(actual! - expected) < 1e-8, message)
        }
        check(rotation.sample(fingers(angle: 0)) == nil, "Second finger primes rotation without an initial jump")
        near(rotation.sample(fingers(angle: 0.000001)), 0.000001, "Tiny arcs are detected without an angle dead zone")
        near(rotation.sample(fingers(angle: 90)), 89.999999, "Clockwise screen rotation selects the right binding")
        near(rotation.sample(fingers(angle: 45)), -45, "Reversing the moving finger selects the left binding")
        check(rotation.sample(fingers(angle: 45, radius: 200, x: 25, y: -30)) == 0, "Translation and radial pinch cannot start rotation from rounding noise")
        near(rotation.sample(Array(fingers(angle: 60, radius: 200, x: 25, y: -30).reversed())), 15, "Touch identity is stable regardless of array order")
        rotation.reset()
        _ = rotation.sample(fingers(angle: 179))
        near(rotation.sample(fingers(angle: -179)), 2, "Crossing the angle boundary follows the short arc")
        near(rotation.sample(fingers(angle: 179)), -2, "Boundary crossing preserves reverse direction")
        check(rotation.sample([.init(id: 10, x: 0, y: 0)]) == nil, "Lifting either finger resets rotation")
        check(rotation.sample(fingers(angle: 90)) == nil, "A new pair starts a fresh vector")
        check(rotation.sample([.init(id: 10, x: 0, y: 0), .init(id: 30, x: 100, y: 0)]) == nil, "Replacing a finger cannot create a spurious angle")
        check(rotation.sample(fingers(angle: 0, radius: 0)) == nil, "Coincident touches cannot produce invalid angles")
        check(rotation.sample(fingers(angle: 0)) == nil, "Rebase after a degenerate vector")
        var withThirdFinger = fingers(angle: 15)
        withThirdFinger.append(.init(id: 30, x: 50, y: 50))
        check(rotation.sample(withThirdFinger) == nil, "A third finger terminates this two-finger rotation")
        check(rotation.sample(fingers(angle: 15)) == nil, "Removing a third finger does not synthesize an angle")
        print("GestureActionEngine: all checks passed")
    }
}
