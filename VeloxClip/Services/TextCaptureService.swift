import AppKit
import SwiftUI
import Vision

// Screen text capture (OCR anywhere): select a screen region, the recognized
// text lands directly on the clipboard — no image is kept. QR/barcode payloads
// take precedence over OCR text. The F1 screenshot flow is untouched.
@MainActor
final class TextCaptureService {
    static let shared = TextCaptureService()

    private var isCapturing = false
    private var toastPanel: NSPanel?

    private init() {}

    func captureText() {
        guard !isCapturing else { return }
        isCapturing = true

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("veloxclip-textcapture-\(UUID().uuidString).png")

        // -i interactive selection, -x no sound; output to a temp file so the
        // pasteboard is never touched by the capture itself
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-x", tmpURL.path]
        task.terminationHandler = { _ in
            Task { @MainActor in
                await TextCaptureService.shared.processCapturedFile(at: tmpURL)
            }
        }

        do {
            try task.run()
        } catch {
            isCapturing = false
            print("Failed to launch screencapture for text capture: \(error)")
        }
    }

    // Barcode payloads beat OCR text: when the user frames a QR code, the
    // payload is the intent, not the "scan me" caption around it
    nonisolated static func chooseContent(ocrText: String?, barcodePayloads: [String]) -> String? {
        if !barcodePayloads.isEmpty {
            return barcodePayloads.joined(separator: "\n")
        }
        let trimmed = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func processCapturedFile(at url: URL) async {
        defer {
            isCapturing = false
            try? FileManager.default.removeItem(at: url)
        }

        // User pressed ESC during selection — no file, no toast
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let imageData = try? Data(contentsOf: url),
                  let image = NSImage(data: imageData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return Self.recognize(in: cgImage)
        }.value

        guard let content else {
            showToast(message: "No text found", isSuccess: false)
            return
        }

        // Clipboard write is gated so ClipboardMonitor doesn't re-ingest it;
        // the history entry is added directly with a recognizable source
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        PasteboardSelfWriteGate.shared.recordSelfWrite()

        ClipboardStore.shared.addItem(
            ClipboardItem(type: "text", content: content, sourceApp: "Text Capture")
        )

        showToast(message: "Copied \(content.count) characters", isSuccess: true)
    }

    // Runs text + barcode recognition on the captured region (background thread)
    nonisolated private static func recognize(in cgImage: CGImage) -> String? {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        textRequest.usesLanguageCorrection = true

        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, barcodeRequest])

        let ocrText = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let payloads = (barcodeRequest.results ?? [])
            .compactMap { $0.payloadStringValue }

        return chooseContent(ocrText: ocrText, barcodePayloads: payloads)
    }

    // MARK: - Toast

    private func showToast(message: String, isSuccess: Bool) {
        toastPanel?.orderOut(nil)

        let view = TextCaptureToastView(message: message, isSuccess: isSuccess)
        let hosting = NSHostingController(rootView: view)
        // Size the panel to the SwiftUI content — a fixed frame clips long
        // messages, leaving only the leading icon visible
        hosting.view.layoutSubtreeIfNeeded()
        let contentSize = hosting.view.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.setContentSize(contentSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        // Top-center of the screen, just below the menu bar
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(
            x: screen.midX - panel.frame.width / 2,
            y: screen.maxY - panel.frame.height - 16
        ))
        panel.orderFrontRegardless()
        toastPanel = panel

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard self.toastPanel === panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    if self.toastPanel === panel { self.toastPanel = nil }
                }
            }
        }
    }
}

private struct TextCaptureToastView: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isSuccess ? .green : .orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(6)
    }
}
