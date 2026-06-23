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

    func attach(to scrollView: UIScrollView) {
        // SwiftUIIntrospect's customize closure can fire repeatedly — wire KVO up
        // once per scroll view instance.
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        wasAtTop = Self.isAtTop(scrollView)
        token = scrollView.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleOffsetChange(scrollView)
            }
        }
    }

    /// Scrolls the tracked view back to its top edge, animated. No-op if the
    /// scroll view has gone away.
    func scrollToTop() {
        guard let scrollView else { return }
        let top = -scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: true)
    }

    private static func isAtTop(_ scrollView: UIScrollView) -> Bool {
        // 1pt tolerance absorbs sub-point rounding in the resting offset.
        scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
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
        // so the at-top edge stays accurate even when the view is not "scrolling".
        let atTop = Self.isAtTop(scrollView)
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
    /// `ScrollActivityClient` under `scope`.
    public func trackScrollActivity(
        _ container: ScrollContainerKind = .list,
        scope: ScrollActivityClient.Scope
    ) -> some View {
        modifier(ScrollActivityModifier(container: container, scope: scope, onStop: nil))
    }

    /// Like `trackScrollActivity(_:scope:)`, plus fires `action` each time the
    /// container comes fully to rest.
    public func onScrollStopped(
        _ container: ScrollContainerKind = .list,
        scope: ScrollActivityClient.Scope,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ScrollActivityModifier(container: container, scope: scope, onStop: action))
    }
}

private struct ScrollActivityModifier: ViewModifier {
    var container: ScrollContainerKind
    var scope: ScrollActivityClient.Scope
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
