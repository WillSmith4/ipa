import UIKit
import ImageIO
#if !os(tvOS)
import SafariServices
import UniformTypeIdentifiers

@MainActor @objc final class ApplicationShortcutActions: NSObject {
    @objc(addActionsTo:app:presenter:)
    static func addActions(to menu: UIAlertController, app: TemporaryApp, presenter: UIViewController) {
        let link = ApplicationLaunchLink.make(hostUUID: app.host?.uuid ?? "", appID: app.id ?? "")
        let copy = UIAlertAction(title: "Copy Launch URL".localized, style: .default) { _ in
            guard let link else { return }
            UIPasteboard.general.url = link
            showMessage("Launch URL copied. Paste it into the Launch Application in VoidLink action in Shortcuts, or use Open URLs.", in: presenter)
        }
        copy.isEnabled = link != nil && app.host?.serverCert != nil
        menu.addAction(copy)
        let save = UIAlertAction(title: "Save App Icon".localized, style: .default) { _ in
            openIconFlow(app: app, link: link, createWebClip: false, presenter: presenter)
        }
        menu.addAction(save)
        let clip = UIAlertAction(title: "Create App Clip".localized, style: .default) { _ in
            openIconFlow(app: app, link: link, createWebClip: true, presenter: presenter)
        }
        clip.isEnabled = copy.isEnabled
        menu.addAction(clip)
    }

    private static func openIconFlow(app: TemporaryApp, link: URL?, createWebClip: Bool, presenter: UIViewController) {
        let picker = ApplicationIconController(appName: app.name ?? "Application", launchURL: link, createWebClip: createWebClip)
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .formSheet
        presenter.present(navigation, animated: true)
    }

    @objc(showMessage:in:)
    static func showMessage(_ key: String, in presenter: UIViewController) {
        let activeWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        var top = presenter.view.window?.rootViewController ?? activeWindow?.rootViewController ?? presenter
        while let presented = top.presentedViewController { top = presented }
        let alert = UIAlertController(title: "VoidLink", message: key.localized, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok".localized, style: .default))
        top.present(alert, animated: true)
    }
}

@MainActor private final class ApplicationIconController: UITableViewController,
    UIDocumentPickerDelegate, SFSafariViewControllerDelegate {
    private let appName: String
    private let launchURL: URL?
    private let createWebClip: Bool
    private let service = GameCoverService()
    private var task: Task<Void, Never>?
    private var exportDirectory: URL?
    private var profileServer: WebClipProfileServer?
    private var profile: Data?
    private var footer = ""
    private weak var imagePicker: UIDocumentPickerViewController?
    private var hasStarted = false

    init(appName: String, launchURL: URL?, createWebClip: Bool) {
        self.appName = appName
        self.launchURL = launchURL
        self.createWebClip = createWebClip
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = (createWebClip ? "Create App Clip" : "Save App Icon").localized
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasStarted { hasStarted = true; loadIcon() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed == true || isBeingDismissed {
            task?.cancel()
            profileServer?.stop()
        }
    }

    @objc private func close() {
        task?.cancel()
        profileServer?.stop()
        dismiss(animated: true)
    }

    private func setBusy(_ busy: Bool) {
        if busy {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else { navigationItem.rightBarButtonItem = nil }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        profile == nil ? 0 : 2
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { footer }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cover") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cover")
        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = (indexPath.row == 0 ? "Install Web Clip" : "Save Web Clip Profile").localized
        cell.detailTextLabel?.text = appName
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let profile {
            if indexPath.row == 0 { install(profile) }
            else { export(profile, extension: "mobileconfig") }
        }
    }

    @objc private func loadIcon() {
        task?.cancel()
        profileServer?.stop()
        profile = nil
        footer = "Finding the app icon automatically…".localized
        tableView.reloadData()
        setBusy(true)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await service.automaticIcon(named: appName)
                try Task.checkCancellation()
                try useIcon(ApplicationIcon.png(from: data))
            } catch ApplicationShortcutError.noCover {
                guard !Task.isCancelled else { return }
                setBusy(false)
                footer = ApplicationShortcutError.noCover.localizedDescription
                tableView.reloadData()
                chooseImage()
            } catch {
                guard !Task.isCancelled else { return }
                failed(error)
            }
        }
    }

    private func useIcon(_ png: Data) throws {
        setBusy(false)
        if createWebClip {
            guard let launchURL else { throw ApplicationShortcutError.invalidLink }
            profile = try ApplicationWebClip.profile(name: appName, launchURL: launchURL, icon: png)
            footer = "The Web Clip opens this application in VoidLink. Tap Install Web Clip, allow the profile download, then open Settings > Profile Downloaded > Install. You can remove the icon or profile later.".localized
            let preview = UIImageView(image: UIImage(data: png))
            preview.contentMode = .scaleAspectFit
            preview.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 180)
            preview.accessibilityLabel = appName
            tableView.tableHeaderView = preview
            tableView.reloadData()
        } else {
            footer = "App icon ready. Choose where to save the PNG file.".localized
            tableView.reloadData()
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Retry".localized, style: .plain, target: self, action: #selector(loadIcon))
            export(png, extension: "png")
        }
    }

    @objc private func chooseImage() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Choose Image".localized, style: .plain, target: self, action: #selector(chooseImage))
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true) }
        else { picker = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .import) }
        picker.allowsMultipleSelection = false
        picker.delegate = self
        imagePicker = picker
        present(picker, animated: true)
    }

    private func failed(_ error: Error) {
        setBusy(false)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Retry".localized, style: .plain, target: self, action: #selector(loadIcon))
        footer = error.localizedDescription
        tableView.reloadData()
    }

    private func export(_ data: Data, extension fileExtension: String) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
            exportDirectory = directory
            let safeName = String(appName.map { "/\\:\n\r".contains($0) ? "_" : $0 }.prefix(100))
            let file = directory.appendingPathComponent(safeName.isEmpty ? "VoidLink" : safeName).appendingPathExtension(fileExtension)
            try data.write(to: file, options: .atomic)
            let picker: UIDocumentPickerViewController
            if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true) }
            else { picker = UIDocumentPickerViewController(url: file, in: .exportToService) }
            picker.delegate = self
            present(picker, animated: true)
        } catch { failed(error) }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if controller === imagePicker {
            guard let url = urls.first else { return }
            // Finish dismissal before presenting the export sheet, if requested.
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.setBusy(true)
                self.task = Task {
                    do {
                        let png = try await Task.detached {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 50 * 1024 * 1024 else { throw ApplicationShortcutError.invalidImage }
                            return try ApplicationIcon.png(from: Data(contentsOf: url, options: .mappedIfSafe))
                        }.value
                        try Task.checkCancellation()
                        try self.useIcon(png)
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.failed(error)
                        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Choose Image".localized, style: .plain, target: self, action: #selector(self.chooseImage))
                    }
                }
            }
        } else if !createWebClip { dismiss(animated: true) }
    }

    private func install(_ data: Data) {
        profileServer?.stop()
        let server = WebClipProfileServer(profile: data)
        profileServer = server
        setBusy(true)
        server.start { [weak self, weak server] result in
            guard let self, self.profileServer === server else { return }
            self.setBusy(false)
            switch result {
            case .success(let url):
                let safari = SFSafariViewController(url: url)
                safari.delegate = self
                self.present(safari, animated: true)
            case .failure(let error): self.failed(error)
            }
        }
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) { profileServer?.stop() }

    deinit {
        task?.cancel()
        profileServer?.stop()
        if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
    }
}
#endif
