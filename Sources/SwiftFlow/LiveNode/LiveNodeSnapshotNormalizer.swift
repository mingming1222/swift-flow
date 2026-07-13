import CoreGraphics
import Foundation

enum LiveNodeSnapshotNormalizer {
    static func pixelSize(logicalSize: CGSize, scale: CGFloat) throws -> CGSize {
        guard logicalSize.width.isFinite,
              logicalSize.height.isFinite,
              logicalSize.width > 0,
              logicalSize.height > 0 else {
            throw LiveNodeSnapshotCaptureError.invalidLogicalSize(logicalSize)
        }
        guard scale.isFinite, scale > 0 else {
            throw LiveNodeSnapshotCaptureError.invalidScale(scale)
        }
        return CGSize(
            width: max(1, (logicalSize.width * scale).rounded(.toNearestOrAwayFromZero)),
            height: max(1, (logicalSize.height * scale).rounded(.toNearestOrAwayFromZero))
        )
    }

    static func normalize(
        _ snapshot: FlowNodeSnapshot,
        logicalSize: CGSize,
        scale: CGFloat
    ) throws -> FlowNodeSnapshot {
        let targetSize = try pixelSize(logicalSize: logicalSize, scale: scale)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

        if snapshot.cgImage.width == targetWidth,
           snapshot.cgImage.height == targetHeight {
            return FlowNodeSnapshot(
                cgImage: snapshot.cgImage,
                scale: scale,
                capturedAt: snapshot.capturedAt
            )
        }

        let sourceColorSpace = snapshot.cgImage.colorSpace
        let fallbackColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let context = sourceColorSpace.flatMap {
            makeContext(width: targetWidth, height: targetHeight, colorSpace: $0)
        } ?? fallbackColorSpace.flatMap {
            makeContext(width: targetWidth, height: targetHeight, colorSpace: $0)
        }
        guard let context else {
            throw LiveNodeSnapshotCaptureError.bitmapContextUnavailable
        }

        context.interpolationQuality = .high
        context.draw(
            snapshot.cgImage,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )
        guard let image = context.makeImage() else {
            throw LiveNodeSnapshotCaptureError.renderingFailed
        }
        return FlowNodeSnapshot(
            cgImage: image,
            scale: scale,
            capturedAt: snapshot.capturedAt
        )
    }

    private static func makeContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
