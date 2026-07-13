#if os(macOS)
import CoreGraphics
import Testing
@testable import SwiftFlow

@Suite("LiveNodeMountedWindowSnapshotter Tests")
@MainActor
struct LiveNodeMountedWindowSnapshotterTests {
    @Test("Mounted window capture crops the current window image")
    func cropsCurrentWindowImage() async throws {
        let capturer = FakeLiveNodeWindowCapturer(
            image: try TestCGImageFactory.make(width: 400, height: 300)
        )
        let snapshotter = LiveNodeMountedWindowSnapshotter(capturer: capturer)

        let snapshot = try await snapshotter.snapshot(
            windowID: 42,
            nodeScreenRect: CGRect(x: 150, y: 250, width: 50, height: 40),
            windowScreenFrame: CGRect(x: 100, y: 200, width: 200, height: 150),
            logicalSize: CGSize(width: 50, height: 40),
            scale: 2
        )

        #expect(capturer.capturedWindowIDs == [42])
        #expect(snapshot.cgImage.width == 100)
        #expect(snapshot.cgImage.height == 80)
        #expect(snapshot.scale == 2)
    }

    @Test("A zoomed-out crop is rejected before normalization")
    func rejectsZoomedOutCrop() async throws {
        let capturer = FakeLiveNodeWindowCapturer(
            image: try TestCGImageFactory.make(width: 200, height: 150)
        )
        let snapshotter = LiveNodeMountedWindowSnapshotter(capturer: capturer)

        do {
            _ = try await snapshotter.snapshot(
                windowID: 42,
                nodeScreenRect: CGRect(x: 150, y: 250, width: 50, height: 40),
                windowScreenFrame: CGRect(x: 100, y: 200, width: 200, height: 150),
                logicalSize: CGSize(width: 50, height: 40),
                scale: 2
            )
            Issue.record("Expected a zoomed-out crop to be rejected")
        } catch let error as LiveNodeSnapshotCaptureError {
            guard case .insufficientResolution = error else {
                Issue.record("Unexpected capture error: \(error)")
                return
            }
        }
    }
}

@MainActor
private final class FakeLiveNodeWindowCapturer: LiveNodeWindowCapturing {
    let image: CGImage
    private(set) var capturedWindowIDs: [CGWindowID] = []

    init(image: CGImage) {
        self.image = image
    }

    func capture(windowID: CGWindowID) async throws -> CGImage {
        capturedWindowIDs.append(windowID)
        return image
    }
}
#endif
