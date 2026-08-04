import Dependencies
import ScrollActivityClient
import SwiftUI
import SwiftUIIntrospect
import UIKit
import os.log

private let logger = Logger(subsystem: "ScrollActivityClientLive", category: "ScrollStopObserver")

/// Bridges a `UIScrollView`'s motion into Swift via KVO on `contentOffset`,
/// without touching the scroll view's delegate. Reports edges only — `onMove`
/// once when motion starts, `onStop` once when the view has settled.
@MainActor
final class ScrollStopObserver {
    private weak var scrollView: UIScrollView?
    private var token: NSKeyValueObservation?
    private var settleLoop: Task<Void, Never>?
    private var lastMovement = ContinuousClock.now
    private var isMoving = false

    /// Which direction this surface scrolls. Position/scroll-to-top read the
    /// offset and inset along this axis; set it before `attach`. Phase tracking
    /// is axis-agnostic and ignores it.
    var axis: ScrollActivityClient.Axis = .vertical

    /// How long `contentOffset` must stay quiet (with no active gesture/momentum)
    /// before the list is considered at rest.
    private let settleDelay = Duration.milliseconds(120)
    /// How often the settle loop re-checks while a gesture is in flight.
    private let pollInterval = Duration.milliseconds(60)

    var onMove: (() -> Void)?
    var onStop: (() -> Void)?
    /// Fires with the new value whenever the surface crosses its top edge —
    /// `true` when it reaches the top, `false` when it leaves it. Unlike
    /// `onMove`/`onStop`, this tracks *any* offset change (including
    /// programmatic and momentum), so position stays accurate at rest.
    var onTopChange: ((Bool) -> Void)?
    private var wasAtTop = true

    /// Delay after an animated scroll-to-top before re-checking whether it
    /// actually reached the top — just past UIScrollView's ~0.3s programmatic
    /// scroll animation.
    private let scrollToTopReassertDelay = Duration.milliseconds(400)
    /// Hard cap on automatic re-asserts so a perpetually-shifting estimate can
    /// never loop forever.
    private let maxScrollToTopReasserts = 3

    func attach(to scrollView: UIScrollView) {
        // SwiftUIIntrospect's customize closure can fire repeatedly — wire KVO up
        // once per scroll view instance.
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        wasAtTop = isAtStart(scrollView)
        token = scrollView.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleOffsetChange(scrollView)
            }
        }
    }

    /// Scrolls the tracked view back to its top edge, animated. No-op if the
    /// scroll view has gone away.
    func scrollToTop() {
        reassertTop(attempt: 0)
    }

    /// Animates to the top edge, then re-asserts the target after the animation
    /// settles if it landed short. SwiftUI `List` is backed by a self-sizing
    /// collection view with *estimated* row heights, so off-screen rows above the
    /// viewport resolve their real heights mid-animation and the content size
    /// shifts — a single fire-once `setContentOffset` can stop below the true top
    /// (the user then has to tap a second time). Re-issuing once the animation
    /// finishes lets the estimate converge so a single tap reaches the top. Bounded
    /// by `maxScrollToTopReasserts`, and never fights an in-flight user gesture.
    private func reassertTop(attempt: Int) {
        guard let scrollView else { return }
        scrollView.setContentOffset(startOffset(scrollView), animated: true)
        guard attempt < maxScrollToTopReasserts else { return }
        let delay = scrollToTopReassertDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                let scrollView = self.scrollView,
                !scrollView.isDragging,
                !scrollView.isTracking,
                !self.isAtStart(scrollView)
            else {
                return
            }
            self.reassertTop(attempt: attempt + 1)
        }
    }

    /// The scroll offset along the tracked axis (`.y` for vertical, `.x` for
    /// horizontal); the cross-axis component is left untouched.
    private func axisOffset(_ scrollView: UIScrollView) -> CGFloat {
        switch axis {
        case .vertical: scrollView.contentOffset.y
        case .horizontal: scrollView.contentOffset.x
        }
    }

    /// The content inset at the start edge along the tracked axis (`.top` for
    /// vertical, `.left` for horizontal).
    private func startInset(_ scrollView: UIScrollView) -> CGFloat {
        switch axis {
        case .vertical: scrollView.adjustedContentInset.top
        case .horizontal: scrollView.adjustedContentInset.left
        }
    }

    /// The resting content offset that pins the tracked axis to its start edge
    /// while preserving the cross-axis position.
    private func startOffset(_ scrollView: UIScrollView) -> CGPoint {
        let start = -startInset(scrollView)
        switch axis {
        case .vertical: return CGPoint(x: scrollView.contentOffset.x, y: start)
        case .horizontal: return CGPoint(x: start, y: scrollView.contentOffset.y)
        }
    }

    private func isAtStart(_ scrollView: UIScrollView) -> Bool {
        // 1pt tolerance absorbs sub-point rounding in the resting offset.
        axisOffset(scrollView) <= -startInset(scrollView) + 1
    }

    /// Cancels the settle poll loop and tears down KVO. Idempotent.
    func detach() {
        settleLoop?.cancel()
        settleLoop = nil
        token?.invalidate()
        token = nil
        scrollView = nil
        isMoving = false
        wasAtTop = true
    }

    private func handleOffsetChange(_ scrollView: UIScrollView) {
        // Position tracks every offset change (programmatic, momentum, gesture),
        // so the at-start edge stays accurate even when the view is not "scrolling".
        let atTop = isAtStart(scrollView)
        if atTop != wasAtTop {
            wasAtTop = atTop
            onTopChange?(atTop)
        }

        // Only a real user gesture (touch / drag / momentum) counts as scrolling;
        // a change with every flag clear is a programmatic/layout-driven shift.
        guard scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating else {
            return
        }
        lastMovement = .now
        if !isMoving {
            isMoving = true
            logger.debug("▶ started moving (y=\(Int(scrollView.contentOffset.y), privacy: .public))")
            onMove?()
        }
        if settleLoop == nil {
            startSettleLoop(scrollView)
        }
    }

    private func startSettleLoop(_ scrollView: UIScrollView) {
        let poll = pollInterval
        let settle = settleDelay
        settleLoop = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: poll)
                guard !Task.isCancelled, let self else { return }
                let quietFor = ContinuousClock.now - self.lastMovement
                let active = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
                if quietFor >= settle, !active {
                    self.isMoving = false
                    self.settleLoop = nil
                    logger.debug("⏹ stopped — at rest (y=\(Int(scrollView.contentOffset.y), privacy: .public))")
                    self.onStop?()
                    return
                }
            }
        }
    }
}

