import CoreGraphics
import Foundation

enum LiveNodeSnapshotQuality {
    static func validate(
        _ snapshot: FlowNodeSnapshot,
        logicalSize: CGSize,
        requiredScale: CGFloat
    ) throws {
        let requiredPixelSize = try LiveNodeSnapshotNormalizer.pixelSize(
            logicalSize: logicalSize,
            scale: requiredScale
        )
        let sourcePixelSize = CGSize(
            width: snapshot.cgImage.width,
            height: snapshot.cgImage.height
        )
        guard sourcePixelSize.width >= requiredPixelSize.width,
              sourcePixelSize.height >= requiredPixelSize.height else {
            throw LiveNodeSnapshotCaptureError.insufficientResolution(
                sourcePixelSize: sourcePixelSize,
                requiredPixelSize: requiredPixelSize
            )
        }
    }

    static func normalize(
        _ snapshot: FlowNodeSnapshot,
        logicalSize: CGSize,
        scale: CGFloat
    ) throws -> FlowNodeSnapshot {
        try validate(
            snapshot,
            logicalSize: logicalSize,
            requiredScale: scale
        )
        return try LiveNodeSnapshotNormalizer.normalize(
            snapshot,
            logicalSize: logicalSize,
            scale: scale
        )
    }
}
