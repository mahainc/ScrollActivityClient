//
//  Live.swift
//  ScrollActivityClientLive
//

import Dependencies
import ScrollActivityClient

extension ScrollActivityClient: DependencyKey {
    public static let liveValue: ScrollActivityClient = {
        let hub = ScrollActivityHub()
        return ScrollActivityClient(
            phases: { scope in await hub.stream(scope) },
            report: { scope, phase in await hub.report(scope, phase) },
            positions: { scope in await hub.positionStream(scope) },
            reportPosition: { scope, position in await hub.reportPosition(scope, position) },
            commands: { scope in await hub.commandStream(scope) },
            scrollToTop: { scope in await hub.sendCommand(scope, .scrollToTop) },
            visibleItems: { scope in await hub.visibilityStream(scope) },
            reportVisibleItems: { scope, items in await hub.reportVisibleItems(scope, items) }
        )
    }()
}
