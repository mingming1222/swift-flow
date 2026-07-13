#if os(macOS)
import CoreGraphics

@MainActor
protocol LiveNodeWindowCapturing: AnyObject {
    func capture(windowID: CGWindowID) async throws -> CGImage
}
#endif
