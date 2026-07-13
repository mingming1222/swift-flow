import Testing
@testable import SwiftFlow

@Suite("LiveNodeInteractionCoordinator Tests")
@MainActor
struct LiveNodeInteractionCoordinatorTests {

    @Test("Atomic preferences replace scoped entries and preserve outside scope")
    func atomicPreferencesReplaceScopedEntriesAndPreserveOutsideScope() {
        let coordinator = LiveNodeInteractionCoordinator()

        coordinator.applyPreferences(
            evaluated: ["a", "b"],
            present: ["a", "b"],
            policies: [
                "a": .persistent,
                "b": .onInteraction,
            ],
            storeNodeIDs: ["a", "b"]
        )

        #expect(coordinator.liveNodeIDs == ["a", "b"])
        #expect(coordinator.liveNodeMountPolicies["a"] == .persistent)
        #expect(coordinator.liveNodeMountPolicies["b"] == .onInteraction)

        coordinator.applyPreferences(
            evaluated: ["b"],
            present: [],
            policies: [:],
            storeNodeIDs: ["a", "b"]
        )

        #expect(coordinator.liveNodeIDs == ["a"])
        #expect(coordinator.liveNodeMountPolicies["a"] == .persistent)
        #expect(coordinator.liveNodeMountPolicies["b"] == nil)

        coordinator.applyPreferences(
            evaluated: ["a", "b"],
            present: ["b"],
            policies: ["b": .persistent],
            storeNodeIDs: ["a", "b"]
        )

        #expect(coordinator.liveNodeIDs == ["b"])
        #expect(coordinator.liveNodeMountPolicies["a"] == nil)
        #expect(coordinator.liveNodeMountPolicies["b"] == .persistent)
    }

    @Test("Successful poster capture completes the live-to-canvas handoff")
    func successfulCaptureCompletesHandoff() async throws {
        let coordinator = LiveNodeInteractionCoordinator()
        let attempts = CaptureAttemptCounter()
        coordinator.registerPosterProvider(for: "node") {
            attempts.increment()
            return true
        }

        coordinator.update(nodeID: "node", intent: true)
        coordinator.update(nodeID: "node", intent: false)
        try await waitUntil { attempts.count == 1 }
        try await waitUntil { !coordinator.isRenderedInteractive("node") }

        #expect(!coordinator.isRenderedInteractive("node"))
    }

    @Test("Failed poster capture keeps the live surface visible")
    func failedCaptureKeepsLiveSurfaceVisible() async throws {
        let coordinator = LiveNodeInteractionCoordinator()
        let attempts = CaptureAttemptCounter()
        coordinator.registerPosterProvider(for: "node") {
            attempts.increment()
            return false
        }

        coordinator.update(nodeID: "node", intent: true)
        coordinator.update(nodeID: "node", intent: false)
        try await waitUntil { attempts.count == 1 }

        #expect(coordinator.isRenderedInteractive("node"))
    }

    @Test("Re-entering interaction cancels an in-flight handoff")
    func reenteringInteractionCancelsHandoff() async throws {
        let coordinator = LiveNodeInteractionCoordinator()
        let attempts = CaptureAttemptCounter()
        coordinator.registerPosterProvider(for: "node") {
            attempts.increment()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return false
            }
            return true
        }

        coordinator.update(nodeID: "node", intent: true)
        coordinator.update(nodeID: "node", intent: false)
        try await waitUntil { attempts.count == 1 }
        coordinator.update(nodeID: "node", intent: true)
        do {
            try await Task.sleep(nanoseconds: 60_000_000)
        } catch {
            throw LiveNodeCoordinatorTestError.cancelled
        }

        #expect(coordinator.isRenderedInteractive("node"))
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition() {
            guard clock.now < deadline else {
                throw LiveNodeCoordinatorTestError.timedOut
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                throw LiveNodeCoordinatorTestError.cancelled
            }
        }
    }
}

@MainActor
private final class CaptureAttemptCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private enum LiveNodeCoordinatorTestError: Error {
    case cancelled
    case timedOut
}
