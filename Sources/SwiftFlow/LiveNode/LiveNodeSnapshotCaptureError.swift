import CoreGraphics
import Foundation

enum LiveNodeSnapshotCaptureError: Error, CustomStringConvertible {
    case invalidLogicalSize(CGSize)
    case invalidScale(CGFloat)
    case surfaceNotVisible
    case windowUnavailable
    case screenCaptureAccessDenied
    case insufficientResolution(sourcePixelSize: CGSize, requiredPixelSize: CGSize)
    case shareableWindowUnavailable(UInt32)
    case imageUnavailable
    case cropOutsideImage(CGRect)
    case bitmapContextUnavailable
    case renderingFailed
    case underlying(Error)

    var description: String {
        switch self {
        case .invalidLogicalSize(let size):
            "invalidLogicalSize(\(size))"
        case .invalidScale(let scale):
            "invalidScale(\(scale))"
        case .surfaceNotVisible:
            "surfaceNotVisible"
        case .windowUnavailable:
            "windowUnavailable"
        case .screenCaptureAccessDenied:
            "screenCaptureAccessDenied"
        case let .insufficientResolution(sourcePixelSize, requiredPixelSize):
            "insufficientResolution(source=\(sourcePixelSize), required=\(requiredPixelSize))"
        case .shareableWindowUnavailable(let windowID):
            "shareableWindowUnavailable(\(windowID))"
        case .imageUnavailable:
            "imageUnavailable"
        case .cropOutsideImage(let rect):
            "cropOutsideImage(\(rect))"
        case .bitmapContextUnavailable:
            "bitmapContextUnavailable"
        case .renderingFailed:
            "renderingFailed"
        case .underlying(let error):
            "underlying(\(error))"
        }
    }
}
