import XCTest
@testable import VeloxClip

@MainActor
final class ErrorHandlerTests: XCTestCase {
    private enum SampleError: LocalizedError {
        case disk
        var errorDescription: String? { "the disk went away" }
    }

    override func tearDown() {
        ErrorHandler.shared.clear()
        super.tearDown()
    }

    func testHandlingAnErrorPublishesItForTheAlert() {
        ErrorHandler.shared.clear()
        ErrorHandler.shared.handle(SampleError.disk)

        XCTAssertTrue(ErrorHandler.shared.showError)
        XCTAssertEqual(ErrorHandler.shared.currentError?.message, "the disk went away")
    }

    func testClearDismissesIt() {
        ErrorHandler.shared.handle(SampleError.disk)
        ErrorHandler.shared.clear()

        XCTAssertFalse(ErrorHandler.shared.showError)
        XCTAssertNil(ErrorHandler.shared.currentError)
    }

    /// AI failures are titled separately so the alert can say what broke.
    func testAIServiceErrorsGetTheirOwnTitle() {
        ErrorHandler.shared.handle(AIServiceError.embeddingUnavailable)
        XCTAssertEqual(ErrorHandler.shared.currentError?.title, "AI Service Error")

        ErrorHandler.shared.handle(SampleError.disk)
        XCTAssertEqual(ErrorHandler.shared.currentError?.title, "Error")
    }

    /// A later error replaces an earlier one rather than being dropped.
    func testASecondErrorSupersedesTheFirst() {
        ErrorHandler.shared.handle(AIServiceError.embeddingUnavailable)
        let first = ErrorHandler.shared.currentError?.id

        ErrorHandler.shared.handle(SampleError.disk)

        XCTAssertNotEqual(ErrorHandler.shared.currentError?.id, first)
        XCTAssertEqual(ErrorHandler.shared.currentError?.message, "the disk went away")
    }
}

@MainActor
final class CacheRegistryTests: XCTestCase {
    /// CacheManager used to reach into the view layer and clear statics on
    /// concrete SwiftUI views. Now caches register a handler instead.
    func testRegisteredHandlersAllRunOnClearAll() {
        final class Counter { var count = 0 }
        let a = Counter(), b = Counter()

        CacheRegistry.register { a.count += 1 }
        CacheRegistry.register { b.count += 1 }

        CacheRegistry.clearAll()

        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1, "every registered cache must be cleared, not just the first")
    }
}
