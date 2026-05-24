import Testing
@testable import SwiftFlow

@Suite("LiveNodePosterPolicy Tests")
struct LiveNodePosterPolicyTests {

    @Test("Default configuration uses automatic poster policy")
    func defaultConfigurationUsesAutomaticPosterPolicy() {
        let configuration = LiveNodeConfiguration.default

        #expect(configuration.posterPolicy == .automatic)
    }

    @Test("Manual poster policy disables automatic capture timing")
    func manualPosterPolicyDisablesAutomaticCaptureTiming() {
        let policy = LiveNodePosterPolicy.manual

        #expect(policy.initialCapture == .manual)
        #expect(policy.interactionEndCapture == .manual)
    }
}
