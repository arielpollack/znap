import AppKit
import SwiftUI

// MARK: - Centering Clip View

/// An `NSClipView` subclass that centers the document when it's smaller than the viewport.
final class CenteringClipView: NSClipView {

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView = documentView else { return constrained }

        let docFrame = documentView.frame

        // Center when document fits; otherwise super's result is used as-is.
        if docFrame.width <= proposedBounds.width {
            constrained.origin.x = (docFrame.width - proposedBounds.width) / 2
        }
        if docFrame.height <= proposedBounds.height {
            constrained.origin.y = (docFrame.height - proposedBounds.height) / 2
        }

        return constrained
    }
}

// MARK: - Magnification Host View

/// An `NSView` installed inside a SwiftUI `ScrollView` that locates the
/// enclosing `NSScrollView` and enables built-in magnification (pinch-to-zoom).
///
/// It also intercepts ⌘+scroll-wheel events and translates them into
/// zoom-toward-cursor calls via `NSScrollView.setMagnification(_:centeredAt:)`.
final class MagnificationHostView: NSView {

    // MARK: - Configuration

    var minMagnification: CGFloat = 0.1
    var maxMagnification: CGFloat = 10.0
    var scrollZoomSensitivity: CGFloat = 0.02
    var preciseScrollZoomSensitivity: CGFloat = 0.005

    /// Called whenever the magnification value changes.
    var onMagnificationChanged: ((CGFloat) -> Void)?

    /// The initial magnification to apply once the scroll view is found.
    var initialMagnification: CGFloat = 1.0

    /// The intrinsic content size (image + background), ignoring viewport expansion.
    var contentSizeOverride: CGSize = .zero

    // MARK: - State

