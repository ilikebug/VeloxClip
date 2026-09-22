import XCTest
import SwiftUI
@testable import VeloxClip

/// The editor's drag state versus tool switching and undo.
@MainActor
final class EditorDragStateTests: XCTestCase {
    /// Switching tools mid-drag must not leave a drag in progress.
    ///
    /// `isDrawing` stuck true makes the canvas render a phantom preview stroke
    /// forever, and because the text tool's floating input is gated on
    /// `isDrawing == false`, the text tool goes dead until the window is
    /// reopened.
    func testSwitchingToolMidDragCancelsTheDrag() {
        let state = EditorState()
        state.currentTool = .rectangle
        state.startDrawing(at: CGPoint(x: 10, y: 10))
        state.updateDrawing(to: CGPoint(x: 80, y: 80))
        XCTAssertTrue(state.isDrawing, "precondition: a drag is in progress")

        state.currentTool = .text

        XCTAssertFalse(state.isDrawing, "switching tools must cancel the in-progress drag")
        XCTAssertNil(state.currentPath, "…and drop its partial path")
        XCTAssertTrue(state.elements.isEmpty, "an abandoned drag must not commit an element")
    }

    /// An abandoned drag must not be committed under the NEW tool's semantics —
    /// a rectangle released after switching to the arrow tool would otherwise
    /// export with the arrow's filled-triangle treatment.
    func testAbandonedDragIsNotCommittedAsTheNewToolType() {
        let state = EditorState()
        state.currentTool = .rectangle
        state.startDrawing(at: CGPoint(x: 0, y: 0))
        state.updateDrawing(to: CGPoint(x: 50, y: 50))

        state.currentTool = .arrow
        state.finishDrawing()

        XCTAssertTrue(state.elements.isEmpty,
                      "a drag abandoned by a tool switch must not be committed at all")
    }

    /// Undo during a drag must not leave the transient preview behind.
    func testUndoDuringADragClearsTheDragState() {
        let state = EditorState()
        state.currentTool = .line
        state.startDrawing(at: CGPoint(x: 0, y: 0))
        state.updateDrawing(to: CGPoint(x: 30, y: 30))

        state.undo()

        XCTAssertFalse(state.isDrawing, "undo must not leave a half-finished stroke on the canvas")
        XCTAssertNil(state.currentPath)
    }

    func testRedoDuringADragClearsTheDragState() {
        let state = EditorState()
        state.currentTool = .line
        state.startDrawing(at: CGPoint(x: 0, y: 0))
        state.updateDrawing(to: CGPoint(x: 10, y: 10))
        state.finishDrawing()
        state.undo()

        state.startDrawing(at: CGPoint(x: 50, y: 50))
        state.updateDrawing(to: CGPoint(x: 60, y: 60))
        state.redo()

        XCTAssertFalse(state.isDrawing)
        XCTAssertNil(state.currentPath)
    }

    /// Switching tools when nothing is being drawn must be inert.
    func testSwitchingToolWithNoDragInProgressKeepsElements() {
        let state = EditorState()
        state.currentTool = .line
        state.startDrawing(at: CGPoint(x: 0, y: 0))
        state.updateDrawing(to: CGPoint(x: 10, y: 10))
        state.finishDrawing()
        XCTAssertEqual(state.elements.count, 1)

        state.currentTool = .pen
        state.currentTool = .mosaic

        XCTAssertEqual(state.elements.count, 1, "committed elements survive tool changes")
        XCTAssertFalse(state.isDrawing)
    }

    /// The pen's point buffer must not survive into the next stroke, or the
    /// new stroke starts with a tail of the abandoned one.
    func testPenPointsDoNotLeakAcrossACancelledStroke() {
        let state = EditorState()
        state.currentTool = .pen
        state.startDrawing(at: CGPoint(x: 1, y: 1))
        state.updateDrawing(to: CGPoint(x: 2, y: 2))
        state.updateDrawing(to: CGPoint(x: 3, y: 3))

        state.currentTool = .line   // cancels

        XCTAssertTrue(state.penPoints.isEmpty, "the abandoned stroke's points must be discarded")
    }
}
