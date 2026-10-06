import Foundation

@main
struct GestureActionEngineTests {
    static func main() {
        let mappings = GestureTestKeyboard.keyboardButtonMappings
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
        for (name, code) in mappings where name != "NULL" {
            check(GestureAction.inputs(name, mappings: mappings) == [.key(code)], "Keep every existing key assignable: \(name)")
        }
        for number in 1...24 {
            check(GestureAction.keys("F\(number)", mappings: mappings) == [Int16(0x6F + number)], "Support all function keys")
        }
        for plus in ["+", "PLUS", "SHIFT+EQUALS", "SHIFT++", "+++", "PLUS+PLUS"] {
            check(GestureAction.keys(plus, mappings: mappings) == [0x10, 0xBB], "Plus must press Shift and the equals key once: \(plus)")
        }
        for minus in ["-", "MINUS"] {
            check(GestureAction.keys(minus, mappings: mappings) == [0xBD], "Minus must not add a modifier")
        }
        check(GestureAction.keys("CTRL++", mappings: mappings) == [0x10, 0x11, 0xBB], "Literal plus can follow a chord separator")
        check(GestureAction.keys("++CTRL", mappings: mappings) == [0x10, 0x11, 0xBB], "Literal plus can precede a chord separator")
        check(GestureAction.keys("CTRL+PLUS", mappings: mappings) == [0x10, 0x11, 0xBB], "PLUS is an unambiguous chord name")
        check(GestureAction.keys("ctrl + -", mappings: mappings) == [0x11, 0xBD], "Minus works in a chord")
        check(GestureAction.keys("=", mappings: mappings) == [0xBB], "Equals keeps the unshifted physical key available")
        check(GestureAction.keys("ADD", mappings: mappings) == [0x6B], "Numpad plus remains distinct")
        check(GestureAction.keys("SUBTRACT", mappings: mappings) == [0x6D], "Numpad minus remains distinct")
        let plainSymbols: [(String, Int16)] = [(",", 0xBC), (".", 0xBE), ("/", 0xBF), (";", 0xBA),
            ("'", 0xDE), ("`", 0xC0), ("[", 0xDB), ("]", 0xDD), ("\\", 0xDC)]
        for (symbol, code) in plainSymbols {
            check(GestureAction.keys(symbol, mappings: mappings) == [code], "Accept punctuation keys: \(symbol)")
        }
        let shiftedSymbols: [(String, Int16)] = [("!", 0x31), ("@", 0x32), ("#", 0x33), ("$", 0x34),
            ("%", 0x35), ("^", 0x36), ("&", 0x37), ("*", 0x38), ("(", 0x39), (")", 0x30),
            ("_", 0xBD), (":", 0xBA), ("\"", 0xDE), ("<", 0xBC), (">", 0xBE), ("?", 0xBF),
            ("~", 0xC0), ("{", 0xDB), ("}", 0xDD), ("|", 0xDC)]
        for (symbol, code) in shiftedSymbols {
            check(GestureAction.keys(symbol, mappings: mappings) == [0x10, code], "Shifted symbols use the existing keyboard convention: \(symbol)")
        }
        for invalid in ["++", "CTRL+", "CTRL++Q", "CTRL+++", "PLUS+UNKNOWN", "F25", "F013"] {
            check(GestureAction.inputs(invalid, mappings: mappings) == nil, "Reject malformed chords: \(invalid)")
        }
        check(GestureAction.inputs("MOUSE_MIDDLE++", mappings: mappings) == [.key(0x10), .key(0xBB), .mouse(2)], "Symbols also work with mouse bindings")
        engine.cancel()
        events.removeAll()
        engine.move(axis: 0, action: "+", amount: 10, now: 12)
        check(events == ["16:down", "187:down"], "Pinch plus presses the modifier before the key")
        engine.move(axis: 0, action: "-", amount: 10, now: 12.01)
        check(events == ["16:down", "187:down", "187:up", "16:up", "189:down"], "Pinch reversal releases plus and Shift before minus")
        engine.end(axis: 0)
        check(events.last == "189:up", "Finger lift releases minus")
        events.removeAll()
        engine.move(axis: 0, action: "+", amount: 10, now: 13)
        engine.move(axis: 1, action: "SHIFT+Q", amount: 10, now: 13)
        engine.end(axis: 0)
        check(events == ["16:down", "187:down", "81:down", "187:up"], "Another gesture keeps ownership of Shift after plus ends")
        engine.cancel()
        check(events.suffix(2) == ["81:up", "16:up"], "Cancellation releases every remaining key")
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

        var anchor = GestureCursorAnchor()
        anchor.sample([.init(id: 1, x: 50, y: 60)])
        anchor.sample([.init(id: 1, x: 80, y: 90)])
        check(anchor.takeOrigin(fingerCount: 2) == nil, "An unmatched gesture cannot consume the start position")
        check(anchor.takeOrigin(fingerCount: 1) == .init(x: 50, y: 60), "Swipe anchors at touch down, not the recognition location")
        anchor.sample([.init(id: 1, x: 100, y: 90)])
        check(anchor.takeOrigin(fingerCount: 1) == nil, "Continuing a gesture must not warp again")
        anchor.sample([.init(id: 1, x: 100, y: 90), .init(id: 2, x: 200, y: 110)])
        anchor.sample([.init(id: 2, x: 230, y: 140), .init(id: 1, x: 90, y: 80)])
        check(anchor.takeOrigin(fingerCount: 2) == .init(x: 150, y: 100), "Two-finger gestures anchor at the original midpoint")
        check(anchor.takeOrigin(fingerCount: 2) == nil, "Simultaneous pinch and rotation share one initial teleport")
        anchor.sample([])
        anchor.sample([.init(id: 3, x: 10, y: 20), .init(id: 4, x: 30, y: 40)])
        check(anchor.takeOrigin(fingerCount: 2) == .init(x: 20, y: 30), "The next gesture gets its own midpoint")
        anchor.sample([.init(id: 5, x: 10, y: 20), .init(id: 6, x: 30, y: 40)])
        anchor.reset()
        check(anchor.takeOrigin(fingerCount: 2) == nil, "Cancellation discards a pending teleport")
        anchor.sample([.init(id: 5, x: 10, y: 20), .init(id: 6, x: 30, y: 40)])
        anchor.sample([.init(id: 5, x: 10, y: 20), .init(id: 6, x: 30, y: 40), .init(id: 7, x: 50, y: 60)])
        check(anchor.takeOrigin(fingerCount: 2) == nil, "A third finger invalidates the two-finger anchor")
        anchor.sample([.init(id: 1, x: .nan, y: 0)])
        check(anchor.takeOrigin(fingerCount: 1) == nil, "Invalid positions cannot teleport the cursor")

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
        near(rotation.sample(fingers(angle: 90)), 89.999999, "Clockwise screen rotation produces a positive angle")
        near(rotation.sample(fingers(angle: 45)), -45, "Reversing the moving finger produces a negative angle")
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
        // Exercise the actual angle -> relative mouse path. Unlike following a
        // finger's XY position, a continuous twist cannot reverse direction as
        // that finger travels around the lower half of its circle.
        func orbit(_ angles: [Double], radius: Double = 100, sensitivity: Double = 1, vertical: Double = 0) -> [Int] {
            var twist = GestureRotationMotion()
            var mouse = GesturePointerMotion()
            var centre = GesturePointerMotion()
            return angles.enumerated().compactMap { index, angle in
                let radians = angle * .pi / 180
                let x = cos(radians) * radius, y = sin(radians) * radius
                // Move both fingers symmetrically and translate the whole hand.
                let offset = Double(index) * 3
                let height = Double(index) * vertical
                let points: [Point] = [.init(id: 1, x: offset - x, y: height - y),
                                       .init(id: 2, x: offset + x, y: height + y)]
                let translation = centre.sample(points)
                guard let delta = twist.sample(points) else { return nil }
                let dx = GestureRotationMotion.mouseDeltaX(degrees: delta, sensitivity: sensitivity)
                let movement = mouse.cursor(dx: dx, dy: translation.y, speed: 1)
                if vertical == 0 {
                    check(movement.1 == 0, "A centred twist cannot add vertical cursor motion")
                } else {
                    check(vertical < 0 ? movement.1 < 0 : movement.1 > 0,
                          "Both fingers moving up/down must move the cursor in the same vertical direction")
                    check(abs(Double(movement.1) - vertical * 1.35) < 1.01,
                          "Vertical speed follows hand translation, without counting both fingers twice")
                }
                return Int(movement.0)
            }
        }
        let fullTurn = Array(stride(from: 0.0, through: 360.0, by: 5.0))
        let clockwise = orbit(fullTurn)
        check(clockwise.allSatisfy { $0 > 0 }, "A clockwise full circle always sends positive mouse X, across every quadrant")
        check(abs(clockwise.reduce(0, +) - 848) <= 1, "Mouse distance is proportional to accumulated angle")
        let counterclockwise = orbit(fullTurn.map { -$0 })
        check(counterclockwise.allSatisfy { $0 < 0 }, "Counterclockwise twist always sends negative mouse X")
        check(abs(clockwise.reduce(0, +) + counterclockwise.reduce(0, +)) <= 1, "Opposite turns have equal strength")
        for radius in [5.0, 1000.0] {
            check(abs(orbit(fullTurn, radius: radius).reduce(0, +) - clockwise.reduce(0, +)) <= 1,
                  "Finger spacing cannot change rotation strength")
        }
        let slowTurn = orbit(Array(stride(from: 0.0, through: 360.0, by: 0.25)))
        check(slowTurn.contains(0), "Subpixel angle increments are accumulated")
        check(abs(slowTurn.reduce(0, +) - clockwise.reduce(0, +)) <= 1, "Sampling frequency cannot change total rotation")
        let boundary = orbit([179, -179, 179])
        check(boundary[0] > 0 && boundary[1] < 0 && abs(boundary.reduce(0, +)) <= 1,
              "The short arc across +/-180 reverses immediately without a jump")
        let faster = orbit(fullTurn, sensitivity: 2).reduce(0, +)
        check(abs(faster - 2 * clockwise.reduce(0, +)) <= 1, "Rotation sensitivity scales mouse distance")
        check(orbit(fullTurn, sensitivity: 0).allSatisfy { $0 == 0 }, "Zero rotation sensitivity suppresses mouse movement")
        check(orbit([45, 45, 45, 45]).allSatisfy { $0 == 0 }, "Hand translation alone does not rotate the camera")
        for vertical in [-10.0, 10.0] {
            let combined = orbit(fullTurn, vertical: vertical)
            check(combined.allSatisfy { $0 > 0 } && abs(combined.reduce(0, +) - clockwise.reduce(0, +)) <= 1,
                  "Adding vertical hand movement preserves the improved horizontal rotation")
            check(orbit([0, 5, 5, 5], vertical: vertical).dropFirst().allSatisfy { $0 == 0 },
                  "After rotation begins, vertical movement continues when the twist angle stops changing")
        }
        check(GestureRotationMotion.mouseDeltaX(degrees: .nan, sensitivity: 1) == 0, "Reject invalid angles")
        check(GestureRotationMotion.mouseDeltaX(degrees: 10, sensitivity: .infinity) == 0, "Reject invalid sensitivity")

        engine.cancel()
        events.removeAll()
        for angle in [5.0, 10, -10, -5] {
            engine.move(axis: 1, action: GestureAction.defaults[2], amount: abs(angle), now: 100)
        }
        engine.tick(now: 200)
        check(events == ["mouse2:down"], "Unified rotation keeps MIDDLE held through direction changes and pauses")
        engine.end(axis: 1)
        check(events == ["mouse2:down", "mouse2:up"], "Unified rotation releases once on lift")
        print("GestureActionEngine: all checks passed")
    }
}
