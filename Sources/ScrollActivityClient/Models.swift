//
//  Models.swift
//  ScrollActivityClient
//

extension ScrollActivityClient {
    public enum Phase: Sendable, Equatable {
        case idle
        case scrolling
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
