import SwiftUI
import Testing
@testable import SwiftFlow

@Suite("LiveNodeSupport Tests")
@MainActor
struct LiveNodeSupportTests {
    @Test("Live-node overlay is enabled by default")
    func enabledByDefault() {
        let canvas = FlowCanvas(store: FlowStore<String>())

        #expect(canvas.isLiveNodeOverlayEnabled)
    }

    @Test("Live-node overlay can be disabled explicitly")
    func explicitlyDisabled() {
        let canvas = FlowCanvas(store: FlowStore<String>())
            .liveNodeSupport(.disabled)

        #expect(!canvas.isLiveNodeOverlayEnabled)
    }
}
