//
//  Mocks.swift
//  ScrollActivityClient
//

import Dependencies

extension DependencyValues {
    public var scrollActivity: ScrollActivityClient {
        get { self[ScrollActivityClient.self] }
        set { self[ScrollActivityClient.self] = newValue }
    }
}

extension ScrollActivityClient: TestDependencyKey {
    public static let previewValue = Self.noop
    public static let testValue = Self()
}

extension ScrollActivityClient {
    public static let noop = Self(
        phases: { _ in AsyncStream { _ in } },
        report: { _, _ in }
    )
}
