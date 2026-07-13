import Foundation
import Testing
@testable import SwiftFlow

@Suite("LiveNodeSnapshotNormalizer Tests")
struct LiveNodeSnapshotNormalizerTests {
    @Test("Canonical pixel dimensions follow display scale", arguments: [1.0, 2.0, 3.0])
    func canonicalPixelDimensions(scale: CGFloat) throws {
        let capturedAt = Date(timeIntervalSince1970: 123)
        let source = FlowNodeSnapshot(
            cgImage: try TestCGImageFactory.make(width: 7, height: 5),
            scale: 1,
            capturedAt: capturedAt
        )

        let normalized = try LiveNodeSnapshotNormalizer.normalize(
            source,
            logicalSize: CGSize(width: 10.25, height: 6.5),
            scale: scale
        )

        #expect(normalized.cgImage.width == Int((10.25 * scale).rounded()))
        #expect(normalized.cgImage.height == Int((6.5 * scale).rounded()))
        #expect(normalized.scale == scale)
        #expect(normalized.capturedAt == capturedAt)
    }

    @Test("Matching pixels are reused without another raster pass")
    func matchingPixelsAreReused() throws {
        let image = try TestCGImageFactory.make(width: 40, height: 24)
        let source = FlowNodeSnapshot(cgImage: image, scale: 4)

        let normalized = try LiveNodeSnapshotNormalizer.normalize(
            source,
            logicalSize: CGSize(width: 20, height: 12),
            scale: 2
        )

        #expect(normalized.cgImage === image)
        #expect(normalized.scale == 2)
    }
}
