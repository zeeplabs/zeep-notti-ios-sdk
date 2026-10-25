import UIKit
import XCTest
@testable import NottiSDK

/// T15: the `top` and `bottom` overlays (IAM-13, IAM-15 thumbnail, IAM-18, IAM-19, IAM-21 margin), laid out at fixed
/// sizes with injected safe areas. The RN 0.8.0 metrics (16 pt margin, 40% cap, 56 pt thumbnail, min(h/3, 44) swipe)
/// are literals.
final class NottiInAppBarLayoutTests: XCTestCase {

    private typealias Fix = InAppViewFixtures

    private let portrait = CGSize(width: 390, height: 844)
    private let landscape = CGSize(width: 844, height: 390)
    private let notch = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    private let sideNotch = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)

    private func bar(
        _ message: NottiInAppMessage,
        image: UIImage? = nil,
        traits: UITraitCollection = Fix.regular,
        size: CGSize,
        safe: UIEdgeInsets
    ) -> NottiInAppBarLayout {
        let overlay = Fix.hosted(NottiInAppBarLayout(messageView: Fix.view(message, image: image, traits: traits)))
        overlay.interaction.reduceMotion = { true }
        layout(overlay, size: size, safe: safe)
        return overlay
    }

    private func layout(_ overlay: NottiInAppBarLayout, size: CGSize, safe: UIEdgeInsets) {
        overlay.safeAreaOverride = safe
        overlay.frame = CGRect(origin: .zero, size: size)
        overlay.layoutIfNeeded()
        overlay.messageView.layoutIfNeeded()
        overlay.messageView.buttonRow?.layoutIfNeeded()
    }

    private func outcomes(of overlay: NottiInAppBarLayout) -> () -> [NottiInAppViewOutcome] {
        var recorded: [NottiInAppViewOutcome] = []
        overlay.messageView.onOutcome = { recorded.append($0) }
        return { recorded }
    }

    // MARK: Placement (IAM-13, IAM-21)

    func test_portraitBarsSit16FromTheSafeAreaEdgeAndCapTheirHeight() {
        let long = Fix.message(.top, body: Fix.body500)
        let top = bar(long, traits: Fix.largest, size: portrait, safe: notch).messageView.frame
        XCTAssertEqual(top.minY, 59 + 16)
        XCTAssertEqual(top.minX, 16)
        XCTAssertEqual(top.maxX, 390 - 16)
        XCTAssertLessThanOrEqual(top.height, min(844 * 0.4, 844 - 59 - 34 - 32) + 0.5)
        XCTAssertGreaterThan(top.height, 300, "the long body fills the cap")

        let bottom = bar(Fix.message(.bottom, body: Fix.body500), traits: Fix.largest, size: portrait, safe: notch)
        XCTAssertEqual(bottom.messageView.frame.maxY, 844 - 34 - 16)
        XCTAssertEqual(bottom.messageView.frame.minX, 16)
        XCTAssertLessThanOrEqual(bottom.messageView.frame.height, 337.6 + 0.5)
    }

    func test_landscapeBarsKeepClearOfTheSideInsetsAndCapAt40Percent() {
        for format in [NottiInAppFormat.top, .bottom] {
            let overlay = bar(Fix.message(format, body: Fix.body500), traits: Fix.largest, size: landscape, safe: sideNotch)
            let frame = overlay.messageView.frame
            XCTAssertEqual(frame.minX, 59 + 16, "\(format)")
            XCTAssertEqual(frame.maxX, 844 - 59 - 16, "\(format)")
            XCTAssertLessThanOrEqual(frame.height, min(390 * 0.4, 390 - 21 - 32) + 0.5, "\(format)")
            if format == .top {
                XCTAssertEqual(frame.minY, 16)
            } else {
                XCTAssertEqual(frame.maxY, 390 - 21 - 16)
            }
        }
    }

    func test_marginFalseTouchesTheSafeAreaEdgesInBothOrientations() {
        let noMargin: [String: Any] = ["margin": false]
        let top = bar(Fix.message(.top, style: noMargin), size: portrait, safe: notch).messageView.frame
        XCTAssertEqual([top.minX, top.minY, top.maxX], [0, 59, 390])
        let bottom = bar(Fix.message(.bottom, style: noMargin), size: portrait, safe: notch).messageView.frame
        XCTAssertEqual(bottom.maxY, 844 - 34)
        let wide = bar(Fix.message(.top, style: noMargin), size: landscape, safe: sideNotch).messageView.frame
        XCTAssertEqual([wide.minX, wide.minY, wide.maxX], [59, 0, 844 - 59])
        let wideBottom = bar(Fix.message(.bottom, style: noMargin), size: landscape, safe: sideNotch).messageView.frame
        XCTAssertEqual([wideBottom.minX, wideBottom.maxX, wideBottom.maxY], [59, 844 - 59, 390 - 21])
    }

    func test_marginTrueAndAbsentGiveTheSameFrame() {
        let absent = bar(Fix.message(.bottom), size: landscape, safe: sideNotch).messageView.frame
        let explicit = bar(Fix.message(.bottom, style: ["margin": true]), size: landscape, safe: sideNotch).messageView.frame
        XCTAssertEqual(absent, explicit)
        XCTAssertEqual(absent.minX, 75)
    }

    // MARK: Thumbnail (IAM-15)

    func test_theThumbnailIs56AtTheLeadingEdgeAndTrailingUnderRightToLeft() throws {
        let overlay = bar(Fix.message(.top), image: Fix.picture(), size: portrait, safe: notch)
        let card = overlay.messageView
        let image = try XCTUnwrap(card.imageView)
        XCTAssertEqual(image.frame.size, CGSize(width: 56, height: 56))
        XCTAssertEqual(image.convert(image.bounds, to: card).minX, 16)
        XCTAssertLessThanOrEqual(image.frame.maxX + 12, card.textBlock.frame.minX + 0.5)
        XCTAssertEqual(image.contentMode, .scaleAspectFill)

        let rtl = bar(Fix.message(.bottom), image: Fix.picture(), size: portrait, safe: notch)
        rtl.messageView.semanticContentAttribute = .forceRightToLeft
        layout(rtl, size: portrait, safe: notch)
        let rtlImage = try XCTUnwrap(rtl.messageView.imageView)
        XCTAssertEqual(rtlImage.frame.size, CGSize(width: 56, height: 56))
        XCTAssertEqual(rtl.messageView.bounds.width - rtlImage.convert(rtlImage.bounds, to: rtl.messageView).maxX, 16)
        XCTAssertLessThanOrEqual(rtl.messageView.textBlock.frame.maxX, rtlImage.frame.minX - 12 + 0.5)
    }

    // MARK: Swipe (IAM-13)

    func test_topDismissesAtTheThresholdAndSnapsBackShortOfIt() {
        let overlay = bar(Fix.message(.top), size: portrait, safe: notch)
        let recorded = outcomes(of: overlay)
        let card = overlay.messageView
        card.bounds = CGRect(x: 0, y: 0, width: 358, height: 300)
        XCTAssertEqual(overlay.interaction.swipeThreshold, 44)
        overlay.interaction.panChanged(-43)
        XCTAssertEqual(card.transform.ty, -43)
        overlay.interaction.panEnded(-43)
        XCTAssertEqual(card.transform, .identity)
        XCTAssertTrue(recorded().isEmpty)
        overlay.interaction.panChanged(60)
        XCTAssertEqual(card.transform.ty, 0, "a downward drag does not move a top bar")
        overlay.interaction.panEnded(60)
        XCTAssertTrue(recorded().isEmpty)
        overlay.interaction.panEnded(-44)
        XCTAssertEqual(recorded(), [.dismiss(reason: "swipe")])
    }

    func test_aShortBarDismissesAtOneThirdOfItsHeight() {
        let overlay = bar(Fix.message(.top), size: portrait, safe: notch)
        let recorded = outcomes(of: overlay)
        overlay.messageView.bounds = CGRect(x: 0, y: 0, width: 358, height: 60)
        XCTAssertEqual(overlay.interaction.swipeThreshold, 20, accuracy: 0.001)
        overlay.interaction.panEnded(-19)
        XCTAssertTrue(recorded().isEmpty)
        overlay.interaction.panEnded(-20)
        XCTAssertEqual(recorded(), [.dismiss(reason: "swipe")])
    }

    func test_bottomIsTheMirror() {
        let overlay = bar(Fix.message(.bottom), size: portrait, safe: notch)
        let recorded = outcomes(of: overlay)
        overlay.messageView.bounds = CGRect(x: 0, y: 0, width: 358, height: 300)
        overlay.interaction.panChanged(-80)
        XCTAssertEqual(overlay.messageView.transform.ty, 0)
        overlay.interaction.panEnded(-80)
        overlay.interaction.panEnded(43)
        XCTAssertTrue(recorded().isEmpty)
        overlay.interaction.panChanged(44)
        XCTAssertEqual(overlay.messageView.transform.ty, 44)
        overlay.interaction.panEnded(44)
        XCTAssertEqual(recorded(), [.dismiss(reason: "swipe")])
    }

    func test_onlyAMostlyVerticalDragInTheDismissDirectionBegins() {
        let top = bar(Fix.message(.top), size: portrait, safe: notch).interaction
        XCTAssertTrue(top.startsSwipe(horizontal: 5, vertical: -50))
        XCTAssertFalse(top.startsSwipe(horizontal: 60, vertical: -50))
        XCTAssertFalse(top.startsSwipe(horizontal: 0, vertical: 50))
        let bottom = bar(Fix.message(.bottom), size: portrait, safe: notch).interaction
        XCTAssertTrue(bottom.startsSwipe(horizontal: -5, vertical: 50))
        XCTAssertFalse(bottom.startsSwipe(horizontal: 0, vertical: -50))
    }

    func test_aPanDoesNotBeginWhileTheTextCanStillScrollThatWay() {
        let bottom = bar(Fix.message(.bottom, body: Fix.body500), traits: Fix.largest, size: portrait, safe: notch)
        let scroll = bottom.messageView.scroll
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertTrue(bottom.interaction.startsSwipe(horizontal: 0, vertical: 50))
        scroll.contentOffset = CGPoint(x: 0, y: 40)
        XCTAssertFalse(bottom.interaction.startsSwipe(horizontal: 0, vertical: 50))

        let top = bar(Fix.message(.top, body: Fix.body500), traits: Fix.largest, size: portrait, safe: notch)
        XCTAssertFalse(top.interaction.startsSwipe(horizontal: 0, vertical: -50))
        let topScroll = top.messageView.scroll
        topScroll.contentOffset = CGPoint(x: 0, y: topScroll.contentSize.height - topScroll.bounds.height)
        XCTAssertTrue(top.interaction.startsSwipe(horizontal: 0, vertical: -50))
    }

    func test_thePanLivesOnTheCardAndTheTextScrollWaitsForIt() {
        for format in [NottiInAppFormat.top, .bottom] {
            let overlay = bar(Fix.message(format), size: portrait, safe: notch)
            XCTAssertTrue(overlay.interaction.pan?.view === overlay.messageView, "\(format)")
            XCTAssertTrue(overlay.interaction.pan?.delegate === overlay.interaction, "\(format)")
        }
    }

    func test_snapBackAnimatesUnlessReduceMotion() {
        let overlay = bar(Fix.message(.top), size: portrait, safe: notch)
        var animations: [TimeInterval] = []
        overlay.interaction.animate = { duration, changes in animations.append(duration); changes() }
        overlay.interaction.reduceMotion = { false }
        overlay.interaction.panChanged(-10)
        overlay.interaction.panEnded(-10)
        XCTAssertEqual(animations, [0.2])
        overlay.interaction.reduceMotion = { true }
        overlay.interaction.panChanged(-10)
        overlay.interaction.settle()
        XCTAssertEqual(animations, [0.2], "no animation under Reduce Motion")
        XCTAssertEqual(overlay.messageView.transform, .identity)
    }

    func test_theCloseControlYieldsCloseButton() {
        for format in [NottiInAppFormat.top, .bottom] {
            let overlay = bar(Fix.message(format, buttons: [Fix.button("a", "A")]), size: portrait, safe: notch)
            let recorded = outcomes(of: overlay)
            overlay.messageView.closeButton.sendActions(for: .touchUpInside)
            overlay.interaction.panEnded(200 * overlay.interaction.dismissDirection)
            overlay.interaction.handleBodyTap()
            XCTAssertEqual(recorded(), [.dismiss(reason: "close_button")], "\(format)")
        }
    }

    // MARK: Body tap (IAM-19)

    func test_aBodyTapActsAsTheFirstButton() {
        let buttons = [Fix.button("allow", "Allow", .pushPermission), Fix.button("later", "Later")]
        let overlay = bar(Fix.message(.top, buttons: buttons), size: portrait, safe: notch)
        let recorded = outcomes(of: overlay)
        XCTAssertTrue(overlay.interaction.bodyTap?.view === overlay.messageView)
        overlay.interaction.handleBodyTap()
        XCTAssertEqual(recorded(), [.tap(buttonId: "allow", action: .pushPermission)])
    }

    func test_withNoButtonsThereIsNoBodyRecognizer() {
        let overlay = bar(Fix.message(.bottom), size: portrait, safe: notch)
        XCTAssertNil(overlay.interaction.bodyTap)
        XCTAssertEqual(overlay.messageView.gestureRecognizers?.count, 1, "the pan only")
    }

    func test_aTapOnAButtonTheCloseOrATappableImageIsNotABodyTap() throws {
        let action = NottiInAppLinkAction(type: .url, value: "https://example.invalid/promo")
        let message = Fix.message(.top, buttons: [Fix.button("a", "A"), Fix.button("b", "B")], imageAction: action)
        let overlay = bar(message, image: Fix.picture(), size: portrait, safe: notch)
        let card = overlay.messageView
        let interaction = overlay.interaction
        func center(_ view: UIView) -> CGPoint {
            let rect = view.convert(view.bounds, to: card)
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        XCTAssertFalse(interaction.bodyTapAccepts(center(card.closeButton)))
        for button in card.buttons { XCTAssertFalse(interaction.bodyTapAccepts(center(button))) }
        XCTAssertFalse(interaction.bodyTapAccepts(center(try XCTUnwrap(card.imageView))))
        XCTAssertTrue(interaction.bodyTapAccepts(center(card.bodyLabel)))

        let recorded = outcomes(of: overlay)
        card.buttons[1].sendActions(for: .touchUpInside)
        interaction.handleBodyTap()
        XCTAssertEqual(recorded(), [.tap(buttonId: "b", action: nil)])
    }

    // MARK: Hit testing and re-layout (IAM-18, IAM-36)

    func test_touchesOutsideTheBarPassThrough() {
        let overlay = bar(Fix.message(.top), size: portrait, safe: notch)
        XCTAssertEqual(overlay.backgroundColor, .clear)
        XCTAssertNil(overlay.hitTest(CGPoint(x: 195, y: 600), with: nil))
        let card = overlay.messageView.frame
        XCTAssertNotNil(overlay.hitTest(CGPoint(x: card.midX, y: card.midY), with: nil))
    }

    func test_reLayoutKeepsOneHierarchyAndReportsNothing() {
        let overlay = bar(Fix.message(.bottom, buttons: [Fix.button("a", "A")]), image: Fix.picture(),
                          size: portrait, safe: notch)
        let recorded = outcomes(of: overlay)
        let card = overlay.messageView
        for (size, safe) in [(landscape, sideNotch), (portrait, notch), (landscape, sideNotch), (portrait, notch)] {
            layout(overlay, size: size, safe: safe)
            XCTAssertEqual(overlay.subviews, [card])
            XCTAssertEqual(card.subviews.filter { $0 === card.closeButton }.count, 1)
            XCTAssertEqual(card.frame.maxY, size.height - safe.bottom - 16)
        }
        XCTAssertTrue(recorded().isEmpty)
        XCTAssertFalse(card.isFinished)
    }
}
