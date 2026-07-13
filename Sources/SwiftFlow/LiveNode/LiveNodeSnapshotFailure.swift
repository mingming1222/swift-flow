import Foundation

struct LiveNodeSnapshotFailure: Error, CustomStringConvertible {
    enum Stage: String {
        case mountedWindowCapture
        case mountedViewCapture
        case nativeViewCapture
        case normalization
    }

    let nodeID: String
    let stage: Stage
    let underlyingError: Error

    var description: String {
        "node=\(nodeID) stage=\(stage.rawValue) error=\(underlyingError)"
    }
}
