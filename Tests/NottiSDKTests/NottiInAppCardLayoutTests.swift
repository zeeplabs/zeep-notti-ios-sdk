import UIKit
import XCTest
@testable import NottiSDK

/// T16: the `center` and `full` overlays (IAM-13, IAM-15 image, IAM-17, IAM-18, IAM-21 margin), laid out at fixed
/// sizes with injected safe areas. The RN 0.8.0 metrics (90%, 560 pt, 90% of the safe height, 0.5 backdrop, 180 pt
/// image cap, 16 pt margin) are literals.
final class NottiInAppCardLayoutTests: XCTestCase {

    private typealias Fix = InAppViewFixtures

    private let portrait = CGSize(width: 390, height: 844)
    private let landscape = CGSize(width: 844, height: 390)
    private let notch = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    private let sideNotch = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)

    private func overlay(
        _ message: NottiInAppMessage,
        image: UIImage? = nil,
        traits: UITraitCollection = Fix.regular,
        size: CGSize,
        safe: UIEdgeInsets
    ) -> NottiInAppCardLayout {
        let view = Fix.hosted(NottiInAppCardLayout(messageView: Fix.view(message, image: image, traits: traits)))
        layout(view, size: size, safe: safe)
        return view
    }

    private func layout(_ view: NottiInAppCardLayout, size: CGSize, safe: UIEdgeInsets) {
        view.safeAreaOverride = safe
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        view.messageView.layoutIfNeeded()
        view.messageView.buttonRow?.layoutIfNeeded()
    }

    private func outcomes(of view: NottiInAppCardLayout) -> () -> [NottiInAppViewOutcome] {
        var recorded: [NottiInAppViewOutcome] = []
        view.messageView.onOutcome = { recorded.append($0) }
        return { recorded }
    }

    // MARK: center (IAM-13)

    func test_centerIs90PercentWideOnAPhone() {
        let card = overlay(Fix.message(.center), size: portrait, safe: notch).messageView.frame
        XCTAssertEqual(card.width, 351)
        XCTAssertEqual(card.midX, 195, accuracy: 0.001)
    }

    func test_centerIsCappedAt560OnAnIPad() {
        let card = overlay(Fix.message(.center), size: CGSize(width: 1024, height: 1366), safe: .zero).messageView.frame
        XCTAssertEqual(card.width, 560)
        XCTAssertEqual(card.midX, 512, accuracy: 0.001)
    }

    func test_centerIsNeverWiderThanTheSafeWidthInLandscape() {
        let card = overlay(Fix.message(.center), size: landscape, safe: sideNotch).messageView.frame
        XCTAssertEqual(card.width, 560)
        XCTAssertGreaterThanOrEqual(card.minX, 59)
        let narrow = UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)
        let small = overlay(Fix.message(.center), size: CGSize(width: 568, height: 320), safe: narrow).messageView.frame
        XCTAssertEqual(small.width, 568 - 88)
        XCTAssertEqual(small.minX, 44)
    }

    func test_centerIsCenteredInAnAsymmetricSafeArea() {
        let asymmetric = UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0)
        let card = overlay(Fix.message(.center), size: portrait, safe: asymmetric).messageView.frame
        XCTAssertEqual(card.midY, 59 + (844 - 59) / 2, accuracy: 1)
        let side = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
        let wide = overlay(Fix.message(.center), size: landscape, safe: side).messageView.frame
        XCTAssertEqual(wide.midX, 59 + (844 - 59) / 2, accuracy: 0.001)
        XCTAssertEqual(wide.midY, (390 - 21) / 2, accuracy: 1)
    }

    func test_centerHeightNeverExceeds90PercentOfTheSafeHeight() {
        for (size, safe) in [(portrait, notch), (landscape, sideNotch)] {
            let view = overlay(
                Fix.message(.center, body: Fix.body500, buttons: [Fix.button("a", "A")]),
                traits: Fix.largest, size: size, safe: safe
            )
            let safeHeight = size.height - safe.top - safe.bottom
            XCTAssertLessThanOrEqual(view.messageView.frame.height, safeHeight * 0.9 + 0.001, "\(size)")
            XCTAssertGreaterThan(view.messageView.scroll.contentSize.height, view.messageView.scroll.bounds.height)
        }
    }

    func test_centerHasAHalfBlackBackdropAndIgnoresMargin() throws {
        let view = overlay(Fix.message(.center), size: portrait, safe: notch)
        var white: CGFloat = 1
        var alpha: CGFloat = 0
        XCTAssertTrue(try XCTUnwrap(view.backgroundColor).getWhite(&white, alpha: &alpha))
        XCTAssertEqual(white, 0)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(view.accessibilityIdentifier, "notti.inapp.backdrop")
        let bare = overlay(Fix.message(.center, style: ["margin": false]), size: portrait, safe: notch)
        XCTAssertEqual(bare.messageView.frame, view.messageView.frame)
        XCTAssertEqual(bare.messageView.layer.cornerRadius, 12)
    }

    func test_anOutsideTapYieldsOutsideTapAndATapInsideTheCardNothing() {
        let view = overlay(Fix.message(.center), size: portrait, safe: notch)
        let recorded = outcomes(of: view)
        XCTAssertTrue(view.backdropTap?.view === view)
        XCTAssertTrue(view.backdropTap?.delegate === view)
        let card = view.messageView.frame
        XCTAssertFalse(view.backdropAccepts(CGPoint(x: card.midX, y: card.midY)))
        XCTAssertTrue(view.backdropAccepts(CGPoint(x: 4, y: 4)))
        XCTAssertTrue(recorded().isEmpty)
        view.handleBackdropTap()
        view.handleBackdropTap()
        XCTAssertEqual(recorded(), [.dismiss(reason: "outside_tap")])
    }

    // MARK: center image (IAM-15)

    func test_aWideImageFillsTheInnerWidthAtItsAspect() throws {
        let view = overlay(Fix.message(.center), image: Fix.picture(width: 200, height: 100), size: portrait, safe: notch)
        let image = try XCTUnwrap(view.messageView.imageView)
        let inner: CGFloat = 351 - 32
        XCTAssertEqual(image.frame.width, inner)
        XCTAssertEqual(image.frame.height, inner / 2, accuracy: 0.001)
        XCTAssertEqual(image.contentMode, .scaleAspectFill)
        XCTAssertTrue(image.clipsToBounds)
        XCTAssertLessThanOrEqual(image.frame.maxY, view.messageView.textBlock.frame.minY)
    }

    func test_aTallImageIsCappedAt180() throws {
        let view = overlay(Fix.message(.center), image: Fix.picture(width: 100, height: 200), size: portrait, safe: notch)
        let image = try XCTUnwrap(view.messageView.imageView)
        XCTAssertEqual(image.frame.height, 180)
        XCTAssertEqual(image.frame.width, 351 - 32)
        XCTAssertEqual(image.contentMode, .scaleAspectFill)
    }

    // MARK: full (IAM-13, IAM-15, IAM-21)

    func test_fullIsTheSafeAreaInsetByTheMargin() {
        struct Case {
            let size: CGSize
            let safe: UIEdgeInsets
            let style: [String: Any]
            let inset: CGFloat
        }
        let cases = [
            Case(size: portrait, safe: notch, style: [:], inset: 16),
            Case(size: portrait, safe: notch, style: ["margin": true], inset: 16),
            Case(size: portrait, safe: notch, style: ["margin": false], inset: 0),
            Case(size: landscape, safe: sideNotch, style: [:], inset: 16),
            Case(size: landscape, safe: sideNotch, style: ["margin": false], inset: 0)
        ]
        for item in cases {
            let (size, safe, style) = (item.size, item.safe, item.style)
            let card = overlay(Fix.message(.full, style: style), size: size, safe: safe).messageView.frame
            let expected = CGRect(origin: .zero, size: size).inset(by: safe).insetBy(dx: item.inset, dy: item.inset)
            XCTAssertEqual(card, expected, "\(size) \(style)")
        }
    }

    func test_fullCornerRadiusIsZeroOnlyWithoutMargin() {
        XCTAssertEqual(overlay(Fix.message(.full), size: portrait, safe: notch).messageView.layer.cornerRadius, 12)
        let bare = overlay(Fix.message(.full, style: ["margin": false]), size: portrait, safe: notch)
        XCTAssertEqual(bare.messageView.layer.cornerRadius, 0)
    }

    func test_fullImageIsContainedAndTakesTheFreeRoom() throws {
        let view = overlay(Fix.message(.full), image: Fix.picture(width: 200, height: 100), size: portrait, safe: notch)
        let image = try XCTUnwrap(view.messageView.imageView)
        let natural = (358 - 32) / 2 as CGFloat
        XCTAssertEqual(image.contentMode, .scaleAspectFit)
        XCTAssertGreaterThan(image.frame.height, natural + 100)
        XCTAssertEqual(image.frame.width, 358 - 32)
        XCTAssertLessThanOrEqual(image.frame.maxY + 12, view.messageView.textBlock.frame.minY + 0.5)
    }

    func test_fullPinsTheButtonsToTheBottomWhileALongBodyScrolls() throws {
        let view = overlay(
            Fix.message(.full, body: Fix.body500, buttons: [Fix.button("a", "A"), Fix.button("b", "B")]),
            traits: Fix.largest, size: portrait, safe: notch
        )
        let card = view.messageView
        let row = try XCTUnwrap(card.buttonRow)
        XCTAssertFalse(card.buttonsScroll)
        XCTAssertTrue(row.superview === card)
        XCTAssertEqual(row.frame.maxY, card.bounds.height - 16, accuracy: 0.5)
        XCTAssertGreaterThan(card.scroll.contentSize.height, card.scroll.bounds.height)
        XCTAssertEqual(card.scroll.frame.maxY + 12, row.frame.minY, accuracy: 0.5)

        let short = overlay(Fix.message(.full, buttons: [Fix.button("a", "A")]), size: portrait, safe: notch)
        let shortRow = try XCTUnwrap(short.messageView.buttonRow)
        XCTAssertEqual(shortRow.frame.maxY, short.messageView.bounds.height - 16, accuracy: 0.5)
    }

    func test_fullHasNoSwipeAndNoBackdropRecognizer() {
        let view = overlay(Fix.message(.full, buttons: [Fix.button("a", "A")]), size: portrait, safe: notch)
        XCTAssertNil(view.backdropTap)
        XCTAssertTrue(view.gestureRecognizers?.isEmpty ?? true)
        XCTAssertTrue(view.messageView.gestureRecognizers?.isEmpty ?? true)
        XCTAssertEqual(view.backgroundColor, .clear)
    }

    // MARK: Both

    func test_theCloseControlIs44InBothAlsoWithALongBodyAtTheLargestSize() {
        for format in [NottiInAppFormat.center, .full] {
            let view = overlay(Fix.message(format, body: Fix.body500), traits: Fix.largest, size: portrait, safe: notch)
            let close = view.messageView.closeButton
            XCTAssertFalse(close.isHidden, "\(format)")
            XCTAssertTrue(close.superview === view.messageView, "\(format)")
            XCTAssertEqual(close.frame, CGRect(x: view.messageView.bounds.width - 52, y: 8, width: 44, height: 44))
        }
    }

    func test_theBackdropBlocksTouchesInBoth() {
        for format in [NottiInAppFormat.center, .full] {
            let view = overlay(Fix.message(format), size: portrait, safe: notch)
            XCTAssertTrue(view.hitTest(CGPoint(x: 2, y: 2), with: nil) === view, "\(format)")
        }
    }

    func test_reLayoutKeepsOneHierarchyAndReportsNothing() {
        for format in [NottiInAppFormat.center, .full] {
            let view = overlay(Fix.message(format), image: Fix.picture(), size: portrait, safe: notch)
            let recorded = outcomes(of: view)
            for (size, safe) in [(landscape, sideNotch), (portrait, notch), (landscape, sideNotch)] {
                layout(view, size: size, safe: safe)
                XCTAssertEqual(view.subviews, [view.messageView])
            }
            XCTAssertTrue(recorded().isEmpty)
        }
    }
}
