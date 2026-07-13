import CoreGraphics
import Testing
@testable import SwiftFlow

@Suite("LiveNode Geometry Tests")
struct LiveNodeGeometryTests {
    @Test(
        "Canvas and overlay share the same continuous draw rectangle",
        arguments: [0.5, 1.0, 2.0, 2.35, 4.0]
    )
    func sharedScreenGeometry(zoom: CGFloat) {
        let viewport = Viewport(offset: CGPoint(x: 13.25, y: -7.5), zoom: zoom)
        let geometry = LiveNodeScreenGeometry(
            nodePosition: CGPoint(x: 40.5, y: 30.25),
            nodeSize: CGSize(width: 120, height: 72),
            viewport: viewport,
            handleInset: 6
        )
        let origin = viewport.canvasToScreen(CGPoint(x: 40.5, y: 30.25))

        #expect(geometry.contentOrigin == origin)
        #expect(geometry.drawRect.minX == origin.x - 6 * zoom)
        #expect(geometry.drawRect.minY == origin.y - 6 * zoom)
        #expect(geometry.drawRect.width == 132 * zoom)
        #expect(geometry.drawRect.height == 84 * zoom)
        #expect(
            geometry.overlayDisplayScale(physicalDisplayScale: 2)
                == 2 * max(zoom, 1)
        )
    }

    #if os(macOS)
    @Test(
        "Window crop converts bottom-left screen points to top-left pixels",
        arguments: [1.0, 2.0]
    )
    func windowCropCoordinates(imageScale: CGFloat) throws {
        let geometry = try LiveNodeWindowCropGeometry(
            nodeScreenRect: CGRect(x: 150, y: 250, width: 50, height: 40),
            windowScreenFrame: CGRect(x: 100, y: 200, width: 200, height: 150),
            imageSize: CGSize(width: 200 * imageScale, height: 150 * imageScale)
        )

        #expect(
            geometry.pixelRect == CGRect(
                x: 50 * imageScale,
                y: 60 * imageScale,
                width: 50 * imageScale,
                height: 40 * imageScale
            )
        )
    }

    @Test("Window crop uses independent pixel ratios and clamps fractional geometry")
    func fractionalWindowCropCoordinates() throws {
        let geometry = try LiveNodeWindowCropGeometry(
            nodeScreenRect: CGRect(x: 99.8, y: 49.7, width: 30.4, height: 20.6),
            windowScreenFrame: CGRect(x: 100, y: 50, width: 100, height: 80),
            imageSize: CGSize(width: 200, height: 120)
        )

        #expect(geometry.pixelRect.minX == 0)
        #expect(geometry.pixelRect.maxX == 60)
        #expect(geometry.pixelRect.minY == 90)
        #expect(geometry.pixelRect.maxY == 120)
    }
    #endif
}
