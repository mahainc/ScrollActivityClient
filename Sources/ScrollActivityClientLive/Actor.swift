//
//  Actor.swift
//  ScrollActivityClientLive
//

import Foundation
import ScrollActivityClient

/// Fans the latest `ScrollActivityPhase` out to every live `phases(scope)`
/// subscriber, partitioned by `ScrollScope` so screens stay isolated. Mirrors
/// `NotificationsStore.makeStream`: a continuation registry keyed by id, cleaned
/// up on stream termination.
actor ScrollActivityHub {
    private var continuations: [ScrollScope: [UUID: AsyncStream<ScrollActivityPhase>.Continuation]] = [:]
    private var latest: [ScrollScope: ScrollActivityPhase] = [:]

    func stream(_ scope: ScrollScope) -> AsyncStream<ScrollActivityPhase> {
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
        _ scope: ScrollScope,
        _ phase: ScrollActivityPhase
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
        scope: ScrollScope
    ) {
        continuations[scope]?[id] = nil
        if continuations[scope]?.isEmpty == true {
            continuations[scope] = nil
        }
    }
}
