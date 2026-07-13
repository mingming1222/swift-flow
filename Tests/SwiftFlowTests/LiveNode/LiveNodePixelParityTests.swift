import CoreGraphics
import Foundation
import Testing
@testable import SwiftFlow

@Suite("LiveNode Pixel Parity Tests")
struct LiveNodePixelParityTests {
    @Test("Poster and live boundary pixels stay within parity thresholds")
    func posterAndLiveBoundaryParity() throws {
        let displayScale: CGFloat = 2
        let nodeSize = CGSize(width: 40, height: 30)
        let sourceImage = try TestCGImageFactory.make(width: 80, height: 60)
        let snapshot = try LiveNodeSnapshotNormalizer.normalize(
            FlowNodeSnapshot(cgImage: sourceImage, scale: displayScale),
            logicalSize: nodeSize,
            scale: displayScale
        )
        let canvasSize = CGSize(width: 320, height: 240)

        for zoom: CGFloat in [0.5, 1, 2, 2.35, 4] {
            for offset in [CGPoint(x: 20, y: 18), CGPoint(x: 20.25, y: 18.5)] {
                let viewport = Viewport(offset: offset, zoom: zoom)
                let nodePosition = CGPoint(x: 24.5, y: 16.25)
                let geometry = LiveNodeScreenGeometry(
                    nodePosition: nodePosition,
                    nodeSize: nodeSize,
                    viewport: viewport,
                    handleInset: 0
                )
                let liveOrigin = viewport.canvasToScreen(nodePosition)
                let liveRect = CGRect(
                    origin: liveOrigin,
                    size: CGSize(
                        width: nodeSize.width * zoom,
                        height: nodeSize.height * zoom
                    )
                )
                let liveImage = try render(
                    sourceImage,
                    in: liveRect,
                    canvasSize: canvasSize,
                    displayScale: displayScale
                )
                let posterImage = try render(
                    snapshot.cgImage,
                    in: geometry.drawRect,
                    canvasSize: canvasSize,
                    displayScale: displayScale
                )
                let difference = try boundaryDifference(
                    liveImage,
                    posterImage,
                    rect: geometry.drawRect,
                    bandWidth: 2
                )

                #expect(difference.meanRGBA <= 1.0 / 255.0)
                #expect(difference.maximumAlpha <= 2.0 / 255.0)
            }
        }
    }

    private func render(
        _ image: CGImage,
        in rect: CGRect,
        canvasSize: CGSize,
        displayScale: CGFloat
    ) throws -> CGImage {
        let width = Int((canvasSize.width * displayScale).rounded())
        let height = Int((canvasSize.height * displayScale).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestCGImageFactory.FactoryError.contextUnavailable
        }
        context.scaleBy(x: displayScale, y: displayScale)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        guard let result = context.makeImage() else {
            throw TestCGImageFactory.FactoryError.imageUnavailable
        }
        return result
    }

    private func boundaryDifference(
        _ lhs: CGImage,
        _ rhs: CGImage,
        rect: CGRect,
        bandWidth: Int
    ) throws -> (meanRGBA: Double, maximumAlpha: Double) {
        guard lhs.width == rhs.width,
              lhs.height == rhs.height,
              lhs.bytesPerRow == rhs.bytesPerRow,
              let lhsData = lhs.dataProvider?.data,
              let rhsData = rhs.dataProvider?.data,
              let lhsBytes = CFDataGetBytePtr(lhsData),
              let rhsBytes = CFDataGetBytePtr(rhsData) else {
            throw TestCGImageFactory.FactoryError.imageUnavailable
        }

        let pixelScale = CGFloat(lhs.width) / 320
        let pixelRect = CGRect(
            x: rect.minX * pixelScale,
            y: rect.minY * pixelScale,
            width: rect.width * pixelScale,
            height: rect.height * pixelScale
        )
        let scanRect = pixelRect.insetBy(dx: -CGFloat(bandWidth), dy: -CGFloat(bandWidth))
            .intersection(CGRect(x: 0, y: 0, width: lhs.width, height: lhs.height))
            .integral
        let innerRect = pixelRect.insetBy(dx: CGFloat(bandWidth), dy: CGFloat(bandWidth))
        var totalDifference = 0
        var maximumAlphaDifference = 0
        var componentCount = 0

        for y in Int(scanRect.minY)..<Int(scanRect.maxY) {
            for x in Int(scanRect.minX)..<Int(scanRect.maxX) where !innerRect.contains(
                CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            ) {
                let byteOffset = y * lhs.bytesPerRow + x * 4
                for component in 0..<4 {
                    let difference = abs(
                        Int(lhsBytes[byteOffset + component])
                            - Int(rhsBytes[byteOffset + component])
                    )
                    totalDifference += difference
                    componentCount += 1
                    if component == 3 {
                        maximumAlphaDifference = max(maximumAlphaDifference, difference)
                    }
                }
            }
        }

        return (
            meanRGBA: Double(totalDifference) / Double(max(componentCount, 1)) / 255.0,
            maximumAlpha: Double(maximumAlphaDifference) / 255.0
        )
    }
}
