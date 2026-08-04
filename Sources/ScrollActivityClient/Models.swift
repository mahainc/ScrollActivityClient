//
//  Models.swift
//  ScrollActivityClient
//

import Dependencies

extension ScrollActivityClient {
    public enum Phase: Sendable, Equatable {
        case idle
        case scrolling
    }

    /// Where a scroll surface sits relative to its top edge. Independent of
    /// `Phase`: a view can be `.scrolled` while `.idle` (resting mid-content).
    public enum Position: Sendable, Equatable {
        case atTop
        case scrolled
    }

    /// A transient instruction sent *down* to a scroll surface, the inverse of
    /// the `phases`/`positions` signals that flow *up* from it.
    public enum Command: Sendable, Equatable {
        case scrollToTop
    }

    /// The scrolling direction a tracked surface moves along. `Position` and
    /// `scrollToTop` are edge-relative: for `.vertical` the edge is the top, for
    /// `.horizontal` it is the leading edge — so `.atTop` reads as "at leading"
    /// and `scrollToTop` scrolls back to the start. `Phase` is axis-agnostic.
    public enum Axis: Sendable, Equatable {
        case vertical
        case horizontal
    }

    /// Identifies an independent scroll surface. Extensible like
    /// `Notification.Name`: consumers add their own scopes in the app via
    /// `extension ScrollActivityClient.Scope { static let … }`.
    public struct Scope: Hashable, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The items on screen when a surface came to rest, split by how much of each
    /// one is inside the viewport along the tracked axis: `fullyVisible` are
    /// wholly inside (edges within tolerance), `partiallyVisible` straddle an
    /// edge. Off-screen items — including lazily-unrendered ones — appear in
    /// neither. IDs are type-erased so the channel stays non-generic; read them
    /// back with `fullyVisible(as:)` / `partiallyVisible(as:)`.
    public struct VisibleItems: Sendable, Equatable {
        public var fullyVisible: [AnyHashableSendable]
        public var partiallyVisible: [AnyHashableSendable]

        /// No items on screen. Also the snapshot a scope replays before its
        /// surface has settled once.
        public static let empty = Self(fullyVisible: [], partiallyVisible: [])

        public init(
            fullyVisible: [AnyHashableSendable],
            partiallyVisible: [AnyHashableSendable]
        ) {
            self.fullyVisible = fullyVisible
            self.partiallyVisible = partiallyVisible
        }

        /// The fully-visible IDs recovered as `id`, dropping any that were
        /// reported under a different concrete type.
        public func fullyVisible<ID: Hashable & Sendable>(as _: ID.Type) -> [ID] {
            fullyVisible.compactMap { $0.base as? ID }
        }

        /// The partially-visible IDs recovered as `id`, dropping any that were
        /// reported under a different concrete type.
        public func partiallyVisible<ID: Hashable & Sendable>(as _: ID.Type) -> [ID] {
            partiallyVisible.compactMap { $0.base as? ID }
        }
    }
}
