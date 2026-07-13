#if os(macOS)
import CoreGraphics
import Foundation

@MainActor
struct LiveNodeMountedWindowSnapshotter {
    let capturer: any LiveNodeWindowCapturing

    func snapshot(
        windowID: CGWindowID,
        nodeScreenRect: CGRect,
        windowScreenFrame: CGRect,
        logicalSize: CGSize,
        scale: CGFloat
    ) async throws -> FlowNodeSnapshot {
        let fullWindowImage = try await capturer.capture(windowID: windowID)
        guard !Task.isCancelled else {
            throw CancellationError()
        }
        let cropGeometry = try LiveNodeWindowCropGeometry(
            nodeScreenRect: nodeScreenRect,
            windowScreenFrame: windowScreenFrame,
            imageSize: CGSize(
                width: fullWindowImage.width,
                height: fullWindowImage.height
            )
        )
        guard let croppedImage = fullWindowImage.cropping(to: cropGeometry.pixelRect) else {
            throw LiveNodeSnapshotCaptureError.imageUnavailable
        }
        let snapshot = FlowNodeSnapshot(cgImage: croppedImage, scale: scale)
        try LiveNodeSnapshotQuality.validate(
            snapshot,
            logicalSize: logicalSize,
            requiredScale: scale
        )
        return snapshot
    }
}
#endif
