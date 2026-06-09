//
//  Models.swift
//  ScrollActivityClient
//

/// Coarse scroll phase for a feed's scroll view.
///
/// Named `ScrollActivityPhase` (not `ScrollPhase`) to avoid colliding with
/// `SwiftUI.ScrollPhase` — both ship an `.idle` case, and `ScrollActivityClientLive`
/// imports SwiftUI.
public enum ScrollActivityPhase: Sendable, Equatable {
    /// The scroll view is fully at rest (no touch, drag, or momentum).
    case idle
    /// The scroll view is actively moving (user drag or deceleration).
    case scrolling
}

/// Identifies an independent scroll surface, so phases reported by one screen
/// don't drive another screen's consumers. Producers report under a scope;
/// consumers subscribe to the same scope. Extensible like `Notification.Name`:
/// add new scopes as `static let`s without touching this module.
public struct ScrollScope: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let savedList = ScrollScope("savedList")
    public static let savedDetail = ScrollScope("savedDetail")
    public static let scanResult = ScrollScope("scanResult")
}
