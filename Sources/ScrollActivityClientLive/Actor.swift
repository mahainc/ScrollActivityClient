//
//  Actor.swift
//  ScrollActivityClientLive
//

import Foundation
import ScrollActivityClient

/// Fans the latest phase out to every live `phases(scope)` subscriber,
/// partitioned by scope so screens stay isolated. Carries three channels:
/// `phase` (moving/idle) and `position` (top/scrolled) flow *up* from the
/// surface and replay their latest value to new subscribers; `command`
/// (e.g. scroll-to-top) flows *down* and is a transient event — no replay.
actor ScrollActivityHub {
    private var phaseContinuations:
        [ScrollActivityClient.Scope: [UUID: AsyncStream<ScrollActivityClient.Phase>.Continuation]] = [:]
    private var latestPhase: [ScrollActivityClient.Scope: ScrollActivityClient.Phase] = [:]

    private var positionContinuations:
        [ScrollActivityClient.Scope: [UUID: AsyncStream<ScrollActivityClient.Position>.Continuation]] = [:]
    private var latestPosition: [ScrollActivityClient.Scope: ScrollActivityClient.Position] = [:]

    private var commandContinuations:
        [ScrollActivityClient.Scope: [UUID: AsyncStream<ScrollActivityClient.Command>.Continuation]] = [:]

    // MARK: Phase channel (up)

    func stream(_ scope: ScrollActivityClient.Scope) -> AsyncStream<ScrollActivityClient.Phase> {
        AsyncStream { continuation in
            let id = UUID()
            phaseContinuations[scope, default: [:]][id] = continuation
            continuation.yield(latestPhase[scope] ?? .idle)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePhaseSubscriber(id, scope: scope) }
            }
        }
    }

    func report(
        _ scope: ScrollActivityClient.Scope,
        _ phase: ScrollActivityClient.Phase
    ) {
        guard (latestPhase[scope] ?? .idle) != phase else { return }  // edge-only
        latestPhase[scope] = phase
        guard let conts = phaseContinuations[scope] else { return }
        for continuation in conts.values {
            continuation.yield(phase)
        }
    }

    // MARK: Position channel (up)

    func positionStream(_ scope: ScrollActivityClient.Scope) -> AsyncStream<ScrollActivityClient.Position> {
        AsyncStream { continuation in
            let id = UUID()
            positionContinuations[scope, default: [:]][id] = continuation
            continuation.yield(latestPosition[scope] ?? .atTop)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePositionSubscriber(id, scope: scope) }
            }
        }
    }

    func reportPosition(
        _ scope: ScrollActivityClient.Scope,
        _ position: ScrollActivityClient.Position
    ) {
        guard (latestPosition[scope] ?? .atTop) != position else { return }  // edge-only
        latestPosition[scope] = position
        guard let conts = positionContinuations[scope] else { return }
        for continuation in conts.values {
            continuation.yield(position)
        }
    }

    // MARK: Command channel (down)

    func commandStream(_ scope: ScrollActivityClient.Scope) -> AsyncStream<ScrollActivityClient.Command> {
        AsyncStream { continuation in
            let id = UUID()
            commandContinuations[scope, default: [:]][id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeCommandSubscriber(id, scope: scope) }
            }
        }
    }

    func sendCommand(
        _ scope: ScrollActivityClient.Scope,
        _ command: ScrollActivityClient.Command
    ) {
        guard let conts = commandContinuations[scope] else { return }
        for continuation in conts.values {
            continuation.yield(command)
        }
    }

    // MARK: Subscriber cleanup

    private func removePhaseSubscriber(
        _ id: UUID,
        scope: ScrollActivityClient.Scope
    ) {
        phaseContinuations[scope]?[id] = nil
        if phaseContinuations[scope]?.isEmpty == true {
            phaseContinuations[scope] = nil
        }
    }

    private func removePositionSubscriber(
        _ id: UUID,
        scope: ScrollActivityClient.Scope
    ) {
        positionContinuations[scope]?[id] = nil
        if positionContinuations[scope]?.isEmpty == true {
            positionContinuations[scope] = nil
        }
    }

    private func removeCommandSubscriber(
        _ id: UUID,
        scope: ScrollActivityClient.Scope
    ) {
        commandContinuations[scope]?[id] = nil
        if commandContinuations[scope]?.isEmpty == true {
            commandContinuations[scope] = nil
        }
    }
}