/// Which SwiftUI scrolling container backs the tracked view — SwiftUIIntrospect
/// resolves each through a different selector.
public enum ScrollContainerKind: Sendable {
    case list
    case scrollView
}

extension View {
    /// Observes the underlying `List`/`ScrollView` and reports its phase to the
    /// `ScrollActivityClient` under `scope`. Pass `axis: .horizontal` for a
    /// sideways-scrolling surface so position and scroll-to-top track the
    /// leading edge instead of the top.
    public func trackScrollActivity(
        _ container: ScrollContainerKind = .list,
        scope: ScrollActivityClient.Scope,
        axis: ScrollActivityClient.Axis = .vertical
    ) -> some View {
        modifier(
            ScrollActivityModifier(container: container, scope: scope, axis: axis, onStop: nil)
        )
    }

    /// Like `trackScrollActivity(_:scope:axis:)`, plus fires `action` each time
    /// the container comes fully to rest.
    public func onScrollStopped(
        _ container: ScrollContainerKind = .list,
        scope: ScrollActivityClient.Scope,
        axis: ScrollActivityClient.Axis = .vertical,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            ScrollActivityModifier(container: container, scope: scope, axis: axis, onStop: action)
        )
    }
}

private struct ScrollActivityModifier: ViewModifier {
    var container: ScrollContainerKind
    var scope: ScrollActivityClient.Scope
    var axis: ScrollActivityClient.Axis
    var onStop: (() -> Void)?

    @Dependency(\.scrollActivity) private var scrollActivity
    @State private var observer = ScrollStopObserver()

    func body(content: Content) -> some View {
        Group {
            switch container {
                case .list:
                    content.introspect(.list, on: .iOS(.v17, .v18, .v26), customize: attach)
                case .scrollView:
                    content.introspect(.scrollView, on: .iOS(.v17, .v18, .v26), customize: attach)
            }
        }
        .onDisappear { observer.detach() }
        .task {
            // Perform scroll-to-top (and any future) commands targeting this scope.
            for await command in await scrollActivity.commands(scope) {
                switch command {
                    case .scrollToTop:
                        observer.scrollToTop()
                }
            }
        }
    }

    private func attach(_ scrollView: UIScrollView) {
        let client = scrollActivity
        let scope = scope
        observer.axis = axis
        observer.onMove = { Task { await client.report(scope, .scrolling) } }
        observer.onStop = {
            Task { await client.report(scope, .idle) }
            onStop?()
        }
        observer.onTopChange = { atTop in
            Task { await client.reportPosition(scope, atTop ? .atTop : .scrolled) }
        }
        observer.attach(to: scrollView)
    }
}