    private weak var magnifiedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?
    private var clipFrameObservation: NSKeyValueObservation?
    private var didApplyInitial = false
    /// The document's intrinsic layout size, captured before magnification is applied.
    private var unmagnifiedContentSize: CGSize = .zero

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            configureScrollViewIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        configureScrollViewIfNeeded()
    }

    private func configureScrollViewIfNeeded() {
        guard magnifiedScrollView == nil else { return }
        guard let sv = findParentScrollView() else { return }

        // Replace the clip view with a custom one.
        if !(sv.contentView is CenteringClipView) {
            let oldClipView = sv.contentView
            let docView = sv.documentView
            let centeringClip = CenteringClipView()
            centeringClip.drawsBackground = oldClipView.drawsBackground
            centeringClip.backgroundColor = oldClipView.backgroundColor
            sv.contentView = centeringClip
            if let docView {
                sv.documentView = docView
            }
        }

        sv.allowsMagnification = true
        sv.minMagnification = minMagnification
        sv.maxMagnification = maxMagnification
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsetsZero
        sv.scrollerInsets = NSEdgeInsetsZero

        // Remove any additional content margins (macOS 14+).
        if #available(macOS 14.0, *) {
            sv.contentView.automaticallyAdjustsContentInsets = false
        }

        magnifiedScrollView = sv

        // Observe magnification changes to report zoom percentage.
        magnificationObservation = sv.observe(\.magnification, options: [.new]) { [weak self] scrollView, _ in
            self?.onMagnificationChanged?(scrollView.magnification)
        }

        // Capture the unmagnified content size and apply initial magnification.
        if !didApplyInitial {
            didApplyInitial = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let sv = self.magnifiedScrollView else { return }
                self.unmagnifiedContentSize = self.contentSizeOverride.width > 0
                    ? self.contentSizeOverride
                    : sv.documentView?.frame.size ?? .zero
                sv.magnification = self.initialMagnification
                self.onMagnificationChanged?(self.initialMagnification)

                // // Observe viewport size changes to zoom out when window shrinks.
                // self.clipFrameObservation = sv.contentView.observe(\.frame, options: [.old, .new]) { [weak self] _, change in
                //     guard let self else { return }
                //     guard let oldFrame = change.oldValue, let newFrame = change.newValue,
                //           oldFrame.size != newFrame.size else { return }
                //     self.zoomOutToFitIfNeeded()
                // }
            }
        }
    }

    private func findParentScrollView() -> NSScrollView? {
        var current: NSView? = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    // MARK: - Cmd+Scroll → Zoom

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              let sv = magnifiedScrollView else {
            super.scrollWheel(with: event)
            return
        }

        let sensitivity = event.hasPreciseScrollingDeltas
            ? preciseScrollZoomSensitivity
            : scrollZoomSensitivity
        let delta = event.scrollingDeltaY * sensitivity
        let newMag = (sv.magnification * (1.0 + delta))
            .clamped(to: minMagnification...maxMagnification)

        let cursorInWindow = event.locationInWindow
        let cursorInContent = sv.contentView.convert(cursorInWindow, from: nil)
        sv.setMagnification(newMag, centeredAt: cursorInContent)
    }

    // MARK: - Programmatic Zoom Actions

    func zoomIn() {
        guard let sv = magnifiedScrollView else { return }
        let newMag = (sv.magnification * 1.5).clamped(to: minMagnification...maxMagnification)
        animateZoom(to: newMag)
    }

    func zoomOut() {
        guard let sv = magnifiedScrollView else { return }
        let newMag = (sv.magnification / 1.5).clamped(to: minMagnification...maxMagnification)
        animateZoom(to: newMag)
    }

    func zoomToActualSize() {
        animateZoom(to: 1.0)
    }

    /// Recaptures the unmagnified content size (call after content changes, e.g. background toggle).
    func invalidateContentSize() {
        guard let sv = magnifiedScrollView else { return }
        let docFrame = sv.documentView?.frame.size ?? .zero
        guard docFrame.width > 0, docFrame.height > 0 else { return }
        unmagnifiedContentSize = CGSize(
            width: docFrame.width / sv.magnification,
            height: docFrame.height / sv.magnification
        )
    }

    /// Sets the unmagnified content size directly (use when the new size is known before layout).
    func setContentSize(_ size: CGSize) {
        unmagnifiedContentSize = size
    }

    func zoomToFit() {
        guard let sv = magnifiedScrollView else { return }
        guard unmagnifiedContentSize.width > 0, unmagnifiedContentSize.height > 0 else { return }

        let viewportSize = sv.contentView.frame.size
        let fitScale = min(
            viewportSize.width / unmagnifiedContentSize.width,
            viewportSize.height / unmagnifiedContentSize.height
        )
        sv.contentView.setBoundsOrigin(.zero)
        sv.magnification = fitScale.clamped(to: minMagnification...maxMagnification)
    }

    /// Zooms out (only) when the viewport shrinks below the content size.
    private func zoomOutToFitIfNeeded() {
        guard let sv = magnifiedScrollView else { return }
        guard unmagnifiedContentSize.width > 0, unmagnifiedContentSize.height > 0 else { return }

        let viewport = sv.contentView.frame.size
        let fitScale = min(
            viewport.width / unmagnifiedContentSize.width,
            viewport.height / unmagnifiedContentSize.height
        )
        let clampedScale = fitScale.clamped(to: minMagnification...maxMagnification)

        // Only zoom out, never in.
        guard clampedScale < sv.magnification else { return }
        sv.magnification = clampedScale
    }

    private func animateZoom(to magnification: CGFloat) {
        guard let sv = magnifiedScrollView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sv.animator().magnification = magnification
        }
    }
}

// MARK: - SwiftUI Bridge

/// An `NSViewRepresentable` that installs a ``MagnificationHostView`` inside
/// the SwiftUI view hierarchy.
struct MagnificationHost: NSViewRepresentable {

    let initialMagnification: CGFloat
    let contentSize: CGSize
    let onMagnificationChanged: (CGFloat) -> Void
    /// Gives the parent a handle to perform zoom actions.
    let onHostReady: (MagnificationHostView) -> Void

    func makeNSView(context: Context) -> MagnificationHostView {
        let view = MagnificationHostView()
        view.initialMagnification = initialMagnification
        view.contentSizeOverride = contentSize
        view.onMagnificationChanged = onMagnificationChanged
        onHostReady(view)
        return view
    }

    func updateNSView(_ nsView: MagnificationHostView, context: Context) {
        nsView.onMagnificationChanged = onMagnificationChanged
    }
}

// MARK: - Comparable Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
