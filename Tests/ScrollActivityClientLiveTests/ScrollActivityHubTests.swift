import XCTest

@testable import ScrollActivityClientLive

import ScrollActivityClient

final class ScrollActivityHubTests: XCTestCase {
    /// A fresh subscriber replays the scope's latest phase immediately.
    func testStreamReplaysLatestForScope() async {
        let hub = ScrollActivityHub()
        await hub.report(.savedList, .scrolling)

        var iterator = await hub.stream(.savedList).makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first, .scrolling)
    }

    /// Phases reported on one scope never reach a different scope's subscriber.
    func testScopesAreIsolated() async {
        let hub = ScrollActivityHub()
        await hub.report(.scanResult, .scrolling)

        var iterator = await hub.stream(.savedList).makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first, .idle)
    }

    /// A subscribed consumer receives a subsequent change on its scope.
    func testSubscriberReceivesSubsequentChange() async {
        let hub = ScrollActivityHub()
        var iterator = await hub.stream(.savedList).makeAsyncIterator()
        _ = await iterator.next()  // initial .idle replay

        await hub.report(.savedList, .scrolling)
        let next = await iterator.next()

        XCTAssertEqual(next, .scrolling)
    }
}
