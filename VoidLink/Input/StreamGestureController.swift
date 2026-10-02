import UIKit

#if !os(tvOS)
/// Two-finger camera gestures on the stream surface, including native touch
/// mode. UIKit cancels the underlying touch handler once a gesture is recognized.
@objc final class StreamGestureController: NSObject, UIGestureRecognizerDelegate {
    private weak var view: UIView?
    private var pinch: UIPinchGestureRecognizer!
    private var rotation: UIRotationGestureRecognizer!
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var actions = GestureAction.defaults
    private var pinchSensitivity = 1.0
    private var rotationSensitivity = 1.0
    private var controlScroll = false
    private var edgeTolerance: CGFloat = 0
    private var lastPinch = 1.0
    private var lastRotation = 0.0
    private var pending = [0.0, 0.0]
    private var enabled = true
    private var pinchEnabled = true
    private lazy var engine = GestureActionEngine(
        mappings: CommandManager.keyboardButtonMappings,
        sendKey: { key, down in
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000 | UInt16(bitPattern: key)),
                                CChar(down ? KEY_ACTION_DOWN : KEY_ACTION_UP), 0)
        },
        sendScroll: { LiSendHighResScrollEvent($0) }
    )

    @objc init(view: UIView) {
        self.view = view
        super.init()
        pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        let recognizers: [UIGestureRecognizer] = [pinch, rotation]
        for recognizer in recognizers {
            recognizer.delegate = self
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            recognizer.cancelsTouchesInView = true
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
        let bindings: [String?] = [settings.pinchInAction, settings.pinchOutAction, settings.rotateLeftAction, settings.rotateRightAction]
        actions = bindings
            .enumerated().map { $0.element ?? GestureAction.defaults[$0.offset] }
        pinchSensitivity = settings.pinchSensitivity.doubleValue
        rotationSensitivity = settings.rotationSensitivity.doubleValue
        controlScroll = settings.ctrlDownForPinch
        edgeTolerance = CGFloat(settings.edgeSlidingSensitivity.doubleValue)
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
        pinch.isEnabled = enabled && pinchEnabled && actions[0...1].contains(where: { $0 != "NONE" })
        rotation.isEnabled = enabled && actions[2...3].contains(where: { $0 != "NONE" })
    }

    @objc func cancel() {
        engine.cancel()
        timer?.invalidate()
        timer = nil
        pending = [0, 0]
        // Reset UIKit too, preventing an interrupted sequence from resuming.
        let optionalRecognizers: [UIGestureRecognizer?] = [pinch, rotation]
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
            fallthrough
        case .changed:
            guard recognizer.numberOfTouches == 2, recognizer.scale > 0 else { cancel(); return }
            let scale = Double(recognizer.scale)
            let delta = log(scale / lastPinch) * 100 * pinchSensitivity
            lastPinch = scale
            move(axis: 0, delta: delta)
        default:
            engine.end(axis: 0)
            pending[0] = 0
        }
    }

    @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lastRotation = 0
            pending[1] = 0
            fallthrough
        case .changed:
            guard recognizer.numberOfTouches == 2 else { cancel(); return }
            let angle = Double(recognizer.rotation)
            // Positive UIKit rotation is clockwise (right).
            let delta = (angle - lastRotation) * 100 * rotationSensitivity
            lastRotation = angle
            move(axis: 1, delta: delta)
        default:
            engine.end(axis: 1)
            pending[1] = 0
        }
    }

    private func move(axis: Int, delta: Double) {
        guard delta.isFinite else { return }
        TouchPadGestureHandler.cancel()
        pending[axis] += delta
        // Accumulate small samples rather than making sensitivity depend on FPS.
        guard abs(pending[axis]) >= 0.15 else { return }
        let amount = pending[axis]
        pending[axis] = 0
        let action = actions[axis * 2 + (amount > 0 ? 1 : 0)]
        engine.move(axis: axis, action: action, amount: abs(amount), now: CACurrentMediaTime(),
                    controlScroll: axis == 0 && controlScroll)
        if engine.hasHolds && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.engine.tick(now: CACurrentMediaTime())
                if !self.engine.hasHolds { timer.invalidate(); self.timer = nil }
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
        guard gestureRecognizer.numberOfTouches == 2,
              OnScreenControls.touchesCapturedByOnScreenControls().count == 0 else { return false }
        TouchPadGestureHandler.cancel()
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === pinch && other === rotation) || (gestureRecognizer === rotation && other === pinch)
    }

    deinit {
        engine.cancel()
        timer?.invalidate()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif

/// Shared editor for both settings front ends. Only stateful keyboard chords
/// are accepted here; macro commands would violate held-key semantics.
@objc final class GestureActionEditor: NSObject {
    @objc static func edit(in presenter: UIViewController, title: String, current: String,
                           completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: "Gesture key binding help".localized, preferredStyle: .alert)
        alert.addTextField {
            $0.text = GestureAction.presets.contains(current) ? "" : current
            $0.placeholder = "Q / CTRL+Q / SPACE / LEFT_ARROW"
            $0.autocapitalizationType = .allCharacters
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel) { _ in completion(current) })
        alert.addAction(UIAlertAction(title: "Save".localized, style: .default) { [weak presenter, weak alert] _ in
            let action = (alert?.textFields?.first?.text ?? "").uppercased().filter { !$0.isWhitespace }
            guard GestureAction.keys(action, mappings: CommandManager.keyboardButtonMappings) != nil else {
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
