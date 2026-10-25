import UIKit

/// Root of a display window (RN `NottiInAppViewController`, `NottiInAppPresenter.swift:63-109`): a clear container
/// holding the overlay, which it sizes to the window on every layout pass. It never changes the host's orientation
/// or status bar: it reports the host key window's root view controller values (IAM-18). It is in the overlay's
/// responder chain, so it also receives the accessibility escape gesture (IAM-38).
@available(iOSApplicationExtension, unavailable)
final class NottiInAppViewController: UIViewController {

    let content: NottiInAppWindowContent
    /// The host's key-window controller, followed for orientation and status bar.
    private weak var host: UIViewController?

    init(content: NottiInAppWindowContent, host: UIViewController?) {
        self.content = content
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = .clear
        container.addSubview(content.overlay)
        view = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        content.overlay.frame = view.bounds
        content.overlay.layoutIfNeeded()
        content.onLayout()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        host?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        host?.preferredStatusBarStyle ?? super.preferredStatusBarStyle
    }

    override var prefersStatusBarHidden: Bool {
        host?.prefersStatusBarHidden ?? super.prefersStatusBarHidden
    }

    /// VoiceOver's escape gesture acts as the close control on `center` and `full`; bars do not handle it.
    override func accessibilityPerformEscape() -> Bool {
        content.onEscape()
    }
}
