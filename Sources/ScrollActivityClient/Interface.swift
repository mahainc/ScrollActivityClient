//
//  Interface.swift
//  ScrollActivityClient
//

import DependenciesMacros

@DependencyClient
public struct ScrollActivityClient: Sendable {
    public var phases: @Sendable (_ scope: Scope) async -> AsyncStream<Phase> = { _ in
        AsyncStream { _ in }
    }
    public var report: @Sendable (_ scope: Scope, _ phase: Phase) async -> Void
}
