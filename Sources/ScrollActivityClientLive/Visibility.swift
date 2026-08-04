//
//  Visibility.swift
//  ScrollActivityClientLive
//

import Dependencies
import ScrollActivityClient
import SwiftUI

// MARK: - Item reporting

extension View {
    /// Tags this view as item `id` inside a `trackVisibleItems(scope:)` surface,
    /// so its on-screen frame is measured when the surface settles. Apply it to
    /// each row/card and the enclosing scroll view to the matching container
    /// modifier; both must share the same `scope`.
    public func visibleItem(
        _ id: some Hashable & Sendable,
        scope: ScrollActivityClient.Scope
    ) -> some View {
        modifier(VisibleItemModifier(id: AnyHashableSendable(id), scope: scope))
    }
}

private struct VisibleItemModifier: ViewModifier {
    let id: AnyHashableSendable
    let scope: ScrollActivityClient.Scope

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: VisibleItemFramesKey.self,
                    value: [id: proxy.frame(in: .named(ScrollVisibilitySpace(scope: scope.rawValue)))]
                )
            }
        )
    }
}

/// The frames of every tagged item, keyed by id, in their surface's coordinate
/// space. Merged across items so one preference carries the whole snapshot.
private struct VisibleItemFramesKey: PreferenceKey {
    static var defaultValue: [AnyHashableSendable: CGRect] { [:] }

    static func reduce(
        value: inout [AnyHashableSendable: CGRect],
        nextValue: () -> [AnyHashableSendable: CGRect]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

/// The coordinate space each scope measures item frames in, so an item and the
/// surface tracking it agree on geometry without sharing a hardcoded name.
private struct ScrollVisibilitySpace: Hashable {
    let scope: String
}

// MARK: - Surface tracking

extension View {
    /// Reports the on-screen items to `scope`'s `visibleItems` stream each time
    /// the surface comes to rest, split into fully- and partially-visible along
    /// `axis`. Pair with `visibleItem(_:scope:)` on each item and, typically,
    /// `trackScrollActivity(_:scope:axis:)` on the same surface.
    public func trackVisibleItems(
        scope: ScrollActivityClient.Scope,
        axis: ScrollActivityClient.Axis = .vertical
    ) -> some View {
        modifier(TrackVisibleItemsModifier(scope: scope, axis: axis))
    }
}

private struct TrackVisibleItemsModifier: ViewModifier {
    let scope: ScrollActivityClient.Scope
    let axis: ScrollActivityClient.Axis

    @Dependency(\.scrollActivity) private var scrollActivity
    @State private var frames: [AnyHashableSendable: CGRect] = [:]
    @State private var viewportSize: CGSize = .zero
    @State private var isIdle = true

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(ScrollVisibilitySpace(scope: scope.rawValue)))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in viewportSize = size }
                }
            )
            .onPreferenceChange(VisibleItemFramesKey.self) { frames = $0 }
            .onChange(of: frames) { _, _ in reportIfIdle() }
            .task { await trackPhase() }
    }

    /// Publishes a fresh snapshot on every settle. Phase replays `.idle` to a new
    /// subscriber, so this also fires once on appear with whatever is on screen.
    private func trackPhase() async {
        for await phase in await scrollActivity.phases(scope) {
            isIdle = phase == .idle
            guard isIdle else { continue }
            await report()
        }
    }

    /// Re-publishes when items shift while at rest — the first frames often land
    /// just after the initial `.idle`, and layout can settle a frame late.
    private func reportIfIdle() {
        guard isIdle else { return }
        Task { await report() }
    }

    private func report() async {
        let viewport = CGRect(origin: .zero, size: viewportSize)
        let items = classifyVisibleItems(frames: frames, viewport: viewport, axis: axis)
        await scrollActivity.reportVisibleItems(scope, items)
    }
}

// MARK: - Classification

/// Splits `frames` into fully- and partially-visible items against `viewport`
/// along `axis`, each list ordered by leading edge so it reads in scroll order.
/// Items with no overlap are dropped. Pure and synchronous for testability.
func classifyVisibleItems(
    frames: [AnyHashableSendable: CGRect],
    viewport: CGRect,
    axis: ScrollActivityClient.Axis
) -> ScrollActivityClient.VisibleItems {
    var full: [(id: AnyHashableSendable, start: CGFloat)] = []
    var partial: [(id: AnyHashableSendable, start: CGFloat)] = []
    for (id, frame) in frames {
        switch visibility(of: frame, in: viewport, axis: axis) {
        case .full:
            full.append((id, axisStart(frame, axis)))
        case .partial:
            partial.append((id, axisStart(frame, axis)))
        case .hidden:
            break
        }
    }
    return ScrollActivityClient.VisibleItems(
        fullyVisible: sortedIDs(full),
        partiallyVisible: sortedIDs(partial)
    )
}

private enum ItemVisibility {
    case full
    case partial
    case hidden
}

/// How much of `frame` lies inside `viewport` along `axis`. `tolerance` (1pt)
/// absorbs sub-point rounding so a flush edge still counts as fully visible.
private func visibility(
    of frame: CGRect,
    in viewport: CGRect,
    axis: ScrollActivityClient.Axis,
    tolerance: CGFloat = 1
) -> ItemVisibility {
    let (start, end) = axisSpan(frame, axis)
    let (viewStart, viewEnd) = axisSpan(viewport, axis)
    guard end > viewStart + tolerance, start < viewEnd - tolerance else {
        return .hidden
    }
    let contained = start >= viewStart - tolerance && end <= viewEnd + tolerance
    return contained ? .full : .partial
}

/// The `(start, end)` extent of `rect` along `axis`.
private func axisSpan(_ rect: CGRect, _ axis: ScrollActivityClient.Axis) -> (CGFloat, CGFloat) {
    switch axis {
    case .vertical: (rect.minY, rect.maxY)
    case .horizontal: (rect.minX, rect.maxX)
    }
}

private func axisStart(_ frame: CGRect, _ axis: ScrollActivityClient.Axis) -> CGFloat {
    axisSpan(frame, axis).0
}

private func sortedIDs(_ bucket: [(id: AnyHashableSendable, start: CGFloat)]) -> [AnyHashableSendable] {
    bucket.sorted { $0.start < $1.start }.map(\.id)
}
