//
//  ScrollActivityClient Interface
//  A dependency-injectable conduit for feed scroll activity.
//

import DependenciesMacros

/// A dependency client that carries a feed's scroll phase across the app.
///
/// The signal is *produced* in the view layer — a `UIScrollView` is only
/// reachable there (via SwiftUIIntrospect, in `ScrollActivityClientLive`) — and
/// pushed in through `report`. Reducers and other features consume it through
/// `phases()`. This mirrors the `NotificationsClient.observeIncoming()` shape: an
/// `AsyncStream` fed by a live actor.
///
/// ## Usage
///
/// ```swift
/// @Dependency(\.scrollActivity) var scrollActivity
///
/// // Producer (view): on each scroll edge
/// await scrollActivity.report(.savedList, .scrolling)
///
/// // Consumer (reducer): react to phase changes
/// for await phase in await scrollActivity.phases(.savedList) { … }
/// ```
@DependencyClient
public struct ScrollActivityClient: Sendable {

    /// A multicast stream of edge-triggered scroll-phase changes for `scope`.
    /// Each subscriber receives the current phase immediately on subscribe, then
    /// every subsequent change.
    public var phases: @Sendable (_ scope: ScrollScope) async -> AsyncStream<ScrollActivityPhase> = { _ in .finished }

    /// Pushes a new phase for `scope`. Called by the view's scroll observer on
    /// each edge (rest → moving, moving → rest).
    public var report: @Sendable (_ scope: ScrollScope, _ phase: ScrollActivityPhase) async -> Void
}
