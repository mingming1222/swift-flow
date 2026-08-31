/// Declares whether a ``FlowCanvas`` can contain ``LiveNode`` content.
///
/// Disabling support removes the live overlay and its registrar pass. Only
/// disable it when the canvas's node builder is guaranteed not to emit a
/// ``LiveNode``.
public enum LiveNodeSupport: Sendable, Hashable {
    case enabled
    case disabled
}
