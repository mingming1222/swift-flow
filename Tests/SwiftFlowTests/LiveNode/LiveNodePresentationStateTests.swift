import Testing
@testable import SwiftFlow

@Suite("LiveNodePresentationState Tests")
struct LiveNodePresentationStateTests {
    @Test("Missing snapshot gives the overlay exclusive drawing ownership")
    func warmupUsesOverlayOnly() {
        let state = makeState(hasSnapshot: false)

        #expect(state.drawingOwner == .overlay)
        #expect(state.suppressesCanvas)
        #expect(state.isOverlayMounted)
        #expect(state.isOverlayVisible)
        #expect(!state.isInteractive)
        #expect(!state.isHittable)
    }

    @Test("Warmup remains visible but non-hittable during viewport interaction")
    func warmupDuringViewportInteraction() {
        let state = makeState(
            hasSnapshot: false,
            hasInteractionIntent: true,
            isViewportInteracting: true
        )

        #expect(state.drawingOwner == .overlay)
        #expect(state.isOverlayVisible)
        #expect(!state.isInteractive)
        #expect(!state.isHittable)
    }

    @Test("Idle snapshot is owned by Canvas")
    func idleSnapshotUsesCanvas() {
        let onInteraction = makeState(hasSnapshot: true)
        let persistent = makeState(hasSnapshot: true, mountPolicy: .persistent)

        #expect(onInteraction.drawingOwner == .canvas)
        #expect(!onInteraction.isOverlayMounted)
        #expect(!onInteraction.isOverlayVisible)
        #expect(persistent.drawingOwner == .canvas)
        #expect(persistent.isOverlayMounted)
        #expect(!persistent.isOverlayVisible)
    }

    @Test("Interaction gives the visible overlay hit testing")
    func interactionUsesHittableOverlay() {
        let state = makeState(
            hasSnapshot: true,
            hasInteractionIntent: true
        )

        #expect(state.drawingOwner == .overlay)
        #expect(state.isOverlayVisible)
        #expect(state.isInteractive)
        #expect(state.isHittable)
    }

    @Test("Handoff and capture failure keep a non-hittable overlay visible")
    func handoffKeepsOverlayVisible() {
        let state = makeState(
            hasSnapshot: true,
            keepsOverlayVisibleForHandoff: true
        )

        #expect(state.drawingOwner == .overlay)
        #expect(state.isOverlayVisible)
        #expect(!state.isInteractive)
        #expect(!state.isHittable)
    }

    @Test("Viewport interaction uses a valid Canvas poster")
    func viewportInteractionUsesCanvasPoster() {
        let state = makeState(
            hasSnapshot: true,
            mountPolicy: .persistent,
            hasInteractionIntent: true,
            keepsOverlayVisibleForHandoff: true,
            isViewportInteracting: true
        )

        #expect(state.drawingOwner == .canvas)
        #expect(state.isOverlayMounted)
        #expect(!state.isOverlayVisible)
        #expect(!state.isHittable)
    }

    @Test("Every input combination preserves drawing ownership invariants")
    func exhaustiveInvariants() {
        for isLiveNode in [false, true] {
            for hasSnapshot in [false, true] {
                for mountPolicy in [LiveNodeMountPolicy.onInteraction, .persistent] {
                    for hasInteractionIntent in [false, true] {
                        for keepsOverlayVisibleForHandoff in [false, true] {
                            for isViewportInteracting in [false, true] {
                                let state = LiveNodePresentationState(
                                    isLiveNode: isLiveNode,
                                    hasSnapshot: hasSnapshot,
                                    mountPolicy: mountPolicy,
                                    hasInteractionIntent: hasInteractionIntent,
                                    keepsOverlayVisibleForHandoff: keepsOverlayVisibleForHandoff,
                                    isViewportInteracting: isViewportInteracting
                                )

                                #expect(
                                    state.isOverlayVisible == state.suppressesCanvas
                                )
                                #expect(!state.isOverlayVisible || state.isOverlayMounted)
                                #expect(!state.isHittable || state.isOverlayVisible)
                            }
                        }
                    }
                }
            }
        }
    }

    private func makeState(
        hasSnapshot: Bool,
        mountPolicy: LiveNodeMountPolicy = .onInteraction,
        hasInteractionIntent: Bool = false,
        keepsOverlayVisibleForHandoff: Bool = false,
        isViewportInteracting: Bool = false
    ) -> LiveNodePresentationState {
        LiveNodePresentationState(
            isLiveNode: true,
            hasSnapshot: hasSnapshot,
            mountPolicy: mountPolicy,
            hasInteractionIntent: hasInteractionIntent,
            keepsOverlayVisibleForHandoff: keepsOverlayVisibleForHandoff,
            isViewportInteracting: isViewportInteracting
        )
    }
}
