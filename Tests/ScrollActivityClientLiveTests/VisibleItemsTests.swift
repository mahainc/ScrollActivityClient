import CoreGraphics
import Dependencies
import ScrollActivityClient
import XCTest

@testable import ScrollActivityClientLive

extension ScrollActivityClient.Scope {
    fileprivate static let savedList = Self("savedList")
    fileprivate static let scanResult = Self("scanResult")
}

final class ClassifyVisibleItemsTests: XCTestCase {
    /// A 100pt viewport with three stacked 40pt rows: row 0 sits flush inside,
    /// row 1 is inside, row 2 straddles the bottom edge.
    private func verticalFrames() -> [AnyHashableSendable: CGRect] {
        [
            AnyHashableSendable("row0"): CGRect(x: 0, y: 0, width: 50, height: 40),
            AnyHashableSendable("row1"): CGRect(x: 0, y: 40, width: 50, height: 40),
            AnyHashableSendable("row2"): CGRect(x: 0, y: 80, width: 50, height: 40),
        ]
    }

    private let viewport = CGRect(x: 0, y: 0, width: 50, height: 100)

    func testVerticalSplitsFullyAndPartially() {
        let items = classifyVisibleItems(
            frames: verticalFrames(),
            viewport: viewport,
            axis: .vertical
        )

        XCTAssertEqual(items.fullyVisible(as: String.self), ["row0", "row1"])
        XCTAssertEqual(items.partiallyVisible(as: String.self), ["row2"])
    }

    /// Fully-visible are ordered by leading edge regardless of dictionary order.
    func testFullyVisibleOrderedByLeadingEdge() {
        let frames: [AnyHashableSendable: CGRect] = [
            AnyHashableSendable("b"): CGRect(x: 0, y: 40, width: 50, height: 30),
            AnyHashableSendable("a"): CGRect(x: 0, y: 0, width: 50, height: 30),
        ]

        let items = classifyVisibleItems(frames: frames, viewport: viewport, axis: .vertical)

        XCTAssertEqual(items.fullyVisible(as: String.self), ["a", "b"])
    }

    /// An item entirely past the trailing edge appears in neither list.
    func testOffscreenItemDropped() {
        var frames = verticalFrames()
        frames[AnyHashableSendable("row3")] = CGRect(x: 0, y: 200, width: 50, height: 40)

        let items = classifyVisibleItems(frames: frames, viewport: viewport, axis: .vertical)

        let all = items.fullyVisible(as: String.self) + items.partiallyVisible(as: String.self)
        XCTAssertFalse(all.contains("row3"))
    }

    /// A row flush against the bottom edge (within tolerance) still counts full.
    func testFlushEdgeCountsFull() {
        let frames = [AnyHashableSendable("edge"): CGRect(x: 0, y: 60, width: 50, height: 40)]

        let items = classifyVisibleItems(frames: frames, viewport: viewport, axis: .vertical)

        XCTAssertEqual(items.fullyVisible(as: String.self), ["edge"])
        XCTAssertTrue(items.partiallyVisible.isEmpty)
    }

    /// Horizontal axis classifies against the x extent, ignoring vertical.
    func testHorizontalAxisUsesXExtent() {
        let frames: [AnyHashableSendable: CGRect] = [
            AnyHashableSendable("c0"): CGRect(x: 0, y: 0, width: 40, height: 200),
            AnyHashableSendable("c1"): CGRect(x: 80, y: 0, width: 40, height: 200),
        ]
        let wideViewport = CGRect(x: 0, y: 0, width: 100, height: 50)

        let items = classifyVisibleItems(frames: frames, viewport: wideViewport, axis: .horizontal)

        XCTAssertEqual(items.fullyVisible(as: String.self), ["c0"])
        XCTAssertEqual(items.partiallyVisible(as: String.self), ["c1"])
    }
}

final class ScrollActivityHubVisibilityTests: XCTestCase {
    /// A fresh subscriber replays the scope's latest snapshot immediately.
    func testVisibilityReplaysLatestForScope() async {
        let hub = ScrollActivityHub()
        let items = ScrollActivityClient.VisibleItems(
            fullyVisible: [AnyHashableSendable("row0")],
            partiallyVisible: []
        )
        await hub.reportVisibleItems(.savedList, items)

        var iterator = await hub.visibilityStream(.savedList).makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first, items)
    }

    /// Snapshots reported on one scope never reach another scope's subscriber.
    func testVisibilityScopesAreIsolated() async {
        let hub = ScrollActivityHub()
        await hub.reportVisibleItems(
            .scanResult,
            ScrollActivityClient.VisibleItems(fullyVisible: [AnyHashableSendable("x")], partiallyVisible: [])
        )

        var iterator = await hub.visibilityStream(.savedList).makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first, ScrollActivityClient.VisibleItems.empty)
    }
}
