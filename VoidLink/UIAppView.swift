//
//  UIAppView.swift
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Created by True Zhuanjia on 2025.7.20.
//  Copyright 2025 True Zhuanjia @ Bilibili. All rights reserved.
//

import UIKit

private let refreshCycle: TimeInterval = 1.0

@objc protocol AppViewUpdateLoopDelegate: AnyObject {
    func isInAppView() -> Bool
}

@objc protocol AppCallback: AnyObject {
    @objc(appClicked:view:)
    func appClicked(_ app: TemporaryApp, view: UIView)

    @objc(appLongClicked:view:)
    func appLongClicked(_ app: TemporaryApp, view: UIView)
}

@objcMembers
final class UIAppView: UIButton {
    weak var updateLoopDelegate: AppViewUpdateLoopDelegate?

    private static var noImage: UIImage?

    let app: TemporaryApp
    fileprivate weak var callback: AppCallback?
    private let artCache: NSCache<AnyObject, AnyObject>
    private var appLabel: UILabel?
    private var appOverlay: UIImageView?
    private var appImage: UIImageView
    private var contextMenuDelegate: AnyObject?

    @objc(initWithApp:cache:andCallback:)
    init(app: TemporaryApp, cache: NSCache<AnyObject, AnyObject>, andCallback callback: AppCallback) {
        self.app = app
        self.callback = callback
        self.artCache = cache

        if UIAppView.noImage == nil {
            UIAppView.noImage = UIImage(named: "NoAppImage")
        }

        #if os(tvOS)
        let initialFrame = CGRect(x: 0, y: 0, width: 200, height: 265)
        #else
        let initialFrame = CGRect(x: 0, y: 0, width: 150, height: 200)
        #endif

        self.appImage = UIImageView(frame: initialFrame)

        super.init(frame: .zero)

        layer.cornerRadius = 16
        if #available(iOS 13.0, tvOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
        clipsToBounds = true
        frame = initialFrame
        alpha = app.hidden ? 0.4 : 1.0

        appImage.image = UIAppView.noImage
        addSubview(appImage)

        #if !os(tvOS)
        addInteraction(UIDropInteraction(delegate: self))
        if #available(iOS 13.0, *) {
            let delegate = UIAppViewContextMenuDelegate(appView: self)
            contextMenuDelegate = delegate
            let rightClickInteraction = UIContextMenuInteraction(delegate: delegate)
            addInteraction(rightClickInteraction)
        } else {
            let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(appLongClicked(_:)))
            addGestureRecognizer(longPressRecognizer)
        }
        #else
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(appLongClicked(_:)))
        addGestureRecognizer(longPressRecognizer)
        #endif

        addTarget(self, action: #selector(appClicked(_:)), for: .primaryActionTriggered)
        addTarget(self, action: #selector(buttonSelected(_:)), for: .touchDown)
        addTarget(self, action: #selector(buttonDeselected(_:)), for: [.touchUpInside, .touchCancel, .touchDragExit])

        #if os(tvOS)
        appImage.adjustsImageWhenAncestorFocused = true
        #else
        layer.shouldRasterize = false
        if #available(iOS 13.4, *) {
            isPointerInteractionEnabled = true
        }
        #endif

        updateAppImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil {
            updateLoop()
        }
    }

    @objc private func appClicked(_ view: UIView) {
        callback?.appClicked(app, view: view)
    }

    @objc private func appLongClicked(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            callback?.appLongClicked(app, view: self)
        }
    }

    private var isCurrentApp: Bool {
        app.id == app.host?.currentGame
    }

    func updateAppImage() {
        appOverlay?.removeFromSuperview()
        appOverlay = nil
        appLabel?.removeFromSuperview()
        appLabel = nil

        var noAppImage = false
        var loadedAppImage: UIImage?

        if let boxArtPath = AppAssetManager.boxArtPath(for: app) {
            loadedAppImage = UIImage(contentsOfFile: boxArtPath)
            if let loadedAppImage {
                artCache.setObject(loadedAppImage, forKey: app)
            }
        }

        if let loadedAppImage {
            let isGFE2BlankImage = loadedAppImage.size.width == 130.0 && loadedAppImage.size.height == 180.0
            let isGFE3BlankImage = loadedAppImage.size.width == 628.0 && loadedAppImage.size.height == 888.0
            if !isGFE2BlankImage && !isGFE3BlankImage {
                appImage.image = loadedAppImage
            } else {
                noAppImage = true
            }
        } else {
            noAppImage = true
        }

        if isCurrentApp {
            if #available(iOS 13.0, tvOS 13.0, *) {
                let config = UIImage.SymbolConfiguration(pointSize: 23)
                let image = UIImage(systemName: "play.circle.fill", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
                let playIcon = UIImageView(image: image)
                playIcon.tintColor = UIColor.black.withAlphaComponent(0.55)
                appOverlay = playIcon
            } else {
                let playIcon = UIImageView(image: UIImage(named: "play.circle.fill"))
                playIcon.tintColor = UIColor.black.withAlphaComponent(0.55)
                appOverlay = playIcon
            }
        } else if noAppImage {
            if #available(iOS 13.0, tvOS 13.0, *) {
                let config = UIImage.SymbolConfiguration(pointSize: 70)
                let image = UIImage(named: "icon-pc-app")?.withConfiguration(config).withRenderingMode(.alwaysTemplate)
                let appIcon = UIImageView(image: image)
                appIcon.tintColor = UIColor.black.withAlphaComponent(0.5)
                appOverlay = appIcon
            }
        }

        let label = UILabel()
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.textColor = .white.withAlphaComponent(UIAppView.appLabelAlpha)
        label.text = app.name == "Steam Big Picture" ? "Steam" : app.name
        let baseFont = UIFont.systemFont(ofSize: PublicUtils.isTVOS ? 18 : 15)
        if let desc = baseFont.fontDescriptor.withDesign(.rounded) {
            label.font = UIFont(descriptor: desc, size: PublicUtils.isTVOS ? 18 : 15)
        }
        label.baselineAdjustment = .alignCenters
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 2
        appLabel = label

        positionSubviews()

        #if os(tvOS)
        appImage.overlayContentView.addSubview(label)
        if let appOverlay {
            appImage.overlayContentView.addSubview(appOverlay)
        }
        #else
        if let appOverlay {
            addSubview(appOverlay)
        }
        addSubview(label)
        #endif
    }
    
    static var appLabelAlpha: CGFloat {
        return ThemeManager.userInterfaceStyle() == .dark ? (PublicUtils.isTVOS ? 0.97 : 0.8) : 1.0
    }
    
    func updateTheme() {
        appLabel?.textColor = .white.withAlphaComponent(UIAppView.appLabelAlpha)
    }

    @objc private func buttonSelected(_ sender: Any) {
        appImage.layer.opacity = 0.5
    }

    @objc private func buttonDeselected(_ sender: Any) {
        appImage.layer.opacity = isCurrentApp ? 0.75 : 1.0
    }

    private func positionSubviews() {
        let verticalPadding: CGFloat = 10
        let frameSize = appImage.frame.size

        appLabel?.frame = CGRect(x: 0, y: frameSize.height - 43, width: frameSize.width, height: 43)

        guard let appOverlay else { return }
        let overlaySize = isCurrentApp ? frameSize.width / 2.39 : frameSize.width / 2.0
        appOverlay.frame = CGRect(x: 0, y: 0, width: overlaySize, height: overlaySize)
        appOverlay.center = CGPoint(x: frameSize.width / 2.0, y: frameSize.height / 2.0 - 2.0 * verticalPadding)

        if isCurrentApp {
            appImage.layer.opacity = 0.75
        }
    }

    @objc private func updateLoop() {
        guard superview != nil, updateLoopDelegate?.isInAppView() == true else {
            return
        }

        if (appOverlay != nil && !isCurrentApp) || (appOverlay == nil && isCurrentApp) {
            updateAppImage()
        }

        superview?.layer.shadowOpacity = 0
        alpha = app.hidden ? 0.4 : 1.0

        perform(#selector(updateLoop), with: self, afterDelay: refreshCycle)
    }
}

