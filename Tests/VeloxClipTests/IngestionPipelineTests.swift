import XCTest
@testable import VeloxClip

final class IngestionPipelineTests: XCTestCase {
    /// Files are checked before text because Finder also puts the file name on
    /// the pasteboard as plain text; checking text first shadowed every file
    /// copy and recorded it as a text item.
    func testFilesWinOverTheFilenameTextFinderAlsoPuts() {
        let payload = PasteboardPayload(filePaths: "/tmp/a.txt", text: "a.txt")
        XCTAssertEqual(IngestionPipeline.classify(payload), .file(paths: "/tmp/a.txt"))
    }

    func testColorIsDetectedBeforePlainText() {
        XCTAssertEqual(IngestionPipeline.classify(PasteboardPayload(text: "#ff0000")), .color("#ff0000"))
        XCTAssertEqual(IngestionPipeline.classify(PasteboardPayload(text: "hello")), .text("hello"))
    }

    func testTypePriorityLadderIsFileTextRtfImage() {
        let rtf = Data([0x7B, 0x5C, 0x72, 0x74, 0x66])
        let png = TestSupport.makePNG(width: 2, height: 2)

        XCTAssertEqual(
            IngestionPipeline.classify(PasteboardPayload(text: "t", rtf: rtf, image: png)),
            .text("t")
        )
        XCTAssertEqual(
            IngestionPipeline.classify(PasteboardPayload(rtf: rtf, image: png)),
            .rtf(rtf)
        )
        XCTAssertEqual(
            IngestionPipeline.classify(PasteboardPayload(image: png)),
            .image(png)
        )
        XCTAssertEqual(IngestionPipeline.classify(PasteboardPayload()), IngestKind.none)
    }

    /// The regression this pipeline exists for. The monitor used to spawn an
    /// unordered `Task.detached` per tick; the image branch's decode outlives
    /// the 0.5s poll interval while text returns instantly, so a later text
    /// copy landed above an earlier image copy in history.
    func testSlowImageStillLandsBeforeLaterFastText() async {
        actor Recorder {
            private(set) var order: [String] = []
            func append(_ label: String) { order.append(label) }
            func snapshot() -> [String] { order }
        }
        let recorder = Recorder()

        let pipeline = IngestionPipeline { kind, _ in
            switch kind {
            case .image:
                // Stand in for the TIFF decode + PNG re-encode
                try? await Task.sleep(nanoseconds: 60_000_000)
                await recorder.append("image")
            case .text(let t):
                await recorder.append(t)
            default:
                break
            }
        }

        let png = TestSupport.makePNG(width: 4, height: 4)
        await pipeline.submit(PasteboardPayload(image: png))
        await pipeline.submit(PasteboardPayload(text: "copied-after-the-image"))

        let order = await recorder.snapshot()
        XCTAssertEqual(order, ["image", "copied-after-the-image"],
                       "history order must match copy order even when the first item is slow to decode")
    }

    func testOversizedImageIsDropped() {
        let png = TestSupport.makePNG(width: 4, height: 4)
        XCTAssertNotNil(IngestionPipeline.prepareImage(png))

        // Byte ceiling applies to the normalized blob
        let huge = Data(repeating: 0x89, count: ClipboardIngestion.maxImageBytes + 1)
        XCTAssertNil(IngestionPipeline.prepareImage(huge),
                     "a blob over the storage ceiling must not reach SQLite")
    }

    func testPngPassesThroughNormalizationUnchanged() {
        let png = TestSupport.makePNG(width: 3, height: 3)
        XCTAssertEqual(IngestionPipeline.normalizedImageData(png), png,
                       "already-PNG data must not be re-encoded")
    }
}
