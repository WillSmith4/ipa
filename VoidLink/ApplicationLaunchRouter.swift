import UIKit
#if !os(tvOS)
import AppIntents

/// One entry point for cold/warm URL opens and the Shortcuts action. Delivery
/// waits for both an active scene and MainFrame's completed view setup.
@MainActor @objc final class ApplicationLaunchRouter: NSObject {
    @objc static let shared = ApplicationLaunchRouter()
    private weak var controller: MainFrameViewController?
    private var pending: URL?
    private var retry: DispatchWorkItem?

    @objc @discardableResult func receive(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "voidlink" else { return false }
        pending = url
        drain()
        return true
    }

    @objc func attach(_ controller: MainFrameViewController) {
        self.controller = controller
        drain()
    }

    @objc func drain() {
        retry?.cancel()
        retry = nil
        guard UIApplication.shared.applicationState == .active,
              let controller, controller.isViewLoaded,
              controller.view.window != nil || controller.isStreaming(),
              let url = pending else { return }
        // Foreground refresh may already be fetching the app list. Let it finish
        // instead of rejecting a valid warm launch or presenting two spinners.
        if controller.isApplicationLaunchBusy() {
            let work = DispatchWorkItem { [weak self] in self?.drain() }
            retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        pending = nil
        controller.launchApplication(from: url)
    }
}

@available(iOS 16.0, *)
struct LaunchVoidLinkApplicationIntent: AppIntent {
    static var title: LocalizedStringResource = "Launch Application in VoidLink"
    static var description = IntentDescription("Launch an application on a paired host. In VoidLink, hold its banner and choose Copy Launch URL, then paste that URL here.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Launch URL") var launchURL: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Launch application at \(\.$launchURL)")
    }

    @MainActor func perform() async throws -> some IntentResult {
        guard ApplicationLaunchLink.parse(launchURL) != nil else { throw ApplicationShortcutError.invalidLink }
        ApplicationLaunchRouter.shared.receive(launchURL)
        return .result()
    }
}
#endif
