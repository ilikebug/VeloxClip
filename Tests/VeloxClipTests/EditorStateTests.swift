import XCTest
import SwiftUI
@testable import VeloxClip

/// The screenshot editor's undo/redo is a real state machine and had no tests.
@MainActor
final class EditorStateTests: XCTestCase {
    private func element(_ tag: CGFloat = 1) -> DrawingElement {
        DrawingElement(type: .line, path: CGMutablePath(), color: .red, lineWidth: tag,
                       startPoint: .zero, endPoint: CGPoint(x: tag, y: tag))
    }

    func testFreshStateHasNothingToUndoOrRedo() {
        let state = EditorState()
        XCTAssertFalse(state.canUndo())
        XCTAssertFalse(state.canRedo())
        XCTAssertTrue(state.elements.isEmpty)
    }

    func testUndoRemovesTheLastElement() {
        let state = EditorState()
        state.addElement(element(1))
        state.addElement(element(2))
        XCTAssertEqual(state.elements.count, 2)

        state.undo()

        XCTAssertEqual(state.elements.count, 1)
        XCTAssertEqual(state.elements.first?.lineWidth, 1)
        XCTAssertTrue(state.canRedo())
    }

    func testRedoRestoresIt() {
        let state = EditorState()
        state.addElement(element(1))
        state.addElement(element(2))
        state.undo()

        state.redo()

        XCTAssertEqual(state.elements.count, 2)
        XCTAssertEqual(state.elements.last?.lineWidth, 2)
    }

    /// The classic undo-stack rule: branching discards the redo future.
    func testDrawingAfterUndoDiscardsTheRedoStack() {
        let state = EditorState()
        state.addElement(element(1))
        state.addElement(element(2))
        state.undo()
        XCTAssertTrue(state.canRedo())

        state.addElement(element(3))

        XCTAssertFalse(state.canRedo(), "a new stroke must invalidate the redo future")
        XCTAssertEqual(state.elements.map(\.lineWidth), [1, 3])
    }

    func testUndoOnAnEmptyStackIsANoOp() {
        let state = EditorState()
        state.undo()
        state.undo()
        XCTAssertTrue(state.elements.isEmpty)
    }

    func testRedoOnAnEmptyStackIsANoOp() {
        let state = EditorState()
        state.addElement(element(1))
        state.redo()
        XCTAssertEqual(state.elements.count, 1)
    }

    /// Clear is undoable — wiping an annotated screenshot by accident must be
    /// recoverable.
    func testClearIsUndoable() {
        let state = EditorState()
        state.addElement(element(1))
        state.addElement(element(2))

        state.clear()
        XCTAssertTrue(state.elements.isEmpty)

        state.undo()
        XCTAssertEqual(state.elements.count, 2, "clear must be undoable")
    }

    /// The stack is capped at 50; the oldest entry is dropped rather than
    /// growing without bound on a long editing session.
    func testUndoHistoryIsBounded() {
        let state = EditorState()
        for i in 0..<60 {
            state.addElement(element(CGFloat(i)))
        }
        XCTAssertEqual(state.elements.count, 60)

        // Unwind everything the stack can still reach
        var undos = 0
        while state.canUndo() {
            state.undo()
            undos += 1
            if undos > 100 { break }   // guard against a runaway loop
        }
        XCTAssertLessThanOrEqual(undos, 50, "the undo stack must stay bounded")
        XCTAssertFalse(state.canUndo())
    }
}
