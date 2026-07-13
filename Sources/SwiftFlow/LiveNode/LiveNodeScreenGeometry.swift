import CoreGraphics

struct LiveNodeScreenGeometry: Sendable, Hashable {
    let contentOrigin: CGPoint
    let drawRect: CGRect
    let zoom: CGFloat

    func overlayDisplayScale(physicalDisplayScale: CGFloat) -> CGFloat {
        max(physicalDisplayScale, 1) * max(zoom, 1)
    }

    init(
        nodePosition: CGPoint,
        nodeSize: CGSize,
        viewport: Viewport,
        handleInset: CGFloat
    ) {
        let contentOrigin = viewport.canvasToScreen(nodePosition)
        self.contentOrigin = contentOrigin
        self.drawRect = CGRect(
            x: contentOrigin.x - handleInset * viewport.zoom,
            y: contentOrigin.y - handleInset * viewport.zoom,
            width: (nodeSize.width + handleInset * 2) * viewport.zoom,
            height: (nodeSize.height + handleInset * 2) * viewport.zoom
        )
        self.zoom = viewport.zoom
    }
}
