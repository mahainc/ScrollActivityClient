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

    /// A multicast stream of edge-triggered top/scrolled changes for `scope`.
    /// New subscribers receive the scope's current position immediately, then
    /// every subsequent change.
    public var positions: @Sendable (_ scope: Scope) async -> AsyncStream<Position> = { _ in
        AsyncStream { _ in }
    }
    /// Pushes a new position for `scope`. Called by the view's scroll observer
    /// when the surface crosses (or leaves) its top edge.
    public var reportPosition: @Sendable (_ scope: Scope, _ position: Position) async -> Void

    /// A stream of transient commands for `scope`'s scroll surface. Unlike
    /// `phases`/`positions`, commands are events — not replayed to late
    /// subscribers and not de-duplicated.
    public var commands: @Sendable (_ scope: Scope) async -> AsyncStream<Command> = { _ in
        AsyncStream { _ in }
    }
    /// Asks `scope`'s scroll surface to scroll back to its top, animated.
    public var scrollToTop: @Sendable (_ scope: Scope) async -> Void
}
