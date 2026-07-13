import Foundation
import Testing
@testable import SwiftFlow

@Suite("LiveNodeSnapshotRegistry Tests")
@MainActor
struct LiveNodeSnapshotRegistryTests {
    @Test("Native provider has priority over mounted window capture")
    func nativeProviderHasPriority() async throws {
        let registry = LiveNodeSnapshotRegistry()
        let calls = SnapshotProviderCallCounts()
        let mountedImage = try TestCGImageFactory.make(width: 10, height: 10)
        let nativeImage = try TestCGImageFactory.make(width: 20, height: 20)

        registry.setMountedViewSnapshotProvider(token: UUID()) {
            calls.mounted += 1
            return FlowNodeSnapshot(cgImage: mountedImage, scale: 1)
        }
        registry.setNativeSnapshotProvider {
            calls.native += 1
            return FlowNodeSnapshot(cgImage: nativeImage, scale: 2)
        }

        let provider = try #require(
            registry.preferredSnapshotProvider(allowsMountedView: true)
        )
        let snapshot = try #require(await provider())

        #expect(snapshot.cgImage === nativeImage)
        #expect(calls.native == 1)
        #expect(calls.mounted == 0)
    }

    @Test("Mounted provider is unavailable while the live surface is hidden")
    func mountedProviderRequiresVisibleSurface() async throws {
        let registry = LiveNodeSnapshotRegistry()
        let image = try TestCGImageFactory.make(width: 10, height: 10)

        registry.setMountedViewSnapshotProvider(token: UUID()) {
            FlowNodeSnapshot(cgImage: image, scale: 1)
        }

        #expect(registry.preferredSnapshotProvider(allowsMountedView: false) == nil)
        #expect(registry.preferredSnapshotProvider(allowsMountedView: true) != nil)
    }
}

@MainActor
private final class SnapshotProviderCallCounts {
    var native = 0
    var mounted = 0
}
