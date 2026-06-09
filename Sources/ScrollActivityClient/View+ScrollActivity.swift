//
//  View+ScrollActivity.swift
//  ScrollActivityClient
//

import Dependencies
import SwiftUI

extension View {
    /// Fires `action` whenever `scope`'s scroll surface is at rest **and**
    /// `isLoaded()` returns `false`. Drives the "load a native ad only while the
    /// list is idle" gate: the `.task` lives for the view's on-screen lifetime,
    /// `phases(scope)` yields `.idle` only at rest, and `isLoaded` is re-checked
    /// each tick so the load fires at most once and never mid-scroll.
    public func loadWhenScrollIdle(
        scope: ScrollScope,
        isLoaded: @escaping () -> Bool,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(
            LoadWhenScrollIdleModifier(
                scope: scope,
                isLoaded: isLoaded,
                action: action
            )
        )
    }
}

private struct LoadWhenScrollIdleModifier: ViewModifier {
    let scope: ScrollScope
    let isLoaded: () -> Bool
    let action: () -> Void

    @Dependency(\.scrollActivity) private var scrollActivity

    func body(content: Content) -> some View {
        content.task {
            for await phase in await scrollActivity.phases(scope) {
                guard phase == .idle, !isLoaded() else { continue }
                action()
            }
        }
    }
}
