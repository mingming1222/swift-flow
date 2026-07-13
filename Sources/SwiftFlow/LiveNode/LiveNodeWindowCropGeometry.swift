import CoreGraphics

struct LiveNodeWindowCropGeometry: Sendable, Hashable {
    let pixelRect: CGRect

    init(
        nodeScreenRect: CGRect,
        windowScreenFrame: CGRect,
        imageSize: CGSize
    ) throws {
        guard windowScreenFrame.width > 0,
              windowScreenFrame.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            throw LiveNodeSnapshotCaptureError.cropOutsideImage(nodeScreenRect)
        }

        let scaleX = imageSize.width / windowScreenFrame.width
        let scaleY = imageSize.height / windowScreenFrame.height
        let minX = ((nodeScreenRect.minX - windowScreenFrame.minX) * scaleX)
            .rounded(.toNearestOrAwayFromZero)
        let maxX = ((nodeScreenRect.maxX - windowScreenFrame.minX) * scaleX)
            .rounded(.toNearestOrAwayFromZero)
        let minY = ((windowScreenFrame.maxY - nodeScreenRect.maxY) * scaleY)
            .rounded(.toNearestOrAwayFromZero)
        let maxY = ((windowScreenFrame.maxY - nodeScreenRect.minY) * scaleY)
            .rounded(.toNearestOrAwayFromZero)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let candidate = CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        ).intersection(imageBounds)

        guard !candidate.isNull,
              candidate.width > 0,
              candidate.height > 0 else {
            throw LiveNodeSnapshotCaptureError.cropOutsideImage(candidate)
        }
        self.pixelRect = candidate.integral
    }
}
