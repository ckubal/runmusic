import SwiftUI

// Simple placeholder for pull-to-refresh - uses native SwiftUI .refreshable
struct PullToRefreshModifier: ViewModifier {
    let onRefresh: () async -> Void
    
    func body(content: Content) -> some View {
        content
            .refreshable {
                await onRefresh()
            }
    }
}

extension View {
    func pullToRefresh(onRefresh: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(onRefresh: onRefresh))
    }
}