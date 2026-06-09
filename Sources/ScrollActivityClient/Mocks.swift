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
    /// A no-op implementation: emits no phases and ignores reports.
    public static let noop = Self(
        phases: { _ in .finished },
        report: { _, _ in }
    )
}
