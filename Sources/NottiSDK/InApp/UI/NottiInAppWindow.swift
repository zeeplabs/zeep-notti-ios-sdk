import UIKit

/// Where a display window goes (IAM-36): the active `UIWindowScene`, or the screen for a scene-less app.
@available(iOSApplicationExtension, unavailable)
enum NottiInAppWindowTarget {
    case scene(UIWindowScene)
    case screen(CGRect)
}

/// Resolves the window target. Production reads `UIApplication`; tests inject a fake (RN `InAppSceneProviding`).
@available(iOSApplicationExtension, unavailable)
protocol NottiInAppSceneProviding: AnyObject {
    /// The first `.foregroundActive` scene, the screen for a scene-less app that is active, or nil while nothing
    /// is active (the display then waits for `didBecomeActive` or `UIScene.didActivateNotification`).
    func activeTarget() -> NottiInAppWindowTarget?
    /// True while the app is active (`UIApplication.State.active`).
    var isAppActive: Bool { get }
}

/// Production scene provider, a port of RN `NottiInAppSceneProvider` (`NottiInAppPresenter.swift:29-45`).
@available(iOSApplicationExtension, unavailable)
final class NottiInAppSceneProvider: NottiInAppSceneProviding {

    var isAppActive: Bool { UIApplication.shared.applicationState == .active }

    func activeTarget() -> NottiInAppWindowTarget? {
        let app = UIApplication.shared
        let scenes = app.connectedScenes.compactMap { $0 as? UIWindowScene }
        return Self.target(
            activeScene: scenes.first { $0.activationState == .foregroundActive },
            sceneCount: scenes.count,
            appActive: app.applicationState == .active,
            screenBounds: UIScreen.main.bounds
        )
    }

    /// The decision, free of `UIApplication`: the active scene wins; a scene-less app that is active gets a
    /// screen-sized window; anything else waits.
    static func target(
        activeScene: UIWindowScene?,
        sceneCount: Int,
        appActive: Bool,
        screenBounds: CGRect
    ) -> NottiInAppWindowTarget? {
        if let scene = activeScene { return .scene(scene) }
        if sceneCount == 0 && appActive { return .screen(screenBounds) }
        return nil
    }
}

/// Window above the app (`.alert` level, like RN), never key: the host keeps its key window, keyboard and first
/// responder (IAM-36). A touch that lands on the window or on the root view (outside a bar) falls through to the
/// app; `center` and `full` cover the window with their overlay, so they block it.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppWindow: UIWindow {

    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === rootViewController?.view { return nil }
        return hit
    }
}

/// What a window shows: the overlay (`NottiInAppBarLayout` or `NottiInAppCardLayout`), a callback after each
/// layout pass, and the escape-gesture handler.
@available(iOSApplicationExtension, unavailable)
struct NottiInAppWindowContent {
    let overlay: UIView
    let onLayout: () -> Void
    /// The accessibility escape gesture: true when handled (`center`, `full`).
    let onEscape: () -> Bool
}

/// One shown display window. Tests inject a fake (no real window in presenter tests).
@available(iOSApplicationExtension, unavailable)
protocol NottiInAppWindowHosting: AnyObject {
    func show(_ content: NottiInAppWindowContent)
    func hide()
    /// The scene the window lives in, nil for a scene-less window; matched against `UIScene.didDisconnectNotification`.
    var sceneKey: AnyObject? { get }
}

/// Production window host (RN `NottiInAppWindowHost`, `NottiInAppPresenter.swift:111-147`).
@available(iOSApplicationExtension, unavailable)
final class NottiInAppWindowHost: NottiInAppWindowHosting {

    private let target: NottiInAppWindowTarget
    private let hostController: (NottiInAppWindowTarget) -> UIViewController?
    private(set) var window: NottiInAppWindow?

    /// `hostController` finds the host view controller whose orientations and status bar the window follows.
    init(
        target: NottiInAppWindowTarget,
        hostController: @escaping (NottiInAppWindowTarget) -> UIViewController? = NottiInAppWindowHost.keyRootController
    ) {
        self.target = target
        self.hostController = hostController
    }

    /// The scene of the target, held strongly here: `UIWindow.windowScene` is weak and UIKit may clear it before
    /// it posts `UIScene.didDisconnectNotification` (PRF-09).
    var sceneKey: AnyObject? {
        switch target {
        case .scene(let scene):
            return scene
        case .screen:
            return nil
        }
    }

    func show(_ content: NottiInAppWindowContent) {
        let window: NottiInAppWindow
        switch target {
        case .scene(let scene):
            window = NottiInAppWindow(windowScene: scene)
        case .screen(let bounds):
            window = NottiInAppWindow(frame: bounds)
        }
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.rootViewController = NottiInAppViewController(content: content, host: hostController(target))
        // Shown without makeKey (canBecomeKey is false as well).
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// The root view controller of the host's key window in the scene, or of the app delegate's window for a
    /// scene-less app.
    static func keyRootController(_ target: NottiInAppWindowTarget) -> UIViewController? {
        switch target {
        case .scene(let scene):
            return scene.windows.first { $0.isKeyWindow }?.rootViewController
        case .screen:
            return UIApplication.shared.delegate?.window??.rootViewController
        }
    }
}
