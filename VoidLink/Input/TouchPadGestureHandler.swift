//
//  TouchPadGestureHandler.swift
//  VoidLink
//
//  Created by TrueĂ§Â â€“ÄşÂ®Â¶ on 2025/11/5.
//  Copyright Ă‚Â© 2025 TrueĂ§Â â€“ÄşÂ®Â¶ on Bilibili. All rights reserved.
//

import UIKit

@objc class TouchPadGestureHandler: NSObject {
    
    @objc public static var ctrlDown = false
    @objc public static var enablePinch = true
    @objc public static var ctrlDownForPinch = true
    @objc public static var pinchSensitivity: CGFloat = 1
    @objc public static var enableHorizontalScroll:Bool = true
    @objc public static var scrollSensitivity:CGFloat = 1.0
    @objc public static var displayLinkRate:CGFloat = 60

    private static var inertialScroller: InertialScroller = InertialScroller(decelerationRate: displayLinkRate > 110 ? 0.96 : 0.9, displayLinkRate: displayLinkRate) {
        if ctrlDown { return }
        LiSendHighResScrollEvent(Int16(inertialScroller.vector.dy*7*scrollSensitivity))
        if TouchPadGestureHandler.enableHorizontalScroll {LiSendHighResHScrollEvent(Int16(-inertialScroller.vector.dx*7*scrollSensitivity))}
    }
    
    @objc public static func releaseControl() {
        if ctrlDown {
            LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_UP), 0)
        }
    }

    @objc public static func cancel() {
        releaseControl()
        ctrlDown = false
        inertialScroller.timer?.pause()
        inertialScroller.vector = .zero
    }

    @objc public static func startInertialScroll(){
        inertialScroller.timer?.restart()
    }
    
    @objc public static func handleGesture(in view: UIView, with event: UIEvent) {
        inertialScroller.timer?.pause()
        
        let currentTouches = UITouchUtil.touches(in: view, from: event)
        guard currentTouches.count == 2, currentTouches.allSatisfy({ $0.type == .direct }) else { cancel(); return }
        
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_RIGHT)
        
        guard let touch1 = currentTouches.first else { return }
        var mutable = Array(currentTouches)
        mutable.removeAll { $0 == touch1 }
        guard let touch2 = mutable.first else { return }
        
        let currentDistance = UITouchUtil.distance(between: touch1, and: touch2, in: view)
        let previousDistance = UITouchUtil.previousDistance(between: touch1, and: touch2, in: view)
        
        let midPointVector = UITouchUtil.midPointVector(between: touch1, and: touch2, in: view)
        let midPointDeltaX = midPointVector.dx
        let midPointDeltaY = midPointVector.dy
        
        let sendHorizontalScroll = abs(midPointDeltaX) > 1.2*abs(midPointDeltaY)
        
        inertialScroller.vector = CGVector(dx: sendHorizontalScroll ? midPointDeltaX : 0, dy: midPointDeltaY)
        
        // Pinch and rotation are recognized by StreamGestureController. Keep
        // ordinary two-finger translation here, including its existing inertia.
        // Reject shape changes while UIKit is still deciding which gesture won.
        let a = touch1.location(in: view), b = touch2.location(in: view)
        let oldA = touch1.previousLocation(in: view), oldB = touch2.previousLocation(in: view)
        let angle = atan2(b.y - a.y, b.x - a.x) - atan2(oldB.y - oldA.y, oldB.x - oldA.x)
        let arc = abs(atan2(sin(angle), cos(angle))) * previousDistance / 2
        if max(abs(currentDistance - previousDistance), arc) > hypot(midPointDeltaX, midPointDeltaY) {
            cancel()
            return
        }
        LiSendHighResScrollEvent(Int16(clamping: Int(midPointDeltaY * 7 * scrollSensitivity)))
        if enableHorizontalScroll, sendHorizontalScroll {
            LiSendHighResHScrollEvent(Int16(clamping: Int(-midPointDeltaX * 7 * scrollSensitivity)))
        }
    }
    @objc(handleTouchpadGestureIn:with:) public static func handleTouchpadGesture(in view: UIView, with event: UIEvent) {
        inertialScroller.timer?.pause()

        let currentTouches = UITouchUtil.touches(in: view, from: event)
        guard currentTouches.count == 2 else { return }

        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_RIGHT)

        guard let touch1 = currentTouches.first else { return }
        var mutable = Array(currentTouches)
        mutable.removeAll { $0 == touch1 }
        guard let touch2 = mutable.first else { return }

        let currentDistance = UITouchUtil.distance(between: touch1, and: touch2, in: view)
        let previousDistance = UITouchUtil.previousDistance(between: touch1, and: touch2, in: view)

        let midPointVector = UITouchUtil.midPointVector(between: touch1, and: touch2, in: view)
        let midPointDeltaX = midPointVector.dx
        let midPointDeltaY = midPointVector.dy

        let sendHorizontalScroll = abs(midPointDeltaX) > 1.2*abs(midPointDeltaY)

        inertialScroller.vector = CGVector(dx: sendHorizontalScroll ? midPointDeltaX : 0, dy: midPointDeltaY)

        let originalPinchDelta = currentDistance-previousDistance;
        let pinchDelta = enablePinch ? originalPinchDelta*7*pinchSensitivity : 0;
        LiSendHighResScrollEvent(Int16(pinchDelta + midPointDeltaY*7*scrollSensitivity))
        if enableHorizontalScroll, sendHorizontalScroll {LiSendHighResHScrollEvent(Int16(-midPointDeltaX*7*scrollSensitivity))}

        if enablePinch, ctrlDownForPinch {
            let midPointDelta = hypot(midPointDeltaX, midPointDeltaY)
            if abs(originalPinchDelta) > midPointDelta*1.3, midPointDelta < 2 {
                LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_DOWN), 0)
                ctrlDown = true
            } else {
                LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_UP), 0)
                ctrlDown = false
            }
        }
    }
}
