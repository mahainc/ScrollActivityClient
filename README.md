# ScrollActivityClient

A dependency-injectable conduit for a feed's scroll phase (`idle` / `scrolling`),
partitioned per screen. The signal is **produced** in the view layer (a
`UIScrollView` reached via SwiftUIIntrospect) and **consumed** by reducers or
views — e.g. to gate native-ad loads to scroll-rest.

- `ScrollActivityClient` — interface: the `@DependencyClient`, `ScrollActivityPhase`,
  `ScrollScope`, and the `loadWhenScrollIdle(scope:isLoaded:perform:)` consumer modifier.
- `ScrollActivityClientLive` — live: the `trackScrollActivity(_:scope:)` /
  `onScrollStopped(_:scope:)` producer modifiers and the multicast actor hub.

## Installation

```swift
.package(url: "https://github.com/mahainc/ScrollActivityClient.git", from: "0.1.0")
```

…or locally:

```swift
.package(path: "../ScrollActivityClient")
```

Add `ScrollActivityClient` to any target that consumes phases; add
`ScrollActivityClientLive` only where you also produce them (and in the app's
composition root).

## Usage

```swift
// Producer (view): report the surface's phase under a scope.
List { … }
    .trackScrollActivity(scope: .savedList)

// Consumer (view): run a one-shot load only while that surface is at rest.
AdRow(…)
    .loadWhenScrollIdle(scope: .savedList, isLoaded: { store.ad != nil }) {
        store.send(.loadAd)
    }

// Consumer (reducer):
@Dependency(\.scrollActivity) var scrollActivity
for await phase in await scrollActivity.phases(.savedList) { … }
```

Define your own surfaces by extending `ScrollScope` (like `Notification.Name`):

```swift
extension ScrollScope { static let myFeed = ScrollScope("myFeed") }
```

## Platforms

iOS 17+.
