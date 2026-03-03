import AppKit
import SwiftUI

// MARK: - Centering Clip View

/// An `NSClipView` subclass that centres the document view when its
/// magnified size is smaller than the visible area.
final class CenteringClipView: NSClipView {

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return constrained }

        let docFrame = docView.frame

        // If the document is narrower than the visible area, centre horizontally.
        if docFrame.width < constrained.width {
            constrained.origin.x = (docFrame.width - constrained.width) / 2
        }

        // If the document is shorter than the visible area, centre vertically.
        if docFrame.height < constrained.height {
            constrained.origin.y = (docFrame.height - constrained.height) / 2
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

    // MARK: - State

    private weak var magnifiedScrollView: NSScrollView?
    private var magnificationObservation: NSKeyValueObservation?
    private var didApplyInitial = false

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollViewIfNeeded()
    }

    override func layout() {
        super.layout()
        configureScrollViewIfNeeded()
    }

    private func configureScrollViewIfNeeded() {
        guard magnifiedScrollView == nil else { return }
        guard let sv = findParentScrollView() else { return }

        // Replace the clip view with a centering one so content is centred
        // when zoomed out smaller than the viewport.
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

        magnifiedScrollView = sv

        // Observe magnification changes to report zoom percentage.
        magnificationObservation = sv.observe(\.magnification, options: [.new]) { [weak self] scrollView, _ in
            self?.onMagnificationChanged?(scrollView.magnification)
        }

        // Apply the initial magnification (fit-to-window for large captures).
        if !didApplyInitial {
            didApplyInitial = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let sv = self.magnifiedScrollView else { return }
                sv.magnification = self.initialMagnification
                self.onMagnificationChanged?(self.initialMagnification)
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

        // Zoom toward the cursor position.
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

    func zoomToFit() {
        guard let sv = magnifiedScrollView else { return }
        let contentSize = sv.documentView?.frame.size ?? .zero
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let visibleSize = sv.contentView.bounds.size
        // Account for current magnification when computing the unmagnified content size.
        let unmagnifiedWidth = contentSize.width / sv.magnification
        let unmagnifiedHeight = contentSize.height / sv.magnification
        let fitScale = min(
            visibleSize.width / unmagnifiedWidth,
            visibleSize.height / unmagnifiedHeight
        )
        let clampedScale = fitScale.clamped(to: minMagnification...maxMagnification)
        animateZoom(to: clampedScale)
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
    let onMagnificationChanged: (CGFloat) -> Void
    /// Gives the parent a handle to perform zoom actions.
    let onHostReady: (MagnificationHostView) -> Void

    func makeNSView(context: Context) -> MagnificationHostView {
        let view = MagnificationHostView()
        view.initialMagnification = initialMagnification
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
