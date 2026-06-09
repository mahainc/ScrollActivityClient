//
//  View+ScrollActivity.swift
//  ScrollActivityClient
//

import Dependencies
import SwiftUI

extension View {
    /// Fires `action` whenever `scope`'s scroll surface is at rest **and**
    /// `isLoaded()` returns `false`.
    @available(macOS 12.0, *)
    public func loadWhenScrollIdle(
        scope: ScrollActivityClient.Scope,
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

@available(macOS 12.0, *)
private struct LoadWhenScrollIdleModifier: ViewModifier {
    let scope: ScrollActivityClient.Scope
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
