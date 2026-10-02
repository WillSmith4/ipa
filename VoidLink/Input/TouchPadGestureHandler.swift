//
//  TouchPadGestureHandler.swift
//  VoidLink
//
//  Created by True砖家 on 2025/11/5.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//

import UIKit

@objc class TouchPadGestureHandler: NSObject {
    
    @objc public static var enableHorizontalScroll:Bool = true
    @objc public static var scrollSensitivity:CGFloat = 1.0
    @objc public static var displayLinkRate:CGFloat = 60

    private static var inertialScroller: InertialScroller = InertialScroller(decelerationRate: displayLinkRate > 110 ? 0.96 : 0.9, displayLinkRate: displayLinkRate) {
        LiSendHighResScrollEvent(Int16(inertialScroller.vector.dy*7*scrollSensitivity))
        if TouchPadGestureHandler.enableHorizontalScroll {LiSendHighResHScrollEvent(Int16(-inertialScroller.vector.dx*7*scrollSensitivity))}
    }
    
    @objc public static func cancel() {
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
}
