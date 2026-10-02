import Foundation

@main
struct GestureActionEngineTests {
    static func main() {
        let mappings: [String: Int16] = ["Q": 0x51, "E": 0x45, "CTRL": 0x11, "SHIFT": 0x10, "NULL": 0xFF]
        var events: [String] = []
        var scroll: [Int16] = []
        let engine = GestureActionEngine(mappings: mappings,
            sendKey: { events.append("\($0):\($1 ? "down" : "up")") },
            sendScroll: { scroll.append($0) })
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

        check(GestureAction.keys("q + ctrl + Q", mappings: mappings) == [0x11, 0x51], "Normalize and deduplicate chords")
        check(GestureAction.keys("Q+", mappings: mappings) == nil, "Reject empty chord components")
        check(GestureAction.keys("NULL", mappings: mappings) == nil, "Do not send the NULL sentinel")
        check(GestureAction.keys("UNKNOWN", mappings: mappings) == nil, "Reject unsupported keys")
        engine.cancel()
        print("GestureActionEngine: all checks passed")
    }
}
