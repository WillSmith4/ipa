import UIKit
import UIKit.UIGestureRecognizerSubclass

#if !os(tvOS)
/// Observes physical motion without competing with gesture recognition. Cursor
/// output is deferred until UIKit has delivered cancellation to old handlers.
private final class GestureMotionObserver: UIGestureRecognizer {
    var onMotion: ((Double, Double) -> Void)?
    var onCountChanged: ((Int) -> Void)?
    private var fingers: [UITouch: Int] = [:]
    private var nextID = 0
    private var motion = GesturePointerMotion()

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    private func sample() {
        let points = fingers.map { touch, id -> GesturePointerMotion.Point in
            let p = touch.location(in: view)
            return .init(id: id, x: Double(p.x), y: Double(p.y))
        }
        let delta = motion.sample(points)
        if delta.x != 0 || delta.y != 0 { onMotion?(delta.x, delta.y) }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches.sorted(by: { $0.location(in: view).x < $1.location(in: view).x }) {
            fingers[touch] = nextID
            nextID += 1
        }
        sample()
        onCountChanged?(fingers.count)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { sample() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { fingers.removeValue(forKey: touch) }
        sample()
        onCountChanged?(fingers.count)
        if fingers.isEmpty { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touchesEnded(touches, with: event)
    }
    override func reset() { super.reset(); fingers.removeAll(); motion.reset() }
}

/// One continuous rotation gesture drives both directional bindings. Track the
/// same fingers from the second touch down and sample every subsequent move.
private final class StreamRotationRecognizer: UIGestureRecognizer {
    private var fingers: [UITouch] = []
    private var motion = GestureRotationMotion()
    private(set) var deltaDegrees = 0.0

    private func sample() -> Double? {
        motion.sample(fingers.enumerated().map { index, touch in
            let point = touch.location(in: view)
            return .init(id: index, x: Double(point.x), y: Double(point.y))
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        fingers.append(contentsOf: touches.sorted { $0.location(in: view).x < $1.location(in: view).x })
        guard fingers.count <= 2 else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        _ = sample()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard fingers.count == 2, let angle = sample() else { return }
        deltaDegrees = angle
        if state == .possible {
            // Zero angle has no rotation direction. Leave pure translation and
            // radial pinching alone; any nonzero angle starts rotation immediately.
            if angle != 0 { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() { super.reset(); fingers.removeAll(); motion.reset(); deltaDegrees = 0 }
}

/// Uses the existing touchpad dead zone to distinguish a swipe from a tap.
private final class StreamSwipeRecognizer: UIGestureRecognizer {
    var threshold = 6.0
    private var finger: UITouch?
    private(set) var origin = CGPoint.zero
    var delta = CGPoint.zero
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard finger == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        finger = touch
        origin = touch.location(in: view)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        let p = finger.location(in: view), old = finger.previousLocation(in: view)
        delta = CGPoint(x: p.x - old.x, y: p.y - old.y)
        if state == .possible {
            if hypot(Double(p.x - origin.x), Double(p.y - origin.y)) > threshold * sqrt(2) { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = state == .possible ? .failed : .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = state == .possible ? .failed : .cancelled }
    override func reset() { super.reset(); finger = nil; delta = .zero }
}

/// Two-finger camera gestures on the stream surface, including native touch
/// mode. UIKit cancels the underlying touch handler once a gesture is recognized.
@objc final class StreamGestureController: NSObject, UIGestureRecognizerDelegate {
    private weak var view: UIView?
    private var pinch: UIPinchGestureRecognizer!
    private var rotation: StreamRotationRecognizer!
    private var swipe: StreamSwipeRecognizer!
    private var motionObserver: GestureMotionObserver!
    private var cursorEnabled = Array(repeating: false, count: 5)
    private var pointerSpeed = 1.0
    private var pointer = GesturePointerMotion()
    private var cursorDelta = (x: 0.0, y: 0.0)
    private var swipeCursorOrigin: CGPoint?
    private var queuedMoves: [(axis: Int, delta: Double)] = []
    private var endingAxes: Set<Int> = []
    private var activeActions: [Int: Int] = [:]
    private var flushScheduled = false
    private var generation = 0
    private var hasRecognizedGesture = false
    private var fingerCount = 0
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var actions = GestureAction.defaults
    private var pinchSensitivity = 1.0
    private var rotationSensitivity = 1.0
    private var controlScroll = false
    private var edgeTolerance: CGFloat = 0
    private var lastPinch = 1.0
    private var pending = [0.0, 0.0, 0.0]
    private var enabled = true
    private var pinchEnabled = true
    private lazy var engine = GestureActionEngine(
        mappings: CommandManager.keyboardButtonMappings,
        sendKey: { key, down in
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000 | UInt16(bitPattern: key)),
                                CChar(down ? KEY_ACTION_DOWN : KEY_ACTION_UP), 0)
        },
        sendScroll: { LiSendHighResScrollEvent($0) },
        sendMouse: { LiSendMouseButtonEvent(CChar($1 ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE), $0) }
    )

    @objc init(view: UIView) {
        self.view = view
        super.init()
        pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        rotation = StreamRotationRecognizer(target: self, action: #selector(rotated(_:)))
        swipe = StreamSwipeRecognizer(target: self, action: #selector(swiped(_:)))
        // Hold ordinary touches until we know whether this is a configured swipe.
        // Failed recognition still delivers taps to the existing touch handler.
        swipe.delaysTouchesBegan = true
        motionObserver = GestureMotionObserver(target: nil, action: nil)
        motionObserver.cancelsTouchesInView = false
        motionObserver.onMotion = { [weak self] x, y in
            guard let self else { return }
            self.cursorDelta.x += x
            self.cursorDelta.y += y
            self.scheduleFlush()
        }
        motionObserver.onCountChanged = { [weak self] count in
            guard let self else { return }
            self.fingerCount = count
            if count != 2 { self.endingAxes.formUnion([0, 1]) }
            if count != 1 { self.endingAxes.insert(2) }
            if count == 0 { self.hasRecognizedGesture = false }
            self.scheduleFlush()
        }
        let recognizers: [UIGestureRecognizer] = [motionObserver, pinch, rotation, swipe]
        for recognizer in recognizers {
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            recognizer.cancelsTouchesInView = recognizer !== motionObserver
            view.addGestureRecognizer(recognizer)
        }
        notificationTokens = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancel()
            }
        }
    }

    @objc func configure(_ settings: TemporarySettings, enabled: Bool) {
        cancel()
        let bindings: [String?] = [settings.pinchInAction, settings.pinchOutAction, settings.rotateLeftAction, settings.rotateRightAction, settings.swipeAction]
        actions = bindings
            .enumerated().map { $0.element ?? GestureAction.defaults[$0.offset] }
        pinchSensitivity = settings.pinchSensitivity.doubleValue
        rotationSensitivity = settings.rotationSensitivity.doubleValue
        controlScroll = settings.ctrlDownForPinch
        edgeTolerance = CGFloat(settings.edgeSlidingSensitivity.doubleValue)
        cursorEnabled = [settings.pinchInMovesCursor, settings.pinchOutMovesCursor,
                         settings.rotateLeftMovesCursor, settings.rotateRightMovesCursor, settings.swipeMovesCursor]
        pointerSpeed = settings.mousePointerVelocityFactor.doubleValue
        swipe.threshold = max(0, settings.relativeTouchSlideThreshold.doubleValue)
        pinchEnabled = settings.enablePinch
        self.enabled = enabled
        updateEnabled()
    }

    @objc func setInputEnabled(_ enabled: Bool) {
        cancel()
        self.enabled = enabled
        updateEnabled()
    }

    private func updateEnabled() {
        pinch.isEnabled = enabled && pinchEnabled && (0...1).contains { actions[$0] != "NONE" || cursorEnabled[$0] }
        rotation.isEnabled = enabled && (2...3).contains { actions[$0] != "NONE" || cursorEnabled[$0] }
        swipe.isEnabled = enabled && (actions[4] != "NONE" || cursorEnabled[4])
        motionObserver.isEnabled = enabled
    }

    @objc func cancel() {
        engine.cancel()
        timer?.invalidate()
        timer = nil
        generation += 1
        flushScheduled = false
        queuedMoves.removeAll()
        endingAxes.removeAll()
        activeActions.removeAll()
        cursorDelta = (0, 0)
        swipeCursorOrigin = nil
        pointer.reset()
        pending = [0, 0, 0]
        hasRecognizedGesture = false
        // Reset UIKit too, preventing an interrupted sequence from resuming.
        let optionalRecognizers: [UIGestureRecognizer?] = [pinch, rotation, swipe, motionObserver]
        let recognizers = optionalRecognizers.compactMap { $0 }
        for recognizer in recognizers {
            let wasEnabled = recognizer.isEnabled
            recognizer.isEnabled = false
            recognizer.isEnabled = wasEnabled
        }
        TouchPadGestureHandler.cancel()
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lastPinch = 1
            pending[0] = 0
            endingAxes.remove(0)
            fallthrough
        case .changed:
            guard recognizer.numberOfTouches == 2, recognizer.scale > 0 else { cancel(); return }
            let scale = Double(recognizer.scale)
            let delta = log(scale / lastPinch) * 100 * pinchSensitivity
            lastPinch = scale
            move(axis: 0, delta: delta)
        default:
            endingAxes.insert(0)
            scheduleFlush()
        }
    }

    @objc private func rotated(_ recognizer: StreamRotationRecognizer) {
        switch recognizer.state {
        case .began:
            pending[1] = 0
            endingAxes.remove(1)
            fallthrough
        case .changed:
            guard recognizer.numberOfTouches == 2 else { cancel(); return }
            // Preserve existing sensitivity units while using per-event angles.
            let delta = recognizer.deltaDegrees * .pi / 180 * 100 * rotationSensitivity
            move(axis: 1, delta: delta)
        default:
            endingAxes.insert(1)
            scheduleFlush()
        }
    }

    private func move(axis: Int, delta: Double) {
        queuedMoves.append((axis, delta))
        scheduleFlush()
    }

    @objc private func swiped(_ recognizer: StreamSwipeRecognizer) {
        if recognizer.state == .began || recognizer.state == .changed {
            if recognizer.state == .began {
                endingAxes.remove(2)
                if cursorEnabled[4] { swipeCursorOrigin = recognizer.origin }
            }
            move(axis: 2, delta: hypot(Double(recognizer.delta.x), Double(recognizer.delta.y)))
        } else {
            if recognizer.state == .cancelled || recognizer.state == .failed { swipeCursorOrigin = nil }
            endingAxes.insert(2)
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        let currentGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.flushScheduled = false
            if let origin = self.swipeCursorOrigin, self.fingerCount == 1 {
                // Reuse Single Point's video-area mapping. Position first, before
                // pressing a drag button, then continue with relative movement.
                (self.view as? StreamView)?.updateCursorLocation(origin, isMouse: false)
                self.pointer.reset()
            }
            self.swipeCursorOrigin = nil
            // All legacy touchesCancelled callbacks finish before a new mouse
            // hold starts, and both simultaneous recognizers share one cursor move.
            for move in self.queuedMoves { self.applyMove(axis: move.axis, delta: move.delta) }
            self.queuedMoves.removeAll()
            if self.activeActions.values.contains(where: { self.cursorEnabled[$0] }) {
                let delta = self.pointer.cursor(dx: self.cursorDelta.x, dy: self.cursorDelta.y, speed: self.pointerSpeed)
                if delta.0 != 0 || delta.1 != 0 { LiSendMouseMoveEvent(delta.0, delta.1) }
            }
            self.cursorDelta = (0, 0)
            for axis in self.endingAxes {
                self.engine.end(axis: axis)
                self.activeActions.removeValue(forKey: axis)
                self.pending[axis] = 0
            }
            self.endingAxes.removeAll()
            if self.activeActions.isEmpty { self.pointer.reset() }
        }
    }

    private func applyMove(axis: Int, delta: Double) {
        guard delta.isFinite, fingerCount == (axis == 2 ? 1 : 2) else { return }
        TouchPadGestureHandler.cancel()
        pending[axis] += delta
        // Accumulate small samples rather than making sensitivity depend on FPS.
        // Rotation has no minimum-angle threshold: even a tiny nonzero delta
        // selects its direction immediately, matching the vector gesture.
        guard axis == 1 ? pending[axis] != 0 : abs(pending[axis]) >= 0.15 else { return }
        let amount = pending[axis]
        pending[axis] = 0
        let index = axis == 2 ? 4 : axis * 2 + (amount > 0 ? 1 : 0)
        activeActions[axis] = index
        let action = actions[index]
        engine.move(axis: axis, action: action, amount: abs(amount), now: CACurrentMediaTime(),
                    controlScroll: axis == 0 && controlScroll)
        if engine.hasTimedHolds && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.engine.tick(now: CACurrentMediaTime())
                if !self.engine.hasTimedHolds { timer.invalidate(); self.timer = nil }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view, touch.view === view, touch.type == .direct else { return false }
        let point = touch.location(in: view)
        // Leave the existing screen-edge menu gestures in charge of their area.
        return !(point.y < view.bounds.height * 0.4 &&
                 (point.x < edgeTolerance || point.x > view.bounds.width - edgeTolerance))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard (gestureRecognizer === swipe || gestureRecognizer.numberOfTouches == 2),
              OnScreenControls.touchesCapturedByOnScreenControls().count == 0 else { return false }
        TouchPadGestureHandler.cancel()
        if !hasRecognizedGesture {
            // A swipe delays touchesBegan, so UIKit may have nothing to cancel.
            // Invalidate any delayed click from the previous sequence explicitly.
            (view as? StreamView)?.cancelMouseTouchesForGesture()
            hasRecognizedGesture = true
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let ours: [UIGestureRecognizer] = [pinch, rotation, swipe, motionObserver]
        return ours.contains(where: { $0 === gestureRecognizer }) && ours.contains(where: { $0 === other })
    }

    deinit {
        engine.cancel()
        timer?.invalidate()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif

/// Shared editor for stateful keyboard/mouse chords in both settings front ends.
@objc final class GestureActionEditor: NSObject {
    @objc static func edit(in presenter: UIViewController, title: String, current: String,
                           completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: "Gesture key binding help".localized, preferredStyle: .alert)
        alert.addTextField {
            $0.text = GestureAction.presets.contains(current) ? "" : current
            $0.placeholder = "W+D / CTRL+Q / MOUSE_MIDDLE"
            $0.autocapitalizationType = .allCharacters
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel) { _ in completion(current) })
        alert.addAction(UIAlertAction(title: "Save".localized, style: .default) { [weak presenter, weak alert] _ in
            let action = (alert?.textFields?.first?.text ?? "").uppercased().filter { !$0.isWhitespace }
            guard GestureAction.inputs(action, mappings: CommandManager.keyboardButtonMappings) != nil else {
                completion(current)
                guard let presenter else { return }
                let error = UIAlertController(title: "Invalid key binding".localized,
                                              message: "Gesture key binding help".localized, preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "OK".localized, style: .default))
                presenter.present(error, animated: true)
                return
            }
            completion(action)
        })
        presenter.present(alert, animated: true)
    }
}
