import XCTest
import SwiftUI
@testable import VeloxClip

/// Round-9 audit findings in the screenshot editor's state machine.
@MainActor
final class Round9EditorTests: XCTestCase {

    private func drawHighlight(on state: EditorState, from start: CGPoint, to end: CGPoint) {
        state.currentTool = .highlight
        state.startDrawing(at: start)
        state.updateDrawing(to: end)
        state.finishDrawing()
    }

    // MARK: - A highlight could only be erased on its edge

    /// Highlights are filled areas, but the eraser tested only the stroked
    /// outline, so swiping across the middle left them in place.
    func testEraserRemovesHighlightFromItsMiddle() {
        let state = EditorState()
        drawHighlight(on: state, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300))
        XCTAssertEqual(state.elements.count, 1)

        state.eraseElements(at: CGPoint(x: 500, y: 500), radius: 5)
        XCTAssertEqual(state.elements.count, 1, "a far-away swipe must not erase it")

        state.eraseElements(at: CGPoint(x: 200, y: 200), radius: 5)
        XCTAssertTrue(state.elements.isEmpty)
    }

    // MARK: - A highlight changed opacity on mouse-up

    /// The preview drew with the slider opacity, the committed element with a
    /// hard-coded 0.5 — they must be the same value.
    func testCommittedHighlightKeepsThePreviewOpacity() throws {
        let state = EditorState()
        state.opacity = 0.6
        state.currentTool = .highlight
        let previewOpacity = state.drawingOpacity

        drawHighlight(on: state, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 80))

        let element = try XCTUnwrap(state.elements.first)
        XCTAssertEqual(element.opacity, previewOpacity, accuracy: 0.0001)
        XCTAssertEqual(element.opacity, 0.3, accuracy: 0.0001)
    }

    func testOtherToolsDrawWithTheSliderOpacity() throws {
        let state = EditorState()
        state.opacity = 0.6
        state.currentTool = .rectangle
        XCTAssertEqual(state.drawingOpacity, 0.6, accuracy: 0.0001)

        state.startDrawing(at: CGPoint(x: 10, y: 10))
        state.updateDrawing(to: CGPoint(x: 80, y: 80))
        state.finishDrawing()

        XCTAssertEqual(try XCTUnwrap(state.elements.first).opacity, 0.6, accuracy: 0.0001)
    }

    // MARK: - Closing after a save still prompted "unsaved"

    func testSavedCanvasHasNoUnsavedChanges() {
        let state = EditorState()
        XCTAssertFalse(state.hasUnsavedChanges, "an empty canvas has nothing to lose")

        drawHighlight(on: state, from: .zero, to: CGPoint(x: 50, y: 50))
        XCTAssertTrue(state.hasUnsavedChanges)

        state.markSaved(state.elements.map(\.id))
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testEditsAfterASaveAreUnsavedAgain() {
        let state = EditorState()
        drawHighlight(on: state, from: .zero, to: CGPoint(x: 50, y: 50))
        state.markSaved(state.elements.map(\.id))

        drawHighlight(on: state, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 90, y: 90))
        XCTAssertTrue(state.hasUnsavedChanges, "a stroke after the save is unsaved")

        state.undo()
        XCTAssertFalse(state.hasUnsavedChanges, "undoing back to the saved canvas")

        state.clear()
        XCTAssertTrue(state.hasUnsavedChanges, "clearing the saved annotations is a change")
    }
}
