import AppKit
import Combine
import NottiSDK

/// The macOS example (AD-025): one window with a button per call and a redacting log. The log shows fixed
/// events only (`ExampleLog`): no token, email, phone, client key or payload value ever reaches a row. With no real
/// credentials in `Config/Example.local.xcconfig` the app builds and runs but never calls `Notti.initialize`.
///
/// The Notti delegate integration swizzles `NSApplicationDelegate` for this class; a host that sets
/// `NottiDisableSwizzling` forwards the callbacks itself (README).
@main
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let config = ExampleConfig()
    private let log = ExampleLog()
    private let logView = NSTextView()
    private var window: NSWindow?
    private var logSubscription: AnyCancellable?
    private var removers: [() -> Void] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        logSubscription = log.$rows.sink { [weak self] rows in
            self?.logView.string = rows.joined(separator: "\n")
        }
        initialize()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removers.forEach { $0() }
    }

    // MARK: - Calls

    @objc private func initialize() {
        guard config.isConfigured else {
            log.record(.notConfigured)
            return
        }
        // Module-qualified like the iOS example: `NottiSDK.Notti` resolves under every linkage (AD-023).
        NottiSDK.Notti.initialize(
            appId: config.appId,
            clientKey: config.clientKey,
            options: Notti.Options(baseUrl: config.baseUrl, opensInAppURLs: true)
        )
        log.record(.call(.initialize, .ok))
        addListeners()
    }

    @objc private func requestPermission() {
        Notti.Notifications.requestPermission { [weak self] granted in
            Task { @MainActor in self?.log.record(.permission(granted: granted)) }
        }
    }

    @objc private func login() {
        Notti.login("example-user")
        log.record(.call(.login, .ok))
    }

    @objc private func logout() {
        Notti.logout()
        log.record(.call(.logout, .ok))
    }

    @objc private func addTag() {
        Notti.User.addTag("example", value: "1")
        log.record(.call(.addTag, .ok))
    }

    @objc private func takeInitialClick() {
        guard let payload = Notti.Notifications.takeInitialClick() else {
            log.record(.call(.takeInitialClick, .skipped))
            return
        }
        log.record(.payload(.clicked, keys: Self.keys(of: payload)))
    }

    @objc private func clearLog() {
        log.clear()
    }

    private func addListeners() {
        guard removers.isEmpty else { return }
        let received = Notti.Notifications.addReceivedListener { [weak self] payload in
            let keys = Self.keys(of: payload)
            Task { @MainActor in self?.log.record(.payload(.received, keys: keys)) }
        }
        let clicked = Notti.Notifications.addClickedListener { [weak self] payload in
            let keys = Self.keys(of: payload)
            Task { @MainActor in self?.log.record(.payload(.clicked, keys: keys)) }
        }
        removers = [{ received.remove() }, { clicked.remove() }]
        log.record(.call(.addListeners, .ok))
    }

    /// Key names only; `title` and `body` count by presence. No value is read out.
    nonisolated private static func keys(of payload: NottiNotificationPayload) -> [String] {
        var keys = Array(payload.data.keys)
        if payload.title != nil { keys.append("title") }
        if payload.body != nil { keys.append("body") }
        return keys
    }

    // MARK: - Window

    private func buildWindow() {
        let actions: [(String, Selector)] = [
            ("Initialize", #selector(initialize)),
            ("Request permission", #selector(requestPermission)),
            ("Login", #selector(login)),
            ("Logout", #selector(logout)),
            ("Add tag", #selector(addTag)),
            ("Take initial click", #selector(takeInitialClick)),
            ("Clear log", #selector(clearLog))
        ]
        let buttons = actions.map { NSButton(title: $0.0, target: self, action: $0.1) }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let column = NSStackView(views: [row, scroll])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notti Example Mac"
        window.contentView = column
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
