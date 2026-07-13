#if os(macOS)
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureKitLiveNodeWindowCapturer: LiveNodeWindowCapturing {
    func capture(windowID: CGWindowID) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            throw LiveNodeSnapshotCaptureError.screenCaptureAccessDenied
        }
        let window = try await shareableWindow(for: windowID)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.ignoreClipping = false
        configuration.includeChildWindows = false
        configuration.displayIntent = .local
        configuration.dynamicRange = .sdr

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureScreenshot(
                contentFilter: filter,
                configuration: configuration
            ) { output, error in
                if let image = output?.sdrImage {
                    continuation.resume(returning: image)
                    return
                }
                if let error {
                    continuation.resume(
                        throwing: LiveNodeSnapshotCaptureError.underlying(error)
                    )
                    return
                }
                continuation.resume(
                    throwing: LiveNodeSnapshotCaptureError.imageUnavailable
                )
            }
        }
    }

    private func shareableWindow(for windowID: CGWindowID) async throws -> SCWindow {
        for attempt in 0..<10 {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.currentProcess
            } catch {
                throw LiveNodeSnapshotCaptureError.underlying(error)
            }
            if let window = content.windows.first(where: { $0.windowID == windowID }) {
                return window
            }
            if attempt < 9 {
                do {
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch {
                    throw CancellationError()
                }
            }
        }
        throw LiveNodeSnapshotCaptureError.shareableWindowUnavailable(windowID)
    }
}
#endif