@available(iOS 13.0, tvOS 17.0, *)
private final class UIAppViewContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    private weak var appView: UIAppView?

    init(appView: UIAppView) {
        self.appView = appView
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let appView else { return nil }
        appView.cancelTracking(with: nil)
        appView.callback?.appLongClicked(appView.app, view: appView)
        return nil
    }
}

#if !os(tvOS)
extension UIAppView: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        app.host?.uuid != nil && app.id != nil && GameProfileTransfer.accepts(session)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let item = session.items.first, let hostUUID = app.host?.uuid, let appID = app.id else { return }
        // Capture the destination before asynchronous iCloud/file loading can finish.
        if let reference = item.localObject as? GameProfileDragReference {
            assignProfile(reference.identifier, hostUUID: hostUUID, appID: appID)
        } else {
            GameProfileTransfer.loadFile(from: item.itemProvider) { [weak self] result in
                do {
                    let identifier = try GameProfileTransfer.importFile(result.get())
                    ApplicationProfileStore.shared.setProfileIdentifier(identifier, forHostUUID: hostUUID, appID: appID)
                    self?.showProfileDropFeedback(identifier)
                } catch {
                    GameProfileTransfer.showImportResult(false, on: self?.dropPresentationController())
                }
            }
        }
    }

    private func assignProfile(_ identifier: String, hostUUID: String, appID: String) {
        let profiles = OSCProfilesManager.sharedManager(.zero).getAllProfiles()
        guard profiles.contains(where: { ($0 as? OSCProfile)?.profileIdentifier == identifier }) else { return }
        ApplicationProfileStore.shared.setProfileIdentifier(identifier, forHostUUID: hostUUID, appID: appID)
        showProfileDropFeedback(identifier)
    }

    private func dropPresentationController() -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }

    private func showProfileDropFeedback(_ identifier: String) {
        let profiles = OSCProfilesManager.sharedManager(.zero).getAllProfiles()
        let profile = profiles.compactMap { $0 as? OSCProfile }.first { $0.profileIdentifier == identifier }
        let label = UILabel()
        label.text = "✓ " + (profile?.name ?? "Game Profile".localized)
        label.textColor = .white
        label.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.95)
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .caption1)
        label.numberOfLines = 2
        label.frame = CGRect(x: 0, y: bounds.midY - 24, width: bounds.width, height: 48)
        label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
        addSubview(label)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: label.text)
        UIView.animate(withDuration: 0.25, delay: 2, options: []) { label.alpha = 0 } completion: { _ in label.removeFromSuperview() }
    }
}
#endif
