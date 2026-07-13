import CoreGraphics
import Foundation
import Testing
@testable import SwiftFlow

@Suite("LiveNodeSnapshotQuality Tests")
struct LiveNodeSnapshotQualityTests {
    @Test("A crop below canonical density is rejected")
    func rejectsLowResolutionCrop() throws {
        let snapshot = FlowNodeSnapshot(
            cgImage: try TestCGImageFactory.make(width: 180, height: 107),
            scale: 2
        )

        do {
            try LiveNodeSnapshotQuality.validate(
                snapshot,
                logicalSize: CGSize(width: 360, height: 214),
                requiredScale: 2
            )
            Issue.record("Expected a low-resolution crop to be rejected")
        } catch let error as LiveNodeSnapshotCaptureError {
            guard case let .insufficientResolution(source, required) = error else {
                Issue.record("Unexpected capture error: \(error)")
                return
            }
            #expect(source == CGSize(width: 180, height: 107))
            #expect(required == CGSize(width: 720, height: 428))
        }
    }

    @Test("A native provider at canonical density is accepted")
    func acceptsCanonicalResolution() throws {
        let image = try TestCGImageFactory.make(width: 720, height: 428)
        let snapshot = FlowNodeSnapshot(cgImage: image, scale: 2)

        try LiveNodeSnapshotQuality.validate(
            snapshot,
            logicalSize: CGSize(width: 360, height: 214),
            requiredScale: 2
        )
        let normalized = try LiveNodeSnapshotQuality.normalize(
            snapshot,
            logicalSize: CGSize(width: 360, height: 214),
            scale: 2
        )
        #expect(normalized.cgImage === image)
    }
}
