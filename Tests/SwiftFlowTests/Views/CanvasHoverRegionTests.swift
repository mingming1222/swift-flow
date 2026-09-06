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
