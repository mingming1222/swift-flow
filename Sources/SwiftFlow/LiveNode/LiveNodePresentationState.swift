struct LiveNodePresentationState: Sendable, Equatable {
    enum DrawingOwner: Sendable, Equatable {
        case canvas
        case overlay
    }

    let drawingOwner: DrawingOwner
    let isOverlayMounted: Bool
    let isOverlayVisible: Bool
    let isInteractive: Bool
    let isHittable: Bool

    var suppressesCanvas: Bool {
        drawingOwner == .overlay
    }

    init(
        isLiveNode: Bool,
        hasSnapshot: Bool,
        mountPolicy: LiveNodeMountPolicy,
        hasInteractionIntent: Bool,
        keepsOverlayVisibleForHandoff: Bool,
        isViewportInteracting: Bool
    ) {
        guard isLiveNode else {
            self = Self.canvasOnly
            return
        }

        if !hasSnapshot {
            let interactionEnabled = hasInteractionIntent && !isViewportInteracting
            self = Self.overlay(
                isInteractive: interactionEnabled,
                isHittable: interactionEnabled
            )
            return
        }

        if isViewportInteracting {
            self = Self.canvas(
                keepsOverlayMounted: mountPolicy == .persistent
            )
            return
        }

        if hasInteractionIntent || keepsOverlayVisibleForHandoff {
            self = Self.overlay(
                isInteractive: hasInteractionIntent,
                isHittable: hasInteractionIntent
            )
            return
        }

        self = Self.canvas(
            keepsOverlayMounted: mountPolicy == .persistent
        )
    }

    private static let canvasOnly = LiveNodePresentationState(
        drawingOwner: .canvas,
        isOverlayMounted: false,
        isOverlayVisible: false,
        isInteractive: false,
        isHittable: false
    )

    private static func canvas(keepsOverlayMounted: Bool) -> LiveNodePresentationState {
        LiveNodePresentationState(
            drawingOwner: .canvas,
            isOverlayMounted: keepsOverlayMounted,
            isOverlayVisible: false,
            isInteractive: false,
            isHittable: false
        )
    }

    private static func overlay(
        isInteractive: Bool,
        isHittable: Bool
    ) -> LiveNodePresentationState {
        LiveNodePresentationState(
            drawingOwner: .overlay,
            isOverlayMounted: true,
            isOverlayVisible: true,
            isInteractive: isInteractive,
            isHittable: isHittable
        )
    }

    private init(
        drawingOwner: DrawingOwner,
        isOverlayMounted: Bool,
        isOverlayVisible: Bool,
        isInteractive: Bool,
        isHittable: Bool
    ) {
        self.drawingOwner = drawingOwner
        self.isOverlayMounted = isOverlayMounted
        self.isOverlayVisible = isOverlayVisible
        self.isInteractive = isInteractive
        self.isHittable = isHittable
    }
}
