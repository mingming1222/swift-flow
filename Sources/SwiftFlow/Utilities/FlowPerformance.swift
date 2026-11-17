import Dispatch
import Synchronization
import SwiftUI

/// Optional local instrumentation. Callbacks execute synchronously on the emitting
/// thread, outside the configuration lock; consumers should aggregate hot samples.
/// Durations describe CPU callbacks or explicitly named async work, never GPU presentation.
public enum FlowPerformance {
    public enum Kind: Sendable { case duration, counter }

    public struct Sample: Sendable {
        public let name: StaticString
        public let nanoseconds: UInt64
        public let count: Int
        public let scope: UInt64
        public let kind: Kind
    }

    private static let sink = Mutex<(@Sendable (Sample) -> Void)?>(nil)

    /// Nil disables instrumentation without clocks, tasks, output, or allocation.
    public static func configure(sink: (@Sendable (Sample) -> Void)?) {
        self.sink.withLock { $0 = sink }
    }

    struct Interval: Sendable {
        let start: UInt64
        let scope: UInt64
        let emit: @Sendable (Sample) -> Void

        func end(_ name: StaticString, count: Int = 1) {
            emit(Sample(name: name, nanoseconds: DispatchTime.now().uptimeNanoseconds - start,
                        count: count, scope: scope, kind: .duration))
        }

        func count(_ name: StaticString, _ value: Int = 1) {
            emit(Sample(name: name, nanoseconds: 0, count: value, scope: scope, kind: .counter))
        }
    }

    static func begin(scope: UInt64) -> Interval? {
        guard let emit = sink.withLock({ $0 }) else { return nil }
        return Interval(start: DispatchTime.now().uptimeNanoseconds, scope: scope, emit: emit)
    }

    static func count(_ name: StaticString, _ value: @autoclosure () -> Int = 1, scope: UInt64) {
        guard let emit = sink.withLock({ $0 }) else { return }
        emit(Sample(name: name, nanoseconds: 0, count: value(), scope: scope, kind: .counter))
    }
}

private struct FlowPerformanceScopeKey: EnvironmentKey {
    static let defaultValue: UInt64 = 0
}

extension EnvironmentValues {
    var flowPerformanceScope: UInt64 {
        get { self[FlowPerformanceScopeKey.self] }
        set { self[FlowPerformanceScopeKey.self] = newValue }
    }
}
