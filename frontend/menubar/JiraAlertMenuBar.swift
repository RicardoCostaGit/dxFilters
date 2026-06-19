import Cocoa
import CoreServices
import UserNotifications

/// ponytail: append-only file log for field debugging; ceiling ~2MB then truncate head.
private enum DiagnosticLog {
    static let maxBytes = 2_000_000
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/jira-alert/dxFilters.log")

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(timestamp.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > maxBytes {
            truncateHead(keeping: maxBytes / 2)
        }
    }

    private static func truncateHead(keeping bytes: Int) {
        guard let data = try? Data(contentsOf: url), data.count > bytes else { return }
        let slice = data.suffix(bytes)
        try? slice.write(to: url, options: .atomic)
        write("[log truncated]")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate, MenuPanelDelegate {
    private var statusItem: NSStatusItem!
    private var menuBarStatusView: MenuBarStatusItemView?
    private var lastRenderedBadgeCount = -1
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?
    private var outsideClickGlobalMonitor: Any?
    private var panelView: MenuPanelView?
    private var pollTimer: Timer?
    private var lastStatus = "dxFilters · Jira filter alerts"
    private var unreadCount = 0
    private var badgeCount = 0
    private var badgePulseAlpha: CGFloat = 1
    private var badgePulseTimer: Timer?
    private var lastCriticalAlertAtCount = 0
    private var repoRootURL: URL?
    private var pythonPath = "/usr/bin/python3"
    private var scriptPath = ""
    private var panelState = MenuPanelState()
    private var lastCheckDate: Date?
    private var currentFilterURL: String?
    private var pollingPaused = false
    private var pauseReason = ""
    private var powerObservers: [NSObjectProtocol] = []
    private var doNotDisturbMode: DoNotDisturbDuration = .off
    private var doNotDisturbUntil: Date?
    private var notificationVolume: Double = 1.0
    private var notificationSoundID = NotificationSound.default.rawValue

    private static let appDisplayName = "dxFilters"
    private static let appLongName = "Jira filter alerts"
    private static let notificationCategoryID = "JIRA_NEW_ISSUE"
    private static let notificationGroupID = "dxfilters"
    private static let openIssueActionID = "OPEN_ISSUE"
    private static let dismissActionID = "DISMISS"
    private static let appBundleID = "com.dxfilters.menubar"

    private var repoRoot: URL {
        if let repoRootURL {
            return repoRootURL
        }
        fatalError("repoRoot accessed before configurePaths()")
    }

    private func resolveRepoRoot() -> URL? {
        if let configured = Bundle.main.infoDictionary?["JiraAlertRepoRoot"] as? String {
            let url = URL(fileURLWithPath: configured, isDirectory: true)
            if hasScript(at: url) {
                return url
            }
        }

        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/jira-alert/repo.path")
        if let text = try? String(contentsOf: config, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let url = URL(fileURLWithPath: trimmed, isDirectory: true)
                if hasScript(at: url) {
                    return url
                }
            }
        }

        if let env = ProcessInfo.processInfo.environment["JIRA_ALERT_HOME"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if hasScript(at: url) {
                return url
            }
        }

        var dir = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        while dir.path != "/" {
            if hasScript(at: dir) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private func hasScript(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("backend/jira_alert.py").path)
    }

    private func configurePaths() -> String? {
        guard let root = resolveRepoRoot() else {
            DiagnosticLog.write("configurePaths: backend/jira_alert.py not found")
            return "Could not find backend/jira_alert.py. Run ./frontend/menubar/install.sh from the repo."
        }
        repoRootURL = root
        scriptPath = root.appendingPathComponent("backend/jira_alert.py").path
        let venv = root.appendingPathComponent("backend/.venv/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: venv.path) else {
            DiagnosticLog.write("configurePaths: missing venv at \(venv.path)")
            return "Python backend not set up. Run ./frontend/menubar/install.sh from the repo."
        }
        pythonPath = venv.path
        DiagnosticLog.write("configurePaths: repo=\(root.path) python=\(pythonPath)")
        return nil
    }

    private func logStartupDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        DiagnosticLog.write("=== dxFilters \(version) build \(build) ===")
        DiagnosticLog.write("bundle=\(Bundle.main.bundlePath)")
        if let plistRoot = Bundle.main.infoDictionary?["JiraAlertRepoRoot"] as? String {
            DiagnosticLog.write("Info.plist JiraAlertRepoRoot=\(plistRoot)")
        }
        let repoPathFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/jira-alert/repo.path")
        if let repoPath = try? String(contentsOf: repoPathFile, encoding: .utf8) {
            DiagnosticLog.write("repo.path=\(repoPath.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if let root = resolveRepoRoot() {
            let venv = root.appendingPathComponent("backend/.venv/bin/python3")
            DiagnosticLog.write(
                "resolved repo=\(root.path) venv_exists=\(FileManager.default.isExecutableFile(atPath: venv.path))"
            )
        } else {
            DiagnosticLog.write("resolved repo=NOT FOUND")
        }
        DiagnosticLog.write("log file: \(DiagnosticLog.url.path)")
    }

    private static func logSafePythonArgs(_ args: [String]) -> String {
        args.map { arg in
            if arg.contains("jira_pat") { return "{credentials: redacted}" }
            if arg.count > 160 { return String(arg.prefix(157)) + "…" }
            return arg
        }.joined(separator: " ")
    }

    private var pollInterval: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["POLL_INTERVAL_SECONDS"],
           let value = Double(raw), value >= 30 {
            return value
        }
        return 300
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureAppIcon()
        registerAppWithLaunchServices()
        loadDoNotDisturbSettings()
        loadNotificationPreferences()
        setupNotificationCenter()
        setupPowerObservers()
        setupStatusItem()

        logStartupDiagnostics()

        if let error = configurePaths() {
            applyPanelError(error, detail: "Diagnostics: \(DiagnosticLog.url.path)")
            updatePanel()
            requestNotificationAccess()
            return
        }

        requestNotificationAccess()
        panelState.statusLine = "Starting…"
        refreshCredentialsPanelState()
        updatePanel()
        schedulePoll()
        runCheck(resetBaseline: false)
    }

    private func setupNotificationCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let openAction = UNNotificationAction(
            identifier: Self.openIssueActionID,
            title: "Open the ticket",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionID,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    private func notificationIconURL() -> URL? {
        if let url = Bundle.main.url(forResource: "notification-icon@2x", withExtension: "png") {
            return url
        }
        if let url = Bundle.main.url(forResource: "notification-icon", withExtension: "png") {
            return url
        }
        if let url = Bundle.main.url(forResource: "jntc-logo-panel@2x", withExtension: "png") {
            return url
        }
        return Bundle.main.url(forResource: "jntc-logo@2x", withExtension: "png")
    }

    private func bundledAppIcon() -> NSImage? {
        if let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: icnsPath) {
            icon.isTemplate = false
            return icon
        }
        guard let url = notificationIconURL(),
              let icon = NSImage(contentsOf: url) else { return nil }
        icon.isTemplate = false
        return icon
    }

    private func configureAppIcon() {
        guard let icon = bundledAppIcon() else { return }
        NSApplication.shared.applicationIconImage = icon
        NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
    }

    private func registerAppWithLaunchServices() {
        let appURL = Bundle.main.bundleURL as CFURL
        _ = LSRegisterURL(appURL, true)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: Bundle.main.bundlePath
        )
    }

