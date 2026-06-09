//
//  Actor.swift
//  ScrollActivityClientLive
//

import Foundation
import ScrollActivityClient

/// Fans the latest phase out to every live `phases(scope)` subscriber,
/// partitioned by scope so screens stay isolated.
actor ScrollActivityHub {
    private var continuations:
        [ScrollActivityClient.Scope: [UUID: AsyncStream<ScrollActivityClient.Phase>.Continuation]] = [:]
    private var latest: [ScrollActivityClient.Scope: ScrollActivityClient.Phase] = [:]

    func stream(_ scope: ScrollActivityClient.Scope) -> AsyncStream<ScrollActivityClient.Phase> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[scope, default: [:]][id] = continuation
            continuation.yield(latest[scope] ?? .idle)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id, scope: scope) }
            }
        }
    }

    func report(
        _ scope: ScrollActivityClient.Scope,
        _ phase: ScrollActivityClient.Phase
    ) {
        guard (latest[scope] ?? .idle) != phase else { return }  // edge-only
        latest[scope] = phase
        guard let conts = continuations[scope] else { return }
        for continuation in conts.values {
            continuation.yield(phase)
        }
    }

    private func removeSubscriber(
        _ id: UUID,
        scope: ScrollActivityClient.Scope
    ) {
        continuations[scope]?[id] = nil
        if continuations[scope]?.isEmpty == true {
            continuations[scope] = nil
        }
    }
}
