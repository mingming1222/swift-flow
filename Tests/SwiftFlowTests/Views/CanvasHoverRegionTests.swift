import Testing
import SwiftUI
@testable import SwiftFlow

@Suite("Canvas hover exclusion")
@MainActor
struct CanvasHoverRegionTests {
    @Test("Visible rounded surfaces exclude hover but transparent corners and gaps do not")
    func visibleSurfaces() {
        let circle = CanvasHoverRegion(frame: CGRect(x: 10, y: 20, width: 36, height: 36), cornerRadius: 18)
        #expect(circle.contains(CGPoint(x: 28, y: 38)))
        #expect(!circle.contains(CGPoint(x: 11, y: 21)))
        #expect(!circle.contains(CGPoint(x: 60, y: 38)))
        let empty = CanvasHoverRegion(frame: .zero)
        #expect(!empty.contains(.zero))
    }

    #if os(macOS)
    @Test("The host cursor resolver respects controls above nodes, including a transformed viewport")
    func hostCursorRespectsExclusions() {
        _ = NSApplication.shared
        let store = FlowStore<String>()
        store.addNode(FlowNode(id: "node", position: .zero, size: CGSize(width: 240, height: 160), data: "Node"))
        store.zoom(by: 1.5, anchor: .zero)
        store.pan(by: CGSize(width: 45, height: 30))
        let point = store.viewport.canvasToScreen(CGPoint(x: 120, y: 80))
        let control = CanvasHoverRegion(
            frame: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36),
            cornerRadius: 18
        )
        let canvas = FlowCanvas(store: store)
        #expect(canvas.cursor(at: point) === NSCursor.openHand)
        let coveredCanvas = canvas.hoverExclusionRegions([control])
        #expect(coveredCanvas.cursor(at: point) === NSCursor.arrow)
        // The transparent circle corner still belongs to the underlying node.
        let corner = CGPoint(x: control.frame.minX + 1, y: control.frame.minY + 1)
        #expect(coveredCanvas.cursor(at: corner) === NSCursor.openHand)
        #expect(coveredCanvas.hoverExclusionRegions([]).cursor(at: point) === NSCursor.openHand)
    }

    @Test("Entering a control clears node hover without asking for a node cursor; leaving restores it")
    func clearsAndRestoresHover() {
        let view = CanvasHoverTrackingNSView()
        let store = FlowStore<String>()
        store.addNode(FlowNode(id: "node", position: .zero, data: "Node"))
        var cursorQueries = 0
        view.onHover = { _ in store.setHoveredNode("node") }
        view.onExit = { store.setHoveredNode(nil) }
        view.cursorAt = { _ in cursorQueries += 1; return .arrow }
        let point = CGPoint(x: 28, y: 38)
        view.updateHoverAndCursor(at: point)
        #expect(store.hoveredNodeID == "node")
        #expect(cursorQueries == 1)

        // A control appearing under a stationary pointer uses the same gate.
        view.exclusionRegions = [CanvasHoverRegion(frame: CGRect(x: 10, y: 20, width: 36, height: 36), cornerRadius: 18)]
        view.updateHoverAndCursor(at: point)
        view.updateHoverAndCursor(at: point)
        #expect(store.hoveredNodeID == nil)
        #expect(store.nodeLookup["node"]?.isHovered == false)
        #expect(cursorQueries == 1)

        view.updateHoverAndCursor(at: CGPoint(x: 80, y: 38))
        #expect(store.hoveredNodeID == "node")
        #expect(cursorQueries == 2)

        // Removing a control restores hover without requiring a new event.
        view.exclusionRegions = []
        view.updateHoverAndCursor(at: point)
        #expect(store.hoveredNodeID == "node")
        #expect(cursorQueries == 3)
    }
    #endif
}