    private func makeNotificationContent(
        title: String,
        subtitle: String,
        body: String,
        userInfo: [AnyHashable: Any],
        timeSensitive: Bool = false
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.userInfo = userInfo
        content.categoryIdentifier = Self.notificationCategoryID
        content.threadIdentifier = Self.notificationGroupID
        if #available(macOS 12.0, *) {
            content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        }
        return content
    }

    private func requestNotificationAccess(then completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    if let error {
                        self.setStatus("!", tooltip: error.localizedDescription)
                        self.panelState.statusLine = "Notifications: \(error.localizedDescription)"
                        self.updatePanel()
                        completion?()
                        return
                    }
                    if granted {
                        completion?()
                        return
                    }
                    self.setStatus("!", tooltip: "Allow dxFilters in System Settings → Notifications → Banners")
                    self.panelState.statusLine = "Enable dxFilters banners in System Settings → Notifications"
                    self.updatePanel()
                    completion?()
                }
            }
        }
    }

    private func runCommand(_ launchPath: String, arguments: [String]) -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (127, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, text)
    }

    private func notificationSoundURL() -> URL? {
        let sound = NotificationSound(rawValue: notificationSoundID) ?? .default
        let system = sound.fileURL
        if FileManager.default.fileExists(atPath: system.path) {
            return system
        }
        // ponytail: legacy bundled mp3 if a custom sound was ever shipped
        if let url = Bundle.main.url(forResource: "alert-notification", withExtension: "mp3") {
            return url
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/alert-notification.mp3")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    private func playNotificationSound() {
        guard notificationVolume > 0 else { return }
        guard let url = notificationSoundURL() else { return }
        let volume = String(format: "%.2f", notificationVolume)
        DispatchQueue.global(qos: .utility).async {
            _ = self.runCommand("/usr/bin/afplay", arguments: ["-v", volume, url.path])
        }
    }

    private func afterPanelDismiss(_ action: @escaping () -> Void) {
        hidePanel()
        DispatchQueue.main.async(execute: action)
    }

    private func deliverNotification(
        identifier: String,
        title: String,
        subtitle: String,
        body: String,
        userInfo: [AnyHashable: Any] = [:],
        onDone: @escaping (String?, String) -> Void
    ) {
        let finish: (String?, String) -> Void = { error, via in
            if error == nil {
                self.playNotificationSound()
            }
            onDone(error, via)
        }

        let send = {
            DispatchQueue.main.async {
                let center = UNUserNotificationCenter.current()
                center.getNotificationSettings { settings in
                    let sendUN = {
                        let content = self.makeNotificationContent(
                            title: title,
                            subtitle: subtitle,
                            body: body,
                            userInfo: userInfo,
                            timeSensitive: identifier.hasPrefix("jira-alert-test-")
                        )
                        center.removePendingNotificationRequests(withIdentifiers: [identifier])
                        center.removeDeliveredNotifications(withIdentifiers: [identifier])
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
                        NSApp.activate(ignoringOtherApps: true)
                        center.add(request) { error in
                            DispatchQueue.main.async {
                                if let error {
                                    finish(error.localizedDescription, "failed")
                                } else {
                                    finish(nil, Self.appDisplayName)
                                }
                            }
                        }
                    }

                    let deniedMessage =
                        "Enable \(Self.appDisplayName) in System Settings → Notifications (Banners or Alerts)"

                    let alertsDisabledMessage =
                        "Turn on Banners or Alerts for \(Self.appDisplayName) in System Settings → Notifications"

                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        if settings.alertSetting == .disabled {
                            finish(alertsDisabledMessage, "denied")
                            return
                        }
                        sendUN()
                    case .notDetermined:
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            DispatchQueue.main.async {
                                if granted {
                                    sendUN()
                                } else {
                                    finish(deniedMessage, "denied")
                                }
                            }
                        }
                    case .denied:
                        finish(deniedMessage, "denied")
                    @unknown default:
                        finish(deniedMessage, "denied")
                    }
                }
            }
        }

        if popover?.isShown == true {
            afterPanelDismiss(send)
        } else {
            hidePanel()
            send()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        badgePulseTimer?.invalidate()
        for observer in powerObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        powerObservers.removeAll()
    }

    private func setupPowerObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        powerObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pausePolling(reason: "Mac sleeping")
        })
        powerObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumePolling(runImmediateCheck: true)
        })

        let lockCenter = DistributedNotificationCenter.default()
        powerObservers.append(lockCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pausePolling(reason: "Screen locked")
        })
        powerObservers.append(lockCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumePolling(runImmediateCheck: true)
        })
    }

    private func pausePolling(reason: String) {
        pollingPaused = true
        pauseReason = reason
        pollTimer?.invalidate()
        pollTimer = nil
        panelState.connection = "Paused"
        panelState.connectionOK = true
        panelState.statusLine = "Polling paused · \(reason.lowercased())"
        updatePanel()
        setStatus("⏸", tooltip: "Polling paused: \(reason)")
    }

    private func resumePolling(runImmediateCheck: Bool) {
        guard pollingPaused else { return }
        pollingPaused = false
        pauseReason = ""
        schedulePoll()
        if runImmediateCheck {
            runCheck(resetBaseline: false, force: true)
        } else {
            panelState.connection = "Running"
            panelState.connectionOK = true
            updatePanel()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Never set button.title or button.image for counts — custom NSStackView subview owns layout.
        button.image = nil
        button.title = ""

        let statusView = MenuBarStatusItemView()
        statusView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            statusView.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor),
            statusView.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor),
        ])
        menuBarStatusView = statusView

        syncBadgePulseAnimation()
        updateStatusIcon()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if let popover, popover.isShown {
            hidePanel()
            return
        }
        let popover = NSPopover()
        let panel = MenuPanelView(frame: NSRect(origin: .zero, size: MenuPanelView.panelSize))
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.refreshBrandIcon()
        panel.update(state: panelState)
        panelView = panel
        popover.delegate = self
        popover.contentSize = NSSize(
            width: MenuPanelView.panelWidth,
            height: panelContentHeight()
        )
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = panel
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = panel.window {
            panel.layer?.contentsScale = window.backingScaleFactor
            panel.needsLayout = true
        }
        self.popover = popover
        DispatchQueue.main.async { [weak self] in
            self?.installOutsideClickMonitor()
        }
    }

    private func hidePanel() {
        removeOutsideClickMonitor()
        popover?.close()
        popover = nil
        panelView = nil
        panelState.soundExpanded = false
        panelState.errorDetailExpanded = false
    }

    private static func panelContentHeight(for state: MenuPanelState) -> CGFloat {
        MenuPanelView.panelHeight(
            soundExpanded: state.soundExpanded,
            errorVisible: state.statusDetail != nil,
            errorExpanded: state.errorDetailExpanded
        )
    }

    private func panelContentHeight() -> CGFloat {
        Self.panelContentHeight(for: panelState)
    }

    private func resizePopoverIfNeeded() {
        guard let popover, popover.isShown else { return }
        let size = NSSize(
            width: MenuPanelView.panelWidth,
            height: panelContentHeight()
        )
        popover.contentSize = size
        panelView?.setFrameSize(size)
        panelView?.layoutSubtreeIfNeeded()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissPanelIfClickOutside(event)
            return event
        }
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissPanelIfClickOutside(event)
        }
    }

    private func dismissPanelIfClickOutside(_ event: NSEvent) {
        guard popover?.isShown == true else { return }
        if isStatusBarClick(event) { return }
        if isClickInsidePanel(event) { return }
        hidePanel()
    }

    private func isStatusBarClick(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else { return false }
        if event.window === buttonWindow { return true }
        let screenPoint: NSPoint = if let window = event.window {
            window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        } else {
            NSEvent.mouseLocation
        }
        let pointInWindow = buttonWindow.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        let pointInButton = button.convert(pointInWindow, from: nil)
        return button.bounds.insetBy(dx: -4, dy: -4).contains(pointInButton)
    }

    private func isClickInsidePanel(_ event: NSEvent) -> Bool {
        guard let panelWindow = popover?.contentViewController?.view.window else { return false }
        return event.window === panelWindow
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        panelState.soundExpanded = false
        popover = nil
        panelView = nil
    }

    private func updatePanel() {
        panelState.newCount = unreadCount
        panelState.badgeCount = badgeCount
        panelState.filterURL = currentFilterURL
        refreshDoNotDisturbPanelState()
        refreshNotificationPreferencesPanelState()
        if let lastCheckDate {
            panelState.lastCheck = Self.timeFormatter.string(from: lastCheckDate)
        }
        panelView?.update(state: panelState)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func compactStatus(message: String, issueCount: Int, newCount: Int) -> String {
        if newCount > 0 {
            return "\(newCount) new · \(issueCount) in filter"
        }
        if message.lowercased().contains("baseline") {
            return "Baseline saved · \(issueCount) issues"
        }
        if message.lowercased().contains("no new") {
            return "Up to date · \(issueCount) in filter"
        }
        return message
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        let animateWidth = badgeCount != lastRenderedBadgeCount
        menuBarStatusView?.apply(
            count: badgeCount,
            severityCount: panelState.issueCount,
            pulse: badgePulseAlpha,
            animated: animateWidth
        )
        lastRenderedBadgeCount = badgeCount
        button.toolTip = lastStatus
    }

    private func syncBadgePulseAnimation() {
        badgePulseTimer?.invalidate()
        badgePulseTimer = nil
        guard badgeCount > 0 else {
            badgePulseAlpha = 1
            return
        }

        badgePulseAlpha = 1
        badgePulseTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.badgePulseAlpha = self.badgePulseAlpha > 0.75 ? 0.38 : 1
            self.updateStatusIcon()
        }
    }

    private func setStatus(_ text: String, tooltip: String? = nil) {
        lastStatus = tooltip ?? text
        updateStatusIcon()
    }

    func panelDidRequestCheck() { runCheck(resetBaseline: false, force: true) }
    func panelDidRequestTestNotification() { sendTestNotification() }
    func panelDidRequestOpenFilter() {
        if let urlString = currentFilterURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    func panelDidRequestResetBaseline() { runCheck(resetBaseline: true) }
    func panelDidChangeSoundExpanded(_ expanded: Bool) {
        panelState.soundExpanded = expanded
        updatePanel()
        resizePopoverIfNeeded()
    }
    func panelDidChangeErrorDetailExpanded(_ expanded: Bool) {
        panelState.errorDetailExpanded = expanded
        updatePanel()
        resizePopoverIfNeeded()
    }
    func panelDidUpdateNotificationVolume(_ volume: Double) {
        notificationVolume = min(max(volume, 0), 1)
        saveNotificationPreferences()
        refreshNotificationPreferencesPanelState()
        updatePanel()
    }
    func panelDidSelectNotificationSound(_ soundID: String) {
        guard NotificationSound(rawValue: soundID) != nil else { return }
        notificationSoundID = soundID
        saveNotificationPreferences()
        refreshNotificationPreferencesPanelState()
        updatePanel()
        playNotificationSound()
    }
    func panelDidRequestPreviewNotificationSound() { playNotificationSound() }
    func panelDidRequestOpenSystemNotificationSettings() { openNotificationSettings(nil) }

    private static func isCredentialsError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("jira_pat")
            || (lower.contains("jira_base_url") && lower.contains("set"))
    }

    private static func compactPanelError(_ raw: String) -> (summary: String, detail: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("modulenotfounderror") {
            if lower.contains("requests") {
                return (
                    "Python dependencies missing",
                    "Missing the requests package. From the repo root run ./frontend/menubar/install.sh "
                        + "(it creates backend/.venv and installs requirements.txt). "
                        + "Diagnostics: \(DiagnosticLog.url.path)"
                )
            }
            return ("Python backend error", trimmed + "\nDiagnostics: \(DiagnosticLog.url.path)")
        }
        if trimmed.count <= 56 { return (trimmed, nil) }
        return (String(trimmed.prefix(53)) + "…", trimmed)
    }

    private func clearPanelErrorDetail() {
        panelState.statusDetail = nil
        panelState.errorDetailExpanded = false
    }

    private func applyPanelError(_ raw: String, tooltip: String? = nil, detail: String? = nil) {
        let compact = Self.compactPanelError(raw)
        panelState.statusLine = compact.summary
        panelState.statusDetail = detail ?? compact.detail
        panelState.errorDetailExpanded = false
        panelState.connection = "Error"
        panelState.connectionOK = false
        setStatus("!", tooltip: tooltip ?? compact.summary)
    }

    private func applyPanelStatusMessage(_ message: String) {
        clearPanelErrorDetail()
        panelState.statusLine = message
    }

    func panelDidRequestConfigureCredentials() {
        guard repoRootURL != nil else {
            applyPanelError("Could not find backend/jira_alert.py")
            updatePanel()
            return
        }
        runPythonCommand(["--credentials-status"]) { payload in
            let base = payload["jira_base_url"] as? String ?? ""
            self.presentCredentialsDialog(prefilledBaseURL: base)
        }
    }
    func panelDidRequestSelectFilter(id: String) {
        guard id != panelState.filterID else { return }
        runPythonCommand(["--set-filter", id]) { payload in
            if let error = payload["error"] as? String, !error.isEmpty {
                self.applyPanelError(error)
                self.updatePanel()
                return
            }
            self.runCheck(resetBaseline: false)
        }
    }
    func panelDidRequestAddFilter() {
        let alert = NSAlert()
        alert.messageText = "Add Jira Filter"
        alert.informativeText = "Enter the numeric filter id from Jira (e.g. 12345)."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Filter id"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let filterID = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filterID.isEmpty else { return }
        runPythonCommand(["--add-filter", filterID, "--set-filter", filterID]) { payload in
            if let error = payload["error"] as? String, !error.isEmpty {
                self.applyPanelError(error)
                self.updatePanel()
                return
            }
            self.runCheck(resetBaseline: false)
        }
    }
    func panelDidRequestRenameFilter(id: String, currentName: String, jiraName: String) {
        let alert = NSAlert()
        alert.messageText = "Rename Filter"
        alert.informativeText = "Original Jira name: \(jiraName)"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = currentName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        runPythonCommand(["--rename-filter", id, "--filter-name", newName]) { payload in
            if let error = payload["error"] as? String, !error.isEmpty {
                self.applyPanelError(error)
                self.updatePanel()
                return
            }
            self.runCheck(resetBaseline: false)
        }
    }
    func panelDidRequestDeleteFilter(id: String, name: String) {
        let alert = NSAlert()
        alert.messageText = "Remove Filter?"
        alert.informativeText = "Remove \"\(name)\" (#\(id)) from watchers? Its saved baseline will be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runPythonCommand(["--remove-filter", id]) { payload in
            if let error = payload["error"] as? String, !error.isEmpty {
                self.applyPanelError(error)
                self.updatePanel()
                return
            }
            self.runCheck(resetBaseline: false)
        }
    }
    func panelDidRequestQuit() { NSApp.terminate(nil) }

    func panelDidSetDoNotDisturb(duration: DoNotDisturbDuration) {
        applyDoNotDisturb(duration: duration)
        updatePanel()
    }

    private struct StoredDoNotDisturb: Codable {
        var mode: Int
        var until: Date?
    }

    private struct StoredNotificationPreferences: Codable {
        var volume: Double
        var soundID: String?
    }

    private static var preferencesConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/jira-alert/preferences.json")
    }

    private static var dndConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/jira-alert/dnd.json")
    }

    private static let dndUntilFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func loadNotificationPreferences() {
        let url = Self.preferencesConfigURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(StoredNotificationPreferences.self, from: data) {
            notificationVolume = min(max(stored.volume, 0), 1)
            if let soundID = stored.soundID, NotificationSound(rawValue: soundID) != nil {
                notificationSoundID = soundID
            }
        }
        refreshNotificationPreferencesPanelState()
    }

    private func saveNotificationPreferences() {
        let url = Self.preferencesConfigURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stored = StoredNotificationPreferences(volume: notificationVolume, soundID: notificationSoundID)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func refreshNotificationPreferencesPanelState() {
        panelState.notificationVolume = notificationVolume
        panelState.notificationSoundID = notificationSoundID
    }

    private func refreshCredentialsPanelState() {
        guard repoRootURL != nil else { return }
        runPythonCommand(["--credentials-status"]) { payload in
            self.panelState.jiraBaseURL = payload["jira_base_url"] as? String ?? ""
            self.panelState.jiraCredentialsConfigured = payload["configured"] as? Bool ?? false
            self.updatePanel()
        }
    }

    private func presentCredentialsDialog(prefilledBaseURL: String) {
        let panelWidth: CGFloat = 380
        let horizontalInset: CGFloat = 20
        let fieldWidth = panelWidth - (horizontalInset * 2)
        let fieldHeight: CGFloat = 28
        let fieldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let controller = CredentialsFormPanelController()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Jira setup"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let logoView = NSImageView()
        logoView.image = JiraAssets.menuBarLogoImage(pointSize: 24)
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.translatesAutoresizingMaskIntoConstraints = false

        let infoLabel = NSTextField(wrappingLabelWithString: "Enter your Jira URL and personal access token (PAT).")
        infoLabel.font = .systemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.isEditable = false
        infoLabel.isBezeled = false
        infoLabel.drawsBackground = false
        infoLabel.preferredMaxLayoutWidth = fieldWidth
        infoLabel.maximumNumberOfLines = 0
        infoLabel.lineBreakMode = .byWordWrapping
        infoLabel.setContentHuggingPriority(.defaultLow, for: .vertical)

        let urlLabel = NSTextField(labelWithString: "Jira URL")
        urlLabel.font = .systemFont(ofSize: 11, weight: .medium)
        urlLabel.textColor = .secondaryLabelColor

        let urlField = NSTextField(
            string: prefilledBaseURL
        )
        urlField.placeholderString = "https://<BASE_URL>"
        configureCredentialsInputField(urlField, font: fieldFont)
        urlField.delegate = controller.fieldDelegate

        let patLabel = NSTextField(labelWithString: "Personal access token")
        patLabel.font = .systemFont(ofSize: 11, weight: .medium)
        patLabel.textColor = .secondaryLabelColor

        let patField = PasteableSecureTextField(string: "")
        configureCredentialsInputField(patField, font: fieldFont)
        patField.delegate = controller.fieldDelegate

        let saveButton = NSButton(title: "Save", target: controller, action: #selector(CredentialsFormPanelController.save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "Cancel", target: controller, action: #selector(CredentialsFormPanelController.cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually

        let fieldsStack = NSStackView(views: [urlLabel, urlField, patLabel, patField])
        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 4
        fieldsStack.setCustomSpacing(10, after: urlField)

        let mainStack = NSStackView(views: [logoView, infoLabel, fieldsStack, buttonRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: horizontalInset, bottom: 16, right: horizontalInset)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 260))
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 24),
            logoView.heightAnchor.constraint(equalToConstant: 24),
            urlField.widthAnchor.constraint(equalToConstant: fieldWidth),
            urlField.heightAnchor.constraint(equalToConstant: fieldHeight),
            patField.widthAnchor.constraint(equalTo: urlField.widthAnchor),
            patField.heightAnchor.constraint(equalToConstant: fieldHeight),
            buttonRow.widthAnchor.constraint(equalToConstant: fieldWidth),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        panel.contentView = contentView
        contentView.layoutSubtreeIfNeeded()
        let fittedHeight = mainStack.fittingSize.height
        panel.setContentSize(NSSize(width: panelWidth, height: max(fittedHeight, 240)))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(urlField)
        CredentialsFieldEditorSupport.configureEditor(for: urlField)

        let code = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard code == .OK, controller.saved else { return }

        let base = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pat = patField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !pat.isEmpty else {
            applyPanelStatusMessage("Jira URL and PAT are required")
            updatePanel()
            return
        }

        let payload: [String: String] = ["jira_base_url": base, "jira_pat": pat]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            applyPanelStatusMessage("Could not encode credentials")
            updatePanel()
            return
        }

        runPythonCommand(["--save-credentials-json", json]) { response in
            if let error = response["error"] as? String, !error.isEmpty {
                DiagnosticLog.write("save-credentials failed: \(error)")
                self.applyPanelError(error)
                self.updatePanel()
                return
            }
            let configured = response["configured"] as? Bool ?? false
            DiagnosticLog.write("save-credentials ok configured=\(configured)")
            self.clearPanelErrorDetail()
            self.panelState.jiraBaseURL = response["jira_base_url"] as? String ?? base
            self.panelState.jiraCredentialsConfigured = response["configured"] as? Bool ?? true
            self.panelState.statusLine = "Credentials saved"
            self.updatePanel()
            self.runCheck(resetBaseline: false, force: true)
        }
    }

    private func configureCredentialsInputField(_ field: NSTextField, font: NSFont) {
        field.font = font
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.focusRingType = .exterior
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
    }

    private func loadDoNotDisturbSettings() {
        let url = Self.dndConfigURL
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredDoNotDisturb.self, from: data),
              let mode = DoNotDisturbDuration(rawValue: stored.mode) else {
            refreshDoNotDisturbPanelState()
            return
        }
        doNotDisturbMode = mode
        doNotDisturbUntil = stored.until
        if let until = stored.until, until <= Date() {
            applyDoNotDisturb(duration: .off, persist: true)
        } else {
            refreshDoNotDisturbPanelState()
        }
    }

    private func saveDoNotDisturbSettings() {
        let url = Self.dndConfigURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stored = StoredDoNotDisturb(mode: doNotDisturbMode.rawValue, until: doNotDisturbUntil)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func applyDoNotDisturb(duration: DoNotDisturbDuration, persist: Bool = true) {
        doNotDisturbMode = duration
        switch duration {
        case .off:
            doNotDisturbUntil = nil
        case .oneDay, .threeDays, .sevenDays:
            doNotDisturbUntil = Calendar.current.date(byAdding: .day, value: duration.rawValue, to: Date())
        case .untilOff:
            doNotDisturbUntil = nil
        }
        if persist {
            saveDoNotDisturbSettings()
        }
        refreshDoNotDisturbPanelState()
    }

    private func refreshDoNotDisturbPanelState() {
        guard doNotDisturbMode != .off else {
            panelState.doNotDisturbActive = false
            panelState.doNotDisturbSummary = "Alerts on"
            panelState.doNotDisturbModeRaw = DoNotDisturbDuration.off.rawValue
            return
        }
        panelState.doNotDisturbActive = true
        panelState.doNotDisturbModeRaw = doNotDisturbMode.rawValue
        switch doNotDisturbMode {
        case .untilOff:
            panelState.doNotDisturbSummary = "Muted · until off"
        case .oneDay, .threeDays, .sevenDays:
            if let until = doNotDisturbUntil {
                panelState.doNotDisturbSummary = "Until \(Self.dndUntilFormatter.string(from: until))"
            } else {
                panelState.doNotDisturbSummary = doNotDisturbMode.menuTitle
            }
        case .off:
            panelState.doNotDisturbSummary = "Alerts on"
        }
    }

    private func isDoNotDisturbActive() -> Bool {
        if doNotDisturbMode == .off {
            return false
        }
        if let until = doNotDisturbUntil, until <= Date() {
            applyDoNotDisturb(duration: .off)
            updatePanel()
            return false
        }
        return true
    }

    private func filterURLForNotifications() -> String? {
        if let url = currentFilterURL, !url.isEmpty { return url }
        var base = panelState.jiraBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let filterID = panelState.filterID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !filterID.isEmpty else { return nil }
        return "\(base)/issues/?filter=\(filterID)"
    }

    private func sendTestNotification() {
        guard panelState.jiraCredentialsConfigured else {
            panelState.statusLine = "Configure Jira URL and PAT first (key icon)"
            updatePanel()
            return
        }
        let filterID = panelState.filterID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filterID.isEmpty else {
            panelState.statusLine = "Add a watcher filter before testing alerts"
            updatePanel()
            return
        }
        guard let filterURL = filterURLForNotifications() else {
            panelState.statusLine = "Jira URL missing — configure credentials first"
            updatePanel()
            return
        }

        let filterName = panelState.filterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = filterName.isEmpty ? "Filter #\(filterID)" : "\(filterName) · #\(filterID)"
        let userInfo: [AnyHashable: Any] = [
            "filterURL": filterURL,
            "issueURL": filterURL,
            "issueKey": "TEST",
        ]

        afterPanelDismiss {
            self.deliverNotification(
                identifier: "jira-alert-test-\(UUID().uuidString)",
                title: "dxFilters test alert",
                subtitle: subtitle,
                body: "Tap to open your Jira filter in the browser.",
                userInfo: userInfo
            ) { error, via in
                if let error {
                    self.applyPanelError(error)
                } else {
                    self.clearPanelErrorDetail()
                    self.setStatus("OK", tooltip: "Test banner sent via \(via)")
                    self.panelState.statusLine = "Test banner sent via \(via)"
                }
                self.updatePanel()
            }
        }
    }

    private func schedulePoll() {
        guard !pollingPaused else { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.runCheck(resetBaseline: false)
        }
    }

    @objc private func openNotificationSettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func runCheck(resetBaseline: Bool, force: Bool = false) {
        guard force || !pollingPaused else { return }
        guard repoRootURL != nil else { return }
        DispatchQueue.global(qos: .utility).async {
            let payload = self.runPythonCheck(resetBaseline: resetBaseline)
            DispatchQueue.main.async {
                self.handleCheckResult(payload)
            }
        }
    }

    private func runPythonCommand(_ extraArgs: [String], completion: (([String: Any]) -> Void)? = nil) {
        guard repoRootURL != nil else { return }
        DispatchQueue.global(qos: .utility).async {
            let payload = self.runPython(extraArgs: extraArgs)
            DispatchQueue.main.async {
                completion?(payload)
            }
        }
    }

    private func runPython(extraArgs: [String]) -> [String: Any] {
        let argsSummary = Self.logSafePythonArgs(extraArgs)
        DiagnosticLog.write("python \(pythonPath) jira_alert.py \(argsSummary)")

        let process = Process()
        process.currentDirectoryURL = repoRoot
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath] + extraArgs
        var env = ProcessInfo.processInfo.environment
        env["PYTHONWARNINGS"] = "ignore"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            DiagnosticLog.write("python launch error: \(error.localizedDescription)")
            return ["error": "Failed to run python: \(error.localizedDescription)"]
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String, !error.isEmpty {
                DiagnosticLog.write("python exit=\(process.terminationStatus) error=\(error)")
            } else {
                DiagnosticLog.write("python exit=\(process.terminationStatus) ok")
            }
            return json
        }
        if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            DiagnosticLog.write("python exit=\(process.terminationStatus) filters=\(list.count)")
            return ["filters": list]
        }

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let outText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DiagnosticLog.write(
            "python exit=\(process.terminationStatus) stderr=\(Self.logSafePythonArgs([errText])) stdout=\(Self.logSafePythonArgs([outText]))"
        )
        if process.terminationStatus == 0, !outText.isEmpty {
            return ["message": outText]
        }
        return ["error": Self.sanitizePythonError(errText.isEmpty ? outText : errText)]
    }

    /// Prefer the last actionable line from Python stderr (skip urllib warnings and file paths).
    private static func sanitizePythonError(_ raw: String) -> String {
        let fallback = "Invalid JSON from jira_alert.py"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("site-packages")
                || lower.contains("notopensslwarning")
                || lower.hasPrefix("warnings.warn")
                || line.hasPrefix("/") && line.contains(".venv/") {
                continue
            }
            if line.count <= 120 { return line }
            return String(line.prefix(117)) + "…"
        }
        return fallback
    }

    private func runPythonCheck(resetBaseline: Bool) -> [String: Any] {
        var args = ["--check-json"]
        if resetBaseline {
            args.append("--reset-baseline")
        }
        return runPython(extraArgs: args)
    }

    private func handleCheckResult(_ payload: [String: Any]) {
        lastCheckDate = Date()
        if let error = payload["error"] as? String, !error.isEmpty {
            unreadCount = 0
            badgeCount = 0
            syncBadgePulseAnimation()
            lastCriticalAlertAtCount = 0
            if Self.isCredentialsError(error) {
                panelState.jiraCredentialsConfigured = false
                clearPanelErrorDetail()
                panelState.statusLine = "Credentials required"
                panelState.connection = "Setup required"
                panelState.connectionOK = false
                setStatus("!", tooltip: "Click the key icon to configure Jira credentials")
            } else {
                applyPanelError(error)
            }
            panelState.issueCount = 0
            updatePanel()
            resizePopoverIfNeeded()
            return
        }

        clearPanelErrorDetail()
        let issueCount = payload["issue_count"] as? Int ?? 0
        let message = payload["message"] as? String ?? "Checked"
        let baseline = payload["baseline"] as? Bool ?? false
        let newIssues = payload["new_issues"] as? [[String: Any]] ?? []
        let baseURL = payload["jira_base_url"] as? String ?? ""
        let filterID = payload["filter_id"] as? String ?? panelState.filterID
        let filterName = payload["filter_name"] as? String ?? panelState.filterName
        let filterURL = baseURL.isEmpty ? nil : "\(baseURL)/issues/?filter=\(filterID)"
        currentFilterURL = filterURL

        panelState.filterID = filterID
        panelState.filterName = filterName
        panelState.filterJiraName = payload["filter_jira_name"] as? String ?? filterName
        panelState.filterIsRenamed = (payload["filter_renamed"] as? String)?.lowercased() == "true"
        panelState.savedFilters = Self.parseSavedFilters(payload["filters"])
        panelState.issueCount = issueCount
        panelState.connection = "Running"
        panelState.connectionOK = true
        panelState.statusLine = Self.compactStatus(message: message, issueCount: issueCount, newCount: newIssues.count)

        unreadCount = newIssues.count
        if unreadCount > 0 {
            badgeCount = unreadCount
        } else if issueCount > 0 {
            badgeCount = issueCount
        } else {
            badgeCount = 0
        }

        maybeShowCriticalAlert(issueCount: issueCount, filterName: filterName, filterURL: filterURL)

        if baseline {
            setStatus("OK", tooltip: message)
            syncBadgePulseAnimation()
            updatePanel()
            return
        }

        setStatus(unreadCount > 0 ? "•" : "OK", tooltip: message)
        syncBadgePulseAnimation()
        updatePanel()

        postNotificationsForNewIssues(newIssues, baseURL: baseURL)
    }

    private func postNotificationsForNewIssues(_ issues: [[String: Any]], baseURL: String) {
        guard !issues.isEmpty else { return }
        if isDoNotDisturbActive() {
            panelState.statusLine = "Do not disturb · \(issues.count) new ticket(s) muted"
            updatePanel()
            return
        }
        var index = 0
        func postNext() {
            guard index < issues.count else { return }
            let issue = issues[index]
            index += 1
            guard let key = issue["key"] as? String else {
                postNext()
                return
            }
            let summary = issue["summary"] as? String ?? "(no summary)"
            postNotification(key: key, summary: summary, baseURL: baseURL) { _ in
                if index < issues.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: postNext)
                }
            }
        }
        postNext()
    }

    private func maybeShowCriticalAlert(issueCount: Int, filterName: String, filterURL: String?) {
        guard issueCount >= 20 else {
            lastCriticalAlertAtCount = 0
            return
        }
        guard issueCount > lastCriticalAlertAtCount else { return }
        lastCriticalAlertAtCount = issueCount

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "ALERT · \(issueCount) tickets in filter"
        alert.informativeText = "\(filterName) has reached a critical backlog. Review the filter and triage open issues."
        alert.addButton(withTitle: "Open Filter")
        alert.addButton(withTitle: "Dismiss")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let urlString = filterURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func parseSavedFilters(_ value: Any?) -> [SavedFilter] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let name = item["name"] as? String ?? "Filter \(id)"
            let jiraName = item["jira_name"] as? String ?? name
            let renamed = (item["renamed"] as? String)?.lowercased() == "true"
            let active = (item["active"] as? String)?.lowercased() == "true"
            return SavedFilter(id: id, name: name, jiraName: jiraName, isRenamed: renamed, isActive: active)
        }
    }

    private func postNotification(
        key: String,
        summary: String,
        baseURL: String,
        completion: ((String?) -> Void)? = nil
    ) {
        deliverNotification(
            identifier: "jira-alert-\(key)-\(Date().timeIntervalSince1970)",
            title: "NEW TICKET ARRIVED IN FILTER",
            subtitle: key,
            body: summary,
            userInfo: ["issueKey": key, "issueURL": "\(baseURL)/browse/\(key)"],
            onDone: { error, _ in
                completion?(error)
            }
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notificationID = response.notification.request.identifier
        switch response.actionIdentifier {
        case Self.dismissActionID:
            center.removeDeliveredNotifications(withIdentifiers: [notificationID])
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        case Self.openIssueActionID, UNNotificationDefaultActionIdentifier:
            let userInfo = response.notification.request.content.userInfo
            if let urlString = userInfo["filterURL"] as? String ?? userInfo["issueURL"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else if let filterURL = currentFilterURL, let url = URL(string: filterURL) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}

private final class CredentialsFieldEditorSupport: NSObject, NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        Self.configureEditor(for: field)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        Self.scrollInsertionPointToVisible(in: field)
    }

    static func configureEditor(for field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = .controlAccentColor
        editor.selectedTextAttributes = [
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .font: field.font ?? NSFont.systemFont(ofSize: 12),
        ]
        scrollInsertionPointToVisible(in: field)
    }

    static func scrollInsertionPointToVisible(in field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.scrollRangeToVisible(editor.selectedRange())
    }
}

private final class PasteableSecureTextField: NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { CredentialsFieldEditorSupport.configureEditor(for: self) }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let key = event.charactersIgnoringModifiers?.lowercased(),
           key == "v" {
            return pastePlainTextFromPasteboard()
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        _ = pastePlainTextFromPasteboard()
    }

    private func pastePlainTextFromPasteboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return false
        }
        stringValue = text
        CredentialsFieldEditorSupport.configureEditor(for: self)
        return true
    }
}

private final class CredentialsFormPanelController: NSObject {
    var saved = false
    let fieldDelegate = CredentialsFieldEditorSupport()

    @objc func save() {
        saved = true
        NSApp.stopModal(withCode: .OK)
    }

    @objc func cancel() {
        saved = false
        NSApp.stopModal(withCode: .cancel)
    }
}

@main
struct JiraAlertMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
