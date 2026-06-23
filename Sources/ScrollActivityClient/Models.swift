//
//  Models.swift
//  ScrollActivityClient
//

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

    /// Identifies an independent scroll surface. Extensible like
    /// `Notification.Name`: consumers add their own scopes in the app via
    /// `extension ScrollActivityClient.Scope { static let … }`.
    public struct Scope: Hashable, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }
}
